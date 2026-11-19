extends SceneTree
## Read-only actual24 CPU attribution and exact derived geometry/material state.
## Headless only; no renderer/physics readiness, FPS, OS or VA qualification.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
class MeteredView extends "res://scripts/buildings/building_view.gd":
	var costs:Dictionary={}
	var calls:Dictionary={}
	var cold_textures:Dictionary={}
	func record(key:String,started:int)->void:
		costs[key]=int(costs.get(key,0))+Time.get_ticks_usec()-started
		calls[key]=int(calls.get(key,0))+1
	func material(id:String)->StandardMaterial3D:
		var started:int=Time.get_ticks_usec();var result:StandardMaterial3D=super.material(id)
		record("material",started);return result
	func texture(path:String,mipmaps:bool=false)->Texture2D:
		var started:int=Time.get_ticks_usec();var result:Texture2D=super.texture(path,mipmaps)
		cold_textures[path]=int(cold_textures.get(path,0))+Time.get_ticks_usec()-started
		record("texture",started);return result
	func model(id:String)->Node3D:
		var started:int=Time.get_ticks_usec();var result:Node3D=super.model(id)
		record("model",started);return result
	func entity_object(entity:Dictionary)->Node3D:
		var started:int=Time.get_ticks_usec();var result:Node3D=super.entity_object(entity)
		record("entity_object",started);return result
	func rebuild()->void:
		var started:int=Time.get_ticks_usec();super.rebuild();record("rebuild",started)
	func update_contents()->void:
		var started:int=Time.get_ticks_usec();super.update_contents();record("contents",started)
	func update_state_details()->void:
		var started:int=Time.get_ticks_usec();super.update_state_details();record("state_details",started)
	func update_visibility()->void:
		var started:int=Time.get_ticks_usec();super.update_visibility();record("visibility",started)
var checks:Array=[]
var image_hashes:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"label":label,"ok":ok,"detail":detail})
func digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func material_state(m:Material)->Variant:
	if m==null:return null
	if not m is StandardMaterial3D:return {"class":m.get_class(),"path":m.resource_path}
	var t:Texture2D=m.albedo_texture;var tex:Variant=null
	if t!=null:
		var key:int=t.get_instance_id()
		if not image_hashes.has(key):
			var image:Image=t.get_image()
			image_hashes[key]={"width":t.get_width(),"height":t.get_height(),"image":null if image==null else {"format":image.get_format(),"mipmaps":image.has_mipmaps(),"data_sha256":digest(image.get_data())}}
		tex=image_hashes[key]
	return {"albedo":m.albedo_color,"texture":tex,"filter":m.texture_filter,"repeat":m.texture_repeat,"roughness":m.roughness,"cull":m.cull_mode,"transparency":m.transparency,"alpha_scissor":m.alpha_scissor_threshold,"shading":m.shading_mode}
func node_state(n:Node3D)->Dictionary:
	var r:Dictionary={"transform":n.transform,"visible":n.visible,"piece":n.get_meta("piece",{}),"children":[]}
	for key:String in ["role","piece_ids","state","state_material","state_batch","wall_attached","facade_skin_version"]:
		if n.has_meta(key):r[key]=n.get_meta(key)
	if n is MeshInstance3D and n.mesh!=null:
		r.surfaces=[];r.shadow=n.cast_shadow
		for i:int in n.mesh.get_surface_count():r.surfaces.append({"geometry_sha256":digest(var_to_bytes(n.mesh.surface_get_arrays(i))),"material":material_state(n.get_active_material(i))})
	for child:Node in n.get_children():
		if child is Node3D:r.children.append(node_state(child))
	return r
func view_state(view:Node3D)->Dictionary:
	var r:Dictionary={"statistics":view.residency_statistics(),"static":{},"objects":{},"doors":{},"contents":{},"state":[]}
	for key:String in view.static_nodes:r.static[key]=node_state(view.static_nodes[key])
	for key:String in view.objects:r.objects[key]=node_state(view.objects[key])
	for key:String in view.doors:r.doors[key]=node_state(view.doors[key].node)
	for key:String in view.content_nodes:r.contents[key]=node_state(view.content_nodes[key])
	if view.has_node("StateDetails"):
		for child:Node3D in view.get_node("StateDetails").get_children():r.state.append(node_state(child))
	return r
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size() not in [2,3]:quit(2);return
	var output:String=args[0];var input:String=args[1];DirAccess.make_dir_recursive_absolute(output)
	var input_sha:String=FileAccess.get_sha256(input)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	check("exact 24-region input decodes",decoded.get("ok",false) and input_sha=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48")
	if not decoded.get("ok",false):quit(1);return
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("formal Native fully assembles original input",built.get("ok",false))
	if not built.get("ok",false):quit(1);return
	var runtime:RefCounted=built.runtime;var service:RefCounted=built.services.buildings
	var before:Dictionary=runtime.capture_checkpoint();var early:MeteredView;var early_usec:int=0
	if args.size()==3:
		early=MeteredView.new();var t:int=Time.get_ticks_usec();early.configure({"service":service,"runtime":runtime});early_usec=Time.get_ticks_usec()-t
	var started:int=Time.get_ticks_usec()
	var actual:Node3D=service.create_view({"runtime":runtime});var actual_usec:int=Time.get_ticks_usec()-started
	var actual_state:Dictionary=view_state(actual)
	check("all formal view construction is synchronous before return",actual!=null and actual_state.statistics.objects>0)
	var repeats:Array=[]
	for i:int in 2:
		started=Time.get_ticks_usec();var next:Node3D=service.create_view({"runtime":runtime});repeats.append(Time.get_ticks_usec()-started)
		check("repeated formal create_view exact geometry material state "+str(i),Data.json_equal(actual_state,view_state(next)))
		next.free()
	var metered:=MeteredView.new();started=Time.get_ticks_usec();metered.configure({"service":service,"runtime":runtime});var metered_usec:int=Time.get_ticks_usec()-started
	check("instrumentation retains exact formal view output",Data.json_equal(actual_state,view_state(metered)))
	var image:=JSON.stringify(actual_state,"",true,true)
	FileAccess.open(output+"/view-state.json",FileAccess.WRITE).store_string(image+"\n")
	check("views do not change world inventory clock actors receipts or metadata",Data.json_equal(before,runtime.capture_checkpoint()))
	check("read-only source remains byte-identical",FileAccess.get_sha256(input)==input_sha)
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"input_sha256":input_sha,"regions":built.world.regions().size(),"chunks":built.world.chunk_keys().size(),"first_create_view_usec":actual_usec,"repeat_create_view_usec":repeats,"metered_configure_usec":metered_usec,"nested_costs_usec":metered.costs,"nested_calls":metered.calls,"material_ids":metered.materials.keys(),"texture_count":metered.texture_cache.size(),"view_state_sha256":image.sha256_text(),"statistics":actual_state.statistics,"scope":"Actual same24 formal BuildingService.create_view synchronous CPU; metered nested calls overlap, not additive; resource warm repeats disclosed. Exact rendered node/mesh arrays/used material pixels/state, not GPU/frame/readiness/OS/VA."}
	if early!=null:
		report.profile_first={"configure_usec":early_usec,"nested_costs_usec":early.costs,"nested_calls":early.calls,"texture_costs_usec":early.cold_textures}
		report.scope+=" Explicit profile-first mode warms resources before all formal create_view times."
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	if early!=null:early.free()
	metered.free();actual.free();runtime.retire()
	print(JSON.stringify(report,"",false,true));quit(1 if report.failed else 0)
