extends "res://tests/integration/run_gameplay.gd"
## Target selection and contact timing through the real command and spatial authorities.
const Geo = preload("res://scripts/buildings/building_geometry.gd")
const Draft = preload("res://scripts/actions/domain_draft.gd")
const AXE := "fixture:axe"
const FAR := "infected:village-road:1"
const NEAR := "infected:village-road:0"
var events: Array[Dictionary] = []

func attack(target: String, manual: bool = true) -> Dictionary:
	return request("attack", target, {"tool_id": AXE, "manual_aim": manual, "aim": {"x": 32.0, "y": 0.0, "z": -9.0}})

func listen() -> void:
	events.clear()
	runtime.changed.connect(func(change: Dictionary) -> void:
		for event: Dictionary in change.get("events", []):
			if event.get("actor_id") == "player": events.append(event.duplicate(true)))

func player_events(kind: String) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event.kind == kind)

func mount(snapshot: Dictionary) -> bool:
	var mounted: Dictionary = host._assemble(snapshot)
	check("mount combat fixture", mounted.ok, mounted.get("reason"))
	if not mounted.ok: return false
	runtime = mounted.runtime
	listen()
	return true

func insert_wall() -> bool:
	var actor: Dictionary = runtime.actor("player")
	var midpoint := Geo.point(actor).lerp(Geo.point(runtime.actor(FAR)), 0.5)
	var wall := {"id": "fixture:melee-wall", "kind": "prop", "regionId": actor.regionId, "revision": 0,
		"position": Geo.json_point(midpoint), "bounds": Geo.json_box(AABB(midpoint + Vector3(-0.08, 0, -0.025), Vector3(0.16, 1.8, 0.05))),
		"data": {"solid": true, "opaque": false}}
	var tx := Draft.new(runtime._services.gameplay.context)
	tx.extra.append({"op": "entity.put", "id": wall.id, "before_exists": false, "before": null, "after": wall})
	var result: Dictionary = runtime._commit(tx.result())
	check("commit thin transparent solid between the actors", result.ok, result)
	return result.ok

func run() -> void:
	var output:String=OS.get_cmdline_user_args()[0]
	var world:=World.new();check("finite rural source loaded",world.load_snapshot(Rural.generate(713)).ok)
	var temporary_runtime:=Runtime.new()
	var b:=Building.new();b.configure({"world":world,"runtime":temporary_runtime})
	var seed:Dictionary=b.seed_rural(world)
	check("B actual rural buildings seeded",seed.ok,seed.get("reason"))
	if not seed.ok:finish(output);return
	var facts:Dictionary=Initial.facts(seed)
	# Fixture starts on the real village road with one running exploration and a
	# real unique axe. We do not call this fixture a completed travel route.
	facts.actors[0].merge({"x":32.0,"y":0.0,"z":-11.2,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null,"stamina":100.0},true)
	check("explicit initial fixture facts validate",Runtime.validate_facts(facts).ok,facts if not Runtime.validate_facts(facts).ok else null)
	var gameplay:Dictionary=Gameplay.initial()
	gameplay.exploration.merge({"status":"running","run_id":"fixture-run"},true)
	var production:Dictionary=Initial.production(seed)
	production.tools.append({"id":"fixture:axe","kind":"salvaged_axe","holderId":"pack:player","durability":90.0})
	var changes:Array=seed.world_changes.duplicate(true)
	changes.append_array([{"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":production},{"op":"extension.set","id":Gameplay.KEY,"before_exists":false,"before":null,"after":gameplay},{"op":"extension.set","id":"r3:structure-orders","before_exists":false,"before":null,"after":{"version":1,"orders":[]}}])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision());check("combined fixture prepares",draft.ok,draft.get("reason"))
	if not draft.ok:finish(output);return
	check("fixture commit",world.commit_prepared(draft.capability).ok)
	host=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":facts,"source":{"test":"isolated integration"}})
	check("actual formal client assembles all real services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:finish(output);return
	runtime=assembled.runtime
	runtime.tick(0.1)
	if runtime.actor(FAR).is_empty() or runtime.actor(NEAR).is_empty():
		check("spawn two real infected", false); finish(output); return
	var positions := Draft.new(runtime._services.gameplay.context)
	var near_actor: Dictionary = positions.actor(NEAR)
	var far_actor: Dictionary = positions.actor(FAR)
	near_actor.x = 31.35
	near_actor.z = -10.55
	far_actor.x = 32.0
	far_actor.z = -9.7
	check("place a nearer distractor and farther chosen target on the actual road", runtime._commit(positions.result()).ok)
	var baseline: Dictionary = runtime.capture_checkpoint()
	listen()
	var stamina: float = runtime.actor("player").stamina
	check("missing explicit target is rejected", attack("fixture:missing").get("code") == "TARGET_UNAVAILABLE")
	check("start an explicit swing at the farther target", attack(FAR).ok)
	check("windup publishes with stamina, wear and target health intact", player_events("combat-windup").size() == 1 and runtime.actor("player").stamina == stamina and runtime.tool(AXE).durability == 90.0 and runtime.actor(FAR).hp == 48.0)
	check("repeat during windup is rejected", attack(NEAR).get("code") == "COOLDOWN")
	var encoded: Dictionary = Store.encode(runtime.capture_checkpoint())
	var restored: Dictionary = Store.decode(encoded.get("text", ""))
	check("checkpoint encodes the pending contact", restored.ok, restored.get("reason"))
	if not restored.ok or not mount(restored.capture): finish(output); return
	runtime.tick(0.1)
	var hits := player_events("combat-hit")
	check("first fixed contact after load hits only the farther explicit target", hits.size() == 1 and hits[0].target_id == FAR and hits[0].primary_hit and runtime.actor(FAR).hp == 30.0 and runtime.actor(NEAR).hp == 48.0, hits)
	check("contact charges wear and starts recovery", is_equal_approx(float(runtime.tool(AXE).durability), 89.6) and attack(NEAR).get("code") == "COOLDOWN")
	for i: int in 5: runtime.tick(0.1)
	check("additional ticks never repeat the same contact", player_events("combat-hit").size() == 1 and is_equal_approx(float(runtime.tool(AXE).durability), 89.6))

	if not mount(baseline): finish(output); return
	check("air swing starts even when enemies are nearby", attack("").ok)
	runtime.tick(0.1)
	var misses := player_events("combat-miss")
	check("air swing reports a single miss with zero damage", player_events("combat-hit").is_empty() and misses.size() == 1 and misses[0].code == "SWING_EMPTY" and misses[0].contact and is_equal_approx(float(misses[0].aim.z), 1.0) and runtime.actor(NEAR).hp == 48.0)

	if not mount(baseline): finish(output); return
	if insert_wall():
		check("a transparent solid forbids starting contact", attack(FAR).get("code") == "ATTACK_BLOCKED" and player_events("combat-windup").is_empty())
	if not mount(baseline): finish(output); return
	check("start swing with clear contact path", attack(FAR).ok)
	if insert_wall():
		runtime.tick(0.1)
		misses = player_events("combat-miss")
		check("a wall added during windup blocks damage without retarget", player_events("combat-hit").is_empty() and misses.size() == 1 and misses[0].code == "ATTACK_BLOCKED")

	if not mount(baseline): finish(output); return
	check("start swing while the real equipped tool is available", attack(FAR).ok)
	var removed_tool_tx := Draft.new(runtime._services.gameplay.context)
	var tools: Array = removed_tool_tx.extension("r3:production").tools
	var old_tool: Dictionary = Draft.find(tools, AXE)
	tools.erase(old_tool)
	var removed: Dictionary = runtime._commit(removed_tool_tx.result())
	check("remove the real tool before contact", removed.ok, removed)
	if removed.ok:
		runtime.tick(0.1)
		misses = player_events("combat-miss")
		check("unavailable tool cancels contact and leaves stamina intact", player_events("combat-hit").is_empty() and misses.size() == 1 and misses[0].code == "MISSING_TOOL" and not misses[0].contact and is_equal_approx(float(runtime.actor("player").stamina), stamina), {"hits": player_events("combat-hit"), "misses": misses, "stamina": runtime.actor("player").stamina, "before": stamina})

	if not mount(baseline): finish(output); return
	check("legacy untargeted attack remains accepted", attack("", false).ok)
	hits = player_events("combat-hit")
	check("legacy untargeted attack retains its nearest-target behavior", hits.size() == 1 and hits[0].target_id == NEAR, hits)

	if not mount(baseline): finish(output); return
	var tx := Draft.new(runtime._services.gameplay.context)
	tx.extension(Gameplay.KEY).exploration.upgrades = ["chain"]
	var committed: Dictionary = runtime._commit(tx.result())
	check("install explicit chain upgrade fixture", committed.ok, committed)
	check("legacy synchronous attack remains accepted", attack(FAR, false).ok)
	hits = player_events("combat-hit")
	check("chain hits the requested target first and adds one target", hits.size() == 2 and hits[0].target_id == FAR and hits[0].primary_hit and hits[1].target_id == NEAR and not hits[1].primary_hit, hits)
	check("chain charges stamina and wear exactly once", is_equal_approx(stamina - float(runtime.actor("player").stamina), 14.0) and is_equal_approx(float(runtime.tool(AXE).durability), 89.6))
	finish(output)
