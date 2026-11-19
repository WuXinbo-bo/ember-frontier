extends RefCounted
const TOOL_FIELDS: Array[String] = ["tools"]
## One expedition lives in the existing transactional world and clock.
const G = preload("res://scripts/buildings/building_geometry.gd")
const Contact = preload("res://scripts/modules/module_contact.gd")
const Draft = preload("res://scripts/actions/domain_draft.gd")
const KEY = "village:expedition"
const SITE = {"x":34.0,"y":0.0,"z":12.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
const EXIT = {"x":34.0,"y":0.0,"z":24.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
const WAVES = [3, 4, 6]
const PERKS = {"reach":"长杆横扫 · 木棒距离 +25%", "tempo":"快手 · 出手间隔 -28%", "guard":"护具 · 受到伤害 -25%", "force":"重击 · 木棒击退 +60%", "pierce":"穿透箭 · 一箭最多打中 2 只", "rally":"互相掩护 · 同伴出手间隔 -25%"}
const PREPARATIONS = {"medical":"急救包", "tipped":"硬头箭"}
const PREPARATION_COST = 3
const WORKSHOP = "r34:generated:RH-HOME:woodwork"
const WAREHOUSE = "r34:generated:RH-HOME:village-warehouse"
const BOW_ID = "village:expedition:bow"

static func initial() -> Dictionary:
	return {"phase":"idle", "attempt":0, "wave":0, "escort":"", "roster":[], "perks":[], "rewarded":0, "result":""}

static func snapshot(host) -> Dictionary:
	var value: Variant = host.context.world.extension(KEY)
	return value if value is Dictionary else initial()

static func checkpoint(host, point: Dictionary) -> Dictionary:
	return host.context.spatial.current_space().standing_point(point)

static func near(actor: Dictionary, point: Dictionary, radius: float) -> bool:
	return not actor.is_empty() and actor.get("regionId") == point.get("regionId") and Vector2(float(actor.x)-float(point.x),float(actor.z)-float(point.z)).length() <= radius

static func check(host, request: Dictionary) -> Dictionary:
	var player: Dictionary = host.context.actor.call("player")
	if request.get("actor_id","player") != "player" or player.is_empty() or float(player.hp) <= 0:
		return host._no("ACTOR_UNAVAILABLE", "需要主角在场")
	var run := snapshot(host)
	var payload: Dictionary = request.get("payload", {})
	match request.kind:
		"expedition.prepare":
			if run.phase != "idle" or int(run.get("rewarded", 0)) == 0:
				return host._no("EXPEDITION_PREP_UNAVAILABLE", "先从补给站带回一批战利品")
			if not PREPARATIONS.has(payload.get("preparation")) or not str(run.get("prepared", "")).is_empty():
				return host._no("EXPEDITION_PREP_ALREADY_CHOSEN", "每趟只能带一种整备")
			if not workshop_ready(host, player):
				return host._no("EXPEDITION_PREP_NEEDS_WORKSHOP", "先修好仓棚，再到手工作坊整备")
			if float(player.pack.get("scrap", 0)) < PREPARATION_COST:
				return host._no("EXPEDITION_PREP_MATERIALS", "需要背包里有 3 个废料")
		"expedition.depart":
			if run.phase != "idle" or player.regionId != SITE.regionId:
				return host._no("OUT_OF_REACH", "先到村口再出发")
			var escort_id: String = str(payload.get("escort", ""))
			if not escort_id.is_empty():
				var escort: Dictionary = host.context.actor.call(escort_id)
				if escort_id == "player" or not escort.get("relationship", {}).get("member", false) or not escort.get("relationship", {}).get("consent", false) or float(escort.get("hp", 0)) <= 0 or not near(escort, player, 24):
					return host._no("ESCORT_UNAVAILABLE", "同伴需要在村口附近并且能行动")
		"expedition.open":
			if run.phase not in ["idle", "approach"] or not near(player, SITE, 2.7):
				return host._no("OUT_OF_REACH", "先走到补给箱旁")
			if not run.escort.is_empty() and not near(host.context.actor.call(run.escort), player, 2.9):
				return host._no("ESCORT_CATCHING_UP", "等同伴走到补给箱旁，或撤回村口")
		"expedition.next":
			if run.phase != "between" or not offers(run).has(payload.get("perk")):
				return host._no("CHOOSE_PERK", "选择一项增益再继续")
		"expedition.retreat":
			if run.phase not in ["approach","warning","fighting","between","complete"]:
				return host._no("NO_EXPEDITION", "当前没有可以撤离的出征")
		"expedition.extract":
			if run.phase != "retreat" or not near(player, EXIT, 2.8):
				return host._no("OUT_OF_REACH", "先沿路走到撤离点")
		"expedition.weapon":
			var kind: String = str(payload.get("weapon", ""))
			if kind not in ["club", "bow"]:
				return host._no("MISSING_WEAPON", "请选择木棒或弓")
			if locate_weapon(host, player, kind).is_empty() and not (kind == "bow" and run.phase != "idle" and int(run.get("secured",0)) >= 1):
				return host._no("MISSING_WEAPON", "这把武器还不在背包里")
		_:
			return host._no("UNKNOWN_COMMAND", "未知探索操作")
	return host._ok()

static func locate_weapon(host, actor: Dictionary, kind: String) -> Dictionary:
	for tool: Dictionary in host.context.world.extension_fields("r3:production",TOOL_FIELDS).get("tools", []):
		if tool.kind == kind and tool.holderId == "pack:" + str(actor.id):
			return tool
	return {}

static func execute(host, tx: RefCounted, request: Dictionary) -> Dictionary:
	var run: Dictionary = tx.extension(KEY, initial())
	var player: Dictionary = tx.actor("player")
	var payload: Dictionary = request.get("payload", {})
	match request.kind:
		"expedition.prepare":
			tx.stock_delta("pack:player", {"scrap":-PREPARATION_COST})
			run.prepared = str(payload.preparation)
			tx.events.append({"kind":"expedition-prepared","actor_id":"player","preparation":run.prepared})
		"expedition.depart":
			var escort_id: String = str(payload.get("escort", ""))
			if not escort_id.is_empty():
				var assigned: Dictionary = tx.actor(escort_id)
				var intent: Variant = assigned.get("intent")
				if intent is Dictionary and intent.get("owner") == "residents" and intent.get("purpose") in ["village-stroll","watch","return-home"]:
					assigned.intent = null
				var plan: Dictionary = host._actions.get_ref().safe_handoff(escort_id, "", tx.staged, tx.extensions)
				if not plan.ok:
					return host._no("ESCORT_BUSY", "同伴正在处理当前工作，请等他空下来")
				var merged: Dictionary = preload("res://scripts/runtime/settlement_workforce.gd")._merge_prepared(tx, plan)
				if not merged.ok:
					return merged
				run = tx.extension(KEY, initial())
				var escort: Dictionary = tx.actor(escort_id)
				escort.expedition_follow = true
				escort.activity = "跟随出征"
			begin_approach(host, run, escort_id)
		"expedition.open":
			if run.phase == "idle":
				begin_approach(host, run, "")
			apply_preparation(player, run)
			start_wave(host, run)
		"expedition.next":
			run.perks.append(payload.perk)
			start_wave(host, run)
		"expedition.retreat":
			run.phase = "retreat"
		"expedition.extract":
			settle(host, tx, run, false)
		"expedition.weapon":
			player.combat_preference = payload.weapon
	if request.kind in ["expedition.open", "expedition.next"]:
		tx.events.append({"kind":"expedition-warning","actor_id":"player","wave":run.wave})
	return tx.result()

static func workshop_ready(host, player: Dictionary) -> bool:
	if player.get("regionId") != SITE.regionId or host._modules == null:
		return false
	var modules: Variant = host._modules.get_ref()
	if modules == null:
		return false
	var storage: Dictionary = modules.instance(WAREHOUSE)
	var workshop: Dictionary = modules.instance(WORKSHOP)
	if storage.get("status") != "operational" or workshop.get("status") != "operational" or not workshop.get("discovered", false):
		return false
	return modules.permitted(player, workshop.owner) and Contact.near(host.context.spatial.current_space(), G.location(player), workshop)

static func apply_preparation(player: Dictionary, run: Dictionary) -> void:
	match run.get("prepared", ""):
		"medical":
			player.hp = minf(float(player.max_hp), float(player.hp) + 30.0)
			run.perks.append("guard")
		"tipped":
			run.perks.append("pierce")
	run.prepared = ""

static func begin_approach(host, run: Dictionary, escort_id: String) -> void:
	var attempt: int = int(run.attempt) + 1
	var profile: int = 0
	if int(run.get("rewarded", 0)) > 0:
		profile = 1 + posmod(int(host.context.world.identity().seed) + attempt, 2)
	run.merge({"phase":"approach","wave":0,"secured":0,"perks":[],"roster":[],"escort":escort_id,"result":"","attempt":attempt,"profile":profile},true)

static func wave_length(run: Dictionary, wave: int) -> int:
	if wave == 2 and int(run.get("profile", 0)) == 1:
		return 5
	if wave == 3 and int(run.get("profile", 0)) == 2:
		return 5
	return WAVES[wave - 1]

static func runners(run: Dictionary, wave: int) -> int:
	if int(run.get("profile", 0)) == 2 and wave >= 2:
		return 2
	return int(wave == 3)

static func wave_preview(run: Dictionary, wave: int) -> String:
	var running := runners(run, wave)
	var amount := wave_length(run, wave)
	if wave == 1:
		return "%d 只 · 单入口" % amount
	var detail := " · %d 只跑尸" % running if running > 0 else " · 慢尸群"
	return "%d 只 · 双入口%s" % [amount, detail]

static func start_wave(host, run: Dictionary) -> void:
	run.wave = int(run.wave) + 1
	run.phase = "warning"
	run.arrival = float(host.context.clock.call()) + 3.0
	run.erase("spawn_error")

static func spawn_wave(host, tx: RefCounted, run: Dictionary, player: Dictionary) -> void:
	var wave: int = int(run.wave)
	var length := wave_length(run, wave)
	var positions: Array = []
	var groups := [Vector2(34,5), Vector2(43,12)]
	var zone: Vector2 = Vector2(player.x, player.z)
	for i: int in length:
		var centre: Vector2 = groups[0 if wave == 1 else i % 2]
		var found := false
		for step: int in 16:
			var angle: float = TAU * float((step + i * 3) % 16) / 16.0
			var candidate: Vector2 = centre + Vector2.from_angle(angle) * (2.5 if step < 8 else 4.2)
			if zone.distance_to(candidate) < 4 or positions.any(func(p: Dictionary) -> bool: return Vector2(p.x,p.z).distance_to(candidate) < 0.9):
				continue
			var at := SITE.duplicate()
			at.x = candidate.x
			at.z = candidate.y
			var feet := checkpoint(host, at)
			if feet.is_empty():
				continue
			positions.append(feet)
			found = true
			break
		if not found:
			break
	if positions.size() < length:
		run.spawn_error = "来敌入口被堵住，先让开道路，或撤回村里"
		run.arrival = float(host.context.clock.call()) + 3.0
		return
	var encounter: Dictionary = {"id":"village:raid:%d:%d" % [run.attempt, wave],"position":positions[0],"positions":positions,"count":length,"expedition":true,"runner_count":runners(run, wave)}
	var spawned: Dictionary = host._spawn(tx, encounter)
	if not spawned.ok:
		run.spawn_error = spawned.get("reason", "来敌入口不可达")
		run.arrival = float(host.context.clock.call()) + 3.0
		return
	run.roster = encounter.actors
	run.phase = "fighting"
	run.erase("spawn_error")
	run.wave_started = float(host.context.clock.call())
	tx.events.append({"kind":"expedition-wave-started","actor_id":"player","wave":wave})

static func remove_wave(tx: RefCounted, run: Dictionary) -> void:
	var roster: Array = run.roster
	if not roster.is_empty():
		tx.staged.actors = tx.staged.actors.filter(func(actor: Dictionary) -> bool: return not roster.has(actor.id))
		run.roster = []

static func settle(host, tx: RefCounted, run: Dictionary, failed: bool) -> void:
	var player: Dictionary = tx.actor("player")
	var secured: int = int(run.get("secured",0))
	var result := "已撤回村口"
	if failed:
		var safe := checkpoint(host, EXIT)
		if safe.is_empty(): safe = checkpoint(host, player.home)
		if not safe.is_empty(): player.merge(safe, true)
		player.hp = 36.0
		player.hunger = maxf(25.0, float(player.hunger))
		player.thirst = maxf(25.0, float(player.thirst))
		result = "撤回休整 · 本趟战利品已遗失"
	elif secured > 0:
		var production: Dictionary = tx.extension("r3:production")
		if Draft.find(production.tools, BOW_ID).is_empty():
			production.tools.append({"id":BOW_ID,"kind":"bow","holderId":"pack:player","durability":100.0})
		var payout: int = maxi(0, secured - int(run.rewarded))
		if payout > 0:
			tx.stock_delta("pack:player", {"scrap":payout * 3})
		if secured == 3 and int(run.rewarded) < 3:
			tx.stock_delta("pack:player", {"cloth":2})
		elif secured == 3 and int(run.get("profile", 0)) > 0:
			tx.stock_delta("pack:player", {"scrap":2})
		run.rewarded = maxi(secured, int(run.rewarded))
		result = "已回村 · 保住第 %d 波战利品" % secured
	var escort: Dictionary = tx.actor(str(run.escort))
	if not escort.is_empty():
		escort.erase("expedition_follow")
		escort.erase("expedition_route")
		escort.activity = "结束出征，返回村庄工作"
		if float(escort.hp) <= 0:
			var safe := checkpoint(host, EXIT)
			if not safe.is_empty(): escort.merge(safe, true)
			escort.hp = 36.0
	remove_wave(tx, run)
	run.merge({"phase":"idle","escort":"","perks":[],"secured":0,"wave":0,"result":result},true)
	if player.get("combat_preference") == "bow" and locate_weapon(host, player, "bow").is_empty() and (failed or secured == 0):
		player.combat_preference = "club"
	tx.events.append({"kind":"expedition-settled","actor_id":"player","failed":failed,"waves":secured,"attempt":run.attempt})

static func follow(host, escort: Dictionary, player: Dictionary, dt: float, now: float) -> void:
	if escort.is_empty() or float(escort.hp) <= 0 or not near(escort, player, 60):
		return
	var from := G.location(escort)
	var goal := G.location(player)
	if G.point(goal).distance_to(G.point(from)) < 1.45:
		escort.erase("expedition_route")
		return
	var actions: Variant = host._actions.get_ref()
	var route: Array = escort.get("expedition_route", [])
	while not route.is_empty() and G.point(route[0].get("to", {})).distance_to(G.point(from)) < 0.23:
		route.pop_front()
	var waypoint: Dictionary = goal if route.is_empty() else route[0].get("to", goal)
	var stride := (G.point(waypoint)-G.point(from)).limit_length(dt * 3.35)
	var to := from.duplicate()
	to.x += stride.x
	to.z += stride.z
	var moved: Dictionary = actions.move_step(str(escort.id), from, to)
	if moved.ok and not G.point(moved.location).is_equal_approx(G.point(from)):
		escort.merge(moved.location,true)
		return
	if now < float(escort.get("expedition_next_route", 0)) or host._walker_path_budget <= 0:
		return
	host._walker_path_budget -= 1
	escort.expedition_next_route = now + 2.0
	var plan: Dictionary = actions.route(str(escort.id), from, goal)
	escort.expedition_route = plan.get("steps", []) if plan.ok else []

static func advance(host, tx: RefCounted, dt: float, now: float, night: Dictionary = {}) -> void:
	var observed := snapshot(host)
	var active: bool = observed.phase != "idle"
	var actors: Array = tx.observe_facts().actors
	if not active and not actors.any(func(a: Dictionary) -> bool: return a.get("faction") == "infected" and float(a.hp) > 0):
		return
	var player: Dictionary = tx.actor("player")
	var run: Dictionary = tx.extension(KEY, initial()) if active else observed
	if active and float(player.hp) <= 0:
		settle(host, tx, run, true)
		return
	if active and not near(player, SITE, 29):
		if run.phase == "approach":
			# The walk from home can begin outside the arena.
			pass
		elif run.phase in ["warning","fighting","between","complete"]:
			run.phase = "retreat"
			remove_wave(tx, run)
	if run.phase == "warning" and now >= float(run.arrival):
		spawn_wave(host, tx, run, player)
	if active:
		follow(host, tx.actor(str(run.escort)), player, dt, now)
	var live: Array = tx.staged.actors.filter(func(a: Dictionary) -> bool: return a.get("faction") == "infected" and float(a.hp) > 0 and host.context.region_is_detailed.call(str(a.regionId)))
	if not live.is_empty():
		var tools: Array = tx.read_extension_fields("r3:production",TOOL_FIELDS).get("tools", [])
		for actor: Dictionary in tx.staged.actors:
			if float(actor.hp) <= 0 or actor.get("faction") == "infected" or float(actor.get("cooldown",0)) > 0 or not host.context.region_is_detailed.call(str(actor.regionId)):
				continue
			if actor.id != "player" and (not actor.get("relationship", {}).get("member", false) or not actor.get("relationship", {}).get("consent", false)):
				continue
			auto_attack(host, tx, actor, live, tools, night if night.get("phase") == "fighting" else run, now)
		for enemy: Dictionary in live:
			if float(enemy.hp) <= 0: continue
			if enemy.get("night_enemy", false):
				host.pursue_night_enemy(tx, enemy, player, night, dt, now)
			elif enemy.get("expedition_enemy", false):
				pursue(host, tx, enemy, player, tx.actor(str(run.escort)), run, dt, now)
			else:
				host._enemy_step(tx, enemy, {"exploration":{"status":"idle","upgrades":[]}},dt,now)
	if active and float(player.hp) <= 0:
		settle(host, tx, run, true)
		return
	if run.phase == "fighting" and now - float(run.wave_started) >= 100.0:
		run.phase = "retreat"
		run.spawn_error = "本波尚未清理，沿村路撤离可保住已取得的战利品"
	if run.phase == "fighting" and host._cleared(tx, {"actors":run.roster,"id":"village:raid:%d:%d" % [run.attempt, run.wave]}, wave_length(run, int(run.wave))):
		run.secured = run.wave
		run.phase = "complete" if int(run.wave) == WAVES.size() else "between"
		if int(run.wave) == 1 and int(run.rewarded) == 0:
			player.combat_preference = "bow"
		remove_wave(tx,run)
		tx.events.append({"kind":"expedition-wave-cleared","actor_id":"player","wave":run.wave})

static func auto_attack(host, tx: RefCounted, actor: Dictionary, live: Array, tools: Array, run: Dictionary, now: float) -> void:
	var preference: String = str(actor.get("combat_preference", "club"))
	var weapon: String = ""
	for tool: Dictionary in tools:
		if tool.holderId != "pack:" + str(actor.id) or tool.kind not in ["club","bow"]:
			continue
		if weapon.is_empty() or tool.kind == preference: weapon = tool.kind
	if actor.id == "player" and preference == "bow" and run.has("attempt") and int(run.get("secured",0)) >= 1: weapon = "bow"
	if weapon.is_empty(): return
	var perks: Array = run.perks if actor.id == "player" else []
	var cover: bool = actor.id == run.escort and run.perks.has("rally")
	var bow: bool = weapon == "bow"
	var reach: float = 7.2 if bow else 2.15 + (0.55 if perks.has("reach") else 0.0)
	var targets: Array = live.filter(func(e: Dictionary) -> bool: return float(e.hp) > 0 and (not e.get("expedition_enemy", false) or run.phase == "fighting") and host._near(actor, e, reach) and host._clear(actor,e))
	if targets.is_empty(): return
	var origin := G.point(actor)
	targets.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return origin.distance_squared_to(G.point(a)) < origin.distance_squared_to(G.point(b)))
	var direction: Vector3 = (G.point(targets[0])-origin).normalized()
	actor.combat_aim = G.json_point(direction)
	actor.attack_until = now + 0.25
	actor.combat_kind = weapon
	actor.cooldown = (0.75 if bow else 0.56) * (0.72 if perks.has("tempo") else 1.0)
	if cover: actor.cooldown *= 0.75
	var hits := 0
	for enemy: Dictionary in targets:
		var heading := (G.point(enemy)-origin).normalized()
		if hits > 0 and direction.dot(heading) < (0.93 if bow else 0.25): continue
		var damage := 16.0 if bow else 19.0
		enemy.hp = maxf(0, float(enemy.hp) - damage)
		enemy.hit_until = now + 0.18
		if not bow and float(enemy.hp) > 0:
			var to := G.location(enemy)
			var push_distance: float = 0.64 if perks.has("force") else 0.40
			to.x += heading.x * push_distance
			to.z += heading.z * push_distance
			var pushed: Dictionary = host._actions.get_ref().move_step(str(enemy.id),G.location(enemy),to)
			if pushed.ok: enemy.merge(pushed.location,true)
			enemy.stunned_until = now + 0.10
		tx.events.append({"kind":"combat-hit","actor_id":actor.id,"target_id":enemy.id,"damage":damage,"weapon":weapon,"primary_hit":hits == 0,"position":G.json_point(G.point(enemy)),"from":G.json_point(origin)})
		if float(enemy.hp) <= 0: host._drop(tx, enemy)
		hits += 1
		var limit: int = 3
		if bow: limit = 2 if perks.has("pierce") else 1
		if hits >= limit: break

static func pursue(host, tx: RefCounted, enemy: Dictionary, player: Dictionary, escort: Dictionary, run: Dictionary, dt: float, now: float) -> void:
	if now < float(enemy.get("stunned_until",0)): return
	var target: Dictionary = player
	if not escort.is_empty() and float(escort.hp) > 0 and G.point(enemy).distance_squared_to(G.point(escort)) < G.point(enemy).distance_squared_to(G.point(player)):
		target = escort
	if not near(target, SITE, 29): return
	var offset := G.point(target)-G.point(enemy)
	if offset.length() <= 1.10 and host._clear(enemy,target):
		if float(enemy.cooldown) <= 0:
			var damage := 7.0 if int(run.wave) < 3 else 9.0
			if target.id == "player" and run.perks.has("guard"): damage *= 0.72
			target.hp = maxf(0,float(target.hp)-damage)
			target.hit_until = now + 0.18
			enemy.cooldown = 1.0
			enemy.attack_until = now + 0.26
			tx.events.append({"kind":"combat-hit","actor_id":enemy.id,"target_id":target.id,"damage":damage})
		return
	# The same bounded path budget used by roaming infected handles corners.
	host._walker_move(tx, enemy, G.location(target), dt, now, false)

static func offers(run: Dictionary) -> Dictionary:
	if run.phase != "between": return {}
	var result: Dictionary = {}
	var options: Array = ["reach", "tempo", "guard", "force", "pierce"]
	if not str(run.escort).is_empty():
		options.append("rally")
	var profile: int = int(run.get("profile", 0))
	var featured: String = "force" if profile == 1 else "pierce" if profile == 2 or int(run.wave) > 1 else ""
	if profile == 2 and not str(run.escort).is_empty() and int(run.wave) > 1:
		featured = "rally"
	if not featured.is_empty():
		options.erase(featured)
		options.push_front(featured)
	for perk: String in options:
		if not run.perks.has(perk): result[perk] = PERKS[perk]
		if result.size() == 3: break
	return result

static func display(host) -> Dictionary:
	var value := snapshot(host)
	var player: Dictionary = host.context.actor.call("player")
	var live: int = 0
	var secured: int = int(value.get("secured", 0))
	var previous: int = int(value.get("rewarded", 0))
	var loot: PackedStringArray = []
	var scrap: int = maxi(0, secured - previous) * 3
	if secured > 0 and locate_weapon(host, player, "bow").is_empty(): loot.append("弓")
	if secured == 3 and previous >= 3 and int(value.get("profile", 0)) > 0: scrap += 2
	if scrap > 0: loot.append("%d 废料" % scrap)
	if secured == 3 and previous < 3: loot.append("2 布料")
	for id: String in value.roster:
		if float(host.context.actor.call(id).get("hp",0)) > 0: live += 1
	return {"phase":value.phase,"wave":int(value.wave),"remaining":live,"escort":value.escort,"perks":value.perks,"choices":offers(value),"result":value.result,
		"warning":maxi(0,ceili(float(value.get("arrival",0))-float(host.context.clock.call()))),"error":value.get("spawn_error",""),
		"exit":EXIT,"site":SITE,"near_site":near(player,SITE,2.7),"escort_ready":value.escort.is_empty() or near(host.context.actor.call(value.escort), player, 2.9),"near_exit":near(player,EXIT,2.8),"may_depart":player.get("regionId") == SITE.regionId,
		"site_distance":roundi(Vector2(player.x - SITE.x, player.z - SITE.z).length()) if player.get("regionId") == SITE.regionId else -1,
		"entrances":[SITE.merged({"x":34.0,"z":5.0},true)] if int(value.wave) < 2 else [SITE.merged({"x":34.0,"z":5.0},true),SITE.merged({"x":43.0,"z":12.0},true)],
		"weapon":player.get("combat_preference","club"),"bow":int(value.get("secured",0)) >= 1 or not locate_weapon(host,player,"bow").is_empty(),
		"prepared":str(value.get("prepared", "")),"prepared_label":PREPARATIONS.get(value.get("prepared", ""), ""),
		"may_prepare":value.phase == "idle" and int(value.get("rewarded", 0)) > 0,
		"loot_label":"、".join(loot),
		"wave_preview":wave_preview(value, clampi(int(value.wave) + int(value.phase == "between"), 1, WAVES.size()))}
