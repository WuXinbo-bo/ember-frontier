extends RefCounted
## Detached public display DTOs only. No extension reads, stock or clock ownership.
const P = preload("res://scripts/ui/ui_projection.gd")
const Identity = preload("res://scripts/ui/building_identity.gd")
const SCHEMA := "afterglow-factory-display-v1"
const TITLES := {"factory":"村落设施", "factory_catalog":"建造模块", "factory_module":"设施与生产", "factory_inventory":"现场取放", "factory_stock":"村庄库存", "factory_production":"生产与批次", "factory_logistics":"物流与瓶颈", "factory_people":"人物与岗位", "factory_alerts":"地图与告警", "factory_handbook":"生存手册", "factory_confirm":"确认操作后果"}
const STATE_NAMES := {"needs_restoration":"待修复", "restoration_required":"结构与部件待修复，请补齐所需材料", "ruined":"残骸", "invalid":"不可用", "damaged":"受损", "paused":"已暂停", "maintenance":"维护中", "region_paused":"区域暂停", "unconfigured":"待配置", "output_fault":"本批输出受阻", "output_full":"下批输出空间不足", "missing_input":"缺少原料", "missing_energy":"缺少能源", "missing_operator":"等待值守", "running":"运行中", "target_met":"目标已达成", "idle":"空闲", "active":"进行中", "blocked":"受阻", "refund_pending":"等待原料退回空间", "completed":"已完成", "cancelled":"已取消", "queued":"待取货", "collecting":"取货中", "delivering":"送货中", "cargo_held":"货物由原承运者保管"}

static func read(authority: Object, actor_id: String = "player", details: bool = true) -> Dictionary:
	if not is_instance_valid(authority) or not authority.has_method("factory_snapshot"): return {}
	# All regular surfaces need current facts, not all possible workforce jobs.
	# The complete public factory API remains the compatibility fallback.
	var method := "factory_ui_snapshot" if authority.has_method("factory_ui_snapshot") else "factory_snapshot"
	if not details and authority.has_method("factory_hud_snapshot"):method="factory_hud_snapshot"
	var value: Variant = authority.call(method, actor_id)
	if not value is Dictionary or value.get("schema") != SCHEMA or value.get("version") != 1: return {}
	return value # The facade already returns a detached display DTO.

static func read_workforce(authority: Object, actor_id: String) -> Dictionary:
	if not is_instance_valid(authority): return {}
	var value: Variant
	if authority.has_method("workforce_snapshot"):
		value = authority.call("workforce_snapshot",actor_id)
	elif authority.has_method("factory_snapshot"):
		var full: Variant=authority.call("factory_snapshot",actor_id)
		value=full.get("workforce",{}) if full is Dictionary else {}
	if not value is Dictionary or not value.get("available") is bool or not value.get("people") is Array: return {}
	return value

static func read_page(authority:Object,actor_id:String,page:String,subject:String)->Dictionary:
	if not is_instance_valid(authority) or not authority.has_method("factory_page_snapshot"):return read(authority,actor_id,not page.is_empty())
	if page.is_empty():return read(authority,actor_id,false)
	var value:Variant=authority.call("factory_page_snapshot",actor_id,page,subject)
	return value if value is Dictionary and value.get("schema")==SCHEMA and value.get("version")==1 else {}

static func read_person(authority:Object,actor_id:String)->Dictionary:
	if not is_instance_valid(authority):return {}
	if authority.has_method("workforce_person_snapshot"):
		var value:Variant=authority.call("workforce_person_snapshot",actor_id)
		return value if value is Dictionary and value.get("actor_id")==actor_id else {}
	var workforce:Dictionary=read_workforce(authority,actor_id)
	if not workforce.get("available",false):return {}
	return find(dictionaries(workforce.get("people",[])),actor_id,"actor_id")

static func enabled(data: Dictionary) -> bool:
	return data.get("available", false) and section(data, "modules").get("available", false)

static func section(data: Dictionary, key: String) -> Dictionary:
	return data[key] if data.get(key) is Dictionary else {}

static func rows(data: Dictionary, domain: String, key: String) -> Array:
	var source := section(data, domain)
	if not source.get("available", false): return []
	var result := dictionaries(source.get(key, []))
	if domain == "modules":
		var definitions: Dictionary = {}
		if key == "instances":
			for value: Variant in source.get("definitions", []):
				if value is Dictionary: definitions[str(value.get("id", ""))] = value
		for row: Dictionary in result:
			if key == "definitions": _display_definition(row)
			elif key == "instances": _display_instance(data, row, definitions)
	return result

static func dictionaries(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for row in value:
			if row is Dictionary: result.append(row.duplicate(true))
	return result

static func find(rows_: Array, id: String, field: String = "id") -> Dictionary:
	for row: Dictionary in rows_:
		if str(row.get(field, "")) == id: return row.duplicate(true)
	return {}

static func instance(data: Dictionary, id: String) -> Dictionary:
	var row := _module_row(data,"instances",id)
	if not row.is_empty(): _display_instance(data,row)
	return row

static func definition(data: Dictionary, id: String) -> Dictionary:
	var row := _module_row(data,"definitions",id)
	if not row.is_empty(): _display_definition(row)
	return row

static func _display_definition(row: Dictionary) -> void:
	row["source_name"] = row.get("source_name", row.get("name", ""))
	row["name"] = Identity.name(row)
	row["use_hint"] = Identity.purpose(row)

static func _display_instance(data: Dictionary, row: Dictionary, indexed: Dictionary = {}) -> void:
	var id := str(row.get("definition_id", ""))
	var definition_row: Dictionary = indexed.get(id,{})
	# Read only scalar identity hints; never clone a full geometry/recipe DTO
	# merely to label each instance in a list.
	if definition_row.is_empty():
		var values: Variant = section(data,"modules").get("definitions", [])
		if values is Array:
			for value: Variant in values:
				if value is Dictionary and str(value.get("id", "")) == id:
					definition_row = value
					break
	if definition_row.is_empty(): return
	row["source_name"] = row.get("source_name",row.get("name", ""))
	row["name"] = Identity.instance_name(definition_row,row)
	row["use_hint"] = Identity.purpose(definition_row)

static func _module_row(data:Dictionary,key:String,id:String)->Dictionary:
	var source:Dictionary=section(data,"modules")
	if not source.get("available",false):return {}
	var values:Variant=source.get(key,[])
	if not values is Array:return {}
	# Only the selected detached row escapes; scanning must not copy every
	# building's nested ports, recipes and architecture on each lookup.
	for row:Variant in values:
		if row is Dictionary and str(row.get("id",""))==id:return row.duplicate(true)
	return {}

static func build_definitions(data: Dictionary) -> Array:
	# Selection belongs to the same modules owner. Keep the full definitions
	# untouched for existing facilities, handbook entries and historical saves.
	var source := section(data, "modules")
	var definitions := rows(data, "modules", "definitions")
	if not source.has("build_definition_ids"): return definitions
	var ids: Variant = source.build_definition_ids
	if not ids is Array: return []
	var by_id: Dictionary = {}
	for row: Dictionary in definitions: by_id[str(row.get("id", ""))] = row
	var result: Array = []
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not id is String or seen.has(id) or not by_id.has(id): continue
		seen[id] = true
		result.append(by_id[id])
	return result

static func state_text(row: Dictionary) -> String:
	var code := str(row.get("state_code", row.get("status", "")))
	if code == "needs_restoration": return STATE_NAMES.needs_restoration
	return str(row.get("state_label", STATE_NAMES.get(code, code if not code.is_empty() else "状态未提供")))

static func stock_visible(data: Dictionary, snapshot: Dictionary, stock_id: String) -> bool:
	var stock := P.stock(snapshot, stock_id)
	if stock.is_empty() or not stock.get("searched", false): return false
	if not str(stock.get("module_id", "")).is_empty() and instance(data,str(stock.module_id)).is_empty():return false
	return buffers_known(data,stock_id)

static func buffers_known(data:Dictionary,stock_id:String)->bool:
	for row: Dictionary in rows(data, "modules", "instances"):
		if not row.get("stock_refs", {}).values().has(stock_id): continue
		var visibility: Variant = row.get("stock_visibility", {})
		if visibility is bool and not visibility: return false
		if visibility is Dictionary:
			if visibility.get(stock_id) is bool and not visibility[stock_id]: return false
			for key in row.stock_refs:
				if row.stock_refs[key] == stock_id and visibility.get(key) is bool and not visibility[key]: return false
		var values := stock_buffers(data, stock_id)
		if values.is_empty(): return false # Missing public rows are unknown, never empty.
		for buffer: Dictionary in values:
			if (buffer.get("stock_visibility") is bool and not buffer.stock_visibility) or (buffer.get("visible") is bool and not buffer.visible) or not (buffer.get("actual") is int or buffer.get("actual") is float): return false
	return true

static func visible_stock(data: Dictionary, snapshot: Dictionary, id: String) -> Dictionary:
	var result := P.stock(snapshot, id)
	if not result.is_empty() and stock_visible(data, snapshot, id): return result
	# Remote aggregate is explicitly read-only. It never becomes draggable goods,
	# free stock or invented tool/book identities in the ordinary snapshot.
	if result.is_empty() and buffers_known(data,id):
		for row:Dictionary in rows(data,"modules","instances"):
			if not row.get("stock_refs",{}).values().has(id):continue
			var location:Dictionary={}
			for port:Dictionary in dictionaries(row.get("ports",[])):
				if row.stock_refs.get(port.get("buffer_id",""))==id:location=port.get("location",{});break
			return {"id":id,"searched":true,"owner":row.get("owner"),"location":location,"display_only":true,"items":{}}
	if result.is_empty():return {}
	result["items"] = {}; result["searched"] = false
	return result

static func location(value: Variant) -> String:
	if not value is Dictionary or not value.has("x") or not value.has("z"): return "位置未提供"
	return "%s · %s, %s" % [region_name(str(value.get("regionId", value.get("region", "")))), P.stat_number(value.x), P.stat_number(value.z)]

static func region_name(id: String) -> String:
	# Call only for locations already exposed by the authoritative snapshot.
	# No generated names or unknown destination/compass inference.
	return str({"RH-HOME":"旧宅周边", "RH-VILLAGE":"村落"}.get(id, "已知地区"))

static func buffers(row: Dictionary) -> Array:
	var visuals: Variant = row.get("visuals", {})
	return dictionaries(visuals.get("buffers", [])) if visuals is Dictionary else []

static func stock_buffers(data: Dictionary, stock_id: String) -> Array:
	var result: Array = []
	for row: Dictionary in rows(data, "modules", "instances"):
		for buffer: Dictionary in buffers(row):
			if buffer.get("stock_ref") == stock_id: result.append(buffer)
	return result

static func quantity(value: Variant, unit: String = "count") -> String:
	return (P.stat_number(value) if unit == "count" else P.number(value)) + (" m³" if unit in ["m3", "m³"] else " 件" if unit == "count" else " " + unit)

static func buffer_text(buffer: Dictionary) -> String:
	# reserved is future OUTPUT CAPACITY, not a hold to subtract from actual.
	var unit := str(buffer.get("unit", "count"))
	var text := "%s  %s / %s" % [P.item_name(str(buffer.get("item_id", ""))), quantity(buffer.get("actual"), unit), quantity(buffer.get("capacity"), unit)]
	if float(buffer.get("reserved", 0)) > 0: text += " · 输出预占 " + quantity(buffer.reserved, unit)
	return text

static func progress(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("progress_seconds") is float and not value.get("progress_seconds") is int: return {}
	var duration := float(value.get("duration_seconds", 0))
	if duration <= 0: return {}
	return {"value":clampf(float(value.progress_seconds) / duration, 0, 1), "text":P.number(value.progress_seconds) + " / " + P.number(duration) + " 秒", "reason":str(value.get("paused_reason", "") if value.get("paused_reason") != null else "")}

static func alerts(data: Dictionary) -> Array:
	var result := dictionaries(data.get("alerts", []))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if severity(a) != severity(b): return severity(a) > severity(b)
		return str(a.get("id", a.get("key", ""))) < str(b.get("id", b.get("key", ""))))
	return result

static func attention_alerts(data: Dictionary) -> Array:
	# Temporary reading preferences never hide an urgent cause or resolve it.
	return alerts(data).filter(func(row: Dictionary): return row.get("severity") == "critical" or row.get("status", "new") != "ignored")

static func alert_payload(row: Dictionary) -> Dictionary:
	return {"key":str(row.get("key", "")), "notification_token":str(row.get("notification_token", ""))}

static func alert_status(row: Dictionary, now: float) -> String:
	if row.get("resolved", false): return "已解决 · 来源已结束"
	var status := str(row.get("status", "new"))
	if row.get("severity") == "critical":
		return "紧急 · 已确认，尚未解决" if row.get("acknowledged", false) else "紧急 · 未确认，尚未解决"
	if status == "ignored": return "暂忽略 · 尚未解决 · 剩余 " + P.number(maxf(0, float(row.get("ignored_until", now)) - now)) + " 模拟秒"
	return "已确认 · 尚未解决" if status == "acknowledged" else "新告警 · 尚未解决"

static func severity(row: Dictionary) -> int:
	var value: Variant = row.get("severity", "info")
	return int(value) if value is int or value is float else int({"critical":4,"danger":3,"error":3,"warning":2,"info":1}.get(str(value), 1))

static func known_stocks(data: Dictionary, snapshot: Dictionary, row: Dictionary) -> Array:
	var result: Array = []
	if instance(data, str(row.get("id", ""))).is_empty(): return result
	var references: Variant = row.get("stock_refs", {})
	if not references is Dictionary: return result
	for key in references:
		var stock := visible_stock(data, snapshot, str(references[key]))
		# Opening a module does not search its closed containers or disclose goods.
		result.append({"buffer_id":str(key), "stock_id":str(references[key]), "stock":stock})
	return result
