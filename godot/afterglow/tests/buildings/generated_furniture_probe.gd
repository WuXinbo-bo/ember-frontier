extends "res://tests/buildings/family_generation_suite.gd"
## Read-only sixth-app save -> actual assembler and B renderer inspection.
## Explicit supported observation fixtures are NOT a player route/VA pass.
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
var rows:Array=[]

func mesh_rows(node:Node,at:Transform3D=Transform3D.IDENTITY)->Array:
	var result:Array=[]
	var transform:Transform3D=at*node.transform if node is Node3D else at
	if node is MeshInstance3D and node.mesh!=null:
		var surfaces:Array=[]
		for i in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(i)
			var arrays:Array=node.mesh.surface_get_arrays(i)
			surfaces.append({"surface":i,"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"uv_count":arrays[Mesh.ARRAY_TEX_UV].size() if arrays[Mesh.ARRAY_TEX_UV]!=null else 0,"material":material.resource_name if material!=null else null,"class":material.get_class() if material!=null else null,"texture":material.albedo_texture.resource_path if material is StandardMaterial3D and material.albedo_texture!=null else null,"color":str(material.albedo_color) if material is StandardMaterial3D else null})
		result.append({"name":str(node.name),"aabb":str(transform*node.mesh.get_aabb()),"surfaces":surfaces})
	for child:Node in node.get_children():result.append_array(mesh_rows(child,transform))
	return result

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var original:=FileAccess.get_file_as_string(args[0])
	var decoded:=Store.decode(original)
	expect("readonly exact sixth-app slot passes actual native integrity",decoded.ok,decoded.get("reason"))
	if not decoded.ok:finish(Time.get_ticks_msec());return
	var host:=Client.new();var assembled:Dictionary=host._assemble(decoded.capture)
	expect("sixth-app original facts and world assemble without generation",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(Time.get_ticks_msec());return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	var before:=runtime.capture_checkpoint()
	var view:Node3D=building.create_view({"runtime":runtime})
	var policy:=Policy.new();view.set_view_policy(policy)
	var home:="RH-HOME:home"
	var expected:Array=[home+":storage",home+":kitchen",home+":table",home+":chair",home+":sleeping-place"]
	for id:String in expected:
		var entity:Dictionary=world.entity(id)
		var node:Node3D=view.objects.get(id)
		rows.append({"kind":"actual_object","id":id,"entity":entity,"model_instantiated":node!=null,"meshes":mesh_rows(node) if node!=null else []})
	var query:RefCounted=building.current_space()
	var plan:Dictionary=world.extension("generation:RH-HOME")
	var parcel:Dictionary=plan.parcels.filter(func(p:Dictionary)->bool:return p.id==home)[0]
	for station:Array in [[11,0,8],[11,0,3],[5,0,9],[5,0,3]]:
		var position:Vector3=Geometry.point(parcel.origin)+Geometry.rotate(Vector3(station[0],station[1],station[2]),int(parcel.quarter_turn))
		var feet:Dictionary=query.standing_point({"x":position.x,"y":position.y,"z":position.z,"regionId":"RH-HOME","buildingId":home,"storeyId":home+":ground"})
		if feet.is_empty():rows.append({"kind":"station_rejected","local":station});continue
		var actor:Dictionary=Geometry.actor_at(runtime.actor("player"),feet)
		policy.sample(feet,Time.get_ticks_msec()+200)
		var seen:Array=[]
		for id:String in expected:
			var node:Node3D=view.objects.get(id)
			if node==null:continue
			var entity:Dictionary=node.get_meta("piece")
			var sight:bool=view.visible_room(entity,actor)
			seen.append({"id":id,"same_floor":Geometry.location(entity).storeyId==feet.storeyId,"los":sight,"policy":policy.base_visible(entity,"object"),"ray_target":Geometry.location(entity)})
		rows.append({"kind":"supported_station","local":station,"feet":feet,"objects":seen,"policy":policy.statistics()})
	expect("derived object/model/LOS diagnosis preserves complete captured authority",preload("res://scripts/world/world_data.gd").json_equal(before,runtime.capture_checkpoint()))
	print(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"rows":rows,"source_sha256":original.sha256_text(),"scope":"exact sixth-app slot read-only material/mesh/LOS probe; no OS app or visual acceptance"}))
	view.free();host.free();quit(1 if not failures.is_empty() else 0)
