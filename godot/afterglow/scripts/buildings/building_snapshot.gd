extends RefCounted
## Referential/type checks at restore and final CAS boundaries. No repair/reseed.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Draft = preload("res://scripts/actions/domain_draft.gd")

static func bad(reason: String) -> Dictionary:
	return {"ok":false,"code":"INVALID_DOMAIN_STATE","reason":reason}

static func number(v: Variant, low: float = 0.0, high: float = INF) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= low and float(v) <= high

static func identity(v: Variant) -> bool:
	return v is String and not v.is_empty() and v.length() <= 512

static func indexed(values: Variant) -> Dictionary:
	if not values is Array: return {}
	var result: Dictionary = {}
	for v in values:
		if not v is Dictionary or not identity(v.get("id")) or result.has(v.id): return {}
		result[v.id] = v
	return result

static func holder(id: Variant, facts: Dictionary) -> Dictionary:
	if not identity(id): return {}
	if str(id).begins_with("pack:"):
		var a := Draft.find(facts.get("actors",[]), str(id).trim_prefix("pack:"))
		return {} if a.is_empty() else {"items":a.get("pack",{})}
	return Draft.find(facts.get("stocks",[]), str(id))

static func stock_references(view: RefCounted, facts: Dictionary) -> Dictionary:
	var stocks := indexed(facts.get("stocks",[]))
	if stocks.size() != facts.get("stocks",[]).size(): return bad("容器身份重复或无效")
	var region_presence: Dictionary = {}
	for stock in stocks.values():
		var at := Geometry.location(stock)
		if not stock.get("items") is Dictionary:
			return bad("容器归属或数量表无效：" + stock.id)
		var region_id := str(at.regionId)
		if not region_presence.has(region_id):
			region_presence[region_id] = not view.region(region_id).is_empty()
		if not region_presence[region_id]:
			return bad("容器归属或数量表无效：" + stock.id)
		var raw: Variant = stock.get("location",stock.get("position",stock))
		if not raw is Dictionary or not ["x","y","z"].all(func(k:String)->bool:return number(raw.get(k),-100000,100000)): return bad("容器位置无效："+stock.id)
		if not stock.items.values().all(func(n:Variant)->bool:return number(n)): return bad("容器物资数值无效："+stock.id)
		var parent: Variant = stock.get("structureId")
		if parent not in [null,""]:
			if not identity(parent):return bad("容器构件身份无效："+stock.id)
			var e: Dictionary = view.entity(str(parent))
			var v: Dictionary = e.get("data",{}).get("structure",{})
			var p := Geometry.location(v)
			# Legacy stocks use their cabinet's interaction side, not its centre.
			if e.get("kind") != "structure" or p.regionId != at.regionId or p.get("buildingId") != at.get("buildingId") or p.get("storeyId") != at.get("storeyId") or Geometry.point(p).distance_to(Geometry.point(at)) > 2.25: return bad("容器与实际承载构件分离："+stock.id)
	return {"ok":true,"code":"OK"}

static func validate(view: RefCounted, facts: Dictionary, catalog: Dictionary, structures_check: bool = true, production_check: bool = true) -> Dictionary:
	if facts.has("tools"): return bad("旧工具必须先迁入唯一production扩展，不能保留两张活工具表")
	var stock_check := stock_references(view,facts)
	if not stock_check.ok:return stock_check
	if structures_check:
		var s: Variant = view.extension("r3:structures")
		if s != null:
			if not s is Dictionary or s.get("schemaVersion") != 1 or not s.get("instances") is Array or not s.get("storeys") is Array: return bad("建筑存档结构无效")
			# The view is immutable during this synchronous validation. Detach its
			# entity aggregate ONCE, then reuse the existing ID index for every
			# original referential check and the complete orphan scan. No result
			# or authority survives this call; a new draft is always read afresh.
			var entity_facts := indexed(view.entities())
			var region_presence:Dictionary={}
			var instances := indexed(s.instances); var storeys := indexed(s.storeys)
			if instances.size() != s.instances.size() or storeys.size() != s.storeys.size(): return bad("构件或楼层身份重复/无效")
			for level in storeys.values():
				var region_id:=str(level.get("regionId",""))
				if not region_presence.has(region_id):region_presence[region_id]=not view.region(region_id).is_empty()
				if not identity(level.get("buildingId")) or not region_presence[region_id] or not number(level.get("elevation"),-100000,100000): return bad("楼层归属或高度无效")
			for v in instances.values():
				if not Geometry.supported_version(v.get("geometryVersion",1)):return bad("不支持的建筑几何版本："+str(v.id))
				var d: Dictionary = catalog.get("structure_definitions",{}).get(v.get("definitionId"),{})
				if d.is_empty() or not number(v.get("hp"),0,float(d.maxHp)) or not number(v.get("version")) or float(v.version) != floor(float(v.version)) or not number(v.get("quarterTurn"),0,3) or float(v.quarterTurn) != floor(float(v.quarterTurn)): return bad("构件定义、生命或版本无效："+v.id)
				var region_id:=str(v.get("regionId",""))
				if not region_presence.has(region_id):region_presence[region_id]=not view.region(region_id).is_empty()
				if not v.get("position") is Dictionary or not ["x","y","z"].all(func(k:String)->bool:return number(v.position.get(k),-100000,100000)) or not region_presence[region_id]: return bad("构件坐标无效："+v.id)
				if v.get("storeyId") != null:
					var level: Dictionary = storeys.get(v.storeyId,{})
					if level.is_empty() or level.buildingId != v.get("buildingId") or level.regionId != v.regionId: return bad("构件楼层引用无效："+v.id)
				if d.has("door"):
					if not v.get("door") is Dictionary or not ["open","locked","blocked"].all(func(k:String)->bool:return v.door.get(k) is bool) or not number(v.door.get("swing"),-1,1) or absf(float(v.door.swing)) != 1.0 or (v.door.open and v.door.locked): return bad("门状态无效："+v.id)
				if d.has("stairs"):
					if not v.get("stairs") is Dictionary: return bad("楼梯连接缺失："+v.id)
					for k in ["fromStoreyId","toStoreyId"]:
						if not storeys.has(v.stairs.get(k)) or storeys[v.stairs[k]].buildingId != v.buildingId: return bad("楼梯楼层引用无效："+v.id)
				var e: Dictionary = entity_facts.get(v.id,{})
				if e.get("kind") != "structure" or e.get("regionId") != v.regionId or e.get("position") != v.position or e.get("data",{}).get("structure") != v: return bad("建筑扩展与实体事实不一致："+v.id)
			for e in entity_facts.values():
				if e.kind == "structure" and not instances.has(e.id): return bad("存在未登记的建筑实体："+e.id)
	if production_check:
		var p: Variant = view.extension("r3:production")
		if p != null:
			if not p is Dictionary or p.get("version") != 1 or not p.get("knowledge") is Dictionary: return bad("生产存档结构无效")
			for key in ["tools","records","trees","orders","facts"]:
				if not p.get(key) is Array or indexed(p[key]).size() != p[key].size(): return bad("生产条目身份重复或无效："+key)
			var tools := indexed(p.tools)
			for t in tools.values():
				var definitions:Dictionary=catalog.get("tool_definitions",{})
				var d: Dictionary = definitions.get(t.get("kind"),definitions.get("legacy_tool",{}) if t.get("qualities") is Dictionary else {})
				if d.is_empty() or holder(t.get("holderId"),facts).is_empty() or not number(t.get("durability"),0,float(d.maxDurability)): return bad("工具定义/持有人/耐久无效："+t.id)
				if t.has("qualities"):
					if not t.qualities is Dictionary or not t.qualities.values().all(func(n:Variant)->bool:return number(n)): return bad("工具能力无效："+t.id)
			for record in p.records:
				var stock := holder(record.get("holderId"),facts)
				if stock.is_empty() or not identity(record.get("itemId")) or float(stock.items.get(record.itemId,0)) < 1 or not number(record.get("seconds"),0.001) or not record.get("grants") is Array or not record.grants.all(identity): return bad("书册事实或持有人无效："+record.id)
			for tree in p.trees:
				if tree.get("phase") not in ["standing","stump"] or not number(tree.get("seconds"),0.001) or not number(tree.get("work"),0,float(tree.seconds)) or not number(tree.get("toolWear")) or not tree.get("yield") is Dictionary or not tree.yield.values().all(func(n:Variant)->bool:return number(n)): return bad("树资源状态无效："+tree.id)
			var recipes := indexed(catalog.get("production_recipes",[]))
			var regional_recipes:Array=preload("res://scripts/production/module_recipes.gd").definitions()
			if not preload("res://scripts/runtime/content_definitions.gd").validate_catalog({"production_recipes":regional_recipes}).ok:return bad("区域配方定义无效")
			for recipe:Dictionary in regional_recipes:
				if recipes.has(recipe.id):return bad("区域配方覆盖旧定义："+str(recipe.id))
				recipes[recipe.id]=recipe
			for o in p.orders:
				if o.get("kind") not in ["craft","study","harvest"] or o.get("status") not in ["active","blocked","completed","cancelled"] or not number(o.get("duration"),0.001) or not number(o.get("elapsed"),0,float(o.duration)+0.00001) or not o.get("toolIds") is Array: return bad("生产工时或状态无效："+o.id)
				if not preload("res://scripts/production/production_teaching.gd").valid_order(o):return bad("学习来源或教师订单无效："+o.id)
				if o.toolIds.size()!=Draft.unique(o.toolIds).size() or not o.toolIds.all(identity):return bad("订单工具清单无效："+o.id)
				if o.kind=="craft" and not recipes.has(o.get("targetId")):return bad("订单配方不存在："+o.id)
				if o.status in ["active","blocked"]:
					if Draft.find(facts.actors,str(o.get("actorId",""))).is_empty(): return bad("订单角色缺失："+o.id)
					for id in o.toolIds + ([o.repairToolId] if o.get("repairToolId") != null else []):
						if not tools.has(id): return bad("订单工具引用失效："+o.id)
					for key in ["sourceId","outputId"]:
						if o.get(key)!=null and holder(o[key],facts).is_empty():return bad("活动订单容器引用失效："+o.id)
			for id in p.knowledge:
				if Draft.find(facts.actors,str(id)).is_empty() or not p.knowledge[id] is Array or not p.knowledge[id].all(identity): return bad("知识归属无效")
		var orders: Variant = view.extension("r3:structure-orders")
		if orders != null:
			if not orders is Dictionary or orders.get("version") != 1 or not orders.get("orders") is Array or indexed(orders.orders).size() != orders.orders.size(): return bad("施工订单结构无效")
			for o in orders.orders:
				if o.get("kind") not in ["place","damage","repair","remove","move"] or o.get("status") not in ["active","blocked","completed","cancelled"] or not number(o.get("seconds"),0.001) or not number(o.get("elapsed"),0,float(o.seconds)+0.00001) or not o.get("cost") is Dictionary or not o.cost.values().all(func(n:Variant)->bool:return number(n)): return bad("施工工时或状态无效："+o.id)
				if o.status in ["active","blocked"]:
					if Draft.find(facts.actors,str(o.get("actorId",""))).is_empty():return bad("施工角色不存在："+o.id)
					for key in ["sourceId","outputId"]:
						if o.get(key)!=null and holder(o[key],facts).is_empty():return bad("施工容器引用失效："+o.id)
	return {"ok":true,"code":"OK"}
