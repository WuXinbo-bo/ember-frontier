extends SceneTree
## Focused UI regression on an explicit real saved factory capture. This does
## not qualify the current generator, a formal app, OS input, or frame timing.
const Client = preload("res://scripts/runtime/native_client.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")
class TestClient extends Client:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var checks: Array = []
var output := ""
var host: Node3D
var runtime: RefCounted
var router: Node
var ui: Control
func _initialize() -> void: call_deferred("run")
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: print("FAIL " + label + " " + str(detail))
func flush() -> void:
	await process_frame
	await process_frame
func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = down
	root.push_input(event, true)
	await flush()
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2: quit(2); return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	var decoded: Dictionary = Store.decode(FileAccess.get_file_as_string(args[1]))
	check("explicit historical factory checkpoint decodes without modification", decoded.get("ok", false))
	if not decoded.get("ok", false): return finish()
	host = TestClient.new(); root.add_child(host)
	var assembled: Dictionary = host._assemble(decoded.capture)
	check("current Native assembles the real saved factory authority", assembled.get("ok", false), assembled.get("reason"))
	if not assembled.get("ok", false): return finish()
	runtime = assembled.runtime
	router = TestRouter.new(); host.add_child(router); router.configure(runtime)
	check("A modal policy API is actually available", router.has_method("set_modal_policy"))
	ui = Mount.mount(host, runtime, router); await flush()
	check("saved factory uses actual public factory facade", F.enabled(ui.factory))
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_panel("inventory"); await flush()
	ui.notify("当前容器容量不足，物品仍在原库存", true); await flush()
	check("modal failure survives hiding duplicate HUD", not ui._hud_backdrop.is_visible_in_tree() and ui._panel_notice.is_visible_in_tree() and ui._panel_notice.text == ui._notice.text and ui._panel_notice.text.contains("容量不足"))
	check("rendering failure feedback does not change real inventory", Data.json_equal(before, runtime.capture_checkpoint()))
	ui._expire_notice(ui._notice_serial); await flush()
	check("expired feedback clears both presentation surfaces", not ui._notice.visible and not ui._panel_notice.visible and ui._panel_notice.text.is_empty())
	check("inventory preserves the sole world pause", router.is_paused() and router.world_is_paused() and runtime.is_paused())
	ui.open_panel("factory_alerts"); await flush()
	check("WF07 still consumes all world input", router.state().pause_reasons.modal and router.is_paused())
	check("WF07 alone does not pause world settlement", not router.world_is_paused() and not runtime.is_paused() and ui._modal_policy_hint.text.contains("不暂停"))
	var time_before: float = runtime.clock()
	runtime.tick(0.1)
	check("WF07 advances the same runtime clock", runtime.clock() > time_before)
	var emitted := {"movement":0,"interact":0,"primary":0,"secondary":0}
	router.movement_requested.connect(func(_direction: Vector2, _delta: float): emitted.movement += 1)
	router.interact_requested.connect(func(): emitted.interact += 1)
	router.primary_requested.connect(func(down: bool):
		if down: emitted.primary += 1)
	router.secondary_requested.connect(func(): emitted.secondary += 1)
	var selected: int = router.state().selected
	for code: Key in [KEY_W, KEY_E, KEY_9]:
		await key(code, true); await key(code, false)
	for button_index: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		for down: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = Vector2(2, 2); event.global_position = event.position
			event.button_index = button_index; event.pressed = down
			root.push_input(event, true); await flush()
	check("live map input cannot move attack interact or change hand", emitted == {"movement":0,"interact":0,"primary":0,"secondary":0} and router.state().selected == selected and not router.state().held.primary, emitted)
	ui.open_panel("factory_confirm"); await flush()
	check("secondary confirmation restores world pause", runtime.is_paused() and router.world_is_paused())
	ui.cancel_ui(); await flush()
	check("cancelling confirmation returns to live map", ui.pages.back().page == "factory_alerts" and not runtime.is_paused())
	# A owns focus/file/save barriers. The UI must not overwrite these reasons.
	router.set_window_focus(false); ui._on_focus_exited(); await flush()
	check("focus loss overrides live viewing policy", runtime.is_paused() and router.state().pause_reasons.window_focus)
	router.set_window_focus(true); await flush()
	check("focus restoration retains map input barrier without paused clock", not runtime.is_paused() and router.is_paused() and not router.state().held.primary)
	router.set_file_dialog(true); await flush()
	check("native file barrier overrides live viewing policy", runtime.is_paused())
	router.set_file_dialog(false); await flush()
	check("closing file barrier returns to the same live map", not runtime.is_paused() and ui.pages.back().page == "factory_alerts")
	ui.saving = true; ui._sync_modal(); await flush()
	check("UI save in progress restores pausing modal policy", runtime.is_paused())
	ui.saving = false; ui._sync_modal(); await flush()
	check("save completion returns to live viewing policy", not runtime.is_paused())
	ui.open_panel("inventory"); await flush()
	check("navigation from live map to inventory pauses again", runtime.is_paused())
	ui.close_panels(); await flush()
	check("final close releases both modal policies and held input", ui.pages.is_empty() and not router.is_paused() and not runtime.is_paused() and not router.state().held.primary)
	finish()
func finish() -> void:
	var report := {"scope":"focused native Control feedback/modal policy on explicit real historical capture; current generation and formal OS/VA/performance not qualified", "checks":checks, "failed":checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()}
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	quit(1 if report.failed else 0)
