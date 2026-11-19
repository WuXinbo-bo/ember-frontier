extends "res://tests/integration/run_village_night.gd"
## Desktop run with --normal-profile, --seed, and a marked absolute --qa-data-root.
const COMBAT_EFFECTS = preload("res://scripts/presentation/expedition_effects.gd")
const FIGHT_FRAME_SAMPLE_US := 7000000
var evidence_dir := ""
var combat_effects: Node3D
var spawn_screens: Array[Dictionary] = []
var combat_hits := 0
var impact_cues := 0
var player_hit_cues := 0
var impact_shot: Image
var sample_start_us := 0
var previous_draw_us := 0
var sample_elapsed_us := 0
var draw_intervals: Array[float] = []

func run() -> void:
	started20 = Time.get_ticks_msec()
	var options: Dictionary = Native.startup_options(OS.get_cmdline_user_args())
	var isolated: bool = options.get("ok", false) and options.get("new_world_profile") == "normal" and options.has("qa_data_root") and int(options.get("seed", -1)) >= 0 and not options.get("resume", false)
	check("seeded desktop normal-profile run has an isolated QA root", isolated and DisplayServer.get_name() != "headless", options)
	if not isolated or DisplayServer.get_name() == "headless": return finish()
	evidence_dir = str(options.qa_data_root)
	seed20 = int(options.seed)
	if not FileAccess.file_exists(evidence_dir.path_join("afterglow-qa-root.json")):
		check("isolated QA root has its startup marker", false, evidence_dir)
		return finish()
	chapter_host = Native.new()
	root.add_child(chapter_host)
	var boot_deadline := Time.get_ticks_msec() + 75000
	while not chapter_host._ready_game and Time.get_ticks_msec() < boot_deadline:
		await process_frame
	check("native scene loads an ordinary opening", chapter_host._ready_game)
	if not chapter_host._ready_game: return finish()
	chapter_runtime = chapter_host.runtime
	var runtime := chapter_runtime
	chapter_host.ui.close_panels()
	chapter_host.router.set_window_focus(true)
	await process_frame
	for child: Node in chapter_host.scene_root.get_children():
		if child.get_script() == COMBAT_EFFECTS:
			combat_effects = child as Node3D
			break
	var camera: Camera3D = chapter_host.camera
	var screen: Callable = runtime.domain_service("gameplay").night_screen_test
	var native_basis: bool = root.get_camera_3d() == camera and screen.is_valid() and screen.get_object() == chapter_host and str(screen.get_method()) == "_night_point_visible"
	check("defense uses the active Native camera visibility callback", native_basis)
	check("mounted scene contains real combat effects", is_instance_valid(combat_effects))
	check("ordinary opening starts without a raid", phase(runtime) == "dormant")
	if not native_basis or not is_instance_valid(combat_effects): return finish()
	var sun: DirectionalLight3D = chapter_host._settlement_lights.sun
	var day_energy: float = sun.light_energy
	await shot("night-00-day")
	var workshop: Dictionary = runtime._services.modules.instance(BENCH20)
	var input_id: String = workshop.stock_refs.input
	var source_id: String = workshop.stock_refs.tools
	if not take_source(runtime, source_id, {"scrap":1}): return finish()
	if not near_stock(runtime, input_id):
		check("the actual input is reachable", false, input_id)
		return finish()
	var before: float = float(runtime.stock(input_id).items.get("scrap", 0))
	var delivered := send(runtime, "deposit", input_id, {"items":{"scrap":1}})
	var real_delivery: bool = delivered.ok and float(runtime.stock(input_id).items.get("scrap", 0)) == before + 1.0
	check("ordinary player physically transfers material into the workshop", real_delivery, delivered)
	if not real_delivery: return finish()
	var ready_deadline := Time.get_ticks_msec() + 8000
	var ready_button: Button = null
	while Time.get_ticks_msec() < ready_deadline:
		await process_frame
		ready_button = start_button()
		if phase(runtime) == "ready" and is_instance_valid(ready_button): break
	var ready: bool = phase(runtime) == "ready" and is_instance_valid(ready_button)
	check("material delivery exposes a visible start-defense button", ready, night(runtime))
	if not ready: return finish()
	runtime.changed.connect(record_night_events)
	ready_button.pressed.emit()
	check("actual HUD button enters the warning", phase(runtime) == "warning", night(runtime))
	if phase(runtime) != "warning": return finish()
	var light_deadline := Time.get_ticks_msec() + 4500
	while (sun.light_energy >= day_energy - 0.20 or sun.light_color.b <= sun.light_color.r) and Time.get_ticks_msec() < light_deadline:
		await process_frame
	check("live night lighting darkens and cools the settlement", sun.light_energy < day_energy - 0.20 and sun.light_color.b > sun.light_color.r, [day_energy, sun.light_energy, sun.light_color])
	await shot("night-01-warning")
	var spawn_deadline := Time.get_ticks_msec() + 26000
	while spawn_screens.is_empty() and Time.get_ticks_msec() < spawn_deadline:
		await process_frame
	var hidden: bool = spawn_screens.size() == 3 and spawn_screens.all(func(row: Dictionary) -> bool: return not row.visible)
	check("first wave publishes three real infected outside the active camera", hidden, spawn_screens)
	if not hidden: return finish()
	await shot("night-02-first-wave")
	# Walk out to meet the wave: waiting at the delivery port does not exercise
	# the normal player loop of reading the warning and moving to intercept.
	for id: String in night(runtime).roster:
		var walker: Dictionary = runtime.actor(id)
		var target := G.location(walker)
		var contact := G.point(walker).lerp(G.point(runtime.actor("player")), 0.14)
		target.x = contact.x
		target.z = contact.z
		var standing: Dictionary = runtime._services.buildings.current_space().standing_point(target)
		if not standing.is_empty() and send(runtime, "walk", "", {}, standing).ok: break
	var fight_deadline := Time.get_ticks_msec() + 44000
	while (impact_cues == 0 or impact_shot == null) and Time.get_ticks_msec() < fight_deadline:
		await process_frame
	check("committed live defense hits trigger the scene impact effect", combat_hits > 0 and impact_cues > 0, {"hits":combat_hits,"impact_cues":impact_cues,"player_hit_cues":player_hit_cues,"night":night(runtime),"clock":runtime.clock()})
	save_shot("night-03-impact", impact_shot)
	if impact_cues == 0: return finish()
	# Start after the render readback and PNG write so neither enters the sample.
	RenderingServer.frame_post_draw.connect(record_draw)
	var sample_deadline := Time.get_ticks_msec() + 12000
	while sample_elapsed_us < FIGHT_FRAME_SAMPLE_US and Time.get_ticks_msec() < sample_deadline:
		await process_frame
	RenderingServer.frame_post_draw.disconnect(record_draw)
	check("short live frame sample spans seven seconds", sample_elapsed_us >= FIGHT_FRAME_SAMPLE_US and not draw_intervals.is_empty(), draw_intervals.size())
	print_draw_metrics()
	finish()

func start_button() -> Button:
	for child: Node in chapter_host.ui._expedition_hud._actions.get_children():
		if child is Button and child.is_visible_in_tree() and not child.disabled and str(child.get_meta("ui_focus_key", "")).begins_with("night:start:"):
			return child
	return null

func record_night_events(delta: Dictionary) -> void:
	var runtime := chapter_runtime
	for event: Dictionary in delta.get("events", []):
		if event.get("kind") == "village-defense-wave" and int(event.get("wave", 0)) == 1 and spawn_screens.is_empty():
			for id: String in night(runtime).roster:
				var point := G.point(runtime.actor(id))
				spawn_screens.append({"id":id,"visible":chapter_host._night_point_visible(point),"screen":chapter_host.camera.unproject_position(point)})
		if event.get("kind") != "combat-hit": continue
		var target_id := str(event.get("target_id", ""))
		var enemy_id := str(event.get("actor_id", ""))
		if not target_id.begins_with("infected:village:night:") and not enemy_id.begins_with("infected:village:night:"): continue
		combat_hits += 1
		var impact: AudioStreamPlayer = combat_effects.get("_audio").get("impact")
		var pool: Array = combat_effects.get("_pool")
		var tint := Color("ed715b") if target_id == "player" else Color("ff9970")
		if impact.playing and pool.any(func(row: Dictionary) -> bool: return float(row.remaining) > 0 and row.get("tint") == tint and row.view.visible):
			impact_cues += 1
			if target_id == "player": player_hit_cues += 1
			if impact_cues == 1:
				RenderingServer.frame_post_draw.connect(capture_impact, CONNECT_ONE_SHOT)

func record_draw() -> void:
	var now := Time.get_ticks_usec()
	if previous_draw_us == 0:
		sample_start_us = now
	elif sample_elapsed_us < FIGHT_FRAME_SAMPLE_US:
		draw_intervals.append(float(now - previous_draw_us) / 1000.0)
		sample_elapsed_us = now - sample_start_us
	previous_draw_us = now

func print_draw_metrics() -> void:
	if draw_intervals.is_empty(): return
	var elapsed: float = 0.0
	for interval: float in draw_intervals: elapsed += interval
	draw_intervals.sort()
	var count := draw_intervals.size()
	print("NIGHT GRAPHICS ", JSON.stringify({"frames":count,"elapsed_ms":elapsed,"fps":count * 1000.0 / elapsed,"p95_ms":draw_intervals[ceili(count * 0.95) - 1],"p99_ms":draw_intervals[ceili(count * 0.99) - 1],"max_ms":draw_intervals[-1],"hits":combat_hits,"impact_cues":impact_cues,"player_hit_cues":player_hit_cues}))

func shot(stem: String) -> void:
	var capture := func() -> void: save_shot(stem, root.get_texture().get_image())
	RenderingServer.frame_post_draw.connect(capture, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + 5000
	while RenderingServer.frame_post_draw.is_connected(capture) and Time.get_ticks_msec() < deadline:
		await process_frame
	if RenderingServer.frame_post_draw.is_connected(capture):
		RenderingServer.frame_post_draw.disconnect(capture)
		check("render deadline reached before screenshot: " + stem, false)

func capture_impact() -> void:
	impact_shot = root.get_texture().get_image()

func save_shot(stem: String, image: Image) -> void:
	var result: Error = ERR_UNAVAILABLE
	if image != null and not image.is_empty(): result = image.save_png(evidence_dir.path_join(stem + ".png"))
	check("screenshot captured: " + stem, result == OK, result)
