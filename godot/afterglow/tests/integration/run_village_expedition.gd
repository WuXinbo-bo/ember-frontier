extends SceneTree
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const Opening = preload("res://scripts/runtime/playtest_profile.gd")
const Native = preload("res://scripts/runtime/native_client.gd")
const Save = preload("res://scripts/storage/native_store.gd")
const E = preload("res://scripts/runtime/village_expedition.gd")
const G = preload("res://scripts/buildings/building_geometry.gd")
const Contact = preload("res://scripts/modules/module_contact.gd")
var host: Node
var runtime: RefCounted
var seed_id := 713
var serial := 0
var total := 0
var errors := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	total += 1
	if not ok: errors += 1
	print("PASS " if ok else "FAIL ", label, " ", details if not ok else "")
	return ok

func send(kind: String, payload: Dictionary = {}, to: Dictionary = {}, target: String = "") -> Dictionary:
	serial += 1
	return runtime.command({"kind":kind,"actor_id":"player","command_id":"expedition-journey:%d" % serial,"payload":payload,"destination":to,"target_id":target})

func travel(point: Dictionary) -> bool:
	var from: Dictionary = G.location(runtime.actor("player"))
	var destination: Dictionary = runtime._services.buildings.current_space().standing_point(point)
	if destination.is_empty():
		print("NO GROUND ", point)
		return false
	var plan: Dictionary = runtime._services.actions.route("player", from, destination)
	if not plan.ok:
		print("NO ROUTE ", from, " ",point," ",plan.get("reason"))
		return false
	for step: Dictionary in plan.steps:
		if step.kind != "move": return false
		for n: int in 70:
			var actor: Dictionary = runtime.actor("player")
			var direction: Vector3 = G.point(step.to)-G.point(actor)
			if Vector2(direction.x,direction.z).length() < 0.06: break
			var at: Dictionary = G.location(actor)
			var stride: Vector2 = Vector2(direction.x,direction.z).limit_length(0.23)
			at.x += stride.x
			at.z += stride.y
			var receipt := send("move",{"movement_dt":0.1},at)
			if not receipt.ok:
				print("MOVE FAILED ",receipt)
				return false
			runtime.tick(.1)
	return E.near(runtime.actor("player"), destination, .40)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_id = int(arg.trim_prefix("--seed="))
	var profiles := Assembly.generation_profiles()
	var opening := Assembly.prepare(Assembly.generate(seed_id, profiles.profiles))
	if not check(opening.ok,"generate ordinary content 21",opening.get("code")): return finish()
	host=Native.new()
	var built: Dictionary = host._assemble(Opening.prepare_opening(opening.capture, "normal"))
	if not check(built.ok,"assemble ordinary new save",built.get("code")): return finish()
	runtime = built.runtime
	if not check(runtime.tool("village:club:player").get("holderId") == "pack:player","club in pack"): return finish()
	var starting_run: Dictionary = runtime.expedition_snapshot()
	check(starting_run.may_depart and starting_run.site_distance > 0, "exploration is available from the ordinary spawn", starting_run)
	check(not send("expedition.open").ok,"no remote trigger")
	var depart := send("expedition.depart",{"escort":"village-resident"})
	if not check(depart.ok,"escort can leave from a new game",depart): return finish()
	if not check(travel(E.SITE),"walk to supply crate on real terrain"): return finish()
	for i: int in 200:
		if E.near(runtime.actor("village-resident"),runtime.actor("player"),2.8): break
		runtime.tick(.1)
	if not check(E.near(runtime.actor("village-resident"),runtime.actor("player"),2.8),"escort reaches the crate",[runtime.expedition_snapshot(), runtime.actor("player"), runtime.actor("village-resident")]): return finish()
	if not check(send("expedition.open").ok,"nearby crate triggers warning"): return finish()
	for i: int in 32: runtime.tick(.1)
	var state: Dictionary = runtime.expedition_snapshot()
	if not check(state.phase == "fighting" and state.remaining == 3,"wave spawns after warning",state): return finish()
	if not check(reload(),"cold reload keeps in-flight actors"): return finish()
	for wave: int in [1,2,3]:
		for i: int in 450:
			if wave == 3: kite()
			runtime.tick(.1)
			state = runtime.expedition_snapshot()
			if state.phase != "fighting" and state.phase != "warning": break
		if not check(state.phase == ("complete" if wave == 3 else "between"),"auto attacks clear wave %d" % wave,state): return finish()
		if wave < 3:
			check(state.bow and state.weapon == "bow","bow can fight before settlement")
			var next := send("expedition.next",{"perk":"tempo" if wave == 1 else "guard"})
			if not check(next.ok,"advance wave with upgrade",next): return finish()
	check(runtime.facts().ledger.any(func(e: Dictionary) -> bool: return e.get("weapon") == "bow"),"ranged auto hits recorded")
	check(runtime.facts().ledger.any(func(e: Dictionary) -> bool: return e.get("actor_id") == "village-resident" and e.get("weapon") == "club"),"escort automatically attacks")
	if not E.near(runtime.actor("player"),E.SITE,2.8):
		check(travel(E.SITE),"return to supply site after kiting")
	check(send("expedition.retreat").ok,"retreat accepted")
	check(not send("expedition.extract").ok,"no remote reward")
	if not check(travel(E.EXIT),"walk back to extraction"): return finish()
	var receipt := send("expedition.extract")
	if not check(receipt.ok,"commit extraction",receipt): return finish()
	check(runtime.tool(E.BOW_ID).get("holderId") == "pack:player" and float(runtime.actor("player").pack.get("scrap", 0)) == 9,"bow and finite scrap reach pack")
	check(not runtime.actor("village-resident").get("expedition_follow",false) and runtime.world.extension(E.KEY).perks.is_empty(),"escort released and temporary perks removed")
	check(not send("expedition.extract").ok,"duplicate extraction rejected")
	check(reload() and runtime.tool(E.BOW_ID).get("holderId") == "pack:player","reward survives cold reload")
	check_early_return_and_failure()
	if seed_id == 713:
		check_outer_patrol()
	else:
		check_preparation()
	finish()

func check_early_return_and_failure() -> void:
	if not check(send("expedition.depart").ok,"can explore again solo with a recovered bow"): return
	if not check(travel(E.SITE),"repeat expedition reaches the site"): return
	if not check(send("expedition.open").ok,"repeat run has a fresh warning"): return
	for i: int in 200:
		runtime.tick(.1)
		if runtime.expedition_snapshot().phase == "between": break
	if not check(runtime.expedition_snapshot().phase == "between","solo player can survive the first wave with the bow"): return
	if not check(send("expedition.retreat").ok and travel(E.EXIT) and send("expedition.extract").ok,"one-wave retreat settles on foot"): return
	check(float(runtime.actor("player").pack.get("scrap",0)) == 9,"replaying known loot does not print resources")
	if not check(travel(E.SITE) and send("expedition.open").ok and runtime.expedition_snapshot().phase == "warning","walking directly to the crate opens a solo run"): return
	var capture: Dictionary = runtime.capture_checkpoint()
	for a: Dictionary in capture.facts.actors:
		if a.id == "player":
			a.hp = 1.0
			a.cooldown = 18.0
	var opened: Dictionary = host._assemble(capture)
	if not check(opened.ok,"near-death checkpoint cold mounts",opened.get("code")): return
	runtime.retire()
	runtime = opened.runtime
	for i: int in 200:
		runtime.tick(.1)
		if runtime.expedition_snapshot().phase == "idle": break
	var state: Dictionary = runtime.expedition_snapshot()
	check(state.phase == "idle" and state.result.contains("遗失") and E.near(runtime.actor("player"), E.EXIT, 3),"knockout returns to village and drops this run",state)
	check(runtime.tool(E.BOW_ID).get("holderId") == "pack:player" and float(runtime.actor("player").pack.get("scrap",0)) == 9,"failure preserves previously owned rewards")

func check_preparation() -> void:
	if not check(not send("expedition.prepare", {"preparation":"tipped"}).ok,"unrepaired warehouse blocks expedition supplies"): return
	# Isolate the battle-to-village handoff from the long forestry journey.
	# The fixture supplies construction inputs. The player still pays for and
	# performs the restoration, and spends only scrap earned during the raid.
	var capture: Dictionary = runtime.capture_checkpoint()
	var warehouse: Dictionary = runtime._services.modules.instance(E.WAREHOUSE)
	var player: Dictionary = capture.facts.actors.filter(func(actor: Dictionary) -> bool: return actor.id == "player")[0]
	for item: String in warehouse.restoration.cost:
		if item != "scrap": player.pack[item] = maxf(float(player.pack.get(item, 0)), float(warehouse.restoration.cost[item]))
	player.pack["log"] = 4.0
	var hammer: String = ""
	for tool: Dictionary in capture.world.extensions["r3:production"].tools:
		if tool.kind == "hammer" and str(tool.get("holderId", "")).contains("workshop"):
			hammer = tool.id
			tool.holderId = "pack:player"
			break
	if hammer.is_empty():
		for tool: Dictionary in capture.world.extensions["r3:production"].tools:
			if tool.kind == "hammer":
				hammer = tool.id
				tool.holderId = "pack:player"
				break
	var mounted: Dictionary = host._assemble(capture)
	if not check(mounted.ok,"mount paid-repair fixture after the natural expedition",mounted.get("reason")): return
	runtime.retire()
	runtime = mounted.runtime
	var restore := send("module.restore", {"source_id":"pack:player", "tool_id":hammer}, {}, E.WAREHOUSE)
	if not check(restore.ok,"returned scrap can pay for warehouse restoration",restore): return
	for i: int in 1100:
		runtime.tick(.1)
		if runtime._services.modules.instance(E.WAREHOUSE).status == "operational": break
	if not check(runtime._services.modules.instance(E.WAREHOUSE).status == "operational","warehouse is operational before preparation"): return
	var workshop: Dictionary = runtime._services.modules.instance(E.WORKSHOP)
	var nearby := false
	for port: Dictionary in Contact.points(runtime._services.buildings.current_space(), G.location(runtime.actor("player")), workshop):
		if travel(port):
			nearby = true
			break
	if not check(nearby,"walk to workshop for the next expedition"): return
	var input: Dictionary = runtime.stock(workshop.stock_refs.input)
	if not check(travel(input.location) and send("deposit", {"items":{"log":4}}, {}, input.id).ok,"put raw logs in the actual workshop input",input): return
	var order := send("module.recipe.configure", {"recipe_id":"r34:saw_timber_v2", "order_id":E.WORKSHOP+":board-stock", "mode":"target", "target_item":"timber", "target_quantity":4}, {}, E.WORKSHOP)
	if not check(order.ok,"set the workshop's normal target of four boards",order): return
	for i: int in 500:
		runtime.tick(.1)
		if float(runtime.stock(workshop.stock_refs.output).items.get("timber",0)) >= 4: break
	check(float(runtime.stock(workshop.stock_refs.output).items.get("timber",0)) == 4,"companion physically stocks four boards at the workshop",runtime.stock(workshop.stock_refs.output))
	var before: float = float(runtime.actor("player").pack.get("scrap", 0))
	var prep := send("expedition.prepare", {"preparation":"tipped"})
	if not check(prep.ok and float(runtime.actor("player").pack.get("scrap",0)) == before - 3,"workshop crafts tipped arrows for 3 recovered scrap",prep): return
	check(not send("expedition.prepare", {"preparation":"medical"}).ok,"same run cannot be prepared or charged twice")
	if not check(reload() and runtime.expedition_snapshot().prepared == "tipped","preparation survives save and reload"): return
	if not check(travel(E.SITE) and send("expedition.open").ok,"begin the next expedition with the preparation"): return
	for i: int in 36: runtime.tick(.1)
	var run: Dictionary = runtime.world.extension(E.KEY)
	check(run.phase == "fighting" and run.perks.has("pierce") and run.get("prepared", "").is_empty(),"first wave applies the preparation once",run)

func check_outer_patrol() -> void:
	check(runtime.actor_states().all(func(actor: Dictionary) -> bool: return actor.get("faction") != "infected"), "the home region stays clear before visiting the outskirts")
	var exterior: Dictionary = {}
	var space: RefCounted = runtime._services.buildings.current_space()
	for stock: Dictionary in runtime.facts().stocks:
		var location: Dictionary = stock.get("location", {})
		if stock.get("module_id", "").is_empty() or location.get("regionId", "RH-HOME") == "RH-HOME":
			continue
		for offset: Vector2 in [Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0), Vector2(0, -12)]:
			var point: Dictionary = location.merged({"x":float(location.x) + offset.x,"z":float(location.z) + offset.y,"buildingId":null,"storeyId":null}, true)
			var feet: Dictionary = space.standing_point(point)
			if not feet.is_empty() and feet.regionId == location.regionId:
				exterior = feet
				break
		if not exterior.is_empty():
			break
	if not check(not exterior.is_empty(), "generated outskirts include a legal approach to an exterior facility"):
		return
	# Start at an actual outdoor stand to exercise encounter admission without
	# making an arbitrary cross-region path part of this combat regression.
	var capture: Dictionary = runtime.capture_checkpoint()
	for actor: Dictionary in capture.facts.actors:
		if actor.id == "player":
			actor.merge(exterior, true)
			break
	var mounted: Dictionary = host._assemble(capture)
	if not check(mounted.ok, "outskirts approach mounts on actual terrain", mounted.get("reason")):
		return
	runtime.retire()
	runtime = mounted.runtime
	for step: int in 35:
		runtime.tick(.1)
	var encounter: Dictionary = runtime.world.extension("r33:gameplay").get("opening_walkers", {})
	var roster: Array = encounter.get("actors", [])
	if not check(roster.size() in [1, 2], "visiting the exterior facility brings back a finite old patrol", encounter):
		return
	check(roster.all(func(id: String) -> bool:
		var actor: Dictionary = runtime.actor(id)
		return actor.get("faction") == "infected" and actor.get("patrol_region") == exterior.regionId and actor.get("regionId") == exterior.regionId), "outskirts infected stay assigned to their exterior region")
	check(reload() and runtime.world.extension("r33:gameplay").get("opening_walkers", {}).get("actors", []) == roster, "one patrol roster survives save and reload")

func kite() -> void:
	var player: Dictionary = runtime.actor("player")
	var closest := 3.8
	var danger := Vector3.ZERO
	for enemy: Dictionary in runtime.actor_states():
		if not enemy.get("expedition_enemy",false) or float(enemy.hp) <= 0: continue
		var distance: float = G.point(enemy).distance_to(G.point(player))
		if distance < closest:
			closest = distance
			danger = G.point(enemy) - G.point(player)
	if danger.is_zero_approx(): return
	var angle := atan2(-danger.z,-danger.x)
	for index: int in 7:
		var heading := angle + float(index / 2 + 1)*0.5*float(1 if index % 2 == 0 else -1) if index > 0 else angle
		var at := G.location(player)
		at.x += cos(heading)*.22
		at.z += sin(heading)*.22
		if not E.near(at,E.SITE,12): continue
		if send("move",{"movement_dt":0.1},at).ok: return

func reload() -> bool:
	var encoded := Save.encode(runtime.capture_checkpoint())
	var decoded := Save.decode(encoded.get("text","")) if encoded.ok else encoded
	var opened: Dictionary = host._assemble(decoded.capture) if decoded.ok else decoded
	if not opened.ok:
		print("RELOAD FAILED ", opened)
		return false
	runtime.retire()
	runtime = opened.runtime
	return true

func finish() -> void:
	if runtime != null: runtime.retire()
	if host != null: host.free()
	print("EXPEDITION CHECKS ", total-errors,"/",total, " seed ",seed_id)
	quit(1 if errors > 0 else 0)
