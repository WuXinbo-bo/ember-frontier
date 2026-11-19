extends "res://tests/buildings/domain_suite.gd"
## Derived ceiling checks at A's exact camera stations. Fixture repositioning
## is explicit; this does not claim a player route, a screenshot or VA pass.
const Client=preload("res://scripts/runtime/native_client.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const HOME="rural:v1:RH-HOME:old-house"
var host:Node
var view:Node3D

func fixture_at(x:float,z:float)->bool:
	var point:Dictionary=building.current_space().standing_point({"x":x,"y":0,"z":z,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	expect("explicit exact station has real foot/body clearance "+str(Vector2(x,z)),not point.is_empty())
	if point.is_empty():return false
	var facts:=runtime.facts()
	for actor:Dictionary in facts.actors:
		if actor.id=="player":actor.merge(point,true);actor.intent=null
	var configured:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	expect("exact station configures same authority",configured.ok,configured.get("reason"))
	view.update_visibility()
	return configured.ok

func roof_state()->Dictionary:
	var result:Dictionary={}
	for node:MeshInstance3D in view.static_nodes.values():
		if node.get_meta("role")!="roof":continue
		for id:String in node.get_meta("piece_ids",[]):
			if building.current_space().by_id[id].get("buildingId")==HOME:result[id]=node.visible
	return result

func exact_values(a:Variant,b:Variant)->bool:
	# JSON decodes integer-valued numbers as floats. Preserve every value and
	# field exactly, allowing only that representation change, no tolerance.
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not exact_values(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not exact_values(a[i],b[i]):return false
		return true
	return a==b

func coherent(label:String)->void:
	var state:=roof_state();var visibility:Dictionary={};var mixed:Array=[]
	for id:String in state:
		var component:int=view.roof_cutaway.components[id]
		if visibility.has(component) and visibility[component]!=state[id]:mixed.append(id)
		visibility[component]=state[id]
	var p:=Geometry.location(runtime.actor("player"))
	var active:int=view.roof_cutaway.component_at(p)
	var wrong_active:Array=[]
	for id:String in state:
		if int(view.roof_cutaway.components[id])==active and state[id]:wrong_active.append(id)
	expect(label+" changes whole connected ceiling regions",not state.is_empty() and mixed.is_empty() and wrong_active.is_empty(),{"roof_count":state.size(),"components":visibility,"active":active,"mixed":mixed,"wrong_active":wrong_active})
	var unknown:Array=[]
	for id:String in view.objects:
		var node:Node3D=view.objects[id]
		if node.get_meta("piece",{}).get("buildingId")==HOME and not view.visible_room(node.get_meta("piece"),runtime.actor("player")) and node.visible:unknown.append(id)
	expect(label+" leaves unseen props on original line-of-sight boundary",unknown.is_empty(),unknown)

func operate_door(id:String,operation:String)->bool:
	var attempts:Array=[]
	for point:Dictionary in building.use_points(id):
		if not fixture_at(float(point.x),float(point.z)):continue
		var result:=command("door",id,{"operation":operation})
		attempts.append(result)
		if not result.ok:continue
		for i in 4:runtime.tick(0.1)
		expect("real unified timed door "+operation,building.instance(id).door.open==(operation=="open"),attempts)
		view.update_visibility();coherent(operation+" internal door")
		return true
	expect("real door operation available "+operation,false,attempts)
	return false

func safe_edit(removed:Array,added:Array)->bool:
	# Spatial edit fixture, deliberately not a material/production claim: use
	# the production prepare + full world-draft validator + C capability CAS.
	var prepared:Dictionary=building.prepare_edit(removed,added)
	if not prepared.ok:expect("roof edit passes original spatial preparation",false,prepared);return false
	var draft:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision())
	var safety:Dictionary=building.validate_world_draft(draft.view,runtime.facts(),prepared.world_changes) if draft.ok else draft
	expect("roof edit passes complete draft support and resident safety",safety.ok,safety.get("reason"))
	if not safety.ok:return false
	expect("roof edit atomically commits original C capability",world.commit_prepared(draft.capability).ok)
	view.rebuild()
	return true

func save_restore()->void:
	var before:=roof_state();var capture:=runtime.capture_checkpoint()
	var saved:=Store.encode(capture)
	var decoded:=Store.decode(saved.get("text",""))
	var restored:Dictionary=host._assemble(decoded.capture) if saved.ok and decoded.ok else {"ok":false,"reason":saved.get("reason",decoded.get("reason"))}
	expect("real native codec and formal assembler restore modified ceiling",restored.ok,restored.get("reason"))
	if not restored.ok:return
	view.free();world=restored.world;runtime=restored.runtime;building=restored.services.buildings;actions=restored.services.actions;production=restored.services.production
	view=building.create_view({"runtime":runtime})
	expect("restore reproduces exact roof IDs and derived visibility",roof_state()==before)
	var stocks_equal:bool=exact_values(runtime.facts().stocks,capture.facts.stocks)
	var knowledge_equal:bool=world.extension(Production.KEY).knowledge==capture.world.extensions[Production.KEY].knowledge
	var door_open:bool=building.instance(HOME+":living-kitchen-door").door.open
	expect("restore preserves exact stock identities counts knowledge and door state",stocks_equal and knowledge_equal and door_open,{"stocks_equal":stocks_equal,"knowledge_equal":knowledge_equal,"door_open":door_open,"before_stocks":capture.facts.stocks if not stocks_equal else [],"after_stocks":runtime.facts().stocks if not stocks_equal else []})
	expect("stock comparator permits JSON numeric type only and rejects any quantity change",exact_values({"items":{"water":2}},{"items":{"water":2.0}}) and not exact_values({"items":{"water":2}},{"items":{"water":2.000000001}}) and not exact_values({"items":{"water":2}},{"items":{"water":1}}) and not exact_values({"id":"old"},{"id":"new"}))
	coherent("save and formal restore")

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real rural C world loads",world.load_snapshot(Generator.generate(713)).ok)
	building.configure({"world":world,"runtime":runtime})
	var seeded:Dictionary=building.seed_rural(world)
	var facts:=Initial.facts(seeded)
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([building.extension_change(Production.KEY,Initial.production(seeded)),building.extension_change(Gameplay.KEY,Gameplay.initial()),building.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	expect("finite rural setup is real C capability",draft.ok and world.commit_prepared(draft.capability).ok)
	host=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":facts,"source":{"test":"B connected ceiling exact-station fixtures"}})
	expect("formal assembler supplies sole runtime and all actual services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	view=building.create_view({"runtime":runtime})
	for station:Vector2 in [Vector2(15.38977,28.50865),Vector2(21.33907,27.50282),Vector2(18,36),Vector2(12,35.5),Vector2(12,29.5),Vector2(20,29.5),Vector2(30,43)]:
		if fixture_at(station.x,station.y):coherent("A/existing station "+str(station))
	fixture_at(18,36)
	var kitchen_id:int=view.roof_cutaway.components[HOME+":roof:13:35"]
	var living_id:int=view.roof_cutaway.components[HOME+":roof:19:35"]
	expect("closed real partition separates kitchen and living ceilings",kitchen_id!=living_id)
	if operate_door(HOME+":living-kitchen-door","open"):
		expect("real door opening recomputes and joins reachable ceiling regions",view.roof_cutaway.components[HOME+":roof:13:35"]==view.roof_cutaway.components[HOME+":roof:19:35"])
		if operate_door(HOME+":living-kitchen-door","close"):
			expect("real door closing splits ceilings without stale topology",view.roof_cutaway.components[HOME+":roof:13:35"]!=view.roof_cutaway.components[HOME+":roof:19:35"])
	fixture_at(18,36)
	var removed:Dictionary=building.instance(HOME+":roof:19:35")
	if safe_edit([removed.id],[]):
		expect("actual removed roof is absent in derived mesh",not roof_state().has(removed.id))
		if fixture_at(19,35):
			coherent("player under real missing tile")
			expect("standing under missing roof retains room membership",view.roof_cutaway.component_at(Geometry.location(runtime.actor("player")))>=0)
		# Removed IDs are retired by the authoritative world. A reconstruction
		# is a new piece at the same footprint, never a resurrected old identity.
		var retired:Dictionary=building.prepare_edit([],[removed])
		var retired_draft:Dictionary=world.prepare_changes(retired.world_changes,world.get_revision()) if retired.ok else retired
		var retired_safe:Dictionary=building.validate_world_draft(retired_draft.view,runtime.facts(),retired.world_changes) if retired_draft.ok else retired_draft
		expect("retired roof identity cannot be resurrected",not retired_safe.ok and retired_safe.get("reason")=="RETIRED_ENTITY_ID",retired_safe.get("reason"))
		var rebuilt:=removed.duplicate(true);rebuilt.id="bbb:roof-rebuilt:19:35"
		if safe_edit([],[rebuilt]):
			expect("real rebuilt roof uses new ID and original two-metre footprint",view.roof_cutaway.components.has(rebuilt.id) and not view.roof_cutaway.components.has(removed.id) and building.instance(rebuilt.id).position==removed.position)
			coherent("rebuilt tile with new authoritative ID")
	if operate_door(HOME+":living-kitchen-door","open"):save_restore()
	view.free();host.free();finish(started)
