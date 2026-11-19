extends "res://tests/integration/run_chapter20_journey.gd"

const Expedition = preload("res://scripts/runtime/village_expedition.gd")

func finish() -> void:
	if chapter_runtime != null and checks.all(func(row: Dictionary) -> bool: return row.ok):
		play_expedition(chapter_runtime)
	super.finish()

func play_expedition(runtime: RefCounted) -> void:
	if not care(runtime, 60.0):
		check("player can recover for an expedition after radio", false)
		return
	var reply := send(runtime, "expedition.depart")
	check("ordinary completed chapter can depart", reply.ok, reply.get("reason"))
	if not reply.ok: return
	var query: RefCounted = runtime._services.buildings.current_space()
	var site: Dictionary = query.standing_point(Expedition.SITE)
	var arrived := walk(runtime, site) if not site.is_empty() else {"ok":false}
	check("walk from the village to the expedition", arrived.ok, arrived.get("reason"))
	if not arrived.ok: return
	var scrap: float = float(runtime.stock("pack:player").items.get("scrap", 0))
	reply = send(runtime, "expedition.open")
	check("site opens the first wave after radio", reply.ok, reply.get("reason"))
	if not reply.ok: return
	for i in 450:
		runtime.tick(0.1)
		if runtime.expedition_snapshot().phase not in ["warning", "fighting"]: break
	var result: Dictionary = runtime.expedition_snapshot()
	check("player survives first wave without granted equipment", result.phase == "between", result)
	if result.phase != "between": return
	reply = send(runtime, "expedition.retreat")
	check("short first trip can choose to retreat", reply.ok, reply.get("reason"))
	if not reply.ok: return
	var exit: Dictionary = runtime._services.buildings.current_space().standing_point(Expedition.EXIT)
	arrived = walk(runtime, exit) if not exit.is_empty() else {"ok":false}
	check("returns on foot before the reward", arrived.ok, arrived.get("reason"))
	if not arrived.ok: return
	reply = send(runtime, "expedition.extract")
	check("real reward arrives once on return", reply.ok and float(runtime.stock("pack:player").items.get("scrap", 0)) == scrap + 3, reply)
	if not reply.ok: return
	var workshop: Dictionary = runtime._services.modules.instance(Expedition.WORKSHOP)
	for point: Dictionary in ChapterShape.ports(workshop, Catalog.definition(workshop.definition_id)):
		if not walk(runtime, point.location).ok: continue
		reply = send(runtime, "expedition.prepare", "", {"preparation":"tipped"})
		if reply.ok: break
	check("the same village spends the loot on next-run preparation", reply.ok and runtime.expedition_snapshot().prepared == "tipped" and float(runtime.stock("pack:player").items.get("scrap", 0)) == scrap, reply)