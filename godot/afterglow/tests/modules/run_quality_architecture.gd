extends SceneTree
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Quality=preload("res://scripts/modules/module_quality_geometry.gd")
const Roof=preload("res://scripts/buildings/module_roof_mesh.gd")
const Facade=preload("res://scripts/buildings/module_quality_facade.gd")
const MeshBuilder=preload("res://scripts/buildings/building_mesh.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const World=preload("res://scripts/world/world_state.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Navigation=preload("res://scripts/buildings/building_navigation.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const LegacyFacade=preload("res://scripts/buildings/module_facade_detail.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var observations:Array=[]
var out:String
class SkinView extends Node3D:
	var manifest:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();out=args[0]
	var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1]+"/data/modules/catalog_v1.json"))
	var original:Script=load(args[1]+"/scripts/modules/module_geometry.gd")
	var surfaces:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json")).textures
	check("catalog validates additive definitions",Catalog.validate().ok)
	check("default generation keeps original twelve profiles",Catalog.profiles().size()==12 and Catalog.profiles(true).size()==18)
	check("public generation owner preserves default and explicit opt-in",Data.json_equal(Modules.generation_profiles(),Catalog.profiles()) and Data.json_equal(Modules.generation_profiles(true),Catalog.profiles(true)))
	var old_skin:Script=load(args[1]+"/scripts/buildings/module_facade_detail.gd")
	var skin_view:=SkinView.new();skin_view.manifest={"textures":surfaces}
	for material:String in ["b_wood_aged","old_brick","painted_metal"]:
		var old_builder:=MeshBuilder.new();var new_builder:=MeshBuilder.new();var sz:=Vector3(0.8,1.1,0.1)
		old_skin._box(old_builder,Transform3D.IDENTITY,Vector3.ZERO,sz,material)
		LegacyFacade._box(skin_view,new_builder,Transform3D.IDENTITY,Vector3.ZERO,sz,material)
		var old_group:Dictionary=old_builder.groups[material];var new_group:Dictionary=new_builder.groups[material]
		check("existing wall skin geometry exact and UV follows actual metres "+material,old_group.v==new_group.v and old_group.n==new_group.n and old_group.i==new_group.i and is_equal_approx(new_group.uv[1].x,float(sz.x)/float(surfaces[material].tile_meters)))
	skin_view.free()
	var current_ids:=Catalog.build_definition_ids()
	check("build menu explicit ten choices no old family duplicates",current_ids.size()==10 and current_ids.all(func(id:String)->bool:return Quality.IDS.has(id) or Catalog.definition(id).shape in ["manual","supply"]))
	var legacy_ok:=true
	for d:Dictionary in before.definitions:
		var next:Dictionary=Catalog.definition(d.id)
		legacy_ok=legacy_ok and Data.json_equal(d,next) and Data.json_equal(original.parts(d),Shape.parts(next))
		var instance:=Modules.record_for({"id":"quality:legacy:"+d.id,"definition_id":d.id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":3})
		check("legacy member DTO exact "+d.id,Data.json_equal(original.entities(instance,d),Shape.entities(instance,next)))
	check("old definitions and parts remain strictly identical",legacy_ok)
	var locked:=Contract.fresh(Catalog.profiles(),8,1)
	check("existing content8 lock resolves against enlarged catalog",locked.ok and Contract.resolve(locked.contract,Catalog.profiles(true)).ok)
	var source:=Generator.generate(713,Catalog.profiles(),locked.contract)
	# Explicit isolated flat patch for exhaustive structure/body/route checks.
	# This is neither a natural placement nor economic/playtest qualification.
	for key:String in source.chunks:
		var coord:Vector3i=Data.coord(key)
		if coord.x not in [2,3,4,5] or coord.z not in [2,3,4,5]:continue
		var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if coord.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	var world:=World.new();check("isolated original world floor fixture validates",world.load_snapshot(source).ok)
	var building:=Modules.building_adapter(world,{"actors":[],"stocks":[]})
	var silhouettes:Dictionary={}
	for id:String in Quality.IDS:
		# This suite retains the original six-family scope; repair has its own suite.
		if id=="r34.module.repair_shed_v3":continue
		var d:=Catalog.definition(id);var parent:=Catalog.definition(Quality.IDS[id]);var copy:Dictionary=d.duplicate(true)
		for key:String in ["id","name","geometry_version","design_id","dimensions_status","geometry_family_version","quality_parent_definition_id"]:copy[key]=parent.get(key)
		for key:String in ["geometry_family_version","quality_parent_definition_id"]:copy.erase(key)
		check("exact inherited gameplay footprint ports "+id,Data.json_equal(copy,parent))
		var parts:=Shape.parts(d);var extent:=G.aabb(d.footprint);var valid:=true;var ids:Dictionary={};var roofs:=0;var vertices:=0;var tris:=0;var groups:Dictionary={}
		var signature:Array=[]
		for part:Dictionary in parts:
			var b:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size));ids[part.id]=true
			valid=valid and extent.grow(0.001).encloses(b) and surfaces.has(part.material)
			if part.has("roof_mesh"):
				roofs+=1
				var builder:=MeshBuilder.new();var roofpart:Dictionary=part.duplicate(true)
				check("actual sloped roof consumes recipe "+id+part.id,Roof.add(builder,roofpart,surfaces))
				var geometric:=true;var slope:=false;var miny:=INF;var maxy:=-INF
				for m:String in builder.groups:
					groups[m]=true;var g:Dictionary=builder.groups[m]
					vertices+=g.v.size();tris+=g.i.size()/3
					for n:int in g.v.size():
						geometric=geometric and g.v[n].is_finite() and g.n[n].is_finite() and g.uv[n].is_finite() and AABB(Vector3.ZERO,G.point(part.size)).grow(0.001).has_point(g.v[n])
						slope=slope or (absf(g.n[n].y)>0.01 and absf(g.n[n].y)<0.99)
						miny=minf(miny,g.v[n].y);maxy=maxf(maxy,g.v[n].y)
				check("roof real slopes finite UV within proxy "+id+part.id,geometric and slope and maxy-miny>0.4)
				var roofdata:Dictionary=builder.groups[part.material]
				var real_slant:float=Vector2(G.point(part.size).z/2,float(part.roof_mesh.rise)).length()
				check("roof UV uses slant metres "+id+part.id,is_equal_approx(absf(roofdata.uv[0].y-roofdata.uv[2].y),real_slant/float(surfaces[part.material].tile_meters)))
			if part.has("quality_facade"):
				var fb:=MeshBuilder.new();check("closed wall skin uses existing material recipe "+id+part.id,Facade.add(fb,part,surfaces))
				for m:String in fb.groups:groups[m]=true;vertices+=fb.groups[m].v.size();tris+=fb.groups[m].i.size()/3
			signature.append([part.center,part.size,part.material,part.get("roof_mesh",{})])
		check("complete unique contained structural parts "+id,valid and ids.size()==parts.size() and roofs>=2,{"parts":parts.size(),"roofs":roofs})
		silhouettes[id]=JSON.stringify(signature).sha256_text()
		var costs:Dictionary={"id":id,"geometry_version":d.geometry_version,"parent":parent.id,"parts":parts.size(),"roofs":roofs,"derived_vertices":vertices,"derived_triangles":tris,"material_groups":groups.keys(),"rotations":[]}
		for turn:int in 4:
			var instance:=Modules.record_for({"id":"quality:sample:"+str(turn)+id,"definition_id":id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":turn})
			var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
			Modules.append_instance(world,building,instance,d,changes,structures)
			var prepared:Dictionary=world.prepare_changes(changes,world.get_revision())
			var safe:Dictionary=building.validate_world_draft(prepared.view,{"actors":[],"stocks":[]},changes) if prepared.ok else prepared
			check("real World CAS and structural safety "+id+" q"+str(turn),safe.ok,safe.get("reason"))
			if not safe.ok:continue
			var query:=Space.new();query.configure(prepared.view,structures,building.geometry,func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
			var ports:=Shape.ports(instance,d);var clear:=true;var rays:=true;var mesh_ok:=true
			for port:Dictionary in ports:
				for at:Dictionary in port.use_points:clear=clear and not query.standing_point(at).is_empty()
				var end:Dictionary=port.location.duplicate(true);end.x+=float(port.normal.x)*1.0;end.z+=float(port.normal.z)*1.0
				rays=rays and query.line_clear(Modules.offset(port.location,Vector3(0,1.3,0)),Modules.offset(end,Vector3(0,1.3,0)))
			check("all use points retain body and exterior sight "+id+" q"+str(turn),clear and rays)
			var routes_ok:=true;var route_records:Array=[]
			for port:Dictionary in ports:
				var outward:Vector3=G.point(port.normal)
				var arrival:=Modules.offset(port.location,outward*1.0)
				var route:=Navigation.new().plan(query,"player",arrival,port.location)
				routes_ok=routes_ok and route.ok
				route_records.append({"port":port.id,"ok":route.ok,"steps":route.get("steps",[]).size()})
			check("real body navigation reaches every exterior service "+id+" q"+str(turn),routes_ok,route_records)
			var yard:Vector3=Vector3(0.5,0,-1.1) if d.shape=="woodshop" else Vector3(0.8,0,-2.3) if id.ends_with("home_court_v3") else Vector3(-0.66,0,-1.54) if d.shape=="home" else Vector3(-0.64,0,0) if id.ends_with("warehouse_long_v3") else Vector3(0.8,0,-1.5)
			check("working or living apron has real full-height standing room "+id+" q"+str(turn),not query.standing_point(Shape.at(instance,yard)).is_empty())
			var closed:bool=not query.line_clear(Shape.at(instance,Vector3(0,1.3,-3.95)),Shape.at(instance,Vector3(0,1.3,3.95)))
			check("real enclosing room remains opaque "+id+" q"+str(turn),closed if not id.ends_with("warehouse_long_v3") else not query.line_clear(Shape.at(instance,Vector3(2.18,1.3,-3.0)),Shape.at(instance,Vector3(2.18,1.3,3.0))))
			if d.shape=="woodshop":
				var drive:Dictionary={};var overlaps:Array=[]
				for part:Dictionary in parts:
					if part.id=="fixed-power":drive=part
				var drive_box:=AABB(G.point(drive.center)-G.point(drive.size)/2,G.point(drive.size))
				for part:Dictionary in parts:
					if ":rear-" in str(part.id) or ":drive-header" in str(part.id):
						var bp:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))
						if drive_box.intersects(bp):overlaps.append(part.id)
				check("drive recess is physical and never a human doorway "+id+" q"+str(turn),overlaps.is_empty() and query.standing_point(Shape.at(instance,Vector3(1.65,0,1.85))).is_empty(),overlaps)
			for entity:Dictionary in Shape.entities(instance,d):
				if not entity.data.module_part.has("roof_mesh"):continue
				var rb:=MeshBuilder.new();mesh_ok=mesh_ok and Roof.add(rb,entity.data.module_part,surfaces)
				for m:String in rb.groups:
					for point:Vector3 in rb.groups[m].v:mesh_ok=mesh_ok and G.aabb(entity.bounds).grow(0.001).has_point(point+G.point(entity.position))
			check("four-way roof mesh follows exact member world bounds "+id+" q"+str(turn),mesh_ok)
			var adapter:=Modules.building_adapter(prepared.view,{"actors":[],"stocks":[]})
			var view:=View.new();var start:int=Time.get_ticks_usec()
			view.configure({"service":adapter})
			var create_usec:int=Time.get_ticks_usec()-start;var roof_nodes:=0;var actual_meshes:=0;var actual_surfaces:=0
			for member:Dictionary in instance.members:
				if view.objects.has(member.id):
					var node:Node3D=view.objects[member.id]
					if node is MeshInstance3D:
						actual_meshes+=1;actual_surfaces+=node.mesh.get_surface_count()
						if prepared.view.entity(member.id).data.module_part.has("roof_mesh"):
							for si:int in node.mesh.get_surface_count():
								var normals:PackedVector3Array=node.mesh.surface_get_arrays(si)[Mesh.ARRAY_NORMAL]
								var has_slope:=false
								for normal:Vector3 in normals:has_slope=has_slope or (absf(normal.y)>0.01 and absf(normal.y)<0.99)
								if has_slope:roof_nodes+=1;break
			check("original configure consumes all members and sloped meshes "+id+" q"+str(turn),actual_meshes==parts.size() and roof_nodes==roofs,{"meshes":actual_meshes,"surfaces":actual_surfaces,"roof_nodes":roof_nodes})
			var identities:Dictionary={}
			for key:Variant in view.objects:identities[key]=view.objects[key].get_instance_id()
			view._changed({"clock":1.0,"revision":1})
			check("pure clock does not recreate decoration or roof "+id+" q"+str(turn),identities.keys()==view.objects.keys() and identities.keys().all(func(key:Variant)->bool:return identities[key]==view.objects[key].get_instance_id()))
			costs.rotations.append({"quarter_turn":turn,"entities":changes.size(),"save_json_bytes":JSON.stringify(changes).to_utf8_buffer().size(),"create_view_usec":create_usec,"actual_meshes":actual_meshes,"actual_surfaces":actual_surfaces})
			view.free()
			world.discard_prepared(prepared.capability)
		observations.append(costs)
	var distinct:Dictionary={};for value:Variant in silhouettes.values():distinct[value]=true
	check("six distinct multi-volume structural silhouettes",distinct.size()==6)
	var bad:=MeshBuilder.new();check("unknown roof falls back without adding mesh",not Roof.add(bad,{"roof_mesh":{"version":"future"}},surfaces) and bad.groups.is_empty())
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	var result:Dictionary={"ok":ok,"checks":checks,"observations":observations,"scope":"Current B implementation; explicit flat isolated structure fixture, NOT natural placement/economy, normal-camera VA, renderer/FPS or package qualification."}
	var f:=FileAccess.open(out+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("QUALITY "+str(checks.size())+" "+str(ok));quit(0 if ok else 1)
