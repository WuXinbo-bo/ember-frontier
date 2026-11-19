extends RefCounted
## Public work facts and physical admission. E chooses; no scheduler or clock.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const KEY:="r34:modules"
const PREFIX:="module-project:"
static func draft(host:RefCounted,facts:Dictionary,overrides:Dictionary)->RefCounted:
	var tx:=Draft.new(host.context)
	if not facts.is_empty():tx.initial=facts.duplicate(true);tx.staged=facts.duplicate(true)
	tx.extensions=overrides.duplicate(true);return tx
static func candidates(host:RefCounted,actor_id:String,facts:Dictionary,overrides:Dictionary)->Array:
	var tx:=draft(host,facts,overrides);var state:Dictionary=tx.extension(KEY,host.initial());var rows:Array=[]
	for a:Dictionary in tx.staged.get("actors",[]):
		if actor_id!="*" and a.id!=actor_id:continue
		for p:Dictionary in state.projects:
			if Projects.active(p):rows.append(candidate(host,a,p,state,tx.staged,tx.extensions))
	return rows
static func candidate(host:RefCounted,a:Dictionary,p:Dictionary,state:Dictionary,facts:Dictionary,overrides:Dictionary)->Dictionary:
	var v:=Draft.find(state.instances,str(p.module_id));var reason:String="";var source_id:String=str(p.source_id);var tool_id:String="";var location:Dictionary={}
	var prod:Variant=Projects.production(host)
	if not Projects.actor_ready(a):reason="no_consent"
	elif v.is_empty() or not host.permitted(a,v.owner):reason="permission"
	elif v.status in ["ruined","dismantled"] and p.operation!="clear_ruin":reason="target_unavailable"
	elif host.context.get("region_is_detailed") is Callable and (not host.context.region_is_detailed.call(str(v.region)) or not host.context.region_is_detailed.call(str(a.regionId))):reason="region_paused"
	elif prod==null:reason="production_unavailable"
	var old:Dictionary=Draft.find(facts.get("actors",[]),str(p.actor_id))
	if reason.is_empty() and old.get("id")!=a.id and old.get("intent") is Dictionary and ((old.intent.get("owner")=="modules" and old.intent.get("project_id")==p.id) or (old.intent.get("owner")=="actions" and old.intent.get("workforce_candidate_id")==PREFIX+str(p.id))):reason="worker_occupied"
	if reason.is_empty():
		var probe:=draft(host,facts,overrides);var pa:Dictionary=probe.actor(str(a.id))
		# Another person's pack never becomes a shared source. A replacement
		# worker may offer its own already-carried material, not teleport theirs.
		if source_id.begins_with("pack:") and source_id!="pack:"+str(a.id):source_id="pack:"+str(a.id)
		var source:Dictionary=probe.stock(source_id)
		if source.is_empty() or not source.get("searched",true) or not host.permitted(a,source.get("owner")):reason="source_unavailable"
		if reason.is_empty():
			for item:String in p.cost:
				if float(source.items.get(item,0))-prod.reserved(source_id,item,str(p.id),probe)+0.000001<float(p.cost[item]):reason="missing_input";break
		if reason.is_empty():
			var legacy:Dictionary=probe.extension(prod.KEY,prod.empty_state());var query:RefCounted=host.context.spatial.current_space()
			for port:Dictionary in Shape.ports(v,Catalog.definition_view(str(v.definition_id))):
				if port.purpose not in ["work","repair","service","input"] or query.standing_point(port.location).is_empty():continue
				pa.merge(port.location,true)
				if prod.reach(str(a.id),source_id,probe.stock(source_id),"stock",probe)!=null:continue
				for tool:Dictionary in legacy.tools:
					if float(tool.get("durability",0))<=0 or float(prod.tool_qualities(tool).get("hammering",0))<1 or prod.tool_unavailable(str(tool.id),str(p.id),probe):continue
					if prod.reach(str(a.id),str(tool.holderId),probe.stock(str(tool.holderId)),"stock",probe)!=null:continue
					location=port.location.duplicate(true);tool_id=str(tool.id);break
				if not location.is_empty():break
			if location.is_empty():reason="site_material_or_tool_unreachable"
	var distance:float=G.point(G.location(a)).distance_to(G.point(location)) if not location.is_empty() else 0
	return {"id":PREFIX+str(p.id),"actor_id":a.id,"kind":"construction" if p.operation=="build" else p.operation,"valid":reason.is_empty(),"reason":reason,"carrying":false,"player_priority":0.0,"wait_seconds":maxf(0,float(host.context.clock.call())-float(p.created_at)),"route_cost":distance,"unblocks_output":false,"critical_supply":false,"module_id":p.module_id,"project_id":p.id,"location":location,"source_id":source_id,"tool_id":tool_id,"progress_seconds":p.progress_seconds,"duration_seconds":p.duration_seconds}
static func claim_in(host:RefCounted,tx:RefCounted,actor_id:String,candidate_id:String,command_id:String,arrived:bool)->Dictionary:
	if not candidate_id.begins_with(PREFIX):return Data.reject("INVALID_CANDIDATE")
	var a:Dictionary=tx.actor(actor_id);var state:Dictionary=tx.extension(KEY,host.initial());var p:=Draft.find(state.projects,candidate_id.trim_prefix(PREFIX))
	if p.is_empty() or not Projects.active(p):return Data.reject("CANDIDATE_UNAVAILABLE")
	var current:Variant=a.get("intent")
	if current!=null and not (arrived and current is Dictionary and current.get("owner")=="actions" and current.get("workforce_candidate_id")==candidate_id):return Data.reject("ACTOR_BUSY")
	var c:=candidate(host,a,p,state,tx.staged,tx.extensions)
	if not c.valid:return Data.reject("CANDIDATE_BLOCKED",str(c.reason))
	p.actor_id=a.id;p.source_id=c.source_id;p.tool_id=c.tool_id;p.status="active";p.paused_reason="";p.effective_work=0.0
	if arrived:
		a.intent={"schema_version":1,"owner":"modules","kind":"construction","id":command_id,"project_id":p.id,"held":true}
		var problem:String=Projects.labor_problem(host,tx,p,Draft.find(state.instances,str(p.module_id)))
		if not problem.is_empty():return Data.reject("CANDIDATE_BLOCKED",problem)
		a.activity="实际模块作业"
	return {"ok":true,"code":"OK","candidate":c}
static func handoff(host:RefCounted,actor_id:String,facts:Dictionary,overrides:Dictionary)->Dictionary:
	var tx:=draft(host,facts,overrides);var a:Dictionary=tx.actor(actor_id)
	if a.is_empty():return Data.reject("ACTOR_UNAVAILABLE")
	var state:Dictionary=tx.extension(KEY,host.initial());var intent:Variant=a.get("intent")
	var project_id:String=str(intent.get("project_id","")) if intent is Dictionary else ""
	if intent is Dictionary and intent.get("owner")=="actions" and str(intent.get("workforce_candidate_id","")).begins_with(PREFIX):project_id=str(intent.workforce_candidate_id).trim_prefix(PREFIX)
	var p:=Draft.find(state.projects,project_id)
	if p.is_empty() or p.actor_id!=a.id:return Data.reject("MODULE_PROJECT_MISSING")
	if Projects.active(p):p.status="paused";p.paused_reason="safe_handoff";p.effective_work=0.0
	a.intent=null
	var result:Dictionary=tx.result();result.handoff_safe=true;result.carrying=false;return result
static func release_in(host:RefCounted,tx:RefCounted,actor_id:String,candidate_id:String)->void:
	# A manual move/cancel during approach releases the physical worker claim
	# in the SAME draft. Progress, original materials and project identity stay.
	if not candidate_id.begins_with(PREFIX):return
	var state:Dictionary=tx.extension(KEY,host.initial());var p:=Draft.find(state.projects,candidate_id.trim_prefix(PREFIX))
	if not p.is_empty() and p.actor_id==actor_id and Projects.active(p):p.status="paused";p.paused_reason="safe_handoff";p.effective_work=0.0
