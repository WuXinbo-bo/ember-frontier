extends RefCounted
## E owns assignment intent and arbitration; B owns task/order execution and cargo.
const Context=preload("res://scripts/actions/domain_context.gd")
const Arbitration=preload("res://scripts/runtime/workforce_arbitration.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Gameplay=preload("res://tests/gameplay/fixtures/performance17/factory_gameplay_before17.gd")
const Regional=preload("res://scripts/runtime/factory_gameplay_region.gd")
const Story=preload("res://scripts/runtime/factory_gameplay_story.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const KEY:="r34:workforce"
const MAX_ASSIGNMENTS:=1024
const MAX_INTERRUPTED:=2048
const MAX_EVENTS:=4096
var context:Dictionary
var _runtime:WeakRef
var _actions:WeakRef
var _production:WeakRef
var _gameplay:WeakRef
var _residents:WeakRef
var _zonework:WeakRef
var _enabled:=false

static func initial()->Dictionary:
	return {"version":1,"assignments":[],"interrupted":[],"events":[],"next_id":1}

static func validate_state(value:Variant)->Dictionary:
	if not value is Dictionary or not Data.json_value(value) or not _whole(value.get("version")) or int(value.version)!=1:return _bad("INVALID_WORKFORCE_SCHEMA","劳动力状态版本无效")
	for key:String in ["assignments","interrupted","events"]:
		if not value.get(key) is Array:return _bad("INVALID_WORKFORCE_SCHEMA","劳动力状态列表无效："+key)
	if value.assignments.size()>MAX_ASSIGNMENTS or value.interrupted.size()>MAX_INTERRUPTED or value.events.size()>MAX_EVENTS:return _bad("WORKFORCE_LIMIT","劳动力状态超过有界容量")
	var next:Variant=value.get("next_id")
	if not _whole(next) or int(next)<1:return _bad("INVALID_WORKFORCE_SCHEMA","劳动力序号无效")
	var actors:Dictionary={};var candidates:Dictionary={};var assignment_ids:Dictionary={}
	for item:Variant in value.assignments:
		if not item is Dictionary or not _id(item.get("actor_id")) or not _id(item.get("candidate_id")) or not _id(item.get("id")):return _bad("INVALID_WORKFORCE_SCHEMA","岗位引用无效")
		if actors.has(item.actor_id) or candidates.has(item.candidate_id) or assignment_ids.has(item.id):return _bad("WORKFORCE_SLOT_CONFLICT","一人或一个B候选不能重复占槽")
		if not _whole(item.get("sequence")) or int(item.sequence)<1 or int(item.sequence)>=int(next) or not _number(item.get("priority")) or float(item.priority)<-100 or float(item.priority)>100:return _bad("INVALID_WORKFORCE_SCHEMA","岗位排序字段无效")
		if item.get("status") not in ["requested","active","interrupted","blocked"]:return _bad("INVALID_WORKFORCE_SCHEMA","岗位状态无效")
		if not _number(item.get("created_at")) or float(item.created_at)<0:return _bad("INVALID_WORKFORCE_SCHEMA","岗位创建时间无效")
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

func validate_extensions(facts_state:Dictionary,extension_overrides:Dictionary={})->Dictionary:
	# Dictionary.get evaluates its fallback eagerly. Read only the exact
	# selected source; full validators below still inspect the supplied value.
	var gameplay:Variant=extension_overrides[Gameplay.KEY] if extension_overrides.has(Gameplay.KEY) else context.world.extension(Gameplay.KEY)
	if gameplay!=null:
		var gameplay_valid:Dictionary=Gameplay.validate_state(gameplay)
		if not gameplay_valid.ok:return gameplay_valid
		for id:String in gameplay.get("regional_objectives",{}):
			if Regional.find_site(context,gameplay.get("layout",{}),id).is_empty():return _bad("STALE_REGIONAL_SITE","地区目标引用的持久生成地点不存在或不匹配")
		var defense:Dictionary=gameplay.defense
		if defense.status in ["active","cleared"]:
			if defense.actors.size()!=3:return _bad("INVALID_FACTORY_DEFENSE","首轮防守须是完整三名既有感染者")
			for id:String in defense.actors:
				var found:Dictionary=Draft.find(facts_state.get("actors",[]),id)
				if found.is_empty() or found.get("faction")!="infected" or found.get("encounter_id")!="r34:first-defense":return _bad("STALE_FACTORY_DEFENSE","防守引用并非本次真实生成感染者")
				if defense.status=="cleared" and float(found.get("hp",0))>0:return _bad("INVALID_FACTORY_DEFENSE","活感染者不能虚报清除")
	var value:Variant=extension_overrides[KEY] if extension_overrides.has(KEY) else context.world.extension(KEY)
	if value==null:return {"ok":true,"code":"OK","reason":null}
	var valid:Dictionary=validate_state(value)
	if not valid.ok:return valid
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
	var state:Variant=context.world.extension(Gameplay.KEY)
	return {"available":available,"alerts":_alerts(context.facts.call(),state if state is Dictionary else {})}

func projection(actor_id:String="player")->Dictionary:
	return _projection(actor_id,true)

func summary_projection(actor_id:String="player")->Dictionary:
	# Display-only demand boundary. Live arbitration/advance and full reads
	# retain every candidate check; an unrequested list is never "no work".
	return _projection(actor_id,false)

func hud_projection(_actor_id:String="player")->Dictionary:
	# HUD needs membership/real alerts, never house routes or candidate jobs.
	var facts:Dictionary=context.facts.call();var members:Array=[];var assignments:Dictionary={}
	for row:Dictionary in _state().assignments:assignments[row.actor_id]=row.id
	for a:Dictionary in facts.get("actors",[]):
		if a.get("faction")=="infected" or (a.id!="player" and not a.get("relationship",{}).get("member",false)):continue
		members.append({"actor_id":a.id,"alive":float(a.get("hp",0))>0,"consent":a.id=="player" or a.get("relationship",{}).get("consent",false),"activity":a.get("activity",""),"assignment_id":assignments.get(a.id,"")})
	var state:Variant=context.world.extension(Gameplay.KEY)
	return {"available":_enabled,"members":members,"alerts":_alerts(facts,state if state is Dictionary else {}),"candidates_included":false,"candidates_state":"not_requested","details_state":"not_requested"}

func _projection(actor_id:String,include_candidates:bool)->Dictionary:
	var state:Dictionary=_state();var facts:Dictionary=context.facts.call()
	var candidates:Array=[];var actions:Variant=_actions.get_ref() if _actions!=null else null
	var candidate_api:bool=actions!=null and actions.has_method("workforce_candidates")
	if include_candidates and candidate_api:candidates=_work_candidates(actor_id)
	var people:Array=[]
	for a:Dictionary in facts.get("actors",[]):
		if a.get("faction")=="infected" or (a.id!="player" and not a.get("relationship",{}).get("member",false)):continue
		if actor_id!="*" and a.id!=actor_id:continue
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
		people.append(person)
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
	var result:Dictionary={"schema":"r34-workforce-v1","available":available,"assignments":state.assignments.duplicate(true),"members":members,"people":people,"housing":housing,"interrupted":state.interrupted.duplicate(true),"events":state.events.duplicate(true),"stories":stories,"regional_event":regional_event,"map_markers":_map_markers(facts,regional_event,stories),"alerts":_alerts(facts,story_state if story_state is Dictionary else {}),"error":null if available else {"code":"WORKFORCE_EXECUTOR_UNAVAILABLE","reason":"B岗位候选与安全交接接口尚未装配"},"world_revision":context.world.get_revision(),"runtime_revision":_runtime.get_ref().get_revision()}
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
	if not request.get("kind") is String or request.kind not in ["workforce.assign","workforce.clear","workforce.priority"]:return _bad("INVALID_WORKFORCE_COMMAND","劳动力命令无效")
	if not _enabled:return _bad("SCENARIO_UNAVAILABLE","R3.4劳动力只在factory-settlement-r34运行")
	if not _id(request.get("actor_id")):return _bad("INVALID_ACTOR","岗位人物身份无效")
	var actor:Dictionary=context.actor.call(str(request.actor_id))
	if actor.is_empty() or float(actor.get("hp",0))<=0:return _bad("ACTOR_UNAVAILABLE","岗位人物无法行动")
	if actor.id!="player" and (not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false) or (not _at_home(actor) and not actor.get("relationship",{}).get("home_arrived",false))):return _bad("NO_CONSENT","需要已自愿同行并实际返家的成员")
	var state:Dictionary=_state();var exists:=false
	for item:Dictionary in state.assignments:
		if item.actor_id==actor.id:exists=true
	if request.kind=="workforce.assign":
		if not _id(payload.get("candidate_id")):return _bad("INVALID_CANDIDATE","payload.candidate_id必须引用B的稳定候选ID")
		var candidate:Dictionary=_candidate(actor.id,str(payload.candidate_id))
		if candidate.is_empty():return _bad("CANDIDATE_UNAVAILABLE","B尚未提供有效岗位／物流候选；未占槽")
		if not candidate.get("valid",false):return _bad("CANDIDATE_BLOCKED",str(candidate.get("reason","候选当前不可执行")))
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
	var index:int=-1
	for i:int in after.assignments.size():
		if after.assignments[i].actor_id==actor_id:index=i;break
	if request.kind=="workforce.assign":
		var candidate_id:String=payload.candidate_id
		var candidate:Dictionary=_candidate(actor_id,candidate_id)
		if candidate.get("carrying",false):return _bad("CARGO_HANDOFF_REQUIRED","候选携货仍由原人物承担")
		if index>=0:after.assignments.remove_at(index)
		var id:="workforce:"+str(after.next_id)
		var row:Dictionary={"id":id,"actor_id":actor_id,"candidate_id":candidate_id,"priority":float(payload.get("priority",0)),"sequence":int(after.next_id),"status":"requested","created_at":float(context.clock.call()),"source_runtime_revision":int(_runtime.get_ref().get_revision()),"source_world_revision":int(context.world.get_revision())}
		after.next_id=int(after.next_id)+1;after.assignments.append(row)
		after.events.append({"id":id,"kind":"assignment-requested","actor_id":actor_id,"candidate_id":candidate_id,"time":float(context.clock.call())})
	elif request.kind=="workforce.clear":
		var row:Dictionary=after.assignments[index]
		after.interrupted.append({"id":row.id,"actor_id":actor_id,"candidate_id":row.candidate_id,"reason":"player-cleared","time":float(context.clock.call()),"resume_sequence":row.sequence})
		after.assignments.remove_at(index)
		after.events.append({"id":"workforce:"+str(after.next_id),"kind":"assignment-cleared","actor_id":actor_id,"candidate_id":row.candidate_id,"time":float(context.clock.call())});after.next_id=int(after.next_id)+1
	else:
		after.assignments[index].priority=float(payload.priority)
	var checked:Dictionary=validate_state(after)
	if not checked.ok:return checked
	var change:Dictionary={"op":"extension.set","id":KEY,"before_exists":context.world.has_extension(KEY),"before":context.world.extension(KEY),"after":after}
	return {"ok":true,"code":"OK","reason":null,"world_changes":[change],"fact_changes":[],"events":[]}

func _at_home(actor:Dictionary,layout:Dictionary={})->bool:
	if layout.is_empty():layout=context.world.extension(Gameplay.KEY).get("layout",{})
	if layout.is_empty() or not layout.get("home") is Dictionary:return false
	var home:Dictionary=layout.home
	return actor.get("regionId")==home.get("regionId") and Vector2(float(actor.get("x",0))-float(home.get("x",0)),float(actor.get("z",0))-float(home.get("z",0))).length()<=float(layout.get("home_radius",18.0))

func event_dependency_regions()->Array:
	# Pure input to A's common pause/pin boundary; never infer a radius or load
	# anything here. Production and combat must share these actual dependencies.
	var event:Variant=context.world.extension(Gameplay.KEY)
	if not event is Dictionary or event.get("defense",{}).get("status") not in ["warning","awaiting_execution","active"]:return []
	var regions:Array=[]
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

func site_work_permission(request:Dictionary)->Dictionary:
	if not _enabled:return {"ok":true,"code":"OK","reason":null}
	return Regional.permission(context,context.world.extension(Gameplay.KEY),request)

func advance(dt:float)->Dictionary:
	if not _enabled:return {"ok":true,"world_changes":[],"fact_changes":[],"events":[]}
	if not is_finite(float(dt)) or float(dt)<=0 or float(dt)>1:return {"ok":false,"code":"INVALID_STEP","reason":"劳动力由A同一时钟推进"}
	var state:Dictionary=_state();var valid:Dictionary=validate_state(state)
	if not valid.ok:return {"ok":false,"code":valid.code,"reason":valid.reason}
	var tx:=Draft.new(context)
	var observed:Dictionary=Gameplay.advance_in(tx,float(context.clock.call()),dt)
	if not observed.ok:return observed
	var gameplay:Variant=_gameplay.get_ref() if _gameplay!=null else null
	var event_state:Dictionary=tx.extension(Gameplay.KEY,Gameplay.initial_state())
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
	if residents!=null and residents.has_method("prepare_factory_person"):
		_advance_survival(tx,residents,dt,float(context.clock.call()),state)
	# B alone turns work candidates into task/action intents once its prepared
	# safe-handoff API is available. E self-care reuses existing A/B rules.
	return tx.result()

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
	var due:Array=[];var actions:Variant=_actions.get_ref() if _actions!=null else null
	var layout:Dictionary=tx.extension(Gameplay.KEY).get("layout",{})
	# Reuse only this advance's validated snapshot. Prepared handoffs merge
	# after selection, so every actor still sees the same assignment revision.
	if workforce_state.is_empty():workforce_state=_state()
	var work_api:bool=actions!=null and actions.has_method("prepare_workforce") and actions.has_method("safe_handoff") and actions.has_method("workforce_candidates")
	var wake_revision:int=-1
	for event:Dictionary in tx.staged.get("ledger",[]):
		var kind:String=str(event.get("kind",""))
		if kind.begins_with("factory-") or kind.begins_with("module-") or kind.begins_with("logistics-") or kind.begins_with("zone-") or kind.begins_with("zonework-") or kind.begins_with("ecology-") or kind in ["inventory-transfer","consent","invite","combat-hit"]:wake_revision=maxi(wake_revision,int(event.get("revision",-1)))
	for a:Dictionary in tx.staged.get("actors",[]):
		if a.id=="player" or a.get("faction")=="infected" or float(a.get("hp",0))<=0:continue
		if not context.region_is_detailed.call(str(a.regionId)):continue
		var emergency:Dictionary=_guard_candidate(a,tx) if actions!=null and actions.has_method("prepare_guard") else {}
		if a.get("intent") is Dictionary and a.intent.get("owner")=="residents":
			var walking_signals:Dictionary=residents.factory_signals(a,tx)
			var purpose:String=str(a.intent.get("purpose",""))
			if (walking_signals.danger and purpose!="avoid") or (not walking_signals.danger and not str(walking_signals.urgent_need).is_empty() and purpose in ["watch","return-home"]) or (not emergency.is_empty() and purpose!="avoid"):
				walking_signals.emergency=emergency
				walking_signals.merge({"actor_id":a.id,"actor_exists":true,"alive":true,"requires_consent":false},true)
				due.append({"id":a.id,"decision":Arbitration.decide(walking_signals),"work_api":work_api})
			else:residents.prepare_factory_person(tx,str(a.id),dt,now,false,layout)
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
			candidates=_work_candidates(str(a.id),candidate_facts,candidate_extensions)
		var explicit:Dictionary={};var carried:Dictionary={}
		for row:Dictionary in workforce_state.assignments:
			if row.actor_id!=a.id:continue
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
	if due.is_empty():return
	due.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.decision.priority<b.decision.priority if a.decision.priority!=b.decision.priority else str(a.id)<str(b.id))
	var selected:Dictionary=due[0];var actor:Dictionary=tx.actor(str(selected.id));var decision:Dictionary=selected.decision
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
		residents.prepare_factory_person(tx,str(selected.id),dt,now,true,layout)
	elif decision.priority=="N3" and decision.action=="hold":
		actor.activity="在真实警戒点守备，沿既有攻击结算"
	elif decision.action in ["request","deliver","wait_handoff"]:
		if actor.get("intent") is Dictionary and actor.intent.get("owner")=="residents":actor.intent=null
		var candidate_id:String=str(decision.candidate.get("id",""))
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
		if not handoff.get("ok",false):_decision_failed(actor,str(handoff.get("code","HANDOFF_REQUIRED")),str(handoff.get("reason","等待安全交接")),now);return
		if decision.priority=="N4":
			decision.action="request";decision.reason="player_assignment";decision.candidate.handoff_safe=true
		var request:Dictionary={"actor_id":actor.id,"candidate_id":candidate_id,"command_id":"workforce:execute:"+str(actor.id)+":"+str(int(now*10))}
		# These isolated views belong only to this handoff, before any merge.
		# B admission is read-only on its inputs. Reuse the same prepared views
		# at merge after every original CAS guard, instead of deep-copying twice.
		var handoff_facts:Dictionary=_facts_after(tx,handoff)
		var handoff_extensions:Dictionary=_extensions_after(tx,handoff)
		var prepared:Dictionary
		if decision.candidate.get("kind")=="guard":
			request.site_id=decision.candidate.site_id;request.position=decision.candidate.position.duplicate(true)
			prepared=actions.prepare_guard(request,handoff_facts,handoff_extensions)
		else:prepared=_prepare_work(request,handoff_facts,handoff_extensions)
		if not prepared.get("ok",false):_decision_failed(actor,str(prepared.get("code","WORK_BLOCKED")),str(prepared.get("reason","实际路线不可执行")),now);return
		var merged:Dictionary=_merge_prepared(tx,handoff,handoff_facts,handoff_extensions)
		if merged.ok:merged=_merge_prepared(tx,prepared)
		if merged.ok:tx.actor(str(selected.id)).self_routine.factory_decision=decision.duplicate(true)
		else:_decision_failed(tx.actor(str(selected.id)),str(merged.code),str(merged.reason),now)
	elif decision.priority=="N7":
		residents.prepare_factory_person(tx,str(selected.id),dt,now,true,layout)
	else:_decision_failed(actor,"WORKFORCE_BLOCKED",str(decision.reason),now)

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
