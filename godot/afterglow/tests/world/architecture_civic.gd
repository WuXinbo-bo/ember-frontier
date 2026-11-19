extends SceneTree
## Exact-source spatial laboratory, not normal paid play or renderer/VA.
const Civic=preload("res://scripts/modules/module_civic_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const World=preload("res://scripts/world/world_state.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Navigation=preload("res://scripts/buildings/building_navigation.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Plot=preload("res://scripts/generation/architecture_plot_layout.gd")
var checks:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func commit(world:RefCounted,ops:Array)->Dictionary:
	var draft:Dictionary=world.prepare_changes(ops,world.get_revision())
	return world.commit_prepared(draft.capability) if draft.ok else draft
func query_for(world:RefCounted,structures:Dictionary,building:RefCounted)->RefCounted:
	var query:=Space.new();query.agent.radius=0.4;query.agent.height=1.8
	query.configure(world,structures,building.geometry,func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
	return query
func run()->void:
	var source:Dictionary=Factory.generate(713,Catalog.profiles(),Contract.fresh(Catalog.profiles(),8,1).contract)
	# Deliberate bounded flat structural fixture, no authority capture editing.
	for key:String in source.chunks:
		var c:Vector3i=Data.coord(key);var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	var world:=World.new();check("bounded structural fixture validates",world.load_snapshot(source).ok)
	var building:=Modules.building_adapter(world,{"actors":[],"stocks":[]})
	var silhouettes:Dictionary={}
	for definition:Dictionary in Catalog.definitions():
		if not Civic.IDS.has(definition.id):check("legacy and other owner not intercepted "+str(definition.id),not Civic.supports(definition))
	for id:String in Civic.IDS:
		var d:=Catalog.definition(id)
		check("exact new definition dispatch "+id,Civic.supports(d) and Data.json_equal(Shape.parts(d),Civic.parts(d)))
		if d.is_empty():continue
		var parts:=Civic.parts(d);var bound:=G.aabb(d.footprint);var bad:Array=[];var ids:Dictionary={}
		for part:Dictionary in parts:
			if ids.has(part.id) or not bound.grow(0.002).encloses(AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))):bad.append(part.id)
			ids[part.id]=true
		check("all structural and derived proxies contained "+id,bad.is_empty() and not parts.is_empty(),bad)
		silhouettes[JSON.stringify(parts).sha256_text()]=true
		for q:int in 4:
			var instance:=Modules.record_for({"id":"C:civic:"+id+":"+str(q),"definition_id":id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":q})
			var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
			Modules.append_instance(world,building,instance,d,changes,structures)
			var draft:=world.prepare_changes(changes,world.get_revision())
			var safe:Dictionary=building.validate_world_draft(draft.view,{"actors":[],"stocks":[]},changes) if draft.ok else draft
			check("original World and construction validate "+id+" q"+str(q),safe.ok,safe)
			if not safe.ok:
				if draft.ok:world.discard_prepared(draft.capability)
				continue
			var query:=query_for(draft.view,structures,building)
			var routes:Array=[]
			for port:Dictionary in Shape.ports(instance,d):
				var arrival:=Modules.offset(port.location,G.point(port.normal)*1.6)
				var route:=Navigation.new().plan(query,"player",arrival,port.location)
				routes.append({"port":port.id,"stand":not query.standing_point(port.location).is_empty(),"route":route.ok,"code":route.get("code")})
			check("actual conservative body all services "+id+" q"+str(q),routes.all(func(r:Dictionary)->bool:return r.stand and r.route),routes)
			var plot:=Plot.plot(d,Vector3(32,0,32),q)
			var ring_ok:bool=plot.ok
			if plot.ok:
				for path:Dictionary in plot.paths:
					for i:int in path.points.size()-1:
						var a:Dictionary=path.points[i].merged({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
						var b:Dictionary=path.points[i+1].merged({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
						ring_ok=ring_ok and Navigation.new().plan(query,"player",a,b).ok
			check("entire suggested outer ring and service throats navigable "+id+" q"+str(q),ring_ok,plot.get("code"))
			var adapter:=Modules.building_adapter(draft.view,{"actors":[],"stocks":[]})
			var view:=View.new();var started:=Time.get_ticks_usec();view.configure({"service":adapter});var cost:int=Time.get_ticks_usec()-started
			var mesh_ok:=true;var mesh_bad:Array=[];var count:=0;var tris:=0;var actual_materials:Dictionary={};var collision_count:=0
			for member:Dictionary in instance.members:
				var entity:Dictionary=draft.view.entity(member.id)
				if not entity.get("data",{}).has("module_part"):continue
				var node:Variant=view.objects.get(member.id)
				if not node is MeshInstance3D:mesh_ok=false;continue
				count+=1
				for si:int in node.mesh.get_surface_count():
					var arr:Array=node.mesh.surface_get_arrays(si);var material:StandardMaterial3D=node.mesh.surface_get_material(si)
					# Glass uses the owner's native opaque dark material, as
					# specified; it has no invented glass PNG or transparency.
					var native_window:bool=material!=null and material==view.materials.get("architecture_window") and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a==1.0 and material.albedo_color.v<0.4
					if material==null or (material.albedo_texture==null and not native_window):mesh_bad.append({"part":member.id,"issue":"missing actual texture or approved native material"})
					mesh_ok=mesh_ok and material!=null and (material.albedo_texture!=null or native_window)
					var violations:Array=[]
					for p:Vector3 in arr[Mesh.ARRAY_VERTEX]:
						# Window sills deliberately project beyond the sealed wall
						# proxy. The complete reserved building envelope is the
						# actual visual containment boundary, including those sills.
						var inside:bool=p.is_finite() and Shape.transform_box(instance,G.aabb(d.footprint)).grow(0.002).has_point(node.transform*p)
						mesh_ok=mesh_ok and inside
						if not inside and violations.size()<2:violations.append({"local":G.json_point(p),"world":G.json_point(node.transform*p),"bounds":entity.bounds})
					if not violations.is_empty():mesh_bad.append({"part":member.id,"issue":"vertex beyond proxy","samples":violations})
					for uv:Vector2 in arr[Mesh.ARRAY_TEX_UV]:mesh_ok=mesh_ok and uv.is_finite()
					tris+=arr[Mesh.ARRAY_INDEX].size()/3
					if material!=null:actual_materials[material.resource_name+str(material.albedo_texture.resource_path if material.albedo_texture else "null")]=true
				if entity.data.solid:collision_count+=1
			check("actual mesh UV textures and finite geometry "+id+" q"+str(q),mesh_ok and count==parts.size(),{"mesh_count":count,"parts":parts.size(),"triangles":tris,"bad":mesh_bad})
			check("derived paving has no second collision "+id+" q"+str(q),not draft.view.entity(instance.id+":part:service-paving-drain").data.solid and query.solid_entities.all(func(e:Dictionary)->bool:return e.get("id")!=instance.id+":part:service-paving-drain"))
			if d.shape=="manual":check("sole original workbench "+id+" q"+str(q),structures.instances.size()==1 and instance.members.filter(func(m:Dictionary)->bool:return m.kind=="structure").size()==1 and instance.config.workbench_id==structures.instances[0].id)
			rows.append({"id":id,"q":q,"parts":parts.size(),"triangles":tris,"collision_members":collision_count,"actual_materials":actual_materials.size(),"view_cpu_usec":cost,"scope":"headless source local CPU, not frame/GPU cost"})
			view.free();world.discard_prepared(draft.capability)
	check("nine genuinely different part assemblies",silhouettes.size()==9)
	# Commit a compound set through the same CAS, then real codec + cold/warm.
	var compound:Array=[];var ss:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]};var module_state:=Modules.initial();var index:=0
	for id:String in Civic.IDS:
		var d:=Catalog.definition(id);var v:=Modules.record_for({"id":"C:compound:"+id,"definition_id":id,"region":"RH-HOME","position":{"x":14+(index%3)*18,"y":0,"z":14+(index/3)*18},"quarter_turn":index%4})
		Modules.append_instance(world,building,v,d,compound,ss);module_state.instances.append(v);index+=1
	compound.append({"op":"extension.set","id":"r3:structures","before_exists":false,"before":null,"after":ss})
	compound.append({"op":"extension.set","id":Modules.KEY,"before_exists":false,"before":null,"after":module_state})
	var built:=commit(world,compound);check("nine compound structures commit through original CAS",built.ok,built.get("code"))
	if built.ok:
		var saved:=world.snapshot();var cold_ok:=true;var batches:=0
		for resident:bool in [false,true]:
			for _batch:int in 32:
				var draft:Dictionary=world.prepare_region_residency("RH-HOME",resident,world.get_revision(),32)
				if not draft.ok:cold_ok=false;break
				if not draft.world_changes.is_empty():cold_ok=cold_ok and commit(world,draft.world_changes).ok;batches+=1
				if draft.complete:break
		check("32chunk cold/warm retains every authoritative member",cold_ok and Data.json_equal(saved.entities,world.snapshot().entities) and Data.json_equal(saved.extensions,world.snapshot().extensions),{"batches":batches})
		var encoded:=Codec.encode(world.snapshot(),{},"C:architecture:codec")
		var decoded:Dictionary=Codec.decode(encoded.envelope) if encoded.ok else encoded
		var restored:=World.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
		var payload:Dictionary=JSON.parse_string(encoded.envelope.payload) if encoded.ok else {}
		check("codec restore retains complete canonical payload IDs recipes and modules",loaded.ok and Data.json_equal(restored.snapshot().entities,payload.world.entities) and Data.json_equal(restored.snapshot().extensions,payload.world.extensions),{"code":loaded.get("code"),"raw_original_entity_equal":Data.json_equal(restored.snapshot().entities,saved.entities) if loaded.ok else false,"raw_original_extension_equal":Data.json_equal(restored.snapshot().extensions,saved.extensions) if loaded.ok else false,"limitation":"Existing JSON scalar tail/1ULP limitation retained; original source and encoded payload retained, no epsilon and no codec change."})
		FileAccess.open(OS.get_cmdline_user_args()[0]+".envelope.json",FileAccess.WRITE).store_string(JSON.stringify(encoded.envelope,"\t",true,true))
		FileAccess.open(OS.get_cmdline_user_args()[0]+".saved-entities.json",FileAccess.WRITE).store_string(JSON.stringify(saved.entities,"\t",true,true))
		FileAccess.open(OS.get_cmdline_user_args()[0]+".restored-entities.json",FileAccess.WRITE).store_string(JSON.stringify(restored.snapshot().entities,"\t",true,true))
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"Civic9 source structural/mesh/material/actual .4m body/outer ring/codec/cold-warm fixture. No paid build/normal play/renderer/VA/FPS/PCK qualification."},"\t",true,true))
	print("CIVIC "+str(checks.size())+" failed="+str(failed));quit(0 if failed==0 else 1)
