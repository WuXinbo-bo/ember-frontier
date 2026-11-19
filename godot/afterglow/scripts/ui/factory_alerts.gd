extends RefCounted
## WF07 consumes only public display DTOs and the shared command path.
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")
const Map = preload("res://scripts/ui/factory_map.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const KIND_NAMES := {"player":"你", "member":"成员", "module":"设施", "regional_site":"地点", "hostile":"视线内威胁"}

static func render(ui, body: VBoxContainer, site_id: String = "") -> void:
	# Keep the explored map beside its decisions on a desktop canvas. At a
	# narrow window or larger text, use one column without shrinking controls.
	var columns: Container = HBoxContainer.new() if ui.get_viewport_rect().size.x >= 1200 * ui.text_scale else VBoxContainer.new()
	columns.add_theme_constant_override("separation", 20); body.add_child(columns)
	var overview := VBoxContainer.new(); overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.size_flags_stretch_ratio = 1.6; columns.add_child(overview)
	_map(ui, overview)
	var scope: Dictionary = ui.factory.get("scope", {})
	if not scope.is_empty(): C.caption(ui, str(scope.get("label", "远区生产、运输与交战暂停")), overview)
	var decisions := VBoxContainer.new(); decisions.size_flags_horizontal = Control.SIZE_EXPAND_FILL; columns.add_child(decisions)
	if columns is HBoxContainer: decisions.custom_minimum_size.x = 320
	var event := C.card(decisions)
	Ops.regional_event(ui, event, site_id)
	body = decisions
	var summary: Dictionary = ui.factory.get("alert_summary", {})
	Panels.heading(ui, "未解决告警 · " + str(F.alerts(ui.factory).size()), body)
	if not summary.is_empty():
		ui.paragraph("新告警 %s · 已确认 %s · 暂忽略 %s · 紧急 %s" % [summary.get("new",0), summary.get("acknowledged",0), summary.get("ignored",0), summary.get("critical",0)], body)
	ui.paragraph("确认只记录已阅读；暂忽略仅停止本次普通提醒，问题仍未解决。紧急告警始终保留。", body)
	var rows := F.alerts(ui.factory)
	if rows.is_empty(): ui.paragraph("当前没有发布的告警。", body)
	for row: Dictionary in rows: _alert(ui, body, row)
	var history := F.dictionaries(ui.factory.get("alert_history", []))
	var show_history: bool = ui.factory_view.get("alert_history_open", false)
	ui.add_button(("收起" if show_history else "查看") + "已解决历史 · " + str(history.size()), func():
		ui.factory_view.alert_history_open = not show_history; ui.queue_refresh(), "factory:alerts:history", "", body)
	if show_history:
		ui.paragraph("来源结束后才归入历史；最近最多128条。下列时间均为同一世界的模拟时间。", body)
		if history.is_empty(): ui.paragraph("尚无已解决历史。", body)
		history.reverse()
		for row: Dictionary in history: _alert(ui, body, row, true)

static func _alert(ui, body: VBoxContainer, row: Dictionary, historical: bool = false) -> void:
	var panel := PanelContainer.new(); body.add_child(panel)
	panel.set_meta("ui_alert_id", row.get("id", row.get("key", "")))
	panel.set_meta("ui_alert_historical", historical)
	var card := VBoxContainer.new(); panel.add_child(card)
	Panels.heading(ui, str(row.get("title", row.get("reason", "现场问题"))), card)
	var status: Label = ui.paragraph(F.alert_status(row, float(ui.snapshot.get("time", 0))), card)
	if row.get("severity") == "critical": status.add_theme_color_override("font_color", Color("e8ae99"))
	ui.paragraph(str(row.get("detail", row.get("reason", ""))), card)
	ui.paragraph(F.location(row.get("location")), card)
	if row.has("first_seen"):
		var times := "发生于 " + P.number(row.first_seen) + " 模拟秒"
		if historical: times += " · 结束于 " + P.number(row.get("resolved_at", 0)) + " 模拟秒"
		ui.paragraph(times, card)
	var actions := HFlowContainer.new(); card.add_child(actions)
	var id := str(row.get("id", ""))
	var allowed: Array = row.get("allowed_actions", [])
	if not historical and not id.is_empty() and not str(row.get("notification_token", "")).is_empty():
		if allowed.has("acknowledge") and not row.get("acknowledged", false):
			Ops.action(ui, actions, "确认已阅读", "alerts.acknowledge", id, F.alert_payload(row))
		if row.get("severity") != "critical" and allowed.has("ignore") and row.get("status") != "ignored":
			var payload := F.alert_payload(row); payload.seconds = 60.0
			Ops.action(ui, actions, "暂忽略60模拟秒", "alerts.ignore", id, payload)
	if not id.is_empty() and Map.valid_location(row.get("location")) and (historical or allowed.has("locate")):
		ui.add_button("在地图定位", func(): locate(ui, id, "history" if historical else "alert"), "factory:alert:locate:" + id, "", actions)
	var object_id := str(row.get("object_id", row.get("target_id", "")))
	if not F.instance(ui.factory, object_id).is_empty():
		ui.add_button("查看设施", func(): ui.open_panel("factory_module", object_id), "factory:alert:" + str(row.get("key", "")), "", actions)

static func locate(ui, id: String, source: String = "marker") -> void:
	ui.factory_view.map_focus = id
	ui.factory_view.map_focus_source = source
	ui.factory_view.map_locating = true
	ui.queue_refresh()

static func focused(ui, data: Dictionary) -> Dictionary:
	var id := str(ui.factory_view.get("map_focus", ""))
	var source := str(ui.factory_view.get("map_focus_source", "marker"))
	var rows: Array = F.dictionaries(data.get("markers", []))
	if source == "alert": rows = F.alerts(ui.factory)
	elif source == "history": rows = F.dictionaries(ui.factory.get("alert_history", []))
	var row := F.find(rows, id)
	# Never preserve a last-known hostile coordinate after A removes its marker.
	return row if Map.valid_location(row.get("location")) else {}

static func _map(ui, body: VBoxContainer) -> void:
	var data: Dictionary = ui.factory.get("map", {})
	if data.get("schema") != Map.SCHEMA:
		ui.paragraph("已探索地图尚未发布；不以整个生成地区替代探索范围。", body)
		return
	var selection := focused(ui, data)
	var known := Map.regions(data)
	if not selection.is_empty() and not known.has(selection.location.regionId): known.append(str(selection.location.regionId))
	var region := str(ui.factory_view.get("map_region", ""))
	if not selection.is_empty(): region = str(selection.location.regionId)
	elif not known.has(region):
		var player := F.find(F.dictionaries(data.get("markers", [])), "player")
		region = str(player.get("location", {}).get("regionId", ""))
		if not known.has(region): region = str(known[0]) if not known.is_empty() else ""
	var chooser := OptionButton.new()
	chooser.set_meta("ui_focus_key", "factory:map:region")
	chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in known.size():
		var label := F.region_name(str(known[index]))
		chooser.add_item(label + (" · " + str(index + 1) if label == "已知地区" else ""))
		chooser.set_item_metadata(index, str(known[index]))
		if known[index] == region: chooser.select(index)
	chooser.disabled = known.size() < 2; body.add_child(chooser)
	chooser.item_selected.connect(func(index: int):
		ui.factory_view.map_region = str(known[index]); ui.factory_view.erase("map_focus"); ui.factory_view.erase("map_focus_source"); ui.queue_refresh())
	var map := Map.new(); map.configure(data, selection, region, ui.text_scale)
	ui._known_map_canvas=map
	ui._known_map_focus_label=null
	map.set_meta("ui_focus_key", "factory:map:canvas")
	map.marker_selected.connect(func(marker: Dictionary): locate(ui, str(marker.id)))
	body.add_child(map)
	ui.paragraph("乡野底图只绘制已探索地表、道路与建筑足迹；蓝环是已知水源，深色为未知。圆点：你／成员／地点，方点：设施，赤色：实际视线内威胁。", body)
	ui.paragraph("点击标记或下方定位仅聚焦此地图，不移动人物或主镜头。", body)
	if not selection.is_empty():
		ui._known_map_focus_label=ui.paragraph("地图焦点 · " + str(selection.get("title", selection.id)) + " · " + F.location(selection.location), body)
		ui.add_button("清除地图焦点", func(): ui.factory_view.erase("map_focus"); ui.factory_view.erase("map_focus_source"); ui.queue_refresh(), "factory:map:clear", "", body)
	elif not str(ui.factory_view.get("map_focus", "")).is_empty():
		ui.paragraph("该目标已不在当前公开投影中，未保留其坐标。", body)
	if known.is_empty(): ui.paragraph("尚无探索记忆或公开标记。", body)
	var markers: Array = F.dictionaries(data.get("markers", [])).filter(func(row: Dictionary): return Map.valid_location(row.get("location")) and row.location.regionId == region)
	if not markers.is_empty():
		var list := OptionButton.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.set_meta("ui_focus_key", "factory:map:markers")
		list.add_item("定位当前地区的公开标记…")
		for marker: Dictionary in markers:
			list.add_item(str(KIND_NAMES.get(str(marker.get("kind", "")), "标记")) + " · " + str(marker.get("title", marker.id)))
		body.add_child(list)
		list.item_selected.connect(func(index: int):
			if index > 0: locate(ui, str(markers[index-1].id)))
