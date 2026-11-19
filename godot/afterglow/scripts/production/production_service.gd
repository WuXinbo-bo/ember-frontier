extends RefCounted
## Port of ProductionKernel: arrivals/holds/labor remain project rules, A owns time/CAS.
const Draft = preload("res://scripts/actions/domain_draft.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Teaching=preload("res://scripts/production/production_teaching.gd")
const ModuleRecipes=preload("res://scripts/production/module_recipes.gd")
const WorkOrders=preload("res://scripts/production/module_work_orders.gd")
const StockPolicy=preload("res://scripts/modules/module_stock_policy.gd")
const ModuleContact=preload("res://scripts/modules/module_contact.gd")
const KEY := "r3:production"
var context: Dictionary
var recipes: Dictionary = {}
var tool_definitions: Dictionary = {}
var wear_enabled := true
var _hold_providers:Array=[]
# These providers read only actor existence, health and permission for
# extension-based holds. They can inspect more fields while an intent exists.
const HUD_IDLE_HOLD_PROVIDERS := [
	"res://scripts/actions/action_service.gd",
	"res://scripts/modules/module_service.gd",
	"res://scripts/planning/zone_service.gd",
	"res://scripts/planning/zone_work_service.gd",
	"res://scripts/runtime/factory_display.gd",
	"res://scripts/runtime/game_runtime.gd",
	"res://scripts/runtime/resident_life.gd",
	"res://scripts/runtime/rural_gameplay.gd",
	"res://scripts/runtime/settlement_workforce.gd",
	"res://scripts/terrain/terrain_service.gd",
]
var _hud_idle_holds_supported: bool = false
var _hud_idle_holds_basis: Array = []
var _hud_idle_holds: Array = []
var content_validation:Dictionary={}
var chapter_one:bool=false

func configure(value: Dictionary) -> void:
	context = preload("res://scripts/actions/domain_context.gd").isolate(value)
	_hold_providers.clear()
	var runtime_host:Variant=value.get("runtime")
	if runtime_host is RefCounted:_hold_providers.append(weakref(runtime_host))
	for provider:Variant in value.get("services",{}).values():
		if provider is RefCounted and provider!=self:_hold_providers.append(weakref(provider))
	_hud_idle_holds_basis.clear()
	_hud_idle_holds.clear()
	_hud_idle_holds_supported = true
	for source: WeakRef in _hold_providers:
		var provider: RefCounted = source.get_ref()
		if provider == null or not provider.has_method("hold_descriptors"):
			continue
		var script: Script = provider.get_script()
		if script == null or script.resource_path not in HUD_IDLE_HOLD_PROVIDERS:
			_hud_idle_holds_supported = false
			break
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	content_validation=Content.validate_catalog(catalog)
	tool_definitions = catalog.tool_definitions
	wear_enabled = preload("res://scripts/runtime/tool_wear_policy.gd").enabled(context.world)
	recipes.clear()
	for recipe in catalog.production_recipes:
		if wear_enabled or not recipe.has("repairTool"): recipes[recipe.id] = recipe
	for recipe:Dictionary in ModuleRecipes.definitions():recipes[recipe.id]=recipe
	var generation:Variant=context.world.extension("generation:factory-r34")
	chapter_one=generation is Dictionary and int(generation.get("content_version",0))>=20
	if chapter_one:ModuleRecipes.configure_chapter_one(recipes)

static func empty_state() -> Dictionary:
	return {"version": 1, "catalogVersion": 1, "nextId": 1, "tools": [], "trees": [], "records": [], "knowledge": {}, "orders": [], "facts": []}

static func active(o: Dictionary) -> bool:
	return o.get("status") in ["active", "blocked"]

func state() -> Dictionary:
	var v: Variant = context.world.extension(KEY)
	return v if v is Dictionary else empty_state()

func hold_descriptors(observed:Dictionary,extension_overrides:Dictionary={})->Array:
	var world:RefCounted=context.world
	var projected:bool=not extension_overrides.has(KEY) and world.has_method("extension_fields")
	var order_fields:Array[String]=["orders"]
	var p:Dictionary=world.extension_fields(KEY,order_fields) if projected else extension_overrides[KEY] if extension_overrides.has(KEY) else state()
	var records:Variant=null
	var holds:Array=[]
	for o:Dictionary in p.get("orders",[]):
		if not active(o):continue
		var actor:Dictionary=Draft.find(observed.get("actors",[]),str(o.get("actorId","")))
		if actor.is_empty() or float(actor.get("hp",0))<=0:continue
		if actor.id!="player" and (not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false)):continue
		var cost:Dictionary={}
		if o.kind=="craft":cost=recipes.get(o.targetId,{}).get("inputs",{}).duplicate(true)
		elif o.kind=="study":
			if records==null:
				var record_fields:Array[String]=["records"]
				records=world.extension_fields(KEY,record_fields).get("records",[]) if projected else p.get("records",[])
			var record:=Draft.find(records,str(o.targetId))
			if not record.is_empty():cost[str(record.itemId)]=1
		var tools:Array=o.get("toolIds",[]).duplicate()
		if o.get("repairToolId")!=null:tools.append(o.repairToolId)
		holds.append({"schema_version":1,"owner":"actions","intent_id":str(o.id),"actor_id":str(o.actorId),"phase":"paused" if o.status=="blocked" else "active","source_id":str(o.sourceId) if o.get("sourceId")!=null else "","cost":cost,"tool_ids":tools,"use_target_id":str(o.stationId) if o.get("stationId")!=null else str(o.targetId) if o.kind in ["harvest","study"] else ""})
	holds.append_array(Factory.hold_descriptors(self,observed,extension_overrides))
	return holds

func all_holds(tx:RefCounted=null)->Array:
	var cache_key:String="production.all_holds:"+str(get_instance_id())
	if tx!=null and tx.observation_only:
		var cached:Variant=tx.cached_observation(cache_key)
		if cached is Array:return cached
	var observed:Dictionary=context.facts.call() if tx==null else tx.staged
	var overrides:Dictionary={} if tx==null else tx.extensions
	var holds:=hold_descriptors(observed,overrides)
	for source:WeakRef in _hold_providers:
		var provider:Variant=source.get_ref()
		if provider!=null and provider.has_method("hold_descriptors"):
			holds.append_array(provider.hold_descriptors(observed,overrides))
	if tx!=null and tx.observation_only:tx.cache_observation(cache_key,holds)
	return holds

func hud_holds(actors: Array) -> Array:
	var world: RefCounted = context.world
	if not _hud_idle_holds_supported or not world.has_method("extension_token"):
		return all_holds()
	var basis: Array = []
	for actor: Dictionary in actors:
		# A resident's outdoor stroll owns no resources. All other intent
		# families, including bed use, retain their full validation/read path.
		var intent: Variant = actor.get("intent")
		if intent != null:
			var goal: Variant = intent.get("resident_goal", {}) if intent is Dictionary else null
			if not intent is Dictionary or intent.get("owner") != "residents" or intent.get("kind") != "walk" or intent.get("purpose") != "village-stroll" or not goal is Dictionary or goal.get("kind") == "bed":
				return all_holds()
		var relationship: Dictionary = actor.get("relationship", {}) if actor.get("relationship") is Dictionary else {}
		basis.append([actor.id, float(actor.get("hp", 0)) > 0, relationship.get("member", false), relationship.get("consent", false)])
	for extension_id: String in [KEY, "r3:structure-orders", Factory.LOGISTICS, "r34:modules", "r34:zonework"]:
		basis.append(world.extension_token(extension_id))
	if basis != _hud_idle_holds_basis:
		_hud_idle_holds = all_holds()
		_hud_idle_holds_basis = basis
	return _hud_idle_holds.duplicate(true)

func reserved(source:String,item:String,excluding:String="",tx:RefCounted=null)->float:
	var total:=0.0
	for hold:Dictionary in all_holds(tx):
		if hold.intent_id!=excluding and hold.source_id==source:total+=float(hold.cost.get(item,0))
	return total

func reserve_floor(source:String,item:String,tx:RefCounted=null)->float:return StockPolicy.floor_for(self,source,item,tx)
func work_reserved(source:String,item:String,excluding:String="",tx:RefCounted=null)->float:return reserved(source,item,excluding,tx)+reserve_floor(source,item,tx)
func available_for(source:String,item:String,purpose:String="work",excluding:String="",tx:RefCounted=null)->float:
	var stock:Dictionary=context.stock.call(source) if tx==null else tx.stock(source)
	var held:float=reserved(source,item,excluding,tx)
	if purpose!="life":held+=reserve_floor(source,item,tx)
	return maxf(0,float(stock.get("items",{}).get(item,0))-held)

func tool_reserved(id:String,excluding:String="",tx:RefCounted=null)->bool:
	# C's completion path retains its own terrain conflict check. This public
	# legacy query excludes terrain only; every B use calls tool_unavailable.
	for hold:Dictionary in all_holds(tx):
		if hold.owner!="terrain" and hold.intent_id!=excluding and hold.tool_ids.has(id):return true
	return false

func tool_unavailable(id:String,excluding:String="",tx:RefCounted=null)->bool:
	for hold:Dictionary in all_holds(tx):
		if hold.intent_id!=excluding and hold.tool_ids.has(id):return true
	return false

func use_reserved(target_id:String,excluding:String="",tx:RefCounted=null)->bool:
	if target_id.is_empty():return false
	for hold:Dictionary in all_holds(tx):
		if hold.intent_id!=excluding and hold.use_target_id==target_id:return true
	return false

func tool_qualities(tool: Dictionary) -> Dictionary:
	return tool.get("qualities", tool_definitions.get(tool.get("kind"), {}).get("qualities", {}))

func tool_definition(tool: Dictionary) -> Dictionary:
	return tool_definitions.get(tool.get("kind"),tool_definitions.get("legacy_tool",{}) if tool.get("qualities") is Dictionary else {})

static func migrate_legacy_tools(world_snapshot: Dictionary, runtime_facts: Dictionary) -> Dictionary:
	# Called by A once at the import boundary, before constructing live services.
	# Original source bytes stay archived by A. Never keep two live tool tables.
	var w := world_snapshot.duplicate(true)
	var f := runtime_facts.duplicate(true)
	if not f.get("tools", []) is Array: return Building.failure("INVALID_TOOLS", "旧工具表无效")
	var p: Dictionary = w.get("extensions", {}).get(KEY, empty_state()).duplicate(true)
	var migrated: Array = []
	for source in f.get("tools", []):
		if not source is Dictionary or not source.get("id") is String or not source.get("holderId") is String or not source.get("qualities") is Dictionary: return Building.failure("INVALID_TOOLS", "旧工具身份或能力无效")
		if not (source.get("durability") is int or source.get("durability") is float) or not is_finite(float(source.durability)) or float(source.durability) < 0 or float(source.durability) > 100: return Building.failure("INVALID_TOOLS", "旧工具耐久无效")
		for q in source.qualities.values():
			if not (q is int or q is float) or not is_finite(float(q)) or float(q) < 0: return Building.failure("INVALID_TOOLS", "旧工具能力数值无效")
		var old := Draft.find(p.get("tools", []), str(source.id))
		if not old.is_empty():
			if old.get("holderId") != source.holderId or old.get("durability") != source.durability or old.get("qualities", {}) != source.qualities: return Building.failure("TOOL_CONFLICT", "同一工具在两个旧表中的事实冲突")
		else:
			var tool: Dictionary = source.duplicate(true)
			p.tools.append(tool)
			migrated.append(source.id)
	f.erase("tools")
	if not w.has("extensions"): w.extensions = {}
	w.extensions[KEY] = p
	return {"ok":true, "code":"OK", "world":w, "facts":f, "migrated_ids":migrated}

func reach(actor_id: String, id: String, target: Dictionary, kind: String = "stock", tx: RefCounted = null) -> Variant:
	var a: Dictionary = context.actor.call(actor_id) if tx == null else tx.actor(actor_id)
	if a.is_empty() or float(a.get("hp", 0)) <= 0: return "角色已失能"
	if target.is_empty(): return "实际目标不存在"
	var from := Geometry.location(a)
	var to := Geometry.location(target)
	if not Interaction.same_level(from,to): return "需要真实到达同层目标旁"
	if kind == "stock" and not target.get("searched", true): return "尚未搜索这个容器"
	var owner: Variant = target.get("owner")
	var team_handoff := false
	if kind == "handoff" and id.begins_with("pack:") and owner != actor_id:
		var other: Dictionary = context.actor.call(str(owner)) if tx == null else tx.actor(str(owner))
		var requester_consents: bool = actor_id == "player" or (a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false))
		var owner_consents: bool = str(owner) == "player" or (other.get("relationship",{}).get("member",false) and other.get("relationship",{}).get("consent",false))
		team_handoff = requester_consents and owner_consents and float(other.get("hp",0)) > 0
	if owner != null and owner not in [actor_id, "home-residents", a.get("householdId")] and not team_handoff: return "没有物主许可"
	if owner == "home-residents" and actor_id != "player" and not a.get("relationship",{}).get("member",false): return "尚未自愿加入共同生活"
	var query:RefCounted=context.spatial.current_space()
	if target.has("module_id"):
		var module:Dictionary=ModuleRecipes.module(self,str(target.module_id),tx)
		if module.is_empty() or module.get("status") in ["ruined","dismantled","planned","constructing"]:return "建筑储物设施不可用"
		return null if ModuleContact.near(query,from,module) else "需要靠近同层建筑"
	var piece:Dictionary=query.by_id.get(str(target.get("structureId",id)),{})
	if not piece.is_empty():
		if Interaction.structure(query,from,piece,2.25):return null
	else:
		var entity:Dictionary=context.world.entity(id)
		if not entity.is_empty() and Interaction.entity(query,from,entity):return null
	if Geometry.point(from).distance_to(Geometry.point(to))>2.25:return "需要靠近同层目标的实际表面"
	if not query.contact_clear(from, to, id): return "实际使用线被墙体或地形遮挡"
	return null

func availability(request: Dictionary) -> Dictionary:
	var r := prepare(request)
	if r.get("ok", false): r.world_changes = []; r.fact_changes = []
	return r

func prepare(request: Dictionary) -> Dictionary:
	if str(request.get("kind","")).begins_with("factory.") or str(request.get("kind","")).begins_with("logistics."):return Factory.prepare(self,request)
	var tx := Draft.new(context)
	var r := start(tx, request)
	return tx.result() if r.ok else r

func start(tx: RefCounted, request: Dictionary) -> Dictionary:
	if not content_validation.get("ok",false):return content_validation.duplicate(true)
	var p: Dictionary = tx.extension(KEY, empty_state())
	var a: Dictionary = tx.actor(str(request.get("actor_id", "")))
	var payload: Dictionary = request.get("payload", {})
	var kind := str(request.get("kind", ""))
	if not payload.get("tool_ids",[]) is Array: return Building.failure("INVALID", "工具清单无效")
	var selected: Array = payload.get("tool_ids",[payload.tool_id] if payload.get("tool_id") is String and not payload.tool_id.is_empty() else []).duplicate()
	if selected.size()!=Draft.unique(selected).size() or not selected.all(func(id:Variant)->bool:return id is String and not id.is_empty()): return Building.failure("TOOLS", "工具身份无效或重复")
	if a.is_empty() or float(a.get("hp", 0)) <= 0: return Building.failure("FORBIDDEN", "角色已失能")
	for o in p.orders:
		if active(o) and o.actorId == a.id: return Building.failure("RESERVED", "角色已有未结束的生产订单")
	var so: Dictionary = tx.extension("r3:structure-orders", {"version": 1, "orders": []})
	for o in so.orders:
		if active(o) and o.actorId == a.id: return Building.failure("RESERVED", "角色正在施工")
	var order := {"id": str(request.get("command_id", "preview")) + ":order", "kind": kind, "actorId": a.id,
		"targetId": request.get("target_id", ""), "sourceId": null, "outputId": payload.get("output_id"),
		"stationId": null, "repairToolId": payload.get("repair_tool_id"), "toolIds": selected,
		"status": "active", "elapsed": 0.0, "duration": 0.0, "reason": null}
	if kind == "craft":
		if payload.has("module_program_id"):
			order.module_program_id=payload.module_program_id;order.module_program_revision=payload.get("module_program_revision")
		order.targetId = payload.get("recipe_id", "")
		var r: Dictionary = recipes.get(order.targetId, {})
		if r.is_empty(): return Building.failure("INVALID", "配方不存在")
		var defined:Dictionary=Content.validate_catalog({"production_recipes":[r]})
		if not defined.ok:return defined
		order.sourceId = payload.get("source_id")
		order.stationId = request.get("target_id")
		order.duration = r.seconds
		var operators: Array=[]
		for quality in r.qualities:
			for id in selected:
				var t:=Draft.find(p.tools,str(id))
				if not t.is_empty() and float(tool_qualities(t).get(quality,0))>=float(r.qualities[quality]):
					if not operators.has(id):operators.append(id)
					break
		order.toolIds=operators
	elif kind == "study":
		var learning_source:Variant=payload.get("learning_source","book")
		if learning_source not in ["book","teacher"]:return Building.failure("INVALID_LEARNING_SOURCE","学习来源无效")
		if learning_source=="teacher":
			for key:String in ["record_id","source_id","output_id","tool_id","tool_ids","repair_tool_id","station_id","grants","seconds"]:
				if payload.has(key):return Building.failure("INVALID_TEACHING_PAYLOAD","居民教学不能混用书册、工具或材料参数")
			order.learning_source="teacher";order.teacher_id=Teaching.TEACHER;order.knowledge_id=payload.get("knowledge_id")
			order.outputId=null;order.toolIds=[];order.duration=12.0
			if not Teaching.valid_order(order):return Building.failure("INVALID_TEACHING_SOURCE","本期仅支持该居民教授基础工具维修")
			if p.knowledge.get(a.id,[]).has(Teaching.KNOWLEDGE):return Building.failure("KNOWN","已经掌握该内容")
		else:
			if payload.has("knowledge_id") or payload.has("teacher_id"):return Building.failure("INVALID_LEARNING_SOURCE","书册学习不能混用教师参数")
			order.targetId = payload.get("record_id", order.targetId)
			var record := Draft.find(p.records, str(order.targetId))
			if record.is_empty(): return Building.failure("MISSING", "学习记录不存在")
			order.sourceId = record.holderId
			order.outputId = null
			order.toolIds = []
			order.duration = record.seconds
			if record.grants.all(func(k: String) -> bool: return p.knowledge.get(a.id, []).has(k)): return Building.failure("KNOWN", "已经掌握记录内容")
	elif kind == "harvest":
		order.targetId = payload.get("tree_id", order.targetId)
		var tree := tree_state(p, str(order.targetId))
		if tree.is_empty() or tree.phase != "standing": return Building.failure("DESTROYED", "树木已采伐或不存在")
		if Draft.find(p.trees, str(tree.id)).is_empty(): p.trees.append(tree)
		order.duration = tree.seconds
		order.elapsed = tree.work
		if order.outputId == null: order.outputId=context.world.entity(str(tree.id)).get("data",{}).get("outputId")
	else: return Building.failure("UNKNOWN_COMMAND", "生产服务不处理此动作")
	for o in p.orders:
		if active(o) and ((order.kind in ["study", "harvest"] and o.kind == order.kind and o.targetId == order.targetId) or (order.stationId != null and o.get("stationId") == order.stationId)): return Building.failure("RESERVED", "目标或工位正在被使用")
	var use_target:String=str(order.stationId) if order.stationId!=null else str(order.targetId) if kind in ["study","harvest"] else ""
	if use_reserved(use_target,"",tx):return Building.failure("RESERVED","目标或工位正在被使用")
	if order.toolIds.size() != Draft.unique(order.toolIds).size() or order.toolIds.has(order.repairToolId): return Building.failure("TOOLS", "操作工具不能重复，待修工具不能同时操作")
	for id in order.toolIds + ([order.repairToolId] if order.repairToolId != null else []):
		if tool_unavailable(str(id), "", tx): return Building.failure("RESERVED", "工具已被作业或地形劳动预留")
	var reason: Variant = check(tx, order)
	if reason != null: return Building.failure("UNAVAILABLE", reason)
	p.orders.append(order)
	return Building.success([], [], order.duration)

func tree_state(p: Dictionary, id: String) -> Dictionary:
	var saved := Draft.find(p.trees, id)
	if not saved.is_empty(): return saved
	var e: Dictionary = context.world.entity(id)
	var h: Dictionary = e.get("data", {}).get("harvest", {})
	if h.is_empty(): return {}
	return {"id": id, "place": Geometry.location(e), "phase": h.get("phase", "standing"), "work": h.get("work", 0.0), "seconds": h.get("seconds", 24.0), "yield": h.get("yield", {}), "toolWear": h.get("toolWear", 6.0)}

func check(tx: RefCounted, o: Dictionary) -> Variant:
	var p: Dictionary = tx.extension(KEY, empty_state())
	var a: Dictionary = tx.actor(str(o.actorId))
	if a.is_empty() or float(a.get("hp", 0)) <= 0: return "角色已失能"
	if a.id != "player" and (not a.get("relationship", {}).get("member",false) or not a.get("relationship", {}).get("consent", false)): return "住户未自愿加入或未同意工作"
	var use_target:String=str(o.stationId) if o.get("stationId")!=null else str(o.targetId) if o.kind in ["study","harvest"] else ""
	if use_reserved(use_target,str(o.id),tx):return "目标或工位已被其他行动占用"
	var player_harvest:bool=a.id=="player" and o.kind=="harvest"
	for id in [o.sourceId, null if player_harvest else o.outputId]:
		if id != null:
			var problem: Variant = reach(a.id, str(id), tx.stock(str(id)), "stock", tx)
			if problem != null: return problem
	for id in o.toolIds + ([o.repairToolId] if o.repairToolId != null else []):
		var t := Draft.find(p.tools, str(id))
		if t.is_empty() or tool_definition(t).is_empty(): return "工具不存在"
		if id != o.repairToolId and float(o.elapsed) < float(o.duration) - 0.00001 and float(t.durability) <= 0: return "工具已损坏"
		if tool_unavailable(str(id), str(o.id), tx): return "工具被其他订单或地形劳动占用"
		var problem: Variant = reach(a.id, str(t.holderId), tx.stock(str(t.holderId)), "stock", tx)
		if problem != null: return problem
	if o.kind == "harvest":
		var tree := tree_state(p, str(o.targetId))
		var e: Dictionary = context.world.entity(str(o.targetId))
		if tree.is_empty() or tree.phase != "standing" or e.is_empty() or e.data.harvest.phase != "standing": return "树木已经采伐"
		if player_harvest:
			if not Interaction.player_tree_near(Geometry.location(a),e):return "再靠近一点就能砍树"
		else:
			var problem: Variant = reach(a.id, str(tree.id), tree.place, "tree", tx)
			if problem != null: return problem
		if not qualities(p, o.toolIds, {"chopping": 1}): return "缺少采伐工具"
		var drop: Dictionary = context.world.entity(str(o.outputId))
		if drop.get("kind") != "container" or not drop.get("data", {}).get("dropped", false) or Geometry.point(Geometry.location(drop)).distance_to(Geometry.point(tree.place)) > 1.5: return "采伐必须落到树旁真实掉落容器"
	elif o.kind == "craft":
		var r: Dictionary = recipes.get(o.targetId, {})
		if r.is_empty(): return "配方不存在"
		if not r.knowledge.all(func(k: String) -> bool: return p.knowledge.get(a.id, []).has(k)): return "尚未学习这道工艺"
		if not Content.validate_catalog({"production_recipes":[r]}).ok:return "配方引用了未定义或数量非法的正式物资"
		if float(Content.actor_effects(a).skills.get("crafting", 0)) < float(r.minCrafting): return "制作熟练度不足"
		var program_problem:Variant=WorkOrders.program_problem(self,tx,o)
		if program_problem!=null:return program_problem
		if ModuleRecipes.applies(r):
			var problem:Variant=ModuleRecipes.problem(self,tx,a,o,r)
			if problem!=null:return problem
		else:
			var station: Dictionary = context.spatial.instance(str(o.stationId))
			if station.is_empty() or float(station.hp) <= 0 or not r.stationTags.all(func(tag: String) -> bool: return context.spatial.geometry.definition(station).stationTags.has(tag)): return "缺少可运行的工位"
			var problem: Variant = context.spatial.can_use(a.id, station, {}, tx.staged)
			if problem != null: return problem
			problem = context.spatial.permission(a.id, station.id, "use", station, tx.staged)
			if problem != null: return problem
		if not qualities(p, o.toolIds, r.qualities): return "缺少对应工具能力"
		var source: Dictionary = tx.stock(str(o.sourceId))
		if source.is_empty(): return "材料容器不存在"
		for item in r.inputs:
			if float(source.items.get(item, 0)) - work_reserved(str(o.sourceId), item, str(o.id), tx) < float(r.inputs[item]): return "材料不足、已预留或低于生活保留量：" + item
		var capacity:=capacity_check(str(o.outputId),r.outputs,str(o.id),tx)
		if not capacity.ok:return capacity.get("reason",capacity.code)
		var target := Draft.find(p.tools, str(o.repairToolId))
		if r.has("repairTool") and (target.is_empty() or target.get("kind") != r.repairTool.kind or float(target.durability) >= float(tool_definitions[target.kind].maxDurability)): return "没有需要此项维修的工具"
		if not r.has("repairTool") and o.repairToolId != null: return "该工序不接受待修工具"
	elif o.kind == "study":
		if o.get("learning_source")=="teacher":return Teaching.problem(self,tx,o)
		var record := Draft.find(p.records, str(o.targetId))
		if record.is_empty() or record.holderId != o.sourceId: return "书册持有人已变化"
		var source: Dictionary = tx.stock(str(record.holderId))
		if source.is_empty() or float(source.items.get(record.itemId, 0)) - reserved(str(record.holderId), str(record.itemId), str(o.id), tx) < 1: return "实际书册不存在或已预留"
	return null

func qualities(p: Dictionary, ids: Array, required: Dictionary) -> bool:
	for key in required:
		var found := false
		for id in ids:
			var t := Draft.find(p.tools, str(id))
			if not t.is_empty() and float(tool_qualities(t).get(key, 0)) >= float(required[key]): found = true
		if not found: return false
	return true

func work(tx: RefCounted, order_id: String, dt: float) -> Dictionary:
	if not is_finite(dt) or dt <= 0 or dt > 1: return Building.failure("INVALID", "作业步长必须在(0,1]秒")
	var p: Dictionary = tx.extension(KEY, empty_state())
	var o := Draft.find(p.orders, order_id)
	if o.is_empty() or not active(o): return Building.failure("MISSING", "订单不存在或已结束")
	var problem: Variant = check(tx, o)
	if problem != null:
		o.status = "blocked"; o.reason = problem;o.effective_work=0.0
		return Building.success()
	var a: Dictionary = tx.actor(str(o.actorId))
	var recipe: Dictionary = recipes.get(o.targetId, {})
	var tree := tree_state(p, str(o.targetId)) if o.kind == "harvest" else {}
	var rate := 2.0 if o.kind == "harvest" else 0.0 if o.kind == "study" else float(recipe.staminaPerSecond)
	if o.kind=="harvest" and a.id=="player":rate*=preload("res://scripts/runtime/movement_policy.gd").PLAYER_EXERTION_SCALE
	var wear := 0.0 if not wear_enabled or o.kind == "study" else float(tree.toolWear if o.kind == "harvest" else recipe.toolWear) / float(o.duration)
	var seconds := minf(dt, maxf(0, float(o.duration) - float(o.elapsed)))
	if rate > 0: seconds = minf(seconds, float(a.stamina) / rate)
	for id in o.toolIds:
		if wear > 0: seconds = minf(seconds, float(Draft.find(p.tools, str(id)).durability) / wear)
	if seconds <= 0.000001 and float(o.elapsed) < float(o.duration) - 0.000001:
		o.status = "blocked"; o.reason = "体力或工具耐久不足"
		return Building.success()
	a.stamina = maxf(0, float(a.stamina) - seconds * rate)
	if wear > 0:
		for id in o.toolIds:
			var t := Draft.find(p.tools, str(id)); t.durability = maxf(0, float(t.durability) - seconds * wear)
	o.effective_work=seconds
	o.elapsed = minf(float(o.duration), float(o.elapsed) + seconds)
	o.status = "active"; o.reason = null
	if not tree.is_empty(): tree.work = o.elapsed
	if float(o.duration) - float(o.elapsed) > 0.000001: return Building.success()
	problem = check(tx, o)
	if problem != null: o.status = "blocked"; o.reason = problem; return Building.success()
	if o.kind == "craft":
		if not tx.stock_delta(str(o.sourceId), recipe.inputs, -1) or not tx.stock_delta(str(o.outputId), recipe.outputs): return Building.failure("MATERIALS", "材料结算失败，事务未提交")
		if recipe.has("repairTool"):
			var t := Draft.find(p.tools, str(o.repairToolId)); t.durability = minf(float(tool_definitions[t.kind].maxDurability), float(t.durability) + float(recipe.repairTool.restore))
		if recipe.has("createTool"):
			p.tools.append({"id": str(o.id) + ":tool", "kind": recipe.createTool.kind, "holderId": o.outputId, "durability": recipe.createTool.durability if wear_enabled else 100.0})
		WorkOrders.completed(self,tx,o)
		a.skills.crafting = float(a.skills.get("crafting", 0)) + 1
	elif o.kind == "study":
		var known: Array = p.knowledge.get(a.id, [])
		var grants:Array=[Teaching.KNOWLEDGE] if o.get("learning_source")=="teacher" else Draft.find(p.records, str(o.targetId)).grants
		for key in grants:
			if not known.has(key): known.append(key)
		p.knowledge[a.id] = known
	else:
		if not tx.stock_delta(str(o.outputId), tree.yield): return Building.failure("MATERIALS", "掉落结算失败")
		tree.phase = "stump"; tree.work = tree.seconds
		var e: Dictionary = context.world.entity(str(tree.id))
		var next := e.duplicate(true)
		next.data.harvest.phase = "stump"; next.data.harvest.work = tree.seconds
		next.data.solid = false; next.data.opaque = false
		next.bounds = Geometry.json_box(AABB(Geometry.point(e.position) - Vector3(0.25, 0, 0.25), Vector3(0.5, 0.3, 0.5)))
		next.revision = int(e.get("revision", 0)) + 1
		tx.extra.append({"op": "entity.put", "id": e.id, "before_exists": true, "before": e, "after": next})
		a.skills.gathering = float(a.skills.get("gathering", 0)) + 1
	o.status = "completed"; o.reason = null
	var fact := {"id": str(o.id) + ":complete", "orderId": o.id, "actorId": o.actorId, "kind": "tree-felled" if o.kind == "harvest" else "learned" if o.kind == "study" else "tool-repaired" if recipe.has("repairTool") else "crafted", "targetId": o.targetId, "outputId": o.outputId}
	if o.get("learning_source")=="teacher":fact.source_kind="teacher";fact.teacher_id=o.teacher_id;fact.knowledge_id=o.knowledge_id
	p.facts.append(fact)
	if p.facts.size() > 160: p.facts = p.facts.slice(-160)
	tx.events.append(fact)
	return Building.success()

func teaching_projection(actor_id:String="player",teacher_id:String="")->Dictionary:return Teaching.projection(self,actor_id,teacher_id)

func cancel(tx: RefCounted, actor_id: String, order_id: String) -> Dictionary:
	var p: Dictionary = tx.extension(KEY, empty_state())
	var o := Draft.find(p.orders, order_id)
	if o.is_empty() or o.actorId != actor_id or not active(o): return Building.failure("FORBIDDEN", "不能取消此订单")
	o.status = "cancelled"; o.reason = "取消作业，释放尚未消费材料和工具；已消耗劳动保留"
	return Building.success()

func capacity_reserved(stock_id:String,item:String,excluding:String="",tx:RefCounted=null)->float:return Factory.capacity_reserved(self,stock_id,item,excluding,tx)
func visual_capacity_query()->Callable:
	# Exactly one synchronous render projection, using detached fields.
	var sources:Dictionary=Factory.visual_capacity_sources(self)
	return func(stock_id:String,item:String)->float:return Factory.sum_capacity_reservations(self,sources,stock_id,item,"")
func capacity_check(stock_id:String,items:Dictionary,excluding:String="",tx:RefCounted=null)->Dictionary:return Factory.capacity_check(self,stock_id,items,excluding,tx)
func advance(dt:float)->Dictionary:return Factory.advance(self,dt)
func factory_projection(actor_id:String="player")->Dictionary:return Factory.projection(self,actor_id)
func logistics_projection(actor_id:String="player")->Dictionary:return Factory.logistics_projection(self,actor_id)
func alert_projection(actor_id:String="player")->Dictionary:return Factory.alert_projection(self,actor_id)

func validate_extensions(facts_state:Dictionary,extension_overrides:Dictionary={})->Dictionary:return Factory.validate(self,facts_state,extension_overrides)
func prepare_actor_release(transitions:Array,staged_facts:Dictionary,pending_world_changes:Array)->Dictionary:return Factory.actor_release(self,transitions,staged_facts,pending_world_changes)
func actor_work_projection(actor_id:String)->Dictionary:
	var a:Dictionary=context.actor.call(actor_id)
	var intent:Variant=a.get("intent")
	if not intent is Dictionary or intent.get("owner")!="actions" or intent.get("kind") not in ["craft","study","harvest"] or not intent.get("held",true):return {}
	var o:=Draft.find(state().orders,str(intent.get("order_id","")))
	if o.is_empty() or not active(o):return {}
	var tx:=Draft.new(context)
	var problem:Variant=check(tx,o)
	var recipe:Dictionary=recipes.get(o.targetId,{})
	if o.kind=="craft" and ModuleRecipes.applies(recipe):return ModuleRecipes.work_projection(self,a,o,recipe,problem)
	if o.get("learning_source")=="teacher":
		var teacher:Dictionary=context.actor.call(str(o.teacher_id));var at:Vector3=Geometry.point(Geometry.location(teacher))+Vector3.UP
		return {"owner":"actions","work_domain":"production","kind":"study","learning_source":"teacher","teacher_id":o.teacher_id,"progress_seconds":o.elapsed,"duration_seconds":o.duration,"effective_work":problem==null and o.status=="active" and float(o.get("effective_work",0))>0,"effective_seconds":o.get("effective_work",0),"paused_reason":str(problem) if problem!=null else "","contact":{"position":[at.x,at.y,at.z],"normal":[0,1,0]}}
	var target:Dictionary=context.world.entity(str(o.targetId if o.kind=="harvest" else o.stationId if o.kind=="craft" else o.sourceId))
	if target.is_empty() or not target.get("bounds") is Dictionary:return {}
	var chest:=Geometry.point(Geometry.location(a))+Vector3(0,1.0,0);var box:=Geometry.aabb(target.bounds)
	var point:=chest.max(box.position).min(box.end)
	if o.kind=="craft":point.y=minf(box.end.y,maxf(box.position.y,0.9+float(target.position.y)))
	var outward:Vector3=chest-point
	if o.kind=="craft":outward=Vector3.UP # Actual horizontal 0.9m tabletop.
	if outward.length_squared()<0.000001:return {}
	return {"owner":"actions","work_domain":"production","kind":o.kind,"progress_seconds":o.elapsed,"duration_seconds":o.duration,"effective_work":problem==null and o.status=="active" and float(o.get("effective_work",0))>0,"effective_seconds":o.get("effective_work",0),"paused_reason":str(problem) if problem!=null else str(o.get("reason")) if o.get("reason")!=null else "","contact":{"position":[point.x,point.y,point.z],"normal":[outward.normalized().x,outward.normalized().y,outward.normalized().z]}}

func module_machine_projection(module_id:String)->Dictionary:return Factory.machine_visual(self,module_id)

func module_machine_visual(module: Dictionary) -> Dictionary:
	return Factory.machine_visual_for(self, module)

func residency_dependency_regions()->Array[String]:
	# Pure references only. A owns pinning, checkpoints, release and loading.
	var ids:Dictionary={};var observed:Dictionary=context.facts.call()
	for task:Dictionary in Factory.state(self,Factory.LOGISTICS).tasks:
		if str(task.get("actor_id","")).is_empty() or task.status not in ["collecting","delivering","blocked","cargo_held"]:continue
		var a:=Draft.find(observed.get("actors",[]),str(task.actor_id))
		if a.is_empty():continue
		ids[str(a.regionId)]=true
		for id:String in [str(task.source_id),str(task.destination_id)]:
			var stock:=Draft.find(observed.get("stocks",[]),id)
			if not stock.is_empty():ids[str(stock.location.regionId)]=true
		var intent:Variant=a.get("intent")
		if intent is Dictionary and intent.get("owner")=="actions" and intent.get("logistics_task_id")==task.id:
			for step:Dictionary in intent.get("steps",[]):
				if step.get("to") is Dictionary:ids[str(step.to.get("regionId",""))]=true
	var result:Array[String]=[]
	for id:String in ids:
		if not id.is_empty():result.append(id)
	result.sort();return result
