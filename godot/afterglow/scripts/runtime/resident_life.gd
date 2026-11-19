extends RefCounted
## Unrecruited people act for THEMSELVES. Player-assigned work remains in B's
## consent-gated action service. Reuse its actual routes, door actions and
## step executor, and A's existing paid self-care. No idle production/rewards.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Costs=preload("res://scripts/runtime/frame_costs.gd")
const FATIGUE_SEEK_BED:=65.0
const FATIGUE_LEAVE_BED:=40.0
var context:Dictionary
var _runtime:WeakRef
var _actions:WeakRef
var _production:WeakRef
var _modules:WeakRef
var _enabled:=false
var _activity_space_id: int = 0
var _activity_by_origin: Dictionary = {}

func configure(value:Dictionary)->void:
	_activity_space_id = 0
	_activity_by_origin.clear()
	context=preload("res://scripts/actions/domain_context.gd").isolate(value)
	_runtime=weakref(value.runtime);_actions=weakref(value.services.actions)
	_production=weakref(value.services.production)
	_modules=weakref(value.services.modules) if value.services.get("modules") is RefCounted else null
	var facts:Dictionary=context.facts.call()
	_enabled=facts.get("scenario")=="rural-home-r33"

func housing_projection(actor_id:String="player",staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:
	# B owns design capacity, discovery, permissions and current module health.
	# Design capacity never creates occupancy, beds or people.
	var modules:Variant=_modules.get_ref() if _modules!=null else null
	if modules==null or not modules.has_method("housing_projection"):return {"available":false,"homes":[]}
	var result:Variant=modules.housing_projection(actor_id,staged_facts,extension_overrides)
	if not result is Dictionary or not result.get("available") is bool or not result.get("homes") is Array:return {"available":false,"homes":[]}
	return result.duplicate(true)

func _housing_source(stock:Dictionary,actor_id:String,tx:RefCounted,housing:Dictionary={})->Dictionary:
	if str(stock.get("module_id","")).is_empty():return {"applicable":false}
	var modules:Variant=_modules.get_ref() if _modules!=null else null
	if modules==null or not modules.has_method("instance") or not modules.has_method("definition"):return {"applicable":false}
	var home:Dictionary=modules.instance(str(stock.get("module_id","")),tx.extensions)
	var definition:Dictionary=modules.definition(str(home.get("definition_id","")))
	if definition.get("architecture",{}).get("set")!="r34-architecture-30-v1" or definition.get("shape")!="home":return {"applicable":false}
	var projection:Dictionary=housing_projection(actor_id,tx.staged,tx.extensions) if housing.is_empty() else housing
	for row:Dictionary in projection.get("homes",[]):
		if row.get("id")==home.get("id") and str(stock.get("id","")) in row.get("stock_refs",{}).values():return {"applicable":true,"usable":projection.get("available",false) and row.get("usable",false),"service_points":row.get("service_points",[])}
	return {"applicable":true,"usable":false,"service_points":[]}

func _take_supply(tx:RefCounted,actor_id:String,source_id:String,item:String)->Dictionary:
	# Recheck after walking: damage, consent or residency may have changed.
	# B still validates and pays the actual transfer.
	if Content.consumable_definition(item).get("kind","") not in ["eat","drink"]:return {"ok":false,"code":"UNSAFE_LIFE_SUPPLY","reason":"种苗、原水与未熟食材不能当成生活食水"}
	var stock:Dictionary=tx.stock(source_id)
	var source:Dictionary=_housing_source(stock,actor_id,tx)
	if source.get("applicable",false) and (not source.get("usable",false) or not _supply_allowed(tx.actor(actor_id),stock,true)):return {"ok":false,"code":"HOUSING_SERVICE_UNAVAILABLE","reason":"住宅服务当前不可用或无权使用"}
	if not _supply_allowed(tx.actor(actor_id),stock,tx.staged.get("scenario")=="factory-settlement-r34"):return {"ok":false,"code":"LIFE_SUPPLY_FORBIDDEN","reason":"食水来源未知或当前无取用许可"}
	if _free_supply(stock,item,tx)<1:return {"ok":false,"code":"NO_FREE_LIFE_SUPPLY","reason":"食水已被真实作业预约或已无可用份额"}
	return _actions.get_ref().transfer_in(tx,actor_id,source_id,"pack:"+actor_id,{"items":{item:1},"purpose":"life"})

func _free_supply(stock:Dictionary,item:String,tx:RefCounted)->float:
	var production:Variant=_production.get_ref() if _production!=null else null
	if production==null:return 0.0
	# B's warehouse floor protects work inputs, while real one-unit self-care
	# can use the floor. Both still respect every existing committed hold.
	if production.has_method("available_for"):return production.available_for(str(stock.get("id","")),item,"life","",tx)
	return float(stock.get("items",{}).get(item,0))-production.reserved(str(stock.get("id","")),item,"",tx)

static func _supply_allowed(a:Dictionary,stock:Dictionary,shared_services:bool)->bool:
	var shared:bool=shared_services and _cooperating(a) and stock.get("owner")=="home-residents"
	return stock.get("searched",false) and (shared or (stock.get("owner")!=null and stock.owner in [a.get("id"),a.get("householdId")] and stock.owner!="home-residents"))

func prepare_actor_release(transitions:Array,observed:Dictionary,_pending_world_changes:Array)->Dictionary:
	# A supplies post-request facts and merges this pure draft into that same
	# transaction. Intent/order release belongs to A/B; cargo stays untouched.
	var plan:Dictionary={"ok":true,"fact_changes":[],"world_changes":[],"events":[]}
	var bad:Dictionary={"ok":false,"code":"INVALID_LIFECYCLE_RELEASE","reason":"居民释放描述无效","fact_changes":[],"world_changes":[],"events":[]}
	if not observed.get("actors") is Array:return bad
	var seen:Dictionary={}
	for transition:Variant in transitions:
		if not transition is Dictionary or not Data.valid_id(transition.get("actor_id")) or transition.get("kind") not in ["incapacitated","removed","consent_revoked"]:return bad
		var id:String=transition.actor_id
		if seen.has(id):return bad
		seen[id]=true
		var before:Dictionary=Draft.find(observed.actors,id)
		if transition.kind=="removed":
			if not before.is_empty():return bad
			continue
		if before.is_empty():return bad
		if not before.get("self_routine") is Dictionary or before.self_routine.is_empty():continue
		var after:Dictionary=before.duplicate(true)
		after.self_routine.next_decision=0.0
		after.self_routine.erase("last_failure")
		if transition.kind=="consent_revoked" and observed.get("scenario")=="factory-settlement-r34":
			after.self_routine.origin=Geometry.location(after)
			after.self_routine.erase("factory_arrived_goal")
			if _own(after):after.intent=null;after.activity="已撤回合作，自主决定生活路线"
		if not Data.json_equal(before,after):plan.fact_changes.append({"collection":"actors","id":id,"before":before.duplicate(true),"after":after})
	return plan

func validate_intent(intent:Dictionary,actor_state:Dictionary={},_facts_state:Dictionary={})->Dictionary:
	var bad:Dictionary={"ok":false,"code":"INVALID_RESIDENT_INTENT","reason":"居民路线描述无效"}
	var version:Variant=intent.get("schema_version",0)
	if not version is int and not version is float:return bad
	if not is_finite(float(version)) or float(version) not in [0.0,1.0]:return bad
	if intent.get("owner")!="residents" or intent.get("kind")!="walk" or not Data.valid_id(intent.get("id")):return bad
	if intent.has("phase") and intent.phase not in ["active","paused"]:return bad
	if not actor_state.is_empty() and not Data.valid_id(actor_state.get("id")):return bad
	if not intent.get("steps") is Array or intent.steps.size()>8192:return bad
	var cursor:Variant=intent.get("step",0)
	if not (cursor is int or cursor is float) or not is_finite(float(cursor)) or float(cursor)!=floorf(float(cursor)) or float(cursor)<0 or float(cursor)>intent.steps.size():return bad
	if not intent.get("held",true) is bool or intent.get("movement_mode","walk") not in ["walk","run"]:return bad
	for step:Variant in intent.steps:
		if not step is Dictionary:return bad
		if step.get("kind")=="open-door":
			if not Data.valid_id(step.get("targetId")) or not _route_location(step.get("at")):return bad
		elif step.get("kind") in ["move","cross-region","stairs"]:
			if not _route_location(step.get("to")):return bad
			if step.kind=="stairs" and (not Data.valid_id(step.get("targetId")) or not _route_location(step.get("from"))):return bad
		else:return bad
	if intent.get("replan_after_door",false) and not _route_location(intent.get("path_goal")):return bad
	for field:String in ["door_elapsed","blocked_seconds"]:
		var value:Variant=intent.get(field,0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0:return bad
	var goal:Variant=intent.get("resident_goal",{})
	if not goal is Dictionary:return bad
	if not goal.is_empty():
		if goal.get("kind")=="bed":
			if not Data.valid_id(goal.get("target_id")):return bad
		elif not Data.valid_id(goal.get("source_id")) or not Data.valid_id(goal.get("item")):return bad
	return {"ok":true,"code":"OK","reason":null}

static func _route_location(value:Variant)->bool:
	return Data.vec(value) and Data.valid_id(value.get("regionId")) and (value.get("buildingId")==null or Data.valid_id(value.buildingId)) and (value.get("storeyId")==null or Data.valid_id(value.storeyId))

func hold_descriptors(facts:Dictionary,_extension_overrides:Dictionary={})->Array:
	var result:Array=[]
	for a:Dictionary in facts.get("actors",[]):
		if float(a.get("hp",0))<=0 or not _own(a) or not validate_intent(a.intent,a,facts).ok:continue
		var goal:Dictionary=a.intent.get("resident_goal",{})
		if goal.get("kind")!="bed":continue
		result.append({"schema_version":1,"owner":"residents","intent_id":a.intent.id,"actor_id":a.id,"phase":"active","source_id":"","cost":{},"tool_ids":[],"use_target_id":goal.target_id})
	return result

static func _own(a:Dictionary)->bool:
	return a.get("intent") is Dictionary and a.intent.get("owner")=="residents"

static func _cooperating(a:Dictionary)->bool:
	return a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false)

static func _own_care(a:Dictionary)->bool:
	return a.get("intent") is Dictionary and a.intent.get("owner")=="runtime" and str(a.intent.get("id","")).begins_with("resident:self:")

static func _routine(a:Dictionary)->Dictionary:
	if not a.get("self_routine") is Dictionary or a.self_routine.is_empty():
		a.self_routine={"version":1,"origin":Geometry.location(a),"phase":0,"next_decision":0.0}
	return a.self_routine

func _available_for_self(a:Dictionary)->bool:
	if not _cooperating(a):return true
	# Explicit voluntary rest may use the same E self-care, but never take a
	# suspended/active B order or a person's physically held delivery cargo.
	if a.get("job")!="rest" or a.has("suspended_work"):return false
	if a.get("pending_delivery") is Dictionary and not a.pending_delivery.is_empty():return false
	for key:String in ["r3:production","r3:structure-orders"]:
		var state:Variant=context.world.extension(key)
		if state is Dictionary:
			for order:Dictionary in state.get("orders",[]):
				if order.get("actorId")==a.id and order.get("status") in ["active","blocked"]:return false
	return true

func _stamina_max(a:Dictionary)->float:
	# Decisions already have the current draft actor. An ID lookup can read
	# older fatigue; use A's one pure effects rule without a second ceiling.
	var cap:Variant=Content.actor_effects(a).get("stamina_max")
	if (cap is float or cap is int) and is_finite(float(cap)) and float(cap)>0:return float(cap)
	return -1.0

func _need(a:Dictionary)->String:
	if float(a.thirst)<35 and not _supply_item(a.get("pack",{}),"drink").is_empty():return "drink"
	if float(a.hunger)<35 and not _supply_item(a.get("pack",{}),"eat").is_empty():return "eat"
	var cap:=_stamina_max(a)
	if cap>0 and float(a.stamina)<minf(45.0,cap*0.5):return "rest"
	if float(a.thirst)<35:return "drink"
	if float(a.hunger)<35:return "eat"
	var routine:Dictionary=_routine(a)
	if float(a.fatigue)>=FATIGUE_SEEK_BED:routine.seeking_sleep=true
	if float(a.fatigue)<=FATIGUE_LEAVE_BED:routine.erase("seeking_sleep")
	return "bed" if routine.get("seeking_sleep",false) else ""

func _supply_item(items:Dictionary,kind:String,source_id:String="",tx:RefCounted=null)->String:
	# Query only IDs physically present here, never the whole recipe catalog.
	# A's descriptor alone declares food/safe water; seeds, raw and filtered
	# water and uncooked crops have no matching consumption definition.
	var ids:Array=[];var legacy:String={"eat":"food","drink":"water"}.get(kind,"")
	if not legacy.is_empty() and items.has(legacy):ids.append(legacy)
	for id:String in items:
		if id!=legacy:ids.append(id)
	for id:String in ids:
		if Content.consumable_definition(id,kind).is_empty():continue
		var free:float=_free_supply(tx.stock(source_id),id,tx) if tx!=null and not source_id.is_empty() else float(items[id])
		if free>=1:return id
	return ""

static func _blocked(a:Dictionary,routine:Dictionary,code:String,reason:String,now:float)->void:
	routine.last_failure={"code":code,"reason":reason,"at":now}
	a.activity=reason

func _bed_usable(a:Dictionary,bed:Dictionary,tx:RefCounted=null)->bool:
	if bed.is_empty():return false
	# A owns the exact same permission/occupancy policy for player and NPC.
	# A remote candidate skips only contact; arrival and recovery still prove it.
	return _runtime.get_ref().bed_availability(a,str(bed.id),{} if tx==null else tx.staged,false).ok

func _care(a:Dictionary,kind:String,now:float,target_id:String="",tx:RefCounted=null)->bool:
	var request:Dictionary={"command_id":"resident:self:"+str(a.id)+":"+str(int(now*10)),"actor_id":a.id,"kind":kind}
	var host:RefCounted=_runtime.get_ref()
	if not target_id.is_empty():
		var bed:Dictionary=context.world.entity(target_id)
		if not _bed_usable(a,bed,tx):
			_blocked(a,_routine(a),"NO_BED","寝具已不可用或有人使用",now)
			return false
		request.target_id=target_id
	elif kind=="rest":
		# A distinguishes a short rest from fatigue recovery at a prepared bed.
		# Never declare a missing/unprepared or somebody else's bed usable.
		for bed:Dictionary in context.world.entities():
			if not _bed_usable(a,bed,tx):continue
			var candidate:Dictionary=request.merged({"target_id":bed.id})
			if host.life_availability(candidate,a,{} if tx==null else tx.staged).ok:request=candidate;break
	var ready:Dictionary=host.life_availability(request,a,{} if tx==null else tx.staged)
	if not ready.ok:
		_blocked(a,_routine(a),str(ready.code),str(ready.reason),now)
		return false
	var plan:Dictionary=host.prepare_life(request,a,{} if tx==null else tx.staged)
	if not plan.ok:
		_blocked(a,_routine(a),str(plan.code),str(plan.reason),now)
		return false
	for change:Dictionary in plan.fact_changes:
		if change.id==a.id:a.merge(change.after,true)
	a.self_routine.erase("last_failure")
	return true

func _bed_points(bed:Dictionary)->Array:
	var points:Array=context.spatial.use_points(str(bed.id))
	if not points.is_empty() or not bed.get("bounds") is Dictionary:return points
	# Generated sleeping props are world entities, not B structure instances.
	# Choose nearby surfaces only; B still proves standing/body/route, and A
	# rechecks the actual bed's life availability at arrival.
	var query:RefCounted=context.spatial.current_space()
	var bounds:AABB=Geometry.aabb(bed.bounds)
	var center:Vector3=bounds.get_center()
	for offset:Vector3 in [Vector3(bounds.size.x*0.5+0.5,0,0),Vector3(-bounds.size.x*0.5-0.5,0,0),Vector3(0,0,bounds.size.z*0.5+0.5),Vector3(0,0,-bounds.size.z*0.5-0.5)]:
		var raw:Dictionary=Geometry.location(bed)
		raw.x=center.x+offset.x;raw.z=center.z+offset.z
		var feet:Dictionary=query.standing_point(raw)
		if not feet.is_empty() and Interaction.entity(query,feet,bed):points.append(feet)
	return points

func _seek_bed(a:Dictionary,routine:Dictionary,tx:RefCounted,now:float)->void:
	var beds:Array=context.world.entities().filter(func(bed:Dictionary)->bool:return _bed_usable(a,bed,tx))
	beds.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(Geometry.location(x)).distance_squared_to(Geometry.point(a))<Geometry.point(Geometry.location(y)).distance_squared_to(Geometry.point(a)))
	var failure:Dictionary={"code":"NO_BED","reason":"没有可使用的自有已铺寝具，只能短歇回气"}
	for bed:Dictionary in beds:
		var ready:Dictionary=_runtime.get_ref().life_availability({"kind":"rest","target_id":bed.id},a,tx.staged)
		if ready.ok:
			_care(a,"rest",now,str(bed.id),tx)
			return
		failure=ready
		var points:Array=_bed_points(bed)
		if points.is_empty():failure={"code":"NO_BED_APPROACH","reason":"寝具旁没有合法可使用脚点"}
		points.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(x).distance_squared_to(Geometry.point(a))<Geometry.point(y).distance_squared_to(Geometry.point(a)))
		for point:Dictionary in points:
			var route:Dictionary=_route_to(a,point,now,"bed",{"kind":"bed","target_id":bed.id})
			if route.ok:a.activity="疲劳，前往真实寝具休息";return
			failure=route
	routine.next_decision=now+12.0
	_blocked(a,routine,str(failure.get("code","UNREACHABLE")),"疲劳寻寝具受阻："+str(failure.get("reason","通路不可用")),now)

func _threat(a:Dictionary,tx:RefCounted)->Dictionary:
	var nearest: Dictionary = {}
	var distance := 7.0
	var observed: Dictionary = tx.read_facts()
	var factory_scenario: bool = observed.get("scenario") == "factory-settlement-r34"
	var query: RefCounted
	var actor_point := Geometry.point(a)
	for other: Dictionary in observed.actors:
		if other.get("faction") != "infected" or float(other.get("hp", 0)) <= 0:
			continue
		if factory_scenario and not context.region_is_detailed.call(str(other.regionId)):
			continue
		var d := Geometry.point(other).distance_to(actor_point)
		if d >= distance:
			continue
		if query == null:
			query = context.spatial.current_space()
		# B's line_clear already raises both locations to eye height.
		var from:=Geometry.location(a)
		var to:=Geometry.location(other)
		if not query.line_clear(from,to,""):continue
		nearest=other;distance=d
	return nearest

func _route_to(a:Dictionary,destination:Dictionary,now:float,purpose:String,goal:Dictionary={})->Dictionary:
	var scenario: String = context.scenario.call() if context.get("scenario") is Callable else str(context.facts.call().get("scenario", ""))
	if scenario=="factory-settlement-r34" and not context.region_is_detailed.call(str(destination.get("regionId",""))):return {"ok":false,"code":"REGION_PAUSED","reason":"目标地区未详细模拟，保持原地和真实物资"}
	var route_started := Costs.begin()
	var route: Dictionary
	if purpose == "village-stroll":
		# Leisure can choose another nearby point. Use the normal segment proof
		# and avoid building a detour graph for each blocked optional destination.
		route = context.spatial.current_space().route(str(a.id), Geometry.location(a), destination, false)
	else:
		route = _actions.get_ref().route(str(a.id), Geometry.location(a), destination)
	if route_started != 0:
		Costs.end("resident/route/" + purpose, route_started)
	if not route.ok:return route
	if route.steps.is_empty():return {"ok":false,"code":"NO_ROUTE_STEPS","reason":"未到使用点，路线没有可执行步进"}
	a.intent={"schema_version":1,"owner":"residents","kind":"walk","id":"resident:walk:"+str(a.id)+":"+str(int(now*10)),"steps":route.steps,"step":0,"held":true,"purpose":purpose,"movement_mode":"run" if purpose=="avoid" else "walk","resident_goal":goal.duplicate(true)}
	return route

func _seek_supplies(a:Dictionary,routine:Dictionary,tx:RefCounted,need:String,now:float,shared_services:bool=false)->bool:
	if need not in ["drink","eat"]:return false
	var candidates:Array=[]
	var selected_items:Dictionary={}
	var housing:Dictionary={}
	var housing_sources:Dictionary={}
	for stock:Dictionary in tx.staged.get("stocks",[]):
		# Personal supplies only: revoking work consent never grants a new right
		# to take the player's/team stock or to inspect unknown containers.
		if not _supply_allowed(a,stock,shared_services):continue
		var source:Dictionary=_housing_source(stock,str(a.id),tx,housing)
		if source.get("applicable",false):
			if housing.is_empty():housing=housing_projection(str(a.id),tx.staged,tx.extensions)
			if not source.get("usable",false):continue
			housing_sources[str(stock.id)]=source
		# A new opening may place someone on the home road while their known
		# personal supplies remain in the village. B can route across the real
		# connected regions; a regional filter would strand those finite supplies.
		var item:String=_supply_item(stock.get("items",{}),need,str(stock.id),tx)
		if not item.is_empty():candidates.append(stock);selected_items[str(stock.id)]=item
	if candidates.is_empty():return false
	candidates.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(Geometry.location(x)).distance_squared_to(Geometry.point(a))<Geometry.point(Geometry.location(y)).distance_squared_to(Geometry.point(a)))
	var failure:Dictionary={}
	for stock:Dictionary in candidates:
		var item:String=selected_items[str(stock.id)]
		var goal:Dictionary={"source_id":stock.id,"item":item}
		var moved:Dictionary=_take_supply(tx,str(a.id),str(stock.id),item)
		if moved.ok:
			routine.next_decision=now;a.activity="已从自有容器取用一份食水";routine.erase("last_failure")
			return true
		failure=moved
		var points:Array=housing_sources[str(stock.id)].service_points if housing_sources.has(str(stock.id)) else context.spatial.use_points(str(stock.get("structureId","")))
		if points.is_empty() and not housing_sources.has(str(stock.id)):points=[Geometry.location(stock)]
		for point:Dictionary in points:
			var route:Dictionary=_route_to(a,point,now,"supply",goal)
			if route.ok:a.activity="前往自有食水容器";return true
			failure=route
	_blocked(a,routine,str(failure.get("code","UNREACHABLE")),"自有食水取用受阻："+str(failure.get("reason","容器不可用")),now)
	return true

func _walk(a:Dictionary,routine:Dictionary,tx:RefCounted,now:float,threat:Dictionary={})->bool:
	var candidates:Array=_destinations(a,routine,tx)
	if not threat.is_empty():
		var distance:float=Geometry.point(a).distance_to(Geometry.point(threat))
		candidates=candidates.filter(func(p:Dictionary)->bool:return Geometry.point(p).distance_to(Geometry.point(threat))>distance+0.25)
		candidates.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(x).distance_squared_to(Geometry.point(threat))>Geometry.point(y).distance_squared_to(Geometry.point(threat)))
	var failure:Dictionary={"code":"NO_SAFE_POINT","reason":"生活锚点没有合法可达脚点" if threat.is_empty() else "没有更远的合法避险脚点"}
	for destination:Dictionary in candidates:
		var route:Dictionary=_route_to(a,destination,now,"watch" if threat.is_empty() else "avoid")
		if not route.ok:failure=route;continue
		if not threat.is_empty():
			a.activity="沿真实通路避险";routine.erase("last_failure")
		else:
			a.activity="查看门口与村路" if destination.get("buildingId")==null else "在住处附近查看"
			if routine.get("last_failure",{}).get("code")=="NO_ITEM":a.activity="食水不足，在住处附近查看"
		return true
	_blocked(a,routine,str(failure.get("code","UNREACHABLE")),("活动受阻：" if threat.is_empty() else "避险受阻：")+str(failure.get("reason","通路不可用")),now)
	return false

func factory_signals(a:Dictionary,tx:RefCounted)->Dictionary:
	# Same thresholds and body rules, no second metabolism or recovery timer.
	_routine(a)
	var need:String=_need(a)
	return {"danger":not _threat(a,tx).is_empty(),"urgent_need":need,"guard_qualified":_cooperating(a) and a.get("job")=="guard" and float(a.get("stamina",0))>=14,"owns_walk":_own(a),"owns_care":_own_care(a)}

func teaching_target_reserved(a:Dictionary,tx:RefCounted)->bool:
	# The adopted teaching offer has one real teacher. B's existing use hold
	# owns the appointment; E owns neither its progress nor its completion.
	if a.get("id")!="repair-resident":return false
	var production:Variant=_production.get_ref() if _production!=null else null
	return production!=null and production.use_reserved(str(a.id),"",tx)

func prepare_factory_person(tx:RefCounted,actor_id:String,dt:float,now:float,allow_new:bool=false,layout:Dictionary={})->Dictionary:
	# Called only by E workforce in A's fixed step. residents.advance remains
	# legacy-only, so there is a single decision owner in the new scenario.
	if tx.read_facts().get("scenario") != "factory-settlement-r34":
		return {"ok": false, "code": "SCENARIO_UNAVAILABLE"}
	var a:Dictionary=tx.actor(actor_id)
	if a.is_empty() or a.id=="player" or a.get("faction")=="infected" or float(a.get("hp",0))<=0:return {"ok":true,"new_intent":false}
	if not context.region_is_detailed.call(str(a.regionId)):return {"ok":true,"new_intent":false,"paused":true}
	var routine:Dictionary=_routine(a)
	if _own(a):
		var goal:Dictionary=a.intent.get("resident_goal",{}).duplicate(true)
		var purpose:String=str(a.intent.get("purpose",""))
		_actions.get_ref().advance_path(tx,a,dt)
		if a.get("intent")==null:
			routine.phase=int(routine.get("phase",0))+1
			routine.next_decision=now+1.0
			if a.activity=="已到达":
				# Only a real use goal needs immediate follow-up. Ordinary watching
				# keeps the existing one-second idle interval after arrival.
				if not goal.is_empty():routine.factory_arrived_goal=goal;routine.next_decision=now
				if purpose=="village-stroll":
					a.activity="在村里歇脚"
					routine.village_stroll_after=now+8.0+float(posmod(hash(a.id),7))
				if purpose=="return-home" and _cooperating(a) and layout.get("home") is Dictionary and a.regionId==layout.home.regionId and Geometry.point(a).distance_to(Geometry.point(layout.home))<=float(layout.get("home_radius",18.0)):
					a.relationship.home_arrived=true
					tx.events.append({"kind":"settlement-member-arrived","actor_id":a.id,"region_id":a.regionId})
		return {"ok":true,"new_intent":false}
	if a.get("intent")!=null or not allow_new:return {"ok":true,"new_intent":false}
	routine.next_decision=now+1.0
	var threat:Dictionary=_threat(a,tx)
	if not threat.is_empty():
		if _cooperating(a) and a.get("job")=="guard" and float(a.get("stamina",0))>=14:
			a.activity="在真实站位守备，沿既有攻击结算"
			return {"ok":true,"new_intent":false}
		_walk(a,routine,tx,now,threat)
		return {"ok":true,"new_intent":a.get("intent")!=null}
	var goal:Dictionary=routine.get("factory_arrived_goal",{}).duplicate(true)
	routine.erase("factory_arrived_goal")
	if goal.get("kind")=="bed":
		_care(a,"rest",now,str(goal.get("target_id","")),tx)
		return {"ok":true,"new_intent":a.get("intent")!=null}
	if goal.has("source_id"):
		var moved:Dictionary=_take_supply(tx,str(a.id),str(goal.source_id),str(goal.item))
		if not moved.ok:_blocked(a,routine,str(moved.code),str(moved.reason),now)
		return {"ok":true,"new_intent":false}
	var need:String=_need(a)
	if need=="bed":
		_seek_bed(a,routine,tx,now)
		return {"ok":true,"new_intent":a.get("intent")!=null}
	if not need.is_empty():
		if _care(a,need,now,"",tx):return {"ok":true,"new_intent":true}
		if _seek_supplies(a,routine,tx,need,now,true):return {"ok":true,"new_intent":a.get("intent")!=null}
		_blocked(a,routine,"NO_ITEM","没有已知且有权的真实食水，保持原有身体规则",now)
		return {"ok":true,"new_intent":false}
	if teaching_target_reserved(a,tx):
		a.activity="在现场交流教学；紧急需求仍可中断"
		return {"ok":true,"new_intent":false}
	if _cooperating(a):
		var home:Variant=layout.get("home")
		if home is Dictionary and (a.get("regionId")!=home.get("regionId") or Geometry.point(a).distance_to(Geometry.point(home))>float(layout.get("home_radius",18.0))):
			var route:Dictionary=_route_to(a,home,now,"return-home")
			if not route.ok:_blocked(a,routine,str(route.code),str(route.reason),now)
			else:a.activity="自愿沿真实通路返家"
		elif int(layout.get("opening_version",0))==3 and home is Dictionary and now>=float(routine.get("village_stroll_after",0.0)):
			_stroll(a,routine,tx,now,home,float(layout.get("home_radius",18.0)))
		elif a.activity!="在村里歇脚":a.activity="在据点休息待命"
	else:_walk(a,routine,tx,now)
	return {"ok":true,"new_intent":a.get("intent")!=null}

func _stroll(a:Dictionary,routine:Dictionary,tx:RefCounted,now:float,home:Dictionary,radius:float)->void:
	routine.village_stroll_after=now+12.0+float(posmod(hash(a.id),7))
	var local:Dictionary=routine.duplicate()
	local.phase=int(routine.get("phase",0))+posmod(hash(a.id),5)
	var peers:Array=[]
	for other: Dictionary in tx.read_facts().get("actors", []):
		if other.id==a.id or other.regionId!=a.regionId or float(other.get("hp",0))<=0:continue
		peers.append(Geometry.point(other))
		var steps:Variant=other.get("intent",{}).get("steps",[]) if other.get("intent") is Dictionary and other.intent.get("purpose")=="village-stroll" else []
		if not steps.is_empty() and steps.back().get("to") is Dictionary:peers.append(Geometry.point(steps.back().to))
	for destination:Dictionary in _destinations(a,local,tx):
		if destination.regionId!=home.regionId or Geometry.point(destination).distance_to(Geometry.point(home))>radius:continue
		var point:=Geometry.point(destination)
		if peers.any(func(p:Vector3)->bool:return p.distance_to(point)<0.9):continue
		if not _route_to(a,destination,now,"village-stroll").ok:continue
		a.activity="在旧村里走动"
		return
	a.activity="在据点休息待命"

func advance(dt:float)->Dictionary:
	if not is_finite(dt) or dt<=0 or dt>1:return {"ok":false,"code":"INVALID_STEP","reason":"居民仅由同一时钟推进"}
	if not _enabled:return {"ok":true,"world_changes":[],"fact_changes":[]}
	var now:float=context.clock.call();var due:=false
	# Rebuild this small decision view from A's current actors. It is not a
	# configure-time roster or a second persisted actor/lifecycle authority.
	var facts:Dictionary=context.facts.call()
	var people:Array=[]
	for a:Dictionary in facts.get("actors",[]):
		if a.id=="player" or a.get("faction")=="infected" or a.get("expedition_follow",false):continue
		people.append(str(a.id))
		var living:bool=float(a.get("hp",0))>0
		var decision:float=float(a.get("self_routine",{}).get("next_decision",0))
		if _own(a) or _own_care(a) or (not living and decision>0) or (living and _available_for_self(a) and a.get("intent")==null and now>=decision):due=true
	if not due:return {"ok":true,"world_changes":[],"fact_changes":[]}
	var tx:=Draft.new(context)
	for id:String in people:
		var a:Dictionary=tx.actor(id)
		if a.is_empty():continue
		if not _available_for_self(a) or float(a.hp)<=0:
			if _own(a) or (float(a.hp)<=0 and _own_care(a)):a.intent=null;a.activity="自愿同行" if float(a.hp)>0 else "已失能"
			# A future idle deadline must not strand an otherwise recovered actor.
			# B owns its orders/cargo cleanup; only E's own schedule is reset here.
			if float(a.hp)<=0 and a.get("self_routine") is Dictionary:a.self_routine.next_decision=0.0
			continue
		var routine:Dictionary=_routine(a)
		var threat:Dictionary=_threat(a,tx)
		if not threat.is_empty() and (_own(a) or _own_care(a)) and a.intent.get("purpose")!="avoid":
			# Interrupt only this service's walk/self-care. B cancels its own orders
			# and reservations; a life completion still consumes through A alone.
			a.intent=null;routine.next_decision=now+3.0
			_walk(a,routine,tx,now,threat)
			continue
		if _own(a):
			var need:String=_need(a)
			a.intent.movement_mode="run" if a.intent.get("purpose")=="avoid" and not threat.is_empty() else "walk"
			if threat.is_empty() and need=="bed" and a.intent.get("purpose")!="bed":
				a.intent=null
				_seek_bed(a,routine,tx,now)
				continue
			if threat.is_empty() and not need.is_empty():
				var ready:Dictionary={"ok":false} if need=="bed" else _runtime.get_ref().life_availability({"kind":need},a,tx.staged)
				if ready.ok:
					var walking:Dictionary=a.intent
					a.intent=null
					if _care(a,need,now,"",tx):continue
					a.intent=walking
			var goal:Dictionary=a.intent.get("resident_goal",{}).duplicate(true)
			_actions.get_ref().advance_path(tx,a,dt)
			if a.intent==null:
				routine.phase=int(routine.get("phase",0))+1
				routine.next_decision=now+4.0
				if a.activity=="已到达" and goal.get("kind")=="bed":
					_care(a,"rest",now,str(goal.target_id),tx)
				elif a.activity=="已到达" and not goal.is_empty():
					var moved:Dictionary=_take_supply(tx,str(a.id),str(goal.source_id),str(goal.item))
					if moved.ok:routine.next_decision=now;a.activity="已从自有容器取用一份食水";routine.erase("last_failure")
					else:_blocked(a,routine,str(moved.code),str(moved.reason),now)
				elif a.activity=="已到达":a.activity="在住处附近守望"
				else:_blocked(a,routine,"ROUTE_BLOCKED",str(a.activity),now)
			continue
		if a.get("intent")!=null:continue
		if now<float(routine.get("next_decision",0)):continue
		routine.next_decision=now+3.0
		if threat.is_empty():
			var need:String=_need(a)
			if need=="bed":_seek_bed(a,routine,tx,now);continue
			if not need.is_empty() and _care(a,need,now,"",tx):continue
			if not need.is_empty() and _seek_supplies(a,routine,tx,need,now):continue
			# A consenting person's explicit rest is not permission to resume
			# their pre-joining village patrol and leave the shared home again.
			if _cooperating(a):a.activity="自愿休息";continue
		if not _walk(a,routine,tx,now,threat):
			routine.phase=int(routine.get("phase",0))+1
	return tx.result()

func _gather_activity_points(origin: Dictionary, query: RefCounted) -> Array:
	# Generated entrances and roads are real persisted places. Select local
	# survival observation points; B still decides doors, ownership and route.
	# This does not assign unpaid work, reveal unknown stock or move an old save.
	var plan:Variant=context.world.extension("generation:"+str(origin.regionId))
	if not plan is Dictionary or plan.get("schema") not in ["afterglow-settlement-plan-v1","afterglow-factory-settlement-plan-v1"]:return []
	var building_id:String=str(origin.get("buildingId","") if origin.get("buildingId")!=null else "")
	var anchors:Dictionary=context.spatial.life_anchors()
	if building_id.is_empty():
		var nearest:=25.0
		for id:String in anchors:
			for anchor:Dictionary in anchors[id].values():
				var at:Dictionary=anchor.get("position",{})
				if at.get("regionId")!=origin.regionId:continue
				var distance:float=Geometry.point(at).distance_to(Geometry.point(origin))
				if distance<nearest:nearest=distance;building_id=id
	var entrances:Array=[]
	for slot:Dictionary in plan.get("slots",[]):
		if slot.get("kind")!="entrance" or slot.get("buildingId")!=building_id:continue
		var raw:Dictionary=Geometry.location(slot);raw.regionId=origin.regionId
		var feet:Dictionary=query.standing_point(raw)
		if not feet.is_empty() and feet.get("buildingId")==null and Geometry.point(feet).distance_to(Geometry.point(origin))<=28:entrances.append(feet)
	entrances.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(x).distance_squared_to(Geometry.point(origin))<Geometry.point(y).distance_squared_to(Geometry.point(origin)))
	var result:Array=entrances.slice(0,3)
	# Add a supported stretch of the nearest actual village road. Avoid dozens
	# of nearly identical metre-spaced points and keep decisions local/bounded.
	var roads:Array=[]
	for path:Dictionary in plan.get("paths",[]):
		for value:Dictionary in path.get("points",[]):
			var raw:Dictionary=Geometry.location(value);raw.regionId=origin.regionId
			if Geometry.point(raw).distance_to(Geometry.point(origin))>22:continue
			if not entrances.is_empty() and Geometry.point(raw).distance_to(Geometry.point(entrances[0]))>8:continue
			roads.append(raw)
	roads.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(x).distance_squared_to(Geometry.point(origin))<Geometry.point(y).distance_squared_to(Geometry.point(origin)))
	for raw:Dictionary in roads:
		if result.any(func(p:Dictionary)->bool:return Geometry.point(p).distance_to(Geometry.point(raw))<2):continue
		var feet:Dictionary=query.standing_point(raw)
		if feet.is_empty() or feet.get("buildingId")!=null:continue
		result.append(feet)
		if result.size()>=5:break
	return result

func _destinations(a:Dictionary,routine:Dictionary,_tx:RefCounted)->Array:
	var query:RefCounted=context.spatial.current_space()
	var result:Array=[]
	var origin:Dictionary=routine.origin
	var offsets:Array=[Vector2(-1.4,0),Vector2(0,-1.4),Vector2(1.4,0),Vector2(0,1.4),Vector2(-1.0,-1.0),Vector2(1.0,1.0),Vector2.ZERO]
	var phase:int=int(routine.get("phase",0))
	var raw_points:Array=routine.get("points",[]).duplicate(true)
	# A current Space instance covers one world revision. These derived points
	# contain no actor state and do not prove a route or grant door access.
	if _activity_space_id != query.get_instance_id():
		_activity_space_id = query.get_instance_id()
		_activity_by_origin.clear()
	var origin_key: Array = [origin.regionId, origin.get("buildingId"), Geometry.point(origin)]
	if not _activity_by_origin.has(origin_key):
		if _activity_by_origin.size() >= 32:
			_activity_by_origin.clear()
		_activity_by_origin[origin_key] = _gather_activity_points(origin, query)
	raw_points.append_array(_activity_by_origin[origin_key])
	for i in raw_points.size():
		var p:Dictionary=raw_points[posmod(i+phase,raw_points.size())].duplicate(true)
		if Geometry.point(p).distance_to(Geometry.point(a))>0.3:result.append(p)
	for i in offsets.size():
		var p:Dictionary=origin.duplicate(true);var offset:Vector2=offsets[posmod(i+phase,offsets.size())]
		p.x=float(p.x)+offset.x;p.z=float(p.z)+offset.y
		var feet:Dictionary=query.standing_point(p)
		if feet.is_empty() or (feet.get("buildingId")!=null and feet.get("buildingId")!=origin.get("buildingId")):continue
		if Geometry.point(feet).distance_to(Geometry.point(a))>0.3:result.append(feet)
	return result
