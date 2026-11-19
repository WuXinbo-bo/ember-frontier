extends RefCounted
## Construction uses the existing DomainDraft and building safety authority.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Recovery=preload("res://scripts/modules/module_recovery.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const Water=preload("res://scripts/modules/module_water.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const Upgrade=preload("res://scripts/modules/module_upgrade.gd")
const Stage=preload("res://scripts/modules/village_building_stage.gd")
const RestoreAction=preload("res://scripts/modules/module_restoration_action.gd")
const Contact=preload("res://scripts/modules/module_contact.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const KEY:="r34:modules"
const REPAIR_COST:={"timber":2,"scrap":1}
const REPAIR_DURATION:=8.0
static func active(p:Dictionary)->bool:return p.get("status") in ["active","blocked","paused"]
static func queued(p:Dictionary)->bool:return p.get("status")=="queued" and p.get("operation")=="build"
static func actor_ready(a:Dictionary)->bool:return not a.is_empty() and float(a.get("hp",0))>0 and (a.id=="player" or (a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false)))
static func conflict(code:String,detail:Dictionary,reason:String="")->Dictionary:
	var result:=Data.reject(code,reason);result.conflicts=[detail];return result
static func footprint_check(host:RefCounted,v:Dictionary,facts:Dictionary,excluding:String="")->Dictionary:
	var d:=Catalog.definition(str(v.definition_id));var box:=Shape.transform_box(v,G.aabb(d.footprint));var world:RefCounted=host.context.world
	if world.region_at(G.json_point(G.point(v.position))).get("id")!=v.region:return Data.reject("MODULE_REGION_MISMATCH")
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(v.region)):return Data.reject("REGION_PAUSED")
	for x:int in range(floori(box.position.x*2),ceili(box.end.x*2)):
		for z:int in range(floori(box.position.z*2),ceili(box.end.z*2)):
			var y:int=roundi(box.position.y*2)
			if absf(float(y)*0.5-box.position.y)>0.001 or not world.is_cell_resident(x,y-1,z) or not Data.material_blocks(world.cell_at(x,y-1,z),"support"):return conflict("MODULE_FOUNDATION_UNSUPPORTED",{"point":{"x":x*.5+.25,"y":(y-1)*.5+.25,"z":z*.5+.25},"kind":"support"})
			for cy:int in range(y,ceili(box.end.y*2)):
				if not world.is_cell_resident(x,cy,z) or Data.material_blocks(world.cell_at(x,cy,z),"body"):return conflict("MODULE_TERRAIN_OCCUPIED",{"point":{"x":x*.5+.25,"y":cy*.5+.25,"z":z*.5+.25},"kind":"terrain"})
	for m:Dictionary in host.state().instances:
		if m.id==excluding or m.status=="dismantled":continue
		if box.intersects(Shape.transform_box(m,G.aabb(Catalog.definition(str(m.definition_id)).footprint))):return conflict("MODULE_OCCUPIED",{"bounds":G.json_box(box.intersection(Shape.transform_box(m,G.aabb(Catalog.definition(str(m.definition_id)).footprint)))),"kind":"module"})
	var query:RefCounted=host.context.spatial.current_space()
	var excluded_members:Dictionary={}
	if not excluding.is_empty():
		for member:Dictionary in host.instance(excluding).get("members",[]):excluded_members[member.id]=true
	for e:Dictionary in query.solid_entities:
		if e.get("data",{}).get("module_id")==excluding:continue
		if box.intersects(G.aabb(e.bounds)):return conflict("MODULE_ENTITY_OCCUPIED",{"bounds":G.json_box(box.intersection(G.aabb(e.bounds))),"kind":"entity"})
	for piece:Dictionary in query.pieces:
		if float(piece.hp)<=0:continue
		if piece.get("module_id")==excluding or excluded_members.has(piece.id):continue
		for collider:AABB in query.geometry.boxes(piece):
			if box.intersects(collider):return conflict("MODULE_STRUCTURE_OCCUPIED",{"bounds":G.json_box(box.intersection(collider)),"kind":"structure"})
	for a:Dictionary in facts.get("actors",[]):
		if float(a.get("hp",0))<=0:continue
		var body:=AABB(G.point(G.location(a))-Vector3(0.26,0,0.26),Vector3(0.52,1.8,0.52))
		if box.intersects(body):return conflict("MODULE_LIVE_ACTOR_OCCUPIED",{"bounds":G.json_box(box.intersection(body)),"kind":"actor"})
	for port:Dictionary in Shape.ports(v,d):
		var standing:Dictionary=query.standing_point(port.location)
		if standing.is_empty() or absf(float(standing.y)-float(port.location.y))>0.01:return conflict("MODULE_PORT_UNSUPPORTED",{"point":port.location.duplicate(true),"port_id":port.id,"kind":"service_support"},str(port.id))
		# A neighbouring planned/operational shell cannot reserve this service pad.
		var body:=AABB(G.point(port.location)-Vector3(0.4,0,0.4),Vector3(0.8,1.8,0.8))
		for m:Dictionary in host.state().instances:
			if m.id!=excluding and m.status!="dismantled" and body.intersects(Shape.transform_box(m,G.aabb(Catalog.definition(str(m.definition_id)).footprint))):return conflict("MODULE_PORT_OCCUPIED",{"bounds":G.json_box(body.intersection(Shape.transform_box(m,G.aabb(Catalog.definition(str(m.definition_id)).footprint)))),"port_id":port.id,"kind":"service_occupied"},str(port.id))
	return {"ok":true,"code":"OK"}
static func plan_instance(host:RefCounted,request:Dictionary)->Dictionary:
	var payload:Dictionary=request.get("payload",{});var d:=Catalog.definition(str(payload.get("definition_id","")));var p:Variant=payload.get("position")
	if d.is_empty() or not Data.vec(p) or not Data.valid_id(p.get("regionId")) or not Data.integer(payload.get("quarter_turn")) or int(payload.quarter_turn) not in [0,1,2,3] or not Data.valid_id(request.get("target_id")):return {}
	var result:Dictionary=host.record_for({"id":request.target_id,"definition_id":d.id,"region":p.regionId,"position":G.json_point(G.point(p)),"quarter_turn":int(payload.quarter_turn),"player_built":true},"home-residents")
	var generation:Variant=host.context.world.extension("generation:factory-r34")
	if generation is Dictionary and int(generation.get("content_version",0)) in [13,14,15,16,17,18,19,20,21] and preload("res://scripts/modules/village_style.gd").eligible(d):result.config.village_style_v1=1
	return result
static func preview(host:RefCounted,request:Dictionary)->Dictionary:
	var v:=plan_instance(host,request)
	if v.is_empty():return Data.reject("INVALID_MODULE_PLAN")
	var a:Dictionary=host.context.actor.call(str(request.get("actor_id","player")))
	if not actor_ready(a):return Data.reject("ACTOR_UNAVAILABLE")
	var d:=Catalog.definition(str(v.definition_id))
	var version_fields:Array[String]=["content_version"]
	var lock:Variant=host.context.world.extension_fields("generation:factory-r34",version_fields) if host.context.world.has_method("extension_fields") else host.context.world.extension("generation:factory-r34")
	var version:int=int(lock.get("content_version",1)) if lock is Dictionary else 1
	if (version>=18 and not host.build_choices().has(d.id)) or (version<18 and (d.has("village_family_art") or d.get("regional_art",false))):return Data.reject("MODULE_NOT_IN_BUILD_MENU","此建筑不能直接建造，请从已有建筑升级")
	var reason:=Stage.reason(host.context.world,d)
	if not reason.is_empty():return Data.reject("MODULE_VILLAGE_STAGE",reason)
	var result:=footprint_check(host,v,host.context.facts.call())
	result.footprint=G.json_box(Shape.transform_box(v,G.aabb(d.footprint)));result.ports=Shape.ports(v,d);result.definition_id=d.id;result.geometry_version=d.geometry_version
	return result
static func production(host:RefCounted)->Variant:return host._production.get_ref() if host._production!=null else null
static func labor_problem(host:RefCounted,tx:RefCounted,p:Dictionary,v:Dictionary)->String:
	var a:Dictionary=tx.actor(str(p.actor_id));var prod:Variant=production(host)
	if not actor_ready(a):return "actor_unavailable"
	if not host.permitted(a,v.get("owner")):return "permission"
	if prod==null:return "production_unavailable"
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(v.region)):return "region_paused"
	if a.get("intent") is Dictionary and a.intent.get("owner")=="actions" and a.intent.get("kind")=="module_approach" and a.intent.get("workforce_candidate_id")=="module-project:"+str(p.id):return "approaching" if a.intent.get("held",true) else "paused"
	if a.get("intent")==null or not a.intent is Dictionary or a.intent.get("owner")!="modules" or a.intent.get("project_id")!=p.id:return "missing_operator"
	if not a.intent.get("held",true):return "paused"
	var query:RefCounted=host.context.spatial.current_space()
	var work_definition:Dictionary=Catalog.definition(str(v.definition_id))
	if p.operation=="upgrade":
		if v.status!="operational" or float(v.hp)!=float(work_definition.hp):return "upgrade_requires_repaired_building"
		var empty:=upgrade_ready(host,tx,v,p.target_definition_id)
		if not empty.ok:return str(empty.code)
	var work_instance:Dictionary=v
	if p.operation=="upgrade":work_instance=v.duplicate(true);work_instance.definition_id=p.target_definition_id
	if not Contact.work_near(query,G.location(a),work_instance):return "operator_not_at_port"
	var source:Dictionary=tx.stock(str(p.source_id));var problem:Variant=prod.reach(str(a.id),str(p.source_id),source,"stock",tx)
	if problem!=null:return str(problem)
	for item:String in p.cost:
		if float(source.items.get(item,0))-prod.work_reserved(str(p.source_id),item,str(p.id),tx)<float(p.cost[item]):return "missing_input"
	var legacy:Dictionary=tx.extension(prod.KEY,prod.empty_state());var tool:=Draft.find(legacy.tools,str(p.tool_id))
	if tool.is_empty() or float(tool.get("durability",0))<=0 or float(prod.tool_qualities(tool).get("hammering",0))<1 or prod.tool_unavailable(str(tool.id),str(p.id),tx):return "missing_tool"
	problem=prod.reach(str(a.id),str(tool.holderId),tx.stock(str(tool.holderId)),"stock",tx)
	return str(problem) if problem!=null else ""
static func discover(host:RefCounted,request:Dictionary)->Dictionary:
	var tx:=Draft.new(host.context);var a:Dictionary=tx.actor(str(request.get("actor_id","")));var state:Dictionary=tx.extension(KEY,host.initial());var v:=Draft.find(state.instances,str(request.get("target_id","")))
	if not actor_ready(a) or v.is_empty() or not host.permitted(a,v.owner):return Data.reject("MODULE_PERMISSION")
	if v.get("discovered",false):return tx.result()
	if not Contact.near(host.context.spatial.current_space(),G.location(a),v):return Data.reject("MODULE_DISCOVER_REQUIRES_CONTACT")
	v.discovered=true;tx.events.append({"kind":"module-discovered","module_id":v.id,"actor_id":a.id});return tx.result()
static func site_entity(v:Dictionary,d:Dictionary)->Dictionary:
	var bounds:=Shape.transform_box(v,G.aabb(d.footprint))
	return {"id":v.id,"kind":"prop","regionId":v.region,"position":v.position.duplicate(true),"bounds":G.json_box(bounds),"revision":0,"blocksTerrain":true,"supportBounds":[G.json_box(AABB(bounds.position,Vector3(bounds.size.x,0.05,bounds.size.z)))],"data":{"module_id":v.id,"module_target":true,"module_construction_site":{"footprint":d.footprint.duplicate(true)},"quarterTurn":int(v.quarter_turn),"solid":false,"opaque":false,"owner":v.owner}}
static func prepare(host:RefCounted,request:Dictionary,facts:Dictionary={},overrides:Dictionary={})->Dictionary:
	if request.get("kind")=="module.discover":return discover(host,request)
	var tx:=Draft.new(host.context)
	if not facts.is_empty():tx.initial=facts.duplicate(true);tx.staged=facts.duplicate(true)
	tx.extensions=overrides.duplicate(true)
	var a:Dictionary=tx.actor(str(request.get("actor_id","")))
	if not actor_ready(a):return Data.reject("ACTOR_UNAVAILABLE")
	var state:Dictionary=tx.extension(KEY,host.initial());var kind:String=str(request.get("kind",""));var payload:Dictionary=request.get("payload",{});var prod:Variant=production(host)
	if kind=="module.plan":
		var preview_result:=preview(host,request)
		if not preview_result.ok:return preview_result
		if not payload.get("plan_only",false) is bool:return Data.reject("INVALID_MODULE_PLAN")
		var plan_only:bool=payload.get("plan_only",false)
		if plan_only and a.id!="player":return Data.reject("MODULE_WORKER_PERMISSION")
		if not plan_only and a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
		var v:=plan_instance(host,request)
		if not Draft.find(state.instances,str(v.id)).is_empty() or not host.context.world.entity(str(v.id)).is_empty() or host.context.world.retired_entity_ids().has(v.id):return Data.reject("MODULE_ID_OCCUPIED")
		if not plan_only and (not Data.valid_id(payload.get("source_id")) or not Data.valid_id(payload.get("tool_id")) or prod==null):return Data.reject("MODULE_SOURCE_REQUIRED")
		v.status="planned" if plan_only else "constructing";var d:=Catalog.definition(str(v.definition_id));var id:String=str(v.id)+":build"
		var p:Dictionary={"id":id,"module_id":v.id,"actor_id":a.id,"operation":"build","source_id":"" if plan_only else payload.source_id,"tool_id":"" if plan_only else payload.tool_id,"cost":d.build_cost.duplicate(true),"progress_seconds":0.0,"duration_seconds":float(d.build_seconds),"status":"queued" if plan_only else "active","paused_reason":"awaiting_worker" if plan_only else "","effective_work":0.0,"geometry_version":v.geometry_version,"created_at":float(host.context.clock.call())}
		v.project_id=id;v.members.append({"id":v.id,"kind":"entity"});state.instances.append(v);state.projects.append(p);tx.staged.stocks.append_array(host.stock_rows(v,d))
		tx.extra.append({"op":"entity.put","id":v.id,"before_exists":false,"before":null,"after":site_entity(v,d)})
		if plan_only:
			tx.events.append({"kind":"module-planned","module_id":v.id,"project_id":p.id,"actor_id":a.id,"plan_only":true})
			return tx.result()
		a.intent={"schema_version":1,"owner":"modules","kind":"construction","id":str(request.get("command_id",id)),"project_id":id,"held":true};a.activity="模块施工"
		# Reserves a real, authorised source; final physical reach is per labor step.
		var source:Dictionary=tx.stock(str(p.source_id))
		if source.is_empty() or not host.permitted(a,source.get("owner")) or not source.get("searched",true):return Data.reject("MODULE_SOURCE_PERMISSION")
		for item:String in p.cost:
			if float(source.items.get(item,0))-prod.work_reserved(str(p.source_id),item,id,tx)<float(p.cost[item]):return Data.reject("MODULE_MATERIALS")
		tx.events.append({"kind":"module-planned","module_id":v.id,"project_id":p.id,"actor_id":a.id})
	elif kind in ["module.work","module.cancel","module.held","module.repair","module.restore","module.dismantle","module.clear_ruin","module.upgrade"]:
		var v:=Draft.find(state.instances,str(request.get("target_id","")))
		if v.is_empty() or not host.permitted(a,v.owner):return Data.reject("MODULE_PERMISSION")
		var p:=Draft.find(state.projects,str(v.project_id))
		if kind in ["module.repair","module.restore","module.dismantle","module.clear_ruin","module.upgrade"]:
			if not p.is_empty() and active(p):return Data.reject("MODULE_PROJECT_ACTIVE")
			if a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
			var d:=Catalog.definition(str(v.definition_id))
			var rebuild:bool=kind=="module.repair" and v.status=="ruined" and Recovery.rebuildable(v,d)
			if kind=="module.clear_ruin" and v.status!="ruined":return Data.reject("MODULE_NOT_OPERATIONAL")
			if kind!="module.clear_ruin" and v.status in ["constructing","planned","dismantled","ruined"] and not rebuild:return Data.reject("MODULE_NOT_OPERATIONAL")
			if kind=="module.repair" and Restoration.pending(v) and not rebuild:return Data.reject("MODULE_RESTORATION_REQUIRED")
			if kind=="module.restore" and (not Restoration.pending(v) or v.status!="damaged"):return Data.reject("MODULE_NOT_RESTORABLE")
			if kind=="module.repair" and float(v.hp)>=float(d.hp):return Data.reject("MODULE_INTACT")
			if kind in ["module.dismantle","module.clear_ruin"]:
				var safe:=can_dismantle(host,tx,v)
				if not safe.ok:return safe
			if kind=="module.upgrade":
				if v.status!="operational" or float(v.hp)!=float(d.hp):return Data.reject("UPGRADE_REQUIRES_REPAIRED_BUILDING")
				var empty:=upgrade_ready(host,tx,v,str(payload.get("definition_id","")))
				if not empty.ok:return empty
			if kind in ["module.restore","module.repair"]:
				var cost:Dictionary=Recovery.rebuild_cost(v,d) if rebuild else REPAIR_COST if kind=="module.repair" else Restoration.cost(v)
				var resolved:=RestoreAction.resolve(host,tx,a,v,payload,"",cost)
				if not resolved.ok:return resolved
				payload=resolved.payload
			if not Data.valid_id(payload.get("source_id")) or not Data.valid_id(payload.get("tool_id")):return Data.reject("MODULE_SOURCE_REQUIRED")
			var id:String=str(v.id)+":project:"+str(state.next_id);state.next_id=int(state.next_id)+1
			p={"id":id,"module_id":v.id,"actor_id":a.id,"operation":"repair" if kind=="module.repair" else "clear_ruin" if kind=="module.clear_ruin" else "dismantle","source_id":payload.source_id,"tool_id":payload.tool_id,"cost":REPAIR_COST.duplicate() if kind=="module.repair" else {},"output_id":payload.get("output_id",payload.source_id),"progress_seconds":0.0,"duration_seconds":REPAIR_DURATION if kind=="module.repair" else 12.0,"status":"active","paused_reason":"","effective_work":0.0,"geometry_version":v.geometry_version,"created_at":float(host.context.clock.call())};state.projects.append(p);v.project_id=id
			if kind=="module.restore":p.operation="restore";p.cost=Restoration.cost(v);p.duration_seconds=Restoration.duration(v)
			if rebuild:
				p.rebuild_ruin_id=v.ruin_id
				p.definition_id=v.definition_id
				p.operation="restore" if Restoration.pending(v) else "repair"
				p.cost=Recovery.rebuild_cost(v,d)
				p.duration_seconds=Recovery.rebuild_seconds(v,d)
			if kind=="module.upgrade":
				var proposal:=Upgrade.proposal(host,v,str(payload.get("definition_id","")),tx.staged)
				if not proposal.ok:return proposal
				p.operation="upgrade";p.paid_basis=v.get("paid_cost",{}).duplicate(true);p.cost=proposal.cost;p.duration_seconds=proposal.duration;p.source_definition_id=v.definition_id;p.target_definition_id=proposal.target.id;p.definition_id=v.definition_id
				# A queued project may still need a worker to walk to the port, but
				# it cannot reserve fictional tools, unauthorised stocks or unpaid
				# material. Actual contact is rechecked during every labor step.
				var source:Dictionary=tx.stock(str(p.source_id))
				if source.is_empty() or not source.get("searched",true) or not host.permitted(a,source.get("owner")):return Data.reject("MODULE_SOURCE_PERMISSION")
				for item:String in p.cost:
					if prod.available_for(str(p.source_id),item,"work",str(p.id),tx)+.000001<float(p.cost[item]):return Data.reject("MODULE_MATERIALS")
				var tool:Dictionary=Draft.find(tx.extension(prod.KEY,prod.empty_state()).tools,str(p.tool_id))
				if tool.is_empty() or float(tool.get("durability",0))<=0 or float(prod.tool_qualities(tool).get("hammering",0))<1 or prod.tool_unavailable(str(p.tool_id),str(p.id),tx):return Data.reject("MODULE_TOOL_REQUIRED")
				var holder:Dictionary=tx.stock(str(tool.holderId))
				if holder.is_empty() or not holder.get("searched",true) or not host.permitted(a,holder.get("owner")):return Data.reject("MODULE_SOURCE_PERMISSION")
		elif p.is_empty() or (not active(p) and not queued(p) and not (kind=="module.work" and p.status=="cancelled" and p.operation=="build" and v.status=="planned")):return Data.reject("MODULE_PROJECT_MISSING")
		if kind=="module.cancel":
			if p.actor_id!=a.id:return Data.reject("MODULE_WORKER_PERMISSION")
			if queued(p):
				var site:Dictionary=host.context.world.entity(str(v.id))
				if site.is_empty():return Data.reject("MODULE_PROJECT_MISSING")
				state.instances.erase(v);state.projects.erase(p)
				var buffers:Array=v.stock_refs.values()
				tx.staged.stocks=tx.staged.stocks.filter(func(stock:Dictionary)->bool:return not buffers.has(stock.id))
				tx.extra.append({"op":"entity.remove","id":v.id,"before_exists":true,"before":site,"after":null})
				tx.events.append({"kind":"module-blueprint-cancelled","module_id":v.id,"project_id":p.id,"actor_id":a.id})
				return tx.result()
			p.status="cancelled";p.effective_work=0.0
			if p.operation=="build":v.status="planned"
			if a.get("intent") is Dictionary and ((a.intent.get("owner")=="modules" and a.intent.get("project_id")==p.id) or (a.intent.get("owner")=="actions" and a.intent.get("workforce_candidate_id")=="module-project:"+str(p.id))):a.intent=null
		elif kind=="module.held":
			if p.actor_id!=a.id or not a.get("intent") is Dictionary or not ((a.intent.get("owner")=="modules" and a.intent.get("project_id")==p.id) or (a.intent.get("owner")=="actions" and a.intent.get("workforce_candidate_id")=="module-project:"+str(p.id))):return Data.reject("MODULE_WORKER_PERMISSION")
			a.intent.held=bool(payload.get("held",false))
		else:
			if a.get("intent")!=null and (not a.intent is Dictionary or not ((a.intent.get("owner")=="modules" and a.intent.get("project_id")==p.id) or (a.intent.get("owner")=="actions" and a.intent.get("workforce_candidate_id")=="module-project:"+str(p.id)))):return Data.reject("ACTOR_BUSY")
			var previous:Dictionary=tx.actor(str(p.actor_id))
			if not previous.is_empty() and previous.id!=a.id and previous.get("intent") is Dictionary and ((previous.intent.get("owner")=="modules" and previous.intent.get("project_id")==p.id) or (previous.intent.get("owner")=="actions" and previous.intent.get("workforce_candidate_id")=="module-project:"+str(p.id))):return Data.reject("MODULE_WORKER_OCCUPIED")
			if queued(p):
				var supplied:=RestoreAction.resolve(host,tx,a,v,payload,str(p.id),p.cost)
				if not supplied.ok:return supplied
				p.source_id=supplied.payload.source_id;p.tool_id=supplied.payload.tool_id
			p.actor_id=a.id;p.status="active";v.status="constructing" if p.operation=="build" else v.status
			p.paused_reason=""
			a.intent={"schema_version":1,"owner":"modules","kind":"construction","id":str(request.get("command_id",p.id)),"project_id":p.id,"held":true}
			if p.operation in ["restore","repair","upgrade","build","dismantle","clear_ruin"] and not Contact.work_near(host.context.spatial.current_space(),G.location(a),v):
				# Reuse the original path executor and reservation ID. The same
				# project keeps its materials and progress through pause/cold-load.
				var approach:=RestoreAction.approach(host,tx,a,p,v,str(request.get("command_id",p.id)))
				if not approach.ok:return approach
	else:return Data.reject("UNKNOWN_MODULE_COMMAND")
	return tx.result()
static func upgrade_ready(host:RefCounted,tx:RefCounted,v:Dictionary,target_id:String)->Dictionary:
	var target:=Catalog.definition_view(target_id)
	if not target.has("village_family_art"):return can_dismantle(host,tx,v)
	return can_dismantle(host,tx,v,target)

static func can_dismantle(host:RefCounted,tx:RefCounted,v:Dictionary,target:Dictionary={})->Dictionary:
	if preload("res://scripts/modules/module_housing.gd").occupied(v,tx.staged):return Data.reject("MODULE_BED_OCCUPIED","仍有人使用或正在前往实际床位")
	var legacy:Dictionary=tx.extension("r3:production",{"orders":[]})
	if legacy.orders.any(func(o:Dictionary)->bool:return o.get("stationId") in [v.id,v.config.get("workbench_id","")] and o.get("status") in ["active","blocked"]):return Data.reject("MODULE_CRAFT_PENDING")
	for buffer:String in v.stock_refs:
		var stock_id:String=v.stock_refs[buffer]
		var stock:Dictionary=tx.stock(stock_id)
		if not target.is_empty() and not stock.is_empty():
			var spec:=Draft.find(target.buffer_specs,buffer)
			if not spec.is_empty():
				for item:String in stock.items:
					var excess:float=float(stock.items[item])-float(spec.limits.get(item,0))
					if excess>0:return Data.reject("MODULE_UPGRADE_STORAGE","新储位无法容纳 %s，还需移走 %s"%[Content.item_definition(item).get("name",item),str(excess)])
				continue
		if stock.is_empty() or stock.items.values().any(func(n:Variant)->bool:return float(n)>0):return Data.reject("MODULE_CONTENT_NOT_EMPTY")
		var prod:Variant=production(host)
		if prod!=null:
			var p:Dictionary=tx.extension(prod.KEY,prod.empty_state())
			if p.tools.any(func(t:Dictionary)->bool:return t.holderId==stock_id) or p.records.any(func(t:Dictionary)->bool:return t.holderId==stock_id):return Data.reject("MODULE_CONTENT_NOT_EMPTY")
	var factory:Variant=tx.extension("r34:production",{"orders":[],"batches":[],"settlements":[],"next_id":1,"version":1})
	for b:Dictionary in factory.batches:
		if b.module_id==v.id and b.status in ["active","blocked","refund_pending"]:return Data.reject("MODULE_BATCH_PENDING")
	for o:Dictionary in factory.orders:
		if o.module_id==v.id and not o.get("paused",false):return Data.reject("MODULE_MACHINE_NOT_STOPPED")
	return {"ok":true,"code":"OK"}
static func advance(host:RefCounted,dt:float)->Dictionary:
	if not is_finite(dt) or dt<=0 or dt>1:return Data.reject("INVALID_STEP")
	var fields:Array[String]=["projects","water"]
	var observed:Variant
	if host.context.world.has_method("extension_fields") and host.context.world.has_extension(KEY):
		observed=host.context.world.extension_fields(KEY,fields)
		# Empty selected fields do not prove an original Dictionary extension.
		# Preserve absent/null/non-Dictionary behavior through the full fallback.
		if not observed is Dictionary or not observed.has("projects"):observed=host.context.world.extension(KEY)
	else:observed=host.context.world.extension(KEY)
	if observed==null:return {"ok":true,"world_changes":[],"fact_changes":[],"events":[]}
	var tx:=Draft.new(host.context)
	# extension() already returns an isolated copy. Reuse it within this one
	# advance; completed/cancelled projects cannot write facts or extensions.
	if observed is Dictionary and not observed.projects.any(func(p:Dictionary)->bool:return active(p)) and not observed.get("water",{}).get("projects",[]).any(func(p:Dictionary)->bool:return Water.active(p)):return tx.result()
	var state:Dictionary=tx.extension(KEY,host.initial());var prod:Variant=production(host)
	for p:Dictionary in state.projects:
		if not active(p):continue
		var v:=Draft.find(state.instances,str(p.module_id));var problem:=labor_problem(host,tx,p,v)
		p.effective_work=0.0
		if not problem.is_empty():p.status="blocked";p.paused_reason=problem;continue
		var a:Dictionary=tx.actor(str(p.actor_id));var legacy:Dictionary=tx.extension(prod.KEY,prod.empty_state());var tool:=Draft.find(legacy.tools,str(p.tool_id))
		# Finished labor can still await a clear site or output capacity. Retry
		# the same safe settlement without demanding or charging another step.
		if float(p.duration_seconds)-float(p.progress_seconds)>0.000001:
			var skill:int=int(a.get("skills",{}).get("village_building",0))
			var work_rate:float=1.0+(0.24 if skill>=6 else 0.12 if skill>=2 else 0.0)
			var seconds:float=minf(dt*work_rate,minf(float(p.duration_seconds)-float(p.progress_seconds),minf(float(a.stamina)/1.2,float(tool.durability)/0.15)))
			if seconds<=0:p.status="blocked";p.paused_reason="stamina_or_tool";continue
			p.progress_seconds=minf(float(p.duration_seconds),float(p.progress_seconds)+seconds);p.effective_work=seconds;p.status="active";p.paused_reason=""
			a.stamina=maxf(0,float(a.stamina)-seconds*1.2)
			if preload("res://scripts/runtime/tool_wear_policy.gd").enabled(tx.context.world):tool.durability=maxf(0,float(tool.durability)-seconds*0.15)
			if float(p.duration_seconds)-float(p.progress_seconds)>0.000001:continue
		if p.operation=="build":
			var safe:=footprint_check(host,v,tx.staged,str(v.id))
			if not safe.ok:p.status="blocked";p.paused_reason=safe.code;continue
			var structures:Dictionary=tx.extension("r3:structures",{"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]});var changes:Array=[]
			host.append_instance(host.context.world,host.context.spatial,v,Catalog.definition(str(v.definition_id)),changes,structures)
			for c:Dictionary in changes:tx.extra.append(c)
			v.status="operational";v.paid_cost=p.cost.duplicate(true);v.recovery_version="rc01-v1"
		elif p.has("rebuild_ruin_id"):
			var safe:=footprint_check(host,v,tx.staged,str(v.id))
			if not safe.ok:p.status="blocked";p.paused_reason=safe.code;continue
			var rebuilt:=Recovery.rebuild(host,tx,v,p,Catalog.definition(str(v.definition_id)))
			if not rebuilt.ok:p.status="blocked";p.paused_reason=rebuilt.code;continue
		elif p.operation=="restore":
			var safe:=footprint_check(host,v,tx.staged,str(v.id))
			if not safe.ok:p.status="blocked";p.paused_reason=safe.code;continue
			if not Restoration.pending(v):return Data.reject("MODULE_ALREADY_RESTORED")
			Restoration.complete(host,tx,v,p)
		elif p.operation=="repair":
			v.hp=float(Catalog.definition(str(v.definition_id)).hp);v.status="operational"
			preload("res://scripts/modules/module_housing.gd").set_usable(host,tx,v,true)
		elif p.operation=="upgrade":
			var upgraded:=Upgrade.complete(host,tx,v,p)
			if not upgraded.ok:p.status="blocked";p.paused_reason=str(upgraded.code);continue
		else:
			var safe:=can_dismantle(host,tx,v)
			if not safe.ok:p.status="blocked";p.paused_reason=safe.code;continue
			var salvage:Dictionary={};var d:=Catalog.definition(str(v.definition_id))
			if p.operation=="clear_ruin":
				if v.get("recovery",{}).get("claimed",true):return Data.reject("RUIN_ALREADY_CLAIMED")
				salvage=v.recovery.items.duplicate(true)
			else:salvage=Recovery.recovery_items(v,0.75)
			var cap:Dictionary=prod.capacity_check(str(p.output_id),salvage,"",tx)
			if not cap.ok:p.status="blocked";p.paused_reason=cap.code;continue
			if prod.reach(str(a.id),str(p.output_id),tx.stock(str(p.output_id)),"stock",tx)!=null:p.status="blocked";p.paused_reason="output_not_at_site";continue
			if not tx.stock_delta(str(p.output_id),salvage):return Data.reject("MODULE_SALVAGE_FAILED")
			var structures:Dictionary=tx.extension("r3:structures",{"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]})
			for member:Dictionary in v.members:
				var e:Dictionary=host.context.world.entity(str(member.id))
				if not e.is_empty():tx.extra.append({"op":"entity.remove","id":member.id,"before_exists":true,"before":e,"after":null})
				if member.kind=="structure":structures.instances=structures.instances.filter(func(s:Dictionary)->bool:return s.id!=member.id)
			v.status="dismantled"
			if p.operation=="clear_ruin":v.recovery.claimed=true
			v.recovery_settlement={"id":str(p.id)+":recovery","version":"rc01-v1","items":salvage.duplicate(true),"claimed":true}
			for order:Dictionary in factory_orders(tx):
				if order.module_id==v.id:order.energy_seconds=0.0;order.paused=true;order.remaining=0
		if not p.cost.is_empty() and not tx.stock_delta(str(p.source_id),p.cost,-1):return Data.reject("MODULE_MATERIALS_CHANGED")
		p.status="completed";p.paused_reason="";a.intent=null;a.activity="模块作业完成"
		tx.events.append({"kind":"module-project-completed","module_id":v.id,"project_id":p.id,"actor_id":a.id,"operation":p.operation})
	if state.has("water"):Water.advance_in(host,tx,dt)
	return tx.result()

static func factory_orders(tx:RefCounted)->Array:return tx.extension("r34:production",{"version":1,"orders":[],"batches":[],"settlements":[],"next_id":1}).orders
