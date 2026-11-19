extends RefCounted
## Unified arrival/work planner. Called only by A's fixed clock; no timer/autoload.
const Draft = preload("res://scripts/actions/domain_draft.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Content = preload("res://scripts/runtime/content_definitions.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Workforce=preload("res://scripts/actions/workforce_executor.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const ModuleRecipes=preload("res://scripts/production/module_recipes.gd")
const ModuleContact=preload("res://scripts/modules/module_contact.gd")
var context: Dictionary
var building: RefCounted
var production: RefCounted
const ZoneSupply=preload("res://scripts/actions/zone_supply_executor.gd")
var _zone_runtime:WeakRef
var _modules:WeakRef
var rural_layout:Dictionary={}
var _motion_order_basis:Array=[]
var _motion_order_actors:Dictionary={}

func configure(value: Dictionary) -> void:
	context = preload("res://scripts/actions/domain_context.gd").isolate(value)
	_motion_order_basis.clear();_motion_order_actors.clear()
	if value.get("runtime") is RefCounted:_zone_runtime=weakref(value.runtime)
	rural_layout={}
	if value.world.identity().generatorVersion=="rural-1":rural_layout=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/rural_layout.json"))
	building = value.spatial
	production = value.get("services", {}).get("production")
	var modules:Variant=value.get("services",{}).get("modules")
	_modules=weakref(modules) if modules is RefCounted else null
	if production == null:
		production = Production.new()
		production.configure(value)

func zone_work_service()->Variant:
	var runtime_host:Variant=_zone_runtime.get_ref() if _zone_runtime!=null else null
	return runtime_host.domain_service("zonework") if runtime_host!=null else null

func module_service()->Variant:return _modules.get_ref() if _modules!=null else null

static func valid_id(value:Variant)->bool:
	return value is String and not value.is_empty() and value.length()<=512

static func valid_number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0

static func valid_location(value:Variant)->bool:
	if not value is Dictionary or not valid_id(value.get("regionId")):return false
	for key:String in ["x","y","z"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])):return false
	return true

func validate_intent(intent:Dictionary,actor_state:Dictionary={},_facts_state:Dictionary={})->Dictionary:
	# Schema only. Availability/continuous checks own references and permission;
	# restoring an interrupted order must not create or consume any resources.
	var version:Variant=intent.get("schema_version",0)
	var kind:Variant=intent.get("kind")
	if not valid_number(version) or float(version)!=floorf(float(version)) or int(version) not in [0,1] or intent.get("owner")!="actions":return Building.failure("INVALID_ACTION_INTENT","行动归属或版本无效")
	if kind not in ["search","care","zone_supply","walk","approach","module_approach","follow","guard","haul","door","structure","craft","study","harvest"]:return Building.failure("UNSUPPORTED_INTENT","未知行动类型")
	# These four legacy actions were emitted without IDs. Only explicit v0
	# retains that shape; every new action below has a stable v1 identity.
	if (int(version)==1 or kind not in ["search","follow","guard","haul"]) and not valid_id(intent.get("id")):return Building.failure("INVALID_ACTION_INTENT","行动身份缺失")
	if intent.has("id") and not valid_id(intent.id):return Building.failure("INVALID_ACTION_INTENT","行动身份无效")
	if not intent.get("held",true) is bool:return Building.failure("INVALID_ACTION_INTENT","行动暂停状态无效")
	for key:String in ["elapsed","duration","blocked_seconds","door_elapsed"]:
		if intent.has(key) and not valid_number(intent[key]):return Building.failure("INVALID_ACTION_INTENT","行动进度无效")
	if intent.has("duration") and (float(intent.duration)<=0 or float(intent.get("elapsed",0))>float(intent.duration)+0.00001):return Building.failure("INVALID_ACTION_INTENT","行动工时无效")
	if kind=="zone_supply" and not ZoneSupply.valid(self,intent):return Building.failure("INVALID_ACTION_INTENT","区域取料引用无效")
	if kind in ["zone_supply","walk","approach","module_approach","follow","guard","haul"]:
		if not intent.get("steps") is Array or not valid_number(intent.get("step")) or float(intent.step)!=floorf(float(intent.step)) or int(intent.step)>intent.steps.size():return Building.failure("INVALID_ACTION_INTENT","路径游标无效")
		for step:Variant in intent.steps:
			if not step is Dictionary or step.get("kind") not in ["move","open-door","stairs","cross-region"]:return Building.failure("INVALID_ACTION_INTENT","路径步骤无效")
			if step.kind=="open-door":
				if not valid_id(step.get("targetId")):return Building.failure("INVALID_ACTION_INTENT","门步骤身份无效")
			elif not valid_location(step.get("to")):return Building.failure("INVALID_ACTION_INTENT","路径坐标无效")
			if step.kind=="stairs" and (not valid_id(step.get("targetId")) or not valid_location(step.get("from"))):return Building.failure("INVALID_ACTION_INTENT","楼梯步骤无效")
		if intent.get("replan_after_door",false) and not valid_location(intent.get("path_goal")):return Building.failure("INVALID_ACTION_INTENT","重规划目标无效")
	if kind=="module_approach" and (not valid_id(intent.get("workforce_candidate_id")) or not str(intent.workforce_candidate_id).begins_with("module-project:")):return Building.failure("INVALID_ACTION_INTENT","模块行动引用无效")
	if kind in ["walk","approach","door","structure","craft","study","harvest"]:
		var request:Variant=intent.get("request")
		if not request is Dictionary or not valid_id(request.get("actor_id")) or not request.get("payload",{}) is Dictionary:return Building.failure("INVALID_ACTION_INTENT","行动请求无效")
		if not actor_state.is_empty() and request.actor_id!=actor_state.get("id"):return Building.failure("INVALID_ACTION_INTENT","行动角色引用不符")
		var expected:Array=["structure","craft","study","harvest","search"] if kind=="approach" else [kind]
		if request.get("kind") not in expected:return Building.failure("INVALID_ACTION_INTENT","行动请求类型不符")
		if request.has("command_id") and request.command_id!=intent.id:return Building.failure("INVALID_ACTION_INTENT","行动请求身份不符")
		if kind!="walk" and not valid_id(request.get("target_id")):return Building.failure("INVALID_ACTION_INTENT","行动目标缺失")
	if kind in ["structure","craft","study","harvest"] and not valid_id(intent.get("order_id")):return Building.failure("INVALID_ACTION_INTENT","订单身份无效")
	if kind=="search" and (not valid_id(intent.get("target_id")) or not valid_number(intent.get("elapsed"))):return Building.failure("INVALID_ACTION_INTENT","搜索目标或进度无效")
	if kind in ["door","care"] and (not valid_number(intent.get("target_version")) or float(intent.target_version)!=floorf(float(intent.target_version))):return Building.failure("INVALID_ACTION_INTENT","目标版本无效")
	if kind=="care":
		var cost:Variant=intent.get("cost")
		if intent.get("operation")!="prepare_bed" or not valid_id(intent.get("target_id")) or not valid_id(intent.get("source_id")) or not cost is Dictionary or cost.size()!=1 or not cost.has("cloth") or not valid_number(cost.cloth) or float(cost.cloth)!=2.0 or not valid_number(intent.get("elapsed")) or intent.get("duration")!=6.0:return Building.failure("INVALID_ACTION_INTENT","寝具行动描述无效")
	return Building.success()

func hold_descriptors(observed:Dictionary,extension_overrides:Dictionary={})->Array:
	var source:Variant=extension_overrides["r3:structure-orders"] if extension_overrides.has("r3:structure-orders") else context.world.extension("r3:structure-orders")
	var orders:Dictionary=source if source is Dictionary else {"orders":[]}
	var holds:Array=[]
	for o:Dictionary in orders.get("orders",[]):
		if not Production.active(o):continue
		var a:Dictionary=Draft.find(observed.get("actors",[]),str(o.actorId))
		if not hold_actor(a):continue
		holds.append({"schema_version":1,"owner":"actions","intent_id":str(o.id),"actor_id":str(a.id),"phase":"paused" if o.status=="blocked" else "active","source_id":str(o.sourceId) if o.get("sourceId")!=null else "","cost":o.get("cost",{}).duplicate(true),"tool_ids":[o.toolId] if o.get("toolId")!=null and not str(o.toolId).is_empty() else [],"use_target_id":str(o.targetId)})
	for a:Dictionary in observed.get("actors",[]):
		if not hold_actor(a) or not a.get("intent") is Dictionary:continue
		var intent:Dictionary=a.intent
		if intent.get("owner")=="actions" and intent.get("kind")=="zone_supply" and validate_intent(intent,a,observed).ok:
			var offer:Dictionary=intent.supply
			holds.append({"schema_version":1,"owner":"actions","intent_id":intent.id,"actor_id":a.id,"phase":"active" if intent.get("held",true) else "paused","source_id":offer.source_id,"cost":offer.items.duplicate(true),"tool_ids":offer.tool_ids.duplicate(),"use_target_id":""})
			continue
		if intent.get("owner")!="actions" or intent.get("kind") not in ["care","search","door"] or not validate_intent(intent,a,observed).ok:continue
		var target:String=str(intent.request.target_id) if intent.kind=="door" else str(intent.target_id)
		holds.append({"schema_version":1,"owner":"actions","intent_id":str(intent.get("id","legacy:"+str(a.id)+":"+str(intent.kind))),"actor_id":str(a.id),"phase":"active" if intent.get("held",true) else "paused","source_id":str(intent.get("source_id","")),"cost":intent.get("cost",{}).duplicate(true),"tool_ids":[],"use_target_id":target})
	return holds

static func hold_actor(a:Dictionary)->bool:
	return not a.is_empty() and float(a.get("hp",0))>0 and (a.id=="player" or (a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false)))

func prepare_actor_release(transitions:Array,observed:Dictionary,pending_world_changes:Array)->Dictionary:
	# A invokes this inside the SAME transaction before clearing intents. Read
	# the requested final B extensions, but keep their original authority CAS.
	# No tick/commit, no refund/reward, no new holding or lifecycle authority.
	var affected:Dictionary={}
	for transition:Variant in transitions:
		if not transition is Dictionary or not valid_id(transition.get("actor_id")) or transition.get("kind") not in ["incapacitated","removed","consent_revoked"]:return Building.failure("INVALID_LIFECYCLE_PLAN","角色清理转换无效")
		if affected.has(transition.actor_id) and affected[transition.actor_id]!=transition.kind:return Building.failure("INVALID_LIFECYCLE_PLAN","角色清理转换冲突")
		affected[transition.actor_id]=transition.kind
	var tx:=Draft.new(context);tx.initial=observed.duplicate(true);tx.staged=observed.duplicate(true)
	var pending:Dictionary={}
	for change:Variant in pending_world_changes:
		if not change is Dictionary:return Building.failure("INVALID_LIFECYCLE_PLAN","暂存世界操作无效")
		if change.get("op")!="extension.set" or change.get("id") not in [Production.KEY,"r3:structure-orders"]:continue
		var id:String=change.id
		if change.get("before_exists")!=context.world.has_extension(id) or change.get("before")!=context.world.extension(id):return Building.failure("CAS_MISMATCH","角色清理扩展已变化")
		if pending.has(id):return Building.failure("INVALID_LIFECYCLE_PLAN","暂存领域扩展重复")
		if not change.get("after") is Dictionary:return Building.failure("INVALID_LIFECYCLE_PLAN","角色清理所需扩展无效")
		pending[id]=change.after.duplicate(true)
	for key:String in [Production.KEY,"r3:structure-orders"]:
		var state:Variant=pending[key] if pending.has(key) else context.world.extension(key)
		if state==null:continue
		if not state is Dictionary or not state.get("orders") is Array:return Building.failure("INVALID_LIFECYCLE_PLAN","角色清理所需订单表无效")
		tx.extensions[key]=state.duplicate(true)
		for order:Variant in tx.extensions[key].orders:
			if not order is Dictionary:return Building.failure("INVALID_LIFECYCLE_PLAN","角色清理订单无效")
			if affected.has(order.get("actorId")) and Production.active(order):
				order.status="cancelled";order.reason="角色失能、移除或撤回同意，释放未消费的预留"
	var p:Dictionary=tx.extensions.get(Production.KEY,{})
	for id:String in affected:
		var a:=tx.actor(id)
		if affected[id]=="removed":
			if not a.is_empty():return Building.failure("INVALID_LIFECYCLE_PLAN","被移除角色仍在暂存事实中")
			for collection:String in ["tools","records"]:
				for item:Dictionary in p.get(collection,[]):
					if item.get("holderId")=="pack:"+id:return Building.failure("ACTOR_PROPERTY_TRANSFER_REQUIRED","先合法转移角色持有的工具与书册，再移除角色")
			if p.get("knowledge",{}).has(id):
				if not p.knowledge[id] is Array or not p.knowledge[id].is_empty():return Building.failure("ACTOR_KNOWLEDGE_RETIRE_REQUIRED","角色仍有已学知识，尚无可丢弃成长的退场规则")
				p.knowledge.erase(id)
		elif a.is_empty():return Building.failure("INVALID_LIFECYCLE_PLAN","清理角色不在暂存事实中")
		# A clears all owners' intent only AFTER every domain plan succeeds.
		# We remove the B-only suspended continuation, never the real carried
		# materials/tools or E's pending delivery cargo.
		if not a.is_empty():a.erase("suspended_work")
	return tx.result()

func availability(request: Dictionary) -> Dictionary:
	var result := prepare(request)
	if result.get("ok", false): result.world_changes = []; result.fact_changes = []
	return result

func prepare(request: Dictionary) -> Dictionary:
	var tx := Draft.new(context)
	return prepare_in(tx,request)

func prepare_in(tx:RefCounted,request:Dictionary)->Dictionary:
	# Shared-draft adapter for region work. Keep the original harvesting,
	# physical approaches, tool wear and ground-drop settlement authoritative.
	var actor_id := str(request.get("actor_id", ""))
	var a: Dictionary = tx.actor(actor_id)
	if a.is_empty() or float(a.get("hp", 0)) <= 0: return Building.failure("FORBIDDEN", "角色已失能")
	var kind := str(request.get("kind", ""))
	var payload: Dictionary = request.get("payload", {})
	if kind=="pickup":return pickup_in(tx,request)
	if kind in ["take", "deposit"]: return transfer(request)
	if kind == "search":
		var s: Dictionary = tx.stock(str(request.target_id))
		var problem: Variant = production.reach(a.id, str(request.target_id), s, "search", tx)
		if a.get("intent") != null: return Building.failure("BUSY", "先完成当前行动")
		if problem != null:
			if payload.get("direct",true) or not s.has("module_id"):return Building.failure("UNREACHABLE",problem)
			var plan:Dictionary=ZoneSupply.stock_path(self,tx,a,s,"search")
			if not plan.ok:return plan
			a.intent={"schema_version":1,"owner":"actions","id":request.get("command_id","preview"),"kind":"approach","steps":plan.steps,"step":0,"request":request.duplicate(true),"held":true}
			a.activity="靠近建筑搜索";return tx.result()
		a.intent = {"schema_version":1,"owner":"actions", "id":request.get("command_id","preview"), "kind":"search", "target_id":request.target_id, "elapsed":0.0, "held":true}
		a.activity = "搜索容器"
		return tx.result()
	if kind in ["cancel_work", "cancel_action"]:
		cancel_in(tx, a)
		return tx.result()
	if kind == "held":
		if a.get("intent") is Dictionary and a.intent.get("owner") == "actions": a.intent.held = bool(payload.get("held", false))
		return tx.result()
	if kind in ["move", "direct_move"]:
		var plan:=_plan_movement(request,a)
		if not plan.ok:return plan
		var active:Variant=a.get("intent")
		var keep:bool=kind=="direct_move" and actor_id=="player" and active is Dictionary and active.get("kind")=="harvest" and active.get("request",{}).get("payload",{}).get("click_harvest",false) and Interaction.player_tree_near(plan.location,context.world.entity(str(active.request.target_id)))
		if not keep:cancel_in(tx, a)
		set_location(a,plan.location)
		record_movement(tx,actor_id,plan.from,plan.location,plan.budget)
		return tx.result()
	if a.get("intent") != null: return Building.failure("BUSY", "先结束或取消当前行动")
	if kind in ["care","prepare_bed"]:
		var e:Dictionary=context.world.entity(str(request.get("target_id","")))
		var intent:Dictionary={"schema_version":1,"owner":"actions","kind":"care","operation":"prepare_bed","id":request.get("command_id","preview"),"target_id":request.get("target_id",""),"target_version":e.get("revision",-1),"source_id":payload.get("source_id","pack:"+str(a.id)),"cost":{"cloth":2},"elapsed":0.0,"duration":6.0,"held":payload.get("held",true)}
		var problem:Variant=check_care(tx,a,intent)
		if problem!=null:return Building.failure("UNAVAILABLE",problem)
		a.intent=intent;a.activity="清理并准备寝具"
		return tx.result()
	if kind == "walk":
		var plan := route(actor_id, Geometry.location(a), Geometry.location(request.get("destination", {})))
		if not plan.ok: return plan
		a.intent = {"schema_version":1,"owner": "actions", "id": request.get("command_id", "preview"), "kind": "walk", "steps": plan.steps, "step": 0, "request": request.duplicate(true), "held": true}
		a.activity = "前往目标"
		return tx.result()
	if kind == "door":
		var ready: Dictionary = building.prepare(request)
		if not ready.ok: return ready
		var resolved: Dictionary=request.duplicate(true)
		resolved.payload=payload.duplicate(true);resolved.payload.operation=ready.events[0].operation
		a.intent = {"schema_version":1,"owner": "actions", "id": request.get("command_id", "preview"), "kind": "door", "request": resolved, "target_version":building.instance(str(request.target_id)).version,"elapsed": 0.0, "duration": 0.4, "held": true}
		a.activity = "操作门"
		return tx.result()
	if kind in ["structure", "craft", "study", "harvest"]:
		var result: Dictionary = start_structure(tx, request) if kind == "structure" else production.start(tx, request)
		if not result.ok:
			var module_craft:bool=kind=="craft" and ModuleRecipes.applies(production.recipes.get(str(payload.get("recipe_id","")),{}))
			if payload.get("direct", true) and not module_craft:return result
			var destinations := work_points(request)
			for destination in destinations:
				var plan := route(actor_id, Geometry.location(a), destination)
				if not plan.ok: continue
				a.intent = {"schema_version":1,"owner": "actions", "id": request.get("command_id", "preview"), "kind": "approach", "steps": plan.steps, "step": 0, "request": request.duplicate(true), "held": payload.get("held", true)}
				a.activity = "前往作业点"
				return tx.result()
			return result
		var order_id := str(request.get("command_id", "preview")) + ":order"
		a.intent = {"schema_version":1,"owner": "actions", "id": request.get("command_id", "preview"), "kind": kind, "order_id": order_id, "request": request.duplicate(true), "held": payload.get("held", true)}
		a.activity = {"structure": "施工", "craft": "制作", "study": "学习", "harvest": "采伐"}[kind]
		return tx.result()
	return Building.failure("UNKNOWN_COMMAND", "行动类型尚未注册")

func _plan_movement(request:Dictionary,a:Dictionary)->Dictionary:
	var actor_id:String=str(a.id)
	var payload:Dictionary=request.get("payload",{})
	var destination := Geometry.location(request.get("destination", {}))
	var from := Geometry.location(a)
	if not [destination.x,destination.y,destination.z].all(func(v:Variant)->bool:return is_finite(float(v))) or Geometry.point(from).distance_to(Geometry.point(destination))>1.00001: return Building.failure("INVALID", "单次移动坐标或距离无效")
	var duration: Variant = payload.get("movement_dt", 0.1)
	if not duration is float and not duration is int: return Building.failure("INVALID", "移动时长必须是逻辑秒数")
	var budget := movement_budget(actor_id, float(duration), str(payload.get("movement_mode", "walk")))
	if not budget.ok: return budget
	var distance := Vector2(float(destination.x)-float(from.x),float(destination.z)-float(from.z)).length()
	if distance>float(budget.max_distance)+0.000001:
		if payload.has("movement_dt") or payload.has("movement_mode"): return Building.failure("MOVEMENT_BUDGET", "本次位移超过角色实际移动预算")
		# Legacy syntax remains usable, but cannot bypass the new clock budget.
		var fraction := float(budget.max_distance)/maxf(distance,0.000001)
		destination.x=lerpf(from.x,destination.x,fraction);destination.z=lerpf(from.z,destination.z,fraction)
	var moved := move_step(actor_id, from, destination)
	if not moved.ok: return moved
	return {"ok":true,"location":moved.location,"from":from,"budget":budget}

func prepare_idle_direct_move(request:Dictionary,actor:Dictionary)->Dictionary:
	# cancel_in also releases orders whose owner has no attached intent.
	if actor.get("intent")!=null or actor.has("suspended_work") or actor.has("migration_resume"):return {}
	if not context.world.has_method("extension_token"):return {}
	var keys:Array=[Production.KEY,"r3:structure-orders"]
	var basis:Array=[]
	for key:String in keys:basis.append(context.world.extension_token(key))
	if basis!=_motion_order_basis:
		var actors:Dictionary={}
		for key:String in keys:
			var state:Variant=context.world.extension(key)
			if state==null:return {} # Legacy cancel initializes a missing order extension.
			if not state is Dictionary or not state.get("orders") is Array:return {}
			for o:Variant in state.orders:
				if not o is Dictionary or not o.get("actorId") is String:return {}
				if Production.active(o):actors[o.actorId]=true
		_motion_order_basis=basis;_motion_order_actors=actors
	if _motion_order_actors.has(actor.id):return {}
	return _plan_movement(request,actor)

static func set_location(a: Dictionary, location: Dictionary) -> void:
	if a.has("position"): a.position = Geometry.display_location(location)
	else: a.merge(location, true)

func movement_budget(actor_id:String,dt:float,mode:String="walk")->Dictionary:
	if not is_finite(dt) or dt<=0 or dt>0.1 or mode not in ["walk","run"]: return Building.failure("INVALID", "移动步长或模式无效")
	if not context.get("movement_budget") is Callable: return Building.failure("UNAVAILABLE", "需要统一运行时提供移动能力")
	var budget:Dictionary=context.movement_budget.call(actor_id,dt,mode)
	if not budget.get("ok",false): return budget
	for key:String in ["speed","max_distance","stamina_max"]:
		var value:Variant=budget.get(key)
		if (not value is float and not value is int) or not is_finite(float(value)): return Building.failure("INVALID", "权威移动能力数值无效")
	if float(budget.speed)<=0 or float(budget.max_distance)<0 or float(budget.max_distance)>float(budget.speed)*dt+0.000001 or budget.get("mode") not in ["walk","run"]:return Building.failure("MOVEMENT_BUDGET", "当前没有合法移动预算")
	return budget

func record_movement(tx:RefCounted,actor_id:String,from:Dictionary,to:Dictionary,budget:Dictionary)->void:
	var distance:=Vector2(float(to.x)-float(from.x),float(to.z)-float(from.z)).length()
	if distance<=0.000001:return
	# A recomputes distance from committed facts and settles cost once. B only
	# reports accepted movement; doors, failed sweeps and zero steps emit nothing.
	tx.events.append({"kind":"actor-moved","actor_id":actor_id,"mode":budget.mode,"elapsed":distance/float(budget.speed)})

func below_stamina_cap(a:Dictionary)->bool:
	# This actor may already contain this fixed step's fatigue/need changes.
	# Query the same shared formula using staged facts, not a live ID lookup.
	var cap:Variant=Content.actor_effects(a).get("stamina_max")
	return (cap is float or cap is int) and is_finite(float(cap)) and float(a.stamina)+0.000001<float(cap)

func move_step(actor_id: String, from: Dictionary, to: Dictionary) -> Dictionary:
	if not [to.x, to.y, to.z].all(func(v: Variant) -> bool: return is_finite(float(v))): return Building.failure("INVALID", "移动坐标无效")
	if Geometry.point(from).distance_to(Geometry.point(to)) > 1.00001: return Building.failure("INVALID", "单次移动过远")
	var region: Dictionary = context.world.region_at(Geometry.json_point(Geometry.point(to)))
	if region.is_empty(): return Building.failure("UNREACHABLE", "目标在已生成世界之外")
	to.regionId = region.id
	var query: RefCounted = building.current_space()
	if from.regionId == to.regionId: return query.direct_move(actor_id, from, to)
	var permitted := false
	if Data.is_continuous_outdoor_generator(str(context.world.identity().get("generatorVersion",""))):
		if not context.world.has_method("continuous_outdoor_step"):return Building.failure("UNAVAILABLE","连续室外空间证明尚不可用")
		var continuity:Dictionary=context.world.continuous_outdoor_step(from,to)
		if not continuity.ok:return continuity
		permitted=true
	else:
		# Retain authored portals for the old city and the rural-1 save format.
		for exit in context.world.region(str(from.regionId)).get("exits", []):
			if exit.get("toRegionId") == to.regionId and Vector2(from.x - float(exit.position.x), from.z - float(exit.position.z)).length() <= float(exit.get("width", 2)): permitted = true
	if not permitted: return Building.failure("FORBIDDEN", "必须从真实地区连接处通行")
	var local_to := to.duplicate(true); local_to.regionId = from.regionId
	var local_from := from.duplicate(true); local_from.regionId = to.regionId
	# Both regions retain their real colliders and ground; use the same <=8cm
	# body sweep as ordinary motion rather than an unswept region transition.
	var source_proof:Dictionary=query.direct_move(actor_id,from,local_to)
	if not source_proof.ok:return source_proof
	var destination_proof:Dictionary=query.direct_move(actor_id,local_from,to)
	if not destination_proof.ok:return destination_proof
	var feet: Dictionary = query.standing_point(to)
	return Building.failure("UNSUPPORTED", "边界落脚点无支撑") if feet.is_empty() else {"ok": true, "location": feet}

func route(actor_id: String, from: Dictionary, to: Dictionary) -> Dictionary:
	if from.regionId == to.regionId: return building.current_space().route(actor_id, from, to)
	# Rural partitions are management boundaries. Prove the actual segment and
	# every body/door/support substep; authored city portals remain below.
	if Data.is_continuous_outdoor_generator(str(context.world.identity().get("generatorVersion",""))):
		var continuous:Dictionary=building.current_space().route(actor_id,from,to)
		if continuous.ok:return continuous
		return preload("res://scripts/buildings/continuous_navigation.gd").new().plan(building.current_space(),actor_id,from,to)
	var queue: Array = [{"id": from.regionId, "path": []}]
	var seen: Dictionary = {}
	var connections: Array = []
	while not queue.is_empty():
		var head: Dictionary = queue.pop_front()
		if seen.has(head.id): continue
		seen[head.id] = true
		if head.id == to.regionId: connections = head.path; break
		for exit in context.world.region(str(head.id)).get("exits", []):
			queue.append({"id": exit.toRegionId, "path": head.path + [{"from_region": head.id, "exit": exit}]})
	if connections.is_empty(): return Building.failure("UNREACHABLE", "地区之间没有已生成连接")
	var steps: Array = []
	var current := from
	for link in connections:
		var exit := Geometry.location(link.exit.position); exit.regionId = link.from_region
		var segment: Dictionary = building.current_space().route(actor_id, current, exit)
		if not segment.ok: return segment
		steps.append_array(segment.steps)
		var other: Dictionary = {}
		for back in context.world.region(str(link.exit.toRegionId)).get("exits", []):
			if back.toRegionId == link.from_region: other = Geometry.location(back.position); break
		if other.is_empty(): return Building.failure("UNREACHABLE", "地区连接缺少真实返回点")
		other.regionId = link.exit.toRegionId
		steps.append({"kind": "cross-region", "to": other})
		current = other
	var last: Dictionary = building.current_space().route(actor_id, current, to)
	if not last.ok: return last
	steps.append_array(last.steps)
	return {"ok": true, "steps": steps}

func work_points(request: Dictionary) -> Array:
	var kind := str(request.kind)
	if kind == "structure":
		var p: Dictionary = request.get("payload", {})
		var v: Dictionary = p.get("instance", {}) if p.get("kind") == "place" else building.instance(str(request.target_id))
		return building.current_space().use_points(v) if not v.is_empty() else []
	if kind == "craft":
		if ModuleRecipes.applies(production.recipes.get(str(request.get("payload",{}).get("recipe_id","")),{})):return ModuleRecipes.points(production,str(request.target_id),str(request.get("actor_id","player")))
		var station:Dictionary=building.instance(str(request.target_id))
		return Interaction.station_points(building.current_space(),station) if not station.is_empty() else []
	if kind == "study":
		if request.get("payload",{}).get("learning_source")=="teacher":return preload("res://scripts/production/production_teaching.gd").work_points(production,request)
		var record := Draft.find(production.state().records, str(request.get("payload", {}).get("record_id", request.target_id)))
		var stock: Dictionary = context.stock.call(str(record.get("holderId", "")))
		return [Geometry.location(stock)] if not stock.is_empty() else []
	if kind == "harvest":
		var tree: Dictionary = context.world.entity(str(request.target_id))
		return Interaction.tree_points(building.current_space(),tree,request.get("actor_id")=="player") if not tree.is_empty() else []
	return []

func pickup_in(tx:RefCounted,request:Dictionary)->Dictionary:
	# Ground pickup is an ordinary authoritative transfer, with exact current
	# ownership, wall, range, reservation and capacity checks at settlement.
	var id:String=str(request.get("target_id",""))
	var entity:Dictionary=context.world.entity(id)
	var stock:Dictionary=tx.stock(id)
	var actor:Dictionary=tx.actor(str(request.get("actor_id","")))
	if entity.get("kind")!="container" or not entity.get("data",{}).get("dropped",false) or stock.is_empty() or not stock.get("searched",false):return Building.failure("NOT_GROUND_DROP","这不是可拾取的地面物资")
	var automatic:bool=request.get("payload",{}).get("automatic",false)
	if not automatic and actor.get("intent")!=null:return Building.failure("BUSY","先完成或取消当前作业")
	if automatic and (stock.get("owner")!=null or Geometry.point(actor).distance_to(Geometry.point(Geometry.location(stock)))>1.8):return Building.failure("PICKUP_RANGE","自动拾取只收取身旁的掉落物")
	var selected:=_pickup_items(tx,id,str(actor.id),stock.get("items",{}),automatic)
	if selected.is_empty():return Building.failure("NO_PICKUP_SPACE","物资已拾完、被预留或背包无法容纳")
	var result:Dictionary=transfer_in(tx,str(actor.id),id,"pack:"+str(actor.id),{"items":selected})
	return tx.result() if result.ok else result

const AUTO_PICKUP_ITEMS := ["log","scrap","cloth","axe_head","tool_handle","medicine"]

func _pickup_items(tx:RefCounted,id:String,actor_id:String,limit:Dictionary,automatic:bool)->Dictionary:
	var selected:Dictionary={}
	var keys:Array=limit.keys();keys.sort()
	for item:String in keys:
		if automatic and item not in AUTO_PICKUP_ITEMS:continue
		var count:float=minf(float(limit[item]),production.available_for(id,item,"work","",tx))
		if count<=0:continue
		# Pick only a fitting quantity; leave every remainder on the ground.
		var step:float=float(Content.item_definition(item).get("step",1.0))
		var low:int=0;var high:int=mini(64000,int(floor(count/step+0.000001)))
		if automatic:high=mini(high,3)
		while low<high:
			var middle:int=int((low+high+1)/2)
			var candidate:Dictionary=selected.duplicate();candidate[item]=middle*step
			if production.capacity_check("pack:"+actor_id,candidate,"",tx).ok:low=middle
			else:high=middle-1
		if low>0:selected[item]=low*step
		if selected.size()>=8:break
	return selected


func transfer(request: Dictionary) -> Dictionary:
	var tx := Draft.new(context)
	var a: Dictionary = tx.actor(str(request.actor_id))
	var payload: Dictionary = request.get("payload", {})
	var from_id := str(request.target_id) if request.kind == "take" else "pack:" + str(a.id)
	var to_id := "pack:" + str(a.id) if request.kind == "take" else str(request.target_id)
	var result := transfer_in(tx,str(a.id),from_id,to_id,payload)
	return tx.result() if result.ok else result

func transfer_in(tx: RefCounted, actor_id: String, from_id: String, to_id: String, payload: Dictionary, reservation_id:String="", fresh_harvest:bool=false) -> Dictionary:
	var a: Dictionary = tx.actor(actor_id)
	if a.is_empty() or from_id == to_id: return Building.failure("INVALID", "转移双方必须是实际不同容器")
	if not payload.get("items",{}) is Dictionary or not payload.get("tool_ids",[]) is Array: return Building.failure("INVALID", "物资或工具清单无效")
	var from: Dictionary = tx.stock(from_id); var to: Dictionary = tx.stock(to_id)
	for stock in [from, to]:
		# The same transaction has already verified contact with the tree.
		if fresh_harvest and stock.get("id")==from_id and stock.get("owner")==null:continue
		var reason: Variant = production.reach(a.id, str(stock.get("id", "")), stock, "handoff" if str(stock.get("id", "")).begins_with("pack:") else "stock", tx)
		if reason != null: return Building.failure("FORBIDDEN", reason)
	var counts: Dictionary = payload.get("items", {})
	var life:bool=payload.get("purpose")=="life"
	if life:
		for item:Variant in counts:
			var definition:Dictionary=Content.consumable_definition(str(item))
			if definition.get("kind") not in ["eat","drink"] or not (counts[item] is int or counts[item] is float) or float(counts[item])>1:return Building.failure("INVALID_LIFE_TRANSFER","生活储备仅供实际单份安全饮食取用")
	var ids: Array = payload.get("tool_ids", [])
	if ids.size() != Draft.unique(ids).size(): return Building.failure("INVALID", "工具不能重复选择")
	for item in counts:
		if not counts[item] is int and not counts[item] is float: return Building.failure("INVALID", "物资数量必须是数值")
		var count := float(counts[item])
		if count <= 0 or not Content.quantity_valid(str(item),count,true): return Building.failure("INVALID", "数量不符合物品单位或旧库存数量规则")
		if production.available_for(from_id,str(item),"life" if life else "work",reservation_id,tx) < count: return Building.failure("RESERVED", "数量不足、物品已被作业预留或属于生活保留量")
	var capacity:Dictionary=production.capacity_check(to_id,counts,reservation_id,tx)
	if not capacity.ok:return capacity
	var p: Dictionary = tx.extension(Production.KEY, Production.empty_state())
	for id in ids:
		var t := Draft.find(p.tools, str(id))
		if t.is_empty() or t.holderId != from_id or production.tool_unavailable(str(id), reservation_id, tx): return Building.failure("RESERVED", "工具不存在、物主变化或正在作业")
	for record in p.records:
		if record.holderId != from_id or float(counts.get(record.itemId, 0)) <= 0: continue
		if p.orders.any(func(o: Dictionary) -> bool: return Production.active(o) and o.kind == "study" and o.targetId == record.id): return Building.failure("RESERVED", "正在阅读的书不能移动")
		# A record refers to one physical source item. It follows only when no copy stays.
		if float(from.items.get(record.itemId, 0)) - float(counts[record.itemId]) <= 0:
			record.holderId = to_id
			for o in p.orders:
				if o.kind == "study" and o.targetId == record.id and not Production.active(o): o.sourceId = to_id
	if not tx.stock_delta(from_id, counts, -1) or not tx.stock_delta(to_id, counts): return Building.failure("INVALID", "转移结算失败")
	for id in ids: Draft.find(p.tools, str(id)).holderId = to_id
	tx.events.append({"kind": "inventory-transfer", "actor_id": a.id, "source_id": from_id, "output_id": to_id, "items": counts, "tool_ids": ids})
	return Building.success()

func start_structure(tx: RefCounted, request: Dictionary) -> Dictionary:
	var orders: Dictionary = tx.extension("r3:structure-orders", {"version": 1, "orders": []})
	var p: Dictionary = tx.extension(Production.KEY, Production.empty_state())
	var a: Dictionary = tx.actor(str(request.actor_id))
	var v: Dictionary = request.get("payload", {})
	var kind := str(v.get("kind", ""))
	if kind not in ["place", "remove", "damage", "repair", "move"]: return Building.failure("INVALID", "施工动作无效")
	var target: Dictionary = v.get("instance", {}) if kind == "place" else building.instance(str(request.target_id))
	if target.is_empty(): return Building.failure("MISSING", "实际构件不存在")
	for o in orders.orders + p.orders:
		if Production.active(o) and (o.actorId == a.id or o.targetId == request.target_id): return Building.failure("RESERVED", "角色或构件已被订单预留")
	var d: Dictionary = building.geometry.definition(target)
	if d.is_empty(): return Building.failure("INVALID", "未知建筑定义")
	if kind == "place" and not d.get("knowledge",[]).all(func(k:String)->bool:return p.knowledge.get(a.id,[]).has(k)): return Building.failure("KNOWLEDGE", "尚未学会该设施的建造方法")
	if kind == "place" and (target.id != request.target_id or int(target.get("version", -1)) != 0 or float(target.hp) != float(d.maxHp) or target.get("protected", false) or (target.has("door") and (target.door.open or target.door.locked or target.door.blocked))): return Building.failure("INVALID", "新建构件必须使用目录初始状态")
	if kind != "place" and target.get("protected", false): return Building.failure("FORBIDDEN", "关键结构不能拆改")
	var order := {"id": str(request.get("command_id", "preview")) + ":order", "actorId": a.id, "kind": kind, "targetId": request.target_id,
		"instance": target.duplicate(true) if kind == "place" else null, "destination": v.get("destination"), "sourceId": v.get("source_id"), "outputId": v.get("output_id"), "toolId": v.get("tool_id"),
		"targetVersion": null if kind == "place" else target.version, "cost": d.cost.duplicate(true) if kind == "place" else {"timber": 1, "scrap": 1} if kind == "repair" else {},
		"elapsed": 0.0, "seconds": d.seconds if kind == "place" else 2.0 if kind == "damage" else 6.0 if kind == "repair" else 5.0, "status": "active", "reason": null}
	if kind == "move":
		if d.kind != "cabinet" or not order.destination is Dictionary: return Building.failure("INVALID", "只支持在同层附近搬移储物柜")
		var next := target.duplicate(true)
		next.position = order.destination.get("position", target.position).duplicate(true)
		next.quarterTurn = order.destination.get("quarterTurn", target.quarterTurn)
		order.destination = next
		order.origin = {"position": target.position.duplicate(true), "quarterTurn": target.quarterTurn}
	var reason: Variant = check_structure(tx, order)
	if reason != null: return Building.failure("UNAVAILABLE", reason)
	if kind in ["place","move"]:
		# Preview and admission validate the exact same destination as completion.
		# Completion still revalidates current occupants, terrain and permissions;
		# this is not a reusable ticket and reserves no materials during preview.
		var valid: Dictionary = building.prepare_edit([target.id] if kind=="move" else [], [order.destination] if kind=="move" else [target], tx.staged, tx.extensions.get("r3:structures",{}))
		if not valid.ok: return valid
	orders.orders.append(order)
	return Building.success()

func check_structure(tx: RefCounted, o: Dictionary) -> Variant:
	var a: Dictionary = tx.actor(str(o.actorId))
	var target: Dictionary = o.instance if o.kind == "place" else building.instance(str(o.targetId))
	if a.is_empty() or float(a.get("hp", 0)) <= 0 or target.is_empty(): return "角色失能或构件不存在"
	if a.id != "player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false)): return "住户尚未自愿加入或已撤回工作同意"
	if o.kind != "place" and int(target.version) != int(o.targetVersion): return "构件状态已经变化"
	var reason: Variant = building.permission(a.id, target.id, o.kind, target, tx.staged)
	if reason != null: return reason
	reason = building.can_use(a.id, target, {}, tx.staged)
	if reason != null: return reason
	var d: Dictionary = building.geometry.definition(target)
	if o.kind == "repair" and float(target.hp) >= float(d.maxHp): return "构件无需维修"
	if o.kind == "damage" and float(target.hp) <= 0: return "构件已经毁坏"
	if o.kind == "move":
		if target.regionId != o.destination.regionId or target.get("storeyId") != o.destination.get("storeyId") or Geometry.point(target.position).distance_to(Geometry.point(o.destination.position)) > 2.25: return "重物只能在同层附近搬移"
		var can_reach := false
		for at in building.current_space().use_points(o.destination):
			if Geometry.point(Geometry.location(a)).distance_to(Geometry.point(at)) <= 2.25 and building.current_space().contact_clear(Geometry.location(a), at, str(target.id)): can_reach = true
		if not can_reach: return "搬移目的地不可达"
	for id in [o.sourceId, o.outputId]:
		if id != null:
			reason = production.reach(a.id, str(id), tx.stock(str(id)), "stock", tx)
			if reason != null: return reason
	if not o.cost.is_empty() and o.sourceId == null: return "必须指定真实材料来源"
	for item in o.cost:
		var stock: Dictionary = tx.stock(str(o.sourceId))
		if stock.is_empty() or float(stock.items.get(item, 0)) - production.reserved(str(o.sourceId), item, str(o.id), tx) < float(o.cost[item]): return "材料不足或被预留：" + item
	if o.kind == "remove":
		if o.outputId == null: return "必须指定真实回收容器"
		for s in tx.staged.get("stocks", []):
			if s.id == target.id or s.get("structureId") == target.id:
				var p: Dictionary = tx.extension(Production.KEY, Production.empty_state())
				if s.items.values().any(func(n: Variant) -> bool: return float(n) > 0) or p.tools.any(func(t: Dictionary) -> bool: return t.holderId == s.id): return "请先清空柜内物资和工具"
	if d.get("tool") != null:
		var p: Dictionary = tx.extension(Production.KEY, Production.empty_state())
		var tool := Draft.find(p.tools, str(o.toolId))
		if tool.is_empty() or (float(o.elapsed) < float(o.seconds) - 0.00001 and float(tool.durability) <= 0) or float(production.tool_qualities(tool).get(d.tool, 0)) < 1: return "缺少可用的对应工具"
		if production.tool_unavailable(str(o.toolId), str(o.id), tx): return "工具正在被其他作业或地形劳动预留"
		reason = production.reach(a.id, str(tool.holderId), tx.stock(str(tool.holderId)), "stock", tx)
		if reason != null: return reason
	return null

func work_structure(tx: RefCounted, order_id: String, dt: float) -> Dictionary:
	var orders: Dictionary = tx.extension("r3:structure-orders", {"version": 1, "orders": []})
	var o := Draft.find(orders.orders, order_id)
	if o.is_empty() or not Production.active(o): return Building.failure("MISSING", "施工订单不存在")
	var reason: Variant = check_structure(tx, o)
	if reason != null: o.status = "blocked"; o.reason = reason; return Building.success()
	var a: Dictionary = tx.actor(str(o.actorId))
	var p: Dictionary = tx.extension(Production.KEY, Production.empty_state())
	var t := Draft.find(p.tools, str(o.toolId))
	var worked := minf(dt, minf(float(o.seconds) - float(o.elapsed), float(a.stamina) / 1.2))
	var wear_enabled: bool = preload("res://scripts/runtime/tool_wear_policy.gd").enabled(context.world)
	if wear_enabled and not t.is_empty(): worked = minf(worked, float(t.durability) / 0.15)
	if worked <= 0.000001 and float(o.elapsed) < float(o.seconds) - 0.000001: o.status = "blocked"; o.reason = "体力或工具耐久不足"; return Building.success()
	a.stamina = maxf(0, float(a.stamina) - worked * 1.2)
	if wear_enabled and not t.is_empty(): t.durability = maxf(0, float(t.durability) - worked * 0.15)
	o.effective_work=worked
	o.elapsed = minf(float(o.seconds), float(o.elapsed) + worked); o.status = "active"; o.reason = null
	if float(o.seconds) - float(o.elapsed) > 0.000001: return Building.success()
	var target: Dictionary = building.instance(str(o.targetId))
	var added: Array = []; var removed: Array = []
	if o.kind == "place": added = [o.instance]
	elif o.kind == "remove": removed = [o.targetId]
	else:
		var next: Dictionary = (o.destination if o.kind == "move" else target).duplicate(true)
		next.version = int(target.version) + 1
		if o.kind == "repair": next.hp = building.geometry.definition(target).maxHp
		if o.kind == "damage":
			next.hp = maxf(0, float(next.hp) - 60)
			if next.hp == 0 and next.has("door"): next.door.open = true; next.door.locked = false; next.door.blocked = false
		added = [next]; removed = [o.targetId]
	var edit: Dictionary = building.prepare_edit(removed, added, tx.staged, tx.extensions.get("r3:structures", {}))
	if not edit.ok: o.status = "blocked"; o.reason = edit.reason; return Building.success()
	if not o.cost.is_empty() and not tx.stock_delta(str(o.sourceId), o.cost, -1): return Building.failure("MATERIALS", "施工材料结算失败")
	if o.kind == "remove":
		var d: Dictionary = building.geometry.definition(target)
		var salvage: Dictionary = {}
		for item in d.salvage: salvage[item] = floor(float(d.salvage[item]) * float(target.hp) / float(d.maxHp))
		if not tx.stock_delta(str(o.outputId), salvage): return Building.failure("MATERIALS", "回收容器结算失败")
		for s in tx.staged.stocks.duplicate():
			if s.id == target.id or s.get("structureId") == target.id: tx.staged.stocks.erase(s)
	if o.kind == "move":
		for s in tx.staged.stocks:
			if s.id == target.id or s.get("structureId") == target.id: s.location = Geometry.location(o.destination)
	if o.kind == "place" and building.geometry.definition(o.instance).id=="cabinet":
		if not tx.stock(str(o.targetId)).is_empty():return Building.failure("DUPLICATE_STOCK","新储物柜身份已被占用")
		tx.staged.stocks.append({"id":o.targetId,"structureId":o.targetId,"location":Geometry.location(o.instance),"owner":o.instance.get("owner"),"searched":true,"items":{}})
	for c in edit.world_changes:
		if c.op == "extension.set": tx.extensions[c.id] = c.after
		else: tx.extra.append(c)
	o.status = "completed"
	tx.events.append({"kind": "structure-completed", "actor_id": a.id, "order_id": o.id, "target_id": o.targetId, "operation": o.kind, "origin": o.get("origin")})
	return Building.success()

func cancel_in(tx: RefCounted, a: Dictionary) -> void:
	var intent:Variant=a.get("intent");var modules:Variant=module_service()
	if intent is Dictionary and intent.get("owner")=="actions" and intent.get("kind")=="module_approach" and modules!=null:modules.release_workforce_in(tx,str(a.id),str(intent.get("workforce_candidate_id","")))
	for key in [Production.KEY, "r3:structure-orders"]:
		var state: Dictionary = tx.extension(key, Production.empty_state() if key == Production.KEY else {"version": 1, "orders": []})
		for o in state.orders:
			if o.actorId == a.id and Production.active(o): o.status = "cancelled"; o.reason = "主动取消，释放尚未消费的材料和工具"
	a.erase("suspended_work")
	a.intent = null; a.activity = "自由行动"

func needs_action(a: Dictionary) -> String:
	return "drink" if float(a.get("thirst",100)) < 25 and float(a.pack.get("water",0)) >= 1 else "eat" if float(a.get("hunger",100)) < 25 and float(a.pack.get("food",0)) >= 1 else "rest" if float(a.get("stamina",100)) < 5 else ""

func needs_intent(tx:RefCounted,a:Dictionary,kind:String)->void:
	# A owns the same start/continuous/completion rules and clock as the player.
	# Supply this tick's actor and staged facts, never construct a private life
	# intent or bypass a reservation created earlier in this same transaction.
	if not context.get("prepare_life") is Callable:a.activity="生活运行时尚不可用";return
	var request:Dictionary={"command_id":"npc-needs:"+str(a.id)+":"+str(int(context.clock.call()*10)),"actor_id":a.id,"kind":kind,"target_id":"","payload":{}}
	var prepared:Dictionary=context.prepare_life.call(request,a,tx.staged)
	if not prepared.ok:a.activity=str(prepared.get("reason","生活行动暂不可用"));return
	if not prepared.get("world_changes",[]).is_empty():a.activity="生活草案包含尚不支持的世界操作";return
	for change:Dictionary in prepared.get("fact_changes",[]):
		if change.get("collection")=="actors" and change.get("id")==a.id and change.get("after") is Dictionary:a.merge(change.after,true)
	tx.events.append_array(prepared.get("events",[]))
	a.activity="自主休息" if kind=="rest" else "自主饮水" if kind=="drink" else "自主进食"

func npc_work_transition(tx: RefCounted, a: Dictionary) -> bool:
	var active: Variant = a.get("intent")
	var saved: Variant = a.get("suspended_work")
	var job := str(a.get("job","follow"))
	if saved is Dictionary:
		if active != null:return false
		var need := needs_action(a)
		if not need.is_empty():needs_intent(tx,a,need);return true
		if job == "rest":
			if below_stamina_cap(a):needs_intent(tx,a,"rest")
			else:a.activity="作业已暂停，等待继续安排"
			return true
		if job != saved.get("job") or str(a.get("work_target_id","")) != saved.get("target_id"):
			cancel_in(tx,a)
			return false
		a.intent=saved.intent.duplicate(true);a.erase("suspended_work");a.activity="休息后继续原作业"
		return true
	if not active is Dictionary or active.get("owner")!="actions" or active.get("kind") not in ["approach","craft","study","structure","harvest","haul"]:return false
	var work_kind := str(active.get("request",{}).get("kind",active.get("kind")))
	var expected_job := "gather" if work_kind in ["harvest","haul"] else "craft"
	var work_target := str(active.get("work_target_id",active.get("request",{}).get("target_id",a.get("work_target_id",""))))
	# A rest assignment has no work target. Keep the actual order's target,
	# rather than interpreting the cleared assignment as a different task.
	if job not in [expected_job,"rest"] or (job!="rest" and str(a.get("work_target_id","")) != work_target):
		cancel_in(tx,a)
		return true
	var need := needs_action(a)
	if job != "rest" and need.is_empty():return false
	a.suspended_work={"intent":active.duplicate(true),"job":expected_job,"target_id":work_target}
	a.intent=null
	if job=="rest" and need.is_empty() and below_stamina_cap(a):need="rest"
	if not need.is_empty():needs_intent(tx,a,need)
	else:a.activity="作业已暂停，等待继续安排"
	return true

func advance(dt: float) -> Dictionary:
	if not is_finite(dt) or dt <= 0 or dt > 1: return Building.failure("INVALID", "必须由统一时钟提供合法步长")
	var tx := Draft.new(context)
	var observed:Dictionary=tx.observe_facts()
	if observed.get("scenario")=="factory-settlement-r34":
		# Same-step facts, including withdrawals/HP/suspended work. Factory NPC
		# decisions belong to E; only enter the writable legacy action loop when
		# that exact loop can execute or clear an action. No result is cached.
		var pending:bool=false
		for a:Dictionary in observed.get("actors",[]):
			var intent:Variant=a.get("intent")
			var own:bool=intent is Dictionary and intent.get("owner")=="actions"
			if float(a.get("hp",0))<=0 or (a.id!="player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false))):
				if own or a.has("suspended_work"):pending=true;break
			elif own and intent.get("held",true):pending=true;break
		if not pending:return tx.result()
	for a in tx.staged.get("actors", []):
		if float(a.get("hp", 0)) <= 0 or (a.id != "player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false))):
			if (a.get("intent") is Dictionary and a.intent.get("owner") == "actions") or a.has("suspended_work"): cancel_in(tx,a); a.activity = "失能或撤回同意，作业已中断"
			continue
		var factory_scenario:bool=tx.staged.get("scenario")=="factory-settlement-r34"
		if not factory_scenario and a.id != "player" and npc_work_transition(tx,a):continue
		var intent: Variant = a.get("intent")
		if not intent is Dictionary or intent.get("owner") != "actions":
			if not factory_scenario and intent == null and a.id != "player": prepare_npc(tx, a)
			continue
		if not intent.get("held", true): continue
		var kind := str(intent.kind)
		if kind == "search":
			var s: Dictionary = tx.stock(str(intent.target_id))
			var problem: Variant = production.reach(a.id, str(intent.target_id), s, "search", tx)
			if problem != null: a.intent = null; a.activity = problem; continue
			intent.elapsed = float(intent.elapsed) + dt
			if float(intent.elapsed) >= 1.0 - 0.000001:
				s.searched=true;a.intent=null;a.activity="搜索完成"
				if s.has("module_id"):
					var modules:Dictionary=tx.extension("r34:modules",{"instances":[]})
					var module:=Draft.find(modules.instances,str(s.module_id))
					if not module.is_empty():module.discovered=true
		elif kind == "care":
			var problem:Variant=check_care(tx,a,intent)
			if problem!=null:a.activity=problem;continue
			var worked:=minf(dt,minf(float(intent.duration)-float(intent.elapsed),float(a.stamina)/0.5))
			intent.elapsed=float(intent.elapsed)+worked;a.stamina=maxf(0,float(a.stamina)-worked*0.5)
			if float(intent.elapsed)+0.000001<float(intent.duration):continue
			if not tx.stock_delta(str(intent.source_id),intent.cost,-1):return Building.failure("MATERIALS","寝具材料结算失败")
			var before:Dictionary=context.world.entity(str(intent.target_id));var after:=before.duplicate(true)
			after.data.prepared=true;after.revision=int(before.get("revision",0))+1
			tx.extra.append({"op":"entity.put","id":before.id,"before_exists":true,"before":before,"after":after})
			tx.events.append({"kind":"bed-prepared","actor_id":a.id,"target_id":before.id})
			a.intent=null;a.activity="寝具已实际铺好"
		elif kind in ["zone_supply", "walk", "approach", "module_approach", "follow", "guard", "haul"]:
			advance_path(tx, a, dt)
		elif kind == "door":
			intent.elapsed = float(intent.elapsed) + dt
			if float(intent.elapsed) + 0.000001 < 0.4: continue
			if building.instance(str(intent.request.target_id)).get("version")!=intent.get("target_version"):a.intent=null;a.activity="门状态已变化，请重新操作";continue
			var r: Dictionary = building.prepare_door(intent.request, tx.extensions.get("r3:structures", {}), tx.staged)
			if not r.ok: a.intent = null; a.activity = r.reason; continue
			for c in r.world_changes:
				if c.op == "extension.set": tx.extensions[c.id] = c.after
				else: tx.extra.append(c)
			a.stamina = maxf(0, float(a.stamina) - 0.25)
			tx.events.append_array(r.events)
			a.intent = null; a.activity = "自由行动"
		elif kind in ["structure", "craft", "study", "harvest"]:
			if kind=="harvest" and stop_cancelled_zone_harvest(tx,a,intent):continue
			var result: Dictionary = work_structure(tx, str(intent.order_id), dt) if kind == "structure" else production.work(tx, str(intent.order_id), dt)
			if not result.ok: a.activity = result.reason; continue
			var state: Dictionary = tx.extensions.get("r3:structure-orders" if kind == "structure" else Production.KEY, {})
			var o := Draft.find(state.get("orders", []), str(intent.order_id))
			if o.get("status") == "completed":
				if a.id=="player" and kind=="harvest" and intent.request.get("payload",{}).get("pickup_yield",false):
					var drop_id:=str(o.outputId)
					var harvested:Dictionary=production.tree_state(state,str(o.targetId)).get("yield",{})
					var picked:=_pickup_items(tx,drop_id,"player",harvested,true) if tx.stock(drop_id).get("owner")==null else {}
					if not picked.is_empty() and not transfer_in(tx,"player",drop_id,"pack:player",{"items":picked},"",true).ok:picked={}
					var left:bool=harvested.keys().any(func(item:String)->bool:return float(picked.get(item,0))<float(harvested[item]))
					tx.events.append({"kind":"player-harvest-pickup","items":picked,"left":left})
				if a.id != "player" and kind == "harvest":
					var tree: Dictionary = production.tree_state(tx.extension(Production.KEY,Production.empty_state()),str(o.targetId))
					var delivery_id: String = str(intent.get("request",{}).get("payload",{}).get("delivery_id",a.get("work_payload",{}).get("delivery_id","")))
					if not delivery_id.is_empty(): a.pending_delivery = {"source_id":o.outputId,"destination_id":delivery_id,"items":tree.get("yield",{}).duplicate(true),"phase":"collect"}
				a.intent = null; a.activity = "作业完成"
			elif o.get("status") == "blocked":
				if kind=="harvest" and production.chapter_one and _worn_harvest_tool(state,o):
					# Keep the tree's real accumulated work and release its tool hold.
					# A zero-durability axe can then be repaired at a real workbench.
					production.cancel(tx,str(a.id),str(o.id));a.intent=null;a.activity="斧头已损坏；到作坊整备后可继续采伐"
					tx.events.append({"kind":"factory-harvest-tool-worn","actor_id":a.id,"target_id":o.targetId})
				else:a.activity=o.reason
	return tx.result()

static func _worn_harvest_tool(state:Dictionary,order:Dictionary)->bool:
	for id:Variant in order.get("toolIds",[]):
		var tool:=Draft.find(state.get("tools",[]),str(id))
		if not tool.is_empty() and float(tool.get("durability",0))<=0:return true
	return false

func check_care(tx:RefCounted,a:Dictionary,intent:Dictionary)->Variant:
	var e:Dictionary=context.world.entity(str(intent.target_id))
	if e.is_empty() or not e.get("data",{}).get("sleeping",false):return "这里不是实际睡位"
	if e.data.get("prepared",false):return "睡位已经整理好"
	if production.use_reserved(str(e.id),str(intent.id),tx):return "睡位正被其他行动预留"
	if e.get("revision",0)!=intent.target_version:return "睡位状态已变化"
	if a.id!="player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false)):return "住户未同意整理"
	var access:Variant=production.reach(str(a.id),str(e.id),Geometry.location(e),"care",tx)
	if access!=null:return access
	var source:Dictionary=tx.stock(str(intent.source_id))
	access=production.reach(str(a.id),str(intent.source_id),source,"stock",tx)
	if access!=null:return access
	for item in intent.cost:
		if float(source.items.get(item,0))-production.work_reserved(str(intent.source_id),str(item),str(intent.id),tx)<float(intent.cost[item]):return "需要实际的两份布料并保留作业用量"
	return null

func try_module_arrival(tx:RefCounted,a:Dictionary,intent:Dictionary)->bool:
	var modules:Variant=module_service()
	if modules==null:return false
	var state:Dictionary=modules.state(tx.extensions)
	var project:=Draft.find(state.projects,str(intent.get("workforce_candidate_id","")).trim_prefix("module-project:"))
	var module:=Draft.find(state.instances,str(project.get("module_id","")))
	if module.is_empty() or not ModuleContact.near(building.current_space(),Geometry.location(a),module):return false
	# Nearness alone cannot settle work. Prove the same real holds, tools,
	# source contact and permission in an isolated draft before changing intent.
	var probe:RefCounted=Workforce.draft(self,tx.staged,tx.extensions)
	var ready:Dictionary=modules.claim_workforce_in(probe,str(a.id),str(intent.workforce_candidate_id),str(intent.id),true)
	if not ready.ok:return false
	return modules.claim_workforce_in(tx,str(a.id),str(intent.workforce_candidate_id),str(intent.id),true).ok

func try_near_approach(tx:RefCounted,a:Dictionary,intent:Dictionary)->bool:
	var request:Dictionary=intent.request
	if request.kind=="search":
		var stock:Dictionary=tx.stock(str(request.target_id))
		if not stock.has("module_id") or production.reach(str(a.id),str(request.target_id),stock,"search",tx)!=null:return false
		intent.kind="search";intent.target_id=request.target_id;intent.elapsed=0.0;a.activity="搜索容器";return true
	if request.kind!="craft" or not ModuleRecipes.applies(production.recipes.get(str(request.get("payload",{}).get("recipe_id","")),{})):return false
	var module:Dictionary=ModuleRecipes.module(production,str(request.target_id),tx)
	if module.is_empty() or not ModuleContact.near(building.current_space(),Geometry.location(a),module):return false
	var probe:RefCounted=Workforce.draft(self,tx.staged,tx.extensions)
	if not production.start(probe,request).ok:return false
	if not production.start(tx,request).ok:return false
	intent.kind="craft";intent.order_id=str(request.get("command_id","preview"))+":order";a.activity="制作";return true

func stop_cancelled_zone_harvest(tx:RefCounted,a:Dictionary,intent:Dictionary)->bool:
	var request:Dictionary=intent.get("request",{})
	var payload:Dictionary=request.get("payload",{})
	if request.get("kind")!="harvest" or not payload.has("zone_id"):return false
	for zone:Dictionary in Workforce.Regional.zones(self,tx):
		if zone.id!=payload.zone_id or not zone.enabled or zone.revision!=payload.get("zone_revision"):continue
		var workers:Array=zone.policy.get("worker_ids",[])
		if workers.is_empty() or workers.has(a.id):return false
	cancel_in(tx,a);a.activity="已停止区域采伐"
	return true

func advance_path(tx: RefCounted, a: Dictionary, dt: float) -> void:
	if not Workforce.step_ready(self,tx,a):a.activity="区域暂停，保留真实携货";return
	var intent: Dictionary = a.intent
	if intent.kind=="approach" and stop_cancelled_zone_harvest(tx,a,intent):return
	if intent.kind=="module_approach" and try_module_arrival(tx,a,intent):return
	if intent.kind=="approach" and try_near_approach(tx,a,intent):return
	if intent.kind=="zone_supply":
		var supply_problem:String=ZoneSupply.problem(self,tx,a)
		if not supply_problem.is_empty():a.intent=null;a.activity=supply_problem;return
	if intent.get("replan_after_door",false):
		# Opening relocates us to its off-axis use pad and changes the physical
		# leaf. The old straight-edge proof starts elsewhere, so it cannot be
		# executed from here. Replan only after the actual door CAS committed.
		var fresh:=route(str(a.id),Geometry.location(a),intent.path_goal)
		if not fresh.ok:a.intent=null;a.activity="开门后通路不可用："+str(fresh.reason);return
		intent.steps=fresh.steps;intent.step=0;intent.erase("replan_after_door");intent.erase("path_goal")
	var steps: Array = intent.get("steps", [])
	if int(intent.get("step", 0)) >= steps.size():
		if intent.kind=="zone_supply":
			ZoneSupply.arrive(self,tx,a)
		elif intent.kind=="module_approach":
			var modules:Variant=module_service()
			var result:Dictionary=modules.claim_workforce_in(tx,str(a.id),str(intent.workforce_candidate_id),str(intent.id),true) if modules!=null else Data.reject("UNAVAILABLE")
			if not result.ok:a.intent=null;a.activity=str(result.get("reason",result.code))
		elif intent.kind == "approach":
			if intent.request.kind=="search":
				var stock:Dictionary=tx.stock(str(intent.request.target_id))
				var problem:Variant=production.reach(str(a.id),str(intent.request.target_id),stock,"search",tx)
				if problem!=null:a.intent=null;a.activity=str(problem);return
				intent.kind="search";intent.target_id=intent.request.target_id;intent.elapsed=0.0;a.activity="搜索容器";return
			var result: Dictionary = start_structure(tx, intent.request) if intent.request.kind == "structure" else production.start(tx, intent.request)
			if not result.ok: a.intent = null; a.activity = result.reason; return
			intent.kind = intent.request.kind; intent.order_id = str(intent.request.command_id) + ":order"
		elif intent.kind == "haul":
			var delivery: Dictionary = a.get("pending_delivery",{})
			var collecting: bool = delivery.get("phase") == "collect"
			var result := transfer_in(tx,str(a.id),str(delivery.get("source_id")) if collecting else "pack:"+str(a.id),"pack:"+str(a.id) if collecting else str(delivery.get("destination_id")),{"items":delivery.get("items",{})},str(delivery.get("task_id","")))
			Workforce.delivery_result(self,tx,a,delivery,collecting,result.ok,str(result.get("reason","")))
			if not result.ok: a.intent=null; a.activity="搬运中断："+result.reason; return
			if collecting: delivery.phase="deliver"; a.activity="已拾起，准备运回"
			else:
				tx.events.append({"kind":"npc-delivery-completed","actor_id":a.id,"source_id":delivery.source_id,"output_id":delivery.destination_id,"items":delivery.items.duplicate(true)})
				a.erase("pending_delivery"); a.activity="物资已实际送达"
			a.intent=null
		else:
			if intent.kind=="guard" and intent.has("guard_site_id"):tx.events.append({"kind":"guard-arrived","actor_id":a.id,"site_id":intent.guard_site_id,"location":Geometry.location(a)})
			a.intent = null; a.activity = "实际驻守" if intent.kind=="guard" else "已到达"
		return
	var step: Dictionary = steps[int(intent.step)]
	if step.kind == "open-door":
		var request := {"actor_id": a.id, "target_id": step.targetId, "kind": "door", "payload": {"operation": "open"}}
		var ready: Dictionary = building.prepare_door(request, tx.extensions.get("r3:structures", {}), tx.staged)
		if not ready.ok: a.activity = ready.reason; return
		intent.door_elapsed = float(intent.get("door_elapsed", 0)) + dt
		if float(intent.door_elapsed) < 0.4: return
		for c in ready.world_changes:
			if c.op == "extension.set": tx.extensions[c.id] = c.after
			else: tx.extra.append(c)
		a.stamina = maxf(0, float(a.stamina) - 0.25)
		intent.step = int(intent.step) + 1; intent.door_elapsed = 0.0
		if not steps.is_empty() and steps[-1].get("to") is Dictionary:
			intent.replan_after_door=true;intent.path_goal=steps[-1].to.duplicate(true)
		return
	var from := Geometry.location(a)
	var target := Geometry.location(step.to)
	var next := from.duplicate(true)
	var distance := Vector2(target.x - from.x, target.z - from.z).length()
	var requested_mode:=str(intent.get("movement_mode",intent.get("request",{}).get("payload",{}).get("movement_mode","walk")))
	var budget:=movement_budget(str(a.id),dt,requested_mode)
	if not budget.ok:a.activity=str(budget.get("reason","当前无法移动"));return
	var fraction := minf(1, minf(1.0,float(budget.max_distance)) / maxf(0.000001, distance))
	next.x = lerpf(from.x, target.x, fraction); next.z = lerpf(from.z, target.z, fraction)
	var moved := move_step(str(a.id), from, next)
	if not moved.ok:
		a.activity = moved.reason
		intent.blocked_seconds = float(intent.get("blocked_seconds", 0)) + dt
		if float(intent.blocked_seconds) > 2.0: a.intent = null
		return
	set_location(a, moved.location)
	record_movement(tx,str(a.id),from,moved.location,budget)
	intent.blocked_seconds = 0.0
	# Intermediate vertices are the proven ends of two separate body sweeps.
	# Skipping the last few centimetres cuts their corner and can hit a real
	# opened door leaf at a new speed. Clamp onto the actual waypoint first;
	# keep the existing final-goal arrival tolerance for the completed action.
	var arrival_tolerance:=0.08 if int(intent.step)==steps.size()-1 else 0.00001
	if Geometry.point(moved.location).distance_to(Geometry.point(target)) < arrival_tolerance: intent.step = int(intent.step) + 1

func prepare_npc(tx: RefCounted, a: Dictionary) -> void:
	var relationship: Dictionary = a.get("relationship", {})
	if not relationship.get("member", false) or not relationship.get("consent", false): return
	if float(a.get("nextDecision", 0)) > float(context.clock.call()): return
	a.nextDecision = float(context.clock.call()) + 2.0
	# Same runtime needs/rest mechanics, not a second recovery timer or free items.
	var need := needs_action(a)
	if not need.is_empty():
		needs_intent(tx,a,need);return
	if a.get("pending_delivery") is Dictionary and not a.pending_delivery.is_empty():
		prepare_delivery(tx,a);return
	var job := str(a.get("job", "follow"))
	if job == "rest":
		if below_stamina_cap(a):
			needs_intent(tx,a,"rest")
		a.activity = "自愿休息"; return
	var target_id := str(a.get("work_target_id", ""))
	var request := {"command_id": "npc:" + str(a.id) + ":" + str(int(float(context.clock.call()) * 10)), "actor_id": a.id, "target_id": target_id, "payload": {"direct": false, "held": true}}
	if job in ["gather", "craft"] and not target_id.is_empty():
		request.kind = "harvest" if job == "gather" else str(a.get("work_payload",{}).get("action_kind","craft"))
		if request.kind not in ["harvest","craft","study","structure"]:a.activity="工作类型无效";return
		request.payload.merge(a.get("work_payload", {}), true)
		for key in ["source_id","output_id"]:
			if request.payload.get(key)=="$actor_pack":request.payload[key]="pack:"+str(a.id)
		if job == "gather":
			var e: Dictionary = context.world.entity(target_id)
			if e.get("data",{}).get("harvest",{}).get("phase") != "standing": a.activity="采伐目标已完成";return
			request.payload.output_id = e.get("data", {}).get("outputId", "")
			request.payload.tool_ids = select_tools(tx,str(a.id),{"chopping":1})
			if not request.payload.has("delivery_id"):
				var destination:String=home_delivery_stock(tx.staged)
				if not destination.is_empty():request.payload.delivery_id=destination
		elif request.kind=="craft":
			var recipe:Dictionary=production.recipes.get(request.payload.get("recipe_id"),{})
			if not request.payload.has("tool_ids"):request.payload.tool_ids=select_tools(tx,str(a.id),recipe.get("qualities",{}))
			if not request.payload.has("source_id"):request.payload.source_id="pack:"+str(a.id)
			if not request.payload.has("output_id"):request.payload.output_id="pack:"+str(a.id)
			if recipe.has("repairTool") and not request.payload.has("repair_tool_id"):
				for tool in production.state().tools:
					if tool.get("kind")==recipe.repairTool.kind and tool.holderId=="pack:"+str(a.id) and float(tool.durability)<float(production.tool_definition(tool).get("maxDurability",0)) and not production.tool_unavailable(str(tool.id),"",tx):request.payload.repair_tool_id=tool.id;break
		elif request.kind=="structure":
			if not request.payload.has("source_id"):request.payload.source_id="pack:"+str(a.id)
			if not request.payload.has("output_id"):request.payload.output_id="pack:"+str(a.id)
			if not request.payload.has("tool_id"):
				var target:Dictionary=request.payload.get("instance",{}) if request.payload.get("kind")=="place" else building.instance(target_id)
				var tools:Array=select_tools(tx,str(a.id),{str(building.geometry.definition(target).get("tool","hammering")):1})
				if not tools.is_empty():request.payload.tool_id=tools[0]
		var destinations := work_points(request)
		for point in destinations:
			var plan := route(str(a.id), Geometry.location(a), point)
			if plan.ok:
				a.intent = {"schema_version":1,"owner": "actions", "id": request.command_id, "kind": "approach", "steps": plan.steps, "step": 0, "request": request, "held": true}; a.activity = "前往真实工位"; return
		a.activity = "工作目标或路线不可用"; return
	var player: Dictionary = tx.actor("player")
	if player.is_empty(): return
	var destination := Geometry.location(player)
	if job == "guard" and not target_id.is_empty():
		var e: Dictionary = context.world.entity(target_id)
		if not e.is_empty(): destination = Geometry.location(e)
	if Geometry.point(Geometry.location(a)).distance_to(Geometry.point(destination)) <= 2.5: a.activity = "在附近守望" if job == "guard" else "同行等待"; return
	destination.x += 0.9; destination.z += 0.9
	var plan := route(str(a.id), Geometry.location(a), destination)
	if plan.ok: a.intent = {"schema_version":1,"owner": "actions", "id":request.command_id, "kind": "guard" if job == "guard" else "follow", "steps": plan.steps, "step": 0, "held": true}; a.activity = "真实同行"
	else: a.activity = plan.reason

func select_tools(tx: RefCounted, actor_id: String, required: Dictionary) -> Array:
	var result: Array=[]
	var p: Dictionary=tx.extension(Production.KEY,Production.empty_state())
	for quality in required:
		for tool in p.tools:
			if tool.holderId=="pack:"+actor_id and float(tool.durability)>0 and not production.tool_unavailable(str(tool.id),"",tx) and float(production.tool_qualities(tool).get(quality,0))>=float(required[quality]):
				if not result.has(tool.id):result.append(tool.id)
				break
	return result

func home_delivery_stock(staged:Dictionary)->String:
	var candidates:Array=[]
	for anchors:Dictionary in building.life_anchors().values():
		if anchors.has("stock"):candidates.append(anchors.stock.target_id)
	for stock:Dictionary in staged.get("stocks",[]):
		if str(stock.id).contains(":old-house:storage") and not candidates.has(stock.id):candidates.append(stock.id)
	for id:String in candidates:
		var stock:Dictionary=Draft.find(staged.get("stocks",[]),id)
		if not stock.is_empty() and stock.get("owner")=="home-residents" and stock.get("searched",false) and Geometry.location(stock).regionId=="RH-HOME":return id
	return ""

func camp_work_targets()->Array:
	# Read-only choices for A's one assignment selector. No structure/order is
	# created until the assigned resident actually arrives and pays normal costs.
	var result:Array=[]
	var structures:Dictionary=building.structures()
	for record in production.state().get("records",[]):
		var holder:Dictionary=context.stock.call(str(record.get("holderId","")))
		if holder.is_empty() or not holder.get("searched",false):continue
		result.append({"id":"work:study:"+str(record.id),"actual_target_id":record.id,"name":"学习 · "+str(record.itemId),"job":"craft","work_payload":{"action_kind":"study","record_id":record.id}})
	for v in structures.instances:
		var d:Dictionary=building.geometry.definition(v)
		if float(v.hp)<=0 or float(v.hp)>=float(d.maxHp):continue
		result.append({"id":"work:repair:"+str(v.id),"actual_target_id":v.id,"name":"维修 · "+str(d.name),"job":"craft","work_payload":{"action_kind":"structure","kind":"repair","source_id":"$actor_pack","output_id":"$actor_pack"}})
	if context.world.identity().generatorVersion=="rural-1":
		var has_bench:bool=structures.instances.any(func(v:Dictionary)->bool:return v.regionId=="RH-HOME" and v.definitionId=="workbench" and float(v.hp)>0)
		for object in rural_layout.home.objects:
			if object.id_suffix!="workbench-reservation" or has_bench:continue
			var id:String=str(rural_layout.home.id)+":workbench-reservation"
			if not context.world.entity(id).is_empty():continue
			var instance:Dictionary=building.make_instance("workbench",id,{"x":object.position[0],"y":object.position[1],"z":object.position[2],"regionId":"RH-HOME"})
			result.append({"id":"work:build:"+id,"actual_target_id":id,"name":"建造 · 旧宅工作台","job":"craft","work_payload":{"action_kind":"structure","kind":"place","instance":instance,"source_id":"$actor_pack","output_id":"$actor_pack"}})
	elif context.world.has_extension("r3:building-generation"):
		var orders:Variant=context.world.extension("r3:structure-orders")
		for site:Dictionary in building.generation_work_sites():
			if site.get("owner")!="home-residents" or not context.world.entity(site.id).is_empty():continue
			# A completed placement stays consumed even if its real object is
			# later demolished; the retired identity must never be reoffered.
			if orders is Dictionary and orders.get("orders",[]).any(func(o:Dictionary)->bool:return o.get("targetId")==site.id and o.get("kind")=="place" and o.get("status")=="completed"):continue
			var instance:Dictionary=building.make_instance(site.definition_id,site.id,site.position,int(site.quarter_turn),site.owner)
			result.append({"id":"work:build:"+str(site.id),"actual_target_id":site.id,"name":"建造 · "+str(site.name),"job":"craft","work_payload":{"action_kind":"structure","kind":"place","instance":instance,"source_id":"$actor_pack","output_id":"$actor_pack"}})
	return result

func prepare_delivery(tx: RefCounted, a: Dictionary) -> void:
	var delivery: Dictionary=a.pending_delivery
	var id: String=str(delivery.source_id if delivery.phase=="collect" else delivery.destination_id)
	var stock: Dictionary=tx.stock(id)
	if stock.is_empty():a.activity="搬运容器不存在，保留实际物资";return
	var target:=Geometry.location(stock)
	var destinations: Array=[]
	var parent:=str(stock.get("structureId",""))
	if not parent.is_empty():destinations=building.use_points(parent)
	if destinations.is_empty():
		for offset in [Vector3.ZERO,Vector3(0,0,0.7),Vector3(0.7,0,0),Vector3(0,0,-0.7),Vector3(-0.7,0,0)]:
			var point:=target.duplicate(true);point.x+=offset.x;point.z+=offset.z
			var feet:Dictionary=building.current_space().standing_point(point)
			if not feet.is_empty():destinations.append(feet)
	destinations.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(Geometry.location(a)).distance_to(Geometry.point(x))<Geometry.point(Geometry.location(a)).distance_to(Geometry.point(y)))
	for destination in destinations:
		var plan:=route(str(a.id),Geometry.location(a),destination)
		if plan.ok:
			a.intent={"schema_version":1,"owner":"actions","id":"npc-haul:"+str(a.id)+":"+str(int(context.clock.call()*10)),"kind":"haul","steps":plan.steps,"step":0,"held":true,"work_target_id":a.get("work_target_id","")};a.activity="前往拾取" if delivery.phase=="collect" else "搬运回实际仓储";return
	a.activity="搬运路线受阻，保留实际物资"

func workforce_candidates(actor_id:String,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Array:return Workforce.candidates(self,actor_id,staged_facts,extension_overrides)
func workforce_candidate(actor_id:String,candidate_id:String,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:
	return Draft.find(workforce_candidates(actor_id,staged_facts,extension_overrides),candidate_id).duplicate(true)
func safe_handoff(actor_id:String,candidate_id:String="",staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:return Workforce.handoff(self,actor_id,candidate_id,staged_facts,extension_overrides)
func prepare_workforce(request:Dictionary,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:return Workforce.prepare(self,request,staged_facts,extension_overrides)
func prepare_guard(request:Dictionary,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:return Workforce.prepare_guard(self,request,staged_facts,extension_overrides)
func actor_work_projection(actor_id:String)->Dictionary:
	var result:Dictionary=production.actor_work_projection(actor_id)
	if not result.is_empty():return result
	var a:Dictionary=context.actor.call(actor_id);var intent:Variant=a.get("intent")
	if intent is Dictionary and intent.get("owner")=="actions" and intent.get("kind")=="module_approach":
		var modules:Variant=module_service()
		var project_id:String=str(intent.get("workforce_candidate_id","")).trim_prefix("module-project:")
		var project:Dictionary=Draft.find(modules.state().projects,project_id) if modules!=null else {}
		if project.is_empty():return {}
		return {"owner":"actions","kind":"module_approach","operation":project.operation,"phase":"approaching" if intent.get("held",true) else "paused","module_id":project.module_id,"project_id":project.id,"held":intent.get("held",true),"actor_id":actor_id,"progress_seconds":project.progress_seconds,"duration_seconds":project.duration_seconds,"effective_work":false,"effective_seconds":0.0,"paused_code":"approaching" if intent.get("held",true) else "paused","paused_reason":"正在前往实际作业口" if intent.get("held",true) else "已暂停前往作业口"}
	if not intent is Dictionary or intent.get("owner")!="actions" or intent.get("kind")!="structure":return {}
	var state:Variant=context.world.extension("r3:structure-orders");var o:=Draft.find(state.get("orders",[]) if state is Dictionary else [],str(intent.get("order_id","")))
	if o.is_empty() or not Production.active(o):return {}
	var target:Dictionary=o.instance if o.kind=="place" else building.instance(str(o.targetId));var boxes:Array=building.geometry.boxes(target)
	if boxes.is_empty():return {}
	var chest:=Geometry.point(Geometry.location(a))+Vector3(0,1.0,0);var box:AABB=boxes[0];var point:=chest.max(box.position).min(box.end);var normal:Vector3=chest-point
	if normal.length_squared()<0.000001:return {}
	var problem:Variant=check_structure(Draft.new(context),o)
	return {"owner":"actions","work_domain":"structure","kind":"structure","progress_seconds":o.elapsed,"duration_seconds":o.seconds,"effective_work":problem==null and o.status=="active" and intent.get("held",true) and float(o.get("effective_work",0))>0,"effective_seconds":o.get("effective_work",0),"paused_reason":str(problem) if problem!=null else str(o.get("reason")) if o.get("reason")!=null else "","contact":{"position":[point.x,point.y,point.z],"normal":[normal.normalized().x,normal.normalized().y,normal.normalized().z]}}
