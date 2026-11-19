extends "res://tests/world/terrain_streaming.gd"
const OriginalMesher=preload("res://tests/world/fixtures/foundation_mesher_before.gd")
const OriginalView=preload("res://tests/world/fixtures/foundation_view_before.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
func drain_timed(view:Node3D)->void:
	var peaks:Array=[];var frames:=0
	while view.statistics().pending>0 and frames<4096:
		var start:=Time.get_ticks_usec();view.process_budget(4000);peaks.append(Time.get_ticks_usec()-start);frames+=1
		await process_frame
	peaks.sort();costs.staged_process_calls=frames;costs.staged_process_max_usec=peaks.back() if not peaks.is_empty() else 0
	costs.staged_process_p95_usec=peaks[int((peaks.size()-1)*0.95)] if not peaks.is_empty() else 0
	if not costs.has("drain_passes"):costs.drain_passes=[]
	var total:=0
	for value:int in peaks:total+=value
	costs.drain_passes.append({"calls":frames,"max_usec":costs.staged_process_max_usec,"p95_usec":costs.staged_process_p95_usec,"total_process_usec":total})
	await physics_frame;await process_frame
func run()->void:
	var draft:Dictionary=Generator.draft_region(713,Vector2i(1,0))
	var world:=empty_world(draft.plan);var committed:=install(world,draft)
	check("actual finite generated authority installed",committed.ok)
	var material_start:=Time.get_ticks_usec();var materials:=Materials.new()
	for id in materials.manifest():materials.material(id)
	for m in Data.MATERIALS.values():
		if m.solid:materials.terrain_material(m.top,"top");materials.terrain_material(m.side,"side")
	materials.terrain_material("soil_top","top");materials.contact_material()
	for m in [2,4,6]:materials.shoulder_material(m)
	costs.material_warm_usec=Time.get_ticks_usec()-material_start
	var exact:=true;var winding_ok:=true;var old_usec:=0;var new_usec:=0;var layer_peak:=0;var triangles:=0
	for key:String in world.chunk_keys():
		var start:=Time.get_ticks_usec();var before:Dictionary=OriginalMesher.build(world,key);old_usec+=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();var job:Dictionary=Mesher.begin(world,key)
		while not job.done:
			var layer_start:=Time.get_ticks_usec();Mesher.advance(job);layer_peak=maxi(layer_peak,Time.get_ticks_usec()-layer_start)
		new_usec+=Time.get_ticks_usec()-start
		exact=exact and before.groups==job.output.groups and before.quads==job.output.quads
		for group:Dictionary in job.output.groups.values():
			for i in range(0,group.indices.size(),3):
				var a:Vector3=group.vertices[group.indices[i]];var b:Vector3=group.vertices[group.indices[i+1]];var c:Vector3=group.vertices[group.indices[i+2]]
				winding_ok=winding_ok and (b-a).cross(c-a).dot(group.normals[group.indices[i]])<0;triangles+=1
	check("all chunk pure layers preserve exact original vertices normals metre UV indices",exact)
	check("all actual terrain triangles have nondegenerate Godot clockwise outward winding",winding_ok,{"triangles":triangles})
	costs.pure_original_total_usec=old_usec;costs.pure_staged_total_usec=new_usec;costs.pure_layer_peak_usec=layer_peak
	var old:=OriginalView.new();root.add_child(old);old.configure({"world":world,"materials":materials});old.set_process(false)
	var start:=Time.get_ticks_usec();old.flush_pending();costs.before_full_drain_usec=Time.get_ticks_usec()-start
	var expected:=geometry(old);costs.before_max_whole_chunk_usec=old.statistics().max_rebuild_usec;old.free()
	var terrain:=Terrain.new();root.add_child(terrain);terrain.configure({"world":world,"materials":materials,"stream_updates":true,"budgeted_edits":true});terrain.set_process(false)
	await drain_timed(terrain)
	check("staged native mesh and collision exactly match original full sync view",geometry(terrain)==expected)
	var anchor:Dictionary=draft.plan.anchors.arrival
	var cell:=Vector3i(floori(anchor.x*2),roundi(world.surface_height(anchor.x,anchor.z)*2)-1,floori(anchor.z*2))
	var key:=Data.key(Data.cell_chunk(cell,16));var before:int=world.cell_at(cell.x,cell.y,cell.z)
	var edit:Dictionary=commit(world,[{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":before,"after":0}])
	start=Time.get_ticks_usec();terrain.on_world_changed(edit.changes);costs.edit_notification_usec=Time.get_ticks_usec()-start
	check("budgeted edit retires stale collider and overlay before return",not terrain._chunks.has(key) and not terrain.environment._ground.has(key) and not terrain.readiness([key]).ready)
	terrain._queue.erase(key);terrain._queue.push_front(key);terrain.process_budget(1)
	check("tiny time slice keeps an explicit in-flight job",not terrain._active.is_empty() and not terrain.readiness([key]).ready)
	var unrelated:Dictionary=commit(world,[{"op":"extension.set","id":"test:unrelated","before_exists":false,"before":null,"after":{"clock":1}}])
	terrain.on_world_changed(unrelated.changes);var cancelled:int=terrain.statistics().cancelled_jobs
	terrain.process_budget(1)
	check("unrelated revision neither cancels nor requeues snapshot",terrain.statistics().cancelled_jobs==cancelled)
	var second:Dictionary=commit(world,[{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":0,"after":before}])
	terrain.on_world_changed(second.changes)
	check("new edit cancels one obsolete job instead of attaching it",terrain.statistics().cancelled_jobs==cancelled+1)
	await drain_timed(terrain)
	check("edit then undo restores exact mesh collision bytes",geometry(terrain)==expected)
	# The east arrival is deliberately at an ungenerated west edge; its body
	# halo must stay blocked. Test a genuinely covered interior neighborhood.
	var near:Dictionary=terrain.readiness_near([Vector3(96.25,world.surface_height(96.25,32.25),32.25)],0.3,0.5,1.8)
	check("finite actor neighborhood is ready without remote region drain",near.ready,near)
	check("invalid readiness points fail closed",not terrain.readiness_near([Vector3(NAN,0,0)]).ready and not terrain.readiness_near([],1).ready)
	var current_epoch:int=terrain.statistics().view_epoch
	terrain.on_world_changed({"reload":true});terrain.process_budget(1);terrain.cancel_pending()
	check("reload and explicit cancellation advance epoch and retire old work",terrain.statistics().view_epoch==current_epoch+2 and terrain._active.is_empty() and terrain.statistics().pending==0 and not terrain.readiness([key]).ready)
	costs.stages=terrain.statistics().stages;costs.scope="headless same-input CPU diagnostics; parallel development, not quiet FPS/Metal/GPU qualification; native stages non-preemptible"
	terrain.free();finish()
