extends SceneTree
## Real async native composition/save lifecycle in an explicitly isolated store.
## This is not OS-input, normal-camera VA or a performance qualification.
const Client=preload("res://scripts/runtime/native_client.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
class TestClient extends Client:
	func _ready()->void:pass
var checks:Array=[]
var host:Node3D
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	host=TestClient.new();host.controls_path=output+"/isolated-controls.json";root.add_child(host)
	host.store=Store.new(output+"/isolated-saves")
	var legacy:Dictionary=host._new_rural(713)
	check("retained rural-1 formal mount succeeds",legacy.ok,legacy)
	if not legacy.ok:finish();return
	host.runtime.set_paused(true)
	var saved:Dictionary=await host.save_async("fixture-old-slot")
	check("old finite world saved in isolated real store",saved.ok,saved)
	var pointer_path:String=output+"/isolated-saves/active.json"
	var old_pointer:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pointer_path))
	var old_path:String=output+"/isolated-saves/"+old_pointer["namespace"]+"/"+old_pointer.slot+".json"
	var old_text:String=FileAccess.get_file_as_string(old_path)
	var result:Dictionary=await host.start_new_world(713,"generated-entry-713")
	check("real async worker + C/B + validation + ephemeral mount succeeds",result.ok,result)
	if not result.ok:finish();return
	host.runtime.set_paused(true)
	check("same formal runtime now owns rural-3",host.world.identity().get("generatorVersion")=="rural-3",host.world.identity())
	check("fresh entry does not touch active save pointer",JSON.parse_string(FileAccess.get_file_as_string(pointer_path))==old_pointer)
	var explicit:Dictionary=await host.save_async("explicit-new-world")
	check("explicit manual save creates the new namespace",explicit.ok,explicit)
	var pointer:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pointer_path))
	check("new world uses distinct native save namespace",pointer["namespace"]!=old_pointer["namespace"],{"old":old_pointer["namespace"],"new":pointer["namespace"]})
	check("original saved bytes remain recoverable",FileAccess.get_file_as_string(old_path)==old_text)
	var archived:Dictionary=Store.decode(old_text)
	check("original namespace still decodes to unchanged old world",archived.ok and archived.capture.world.generatorVersion=="rural-1")
	var state:Dictionary=host.world.extension(Gameplay.KEY)
	var layout:Dictionary=state.get("layout",{})
	check("runtime source and gameplay layout retain actual generator identity",host.runtime.capture_checkpoint().source.get("generator")=="rural-3" and layout.get("generator")=="rural-3")
	check("gameplay uses persisted actual building IDs",layout.get("home_building")=="RH-HOME:home" and layout.get("store_prefix")=="RH-VILLAGE:store:",layout)
	var harvest:Array=host.runtime.work_targets().filter(func(t:Dictionary)->bool:return t.get("work_payload",{}).get("action_kind")=="harvest")
	check("generated work delivery uses a real home container",not harvest.is_empty() and harvest.all(func(t:Dictionary)->bool:return t.work_payload.delivery_id==str(layout.home_building)+":storage" and not host.runtime.stock(t.work_payload.delivery_id).is_empty()))
	check("home references real nonzero terrain height",float(host.runtime.actor("player").home.y)!=0 and host.runtime.actor("player").home==layout.home)
	check("two residents remain unjoined and unconsented",host.runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.id!="player").all(func(a:Dictionary)->bool:return not a.relationship.member and not a.relationship.consent))
	var building:RefCounted=host.runtime._services.buildings
	var query:RefCounted=building.current_space()
	check("all actual actor spawns pass real spatial validation",building.validate_snapshot(host.world,host.runtime.facts()).ok)
	var positions:Array=layout.encounter_positions.duplicate(true);positions.append(layout.defense_position)
	check("encounters/defense have real supported outdoor anchors",positions.all(func(p:Dictionary)->bool:return not query.standing_point(p).is_empty() and p.get("buildingId")==null),positions)
	var policy:=Policy.new();policy.configure(query)
	var rooms:Dictionary={}
	for roof:Dictionary in policy._rooms.roofs:
		if roof.get("buildingId")!=layout.home_building:continue
		var feet:Dictionary=query.standing_point(policy._rooms.room_point(roof))
		if feet.is_empty() or feet.get("buildingId")!=layout.home_building:continue
		var id:int=policy._rooms.component_at(feet)
		if not rooms.has(id):rooms[id]=[]
		rooms[id].append(feet)
	check("pitched new home provides multiple stable structural rooms",rooms.size()>1,rooms.size())
	var unstable:Array=[];var stations:=0
	for points:Array in rooms.values():
		policy=Policy.new();policy.configure(query);policy.sample(points[0],0)
		var signature:String=policy.signature();var cuts:Array=wall_set(policy,query)
		for p:Dictionary in points:
			stations+=1;policy.sample(p,stations*200)
			if signature!=policy.signature() or cuts!=wall_set(policy,query):unstable.append(p)
	check("new pitched house cutaway is stable across all supported room stations",unstable.is_empty() and stations>5,{"stations":stations,"unstable":unstable})
	var before:Dictionary=host.runtime.capture_checkpoint()
	var invalid:Dictionary=await host.start_new_world(-2,"reject-bad-seed")
	check("invalid new-world request cannot alter active world or pointer",not invalid.ok and Data.json_equal(before,host.runtime.capture_checkpoint()) and JSON.parse_string(FileAccess.get_file_as_string(pointer_path))==pointer)
	var reopened:Dictionary=host.store.load_current()
	var expected_facts:Dictionary=JSON.parse_string(JSON.stringify(before.facts,"",true,true))
	check("actual active slot restores the same generated world",reopened.ok and reopened.capture.world.worldId==before.world.worldId and Data.json_equal(reopened.capture.facts,expected_facts),{"saved_time":reopened.get("capture",{}).get("facts",{}).get("time"),"current_time":before.facts.time,"differing_keys":before.facts.keys().filter(func(key:String)->bool:return not Data.json_equal(reopened.get("capture",{}).get("facts",{}).get(key),expected_facts[key]))})
	var reassembled:Dictionary=host._assemble(reopened.capture) if reopened.ok else {"ok":false}
	check("generated save survives the real formal offscreen assembler",reassembled.ok,reassembled.get("reason"))
	var no_reseed:Dictionary=building.prepare_generation(host.world)
	check("revisit does not rebuild houses or refill stocks",not no_reseed.ok and no_reseed.code=="ALREADY_SEEDED",no_reseed)
	test_retained_v2()
	finish()
func test_retained_v2()->void:
	# Explicit old-generation fixture. It must remain the old persisted world
	# through the production codec/assembler, with no decoration or reseeding.
	var old:Dictionary=Assembly.prepare(Rural.generate_settlement(2026,Buildings.generation_profiles(),"rural-2"))
	check("explicit rural-2 fixture still composes with current B/C",old.ok,old.get("reason"))
	if not old.ok:return
	var encoded:Dictionary=Store.encode(old.capture)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	check("old rural-2 decodes through current native codec",decoded.ok,decoded.get("reason"))
	if not decoded.ok:return
	var mounted:Dictionary=host._assemble(decoded.capture)
	check("old rural-2 restores through current formal assembler",mounted.ok,mounted.get("reason"))
	if not mounted.ok:return
	var identity:Dictionary=mounted.world.identity()
	check("restoring rural-2 preserves its exact generation identity",identity.generatorVersion=="rural-2" and identity.worldId=="rural:v2:2026",identity)
	var restored:Dictionary=mounted.world.snapshot()
	var expected:Dictionary=decoded.capture.world.duplicate(true)
	var warming:bool=expected.chunks.values().any(func(chunk:Dictionary)->bool:return not chunk.resident)
	if warming:
		expected.revision+=1
		for key:String in expected.chunks:
			if not expected.chunks[key].resident:
				expected.chunks[key].resident=true;expected.chunks[key].revision=expected.revision
	# Production assembly warms known saved chunks using one real transaction.
	# Require exactly that change; terrain/entities/plans/resources stay exact.
	var changed_keys:Array=restored.keys().filter(func(key:String)->bool:return not Data.json_equal(restored[key],expected.get(key)))
	check("rural-2 restore only warms saved chunks in one transaction; all world content exact",changed_keys.is_empty(),{"differing_keys":changed_keys,"expected_warming":warming})
	var plan:Dictionary=mounted.services.buildings.prepare_generation(mounted.world)
	check("rural-2 revisit cannot rebuild houses or inject rural-3 dressing",not plan.ok and plan.code=="ALREADY_SEEDED",plan.get("reason"))
func wall_set(policy:RefCounted,query:RefCounted)->Array:
	var result:Array=[]
	for piece:Dictionary in query.pieces:
		if policy.cut_wall(piece):result.append(piece.id)
	result.sort();return result
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"scope":"isolated production async entry/native save + actual C/B composition; not formal app acceptance","failed":failed,"checks":checks}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify(report))
	if host!=null:host.free()
	quit(1 if failed else 0)
