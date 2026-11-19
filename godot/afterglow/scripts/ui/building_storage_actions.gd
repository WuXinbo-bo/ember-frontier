extends RefCounted
## Real visible stock and native drag/drop slots; never an aggregate inventory.
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const Access = preload("res://scripts/ui/factory_service_access.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const LABELS := {"storage":"仓库物品", "supplies":"生活物资", "tools":"工具", "input":"原料", "output":"成品", "fuel":"燃料"}

static func render(ui, parent: Node, module: Dictionary, definition: Dictionary) -> void:
	var stocks := F.known_stocks(ui.factory, ui.snapshot, module)
	if stocks.is_empty(): return
	var is_storage: bool = definition.get("generation_role") == "storage"
	var key := "building-stock:" + str(module.id)
	var selected := str(ui.factory_view.get(key, ""))
	if not stocks.any(func(ref: Dictionary): return str(ref.stock_id) == selected): selected = str(stocks[0].stock_id)
	ui.factory_view[key] = selected
	var card := C.card(parent)
	card.set_meta("ui_building_storage", str(module.id))
	C.heading(ui, "存放与取用" if is_storage else "物资与工具", card)
	if stocks.size() > 1:
		var tabs := HFlowContainer.new()
		card.add_child(tabs)
		for ref: Dictionary in stocks:
			var tab: Button = ui.add_button(str(LABELS.get(str(ref.buffer_id), "物品")), func():
				ui.cancel_transient()
				ui.factory_view[key] = str(ref.stock_id)
				ui.queue_refresh(), "building:stock-select:" + str(ref.stock_id), "", tabs)
			tab.toggle_mode = true
			tab.set_pressed_no_signal(str(ref.stock_id) == selected)
	var chosen: Dictionary = {}
	for ref: Dictionary in stocks:
		if str(ref.stock_id) == selected: chosen = ref; break
	if chosen.is_empty(): return
	var stock: Dictionary = chosen.stock
	if stock.is_empty() or not stock.get("searched", false):
		C.caption(ui, "尚未搜索", card)
		Access.guide(ui, card, module, selected, ui.read_service_approaches(str(module.id)), false, true)
		return
	if stock.get("display_only", false):
		# Public totals may be displayed but never treated as a local drag source.
		var items: Dictionary = {}
		for buffer: Dictionary in F.stock_buffers(ui.factory, selected):
			if float(buffer.get("actual", 0)) > 0: items[str(buffer.item_id)] = buffer.actual
		if items.is_empty(): C.caption(ui, "当前没有物资", card)
		else: ui.item_row(items, "现有物资 · 走近后取放", card)
		Access.guide(ui, card, module, selected, ui.read_service_approaches(str(module.id)), true, true)
		return
	# Use original slot controls, references and transfer handlers. A short preview
	# is enough here; the full paired inventory remains one click away.
	card.set_meta("ui_inventory_width", maxf(160, ui._dialog.size.x - 112))
	ui.inventory_grid(stock, card, 12, false)
	if not ui.carry.is_empty() and str(ui.carry.get("source", {}).get("stock_id", "")) == selected:
		var transfer: Button = ui.add_button("取出到背包", ui.transfer_carried, "building:transfer:" + selected, ui.factory_transfer_reason(stock), card)
		C.primary(transfer)
	var actions := HFlowContainer.new()
	card.add_child(actions)
	var open: Button = ui.add_button("存入 / 取出", func(): ui.open_panel("factory_inventory", selected), "building:inventory:" + selected, "", actions)
	C.primary(open)
	open.icon = Icons.status_texture("inventory")
	open.expand_icon = true
	open.add_theme_constant_override("icon_max_width", 24)
	var payload: Dictionary = ui.take_all_payload(stock, ui.snapshot)
	if not payload.get("items", {}).is_empty() or not payload.get("tool_ids", []).is_empty():
		var ready: Dictionary = ui.availability(ui.request("take", selected, payload))
		var reason := "" if ready.get("ok", false) else P.feedback_text(ready)
		ui.add_button("全部取出", ui.take_all_current, "building:take-all:" + selected, reason, actions)
	C.caption(ui, "点击物品后取出 · Shift点击快速取出", card)
