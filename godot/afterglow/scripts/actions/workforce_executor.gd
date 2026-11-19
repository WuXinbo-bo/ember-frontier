extends RefCounted
## E chooses intent; B proves route/permissions and moves the one physical pack.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Regional=preload("res://scripts/actions/regional_workforce.gd")
const WorkOrders=preload("res://scripts/production/module_work_orders.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const AXE_MAINTENANCE="maintenance:axe:"
const AXE_RECIPE="r34:repair_axe_v2"
static func draft(host:RefCounted,facts:Dictionary,overrides:Dictionary)->RefCounted:
	var tx:=Draft.new(host.context)
	if not facts.is_empty():tx.initial=facts.duplicate(true);tx.staged=facts.duplicate(true)
	tx.extensions=overrides.duplicate(true);return tx
static func observation(host:RefCounted,facts:Dictionary,overrides:Dictionary)->RefCounted:
	# Candidates only read already-isolated caller facts. Do not first fetch and
	# deep-copy live facts and then overwrite those copies. Only the extension
	# lookup table is private: lazy extension enlistment cannot modify its caller.
	# Never use this borrowed view for handoff/prepare/result or any mutation.
	var tx:=Draft.new();tx.context=host.context
	tx.staged=host.context.facts.call() if facts.is_empty() else facts
	tx.initial=tx.staged;tx.extensions=overrides.duplicate();tx.observation_only=true;return tx
static func detailed(host:RefCounted,location:Dictionary)->bool:
	return not host.context.get("region_is_detailed") is Callable or host.context.region_is_detailed.call(str(location.get("regionId","")))
static func candidate(host:RefCounted,tx:RefCounted,a:Dictionary,t:Dictionary)->Dictionary:
	var carrying:bool=t.actor_id==a.id and t.phase=="deliver"
	var from:Dictionary=tx.stock(str(t.source_id));var to:Dictionary=tx.stock(str(t.destination_id));var reason:String=""
	if not host.hold_actor(a):reason="no_consent"
	elif t.status in ["completed","cancelled"]:reason="task_finished"
	elif t.status=="cargo_held" and t.get("reason") in ["cancelled","target_ruined"]:reason="needs_retarget"
	elif not str(t.actor_id).is_empty() and t.actor_id!=a.id:reason="worker_occupied"
	elif to.is_empty() or (not carrying and from.is_empty()):reason="endpoint_missing"
	elif not Factory.permitted(a,to.get("owner")) or (not carrying and not Factory.permitted(a,from.get("owner"))):reason="permission"
	elif not to.get("searched",true) or (not carrying and not from.get("searched",true)):reason="unsearched"
	elif not detailed(host,G.location(a)) or not detailed(host,G.location(to)) or (not carrying and not detailed(host,G.location(from))):reason="region_paused"
	elif not carrying:
		for item:String in t.items:
			if host.production.available_for(str(from.id),item,"work",str(t.id),tx)+0.000001<float(t.items[item]):reason="missing_input";break
	if reason.is_empty() and t.has("zone_id") and not carrying:
		var zone:=Draft.find(Regional.zones(host,tx),str(t.zone_id))
		if zone.is_empty() or not zone.enabled or zone.revision!=t.get("zone_revision"):reason="zone_changed"
		elif not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id):reason="permission"
	if reason.is_empty():
		if carrying:
			for item:String in t.items:
				if float(a.pack.get(item,0))+0.000001<float(t.items[item]):reason="cargo_missing";break
		var cap:Dictionary=host.production.capacity_check(str(t.destination_id),t.items,str(t.id),tx)
		if not cap.ok:reason=str(cap.code)
	var destination:Dictionary=to if carrying else from
	var distance:float=G.point(G.location(a)).distance_to(G.point(G.location(destination))) if not destination.is_empty() else 0.0
	return {"id":t.id,"actor_id":a.id,"kind":"haul","valid":reason.is_empty(),"reason":reason,"carrying":carrying,"player_priority":float(t.priority),"wait_seconds":maxf(0,float(host.context.clock.call())-float(t.created_at)),"route_cost":distance,"unblocks_output":str(t.source_id).ends_with(":stock:output"),"critical_supply":str(t.destination_id).ends_with(":stock:fuel"),"source_id":t.source_id,"destination_id":t.destination_id,"items":t.items.duplicate(true),"phase":t.phase,"status":t.status}
static func candidates(host:RefCounted,actor_id:String,facts:Dictionary,overrides:Dictionary)->Array:
	var tx:=observation(host,facts,overrides);var l:=Factory.state(host.production,Factory.LOGISTICS,tx);var rows:Array=[]
	# Providers inspect different fields of the same committed module state.
	# This observer never commits or mutates that state.
	var module_key := Factory.MODULES
	if not tx.extensions.has(module_key) and host.context.world.has_extension(module_key):
		tx.extension(module_key)
	for a:Dictionary in tx.staged.get("actors",[]):
		if actor_id!="*" and a.id!=actor_id:continue
		for t:Dictionary in l.tasks:
			if t.status not in ["cancelled","completed"]:rows.append(candidate(host,tx,a,t))
		rows.append_array(WorkOrders.candidates(host,a,tx))
		var repair:=_axe_maintenance(host,tx,a)
		if not repair.is_empty():rows.append(repair)
		rows.append_array(Regional.stockpile(host,tx,a))
		rows.append_array(Regional.patrol_points(host,tx,a))
	var modules:Variant=host.module_service()
	if modules!=null:rows.append_array(modules.workforce_candidates(actor_id,tx.staged,tx.extensions))
	return rows

static func _axe_maintenance(host:RefCounted,tx:RefCounted,a:Dictionary)->Dictionary:
	if not host.production.chapter_one or a.get("id")=="player" or not host.hold_actor(a):return {}
	var pack:String="pack:"+str(a.id)
	var broken:String=""
	for tool:Dictionary in tx.extension(host.production.KEY,host.production.empty_state()).tools:
		if tool.holderId!=pack or float(host.production.tool_qualities(tool).get("chopping",0))<1:continue
		if float(tool.durability)>0:return {}
		if tool.kind=="salvaged_axe" and broken.is_empty() and not host.production.tool_unavailable(str(tool.id),"",tx):broken=str(tool.id)
	if broken.is_empty():return {}
	for module:Dictionary in Factory.modules(host.production,tx).instances:
		if module.definition_id!="r40.module.workshop" or not module.get("discovered",false) or module.status!="operational" or not Factory.permitted(a,module.owner) or not detailed(host,{"regionId":module.region}):continue
		for source_id:String in [pack,str(module.stock_refs.get("output","")),str(module.stock_refs.get("input",""))]:
			var source:Dictionary=tx.stock(source_id)
			if source.is_empty() or not source.get("searched",true) or not Factory.permitted(a,source.get("owner")) or host.production.available_for(source_id,"timber","work","",tx)<1:continue
			return {"id":AXE_MAINTENANCE+broken,"actor_id":a.id,"kind":"craft","module_id":module.id,"recipe_id":AXE_RECIPE,"valid":true,"critical_supply":true,"carrying":false,"command":{"kind":"craft","actor_id":a.id,"target_id":module.id,"payload":{"recipe_id":AXE_RECIPE,"source_id":source_id,"output_id":pack,"tool_ids":[],"repair_tool_id":broken,"direct":false}}}
	return {}
static func handoff(host:RefCounted,actor_id:String,candidate_id:String,facts:Dictionary,overrides:Dictionary)->Dictionary:
	var tx:=draft(host,facts,overrides);var a:Dictionary=tx.actor(actor_id)
	if a.is_empty():return Data.reject("ACTOR_UNAVAILABLE")
	var intent:Variant=a.get("intent");var modules:Variant=host.module_service()
	if intent is Dictionary and (intent.get("owner")=="modules" or (intent.get("owner")=="actions" and str(intent.get("workforce_candidate_id","")).begins_with("module-project:"))):
		return modules.safe_handoff(actor_id,tx.staged,tx.extensions) if modules!=null else Data.reject("UNAVAILABLE")
	var l:=Factory.state(host.production,Factory.LOGISTICS,tx);var carrying:bool=false
	for t:Dictionary in l.tasks:
		if t.actor_id!=actor_id or t.status in ["completed","cancelled"]:continue
		if t.phase=="deliver":
			carrying=true
			if not candidate_id.is_empty() and candidate_id!=t.id:return Data.reject("CARGO_HANDOFF_REQUIRED","先继续原交付或安全暂停，货仍在原背包")
			if candidate_id==t.id:continue
			t.status="cargo_held";t.reason="safe_handoff"
		else:
			if candidate_id==t.id:continue
			t.actor_id="";t.status="queued";t.reason="safe_handoff";a.erase("pending_delivery")
	if intent is Dictionary:
		if intent.get("owner")!="actions":return Data.reject("OTHER_OWNER_HANDOFF_REQUIRED")
		# Finish already committed pickups; only uncommitted work is released.
		if candidate_id.is_empty() or intent.get("logistics_task_id")!=candidate_id:
			host.cancel_in(tx,a)
	Factory.sync_logistics(l)
	var result:Dictionary=tx.result();result.handoff_safe=true;result.carrying=carrying;return result
static func prepare(host:RefCounted,request:Dictionary,facts:Dictionary,overrides:Dictionary)->Dictionary:
	var tx:=draft(host,facts,overrides);var actor_id:String=str(request.get("actor_id",""));var a:Dictionary=tx.actor(actor_id)
	if not host.hold_actor(a):return Data.reject("ACTOR_UNAVAILABLE")
	var candidate_id:String=str(request.get("candidate_id",request.get("payload",{}).get("candidate_id","")))
	if candidate_id.is_empty():return Data.reject("INVALID_CANDIDATE")
	var l:=Factory.state(host.production,Factory.LOGISTICS,tx);var t:=Draft.find(l.tasks,candidate_id)
	if candidate_id.begins_with("zone-supply:"):return host.ZoneSupply.prepare(host,tx,a,candidate_id,str(request.get("command_id",candidate_id)))
	if candidate_id.begins_with("stockpile:"):return Regional.prepare_stockpile(host,tx,a,candidate_id)
	if candidate_id.begins_with(AXE_MAINTENANCE):
		var offer:=_axe_maintenance(host,tx,a)
		if offer.get("id")!=candidate_id:return Data.reject("CANDIDATE_UNAVAILABLE","缺少受损斧头、实际板材或可用作坊")
		var command:Dictionary=offer.command.duplicate(true);command.command_id=str(request.get("command_id",candidate_id))
		return host.prepare_in(tx,command)
	if candidate_id.begins_with(WorkOrders.PREFIX):
		for c:Dictionary in WorkOrders.candidates(host,a,tx,candidate_id):
			if c.id!=candidate_id:continue
			if not c.valid:return Data.reject("CANDIDATE_BLOCKED",str(c.reason))
			var command:Dictionary=c.command.duplicate(true);command.command_id=str(request.get("command_id",candidate_id));command.actor_id=actor_id
			return host.prepare_in(tx,command)
		return Data.reject("CANDIDATE_UNAVAILABLE")
	if candidate_id.begins_with("module-project:"):
		for other:Dictionary in l.tasks:
			if other.actor_id==a.id and other.status not in ["completed","cancelled"]:return Data.reject("HANDOFF_REQUIRED")
		var modules:Variant=host.module_service()
		if modules==null:return Data.reject("UNAVAILABLE")
		var claim:Dictionary=modules.claim_workforce_in(tx,actor_id,candidate_id,str(request.get("command_id",candidate_id)))
		if not claim.ok:return claim
		var intent:Dictionary={"schema_version":1,"owner":"actions","kind":"module_approach","id":str(request.get("command_id",candidate_id)),"steps":[],"step":0,"held":true,"workforce_candidate_id":candidate_id}
		if host.try_module_arrival(tx,a,intent):return tx.result()
		var route:Dictionary=host.route(actor_id,G.location(a),claim.candidate.location)
		if not route.ok:return route
		intent.steps=route.steps;a.intent=intent;a.activity="靠近建筑作业"
		return tx.result()
	if t.is_empty():return Data.reject("CANDIDATE_UNAVAILABLE")
	var c:=candidate(host,tx,a,t)
	if not c.valid:return Data.reject("CANDIDATE_BLOCKED",str(c.reason))
	for other:Dictionary in l.tasks:
		if other.id!=t.id and other.actor_id==a.id and other.status not in ["completed","cancelled"]:return Data.reject("HANDOFF_REQUIRED")
	if a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
	var goal:Dictionary=tx.stock(str(t.destination_id if c.carrying else t.source_id))
	var route:Dictionary=host.ZoneSupply.stock_path(host,tx,a,goal)
	if not route.ok:return route
	# Recheck source and destination capacity in this SAME staged draft.
	t.actor_id=a.id;t.status="delivering" if c.carrying else "collecting";t.reason=""
	a.pending_delivery={"source_id":t.source_id,"destination_id":t.destination_id,"items":t.items.duplicate(true),"phase":t.phase,"task_id":t.id}
	var id:String=str(request.get("command_id",str(t.id)+":"+actor_id+":"+str(int(host.context.clock.call()*10))))
	a.intent={"schema_version":1,"owner":"actions","kind":"haul","id":id,"steps":route.steps,"step":0,"held":true,"logistics_task_id":t.id};a.activity="实际取料" if t.phase=="collect" else "实际送货"
	Factory.sync_logistics(l);return tx.result()

static func prepare_guard(host:RefCounted,request:Dictionary,facts:Dictionary,overrides:Dictionary)->Dictionary:
	var tx:=draft(host,facts,overrides);var a:Dictionary=tx.actor(str(request.get("actor_id","")));var at:Variant=request.get("position");var site_id:String=str(request.get("site_id",""))
	if not host.hold_actor(a) or a.get("job")!="guard" or float(a.get("stamina",0))<14:return Data.reject("GUARD_NOT_QUALIFIED")
	if not host.valid_id(request.get("command_id")) or not host.valid_location(at) or site_id.is_empty():return Data.reject("INVALID_GUARD_DESTINATION")
	if a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
	var allowed:bool=false
	for region:Dictionary in host.context.world.regions():
		var plan:Variant=host.context.world.extension("generation:"+str(region.id))
		if not plan is Dictionary:continue
		for site:Dictionary in plan.get("regional_sites",[]):
			if site.id!=site_id:continue
			for point:Dictionary in site.get("encounter_positions",[])+site.get("warning_points",{}).values():
				if point.regionId==at.regionId and G.point(point).distance_to(G.point(at))<0.001:allowed=true
	if not allowed:allowed=Regional.guard_allowed(host,tx,a,site_id,at)
	if not allowed:return Data.reject("INVALID_GUARD_DESTINATION")
	if not detailed(host,G.location(a)) or not detailed(host,at):return Data.reject("REGION_PAUSED")
	var query:RefCounted=host.building.current_space();var feet:Dictionary=query.standing_point(at)
	if feet.is_empty() or G.point(feet).distance_to(G.point(at))>0.01:return Data.reject("GUARD_STANDING_INVALID")
	var route:Dictionary=host.route(str(a.id),G.location(a),at)
	if not route.ok:return route
	a.intent={"schema_version":1,"owner":"actions","kind":"guard","id":request.command_id,"steps":route.steps,"step":0,"held":true,"guard_site_id":site_id,"guard_destination":at.duplicate(true)};a.activity="前往实际守备点"
	return tx.result()
static func step_ready(host:RefCounted,tx:RefCounted,a:Dictionary)->bool:
	var intent:Variant=a.get("intent")
	if intent is Dictionary and intent.get("kind")=="guard":
		var zone:=Draft.find(Regional.zones(host,tx),str(intent.get("guard_site_id","")))
		# Authored city/encounter sites are unaffected. A regional zone keeps
		# real revision/worker permission through the final movement tick.
		if not zone.is_empty() and (not zone.enabled or zone.kind!="patrol" or (not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id))):a.intent=null;a.activity="巡逻区已取消或撤回岗位授权";return false
	var d:Dictionary=a.get("pending_delivery",{})
	if not d.has("task_id"):return true
	var logistics:=Factory.state(host.production,Factory.LOGISTICS,tx);var task:=Draft.find(logistics.tasks,str(d.task_id))
	if not task.is_empty() and task.has("zone_id") and task.phase=="collect":
		var zone:=Draft.find(Regional.zones(host,tx),str(task.zone_id))
		if zone.is_empty() or not zone.enabled or zone.revision!=task.get("zone_revision") or (not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id)):
			task.status="cancelled";task.actor_id="";task.reason="zone_changed";a.erase("pending_delivery");a.intent=null;Factory.sync_logistics(logistics);return false
	var locations:Array=[G.location(a),G.location(tx.stock(str(d.destination_id)))]
	if d.phase=="collect":locations.append(G.location(tx.stock(str(d.source_id))))
	for at:Dictionary in locations:
		if not detailed(host,at):return false
	return true
static func delivery_result(host:RefCounted,tx:RefCounted,a:Dictionary,delivery:Dictionary,collecting:bool,success:bool,reason:String="")->void:
	if not delivery.has("task_id"):return
	var l:=Factory.state(host.production,Factory.LOGISTICS,tx);var t:=Draft.find(l.tasks,str(delivery.task_id))
	if t.is_empty():return
	if not success:
		t.status="cargo_held" if t.phase=="deliver" else "queued";t.reason=reason
		if t.phase=="collect":t.actor_id="";a.erase("pending_delivery")
	elif collecting:t.phase="deliver";t.status="delivering"
	else:
		t.trips=int(t.trips)+1;t.actor_id="";t.phase="collect";t.status="queued" if t.repeat else "completed";t.created_at=float(host.context.clock.call());t.reason=""
		tx.events.append({"kind":"logistics-delivery-completed","task_id":t.id,"actor_id":a.id,"source_id":t.source_id,"destination_id":t.destination_id,"items":t.items.duplicate(true),"trip":t.trips})
	Factory.sync_logistics(l)
