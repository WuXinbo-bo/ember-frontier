extends SceneTree
## Exact-source spatial/consumer laboratory. No renderer, population or natural-generation claim.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const World=preload("res://scripts/world/world_state.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Navigation=preload("res://scripts/buildings/building_navigation.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const StockLayout=preload("res://scripts/modules/module_stock_layout.gd")
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
		if d.has(key):p[key]=d[key].duplicate(true) if d[key] is Dictionary or d[key] is Array else d[key]
	for port:Dictionary in d.ports:
		var x:float=port.position[0];var z:float=port.position[2]
		p.foundation.pad_rectangles.append([x-1,z-1,x+1,z+1])
	return p
func run()->void:
	var args:=OS.get_cmdline_user_args();var base:String=args[0];var out:String=args[1]
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"/before/godot/afterglow/data/modules/catalog_v1.json"))
	check("catalog validates",Catalog.validate().ok)
	check("all original19 definitions unchanged and ordered",Data.json_equal(Catalog.definitions().slice(0,19),old.definitions))
	var p12:Array=[];var p18:Array=[];var p19:Array=[]
	for d:Dictionary in old.definitions:
		p19.append(profile(d))
		if d.id=="r34.module.repair_shed_v3":continue
		p18.append(profile(d))
		if d.get("geometry_family_version",1)!=2:p12.append(profile(d))
	check("old bool12/18 immutable",Data.json_equal(Catalog.profiles(false),p12) and Data.json_equal(Catalog.profiles(true),p18))
	for content:int in range(1,11):check("content%d exact unchanged"%content,Data.json_equal(Catalog.profiles_for_content(content),p12 if content<=8 else p18 if content==9 else p19))
	check("paused11 and unknown remain unsupported",Catalog.profiles_for_content(11).is_empty() and Catalog.profiles_for_content(99).is_empty())
	var added:Array=Catalog.definitions().filter(func(d:Dictionary)->bool:return d.get("architecture",{}).get("set")=="r34-architecture-30-v1")
	check("current build choices append every registered new definition once",Catalog.build_definition_ids().size()==10+added.size() and added.all(func(d:Dictionary)->bool:return Catalog.build_definition_ids().count(d.id)==1))
	var layouts:Array=JSON.parse_string(FileAccess.get_file_as_string(base+"/residential-layout.json"))
	check("nine exact capacities come from authoritative definitions",layouts.all(func(l:Dictionary)->bool:return Catalog.definition(l.id).get("architecture",{}).get("design_capacity")==l.capacity))
	if args.has("small-only"):added=added.filter(func(d:Dictionary)->bool:return d.architecture.family=="home" and d.architecture.tier=="small")
	if args.has("civic-only"):added=added.filter(func(d:Dictionary)->bool:return d.architecture.family in ["water","repair","guard"])
	if args.has("industrial-only"):added=added.filter(func(d:Dictionary)->bool:return d.architecture.family in ["sawmill","warehouse","canteen","artisan"])
	var locked:=Contract.fresh(Catalog.profiles(),8,1)
	var source:=Generator.generate(713,Catalog.profiles(),locked.contract)
	# Explicit bounded laboratory: generated terrain replaced only in this fixture.
	for key:String in source.chunks:
		var c:Vector3i=Data.coord(key);var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	var world:=World.new();var loaded:=world.load_snapshot(source);check("explicit fixture validates",loaded.ok)
	if not loaded.ok:return finish(out)
	var building:=Modules.building_adapter(world,{"actors":[],"stocks":[]})
	var old_shape:Script=load(base+"/before/godot/afterglow/scripts/modules/module_geometry.gd")
	for d:Dictionary in old.definitions:check("old member recipe stays exact "+d.id,Data.json_equal(Shape.parts(d),old_shape.parts(d)))
	for d:Dictionary in added:
		check("explicit owner dispatch supports exact version "+d.id,Shape.Residential.supports(d) or Shape.Civic.supports(d) or Shape.Industrial.supports(d))
		var parts:Array=Shape.parts(d);var bounds:=G.aabb(d.footprint)
		var unique:Dictionary={};var ids_ok:=not parts.is_empty();var contained:=true
		for p:Dictionary in parts:
			ids_ok=ids_ok and not unique.has(p.id);unique[p.id]=true
			contained=contained and G.point(p.size).x>0 and G.point(p.size).y>0 and G.point(p.size).z>0 and bounds.grow(0.002).encloses(AABB(G.point(p.center)-G.point(p.size)/2,G.point(p.size)))
		check("nonempty unique contained parts "+d.id,ids_ok and contained,{"parts":parts.size(),"contained":contained})
		for q:int in 4:
			var v:=Modules.record_for({"id":"B:architecture:"+str(d.id)+":"+str(q),"definition_id":d.id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":q})
			var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
			Modules.append_instance(world,building,v,d,changes,structures)
			changes.append({"op":"extension.set","id":"r3:structures","before_exists":false,"before":null,"after":structures})
			var draft:=world.prepare_changes(changes,world.get_revision())
			var safe:Dictionary=building.validate_world_draft(draft.view,{"actors":[],"stocks":[]},changes) if draft.ok else draft
			check("original World/Building accepts "+d.id+" q"+str(q),safe.ok,safe.get("code"))
			if not safe.ok:continue
			var query:=Space.new();query.agent.radius=0.4;query.configure(draft.view,structures,building.geometry,func(_a:Variant,_b:Variant,_c:Variant,_e:Variant)->Variant:return null)
			var ports:Array=Shape.ports(v,d);var valid:=true;var routes:Array=[]
			for p:Dictionary in ports:
				for point:Dictionary in p.use_points:
					valid=valid and not query.standing_point(point).is_empty()
				var arrival:=Modules.offset(p.location,G.point(p.normal)*1.6)
				var route:=Navigation.new().plan(query,"player",arrival,p.location)
				routes.append({"id":p.id,"ok":route.ok,"code":route.get("code")})
			check("actual .4m/1.8m standing/support and approach "+d.id+" q"+str(q),valid and routes.all(func(r:Dictionary)->bool:return r.ok),routes)
			if d.shape=="manual":
				var bench:Dictionary=draft.view.entity(str(v.config.workbench_id));var contact:bool=false
				for p:Dictionary in ports:
					if p.purpose=="work":
						var feet:Dictionary=p.location
						var target:Dictionary=Shape.at(v,Shape.Families.bench_offset(d))
						contact=not bench.is_empty() and G.point(feet).distance_to(G.point(target))<=1.6 and query.contact_clear(feet,target,str(bench.id))
				check("original unique workbench real contact "+d.id+" q"+str(q),contact)
			var stock_bays:Dictionary=StockLayout.projection(v,d);var stock_ok:bool=true
			for buffer:Dictionary in d.buffer_specs:
				for item:String in buffer.limits:
					var key:String=str(buffer.id)+":"+item
					stock_ok=stock_ok and stock_bays.has(key) and StockLayout.visibility(query,v,stock_bays[key]).visual_available
			check("all real stock bays support and avoid structure/body service "+d.id+" q"+str(q),stock_ok,stock_bays)
			if d.architecture.family=="home":
				var l:Dictionary=layouts.filter(func(row:Dictionary)->bool:return row.id==d.id)[0];var a:Array=l.court_probe
				var goal:=Shape.at(v,Vector3(a[0],a[1],a[2]));var route:=Navigation.new().plan(query,"player",ports[0].location,goal)
				check("real open yard remains reachable "+d.id+" q"+str(q),not query.standing_point(goal).is_empty() and route.ok,route.get("code"))
			var adapter:=Modules.building_adapter(draft.view,{"actors":[],"stocks":[]});var view:=View.new();var started:=Time.get_ticks_usec();view.configure({"service":adapter});var elapsed:=Time.get_ticks_usec()-started
			var mesh_count:=0;var triangles:=0;var material_ids:Dictionary={};var surface_count:=0;var mesh_ok:=true;var output:Array=[]
			for member:Dictionary in v.members:
				var e:Dictionary=draft.view.entity(member.id)
				if not e.get("data",{}).has("module_part"):continue
				var node:Node3D=view.objects.get(member.id)
				if not node is MeshInstance3D:mesh_ok=false;continue
				mesh_count+=1
				for si:int in node.mesh.get_surface_count():
					var arrays:Array=node.mesh.surface_get_arrays(si);var mat:StandardMaterial3D=node.mesh.surface_get_material(si);surface_count+=1
					mesh_ok=mesh_ok and mat!=null and (mat.albedo_texture!=null or (mat.get_meta("architecture_surface","")=="architecture_window" and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED))
					var vv:Array=[];var nn:Array=[];var uv:Array=[];var ii:Array=[]
					for p:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
						mesh_ok=mesh_ok and p.is_finite();var wp:Vector3=node.transform*p;vv.append([wp.x-32,wp.y,wp.z-32])
					for n:Vector3 in arrays[Mesh.ARRAY_NORMAL]:nn.append([n.x,n.y,n.z])
					for u:Vector2 in arrays[Mesh.ARRAY_TEX_UV]:uv.append([u.x,u.y]);mesh_ok=mesh_ok and u.is_finite()
					for i:int in arrays[Mesh.ARRAY_INDEX]:ii.append(i)
					triangles+=ii.size()/3
					var material_id:=""
					for key:String in view.materials:
						if view.materials[key]==mat:material_id=key;break
					material_ids[material_id]=true
					if q==0:output.append({"part":member.id,"material":material_id,"vertices":vv,"normals":nn,"uv":uv,"indices":ii})
			check("actual view consumes all members/textures/UV "+d.id+" q"+str(q),mesh_ok and mesh_count==parts.size(),{"meshes":mesh_count,"parts":parts.size()})
			var identity:Dictionary={}
			for id:String in view.objects:identity[id]=view.objects[id].get_instance_id()
			view._changed({"clock":1.0,"revision":1})
			check("clock preserves actual nodes "+d.id+" q"+str(q),identity.keys()==view.objects.keys() and identity.keys().all(func(key:String)->bool:return identity[key]==view.objects[key].get_instance_id()))
			observations.append({"id":d.id,"q":q,"parts":parts.size(),"nodes":mesh_count,"surfaces":surface_count,"triangles":triangles,"materials":material_ids.keys(),"create_view_usec":elapsed,"ports":ports})
			if q==0:meshes.append({"id":d.id,"parts":parts,"surfaces":output})
			view.free();world.discard_prepared(draft.capability)
	finish(out)
func finish(out:String)->void:
	var ok:bool=not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok)
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"checks":checks,"observations":observations,"scope":"Exact current source; bounded explicit flat fixture, all four rotations actual World/Space/.4 body/Navigation/BuildingView, no renderer/natural generation/VA/FPS/PCK or population claim."},"\t"))
	FileAccess.open(out+"/mesh.json",FileAccess.WRITE).store_string(JSON.stringify(meshes))
	print("ARCHITECTURE "+str(checks.size())+" "+str(ok));quit(0 if ok else 1)
