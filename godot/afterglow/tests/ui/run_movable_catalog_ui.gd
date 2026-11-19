extends "res://tests/ui/run_service_access_ui.gd"
## MV01 changed controls only; retained successful normal economy is read-only.
const Movable = preload("res://scripts/ui/factory_movable.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
class PointerProbe extends "res://scripts/input/direct_interaction.gd":
	# Explicit pointer ray only; original router/ghost/availability/submit/cancel.
	func _refresh() -> void: pass
	func _refresh_at(_mouse: Vector2) -> void: pass
	func _process(_delta: float) -> void: pass
var pointer_actions := 0
func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]
	DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	if args.size() < 2: check("explicit normal-source archive required", false); finish(); return
	var decoded: Dictionary = Store.decode(FileAccess.get_file_as_string(args[1]))
	check("original normal economy archive decodes", decoded.get("ok", false), decoded.get("reason"))
	if not decoded.get("ok", false): finish(); return
	host = TestClient.new(); root.add_child(host)
	if not await mount_capture(decoded.capture): finish(); return
	check("normal profile remains actual with no playtest grant", runtime.snapshot().get("opening_profile") == "normal" and runtime.snapshot().get("playtest", {}).is_empty())
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_panel("build"); await flush()
	var listed := F.build_definitions(ui.factory)
	var has_module := listed.any(func(row: Dictionary): return keyed("factory:preview:" + str(row.get("id", ""))) != null)
	check("ordinary B page lists current module construction", ui.pages.back().page == "factory_catalog" and has_module)
	var tab: Button = keyed("factory:category:movable")
	check("visible movable facilities filter exists", tab != null and not tab.disabled)
	if tab == null: finish(); return
	tab.pressed.emit(); await flush()
	check("limited filter has cabinet placement without generic move", keyed("factory:movable:place:cabinet") != null and keyed("factory:movable:move:cabinet") == null)
	check("limited category does not open whole legacy or module moving", keyed("build:wall") == null and keyed("mode:move") == null and keyed("factory:preview:r34.module.warehouse") == null)
	var definition := Movable.definition(ui)
	check("one actual public definition with original cost tool duration", definition.get("id") == "cabinet" and float(definition.get("cost", {}).get("timber", 0)) == 3.0 and float(definition.get("cost", {}).get("scrap", 0)) == 1.0 and float(definition.get("seconds", 0)) == 8.0 and definition.get("tool") == "hammering", definition)
	check("card exposes real requirements and original control flow", text_in(ui._body).contains("工时 8") and text_in(ui._body).contains("锤") and text_in(ui._body).contains("左键固定") and text_in(ui._body).contains("普通完整模块不提供搬房"), text_in(ui._body))
	router.primary_requested.connect(func(pressed: bool):
		if pressed: pointer_actions += 1
	)
	router.secondary_requested.connect(func(): pointer_actions += 1)
	for button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var event := InputEventMouseButton.new(); event.button_index = button_index; event.pressed = true
		router._unhandled_input(event)
	check("catalogue modal blocks both world mouse actions", pointer_actions == 0 and router.is_paused() and router.world_is_paused())
	var hand_before: Dictionary = router.state()
	keyed("factory:movable:place:cabinet").pressed.emit(); await flush()
	check("formal placement button retains the catalog and releases the world input pause", router.state().get("facility_definition_id") == "cabinet" and router.state().mode == "facility_place" and ui.planning_active() and ui.pages.back().page == "factory_catalog" and not router.is_paused(), router.state())
	check("facility preview never replaces selected hotbar references", hand_before.slots == router.state().slots and hand_before.selected == router.state().selected)
	check("facility HUD explains placement instead of terrain mining", ui._mode_hint.text.contains("可搬设施选址") and ui._mode_hint.text.contains("左键固定") and not ui._mode_hint.text.contains("挖掘"), ui._mode_hint.text)
	check("opening filter and choosing preview never pays or creates a cabinet", Data.json_equal(before, runtime.capture_checkpoint()))
	router.set_mode("tool"); ui.open_panel("build"); await flush()
	ui.factory_view.catalog_search = "不存在的设施名称"; ui.queue_refresh(); await flush()
	check("filter search does not fall back to legacy catalogue", keyed("factory:movable:place:cabinet") == null and text_in(ui._body).contains("没有匹配"))
	ui.factory_view.catalog_search = "储物柜"; ui.queue_refresh(); await flush()
	check("cabinet can be found by its normal name", keyed("factory:movable:place:cabinet") != null)
	var original_hand: Dictionary = router.state()
	# Explicit held-item guard counterexample, not a normal material source.
	ui.carry = {"name":"guard probe", "source":{"stock_id":"pack:player"}, "amount":1}
	var refused: Dictionary = Movable.begin_placement(ui)
	var refused_move: Dictionary = Movable.begin_move(ui, "")
	check("pending item reference cannot be lost by switching work mode", not refused.get("ok", false) and not refused_move.get("ok", false) and ui.carry.get("name") == "guard probe" and original_hand.mode == router.state().mode and original_hand.slots == router.state().slots and not ui.pages.is_empty())
	ui.carry = {}; ui.close_panels(); await flush()
	check("all changed UI controls leave actual normal facts unchanged", Data.json_equal(before, runtime.capture_checkpoint()))
	await preview_cases()
	finish()

func preview_cases() -> void:
	var camera := Camera3D.new(); host.add_child(camera)
	var surface := Node3D.new(); host.add_child(surface)
	var direct := PointerProbe.new(); host.add_child(direct)
	direct.configure({"runtime":runtime, "world":runtime.world, "router":router, "camera":camera, "buildings":runtime._services.buildings, "terrain":surface, "ui":ui})
	ui.open_panel("build"); await flush()
	keyed("factory:movable:place:cabinet").pressed.emit(); await flush()
	var player: Dictionary = runtime.actor("player")
	var point := Vector3(float(player.x), float(player.y), float(player.z) + 2.0)
	direct._point = {"distance":10.0, "unknown":false}
	var before: Dictionary = runtime.capture_checkpoint()
	direct._update_preview(router.held_reference(), point + Vector3.UP * 10, Vector3.DOWN)
	check("actual pointer preview uses original cabinet structure and own pack", direct._ghost.visible and direct._preview.get("instance", {}).get("definitionId") == "cabinet" and direct._preview.get("source_id") == "pack:player")
	check("preview selection does not inject materials or construct", Data.json_equal(before, runtime.capture_checkpoint()))
	var preflight: Dictionary = runtime.snapshot().get("target", {})
	check("current archive supplies a genuinely blocked placement", not preflight.get("enabled", true) and not str(preflight.get("reason", "")).is_empty(), preflight)
	var left := InputEventMouseButton.new(); left.button_index = MOUSE_BUTTON_LEFT; left.pressed = true
	router._unhandled_input(left)
	var interact := InputEventKey.new(); interact.physical_keycode = KEY_E; interact.keycode = KEY_E; interact.pressed = true
	router._unhandled_input(interact)
	check("facility preview never starts left-tool work or E use", Data.json_equal(before, runtime.capture_checkpoint()) and runtime.actor("player").get("intent") == null)
	var right := InputEventMouseButton.new(); right.button_index = MOUSE_BUTTON_RIGHT; right.pressed = true
	router._unhandled_input(right); await flush()
	check("right-click only retracts the fixed facility", not direct._placement_locked() and Data.json_equal(before, runtime.capture_checkpoint()) and runtime.actor("player").get("intent") == null)
	direct._update_preview(router.held_reference(), point + Vector3.UP * 10, Vector3.DOWN)
	router._unhandled_input(left)
	var confirm := InputEventKey.new(); confirm.physical_keycode = KEY_ENTER; confirm.keycode = KEY_ENTER; confirm.pressed = true
	router._unhandled_input(confirm); await flush()
	check("Enter reports the blocked placement and preserves the fixed facility and goods", direct._placement_locked() and Data.json_equal(before, runtime.capture_checkpoint()) and runtime.actor("player").get("intent") == null and not ui._notice.text.is_empty(), ui._notice.text)
	router.cancel()
	check("first Esc retracts the fixed facility and retains placement mode", not direct._placement_locked() and router.mode() == "facility_place")
	router.cancel(); await flush()
	check("second Esc clears the ghost and returns to the same catalog", router.state().mode == "tool" and str(router.state().get("facility_definition_id", "")).is_empty() and not direct._ghost.visible and not ui.planning_active() and ui.pages.back().page == "factory_catalog" and Data.json_equal(before, runtime.capture_checkpoint()), router.state())
	direct.free(); surface.free(); camera.free()
