extends RefCounted
## Building catalogue: public owner choices and descriptive architecture only.
## No inferred IDs, geometry, capacity, upgrade permission or construction cost.
const C = preload("res://scripts/ui/ui_composition.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const Footprint = preload("res://scripts/ui/factory_footprint.gd")
const Handbook = preload("res://scripts/ui/factory_handbook.gd")
const Movable = preload("res://scripts/ui/factory_movable.gd")
const Identity = preload("res://scripts/ui/building_identity.gd")
const SET := "r34-architecture-30-v1"
const FAMILIES := {"home":"住宅", "workshop":"手工作坊", "sawmill":"锯木厂", "warehouse":"仓库", "canteen":"食堂", "artisan":"工匠坊", "water":"水务", "repair":"维修", "guard":"岗亭", "supply":"补给与物流", "legacy":"原有设施"}
const TIERS := {"small":"小型", "medium":"中型", "large":"大型", "low":"Ⅰ级", "mid":"Ⅱ级", "high":"Ⅲ级"}
const PORTS := {"input":"供料", "output":"出料", "fuel":"燃料", "work":"作业", "repair":"维修", "service":"补给服务"}
const COMPACT_FAMILIES := {"cottage":"home", "stockyard":"warehouse", "kitchen":"canteen"}
const PAGE_SIZE := 8

static func architecture(definition: Dictionary) -> Dictionary:
	return _architecture(definition).duplicate(true)

static func _architecture(definition:Dictionary)->Dictionary:
	var value: Variant = definition.get("architecture")
	if not value is Dictionary or value.get("set") != SET: return {}
	# Metadata is descriptive. A missing field never promotes a legacy building
	# into a new family, creates residents or grants an in-place upgrade.
	return value

static func family(definition: Dictionary) -> String:
	if definition.has("village_tier"):
		var kind := str(definition.get("village_family_art", ""))
		var compact_family := str(COMPACT_FAMILIES.get(kind, kind))
		if FAMILIES.has(compact_family): return compact_family
		var identity := Identity.family(definition)
		return identity if FAMILIES.has(identity) else "legacy"
	var value := _architecture(definition)
	var key := str(value.get("family", ""))
	return key if FAMILIES.has(key) and key != "legacy" else "legacy"

static func tier(definition: Dictionary) -> String:
	if definition.has("village_tier"):
		return str({1:"low", 2:"mid", 3:"high"}.get(int(definition.village_tier), ""))
	var value := _architecture(definition)
	var key := str(value.get("tier", ""))
	var allowed: Array = ["small", "medium", "large"] if family(definition) == "home" else ["low", "mid", "high"]
	return key if not value.is_empty() and allowed.has(key) else ""

static func capacity_text(definition: Dictionary) -> String:
	if family(definition) != "home": return ""
	if definition.has("village_tier"):
		var beds := int(definition.get("mechanism", {}).get("beds", 0))
		return "床位上限 %s" % P.stat_number(beds) if beds > 0 else ""
	var amount: Variant = _architecture(definition).get("design_capacity")
	if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) <= 0 or floorf(float(amount)) != float(amount): return "设计容量未提供"
	return "设计容量 %s 人" % P.stat_number(amount)

static func footprint_text(definition: Dictionary) -> String:
	var bounds: Variant = definition.get("footprint")
	if not bounds is Dictionary or not bounds.get("min") is Dictionary or not bounds.get("max") is Dictionary: return "占地尺寸未提供"
	var dimensions: Array = []
	for axis: String in ["x", "z", "y"]:
		var low: Variant = bounds.min.get(axis)
		var high: Variant = bounds.max.get(axis)
		if not (low is int or low is float) or not (high is int or high is float) or not is_finite(float(low)) or not is_finite(float(high)) or float(high) <= float(low): return "占地尺寸未提供"
		dimensions.append(P.number(float(high) - float(low)))
	return "占地 %s × %s 米 · 高 %s 米" % dimensions

static func matches(definition: Dictionary, category: String, purpose: String, level: String, query: String, favorites: Dictionary) -> bool:
	if category == "movable": return false
	var role := str(definition.get("generation_role", ""))
	if category == "workshop" and role not in ["machine", "workshop"]: return false
	if category == "storage" and role not in ["storage", "home"]: return false
	if category == "favorites" and not favorites.has(str(definition.get("id", ""))): return false
	if purpose != "all" and family(definition) != purpose: return false
	if level != "all" and tier(definition) != level: return false
	var normalized:String=query.strip_edges().to_lower()
	if normalized.is_empty():return true
	var value := _architecture(definition)
	var search := " ".join([Identity.name(definition), Identity.purpose(definition), str(definition.get("source_name", "")), str(definition.get("name", "")), str(definition.get("id", "")), role, str(FAMILIES.get(family(definition), "")), str(TIERS.get(tier(definition), "")), str(value.get("variant", "")), str(value.get("variant_label", "")), str(value.get("description", "")), str(definition.get("village_role", "")), capacity_text(definition)]).to_lower()
	return search.contains(normalized)

static func render(ui, body: VBoxContainer) -> void:
	var definitions := F.build_definitions(ui.factory)
	var stage := F.section(ui.factory, "village_stage")
	if stage.is_empty(): stage = F.section(F.section(ui.factory, "modules"), "village_stage")
	if stage.is_empty() and definitions.any(func(row: Dictionary) -> bool: return row.has("village_stage_required")) and is_instance_valid(ui.runtime) and ui.runtime.has_method("domain_service"):
		# Chapter definitions have new IDs but the stage is still owned by modules.
		var modules: Variant = ui.runtime.domain_service("modules")
		if modules != null and modules.has_method("village_building_stage"): stage = modules.village_building_stage()
	if not stage.is_empty(): _stage(ui, body, stage)
	var worker_id:String=ui.building_dispatch_actor() if ui.has_method("building_dispatch_actor") else ""
	if not worker_id.is_empty():
		var worker:=P.find(ui.snapshot.get("actors",[]),worker_id)
		C.heading(ui,"为"+str(worker.get("name","同伴"))+"选择住宅",body)
		C.caption(ui, "选择住宅后在场景固定位置，再确认建立蓝图。", body)
		var homes:=definitions.filter(func(row:Dictionary)->bool:return row.get("shape")=="home")
		if homes.is_empty():C.caption(ui,"当前没有可放置的住宅蓝图",body)
		for row:Dictionary in homes:_card(ui,body,row,stage,true)
		return
	_quick_build(ui, body, definitions, stage)
	var search := LineEdit.new()
	search.placeholder_text = "搜索建筑、款式或用途"
	search.text = str(ui.factory_view.get("catalog_search", ""))
	search.clear_button_enabled = true
	search.theme_type_variation = "SearchField"
	search.set_meta("ui_focus_key", "factory:search:catalog_search")
	search.text_changed.connect(func(value: String): ui.factory_view.catalog_search = value; ui.factory_view.catalog_page = 0; ui.queue_refresh())
	body.add_child(search)
	var filters := HFlowContainer.new(); body.add_child(filters)
	for scope: Array in [["all", "全部"], ["favorites", "收藏"], ["movable", "可搬设施"]]:
		var tab: Button = ui.add_button(scope[1], func(): ui.factory_view.catalog_category = scope[0]; ui.factory_view.catalog_page = 0; ui.queue_refresh(), "factory:category:" + scope[0], "", filters)
		tab.theme_type_variation = "PrimaryButton" if ui.factory_view.get("catalog_category", "all") == scope[0] else "QuietButton"
	var category := str(ui.factory_view.get("catalog_category", "all"))
	var purpose := str(ui.factory_view.get("catalog_family", "all"))
	var level := str(ui.factory_view.get("catalog_tier", "all"))
	if category != "movable":
		var purposes: Array = [["all", "全部用途"]]
		for key: String in FAMILIES:
			if definitions.any(func(row: Dictionary): return family(row) == key): purposes.append([key, FAMILIES[key]])
		# Keep stale preferences explicit and recoverable when an owner removes a
		# choice; never silently replace a requested filter with build permission.
		if not purposes.any(func(row: Array): return row[0] == purpose): purposes.append([purpose, "该用途当前无可选项"])
		_choice(ui, body, "catalog_family", "factory:catalog:family", purposes, purpose, true)
		var levels: Array = [["all", "全部级别"]]
		for key: String in TIERS:
			if definitions.any(func(row: Dictionary): return (purpose == "all" or family(row) == purpose) and tier(row) == key): levels.append([key, TIERS[key]])
		if not levels.any(func(row: Array): return row[0] == level): levels.append([level, "该级别当前无可选项"])
		_choice(ui, body, "catalog_tier", "factory:catalog:tier", levels, level)
	C.caption(ui, "选择建筑后在场景左键固定位置。Enter 确认 · 右键解除固定。", body)
	C.caption(ui, "入口、供料面、出料面和作业面需要接通村路，并为院落与后续扩建留地。", body)
	var filtered:Array=[]
	for definition:Dictionary in definitions:
		if matches(definition,category,purpose,level,search.text,ui.factory_favorites):filtered.append(definition)
	var count:int=filtered.size()
	var last_page:int=maxi(0,ceili(float(count)/PAGE_SIZE)-1)
	var page:int=clampi(int(ui.factory_view.get("catalog_page",0)),0,last_page)
	ui.factory_view.catalog_page=page
	var summary := C.caption(ui, "", body)
	summary.set_meta("ui_catalog_summary", true)
	if count>PAGE_SIZE:
		var paging:=HFlowContainer.new();body.add_child(paging)
		ui.add_button("上一页",func():ui.factory_view.catalog_page=page-1;ui.queue_refresh(),"factory:catalog:previous","已是第一页" if page==0 else "",paging)
		paging.add_child(ui.label("第 %s / %s 页 · 每页最多 %s 款" %[page+1,last_page+1,PAGE_SIZE]))
		ui.add_button("下一页",func():ui.factory_view.catalog_page=page+1;ui.queue_refresh(),"factory:catalog:next","已是最后一页" if page==last_page else "",paging)
	for index:int in range(page*PAGE_SIZE,mini(count,(page+1)*PAGE_SIZE)):_card(ui,body,filtered[index],stage)
	# The existing cabinet is not a new architecture family. Only include it
	# when no architecture filter is active, so it cannot masquerade as a tier.
	var movable_count := Movable.render(ui, body, category) if purpose == "all" and level == "all" or category == "movable" else 0
	summary.text = "建筑 %s / %s 款%s" % [count, definitions.size(), " · 可搬设施另列" if movable_count > 0 else ""]
	if count == 0 and movable_count == 0: C.caption(ui, "没有匹配项。可切回全部用途、全部级别或清空搜索。", body)
	var reason: String = ui.module_preview_reason()
	if not reason.is_empty(): C.reason(ui, body, reason)

static func _choice(ui, parent: Node, state: String, key: String, options: Array, selected: String, reset_tier: bool = false) -> void:
	var select := OptionButton.new()
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.set_meta("ui_focus_key", key)
	for index: int in options.size():
		select.add_item(str(options[index][1]))
		select.set_item_metadata(index, str(options[index][0]))
		if options[index][0] == selected: select.select(index)
	select.item_selected.connect(func(index: int):
		ui.factory_view[state] = str(select.get_item_metadata(index))
		ui.factory_view.catalog_page = 0
		if reset_tier: ui.factory_view.catalog_tier = "all"
		ui.queue_refresh())
	parent.add_child(select)

static func _stage(ui, parent: VBoxContainer, stage: Dictionary) -> void:
	var section := VBoxContainer.new()
	section.set_meta("ui_village_stage", int(stage.get("level", 0)))
	parent.add_child(section)
	C.heading(ui, "村庄阶段 %s · %s" % [stage.get("level", 0), stage.get("name", "")], section)
	var next := str(stage.get("next", ""))
	if not next.is_empty():
		C.caption(ui, "下一阶段 · " + next, section)
		for item: String in stage.get("missing", []): C.caption(ui, "待完成 · " + item, section)

static func _quick_build(ui, body: VBoxContainer, definitions: Array, stage: Dictionary) -> void:
	var presets: Dictionary = {}
	for definition: Dictionary in definitions:
		var key := Identity.family(definition)
		if key not in ["home", "warehouse", "workshop", "canteen", "guard"]: continue
		var locked := not _locked_stage(definition, stage).is_empty()
		if locked and key != "guard": continue
		var previous: Dictionary = presets.get(key, {})
		var previous_locked := not previous.is_empty() and not _locked_stage(previous, stage).is_empty()
		if previous.is_empty() or (previous_locked and not locked) or (previous_locked == locked and float(definition.get("build_seconds", INF)) < float(previous.get("build_seconds", INF))):
			presets[key] = definition
	var wall := _wall_definition(ui)
	if presets.is_empty() and wall.is_empty(): return
	C.caption(ui, "常用建筑 · 点击选址", body)
	var actions := HFlowContainer.new()
	body.add_child(actions)
	for key: String in ["home", "warehouse", "workshop", "canteen", "guard"]:
		if not presets.has(key): continue
		var definition: Dictionary = presets[key]
		var id := str(definition.id)
		var reason := _locked_stage(definition, stage)
		if reason.is_empty(): reason = ui.module_preview_reason()
		var label := "警戒岗" if key == "guard" and not _locked_stage(definition, stage).is_empty() else Identity.name(definition)
		var button: Button = ui.button(label, func(): ui.begin_module_preview(id), "factory:preset:" + id, reason)
		actions.add_child(button)
		if not button.disabled: button.tooltip_text = Identity.purpose(definition) + " · " + footprint_text(definition)
		elif key == "guard": C.caption(ui, label + " · " + reason, body)
	if not wall.is_empty():
		var reason := P.definition_reason(wall)
		if reason.is_empty() and not ui.carry.is_empty(): reason = "请先将手中物品归位"
		if reason.is_empty() and (not is_instance_valid(ui.input_router) or not ui.input_router.has_method("assign_slot")): reason = "场景选址尚未就绪"
		var wall_button: Button = ui.button("实墙 · 整段", func(): _begin_wall_preview(ui), "factory:wall:preview", reason)
		actions.add_child(wall_button)
		if not wall_button.disabled: wall_button.tooltip_text = "实墙 · 长 %s 米 · 左键固定 · Enter 确认" % P.number(wall.get("size", {}).get("x", 0))

static func _wall_definition(ui) -> Dictionary:
	var wall := P.find(ui.snapshot.get("catalog", {}).get("buildings", []), "wall")
	if wall.is_empty() and is_instance_valid(ui.runtime) and ui.runtime.has_method("ui_page_snapshot"):
		# The compact catalogue may omit structural pieces. Use the same public
		# catalogue as the normal construction page when available.
		var build: Dictionary = ui.runtime.ui_page_snapshot("build")
		wall = P.find(build.get("catalog", {}).get("buildings", []), "wall")
	return wall if wall.get("kind") == "wall" and not wall.get("solids", []).is_empty() and wall.get("enabled", true) else {}

static func _begin_wall_preview(ui) -> void:
	var hand: Dictionary = ui.snapshot.get("hand", {})
	var receipt: Dictionary = ui.router_call("assign_slot", [int(hand.get("selected", 0)), {"kind":"recipe", "definition_id":"wall"}])
	if receipt.get("ok", false): receipt = ui.router_call("set_mode", ["tool"])
	if receipt.get("ok", false): ui.close_panels()
	else: ui.notify(P.feedback_text(receipt), true)

static func _locked_stage(definition: Dictionary, stage: Dictionary) -> String:
	var required := int(definition.get("village_stage_required", 0))
	if required <= 1: return ""
	if stage.is_empty(): return "村庄阶段尚未就绪"
	var level := int(stage.get("level", 0))
	if level >= required: return ""
	var next := str(stage.get("next", ""))
	return "需进入「%s」" % next if required == level + 1 and not next.is_empty() else "需达到村庄阶段 %s" % required

static func _card(ui, parent: VBoxContainer, definition: Dictionary, stage: Dictionary = {}, companion:bool=false) -> void:
	var id := str(definition.get("id", ""))
	var value := architecture(definition)
	var card := C.card(parent)
	card.set_meta("ui_catalog_definition", id)
	card.set_meta("ui_catalog_geometry", str(definition.get("geometry_version", "")))
	var picture := Images.module_texture(definition)
	var title := str(definition.get("source_name", definition.get("name", ""))) if definition.has("village_tier") else Identity.name(definition)
	var header := C.image_row(ui, card, picture, title, str(definition.get("village_role", Identity.purpose(definition))), roundi(64 * ui.text_scale))
	header.tooltip_text = str(definition.get("source_name",definition.get("name", ""))) + "\n" + id + "\n" + str(definition.get("geometry_version", ""))
	if not value.is_empty():
		var level := str(TIERS.get(tier(definition), ""))
		if not level.is_empty(): C.caption(ui, level, header)
		if not capacity_text(definition).is_empty():
			ui.paragraph(capacity_text(definition), card)
	elif definition.has("village_tier"):
		var level := str(TIERS.get(tier(definition), ""))
		if not level.is_empty(): C.caption(ui, level, header)
		var capacity := capacity_text(definition)
		if not capacity.is_empty(): C.caption(ui, capacity, header)
	C.caption(ui, footprint_text(definition), card)
	ui.item_row(definition.get("build_cost", {}), "建造所需", card)
	var locked := _locked_stage(definition, stage)
	if not locked.is_empty(): C.reason(ui, card, locked)
	var actions := HFlowContainer.new(); card.add_child(actions)
	if locked.is_empty():
		C.primary(ui.add_button("选址建蓝图" if companion else "开始选址", func(): ui.begin_module_preview(id), "factory:preview:" + id, ui.module_preview_reason(), actions))
	else:
		actions.add_child(ui.button("未解锁", func(): pass, "factory:preview:" + id, locked))
	ui.add_button("取消收藏" if ui.factory_favorites.has(id) else "收藏", func():
		if ui.factory_favorites.has(id): ui.factory_favorites.erase(id)
		else: ui.factory_favorites[id] = true
		ui.queue_refresh(), "factory:favorite:" + id, "", actions)
	Handbook.shortcut(ui, actions, "module:" + id, "catalog:" + id, "手册")
	var details := C.fold(ui, card, "catalog:" + id, "尺寸与生产接口")
	if details == null: return
	var variant := str(value.get("variant_label", ""))
	if not variant.is_empty(): C.caption(ui,"款式 · " + variant,details)
	if not str(value.get("description", "")).is_empty(): C.caption(ui,str(value.description),details)
	if not value.is_empty() and not capacity_text(definition).is_empty(): C.caption(ui,"设计人数，不代表实际入住或床位。",details)
	C.caption(ui, "工期 %s 秒" % P.number(definition.get("build_seconds")), details)
	var diagram := Footprint.new(); diagram.configure(definition); details.add_child(diagram)
	C.caption(ui, "定义足迹示意；场景合法性由真实预检确认。", details)
	for port: Dictionary in F.dictionaries(definition.get("ports", [])): C.caption(ui, str(PORTS.get(str(port.get("purpose", "")), "服务")) + " · " + str(port.get("direction", "")), details)
