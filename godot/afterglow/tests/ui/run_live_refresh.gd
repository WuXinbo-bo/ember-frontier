extends SceneTree
## Bounded UI cost/feedback check, not an application, scene benchmark or OS test.
## Replays notifications and pack-location display changes; never ticks/moves the world.
const Client = preload("res://scripts/runtime/native_client.gd")
const RealRouter = preload("res://scripts/input/input_router.gd")
const Data = preload("res://scripts/world/world_data.gd")

class SeedClient extends Client:
	func _mount_ready(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		# Keep this source-level diagnostic offscreen and free of 3D mounts.
		return _mount(capture, assembly, fresh_profile)
	var fixture: Dictionary
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _mount(capture: Dictionary, _assembly: Dictionary = {}, _fresh: bool = false) -> Dictionary:
		fixture = capture.duplicate(true)
		return {"ok":true}

class Router extends RealRouter:
	func _persist_bindings() -> bool: return true

class ProjectionProbe extends RefCounted:
	signal changed(changes: Dictionary)
	var authority: RefCounted
	var calls := 0
	var snapshot_us: Array = []
	var location_offset := 0.0
	var controlled: Dictionary = {}
	func snapshot() -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary = authority.snapshot() if controlled.is_empty() else controlled.duplicate(true)
		snapshot_us.append(Time.get_ticks_usec() - start)
		calls += 1
		# Explicit display-only replay of A's real pack location field.
		if not result.get("stocks", []).is_empty():
			result.stocks[0].location.x = float(result.stocks[0].location.get("x", 0)) + location_offset
		return result
	func availability(request: Dictionary) -> Dictionary: return authority.availability(request)
	func command(request: Dictionary) -> Dictionary: return authority.command(request)
	func is_paused() -> bool: return authority.is_paused()
	func set_paused(value: bool) -> void: authority.set_paused(value)

var checks: Array = []
var output := ""
var mode := ""
var before_source := ""
var host: SeedClient
var authority: RefCounted
var probe: ProjectionProbe
var router: Router
var ui: Control
var measured: Dictionary = {}

func _initialize() -> void:
	create_timer(25).timeout.connect(func(): push_error("live refresh UI timeout"); finish(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok: push_error(name + " " + str(detail))

func flush() -> void:
	await process_frame
	await process_frame

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0,"mean_us":0.0,"p95_us":0.0,"sum_us":0.0}
	var sorted := values.duplicate(); sorted.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"count":values.size(),"mean_us":total / values.size(),"p95_us":sorted[mini(sorted.size()-1,int(ceil(sorted.size()*0.95))-1)],"sum_us":total}

func instrument(source: String) -> GDScript:
	# Instrument only an in-memory copy, not the production script on disk.
	var code := source
	code += "\nvar _cost_metrics: Dictionary = {\"refresh\":[],\"_render_target\":[],\"_render_hotbar\":[]}\n"
	for method: String in ["refresh", "_render_target", "_render_hotbar"]:
		code = code.replace("func " + method + "() -> void:", "func _cost_original" + method + "() -> void:")
		code += "\nfunc " + method + "() -> void:\n\tvar start := Time.get_ticks_usec()\n\t_cost_original" + method + "()\n\t_cost_metrics[\"" + method + "\"].append(Time.get_ticks_usec() - start)\n"
	var script := GDScript.new()
	script.source_code = code
	var error := script.reload()
	check("in-memory UI instrumentation compiles", error == OK, error)
	return script if error == OK else null

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3: quit(2); return
	output = args[0]; mode = args[1]; before_source = args[2]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	host = SeedClient.new(); root.add_child(host)
	var seed: Dictionary = host._new_rural(713)
	check("existing rural fixture prepares through A without 3D mount", seed.get("ok", false), seed)
	if not seed.get("ok", false): finish(1); return
	var assembly: Dictionary = host._assemble(host.fixture)
	check("A actual offscreen assembler and services configure", assembly.get("ok", false))
	if not assembly.get("ok", false): finish(1); return
	authority = assembly.runtime
	probe = ProjectionProbe.new(); probe.authority = authority
	authority.changed.connect(func(changes: Dictionary): probe.changed.emit(changes))
	router = Router.new(); host.add_child(router); router.configure(authority)
	var source := FileAccess.get_file_as_string(before_source if mode == "baseline" else "res://scripts/ui/game_ui.gd")
	var script := instrument(source)
	if script == null: finish(1); return
	ui = load("res://scenes/ui/game_ui.tscn").instantiate()
	ui.set_script(script) # Preserve the production scene's full-rect layout.
	ui.configure(probe, router); host.add_child(ui)
	await flush()
	var checkpoint: Dictionary = authority.capture_checkpoint()
	if mode == "geometry":
		await geometry_cases()
		check("geometry-only checks preserve actual world and time", Data.json_equal(checkpoint, authority.capture_checkpoint()))
		ui.queue_free(); router.queue_free(); await flush()
		host.queue_free(); await flush()
		finish(0 if checks.all(func(row: Dictionary) -> bool: return row.ok) else 1)
		return
	probe.calls = 0; probe.snapshot_us.clear()
	for values: Array in ui._cost_metrics.values(): values.clear()
	var replaced := 0
	var previous: int = ui._hotbar.get_child(0).get_instance_id()
	var start := Time.get_ticks_usec()
	for index in range(60):
		probe.location_offset = float(index + 1) * 0.001
		probe.changed.emit({"clock":float(index) / 60.0,"revision":index})
		probe.changed.emit({"world":[],"facts":[{"collection":"actors","id":"player"}],"events":[{"kind":"actor-moved","actor_id":"player"}],"revision":index})
		await process_frame
		var current: int = ui._hotbar.get_child(0).get_instance_id()
		if current != previous: replaced += 1
		previous = current
	var elapsed := Time.get_ticks_usec() - start
	await create_timer(0.14).timeout
	measured = {"frames":60,"replayed_notifications":120,"playback_us":elapsed,"snapshot_calls":probe.calls,"snapshot":stats(probe.snapshot_us),"hotbar_replacements":replaced}
	for method in ui._cost_metrics: measured[method] = stats(ui._cost_metrics[method])
	check("notification/cost replay does not mutate actual world facts or time", Data.json_equal(checkpoint, authority.capture_checkpoint()))
	if mode == "baseline":
		check("baseline confirms frame-frequency full snapshots", probe.calls >= 55, measured)
		check("baseline confirms location-only hotbar replacement", replaced >= 55, measured)
	else:
		var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(before_source.get_base_dir() + "/baseline-full-rect/results.json"))
		var old: Dictionary = baseline.get("measurement", {})
		check("replay full snapshots are bounded to 10Hz plus one trailing refresh", probe.calls <= ceili(float(elapsed) / 100000.0) + 2, measured)
		check("location-only changes preserve all hotbar objects", replaced == 0, measured)
		check("snapshot calls lower than fixed build8 replay", probe.calls * 3 < int(old.get("snapshot_calls", 0)), {"before":old.get("snapshot_calls"),"after":probe.calls})
		check("measured UI refresh total lower than build8 replay", measured.refresh.sum_us < float(old.get("refresh", {}).get("sum_us", 0)), {"before":old.get("refresh"),"after":measured.refresh})
		await feedback_and_lifecycle()
	ui.queue_free(); router.queue_free(); await flush()
	host.queue_free(); await flush()
	finish(0 if checks.all(func(row: Dictionary) -> bool: return row.ok) else 1)

func feedback_and_lifecycle() -> void:
	# Actual input/action commands continue to read their own current authority;
	# these view-only fixtures exercise invalidation and never submit a command.
	router._mode = "terrain_dig"
	authority.set_target({"id":"far","kind":"terrain","name":"挖掘","enabled":false,"reason":"实际格面超出手部触及距离"})
	ui.refresh(); await flush()
	check("far passive digging precheck no longer covers the scene", not ui._target.visible and ui._notice.text.is_empty())
	ui.report_action({"ok":false,"code":"UNREACHABLE","reason":"实际格面超出手部触及距离"})
	check("actual failed attempt still has readable feedback and diagnostics", ui._notice.visible and ui._notice.text.contains("超出") and ui._notice.tooltip_text.contains("UNREACHABLE"))
	ui.notify("")
	for reason in ["MISSING_TOOL", "MATERIAL_RESERVED"]:
		authority.set_target({"id":"blocked","kind":"terrain","name":"挖掘","enabled":false,"reason":reason})
		ui.refresh(); await flush()
		check("non-distance terrain precheck remains visible " + reason, ui._target.visible and not ui._target_text.text.contains("\n") and ui._target_text.tooltip_text.contains(reason))
	for target: Dictionary in [{"id":"near","kind":"terrain","name":"挖掘","enabled":true},{"id":"door","kind":"door","name":"旧宅门","action":"开门","enabled":true},{"id":"preview","kind":"placement","name":"木墙","enabled":false,"reason":"UNREACHABLE"}]:
		authority.set_target(target); ui.refresh(); await flush()
		check("near work door and invalid placement stay discoverable " + str(target.id), ui._target.visible and not ui._target_text.text.is_empty())
	probe.controlled = authority.snapshot()
	probe.controlled.stocks[0].items["water"] = 4
	probe.controlled.stocks[0].items["food"] = 2
	probe.controlled.target = {"id":"under-consumable","kind":"terrain","name":"挖掘","enabled":true}
	router._mode = "tool"
	router._slots[0] = {"kind":"item","id":"water"}; router._selected = 0
	ui.refresh(); await flush()
	check("selected real water names use action instead of generic shovel", ui._mode_hint.text.contains("饮水") and ui._mode_hint.text.contains("右键使用") and not ui._mode_hint.text.contains("铲") and not ui._target.visible, ui._mode_hint.text)
	router._slots[6] = {"kind":"item","id":"water"}; router.select_slot(6); await flush()
	check("slot seven water agrees with current selected label and icon cell", ui._mode_hint.text.contains("饮水") and ui._hotbar.get_child(6).visual_state.selected and ui._hotbar.get_child(6).visual_state.quantity == 4 and not ui._target.visible)
	router._slots[1] = {"kind":"item","id":"food"}; router.select_slot(1); await flush()
	check("selected food immediately replaces water description", ui._mode_hint.text.contains("食物") and not ui._mode_hint.text.contains("铲") and not ui._target.visible, ui._mode_hint.text)
	probe.controlled.target = {"id":"door-with-food","kind":"door","name":"旧宅门","action":"开门","enabled":true}
	ui.refresh(); await flush()
	check("holding food preserves nearby door interaction prompt", ui._target.visible and ui._target_text.text.contains("开门"))
	probe.controlled.target = {"id":"npc-with-food","kind":"npc","name":"周婶","action":"交谈","enabled":true}
	ui.refresh(); await flush()
	check("holding food preserves nearby NPC prompt", ui._target.visible and ui._target_text.text.contains("交谈"))
	router.select_slot(0); await flush()
	var slot: int = ui._hotbar.get_child(0).get_instance_id()
	ui._hotbar.get_child(0).grab_focus()
	router._primary = true; router._pressed["run"] = true
	probe.changed.emit({"clock":1,"revision":1}); await create_timer(0.12).timeout
	check("held run primary and pack position do not rebuild hotbar", slot == ui._hotbar.get_child(0).get_instance_id())
	check("location notification preserves native hotbar keyboard focus", root.gui_get_focus_owner() == ui._hotbar.get_child(0))
	probe.controlled.stocks[0].items.water = 3
	probe.changed.emit({"world":[],"facts":[{"collection":"stocks","id":"pack:player"}],"events":[],"revision":2})
	await flush()
	check("real item quantity invalidation is immediate", slot != ui._hotbar.get_child(0).get_instance_id() and ui._hotbar.get_child(0).visual_state.quantity == 3)
	slot = ui._hotbar.get_child(0).get_instance_id()
	probe.controlled.stocks[0].reserved = {"items":{"water":2},"tool_ids":[]}
	probe.changed.emit({"revision":3}); await flush()
	check("unknown revision notification fails open to immediate refresh", slot != ui._hotbar.get_child(0).get_instance_id() and ui._hotbar.get_child(0).visual_state.available == 1)
	var definition: Dictionary = probe.controlled.catalog.tool_definitions.salvaged_axe
	probe.controlled.tools = [{"id":"ui-live:axe","definitionId":"salvaged_axe","holderId":"pack:player","durability":20.0}]
	router._slots[2] = {"kind":"tool","id":"ui-live:axe"}; router.select_slot(2); await flush()
	check("tool label resolves published definition instead of generic digging", ui._mode_hint.text.contains(str(definition.name)) and ui._hotbar.get_child(2).visual_state.durability == 20)
	slot = ui._hotbar.get_child(2).get_instance_id()
	probe.controlled.tools[0].durability = 19.0
	probe.changed.emit({"revision":4}); await flush()
	check("referenced tool wear invalidates shortcut visuals", slot != ui._hotbar.get_child(2).get_instance_id() and ui._hotbar.get_child(2).visual_state.durability == 19)
	probe.controlled.tools[0].reserved = true
	probe.changed.emit({"revision":5}); await flush()
	check("referenced reserved tool stays visible and unavailable", ui._hotbar.get_child(2).visual_state.available == 0 and ui._mode_hint.text.contains("已预留"))
	probe.controlled.tools[0].holderId = "pack:someone-else"
	probe.changed.emit({"revision":6}); await flush()
	check("tool leaving pack does not retain stale usable reference", ui._hotbar.get_child(2).visual_state.unavailable and ui._mode_hint.text.contains("不可用"))
	slot = ui._hotbar.get_child(2).get_instance_id()
	probe.controlled.stocks.append({"id":"unrelated","searched":true,"owner":"other","items":{"food":9},"location":{"x":99}})
	probe.changed.emit({"revision":7}); await flush()
	check("unrelated container contents do not rebuild shortcut visuals", slot == ui._hotbar.get_child(2).get_instance_id())
	router.select_slot(0); await flush()
	ui.drag = {"controlled_gui_hold":true}
	slot = ui._hotbar.get_child(0).get_instance_id()
	probe.controlled.stocks[0].items.water = 2
	probe.changed.emit({"revision":8}); await flush()
	check("pending inventory drag retains native source cell", slot == ui._hotbar.get_child(0).get_instance_id())
	ui.drag.clear(); ui.queue_refresh(); await flush()
	check("ending drag applies deferred real quantity projection", ui._hotbar.get_child(0).visual_state.quantity == 2)
	probe.controlled.stocks[0].items.water = 0
	probe.changed.emit({"revision":4}); await flush()
	check("exhausted reference is not advertised as usable drinking", ui._mode_hint.text.contains("耗尽") and not ui._mode_hint.text.contains("右键使用"), ui._mode_hint.text)
	probe.calls = 0
	probe.changed.emit({"save":true}); await flush()
	check("save change bypasses live display throttling", probe.calls >= 1)
	probe.calls = 0
	router.changed.emit(); await flush()
	check("router changes bypass live display throttling", probe.calls >= 1)
	# A queued low-priority timer must not redraw after a forced full refresh.
	ui.refresh(); probe.calls = 0
	probe.changed.emit({"clock":2,"revision":4})
	probe.changed.emit({"save":true}); await flush()
	var immediate: int = probe.calls
	await create_timer(0.13).timeout
	check("urgent refresh consumes queued temporal refresh without trailing duplicate", immediate >= 1 and probe.calls == immediate, {"immediate":immediate,"after":probe.calls})
	await geometry_cases()
	probe.controlled.clear()
	ui.refresh(); probe.changed.emit({"clock":3,"revision":5})
	ui.configure(probe, router); await flush(); probe.calls = 0
	await create_timer(0.13).timeout
	check("configure generation ignores old low-priority timer", probe.calls == 0, probe.calls)
	ui.refresh(); probe.changed.emit({"clock":4,"revision":6})
	ui.queue_free(); await create_timer(0.13).timeout
	check("freeing UI cancels pending signal delivery safely", not is_instance_valid(ui))
	# Supply a fresh UI to the caller's normal teardown without callbacks.
	ui = Control.new(); host.add_child(ui)

func geometry_cases() -> void:
	if probe.controlled.is_empty(): probe.controlled = authority.snapshot()
	for viewport_size: Vector2i in [Vector2i(1000,700),Vector2i(1280,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		for factor: float in [1.0,1.5]:
			ui.set_text_scale(factor)
			router._mode = "terrain_dig"
			authority.set_target({"id":"near","kind":"terrain","name":"挖掘","enabled":true})
			probe.controlled.target = authority.snapshot().target
			ui.refresh(); await flush()
			check("compact terrain prompt protects hotbar " + str(viewport_size) + " " + str(factor), ui.size == Vector2(viewport_size) and not ui._target_text.text.contains("\n") and ui._target.size.y <= 80 * factor and ui._target.get_global_rect().end.y <= ui._hotbar.get_global_rect().position.y and ui._target.get_global_rect().end.x <= viewport_size.x, {"ui":str(ui.size),"text":ui._target_text.text,"target":str(ui._target.get_global_rect()),"hotbar":str(ui._hotbar.get_global_rect())})

func finish(code: int) -> void:
	if not output.is_empty():
		var f := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok":code == 0,"mode":mode,"checks":checks,"measurement":measured,"scope":"Isolated actual A runtime.snapshot and B/C composition; controlled notification/pack-location display replay; instrumented UI only in memory; no simulation tick or real movement, formal application, OS/VA/performance acceptance","formal_application_launched":false,"overall_acceptance":false},"\t",true,true)); f.close()
	print("UI live refresh " + mode + " " + str(checks.size()) + " checks exit " + str(code))
	quit(code)
