extends Button
## Godot handles the physical drag. The owner commits the one real transaction.
const P = preload("res://scripts/ui/ui_projection.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
var slot: Dictionary = {}
var create_drag: Callable
var can_receive: Callable
var receive: Callable
var activate: Callable
var split: Callable
var _suppress_click := false
var _click_shift := false
var visual_state: Dictionary = {}

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text = true
	custom_minimum_size = Vector2(maxf(64, custom_minimum_size.x), maxf(84, custom_minimum_size.y))
	pressed.connect(func():
		if _suppress_click:
			_suppress_click = false
			return
		if activate.is_valid():
			var clicked:=slot.duplicate(true)
			clicked.quick_transfer=_click_shift
			_click_shift=false
			activate.call(clicked))

func present(title: String, selected: bool = false, scale_factor: float = 1.0) -> void:
	var entry: Dictionary = slot.get("entry", {})
	var info := Icons.descriptor(entry)
	var quantity := float(slot.get("quantity", 0))
	var available := clampf(float(slot.get("available", 0)), 0, quantity)
	var reserved := maxf(0, quantity - available)
	var is_tool: bool = slot.get("reference", {}).get("kind") == "tool"
	var is_recipe: bool = slot.get("reference", {}).get("kind") == "recipe"
	var unit := P.item_unit(str(slot.get("reference", {}).get("item_id", ""))) if slot.get("reference", {}).get("kind") == "item" else ""
	var unavailable: bool = not slot.get("reference", {}).is_empty() and entry.is_empty()
	var exhausted: bool = unavailable and not is_tool
	var durability: Variant = entry.get("durability")
	var maximum: Variant = entry.get("max_durability")
	visual_state = {"name":title, "selected":selected, "reserved":reserved, "quantity":quantity, "available":available, "exhausted":exhausted, "unavailable":unavailable, "icon":info, "durability":durability, "maximum":maximum}
	set_meta("ui_display_name", title)
	set_meta("ui_icon", info)
	text = ""
	icon = null
	tooltip_text = title
	var use_hint := Icons.use_hint(str(slot.get("reference", {}).get("item_id", "")))
	if not use_hint.is_empty(): tooltip_text += "\n" + use_hint
	if unavailable: tooltip_text += "\n不在背包" if is_tool else "\n已耗尽"
	if not entry.is_empty() and not is_recipe:
		tooltip_text += "\n数量 " + P.number(quantity) + unit + " · 可用 " + P.number(available) + unit
		if reserved > 0: tooltip_text += " · 已预留 " + P.number(reserved) + unit
	if durability != null: tooltip_text += "\n耐久 " + P.number(durability) + (" / " + P.number(maximum) if maximum != null else "")
	if not str(info.reason).is_empty(): tooltip_text += "\n" + str(info.reason)
	for state in ["normal", "hover", "pressed"]:
		var fill := Color("d6dfc3") if selected else UiTheme.SURFACE
		if state == "hover": fill = Color("c7d5b1") if selected else UiTheme.RAISED
		elif state == "pressed": fill = Color("b9c9a0") if selected else UiTheme.RAISED
		var style := UiTheme.chrome("slot", fill, UiTheme.ACCENT if selected else UiTheme.EDGE, 2 if selected else 1)
		add_theme_stylebox_override(state, style)
	for child in get_children():
		remove_child(child); child.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 4)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var number := str(int(slot.get("index", -1)) + 1) if slot.get("kind") == "hotbar" else ""
	if selected: number = "[" + number + "]"
	var amount := "" if is_tool or is_recipe or entry.is_empty() else "×" + P.number(quantity).trim_suffix(".0")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var key := _caption(number, 10, scale_factor)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(key)
	top.add_child(_caption(amount, 10, scale_factor))
	var image := Icons.texture(entry)
	if image != null:
		var picture := Icons.image(image, roundi(36 * scale_factor))
		picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(picture)
	else:
		var fallback := _caption(str(info.fallback) if not entry.is_empty() else "—", 11, scale_factor)
		fallback.custom_minimum_size.y = 24
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(fallback)
	var name_label := _caption(title, 12, scale_factor)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.visible = slot.get("kind") != "hotbar" or selected
	column.add_child(name_label)
	var status := "已耗尽" if exhausted else "不在背包" if unavailable else "构件" if is_recipe else ""
	if reserved > 0: status = "已预留" if available <= 0 else "预留" + P.number(reserved).trim_suffix(".0")
	elif durability is int or durability is float: status = "耐久" + P.number(durability).trim_suffix(".0")
	if str(slot.get("reference", {}).get("item_id", "")) in ["r34:raw_water", "r34:filtered_water"]: status = "不可饮用"
	var footer := _caption(status, 10, scale_factor)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", UiTheme.RUST if reserved > 0 else UiTheme.SECONDARY)
	footer.visible = not status.is_empty() and not (is_tool and not unavailable and reserved <= 0)
	column.add_child(footer)
	if (durability is int or durability is float) and (maximum is int or maximum is float) and is_finite(float(durability)) and is_finite(float(maximum)) and float(maximum) > 0:
		var bar := ProgressBar.new()
		bar.name = "Durability"
		bar.step = 0.0; bar.max_value = float(maximum); bar.value = clampf(float(durability), 0, float(maximum))
		bar.show_percentage = false
		bar.custom_minimum_size.y = 3
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(bar)
	custom_minimum_size = Vector2(64, 90) * scale_factor
	queue_redraw()

func _draw() -> void:
	# Selection stays visible above any supplied skin and distinct from focus.
	if visual_state.get("selected",false):
		draw_rect(Rect2(Vector2.ONE, size-Vector2.ONE*2),UiTheme.ACCENT,false,2)

func _caption(value: String, font_size: int, scale_factor: float) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", int(font_size * scale_factor))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _gui_input(event: InputEvent) -> void:
	# Capture the modifier carried by this pointer/key event. Global key state
	# can already be released when Button emits pressed on mouse release.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:_click_shift=event.shift_pressed
	elif event is InputEventKey and event.pressed:_click_shift=event.shift_pressed
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT and event.ctrl_pressed):
		_suppress_click = event.button_index == MOUSE_BUTTON_LEFT
		accept_event()
		if split.is_valid(): split.call(slot.duplicate(true))

func _get_drag_data(_position: Vector2) -> Variant:
	if _suppress_click or _click_shift: return null
	if not create_drag.is_valid(): return null
	var data: Variant = create_drag.call(slot.duplicate(true))
	if not data is Dictionary or data.is_empty(): return null
	var preview := PanelContainer.new()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(row)
	var image := Icons.texture(slot.get("entry", {}))
	if image != null: row.add_child(Icons.image(image, 32))
	var unit := P.item_unit(str(data.get("reference", {}).get("item_id", "")))
	var label := _caption(str(data.get("name", "物品")) + " × " + P.number(data.get("amount", 1)) + unit, 15, 1.0)
	row.add_child(label)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.6
	set_drag_preview(preview)
	return data

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: modulate.a = 1.0

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	# Hover validation only reads the retained slot. Submission below detaches it.
	return data is Dictionary and can_receive.is_valid() and bool(can_receive.call(slot, data))

func _drop_data(_position: Vector2, data: Variant) -> void:
	if receive.is_valid() and data is Dictionary:
		receive.call(slot.duplicate(true), data.duplicate(true))
