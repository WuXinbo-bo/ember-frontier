extends SceneTree
## Production native recovery Controls; bounded discovery DTOs, not disk/OS.
const Recovery = preload("res://scripts/ui/recovery_menu.gd")
const Store = preload("res://scripts/storage/native_store.gd")

class Calls extends RefCounted:
	var choices: Array = []
	var fresh_count := 0
	func choose(id: String, sha: String) -> Dictionary:
		choices.append([id, sha])
		return {"ok":false,"code":"NOT_READY","reason":"布局检查不装载世界"}
	func fresh() -> Dictionary:
		fresh_count += 1
		return {"ok":false,"code":"NOT_READY","reason":"布局检查不创建世界"}

var checks: Array = []
var output := ""
var mouse := Vector2.ZERO
var held := false
var pointer_trace: Array = []

func _initialize() -> void:
	create_timer(40).timeout.connect(func(): finish(2))
	call_deferred("run")

func flush() -> void:
	await process_frame; await process_frame; await process_frame

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	print(("PASS " if ok else "FAIL ") + name)

func rows(count: int) -> Array:
	var result: Array = []
	for i in count:
		result.append({"candidate_id":"namespace:%s/%s" % [i / 2, i % 2],"namespace":"namespace:%s" % (i / 2),"slot":"a" if i % 2 == 0 else "b","sha256":("%064x" % (i + 1)),"checkpoint_id":"native:%s:1794734904.79262" % i,"world_id":"rural:v4:%s" % (700 + i / 2),"seed":700 + i / 2,"command_revision":i,"time":53.7 + i})
	return result

func find_title(node: Node) -> Label:
	if node is Label and node.text == "选择要恢复的存档": return node
	for child in node.get_children():
		var found := find_title(child)
		if found != null: return found
	return null

func inside(node: Control, dimensions: Vector2i) -> bool:
	var bounds := node.get_global_rect()
	return node.is_visible_in_tree() and bounds.position.x >= -0.5 and bounds.position.y >= -0.5 and bounds.end.x <= dimensions.x + 0.5 and bounds.end.y <= dimensions.y + 0.5

func contained(node: Control, area: Control) -> bool:
	var bounds := node.get_global_rect(); var viewport := area.get_global_rect().grow(0.5)
	return viewport.encloses(bounds)

func pointer(point: Vector2, button: MouseButton, pressed: bool, factor: float = 1.0) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	motion.relative = point - mouse; motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	mouse = point
	root.push_input(motion, true)
	await process_frame
	var hovered := root.gui_get_hovered_control()
	pointer_trace.append({"point":str(point),"button":button,"pressed":pressed,"hover":str(hovered.get_path()) if hovered != null else "none","key":hovered.get_meta("ui_focus_key","") if hovered != null else ""})
	var event := InputEventMouseButton.new(); event.position = point; event.global_position = point
	event.button_index = button; event.pressed = pressed; event.factor = factor
	if button == MOUSE_BUTTON_LEFT: held = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await process_frame

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	var probe := OS.get_cmdline_user_args().has("--probe")
	var calls := Calls.new()
	var failure := {"ok":false,"code":"SPATIAL_REJECTED","reason":"存档中的玩家站位无有效支撑；原存档保留，请明确选择其他候选或新建村落"}
	for dimensions: Vector2i in ([Vector2i(1280,800)] if probe else [Vector2i(1280,800), Vector2i(1000,700), Vector2i(800,600)]):
		root.content_scale_size = dimensions; root.size = dimensions
		for scale_factor: float in ([1.0] if probe else [1.0, 1.5]):
			for count: int in ([15] if probe else [0, 1, 15, Store.RECOVERY_NAMESPACES * 2]):
				pointer_trace.clear()
				var menu := Recovery.new(); menu.text_scale = scale_factor; menu.allow_cancel = true
				var source := rows(count); menu.configure(source, calls.choose, calls.fresh); menu.show_failure(failure)
				root.add_child(menu); await flush()
				var title := find_title(menu)
				var scroll := menu._list.get_parent() as ScrollContainer
				var label := "%s font=%s rows=%s" % [dimensions,scale_factor,count]
				var geometry := {"dialog":str(menu._dialog.get_global_rect()),"minimum":str(menu._dialog.get_combined_minimum_size()),"scroll":str(scroll.get_global_rect()),"vertical_mode":scroll.vertical_scroll_mode,"list_minimum":str(menu._list.get_combined_minimum_size()),"status":str(menu._status.get_global_rect()),"fresh":str(menu._fresh.get_global_rect()),"back":str(menu._back.get_global_rect())}
				check("dialog stays within viewport " + label, inside(menu._dialog, dimensions), geometry)
				check("title failure and actions remain reachable " + label, title != null and inside(title,dimensions) and inside(menu._status,dimensions) and inside(menu._fresh,dimensions) and inside(menu._back,dimensions) and menu._status.text.contains(failure.reason), geometry)
				check("candidate viewport has usable independent height " + label, inside(scroll, dimensions) and scroll.size.y >= 60 and scroll.clip_contents, geometry)
				check("all candidate identities retained without automatic activation " + label, menu.candidates == source and menu._list.get_child_count() == maxi(1,count) and menu._selected.is_empty() and menu._restore.disabled and calls.choices.is_empty() and calls.fresh_count == 0)
				if count > 1:
					var bar := scroll.get_v_scroll_bar()
					check("many candidates have an actual scroll range " + label, bar.max_value > bar.page and bar.visible, {"max":bar.max_value,"page":bar.page,"visible":bar.visible})
					var fixed_before := [title.get_global_rect(),menu._status.get_global_rect(),menu._fresh.get_global_rect(),menu._back.get_global_rect()]
					await pointer(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN, true, 1024)
					await pointer(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN, false, 1024)
					await flush()
					var last := menu._list.get_child(count - 1) as Button
					check("native wheel reaches final candidate without moving fixed controls " + label, bar.value > 0 and contained(last,scroll) and fixed_before == [title.get_global_rect(),menu._status.get_global_rect(),menu._fresh.get_global_rect(),menu._back.get_global_rect()], {"value":bar.value,"max":bar.max_value,"page":bar.page,"last":str(last.get_global_rect())})
					await pointer(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, true, 1024)
					await pointer(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, false, 1024)
					await flush()
					check("native wheel returns to first candidate without choosing " + label, is_zero_approx(bar.value) and contained(menu._list.get_child(0),scroll) and menu._selected.is_empty() and calls.choices.is_empty() and calls.fresh_count == 0)
				if count > 0:
					var last := menu._list.get_child(count - 1) as Button
					last.pressed.connect(func(): pointer_trace.append({"pressed_signal":true}))
					last.gui_input.connect(func(event: InputEvent):
						if event is InputEventMouseButton: pointer_trace.append({"gui_pressed":event.pressed,"button":event.button_index,"position":str(event.position)}))
					last.grab_focus(); await flush()
					check("native focus reveals final candidate without activation " + label, contained(last,scroll) and menu._selected.is_empty() and calls.choices.is_empty() and calls.fresh_count == 0)
					var point := last.get_global_rect().get_center()
					await pointer(point,MOUSE_BUTTON_LEFT,true); await pointer(point,MOUSE_BUTTON_LEFT,false); await flush()
					check("native pointer only selects exact final ID and SHA " + label, menu._selected == source[-1] and not menu._restore.disabled and calls.choices.is_empty() and calls.fresh_count == 0, {"selected":menu._selected,"trace":pointer_trace.duplicate(true),"last":str(last.get_global_rect()) if is_instance_valid(last) else "rerendered","disabled":last.disabled if is_instance_valid(last) else false,"tooltip":last.tooltip_text if is_instance_valid(last) else "rerendered","row":source[-1],"scroll":str(scroll.get_global_rect()),"scroll_value":scroll.scroll_vertical})
					if menu._selected.is_empty():
						menu.queue_free(); await flush(); continue
					check("selected metadata and controls fit viewport " + label, inside(menu._dialog,dimensions) and inside(menu._details,dimensions) and inside(menu._restore,dimensions) and inside(menu._fresh,dimensions) and inside(menu._back,dimensions) and scroll.size.y >= 60, str(menu._dialog.get_global_rect()))
					menu._restore_pressed(); await flush()
					check("restore confirmation and safe cancel stay reachable " + label, menu._confirming == "restore" and root.gui_get_focus_owner() == menu._back and inside(menu._dialog,dimensions) and inside(menu._details,dimensions) and inside(menu._back,dimensions) and inside(menu._restore,dimensions) and scroll.size.y >= 60 and calls.choices.is_empty(), str(menu._dialog.get_global_rect()))
					menu.cancel(); menu._fresh_pressed(); await flush()
					check("fresh confirmation stays reachable and does not submit " + label, menu._confirming == "fresh" and inside(menu._dialog,dimensions) and inside(menu._details,dimensions) and inside(menu._fresh,dimensions) and inside(menu._back,dimensions) and calls.choices.is_empty() and calls.fresh_count == 0)
					menu.cancel(); await flush()
					check("cancel keeps every identity and returns usable selection " + label, menu._confirming.is_empty() and menu.candidates == source and menu._selected == source[-1] and not menu.busy and not menu._restore.disabled and calls.choices.is_empty() and calls.fresh_count == 0)
				menu.queue_free(); await flush()
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"scope":"production recovery Control/headless layout; 0/1/15/32 namespaces x 2 slots; no OS, actual storage or world activation","formal_application_launched":false,"route_acceptance":false},"  ")); file.close()
	quit(code)
