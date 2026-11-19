extends "res://tests/integration/run_chapter20_journey.gd"
const Night = preload("res://scripts/runtime/village_night_defense.gd")
const G = preload("res://scripts/buildings/building_geometry.gd")

func run() -> void:
	started20 = Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed20 = int(arg.trim_prefix("--seed="))
	var profiles := ChapterAssembly.generation_profiles(21)
	var opening := ChapterAssembly.prepare(ChapterAssembly.generate(seed20, profiles.profiles, 21))
	check("ordinary opening generated", opening.ok, opening.get("reason", opening.get("code")))
	if not opening.ok: return finish()
	chapter_host = Native.new()
	var built: Dictionary = chapter_host._assemble(ChapterOpening.prepare_opening(opening.capture, "normal"))
	check("ordinary opening mounted", built.ok, built.get("reason"))
	if not built.ok: return finish()
	chapter_runtime = built.runtime
	var runtime := chapter_runtime
	check("intact village lowers second wave pressure", Night.wave_size({"wave":2,"night":1}, 2) == 3 and Night.wave_size({"wave":2,"night":1}, 1) == 4)
	check("no raid at spawn", phase(runtime) == "dormant" and not send(runtime, "night.start").ok)
	var workshop: Dictionary = runtime._services.modules.instance(BENCH20)
	var inputs: String = workshop.stock_refs.input
	var source: String = workshop.stock_refs.tools
	if not take_source(runtime, source, {"scrap":1}): return finish()
	var reached := near_stock(runtime, inputs)
	check("workshop delivery port is reachable", reached)
	if not reached: return finish()
	var paid: Dictionary = send(runtime, "deposit", inputs, {"items":{"scrap":1}})
	check("material physically delivered to the workshop", paid.ok, paid)
	if not paid.ok: return finish()
	for tick: int in 15: runtime.tick(0.1)
	check("delivery starts a preparation window", phase(runtime) == "ready", night(runtime))
	var starting := send(runtime, "night.start")
	check("player starts the night from the village", starting.ok and phase(runtime) == "warning", starting)
	if not starting.ok: return finish()
	check("outdoor expedition cannot activate during defense", not send(runtime, "expedition.depart").ok)
	# The same hook used by the Camera3D rejects every visible spawn candidate.
	runtime.set_night_screen_test(func(_p: Vector3) -> bool: return true)
	for tick: int in 135: runtime.tick(0.1)
	check("visible spawn sites defer the whole wave", phase(runtime) == "warning" and night(runtime).roster.is_empty())
	runtime.set_night_screen_test(func(p: Vector3) -> bool: return p.z < 10.0)
	for tick: int in 40:
		runtime.tick(0.1)
		if phase(runtime) == "fighting": break
	var state := night(runtime)
	check("three infected approach from off-screen village perimeter", state.phase == "fighting" and state.roster.size() == 3 and state.roster.all(func(id: String) -> bool: return float(runtime.actor(id).z) >= 10.0), state)
	check("actual directions reflect off-screen fallback", not state.get("approaches", []).is_empty() and "北边乡道" not in state.approaches, state)
	if state.phase != "fighting": return finish()
	var encoded: Dictionary = Store.encode(runtime.capture_checkpoint())
	var saved: Dictionary = Store.decode(encoded.get("text", "")) if encoded.ok else encoded
	var reopened: Dictionary = chapter_host._assemble(saved.capture) if saved.ok else saved
	check("mid-wave save reloads original roster", reopened.ok and night(reopened.runtime).roster == state.roster, reopened.get("reason"))
	if not reopened.ok: return finish()
	runtime.retire()
	runtime = reopened.runtime
	chapter_runtime = runtime
	for tick: int in 1030:
		runtime.tick(0.1)
		if phase(runtime) != "fighting": break

	check("automatic attacks clear the first wave", phase(runtime) == "between", [runtime.clock(), runtime.actor("player").get("hp"), night(runtime), night(runtime).roster.map(func(id: String) -> Array: var a: Dictionary = runtime.actor(id); return [a.get("x"),a.get("y"),a.get("z"),a.get("hp"),a.get("walker_brain")])])
	check("real attacks were recorded", runtime.facts().ledger.any(func(event: Dictionary) -> bool: return event.get("kind") == "combat-hit" and str(event.get("target_id", "")).begins_with("infected:village:night:")))
	if phase(runtime) == "between":
		check("choose one perk to start the second wave", send(runtime, "night.next", "", {"perk":"force"}).ok and night(runtime).perks == ["force"])
		for tick: int in 1140:
			runtime.tick(0.1)
			if phase(runtime) == "dawn": break
	check("both waves clear and the real damage is recorded at dawn", phase(runtime) == "dawn" and night(runtime).held and int(night(runtime).secured) == 2 and not night(runtime).damage.is_empty(), night(runtime))
	print("NIGHT OUTCOME ", JSON.stringify(night(runtime)))
	if phase(runtime) == "dawn":
		var reward := "materials" if seed20 == 713 else "crew"
		var item := "timber" if reward == "materials" else "scrap"
		var before: float = float(runtime.actor("player").pack.get(item, 0))
		var build_before: int = int(runtime.actor("repair-resident").skills.get("village_building", 0))
		var haul_before: int = int(runtime.actor("village-resident").skills.get("village_hauling", 0))
		check("dawn grants actual recovery resources once", send(runtime, "night.reward", "", {"reward":reward}).ok and phase(runtime) == "day" and float(runtime.actor("player").pack.get(item, 0)) > before and not send(runtime, "night.reward", "", {"reward":reward}).ok)
		if reward == "crew":
			check("crew reward trains both companions in their own specialties", int(runtime.actor("repair-resident").skills.get("village_building", 0)) == build_before + 2 and int(runtime.actor("village-resident").skills.get("village_hauling", 0)) == haul_before + 2)
	check_knockout(saved.capture)
	finish()

func night(runtime: RefCounted) -> Dictionary:
	var value: Variant = runtime.world.extension(Night.KEY)
	return value if value is Dictionary else Night.initial()

func phase(runtime: RefCounted) -> String:
	return str(night(runtime).phase)

func check_knockout(saved: Dictionary) -> void:
	# Start with a downed actor to isolate recovery from combat balance.
	var capture := saved.duplicate(true)
	for actor: Dictionary in capture.facts.actors:
		if actor.id == "player": actor.hp = 0.0
	var mounted: Dictionary = chapter_host._assemble(capture)
	check("a downed actor can load the in-flight defense", mounted.ok, mounted.get("code"))
	if not mounted.ok: return
	var runtime: RefCounted = mounted.runtime
	var timber: float = float(runtime.actor("player").pack.get("timber", 0.0))
	runtime.tick(0.1)
	var recovered: bool = phase(runtime) == "dawn" and Night.at_home(runtime.actor("player")) and float(runtime.actor("player").hp) > 0.0 and night(runtime).roster.is_empty()
	check("knockout preserves the world and returns control at dawn", recovered, night(runtime))
	if recovered:
		var result := send(runtime, "night.reward", "", {"reward":"supplies"})
		check("failed defense gives one emergency supply pack", result.ok and float(runtime.actor("player").pack.get("timber", 0)) == timber + 2 and not send(runtime, "night.reward", "", {"reward":"supplies"}).ok, result)
	runtime.retire()
