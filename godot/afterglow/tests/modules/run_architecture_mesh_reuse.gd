extends SceneTree
## Paired old/new rendering-consumer CPU check; no renderer/FPS/VA claim.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const World=preload("res://scripts/world/world_state.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const View=preload("res://scripts/buildings/building_view.gd")
var checks:Array=[]
var samples:Array=[]
var image_hashes:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func material_state(view:Node3D,value:Material)->Dictionary:
	var key:String=""
	for id:String in view.materials:
		if view.materials[id]==value:key=id;break
	if not value is StandardMaterial3D:return {"invalid":true}
	var tex:Texture2D=value.albedo_texture;var image_hash:String=""
	if tex!=null:
		if not image_hashes.has(tex.get_instance_id()):
			var image:=tex.get_image();var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
			image_hashes[tex.get_instance_id()]={"sha":hash.finish().hex_encode(),"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"mips":image.has_mipmaps()}
		image_hash=str(image_hashes[tex.get_instance_id()])
	return {"id":key,"image":image_hash,"color":value.albedo_color,"roughness":value.roughness,"filter":value.texture_filter,"repeat":value.texture_repeat,"cull":value.cull_mode,"transparency":value.transparency,"scissor":value.alpha_scissor_threshold,"active_binding":not key.is_empty() and view.materials[key]==value}
func equal_node(a:Node3D,b:Node3D,old:Node3D,now:Node3D)->bool:
	if not a is MeshInstance3D or not b is MeshInstance3D or a.transform!=b.transform:return false
	if a.mesh.get_surface_count()!=b.mesh.get_surface_count():return false
	for i:int in a.mesh.get_surface_count():
		if a.mesh.surface_get_arrays(i)!=b.mesh.surface_get_arrays(i):return false
		if material_state(old,a.mesh.surface_get_material(i))!=material_state(now,b.mesh.surface_get_material(i)):return false
	return a.get_meta("piece")==b.get_meta("piece")
func nodes(view:Node3D,entities:Array)->Array:
	var result:Array=[]
	for e:Dictionary in entities:result.append(view.entity_object(e))
	return result
func dispose(values:Array)->void:
	for n:Node in values:n.free()
func reverse_keys(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={};var keys:Array=value.keys();keys.reverse()
		for key:Variant in keys:result[key]=reverse_keys(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item:Variant in value:result.append(reverse_keys(item))
		return result
	return value
func run()->void:
	var args:=OS.get_cmdline_user_args();var out:String=args[0];var before:Script=load(args[1])
	var locked:=Contract.fresh(Catalog.profiles(),8,1);var source:=Generator.generate(713,Catalog.profiles(),locked.contract);source.entities={}
	var world:=World.new();var loaded:=world.load_snapshot(source);check("original generated world mounts for consumer",loaded.ok)
	var adapter:=Modules.building_adapter(world,{"actors":[],"stocks":[]})
	for d:Dictionary in Catalog.definitions():
		if d.get("architecture",{}).get("set")!="r34-architecture-30-v1":continue
		for q:int in 4:
			var instance:=Modules.record_for({"id":"B:mesh:"+d.id,"definition_id":d.id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":q})
			var entities:Array=Shape.entities(instance,d)
			var old:Node3D=before.new();old.configure({"service":adapter});var now:=View.new();now.configure({"service":adapter})
			var started:int=Time.get_ticks_usec();var original:Array=nodes(old,entities);var old_first:int=Time.get_ticks_usec()-started
			started=Time.get_ticks_usec();var current:Array=nodes(now,entities);var new_first:int=Time.get_ticks_usec()-started
			var same:bool=original.size()==current.size()
			for i:int in original.size():same=same and equal_node(original[i],current[i],old,now)
			check("first exact arrays/UV/active material/piece "+d.id+" q"+str(q),same)
			var timings:Array=[];var warm_equal:bool=true
			for repetition:int in 3:
				# Alternate order to expose ordering effects, not imply quiet timing.
				var a:Array=[];var b:Array=[];var old_usec:int;var new_usec:int
				if repetition%2==0:
					started=Time.get_ticks_usec();a=nodes(old,entities);old_usec=Time.get_ticks_usec()-started
					started=Time.get_ticks_usec();b=nodes(now,entities);new_usec=Time.get_ticks_usec()-started
				else:
					started=Time.get_ticks_usec();b=nodes(now,entities);new_usec=Time.get_ticks_usec()-started
					started=Time.get_ticks_usec();a=nodes(old,entities);old_usec=Time.get_ticks_usec()-started
				for i:int in a.size():warm_equal=warm_equal and equal_node(a[i],b[i],old,now)
				timings.append({"old_usec":old_usec,"new_usec":new_usec});dispose(a);dispose(b)
			check("warm exact arrays and independent nodes "+d.id+" q"+str(q),warm_equal and now._architecture_mesh_stats.hit>0)
			samples.append({"id":d.id,"q":q,"members":entities.size(),"old_first_usec":old_first,"new_first_usec":new_first,"warm":timings,"cache":now._architecture_mesh_stats.duplicate(true)})
			if d.id=="r34.module.home_small_porch_v1" and q==0:counterexamples(now,old,entities)
			dispose(original);dispose(current);old.free();now.free()
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"samples":samples,"scope":"Paired source CPU and exact shell mesh arrays/material images, all30/four directions. Does not time manual furniture, renderer/FPS, natural construction, PCK/VA or quiet performance."},"\t"))
	quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
func counterexamples(view:Node3D,old:Node3D,entities:Array)->void:
	var e:Dictionary=entities.filter(func(v:Dictionary)->bool:return v.data.module_part.get("architecture_detail",{}).get("kind")=="wall")[0].duplicate(true)
	var a:MeshInstance3D=view.entity_object(e);var b:MeshInstance3D=view.entity_object(e)
	check("same recipe shares only mesh, separate node and metadata",a!=b and a.mesh==b.mesh and a.get_meta("piece")==b.get_meta("piece"))
	check("recursive key ordering does not change identity",view._architecture_key(e.data.module_part)==view._architecture_key(reverse_keys(e.data.module_part)))
	var changed:Dictionary=e.duplicate(true);changed.id+="-changed";changed.position.x+=3;changed.data.owner="different-owner"
	var c:MeshInstance3D=view.entity_object(changed)
	check("translation ownership metadata remain per instance",c.mesh==a.mesh and c.position.x==a.position.x+3 and c.get_meta("piece").data.owner=="different-owner" and a.get_meta("piece").data.owner!=c.get_meta("piece").data.owner)
	var variant:Dictionary=e.duplicate(true);variant.data.module_part.architecture_detail.openings[0].width+=.07
	var d:MeshInstance3D=view.entity_object(variant)
	check("actual opening geometry mutation cannot reuse old mesh",d.mesh!=a.mesh and d.mesh.surface_get_arrays(0)!=a.mesh.surface_get_arrays(0))
	var old_key:String=view._architecture_key(e.data.module_part);var unknown:Dictionary=e.data.module_part.duplicate(true);unknown.architecture_detail.version="future"
	check("unknown or incomplete recipe does not cache",view._architecture_key(unknown).is_empty() and view._architecture_key({"architecture_detail":{"version":View.ArchitectureDetail.VERSION}}).is_empty())
	view.manifest.textures.b_wood_aged.tile_meters+=.13
	var uv:MeshInstance3D=view.entity_object(e);var uv_old:MeshInstance3D
	old.manifest.textures.b_wood_aged.tile_meters+=.13;uv_old=old.entity_object(e)
	check("manifest UV mutation invalidates with exact new arrays",uv.mesh!=a.mesh and equal_node(uv_old,uv,old,view))
	var replacement:StandardMaterial3D=view.materials.b_wood_aged.duplicate();view.materials.b_wood_aged=replacement
	var bound:MeshInstance3D=view.entity_object(e);var has_replacement:bool=false
	for i:int in bound.mesh.get_surface_count():has_replacement=has_replacement or bound.mesh.surface_get_material(i)==replacement
	check("replacement material invalidates and binds current resource",bound.mesh!=uv.mesh and has_replacement)
	# Rendering lifecycle uses original sync/remove, with every member node intact.
	view.sync_entity_object(e.id,e);var sibling:Dictionary=e.duplicate(true);sibling.id+="-sibling";view.sync_entity_object(sibling.id,sibling)
	var sibling_node:Node3D=view.objects[sibling.id];var damaged:Dictionary=e.duplicate(true);damaged.data.test_damage_state="damaged"
	view.sync_entity_object(e.id,damaged)
	check("state replacement cannot mutate sibling node or world metadata",view.objects[sibling.id]==sibling_node and sibling_node.get_meta("piece").data.get("test_damage_state")==null and view.objects[e.id].get_meta("piece").data.test_damage_state=="damaged")
	view.sync_entity_object(e.id,{})
	check("member deletion retains sibling",not view.objects.has(e.id) and view.objects.get(sibling.id)==sibling_node)
	for i:int in View.ARCHITECTURE_MESH_LIMIT+2:
		var unique:Dictionary=e.duplicate(true)
		unique.data.module_part={"size":{"x":1,"y":1,"z":1},"material":"wood_floor","atlas_cell":i,"architecture_detail":{"version":View.ArchitectureDetail.VERSION,"kind":"details","local_size":{"x":1,"y":1,"z":1},"boxes":[{"center":{"x":.5,"y":.5,"z":.5},"size":{"x":1,"y":1,"z":1},"material":"wood_floor"}]}}
		var node:Node3D=view.entity_object(unique);node.free()
	check("cache bounded eviction keeps already-live meshes valid",view._architecture_meshes.size()<=View.ARCHITECTURE_MESH_LIMIT and view._architecture_mesh_stats.evict>0 and a.mesh.get_surface_count()>0)
	check("complete part key includes changing recipes and atlas",old_key!=view._architecture_key(variant.data.module_part))
	view.configure({"service":view.service})
	check("configure/world rebind clears derived resource cache",view._architecture_meshes.is_empty() and view._architecture_mesh_stats.hit==0)
	for node:Node in [a,b,c,d,uv,uv_old,bound]:node.free()
