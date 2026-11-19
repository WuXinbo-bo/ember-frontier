extends SceneTree
## Exact A real24 input; preimage/candidate CPU staging and C derived equivalence.
## Explicit C edit/storage fixtures, never a normal player/OS/FPS qualification.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const BeforeTerrain=preload("res://tests/world/fixtures/terrain_before_mount.gd")
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")
const BeforeEnvironment=preload("res://tests/world/fixtures/environment_before_mount.gd")
const State=preload("res://scripts/world/world_state.gd")
const Cover=preload("res://scripts/environment/land_use_cover.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
class DiagnosticClient extends Native:
	func _ready()->void:pass
var checks:Array=[]
var costs:Dictionary={}
var world:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"name":label,"ok":ok,"detail":detail})
func digest(value:Variant)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()
func texture_data(texture:Texture2D)->Array:
	return [] if texture==null else [texture.resource_path,texture.resource_name,texture.get_width(),texture.get_height()]
func material_data(material:Material)->Array:
	if material==null:return []
	var row:Array=[material.get_class(),material.resource_name]
	if material is StandardMaterial3D:
		row.append_array([texture_data(material.albedo_texture),material.albedo_color,material.roughness,material.transparency,material.alpha_scissor_threshold,material.texture_filter,material.texture_repeat,material.cull_mode,material.shading_mode])
	elif material is ShaderMaterial:
		row.append(material.shader.resource_path)
		for p:Dictionary in material.get_property_list():
			if not str(p.name).begins_with("shader_parameter/"):continue
			var v:Variant=material.get(p.name)
			row.append([p.name,texture_data(v) if v is Texture2D else v])
	return row
func mesh_data(mesh:Mesh)->Array:
	var rows:Array=[]
	for i:int in mesh.get_surface_count():rows.append([mesh.surface_get_arrays(i),material_data(mesh.surface_get_material(i))])
	return rows
func node_data(node:Node)->Array:
	var row:Array=[node.get_class()]
	if node is Node3D:row.append(node.transform)
	if node is GeometryInstance3D:row.append(node.cast_shadow)
	for key:String in ["world_entity_id","terrain_chunk","persistent_patch_ids","presentation_patch_ids","foundation_ids","contact_quads","atlas_cell","atlas_baseline_px"]:
		if node.has_meta(key):row.append([key,node.get_meta(key)])
	if node is MeshInstance3D:row.append_array([mesh_data(node.mesh),material_data(node.material_override)])
	if node is MultiMeshInstance3D:
		row.append(mesh_data(node.multimesh.mesh))
		for i:int in node.multimesh.instance_count:row.append(node.multimesh.get_instance_transform(i))
	if node is CollisionObject3D:row.append([node.collision_layer,node.collision_mask])
	if node is CollisionShape3D:
		if node.shape is ConcavePolygonShape3D:row.append(node.shape.get_faces())
		elif node.shape is BoxShape3D:row.append(node.shape.size)
		else:row.append(node.shape.get_class())
	for child:Node in node.get_children():row.append(node_data(child))
	return row
func signature(view:Node3D)->String:
	var result:Array=[]
	for collection:Dictionary in [view._roots,view._ecology,view._ground,view._contacts,view._fields]:
		var keys:Array=collection.keys();keys.sort();var rows:Array=[]
		for key:String in keys:rows.append([key,node_data(collection[key])])
		result.append(rows)
	return digest(result)
func ids(view:Node3D)->Array:
	var rows:Array=[]
	for node:Node3D in view._ecology.values():rows.append_array(node.get_meta("persistent_patch_ids",[]));rows.append_array(node.get_meta("presentation_patch_ids",[]))
	rows.sort();return rows
func compare(a:Node3D,b:Node3D,label:String)->void:
	check(label+" exact mesh/UV/transform/material/collider/IDs",signature(a)==signature(b),{"before":a.statistics(),"after":b.statistics()})
func transact(ops:Array,a:Node3D,b:Node3D)->Dictionary:
	var started:int=Time.get_ticks_usec()
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision())
	var result:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
	var transaction_ms:float=(Time.get_ticks_usec()-started)/1000.0
	if result.ok:
		var builds:int=b.presentation_layout_builds
		started=Time.get_ticks_usec();a.on_world_changed(result.changes)
		var before_ms:float=(Time.get_ticks_usec()-started)/1000.0
		started=Time.get_ticks_usec();b.on_world_changed(result.changes)
		var after_ms:float=(Time.get_ticks_usec()-started)/1000.0
		if not costs.has("notifications"):costs.notifications=[]
		costs.notifications.append({"operation":ops[0].op if not ops.is_empty() else "none","operations":ops.size(),"chunks":result.changes.chunks.size(),"transaction_ms":transaction_ms,"old_notify_ms":before_ms,"candidate_notify_ms":after_ms,"new_layout_builds":b.presentation_layout_builds-builds,"scope":"explicit same C commit, old-first shared material functional diagnostic; not balanced throughput or frame budget"})
	return result
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var output:String=args[0];var input:String=args[1];var input_sha:String=FileAccess.get_sha256(input)
	check("exact A normal24 direct input",input_sha=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48")
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	var host:=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("real Native assembly with 24 regions and 6144 chunks",built.get("ok",false) and built.world.regions().size()==24 and built.world.chunk_keys().size()==6144)
	if not built.get("ok",false):return finish(output)
	world=built.world
	var initial:Dictionary=built.runtime.capture_checkpoint()
	var residency:Dictionary={}
	for r:Dictionary in world.regions():residency[r.id]=world.region_residency_state(r.id).resident_chunks
	costs.residency=residency
	var before_ms:Array=[];var after_ms:Array=[];var samples:Array=[]
	for round_id:int in 4:
		for candidate:bool in ([false,true] if round_id%2==0 else [true,false]):
			var view:Node3D=Terrain.new() if candidate else BeforeTerrain.new()
			view.set_process(false)
			var started:int=Time.get_ticks_usec();view.configure({"world":world,"runtime":built.runtime})
			var elapsed:float=(Time.get_ticks_usec()-started)/1000.0
			var sig:String=signature(view.environment)
			samples.append({"round":round_id,"candidate":candidate,"terrain_environment_ms":elapsed,"signature":sig,"layouts":view.environment.presentation_layout_builds,"stats":view.environment.statistics()})
			if round_id>0:
				if candidate:after_ms.append(elapsed)
				else:before_ms.append(elapsed)
			view.cancel_pending();view.free()
			await process_frame
	before_ms.sort();after_ms.sort()
	costs.samples=samples;costs.before_median_ms=before_ms[1];costs.after_median_ms=after_ms[1]
	costs.scope="same Native world, fresh materials per consumer; alternating order, first sample each disclosed/excluded, headless CPU configure only, no mesh queue pump or OS/FPS budget"
	check("all eight old/current configure outputs are identical",samples.all(func(s:Dictionary)->bool:return s.signature==samples[0].signature))
	check("staging preserves every complete authoritative checkpoint fact",Data.json_equal(initial,built.runtime.capture_checkpoint()))
	var old:=BeforeEnvironment.new();var next:=EnvironmentView.new();root.add_child(old);root.add_child(next)
	old.configure({"world":world});next.configure({"world":world,"materials":old.materials})
	compare(old,next,"initial real24")
	# Extra semantic scenarios are added below; timing always uses original input.
	await semantics(old,next)
	old.free();next.free();built.runtime.retire();host.free()
	check("direct input stays byte identical",FileAccess.get_sha256(input)==input_sha)
	finish(output)
func footprint_keys(patch:Dictionary)->Array:
	var p:Dictionary=patch.position;var width:float=float(patch.footprint[0])*float(patch.scale)*sqrt(2.0)
	var keys:Dictionary={};var y:int=roundi(p.y*2)-1
	for z:int in range(floori((p.z-width/2+0.00001)*2),floori((p.z+width/2-0.00001)*2)+1):
		for x:int in range(floori((p.x-width/2+0.00001)*2),floori((p.x+width/2-0.00001)*2)+1):
			if not world.is_cell_known(x,y,z) or not world.is_cell_known(x,y+1,z) or world.cell_at(x,y,z)!=int(patch.material) or world.cell_at(x,y+1,z)!=0:return []
			for cy:int in [y,y+1]:keys[Data.key(Data.cell_chunk(Vector3i(x,cy,z),16))]=true
	return keys.keys()
func storage(region:String,resident:bool,a:Node3D,b:Node3D,selected:Array=[])->Dictionary:
	var prepared:Dictionary=world.prepare_region_residency(region,resident,world.get_revision())
	if not prepared.ok:return prepared
	var ops:Array=prepared.world_changes
	if not selected.is_empty():ops=ops.filter(func(op:Dictionary)->bool:return op.id in selected)
	return transact(ops,a,b)
func semantics(old:Node3D,next:Node3D)->void:
	check("only original two resident fringe layouts initialized; all persistent ecology indexed",next.presentation_layout_builds==2 and next._deferred_cover_regions.size()==22 and next.statistics().ecology_patches==old.statistics().ecology_patches)
	var region:String="RH-VILLAGE";var chosen:Dictionary={};var selected:Array=[]
	for patch:Dictionary in Cover.patches(world.extension("generation:"+region)):
		selected=footprint_keys(patch)
		if selected.is_empty():continue
		var p:=Vector3(patch.position.x,patch.position.y,patch.position.z);var width:float=float(patch.footprint[0])*float(patch.scale)*sqrt(2.0)
		if old._ecology_blocked({"min":{"x":p.x-width/2,"y":p.y+0.01,"z":p.z-width/2},"max":{"x":p.x+width/2,"y":p.y+1.6,"z":p.z+width/2}}):continue
		chosen=patch;break
	check("partial warm chooses actual clear saved fringe support",not chosen.is_empty(),selected)
	if chosen.is_empty():return
	var warmed:Dictionary=storage(region,true,old,next,selected)
	check("first partial warm builds exact deferred layout without whole-region gate",warmed.ok and not world.region_is_resident(region) and chosen.id in ids(next) and next.presentation_layout_builds==3)
	compare(old,next,"partially resident village")
	var hot:String=signature(next);var before_ids:Array=ids(next)
	var cell:Dictionary={"x":floori(chosen.position.x*2),"y":roundi(chosen.position.y*2)-1,"z":floori(chosen.position.z*2)}
	var dug:Dictionary=transact([{"op":"voxel.set","cell":cell,"before":1,"after":0}],old,next)
	check("actual support dig retires the same visible ID immediately",dug.ok and chosen.id not in ids(next) and ids(next).size()<before_ids.size())
	compare(old,next,"actual dug support")
	var filled:Dictionary=transact([{"op":"voxel.set","cell":cell,"before":0,"after":1}],old,next)
	check("exact fill restores all geometry bindings and IDs without reroll",filled.ok and signature(next)==hot and ids(next)==before_ids and next.presentation_layout_builds==3)
	compare(old,next,"actual refilled support")
	var tree:Dictionary={}
	for id:String in next._roots:
		var e:Dictionary=world.entity(id)
		if e.data.get("harvest",{}).get("phase","standing")=="standing" and e.data.get("phase","")!="stump":tree=e;break
	var stump:Dictionary=tree.duplicate(true);stump.data.phase="stump"
	var cut:Dictionary=transact([{"op":"entity.put","id":tree.id,"before_exists":true,"before":tree,"after":stump}],old,next)
	check("entity change preserves real tree stable ID and updates stump collision",cut.ok and next._roots.has(tree.id) and signature(next)!=hot,{"result":cut.get("code"),"reason":cut.get("reason"),"tree":tree.id})
	compare(old,next,"actual entity stump change")
	var standing:Dictionary=transact([{"op":"entity.put","id":tree.id,"before_exists":true,"before":world.entity(tree.id),"after":tree}],old,next)
	check("same original tree facts restore exact tree geometry",standing.ok and signature(next)==hot)
	var count:int=next.presentation_layout_builds
	var note:Dictionary={"operations":[{"op":"extension.set","id":"generation:"+region}],"chunks":[],"entities":[]}
	old.on_world_changed(note);next.on_world_changed(note)
	check("explicit saved-plan invalidation only regenerates that initialized layout",next.presentation_layout_builds==count+1 and signature(next)==hot)
	compare(old,next,"saved plan invalidation")
	var cooled:Dictionary=storage(region,false,old,next)
	check("full region cold pack retires every newly visible patch",cooled.ok and chosen.id not in ids(next) and world.region_residency_state(region).paged)
	compare(old,next,"exact compressed cold region")
	var lazy:=EnvironmentView.new();root.add_child(lazy);lazy.configure({"world":world,"materials":next.materials})
	check("new consumer defers previously explored now cold fringe",lazy._deferred_cover_regions.has(region) and lazy.presentation_layout_builds==2 and signature(lazy)==signature(next))
	var rewarmed:Dictionary=storage(region,true,old,next,selected)
	lazy.sync()
	check("old synchronous sync without chunk notification detects partial warm",rewarmed.ok and not lazy._deferred_cover_regions.has(region) and lazy.presentation_layout_builds==3 and signature(lazy)==signature(next))
	compare(old,next,"cold page subset warm")
	check("cold subset revisit restores same selected visible ID with exact current checks",chosen.id in ids(next) and world.cell_at(cell.x,cell.y,cell.z)==1)
	lazy.free()
	var packed:Dictionary=storage(region,false,old,next)
	# Save the real cold pages and a real hole, not a regenerated same-seed plan.
	var home_patch:Dictionary={}
	for rows:Array in old._ecology_patch_index.values():
		for patch:Dictionary in rows:
			if patch.id in ids(next):home_patch=patch;break
		if not home_patch.is_empty():break
	var home_cell:Dictionary={"x":floori(home_patch.position.x*2),"y":roundi(home_patch.position.y*2)-1,"z":floori(home_patch.position.z*2)}
	var home_material:int=world.cell_at(home_cell.x,home_cell.y,home_cell.z)
	var saved_dig:Dictionary=transact([{"op":"voxel.set","cell":home_cell,"before":home_material,"after":0}],old,next)
	var saved_world:Dictionary=world.snapshot();var expected:String=signature(next)
	var encoded:Dictionary=Codec.encode_checkpoint(saved_world,{},"C-mount-cold-revisit")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("edited facts and original cold pages encode and recover",packed.ok and saved_dig.ok and loaded.ok and restored.cell_at(home_cell.x,home_cell.y,home_cell.z)==0 and Data.json_equal(restored.extension("generation:"+region),saved_world.extensions["generation:"+region]))
	if not loaded.ok:return
	var recovered_before:=BeforeEnvironment.new();var recovered:=EnvironmentView.new();root.add_child(recovered_before);root.add_child(recovered)
	recovered_before.configure({"world":restored});recovered.configure({"world":restored,"materials":recovered_before.materials})
	check("fully cold decoded consumer leaves fringe generation pending",recovered.presentation_layout_builds==0 and recovered._deferred_cover_regions.size()==24 and recovered._roots.is_empty() and ids(recovered).is_empty())
	compare(recovered_before,recovered,"all cold save consumer")
	var warm_ok:bool=true
	for r:Dictionary in world.regions():
		var wanted:Array=world.region_chunk_keys(r.id).filter(func(key:String)->bool:return world.chunk(key).get("resident",false))
		if wanted.is_empty():continue
		var prep:Dictionary=restored.prepare_region_residency(r.id,true,restored.get_revision())
		var tx:Dictionary=restored.prepare_changes(prep.world_changes.filter(func(op:Dictionary)->bool:return op.id in wanted),restored.get_revision()) if prep.ok else prep
		var committed:Dictionary=restored.commit_prepared(tx.capability) if tx.ok else tx
		warm_ok=warm_ok and committed.ok
		if committed.ok:recovered_before.on_world_changed(committed.changes);recovered.on_world_changed(committed.changes)
	check("save restoration warms only original resident chunks and reproduces exact native edited output",warm_ok and signature(recovered)==expected and restored.cell_at(home_cell.x,home_cell.y,home_cell.z)==0 and region in recovered._deferred_cover_regions)
	compare(recovered_before,recovered,"cold save exact native restored")
	check("presentation never writes generator facts or adds visual extensions",Data.json_equal(saved_world,world.snapshot()))
	recovered_before.free();recovered.free()
	# Existing rural generation has no fringe; keep its original layouts exactly.
	var legacy:=State.new();var legacy_loaded:Dictionary=legacy.load_snapshot(Rural.generate())
	var legacy_before:=BeforeEnvironment.new();var legacy_next:=EnvironmentView.new();root.add_child(legacy_before);root.add_child(legacy_next)
	legacy_before.configure({"world":legacy});legacy_next.configure({"world":legacy,"materials":legacy_before.materials})
	check("unchanged legacy rural authority loads",legacy_loaded.ok)
	compare(legacy_before,legacy_next,"legacy rural layouts")
	legacy_before.free();legacy_next.free()

func finish(output:String)->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"costs":costs},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"costs":costs}));quit(1 if failed else 0)
