extends SceneTree
## Bounded same-input, same-quality source comparison. Not renderer/FPS proof.
const Prior=preload("res://tests/performance/fixtures/environment_before_experience14.gd")
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const OldTerrain=preload("res://tests/world/fixtures/terrain_before_readiness_projection.gd")
const View=preload("res://scripts/world/world_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var costs:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error(label)
func node_data(node:Node)->Array:
	var row:Array=[node.get_class()]
	if node is Node3D:row.append(node.transform)
	if node is MeshInstance3D:
		for i:int in node.mesh.get_surface_count():row.append(node.mesh.surface_get_arrays(i))
	if node is MultiMeshInstance3D:
		for i:int in node.multimesh.mesh.get_surface_count():row.append(node.multimesh.mesh.surface_get_arrays(i))
		for i:int in node.multimesh.instance_count:row.append(node.multimesh.get_instance_transform(i))
	if node is CollisionShape3D:
		if node.shape is ConcavePolygonShape3D:row.append(node.shape.get_faces())
		elif node.shape is BoxShape3D:row.append(node.shape.size)
	for child:Node in node.get_children():row.append(node_data(child))
	return row
func signature(view:Node3D)->String:
	var rows:Array=[]
	for collection:Dictionary in [view._roots,view._ecology,view._ground,view._contacts,view._fields]:
		var keys:Array=collection.keys();keys.sort()
		for key:String in keys:rows.append([key,node_data(collection[key])])
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(rows));return h.finish().hex_encode()
func notify(world:RefCounted,ops:Array,a:Node3D,b:Node3D,label:String)->void:
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision())
	var committed:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
	check(label+" complete C transaction",committed.ok,committed.get("reason"))
	if not committed.ok:return
	var started:int=Time.get_ticks_usec();a.on_world_changed(committed.changes);var before:int=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec();b.on_world_changed(committed.changes);var after:int=Time.get_ticks_usec()-started
	var old_sig:String=signature(a);var new_sig:String=signature(b)
	check(label+" exact native mesh/UV/transform/shape",old_sig==new_sig,{"before":old_sig,"after":new_sig})
	costs.append({"label":label,"before_usec":before,"after_usec":after,"scope":"same C transaction, headless old-first derived staging, shared materials; not balanced GPU/FPS"})
func queue_checks()->void:
	var cells:=PackedInt32Array();cells.resize(4096)
	var state:Dictionary={"worldId":"queue:exact","revision":1,"config":Data.DEFAULT_CONFIG.duplicate(true),"chunks":{}}
	for z:int in 20:
		for x:int in 20:state.chunks[Data.key(Vector3i(x,0,z))]={"revision":1,"generated":true,"resident":true,"cells":cells}
	var world:=View.new(state);var old:=OldTerrain.new();var next:=Terrain.new();old.world=world;next.world=world
	var keys:Array=world.chunk_keys()
	for key:String in keys:old._enqueue(key);next._enqueue(key)
	var selected:Array=[]
	for i:int in range(0,keys.size(),2):selected.append(keys[i])
	selected.append_array([keys[0],"999,0,999",keys[2]])
	var start:int=Time.get_ticks_usec();old.prioritize(selected);var old_us:int=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec();next.prioritize(selected);var new_us:int=Time.get_ticks_usec()-start
	check("queue stable partition keeps exact duplicate/unknown order and membership",old._queue==next._queue and old._queued==next._queued)
	old._active={"key":keys[4]};next._active={"key":keys[4]}
	old.prioritize([keys[4],keys[5],keys[6]]);next.prioritize([keys[4],keys[5],keys[6]])
	check("active chunk is never cancelled/reordered by priority",old._queue==next._queue and old._active==next._active)
	costs.append({"label":"400 queued / 203 priority keys","before_usec":old_us,"after_usec":new_us,"scope":"single headless synthetic queue operation, no mesh/FPS claim"})
	old._active.clear();next._active.clear();old.free();next.free()
func run()->void:
	queue_checks()
	var profiles:Dictionary=Assembly.generation_profiles(13)
	check("retained content13 profile lock",profiles.ok)
	if not profiles.ok:return finish()
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(Assembly.generate(713,profiles.profiles,13))
	check("real two-region content13 terrain loads",loaded.ok)
	if not loaded.ok:return finish()
	var a:=Prior.new();var b:=EnvironmentView.new();root.add_child(a);root.add_child(b);a.set_process(false);b.set_process(false)
	a.configure({"world":world});b.configure({"world":world,"materials":a.materials})
	check("initial native output is identical",signature(a)==signature(b))
	var original:Dictionary={}
	for id:String in b._roots:original[id]=b._roots[id].get_instance_id()
	var input:Dictionary=Factory.region_generation_input(world,profiles.profiles)
	var draft:Dictionary=Factory.draft_region_request(input,Vector2i(1,0))
	var prepared:Dictionary=Factory.prepare_region_draft(world,draft,world.get_revision()) if draft.ok else draft
	check("real detached neighbor generation prepares",prepared.ok)
	if prepared.ok:notify(world,prepared.world_changes,a,b,"append neighboring region")
	var retained:bool=true
	for id:String in original:
		if b._roots.has(id):retained=retained and b._roots[id].get_instance_id()==original[id]
	check("unchanged original tree nodes retain identity",retained)
	var tree:Dictionary={}
	for e:Dictionary in world.entities():
		if e.kind=="tree":tree=e;break
	if not tree.is_empty():
		var changed:Dictionary=tree.duplicate(true);changed.data.appearance.yaw+=0.2
		var cell:Vector3i=Vector3i(floori(tree.position.x*2),floori(tree.position.y*2)-1,floori(tree.position.z*2))
		var material:int=world.cell_at(cell.x,cell.y,cell.z)
		notify(world,[{"op":"entity.put","id":tree.id,"before_exists":true,"before":tree,"after":changed},{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":material,"after":0}],a,b,"mixed tree and live support edit")
	a.free();b.free();finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs,"scope":"bounded source equivalence of real content13 generation/derived geometry plus isolated queue; not normal gameplay, GPU or FPS acceptance"}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print("EXPERIENCE14_PROJECTION "+JSON.stringify({"checks":checks.size(),"failed":failed,"costs":costs}));quit(1 if failed else 0)
