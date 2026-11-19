extends RefCounted
## Reusable native composition, never simulation state or permission rules.
const Palette = preload("res://scripts/ui/ui_theme.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")

static func form(page: String) -> String:
	if page in ["factory_module","npc","npc_quick","workbench","water"]: return "object"
	if page in ["factory_catalog","build","terrain","zone_planning"]: return "planning"
	if page in ["pause","new_world","close_failed","factory_confirm"]: return "dialog"
	return "management"

static func bounds(viewport: Vector2, page: String, scale_factor: float) -> Rect2:
	var margin := 16.0
	var height := maxf(240,viewport.y - margin * 2)
	var style := form(page)
	var width := minf(1120,viewport.x - margin * 2)
	if style == "object": width = minf(maxf(400,416 * minf(scale_factor,1.25)),viewport.x * 0.52)
	elif style == "planning": width = minf(360 * minf(scale_factor,1.25),viewport.x * 0.42)
	elif style == "dialog": width = minf(560 * minf(scale_factor,1.25),viewport.x - margin * 2)
	if page == "factory_module": width = minf(520 * minf(scale_factor, 1.25), viewport.x * 0.56)
	var x := viewport.x - width - margin if style == "object" else margin if style == "planning" else (viewport.x-width)/2
	return Rect2(Vector2(x,margin),Vector2(width,height))

static func card(parent: Node, emphasis: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.theme_type_variation = "WorkshopEmphasis" if emphasis else "WorkshopCard"
	parent.add_child(panel)
	var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_child(column)
	return column

static func heading(ui, title: String, parent: Node, note: String = "") -> void:
	var value: Label=ui.paragraph(title,parent);value.theme_type_variation="SectionTitle"
	if not note.is_empty(): caption(ui,note,parent)

static func caption(ui, text: String, parent: Node) -> Label:
	var value: Label=ui.paragraph(text,parent);value.theme_type_variation="Caption";return value

static func fold(ui, parent: Node, key: String, title: String, default_open: bool = false) -> VBoxContainer:
	var opened: bool = ui.factory_view.get("fold:"+key,default_open)
	var button: Button=ui.add_button(("−  " if opened else "+  ")+title,func():ui.factory_view["fold:"+key]=not opened;ui.queue_refresh(),"fold:"+key,"",parent)
	button.theme_type_variation="QuietButton";button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	if not opened:return null
	var content := VBoxContainer.new();parent.add_child(content);return content

static func primary(button: Button) -> Button:
	button.theme_type_variation="PrimaryButton";return button

static func image_row(ui, parent: Node, texture: Texture2D, title: String, note: String="", width: int=64) -> VBoxContainer:
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",16);parent.add_child(row)
	if texture != null:row.add_child(Icons.image(texture,width))
	var text := VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	heading(ui,title,text,note);return text

static func reason(ui, parent: Node, text: String) -> void:
	if text.is_empty():return
	var node: Label=ui.paragraph("!  "+text,parent);node.add_theme_color_override("font_color",Palette.RUST)

static func materials(ui, parent: Node, cost: Dictionary, source: Dictionary, title: String = "材料准备", show_note: bool = true) -> void:
	# Preparation is the selected source's real free stock, not delivered work.
	if cost.is_empty(): return
	caption(ui, title, parent)
	for item: String in cost:
		var need := maxf(0, float(cost[item]))
		var entry := P.entry(source, ui.snapshot, {"kind":"item", "item_id":item})
		var have := maxf(0, float(entry.get("available", 0)))
		var row := HBoxContainer.new(); parent.add_child(row)
		var texture := Icons.texture(entry if not entry.is_empty() else {"reference":{"kind":"item", "item_id":item}, "name":P.item_name(item)})
		if texture != null: row.add_child(Icons.image(texture, roundi(24 * ui.text_scale)))
		var detail := VBoxContainer.new(); detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(detail)
		var amount := P.item_name(item) + "  " + P.number(minf(have,need)) + " / " + P.number(need)
		if have < need: amount += " · 缺 " + P.number(need-have)
		var text: Label = caption(ui, amount, detail)
		text.add_theme_color_override("font_color", Palette.MOSS if have >= need else Palette.RUST)
		var bar := ProgressBar.new(); bar.show_percentage = false; bar.max_value = maxf(1, need); bar.value = minf(have,need); bar.custom_minimum_size.y = 4; detail.add_child(bar)
	if show_note: caption(ui, "可用量已扣预留；开工时再次核对材料、工具与现场。", parent)

static func production_flow(ui, parent: Node, inputs: Dictionary, outputs: Dictionary, seconds: Variant) -> void:
	var flow := HBoxContainer.new(); parent.add_child(flow)
	var incoming := card(flow); incoming.custom_minimum_size.x = 90
	caption(ui, "投入 / 批", incoming); _flow_items(ui, incoming, inputs)
	var arrow := VBoxContainer.new(); arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER; flow.add_child(arrow)
	arrow.custom_minimum_size.x = 56 * ui.text_scale
	var direction: Label = ui.paragraph("→", arrow); direction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var duration: Label = caption(ui, P.number(seconds) + "秒", arrow)
	duration.autowrap_mode = TextServer.AUTOWRAP_OFF
	duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var outgoing := card(flow); outgoing.custom_minimum_size.x = 90
	caption(ui, "产出 / 批", outgoing); _flow_items(ui, outgoing, outputs)

static func _flow_items(ui, parent: Node, items: Dictionary) -> void:
	for item: String in items:
		var row := HBoxContainer.new(); parent.add_child(row)
		var texture := Icons.texture({"reference":{"kind":"item","item_id":item}})
		if texture != null: row.add_child(Icons.image(texture,roundi(22*ui.text_scale)))
		var text: Label = caption(ui,P.item_text(item,items[item]),row)
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x=0
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
