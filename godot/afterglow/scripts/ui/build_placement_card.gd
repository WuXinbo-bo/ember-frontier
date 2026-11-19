extends PanelContainer
## The target snapshot supplies placement facts. Both confirm paths use the router.
const C = preload("res://scripts/ui/ui_composition.gd")
const P = preload("res://scripts/ui/ui_projection.gd")

var _title: Label
var _status: Label
var _details: Label
var _controls: Label
var _confirm: Button
var _retract: Button
var _last_view: Dictionary = {}
var _router: WeakRef

func configure(ui) -> void:
	if is_instance_valid(ui.input_router): _router = weakref(ui.input_router)
	theme_type_variation = "WorkshopEmphasis"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	add_child(content)
	_title = ui.paragraph("", content)
	_title.theme_type_variation = "SectionTitle"
	_status = C.caption(ui, "", content)
	_details = C.caption(ui, "", content)
	_controls = C.caption(ui, "", content)
	var actions := HFlowContainer.new()
	content.add_child(actions)
	_confirm = ui.button("确认", _request_placement.bind("confirm_placement"), "building:placement:confirm", "请先固定位置")
	C.primary(_confirm)
	actions.add_child(_confirm)
	_retract = ui.button("换个位置", _request_placement.bind("retract_placement"), "building:placement:retract", "请先固定位置")
	actions.add_child(_retract)
	hide()

func update_target(target: Dictionary) -> void:
	if _confirm == null: return
	if target.get("kind") != "placement":
		_last_view.clear()
		hide()
		return
	show()
	var enabled: bool = target.get("enabled", false)
	var missing: Dictionary = target.get("missing", {}) if target.get("missing") is Dictionary else {}
	var state := str(target.get("placement_state", ""))
	if state.is_empty():
		state = "ready" if enabled else "blocked"
		if target.get("code") == "MODULE_MATERIALS": state = "shortage"
	var view := {
		"fixed":target.get("placement_locked", false), "valid":enabled,
		"name":target.get("name", "选址"), "worker":target.get("worker_name", ""),
		"state":state, "reason":target.get("reason", ""), "missing":missing,
		"source":target.get("source_name", ""), "action":target.get("action_label", ""),
		"hint":target.get("hint", ""),
	}
	if view == _last_view: return
	_last_view = view.duplicate(true)
	_render(view)

func _render(view: Dictionary) -> void:
	var fixed: bool = view.fixed
	var valid: bool = view.valid
	var state: String = view.state
	var worker: String = view.worker
	_title.text = str(view.name) + (" · " + worker if not worker.is_empty() else "")
	var condition := str({
		"ready":"可建立蓝图" if view.action == "建立蓝图" else "位置可建造",
		"shortage":"缺料，可先建立蓝图" if valid or view.action == "建立蓝图" else "缺少材料",
		"blocked":"当前位置无法使用", "checking":"核对占地与条件",
	}.get(state, "核对占地与条件"))
	_status.text = ("位置已固定 · " if fixed else "选址 · ") + condition
	var details: PackedStringArray = []
	if state != "ready" and view.reason is String and not view.reason.is_empty(): details.append(P.reason_text(view.reason))
	var items: PackedStringArray = []
	for item: String in view.missing:
		if float(view.missing[item]) > 0: items.append("%s × %s" % [P.item_name(item), P.number(view.missing[item])])
	if not items.is_empty(): details.append("缺少 " + "、".join(items))
	if not str(view.source).is_empty(): details.append("物资来源 · " + str(view.source))
	_details.text = "\n".join(details)
	_details.tooltip_text = _details.text
	_details.visible = not details.is_empty()
	_controls.text = str(view.hint)
	_controls.visible = not _controls.text.is_empty()
	var action := str(view.action)
	if action.is_empty(): action = "确认位置"
	_confirm.text = action + " · Enter"
	_confirm.disabled = not (fixed and valid)
	_confirm.tooltip_text = "请先用左键固定位置" if not fixed else _details.text if not valid and not _details.text.is_empty() else condition if not valid else ""
	_retract.disabled = not fixed

func _request_placement(action: String) -> void:
	var router: Object = _router.get_ref() if _router != null else null
	if is_instance_valid(router) and router.has_method(action): router.call(action)
