extends RefCounted
## E owns assignment intent and arbitration; B owns task/order execution and cargo.
const Context=preload("res://scripts/actions/domain_context.gd")
const Arbitration=preload("res://scripts/runtime/workforce_arbitration.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Regional=preload("res://scripts/runtime/factory_gameplay_region.gd")
const Story=preload("res://scripts/runtime/factory_gameplay_story.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const BuildingOrders=preload("res://scripts/runtime/companion_projects.gd")
const WorkOrders=preload("res://scripts/production/module_work_orders.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Costs=preload("res://scripts/runtime/frame_costs.gd")
const KEY:="r34:workforce"
const MAX_ASSIGNMENTS:=1024
const MAX_INTERRUPTED:=2048
const MAX_EVENTS:=4096
const MAX_DEPENDENCY_REGIONS:=24
const JOB_RETRY_SECONDS:=8.0
const GROWTH_LIMIT:=100
const HAUL_SKILL:="village_hauling"
const BUILD_SKILL:="village_building"
var context:Dictionary
var _runtime:WeakRef
var _actions:WeakRef
var _production:WeakRef
var _gameplay:WeakRef
var _residents:WeakRef
var _zonework:WeakRef
var _enabled:=false
var _schema_proofs:Dictionary={}
var _growth_observed_revision:int=-1

static func initial()->Dictionary:
	return {"version":1,"assignments":[],"interrupted":[],"events":[],"building_queue":[],"next_id":1}

static func validate_state(value:Variant)->Dictionary:
	if not value is Dictionary or not Data.json_value(value) or not _whole(value.get("version")) or int(value.version)!=1:return _bad("INVALID_WORKFORCE_SCHEMA","劳动力状态版本无效")
	for key:String in ["assignments","interrupted","events"]:
		if not value.get(key) is Array:return _bad("INVALID_WORKFORCE_SCHEMA","劳动力状态列表无效："+key)
	if value.assignments.size()>MAX_ASSIGNMENTS or value.interrupted.size()>MAX_INTERRUPTED or value.events.size()>MAX_EVENTS:return _bad("WORKFORCE_LIMIT","劳动力状态超过有界容量")
	var next:Variant=value.get("next_id")
	if not _whole(next) or int(next)<1:return _bad("INVALID_WORKFORCE_SCHEMA","劳动力序号无效")
	var queue:Variant=value.get("building_queue",[])
	if not queue is Array or queue.size()>16:return _bad("WORKFORCE_LIMIT","村务待办无效")
	var growth_revision:Variant=value.get("growth_event_revision",-1)
	if not _whole(growth_revision) or int(growth_revision)<-1:return _bad("INVALID_WORKFORCE_SCHEMA","同伴成长进度无效")
	var seen:Dictionary={}
	for target:Variant in queue:
		if not _id(target) or seen.has(target):return _bad("INVALID_WORKFORCE_SCHEMA","工程待办无效或重复")
		seen[target]=true
	var actors:Dictionary={};var candidates:Dictionary={};var assignment_ids:Dictionary={}
	for item:Variant in value.assignments:
		if not item is Dictionary or not _id(item.get("actor_id")) or not _id(item.get("candidate_id")) or not _id(item.get("id")):return _bad("INVALID_WORKFORCE_SCHEMA","岗位引用无效")
		if actors.has(item.actor_id) or candidates.has(item.candidate_id) or assignment_ids.has(item.id):return _bad("WORKFORCE_SLOT_CONFLICT","一人或一个B候选不能重复占槽")
		if not _whole(item.get("sequence")) or int(item.sequence)<1 or int(item.sequence)>=int(next) or not _number(item.get("priority")) or float(item.priority)<-100 or float(item.priority)>100:return _bad("INVALID_WORKFORCE_SCHEMA","岗位排序字段无效")
		if item.get("status") not in ["requested","active","interrupted","blocked"]:return _bad("INVALID_WORKFORCE_SCHEMA","岗位状态无效")
		if not _number(item.get("created_at")) or float(item.created_at)<0:return _bad("INVALID_WORKFORCE_SCHEMA","岗位创建时间无效")
		if item.has("retry_at") and (not _number(item.retry_at) or float(item.retry_at)<0):return _bad("INVALID_WORKFORCE_SCHEMA","岗位重试时间无效")
		if item.has("region_ids"):
			if not item.region_ids is Array or item.region_ids.size()>MAX_DEPENDENCY_REGIONS:return _bad("INVALID_WORKFORCE_SCHEMA","岗位地区列表无效")
			for region:Variant in item.region_ids:
				if not _id(region):return _bad("INVALID_WORKFORCE_SCHEMA","岗位地区无效")
		actors[item.actor_id]=true;candidates[item.candidate_id]=true;assignment_ids[item.id]=true
	for row:Variant in value.interrupted:
		if not row is Dictionary or not _id(row.get("id")) or not _id(row.get("actor_id")) or not _id(row.get("candidate_id")) or not _id(row.get("reason")) or not _number(row.get("time")) or float(row.time)<0 or not _whole(row.get("resume_sequence")) or int(row.resume_sequence)<1:return _bad("INVALID_WORKFORCE_SCHEMA","岗位中断记录无效")
	var event_ids:Dictionary={}
	for event:Variant in value.events:
		if not event is Dictionary or not _id(event.get("id")) or event_ids.has(event.id) or not _id(event.get("kind")) or not _id(event.get("actor_id")) or not _number(event.get("time")) or float(event.time)<0:return _bad("INVALID_WORKFORCE_SCHEMA","工作事件身份无效")
		event_ids[event.id]=true
	return {"ok":true,"code":"OK","reason":null}

static func _bad(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
static func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
static func _whole(value:Variant)->bool:return _number(value) and float(value)==floorf(float(value))
static func _id(value:Variant)->bool:return value is String and not str(value).is_empty() and str(value).length()<=192 and not str(value).contains("..")

func configure(value:Dictionary)->void:
	context=Context.isolate(value)
	_schema_proofs.clear()
	_runtime=weakref(value.runtime)
	var services:Dictionary=value.get("services",{})
	_actions=weakref(services.actions) if services.get("actions") is RefCounted else null
	_production=weakref(services.production) if services.get("production") is RefCounted else null
	_gameplay=weakref(services.gameplay) if services.get("gameplay") is RefCounted else null
	_residents=weakref(services.residents) if services.get("residents") is RefCounted else null
	_zonework=weakref(services.zonework) if services.get("zonework") is RefCounted else null
	_enabled=context.facts.call().get("scenario")=="factory-settlement-r34"

func schema()->Dictionary:
	return {"key":KEY,"validator":Callable(self,"validate_intent"),"initial":Callable(self,"initial"),"state_validator":Callable(self,"validate_state")}

func _check_extension(id:String,overrides:Dictionary={})->Dictionary:
	var world:RefCounted=context.world
	var proposed:bool=overrides.has(id)
	var token:Dictionary=world.extension_token(id) if not proposed and world.has_method("extension_token") else {}
	var prior:Dictionary=_schema_proofs.get(id,{})
	if not token.is_empty() and prior.get("token")==token:return prior
	var source:Variant=overrides[id] if proposed else world.extension(id)
	var valid:Dictionary={"ok":true,"code":"OK","reason":null}
	if source!=null:valid=Gameplay.validate_state(source) if id==Gameplay.KEY else validate_state(source)
	var result:Dictionary={"token":token,"source":source,"valid":valid}
	# Live values are detached and read only here. Draft writes always use the
	# full validator; same-revision reloads are fenced by the generation token.
	if not token.is_empty() and valid.ok:_schema_proofs[id]=result
	return result

func validate_extensions(facts_state:Dictionary,extension_overrides:Dictionary={})->Dictionary:
	var observed_gameplay:Dictionary=_check_extension(Gameplay.KEY,extension_overrides)
	if not observed_gameplay.valid.ok:return observed_gameplay.valid
	var gameplay:Variant=observed_gameplay.source
	if gameplay!=null:
		for id:String in gameplay.get("regional_objectives",{}):
			if Regional.find_site(context,gameplay.get("layout",{}),id).is_empty():return _bad("STALE_REGIONAL_SITE","地区目标引用的持久生成地点不存在或不匹配")
		var defense:Dictionary=gameplay.defense
		if defense.status in ["active","cleared"]:
			if defense.actors.size()!=3:return _bad("INVALID_FACTORY_DEFENSE","首轮防守须是完整三名既有感染者")
			for id:String in defense.actors:
				var found:Dictionary=Draft.find(facts_state.get("actors",[]),id)
				if found.is_empty() or found.get("faction")!="infected" or found.get("encounter_id")!="r34:first-defense":return _bad("STALE_FACTORY_DEFENSE","防守引用并非本次真实生成感染者")
				if defense.status=="cleared" and float(found.get("hp",0))>0:return _bad("INVALID_FACTORY_DEFENSE","活感染者不能虚报清除")
	var observed_workforce:Dictionary=_check_extension(KEY,extension_overrides)
	if not observed_workforce.valid.ok:return observed_workforce.valid
	var value:Variant=observed_workforce.source
	if value==null:return {"ok":true,"code":"OK","reason":null}
	var actors:Dictionary={}
	for actor:Variant in facts_state.get("actors",[]):
		if actor is Dictionary:actors[str(actor.get("id",""))]=actor
	for row:Dictionary in value.assignments:
		if not actors.has(row.actor_id):return _bad("STALE_WORKFORCE_ACTOR","岗位引用的人物不存在")
		var actor:Dictionary=actors[row.actor_id]
		if float(actor.get("hp",0))<=0 or (actor.id!="player" and (not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false))):
			return _bad("WORKFORCE_CONSENT_REVOKED","岗位人物已撤回合作同意")
	return {"ok":true,"code":"OK","reason":null}

func prepare_actor_release(transitions:Array,observed:Dictionary,pending_world_changes:Array)->Dictionary:
	var before:Variant=context.world.extension(KEY)
	var source:Variant=before
	for change:Variant in pending_world_changes:
		if not change is Dictionary:return _bad("INVALID_LIFECYCLE_PLAN","劳动力暂存操作无效")
		if change.get("op")=="extension.set" and change.get("id")==KEY:
			if change.get("before_exists")!=context.world.has_extension(KEY) or not Data.json_equal(change.get("before"),before):return _bad("CAS_MISMATCH","劳动力暂存来源已变化")
			source=change.get("after")
	if source==null:return {"ok":true,"fact_changes":[],"world_changes":[],"events":[]}
	var valid:Dictionary=validate_state(source)
	if not valid.ok:return valid
	var after:Dictionary=source.duplicate(true);var affected:Dictionary={}
	for transition:Variant in transitions:
		if not transition is Dictionary or not _id(transition.get("actor_id")) or transition.get("kind") not in ["incapacitated","removed","consent_revoked"]:return _bad("INVALID_LIFECYCLE_PLAN","劳动力生命周期转换无效")
		if affected.has(transition.actor_id):return _bad("INVALID_LIFECYCLE_PLAN","重复的劳动力生命周期转换")
		var actor:Dictionary={}
		for candidate:Dictionary in observed.get("actors",[]):
			if candidate.id==transition.actor_id:actor=candidate;break
		if (transition.kind=="removed" and not actor.is_empty()) or (transition.kind!="removed" and actor.is_empty()):return _bad("INVALID_LIFECYCLE_PLAN","劳动力生命周期转换与暂存人物不符")
		affected[str(transition.actor_id)]=str(transition.kind)
	for i:int in range(after.assignments.size()-1,-1,-1):
		var row:Dictionary=after.assignments[i]
		if not affected.has(row.actor_id):continue
		after.interrupted.append({"id":row.id,"actor_id":row.actor_id,"candidate_id":row.candidate_id,"reason":affected[row.actor_id],"time":float(context.clock.call()),"resume_sequence":row.sequence})
		after.assignments.remove_at(i)
	var changes:Array=[]
	if not Data.json_equal(source,after):
		if after.interrupted.size()>MAX_INTERRUPTED:after.interrupted=after.interrupted.slice(-MAX_INTERRUPTED)
		changes.append({"op":"extension.set","id":KEY,"before_exists":context.world.has_extension(KEY),"before":before,"after":after})
	return {"ok":true,"fact_changes":[],"world_changes":changes,"events":[]}

func validate_intent(intent:Dictionary,actor_state:Dictionary={},_facts_state:Dictionary={})->Dictionary:
	if intent.get("owner")!="workforce" or intent.get("kind")!="job-request" or not _whole(intent.get("schema_version")) or int(intent.schema_version)!=1 or not _id(intent.get("id")) or not _id(intent.get("candidate_id")):return _bad("INVALID_WORKFORCE_INTENT","劳动力请求描述无效")
	if not actor_state.is_empty() and actor_state.get("id")!=intent.get("actor_id"):return _bad("INVALID_WORKFORCE_INTENT","劳动力请求人物不一致")
	return {"ok":true,"code":"OK","reason":null}

func hold_descriptors(facts:Dictionary,_extension_overrides:Dictionary={})->Array:
	# E's assignment is intent only; B emits every real action and production hold.
	return []

func _state()->Dictionary:
	var value:Variant=context.world.extension(KEY)
	return value if value is Dictionary else initial()

func _candidate(actor_id:String,candidate_id:String)->Dictionary:
	if candidate_id.begins_with(BuildingOrders.PREFIX):
		return _building_order(context.actor.call(actor_id),candidate_id)
	if _is_work_order(candidate_id):return _work_order(context.actor.call(actor_id),candidate_id)
	if candidate_id.begins_with("zonework:") or candidate_id.begins_with("zone-supply:"):
		var zonework:Variant=_zonework.get_ref() if _zonework!=null else null
		if zonework==null or not zonework.has_method("work_candidates"):return {}
		for row:Dictionary in zonework.work_candidates(actor_id):
			if row.get("id")==candidate_id and _zone_offer(row,actor_id):return row.duplicate(true)
		return {}
	var actions:Variant=_actions.get_ref() if _actions!=null else null
	if actions==null:return {}
	if actions.has_method("workforce_candidate"):return actions.workforce_candidate(actor_id,candidate_id)
	return {}

func _building_order(actor:Dictionary,id:String,project_id:String="",overrides:Dictionary={})->Dictionary:
	var modules:Variant=_runtime.get_ref().domain_service("modules")
	return BuildingOrders.inspect(modules,actor,id,project_id,overrides) if modules!=null and not actor.is_empty() else {}

static func _is_work_order(id:String)->bool:
	return id.begins_with(WorkOrders.PREFIX) or id.begins_with("logistics:")

func _work_order(actor:Dictionary,id:String,staged_facts:Dictionary={},overrides:Dictionary={})->Dictionary:
	if actor.is_empty():return {}
	var state:Variant;var order:Dictionary={};var module:Dictionary={}
	var is_recipe:bool=id.begins_with(WorkOrders.PREFIX)
	if is_recipe:
		state=overrides.get(Factory.MODULES) if overrides.has(Factory.MODULES) else context.world.extension(Factory.MODULES)
		if not state is Dictionary:return {}
		for instance:Dictionary in state.get("instances",[]):
			if not instance.get("discovered",false) or not Factory.permitted(actor,instance.owner):continue
			var found:=Draft.find(WorkOrders.rows(instance),id.trim_prefix(WorkOrders.PREFIX))
			if found.is_empty():continue
			if not order.is_empty():return {}
			order=found;module=instance
	else:
		state=overrides.get(Factory.LOGISTICS) if overrides.has(Factory.LOGISTICS) else context.world.extension(Factory.LOGISTICS)
		if not state is Dictionary:return {}
		order=Draft.find(state.get("tasks",[]),id)
	if order.is_empty():return {}
	var carrying:bool=not is_recipe and order.actor_id==actor.id and order.phase=="deliver" and order.status not in ["cancelled","completed"]
	var from_id:String=str(order.source_id);var to_id:String=str(order.output_id if is_recipe else order.destination_id)
	var endpoint_ids:Array=[to_id] if carrying else [from_id,to_id]
	var regions:Array=[];var module_ids:Array=[]
	if not module.is_empty():
		_pin_region(regions,module.region);module_ids.append(str(module.id))
	for stock_id:String in endpoint_ids:
		var stock:Dictionary=context.stock.call(stock_id) if staged_facts.is_empty() else Draft.find(staged_facts.get("stocks",[]),stock_id)
		if stock_id=="pack:"+str(actor.id):stock={"owner":actor.id,"location":Geometry.location(actor)}
		if stock.is_empty() or not stock.get("searched",true) or not Factory.permitted(actor,stock.get("owner")):return {}
		_pin_region(regions,Geometry.location(stock).get("regionId"))
		var module_id:String=str(stock.get("module_id",""))
		if not module_id.is_empty() and not module_ids.has(module_id):module_ids.append(module_id)
	var offer:Dictionary={"id":id,"kind":"recipe_order" if is_recipe else "transport_order","actor_id":actor.id,"valid":true,"phase":"queued","reason":"","carrying":carrying,"region_ids":regions,"module_id":str(module.get("id",module_ids[0] if not module_ids.is_empty() else "")),"module_ids":module_ids,"source_id":from_id,"destination_id":to_id}
	if is_recipe:
		if order.mode=="quantity" and int(order.completed)>=int(order.quantity):offer.valid=false;offer.phase="completed";offer.reason="配方订单已完成"
		elif order.paused:offer.valid=false;offer.reason="配方订单已暂停"
		elif module.status in ["ruined","dismantled"]:offer.valid=false;offer.phase="ended";offer.reason="建筑已不可使用"
		elif module.status in ["planned","constructing","damaged"]:offer.valid=false;offer.reason="等待建筑可用"
	else:
		if order.status in ["completed","cancelled"]:offer.valid=false;offer.phase="completed" if order.status=="completed" else "ended";offer.reason="运输订单已关闭"
		elif not str(order.actor_id).is_empty() and order.actor_id!=actor.id:offer.valid=false;offer.reason="已有同伴在执行此运输"
	return offer

static func _zone_offer(row:Dictionary,actor_id:String)->bool:
	if row.get("actor_id")!=actor_id:return false
	var id:String=str(row.get("id",""))
	if id.begins_with("zonework:"):return true
	# ZoneWork describes prerequisites; original B actions admits and executes
	# each current offer. Never turn a supply DTO into zone labor or a transfer.
	return id.begins_with("zone-supply:") and row.get("owner")=="actions" and row.get("executor")=="actions" and row.get("kind")=="supply"

func _work_candidates(actor_id:String,staged_facts:Dictionary={},overrides:Dictionary={})->Array:
	# One caller-owned observation per provider/actor/decision. Never keep a
	# path, inventory, consent or zone candidate across fixed steps.
	var rows:Array=[];var actions:Variant=_actions.get_ref() if _actions!=null else null
	if actions!=null and actions.has_method("workforce_candidates"):rows=actions.workforce_candidates(actor_id,staged_facts,overrides)
	var zonework:Variant=_zonework.get_ref() if _zonework!=null else null
	if zonework!=null and zonework.has_method("work_candidates"):
		var actors:Array=[actor_id]
		if actor_id=="*":
			actors=[]
			var observed:Dictionary=context.facts.call() if staged_facts.is_empty() else staged_facts
			for actor:Dictionary in observed.get("actors",[]):
				if float(actor.get("hp",0))>0 and (actor.id=="player" or (actor.get("relationship",{}).get("member",false) and actor.get("relationship",{}).get("consent",false))) and context.region_is_detailed.call(str(actor.regionId)):actors.append(str(actor.id))
		for id:String in actors:
			for row:Dictionary in zonework.work_candidates(id,staged_facts,overrides):
				if not _zone_offer(row,id):continue
				if not rows.any(func(existing:Dictionary)->bool:return existing.get("actor_id")==id and existing.get("id")==row.get("id")):rows.append(row.duplicate(true))
	return rows

func _safe_handoff(actor_id:String,candidate_id:String,staged_facts:Dictionary,overrides:Dictionary)->Dictionary:
	# Release through the CURRENT owner, then admit through the target owner.
	# Zone labor may be paused for needs/defense, never cancelled by E itself.
	var actor:Dictionary=Draft.find(staged_facts.get("actors",[]),actor_id)
	var executor:Variant
	if actor.get("intent") is Dictionary and actor.intent.get("owner")=="zonework":executor=_zonework.get_ref() if _zonework!=null else null
	else:executor=_actions.get_ref() if _actions!=null else null
	if executor==null or not executor.has_method("safe_handoff"):return _bad("WORKFORCE_EXECUTOR_UNAVAILABLE","当前作业的安全交接服务尚未装配")
	return executor.safe_handoff(actor_id,candidate_id,staged_facts,overrides)

func _prepare_work(request:Dictionary,staged_facts:Dictionary,overrides:Dictionary)->Dictionary:
	var is_zone:bool=str(request.get("candidate_id","")).begins_with("zonework:")
	var executor:Variant=(_zonework.get_ref() if _zonework!=null else null) if is_zone else (_actions.get_ref() if _actions!=null else null)
	if executor==null or not executor.has_method("prepare_workforce"):return _bad("WORKFORCE_EXECUTOR_UNAVAILABLE","目标作业的唯一执行服务尚未装配")
	return executor.prepare_workforce(request,staged_facts,overrides)

func _zone_projection(actor_id:String)->Dictionary:
	var zonework:Variant=_zonework.get_ref() if _zonework!=null else null
	if zonework==null or not zonework.has_method("projection"):return {"available":false,"owner":"zonework","jobs":[]}
	var result:Variant=zonework.projection(actor_id)
	return result.duplicate(true) if result is Dictionary and result.get("jobs") is Array else {"available":false,"owner":"zonework","jobs":[]}

func alert_projection(_actor_id:String="player")->Dictionary:
	# Same facts/helper/availability as projection().alerts, without computing
	# candidates, story commands, known map markers or complete member DTOs.
	var actions:Variant=_actions.get_ref() if _actions!=null else null
	var available:bool=_enabled and actions!=null and actions.has_method("workforce_candidates")
	var state:=_alert_state()
	return {"available":available,"alerts":_alerts({"actors":_display_actors()},state)}

func _display_actors()->Array:
	var runtime:Variant=_runtime.get_ref() if _runtime!=null else null
	return runtime.actor_states() if runtime!=null and runtime.has_method("actor_states") else context.facts.call().get("actors",[])

func _alert_state()->Dictionary:
	var world:RefCounted=context.world
	if not world.has_method("extension_fields"):
		var value:Variant=world.extension(Gameplay.KEY)
		return value if value is Dictionary else {}
	var fields:Array[String]=["defense"]
	var state:Dictionary=world.extension_fields(Gameplay.KEY,fields)
	if state.get("defense",{}).get("status") in ["warning","awaiting_execution","active"]:
		fields=["regional_objectives","layout"]
		state.merge(world.extension_fields(Gameplay.KEY,fields))
	return state

func projection(actor_id:String="player")->Dictionary:
	return _projection(actor_id,true)

func summary_projection(actor_id:String="player")->Dictionary:
	# Display-only demand boundary. Live arbitration/advance and full reads
	# retain every candidate check; an unrequested list is never "no work".
	return _projection(actor_id,false)

func hud_projection(_actor_id:String="player")->Dictionary:
	# HUD needs membership/real alerts, never house routes or candidate jobs.
	var actors:Array=_display_actors();var members:Array=[];var assignments:Dictionary={};var orders:Array=[]
	var world:RefCounted=context.world
	var fields:Array[String]=["assignments","building_queue"]
	var state:Dictionary=world.extension_fields(KEY,fields) if world.has_method("extension_fields") else _state()
	var assignment_rows:Array=state.get("assignments",[])
	for row:Dictionary in assignment_rows:
		assignments[row.actor_id]=row.id
		if str(row.candidate_id).begins_with(BuildingOrders.PREFIX) or _is_work_order(str(row.candidate_id)):orders.append(row.duplicate(true))
	for a:Dictionary in actors:
		if a.get("faction")=="infected" or (a.id!="player" and not a.get("relationship",{}).get("member",false)):continue
		members.append({"actor_id":a.id,"alive":float(a.get("hp",0))>0,"consent":a.id=="player" or a.get("relationship",{}).get("consent",false),"activity":a.get("activity",""),"assignment_id":assignments.get(a.id,"")})
	return {"available":_enabled,"members":members,"assignments":orders,"building_queue":state.get("building_queue",[]).duplicate(),"alerts":_alerts({"actors":actors},_alert_state()),"candidates_included":false,"candidates_state":"not_requested","details_state":"not_requested"}

func hud_alerts_match_alert_projection()->bool:
	# Both readers emit the same rows for this actor at this observation point.
	# Their capability flags are independent of the rows themselves.
	return true

func person_projection(actor_id:String)->Dictionary:
	# Public target details reuse the same candidate admission and DTO builder.
	# No stories, global routes, housing or other people are requested here.
	var state:Dictionary=_state();var facts:Dictionary=context.facts.call()
	var actor:Dictionary=Draft.find(facts.get("actors",[]),actor_id)
	if actor.is_empty() or actor.get("faction")=="infected" or (actor.id!="player" and not actor.get("relationship",{}).get("member",false)):return {}
	var actions:Variant=_actions.get_ref() if _actions!=null else null
	var candidates:Array=_work_candidates(actor_id) if actions!=null and actions.has_method("workforce_candidates") else []
	return _person_projection(actor,state,candidates,true)

func _person_projection(a:Dictionary,state:Dictionary,candidates:Array,include_candidates:bool)->Dictionary:
	var assignment:Dictionary={}
	for item:Dictionary in state.assignments:
		if item.actor_id==a.id:assignment=item;break
	var owned_candidates:Array=[]
	for candidate:Dictionary in candidates:
		if candidate.get("actor_id")==a.id:owned_candidates.append(candidate.duplicate(true))
	var person:Dictionary={"actor_id":a.id,"activity":a.get("activity",""),"intent":a.get("intent"),"current_owner":str(a.intent.get("owner","")) if a.get("intent") is Dictionary else "","assignment":assignment.duplicate(true),"pending_delivery":a.get("pending_delivery",{}).duplicate(true),"suspended_work":a.get("suspended_work",{}).duplicate(true),"zonework":_zone_projection(str(a.id)),"last_failure":a.get("self_routine",{}).get("last_failure",{}).duplicate(true),"last_decision":a.get("self_routine",{}).get("factory_decision",{}).duplicate(true)}
	if include_candidates:
		var carried:Dictionary=_carried_delivery(a)
		var signals:Dictionary={"actor_id":a.id,"actor_exists":true,"alive":float(a.get("hp",0))>0,"requires_consent":a.id!="player","consent":a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false),"facts_valid":true,"target_valid":true,"danger":false,"urgent_need":"","explicit_assignment":assignment,"carried_delivery":carried,"candidates":owned_candidates}
		person.candidates=owned_candidates.duplicate(true)
		person.decision=Arbitration.decide(signals)
	return person

func _projection(actor_id:String,include_candidates:bool)->Dictionary:
	var state:Dictionary=_state();var facts:Dictionary=context.facts.call()
	var candidates:Array=[];var actions:Variant=_actions.get_ref() if _actions!=null else null
	var candidate_api:bool=actions!=null and actions.has_method("workforce_candidates")
	if include_candidates and candidate_api:candidates=_work_candidates(actor_id)
	var people:Array=[]
	for a:Dictionary in facts.get("actors",[]):
		if a.get("faction")=="infected" or (a.id!="player" and not a.get("relationship",{}).get("member",false)):continue
		if actor_id!="*" and a.id!=actor_id:continue
		people.append(_person_projection(a,state,candidates,include_candidates))
	var members:Array=[]
	for a:Dictionary in facts.get("actors",[]):
		if a.get("faction")=="infected" or (a.id!="player" and not a.get("relationship",{}).get("member",false)):continue
		members.append({"actor_id":a.id,"alive":float(a.get("hp",0))>0,"consent":a.id=="player" or a.get("relationship",{}).get("consent",false),"activity":a.get("activity",""),"assignment_id":""})
	for member:Dictionary in members:
		for row:Dictionary in state.assignments:
			if row.actor_id==member.actor_id:member.assignment_id=row.id;break
	var available:bool=_enabled and candidate_api
	var story_state:Variant=context.world.extension(Gameplay.KEY)
	var stories:Array=Gameplay.story_projection(story_state,facts,context) if story_state is Dictionary else []
	var regional_event:Dictionary=regional_projection(actor_id)
	var residents:Variant=_residents.get_ref() if _residents!=null else null
	var housing:Dictionary=residents.housing_projection(actor_id) if residents!=null and residents.has_method("housing_projection") else {"available":false,"homes":[]}
	var result:Dictionary={"schema":"r34-workforce-v1","available":available,"assignments":state.assignments.duplicate(true),"members":members,"people":people,"building_queue":state.get("building_queue",[]).duplicate(),"housing":housing,"interrupted":state.interrupted.duplicate(true),"events":state.events.duplicate(true),"stories":stories,"regional_event":regional_event,"map_markers":_map_markers(facts,regional_event,stories),"alerts":_alerts(facts,story_state if story_state is Dictionary else {}),"error":null if available else {"code":"WORKFORCE_EXECUTOR_UNAVAILABLE","reason":"B岗位候选与安全交接接口尚未装配"},"world_revision":context.world.get_revision(),"runtime_revision":_runtime.get_ref().get_revision()}
	if not include_candidates:
		result.candidates_included=false
		result.candidates_state="not_requested"
	return result

func _visible_hostiles(facts:Dictionary)->Array:
	var rows:Array=[]
	var enemies:Array=facts.get("actors",[]).filter(func(actor:Dictionary)->bool:return actor.get("faction")=="infected" and float(actor.get("hp",0))>0)
	if enemies.is_empty():return rows
	var runtime:Variant=_runtime.get_ref() if _runtime!=null else null
	if runtime==null or not runtime.has_method("actor_presentation"):return rows
	# Reuse A's actual door/room/terrain sight. No second perception radius.
	var visible:Array=runtime.actor_presentation().get("visible_actor_ids",[])
	for enemy:Dictionary in enemies:
		if visible.has(enemy.id) and context.region_is_detailed.call(str(enemy.regionId)):rows.append(enemy)
	return rows

func _map_markers(facts:Dictionary,regional:Dictionary,stories:Array=[])->Array:
	var rows:Array=[]
	for actor:Dictionary in facts.get("actors",[]):
		if actor.get("faction")=="infected" or (actor.id!="player" and not actor.get("relationship",{}).get("member",false)):continue
		rows.append({"id":actor.id,"kind":"player" if actor.id=="player" else "member","title":str(actor.get("name",actor.id)),"location":Geometry.location(actor),"alive":float(actor.get("hp",0))>0})
	var gameplay: Variant = _gameplay.get_ref() if _gameplay != null else null
	if gameplay != null:
		var expedition: Dictionary = gameplay.expedition_snapshot()
		if not expedition.is_empty():
			rows.append({"id":"village:expedition:site","kind":"regional_site","title":"废弃补给站","location":expedition.site,"completed":false})
	for site:Dictionary in regional.get("sites",[]):rows.append({"id":site.id,"kind":"regional_site","title":site.title,"location":site.location.duplicate(true),"completed":site.completed})
	for story:Dictionary in stories:
		for clue:Dictionary in story.get("clues",[]):
			if not rows.any(func(row:Dictionary)->bool:return row.id==clue.id):rows.append(clue.duplicate(true))
	for actor:Dictionary in _visible_hostiles(facts):rows.append({"id":actor.id,"kind":"hostile","title":str(actor.get("name","感染者")),"location":Geometry.location(actor),"alive":true})
	return rows

func _alerts(facts:Dictionary,state:Dictionary)->Array:
	# Facts only. A owns read/ignore/resolved state and episode persistence.
	var rows:Array=[]
	var defense:Dictionary=state.get("defense",{})
	if defense.get("status") in ["warning","awaiting_execution","active"]:
		var site_id:String=str(defense.get("site_id",""))
		if state.get("regional_objectives",{}).get(site_id,{}).get("surveyed",false):
			var site:Dictionary=Regional.find_site(context,state.get("layout",{}),site_id)
			if not site.is_empty():
				var reason:String="DEFENSE_WARNING" if defense.status=="warning" else "DEFENSE_SPAWN_BLOCKED" if defense.status=="awaiting_execution" else "DEFENSE_ACTIVE"
				var detail:String="预告仍在继续；可停止作业，补给恢复后沿真实绕行通路进入防线。" if defense.status=="warning" else "当地威胁仍未解决；撤退与保存不会重置事件或剩余敌人。"
				if defense.status=="awaiting_execution":detail="真实遭遇点尚未完成生成，事件保持未解决："+str(defense.get("spawn_error",{}).get("reason","等待执行"))
				rows.append({"key":site_id+":"+reason,"object_id":site_id,"reason_code":reason,"episode_id":str(defense.get("warning_id","")),"severity":"warning" if defense.status=="warning" else "critical","location":site.survey_point.duplicate(true),"title":"地区威胁预告" if defense.status=="warning" else "地区威胁尚未解决","detail":detail})
	for actor:Dictionary in facts.get("actors",[]):
		if actor.get("faction")=="infected" or (actor.id!="player" and not actor.get("relationship",{}).get("member",false)):continue
		var reason:String="INCAPACITATED" if float(actor.get("hp",0))<=0 else "CRITICAL_HEALTH" if float(actor.get("hp",0))<=25 else "NEED_WATER" if float(actor.get("thirst",100))<35 else "NEED_FOOD" if float(actor.get("hunger",100))<35 else "NEED_REST" if float(actor.get("stamina",100))<14 else ""
		if reason.is_empty():continue
		rows.append({"key":str(actor.id)+":"+reason,"object_id":actor.id,"reason_code":reason,"severity":"critical" if reason in ["INCAPACITATED","CRITICAL_HEALTH"] else "warning","location":Geometry.location(actor),"title":str(actor.get("name",actor.id))+"："+{"INCAPACITATED":"已失能","CRITICAL_HEALTH":"伤势危急","NEED_WATER":"需要饮水","NEED_FOOD":"需要进食","NEED_REST":"需要恢复体力"}[reason],"detail":"按原有身体规则处理；须有真实可用的物资、路线与合作权限。"})
	return rows

func regional_projection(actor_id:String="player")->Dictionary:
	var state:Variant=context.world.extension(Gameplay.KEY)
	if not state is Dictionary:return {"available":false,"code":"REGIONAL_EVENT_SITE_UNAVAILABLE","sites":[]}
	var rows:Array=[]
	for site:Dictionary in Regional.sites(context,state.get("layout",{})):
		var objective:Dictionary=state.get("regional_objectives",{}).get(site.id,{})
		var observer:Dictionary=context.actor.call("player")
		if not objective.get("surveyed",false) and (observer.is_empty() or Geometry.point(observer).distance_to(Geometry.point(site.survey_point))>2.2 or not context.region_is_detailed.call(str(site.region_id)) or not context.spatial.current_space().line_clear(Geometry.location(observer),site.survey_point,"")):continue
		var actions:Array=[]
		for kind:String in ["settlement.survey","settlement.begin_route_work"]:
			var request:Dictionary={"kind":kind,"actor_id":actor_id,"payload":{"site_id":site.id,"accept_risk":true}}
			var ready:Dictionary=Regional.availability(context,state,request)
			actions.append({"kind":kind,"available":ready.ok,"code":ready.get("code","OK"),"reason":ready.get("reason"),"payload":request.payload.duplicate(true),"requires_confirmation":kind=="settlement.begin_route_work"})
		rows.append({"id":site.id,"kind":site.kind,"location":site.survey_point.duplicate(true),"title":"镇向道路塌石","description":"侧肩仍可步行绕过。开始清障会产生动静并触发当地威胁；可松开工具停工撤回，预告仍继续。确认前准备好食水、恢复与防守安排，不必在预告内清完塌石。","defense_position":site.get("warning_points",{}).get("approach_after",{}).duplicate(true),"surveyed":objective.get("surveyed",false),"risk_accepted":objective.get("risk_accepted",false),"corridor_clear":objective.get("corridor_clear",false),"completed":objective.get("completed",false),"warning_basis":objective.get("warning_basis",{}).duplicate(true),"commands":actions})
	var known_defense:Dictionary=state.defense.duplicate(true)
	known_defense.erase("encounter_positions")
	var visible:Array=_visible_hostiles(context.facts.call()).map(func(actor:Dictionary)->String:return str(actor.id))
	known_defense.actors=known_defense.get("actors",[]).filter(func(id:String)->bool:return visible.has(id))
	return {"available":not rows.is_empty(),"code":"OK" if not rows.is_empty() else "REGIONAL_EVENT_SITE_UNAVAILABLE","sites":rows,"defense":known_defense}

func _carried_delivery(actor:Dictionary)->Dictionary:
	var delivery:Variant=actor.get("pending_delivery")
	if not delivery is Dictionary or delivery.is_empty():return {}
	# Only B can prove a receiver's capacity and safe cargo handoff. Querying UI
	# must not launch route searches or turn a manifest into physical cargo.
	return {"reachable":false,"capacity_valid":false,"delivery":delivery.duplicate(true)}

func availability(request:Dictionary)->Dictionary:
	if str(request.get("kind","")).begins_with("settlement."):
		if not _enabled:return _bad("SCENARIO_UNAVAILABLE","地区事件只服务R3.4场景")
		if request.kind=="settlement.read_story":return Story.read_availability(context.merged({"story_social":Callable(_runtime.get_ref(),"life_availability")}),context.world.extension(Gameplay.KEY),request,_production.get_ref())
		return Regional.availability(context,context.world.extension(Gameplay.KEY),request)
	var payload:Dictionary=request.get("payload",{}).duplicate(true)
	if not payload.has("candidate_id") and request.has("candidate_id"):payload.candidate_id=request.candidate_id
	if not payload.has("priority") and request.has("priority"):payload.priority=request.priority
	if not request.get("kind") is String or request.kind not in ["workforce.assign","workforce.clear","workforce.priority","workforce.queue_building","workforce.cancel_building"]:return _bad("INVALID_WORKFORCE_COMMAND","劳动力命令无效")
	if not _enabled:return _bad("SCENARIO_UNAVAILABLE","R3.4劳动力只在factory-settlement-r34运行")
	if not _id(request.get("actor_id")):return _bad("INVALID_ACTOR","岗位人物身份无效")
	var actor:Dictionary=context.actor.call(str(request.actor_id))
	if actor.is_empty() or float(actor.get("hp",0))<=0:return _bad("ACTOR_UNAVAILABLE","岗位人物无法行动")
	if actor.id!="player" and (not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false) or (not _at_home(actor) and not actor.get("relationship",{}).get("home_arrived",false))):return _bad("NO_CONSENT","需要已自愿同行并实际返家的成员")
	var state:Dictionary=_state()
	if request.kind in ["workforce.queue_building","workforce.cancel_building"]:
		var target:Variant=request.get("target_id")
		if actor.id!="player" or not _id(target):return _bad("INVALID_CANDIDATE","请选择要安排的建筑")
		var queue:Array=state.get("building_queue",[])
		if request.kind=="workforce.cancel_building":
			return {"ok":true} if queue.has(target) else _bad("CANDIDATE_UNAVAILABLE","工程已经离开待办")
		if queue.has(target) or state.assignments.any(func(row:Dictionary)->bool:return row.get("module_id")==target and row.has("building_phase") and row.building_phase not in ["ended","completed"]):
			return _bad("BUILDING_ALREADY_ASSIGNED","这座建筑已安排工程")
		if queue.size()>=16:return _bad("WORKFORCE_LIMIT","村务待办已满")
		if not _building_order(actor,BuildingOrders.PREFIX+target).get("valid",false):
			return _bad("CANDIDATE_UNAVAILABLE","当前建筑没有可安排的工程")
		return {"ok":true}
	var exists:=false
	for item:Dictionary in state.assignments:
		if item.actor_id==actor.id:exists=true
	if request.kind=="workforce.assign":
		if not _id(payload.get("candidate_id")):return _bad("INVALID_CANDIDATE","payload.candidate_id必须引用B的稳定候选ID")
		for item:Dictionary in state.assignments:
			if item.actor_id==actor.id and item.has("building_phase") and item.get("building_phase") not in ["completed","ended"]:
				return _bad("BUILDING_ORDER_PENDING","这名同伴已有工程，请先完工或从工程卡撤下负责人")
		if str(payload.candidate_id).begins_with(BuildingOrders.PREFIX):
			for item:Dictionary in state.assignments:
				if item.candidate_id==payload.candidate_id and item.actor_id!=actor.id and item.get("building_phase") not in ["completed","ended"]:return _bad("BUILDING_ALREADY_ASSIGNED","已有同伴负责，请先从工程卡撤下原负责人")
		else:
			for item:Dictionary in state.assignments:
				if item.candidate_id==payload.candidate_id and item.actor_id!=actor.id and item.get("work_phase") not in ["completed","ended"]:return _bad("WORK_ALREADY_ASSIGNED","这项工作已有同伴负责")
		var candidate:Dictionary=_candidate(actor.id,str(payload.candidate_id))
		if candidate.is_empty():return _bad("CANDIDATE_UNAVAILABLE","B尚未提供有效岗位／物流候选；未占槽")
		if not candidate.get("valid",false) and not (candidate.get("kind")=="recipe_order" and candidate.get("phase")=="queued"):return _bad("CANDIDATE_BLOCKED",str(candidate.get("reason","候选当前不可执行")))
		if not Arbitration.valid_candidate(candidate):return _bad("INVALID_CANDIDATE","B候选排序字段无效")
		if not exists and state.assignments.size()>=MAX_ASSIGNMENTS:return _bad("WORKFORCE_LIMIT","岗位队列已满")
		var priority:Variant=payload.get("priority",0)
		if not _number(priority) or float(priority)<-100 or float(priority)>100:return _bad("INVALID_PRIORITY","玩家优先级须在-100至100之间")
	elif not exists:return _bad("NO_ASSIGNMENT","人物没有E岗位选择")
	if request.kind=="workforce.priority" and (not _number(payload.get("priority")) or float(payload.priority)<-100 or float(payload.priority)>100):return _bad("INVALID_PRIORITY","玩家优先级须在-100至100之间")
	if request.kind=="workforce.clear":
		var item:Dictionary=state.assignments.filter(func(row:Dictionary)->bool:return row.actor_id==actor.id)[0]
		var candidate:Dictionary=_candidate(actor.id,str(item.candidate_id))
		if candidate.get("carrying",false):return _bad("CARGO_HANDOFF_REQUIRED","已取货须先完成可达交付或由B确认安全交接")
	return {"ok":true,"code":"OK","reason":null}

func prepare(request:Dictionary)->Dictionary:
	var ready:Dictionary=availability(request)
	if not ready.ok:return ready
	if str(request.get("kind","")).begins_with("settlement."):
		var tx:=Draft.new(context.merged({"story_social":Callable(_runtime.get_ref(),"life_availability")}));var state:Dictionary=tx.extension(Gameplay.KEY)
		var plan:Dictionary=Story.prepare_read(tx,state,request,_production.get_ref()) if request.kind=="settlement.read_story" else Regional.prepare(tx,state,request,_actions.get_ref())
		return tx.result() if plan.ok else plan
	var payload:Dictionary=request.get("payload",{}).duplicate(true)
	if not payload.has("candidate_id") and request.has("candidate_id"):payload.candidate_id=request.candidate_id
	if not payload.has("priority") and request.has("priority"):payload.priority=request.priority
	var before:Dictionary=_state();var after:Dictionary=before.duplicate(true);var actor_id:String=request.actor_id
	var tx:=Draft.new(context)
	if request.kind in ["workforce.queue_building","workforce.cancel_building"]:
		var queue:Array=after.get("building_queue",[])
		if request.kind=="workforce.queue_building":queue.append(request.target_id)
		else:queue.erase(request.target_id)
		after.building_queue=queue
		tx.extensions[KEY]=after
		tx.events.append({"kind":"workforce-assignment-changed","actor_id":actor_id})
		return tx.result()
	var index:int=-1
	for i:int in after.assignments.size():
		if after.assignments[i].actor_id==actor_id:index=i;break
	if request.kind=="workforce.assign":
		var candidate_id:String=payload.candidate_id
		var candidate:Dictionary=_candidate(actor_id,candidate_id)
		if candidate.get("carrying",false):return _bad("CARGO_HANDOFF_REQUIRED","候选携货仍由原人物承担")
		if candidate.get("kind") in ["building_order","recipe_order","transport_order"]:
			after.assignments=after.assignments.filter(func(item:Dictionary)->bool:return item.candidate_id!=candidate_id or item.actor_id==actor_id)
			index=-1
			for i:int in after.assignments.size():
				if after.assignments[i].actor_id==actor_id:index=i;break
		if index>=0:after.assignments.remove_at(index)
		var id:="workforce:"+str(after.next_id)
		var row:Dictionary={"id":id,"actor_id":actor_id,"candidate_id":candidate_id,"priority":float(payload.get("priority",0)),"sequence":int(after.next_id),"status":"requested","created_at":float(context.clock.call()),"source_runtime_revision":int(_runtime.get_ref().get_revision()),"source_world_revision":int(context.world.get_revision())}
		if candidate.get("kind")=="building_order":
			row.module_id=candidate.module_id;row.region_id=candidate.region_id;row.project_id=candidate.project_id;row.building_phase="queued"
			after.get("building_queue",[]).erase(candidate.module_id)
		elif _is_work_order(candidate_id):
			row.work_phase="queued";row.work_kind=candidate.kind;row.module_id=candidate.module_id;row.module_ids=candidate.module_ids;row.region_ids=candidate.region_ids
			if not candidate.valid:row.work_phase="blocked";row.work_reason=candidate.reason
		after.next_id=int(after.next_id)+1;after.assignments.append(row)
		after.events.append({"id":id,"kind":"assignment-requested","actor_id":actor_id,"candidate_id":candidate_id,"time":float(context.clock.call())})
	elif request.kind=="workforce.clear":
		var row:Dictionary=after.assignments[index]
		var a:Dictionary=tx.actor(actor_id);var intent:Variant=a.get("intent")
		if not str(row.get("project_id","")).is_empty() and intent is Dictionary and (intent.get("project_id")==row.project_id or intent.get("workforce_candidate_id")=="module-project:"+str(row.project_id)):
			var handoff:Dictionary=_safe_handoff(actor_id,"",tx.staged,tx.extensions)
			if not handoff.get("ok",false):return handoff
			var merged:Dictionary=_merge_prepared(tx,handoff)
			if not merged.ok:return merged
		after.interrupted.append({"id":row.id,"actor_id":actor_id,"candidate_id":row.candidate_id,"reason":"player-cleared","time":float(context.clock.call()),"resume_sequence":row.sequence})
		after.assignments.remove_at(index)
		after.events.append({"id":"workforce:"+str(after.next_id),"kind":"assignment-cleared","actor_id":actor_id,"candidate_id":row.candidate_id,"time":float(context.clock.call())});after.next_id=int(after.next_id)+1
	else:
		after.assignments[index].priority=float(payload.priority)
	var checked:Dictionary=validate_state(after)
	if not checked.ok:return checked
	tx.extensions[KEY]=after
	tx.events.append({"kind":"workforce-assignment-changed","actor_id":actor_id})
	return tx.result()

func _at_home(actor:Dictionary,layout:Dictionary={})->bool:
	if layout.is_empty():layout=context.world.extension(Gameplay.KEY).get("layout",{})
	if layout.is_empty() or not layout.get("home") is Dictionary:return false
	var home:Dictionary=layout.home
	return actor.get("regionId")==home.get("regionId") and Vector2(float(actor.get("x",0))-float(home.get("x",0)),float(actor.get("z",0))-float(home.get("z",0))).length()<=float(layout.get("home_radius",18.0))

func event_dependency_regions()->Array:
	# Pure input to A's common pause/pin boundary; never infer a radius or load
	# anything here. Production and combat must share these actual dependencies.
	var regions:Array=[]
	var zone_workers:Dictionary={}
	for row:Dictionary in _state().assignments:
		if row.get("building_phase") not in ["completed","ended"] and row.get("work_phase") not in ["completed","ended"]:
			_pin_region(regions,row.get("region_id"))
			for region:Variant in row.get("region_ids",[]):_pin_region(regions,region)
	var zones:Variant=context.world.extension("r34:zones")
	if zones is Dictionary:
		var plans:Array=zones.get("zones",[])
		for index:int in range(plans.size()-1,-1,-1):
			var zone:Dictionary=plans[index]
			var workers:Array=zone.policy.get("worker_ids",[])
			var mode:String=str(zone.policy.get("mode",""))
			if not zone.enabled or workers.size()!=1 or mode not in ["harvest_only","collect_ground"] or zone_workers.has(workers[0]):continue
			var actor:Dictionary=context.actor.call(str(workers[0]))
			if actor.is_empty() or not float(actor.hp)>0 or not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false):continue
			zone_workers[workers[0]]=true
			_pin_region(regions,zone.get("region_id"))
			for region:Variant in zone.get("region_ids",[]):_pin_region(regions,region)
			if mode=="collect_ground":
				var receiver:Dictionary=context.stock.call(str(zone.policy.get("target_stock_id","")))
				var region:String=str(Geometry.location(receiver).get("regionId",""))
				_pin_region(regions,region)
	var event:Variant=context.world.extension(Gameplay.KEY)
	if not event is Dictionary or event.get("defense",{}).get("status") not in ["warning","awaiting_execution","active"]:return regions
	for anchor:Variant in [event.get("layout",{}).get("home"),event.get("layout",{}).get("defense_position")]:
		if anchor is Dictionary and _id(anchor.get("regionId")) and not regions.has(anchor.regionId):regions.append(anchor.regionId)
	for id:String in event.defense.get("actors",[]):
		var actor:Dictionary=context.actor.call(id)
		if not actor.is_empty() and not regions.has(actor.regionId):regions.append(actor.regionId)
	for anchor:Dictionary in event.defense.get("encounter_positions",[]):
		if not regions.has(anchor.regionId):regions.append(anchor.regionId)
	var site:Dictionary=Regional.find_site(context,event.get("layout",{}),str(event.defense.get("site_id","")))
	if not site.is_empty() and not regions.has(site.region_id):regions.append(site.region_id)
	return regions

static func _pin_region(regions:Array,id:Variant)->void:
	if regions.size()<MAX_DEPENDENCY_REGIONS and _id(id) and not regions.has(id):regions.append(id)

func site_work_permission(request:Dictionary)->Dictionary:
	if not _enabled:return {"ok":true,"code":"OK","reason":null}
	return Regional.permission(context,context.world.extension(Gameplay.KEY),request)

func advance(dt:float)->Dictionary:
	if not _enabled:return {"ok":true,"world_changes":[],"fact_changes":[],"events":[]}
	if not is_finite(float(dt)) or float(dt)<=0 or float(dt)>1:return {"ok":false,"code":"INVALID_STEP","reason":"劳动力由A同一时钟推进"}
	var observed_workforce:Dictionary=_check_extension(KEY)
	var state:Dictionary=observed_workforce.source if observed_workforce.source is Dictionary else initial()
	var valid:Dictionary=observed_workforce.valid
	if not valid.ok:return {"ok":false,"code":valid.code,"reason":valid.reason}
	# Companion orders update their phases during prepare. Keep these writes
	# outside the cached schema proof until the authority accepts the plan.
	var updates_orders:bool=not state.get("building_queue",[]).is_empty() or state.assignments.any(func(row:Dictionary)->bool:return row.has("building_phase") or row.has("work_phase"))
	if updates_orders:state=state.duplicate(true)
	var tx:=Draft.new(context)
	var started:int=Costs.begin()
	var observed:Dictionary=Gameplay.advance_in(tx,float(context.clock.call()),dt)
	Costs.end("workforce/story",started)
	if not observed.ok:return observed
	var gameplay:Variant=_gameplay.get_ref() if _gameplay!=null else null
	var event_state:Dictionary=tx.extension(Gameplay.KEY,Gameplay.initial_state())
	if int(event_state.get("layout",{}).get("content_version",0))>=20:
		var growth_revision:=_observe_companion_growth(tx,int(state.get("growth_event_revision",-1)))
		if growth_revision>int(state.get("growth_event_revision",-1)):
			if not updates_orders:state=state.duplicate(true)
			state.growth_event_revision=growth_revision
			tx.extensions[KEY]=state
	var defense:Dictionary=event_state.defense
	if defense.status=="awaiting_execution" and float(context.clock.call())>=float(defense.get("next_spawn_attempt",0)):
		var points:Array=defense.get("encounter_positions",[])
		var anchor:Variant=points[0] if not points.is_empty() else event_state.get("layout",{}).get("defense_position")
		if gameplay!=null and gameplay.has_method("prepare_defense_spawn") and anchor is Dictionary:
			var encounter:Dictionary={"id":"r34:first-defense","position":anchor.duplicate(true),"positions":points.duplicate(true),"actors":[]}
			var spawned:Dictionary=gameplay.prepare_defense_spawn(tx,encounter)
			if spawned.get("ok",false):
				defense.status="active";defense.actors=encounter.actors.duplicate(true);defense.erase("spawn_error");defense.erase("next_spawn_attempt")
				tx.events.append({"kind":"settlement-defense-started","actor_id":"player","warning_id":defense.warning_id})
			else:
				defense.spawn_error={"code":str(spawned.get("code","SPAWN_FAILED")),"reason":str(spawned.get("reason","真实站位不可用"))};defense.next_spawn_attempt=float(context.clock.call())+3.0
	var residents:Variant=_residents.get_ref() if _residents!=null else null
	started=Costs.begin()
	if residents!=null and residents.has_method("prepare_factory_person"):
		var original:Array=state.assignments.duplicate(true) if updates_orders else []
		var now:float=context.clock.call()
		var dispatched:=false
		if not state.get("building_queue",[]).is_empty():dispatched=_dispatch_building_queue(tx,state,now)
		_advance_survival(tx,residents,dt,now,state)
		if dispatched or (updates_orders and not Data.json_equal(state.assignments,original)):tx.extensions[KEY]=state
	Costs.end("workforce/resident_survival",started)
	# B alone turns work candidates into task/action intents once its prepared
	# safe-handoff API is available. E self-care reuses existing A/B rules.
	started=Costs.begin()
	var result:Dictionary=tx.result()
	Costs.end("workforce/plan_diff",started)
	return result

func _observe_companion_growth(tx:RefCounted,committed_revision:int)->int:
	var ledger:Array=tx.read_facts().get("ledger",[])
	if ledger.is_empty():return committed_revision
	var through:int=maxi(committed_revision,_growth_observed_revision)
	var newest:int=int(ledger.back().get("revision",-1))
	if newest<=through:return committed_revision
	var earned:bool=false
	for index:int in range(ledger.size()-1,-1,-1):
		var receipt:Dictionary=ledger[index]
		if int(receipt.get("revision",-1))<=through:break
		var skill:=_receipt_skill(receipt)
		if skill.is_empty():continue
		var id:String=str(receipt.get("actor_id",""))
		if id in ["","player"]:continue
		var known:=Draft.find(tx.read_facts().get("actors",[]),id)
		if not known.get("relationship",{}).get("member",false):continue
		var actor:Dictionary=tx.actor(id)
		var points:int=2 if skill==BUILD_SKILL else 1
		var skills:Dictionary=actor.get("skills",{})
		skills[skill]=mini(GROWTH_LIMIT,int(skills.get(skill,0))+points)
		actor.skills=skills
		earned=true
	# Wait for the stored cursor after a paid outcome. An authority rejection
	# must leave that receipt eligible for the next step.
	if earned:return newest
	_growth_observed_revision=newest
	return committed_revision

static func _receipt_skill(receipt:Dictionary)->String:
	if receipt.get("kind")=="logistics-delivery-completed" and receipt.get("source_id")==receipt.get("destination_id"):return ""
	if receipt.get("kind")=="logistics-delivery-completed" and receipt.get("items",{}).values().any(func(q:Variant)->bool:return _number(q) and float(q)>0):return HAUL_SKILL
	if receipt.get("kind")=="module-project-completed" and receipt.get("operation") in ["build","restore","upgrade"]:return BUILD_SKILL
	return ""

static func _skill_level(actor:Dictionary,skill:String)->int:
	var points:int=int(actor.get("skills",{}).get(skill,0))
	return 2 if points>=6 else 1 if points>=2 else 0

func _dispatch_building_queue(tx:RefCounted,state:Dictionary,now:float)->bool:
	var queue:Array=state.building_queue
	var workers:Array=tx.staged.get("actors",[]).filter(func(actor:Dictionary)->bool:
		var relation:Dictionary=actor.get("relationship",{})
		return actor.id!="player" and float(actor.get("hp",0))>0 and relation.get("member",false) and relation.get("consent",false) and (_at_home(actor) or relation.get("home_arrived",false)) and not actor.get("expedition_follow",false) and actor.get("intent")==null and _carried_delivery(actor).is_empty())
	workers = workers.filter(func(actor:Dictionary)->bool:
		var index:int=state.assignments.find_custom(func(row:Dictionary)->bool:return row.actor_id==actor.id)
		var current:Dictionary=state.assignments[index] if index>=0 else {}
		return current.is_empty() or current.get("building_phase",current.get("work_phase","")) in ["completed","ended"])
	workers.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		var skill_a:=_skill_level(a,BUILD_SKILL)
		var skill_b:=_skill_level(b,BUILD_SKILL)
		if skill_a!=skill_b:return skill_a>skill_b
		var preferred_a:bool=a.get("role_id")=="woodworker_repair"
		var preferred_b:bool=b.get("role_id")=="woodworker_repair"
		return preferred_a if preferred_a!=preferred_b else a.id<b.id)
	var modules:Variant=_runtime.get_ref().domain_service("modules")
	if modules==null:return false
	var changed:=false
	for target:String in queue.duplicate():
		var candidate_id:String=BuildingOrders.PREFIX+target
		var assigned:Dictionary={}
		for row:Dictionary in state.assignments:
			if row.candidate_id!=candidate_id:continue
			assigned=row
			break
		if not assigned.is_empty() and assigned.get("building_phase") not in ["completed","ended"]:continue
		var building:Dictionary=modules.instance(target,tx.extensions)
		if BuildingOrders.queue_is_finished(modules,building,tx.extensions):
			queue.erase(target)
			changed=true
			continue
		for worker:Dictionary in workers:
			var order:=_building_order(worker,candidate_id,"",tx.extensions)
			if not order.get("valid",false):continue
			if not assigned.is_empty():state.assignments.erase(assigned)
			var index:int=state.assignments.find_custom(func(row:Dictionary)->bool:return row.actor_id==worker.id)
			if index>=0:state.assignments.remove_at(index)
			var id:="workforce:"+str(state.next_id)
			state.assignments.append({"id":id,"actor_id":worker.id,"candidate_id":candidate_id,"priority":0.0,
				"sequence":int(state.next_id),"status":"requested","created_at":now,"module_id":target,
				"region_id":order.region_id,"project_id":order.project_id,"building_phase":"queued"})
			state.next_id=int(state.next_id)+1
			queue.erase(target)
			tx.events.append({"kind":"workforce-assignment-changed","actor_id":worker.id})
			return true
	return changed

static func _read_number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))

func _guard_candidate(actor:Dictionary,tx:RefCounted)->Dictionary:
	if not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false) or actor.get("job")!="guard" or float(actor.get("stamina",0))<14:return {}
	var state:Dictionary=tx.extension(Gameplay.KEY)
	var defense:Dictionary=state.get("defense",{})
	if defense.get("status") not in ["warning","awaiting_execution","active"]:return {}
	var site:Dictionary=Regional.find_site(context,state.get("layout",{}),str(defense.get("site_id","")))
	if site.is_empty():return {}
	# The far approach is a persistent C warning point, outside the stone volume.
	# B rechecks exact whitelist, support, consent and the actual route on admit.
	var position:Variant=site.get("warning_points",{}).get("approach_after")
	if not position is Dictionary or not context.region_is_detailed.call(str(position.regionId)):return {}
	return {"id":"guard:"+str(site.id),"kind":"guard","site_id":site.id,"position":position.duplicate(true),"authorized":true,"qualified":true,"at_position":actor.get("intent")==null and actor.regionId==position.regionId and Geometry.point(actor).distance_to(Geometry.point(position))<=0.2}

func _advance_survival(tx:RefCounted,residents:RefCounted,dt:float,now:float,workforce_state:Dictionary={})->void:
	var selection_started := Costs.begin()
	var due:Array=[];var actions:Variant=_actions.get_ref() if _actions!=null else null
	var layout:Dictionary=tx.extension(Gameplay.KEY).get("layout",{})
	# Reuse only this advance's validated snapshot. Prepared handoffs merge
	# after selection, so every actor still sees the same assignment revision.
	if workforce_state.is_empty():workforce_state=_state()
	var work_api:bool=actions!=null and actions.has_method("prepare_workforce") and actions.has_method("safe_handoff") and actions.has_method("workforce_candidates")
	var wake_revision:int=-1
	for event:Dictionary in tx.read_facts().get("ledger",[]):
		var kind:String=str(event.get("kind",""))
		if kind.begins_with("factory-") or kind.begins_with("module-") or kind.begins_with("logistics-") or kind.begins_with("zone-") or kind.begins_with("zonework-") or kind.begins_with("ecology-") or kind in ["inventory-transfer","consent","invite","combat-hit","workforce-assignment-changed"]:wake_revision=maxi(wake_revision,int(event.get("revision",-1)))
	for a:Dictionary in tx.writable_collection("actors"):
		if a.id=="player" or a.get("faction")=="infected" or a.get("expedition_follow",false) or float(a.get("hp",0))<=0:continue
		if not context.region_is_detailed.call(str(a.regionId)):continue
		var emergency:Dictionary=_guard_candidate(a,tx) if actions!=null and actions.has_method("prepare_guard") else {}
		if a.get("intent") is Dictionary and a.intent.get("owner")=="residents":
			var walking_signals:Dictionary=residents.factory_signals(a,tx)
			var purpose:String=str(a.intent.get("purpose",""))
			if (walking_signals.danger and purpose!="avoid") or (not walking_signals.danger and not str(walking_signals.urgent_need).is_empty() and purpose in ["watch","return-home","village-stroll"]) or (not emergency.is_empty() and purpose!="avoid"):
				walking_signals.emergency=emergency
				walking_signals.merge({"actor_id":a.id,"actor_exists":true,"alive":true,"requires_consent":false},true)
				due.append({"id":a.id,"decision":Arbitration.decide(walking_signals),"work_api":work_api})
				continue
			if purpose=="village-stroll" and wake_revision>int(a.self_routine.get("factory_wake_revision",-1)):
				a.intent=null
			else:
				var measured:int=Costs.begin()
				residents.prepare_factory_person(tx,str(a.id),dt,now,false,layout)
				Costs.end("workforce/continue_resident",measured)
				continue
		# B owns both travel and module labor. Either must yield through the same
		# prepared safe handoff when danger or an urgent bodily need interrupts.
		if a.get("intent") is Dictionary and a.intent.get("owner") not in ["actions","modules","zonework"]:continue
		var routine:Dictionary=a.get("self_routine",{})
		if now<float(routine.get("next_decision",0)) and wake_revision<=int(routine.get("factory_wake_revision",-1)):continue
		var signals:Dictionary=residents.factory_signals(a,tx)
		signals.merge({"actor_id":a.id,"actor_exists":true,"alive":true,"requires_consent":false,"consent":true},true)
		var urgent:bool=signals.danger or not str(signals.urgent_need).is_empty()
		var yieldable:bool=false
		if a.get("intent") is Dictionary and a.intent.get("owner")=="zonework":
			# B performs the O(1) current-work lookup against THIS observation.
			# Only a real blocked job may seek compatible work; working/walking
			# and manually paused jobs never cause candidate churn or auto-resume.
			var zonework:Variant=_zonework.get_ref() if _zonework!=null else null
			if zonework!=null and zonework.has_method("workforce_status"):
				var status:Dictionary=zonework.workforce_status(str(a.id),tx.staged,tx.extensions)
				yieldable=status.get("yieldable",false) and not status.get("manual_paused",false)
		if a.get("intent")!=null and not urgent and not yieldable:
			if emergency.is_empty() or (a.intent.get("owner")=="actions" and a.intent.get("kind")=="guard" and a.intent.get("guard_site_id")==emergency.site_id):continue
		var cooperating:bool=a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false)
		var candidates:Array=[]
		# N1/N2 never inspect work candidates. Keep all live safety/need/
		# guard signals above. N3 still needs the original cargo availability
		# query before the pending-delivery admission check below.
		if not urgent and work_api and cooperating and (_at_home(a,layout) or a.get("relationship",{}).get("home_arrived",false) or a.get("pending_delivery",{}).has("task_id")):
			var candidate_facts:Dictionary=tx.staged;var candidate_extensions:Dictionary=tx.extensions
			if yieldable and emergency.is_empty():
				# B correctly rejects ACTOR_BUSY against the current blocked intent.
				# Observe its prepared safe release, without merging or fabricating an
				# idle actor. The selected replacement is admitted again below against
				# a fresh handoff; rejection leaves the original job and holds intact.
				var observation:Dictionary=_safe_handoff(str(a.id),"",tx.staged,tx.extensions)
				if not observation.get("ok",false):continue
				candidate_facts=_facts_after(tx,observation)
				candidate_extensions=_extensions_after(tx,observation)
			var measured:int=Costs.begin()
			candidates=_work_candidates(str(a.id),candidate_facts,candidate_extensions)
			var occupied:Dictionary={}
			for row:Dictionary in workforce_state.assignments:
				if row.actor_id==a.id or row.get("building_phase") in ["completed","ended"] or row.get("work_phase") in ["completed","ended"]:continue
				occupied[row.candidate_id]=true
				if not str(row.get("project_id","")).is_empty():occupied["module-project:"+str(row.project_id)]=true
			var cooldowns:Dictionary=routine.get("work_retry_at",{})
			candidates=candidates.filter(func(c:Dictionary)->bool:return c.get("carrying",false) or (not occupied.has(c.id) and now>=float(cooldowns.get(c.id,0))))
			Costs.end("workforce/candidates",measured)
		var explicit:Dictionary={};var carried:Dictionary={}
		for row:Dictionary in workforce_state.assignments:
			if row.actor_id!=a.id:continue
			if str(row.candidate_id).begins_with(BuildingOrders.PREFIX):
				if row.get("building_phase") in ["completed","ended"]:break
				var order:=_building_order(a,str(row.candidate_id),str(row.get("project_id","")),tx.extensions)
				if order.is_empty() or order.get("phase") in ["completed","ended"]:
					row.building_phase=order.get("phase","ended");row.erase("building_reason");break
				if not urgent and cooperating:
					order.assignment_id=row.id
					order.deferred=true
					if not context.region_is_detailed.call(order.region_id):order.valid=false;order.reason="等待目标地区加载"
					if now<float(row.get("retry_at",0)):order.valid=false;order.reason=row.get("building_reason","")
					if not order.valid:
						row.building_phase="blocked";row.building_reason=str(order.reason)
						# The normal project candidate points at this same blocked order.
						var pending_project_id:String="module-project:"+str(order.get("project_id",row.get("project_id","")))
						candidates=candidates.filter(func(c:Dictionary)->bool:return c.id!=pending_project_id)
					explicit=order
				break
			if _is_work_order(str(row.candidate_id)):
				if urgent or not cooperating:break
				var order:=_work_order(a,str(row.candidate_id),tx.staged,tx.extensions)
				if order.is_empty() or order.phase in ["completed","ended"]:
					if row.has("work_phase"):row.work_phase=order.get("phase","ended");row.work_reason=order.get("reason","原订单已不可用")
					break
				if row.has("work_phase"):
					row.region_ids=order.region_ids;row.module_id=order.module_id;row.module_ids=order.module_ids
					order.assignment_id=row.id;order.deferred=true
					for region:String in order.region_ids:
						if not context.region_is_detailed.call(region):order.valid=false;order.reason="等待作业地区加载";break
					if now<float(row.get("retry_at",0)):order.valid=false;order.reason=row.get("work_reason","")
					if order.kind=="transport_order" and order.valid:
						var actual:=Draft.find(candidates,str(order.id))
						if not actual.get("valid",false):order.valid=false;order.reason=str(actual.get("reason","等待可用取送路线"))
					if not order.valid:
						row.work_phase="blocked";row.work_reason=str(order.reason)
						candidates=candidates.filter(func(c:Dictionary)->bool:return c.get("carrying",false) or c.id!=order.id)
					explicit=order
					break
			for candidate:Dictionary in candidates:
				if candidate.id==row.candidate_id:explicit=candidate.duplicate(true);break
			if explicit.is_empty():explicit={"id":row.candidate_id,"valid":false,"reason":"candidate_unavailable"}
		for candidate:Dictionary in candidates:
			if candidate.get("carrying",false):carried=candidate.duplicate(true);carried.reachable=candidate.valid;carried.capacity_valid=candidate.valid;break
		# Physical in-transit goods keep their delivery slot before ordinary work.
		# A new explicit job still needs B to prove that changing it is safe.
		if not carried.is_empty() and explicit.get("id")==carried.id:explicit={}
		signals.explicit_assignment=explicit;signals.carried_delivery=carried;signals.candidates=candidates;signals.emergency=emergency
		var decision:Dictionary=Arbitration.decide(signals)
		if decision.priority in ["N4","N5","N6","N7"] and residents.teaching_target_reserved(a,tx):
			decision={"priority":"N7","action":"idle","reason":"teaching_target_reserved","candidate":{}}
		if not urgent and (a.has("suspended_work") or (a.get("pending_delivery") is Dictionary and not a.pending_delivery.is_empty() and carried.is_empty())):continue
		due.append({"id":a.id,"decision":decision,"work_api":work_api,"carried":carried})
	Costs.end("workforce/select_due", selection_started)
	if due.is_empty():return
	due.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.decision.priority!=b.decision.priority:return a.decision.priority<b.decision.priority
		return str(a.id)<str(b.id))
	var selected:Dictionary=due[0]
	var first_job:Dictionary=selected.decision.get("candidate",{})
	if selected.decision.priority=="N6" and first_job.get("kind")=="haul" and not str(first_job.get("id","")).is_empty():
		var skill:=_skill_level(Draft.find(tx.staged.get("actors",[]),str(selected.id)),HAUL_SKILL)
		for option:Dictionary in due:
			if option.decision.priority!="N6" or option.decision.get("candidate",{}).get("id")!=first_job.id:continue
			var contender:=_skill_level(Draft.find(tx.staged.get("actors",[]),str(option.id)),HAUL_SKILL)
			if contender>skill:
				selected=option
				skill=contender
	var actor:Dictionary=tx.actor(str(selected.id));var decision:Dictionary=selected.decision
	actor.self_routine.factory_wake_revision=wake_revision
	actor.self_routine.factory_decision=decision.duplicate(true)
	actor.self_routine.next_decision=now+1.0
	if decision.priority in ["N1","N2"]:
		if actor.get("intent") is Dictionary and actor.intent.get("owner")=="residents":actor.intent=null
		if actor.get("intent")!=null or actor.has("suspended_work") or (actor.get("pending_delivery") is Dictionary and not actor.pending_delivery.is_empty()):
			if not work_api:_decision_failed(actor,"WORKFORCE_EXECUTOR_UNAVAILABLE","等待B安全交接",now);return
			var handoff:Dictionary=_safe_handoff(str(actor.id),"",tx.staged,tx.extensions)
			if not handoff.get("ok",false):_decision_failed(actor,str(handoff.get("code","HANDOFF_REQUIRED")),str(handoff.get("reason","等待安全交接")),now);return
			var merged:Dictionary=_merge_prepared(tx,handoff)
			if not merged.ok:_decision_failed(actor,str(merged.code),str(merged.reason),now);return
		var care_started := Costs.begin()
		residents.prepare_factory_person(tx,str(selected.id),dt,now,true,layout)
		Costs.end("workforce/selected_self_care", care_started)
	elif decision.priority=="N3" and decision.action=="hold":
		actor.activity="在真实警戒点守备，沿既有攻击结算"
	elif decision.action in ["request","deliver","wait_handoff"]:
		if actor.get("intent") is Dictionary and actor.intent.get("owner")=="residents":actor.intent=null
		var candidate_id:String=str(decision.candidate.get("id",""))
		var handoff_started := Costs.begin()
		var handoff:Dictionary=_safe_handoff(str(actor.id),candidate_id,tx.staged,tx.extensions)
		# Authorized emergency defense may pause the original haul through B's
		# existing empty-target handoff; the same physical pack/task stays owned.
		if not handoff.get("ok",false) and decision.priority=="N3" and decision.candidate.get("kind")=="guard" and handoff.get("code")=="CARGO_HANDOFF_REQUIRED":
			handoff=_safe_handoff(str(actor.id),"",tx.staged,tx.extensions)
		# B alone confirms the safe boundary. Keep the explicit assignment queued
		# while completing this same actor's valid physical cargo responsibility.
		if not handoff.get("ok",false) and decision.priority=="N4" and handoff.get("code")=="CARGO_HANDOFF_REQUIRED":
			var carried:Dictionary=selected.get("carried",{})
			if carried.get("valid",false) and carried.get("reachable",false) and carried.get("capacity_valid",false):
				var original:Dictionary=_safe_handoff(str(actor.id),str(carried.id),tx.staged,tx.extensions)
				if original.get("ok",false):
					var pending_id:String=candidate_id
					candidate_id=str(carried.id);handoff=original
					decision=Arbitration.decide({"actor_id":actor.id,"actor_exists":true,"alive":true,"carried_delivery":carried})
					decision.deferred_assignment_id=pending_id
		Costs.end("workforce/selected_handoff", handoff_started)
		if not handoff.get("ok",false):_decision_failed(actor,str(handoff.get("code","HANDOFF_REQUIRED")),str(handoff.get("reason","等待安全交接")),now);return
		if decision.priority=="N4":
			decision.action="request";decision.reason="player_assignment";decision.candidate.handoff_safe=true
		var request:Dictionary={"actor_id":actor.id,"candidate_id":candidate_id,"command_id":"workforce:execute:"+str(actor.id)+":"+str(int(now*10))}
		# These isolated views belong only to this handoff, before any merge.
		# B admission is read-only on its inputs. Reuse the same prepared views
		# at merge after every original CAS guard, instead of deep-copying twice.
		var prep_started := Costs.begin()
		var handoff_facts:Dictionary=_facts_after(tx,handoff)
		var handoff_extensions:Dictionary=_extensions_after(tx,handoff)
		var prepared:Dictionary
		if decision.candidate.get("kind")=="guard":
			request.site_id=decision.candidate.site_id;request.position=decision.candidate.position.duplicate(true)
			prepared=actions.prepare_guard(request,handoff_facts,handoff_extensions)
		elif decision.candidate.get("kind")=="building_order":
			prepared=BuildingOrders.prepare(_runtime.get_ref().domain_service("modules"),decision.candidate,str(actor.id),request.command_id,handoff_facts,handoff_extensions)
		else:prepared=_prepare_work(request,handoff_facts,handoff_extensions)
		Costs.end("workforce/selected_prepare_work", prep_started)
		if not prepared.get("ok",false):
			var row:=Draft.find(workforce_state.assignments,str(decision.candidate.get("assignment_id","")))
			if not row.is_empty():
				var prefix:String="building" if row.has("building_phase") else "work"
				row[prefix+"_phase"]="blocked";row[prefix+"_reason"]=str(prepared.get("reason","作业条件尚未满足"));row.retry_at=now+JOB_RETRY_SECONDS
			elif candidate_id.begins_with("zonework:") and decision.priority=="N6":
				_remember_work_failure(actor,candidate_id,now)
			_decision_failed(actor,str(prepared.get("code","WORK_BLOCKED")),str(prepared.get("reason","实际路线不可执行")),now);return
		var merge_started := Costs.begin()
		var merged:Dictionary=_merge_prepared(tx,handoff,handoff_facts,handoff_extensions)
		if merged.ok:merged=_merge_prepared(tx,prepared)
		Costs.end("workforce/selected_merge", merge_started)
		if merged.ok:
			tx.actor(str(selected.id)).self_routine.factory_decision=decision.duplicate(true)
			var row:=Draft.find(workforce_state.assignments,str(decision.candidate.get("assignment_id","")))
			if not row.is_empty():
				if row.has("building_phase"):
					var project_id:=BuildingOrders.project_id(prepared,str(row.module_id))
					if not project_id.is_empty():row.project_id=project_id
					row.building_phase="accepted";row.erase("building_reason")
				else:
					row.work_phase="accepted";row.erase("work_reason")
				row.erase("retry_at")
		else:_decision_failed(tx.actor(str(selected.id)),str(merged.code),str(merged.reason),now)
	elif decision.priority=="N7":
		var routine_started := Costs.begin()
		residents.prepare_factory_person(tx,str(selected.id),dt,now,true,layout)
		Costs.end("workforce/selected_routine", routine_started)
	else:
		var row:=Draft.find(workforce_state.assignments,str(decision.get("candidate",{}).get("assignment_id","")))
		if not row.is_empty():
			var prefix:String="building" if row.has("building_phase") else "work"
			row[prefix+"_phase"]="blocked";row[prefix+"_reason"]=str(decision.reason);actor.self_routine.next_decision=now+3.0
		_decision_failed(actor,"WORKFORCE_BLOCKED",str(decision.reason),now)

static func _remember_work_failure(actor:Dictionary,candidate_id:String,now:float)->void:
	var cooldowns:Dictionary=actor.self_routine.get("work_retry_at",{})
	for expired:Variant in cooldowns.keys():
		if float(cooldowns[expired])<=now:cooldowns.erase(expired)
	if cooldowns.size()>=16:cooldowns.erase(cooldowns.keys()[0])
	cooldowns[candidate_id]=now+JOB_RETRY_SECONDS
	actor.self_routine.work_retry_at=cooldowns

static func _decision_failed(actor:Dictionary,code:String,reason:String,now:float)->void:
	actor.self_routine.last_failure={"code":code,"reason":reason,"at":now};actor.activity=reason

static func _facts_after(tx:RefCounted,plan:Dictionary)->Dictionary:
	var result:Dictionary=tx.staged.duplicate(true)
	for change:Dictionary in plan.get("fact_changes",[]):
		var rows:Array=result.get(change.collection,[]);var index:int=-1
		for i:int in rows.size():
			if rows[i].id==change.id:index=i;break
		if change.after==null:
			if index>=0:rows.remove_at(index)
		elif index>=0:rows[index]=change.after.duplicate(true)
		else:rows.append(change.after.duplicate(true))
	return result

static func _extensions_after(tx:RefCounted,plan:Dictionary)->Dictionary:
	var result:Dictionary=tx.extensions.duplicate(true)
	for change:Dictionary in plan.get("world_changes",[]):
		if change.get("op")=="extension.set":result[change.id]=change.after.duplicate(true)
	return result

static func _merge_prepared(tx:RefCounted,plan:Dictionary,prepared_facts:Dictionary={},prepared_extensions:Dictionary={})->Dictionary:
	# B returns a prepared draft against the exact supplied staged facts and
	# overlays. A still performs the single final world/fact CAS.
	for change:Dictionary in plan.get("fact_changes",[]):
		var current:Dictionary=Draft.find(tx.staged.get(change.collection,[]),str(change.id))
		if not Data.json_equal(null if current.is_empty() else current,change.before):return _bad("CAS_MISMATCH","B安全交接人物来源与E暂存不符")
	for change:Dictionary in plan.get("world_changes",[]):
		if change.get("op")!="extension.set" or not Data.json_equal(change.get("before"),tx.context.world.extension(str(change.id))):return _bad("CAS_MISMATCH","B安全交接扩展来源与当前世界不符")
	tx.staged=_facts_after(tx,plan) if prepared_facts.is_empty() else prepared_facts
	tx.extensions=_extensions_after(tx,plan) if prepared_extensions.is_empty() else prepared_extensions
	tx.events.append_array(plan.get("events",[]))
	return {"ok":true}
