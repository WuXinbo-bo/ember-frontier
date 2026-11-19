extends SceneTree
const Modules=preload("res://scripts/modules/module_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const World=preload("res://scripts/world/world_state.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var summaries:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail});if not ok:print("FAIL "+name+" "+str(detail))
func run()->void:
	var profiles:=Catalog.profiles();var locked:=Contract.fresh(profiles,3)
	check("v3 locks exact real design metadata",locked.ok and profiles.filter(func(p:Dictionary)->bool:return p.has("design_id")).size()==7)
	for seed:int in [713,2026]:
		var generated:=Generator.generate(seed,profiles,locked.contract);var opening:=Assembly.prepare(generated)
		check("real v3 new-world normal assembly "+str(seed),opening.ok,opening.get("reason"))
		if not opening.ok:continue
		var host:=Native.new();var mounted:=host._assemble(opening.capture)
		check("real v3 same Native restore "+str(seed),mounted.ok,mounted.get("reason"))
		if not mounted.ok:host.free();continue
		var service:RefCounted=mounted.services.modules;var visible:=View.new()
		visible.configure({"service":mounted.services.buildings,"runtime":mounted.runtime})
		var player:Dictionary=mounted.runtime.actor("player");var part_count:int=0;var render_count:int=0;var blocked_count:int=0
		for v:Dictionary in service.state().instances:
			for port:Dictionary in Shape.ports(v,Catalog.definition(v.definition_id)):
				check("actual v3 port supports true body "+str(seed)+v.id+port.id,not mounted.services.buildings.current_space().standing_point(port.location).is_empty())
			if v.region!=player.regionId:continue
			for member:Dictionary in v.members:
				var entity:Dictionary=mounted.world.entity(member.id)
				if not entity.get("data",{}).has("module_part"):continue
				part_count+=1
				if visible.objects.has(member.id) and visible.objects[member.id].visible:render_count+=1
				if not mounted.services.buildings.current_space().line_clear(G.location(player),G.location(entity),member.id):blocked_count+=1
		check("fixed exterior parts survive their own actual LOS occlusion "+str(seed),part_count>0 and render_count==part_count and blocked_count>0,{"parts":part_count,"rendered":render_count,"opaque_ray_blocked":blocked_count})
		var old:Dictionary=mounted.runtime.capture_checkpoint();visible.update_visibility()
		check("render visibility never changes authority or stock visibility "+str(seed),Data.json_equal(old,mounted.runtime.capture_checkpoint()))
		var cold_host:=Native.new();var restored:Dictionary=cold_host._assemble(old)
		check("same new design and member IDs survive cold restore "+str(seed),restored.ok and Data.json_equal(restored.services.modules.state(),service.state()))
		visible.free();cold_host.free();host.free()
	# Deliberately isolated flat physical patch for exhaustive rotations. Real
	# C source, world draft, structure adapter, body collider and material mesh;
	# not normal terrain/economy or rendered quality evidence.
	var source:=Generator.generate(713,profiles,locked.contract)
	for key:String in source.chunks:
		var coord:Vector3i=Data.coord(key)
		if coord.x not in [2,3,4,5] or coord.z not in [2,3,4,5]:continue
		var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if coord.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	var world:=World.new();check("rotation fixture floor remains valid sole world",world.load_snapshot(source).ok)
	var building:=Modules.building_adapter(world,{"actors":[],"stocks":[]});var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	var signatures:Dictionary={}
	for d:Dictionary in Catalog.definitions().filter(func(row:Dictionary)->bool:return row.get("geometry_family_version",1)<2):
		if not d.has("design_id"):continue
		var parts:=Shape.parts(d);var extent:=G.aabb(d.footprint);var valid:bool=not parts.is_empty();var distinct:Dictionary={};var bytes:String=""
		for p:Dictionary in parts:
			var b:=AABB(G.point(p.center)-G.point(p.size)/2,G.point(p.size));distinct[p.id]=true
			valid=valid and extent.grow(0.001).encloses(b) and manifest.textures.has(p.material)
			bytes+=JSON.stringify(p)
		check("design has complete metre-contained textured shell "+d.id,valid and distinct.size()==parts.size(),{"parts":parts.size(),"sha256":bytes.sha256_text()})
		signatures[d.design_id]=bytes.sha256_text();summaries.append({"id":d.id,"geometry_version":d.geometry_version,"parts":parts.size(),"sha256":bytes.sha256_text()})
		for turn:int in 4:
			var instance:=Modules.record_for({"id":"B:design:"+str(turn)+d.id,"definition_id":d.id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":turn})
			var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
			Modules.append_instance(world,building,instance,d,changes,structures)
			if not structures.instances.is_empty():changes.append(building.extension_change(Building.EXTENSION,structures))
			var prepared:Dictionary=world.prepare_changes(changes,world.get_revision());var safe:Dictionary=building.validate_world_draft(prepared.view,{"actors":[],"stocks":[]},changes) if prepared.ok else prepared
			check("rotation real geometry passes same safety "+d.id+" q"+str(turn),safe.ok,safe.get("reason"))
			if not safe.ok:continue
			var query:=Space.new();query.configure(prepared.view,structures,building.geometry,func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
			var good:bool=true
			for port:Dictionary in Shape.ports(instance,d):
				for at:Dictionary in port.use_points:good=good and not query.standing_point(at).is_empty()
			check("rotation every declared use point has full body clearance "+d.id+" q"+str(turn),good)
			world.discard_prepared(prepared.capability)
	check("seven design silhouettes are independently authored",signatures.values().size()==7 and signatures.values().size()==unique(signatures.values()).size())
	print(JSON.stringify({"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"designs":summaries,"scope":"real source/collision/material/visibility checks, isolated rotation floor; no formal renderer or VA"}));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
func unique(values:Array)->Array:
	var set:Dictionary={};for value:Variant in values:set[value]=true
	return set.keys()
