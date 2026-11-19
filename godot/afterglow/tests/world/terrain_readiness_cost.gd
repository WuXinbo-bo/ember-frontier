extends "res://tests/world/environment_mount.gd"
## Same immutable real24 input and actual Native provider, no renderer/preview.
const Prior=preload("res://tests/world/fixtures/terrain_before_readiness_projection.gd")
var old:Node3D
var current:Node3D
func drain_near(view:Node3D,keys:Array)->void:
	view.prioritize(keys)
	var loops:int=0
	while loops<4096 and not view.readiness(keys).geometry_ready:
		view.process_budget(4000);loops+=1;await process_frame
	await physics_frame;await process_frame
	check("real local mesh and physical barrier "+str(checks.size()),view.readiness(keys).ready,{"loops":loops,"ready":view.readiness(keys)})
func record(label:String,before:Callable,after:Callable,count:int=100)->void:
	var values:Array=[];var equal:bool=true
	for i:int in count+2:
		var first:Dictionary;var second:Dictionary;var a:int;var b:int;var started:int
		if i%2==0:
			started=Time.get_ticks_usec();first=before.call();a=Time.get_ticks_usec()-started
			started=Time.get_ticks_usec();second=after.call();b=Time.get_ticks_usec()-started
		else:
			started=Time.get_ticks_usec();second=after.call();b=Time.get_ticks_usec()-started
			started=Time.get_ticks_usec();first=before.call();a=Time.get_ticks_usec()-started
		equal=equal and first==second
		if i>=2:values.append({"before_usec":a,"after_usec":b,"after_first":i%2==1})
	costs[label]=values;check(label+" exact same response for alternating samples",equal)
func proposed(host:Node3D,view:Node3D)->Dictionary:
	var near:Dictionary=view.readiness_keys_near(host.runtime.active_positions(),2.5,0.5,2.0);var keys:Dictionary={}
	for key:String in near.get("keys",[]):
		if world.chunk_is_generated(key):keys[key]=true
	view.prioritize(keys.keys());var ready:Dictionary=view.readiness(keys.keys())
	return ready.merged({"ok":ready.ready,"code":"OK" if ready.ready else "NOT_READY","reason":"" if ready.ready else "附近地形正在更新，几何与碰撞就绪后继续","scope":"all living body/tool neighborhoods; whole fixed step is atomic"},true)
func compare_state(label:String,keys:Array)->void:
	check(label+" same readiness",old.readiness(keys)==current.readiness(keys),current.readiness(keys))
	var exact:bool=true;var geometry:bool=true
	for key:String in keys:
		exact=exact and old._dependencies(key)==current._dependencies(key)
		geometry=geometry and old._chunks.has(key)==current._chunks.has(key)
		if old._chunks.has(key):geometry=geometry and digest(node_data(old._chunks[key].node))==digest(node_data(current._chunks[key].node))
		for collection:String in ["_ground","_contacts","_fields"]:
			var a:Dictionary=old.environment.get(collection);var b:Dictionary=current.environment.get(collection)
			geometry=geometry and a.has(key)==b.has(key)
			if a.has(key):geometry=geometry and digest(node_data(a[key]))==digest(node_data(b[key]))
	check(label+" exact actual boundaries",exact)
	check(label+" exact actual mesh UV material collision and ground projections",geometry)
func change(ops:Array)->Dictionary:
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision());var result:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
	check("isolated edit/storage transaction "+str(checks.size()),result.ok)
	if result.ok:old.on_world_changed(result.changes);current.on_world_changed(result.changes)
	return result
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var output:String=args[0];var input:String=args[1]
	check("same real24 input exact SHA",FileAccess.get_sha256(input)=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48")
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input));var host:=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("actual Native24 assembly",built.get("ok",false))
	if not built.get("ok",false):return finish(output)
	world=built.world;host.world=world;host.runtime=built.runtime
	var capture:Dictionary=built.runtime.capture_checkpoint()
	old=Prior.new();current=Terrain.new();root.add_child(old);root.add_child(current)
	old.configure({"world":world,"stream_updates":true,"budgeted_edits":true});old.set_process(false)
	current.configure({"world":world,"stream_updates":true,"budgeted_edits":true,"materials":old.materials});current.set_process(false)
	var points:Array=built.runtime.active_positions();var near:Dictionary=old.readiness_near(points,2.5,0.5,2.0);var keys:Array=[]
	for key:String in near.keys:
		if world.chunk_is_generated(key):keys.append(key)
	check("three real living actors use same generated finite key set",points.size()==3 and not keys.is_empty() and current.readiness_keys_near(points,2.5,0.5,2.0).keys==near.keys,{"points":points,"keys":keys})
	compare_state("pending before local drain",keys)
	await drain_near(old,keys);await drain_near(current,keys)
	compare_state("after physical local drain",keys)
	var exact_geometry:bool=true
	for key:String in keys:
		exact_geometry=exact_geometry and old._chunks.has(key)==current._chunks.has(key)
		if old._chunks.has(key):exact_geometry=exact_geometry and digest(node_data(old._chunks[key].node))==digest(node_data(current._chunks[key].node))
	check("actual near meshes UV normals material and collision exact",exact_geometry)
	record("readiness_same_keys",func()->Dictionary:return old.readiness(keys),func()->Dictionary:return current.readiness(keys))
	record("near_same_points",func()->Dictionary:return old.readiness_near(points,2.5,0.5,2),func()->Dictionary:return current.readiness_near(points,2.5,0.5,2))
	record("actual_A_provider_old_api",func()->Dictionary:host._terrain_view=old;return host._runtime_readiness(),func()->Dictionary:host._terrain_view=current;return host._runtime_readiness())
	record("A_proposed_key_only_composition",func()->Dictionary:host._terrain_view=old;return host._runtime_readiness(),func()->Dictionary:return proposed(host,current))
	check("all read-only sampling preserves complete normal capture",Data.json_equal(capture,built.runtime.capture_checkpoint()))
	var key:String=keys[0];var q:Vector3i=Data.coord(key);var cell:Vector3i=q*16+Vector3i(15,0,1);var material:int=world.cell_at(cell.x,cell.y,cell.z)
	var operation:Dictionary={"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":material,"after":3 if material==0 else 0}
	change([operation]);compare_state("committed actual boundary edit retires readiness",keys)
	await drain_near(old,keys);await drain_near(current,keys)
	compare_state("edited geometry restored physical readiness",keys)
	operation.before=operation.after;operation.after=material;change([operation]);await drain_near(old,keys);await drain_near(current,keys)
	var region:String="RH-HOME";var cool:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	check("actual cold page conversion prepared",cool.ok)
	if cool.ok:
		change(cool.world_changes);compare_state("actual cold pages deny readiness",keys)
		var storage:Dictionary=world.cell_storage_statistics();var snapshot:Dictionary=world.snapshot()
		for i:int in 10:old.readiness(keys);current.readiness(keys)
		check("cold query never expands pages or mutates cells",storage==world.cell_storage_statistics() and Data.json_equal(snapshot,world.snapshot()))
		var warm:Dictionary=world.prepare_region_residency(region,true,world.get_revision());check("explicit real warm prepared",warm.ok)
		if warm.ok:change(warm.world_changes);await drain_near(old,keys);await drain_near(current,keys);compare_state("actual warm restored",keys)
	old.on_world_changed({"reload":true});current.on_world_changed({"reload":true});compare_state("reload retires stale geometry and ready",keys)
	await drain_near(old,keys);await drain_near(current,keys);compare_state("same world reload restores actual physics",keys)
	var fresh:=Terrain.new();root.add_child(fresh);fresh.configure({"world":world,"materials":old.materials});fresh.set_process(false)
	check("remount starts empty boundary cache and no ready license",fresh._boundary_values.is_empty() and not fresh.readiness(keys).ready)
	fresh.free();old.free();current.free();built.runtime.retire();host.free()
	costs.scope="exact real24 Native assembly and actual provider, same-input alternating headless CPU; not renderer/OS/FPS/quiet performance. Counterexample edit/cold/reload operations are isolated fixtures, not normal gameplay or new saved input."
	finish(output)
