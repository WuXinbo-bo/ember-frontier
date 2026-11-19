extends "res://tests/ui/run_service_access_ui.gd"
## Real Native authority, original Router, actual Viewport keys/clicks and disk
## preferences. Saving uses a counted receipt boundary, never a user save.
const RealRouter = preload("res://scripts/input/input_router.gd")
const Opening = preload("res://scripts/runtime/playtest_profile.gd")
class ControlsHost extends Client:
	var saves := 0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func save_async(request_id: String = "") -> Dictionary:
		saves += 1
		return {"ok":true,"code":"OK","request_id":request_id,"reason":"isolated counted save boundary"}

func tap_key(code: int, shift: bool = false, ctrl: bool = false, meta: bool = false) -> void:
	for down: bool in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code; event.keycode = code; event.pressed = down
		event.shift_pressed = shift; event.ctrl_pressed = ctrl; event.meta_pressed = meta
		root.push_input(event, true); await flush()

func click_key(key: String) -> bool:
	var action := keyed(key, ui) as Button
	check("visible enabled native button " + key, action != null and action.is_visible_in_tree() and not action.disabled)
	if action == null or not action.is_visible_in_tree() or action.disabled: return false
	if ui._scroll.is_ancestor_of(action): ui._scroll.ensure_control_visible(action)
	await flush()
	var motion := InputEventMouseMotion.new()
	motion.position = action.get_global_rect().get_center(); motion.global_position = motion.position
	root.push_input(motion, true); await flush()
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = action.get_global_rect().get_center(); event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event, true); await flush()
	return true

func run() -> void:
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800); root.content_scale_size = root.size
	host = ControlsHost.new(); root.add_child(host)
	var profiles: Dictionary = Assembly.generation_profiles()
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713, profiles.profiles))
	check("current normal opening prepares", prepared.get("ok",false), prepared.get("reason"))
	if not prepared.get("ok",false): return finish()
	var raw_capture:Dictionary=prepared.capture.duplicate(true)
	prepared.capture=Opening.prepare_opening(prepared.capture,"normal")
	var made: Dictionary = host._assemble(prepared.capture)
	check("actual Native owner assembly", made.get("ok",false), made.get("reason"))
	if not made.get("ok",false): return finish()
	runtime = made.runtime; router = RealRouter.new()
	router.controls_path = output + "/actual-controls.json"
	# Reset only this test-owned preference file for repeatable default coverage.
	if FileAccess.file_exists(router.controls_path): DirAccess.remove_absolute(router.controls_path)
	host.add_child(router); router.configure(runtime, false, true)
	ui = Mount.mount(host, runtime, router); await flush()
	var original: Dictionary = runtime.capture_checkpoint()
	var starting:Dictionary=router.state()
	var held:Dictionary=runtime.tool(str(starting.slots[0].get("id","")))
	check("fresh normal hotbar holds the actual transferred axe",starting.selected==0 and starting.slots[0].get("kind")=="tool" and held.get("kind")=="salvaged_axe" and held.get("holderId")=="pack:player",starting.slots[0])
	check("default published binding has exact Tab and I alias", router.state().bindings.inventory.keycode == KEY_TAB and router.state().bindings.inventory.aliases == [{"keycode":KEY_I,"label":"I"}])
	for code: int in [KEY_TAB,KEY_I]:
		await tap_key(code)
		check("world native key opens backpack " + str(code), not ui.pages.is_empty() and ui.pages.back().page == "factory_inventory")
		await tap_key(code)
		check("same native key closes backpack " + str(code), ui.pages.is_empty())
	var hotbar := keyed("hotbar:0",ui)
	if hotbar == null:
		for child: Node in ui._hotbar.get_children():
			if child is Button: hotbar = child; break
	check("real hotbar focus target exists", hotbar != null)
	if hotbar != null: hotbar.grab_focus(); await flush()
	await tap_key(KEY_TAB)
	check("Tab opens before GUI hotbar traversal", not ui.pages.is_empty() and ui.pages.back().page == "factory_inventory")
	await tap_key(KEY_I)
	check("I closes Tab-opened inventory", ui.pages.is_empty())
	if await click_key("hud:personal:inventory"):
		check("actual persistent backpack click opens inventory", not ui.pages.is_empty() and ui.pages.back().page == "factory_inventory")
	await tap_key(KEY_TAB)
	if await click_key("hud:personal:pause"):
		check("actual persistent pause click opens pause", not ui.pages.is_empty() and ui.pages.back().page == "pause")
	if await click_key("pause:settings"):
		check("actual pause settings click opens settings", ui.pages.back().page == "settings")
	if await click_key("bind:inventory"):
		await tap_key(KEY_I,true)
		check("real capture binds Shift I and ends capture", ui.capture_action.is_empty() and router.state().bindings.inventory.keycode == (KEY_I|KEY_MASK_SHIFT))
		check("remapping inventory releases default alias", router.state().bindings.inventory.aliases.is_empty())
	await tap_key(KEY_ESCAPE); ui.close_panels(); await flush()
	await tap_key(KEY_I,true)
	check("modified world key opens backpack", not ui.pages.is_empty() and ui.pages.back().page == "factory_inventory")
	await tap_key(KEY_I,true)
	check("same modified key closes backpack", ui.pages.is_empty())
	await tap_key(KEY_I)
	check("old alias does not silently remain active after remap", ui.pages.is_empty())
	router.assign_slot(8,{"kind":"item","id":"water"});router.select_slot(8)
	var reloaded := RealRouter.new(); reloaded.controls_path = router.controls_path; reloaded.configure(runtime)
	check("actual disk preferences reload modified binding", reloaded.state().bindings.inventory.keycode == (KEY_I|KEY_MASK_SHIFT))
	check("loading preserves saved selected slot and hotbar references",reloaded.state().selected==8 and reloaded.state().slots==router.state().slots)
	reloaded.free()
	check("released I can be assigned to another action", router.bind_key("build",KEY_I).ok)
	check("default inventory refuses alias conflict", router.bind_key("inventory",KEY_TAB).code == "KEY_CONFLICT")
	check("Ctrl S cannot be rebound", router.bind_key("map",KEY_S|KEY_MASK_CTRL).code == "RESERVED_KEY")
	check("Meta S cannot be rebound", router.bind_key("map",KEY_S|KEY_MASK_META).code == "RESERVED_KEY")
	router.reset_bindings(); await flush()
	check("active default I alias refuses conflicting remap", router.bind_key("build",KEY_I).code == "KEY_CONFLICT")
	ui.open_panel("settings"); await flush()
	var edit := LineEdit.new(); ui._body.add_child(edit); edit.grab_focus(); await flush()
	await tap_key(KEY_I)
	check("native text input keeps page and text focus", not ui.pages.is_empty() and ui.pages.back().page == "settings" and root.gui_get_focus_owner() == edit)
	edit.queue_free(); ui.close_panels(); await flush()
	await tap_key(KEY_S,false,true)
	check("world Ctrl S dispatches exactly one save receipt", host.saves == 1,host.saves)
	ui.open_panel("pause"); await flush()
	await tap_key(KEY_S,false,true)
	check("pause Ctrl S dispatches exactly one save receipt", host.saves == 2,host.saves)
	await tap_key(KEY_S,false,false,true)
	check("pause Meta S preserves mac save shortcut", host.saves == 3,host.saves)
	check("control navigation does not mutate world facts", Data.json_equal(original,runtime.capture_checkpoint()))
	var playtest:Dictionary=host._assemble(Opening.prepare_opening(raw_capture,"playtest"))
	check("actual five-tool profile assembles",playtest.get("ok",false),playtest.get("reason"))
	if playtest.get("ok",false):
		var tester:=RealRouter.new();tester.controls_path=output+"/actual-five-tools-controls.json";tester.configure(playtest.runtime,true,true)
		var state:Dictionary=tester.state()
		var kinds:Array=[]
		for index:int in 5:
			var tool:Dictionary=playtest.runtime.tool(str(state.slots[index].get("id","")))
			if tool.get("holderId")=="pack:player":kinds.append(str(tool.get("kind","")))
		check("fresh playtest hotbar uses five real registered tools",kinds==["salvaged_axe","shovel","pickaxe","hammer","hand_saw"] and state.selected==0,kinds)
		tester.free()
	observed.append({"save_boundary":"counted request-matched receipt; no disk world save","preferences":router.controls_path,"ui_input":"actual root.push_input keys and mouse buttons"})
	finish()

func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"Current Native authority, actual Viewport UI input and isolated disk preferences. Counted request-matched save receipt boundary only. Headless source functionality; not OS/GPU/PCK/FPS or whole-economy acceptance."},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
