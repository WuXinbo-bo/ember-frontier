extends SceneTree
## Actual normal-command outputs are readonly inputs. Only cold/warm storage
## below is an explicit isolated C transaction fixture, not runtime scheduling.
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
const TerrainView=preload("res://scripts/terrain/terrain_view.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"label":label,"ok":ok,"detail":detail})
func signature(data:Dictionary)->String:return var_to_bytes([data.groups,data.quads,data.solid_cells]).hex_encode().sha256_text()
func node_data(node:Node)->Array:
	var row:Array=[node.get_class()]
	if node is Node3D:row.append(node.transform)
	if node is MeshInstance3D:
		for i:int in node.mesh.get_surface_count():row.append(node.mesh.surface_get_arrays(i))
	if node is MultiMeshInstance3D:
		for i:int in node.multimesh.mesh.get_surface_count():row.append(node.multimesh.mesh.surface_get_arrays(i))
		for i:int in node.multimesh.instance_count:row.append(node.multimesh.get_instance_transform(i))
	if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:row.append(node.shape.get_faces())
	for child:Node in node.get_children():row.append(node_data(child))
	return row
func derived_signature(view:Node3D)->String:
	var rows:Array=[]
	for collection:Dictionary in [view._chunks,view.environment._roots,view.environment._ecology,view.environment._ground,view.environment._contacts,view.environment._fields]:
		var keys:Array=collection.keys();keys.sort();var list:Array=[]
		for key:String in keys:list.append([key,node_data(collection[key].node if collection[key] is Dictionary else collection[key])])
		rows.append(list)
	return var_to_bytes(rows).hex_encode().sha256_text()
func apply(world:RefCounted,view:Node3D,ops:Array)->Dictionary:
	var prep:Dictionary=world.prepare_changes(ops,world.get_revision())
	if not prep.ok:return prep
	var commit:Dictionary=world.commit_prepared(prep.capability)
	if commit.ok:view.on_world_changed(commit.changes)
	return commit
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var report:String=args[0];var rows:Array=[]
	for index:int in range(1,args.size()):
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[index]));var seed:int=int(decoded.get("capture",{}).get("world",{}).get("seed",-1))
		check("seed%d exact normal-command file decodes"%seed,decoded.get("ok",false))
		if not decoded.get("ok",false):continue
		var live:=State.new();var mounted:Dictionary=live.load_snapshot(decoded.capture.world)
		# Native envelopes deliberately decode to compact cold pages. Use the
		# existing pure C warm transaction before asking a renderer for geometry;
		# the normal-route test separately verifies Native's full warm mount.
		var page_count:int=live.cell_storage_statistics().cold_page_count if mounted.ok else 0
		var warmed:bool=mounted.ok
		if mounted.ok:
			for region:Dictionary in live.regions():
				var prep:Dictionary=live.prepare_region_residency(region.id,true,live.get_revision())
				var transaction:Dictionary=live.prepare_changes(prep.world_changes,live.get_revision()) if prep.ok else prep
				var committed:Dictionary=live.commit_prepared(transaction.capability) if transaction.ok else transaction
				warmed=warmed and committed.ok
		check("seed%d readonly native input cold pages use existing lossless warm API"%seed,warmed and live.cell_storage_statistics().cold_page_count==0,{"decoded_cold_pages":page_count})
		var profiles:Array=Modules.generation_profiles();var lock:Dictionary=Contract.fresh(profiles,8,1)
		var made:Dictionary=Assembly.prepare(Factory.generate(seed,profiles,lock.contract));var original:=State.new()
		var original_mount:Dictionary=original.load_snapshot(made.capture.world) if made.get("ok",false) else made
		check("seed%d original and actual changed authority mount"%seed,mounted.ok and original_mount.ok)
		if not mounted.ok or not original_mount.ok:continue
		var plan:Dictionary=live.extension("generation:RH-HOME");var site:Dictionary=plan.story_entrances[0];var own:Dictionary={};var affected:Dictionary={}
		for c:Dictionary in site.obstacle_cells:
			var key:String=Data.key(Data.cell_chunk(Vector3i(c.x,c.y,c.z),16));own[key]=true;affected[key]=true
		for key:String in own:
			for axis:int in 3:
				for sign:int in [-1,1]:var q:Vector3i=Data.coord(key);q[axis]+=sign;affected[Data.key(q)]=true
		var changed:int=0;var delta_cells:int=0;var uv_ok:bool=true;var quads:Array=[];var started:int=Time.get_ticks_usec()
		for key:String in affected:
			var before:Dictionary=Mesher.build(original,key);var after:Dictionary=Mesher.build(live,key)
			if signature(before)!=signature(after):changed+=1
			if own.has(key):delta_cells+=before.solid_cells-after.solid_cells
			for g:Dictionary in after.groups.values():
				for i:int in g.vertices.size():
					var p:Vector3=g.vertices[i];var normal:Vector3=g.normals[i]
					var expected:=Vector2(p.x,p.z) if absf(normal.y)>0.5 else Vector2(p.z if absf(normal.x)>0.5 else p.x,p.y)
					uv_ok=uv_ok and g.uvs[i]==expected
			quads.append({"key":key,"before":before.quads,"after":after.quads,"before_solid":before.solid_cells,"after_solid":after.solid_cells})
		check("seed%d crossing two real chunks removes exactly24 cells and updates both meshes"%seed,own.size()==2 and changed>=2 and delta_cells==24,{"own":own.keys(),"changed":changed,"solid_delta":delta_cells})
		check("seed%d derived new faces retain exact global metre UVs"%seed,uv_ok)
		var view:=TerrainView.new();root.add_child(view);view.set_process(false);view.configure({"world":live,"stream_updates":true,"budgeted_edits":true});view.cancel_pending()
		for key:String in own:view._rebuild(key)
		await physics_frame
		var shapes_ok:bool=true;var bound_rock:bool=false
		for key:String in own:
			if not view._chunks.has(key):
				var current:Dictionary=Mesher.build(live,key)
				check("seed%d empty derived chunk has no spurious body %s"%[seed,key],current.groups.is_empty(),{"derived":view._derived.get(key),"quads":current.quads,"solid":current.solid_cells,"resident":live.chunk(key).get("resident")})
				shapes_ok=shapes_ok and current.groups.is_empty()
				continue
			var node:Node3D=view._chunks[key].node;var mesh:ArrayMesh=node.get_child(0).mesh;var shape:ConcavePolygonShape3D=node.get_child(1).get_child(0).shape
			shapes_ok=shapes_ok and shape.get_faces()==mesh.get_faces() and not shape.get_faces().is_empty()
			for i:int in mesh.get_surface_count():
				var mat:Material=mesh.surface_get_material(i)
				if mat is StandardMaterial3D and mat.resource_name.begins_with("C:quality:r0") and mat.albedo_texture!=null:bound_rock=true
		var env:Dictionary=view.environment.statistics();var hot:String=derived_signature(view)
		check("seed%d actual new meshes share exact native trimesh collision and readiness"%seed,shapes_ok and view.readiness(own.keys()).ready)
		# The cleared upper chunk can correctly be entirely empty: verify the
		# original physical stone really bound the existing images, separately.
		for key:String in own:
			var original_mesh:ArrayMesh=Mesher.mesh(Mesher.build(original,key),view.materials)
			for i:int in original_mesh.get_surface_count():
				var mat:Material=original_mesh.surface_get_material(i)
				if mat is StandardMaterial3D and mat.resource_name.begins_with("C:quality:r0") and mat.albedo_texture!=null:bound_rock=true
		check("seed%d existing real stone materials and all environment images resolve"%seed,bound_rock and env.missing_materials.is_empty() and env.missing_models.is_empty() and env.missing_quality_images.is_empty(),env)
		var before_storage:Dictionary=live.snapshot();var release:Dictionary=live.prepare_region_residency("RH-HOME",false,live.get_revision())
		var cold:Dictionary=apply(live,view,release.world_changes) if release.ok else release
		check("seed%d isolated cold release removes affected bodies and all home environment"%seed,cold.ok and own.keys().all(func(k:String)->bool:return not view._chunks.has(k)) and not view.readiness(own.keys()).ready and live.entities("RH-HOME").all(func(e:Dictionary)->bool:return not view.environment._roots.has(e.id)))
		var warm_prepare:Dictionary=live.prepare_region_residency("RH-HOME",true,live.get_revision());var warm:Dictionary=apply(live,view,warm_prepare.world_changes) if warm_prepare.ok else warm_prepare
		view.cancel_pending()
		for key:String in own:view._rebuild(key)
		await physics_frame
		check("seed%d warm restores identical affected native meshes collision environment and UV"%seed,warm.ok and view.readiness(own.keys()).ready and derived_signature(view)==hot)
		var unchanged:bool=true
		for key:String in before_storage.chunks:unchanged=unchanged and before_storage.chunks[key].cells==live.chunk(key).cells
		check("seed%d storage fixture preserves all actual command-edited cells and entrance plan"%seed,unchanged and Data.json_equal(plan,live.extension("generation:RH-HOME")) and site.obstacle_cells.all(func(c:Dictionary)->bool:return live.cell_at(c.x,c.y,c.z)==0))
		rows.append({"seed":seed,"input":args[index],"affected":affected.keys(),"actual_mesh_chunks":own.keys(),"arrays":quads,"elapsed_usec":Time.get_ticks_usec()-started,"environment":env,"signature":hot});view.free()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"post23 affected exact normal command input C derivation; cold/warm is explicit isolated storage transaction, no scheduler/PCK/OS/Metal/FPS/G5"},"\t",true,true));quit(1 if failed else 0)
