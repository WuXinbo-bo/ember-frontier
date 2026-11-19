extends "res://tests/modules/factory_boundary_fixture.gd"
## Catalog-assembled geometry reference only: B's exact entities/furniture and
## D's actual idle mechanism. No pretend stock, gameplay route or VA.
const BuildingView=preload("res://scripts/buildings/building_view.gd")
const MachineView=preload("res://scripts/presentation/factory_machine_view.gd")
var texture_ids:Dictionary={}
var texture_count:=0
var out:=""
var retained_materials:Array=[]
func material_pixels(material:StandardMaterial3D)->String:
	if material.albedo_texture==null:return ""
	var key:int=material.albedo_texture.get_instance_id()
	if texture_ids.has(key):return texture_ids[key]
	var image:Image=material.albedo_texture.get_image()
	if image.is_compressed():image.decompress()
	var path:String=out+"/pixels/"+str(texture_count)+".png";texture_count+=1
	image.save_png(path);texture_ids[key]=path
	return path
func surfaces(node:Node,at:Transform3D=Transform3D.IDENTITY)->Array:
	var result:Array=[]
	if node is Node3D and not node.visible:return result
	var transform:Transform3D=at*node.transform if node is Node3D else at
	if node is MeshInstance3D and node.mesh!=null:
		for s:int in node.mesh.get_surface_count():
			var a:Array=node.mesh.surface_get_arrays(s);var points:Array=[];var normals:Array=[];var uv:Array=[]
			for i:int in a[Mesh.ARRAY_VERTEX].size():
				var p:Vector3=transform*a[Mesh.ARRAY_VERTEX][i];var n:Vector3=(transform.basis.inverse().transposed()*a[Mesh.ARRAY_NORMAL][i]).normalized()
				points.append([p.x,p.y,p.z]);normals.append([n.x,n.y,n.z])
				var t:Vector2=a[Mesh.ARRAY_TEX_UV][i] if a[Mesh.ARRAY_TEX_UV]!=null else Vector2.ZERO;uv.append([t.x,t.y])
			var material:StandardMaterial3D=node.get_active_material(s)
			if material==null:continue
			var ix:Array=Array(a[Mesh.ARRAY_INDEX]) if a[Mesh.ARRAY_INDEX]!=null and a[Mesh.ARRAY_INDEX].size()>0 else range(points.size())
			result.append({"part":str(node.name),"vertices":points,"normals":normals,"uv":uv,"indices":ix,"texture":material_pixels(material),"repeat":material.texture_repeat,"double_sided":material.cull_mode==BaseMaterial3D.CULL_DISABLED,"color":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a]})
	for child:Node in node.get_children():result.append_array(surfaces(child,transform))
	return result
func run()->void:
	out=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(out+"/pixels")
	var initial:Dictionary=opening();var geometry:Array=[]
	if initial.is_empty():finish();return
	var ids:Array=["r34.module.fuel_woodshop","r34.module.woodshop_long_v2","r34.module.warehouse_long_v2","r34.module.warehouse_court_v2","r34.module.repair_shed_v2","r34.module.home_court_v2","r34.module.home_roadside_v2","r34.module.supply_roadside_v2"]
	for id:String in ids:
		var d:Dictionary=Modules.definition(id)
		var v:Dictionary=Modules.record_for({"id":"D:cpu:"+id,"definition_id":id,"region":"RH-HOME","position":{"x":0.0,"y":0.0,"z":0.0},"quarter_turn":0,"player_built":false})
		var capture:Dictionary=initial.duplicate(true);capture.world.extensions[Modules.KEY].instances=[v]
		var world:=World.new();var loaded:Dictionary=world.load_snapshot(capture.world)
		check("catalog geometry context loads "+id,loaded.ok)
		if not loaded.ok:continue
		var service:RefCounted=Modules.building_adapter(world,capture.facts)
		var view:Node3D=BuildingView.new();root.add_child(view);view.set_process(false);view.service=service
		view.manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
		var assembly:=Node3D.new();root.add_child(assembly)
		var entities:Array=Shape.entities(v,d)
		for e:Dictionary in entities:
			var piece:Node3D=view.entity_object(e)
			if piece!=null:assembly.add_child(piece)
		if d.shape=="manual":
			var bench:Dictionary=service.make_instance("workbench",str(v.id)+":workbench",Shape.at(v,Shape.Families.bench_offset(d)),0,v.owner)
			var furniture:Node3D=view.furniture(bench,service.geometry.definition(bench))
			if furniture!=null:assembly.add_child(furniture)
		if d.shape=="woodshop":
			var mechanism:Node3D=MachineView.new();assembly.add_child(mechanism);mechanism.position=Vector3(0,1.1,-2.25)
			mechanism.update({"kind":"reciprocating_saw","progress_seconds":0.0,"duration_seconds":1.0,"effective_work":0.0,"active":false,"phase":"idle","paused_reason":""})
		var actual:Array=surfaces(assembly)
		check("actual consumer has nonempty geometry "+id,not actual.is_empty())
		geometry.append({"id":id,"name":d.name,"geometry_version":d.geometry_version,"definition":d,"catalog_instance":v,"entity_count":entities.size(),"surfaces":actual,"scope":"catalog-built reference; empty buffers, idle mechanical pose; not a player-built or operating instance; textures extracted from immutable22 imported resources"})
		BuildingView.retain_object_materials(assembly,retained_materials)
		assembly.free();view.free()
	FileAccess.open(out+"/mesh.json",FileAccess.WRITE).store_string(JSON.stringify(geometry))
	finish()
