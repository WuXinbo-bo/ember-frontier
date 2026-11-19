extends RefCounted
## Read-only display adaptation. IDs/counts always come from the runtime snapshot.

const Content = preload("res://scripts/runtime/content_definitions.gd")
const KNOWLEDGE_NAMES := {"basic_woodwork":"基础木工", "basic_tool_repair":"基础工具维修"}

static func records(value: Variant) -> Array:
	if value is Array:
		return value.filter(func(row): return row is Dictionary)
	var result: Array = []
	if value is Dictionary:
		for key in value:
			if value[key] is Dictionary:
				var row: Dictionary = value[key].duplicate(true)
				if not row.has("id"):
					row["id"] = str(key)
				result.append(row)
	return result

static func find(rows: Variant, id: String) -> Dictionary:
	for row in records(rows):
		if str(row.get("id", "")) == id:
			return row.duplicate(true)
	return {}

static func player(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("player") is Dictionary and not snapshot.player.is_empty():
		return snapshot.player.duplicate(true)
	return find(snapshot.get("actors", []), str(snapshot.get("player_id", "player")))

static func player_stock(snapshot: Dictionary) -> Dictionary:
	var actor := player(snapshot)
	var explicit_id := str(actor.get("stock_id", actor.get("pack_id", snapshot.get("player_stock_id", ""))))
	if not explicit_id.is_empty():
		return find(snapshot.get("stocks", []), explicit_id)
	var owned: Array = []
	for stock in records(snapshot.get("stocks", [])):
		if stock.get("owner") == actor.get("id"):
			owned.append(stock)
	# Never substitute the first container when the ownership projection is ambiguous.
	return owned[0].duplicate(true) if owned.size() == 1 else {}

static func stock(snapshot: Dictionary, id: String) -> Dictionary:
	return find(snapshot.get("stocks", []), id)

static func normalize_reference(value: Dictionary) -> Dictionary:
	var kind := str(value.get("kind", ""))
	var field: String = {"item":"item_id", "tool":"tool_id", "recipe":"definition_id"}.get(kind, "")
	if field.is_empty(): return {}
	var id := str(value.get(field, value.get("id", "")))
	return {"kind":kind, field:id} if not id.is_empty() else {}

static func reference_key(reference: Dictionary) -> String:
	var normalized := normalize_reference(reference)
	var kind := str(normalized.get("kind", ""))
	var field: String = {"item":"item_id", "tool":"tool_id", "recipe":"definition_id"}.get(kind, "")
	if field.is_empty():
		return ""
	return kind + ":" + str(normalized[field])

static func item_name(id: String) -> String:
	return str(Content.item_definition(id).get("name", KNOWLEDGE_NAMES.get(id, id)))

static func item_unit(id: String) -> String:
	# Unknown legacy IDs retain their identity/quantity, not a guessed unit.
	return " m³" if Content.item_definition(id).get("unit") == "m3" else ""

static func item_text(id: String, quantity: Variant) -> String:
	return item_name(id) + " × " + number(quantity) + item_unit(id)

static func definition_reason(definition: Dictionary, recipe: bool = false) -> String:
	# Reuse A's schema check for this displayed formal definition only. Legacy
	# inventory compatibility must never make an invalid catalog selectable.
	var catalog := {"production_recipes":[definition]} if recipe else {"structure_definitions":{str(definition.get("id", "display")):definition}}
	var receipt := Content.validate_catalog(catalog)
	return "" if receipt.get("ok", false) else str(receipt.get("reason", "目录物资定义无效"))

static func reason_text(value: Variant, target: Dictionary = {}) -> String:
	# Explain only confirmed bare codes. Specific authority reasons take precedence.
	var text := str(value) if value != null else "当前不可执行"
	match text.strip_edges():
		"candidate_unavailable": return "原安排的岗位当前不可执行"
		"no_supported_route": return "当前没有经实际空间检查确认的可达通路"
		"held": return "已暂停，继续作业后恢复"
		"no_stamina": return "体力不足，先休息恢复"
		"tool_broken": return "工具已损坏，请维修或更换可用工具"
		"operator_not_at_port": return "距离不足，请走近建筑后继续"
		"operator_not_at_water": return "距离不足，请走近储水设施后继续"
		"stamina_or_tool": return "体力或工具状态不足，施工已暂停；请查看体力与工具耐久"
		"missing_input": return "施工材料不足，请补齐显示的材料"
		"missing_operator": return "施工人员尚未到位"
		"paused": return "施工已暂停，继续后恢复"
		"water_empty": return "有限储水已经耗尽"
		"water_busy": return "此装置正被另一项真实作业占用"
		"region_paused": return "关联地区暂停，作业尚未推进"
		"restoration_required": return "这座设施需要修复，请补齐所需材料"
		"MISSING_TOOL":
			if target.get("kind") == "terrain" or target.get("primary") == "terrain":
				var edit: Dictionary = target.get("edit", {}) if target.get("edit") is Dictionary else {}
				return "请在快捷栏选中可用的铲，再整平地面" if edit.get("operation") == "level" else "请在快捷栏选中适合该地面的铲／镐"
			return "缺少适用工具，请检查手持工具是否可用"
		"UNREACHABLE":
			return "移动通路不可达，请检查通路与落脚点" if target.get("purpose") == "body_move" else "当前够不到目标，请移近或绕到同侧可达处"
		"OUT_OF_REACH": return "目标超出操作距离，请移近后再试"
		"OCCLUDED": return "目标表面被遮挡，请绕到可见的一侧"
		"BLOCKED", "BODY_BLOCKED": return "身体通路被挡住，请检查墙、门或台阶"
		"STEP_TOO_HIGH": return "台阶或高差超过当前可通行范围，请另找通路"
		"UNSUPPORTED", "NO_SUPPORT": return "落脚点或放置位置缺少支撑"
		"NO_VALID_USE_POINT": return "没有可用的使用位置，请检查通路与落脚空间"
		"NOT_READY": return "所需场景尚未就绪，请等待准备完成"
		"FORBIDDEN": return "当前没有操作权限，请检查归属与同意状态"
		"RESERVED": return "所需物品或使用位置已被占用，请等待或取消原作业"
		"WRONG_TOOL": return "当前工具不适用，请在快捷栏选中所需工具"
		"INSUFFICIENT_ITEM": return "可用材料不足，请补充材料或检查其他作业的预留"
		"STALE_INPUT": return "现场状态已改变，请重新指向目标后再操作"
		"TARGET_MISSING": return "原目标已不存在，请重新选择目标"
		"BUSY": return "先结束或取消当前行动，再重试当前操作"
		"UNKNOWN_CELL": return "此处地形尚未加载，暂时不能操作"
		"FOUNDATION_SUPPORT", "ENTITY_SUPPORT": return "此处承托着建筑或物件，不能直接挖除"
		"TOOL_RESERVED": return "工具正在另一项作业中使用，请先完成或取消该作业"
		"NO_MATERIAL": return "随身材料不足，请补充对应材料"
		"MATERIAL_RESERVED": return "材料已被其他作业预留，请先完成或取消该作业"
		"EXHAUSTED": return "体力不足，请先休息恢复"
		"BUFFER_FULL", "BUFFER_OVERCOMMITTED": return "目的缓存容量不足或已被产出预占，请先清运或调整运输"
		"BUFFER_FILTER": return "此缓存不接收该物料，请选择匹配的供料口"
		"MODULE_MATERIALS": return "建设材料不足或已被其他作业预留"
		"MODULE_TOOL_REQUIRED": return "随身缺少可用锤子；请携带锤子并检查耐久和占用状态"
		"MODULE_NOT_RESTORABLE": return "这座建筑当前不需要或不支持修复，请查看建筑现状"
		"MODULE_PROJECT_MISSING": return "原施工项目已不存在，请重新查看建筑"
		"MODULE_LIVE_ACTOR_OCCUPIED": return "施工范围有人，请先让人离开"
		"MODULE_SOURCE_REQUIRED": return "需要真实材料来源和可用手锤"
		"MODULE_DISCOVER_REQUIRES_CONTACT": return "距离不足，靠近建筑即可操作"
		"WATER_DISCOVER_REQUIRES_CONTACT": return "距离不足，靠近储水设施即可操作"
		"MODULE_PERMISSION", "MODULE_SOURCE_PERMISSION": return "无权使用这处设施或材料来源，请确认归属与使用许可"
		"MODULE_NOT_OPERATIONAL", "BUFFER_NOT_OPERATIONAL": return "设施尚不能使用，请先完成施工或处理损坏"
		"MODULE_PROJECT_ACTIVE": return "设施已有现场作业，请先完成或取消原作业"
		"MODULE_RESTORATION_REQUIRED": return "这座设施尚未修复，请查看缺口并备齐材料"
		"MODULE_MACHINE_NOT_STOPPED": return "机器尚未停止，请先停止后续生产并处理当前在制"
		"MODULE_MATERIALS_CHANGED": return "材料或预留已变化，请重新检查现场材料"
		"ACTOR_BUSY": return "此人正在执行其他行动，请先完成或取消原行动"
		"ACTOR_UNAVAILABLE": return "此人当前无法行动，请先查看其身体与行动状态"
		"LOGISTICS_PERMISSION": return "无权执行这项运输，请检查两端库存和承运者的使用许可"
		"LOGISTICS_WORKER_UNAVAILABLE": return "承运者当前不能取送，请查看其行动与身体状态"
		"REGION_PAUSED": return "目标地区尚未恢复运行，请待该地区就绪后重试"
		"MODULE_CONTENT_NOT_EMPTY": return "缓存、工具或书册尚未清空，请先实际运走"
		"MODULE_BATCH_PENDING": return "仍有活动在制，先完成、合法停料或明确废弃"
		"CARGO_HANDOFF_REQUIRED": return "此人仍持有在途货物，须先交付或完成安全交接"
		"CANDIDATE_UNAVAILABLE": return "岗位候选已失效，请重新选择"
		"INVALID_LOGISTICS_ENDPOINT": return "运输两端须为不同、已搜索且有权使用的现场库存"
		"STOCK_POLICY_PERMISSION": return "无权修改此缓存策略，请确认设施归属与当前使用许可"
		"STOCK_POLICY_NOT_SUPPORTED": return "此旧版设施不支持分类与保留量策略；原库存仍保持"
		"STOCK_POLICY_FILTER": return "当前仓储分类不接收此物资，请调整接收范围或选择其他缓存"
		"INVALID_STOCK_FILTER": return "接收分类须为此缓存允许的物资，请重新选择"
		"INVALID_STOCK_THRESHOLD": return "保留量和库存目标须符合物资单位，且不能超过此缓存容量"
		"MODULE_RECIPE_PERMISSION", "RECIPE_STOCK_PERMISSION": return "无权修改此订单或使用所选库存，请检查设施与两端库存许可"
		"MODULE_RECIPE_NOT_SUPPORTED": return "此旧版设施不支持配方订单；原单批制作入口保持"
		"MODULE_RECIPE_NOT_ALLOWED": return "此设施不能执行所选配方，请重新查看它提供的配方"
		"RECIPE_BATCH_IN_PROGRESS": return "此需求仍有在制批次，请先完成或处理原批次后再修改"
		"RECIPE_ORDER_MISSING": return "原配方订单已不存在，请刷新后重新选择"
		"RECIPE_ORDER_LIMIT": return "此设施已达到16项配方需求上限，请修改既有需求"
		"INVALID_RECIPE_ORDER": return "批数须为1至100000的整数，请检查执行方式与批数"
		"INVALID_RECIPE_TARGET": return "库存目标须选择此配方的实际产出，数量为正整数"
	# Translate only a known ID at the explicit reason suffix, never change rules.
	for separator in ["：", ":"]:
		var offset := text.rfind(separator)
		if offset < 0: continue
		var id := text.substr(offset + 1).strip_edges()
		if not Content.item_definition(id).is_empty() or KNOWLEDGE_NAMES.has(id): return text.substr(0, offset + 1) + item_name(id)
	# Future bare codes remain in receipt diagnostics, never in player copy. Do
	# not guess a requirement or promise that a rejected command changed nothing.
	if _bare_reason_code(text): return "当前操作条件尚未满足，请重新查看目标状态后再试"
	return text

static func activity_text(actor: Dictionary) -> String:
	# Activity is owner-published copy or a reason code, never a UI decision.
	# Preserve specific prose and translate only confirmed codes. In particular,
	# an absent work candidate does not establish a path/material/consent cause.
	var raw := str(actor.get("activity", "")).strip_edges()
	if raw.is_empty(): return "等待安排"
	if _bare_reason_code(raw) and reason_text(raw) == "当前操作条件尚未满足，请重新查看目标状态后再试":
		return "当前行动条件尚未满足"
	return reason_text(raw)

static func _bare_reason_code(value: String) -> bool:
	if value.is_empty() or not value.contains("_"): return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		if not (code >= 65 and code <= 90 or code >= 97 and code <= 122 or code >= 48 and code <= 57 or code == 95): return false
	return true

static func feedback_text(feedback: Dictionary, target: Dictionary = {}, fallback: String = "当前不可执行") -> String:
	var reason: Variant = feedback.get("reason")
	if reason is String and not reason.strip_edges().is_empty(): return reason_text(reason, target)
	var code := str(feedback.get("code", ""))
	return reason_text(code, target) if not code.is_empty() else fallback

static func feedback_diagnostic(feedback: Dictionary) -> String:
	var code := str(feedback.get("code", ""))
	var reason: Variant = feedback.get("reason")
	var raw: String = reason if reason is String else ""
	return ("code: " + code + "\n" if not code.is_empty() else "") + ("reason: " + raw if not raw.is_empty() else "")

static func player_movement(snapshot: Dictionary) -> Dictionary:
	var value: Variant = snapshot.get("movement")
	if not value is Dictionary: return {}
	var id := str(player(snapshot).get("id", "player"))
	if value.get(id) is Dictionary: return value[id].duplicate(true)
	# Accept an explicit player-only projection; never substitute another actor.
	return value.duplicate(true) if value.get("moving") is bool else {}

static func movement_text(snapshot: Dictionary) -> String:
	var movement := player_movement(snapshot)
	var hand: Dictionary = snapshot.get("hand", {}) if snapshot.get("hand") is Dictionary else {}
	var bindings: Dictionary = hand.get("bindings", {}) if hand.get("bindings") is Dictionary else {}
	var text := "按住 " + binding_label(bindings.run) + " 跑步" if bindings.has("run") else ""
	if movement.is_empty(): return text
	if movement.get("moving", false):
		text = ("跑步中" if movement.get("mode") == "run" else "步行中") + (" · " + text if not text.is_empty() else "")
		var speed: Variant = movement.get("speed")
		if (speed is int or speed is float) and is_finite(float(speed)): text += " · " + number(speed) + " m/s"
	var reason: Variant = movement.get("reason")
	if reason is String and not reason.strip_edges().is_empty():
		var prefix := "跑步暂不可用" if movement.get("can_run") == false else "移动状态"
		text += ("\n" if not text.is_empty() else "") + prefix + " · " + reason_text(reason)
	return text

static func playtest_profile(snapshot: Dictionary) -> Dictionary:
	var value: Variant = snapshot.get("playtest")
	return value.duplicate(true) if value is Dictionary and not str(value.get("id", "")).is_empty() else {}

static func playtest_text(snapshot: Dictionary) -> String:
	var profile := playtest_profile(snapshot)
	if profile.is_empty(): return ""
	var text := str(profile.get("label", "试玩配置"))
	var seed: Variant = profile.get("seed")
	if seed is int or seed is float: text += " · 种子 " + str(seed)
	return text

static func playtest_supplies(snapshot: Dictionary) -> String:
	var profile := playtest_profile(snapshot)
	if profile.is_empty(): return ""
	var catalog: Dictionary = snapshot.get("catalog", {}) if snapshot.get("catalog") is Dictionary else {}
	var definitions: Dictionary = catalog.get("tool_definitions", {}) if catalog.get("tool_definitions") is Dictionary else {}
	var tools: PackedStringArray = []
	for id: Variant in profile.get("tools", []):
		var definition: Dictionary = definitions.get(str(id), {})
		tools.append(str(definition.get("name", id)))
	var items: PackedStringArray = []
	var initial: Dictionary = profile.get("items", {}) if profile.get("items") is Dictionary else {}
	for id: String in initial:
		items.append(item_text(id, initial[id]))
	return ("新图初始配发（并非当前余量）\n工具 · " + "、".join(tools) + "\n有限物资 · " + "、".join(items))

static func entries(stock: Dictionary, snapshot: Dictionary) -> Array:
	if stock.is_empty() or not stock.get("searched", false) or not stock.get("items") is Dictionary:
		return []
	var result: Array = []
	var reserved: Dictionary = stock.get("reserved", {}) if stock.get("reserved") is Dictionary else {}
	var held_items: Dictionary = reserved.get("items", reserved) if reserved.get("items", reserved) is Dictionary else {}
	for id in stock.items:
		var count: Variant = stock.items[id]
		if not (count is int or count is float) or not is_finite(float(count)) or count <= 0:
			continue
		var held: Variant = held_items.get(id, 0)
		var free := maxf(0.0, float(count) - (float(held) if held is int or held is float else 0.0))
		var definition := Content.item_definition(str(id))
		result.append({"key":"item:" + str(id), "reference":{"kind":"item", "item_id":str(id)}, "name":item_name(str(id)), "quantity":float(count), "available":minf(float(count), free), "step":Content.quantity_step(str(id), true), "unit":str(definition.get("unit", "")), "stackable":definition.get("stackable", true), "legacy":definition.is_empty(), "durability":null})
	var seen: Dictionary = {}
	var tool_ids: Array = stock.get("tool_ids", []).duplicate()
	for tool in records(snapshot.get("tools", [])):
		if str(tool.get("holder_id", tool.get("holderId", ""))) == str(stock.get("id", "")):
			tool_ids.append(str(tool.get("id", "")))
	for id in tool_ids:
		if seen.has(str(id)):
			continue
		seen[str(id)] = true
		var tool := find(snapshot.get("tools", []), str(id))
		if tool.is_empty() or str(tool.get("holder_id", tool.get("holderId", ""))) != str(stock.get("id", "")):
			continue
		var held_tools: Variant = reserved.get("tool_ids", [])
		var locked: bool = bool(tool.get("reserved", false)) or (held_tools is Array and str(id) in held_tools)
		var definition_id := str(tool.get("definition_id", tool.get("definitionId", tool.get("kind", ""))))
		var catalog: Dictionary = snapshot.get("catalog", {}) if snapshot.get("catalog") is Dictionary else {}
		var definition: Dictionary = catalog.get("tool_definitions", {}).get(definition_id, {})
		result.append({"key":"tool:" + str(id), "reference":{"kind":"tool", "tool_id":str(id)}, "definition_id":definition_id, "name":str(tool.get("name", definition.get("name", "未识别工具" if definition_id.is_empty() else definition_id))), "quantity":1.0, "available":0.0 if locked else 1.0, "step":1.0, "durability":tool.get("durability") if snapshot.get("expedition", {}).is_empty() else null, "max_durability":definition.get("maxDurability", definition.get("max_durability")) if snapshot.get("expedition", {}).is_empty() else null})
	return result

static func hand_entry(stock: Dictionary, snapshot: Dictionary, reference: Dictionary) -> Dictionary:
	if reference.get("kind") != "recipe": return entry(stock, snapshot, reference)
	var catalog: Dictionary = snapshot.get("catalog", {})
	var id := str(reference.get("definition_id", ""))
	var definition := find(catalog.get("buildings", catalog.get("structure_definitions", {})), id)
	# A recipe binding is a construction intent, never a manufactured stock item.
	return {"reference":reference.duplicate(true), "definition_id":id, "name":str(definition.get("name", id)), "quantity":0, "available":0} if not id.is_empty() else {}

static func entry(stock: Dictionary, snapshot: Dictionary, reference: Dictionary) -> Dictionary:
	var key := reference_key(reference)
	if key.is_empty(): return {}
	for value in entries(stock, snapshot):
		if value.key == key:
			return value
	return {}

static func number(value: Variant) -> String:
	if not (value is int or value is float) or not is_finite(float(value)):
		return "—"
	return str(snappedf(float(value), 0.001)).trim_suffix(".0")

static func stat_number(value: Variant) -> String:
	# Needs are a glanceable status, not material units. Keep number() precision
	# for m³, reservations and exact quantities elsewhere.
	return str(roundi(float(value))) if (value is int or value is float) and is_finite(float(value)) else "—"

static func action_feedback(feedback: Dictionary, kind: String) -> String:
	if feedback.get("code") == "BUFFER_FILTER":
		var item := str(feedback.get("reason", ""))
		# New owner receipts include the allowed materials; older frozen receipts
		# carry only the exact item ID. Preserve both without exposing a raw ID.
		var explanation := item if item.begins_with("此容器不接收") else "这个容器不接收" + (item_name(item) if not Content.item_definition(item).is_empty() else "这种物料")
		return explanation + ("。物品仍留在原库存。" if kind in ["deposit", "take"] else "。本次操作未提交。") + "可查看当前容器的接收范围。"
	if feedback.get("code") == "BUFFER_FULL": return "这个容器的可用容量不足。" + ("物品仍留在原库存。" if kind in ["deposit", "take"] else "本次操作未提交。") + "请先清出空间或另选容器。"
	if feedback.get("code") == "BUFFER_NOT_OPERATIONAL": return "这个容器当前不能接收物料。" + ("物品仍留在原库存。" if kind in ["deposit", "take"] else "本次操作未提交。") + "请先完成建设或恢复设施。"
	if feedback.get("code") == "NO_ITEM" and kind in ["eat", "drink", "medicine"]:
		return str({"eat":"随身缺少可用食物，请取到食物后再进食", "drink":"随身缺少可用饮水，请取到饮水后再喝", "medicine":"随身缺少可用药品，请取到药品后再处理伤势"}[kind])
	return feedback_text(feedback)

static func progress(value: Variant) -> Dictionary:
	# A scene target supplies a normalized scalar; B orders supply elapsed/seconds.
	# This only projects authority values and never advances a UI-side work clock.
	if value is int or value is float:
		return {"maximum":1.0, "value":clampf(float(value), 0, 1)} if is_finite(float(value)) else {}
	if not value is Dictionary: return {}
	var duration: Variant = value.get("duration", value.get("seconds", 0))
	var elapsed: Variant = value.get("elapsed", 0)
	if not (duration is int or duration is float) or not (elapsed is int or elapsed is float): return {}
	if not is_finite(float(duration)) or not is_finite(float(elapsed)) or float(duration) <= 0: return {}
	return {"maximum":float(duration), "value":clampf(float(elapsed), 0, float(duration))}

static func binding_label(value: Variant) -> String:
	if value is Dictionary: return str(value.get("label", binding_label(value.get("keycode", 0))))
	if value is int or value is float:
		var event := InputEventKey.new()
		var packed := int(value)
		event.physical_keycode = packed & KEY_CODE_MASK
		event.shift_pressed = bool(packed & KEY_MASK_SHIFT)
		event.ctrl_pressed = bool(packed & KEY_MASK_CTRL)
		event.alt_pressed = bool(packed & KEY_MASK_ALT)
		event.meta_pressed = bool(packed & KEY_MASK_META)
		return event.as_text_physical_keycode()
	return str(value).replace("Meta", "⌘").replace("Ctrl", "⌃").replace("Alt", "⌥").replace("Shift", "⇧").replace("Key", "").replace("Digit", "").replace("Escape", "Esc").replace("+", "＋")

static func binding_code(value: Variant, fallback: int = 0) -> int:
	if value is Dictionary: return int(value.get("keycode", fallback))
	return int(value) if value is int or value is float else fallback

static func physical_key(event: InputEventKey) -> int:
	# A's 21:38 contract: physical Godot key plus modifiers, never unicode.
	if event.physical_keycode == 0: return 0
	return event.get_physical_keycode_with_modifiers()

static func encode_key(event: InputEventKey) -> String:
	var key := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var code := ""
	if key >= KEY_A and key <= KEY_Z:
		code = "Key" + char(key)
	elif key >= KEY_0 and key <= KEY_9:
		code = "Digit" + char(key)
	else:
		code = {KEY_ESCAPE:"Escape", KEY_TAB:"Tab", KEY_SPACE:"Space", KEY_UP:"ArrowUp", KEY_DOWN:"ArrowDown", KEY_LEFT:"ArrowLeft", KEY_RIGHT:"ArrowRight", KEY_F1:"F1", KEY_F2:"F2", KEY_F3:"F3", KEY_F4:"F4"}.get(key, "")
	if code.is_empty():
		return ""
	var parts: PackedStringArray = []
	if event.ctrl_pressed: parts.append("Ctrl")
	if event.meta_pressed: parts.append("Meta")
	if event.alt_pressed: parts.append("Alt")
	if event.shift_pressed: parts.append("Shift")
	parts.append(code)
	return "+".join(parts)
