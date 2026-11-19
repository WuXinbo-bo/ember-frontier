extends SceneTree
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
var failures: Array = []
var checks: Array = []
var world := World.new()
var building := Building.new()
var actions := Actions.new()
var production := Production.new()
var runtime := Runtime.new()
var sequence := 0

func expect(label: String, condition: bool, evidence: Variant = null) -> void:
	checks.append({"label": label, "ok": condition, "evidence": evidence})
	if not condition: failures.append(label); print("FAIL ", label, " ", JSON.stringify(evidence))

func resident(id: String, p: Dictionary) -> Dictionary:
	var a := {"id": id, "name": id, "hp": 100.0, "hunger": 100.0, "thirst": 100.0, "fatigue": 0.0, "stamina": 100.0, "pack": {}, "skills": {"gathering": 0.0, "crafting": 2.0}, "relationship": {"member": id == "player", "consent": id == "player"}, "intent": null}
	a.merge(p, true)
	return a

func command(kind: String, target: String = "", payload: Dictionary = {}, destination: Dictionary = {}) -> Dictionary:
	sequence += 1
	return runtime.command({"command_id": "bbb-test:" + str(sequence), "actor_id": "player", "kind": kind, "target_id": target, "payload": payload, "destination": destination, "expected_revision": runtime.get_revision()})

func initialize_at(p: Dictionary, extras: Array = [], stocks: Array = []) -> void:
	var result := runtime.configure({"world": world, "services": {"buildings": building, "production": production, "actions": actions}, "facts": {"time": 0.0, "status": "playing", "actors": [resident("player", p)] + extras, "stocks": stocks, "actions": [], "quests": []}})
	expect("runtime configured", result.ok, result)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_msec()
	var loaded := world.load_snapshot(Generator.generate(713))
	expect("real C rural world valid", loaded.ok, loaded)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded := building.seed_rural(world)
	expect("B rural seed produces actual ops", seeded.ok and seeded.world_changes.size() > 400, seeded.get("reason"))
	if not seeded.ok: finish(started); return
	var bad_cas: Array = []
	for op in seeded.world_changes:
		var before: Variant = world.extension(str(op.id)) if op.op == "extension.set" else world.entity(str(op.id))
		if before is Dictionary and before.is_empty() and not op.before_exists: before = null
		if before != op.before: bad_cas.append({"id": op.id, "op": op.op, "exists": world.has_extension(str(op.id)) if op.op == "extension.set" else not world.entity(str(op.id)).is_empty()})
	print("CAS_DIAGNOSTIC ", JSON.stringify(bad_cas))
	var prepared := world.prepare_changes(seeded.world_changes, world.get_revision())
	expect("C accepts full buildings proposal", prepared.get("ok", false), {"code": prepared.get("code"), "reason": prepared.get("reason")})
	if not prepared.get("ok", false): finish(started); return
	var seeded_facts := runtime.facts(); seeded_facts.stocks = seeded.initial_stocks
	var safety := building.validate_world_draft(prepared.view, seeded_facts, seeded.world_changes)
	expect("all rural pieces supported and unoccupied", safety.ok, safety)
	if not safety.ok: finish(started); return
	expect("atomic C capability commits seed", world.commit_prepared(prepared.capability).ok)
	initialize_at(seeded.spawn_points.player, [], seeded.initial_stocks)
	var state := Production.empty_state(); state.tools = seeded.initial_tools; state.records = seeded.initial_records
	var p := world.prepare_changes([building.extension_change(Production.KEY, state)], world.get_revision())
	expect("production initial data accepted", p.ok and world.commit_prepared(p.capability).ok)
	expect("repeat seed rejected", not building.seed_rural(world).ok)
	var home := "rural:v1:RH-HOME:old-house"
	expect("no free home workbench", building.structures().instances.filter(func(v: Dictionary) -> bool: return v.definitionId == "workbench" and v.buildingId == home).is_empty())
	var q: RefCounted = building.current_space()
	expect("outside feet supported", not q.standing_point(Geometry.location(runtime.actor("player"))).is_empty())
	var from := Geometry.location(runtime.actor("player"))
	var target := from.duplicate(true); target.x = 29.8
	expect("ordinary direct movement commits", command("move", "", {}, target).ok)
	var home_pad := {"x":20.15,"y":0,"z":38.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(home_pad, [], seeded.initial_stocks)
	var door := home + ":front-door"
	var availability := actions.availability({"actor_id":"player","kind":"door","target_id":door,"payload":{"operation":"open"}})
	expect("front door actual outside pad available", availability.ok, availability)
	var open := command("door", door, {"operation":"open"})
	expect("door queues .4s real work", open.ok and not building.instance(door).door.open, open)
	for n in range(4): runtime.tick(0.1)
	expect("door opens after unified time", building.instance(door).door.open)
	var snapshot := world.snapshot()
	var blocker := resident("blocker", {"x":19,"y":0,"z":38.8,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	initialize_at(home_pad, [blocker], seeded.initial_stocks)
	var close := command("door", door, {"operation":"close"})
	expect("living actor in sweep rejected", not close.ok, close)
	expect("failed sweep leaves world unchanged", world.snapshot() == snapshot)
	# Every definition and runtime fact remains isolated from returned query values.
	var copy := building.instance(door); copy.hp = 0
	expect("returned instance is isolated", float(building.instance(door).hp) > 0)
	var inside := {"x":18,"y":0,"z":36,"regionId":"RH-HOME","buildingId":home,"storeyId":home+":ground"}
	initialize_at(inside, [], seeded.initial_stocks)
	var path: Dictionary = building.current_space().route("player", inside, home_pad)
	expect("native AStar route through opened real entrance", path.ok, {"code":path.get("code"),"reason":path.get("reason"),"steps":path.get("steps",[]).size()})
	var zero: Dictionary = building.current_space().route("player", inside, inside)
	expect("zero distance route is safe", zero.ok and zero.steps.is_empty(), zero)
	production_cases(seeded)
	construction_cases(seeded)
	view_case()
	npc_cases(seeded)
	finish(started)

func production_cases(seeded: Dictionary) -> void:
	var shed := "rural:v1:RH-HOME:shed"
	initialize_at({"x":8,"y":0,"z":16,"regionId":"RH-HOME","buildingId":shed,"storeyId":shed+":ground"}, [], seeded.initial_stocks)
	expect("unknown stock transfer rejected", not command("take",shed+":storage",{"items":{"timber":1}}).ok)
	expect("search begins real timed action",command("search",shed+":storage").ok)
	for n in range(10): runtime.tick(0.1)
	expect("search opens actual stock fact",runtime.stock(shed+":storage").searched)
	var take:=command("take",shed+":storage",{"items":{"book_woodwork":1,"book_tool_repair":1,"timber":8,"scrap":6},"tool_ids":[shed+":hand_saw",shed+":hammer",shed+":salvaged_axe"]})
	expect("book tools materials transfer atomically",take.ok,take.get("reason"))
	expect("actual record follows physical book",DraftRecord(shed+":record:woodwork").holderId=="pack:player")
	expect("study starts from actual carried record",command("study",shed+":record:woodwork",{"record_id":shed+":record:woodwork"}).ok)
	expect("active book cannot move",not command("deposit",shed+":storage",{"items":{"book_woodwork":1}}).ok)
	for n in range(120): runtime.tick(0.1)
	expect("knowledge granted after actual work",production.state().knowledge.get("player",[]).has("basic_woodwork"))
	expect("study does not consume physical book",float(runtime.actor("player").pack.get("book_woodwork",0))==1)
	expect("completed study record source can move",command("deposit",shed+":storage",{"items":{"book_woodwork":1}}).ok)
	expect("inactive study source follows record holder",production.state().orders.filter(func(o:Dictionary)->bool:return o.kind=="study")[0].sourceId==shed+":storage")
	# Near tree use actor's real pack and actual C-created ground drop.
	var tree: Dictionary=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")[0]
	var pack: Dictionary=runtime.actor("player").pack.duplicate(true)
	var p:=Geometry.location(tree);p.z+=1.2
	var a:=resident("player",p);a.pack=pack
	var facts:=runtime.facts();facts.actors=[a]
	runtime.configure({"world":world,"services":{"buildings":building,"production":production,"actions":actions},"facts":facts})
	var tool: String=shed+":salvaged_axe"
	var initial_wear: float=runtime.tool(tool).durability
	var harvest:=command("harvest",tree.id,{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":[tool],"held":true})
	expect("harvest requires actual tree and drop",harvest.ok,harvest.get("reason"))
	for n in range(5): runtime.tick(0.1)
	expect("held release accepted",command("held","",{"held":false}).ok)
	var elapsed: float=production.state().orders[-1].elapsed
	for n in range(10): runtime.tick(0.1)
	expect("release preserves work without remote progress",production.state().orders[-1].elapsed==elapsed)
	expect("held resumes same order",command("held","",{"held":true}).ok)
	for n in range(235): runtime.tick(0.1)
	expect("tree becomes real stump after labor",world.entity(tree.id).data.harvest.phase=="stump")
	expect("logs land in actual ground stock",float(runtime.stock(tree.data.outputId).items.get("log",0))==3)
	expect("no automatic logs in player pack",float(runtime.actor("player").pack.get("log",0))==0)
	expect("axe wears exact six points",absf(initial_wear-float(runtime.tool(tool).durability)-6)<0.0001)

func DraftRecord(id:String)->Dictionary:
	for record in production.state().records:
		if record.id==id:return record
	return {}

func construction_cases(_seeded:Dictionary)->void:
	var facts:=runtime.facts()
	var actor:Dictionary=facts.actors[0]
	var p:Dictionary={"x":21,"y":0,"z":42.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	actor.merge(p,true);actor.intent=null;actor.stamina=100
	actor.pack.timber=8;actor.pack.scrap=6
	runtime.configure({"world":world,"services":{"buildings":building,"production":production,"actions":actions},"facts":facts})
	var target:=building.make_instance("workbench","bbb-test:bench",{"x":21,"y":0,"z":44,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var request:Dictionary={"kind":"place","instance":target,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer","held":true}
	var start:=command("structure",target.id,request)
	expect("workbench starts using real tool and source",start.ok,start.get("reason"))
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	expect("materials held not consumed at start",float(before.timber)==8)
	for n in range(5):runtime.tick(0.1)
	expect("construction can cancel",command("cancel_work").ok)
	expect("cancel retains physical material",runtime.actor("player").pack==before)
	expect("cancel produces no building",building.instance(target.id).is_empty())
	var second:=command("structure",target.id,request)
	expect("released holds allow new construction",second.ok,second.get("reason"))
	for n in range(200):runtime.tick(0.1)
	expect("completed workbench is in same world",not building.instance(target.id).is_empty())
	var cost:Dictionary=building.geometry.definitions.workbench.cost
	expect("construction consumes exact source cost once",float(runtime.actor("player").pack.timber)==8-float(cost.get("timber",0)) and float(runtime.actor("player").pack.scrap)==6-float(cost.get("scrap",0)))
	# Explicit finite recipe fixture. The no-added-items opening route is tested
	# separately. Bracket keys preserve the serialized String item identity;
	# assigning a new .log key creates StringName and correctly fails A validation.
	var source:=runtime.facts();source.actors[0].pack["log"]=1
	var craft_setup:=runtime.configure({"world":world,"services":{"buildings":building,"production":production,"actions":actions},"facts":source})
	expect("craft input fixture configured",craft_setup.ok,{"receipt":craft_setup,"requested_facts":source,"actual_actor":runtime.actor("player")})
	var crafted:=command("craft",target.id,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":["rural:v1:RH-HOME:shed:hand_saw"]})
	expect("learned craft starts at actual new station",crafted.ok,{"receipt":crafted,"pack":runtime.actor("player").pack,"reserved_log":production.reserved("pack:player","log"),"orders":production.state().orders})
	var timber_before:float=runtime.actor("player").pack.timber
	for n in range(100):runtime.tick(0.1)
	expect("aliased source/output conserves recipe",float(runtime.actor("player").pack.get("log",0))==0 and float(runtime.actor("player").pack.timber)==timber_before+4)
	var saved:=world.snapshot();var saved_facts:=runtime.facts()
	var second_world:=World.new();expect("world with construction restores",second_world.load_snapshot(saved).ok)
	expect("saved facts remain JSON safe",JSON.parse_string(JSON.stringify(saved_facts)) is Dictionary)

func view_case()->void:
	var view:Node3D=building.create_view({"runtime":runtime})
	root.add_child(view)
	expect("view batches actual building geometry",view.static_nodes.size()>0,{"batches":view.static_nodes.size(),"objects":view.objects.size(),"doors":view.doors.size()})
	var expected_materials:Array=view.manifest.textures.keys()+["glass"]
	# The renderer intentionally allocates textures on first real use. Prove
	# every registered binding through that same accessor, not eager allocation.
	var missing:Array=[]
	for id:String in expected_materials:
		var bound:StandardMaterial3D=view.material(id)
		if bound==null or (id!="glass" and bound.albedo_texture==null):missing.append(id)
	expect("all registered original and reused dressing textures plus glass bind on demand",missing.is_empty(),missing)
	expect("original GLB furniture instantiated",view.objects.size()>5)
	view.free()

func npc_cases(_seeded:Dictionary)->void:
	var data:=runtime.facts();data.actors[0].intent=null
	data.actors[0].merge({"x":32,"y":0,"z":1,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
	var friend:=resident("friend",{"x":32,"y":0,"z":-2,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null})
	friend.relationship={"member":true,"consent":true};friend.job="follow"
	data.actors.append(friend)
	runtime.configure({"world":world,"services":{"buildings":building,"production":production,"actions":actions},"facts":data})
	var before:=Geometry.location(runtime.actor("friend"))
	for i in 45:runtime.tick(0.1)
	var after:=Geometry.location(runtime.actor("friend"))
	expect("consenting NPC follows through real region portal",after.regionId=="RH-HOME" and Geometry.point(after).distance_to(Geometry.point(before))>1,{"before":before,"after":after,"activity":runtime.actor("friend").get("activity"),"intent":runtime.actor("friend").get("intent")})
	var a:Dictionary=runtime.actor("player");var dest:=Geometry.location(a);dest.z=-0.2
	# A world command may not teleport across the full region boundary.
	expect("long teleport still rejected",not actions.prepare({"kind":"move","actor_id":"player","destination":{"x":45,"y":0,"z":-40,"regionId":"RH-VILLAGE"}}).ok)

func finish(started: int) -> void:
	var result := {"scope":"BBB headless domain check on real C world/A runtime, not formal app or visual acceptance", "ok":failures.is_empty(),"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
