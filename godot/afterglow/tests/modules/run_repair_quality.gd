extends SceneTree
## Registered repair-v3 geometry and pinned profile compatibility. Explicit flat laboratory.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const OldShape=preload("res://scripts/modules/module_geometry.gd")
const StockLayout=preload("res://scripts/modules/module_stock_layout.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const World=preload("res://scripts/world/world_state.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Navigation=preload("res://scripts/buildings/building_navigation.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const QualityFamily=preload("res://scripts/world/factory_quality_family.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var observations:Array=[]
var meshes:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func profile(d:Dictionary)->Dictionary:
	var p:Dictionary={}
	for key:String in ["id","version","geometry_version","category","generation_role","footprint","foundation","ports","allowed_quarter_turns","visual_family","design_id","story_front_point"]:
		if not d.has(key):continue
		p[key]=d[key].duplicate(true) if d[key] is Dictionary or d[key] is Array else d[key]
	for port:Dictionary in d.ports:
		var x:float=port.position[0];var z:float=port.position[2]
		p.foundation.pad_rectangles.append([x-1.0,z-1.0,x+1.0,z+1.0])
	return p
func run()->void:
	var args:=OS.get_cmdline_user_args();var base:String=args[0];var out:String=args[1]
	var Shape:Script=OldShape
	var d:Dictionary=Catalog.definition("r34.module.repair_shed_v3")
	var parent:=Catalog.definition("r34.module.repair_shed_v2")
	var copy:Dictionary=d.duplicate(true)
	for key:String in ["id","geometry_version","dimensions_status"]:copy[key]=parent[key]
	for key:String in ["geometry_family_version","quality_parent_definition_id"]:copy.erase(key)
	check("candidate inherits all gameplay fields exactly including BC04 bench identity",Data.json_equal(copy,parent))
	check("registered catalog nineteen with current ten choices",Catalog.validate().ok and Catalog.definitions().size()==19 and Catalog.build_definition_ids().size()==10 and Catalog.build_definition_ids().has(d.id) and not Catalog.build_definition_ids().has(parent.id))
	var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"/before/data/modules/catalog_v1.json"))
	check("all original eighteen definitions retain exact fields and order",Data.json_equal(Catalog.definitions().slice(0,18),previous.definitions))
	var old12:Array=[];var old18:Array=[]
	for definition:Dictionary in previous.definitions:
		old18.append(profile(definition))
		if definition.get("geometry_family_version",1)!=2:old12.append(profile(definition))
	check("boolean API exact original12 and18 including order",Data.json_equal(Catalog.profiles(false),old12) and Data.json_equal(Catalog.profiles(true),old18))
	for content:int in range(1,11):
		var expected:Array=old12 if content<=8 else old18 if content==9 else old18+[profile(d)]
		check("versioned profiles exact content%d"%content,Data.json_equal(Catalog.profiles_for_content(content),expected) and Data.json_equal(Modules.generation_profiles_for_content(content),expected))
	for content:int in [-1,0,11,999]:check("unknown content%d cannot select profiles"%content,Catalog.profiles_for_content(content).is_empty() and Modules.generation_profiles_for_content(content).is_empty())
	check("original manual workbench anchor retained",OldShape.Families.bench_offset(parent)==Vector3(0,0,-0.6) and Shape.Families.bench_offset(d)==Vector3(0,0,-0.6))
	check("tools-buffer shelf layout exact",Data.json_equal(StockLayout.local_plan(parent),StockLayout.local_plan(d)))
	for content:int in [8,9]:
		var old:=Contract.fresh(old12 if content==8 else old18,content,1)
		var current:=Contract.fresh(Catalog.profiles_for_content(content),content,1)
		var resolved:=Contract.resolve(old.contract,Catalog.profiles_for_content(10))
		check("old fresh and saved content%d locks remain exact"%content,old.ok and current.ok and resolved.ok and Data.json_equal(old.contract,current.contract) and Data.json_equal(resolved.contract,old.contract) and not resolved.profiles.any(func(row:Dictionary)->bool:return row.id==d.id))
	var locked:=Contract.fresh(Catalog.profiles(),8,1)
	var source:=Generator.generate(713,Catalog.profiles(),locked.contract)
	# Explicit bounded flat laboratory; does not pretend to be natural placement.
	for key:String in source.chunks:
		var c:Vector3i=Data.coord(key)
		if c.x not in [3,4,5] or c.z not in [3,4,5]:continue
		var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	var world:=World.new();check("explicit bounded fixture world validates",world.load_snapshot(source).ok)
	var building:=Modules.building_adapter(world,{"actors":[],"stocks":[]})
	for variant:String in ["registered-v3"]:
		var definition:Dictionary=parent if variant=="old-v2" else d
		var parts:Array=OldShape.parts(parent) if variant=="old-v2" else Shape.parts(d)
		var roofs:int=parts.filter(func(part:Dictionary)->bool:return part.has("roof_mesh")).size()
		var contained:bool=parts.all(func(part:Dictionary)->bool:return G.aabb(definition.footprint).grow(0.001).encloses(AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))))
		check("contained structural parts "+variant,contained)
		if variant=="registered-v3":check("one continuous pitched roof replaces original eight bands",roofs==1 and parts.all(func(part:Dictionary)->bool:return ":roof:" not in part.id))
		for q:int in 4:
			var v:=Modules.record_for({"id":"work:repair:"+variant+":"+str(q),"definition_id":definition.id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":q})
			var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
			# Registered definition uses the original complete assembly, including bench.
			Modules.append_instance(world,building,v,definition,changes,structures)
			changes.append({"op":"extension.set","id":"r3:structures","before_exists":false,"before":null,"after":structures})
			var prepared:=world.prepare_changes(changes,world.get_revision())
			var safe:Dictionary=building.validate_world_draft(prepared.view,{"actors":[],"stocks":[]},changes) if prepared.ok else prepared
			check("original authority and structural validator accept explicit fixture "+variant+" q"+str(q),safe.ok,safe)
			if not safe.ok:continue
			var query:=Space.new();query.configure(prepared.view,structures,building.geometry,func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
			var ports:Array=Shape.ports(v,definition);var route_rows:Array=[];var clear:=true;var contact:=true
			for port:Dictionary in ports:
				clear=clear and not query.standing_point(port.location).is_empty()
				var arrival:=Modules.offset(port.location,G.point(port.normal))
				var route:=Navigation.new().plan(query,"player",arrival,port.location)
				contact=contact and query.line_clear(arrival,port.location)
				route_rows.append({"id":port.id,"ok":route.ok,"code":route.get("code","OK"),"steps":route.get("steps",[]).size()})
			check("all three original service feet retain standing and approach LOS "+variant+" q"+str(q),clear and contact)
			check("all original service approaches use original navigation "+variant+" q"+str(q),route_rows.all(func(row:Dictionary)->bool:return row.ok),route_rows)
			check("front workport reaches exact old bench with original contact ray "+variant+" q"+str(q),query.contact_clear(Shape.at(v,Vector3(0,0,-1.9)),Shape.at(v,Vector3(0,0,-0.6)),v.config.workbench_id))
			check("rear remains body blocking and opaque "+variant+" q"+str(q),query.standing_point(Shape.at(v,Vector3(0,0,1.26))).is_empty() and not query.line_clear(Shape.at(v,Vector3(0,0,0.7)),Shape.at(v,Vector3(0,0,2.0))))
			var stock_visuals:Dictionary=StockLayout.projection(v,definition);var stock_ok:=true;var stock_rows:Array=[]
			for key:String in stock_visuals:
				if not key.begins_with("tools:"):continue
				var status:=StockLayout.visibility(query,v,stock_visuals[key]);stock_ok=stock_ok and status.visual_available
				stock_rows.append({"item":key,"status":status})
			check("real tools shelf supports every inherited item bay "+variant+" q"+str(q),stock_ok,stock_rows)
			var adapter:=Modules.building_adapter(prepared.view,{"actors":[],"stocks":[]})
			var view:=View.new();var started:int=Time.get_ticks_usec();view.configure({"service":adapter});var elapsed:int=Time.get_ticks_usec()-started
			var mesh_count:=0;var slopes:=0;var surfaces:Array=[];var materials:Dictionary={};var world_mesh_ok:=true
			for member:Dictionary in v.members:
				var e:Dictionary=prepared.view.entity(member.id)
				if not e.get("data",{}).has("module_part"):continue
				var node:Node3D=view.objects.get(member.id)
				if not node is MeshInstance3D:world_mesh_ok=false;continue
				mesh_count+=1;var sloped:=false
				for si:int in node.mesh.get_surface_count():
					var arrays:Array=node.mesh.surface_get_arrays(si);var mat:StandardMaterial3D=node.mesh.surface_get_material(si);var vertices:Array=[];var normals:Array=[];var uvs:Array=[];var indices:Array=[]
					world_mesh_ok=world_mesh_ok and mat!=null and mat.albedo_texture!=null
					for point:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
						var point_world:Vector3=node.transform*point;vertices.append([point_world.x-32,point_world.y,point_world.z-32])
						if e.data.module_part.has("roof_mesh"):world_mesh_ok=world_mesh_ok and G.aabb(e.bounds).grow(0.001).has_point(point_world)
					for n:Vector3 in arrays[Mesh.ARRAY_NORMAL]:
						normals.append([n.x,n.y,n.z]);sloped=sloped or (absf(n.y)>0.01 and absf(n.y)<0.99)
					for uv:Vector2 in arrays[Mesh.ARRAY_TEX_UV]:uvs.append([uv.x,uv.y]);world_mesh_ok=world_mesh_ok and uv.is_finite()
					for index:int in arrays[Mesh.ARRAY_INDEX]:indices.append(index)
					var binding:String=""
					for key:String in view.materials:
						if view.materials[key]==mat:binding=key;break
					materials[binding]=true
					surfaces.append({"part":member.id,"material":binding,"vertices":vertices,"normals":normals,"uv":uvs,"indices":indices})
				if sloped:slopes+=1
			check("actual original entity_object consumes every part with textures finite UV and roof inside collider "+variant+" q"+str(q),world_mesh_ok and mesh_count==parts.size() and slopes==roofs,{"mesh_count":mesh_count,"sloped_meshes":slopes})
			var identities:Dictionary={}
			for key:String in view.objects:identities[key]=view.objects[key].get_instance_id()
			view._changed({"clock":1.0,"revision":1})
			check("pure clock retains actual nodes "+variant+" q"+str(q),identities.keys()==view.objects.keys() and identities.keys().all(func(key:String)->bool:return identities[key]==view.objects[key].get_instance_id()))
			observations.append({"variant":variant,"q":q,"parts":parts.size(),"actual_meshes":mesh_count,"material_bindings":materials.keys(),"surfaces":surfaces.size(),"create_view_usec":elapsed,"original_bench":structures.instances[0],"ports":ports})
			meshes.append({"variant":variant,"q":q,"parts":parts,"surfaces":surfaces})
			view.free();world.discard_prepared(prepared.capability)
	var all_ok:bool=checks.all(func(row:Dictionary)->bool:return row.ok)
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":all_ok,"checks":checks,"observations":observations,"scope":"Registered production definition/geometry/consumer and old profile invariants; explicit bounded flat fixture. Normal payment, natural content10, package, OS/VA/FPS separately qualified."},"\t"))
	FileAccess.open(out+"/mesh.json",FileAccess.WRITE).store_string(JSON.stringify(meshes))
	print("REPAIR_REGISTERED "+str(checks.size())+" "+str(all_ok));quit(0 if all_ok else 1)
