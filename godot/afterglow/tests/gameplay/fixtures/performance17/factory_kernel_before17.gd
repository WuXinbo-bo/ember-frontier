extends RefCounted
## Pure helpers for the existing Production owner; never owns a clock or commits.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Alerts=preload("res://scripts/modules/module_alerts.gd")
const KEY:="r34:production"
const LOGISTICS:="r34:logistics"
const MODULES:="r34:modules"
const RECIPE:="saw_timber"
const SECONDS:=10.0
const FUEL_SECONDS:=20.0

static func initial()->Dictionary:return {"version":1,"orders":[],"batches":[],"settlements":[],"next_id":1}
static func logistics_initial()->Dictionary:return {"version":1,"tasks":[],"reservations":[],"next_id":1}
static func state(host:RefCounted,key:String,tx:RefCounted=null)->Dictionary:
	var fallback:Dictionary=initial() if key==KEY else logistics_initial()
	if tx!=null:return tx.extension(key,fallback)
	var v:Variant=host.context.world.extension(key)
	return v if v is Dictionary else fallback
static func modules(host:RefCounted,tx:RefCounted=null)->Dictionary:
	# Capacity/holds also run for legacy worlds. Observing an absent domain
	# must not enlist a partial {instances:[]} extension in their transaction.
	if tx!=null and tx.extensions.has(MODULES):return tx.extensions[MODULES]
	var v:Variant=host.context.world.extension(MODULES)
	return v if v is Dictionary else {"instances":[]}
static func observed_state(host:RefCounted,key:String,tx:RefCounted=null)->Dictionary:
	return tx.extensions[key] if tx!=null and tx.extensions.has(key) else state(host,key)
static func machine_module(m:Dictionary)->bool:
	var d:=Catalog.definition_view(str(m.get("definition_id","")))
	return d.get("shape")=="woodshop" and d.get("recipe_modes",[]).has("machine")
static func permitted(actor:Dictionary,owner:Variant)->bool:
	return not actor.is_empty() and (owner==null or owner in [actor.get("id"),actor.get("householdId")] or (owner=="home-residents" and (actor.id=="player" or (actor.get("relationship",{}).get("member",false) and actor.get("relationship",{}).get("consent",false)))))
static func module_for(host:RefCounted,id:String,tx:RefCounted=null)->Dictionary:return Draft.find(modules(host,tx).instances,id)
static func spec(host:RefCounted,stock_id:String,tx:RefCounted=null)->Dictionary:
	for m:Dictionary in modules(host,tx).instances:
		for b:Dictionary in Catalog.definition_view(str(m.definition_id)).buffer_specs:
			if m.stock_refs.get(b.id)==stock_id:
				var result:=b.duplicate(true);result.module_status=m.status;return result
	return {}
static func live_batch(b:Dictionary)->bool:return b.get("status") in ["active","blocked","refund_pending"]
static func active_batch(p:Dictionary,module_id:String)->Dictionary:
	for b:Dictionary in p.batches:
		if b.module_id==module_id and live_batch(b):return b
	return {}
static func capacity_reserved(host:RefCounted,stock_id:String,item:String,excluding:String="",tx:RefCounted=null)->float:
	var n:float=0
	for b:Dictionary in observed_state(host,KEY,tx).batches:
		if live_batch(b) and b.id!=excluding and b.output_id==stock_id:n+=float(b.outputs.get(item,0))
	for r:Dictionary in observed_state(host,LOGISTICS,tx).reservations:
		if r.task_id!=excluding and r.destination_id==stock_id:n+=float(r.items.get(item,0))
	# The legacy manual order already promises its complete output.
	var legacy:Dictionary=host.state() if tx==null else tx.extension(host.KEY,host.empty_state())
	for o:Dictionary in legacy.orders:
		if host.active(o) and o.id!=excluding and o.get("outputId")==stock_id and o.kind=="craft":n+=float(host.recipes.get(o.targetId,{}).get("outputs",{}).get(item,0))
	if item=="water":
		for p:Dictionary in modules(host,tx).get("water",{}).get("projects",[]):
			if p.id!=excluding and p.get("operation")=="draw" and p.get("status") in ["active","blocked","paused"] and p.get("output_id")==stock_id:n+=1.0
	return n
static func capacity_check(host:RefCounted,stock_id:String,items:Dictionary,excluding:String="",tx:RefCounted=null)->Dictionary:
	var filter:Dictionary=host.StockPolicy.filter_check(host,stock_id,items,tx)
	if not filter.ok:return filter
	var b:=spec(host,stock_id,tx)
	if b.is_empty():return {"ok":true,"code":"OK"} # Preserve legacy containers/packs.
	if b.module_status not in ["operational","damaged"]:return Data.reject("BUFFER_NOT_OPERATIONAL")
	var stock:Dictionary=host.context.stock.call(stock_id) if tx==null else tx.stock(stock_id)
	if stock.is_empty():return Data.reject("MISSING_BUFFER")
	for item:String in items:
		if not Content.quantity_valid(item,items[item],true) or float(items[item])<0:return Data.reject("INVALID_QUANTITY")
		if not b.limits.has(item):
			var accepted:Array[String]=[]
			for allowed:String in b.limits:accepted.append(str(Content.item_definition(allowed).get("name",allowed)))
			return Data.reject("BUFFER_FILTER","此容器不接收%s；仅接收：%s" % [str(Content.item_definition(item).get("name",item)),"、".join(accepted)])
		if float(stock.items.get(item,0))+float(items[item])+capacity_reserved(host,stock_id,item,excluding,tx)>float(b.limits[item])+0.000001:return Data.reject("BUFFER_FULL",stock_id+"/"+item)
	return {"ok":true,"code":"OK"}
static func reservations(tasks:Array)->Array:
	var result:Array=[]
	for t:Dictionary in tasks:
		if str(t.get("actor_id","")).is_empty() or t.status not in ["collecting","delivering","blocked"]:continue
		result.append({"id":t.id+":reservation","task_id":t.id,"actor_id":t.actor_id,"source_id":t.source_id if t.phase=="collect" else "","destination_id":t.destination_id,"items":t.items.duplicate(true),"phase":t.phase})
	return result
static func sync_logistics(l:Dictionary)->void:l.reservations=reservations(l.tasks)
static func hold_descriptors(host:RefCounted,observed:Dictionary,overrides:Dictionary)->Array:
	var l:Dictionary=overrides[LOGISTICS] if overrides.has(LOGISTICS) else state(host,LOGISTICS);var rows:Array=[]
	var holds_source:Array=l.reservations.duplicate(true)
	for t:Dictionary in l.tasks:
		if t.status=="cargo_held":holds_source.append({"actor_id":t.actor_id,"task_id":t.id,"source_id":"","phase":"deliver","items":t.items})
	for r:Dictionary in holds_source:
		var a:=Draft.find(observed.get("actors",[]),str(r.actor_id))
		if a.is_empty():continue
		rows.append({"schema_version":1,"owner":"production","intent_id":r.task_id,"actor_id":r.actor_id,"phase":"active","source_id":r.source_id if r.phase=="collect" else "pack:"+str(r.actor_id),"cost":r.items.duplicate(true),"tool_ids":[],"use_target_id":""})
	return rows
static func detailed(host:RefCounted,m:Dictionary)->bool:
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(m.region)):return false
	var bounds:AABB=Shape.transform_box(m,G.aabb(Catalog.definition_view(str(m.definition_id)).footprint))
	for x:float in [bounds.position.x,bounds.end.x]:
		for z:float in [bounds.position.z,bounds.end.z]:
			if not host.context.world.is_cell_resident(floori(x*2),floori(float(m.position.y)*2)-1,floori(z*2)):return false
	return true
static func blockers(host:RefCounted,tx:RefCounted,m:Dictionary,o:Dictionary,b:Dictionary)->Array:
	if m.is_empty() or m.get("status") in ["ruined","dismantled","planned","constructing"]:return ["ruined"]
	if m.get("restoration") is Dictionary and not m.restoration.get("completed",false):return ["restoration_required"]
	if float(m.hp)<float(Catalog.definition_view(str(m.definition_id)).hp):return ["damaged"]
	if o.get("paused",false):return ["paused"]
	if not detailed(host,m):return ["region_paused"]
	if o.is_empty():return ["unconfigured"]
	var output:Dictionary=tx.stock(str(m.stock_refs.output))
	if output.is_empty():return ["output_fault"]
	var capacity:=capacity_check(host,str(output.id),{"timber":4.0},str(b.get("id","")),tx)
	if not capacity.ok:return ["output_fault" if not b.is_empty() else "output_full"]
	if b.is_empty():
		if int(o.get("remaining",-1))==0:return ["target_met"]
		var input:Dictionary=tx.stock(str(m.stock_refs.input))
		if input.is_empty() or float(input.items.get("log",0))-host.work_reserved(str(input.id),"log","",tx)<1:return ["missing_input"]
	if float(o.get("energy_seconds",0))<=0.000001:
		var fuel:Dictionary=tx.stock(str(m.stock_refs.fuel))
		if fuel.is_empty() or float(fuel.items.get("log",0))-host.work_reserved(str(fuel.id),"log","",tx)<1:return ["missing_energy"]
	return []
static func prepare(host:RefCounted,request:Dictionary)->Dictionary:
	var tx:=Draft.new(host.context);var a:Dictionary=tx.actor(str(request.get("actor_id","")))
	if a.is_empty() or float(a.get("hp",0))<=0:return Data.reject("ACTOR_UNAVAILABLE")
	var kind:String=str(request.get("kind",""));var payload:Dictionary=request.get("payload",{})
	if kind.begins_with("logistics."):return prepare_logistics(host,tx,request)
	var p:=state(host,KEY,tx);var m:=module_for(host,str(request.get("target_id","")),tx)
	if m.is_empty() or not m.get("discovered",false) or not permitted(a,m.owner):return Data.reject("MODULE_PERMISSION")
	if not machine_module(m):return Data.reject("NOT_MACHINE_MODULE")
	if m.get("restoration") is Dictionary and not m.restoration.get("completed",false):return Data.reject("MODULE_RESTORATION_REQUIRED")
	var o:=Draft.find(p.orders,str(m.id)+":machine")
	if kind=="factory.configure":
		if payload.get("recipe_id",RECIPE)!=RECIPE or not Data.integer(payload.get("batches",-1)) or int(payload.get("batches",-1))==0 or int(payload.get("batches",-1))< -1:return Data.reject("INVALID_FACTORY_CONFIGURATION")
		if o.is_empty():
			o={"id":str(m.id)+":machine","module_id":m.id,"recipe_id":RECIPE,"mode":"machine","remaining":int(payload.get("batches",-1)),"paused":false,"energy_seconds":0.0,"completed":0,"created_at":float(host.context.clock.call())};p.orders.append(o)
		else:o.remaining=int(payload.get("batches",-1));o.paused=false
	elif kind=="factory.pause" or kind=="factory.resume":
		if o.is_empty():return Data.reject("UNCONFIGURED")
		o.paused=kind=="factory.pause"
	elif kind in ["factory.cancel","factory.discard"]:
		if o.is_empty():return Data.reject("UNCONFIGURED")
		o.paused=true;o.remaining=0
		var b:=active_batch(p,str(m.id))
		if not b.is_empty():
			if kind=="factory.discard":
				if payload.get("confirm_discard")!=true:return Data.reject("CONFIRM_WIP_DISCARD_REQUIRED")
				var sid:String=str(b.id)+":discard";b.wip={};b.status="discarded";b.settlement_id=sid;b.effective_work=0.0;b.paused_reason="discarded"
				p.settlements.append({"id":sid,"batch_id":b.id,"module_id":b.module_id,"outputs":{},"time":float(host.context.clock.call()),"kind":"discard"})
				tx.events.append({"kind":"factory-batch-discarded","batch_id":b.id,"module_id":b.module_id,"settlement_id":sid,"actor_id":a.id})
			elif float(b.elapsed)<=0.000001:refund(host,tx,b)
			else:b.status="blocked";b.effective_work=0.0;b.paused_reason="stopped_wip"
	else:return Data.reject("UNKNOWN_FACTORY_COMMAND")
	tx.events.append({"kind":"factory-configuration","actor_id":a.id,"module_id":m.id,"operation":kind})
	return tx.result()
static func refund(host:RefCounted,tx:RefCounted,b:Dictionary)->void:
	var valid:=capacity_check(host,str(b.input_id),b.wip,str(b.id),tx)
	if not valid.ok or tx.stock(str(b.input_id)).is_empty():b.status="refund_pending";b.paused_reason="refund_capacity";return
	if not tx.stock_delta(str(b.input_id),b.wip):b.status="refund_pending";b.paused_reason="refund_capacity";return
	b.wip={};b.status="cancelled";b.paused_reason="cancelled"
	tx.events.append({"kind":"factory-batch-cancelled","batch_id":b.id,"module_id":b.module_id})
static func advance(host:RefCounted,dt:float)->Dictionary:
	if not is_finite(dt) or dt<=0 or dt>1:return Data.reject("INVALID_STEP")
	var observed:Variant=host.context.world.extension(MODULES)
	if observed==null:return {"ok":true,"world_changes":[],"fact_changes":[],"events":[]}
	var tx:=Draft.new(host.context);var p:=state(host,KEY,tx)
	# Blocker checks read the same fresh isolated facts and module snapshot.
	# Fork writable facts before refund, consumption or production, never after
	# mutating a stock. No borrowed reference comes from live authority.
	tx.staged=tx.observe_facts()
	if observed is Dictionary:tx.extensions[MODULES]=observed
	for o:Dictionary in p.orders:
		var m:=module_for(host,str(o.module_id),tx);var b:=active_batch(p,str(o.module_id))
		if not b.is_empty() and b.status=="refund_pending":
			if is_same(tx.initial,tx.staged):tx.staged=tx.initial.duplicate(true)
			refund(host,tx,b);continue
		var faults:=blockers(host,tx,m,o,b)
		o.state_code="idle" if faults.is_empty() else faults[0];o.blockers=faults
		if not faults.is_empty():
			if not b.is_empty():b.status="blocked";b.paused_reason=faults[0];b.effective_work=0.0
			continue
		if is_same(tx.initial,tx.staged):tx.staged=tx.initial.duplicate(true)
		if b.is_empty():
			var id:String="factory-batch:"+str(p.next_id);p.next_id=int(p.next_id)+1
			if not tx.stock_delta(str(m.stock_refs.input),{"log":1.0},-1):return Data.reject("BATCH_INPUT_CHANGED")
			b={"id":id,"module_id":m.id,"order_id":o.id,"recipe_id":RECIPE,"input_id":m.stock_refs.input,"output_id":m.stock_refs.output,"wip":{"log":1.0},"outputs":{"timber":4.0},"status":"active","elapsed":0.0,"duration":SECONDS,"effective_work":0.0,"paused_reason":"","settlement_id":"","started_at":float(host.context.clock.call())};p.batches.append(b)
		if float(o.energy_seconds)<=0.000001:
			if not tx.stock_delta(str(m.stock_refs.fuel),{"log":1.0},-1):return Data.reject("BATCH_FUEL_CHANGED")
			o.energy_seconds=float(o.energy_seconds)+FUEL_SECONDS
		var worked:float=minf(dt,minf(float(b.duration)-float(b.elapsed),float(o.energy_seconds)))
		b.elapsed=minf(float(b.duration),float(b.elapsed)+worked);o.energy_seconds=maxf(0,float(o.energy_seconds)-worked)
		b.status="active";b.effective_work=worked;b.paused_reason="";o.state_code="running";o.blockers=[]
		if float(b.duration)-float(b.elapsed)>0.000001:continue
		var sid:String=str(b.id)+":settlement"
		if not Draft.find(p.settlements,sid).is_empty():return Data.reject("DUPLICATE_BATCH_SETTLEMENT")
		var output_ok:=capacity_check(host,str(b.output_id),b.outputs,str(b.id),tx)
		if not output_ok.ok:b.status="blocked";b.paused_reason="output_fault";continue
		if not tx.stock_delta(str(b.output_id),b.outputs):return Data.reject("BATCH_OUTPUT_CHANGED")
		p.settlements.append({"id":sid,"batch_id":b.id,"module_id":b.module_id,"outputs":b.outputs.duplicate(true),"time":float(host.context.clock.call())})
		b.wip={};b.status="completed";b.settlement_id=sid;o.completed=int(o.completed)+1
		if int(o.remaining)>0:o.remaining=int(o.remaining)-1
		tx.events.append({"kind":"factory-batch-completed","batch_id":b.id,"module_id":b.module_id,"settlement_id":sid,"actor_id":""})
	return tx.result()
static func projection(host:RefCounted,actor_id:String)->Dictionary:
	return _factory_projection(host,actor_id,true)
static func _factory_projection(host:RefCounted,actor_id:String,include_details:bool)->Dictionary:
	var tx:=Draft.new(host.context);var p:=state(host,KEY);var a:Dictionary=tx.actor(actor_id);var orders:Array=[];var batches:Array=[];var alerts:Array=[]
	for o:Dictionary in p.orders:
		var m:=module_for(host,str(o.module_id));if m.is_empty() or not m.get("discovered",false) or not permitted(a,m.owner):continue
		var b:=active_batch(p,str(m.id));var faults:=blockers(host,tx,m,o,b)
		var location:Dictionary=G.location(m.position.merged({"regionId":m.region}))
		for reason:String in faults:
			if reason!="target_met" and m.status not in ["ruined","dismantled"]:alerts.append(Alerts.row(m.id,reason,location,str(b.get("id",o.id))))
		if include_details:
			var row:=o.duplicate(true)
			row.state_code="running" if faults.is_empty() and not b.is_empty() else "idle" if faults.is_empty() else faults[0]
			row.blockers=faults;row.location=location;row.allowed_actions=["factory.configure","factory.pause","factory.resume","factory.cancel","factory.discard"]
			orders.append(row)
			for batch:Dictionary in p.batches:
				if batch.module_id==m.id:batches.append(batch.duplicate(true))
	if not include_details:return {"available":true,"alerts":alerts}
	return {"available":true,"orders":orders,"batches":batches,"alerts":alerts,"recipes":[{"id":RECIPE,"mode":"machine","inputs":{"log":1},"outputs":{"timber":4},"seconds":SECONDS,"fuel_item":"log","fuel_seconds_per_unit":FUEL_SECONDS}]}
static func prepare_logistics(host:RefCounted,tx:RefCounted,request:Dictionary)->Dictionary:
	var l:=state(host,LOGISTICS,tx);var payload:Dictionary=request.get("payload",{});var a:Dictionary=tx.actor(str(request.actor_id))
	if not permitted(a,"home-residents"):return Data.reject("LOGISTICS_PERMISSION")
	if request.kind=="logistics.create":
		var from:Dictionary=tx.stock(str(payload.get("source_id","")));var to:Dictionary=tx.stock(str(payload.get("destination_id","")));var items:Variant=payload.get("items")
		if from.is_empty() or to.is_empty() or from.id==to.id or str(from.id).begins_with("pack:") or str(to.id).begins_with("pack:") or not permitted(a,from.get("owner")) or not permitted(a,to.get("owner")) or not from.get("searched",true) or not to.get("searched",true):return Data.reject("INVALID_LOGISTICS_ENDPOINT")
		if not items is Dictionary or items.is_empty():return Data.reject("INVALID_LOGISTICS_ITEMS")
		for item:String in items:
			if not Content.quantity_valid(item,items[item]) or float(items[item])<=0:return Data.reject("INVALID_LOGISTICS_ITEMS")
		var cap:=capacity_check(host,str(to.id),items,"",tx)
		if not cap.ok:return cap
		var id:String="logistics:"+str(l.next_id);l.next_id=int(l.next_id)+1
		l.tasks.append({"id":id,"source_id":from.id,"destination_id":to.id,"items":items.duplicate(true),"actor_id":"","phase":"collect","status":"queued","repeat":bool(payload.get("repeat",false)),"priority":float(payload.get("priority",0)),"created_at":float(host.context.clock.call()),"trips":0,"reason":""})
	elif request.kind=="logistics.cancel":
		var task:=Draft.find(l.tasks,str(request.get("target_id","")))
		if task.is_empty():return Data.reject("MISSING_LOGISTICS_TASK")
		# Carried goods remain in the actual actor's pack; no teleport/refund.
		task.status="cargo_held" if task.phase=="deliver" and not str(task.actor_id).is_empty() else "cancelled";task.repeat=false;task.reason="cancelled"
		var worker:Dictionary=tx.actor(str(task.actor_id))
		if not worker.is_empty():
			if worker.get("intent") is Dictionary and worker.intent.get("owner")=="actions" and worker.intent.get("logistics_task_id")==task.id:worker.intent=null
			if task.phase=="collect":worker.erase("pending_delivery");task.actor_id=""
	elif request.kind=="logistics.retarget":
		var task:=Draft.find(l.tasks,str(request.get("target_id","")))
		if task.is_empty() or task.status!="cargo_held" or task.phase!="deliver":return Data.reject("CARGO_HANDOFF_REQUIRED")
		var worker:Dictionary=tx.actor(str(task.actor_id));var to:Dictionary=tx.stock(str(payload.get("destination_id","")))
		if worker.is_empty() or not permitted(worker,"home-residents"):return Data.reject("LOGISTICS_WORKER_UNAVAILABLE")
		if to.is_empty() or to.id==task.source_id or str(to.id).begins_with("pack:") or not permitted(a,to.get("owner")) or not permitted(worker,to.get("owner")) or not to.get("searched",true):return Data.reject("INVALID_LOGISTICS_ENDPOINT")
		if worker.get("intent") is Dictionary and worker.intent.get("logistics_task_id")==task.id:return Data.reject("HANDOFF_REQUIRED")
		for item:String in task.items:
			if float(worker.pack.get(item,0))+0.000001<float(task.items[item]):return Data.reject("LOGISTICS_CARGO_MISSING")
		var cap:=capacity_check(host,str(to.id),task.items,str(task.id),tx)
		if not cap.ok:return cap
		task.destination_id=to.id;task.repeat=false;task.reason="retargeted"
		worker.pending_delivery={"source_id":task.source_id,"destination_id":task.destination_id,"items":task.items.duplicate(true),"phase":"deliver","task_id":task.id}
	else:return Data.reject("UNKNOWN_LOGISTICS_COMMAND")
	sync_logistics(l);return tx.result()
static func logistics_projection(host:RefCounted,actor_id:String)->Dictionary:
	return _logistics_projection(host,actor_id,true)
static func _logistics_projection(host:RefCounted,actor_id:String,include_details:bool)->Dictionary:
	var a:Dictionary=host.context.actor.call(actor_id);var l:=state(host,LOGISTICS);var tasks:Array=[];var alerts:Array=[];var visible:Dictionary={}
	if not permitted(a,"home-residents"):
		return {"available":false,"tasks":[],"reservations":[],"alerts":[]} if include_details else {"available":false,"alerts":[]}
	for t:Dictionary in l.tasks:
		var from:Dictionary=host.context.stock.call(str(t.source_id));var to:Dictionary=host.context.stock.call(str(t.destination_id))
		var worker:Dictionary=host.context.actor.call(str(t.actor_id));var held:bool=t.phase=="deliver" and not worker.is_empty() and permitted(a,worker.get("householdId",worker.id))
		if not to.is_empty() and not endpoint_visible(host,a,to):continue
		if not from.is_empty() and not endpoint_visible(host,a,from):continue
		if (to.is_empty() or from.is_empty()) and not held:continue
		if include_details:tasks.append(t.duplicate(true));visible[t.id]=true
		if t.status in ["completed","cancelled"] or str(t.get("reason","")).is_empty():continue
		var location:Dictionary=G.location(worker if held else to)
		alerts.append(Alerts.row(t.id,str(t.reason),location,t.id))
	if not include_details:return {"available":true,"alerts":alerts}
	return {"available":true,"tasks":tasks,"reservations":l.reservations.filter(func(r:Dictionary)->bool:return visible.has(r.task_id)),"alerts":alerts}
static func alert_projection(host:RefCounted,actor_id:String)->Dictionary:
	var factory:Dictionary=_factory_projection(host,actor_id,false)
	var logistics:Dictionary=_logistics_projection(host,actor_id,false)
	var alerts:Array=factory.alerts
	for row:Dictionary in logistics.alerts:
		if not alerts.has(row):alerts.append(row)
	# Factory's existing entry remains available for an unknown actor but yields
	# no private rows; retain that behavior rather than inventing a new policy.
	return {"available":bool(factory.available) or bool(logistics.available),"alerts":alerts}
static func endpoint_visible(host:RefCounted,a:Dictionary,stock:Dictionary)->bool:
	if stock.is_empty() or not stock.get("searched",true) or not permitted(a,stock.get("owner")):return false
	var module_id:String=str(stock.get("module_id",""))
	return module_id.is_empty() or module_for(host,module_id).get("discovered",false)

static func valid_items(items:Variant,positive:bool=false)->bool:
	if not items is Dictionary:return false
	for item:Variant in items:
		if not item is String or not Content.quantity_valid(item,items[item],true) or float(items[item])<0 or (positive and float(items[item])<=0):return false
	return true
static func validate(host:RefCounted,facts:Dictionary,overrides:Dictionary)->Dictionary:
	# Dictionary.get eagerly evaluates its fallback. Read each actual staged
	# domain once, not the full live extension even when an override exists.
	var p:Variant=overrides[KEY] if overrides.has(KEY) else host.context.world.extension(KEY)
	var l:Variant=overrides[LOGISTICS] if overrides.has(LOGISTICS) else host.context.world.extension(LOGISTICS)
	var ms:Variant=overrides[MODULES] if overrides.has(MODULES) else host.context.world.extension(MODULES)
	var instances:Array=ms.get("instances",[]) if ms is Dictionary else []
	if p!=null:
		if not p is Dictionary or p.get("version")!=1 or not p.get("orders") is Array or not p.get("batches") is Array or not p.get("settlements") is Array or not Data.integer(p.get("next_id")) or p.next_id<1:return Data.reject("INVALID_FACTORY_STATE")
		var orders:Dictionary={};var batches:Dictionary={};var settlements:Dictionary={};var working:Dictionary={};var machine_modules:Dictionary={}
		for o:Variant in p.orders:
			if not o is Dictionary or not Data.valid_id(o.get("id")) or orders.has(o.id) or machine_modules.has(o.get("module_id")):return Data.reject("INVALID_FACTORY_ORDER")
			var m:=Draft.find(instances,str(o.get("module_id","")))
			if m.is_empty() or not machine_module(m) or o.get("recipe_id")!=RECIPE or o.get("mode")!="machine" or not o.get("paused") is bool or not Data.integer(o.get("remaining")) or o.remaining< -1 or not Data.integer(o.get("completed")) or o.completed<0 or not finite(o.get("energy_seconds")) or float(o.energy_seconds)<0 or float(o.energy_seconds)>FUEL_SECONDS+0.000001:return Data.reject("INVALID_FACTORY_ORDER")
			orders[o.id]=o;machine_modules[o.module_id]=true
		for b:Variant in p.batches:
			if not b is Dictionary or not Data.valid_id(b.get("id")) or batches.has(b.id) or not orders.has(b.get("order_id")):return Data.reject("INVALID_FACTORY_BATCH")
			var o:Dictionary=orders[b.order_id];var m:=Draft.find(instances,str(b.get("module_id","")))
			if m.is_empty() or b.module_id!=o.module_id or b.get("recipe_id")!=RECIPE or b.get("input_id")!=str(m.id)+":stock:input" or b.get("output_id")!=str(m.id)+":stock:output" or b.get("outputs")!={"timber":4.0} or b.get("status") not in ["active","blocked","refund_pending","completed","cancelled","discarded","destroyed"] or not finite(b.get("elapsed")) or float(b.elapsed)<0 or float(b.elapsed)>SECONDS+0.000001 or b.get("duration")!=SECONDS or not finite(b.get("effective_work")) or float(b.effective_work)<0 or float(b.effective_work)>1.0:return Data.reject("INVALID_FACTORY_BATCH")
			if live_batch(b):
				if working.has(b.module_id) or b.get("wip")!={"log":1.0} or b.get("settlement_id")!="":return Data.reject("INVALID_FACTORY_WIP")
				working[b.module_id]=true
			elif b.get("wip")!={} or (b.status=="completed" and (float(b.elapsed)<SECONDS-0.000001 or b.get("settlement_id")!=str(b.id)+":settlement")) or (b.status=="cancelled" and b.get("settlement_id")!="") or (b.status=="discarded" and b.get("settlement_id")!=str(b.id)+":discard") or (b.status=="destroyed" and b.get("settlement_id")!=str(b.id)+":destroyed"):return Data.reject("INVALID_FACTORY_SETTLEMENT")
			batches[b.id]=b
		for settlement:Variant in p.settlements:
			if not settlement is Dictionary or not Data.valid_id(settlement.get("id")) or settlements.has(settlement.id) or not batches.has(settlement.get("batch_id")):return Data.reject("INVALID_FACTORY_SETTLEMENT")
			var b:Dictionary=batches[settlement.batch_id]
			if b.status not in ["completed","discarded","destroyed"] or b.settlement_id!=settlement.id or b.module_id!=settlement.get("module_id") or (b.outputs if b.status=="completed" else {})!=settlement.get("outputs") or not finite(settlement.get("time")):return Data.reject("INVALID_FACTORY_SETTLEMENT")
			settlements[settlement.id]=true
		for b:Dictionary in p.batches:
			if b.status in ["completed","discarded","destroyed"] and not settlements.has(b.settlement_id):return Data.reject("MISSING_FACTORY_SETTLEMENT")
	if l!=null:
		if not l is Dictionary or l.get("version")!=1 or not l.get("tasks") is Array or not l.get("reservations") is Array or not Data.integer(l.get("next_id")) or l.next_id<1:return Data.reject("INVALID_LOGISTICS_STATE")
		var ids:Dictionary={};var actors:Dictionary={}
		for t:Variant in l.tasks:
			if not t is Dictionary or not Data.valid_id(t.get("id")) or ids.has(t.id) or not Data.valid_id(t.get("source_id")) or not Data.valid_id(t.get("destination_id")) or t.source_id==t.destination_id or not valid_items(t.get("items"),true) or t.items.is_empty() or t.get("phase") not in ["collect","deliver"] or t.get("status") not in ["queued","collecting","delivering","blocked","cargo_held","completed","cancelled"] or not t.get("repeat") is bool or not finite(t.get("priority")) or not finite(t.get("created_at")) or not Data.integer(t.get("trips")) or t.trips<0:return Data.reject("INVALID_LOGISTICS_TASK")
			ids[t.id]=true
			if str(t.get("actor_id","")).is_empty():
				if t.status in ["collecting","delivering","cargo_held"]:return Data.reject("LOGISTICS_ACTOR_MISSING")
			else:
				if actors.has(t.actor_id):return Data.reject("DUPLICATE_LOGISTICS_ACTOR")
				actors[t.actor_id]=true
				var a:=Draft.find(facts.get("actors",[]),str(t.actor_id))
				if a.is_empty():return Data.reject("LOGISTICS_ACTOR_MISSING")
				if t.phase=="deliver" and not ["completed","cancelled"].has(t.status):
					for item:String in t.items:
						if float(a.get("pack",{}).get(item,0))+0.000001<float(t.items[item]):return Data.reject("LOGISTICS_CARGO_MISSING")
		if not Data.json_equal(l.reservations,reservations(l.tasks)):return Data.reject("INVALID_LOGISTICS_RESERVATIONS")
	# Every batch/task schema above still runs. Sum the same promises once in
	# this validation call, then test every real buffer/item including legacy
	# manual holds. No fact snapshot, persistent memo, or second authority.
	var promised:Dictionary={}
	for batch:Dictionary in p.batches if p is Dictionary else []:
		if live_batch(batch):_add_promises(promised,str(batch.output_id),batch.outputs)
	for reservation:Dictionary in l.reservations if l is Dictionary else []:
		_add_promises(promised,str(reservation.destination_id),reservation.items)
	if not instances.is_empty():
		var legacy:Dictionary=overrides[host.KEY] if overrides.has(host.KEY) else host.state()
		for order:Dictionary in legacy.orders:
			if host.active(order) and order.kind=="craft":_add_promises(promised,str(order.outputId),host.recipes.get(order.targetId,{}).get("outputs",{}))
	var stocks:Dictionary={}
	for stock:Dictionary in facts.get("stocks",[]):
		# Runtime validates duplicate IDs; preserve Draft.find's first match in
		# a direct owner call as well. A malformed duplicate is not normalized.
		if not str(stock.id).begins_with("pack:") and not stocks.has(stock.id):stocks[stock.id]=stock
	for actor:Dictionary in facts.get("actors",[]):
		var id:String="pack:"+str(actor.id)
		if not stocks.has(id):stocks[id]={"id":id,"items":actor.pack}
	for m:Dictionary in instances:
		for b:Dictionary in Catalog.definition_view(str(m.definition_id)).buffer_specs:
			var stock:Dictionary=stocks.get(str(m.stock_refs[b.id]),{})
			if stock.is_empty():return Data.reject("MISSING_BUFFER")
			for item:String in b.limits:
				if m.status not in ["ruined","dismantled"] and float(stock.items.get(item,0))+float(promised.get(str(stock.id),{}).get(item,0))>float(b.limits[item])+0.000001:return Data.reject("BUFFER_OVERCOMMITTED")
	return {"ok":true,"code":"OK"}
static func _add_promises(totals:Dictionary,stock_id:String,items:Dictionary)->void:
	if not totals.has(stock_id):totals[stock_id]={}
	for item:String in items:totals[stock_id][item]=float(totals[stock_id].get(item,0))+float(items[item])
static func finite(n:Variant)->bool:return (n is int or n is float) and is_finite(float(n))
static func actor_release(host:RefCounted,transitions:Array,facts:Dictionary,pending:Array)->Dictionary:
	var tx:=Draft.new(host.context);tx.initial=facts.duplicate(true);tx.staged=facts.duplicate(true)
	for c:Dictionary in pending:
		if c.get("op")=="extension.set" and c.get("id") in [KEY,LOGISTICS]:
			if c.get("before_exists")!=host.context.world.has_extension(c.id) or not Data.json_equal(c.get("before"),host.context.world.extension(c.id)) or not c.get("after") is Dictionary:return Data.reject("INVALID_LIFECYCLE_PLAN")
			tx.extensions[c.id]=c.after.duplicate(true)
	var l:=state(host,LOGISTICS,tx)
	for transition:Variant in transitions:
		if not transition is Dictionary or not Data.valid_id(transition.get("actor_id")) or transition.get("kind") not in ["incapacitated","removed","consent_revoked"]:return Data.reject("INVALID_LIFECYCLE_PLAN")
		for t:Dictionary in l.tasks:
			if t.actor_id!=transition.actor_id:continue
			if t.phase=="deliver":
				if transition.kind=="removed":return Data.reject("ACTOR_PROPERTY_TRANSFER_REQUIRED","先安全交接真实携货")
				t.status="cargo_held";t.repeat=false;t.reason=str(transition.kind)
			else:t.actor_id="";t.status="queued";t.reason=str(transition.kind)
	sync_logistics(l);return tx.result()

static func machine_visual(host:RefCounted,module_id:String)->Dictionary:
	var p:=state(host,KEY);var m:=module_for(host,module_id);var o:=Draft.find(p.orders,module_id+":machine");var b:=active_batch(p,module_id)
	if m.is_empty() or not machine_module(m):return {}
	var tx:=Draft.new(host.context);var faults:=blockers(host,tx,m,o,b)
	var code:String="running" if faults.is_empty() and not b.is_empty() else "idle" if faults.is_empty() else faults[0]
	return {"state_code":code,"blockers":faults,"next_batch_blockers":blockers(host,tx,m,o,{}) if not b.is_empty() else [],"mechanism":{"kind":"reciprocating_saw","anchor_id":"saw","active":code=="running" and float(b.get("effective_work",0))>0,"phase":"sawing" if not b.is_empty() else "idle","progress_seconds":float(b.get("elapsed",0)),"duration_seconds":SECONDS,"effective_work":float(b.get("effective_work",0)) if code=="running" else 0.0,"paused_reason":"" if faults.is_empty() else str(faults[0])}}
