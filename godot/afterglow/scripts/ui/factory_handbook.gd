extends RefCounted
## On-demand public handbook DTO; no authority reads during render or STEP.
const P = preload("res://scripts/ui/ui_projection.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const Stories = preload("res://scripts/ui/factory_stories.gd")
const Footprint = preload("res://scripts/ui/factory_footprint.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const Identity = preload("res://scripts/ui/building_identity.gd")
const SCHEMA := "afterglow-factory-handbook-v1"
const PAGE_SIZE := 16
const QUALITIES := {"cutting":"切削", "sawing":"锯切", "hammering":"锤击", "digging":"挖掘", "mining":"采掘", "chopping":"采伐"}
const MODES := {"manual":"手工作业", "machine":"独立机器", "labor":"岗位劳动"}
const BUFFERS := {"input":"原料缓存", "output":"成品缓存", "fuel":"燃料缓存", "tools":"工具与资料", "supplies":"生活物资", "storage":"仓储"}
const PORTS := {"input":"供料", "output":"出料", "fuel":"燃料", "work":"作业", "repair":"维修", "service":"服务"}

static func load_snapshot(ui, entry_id: String = "") -> void:
	ui.handbook_serial += 1
	ui.handbook = {"available":false, "reason":"手册查询尚未接入；地点与线索仍可查看"}
	if not is_instance_valid(ui.runtime) or not ui.runtime.has_method("handbook_snapshot"): return
	var value: Variant = ui.runtime.call("handbook_snapshot", str(P.player(ui.snapshot).get("id", "player")), entry_id)
	if not value is Dictionary or value.get("schema") != SCHEMA or value.get("version") != 1: return
	ui.handbook = value.duplicate(true)
	var selection: Dictionary = ui.handbook.get("selection", {})
	if not entry_id.is_empty() and selection.get("id") == entry_id:
		ui.factory_view.handbook_section = str(selection.get("section_id", "materials"))
		ui.factory_view.handbook_subview = "entries"
	ui.factory_view.handbook_entry = entry_id
	ui.factory_view.handbook_page = 0
	ui.factory_view.handbook_selection_changed = true

static func normalize_alias(ui) -> void:
	if ui.factory_view.get("handbook_section") == "stories":
		ui.factory_view.handbook_section = "knowledge"
		ui.factory_view.handbook_subview = "stories"

static func is_stories(ui) -> bool:
	return ui.factory_view.get("handbook_section") == "stories" or (ui.factory_view.get("handbook_section") == "knowledge" and ui.factory_view.get("handbook_subview") == "stories")

static func view_signature(ui) -> int:
	# Snapshot is refreshed only on open/jump/explicit refresh/preference receipt.
	return [ui.pages, ui.handbook_serial, ui.factory_view, ui.text_scale, ui._notice.text].hash()

static func choose_section(ui, id: String) -> void:
	ui.factory_view.handbook_section = id
	ui.factory_view.handbook_subview = "entries"
	ui.factory_view.handbook_entry = ""
	ui.factory_view.handbook_page = 0
	ui.queue_refresh()

static func preference(ui, kind: String, id: String, enabled: bool) -> Dictionary:
	var receipt: Dictionary = ui.execute("handbook." + kind, id, {"enabled":enabled})
	# No optimistic bookmark/knowledge or amount mutation, including on rejection.
	if receipt.get("ok", false): load_snapshot(ui, str(ui.factory_view.get("handbook_entry", "")))
	return receipt

static func definition_id(entry: Dictionary) -> String:
	var reference: Dictionary = entry.get("reference", {})
	if reference.get("kind") == "item": return "item:" + str(reference.get("item_id", ""))
	if reference.get("kind") == "tool" and not str(entry.get("definition_id", "")).is_empty(): return "tool:" + str(entry.definition_id)
	if reference.get("kind") == "recipe": return "legacy:" + str(reference.get("recipe_id", reference.get("definition_id", "")))
	return ""

static func shortcut(ui, parent: Node, id: String, key: String, text: String = "查阅定义与来源") -> void:
	if id.is_empty(): return
	_button(ui, text, func(): ui.open_handbook(id), "factory:handbook:link:" + key, "请先将拿起的物品归位" if not ui.carry.is_empty() else "", parent)

static func inventory_shortcut(ui, stock: Dictionary, parent: Node) -> void:
	var entries: Array = P.entries(stock, ui.snapshot).filter(func(row: Dictionary): return not definition_id(row).is_empty())
	if entries.is_empty(): return
	var key := "handbook_stock:" + str(stock.get("id", ""))
	var line := HFlowContainer.new(); parent.add_child(line)
	var chooser := OptionButton.new(); chooser.set_meta("ui_focus_key", "factory:handbook:stock-choice:" + str(stock.id))
	var ids: Array = []
	for entry: Dictionary in entries:
		ids.append(definition_id(entry)); chooser.add_item(str(entry.get("name", "物品")))
		chooser.set_item_metadata(chooser.item_count - 1, ids.back())
	var selected := ids.find(str(ui.factory_view.get(key, "")))
	chooser.select(maxi(0, selected)); ui.factory_view[key] = str(ids[maxi(0, selected)])
	chooser.item_selected.connect(func(index: int): ui.factory_view[key] = str(chooser.get_item_metadata(index)))
	line.add_child(chooser)
	_button(ui, "查阅所选物品", func(): ui.open_handbook(str(ui.factory_view.get(key, ""))), "factory:handbook:stock-open:" + str(stock.id), "请先将拿起的物品归位" if not ui.carry.is_empty() else "", line)

static func render(ui, body: VBoxContainer) -> void:
	normalize_alias(ui)
	var book: Dictionary = ui.handbook
	var sections := HFlowContainer.new(); body.add_child(sections)
	for row: Dictionary in F.dictionaries(book.get("sections", [])):
		var id := str(row.get("id", ""))
		var tab: Button = _button(ui, str(row.get("name", id)), func(): choose_section(ui, id), "factory:book:" + id, "", sections)
		tab.theme_type_variation = "PrimaryButton" if ui.factory_view.get("handbook_section", "materials") == id else "QuietButton"
	if not book.get("available", false):
		ui.paragraph(str(book.get("reason", "当前无法读取手册")), body)
		_button(ui, "地点与线索", func(): ui.factory_view.handbook_section = "knowledge"; ui.factory_view.handbook_subview = "stories"; ui.queue_refresh(), "factory:book:stories", "", body)
		if is_stories(ui): Stories.render(ui, body)
		_button(ui, "重试读取手册", ui.refresh_handbook, "factory:book:refresh", "", body)
		return
	_search(ui, body)
	if not str(ui.factory_view.get("handbook_search", "")).strip_edges().is_empty() and not is_stories(ui): C.caption(ui, "全册搜索结果", body)
	var controls := HFlowContainer.new(); body.add_child(controls)
	_button(ui, "刷新现场条件", ui.refresh_handbook, "factory:book:refresh", "", controls)
	_button(ui, "全部条目" if ui.factory_view.get("handbook_favorites", false) else "只看收藏", func(): ui.factory_view.handbook_favorites = not ui.factory_view.get("handbook_favorites", false); ui.factory_view.handbook_page = 0; ui.queue_refresh(), "factory:book:favorites", "", controls)
	C.caption(ui, "查用途、找来源 · 现场有变化时可刷新条件", body)
	if ui.factory_view.get("handbook_section") == "sources": ui.paragraph("来源按已发现的真实对象与配方列出。采伐、补种、种植和加工均需实际资源、工具与劳动；规划本身不产物资。原水、过滤水与可饮用水分别查看，有限储备不会自动回满。", body)
	var preferences: Dictionary = book.get("preferences", {})
	var tracked := str(preferences.get("tracked_target", ""))
	if not tracked.is_empty():
		var target := F.find(F.dictionaries(book.get("entries", [])), tracked)
		shortcut(ui, body, tracked, "tracked", "固定目标 · " + str(target.get("name", tracked)) + " · 查看缺口")
	if ui.factory_view.get("handbook_section", "materials") == "knowledge":
		var tabs := HFlowContainer.new(); body.add_child(tabs)
		var knowledge_tab: Button = _button(ui, "知识与方法", func(): ui.factory_view.handbook_subview = "entries"; ui.queue_refresh(), "factory:book:knowledge:entries", "", tabs)
		var stories_tab: Button = _button(ui, "地点与线索", func(): ui.factory_view.handbook_subview = "stories"; ui.queue_refresh(), "factory:book:stories", "", tabs)
		knowledge_tab.theme_type_variation = "QuietButton" if is_stories(ui) else "PrimaryButton"
		stories_tab.theme_type_variation = "PrimaryButton" if is_stories(ui) else "QuietButton"
		if is_stories(ui): Stories.render(ui, body); return
	var selection: Dictionary = book.get("selection", {})
	var requested := str(ui.factory_view.get("handbook_entry", ""))
	if not requested.is_empty():
		_button(ui, "‹ 返回本类条目", func(): ui.factory_view.handbook_entry = ""; ui.queue_refresh(), "factory:book:list", "", body)
		if selection.get("id") == requested: _detail(ui, body, selection)
		else: ui.paragraph("所选定义当前不可用，请返回列表选择；没有读取隐藏实例。", body)
		return
	_categories(ui, body)
	var matches := filtered(ui)
	var page := clampi(int(ui.factory_view.get("handbook_page", 0)), 0, maxi(0, ceili(matches.size() / float(PAGE_SIZE)) - 1))
	ui.factory_view.handbook_page = page
	ui.paragraph("匹配 %s 条 · 第 %s 页" % [matches.size(), page + 1], body)
	var cards := GridContainer.new(); cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.columns = 2 if ui.get_viewport_rect().size.x >= 1200 and ui.text_scale <= 1.0 else 1
	body.add_child(cards)
	for index in range(page * PAGE_SIZE, mini(matches.size(), (page + 1) * PAGE_SIZE)):
		var entry: Dictionary = matches[index]
		var card := _card(cards)
		C.image_row(ui, card, entry_image(entry), entry_name(entry), _status(entry), roundi(48 * ui.text_scale))
		var actions := HFlowContainer.new(); card.add_child(actions)
		_button(ui, "查看详情", func(): ui.open_handbook(str(entry.id)), "factory:book:entry:" + str(entry.id), "", actions)
	if matches.is_empty(): ui.paragraph("此分类暂无匹配的正式条目；尚未发布的设施不会作为可用内容列出。", body)
	if matches.size() > PAGE_SIZE:
		var paging := HBoxContainer.new(); body.add_child(paging)
		_button(ui, "上一页", func(): ui.factory_view.handbook_page = page - 1; ui.queue_refresh(), "factory:book:previous", "已是第一页" if page == 0 else "", paging)
		_button(ui, "下一页", func(): ui.factory_view.handbook_page = page + 1; ui.queue_refresh(), "factory:book:next", "已是最后一页" if (page + 1) * PAGE_SIZE >= matches.size() else "", paging)

static func _search(ui, body: Node) -> void:
	var edit := LineEdit.new(); edit.placeholder_text = "搜索物品、工具、建筑或工艺"
	edit.text = str(ui.factory_view.get("handbook_search", "")); edit.clear_button_enabled = true
	edit.set_meta("ui_focus_key", "factory:search:handbook_search")
	edit.text_changed.connect(func(text: String): ui.factory_view.handbook_search = text; ui.factory_view.handbook_entry = ""; ui.factory_view.handbook_page = 0; ui.queue_refresh())
	body.add_child(edit)

static func _categories(ui, body: Node) -> void:
	var select := OptionButton.new(); select.set_meta("ui_focus_key", "factory:book:category")
	select.add_item("全部内容类别"); select.set_item_metadata(0, "all")
	for row: Dictionary in F.dictionaries(ui.handbook.get("categories", [])):
		select.add_item(str(row.get("name", row.get("id", "")))); select.set_item_metadata(select.item_count - 1, str(row.get("id", "")))
	var current := str(ui.factory_view.get("handbook_category", "all"))
	for index in select.item_count:
		if select.get_item_metadata(index) == current: select.select(index)
	select.item_selected.connect(func(index: int): ui.factory_view.handbook_category = str(select.get_item_metadata(index)); ui.factory_view.handbook_page = 0; ui.queue_refresh())
	body.add_child(select)

static func filtered(ui) -> Array:
	var result: Array = []
	var query := str(ui.factory_view.get("handbook_search", "")).strip_edges().to_lower()
	var section := str(ui.factory_view.get("handbook_section", "materials"))
	var category := str(ui.factory_view.get("handbook_category", "all"))
	var favorites: Array = ui.handbook.get("preferences", {}).get("favorites", [])
	for entry: Dictionary in F.dictionaries(ui.handbook.get("entries", [])):
		if query.is_empty() and entry.get("section_id") != section: continue
		if category != "all" and entry.get("category_id") != category: continue
		if ui.factory_view.get("handbook_favorites", false) and not favorites.has(entry.get("id")): continue
		if not query.is_empty() and not (entry_name(entry) + " " + str(entry.get("description", "")) + " " + str(entry.get("id", ""))).to_lower().contains(query): continue
		result.append(entry)
	return result

static func entry_name(entry: Dictionary) -> String:
	var name := str(entry.get("name", entry.get("id", "条目")))
	if entry.get("kind") == "module": return Identity.name(entry.get("definition", {}), name)
	return name + " · " + str(MODES.get(str(entry.get("definition", {}).get("mode", "")), "工艺")) if entry.get("kind") == "process" else name

static func _status(entry: Dictionary) -> String:
	var status := "已发现实物" if entry.get("discovered", false) else "尚未发现实物"
	if entry.get("learned") is bool: status += " · 已掌握" if entry.learned else " · 尚未掌握"
	if entry.get("kind") == "legacy": status += " · 旧式设施"
	return status

static func _detail(ui, body: Node, entry: Dictionary) -> void:
	var card := _card(body); card.set_meta("ui_handbook_selection", str(entry.id))
	C.image_row(ui,card,entry_image(entry),entry_name(entry),_status(entry),roundi(64 * ui.text_scale))
	if not str(entry.get("description", "")).is_empty(): ui.paragraph(str(entry.description), card)
	if entry.id == "source:trees": ui.paragraph("采伐与补种由林区真实作业执行；种苗、通路和工具需现场具备，生长随同一世界时钟推进。", card)
	var use_hint := Icons.use_hint(str(entry.get("source_id", "")))
	if not use_hint.is_empty(): C.caption(ui,use_hint,card)
	if entry.id == "item:water": ui.paragraph("饮水仍是有限储备；可饮用性与剩余量以已发现来源的真实状态为准。查阅不补充库存，也不代表河井水可直接饮用。", card)
	if entry.get("kind") == "terrain":
		var material: Dictionary = entry.get("definition", {})
		if material.get("key") == "bedrock": ui.paragraph("受保护基底不可挖掘，不是工具等级不足。", card)
		elif not str(material.get("item", "")).is_empty(): ui.paragraph("对应物资 · " + P.item_name(str(material.item)) + "；可挖性、所需工具与实际产量以现场作业预检为准。", card)
	var prefs: Dictionary = ui.handbook.get("preferences", {})
	var favorite: bool = prefs.get("favorites", []).has(entry.id)
	var tracked: bool = prefs.get("tracked_target", "") == entry.id
	var actions := HFlowContainer.new(); card.add_child(actions)
	_button(ui, "取消收藏" if favorite else "收藏此条目", func(): preference(ui, "favorite", str(entry.id), not favorite), "factory:book:favorite:" + str(entry.id), "", actions)
	_button(ui, "取消固定目标" if tracked else "固定目标并查看缺口", func(): preference(ui, "track", str(entry.id), not tracked), "factory:book:track:" + str(entry.id), "", actions)
	var is_tool: bool = entry.get("kind") == "tool"
	# A tool has use capabilities and actual instances, not a construction test.
	# Keep its two short specifications with the identity rather than reserve
	# an empty comparison column or claim that an unknown craft is actionable.
	if is_tool: _definition(ui, card, entry.get("definition", {}))
	var columns: Container = HBoxContainer.new() if not is_tool and ui.get_viewport_rect().size.x >= 1200 and ui.text_scale <= 1.0 else VBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(columns)
	card = _card(columns)
	C.heading(ui,"现有工具" if is_tool else "库存与去向" if entry.get("kind") == "item" else "准备情况",card)
	if not is_tool:
		var specifications := _card(columns)
		C.heading(ui,"用途与规格",specifications)
		_definition(ui, specifications, entry.get("definition", {}))
	var current: Dictionary = entry.get("current", {})
	if entry.get("kind") == "process":
		ui.paragraph("当前可做 · " + ("条件满足" if current.get("can_make") == true else "暂时无法开始"), card)
		if current.get("onsite") is bool: C.caption(ui, "已在可用工位旁" if current.onsite else "需到工位旁准备材料与工具", card)
		if entry.get("definition", {}).get("mode") == "machine": C.caption(ui, "运行需本机原料、燃料和成品空间，村落合计仅供准备参考。", card)
	elif entry.get("kind") == "module": C.caption(ui, "到建造目录选址，再检查地面与通路。", card)
	elif is_tool: C.caption(ui, "现场有完好且未占用的工具" if current.get("onsite") == true else "现场暂无可用工具", card)
	for order: Dictionary in F.dictionaries(current.get("orders", [])):
		ui.paragraph("本工艺订单 · " + F.state_text(order) + " · 已完成 " + P.number(order.get("completed")) + " 批 · 剩余 " + ("连续" if int(order.get("remaining", 0)) < 0 else P.number(order.get("remaining")) + " 批"), card)
		for reason in order.get("blockers", []): ui.paragraph(str(F.STATE_NAMES.get(str(reason), P.reason_text(reason))), card)
	for blocker: Dictionary in F.dictionaries(current.get("blockers", [])):
		if blocker.get("code") in ["CHOOSE_SITE", "TOOL_UNAVAILABLE"]: continue # Exact condition is already above.
		ui.paragraph(str(blocker.get("reason", blocker.get("code", "条件未满足"))), card)
	for row: Dictionary in F.dictionaries(current.get("materials", [])):
		var id := str(row.get("item_id", ""))
		ui.paragraph(P.item_name(id) + " · 需要 " + P.number(row.get("required")) + P.item_unit(id) + "\n已知可用 " + P.number(row.get("known_free")) + " · 准备缺口 " + P.number(row.get("missing")) + "\n现场可用 " + P.number(row.get("onsite_free")) + " · 现场缺口 " + P.number(row.get("onsite_missing")), card)
	for stock: Dictionary in F.dictionaries(current.get("stocks", [])):
		var quantity: Dictionary = stock.get("quantity", {})
		var known: Dictionary = F.visible_stock(ui.factory, ui.snapshot, str(stock.get("id", "")))
		var name := str(known.get("name", "随身背包" if stock.get("id") == "pack:player" else "已知设施缓存"))
		ui.paragraph(name + " · 实有 " + P.number(quantity.get("actual")) + " · 原料预留 " + P.number(quantity.get("reserved")) + " · 可用 " + P.number(quantity.get("free")) + (" · 已在现场" if stock.get("onsite") == true else " · 需真实运到现场"), card)
	if current.has("actual"):
		ui.paragraph("已知合计 · 实有 " + P.number(current.get("actual")) + " · 原料预留 " + P.number(current.get("reserved")) + " · 可用 " + P.number(current.get("free")) + " · 现场可用 " + P.number(current.get("onsite_free")), card)
	for tool: Dictionary in F.dictionaries(current.get("tools", [])):
		var definition: Dictionary = ui.snapshot.get("catalog", {}).get("tool_definitions", {}).get(str(tool.get("kind", "")), {})
		ui.paragraph(str(tool.get("name", definition.get("name", "真实工具"))) + " · 耐久 " + P.number(tool.get("durability")) + (" · 已被作业占用" if tool.get("reserved") == true else " · 现场未占用" if tool.get("onsite") == true else " · 需到场"), card)
	for instance: Dictionary in F.dictionaries(current.get("known_instances", [])):
		if instance.has("definition_id") and not str(instance.get("id", "")).is_empty(): _button(ui, "打开" + Identity.instance_name(F.definition(ui.factory,str(instance.definition_id)),instance), func(): ui.open_panel("factory_module", str(instance.id)), "factory:book:instance:" + str(instance.id), "", card)
		elif entry.get("kind") == "knowledge": ui.paragraph("已知资料 · " + str(instance.get("name", P.item_name(str(instance.get("itemId", ""))))) + " · 阅读仍需到场并实际研读", card)
	var request: Variant = current.get("request")
	if request is Dictionary and request.get("kind") == "craft" and not str(request.get("target_id", "")).is_empty():
		_button(ui, "在此工位选择原工具" if entry.get("definition", {}).has("repairTool") else "查看现场工位配方", func(): ui.open_panel("workbench", str(request.target_id)), "factory:book:workbench", "", card)
	elif entry.get("definition", {}).has("repairTool"):
		ui.paragraph("请到真实工位按E选择待修的原工具；缺工具时查阅下方已知来源。", card)
	_relations(ui, card, "从哪里获得", entry.get("sources", []))
	_relations(ui, card, "可用于什么", entry.get("uses", []))
	var linked: Array = []
	for relation: Dictionary in F.dictionaries(entry.get("sources", [])) + F.dictionaries(entry.get("uses", [])): linked.append(relation.get("id"))
	for id in entry.get("related_ids", []):
		if id is String and not linked.has(id):
			var related := F.find(F.dictionaries(ui.handbook.get("entries", [])), id)
			if not related.is_empty(): shortcut(ui, card, id, "related:" + id, "关联 · " + str(related.get("name", id)))

static func _relations(ui, parent: Node, title: String, value: Variant) -> void:
	var relations := F.dictionaries(value)
	if relations.is_empty(): return
	Panels.heading(ui, title, parent)
	var links := HFlowContainer.new(); parent.add_child(links)
	for relation: Dictionary in relations:
		if F.find(F.dictionaries(ui.handbook.get("entries", [])), str(relation.get("id", ""))).is_empty(): continue
		var related := F.find(F.dictionaries(ui.handbook.get("entries", [])), str(relation.id))
		shortcut(ui, links, str(relation.id), "relation:" + str(relation.id), entry_name(related))

static func entry_image(entry: Dictionary) -> Texture2D:
	if entry.get("kind") == "module": return Images.module_texture(entry.get("definition", {}))
	return Icons.texture({"reference":{"kind":entry.get("kind"),"item_id":entry.get("source_id")},"definition_id":entry.get("source_id")})

static func _definition(ui, parent: Node, definition: Dictionary) -> void:
	if definition.get("zone_kinds") is Dictionary:
		for kind:String in definition.zone_kinds:
			var zone:Variant=definition.zone_kinds[kind]
			if zone is Dictionary:ui.paragraph(str(zone.get("name","区域"))+" · "+str(zone.get("description","")),parent)
	if definition.get("crop_rules") is Dictionary:
		var rule:Dictionary=definition.crop_rules
		if rule.has("seed"):ui.paragraph("种料 · "+P.item_name(str(rule.seed)),parent)
		for spec:Array in [["seconds","条件满足时的游戏生长秒数"],["water","每阶段需要的土壤水分"]]:
			if rule.has(spec[0]):ui.paragraph(str(spec[1])+" · "+P.number(rule[spec[0]]),parent)
		if rule.has("item") and rule.has("yield"):ui.item_row({str(rule.item):rule.yield},"每次实际收获（规则规格，非现有库存）",parent)
	if definition.get("tree_rules") is Dictionary:
		var rule:Dictionary=definition.tree_rules
		for spec:Array in [["seed","母树种子"],["seedling","栽植苗木"]]:
			if rule.has(spec[0]):ui.paragraph(str(spec[1])+" · "+P.item_name(str(rule[spec[0]])),parent)
		for spec:Array in [["young_seconds","幼苗阶段游戏秒数"],["mature_seconds","幼树阶段游戏秒数"]]:
			if rule.has(spec[0]):ui.paragraph(str(spec[1])+" · "+P.number(rule[spec[0]]),parent)
	if definition.get("ecology_kind")=="raw_water":ui.paragraph("桶可重复使用；具体可取量、补水与到场条件须查看实际已发现水源。",parent)
	for spec in [["build_cost","建设成本"],["cost","所需材料"],["inputs","投入"],["outputs","全部输出"],["byproducts","副产物"]]:
		var value: Variant = definition.get(spec[0])
		if value is Dictionary and value.values().all(func(v): return v is int or v is float): ui.item_row(value, spec[1], parent)
	for spec in [["seconds","有效工时（秒）"],["build_seconds","施工工时（秒）"],["maxDurability","工具最大耐久"],["max_durability","工具最大耐久"],["minCrafting","制作技能条件"],["hp","结构耐久"]]:
		if definition.has(spec[0]) and definition[spec[0]] != null: ui.paragraph(spec[1] + " · " + P.number(definition[spec[0]]), parent)
	if definition.has("unit"): ui.paragraph("计量 · " + str({"count":"份／件", "m3":"立方米"}.get(str(definition.unit), definition.unit)), parent)
	if definition.has("mode"): ui.paragraph("执行方式 · " + str(MODES.get(str(definition.mode), "按现场工艺执行")), parent)
	if definition.get("recipe_modes") is Array:
		ui.paragraph("可承载 · " + " / ".join(definition.recipe_modes.map(func(mode): return str(MODES.get(str(mode), "现场工艺")))), parent)
	if definition.get("qualities") is Dictionary:
		for quality in definition.qualities:
			ui.paragraph(str(QUALITIES.get(str(quality), "作业能力")) + " · " + P.number(definition.qualities[quality]), parent)
	if definition.get("tools") is Dictionary:
		for quality in definition.tools: ui.paragraph(str(QUALITIES.get(str(quality), "所需工具能力")) + " · " + P.number(definition.tools[quality]), parent)
	var footprint: Dictionary = definition.get("footprint", {})
	if footprint.get("min") is Dictionary and footprint.get("max") is Dictionary:
		ui.paragraph("占地 %s × %s 米 · 高 %s 米" % [P.number(float(footprint.max.x) - float(footprint.min.x)), P.number(float(footprint.max.z) - float(footprint.min.z)), P.number(float(footprint.max.y) - float(footprint.min.y))], parent)
		var diagram := Footprint.new(); diagram.configure(definition); parent.add_child(diagram)
	for buffer: Dictionary in F.dictionaries(definition.get("buffer_specs", [])):
		ui.item_row(buffer.get("limits", {}), str(BUFFERS.get(str(buffer.get("id", "")), "设施缓存")) + " · 每物品上限", parent)
	for port: Dictionary in F.dictionaries(definition.get("ports", [])):
		ui.paragraph(str(PORTS.get(str(port.get("purpose", "")), "设施接口")) + "接口 · " + str({"north":"北侧", "south":"南侧", "west":"西侧", "east":"东侧"}.get(str(port.get("direction", "")), "按图示朝向")), parent)
	if definition.get("energy") is Dictionary:
		for field in ["inputs", "fuel"]:
			if definition.energy.get(field) is Dictionary: ui.item_row(definition.energy[field], "能源投入", parent)
	if definition.get("knowledge") is Array and not definition.knowledge.is_empty(): ui.paragraph("所需知识见下方关联；是否掌握以真实学习记录为准。", parent)
	for field in ["createTool", "repairTool"]:
		var tool: Variant = definition.get(field)
		if not tool is Dictionary: continue
		var kind := str(tool.get("kind", ""))
		var target: Dictionary = ui.snapshot.get("catalog", {}).get("tool_definitions", {}).get(kind, {})
		if field == "repairTool":
			ui.paragraph("整备原工具 · " + str(target.get("name", "对应工具")) + " · 恢复 " + P.number(tool.get("restore")) + " 耐久（不超过上限）", parent)
			ui.paragraph("修复同一工具实例；待修工具不能同时充当操作工具，满耐久不可重复整备。", parent)
			if definition.get("qualities") == {}: ui.paragraph("此工序不要求额外操作工具；仍需真实工位、材料和劳动。", parent)
		else: ui.paragraph("实际装配工具 · " + str(target.get("name", "对应工具")), parent)

static func _card(parent: Node) -> VBoxContainer:
	return C.card(parent)

static func _button(ui, text: String, action: Callable, key: String, reason: String = "", parent: Node = null) -> Button:
	var value: Button = ui.add_button(text, action, key, reason, parent)
	value.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return value
