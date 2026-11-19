extends RefCounted
## Region labor owns execution only. Ecology settles items and vegetation in
## the same Draft; Runtime alone commits and advances the authoritative clock.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Context=preload("res://scripts/actions/domain_context.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Contact=preload("res://scripts/buildings/interaction_contact.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Workforce=preload("res://scripts/actions/workforce_executor.gd")
const Delivery=preload("res://scripts/actions/zone_output_delivery.gd")
const Supply=preload("res://scripts/planning/zone_work_supply.gd")
const CandidateContext=preload("res://scripts/planning/zone_candidate_context.gd")
const KEY="r34:zonework"
const ZONES="r34:zones"
const OPERATIONS=["collect_seed","nursery","plant_tree","till","sow","water","compost","harvest_crop","draw_raw_water","clear_stump","recover_seed","remove_crop","terrain_dig","terrain_fill"]
var context:Dictionary={}
var _services:Dictionary={}
var _runtime:WeakRef
var _candidate_costs:Dictionary={}
func candidate_costs()->Dictionary:return _candidate_costs.duplicate(true)

func configure(value:Dictionary)->void:
	context=Context.isolate(value);_services.clear()
	for name:Variant in value.get("services",{}):
		var service:Variant=value.services[name]
		if service is RefCounted and service!=self:_services[name]=weakref(service)
	if value.get("runtime") is RefCounted:_runtime=weakref(value.runtime)

func domain(name:String)->Variant:
	var host:Variant=_runtime.get_ref() if _runtime!=null else null
	if host!=null and host.has_method("domain_service"):return host.domain_service(name)
	var ref:Variant=_services.get(name)
	return ref.get_ref() if ref is WeakRef else null

static func initial()->Dictionary:return {"version":1,"jobs":{},"receipts":[]}
static func eligible(a:Dictionary)->bool:
	return not a.is_empty() and float(a.get("hp",0))>0 and (a.id=="player" or (a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false)))
static func number(v:Variant)->bool:return (v is float or v is int) and is_finite(float(v)) and float(v)>=0
static func location(v:Variant)->bool:
	if not v is Dictionary or not Data.valid_id(v.get("regionId")):return false
	for k:String in ["x","y","z"]:
		if not (v.get(k) is int or v.get(k) is float) or not is_finite(float(v[k])):return false
	return true
func state(overrides:Dictionary={})->Dictionary:
	var v:Variant=overrides[KEY] if overrides.has(KEY) else context.world.extension(KEY)
	return v if v is Dictionary else initial()
func zones(tx:RefCounted)->Array:
	var v:Variant=tx.extensions[ZONES] if tx.extensions.has(ZONES) else context.world.extension(ZONES)
	return v.get("zones",[]) if v is Dictionary else []
func detailed(at:Dictionary)->bool:
	return not context.get("region_is_detailed") is Callable or context.region_is_detailed.call(str(at.get("regionId","")))
static func candidate_id(zone:Dictionary,job:Dictionary)->String:return "zonework:"+str(zone.id)+":"+str(job.id)
func _observation(facts:Dictionary,overrides:Dictionary)->RefCounted:return Workforce.observation(self,facts,overrides)
func _draft(facts:Dictionary={},overrides:Dictionary={})->RefCounted:return Workforce.draft(self,facts,overrides)
func _zone(tx:RefCounted,id:String)->Dictionary:return Draft.find(zones(tx),id)
func _job(tx:RefCounted,id:String)->Dictionary:return tx.extension(KEY,initial()).jobs.get(id,{})

func _tools(tx:RefCounted,a:Dictionary,quality:Dictionary,excluding:String,observation:Variant=null)->Array:
	var selected:Array=[];var prod:Variant=observation if observation!=null else domain("production")
	if prod==null:return selected
	var p:Dictionary=tx.extension(Production.KEY,Production.empty_state())
	for q:Variant in quality:
		for tool:Dictionary in p.tools:
			if tool.get("holderId")!="pack:"+str(a.id) or float(tool.get("durability",0))<=0:continue
			if float(prod.tool_qualities(tool).get(q,0))<float(quality[q]) or prod.tool_unavailable(str(tool.id),excluding,tx):continue
			if not selected.has(tool.id):selected.append(tool.id)
			break
	return selected
func _info(tx:RefCounted,a:Dictionary,job:Dictionary)->Dictionary:
	var ecology:Variant=domain("ecology")
	if ecology==null:return Data.reject("ECOLOGY_UNAVAILABLE","土地作业检查尚未接通")
	return _checked_info(ecology.check_work(tx,job,str(a.id)))
func _checked_info(result:Variant)->Dictionary:
	if not result is Dictionary or not result.get("ok",false):return result if result is Dictionary else Data.reject("INVALID_ECOLOGY_WORK")
	if not number(result.get("duration")) or float(result.duration)<=0 or not location(result.get("location")) or not result.get("cost",{}) is Dictionary or not result.get("tool_quality",{}) is Dictionary or not number(result.get("wear",0)) or not number(result.get("stamina",0)):return Data.reject("INVALID_ECOLOGY_WORK","土地作业工时、工具或位置无效")
	return result

func work_candidates(actor_id:String,staged_facts:Dictionary={},overrides:Dictionary={},zone_filter:String="")->Array:
	_candidate_costs={"enumerate":0,"check":0,"supply":0,"tools":0,"other":0}
	var tx:=_observation(staged_facts,overrides);var a:=Draft.find(tx.staged.get("actors",[]),actor_id)
	var ecology:Variant=domain("ecology");var rows:Array=[]
	if not eligible(a) or ecology==null or not detailed(G.location(a)):return rows
	# Delivery candidates use the same detached draft. With no enabled zones,
	# there is no need to build the supply view or index every stock and hold.
	var enabled_zones: Array = zones(tx).filter(func(zone: Dictionary) -> bool:
		return zone.get("enabled", false) and (zone_filter.is_empty() or zone.id == zone_filter))
	if enabled_zones.is_empty():
		return Delivery.candidates(self, tx, a) if zone_filter.is_empty() else []
	# Enlist existing read snapshots once, before any candidate/hold derivation.
	# Missing legacy domains stay absent; this observer is never committed.
	for key:String in [Production.KEY,"r34:modules","r34:production","r34:logistics",KEY,ZONES]:
		if not tx.extensions.has(key) and context.world.has_extension(key):tx.extension(key)
	var observed_work:Dictionary=state(tx.extensions)
	var supply_context: RefCounted
	if zone_filter.is_empty(): rows.append_array(Delivery.candidates(self,tx,a))
	for zone: Dictionary in enabled_zones:
		# Only a personally dispatched forestry zone can offer remote work.
		if not zone.has("region_ids") and zone.region_id!=a.regionId and (zone.kind!="forestry" or zone.policy.get("worker_ids",[])!=[actor_id] or not detailed({"regionId":zone.region_id})):continue
		if not zone.get("policy",{}).get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(actor_id):continue
		if supply_context == null:
			supply_context = CandidateContext.new(self, tx)
		var entries:Array=[];var checked_jobs:Array=[];var ecology_observation:Dictionary={"production":supply_context.domain("production")}
		var phase:int=Time.get_ticks_usec()
		for raw:Variant in ecology.work_candidates(zone,actor_id,ecology_observation):
			if not raw is Dictionary or not Data.valid_id(raw.get("id")) or not location(raw.get("location")):continue
			var job:Dictionary=raw.duplicate(true);var id:String=candidate_id(zone,job)
			job.zone_id=zone.id;job.work_id="candidate:"+actor_id+":"+id;job.source_id="pack:"+actor_id;job.output_id="pack:"+actor_id;job.tool_ids=[]
			entries.append({"raw":raw,"job":job,"id":id})
			if job.get("kind")!="harvest_tree":checked_jobs.append(job)
		# C owns this synchronous scratch. Every resource/permission/contact
		# result remains ordered and per job; ordinary admission still uses fresh
		# check_work, never these candidate DTOs or a cached accepted route.
		_candidate_costs.enumerate+=Time.get_ticks_usec()-phase;phase=Time.get_ticks_usec()
		var checked:Variant=ecology.check_work_batch(tx,checked_jobs,actor_id,ecology_observation)
		_candidate_costs.check+=Time.get_ticks_usec()-phase
		var check_index:int=0
		for entry:Dictionary in entries:
			var job:Dictionary=entry.job;var id:String=entry.id;var raw:Dictionary=entry.raw
			var info:Dictionary
			if job.get("kind")=="harvest_tree":info={"ok":true,"duration":1.0,"location":job.location,"tool_quality":{"chopping":1},"cost":{}}
			else:
				info=_checked_info(checked[check_index]) if checked is Array and checked.size()==checked_jobs.size() else Data.reject("INVALID_ECOLOGY_WORK_BATCH")
				check_index+=1
			var requirements:Dictionary=info.get("requirements",info if info.get("ok",false) else {})
			if not requirements.is_empty():
				phase=Time.get_ticks_usec()
				for offer:Dictionary in Supply.candidates(supply_context,tx,a,zone,job,requirements):
					offer.command={"kind":"zonework.supply","target_id":zone.id,"payload":{"candidate_id":offer.id}}
					rows.append(offer)
				_candidate_costs.supply+=Time.get_ticks_usec()-phase
			phase=Time.get_ticks_usec()
			var reason:String=str(info.get("reason",info.get("code",""))) if not info.get("ok",false) else ""
			if reason.is_empty():reason=_chapter_output_problem(tx,a,zone,job,info)
			if reason.is_empty():
				job.tool_ids=_tools(tx,a,info.get("tool_quality",{}),str(job.work_id),supply_context.domain("production"))
				var prod:Variant=supply_context.domain("production")
				if prod==null or not prod.qualities(tx.extension(Production.KEY,Production.empty_state()),job.tool_ids,info.get("tool_quality",{})):reason="需要实际持有且可用的工具"
				elif job.kind=="harvest_tree" and prod.use_reserved(str(job.target_id)):reason="这棵树正在由其他角色处理"
			_candidate_costs.tools+=Time.get_ticks_usec()-phase
			if a.get("intent")!=null:reason="角色已有行动"
			for work:Dictionary in observed_work.jobs.values():
				if work.candidate_id==id and work.status in ["active","paused","blocked"] and work.actor_id!=actor_id:reason="目标已被其他作业预留"
			var priority:float=float(zone.get("policy",{}).get("priority",1))
			rows.append({"id":id,"actor_id":actor_id,"owner":"zonework","executor":"zonework","kind":"zonework","operation":job.kind,"valid":reason.is_empty(),"reason":reason,"priority":priority,"player_priority":priority,"wait_seconds":0.0,"route_cost":G.point(G.location(a)).distance_to(G.point(job.location)),"zone_id":zone.id,"job":raw.duplicate(true),"command":{"kind":"zonework.start","target_id":zone.id,"payload":{"candidate_id":id}},"unblocks_output":false,"critical_supply":false,"carrying":false})
	return rows

func supply_candidate(tx:RefCounted,a:Dictionary,id:String,excluding:String="")->Dictionary:
	# Admission/arrival rederive the offer from current authoritative sources.
	# Clearing the isolated actor's intent only permits revalidation of its own
	# in-flight offer; no actor, stock or candidate snapshot is accepted as proof.
	var probe:Dictionary=a.duplicate(true);probe.intent=null
	var ecology:Variant=domain("ecology")
	if ecology==null or not eligible(a):return {}
	for zone:Dictionary in zones(tx):
		if not zone.get("enabled",false) or (not zone.has("region_ids") and zone.region_id!=G.location(a).regionId):continue
		if not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id):continue
		for raw:Dictionary in ecology.work_candidates(zone,str(a.id)):
			var job:Dictionary=raw.duplicate(true);job.work_id=excluding;job.source_id="pack:"+str(a.id);job.output_id=job.source_id
			var info:Dictionary={"ok":true,"tool_quality":{"chopping":1},"cost":{}} if job.kind=="harvest_tree" else _info(tx,probe,job)
			var requirements:Dictionary=info.get("requirements",info if info.get("ok",false) else {})
			if requirements.is_empty():continue
			for offer:Dictionary in Supply.candidates(self,tx,probe,zone,job,requirements):
				if offer.id==id:return offer
	return {}

func _resolve(tx:RefCounted,a:Dictionary,zone_id:String,id:String)->Dictionary:
	var zone:=_zone(tx,zone_id);var ecology:Variant=domain("ecology")
	if zone.is_empty() or not zone.get("enabled",false) or ecology==null:return {}
	if not zone.get("policy",{}).get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id):return {}
	if not detailed(G.location(a)) or (not zone.has("region_ids") and not detailed({"regionId":zone.region_id})):return {}
	for raw:Variant in ecology.work_candidates(zone,str(a.id)):
		if raw is Dictionary and Data.valid_id(raw.get("id")) and candidate_id(zone,raw)==id:
			var job:Dictionary=raw.duplicate(true);job.zone_id=zone.id;job.zone_revision=zone.revision;return job
	return {}

func _path(a:Dictionary,job:Dictionary,info:Dictionary)->Dictionary:
	var actions:Variant=domain("actions");var points:Array=[info.location]
	var target:Dictionary=context.world.entity(str(job.get("target_id","")))
	if target.get("kind")=="tree":points.append_array(Contact.tree_points(context.spatial.current_space(),target))
	var failure:Dictionary=Data.reject("NO_WORK_STANDING","目标周围没有真实可达作业站位")
	for point:Dictionary in points:
		var path:Dictionary=actions.route(str(a.id),G.location(a),point)
		if path.ok:
			# The original route proves a supported body endpoint, which may be
			# half a metre above the requested ground/tool target. Keep that exact
			# endpoint rather than replacing it with the unprojected request.
			var endpoint:Dictionary=G.location(a)
			for step:Dictionary in path.steps:
				if step.get("kind") in ["move","stairs"] and location(step.get("to")):endpoint=step.to
			path.location=endpoint.duplicate(true);return path
		failure=path
	return failure

func availability(request:Dictionary)->Dictionary:
	var result:=prepare(request)
	if result.get("ok",false):result.world_changes=[];result.fact_changes=[];result.events=[]
	return result
func prepare(request:Dictionary)->Dictionary:return prepare_workforce(request)
func prepare_workforce(request:Dictionary,staged_facts:Dictionary={},overrides:Dictionary={})->Dictionary:
	var tx:=_draft(staged_facts,overrides);var a:Dictionary=tx.actor(str(request.get("actor_id","")))
	if not eligible(a):return Data.reject("ACTOR_UNAVAILABLE","角色失能或未同意工作")
	var payload:Variant=request.get("payload",{})
	if not payload is Dictionary:return Data.reject("INVALID_ZONEWORK_COMMAND")
	var kind:String=str(request.get("kind","zonework.start"))
	if kind in ["zonework.pause","zonework.cancel","zonework.resume"]:return _control(tx,a,kind,payload,str(request.get("target_id","")))
	if kind=="zonework.deliver":return Delivery.prepare(self,tx,a,request)
	if kind=="zonework.supply":
		var id:String=str(payload.get("candidate_id",""));var offer:=supply_candidate(tx,a,id)
		if offer.is_empty() or offer.zone_id!=request.get("target_id"):return Data.reject("CANDIDATE_UNAVAILABLE")
		var actions:Variant=domain("actions")
		return actions.ZoneSupply.prepare(actions,tx,a,id,str(request.get("command_id",""))) if actions!=null else Data.reject("UNAVAILABLE")
	if kind not in ["zonework.start","zonework.draw_water"]:return Data.reject("UNKNOWN_ZONEWORK_COMMAND")
	if a.get("intent")!=null:return Data.reject("ACTOR_BUSY","先安全暂停当前行动")
	if Delivery.pending(self,tx,a):return Data.reject("CARGO_HANDOFF_REQUIRED","先实际送达或安全处理既有携货")
	var id:String=str(request.get("candidate_id",payload.get("candidate_id","")))
	var zone_id:String=str(payload.get("zone_id",request.get("target_id","")))
	var job:Dictionary={}
	if kind=="zonework.draw_water":
		var ecology:Variant=domain("ecology")
		var target_id:String=str(request.get("target_id",""))
		if ecology==null or not detailed(G.location(a)):return Data.reject("WATER_SOURCE_UNAVAILABLE","水源附近的地图尚未就绪")
		job=ecology.chapter_water_job(target_id)
		if job.is_empty():return Data.reject("WATER_SOURCE_UNAVAILABLE","井中暂时没有可取得的原水，或水源尚未就绪")
		zone_id=str(job.zone_id);job.zone_revision=0;job.direct_well=true
		id="well-work:"+target_id
	else:
		if zone_id.is_empty():
			for zone:Dictionary in zones(tx):
				if id.begins_with("zonework:"+str(zone.id)+":"):zone_id=zone.id;break
		job=_resolve(tx,a,zone_id,id)
	if job.is_empty():return Data.reject("CANDIDATE_UNAVAILABLE","目标或区域已变化，请重新选择")
	var work_id:String=str(request.get("command_id",""))
	if not Data.valid_id(work_id):return Data.reject("INVALID_ZONEWORK_ID")
	var pack_id:String="pack:"+str(a.id)
	job.work_id=work_id;job.source_id=pack_id if kind=="zonework.draw_water" else str(payload.get("source_id",pack_id));job.output_id=pack_id if kind=="zonework.draw_water" else str(payload.get("output_id",pack_id));job.tool_ids=[]
	var prod:Variant=domain("production");var actions:Variant=domain("actions")
	if prod==null or actions==null:return Data.reject("UNAVAILABLE")
	if job.kind=="harvest_tree":
		var tools:=_tools(tx,a,{"chopping":1},work_id)
		return actions.prepare_in(tx,{"kind":"harvest","actor_id":a.id,"command_id":work_id,"target_id":job.target_id,"payload":{"direct":false,"held":true,"tree_id":job.target_id,"tool_ids":tools,"zone_id":zone_id,"zone_revision":job.zone_revision}})
	if job.kind not in OPERATIONS:return Data.reject("UNSUPPORTED_ZONEWORK")
	var info:=_info(tx,a,job)
	if not info.ok:return info
	var output_problem:String=_chapter_output_problem(tx,a,_zone(tx,zone_id),job,info)
	if not output_problem.is_empty():return Data.reject("CHAPTER_WORK_OUTPUT_BLOCKED",output_problem)
	job.tool_ids=_tools(tx,a,info.tool_quality,work_id)
	if not prod.qualities(tx.extension(Production.KEY,Production.empty_state()),job.tool_ids,info.tool_quality):return Data.reject("TOOLS","需要实际持有且可用的作业工具")
	var current:Dictionary=tx.extension(KEY,initial())
	for other:Dictionary in current.jobs.values():
		if other.actor_id==a.id and other.candidate_id==id and other.status=="suspended":return _control(tx,a,"zonework.resume",{"work_id":other.id},"")
		if other.actor_id==a.id and other.status in ["active","paused","blocked"]:return Data.reject("HANDOFF_REQUIRED")
		if other.candidate_id==id and other.status in ["active","paused","blocked"]:return Data.reject("RESERVED")
	if current.jobs.has(work_id):return Data.reject("ZONEWORK_ID_OCCUPIED")
	var path:Dictionary=_path(a,job,info)
	if not path.ok:return path
	var target:Dictionary=info.target.duplicate(true) if info.get("target") is Dictionary else job.location.duplicate(true)
	var work:Dictionary={"id":work_id,"actor_id":a.id,"candidate_id":id,"job":job,"cost":info.cost.duplicate(true),"reusable":info.get("reusable",info.get("requirements",{}).get("reusable",{})).duplicate(true),"tool_quality":info.tool_quality.duplicate(true),"location":path.location,"target":target,"duration":float(info.duration),"elapsed":0.0,"wear":float(info.get("wear",0)),"stamina":float(info.get("stamina",0)),"status":"active","paused_reason":"","effective_seconds":0.0}
	current.jobs[work_id]=work;_assign(a,work,path.steps)
	tx.events.append({"kind":"zonework-started","actor_id":a.id,"work_id":work_id,"operation":job.kind,"zone_id":zone_id})
	return tx.result()

func _assign(a:Dictionary,work:Dictionary,steps:Array)->void:
	a.intent={"schema_version":1,"owner":"zonework","kind":"zonework","id":work.id,"work_id":work.id,"steps":steps,"step":0,"held":true}
	a.activity="前往区域实际作业点";work.status="active";work.paused_reason=""
func _control(tx:RefCounted,a:Dictionary,kind:String,payload:Dictionary,target:String)->Dictionary:
	var intent:Variant=a.get("intent");var id:String=str(payload.get("work_id",target))
	if intent is Dictionary and intent.get("owner")=="zonework":id=str(intent.work_id)
	var work:=_job(tx,id)
	if work.is_empty() or work.actor_id!=a.id:return Data.reject("ZONEWORK_MISSING")
	if kind=="zonework.cancel":
		_close(tx,work,"cancelled");if intent is Dictionary and intent.get("owner")=="zonework":a.intent=null
		a.activity="已取消区域作业";return tx.result()
	if kind=="zonework.pause":
		if not intent is Dictionary or intent.get("owner")!="zonework":return Data.reject("ZONEWORK_INTENT_MISSING")
		intent.held=false;work.status="paused";work.effective_seconds=0.0;work.paused_reason="手动暂停";return tx.result()
	if intent!=null and (not intent is Dictionary or intent.get("owner")!="zonework" or intent.get("work_id")!=id):return Data.reject("ACTOR_BUSY")
	var resolved:Dictionary={}
	if work.job.get("direct_well",false):
		var ecology:Variant=domain("ecology")
		if ecology!=null:resolved=ecology.chapter_water_job(str(work.job.target_id))
	else:resolved=_resolve(tx,a,str(work.job.zone_id),str(work.candidate_id))
	if resolved.is_empty() or resolved.revision!=work.job.revision:return Data.reject("ZONEWORK_TARGET_CHANGED")
	var info:=_info(tx,a,work.job)
	if not info.ok:return info
	var problem:=_tool_problem(tx,a,work,false)
	if not problem.is_empty():return Data.reject("TOOLS",problem)
	var path:Dictionary=_path(a,work.job,info)
	if not path.ok:return path
	work.location=path.location
	work.target=info.get("target",work.target).duplicate(true)
	_assign(a,work,path.steps);return tx.result()

func _chapter_output_problem(tx:RefCounted,a:Dictionary,zone:Dictionary,job:Dictionary,info:Dictionary)->String:
	var production:Variant=domain("production")
	if production==null or not production.chapter_one or job.kind not in ["draw_raw_water","harvest_crop"]:return ""
	var stock_id:String=str(zone.get("policy",{}).get("target_stock_id",""))
	if stock_id.is_empty():return ""
	var stock:Dictionary=tx.stock(stock_id)
	if stock.is_empty() or not stock.get("searched",true) or not Factory.permitted(a,stock.get("owner")):return "指定收货点目前不可用"
	var cap:Dictionary=production.capacity_check(stock_id,info.get("outputs",{}),"",tx)
	if not cap.ok:return "指定收货点无法接收这一批产物"
	if job.kind=="draw_raw_water":
		var target:float=float(zone.policy.get("target_quantity",4))
		if target>0 and float(stock.items.get("r34:raw_water",0))+production.capacity_reserved(stock_id,"r34:raw_water","",tx)>=target:return "原水库存已达到计划数量"
	return ""

func _tool_problem(tx:RefCounted,a:Dictionary,work:Dictionary,at_work:bool=true)->String:
	var prod:Variant=domain("production");var p:Dictionary=tx.extension(Production.KEY,Production.empty_state())
	if prod==null:return "生产能力不可用"
	if not prod.qualities(p,work.job.tool_ids,work.tool_quality):return "缺少作业工具能力"
	for id:Variant in work.job.tool_ids:
		var tool:=Draft.find(p.tools,str(id))
		if tool.is_empty() or tool.get("holderId")!="pack:"+str(a.id) or (float(tool.get("durability",0))<=0 and float(work.elapsed)+0.000001<float(work.duration)) or prod.tool_unavailable(str(id),str(work.id),tx):return "工具损坏、转移或被其他作业占用"
	if not at_work:return ""
	var at:=G.location(a);var q:RefCounted=context.spatial.current_space()
	var standing:Dictionary=q.standing_point(at)
	if standing.is_empty() or G.point(standing).distance_to(G.point(at))>0.08:return "当前站位缺少真实支撑或身体净空"
	if not Contact.same_level(at,work.location) or G.point(at).distance_to(G.point(work.location))>0.25:return "需要真实到达作业站位"
	var target:Dictionary=work.target if location(work.target) else work.location
	if not q.contact_clear(at,target,str(work.job.get("target_id",""))):return "工具接触线被实际墙体或地形遮挡"
	return ""

func advance(dt:float)->Dictionary:
	if not is_finite(dt) or dt<=0 or dt>0.1:return Data.reject("INVALID_ZONEWORK_STEP")
	if state().jobs.is_empty():return {"ok":true,"code":"OK","world_changes":[],"fact_changes":[],"events":[]}
	var tx:=_draft();var current:Dictionary=tx.extension(KEY,initial())
	# Jobs are the active/suspended work set, never a scan of every world actor.
	for id:Variant in current.jobs.keys():
		var work:Dictionary=current.jobs[id];work.effective_seconds=0.0
		var a:Dictionary=tx.actor(str(work.actor_id))
		if not eligible(a):
			_close(tx,work,"released")
			if a.get("intent") is Dictionary and a.intent.get("owner")=="zonework":a.intent=null
			continue
		var intent:Variant=a.get("intent")
		if not intent is Dictionary or intent.get("owner")!="zonework" or intent.get("work_id")!=id:continue
		if not intent.get("held",false):continue
		var zone:=_zone(tx,str(work.job.zone_id))
		if work.job.get("direct_well",false):zone={"id":work.job.zone_id,"enabled":true,"revision":0,"policy":{}}
		if zone.is_empty() or not zone.enabled or zone.revision!=work.job.zone_revision:
			work.status="blocked";work.paused_reason="工作区已修改或取消";a.activity=work.paused_reason;continue
		if not detailed(G.location(a)) or not detailed(work.location):continue
		if intent.get("replan_after_door",false) or int(intent.step)<intent.steps.size():
			domain("actions").advance_path(tx,a,dt)
			if a.get("intent")==null:work.status="suspended";work.paused_reason="实际路径中断，请重新安排"
			continue
		var info:=_info(tx,a,work.job)
		var problem:String=str(info.get("reason",info.get("code",""))) if not info.ok else _tool_problem(tx,a,work)
		if problem.is_empty() and (float(info.duration)!=float(work.duration) or not Data.json_equal(info.cost,work.cost) or not Data.json_equal(info.tool_quality,work.tool_quality)):problem="作业定义或材料已变化"
		if not problem.is_empty():work.status="blocked";work.paused_reason=problem;a.activity=problem;continue
		var seconds:float=minf(dt,float(work.duration)-float(work.elapsed))
		var rate:float=float(work.stamina)/float(work.duration);var wear_rate:float=float(work.wear)/float(work.duration) if preload("res://scripts/runtime/tool_wear_policy.gd").enabled(context.world) else 0.0
		if rate>0:seconds=minf(seconds,float(a.get("stamina",0))/rate)
		var p:Dictionary=tx.extension(Production.KEY,Production.empty_state())
		for tool_id:Variant in work.job.tool_ids:
			if wear_rate>0:seconds=minf(seconds,float(Draft.find(p.tools,str(tool_id)).durability)/wear_rate)
		if seconds<=0.000001 and float(work.elapsed)+0.000001<float(work.duration):work.status="blocked";work.paused_reason="需要休息或维修工具";a.activity=work.paused_reason;continue
		work.elapsed=minf(float(work.duration),float(work.elapsed)+seconds);work.effective_seconds=seconds
		a.stamina=maxf(0,float(a.stamina)-seconds*rate)
		if wear_rate > 0:
			for tool_id:Variant in work.job.tool_ids:
				var tool:=Draft.find(p.tools,str(tool_id));tool.durability=maxf(0,float(tool.durability)-seconds*wear_rate)
		work.status="active";work.paused_reason="";a.activity="实际区域劳动："+str(work.job.kind)
		if float(work.elapsed)+0.000001<float(work.duration):continue
		# Last-moment ecology, material, capacity and contact checks use the very
		# same staged actor/tools/extensions. Failure never commits partial output.
		var settlement:=_draft(tx.staged,tx.extensions)
		settlement.extra=tx.extra.duplicate(true);settlement.events=tx.events.duplicate(true)
		var completed:Dictionary=domain("ecology").complete_work(settlement,work.job,str(a.id))
		if not completed.ok:work.status="blocked";work.paused_reason=str(completed.get("reason",completed.get("code")));a.activity=work.paused_reason;continue
		tx.staged=settlement.staged;tx.extensions=settlement.extensions;tx.extra=settlement.extra;tx.events=settlement.events
		current=tx.extensions[KEY];work=current.jobs[id];a=tx.actor(str(work.actor_id))
		tx.events.append({"kind":"zonework-completed","actor_id":a.id,"work_id":work.id,"operation":work.job.kind,"zone_id":work.job.zone_id})
		Delivery.queue(self,tx,a,zone,work,info.get("outputs",{}))
		_close(tx,work,"completed");a.intent=null;a.activity="区域作业完成"
	return tx.result()

func _close(tx:RefCounted,work:Dictionary,status:String)->void:
	var current:Dictionary=tx.extension(KEY,initial())
	current.receipts.append({"id":work.id,"actor_id":work.actor_id,"candidate_id":work.candidate_id,"operation":work.job.kind,"elapsed":work.elapsed,"status":status,"at":float(context.clock.call())})
	while current.receipts.size()>128:current.receipts.pop_front()
	current.jobs.erase(work.id)

func safe_handoff(actor_id:String,candidate_id_value:String="",staged_facts:Dictionary={},overrides:Dictionary={})->Dictionary:
	var tx:=_draft(staged_facts,overrides);var a:Dictionary=tx.actor(actor_id)
	if a.is_empty():return Data.reject("ACTOR_UNAVAILABLE")
	var intent:Variant=a.get("intent")
	if intent is Dictionary:
		if intent.get("owner")!="zonework":return Data.reject("OTHER_OWNER_HANDOFF_REQUIRED")
		var work:=_job(tx,str(intent.work_id))
		if work.is_empty():return Data.reject("ZONEWORK_MISSING")
		if candidate_id_value==work.candidate_id:return tx.result()
		work.status="suspended";work.effective_seconds=0.0;work.paused_reason="角色需求或岗位安全让位";a.intent=null;a.activity=work.paused_reason
	var result:Dictionary=tx.result();result.handoff_safe=true;result.carrying=not a.get("pack",{}).is_empty();return result
func prepare_actor_control(request:Dictionary)->Dictionary:
	var translated:Dictionary=request.duplicate(true);var kind:String=str(request.get("kind",""))
	if kind=="cancel":translated.kind="zonework.cancel"
	elif kind=="held":
		if not request.get("payload",{}).get("held") is bool:return Data.reject("INVALID_ZONEWORK_CONTROL")
		translated.kind="zonework.resume" if request.payload.held else "zonework.pause"
	else:return Data.reject("INVALID_ZONEWORK_CONTROL")
	return prepare(translated)
func hold_descriptors(facts:Dictionary,overrides:Dictionary={})->Array:
	var holds:Array=[]
	for work:Dictionary in state(overrides).jobs.values():
		if work.status not in ["active","paused","blocked"] or not eligible(Draft.find(facts.get("actors",[]),str(work.actor_id))):continue
		holds.append({"schema_version":1,"owner":"zonework","intent_id":work.id,"actor_id":work.actor_id,"phase":"active" if work.status=="active" else "paused","source_id":work.job.source_id,"cost":work.cost.duplicate(true),"tool_ids":work.job.tool_ids.duplicate(),"use_target_id":str(work.job.get("target_id",work.candidate_id))})
	return holds
func prepare_actor_release(transitions:Array,facts:Dictionary,pending_changes:Array)->Dictionary:
	var tx:=_draft(facts)
	for change:Dictionary in pending_changes:
		if change.get("op")=="extension.set" and change.get("id")==KEY:
			if change.get("before")!=context.world.extension(KEY) or not change.get("after") is Dictionary:return Data.reject("CAS_MISMATCH")
			tx.extensions[KEY]=change.after.duplicate(true)
	for transition:Variant in transitions:
		if not transition is Dictionary or not Data.valid_id(transition.get("actor_id")) or transition.get("kind") not in ["incapacitated","removed","consent_revoked"]:return Data.reject("INVALID_LIFECYCLE_PLAN")
		for work:Dictionary in tx.extension(KEY,initial()).jobs.values():
			if work.actor_id==transition.actor_id:_close(tx,work,"released")
	return tx.result()

func validate_intent(intent:Dictionary,actor:Dictionary={},_facts:Dictionary={})->Dictionary:
	if intent.get("owner")!="zonework" or intent.get("kind")!="zonework" or intent.get("schema_version")!=1 or not Data.valid_id(intent.get("id")) or intent.get("id")!=intent.get("work_id") or not intent.get("held") is bool:return Data.reject("INVALID_ZONEWORK_INTENT")
	# Reuse the original path schema without granting another owner authority.
	var probe:Dictionary=intent.duplicate(true);probe.owner="actions";probe.kind="guard"
	var actions:Variant=domain("actions")
	if actions==null:return Data.reject("UNAVAILABLE")
	return actions.validate_intent(probe,actor,_facts)
func validate_extensions(facts:Dictionary,overrides:Dictionary={})->Dictionary:
	var v:Variant=overrides[KEY] if overrides.has(KEY) else context.world.extension(KEY)
	if v==null:return {"ok":true,"code":"OK"}
	if not v is Dictionary or v.get("version")!=1 or not v.get("jobs") is Dictionary or not v.get("receipts") is Array or v.receipts.size()>128:return Data.reject("INVALID_ZONEWORK_STATE")
	var workers:Dictionary={};var targets:Dictionary={}
	for id:Variant in v.jobs:
		var w:Variant=v.jobs[id]
		if not w is Dictionary or w.get("id")!=id or not Data.valid_id(id) or not Data.valid_id(w.get("actor_id")) or not Data.valid_id(w.get("candidate_id")) or w.get("status") not in ["active","paused","blocked","suspended"]:return Data.reject("INVALID_ZONEWORK_JOB")
		if not w.get("job") is Dictionary or w.job.get("work_id")!=id or w.job.get("kind") not in OPERATIONS or not w.job.get("tool_ids") is Array or not w.get("cost") is Dictionary or not w.get("tool_quality") is Dictionary or not location(w.get("location")) or not w.get("target") is Dictionary:return Data.reject("INVALID_ZONEWORK_JOB")
		for field:String in ["duration","elapsed","wear","stamina","effective_seconds"]:
			if not number(w.get(field)):return Data.reject("INVALID_ZONEWORK_PROGRESS")
		if float(w.duration)<=0 or float(w.elapsed)>float(w.duration)+0.000001 or float(w.effective_seconds)>0.100001:return Data.reject("INVALID_ZONEWORK_PROGRESS")
		if not Data.valid_id(w.job.get("zone_id")) or not Data.integer(w.job.get("revision")) or int(w.job.revision)<-1 or not number(w.job.get("zone_revision")) or not Data.valid_id(w.job.get("source_id")) or not Data.valid_id(w.job.get("output_id")):return Data.reject("INVALID_ZONEWORK_REFERENCE")
		if w.job.get("direct_well",false) and (w.job.kind!="draw_raw_water" or not Data.valid_id(w.job.get("target_id")) or w.job.zone_id!="well:"+str(w.job.target_id) or w.candidate_id!="well-work:"+str(w.job.target_id) or int(w.job.zone_revision)!=0 or w.job.source_id!="pack:"+str(w.actor_id) or w.job.output_id!=w.job.source_id):return Data.reject("INVALID_WELL_WORK_REFERENCE")
		var a:=Draft.find(facts.get("actors",[]),str(w.actor_id))
		if not eligible(a):return Data.reject("ZONEWORK_ACTOR_UNAVAILABLE")
		if w.status!="suspended":
			if workers.has(w.actor_id) or targets.has(w.candidate_id):return Data.reject("DUPLICATE_ZONEWORK_HOLD")
			workers[w.actor_id]=true;targets[w.candidate_id]=true
	for a:Dictionary in facts.get("actors",[]):
		var intent:Variant=a.get("intent")
		if not intent is Dictionary or intent.get("owner")!="zonework":continue
		var work:Variant=v.jobs.get(intent.get("work_id"))
		if not work is Dictionary or work.actor_id!=a.id or work.status=="suspended":return Data.reject("ZONEWORK_INTENT_ORPHAN")
	return {"ok":true,"code":"OK"}
func actor_work_projection(actor_id:String)->Dictionary:
	var a:Dictionary=context.actor.call(actor_id);var intent:Variant=a.get("intent")
	if not intent is Dictionary or intent.get("owner")!="zonework":return {}
	var w:Dictionary=state().jobs.get(intent.get("work_id"),{})
	if w.is_empty():return {}
	var soil:bool=w.job.kind in ["till","plant_tree","sow","compost"]
	var p:Vector3=G.point(w.target if location(w.target) else w.job.location)+Vector3(0,0.03 if soil else 0.2,0)
	var n:Vector3=G.point(G.location(a))-p;n.y=0;n=n.normalized()
	if soil:n=Vector3.UP
	var tool_id:String=str(w.job.tool_ids[0]) if not w.job.tool_ids.is_empty() else ""
	var prod:Variant=domain("production");var tool:Dictionary=Draft.find(prod.state().tools,tool_id) if prod!=null else {}
	if tool.get("holderId")!="pack:"+actor_id:tool_id="";tool={}
	return {"owner":"zonework","kind":"zonework","operation":w.job.kind,"tool_id":tool_id,"tool_kind":str(tool.get("kind","")),"source_id":str(w.job.source_id),"cost":w.cost.duplicate(true),"reusable":w.get("reusable",{}).duplicate(true),"crop_id":str(w.job.get("crop_id","")),"tree_id":str(w.job.get("tree_id","")),"progress_seconds":w.elapsed,"duration_seconds":w.duration,"effective_work":w.status=="active" and intent.get("held",false) and float(w.effective_seconds)>0,"effective_seconds":w.effective_seconds,"paused_reason":w.paused_reason,"contact":{"position":[p.x,p.y,p.z],"normal":[n.x,n.y,n.z]}}

func projection(actor_id:String="player")->Dictionary:
	var a:Dictionary=context.actor.call(actor_id)
	var result:Dictionary={"available":eligible(a),"owner":"zonework","jobs":[]}
	if not result.available:return result
	for w:Dictionary in state().jobs.values():
		if w.actor_id!=actor_id:continue
		var row:Dictionary=w.duplicate(true)
		row.operation=w.job.kind;row.progress_seconds=w.elapsed;row.duration_seconds=w.duration
		result.jobs.append(row)
	return result

func workforce_status(actor_id:String,staged_facts:Dictionary={},overrides:Dictionary={})->Dictionary:
	var facts:Dictionary=staged_facts if not staged_facts.is_empty() else context.facts.call()
	var a:=Draft.find(facts.get("actors",[]),actor_id);var intent:Variant=a.get("intent")
	var result:Dictionary={"active":false,"manual_paused":false,"yieldable":false,"reason_code":"","candidate_id":""}
	if not intent is Dictionary or intent.get("owner")!="zonework":return result
	var current:Dictionary=state(overrides);var work:Dictionary=current.jobs.get(str(intent.get("work_id","")),{})
	if work.is_empty():result.reason_code="job_missing";return result
	result.active=true;result.candidate_id=work.candidate_id;result.manual_paused=not intent.get("held",false)
	if result.manual_paused:result.reason_code="manual_pause";return result
	result.yieldable=work.status=="blocked";result.reason_code="work_blocked" if result.yieldable else "walking" if int(intent.get("step",0))<intent.get("steps",[]).size() else "working"
	return result
