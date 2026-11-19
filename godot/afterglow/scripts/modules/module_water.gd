extends RefCounted
## WT01 finite sealed source. The existing modules owner/Draft/clock settles
## both the source debit and the destination credit; no liquid simulation.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Contact=preload("res://scripts/modules/module_contact.gd")
const KEY="r34:modules"
const KIND="emergency-water-wt01-v1"
const COST={"timber":2,"scrap":2}
static func empty()->Dictionary:return {"version":1,"sources":[],"projects":[],"source_receipts":{}}
static func active(p:Dictionary)->bool:return p.get("status") in ["active","blocked","paused"]
static func observe(host:RefCounted,overrides:Dictionary={})->Dictionary:return host.state(overrides).get("water",{})
static func entity(source:Dictionary,revision:int)->Dictionary:
	var at:=G.point(source.position);var box:=AABB(at-Vector3(0.6,0,0.6),Vector3(1.2,1.4,1.2))
	return {"id":source.id,"kind":"prop","regionId":source.region,"position":source.position.duplicate(true),"bounds":G.json_box(box),"revision":revision,"blocksTerrain":true,"supportBounds":[G.json_box(AABB(box.position,Vector3(1.2,0.05,1.2)))],"data":{"water_source_id":source.id,"water_use_point":source.use_point.duplicate(true),"solid":true,"opaque":true,"owner":null}}
static func register(view:RefCounted,plan:Dictionary,state:Dictionary,changes:Array)->Dictionary:
	if int(plan.get("generation_content_version",0))<6:return {"ok":true}
	for raw:Dictionary in plan.get("water_sources",[]):
		if raw.get("kind")!=KIND or raw.get("initial_remaining")!=48 or not Data.valid_id(raw.get("id")) or not Data.valid_id(raw.get("source_key")) or not Data.vec(raw.get("position")) or not Data.vec(raw.get("use_point")) or raw.get("region")!=plan.get("region_id") or raw.use_point.get("regionId")!=raw.region:return Data.reject("INVALID_WATER_SOURCE")
		if not state.has("water"):state["water"]=empty()
		var water:Dictionary=state.water
		if water.source_receipts.has(raw.source_key):
			if water.source_receipts[raw.source_key]!=raw.id:return Data.reject("WATER_SOURCE_CONFLICT")
			continue
		if not view.entity(raw.id).is_empty() or view.retired_entity_ids().has(raw.id) or not Draft.find(water.sources,raw.id).is_empty():return Data.reject("WATER_SOURCE_ID_OCCUPIED")
		var s:Dictionary={"id":raw.id,"source_key":raw.source_key,"region":raw.region,"position":raw.position.duplicate(true),"use_point":G.location(raw.use_point),"discovered":false,"status":"needs_repair","remaining":48,"project_id":""}
		water.sources.append(s);water.source_receipts[raw.source_key]=raw.id
		changes.append({"op":"entity.put","id":s.id,"before_exists":false,"before":null,"after":entity(s,view.get_revision())})
	return {"ok":true}
static func sources_match(host:RefCounted,s:Dictionary)->bool:
	# Current source proof, not a cached permission. Only these detached fields
	# are consumed; all unrelated plan geometry remains in the world owner.
	var view:RefCounted=host.context.world
	var key:="generation:"+str(s.region)
	var fields:Array[String]=["generation_content_version","water_sources"]
	var plan:Variant=view.extension_fields(key,fields) if view.has_method("extension_fields") else view.extension(key)
	if not plan is Dictionary or int(plan.get("generation_content_version",0))<6:return false
	for raw:Dictionary in plan.get("water_sources",[]):
		if raw.get("id")==s.id:return raw.get("kind")==KIND and raw.get("initial_remaining")==48 and raw.get("source_key")==s.source_key and raw.get("region")==s.region and raw.get("position")==s.position and G.location(raw.use_point)==s.use_point
	return false
static func validate(host:RefCounted,modules:Dictionary,facts:Dictionary)->Dictionary:
	if not modules.has("water"):return {"ok":true}
	var w:Variant=modules.water
	if not w is Dictionary or w.get("version")!=1 or not w.get("sources") is Array or not w.get("projects") is Array or not w.get("source_receipts") is Dictionary or w.projects.size()>4096:return Data.reject("INVALID_WATER_STATE")
	var ids:Dictionary={};var workers:Dictionary={};var occupied:Dictionary={};var settled:Dictionary={};var repaired:Dictionary={};var project_ids:Dictionary={}
	for s:Variant in w.sources:
		if not s is Dictionary or not Data.valid_id(s.get("id")) or ids.has(s.id) or not Data.valid_id(s.get("source_key")) or not Data.valid_id(s.get("region")) or not Data.vec(s.get("position")) or not Data.vec(s.get("use_point")) or s.use_point.get("regionId")!=s.region or not s.get("discovered") is bool or not s.get("project_id") is String or s.get("status") not in ["needs_repair","ready"] or not Data.integer(s.get("remaining")) or s.remaining<0 or s.remaining>48:return Data.reject("INVALID_WATER_SOURCE")
		if not sources_match(host,s) or w.source_receipts.get(s.source_key)!=s.id:return Data.reject("INVALID_WATER_ORIGIN")
		ids[s.id]=true;settled[s.id]=0;repaired[s.id]=0
	for p:Variant in w.projects:
		if not p is Dictionary or not Data.valid_id(p.get("id")) or project_ids.has(p.id) or not ids.has(p.get("source_id")) or p.get("actor_id")!="player" or p.get("operation") not in ["repair","draw"] or p.get("status") not in ["active","blocked","paused","completed","cancelled"] or not host.number(p.get("duration_seconds")) or not host.number(p.get("progress_seconds")) or not host.number(p.get("effective_work")) or p.effective_work<0 or p.effective_work>1 or p.progress_seconds<0 or p.progress_seconds>p.duration_seconds or not p.get("paused_reason") is String:return Data.reject("INVALID_WATER_PROJECT")
		project_ids[p.id]=true
		var repair:bool=p.operation=="repair"
		if p.get("duration_seconds")!=(16.0 if repair else 12.0) or not Data.json_equal(p.get("cost"),COST if repair else {}) or not p.get("material_source_id") is String or not p.get("output_id") is String or not p.get("tool_id") is String:return Data.reject("INVALID_WATER_COST")
		if (repair and (not Data.valid_id(p.material_source_id) or not Data.valid_id(p.tool_id))) or (not repair and not Data.valid_id(p.output_id)):return Data.reject("INVALID_WATER_REFERENCE")
		if active(p):
			if workers.has(p.actor_id) or occupied.has(p.source_id) or Draft.find(facts.get("actors",[]),p.actor_id).is_empty():return Data.reject("WATER_DOUBLE_RESERVATION")
			workers[p.actor_id]=true;occupied[p.source_id]=p.id
		if p.status=="completed":
			if not is_equal_approx(float(p.progress_seconds),float(p.duration_seconds)):return Data.reject("INVALID_WATER_SETTLEMENT")
			if repair:repaired[p.source_id]+=1
			else:settled[p.source_id]+=1
	for s:Dictionary in w.sources:
		if s.remaining!=48-settled[s.id] or repaired[s.id]!=(1 if s.status=="ready" else 0) or (settled[s.id]>0 and s.status!="ready") or s.project_id!=occupied.get(s.id,""):return Data.reject("INVALID_WATER_LEDGER")
	if w.source_receipts.size()!=ids.size():return Data.reject("INVALID_WATER_RECEIPTS")
	return {"ok":true}
static func holds(facts:Dictionary,water:Dictionary)->Array:
	var rows:Array=[]
	for p:Dictionary in water.get("projects",[]):
		var a:=Draft.find(facts.get("actors",[]),str(p.actor_id))
		if not active(p) or a.is_empty() or float(a.hp)<=0:continue
		rows.append({"schema_version":1,"owner":"modules","intent_id":p.id,"actor_id":p.actor_id,"phase":"paused" if p.status!="active" else "active","source_id":p.material_source_id,"cost":p.cost.duplicate(true),"tool_ids":[p.tool_id] if p.operation=="repair" else [],"use_target_id":p.source_id})
	return rows
static func problem(host:RefCounted,tx:RefCounted,p:Dictionary,s:Dictionary,require_intent:bool=true)->String:
	var a:Dictionary=tx.actor(str(p.actor_id));var prod:Variant=host._production.get_ref() if host._production!=null else null
	if a.is_empty() or a.id!="player" or float(a.get("hp",0))<=0 or prod==null:return "actor_unavailable"
	if s.is_empty() or not s.discovered or not sources_match(host,s):return "water_source_unknown"
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(s.region)):return "region_paused"
	var e:Dictionary=host.context.world.entity(str(s.id))
	if e.get("data",{}).get("water_source_id")!=s.id:return "water_source_missing"
	if not Data.json_equal(e,entity(s,int(e.get("revision",0)))):return "water_source_changed"
	var q:RefCounted=host.context.spatial.current_space()
	if not Contact.near_entity(q,G.location(a),e):return "operator_not_at_water"
	if require_intent:
		var intent:Variant=a.get("intent")
		if not intent is Dictionary or intent.get("owner")!="modules" or intent.get("kind")!="water" or intent.get("project_id")!=p.id:return "missing_operator"
		if not intent.get("held",true):return "paused"
	if prod.use_reserved(s.id,str(p.id),tx):return "water_source_reserved"
	if p.operation=="repair":
		if s.status!="needs_repair":return "water_already_repaired"
		var legacy:Dictionary=tx.extension(prod.KEY,prod.empty_state())
		if not legacy.knowledge.get(a.id,[]).has("basic_tool_repair"):return "missing_knowledge"
		var tool:=Draft.find(legacy.tools,str(p.tool_id))
		if tool.is_empty() or (float(tool.durability)<=0 and float(p.progress_seconds)<16.0-0.000001) or float(prod.tool_qualities(tool).get("hammering",0))<1 or prod.tool_unavailable(str(tool.id),str(p.id),tx):return "missing_tool"
		if prod.reach(a.id,str(tool.holderId),tx.stock(str(tool.holderId)),"stock",tx)!=null:return "tool_not_at_site"
		var stock:Dictionary=tx.stock(str(p.material_source_id))
		if prod.reach(a.id,str(p.material_source_id),stock,"stock",tx)!=null:return "material_not_at_site"
		for item:String in COST:
			if float(stock.items.get(item,0))-prod.reserved(str(p.material_source_id),item,str(p.id),tx)<float(COST[item]):return "missing_input"
	else:
		if s.status!="ready":return "water_needs_repair"
		if int(s.remaining)<=0:return "water_empty"
		if prod.reach(a.id,str(p.output_id),tx.stock(str(p.output_id)),"stock",tx)!=null:return "output_not_at_site"
		var cap:Dictionary=prod.capacity_check(str(p.output_id),{"water":1},str(p.id),tx)
		if not cap.ok:return str(cap.code)
	return ""
static func prepare(host:RefCounted,request:Dictionary)->Dictionary:
	var tx:=Draft.new(host.context);var a:=tx.actor(str(request.get("actor_id","")));var state:Dictionary=tx.extension(KEY,host.initial())
	if a.get("id")!="player" or float(a.get("hp",0))<=0:return Data.reject("WATER_PLAYER_ONLY")
	if not state.get("water") is Dictionary:return Data.reject("WATER_SOURCE_UNKNOWN")
	var w:Dictionary=state.water;var s:=Draft.find(w.sources,str(request.get("target_id","")));var kind:String=str(request.get("kind",""));var payload:Dictionary=request.get("payload",{})
	if s.is_empty():return Data.reject("WATER_SOURCE_UNKNOWN")
	if kind=="module.water.discover":
		var q:RefCounted=host.context.spatial.current_space()
		if not Contact.near_entity(q,G.location(a),host.context.world.entity(str(s.id))):return Data.reject("WATER_DISCOVER_REQUIRES_CONTACT")
		s.discovered=true;return tx.result()
	if not s.discovered:return Data.reject("WATER_SOURCE_UNKNOWN")
	var p:=Draft.find(w.projects,str(s.project_id))
	if kind in ["module.water.cancel","module.water.held"]:
		if p.is_empty() or not active(p) or not a.get("intent") is Dictionary or a.intent.get("project_id")!=p.id or a.intent.get("owner")!="modules":return Data.reject("WATER_PROJECT_MISSING")
		if kind=="module.water.cancel":p.status="cancelled";p.paused_reason="cancelled";p.effective_work=0.0;s.project_id="";a.intent=null
		else:
			if not payload.get("held") is bool:return Data.reject("INVALID_HELD")
			a.intent.held=payload.held;p.status="active" if payload.held else "paused";p.paused_reason="" if payload.held else "paused";p.effective_work=0.0
		return tx.result()
	if kind not in ["module.water.repair","module.water.draw"]:return Data.reject("UNKNOWN_WATER_COMMAND")
	if a.get("intent")!=null or not p.is_empty() or w.projects.size()>=4096:return Data.reject("WATER_BUSY")
	var repair:bool=kind=="module.water.repair"
	p={"id":str(request.get("command_id","preview"))+":water","source_id":s.id,"actor_id":a.id,"operation":"repair" if repair else "draw","material_source_id":str(payload.get("source_id","")) if repair else "","output_id":str(payload.get("output_id","pack:player")) if not repair else "","tool_id":str(payload.get("tool_id","")) if repair else "","cost":COST.duplicate(true) if repair else {},"progress_seconds":0.0,"duration_seconds":16.0 if repair else 12.0,"status":"active","effective_work":0.0,"paused_reason":""}
	var issue:=problem(host,tx,p,s,false)
	if not issue.is_empty():return Data.reject("WATER_UNAVAILABLE",issue)
	w.projects.append(p);s.project_id=p.id
	a.intent={"schema_version":1,"owner":"modules","kind":"water","id":str(request.get("command_id","preview")),"project_id":p.id,"held":true}
	a.activity="修复封闭储水装置" if repair else "手动取水"
	return tx.result()
static func advance_in(host:RefCounted,tx:RefCounted,dt:float)->void:
	var state:Dictionary=tx.extension(KEY,host.initial())
	for p:Dictionary in state.get("water",{}).get("projects",[]):
		if not active(p):continue
		p.effective_work=0.0;var s:=Draft.find(state.water.sources,str(p.source_id));var issue:=problem(host,tx,p,s)
		if not issue.is_empty():p.status="blocked";p.paused_reason=issue;continue
		var a:Dictionary=tx.actor(str(p.actor_id));var repair:bool=p.operation=="repair";var rate:float=1.0 if repair else 0.5
		var seconds:float=minf(dt,minf(float(p.duration_seconds)-float(p.progress_seconds),float(a.stamina)/rate))
		var prod:RefCounted=host._production.get_ref();var tool:Dictionary={}
		if repair:
			tool=Draft.find(tx.extension(prod.KEY,prod.empty_state()).tools,str(p.tool_id));seconds=minf(seconds,float(tool.durability)*16.0)
		if seconds<=0:p.status="blocked";p.paused_reason="stamina_or_tool";continue
		a.stamina=maxf(0,float(a.stamina)-seconds*rate)
		if repair and preload("res://scripts/runtime/tool_wear_policy.gd").enabled(tx.context.world):tool.durability=maxf(0,float(tool.durability)-seconds/16.0)
		p.progress_seconds=minf(float(p.duration_seconds),float(p.progress_seconds)+seconds);p.effective_work=seconds;p.status="active";p.paused_reason=""
		if float(p.duration_seconds)-float(p.progress_seconds)>0.000001:continue
		issue=problem(host,tx,p,s)
		if not issue.is_empty():p.status="blocked";p.paused_reason=issue;continue
		if repair:
			if not tx.stock_delta(str(p.material_source_id),COST,-1):p.status="blocked";p.paused_reason="missing_input";continue
			s.status="ready"
		else:
			if not tx.stock_delta(str(p.output_id),{"water":1}):p.status="blocked";p.paused_reason="output_changed";continue
			s.remaining-=1
		p.status="completed";s.project_id="";a.intent=null;a.activity="储水装置恢复" if repair else "取水完成"
		tx.events.append({"kind":"water-source-repaired" if repair else "water-collected","source_id":s.id,"project_id":p.id,"actor_id":a.id,"amount":0 if repair else 1,"remaining":s.remaining})
static func projection(host:RefCounted,actor_id:String,id:String,visual_only:bool=false)->Dictionary:
	var a:Dictionary=host.context.actor.call(actor_id)
	if actor_id!="player" or a.is_empty() or float(a.get("hp",0))<=0:return {"available":false,"sources":[],"projects":[]}
	var w:Dictionary=observe(host);var sources:Array=[];var visible:Dictionary={};var projects:Array=[]
	for s:Dictionary in w.get("sources",[]):
		if not s.discovered or (not id.is_empty() and s.id!=id):continue
		var location: Dictionary = G.location(s.position.merged({"regionId": s.region}))
		if visual_only:
			# Scene appearance only consumes discovery and the actual finite state.
			sources.append({"id": s.id, "location": location, "discovered": s.discovered, "status": s.status, "remaining": s.remaining, "project_id": s.project_id})
			visible[s.id] = true
			continue
		var row:Dictionary=s.duplicate(true);row.location=location;row.reserved=0;row.name="封闭应急储水装置"
		var actions:Variant=host._actions.get_ref() if host._actions!=null else null
		if actions!=null and a.get("intent")==null and not Contact.near_entity(host.context.spatial.current_space(),G.location(a),host.context.world.entity(str(s.id))):
			for feet:Dictionary in Contact.entity_points(host.context.spatial.current_space(),G.location(a),host.context.world.entity(str(s.id))):
				if actions.route(actor_id,G.location(a),feet).get("ok",false):
					row.approach={"kind":"walk","target_id":"","payload":{},"destination":feet.duplicate(true)};break
		for p:Dictionary in w.projects:
			if p.source_id==s.id and p.operation=="draw" and active(p):row.reserved+=1
		row.requirements={"repair":{"materials":COST.duplicate(true),"seconds":16,"knowledge":["basic_tool_repair"],"qualities":{"hammering":1},"stamina_per_second":1,"tool_wear":1},"draw":{"seconds":12,"amount":1,"stamina_per_second":0.5,"finite_total":48}}
		row.allowed_actions=["module.water.repair"] if s.status=="needs_repair" else ["module.water.draw"] if s.remaining>0 else []
		if not str(s.project_id).is_empty():row.allowed_actions=["module.water.held","module.water.cancel"]
		sources.append(row);visible[s.id]=true
	for p:Dictionary in w.get("projects",[]):
		if visible.has(p.source_id):projects.append(p.duplicate(true))
	return {"available":true,"sources":sources,"projects":projects}
