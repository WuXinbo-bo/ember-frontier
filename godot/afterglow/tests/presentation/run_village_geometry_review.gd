extends SceneTree
## Static catalog geometry review only. Does not simulate construction, stock,
## machine operation, camera cutaway, NPC navigation or the generated village.
## Run graphically; the integration owner exclusively owns graphical previews.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Restore=preload("res://scripts/modules/module_restoration.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const BuildingView=preload("res://scripts/buildings/building_view.gd")
const Lighting=preload("res://scripts/presentation/scene_lighting.gd")

class ReviewWorld:
	extends RefCounted
	var instance:Dictionary={}
	func region_is_resident(_id:String)->bool:return true
	func extension(key:String)->Variant:
		return {"instances":[instance.duplicate(true)]} if key=="r34:modules" else {}

class ReviewService:
	extends RefCounted
	var context:Dictionary={}

var output:String=""
var reports:Array=[]
var failures:Array=[]
var retained_materials:Array=[]
var stage:Node3D
var assembly:Node3D
var camera:Camera3D
var view:Node3D
var heading:Label
var footnote:Label

func _initialize()->void:call_deferred("run")

func cases()->Array:
	var result:Array=[]
	for family:String in ["home","warehouse"]:
		for state:String in ["damaged","repaired","expanded"]:
			result.append({"key":family+"_"+state,"id":"r35.module.village_"+family+("_expanded" if state=="expanded" else ""),"state":state,"style":false})
	result.append({"key":"village_workshop","id":"r35.module.village_workshop","state":"operational","style":false})
	result.append({"key":"village_sawmill","id":"r35.module.village_sawmill","state":"operational","style":false})
	for family:String in ["sawmill","warehouse"]:
		for tier:String in ["low","mid","high"]:
			result.append({"key":family+"_"+tier+"_content13","id":"r34.module."+family+"_"+tier+"_v1.mechanism-v2","state":"operational","style":true})
	return result

func run()->void:
	var args:=OS.get_cmdline_user_args()
	output=ProjectSettings.globalize_path(args[0] if not args.is_empty() else "user://village-geometry-review")
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create review directory: "+output);quit(1);return
	if DisplayServer.get_name()=="headless":
		push_error("This screenshot runner requires a graphical display; --headless is only suitable with --check-only.");quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	stage=Node3D.new();stage.name="StaticCatalogReview";root.add_child(stage)
	Lighting.mount(stage)
	# Neutral display ground only; never part of the reviewed building entities.
	var ground:=MeshInstance3D.new();ground.name="ReviewGround"
	var plane:=PlaneMesh.new();plane.size=Vector2(40,40);ground.mesh=plane;ground.position.y=-.025
	var ground_material:=StandardMaterial3D.new();ground_material.albedo_color=Color(.31,.33,.29);ground_material.roughness=1.0
	ground.material_override=ground_material;stage.add_child(ground)
	camera=Camera3D.new();camera.name="ReviewCamera";camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.05;camera.far=200;stage.add_child(camera);camera.current=true
	var overlay:=CanvasLayer.new();root.add_child(overlay)
	heading=Label.new();heading.position=Vector2(28,16);heading.add_theme_font_size_override("font_size",23);overlay.add_child(heading)
	footnote=Label.new();footnote.position=Vector2(28,752);footnote.add_theme_font_size_override("font_size",16)
	footnote.text="静态目录实体 / 原材质与场景光照 · 空库存 · 无 NPC、运行状态、游戏地图或交互验收";overlay.add_child(footnote)
	var index:int=0
	for row:Dictionary in cases():
		index+=1
		await capture_case(row,index)
	var result:Dictionary={"scope":"14 static catalog fixtures: actual module_geometry.entities and building_view.entity_object; original furniture consumer for manual workbenches, production scene_lighting/materials. Neutral review ground only. Explicit read-only resident-world fixture. No generated world, NPC/route, natural economy, paid construction, operating machine, cutaway, performance or packaged-build acceptance.","size":[1280,800],"cases":reports,"failures":failures}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	if file==null:push_error("Cannot write review manifest");quit(1);return
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("VILLAGE_GEOMETRY_REVIEW ",JSON.stringify({"cases":reports.size(),"failures":failures,"output":output}))
	quit(0 if failures.is_empty() and reports.size()==14 else 1)

func capture_case(row:Dictionary,index:int)->void:
	var d:Dictionary=Catalog.definition(row.id)
	if d.is_empty():failures.append("Missing definition: "+str(row.id));return
	var instance:Dictionary=Modules.record_for({"id":"review:"+str(row.key),"definition_id":row.id,"region":"RH-HOME","position":{"x":0.0,"y":0.0,"z":0.0},"quarter_turn":0,"player_built":false})
	if row.style:instance.config.village_style_v1=1
	if d.has("village_restoration"):
		instance.restoration=Restore.village_initial(d)
		instance.restoration.completed=row.state!="damaged"
		instance.status="damaged" if row.state=="damaged" else "operational"
	var world:=ReviewWorld.new();world.instance=instance.duplicate(true)
	var service:=ReviewService.new();service.context={"world":world}
	view=BuildingView.new();view.name="ActualBuildingConsumer";view.service=service
	view.manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	view.set_process(false);stage.add_child(view)
	assembly=Node3D.new();assembly.name=str(row.key);stage.add_child(assembly)
	var entities:Array=Shape.entities(instance,d);var rendered:int=0
	for entity:Dictionary in entities:
		var piece:Node3D=view.entity_object(entity)
		if piece==null:failures.append("No render node: "+str(entity.id));continue
		assembly.add_child(piece);rendered+=1
	# This matches module_service.append_instance's real manual workbench.
	var furniture_count:int=0
	if d.shape=="manual":
		var building:=Building.new()
		building.geometry.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
		var bench:Dictionary=building.make_instance("workbench",str(instance.id)+":workbench",Shape.at(instance,Shape.Families.bench_offset(d)),int(instance.quarter_turn),instance.owner)
		var furniture:Node3D=view.furniture(bench,building.geometry.definition(bench))
		if furniture==null:failures.append("Missing actual workbench: "+str(row.key))
		else:assembly.add_child(furniture);furniture_count=1
	var bounds:AABB=view.model_bounds(assembly)
	if not bounds.has_volume():failures.append("Empty rendered bounds: "+str(row.key))
	var target:=bounds.get_center()
	camera.position=target+Vector3(1.05,.85,-1.3).normalized()*30.0;camera.look_at(target,Vector3.UP)
	var minimum:=Vector2(INF,INF);var maximum:=Vector2(-INF,-INF)
	for corner:int in 8:
		var point:Vector3=camera.global_transform.affine_inverse()*bounds.get_endpoint(corner)
		minimum=minimum.min(Vector2(point.x,point.y));maximum=maximum.max(Vector2(point.x,point.y))
	var span:Vector2=maximum-minimum
	camera.size=maxf(span.y,span.x/(1280.0/800.0))*1.42
	heading.text="%02d / 14   %s   [%s]"%[index,str(d.name),str(row.state)]
	for frame:int in 5:await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image();var path:String=output+"/%02d_%s.png"%[index,str(row.key)]
	var error:int=image.save_png(path)
	if error!=OK:failures.append("PNG write failed: "+path+" code="+str(error))
	reports.append({"key":row.key,"definition_id":d.id,"geometry_version":d.geometry_version,"state":row.state,"config":instance.config,"entity_count":entities.size(),"rendered_entity_count":rendered,"furniture_count":furniture_count,"image":path,"image_error":error,"bounds":Shape.G.json_box(bounds),"camera_position":Shape.G.json_point(camera.position),"camera_size":camera.size})
	BuildingView.retain_object_materials(assembly,retained_materials)
	assembly.free();view.free()
	await process_frame
