extends RefCounted
## MV01 is a presentation filter over the original catalogue and input router.
## Construction, support, ownership, inventory and movement stay with their owners.
const Panels = preload("res://scripts/ui/ui_panels.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Handbook = preload("res://scripts/ui/factory_handbook.gd")
const Keys = preload("res://scripts/ui/ui_work_modes.gd")

static func definition(ui) -> Dictionary:
	for row: Dictionary in Panels._catalog(ui, "buildings"):
		if row.get("id", row.get("definition_id", "")) == "cabinet": return row
	return {}

static func reason(ui, row: Dictionary) -> String:
	if row.is_empty(): return "储物柜定义尚未提供，请稍后重开目录"
	if not ui.carry.is_empty(): return "请先将手中物品归位，再选择场景作业"
	if not row.get("enabled", true):
		var unavailable := str(row.get("reason", ""))
		return unavailable if not unavailable.is_empty() else "储物柜当前不可建造"
	var blocked := P.definition_reason(row)
	if not blocked.is_empty(): return blocked
	if not is_instance_valid(ui.input_router) or not ui.input_router.has_method("begin_facility_placement"): return "储物柜现场选址尚未就绪"
	return ""

static func render(ui, parent: VBoxContainer, category: String) -> int:
	if category not in ["all", "storage", "movable"]: return 0
	var row := definition(ui)
	var query := str(ui.factory_view.get("catalog_search", "")).strip_edges().to_lower()
	if not query.is_empty() and not (str(row.get("name", "储物柜")) + " 可搬设施 暂存 cabinet").to_lower().contains(query): return 0
	Panels.heading(ui, "可搬设施", parent)
	if row.is_empty(): ui.paragraph(reason(ui, row), parent); return 1
	var panel := PanelContainer.new(); parent.add_child(panel)
	var card := VBoxContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_child(card)
	Panels.heading(ui, str(row.get("name", "储物柜")), card)
	ui.paragraph("作业面附近的可调整暂存柜 · 首台机器两批之后的可选扩展", card)
	Handbook.shortcut(ui, card, "legacy:cabinet", "catalog:cabinet")
	ui.item_row(row.get("cost", {}), "实际建设材料", card)
	ui.paragraph(Panels._requirements(row, false), card)
	if row.has("tool"): ui.paragraph("工具能力 · " + str(Panels.QUALITIES.get(str(row.tool), str(row.tool))), card)
	ui.paragraph("在有支撑的现场预览，左键固定后按 Enter 确认建设；用锤具完成劳动。存物后仍可现场搬移，内容保留在原柜内。", card)
	var actions := HFlowContainer.new(); card.add_child(actions)
	ui.add_button("储物柜选址", func(): begin_placement(ui), "factory:movable:place:cabinet", reason(ui, row), actions)
	var hand: Dictionary = ui.snapshot.get("hand", {})
	ui.paragraph("搬移：靠近已有储物柜，%s打开后选择搬移 → 指向附近同层位置 → 左键固定 → Enter 确认 · %s旋转 · %s取消。普通完整模块不提供搬房；目的地仍须通过支撑、通路与权限检查。" % [Keys.key(hand, "interact", KEY_E), Keys.key(hand, "rotate", KEY_R), Keys.key(hand, "cancel", KEY_ESCAPE)], card)
	return 1

static func begin_placement(ui) -> Dictionary:
	var row := definition(ui)
	var blocked := reason(ui, row)
	if not blocked.is_empty(): ui.notify(blocked, true); return {"ok":false, "reason":blocked}
	var hand: Dictionary = ui.snapshot.get("hand", {})
	var receipt: Dictionary = ui.router_call("begin_facility_placement", [str(row.get("id", row.get("definition_id", "")))])
	if receipt.get("ok", false):
		ui._sync_modal()
		ui.refresh()
		ui._dialog.grab_focus()
		ui.notify("储物柜选址 · 指向附近有支撑的地面，左键固定 · Enter 确认 · %s旋转 · %s取消" % [Keys.key(hand, "rotate", KEY_R), Keys.key(hand, "cancel", KEY_ESCAPE)])
	else: ui.notify(str(receipt.get("reason", "未能开始储物柜选址")), true)
	return receipt

static func read_container(ui, stock_id: String) -> Dictionary:
	var unavailable := {"available":false, "stock_id":stock_id, "can_move":false, "reason":"当前没有可用的储物柜关联"}
	if stock_id.is_empty() or not is_instance_valid(ui.runtime) or not ui.runtime.has_method("movable_facility"): return unavailable
	var value: Variant = ui.runtime.call("movable_facility", stock_id)
	# This association comes exclusively from the authority, never a name or ID prefix.
	if not value is Dictionary or value.get("available") != true: return unavailable
	if value.get("stock_id") != stock_id or value.get("definition_id") != "cabinet" or not value.get("structure_id") is String or str(value.structure_id).is_empty() or not value.get("can_move") is bool: return unavailable
	return value.duplicate(true)

static func move_reason(ui, row: Dictionary) -> String:
	if not ui.carry.is_empty():
		return "请先将手中物品归位，再搬移设施"
	if not row.get("available", false): return "当前没有可用的储物柜关联，请重新打开实际容器"
	if not row.get("can_move", false): return P.feedback_text(row, {}, "暂时无法搬移此柜")
	if not is_instance_valid(ui.input_router) or not ui.input_router.has_method("begin_structure_action"): return "场景搬移尚未就绪"
	return ""

static func container_actions(ui, parent: Node, stock: Dictionary) -> void:
	if stock.is_empty() or not stock.get("searched", false) or stock.get("display_only", false): return
	var stock_id := str(stock.get("id", ""))
	# Queried only while rendering this one actual container, not every world snapshot.
	var row := read_container(ui, stock_id)
	if not row.get("available", false): return
	var structure_id := str(row.structure_id)
	ui.add_button("搬移此柜", func(): begin_move(ui, stock_id, structure_id), "factory:movable:move:" + stock_id, move_reason(ui, row), parent)
	ui.paragraph("保持原柜与柜内物品 · 指向附近同层目的地，左键固定 · Enter 确认 · 右键解除。目的地提交时重新检查。", parent)

static func begin_move(ui, stock_id: String, expected_structure_id: String = "") -> Dictionary:
	var row := read_container(ui, stock_id)
	var blocked := move_reason(ui, row)
	if blocked.is_empty() and (expected_structure_id.is_empty() or row.get("structure_id") != expected_structure_id): blocked = "原储物柜关联已改变，请重新打开容器"
	if blocked.is_empty() and (ui.pages.is_empty() or ui.pages.back().get("page") != "factory_inventory" or ui.pages.back().get("subject", "") != stock_id): blocked = "请从当前储物柜的取放页面选择搬移"
	if not blocked.is_empty():
		ui.notify(blocked, true); ui.queue_refresh()
		return {"ok":false, "reason":blocked}
	# Re-read association and readiness above; the router and destination submit still recheck.
	return ui.select_work_mode("move", str(row.structure_id))
