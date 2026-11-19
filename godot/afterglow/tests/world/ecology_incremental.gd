extends SceneTree
## Same actual A/B landscape input, full derivation versus explicit dirty events.
const Rural=preload("res://scripts/world/rural_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Materials=preload("res://scripts/environment/environment_materials.gd")
# Both paths render the CURRENT image style. Frozen pre-quality bytes/evidence
# remain separate; they cannot qualify different assets or native meshes.
const Before=preload("res://scripts/environment/environment_view.gd")
const After=preload("res://scripts/environment/environment_view.gd")
var checks:Array=[]
var costs:Dictionary={}
var world:=State.new()
var full:Node3D
var incremental:Node3D
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func signature(view:Node3D)->Dictionary:
	var rows:Array=[];var keys:Array=view._ecology.keys();keys.sort()
	for key:String in keys:
		var node:Node3D=view._ecology[key];var parts:Array=[]
		for item:MultiMeshInstance3D in node.get_children():
			var mm:MultiMesh=item.multimesh;var transforms:Array=[];var surfaces:Array=[]
			for i in mm.instance_count:transforms.append(mm.get_instance_transform(i))
			for i in mm.mesh.get_surface_count():
				var a:Array=mm.mesh.surface_get_arrays(i)
				surfaces.append([a[Mesh.ARRAY_VERTEX],a[Mesh.ARRAY_NORMAL],a[Mesh.ARRAY_TEX_UV],a[Mesh.ARRAY_INDEX]])
			parts.append([transforms,surfaces])
		rows.append([key,node.get_meta("persistent_patch_ids"),parts])
	var tree_ids:Array=view._signatures.keys();tree_ids.sort();var trees:Array=[]
	for id:String in tree_ids:trees.append([id,view._signatures[id]])
	return {"ecology_sha256":var_to_bytes(rows).hex_encode().sha256_text(),"trees":trees}
func same(label:String)->void:
	check(label,signature(full)==signature(incremental),{"full":full.statistics(),"incremental":incremental.statistics()})
func commit(ops:Array)->Dictionary:
	var draft:Dictionary=world.prepare_changes(ops,world.get_revision())
	return world.commit_prepared(draft.capability) if draft.ok else draft
func update(result:Dictionary)->void:
	if not result.ok:return
	for op:Dictionary in result.changes.operations:
		if op.op=="extension.set" and str(op.id).begins_with("generation:"):full._ecology_layout_dirty=true
	full.sync();incremental.on_world_changed(result.changes)
func median(values:Array)->float:
	var copy:Array=values.duplicate();copy.sort();return copy[copy.size()/2]
func run()->void:
	var source:Dictionary=Rural.generate_settlement(713,Buildings.generation_profiles())
	var assembled:Dictionary=Assembly.prepare(source)
	check("actual A/B new landscape assembled",assembled.ok)
	if not assembled.ok:return finish()
	world.load_snapshot(assembled.capture.world)
	var mats:=Materials.new();full=Before.new();incremental=After.new()
	root.add_child(full);root.add_child(incremental)
	full.configure({"world":world,"materials":mats});incremental.configure({"world":world,"materials":mats})
	same("cached complete ecology has exact native geometry and transforms")
	var patch:Dictionary={}
	for region:Dictionary in world.regions():
		for candidate:Dictionary in world.extension("generation:"+region.id).ecology.patches:
			if not full._ecology.has(Data.key(Data.cell_chunk(Vector3i(floori(candidate.position.x*2),floori((candidate.position.y-0.001)*2),floori(candidate.position.z*2)),16))):continue
			var ids:Array=full._ecology[Data.key(Data.cell_chunk(Vector3i(floori(candidate.position.x*2),floori((candidate.position.y-0.001)*2),floori(candidate.position.z*2)),16))].get_meta("persistent_patch_ids")
			if candidate.id in ids:patch=candidate;break
		if not patch.is_empty():break
	check("cost and edit input is an actually mounted persistent patch",not patch.is_empty(),patch.get("id"))
	if patch.is_empty():return finish()
	var p:Dictionary=patch.position;var cell:Dictionary={"x":floori(p.x*2),"y":roundi(p.y*2)-1,"z":floori(p.z*2)}
	var material:int=world.cell_at(cell.x,cell.y,cell.z)
	var full_times:Array=[];var dirty_times:Array=[];var all_equal:=true;var less:=true
	for i in 10:
		var result:=commit([{"op":"voxel.set","cell":cell,"before":material if i%2==0 else 0,"after":0 if i%2==0 else material}])
		if not result.ok:all_equal=false;break
		var a:float;var b:float;var t:int
		if i%2==0:
			t=Time.get_ticks_usec();full.sync();a=(Time.get_ticks_usec()-t)/1000.0
			t=Time.get_ticks_usec();incremental.on_world_changed(result.changes);b=(Time.get_ticks_usec()-t)/1000.0
		else:
			t=Time.get_ticks_usec();incremental.on_world_changed(result.changes);b=(Time.get_ticks_usec()-t)/1000.0
			t=Time.get_ticks_usec();full.sync();a=(Time.get_ticks_usec()-t)/1000.0
		all_equal=all_equal and signature(full)==signature(incremental)
		less=less and incremental.statistics().last_ecology_candidates<158
		if i>=2:full_times.append(a);dirty_times.append(b)
	costs={"samples":8,"alternating_call_order":true,"same_actual_voxel_edits":true,"full_ms":full_times,"dirty_ms":dirty_times,"full_median_ms":median(full_times),"dirty_median_ms":median(dirty_times),"scope":"headless CPU derivation only; not quiet-window/OS/GPU/FPS acceptance"}
	check("ten actual digs/fills retain exact full-sync native result",all_equal)
	check("explicit changed chunks bound the ecology candidate set",less,incremental.statistics())
	var key:=Data.key(Data.cell_chunk(Vector3i(cell.x,cell.y,cell.z),16))
	var result:=commit([{"op":"chunk.residency","id":key,"before":true,"after":false}]);update(result)
	same("cold support removes matching full-sync native patches")
	result=commit([{"op":"chunk.residency","id":key,"before":false,"after":true}]);update(result)
	same("warm support remounts original patches without reroll")
	# Exercise a true diagonal footprint dependency, not only centre-cell edits.
	var diagonal:Dictionary={}
	for z in range(-56,57,8):
		for x in range(8,57,8):
			var height:Variant=world.surface_height(x-0.25,z-0.25)
			if height==null:continue
			var pos:=Vector3(x-0.25,height,z-0.25)
			var mat:int=world.cell_at(x*2-1,roundi(height*2)-1,z*2-1)
			if not incremental._grounded(pos,Vector2.ONE*0.9,mat):continue
			var bounds:Dictionary={"min":{"x":pos.x-0.45,"y":pos.y+0.01,"z":pos.z-0.45},"max":{"x":pos.x+0.45,"y":pos.y+1.6,"z":pos.z+0.45}}
			if world.entities_in_bounds(bounds).any(func(e:Dictionary)->bool:return e.get("data",{}).get("solid",false)):continue
			diagonal={"id":"test:diagonal-footprint","model":"low_cover","position":{"x":pos.x,"y":pos.y,"z":pos.z},"yaw":0.0,"scale":1.0,"footprint":[0.636396,0.636396],"material":mat};break
		if not diagonal.is_empty():break
	check("real uniform surface supports a patch crossing X and Z boundaries",not diagonal.is_empty(),diagonal)
	if not diagonal.is_empty():
		var region:Dictionary=world.region_at(diagonal.position)
		var id:String="generation:"+region.id;var old:Dictionary=world.extension(id);var next:Dictionary=old.duplicate(true);next.ecology.patches.append(diagonal)
		result=commit([{"op":"extension.set","id":id,"before_exists":true,"before":old,"after":next}]);update(result)
		same("generation extension-only notification rebuilds cached dependency layout")
		p=diagonal.position
		var far_cell:Dictionary={"x":floori((p.x+0.35)*2),"y":roundi(p.y*2)-1,"z":floori((p.z+0.35)*2)}
		result=commit([{"op":"voxel.set","cell":far_cell,"before":diagonal.material,"after":0}]);update(result)
		same("diagonal support dig invalidates the opposite anchor chunk")
		result=commit([{"op":"voxel.set","cell":far_cell,"before":0,"after":diagonal.material}]);update(result)
		same("diagonal matching fill recovers identical original geometry")
		var blocker:Dictionary={"id":"test:ecology-solid","kind":"resource","regionId":region.id,"position":p.duplicate(),"bounds":{"min":{"x":p.x-0.1,"y":p.y,"z":p.z-0.1},"max":{"x":p.x+0.1,"y":p.y+1.0,"z":p.z+0.1}},"tags":[],"data":{"solid":true},"revision":0}
		result=commit([{"op":"entity.put","id":blocker.id,"before_exists":false,"before":null,"after":blocker}]);update(result)
		same("new solid entity refreshes projection and removes overlapped plants")
		result=commit([{"op":"entity.remove","id":blocker.id,"before":world.entity(blocker.id)}]);update(result)
		same("removed solid refreshes projection and restores derived plants")
	var snapshot:Dictionary=world.snapshot();incremental.clear_ground();incremental.on_world_changed({"reload":true});full._ecology_layout_dirty=true;full.sync()
	same("reload invalidates cached plans residency and entities")
	check("derived reload leaves complete world facts untouched",Data.json_equal(snapshot,world.snapshot()))
	var passes:int=incremental.sync_passes
	incremental.on_world_changed({"operations":[{"op":"extension.set","id":"r3:production"}],"chunks":[],"entities":[]})
	check("unrelated production notification does no extra derivation",passes==incremental.sync_passes)
	full.free();incremental.free();finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
