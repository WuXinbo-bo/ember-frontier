extends SceneTree
## Material correction only: exact saved24 input plus explicit isolated edits.
## No renderer, normal-play qualification, new generation or final VA assertion.
const Materials=preload("res://scripts/environment/environment_materials.gd")
const OldMaterials=preload("res://tests/world/fixtures/natural_soil_before_materials.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
const OldMesher=preload("res://tests/world/fixtures/natural_soil_before_mesher.gd")
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const State=preload("res://scripts/world/world_state.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var observations:Array=[]
var _image_hashes:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func image_hash(texture:Texture2D)->String:
	if texture==null:return "missing"
	var id:int=texture.get_instance_id()
	if not _image_hashes.has(id):
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(texture.get_image().get_data());_image_hashes[id]=hash.finish().hex_encode()
	return _image_hashes[id]
func material_signature(mat:Material)->Array:
	if mat is StandardMaterial3D:
		return ["native",image_hash(mat.albedo_texture),mat.uv1_scale,mat.albedo_color,mat.texture_filter,mat.texture_repeat,mat.roughness,mat.transparency,mat.cull_mode]
	var rows:Array=["shader",mat.shader.code]
	for row:Dictionary in mat.shader.get_shader_uniform_list():
		var value:Variant=mat.get_shader_parameter(row.name)
		rows.append([row.name,image_hash(value) if value is Texture2D else value])
	return rows
func set_residency(world:RefCounted,keys:Array,value:bool)->bool:
	var ops:Array=[]
	for key:String in keys:
		var chunk:Dictionary=world.chunk(key)
		if chunk.is_empty() or chunk.resident==value:continue
		if value and chunk.has("cell_page"):
			var unpacked:Dictionary=Data.ChunkPage.unpack(chunk.cell_page,4096,Data.MATERIALS)
			if not unpacked.ok:return false
			ops.append({"op":"chunk.storage","id":key,"before":{"revision":chunk.revision,"resident":chunk.resident,"sha256":chunk.cell_page.raw_sha256},"after":{"resident":true,"cells":unpacked.cells,"cell_page":null}})
		else:ops.append({"op":"chunk.residency","id":key,"before":not value,"after":value})
	if ops.is_empty():return true
	var prepared:Dictionary=world.prepare_changes(ops,world.get_revision())
	return prepared.ok and world.commit_prepared(prepared.capability).ok
func cool_pages(world:RefCounted,keys:Array)->bool:
	var ops:Array=[]
	for key:String in keys:
		var chunk:Dictionary=world.chunk(key)
		if chunk.is_empty():continue
		var packed:Dictionary=Data.ChunkPage.pack(chunk.cells,4096,Data.MATERIALS)
		if not packed.ok:return false
		ops.append({"op":"chunk.storage","id":key,"before":{"revision":chunk.revision,"resident":chunk.resident,"sha256":Data.ChunkPage.fingerprint(chunk.cells)},"after":{"resident":false,"cells":PackedInt32Array(),"cell_page":packed.page}})
	var prepared:Dictionary=world.prepare_changes(ops,world.get_revision())
	return prepared.ok and world.commit_prepared(prepared.capability).ok
func compare_meshes(world:RefCounted,label:String,keys:Array)->void:
	var prior:=OldMaterials.new();prior.set_world_style("factory-country-1")
	var live:=Materials.new();live.set_world_style("factory-country-1",8)
	var exact:bool=true;var selected:bool=true;var uv_ok:bool=true
	var changed:int=0;var unchanged:int=0;var quads:int=0;var native_image_bytes:int=0
	for key:String in keys:
		var before:Dictionary=OldMesher.build(world,key);var data:Dictionary=Mesher.build(world,key)
		exact=exact and before==data
		var a:ArrayMesh=OldMesher.mesh(before,prior);var b:ArrayMesh=Mesher.mesh(data,live)
		exact=exact and a.get_surface_count()==b.get_surface_count()
		if a.get_surface_count()>0:exact=exact and a.create_trimesh_shape().get_faces()==b.create_trimesh_shape().get_faces()
		var index:int=0
		for group:Dictionary in data.groups.values():
			var arrays:Array=b.surface_get_arrays(index)
			exact=exact and a.surface_get_arrays(index)==arrays
			var top:bool=group.normals[0].y>0.5
			var target:bool=not top and group.material in [1,2] and group.texture=="soil_side"
			var old_mat:Material=a.surface_get_material(index);var mat:Material=b.surface_get_material(index)
			if target:
				changed+=1
				selected=selected and mat is StandardMaterial3D and image_hash(mat.albedo_texture)==image_hash(live.material("natural_soil_side").albedo_texture) and mat.uv1_scale.is_equal_approx(Vector3(0.625,0.625,1))
			else:
				unchanged+=1;selected=selected and material_signature(old_mat)==material_signature(mat)
			for i:int in arrays[Mesh.ARRAY_VERTEX].size():
				var p:Vector3=arrays[Mesh.ARRAY_VERTEX][i];var n:Vector3=arrays[Mesh.ARRAY_NORMAL][i]
				var expected:Vector2=Vector2(p.x,p.z) if absf(n.y)>0.5 else Vector2(p.z if absf(n.x)>0.5 else p.x,p.y)
				uv_ok=uv_ok and arrays[Mesh.ARRAY_TEX_UV][i].is_equal_approx(expected)
			index+=1
		quads+=data.quads
	check(label+": identical authoritative mesh arrays normals indices and trimesh collider",exact)
	check(label+": only grass/soil non-top surfaces select candidate; road/rock/top unchanged",selected and changed>0 and unchanged>0,{"changed_surfaces":changed,"unchanged_surfaces":unchanged})
	check(label+": continuous metre UV including negative/vertical coordinates",uv_ok)
	if live._cache.has("natural_soil_side"):native_image_bytes=live.material("natural_soil_side").albedo_texture.get_image().get_data().size()
	observations.append({"label":label,"keys":keys,"quads":quads,"changed_surfaces":changed,"unchanged_surfaces":unchanged,"new_image_native_bytes_including_mips":native_image_bytes})
func run()->void:
	var args:=OS.get_cmdline_user_args();var input:String=FileAccess.get_file_as_string(args[1])
	var envelope:Dictionary=JSON.parse_string(input)
	check("real immutable saved24 envelope SHA",str(envelope.payload).sha256_text()==envelope.sha256)
	var capture:Dictionary=JSON.parse_string(envelope.payload);var decoded:Dictionary=Codec.decode(capture.world)
	var world:=State.new()
	check("existing codec loads original content8 source without regeneration",decoded.ok and world.load_snapshot(decoded.state).ok and world.extension_fields("generation:factory-r34",["content_version"]).get("content_version")==8)
	var initial:Dictionary=world.snapshot()
	var old:=OldMaterials.new();var live:=Materials.new()
	var original_manifest:Dictionary=old.manifest();original_manifest.erase("natural_soil_side")
	var next_manifest:Dictionary=live.manifest();next_manifest.erase("natural_soil_side")
	check("all original image manifest rows unchanged",original_manifest==next_manifest)
	var row:Dictionary=live.manifest().natural_soil_side
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(FileAccess.get_file_as_bytes(row.resource))
	check("exact selected candidate image and unchanged 1.6m contract",hash.finish().hex_encode()==row.sha256 and row.sha256=="a01e31a823094efded12c31f1d58663220889b2165bb5afa1645457c977d54fb" and row.metres==[1.6,1.6])
	for generator:String in ["r3-town-5","rural-1","rural-2","rural-3","factory-country-1"]:
		for version:int in [0,1,2,3,4,5,6,7,10]:
			old.set_world_style(generator);live.set_world_style(generator,version)
			var exact:bool=true
			for material_id:int in range(1,7):
				for face:String in ["top","side"]:
					var id:String=Data.MATERIALS[material_id][face]
					if face=="top" and material_id==2:id="soil_top"
					exact=exact and material_signature(old.terrain_material(id,face))==material_signature(live.terrain_material(id,face,material_id))
			check("legacy/unadopted exact material selection "+generator+":"+str(version),exact)
	live.set_world_style("factory-country-1",8)
	check("old two-argument material API preserves prior source",material_signature(old.terrain_material("soil_side","side"))==material_signature(live.terrain_material("soil_side","side")))
	var selected:Material=live.terrain_material("soil_side","side",1)
	check("grass and soil share same native candidate without per-cell material",selected==live.terrain_material("soil_side","side",2))
	check("road cuttings explicitly retain original soil image",image_hash(live.terrain_material("soil_side","side",4).albedo_texture)==image_hash(live.material("soil_side").albedo_texture))
	var source_data:Dictionary={"groups":{"grass":{"normals":[Vector3.RIGHT],"material":1,"texture":"soil_side"},"road":{"normals":[Vector3.RIGHT],"material":4,"texture":"soil_side"},"soil":{"normals":[Vector3.UP],"material":2,"texture":"soil_side"}}}
	var requests:Array=live.terrain_preparation(source_data);var ids:Array=requests.map(func(r:Dictionary)->String:return r.id)
	check("preparation selects candidate and preserves existing top/road sources",ids.has("natural_soil_side") and ids.has("soil_side") and ids.has("soil_top_fine") and ids.count("natural_soil_side")==1,ids)
	for request:Dictionary in requests:live.prepare_terrain_input(request)
	var before_keys:Array=live._cache.keys();Mesher.mesh({"groups":{},"quads":0},live)
	check("empty mesh does not load additional resources",before_keys==live._cache.keys())
	var prior_selected:Material=selected
	live.set_world_style("factory-country-1",7)
	check("content switch clears derived terrain cache",live._terrain_cache.is_empty() and image_hash(live.terrain_material("soil_side","side",1).albedo_texture)==image_hash(live.material("soil_side").albedo_texture))
	live.set_world_style("factory-country-1",9)
	check("future adopted9 candidate and repeated style cache stable",image_hash(live.terrain_material("soil_side","side",1).albedo_texture)==image_hash(prior_selected.albedo_texture))
	var cached:Material=live.terrain_material("soil_side","side",1);live.set_world_style("factory-country-1",9)
	check("same style/content does not rebuild native material",live.terrain_material("soil_side","side",1)==cached)
	live.set_world_style("factory-country-1")
	check("legacy one-argument style resets content to compatible default",image_hash(live.terrain_material("soil_side","side",1).albedo_texture)==image_hash(live.material("soil_side").albedo_texture))
	check("resource verification has no authority effect",Data.json_equal(initial,world.snapshot()))
	var keys:Array=["5,0,3","6,0,3","7,0,3"];var warm:Array=keys.duplicate()
	for key:String in keys:
		for axis:int in 3:
			for sign:int in [-1,1]:
				var q:Vector3i=Data.coord(key);q[axis]+=sign;var neighbor:String=Data.key(q)
				if not warm.has(neighbor):warm.append(neighbor)
	check("explicit bounded fixture warmup through original residency transaction",set_residency(world,warm,true),warm)
	var baseline:Dictionary=world.snapshot();compare_meshes(world,"actual C8 near-bank saved cells",keys)
	check("actual mesh and material generation never edits cells/plan/IDs",Data.json_equal(baseline,world.snapshot()))
	var cell:=Vector3i(100,2,48);var before:int=world.cell_at(cell.x,cell.y,cell.z)
	var prepared:Dictionary=world.prepare_changes([{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":before,"after":0}],world.get_revision())
	check("isolated supported bank dig uses original voxel transaction",before>0 and prepared.ok and world.commit_prepared(prepared.capability).ok)
	compare_meshes(world,"isolated bank dig",keys)
	prepared=world.prepare_changes([{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":0,"after":before}],world.get_revision())
	check("isolated fill restores original material fact",prepared.ok and world.commit_prepared(prepared.capability).ok)
	check("cold page conversion uses unchanged original storage transaction",cool_pages(world,warm))
	var cold:Dictionary=world.snapshot();var mats:=Materials.new();mats.set_world_style("factory-country-1",8)
	var empty:Dictionary=Mesher.build(world,keys[0]);check("cold derivation remains empty and cannot read or warm cells",empty.groups.is_empty() and Data.json_equal(cold,world.snapshot()))
	check("explicit revisit warms original pages without regeneration",set_residency(world,warm,true))
	compare_meshes(world,"cold/warm edited revisit",keys)
	var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot());var restored:Dictionary=Codec.decode(encoded.envelope)
	var reload:=State.new();check("old codec restores content/plan after material change",encoded.ok and restored.ok and reload.load_snapshot(restored.state).ok and reload.extension("generation:factory-r34")==world.extension("generation:factory-r34"))
	check("restored explicit warmup accepts original chunk facts",set_residency(reload,warm,true))
	compare_meshes(reload,"saved/reloaded edited bank",keys)
	var terrain:=Terrain.new();root.add_child(terrain);terrain.configure({"world":reload})
	check("formal Terrain.configure consumes saved content lock",terrain.materials._content_version==8 and terrain.materials._world_style=="factory-country-1")
	terrain.free()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"observations":observations,"input_sha256":input.sha256_text(),"scope":"Native headless material/mesh/collider contracts from exact saved24 plus explicit isolated edit/residency fixtures; no renderer/OS/FPS/VA qualification. Existing side group includes natural undersides, no additional mesh groups."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
