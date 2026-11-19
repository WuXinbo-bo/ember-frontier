extends SceneTree
const Generator = preload("res://scripts/world/settlement_generator.gd")
const State = preload("res://scripts/world/world_state.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Terrain = preload("res://scripts/terrain/terrain_view.gd")
const Before = preload("res://tests/world/fixtures/streaming_terrain_view_before.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
var checks: Array=[]
var costs: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))
func empty_world(plan: Dictionary) -> RefCounted:
	var world := State.new()
	var snapshot := {"schemaVersion":1,"worldId":"rural:v2:713","seed":713,"generatorVersion":"rural-2","revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{"generation:rural2":{"profile_contract_sha256":plan.profile_contract_sha256}},"receipts":{}}
	check("empty finite-stream fixture loads",world.load_snapshot(snapshot).ok)
	return world
func install(world: RefCounted,draft: Dictionary) -> Dictionary:
	var region: Dictionary=Generator.prepare_draft(world,draft,world.get_revision())
	if not region.ok:return region
	var prepared: Dictionary=world.prepare_changes(region.world_changes,world.get_revision())
	return world.commit_prepared(prepared.capability) if prepared.ok else prepared
func commit(world: RefCounted,operations: Array) -> Dictionary:
	var prepared: Dictionary=world.prepare_changes(operations,world.get_revision())
	return world.commit_prepared(prepared.capability) if prepared.ok else prepared
func geometry(view: Node3D) -> String:
	var keys: Array=view._chunks.keys();keys.sort()
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	for key in keys:
		hash.update(str(key).to_utf8_buffer())
		var node: Node3D=view._chunks[key].node
		var mesh: ArrayMesh=node.get_child(0).mesh
		for surface in mesh.get_surface_count():
			var a: Array=mesh.surface_get_arrays(surface)
			hash.update(a[Mesh.ARRAY_VERTEX].to_byte_array())
			hash.update(a[Mesh.ARRAY_NORMAL].to_byte_array())
			hash.update(a[Mesh.ARRAY_TEX_UV].to_byte_array())
			hash.update(a[Mesh.ARRAY_INDEX].to_byte_array())
		var body: StaticBody3D=node.get_child(1)
		hash.update(body.get_child(0).shape.get_faces().to_byte_array())
	return hash.finish().hex_encode()
func drain(view: Node3D) -> void:
	var iterations := 0
	while view.statistics().pending>0 and iterations<1024:
		view._process(0.0);iterations+=1
		await process_frame
	costs.queue_frames=iterations
	await physics_frame
	await process_frame
func run() -> void:
	var draft: Dictionary=Generator.draft_region(713,Vector2i(1,0))
	check("real east region draft, not replacement flat geometry",draft.ok and draft.chunks.size()==256 and draft.cost.height_max>draft.cost.height_min)
	if not draft.ok:return finish()
	var keys: Array=draft.chunks.keys()
	# Separate first-use material work from the same-input callback comparison.
	# The real runtime normally already has these sources cached before expansion.
	var material_start := Time.get_ticks_usec()
	var materials := Materials.new()
	for id in materials.manifest(): materials.material(id)
	for m in Data.MATERIALS.values():
		if m.solid:
			materials.terrain_material(m.top,"top");materials.terrain_material(m.side,"side")
	materials.terrain_material("soil_top","top");materials.contact_material()
	for m in [2,4,6]:materials.shoulder_material(m)
	costs.shared_material_prepare_ms=(Time.get_ticks_usec()-material_start)/1000.0
	var old_world := empty_world(draft.plan)
	var before := Before.new();root.add_child(before);before.configure({"world":old_world,"materials":materials});before.set_process(false)
	var installed := install(old_world,draft)
	check("same real region transaction committed for old callback",installed.ok)
	if not installed.ok:return finish()
	var started := Time.get_ticks_usec()
	before.on_world_changed(installed.changes)
	costs.before_callback_ms=(Time.get_ticks_usec()-started)/1000.0
	var expected_geometry := geometry(before)
	check("old callback rebuilds full new region synchronously",before.statistics().rebuilds>0 and before.statistics().pending==0,before.statistics())
	before.free()
	var world := empty_world(draft.plan)
	var terrain := Terrain.new();root.add_child(terrain);terrain.configure({"world":world,"materials":materials,"stream_updates":true});terrain.set_process(false)
	check("unknown and empty readiness never permit loading",not terrain.readiness(keys).ready and not terrain.readiness([]).ready)
	installed=install(world,draft)
	check("new stream uses identical authoritative transaction",installed.ok)
	if not installed.ok:return finish()
	var facts: Dictionary = world.snapshot()
	started=Time.get_ticks_usec();terrain.on_world_changed(installed.changes)
	costs.after_callback_ms=(Time.get_ticks_usec()-started)/1000.0
	costs.stream_enqueue_ms=terrain.statistics().last_stream_enqueue_usec/1000.0
	costs.environment_sync_ms=terrain.statistics().last_environment_sync_usec/1000.0
	check("opted-in allocation queues without synchronous mesh/collision builds",terrain.statistics().rebuilds==0 and terrain.statistics().pending==256 and not terrain.readiness(keys).geometry_ready,terrain.statistics())
	terrain._process(0.0)
	check("one native budget pass leaves region gated",terrain.statistics().pending>0 and not terrain.readiness(keys).ready,terrain.statistics())
	await drain(terrain)
	check("empty upper chunks and real solid chunks both become physics ready",terrain.readiness(keys).ready,terrain.readiness(keys))
	check("queued mesh/normals/metre UV/indices and collision exactly match old callback",geometry(terrain)==expected_geometry,{"sha256":expected_geometry})
	check("derivation never modifies world/plan/entities",Data.json_equal(world.snapshot(),facts))
	var p: Dictionary=draft.plan.anchors.arrival
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x,15,p.z),Vector3(p.x,-3,p.z))
	var hit: Dictionary=root.get_world_3d().direct_space_state.intersect_ray(query)
	check("physics ray hits true native streamed terrain",not hit.is_empty() and absf(hit.position.y-float(world.surface_height(p.x,p.z)))<0.001,hit.get("position"))
	var key := Data.key(Data.cell_chunk(Vector3i(floori(p.x*2),floori((p.y-0.01)*2),floori(p.z*2)),16))
	var residency: Dictionary=commit(world,[{"op":"chunk.residency","id":key,"before":true,"after":false}])
	terrain.on_world_changed(residency.changes)
	check("cold transition removes old body and overlay immediately",not terrain._chunks.has(key) and not terrain.environment._ground.has(key) and not terrain.environment._contacts.has(key) and terrain.readiness([key]).cold==[key])
	residency=commit(world,[{"op":"chunk.residency","id":key,"before":false,"after":true}])
	# Real runtime operation-array notification, not only a world commit summary.
	terrain.on_world_changed({"world":residency.changes.operations})
	check("runtime raw warm operation is queued and physics gated",terrain._queued.has(key) and not terrain.readiness([key]).ready)
	await drain(terrain)
	check("warm body and all seam faces return exactly",terrain.readiness(keys).ready and geometry(terrain)==expected_geometry)
	var cell := {"x":floori(p.x*2),"y":floori(p.y*2)-1,"z":floori(p.z*2)}
	var edit: Dictionary=commit(world,[{"op":"voxel.set","cell":cell,"before":world.cell_at(cell.x,cell.y,cell.z),"after":0}])
	terrain.on_world_changed({"world":edit.changes.operations})
	check("ordinary dig remains synchronously derived with streaming enabled",terrain.readiness([key]).geometry_ready and not terrain._queued.has(key) and world.cell_at(cell.x,cell.y,cell.z)==0)
	var stamp := geometry(terrain)
	var unrelated: Dictionary=commit(world,[{"op":"extension.set","id":"stream-check","before_exists":false,"before":null,"after":{"ok":true}}])
	terrain.on_world_changed(unrelated.changes)
	await physics_frame;await process_frame
	check("unrelated world revision does not invalidate unchanged chunk readiness",terrain.readiness([key]).ready and geometry(terrain)==stamp)
	terrain.on_world_changed({"reload":true})
	check("reload retires old bodies/overlays and gates until actual rebuild",terrain._chunks.is_empty() and terrain.environment._ground.is_empty() and not terrain.readiness(keys).ready)
	await drain(terrain)
	check("reload rebuilds edited facts rather than regenerated terrain",terrain.readiness(keys).ready and geometry(terrain)==stamp and world.cell_at(cell.x,cell.y,cell.z)==0)
	var upper := "8,2,0"
	var mixed_cell := {"x":cell.x+1,"y":cell.y,"z":cell.z}
	var mixed: Dictionary=commit(world,[{"op":"voxel.set","cell":mixed_cell,"before":world.cell_at(mixed_cell.x,mixed_cell.y,mixed_cell.z),"after":0},{"op":"chunk.residency","id":upper,"before":true,"after":false}])
	terrain.on_world_changed({"world":mixed.changes.operations})
	check("mixed residency and actual dig preserve synchronous edit safety",terrain.readiness([key]).geometry_ready and not terrain._queued.has(key) and world.cell_at(mixed_cell.x,mixed_cell.y,mixed_cell.z)==0)
	terrain.set_streaming_updates(false)
	var default_warm: Dictionary=commit(world,[{"op":"chunk.residency","id":upper,"before":false,"after":true}])
	terrain.on_world_changed({"world":default_warm.changes.operations})
	check("disabled streaming retains original synchronous residency semantics",terrain.readiness([upper]).geometry_ready and terrain.statistics().pending==0)
	var final_geometry := geometry(terrain)
	var encoded: Dictionary=Codec.encode_checkpoint(world.snapshot())
	var decoded: Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	check("native memory checkpoint retains streamed region/plan and both edits",decoded.ok and decoded.state.regions.has("R2:1:0") and Data.json_equal(decoded.state.extensions,world.snapshot().extensions))
	if decoded.ok:
		world.load_snapshot(decoded.state);terrain.on_world_changed({"reload":true})
		check("restored cold checkpoint cannot pass loaded-region gate",terrain.readiness(keys).cold.size()==256 and not terrain.readiness(keys).ready)
		var warm_operations: Array=[]
		for id in keys:warm_operations.append({"op":"chunk.residency","id":id,"before":false,"after":true})
		terrain.set_streaming_updates(true)
		var restored_warm: Dictionary=commit(world,warm_operations)
		terrain.on_world_changed({"world":restored_warm.changes.operations})
		await drain(terrain)
		check("cold save restore rebuilds exact edited collision/mesh without mapgen",terrain.readiness(keys).ready and geometry(terrain)==final_geometry and world.cell_at(cell.x,cell.y,cell.z)==0 and world.cell_at(mixed_cell.x,mixed_cell.y,mixed_cell.z)==0)
	terrain.free()
	finish()
func finish() -> void:
	var failed := checks.filter(func(row: Dictionary)->bool:return not row.ok).size()
	var result := {"scope":"CCC actual one-region stream derivation, not formal app/VA/performance qualification","checks":checks,"failed":failed,"costs":costs}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
