extends RefCounted
## Old-village defense on the existing clock, movement, inventory and combat authority.
const G = preload("res://scripts/buildings/building_geometry.gd")
const Expedition = preload("res://scripts/runtime/village_expedition.gd")
const Draft = preload("res://scripts/actions/domain_draft.gd")
const KEY = "village:night-defense"
const HOME = "RH-HOME"
const OLD_HOME = "r34:generated:RH-HOME:home"
const WAREHOUSE = "r34:generated:RH-HOME:village-warehouse"
const PREVIEW_SECONDS = 12.0
const NEXT_EVENING_SECONDS = 540.0
const WAVE_TIMEOUT = 100.0
const DEFENSE_CHOICES = {"force":"重击 · 木棒击退更远", "tempo":"快手 · 出手更快", "reach":"横扫 · 木棒攻击更远"}
const DAWN_REWARDS = {"materials":"建材包 · 木材 +6", "crew":"同伴历练 · 两人熟练度 +2", "supplies":"补给包 · 食物 +4、饮水 +4"}

static func initial() -> Dictionary:
	return {"phase":"dormant", "night":1, "wave":0, "roster":[], "perks":[], "escort":"", "damage":{}, "next_at":0.0, "heading":0, "secured":0}

static func snapshot(host) -> Dictionary:
	return host.context.world.extension(KEY) if host.context.world.has_extension(KEY) else initial()

static func busy(run: Dictionary) -> bool:
	return run.get("phase") in ["warning", "fighting", "between"]

static func at_home(player: Dictionary) -> bool:
	return not player.is_empty() and player.get("regionId") == HOME

static func check(host, request: Dictionary) -> Dictionary:
	if str(request.get("actor_id", "player")) != "player":
		return host._no("FORBIDDEN", "由主角安排守夜")
	var run := snapshot(host)
	var player: Dictionary = host.context.actor.call("player")
	if not at_home(player) or float(player.get("hp", 0)) <= 0:
		return host._no("RETURN_HOME", "先返回旧村")
	var payload: Dictionary = request.get("payload", {})
	match str(request.kind):
		"night.start":
			if run.phase != "ready": return host._no("NIGHT_NOT_READY", "等到黄昏预警后再迎战")
			if Expedition.snapshot(host).phase != "idle": return host._no("EXPEDITION_ACTIVE", "先结束这趟出征")
		"night.next":
			if run.phase != "between" or not perks_to_offer(run).has(payload.get("perk")):
				return host._no("CHOICE_UNAVAILABLE", "选择一个当前可用的强化")
		"night.reward":
			if run.phase != "dawn" or not rewards_to_offer(run).has(payload.get("reward")):
				return host._no("CHOICE_UNAVAILABLE", "当前没有这份战后补给")
		_:
			return host._no("UNKNOWN_COMMAND", "未知守夜操作")
	return host._ok()

static func execute(host, tx: RefCounted, request: Dictionary) -> Dictionary:
	var run: Dictionary = tx.extension(KEY, initial())
	var now: float = host.context.clock.call()
	match str(request.kind):
		"night.start":
			begin_wave(tx, run, now)
		"night.next":
			run.perks.append(str(request.payload.perk))
			run.wave = int(run.wave) + 1
			begin_wave(tx, run, now)
		"night.reward":
			var reward_id: String = request.payload.reward
			var items: Dictionary = {"materials":{"timber":6}, "crew":{"scrap":2}, "supplies":{"food":4,"water":4}}[reward_id]
			if int(run.secured) == 0:
				items = {"timber":2, "food":2, "water":2}
			if not tx.stock_delta("pack:player", items):
				return host._no("REWARD_UNAVAILABLE", "暂时无法领取补给")
			if reward_id == "crew":
				train_crew(tx)
			tx.events.append({"kind":"village-defense-reward", "actor_id":"player", "night":run.night, "reward_id":reward_id, "items":items})
			run.phase = "day"
			run.next_at = now + NEXT_EVENING_SECONDS
			run.night = int(run.night) + 1
	return tx.result()

static func train_crew(tx: RefCounted) -> void:
	for actor: Dictionary in tx.writable_collection("actors"):
		if actor.id not in ["repair-resident", "village-resident"] or not actor.get("relationship", {}).get("member", false): continue
		var skill: String = "village_building" if actor.id == "repair-resident" else "village_hauling"
		actor.skills[skill] = mini(100, int(actor.skills.get(skill, 0)) + 2)

static func begin_wave(tx: RefCounted, run: Dictionary, now: float) -> void:
	run.phase = "warning"
	run.arrival = now + PREVIEW_SECONDS
	tx.events.append({"kind":"village-defense-warning", "actor_id":"player", "night":run.night, "wave":run.wave})
	run.erase("spawn_error")
	run.erase("approaches")

static func earned_warning(tx: RefCounted) -> bool:
	var fields: Array[String] = ["instances"]
	var instances: Array = tx.read_extension_fields("r34:modules", fields).get("instances", [])
	var warehouse: Dictionary = Draft.find(instances, WAREHOUSE)
	var worksite: Dictionary = Draft.find(instances, Expedition.WORKSHOP)
	var destinations: Array = [str(warehouse.get("stock_refs", {}).get("storage", "")), str(worksite.get("stock_refs", {}).get("input", "")), str(worksite.get("stock_refs", {}).get("output", ""))]
	for event: Dictionary in tx.observe_facts().get("ledger", []):
		var destination: String = str(event.get("destination_id", event.get("output_id", "")))
		if event.get("kind") in ["inventory-transfer", "logistics-delivery-completed"] and not destination.is_empty() and destinations.has(destination) and event.get("source_id") != destination and event.get("items", {}).keys().any(func(item: String) -> bool: return item in ["timber", "log", "scrap", "stone"]):
			return true
	if warehouse.get("restoration", {}).get("completed", false): return true
	return false

static func advance(host, tx: RefCounted, observed: Dictionary, player: Dictionary, now: float, expedition: Dictionary) -> Dictionary:
	if observed.phase == "dormant":
		if now < host.night_next_check or not at_home(player): return observed
		host.night_next_check = now + 1.0
		if not earned_warning(tx): return observed
		var first: Dictionary = tx.extension(KEY, initial())
		prepare_evening(first, now)
		return first
	if observed.phase == "day":
		if now < float(observed.next_at): return observed
		var evening: Dictionary = tx.extension(KEY, initial())
		prepare_evening(evening, now)
		return evening
	if observed.phase == "dawn": return observed
	if not at_home(player) and not busy(observed): return observed
	if observed.phase == "ready" and (int(observed.night) == 1 or now < float(observed.arrival) or expedition.phase != "idle"):
		return observed
	var run: Dictionary = tx.extension(KEY, initial())
	if run.phase == "ready": begin_wave(tx, run, now)
	if busy(run) and (float(player.hp) <= 0 or not at_home(player)):
		settle(host, tx, run, player, false)
	elif run.phase == "warning" and now >= float(run.arrival):
		spawn(host, tx, run, player, now)
	return run

static func prepare_evening(run: Dictionary, now: float) -> void:
	run.merge({"phase":"ready", "arrival":now+45.0, "wave":1, "roster":[], "perks":[], "damage":{}, "secured":0, "heading":(int(run.night)-1)%4}, true)

static func heading_name(side: int) -> String:
	return ["北边乡道", "东边林缘", "南边坡地", "西边田埂"][side]

static func village_ready_count(instances: Array) -> int:
	var intact := 0
	for id: String in [OLD_HOME, WAREHOUSE]:
		var module := Draft.find(instances, id)
		if module.get("restoration", {}).get("completed", false) and module.get("status") == "operational" and float(module.get("hp", 0)) > 0:
			intact += 1
	return intact

static func wave_size(run: Dictionary, ready_count: int) -> int:
	var first := int(run.wave) == 1
	var incoming := mini(6, (3 if first else 4) + mini(2, int(run.night) - 1))
	return incoming - (1 if not first and ready_count == 2 else 0)

static func spawn(host, tx: RefCounted, run: Dictionary, player: Dictionary, now: float) -> void:
	var origins := [Vector2(32, 4), Vector2(60, 32), Vector2(32, 60), Vector2(4, 32)]
	var home: Dictionary = player.get("home", G.location(player))
	var screen: Callable = host.night_screen_test
	var positions: Array = []
	var approaches: Array[String] = []
	var fields: Array[String] = ["instances"]
	var ready_count := village_ready_count(tx.read_extension_fields("r34:modules", fields).get("instances", []))
	var count := wave_size(run, ready_count)
	for attempt: int in 28:
		var side: int = (int(run.heading) + int(attempt / 7)) % 4
		var edge: Vector2 = origins[side]
		var lateral: float = float([0,-3,3,-6,6,-10,10][attempt % 7])
		if side % 2 == 0: edge.x += lateral
		else: edge.y += lateral
		if Vector2(home.x, home.z).distance_to(edge) < 14.0 or Vector2(player.x, player.z).distance_to(edge) < 14.0:
			continue
		var point := Expedition.checkpoint(host, {"x":edge.x, "y":0.0, "z":edge.y, "regionId":HOME, "buildingId":null, "storeyId":null})
		if point.is_empty() or (screen.is_valid() and screen.call(G.point(point))): continue
		positions.append(point)
		var approach := heading_name(side)
		if not approaches.has(approach): approaches.append(approach)
		if positions.size() == count: break
	if positions.size() < count:
		run.spawn_error = "村外暂时没有合适的来路，回到村内等待"
		run.arrival = now + 3.0
		return
	var encounter := {"id":"village:night:%d:%d" % [run.night, run.wave], "position":positions[0], "positions":positions, "count":count, "expedition":true, "runner_count":0 if int(run.wave) == 1 else mini(2,int(run.night))}
	var result: Dictionary = host.prepare_defense_spawn(tx, encounter)
	if not result.ok:
		run.spawn_error = str(result.get("reason", "村外来路暂时不可达"))
		run.arrival = now + 3.0
		return
	for id: String in encounter.actors:
		var enemy: Dictionary = tx.actor(id)
		enemy.night_enemy = true
		enemy.patrol_region = HOME
	run.roster = encounter.actors
	run.approaches = approaches
	run.phase = "fighting"
	run.wave_started = now
	run.erase("spawn_error")
	tx.events.append({"kind":"village-defense-wave", "actor_id":"player", "night":run.night, "wave":run.wave})

static func pursue(host, tx: RefCounted, enemy: Dictionary, player: Dictionary, run: Dictionary, dt: float, now: float) -> void:
	if now < float(enemy.get("stunned_until", 0)): return
	var target: Dictionary = {}
	var distance := 8.0
	for actor: Dictionary in tx.staged.actors:
		if actor.get("faction") == "infected" or actor.get("regionId") != HOME or float(actor.hp) <= 0: continue
		var reach := G.point(actor).distance_to(G.point(enemy))
		if reach < distance:
			target = actor
			distance = reach
	if distance <= 1.1 and host._clear(enemy,target):
		if float(enemy.cooldown) <= 0:
			var damage := 5.0 if int(run.wave) == 1 else 7.0
			target.hp = maxf(0.0, float(target.hp)-damage)
			target.hit_until = now + 0.18
			enemy.cooldown = 1.12
			enemy.attack_until = now + 0.26
			tx.events.append({"kind":"combat-hit", "actor_id":enemy.id, "target_id":target.id, "damage":damage})
		return
	var goal: Dictionary = G.location(target) if not target.is_empty() else player.get("home", G.location(player))
	host._walker_move(tx, enemy, goal, dt, now, true)

static func after_combat(host, tx: RefCounted, run: Dictionary, player: Dictionary, now: float) -> void:
	if run.phase != "fighting": return
	for event: Dictionary in tx.events:
		if event.get("kind") in ["module-hostile-hit", "module-damaged", "module-ruined"] and event.has("module_id"):
			run.damage[event.module_id] = "坍塌" if event.kind == "module-ruined" else run.damage.get(event.module_id, "受损")
	if float(player.hp) <= 0:
		settle(host, tx, run, player, false)
		return
	if host._cleared(tx, {"id":"village:night:%d:%d" % [run.night, run.wave], "actors":run.roster}, run.roster.size()):
		run.secured = int(run.wave)
		tx.events.append({"kind":"village-defense-wave-cleared", "actor_id":"player", "night":run.night, "wave":run.wave})
		if int(run.wave) >= 2:
			settle(host, tx, run, player, true)
		else:
			Expedition.remove_wave(tx, run)
			run.phase = "between"
	elif now-float(run.wave_started) >= WAVE_TIMEOUT:
		settle(host, tx, run, player, false)

static func settle(host, tx: RefCounted, run: Dictionary, player: Dictionary, held: bool) -> void:
	Expedition.remove_wave(tx, run)
	for actor: Dictionary in tx.staged.actors:
		if float(actor.hp) > 0 or (actor.id != "player" and not actor.get("relationship", {}).get("member", false)): continue
		var safe := Expedition.checkpoint(host, actor.get("home", G.location(actor)))
		if not safe.is_empty(): actor.merge(safe, true)
		actor.hp = minf(32.0, float(actor.get("max_hp", 100.0)))
		actor.hunger = maxf(24.0, float(actor.hunger))
		actor.thirst = maxf(24.0, float(actor.thirst))
	run.phase = "dawn"
	run.held = held
	tx.events.append({"kind":"village-defense-settled", "actor_id":"player", "night":run.night, "held":held, "waves":run.secured, "damage":run.damage.duplicate(true)})

static func perks_to_offer(_run: Dictionary) -> Dictionary:
	return DEFENSE_CHOICES

static func rewards_to_offer(run: Dictionary) -> Dictionary:
	return {"supplies":"领取应急补给 · 木材、食物、饮水各 +2"} if int(run.secured) == 0 else DAWN_REWARDS

static func display(host) -> Dictionary:
	var run := snapshot(host)
	var player: Dictionary = host.context.actor.call("player")
	var now: float = host.context.clock.call()
	var result := {"phase":run.phase, "night":int(run.night), "wave":int(run.wave), "direction":heading_name(int(run.heading)), "at_home":at_home(player), "error":run.get("spawn_error", ""), "held":run.get("held", false), "secured":int(run.secured)}
	match str(run.phase):
		"ready", "warning": result.seconds = maxi(0, ceili(float(run.get("arrival",now))-now))
		"fighting":
			result.approach = "、".join(run.get("approaches", []))
			result.remaining = run.roster.filter(func(id: String) -> bool: return float(host.context.actor.call(id).get("hp", 0)) > 0).size()
		"between": result.choices = perks_to_offer(run)
		"dawn":
			result.choices = rewards_to_offer(run)
			result.damage_count = run.damage.size()
		"day": result.seconds = maxi(0, ceili(float(run.next_at)-now))
	if run.phase in ["ready", "between"]:
		var fields: Array[String] = ["instances"]
		result.village_ready = village_ready_count(host.context.world.extension_fields("r34:modules", fields).get("instances", []))
	return result
