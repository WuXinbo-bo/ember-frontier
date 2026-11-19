extends Control
## Explicit candidate selection only. A owns scanning, bytes, assembly, readiness
## and active CAS. This view never reads files or chooses a world automatically.
signal closed
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
var candidates: Array = []
var choose: Callable
var fresh: Callable
var allow_cancel := false
var busy := false
var text_scale := 1.0
var _generation := 0
var _selected: Dictionary = {}
var _confirming := ""
var _feedback := ""
var _diagnostic := ""
var _dialog: PanelContainer
var _list: VBoxContainer
var _details: Label
var _status: Label
var _restore: Button
var _fresh: Button
var _back: Button

func configure(rows: Array, choose_callback: Callable, fresh_callback: Callable) -> void:
	_generation += 1
	candidates = rows.duplicate(true)
	choose = choose_callback; fresh = fresh_callback
	_selected.clear(); _confirming = ""; _feedback = ""; _diagnostic = ""; busy = false
	if is_node_ready(): _render()

func show_failure(receipt: Dictionary) -> void:
	# A can supply a real startup/assembly failure before this Control enters
	# the tree. Display only; never unlock an already submitted operation.
	if receipt.is_empty() or receipt.get("ok", false) or busy: return
	_finished(receipt.duplicate(true))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	theme = UiTheme.create(load("res://themes/fonts/NotoSansCJKsc-Regular.otf"), text_scale)
	var shade := ColorRect.new()
	shade.color = Color("111913ee")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.mouse_force_pass_scroll_events = false
	add_child(shade)
	_dialog = PanelContainer.new(); _dialog.focus_mode = Control.FOCUS_ALL
	# Wrapped labels initially measure before the panel has a usable width.
	# Re-apply the viewport bound after that temporary minimum settles.
	_dialog.minimum_size_changed.connect(_resize_dialog)
	add_child(_dialog)
	var column := VBoxContainer.new(); _dialog.add_child(column)
	var title := _paragraph("选择要恢复的存档", column)
	title.add_theme_font_size_override("font_size", int(22 * text_scale))
	_paragraph("请核对世界、种子与检查点，再明确选择。列表不会自动恢复最新时间的世界；恢复时仍需重新校验文件、装配和近域就绪。", column)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 60
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.mouse_force_pass_scroll_events = false
	column.add_child(scroll)
	_list = VBoxContainer.new(); _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_details = _paragraph("", column)
	_status = _paragraph("", column)
	_status.add_theme_color_override("font_color", Color("e8ae99"))
	# Keep the actions outside the scrolling list, including confirmation at
	# larger text sizes in a smaller desktop window.
	var actions := HBoxContainer.new(); column.add_child(actions)
	_restore = _button("选择此存档…", _restore_pressed, "recovery:restore", actions)
	_fresh = _button("新建随机村落…", _fresh_pressed, "recovery:fresh", actions)
	_back = _button("返回 · Esc", cancel, "recovery:back", actions)
	for button: Button in [_restore, _fresh, _back]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_resize_dialog)
	get_window().focus_exited.connect(_focus_exited)
	_resize_dialog(); _render(); _dialog.grab_focus()

func _exit_tree() -> void:
	_generation += 1

func _paragraph(text: String, parent: Node) -> Label:
	var label := Label.new(); label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(text: String, action: Callable, key: String, parent: Node) -> Button:
	var button := Button.new(); button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.set_meta("ui_focus_key", key)
	button.pressed.connect(action); parent.add_child(button)
	return button

func _resize_dialog() -> void:
	if not is_instance_valid(_dialog): return
	_dialog.size = Vector2(minf(900, maxf(280, size.x - 48)), maxf(240, size.y - 48))
	_dialog.position = (size - _dialog.size) * 0.5

static func candidate_reason(row: Dictionary) -> String:
	if not row.get("candidate_id") is String or str(row.candidate_id).is_empty(): return "候选身份缺失，不能恢复"
	var sha := str(row.get("sha256", ""))
	if sha.length() != 64 or not sha.is_valid_hex_number(false): return "候选校验指纹缺失或无效，不能恢复"
	if not row.get("world_id") is String or str(row.world_id).is_empty(): return "候选世界身份缺失，不能恢复"
	return ""

func _render() -> void:
	if not is_node_ready(): return
	for node in _list.get_children(): _list.remove_child(node); node.queue_free()
	var counts: Dictionary = {}
	for value: Variant in candidates:
		if value is Dictionary:
			var id := str(value.get("candidate_id", ""))
			counts[id] = int(counts.get(id, 0)) + 1
	if candidates.is_empty(): _paragraph("没有可列出的恢复候选。原存档保持；可返回或明确新建村落。", _list)
	for index in candidates.size():
		var value: Variant = candidates[index]
		if not value is Dictionary:
			_paragraph("候选描述无效，不能恢复", _list); continue
		var row: Dictionary = value
		var reason := candidate_reason(row)
		if int(counts.get(str(row.get("candidate_id", "")), 0)) > 1: reason = "候选身份重复，请由存储服务重新列出"
		var text := "种子 %s · 检查点 %s · 槽 %s\n世界 %s" % [row.get("seed", "—"), row.get("checkpoint_id", "—"), row.get("slot", "—"), row.get("world_id", "—")]
		var copy := row.duplicate(true)
		var button := _button(text, func(): select_candidate(copy), "recovery:candidate:" + str(index), _list)
		button.toggle_mode = true
		button.button_pressed = not _selected.is_empty() and row.get("candidate_id") == _selected.get("candidate_id") and row.get("sha256") == _selected.get("sha256")
		button.disabled = busy or not _confirming.is_empty() or not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else "仅选中此候选，不立即恢复"
	_details.text = "尚未选择存档" if _selected.is_empty() else "命名空间 %s · 槽 %s · 世界 %s\n种子 %s · 检查点 %s · 命令版本 %s · 游戏时间 %s\n存储候选已列出；完整领域装配与场景就绪仍待提交验证。" % [_selected.get("namespace", "—"), _selected.get("slot", "—"), _selected.get("world_id", "—"), _selected.get("seed", "—"), _selected.get("checkpoint_id", "—"), _selected.get("command_revision", "—"), P.number(_selected.get("time"))]
	_details.tooltip_text = "SHA-256: " + str(_selected.get("sha256", "")) if not _selected.is_empty() else ""
	if _confirming == "restore": _details.text += "\n确认恢复此候选？当前未保存进度将被替换。提交失败保留原现场与存档。"
	elif _confirming == "fresh": _details.text = "确认新建随机村落？当前未保存进度将被替换，已有存档目录保持。"
	_status.text = _feedback; _status.tooltip_text = _diagnostic
	_restore.text = "正在校验并恢复…" if busy else "确认恢复选中存档" if _confirming == "restore" else "选择此存档…"
	_restore.disabled = busy or _selected.is_empty() or not choose.is_valid() or _confirming == "fresh"
	_fresh.text = "确认新建随机村落" if _confirming == "fresh" else "新建随机村落…"
	_fresh.visible = fresh.is_valid()
	_fresh.disabled = busy or _confirming == "restore"
	_back.visible = allow_cancel or not _confirming.is_empty()
	_back.disabled = busy

func select_candidate(row: Dictionary) -> void:
	if busy or not _confirming.is_empty() or not candidate_reason(row).is_empty(): return
	# Match the full stable identity in this display list. Never use an index,
	# label, seed, timestamp or filename as the submitted identity.
	var matches := candidates.filter(func(value: Variant): return value is Dictionary and value.get("candidate_id") == row.get("candidate_id"))
	if matches.size() != 1 or matches[0].get("sha256") != row.get("sha256"): return
	_selected = matches[0].duplicate(true); _feedback = ""; _diagnostic = ""
	_render(); _restore.grab_focus()

func _restore_pressed() -> void:
	if busy or _selected.is_empty() or not choose.is_valid() or _confirming == "fresh": return
	if _confirming != "restore":
		_confirming = "restore"; _render(); _back.grab_focus(); return
	busy = true; _feedback = "正在重新校验候选、装配与场景就绪，请等待真实回执…"; _diagnostic = ""
	_render(); _dialog.grab_focus()
	_await_result(weakref(self), _generation, choose, [str(_selected.candidate_id), str(_selected.sha256)])

func _fresh_pressed() -> void:
	if busy or not fresh.is_valid() or _confirming == "restore": return
	if _confirming != "fresh": _confirming = "fresh"; _render(); _back.grab_focus(); return
	busy = true; _feedback = "正在准备新村落，请等待真实回执…"; _diagnostic = ""
	_render(); _dialog.grab_focus()
	_await_result(weakref(self), _generation, fresh, [])

static func _await_result(view_ref: WeakRef, generation: int, callback: Callable, arguments: Array) -> void:
	var receipt: Variant = await callback.callv(arguments)
	var view: Variant = view_ref.get_ref()
	if not is_instance_valid(view) or not view.is_inside_tree() or view.is_queued_for_deletion() or view._generation != generation: return
	view._finished(receipt)

func _finished(receipt: Variant) -> void:
	if receipt is Dictionary and receipt.get("ok", false) and receipt.get("code") == "OK":
		_feedback = "入口已确认提交，正在接管世界…"
		# A removes this view only when the new authority can take over.
	else:
		busy = false; _confirming = ""
		_feedback = "恢复／新建未完成 · " + (P.feedback_text(receipt, {}, "未收到确认回执，原档保持") if receipt is Dictionary else "未收到确认回执，原档保持")
		_diagnostic = P.feedback_diagnostic(receipt) if receipt is Dictionary else "UNCONFIRMED"
		if receipt is Dictionary and receipt.get("candidates") is Array:
			candidates = receipt.candidates.duplicate(true); _selected.clear()
	_render()
	if is_node_ready(): _dialog.grab_focus()

func cancel() -> void:
	if busy: return
	if not _confirming.is_empty(): _confirming = ""; _render(); _dialog.grab_focus(); return
	if allow_cancel: closed.emit(); queue_free()

func _focus_exited() -> void:
	if busy: return
	_confirming = ""; _render(); _dialog.grab_focus()

func _input(event: InputEvent) -> void:
	if busy: get_viewport().set_input_as_handled(); return
	if event is InputEventKey:
		if event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			if not event.echo: cancel()
		elif event.physical_keycode not in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]: get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
