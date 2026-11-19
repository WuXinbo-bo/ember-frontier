extends SceneTree
## Real router callbacks through Viewport input, including a release over GUI.
const Router = preload("res://scripts/input/input_router.gd")
class RuntimeProbe extends RefCounted:
	func set_hand(_hand: Dictionary) -> void: pass
	func set_paused(_paused: bool) -> void: pass

var failures: Array[String] = []
var count := 0
var primary_edges: Array[bool] = []
var confirmations := 0
var uses := 0
var router: Node

func _initialize() -> void:
	call_deferred("run")

func check(label: String, pass_check: bool) -> void:
	count += 1
	if not pass_check:
		failures.append(label)
		push_error(label)

func mouse(button: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	root.push_input(event)

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)

func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var controls := output.path_join("controls.json")
	var file := FileAccess.open(controls, FileAccess.WRITE)
	file.store_string(JSON.stringify({"bindings": {"interact": KEY_F, "rotate": KEY_U}}))
	file.close()
	router = Router.new()
	router.controls_path = controls
	root.add_child(router)
	router.configure(RuntimeProbe.new())
	router.primary_requested.connect(func(edge: bool): primary_edges.append(edge))
	router.confirm_requested.connect(func(): confirmations += 1)
	router.consume_requested.connect(func(): uses += 1)
	check("legacy F and U are retained while use is unbound", router.state().bindings.interact.keycode == KEY_F and router.state().bindings.rotate.keycode == KEY_U and router.state().bindings.consume.keycode == KEY_NONE)
	check("use can be bound without resetting legacy controls", router.bind_key("consume", KEY_H).ok)
	key(KEY_H)
	key(KEY_H, true, true)
	key(KEY_H, false)
	check("use signal is edge-triggered", uses == 1)

	root.size = Vector2i(800, 600)
	var panel := LineEdit.new()
	panel.position = Vector2(60, 60)
	panel.size = Vector2(220, 60)
	root.add_child(panel)
	await process_frame
	var world := Vector2(420, 260)
	var gui := Vector2(90, 90)
	primary_edges.clear()
	mouse(MOUSE_BUTTON_LEFT, true, world)
	mouse(MOUSE_BUTTON_LEFT, false, gui)
	check("release over GUI ends captured world hold", primary_edges == [true, false] and not router.state().held.primary)
	primary_edges.clear()
	mouse(MOUSE_BUTTON_LEFT, true, gui)
	mouse(MOUSE_BUTTON_LEFT, false, world)
	check("GUI press cannot start world hold", primary_edges.is_empty())
	panel.release_focus()

	mouse(MOUSE_BUTTON_RIGHT, true, world)
	check("right press arms combat", router.combat_ready())
	mouse(MOUSE_BUTTON_RIGHT, false, gui)
	check("right release over GUI ends hold-to-ready", not router.combat_ready())
	check("toggle preference is writable", router.set_combat_toggle(true).ok)
	mouse(MOUSE_BUTTON_RIGHT, true, world)
	mouse(MOUSE_BUTTON_RIGHT, false, world)
	check("toggle survives mouse release", router.combat_ready())
	router.set_modal_policy(true, false)
	check("live modal clears combat and owns world input", not router.combat_ready() and router.is_paused() and not router.world_is_paused())
	router.set_modal_policy(false)
	key(KEY_SHIFT)
	check("run holds before focus loss", router.run_held())
	router.set_window_focus(false)
	router.set_window_focus(true)
	check("focus return needs fresh run input", not router.run_held())
	key(KEY_ENTER)
	check("plain tool mode does not treat Enter as confirmation", confirmations == 0)
	router.set_world_pointer_consumer(Callable(), func() -> bool: return true)
	key(KEY_ENTER)
	key(KEY_ENTER, true, true)
	check("Enter reaches the active zone exactly once", confirmations == 1)
	router.set_modal_policy(true)
	key(KEY_KP_ENTER)
	check("modal blocks world confirmation", confirmations == 1)
	router.set_modal_policy(false)
	router.set_world_pointer_consumer(Callable())
	router.set_mode("module_place")
	key(KEY_KP_ENTER)
	router.confirm_placement()
	check("placement Enter and button dispatch the same confirmation signal", confirmations == 3)
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": count, "failures": failures}, "\t"))
	print("Interaction input %d/%d" % [count - failures.size(), count])
	quit(0 if failures.is_empty() else 1)
