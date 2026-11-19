extends "res://tests/integration/run_village_expedition.gd"
## Run with --normal-profile and a marked isolated --qa-data-root.
var out_dir: String
var cues := {"club":0,"bow":0,"impact":0}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-data-root="): out_dir = arg.trim_prefix("--qa-data-root=")
	if not check(not out_dir.is_empty(), "isolated graphics root is configured"): return finish()
	host = Native.new()
	root.add_child(host)
	var timeout := Time.get_ticks_msec() + 75000
	while not host._ready_game and Time.get_ticks_msec() < timeout:
		await process_frame
	if not check(host._ready_game,"native scene opens at normal profile"): return finish()
	runtime = host.runtime
	host.ui.close_panels()
	host.router.set_window_focus(true)
	await process_frame
	var expedition_hud: Variant = host.ui._expedition_hud
	if not check(expedition_hud.is_visible_in_tree() and expedition_hud._title.text.contains("米"), "opening HUD guides the player to the supply crate"):
		return finish()
	await shot("00-opening-guide")
	if not check(travel(E.SITE), "scene receives real movement to crate"): return finish()
	await create_timer(0.8).timeout
	await shot("01-supply-site")
	var open_button: Button = null
	for child in expedition_hud._actions.get_children():
		if child is Button and child.text.begins_with("开箱"):
			open_button = child
			break
	if not check(is_instance_valid(open_button) and open_button.is_visible_in_tree(), "nearby crate offers a direct open button"):
		return finish()
	open_button.pressed.emit()
	if not check(runtime.expedition_snapshot().phase == "warning", "actual HUD button starts the first warning"):
		return finish()
	await create_timer(.55).timeout
	await shot("02-warning")
	runtime.changed.connect(on_combat)
	for i: int in 280:
		if runtime.expedition_snapshot().phase == "between": break
		await create_timer(.1).timeout
	if not check(cues.club > 0 and cues.impact > 0,"club arc and impact received committed damage events",cues): return finish()
	check(runtime.expedition_snapshot().phase == "between","first wave ends in live window")
	if not check(send("expedition.next",{"perk":"tempo"}).ok,"live window accepts second wave"): return finish()
	var frame_intervals: Array[float] = []
	var last := Time.get_ticks_usec()
	var until := last+9000000
	while Time.get_ticks_usec() < until:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_intervals.append(float(now-last)/1000.0)
		last=now
	check(cues.bow > 0,"arrow trail consumed a committed ranged hit",cues)
	frame_intervals.sort()
	var count := frame_intervals.size()
	print("EXPEDITION GRAPHICS ",JSON.stringify({"frames":count,"fps":float(count)*1000.0/float(last-(until-9000000))*1000.0,"p95_ms":frame_intervals[floori(float(count-1)*.95)],"p99_ms":frame_intervals[floori(float(count-1)*.99)],"max_ms":frame_intervals[-1]}))
	finish()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null and not image.is_empty(): image.save_png(out_dir.path_join(name+".png"))

func on_combat(change: Dictionary) -> void:
	for event: Dictionary in change.get("events", []):
		var weapon: String = str(event.get("weapon",""))
		if event.kind == "combat-hit" and weapon in ["club","bow"]:
			cues.impact += 1
			if cues[weapon] == 0: shot.call_deferred("03-"+weapon)
			cues[weapon] += 1
