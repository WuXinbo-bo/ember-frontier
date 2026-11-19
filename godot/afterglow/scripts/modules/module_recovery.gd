extends RefCounted
## RC01 v1: freeze the actual paid structure cost once. Fixed shell pieces never
## become additional economic objects; tools/cargo/cache goods retain identity.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const KEY:="r34:modules"

static func rebuildable(v:Dictionary,d:Dictionary)->bool:
	return Restoration.village(v) and d.get("shape") in ["home","warehouse"]

static func ruin_id(v:Dictionary)->String:
	return str(v.id)+":ruin:"+str(int(v.get("rebuild_count",0))+1)

static func rebuild_cost(v:Dictionary,d:Dictionary)->Dictionary:
	return Restoration.cost(v) if Restoration.pending(v) else d.build_cost.duplicate(true)

static func rebuild_seconds(v:Dictionary,d:Dictionary)->float:
	return Restoration.duration(v) if Restoration.pending(v) else float(d.build_seconds)

static func rebuild(host:RefCounted,tx:RefCounted,v:Dictionary,p:Dictionary,d:Dictionary)->Dictionary:
	if v.status!="ruined" or v.get("ruin_id")!=p.get("rebuild_ruin_id") or v.get("recovery",{}).get("claimed",true):
		return Data.reject("MODULE_RUIN_CHANGED","残骸已经改变，请重新选择建筑")
	# Ruin caches are still the real stock. Refuse an incompatible cache until
	# its surplus is moved out instead of deleting it or exceeding capacity.
	for buffer:Dictionary in d.buffer_specs:
		var stock:Dictionary=tx.stock(str(v.stock_refs[buffer.id]))
		if stock.is_empty() or stock.get("ruin_id")!=v.ruin_id:return Data.reject("INVALID_RUIN_CACHE")
		for item:String in stock.items:
			var spent:float=float(p.cost.get(item,0)) if stock.id==p.source_id else 0.0
			if not buffer.limits.has(item) or float(stock.items[item])-spent>float(buffer.limits[item])+0.000001:
				return Data.reject("MODULE_REBUILD_STORAGE","残骸缓存的物资超出原建筑储位，请先转移多余物资")
	for buffer:Dictionary in d.buffer_specs:
		var stock:Dictionary=tx.stock(str(v.stock_refs[buffer.id]))
		stock.erase("ruin_id")
		stock.module_id=v.id
		stock.buffer_id=buffer.id
	# Structure salvage stays incorporated in the rebuild. An explicit clear
	# would pay salvage instead and retire the building, so neither can repeat.
	v.erase("recovery")
	v.erase("ruin_id")
	v.rebuild_count=int(v.get("rebuild_count",0))+1
	v.members=[]
	v.status="operational"
	v.hp=float(d.hp)
	if p.operation=="restore":
		v.restoration.completed=true
		v.restoration.project_id=p.id
		v.paid_cost=p.cost.duplicate(true)
	var structures:Dictionary=tx.extension("r3:structures",{"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]})
	host.append_instance(host.context.world,host.context.spatial,v,d,tx.extra,structures)
	tx.events.append({"kind":"module-rebuilt","module_id":v.id,"project_id":p.id,"ruin_id":p.rebuild_ruin_id})
	return {"ok":true,"code":"OK"}

static func recovery_items(v:Dictionary,ratio:float)->Dictionary:
	var result:Dictionary={}
	var basis:Dictionary=Restoration.basis(v)
	if Restoration.pending(v):ratio=0.5
	for item:String in basis:
		var paid:float=float(basis[item]);var step:float=Content.quantity_step(item)
		var quantity:float=minf(1,paid) if item=="r34:salvaged_drive_unit" else floorf(paid*ratio/step)*step
		if quantity>0:result[item]=quantity
	return result
static func damage_in(host:RefCounted,tx:RefCounted,module_id:String,amount:float,cause_id:String)->Dictionary:
	if not is_finite(amount) or amount<=0 or not Data.valid_id(cause_id):return Data.reject("INVALID_MODULE_DAMAGE")
	var state:Dictionary=tx.extension(KEY,host.initial());var v:=Draft.find(state.instances,module_id)
	if v.is_empty() or v.status in ["planned","constructing","dismantled"]:return Data.reject("MODULE_NOT_DAMAGEABLE")
	if v.status=="ruined":return {"ok":true,"code":"ALREADY_RUINED"}
	if host._production==null or host._production.get_ref()==null:return Data.reject("PRODUCTION_UNAVAILABLE")
	if not v.has("damage_receipts"):v.damage_receipts={}
	if v.damage_receipts.has(cause_id):return {"ok":true,"code":"ALREADY_APPLIED"}
	if v.damage_receipts.size()>=8192:return Data.reject("MODULE_DAMAGE_LEDGER_LIMIT")
	v.damage_receipts[cause_id]=amount
	v.hp=maxf(0,float(v.hp)-amount)
	if float(v.hp)>0:
		preload("res://scripts/modules/module_housing.gd").set_usable(host,tx,v,false)
		v.status="damaged";tx.events.append({"kind":"module-damaged","module_id":v.id,"cause_id":cause_id});return {"ok":true,"code":"OK"}
	v.status="ruined";v.ruin_id=ruin_id(v);v.recovery_version="rc01-v1"
	var d:=Catalog.definition(str(v.definition_id));var port:Dictionary=Shape.ports(v,d)[-1]
	v.recovery={"id":str(v.ruin_id)+":recovery","version":"rc01-v1","cause_id":cause_id,"items":recovery_items(v,0.5),"claimed":false,"stock_id":str(v.ruin_id)+":salvage","frozen_at":float(host.context.clock.call())}
	# Caches get explicit ruin storage identity, preserving every item, book and
	# tool at the SAME service face. They are no longer machine buffers.
	var legacy:Dictionary=tx.extension("r3:production",host._production.get_ref().empty_state())
	var relocated:Dictionary={}
	for buffer_id:String in v.stock_refs.keys():
		var old_id:String=v.stock_refs[buffer_id];var stock:Dictionary=tx.stock(old_id)
		if stock.is_empty():return Data.reject("MISSING_MODULE_STOCK")
		var new_id:String=str(v.ruin_id)+":cache:"+buffer_id
		if not tx.stock(new_id).is_empty():return Data.reject("RUIN_STOCK_CONFLICT")
		stock.id=new_id;stock.ruin_id=v.ruin_id;stock.erase("module_id");stock.erase("buffer_id");stock.searched=true;v.stock_refs[buffer_id]=new_id;relocated[old_id]=new_id
		for collection:String in ["tools","records"]:
			for item:Dictionary in legacy.get(collection,[]):
				if item.holderId==old_id:item.holderId=new_id
	for order:Dictionary in legacy.orders:
		if order.get("sourceId") in relocated:order.sourceId=relocated[order.sourceId]
		if order.get("outputId") in relocated:order.outputId=relocated[order.outputId]
		if order.get("stationId") in [v.config.get("workbench_id"),v.id] and order.status in ["active","blocked"]:
			order.status="cancelled";order.reason="module_ruined"
			var a:Dictionary=tx.actor(str(order.actorId))
			if not a.is_empty() and a.get("intent") is Dictionary and a.intent.get("order_id")==order.id:a.intent=null
	var p:=Factory.state(host._production.get_ref(),Factory.KEY,tx)
	for o:Dictionary in p.orders:
		if o.module_id==v.id:o.paused=true;o.remaining=0;o.energy_seconds=0.0;o.state_code="ruined"
	for b:Dictionary in p.batches:
		if b.module_id!=v.id or not Factory.live_batch(b):continue
		var sid:String=str(b.id)+":destroyed"
		if float(b.elapsed)<=0.000001:
			if not tx.stock_delta(str(relocated.get(b.input_id,b.input_id)),b.wip):return Data.reject("RUIN_WIP_RECOVERY_FAILED")
		b.wip={};b.status="destroyed";b.effective_work=0.0;b.settlement_id=sid;b.paused_reason="ruined"
		p.settlements.append({"id":sid,"batch_id":b.id,"module_id":v.id,"outputs":{},"time":float(host.context.clock.call()),"kind":"destroyed"})
	# Old batch endpoint IDs remain historical; active tasks fail honestly and
	# retain carried packs. No target destruction delivers or refunds remotely.
	var logistics:=Factory.state(host._production.get_ref(),Factory.LOGISTICS,tx)
	for task:Dictionary in logistics.tasks:
		if not relocated.has(task.source_id) and not relocated.has(task.destination_id):continue
		if task.phase=="deliver" and not str(task.actor_id).is_empty():
			task.status="cargo_held";task.repeat=false;task.reason="target_ruined"
			var a:Dictionary=tx.actor(str(task.actor_id))
			if not a.is_empty() and a.get("intent") is Dictionary and a.intent.get("owner")=="actions" and a.intent.get("logistics_task_id")==task.id:a.intent=null
		else:
			var a:Dictionary=tx.actor(str(task.actor_id))
			if not a.is_empty():a.intent=null;a.erase("pending_delivery")
			task.status="cancelled";task.actor_id="";task.repeat=false;task.reason="target_ruined"
	Factory.sync_logistics(logistics)
	for project:Dictionary in state.projects:
		if project.module_id==v.id and project.status in ["active","blocked","paused"]:
			project.status="cancelled";project.effective_work=0.0;project.paused_reason="ruined"
			var a:Dictionary=tx.actor(str(project.actor_id))
			var intent:Variant=a.get("intent")
			if intent is Dictionary and intent.get("project_id")==project.id:
				if intent.get("owner")=="modules" or (intent.get("owner")=="actions" and intent.get("kind")=="module_approach"):
					a.intent=null
	# Remove exact member geometry, including old workbench records. Retain a
	# real low static rubble entity, never a running machine hidden by a decal.
	var structures:Dictionary=tx.extension("r3:structures",{"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]})
	for member:Dictionary in v.members:
		if member.id==v.id:continue
		var e:Dictionary=host.context.world.entity(str(member.id))
		if not e.is_empty():tx.extra.append({"op":"entity.remove","id":e.id,"before_exists":true,"before":e,"after":null})
		if member.kind=="structure":structures.instances=structures.instances.filter(func(piece:Dictionary)->bool:return piece.id!=member.id)
	var old:Dictionary=host.context.world.entity(str(v.id));var bounds:=Shape.transform_box(v,G.aabb(d.footprint));bounds.size.y=0.32
	var root:Dictionary={"id":v.id,"kind":"prop","regionId":v.region,"position":G.json_point(bounds.position),"bounds":G.json_box(bounds),"revision":int(old.get("revision",0))+1,"blocksTerrain":true,"supportBounds":[G.json_box(bounds)],"data":{"module_id":v.id,"module_target":true,"ruin_id":v.ruin_id,"module_part":{"size":G.json_point(bounds.size),"material":"old_brick"},"solid":true,"opaque":false,"owner":v.owner}}
	tx.extra.append({"op":"entity.put","id":v.id,"before_exists":not old.is_empty(),"before":null if old.is_empty() else old,"after":root})
	v.members=[{"id":v.id,"kind":"entity"}]
	tx.events.append({"kind":"module-ruined","module_id":v.id,"ruin_id":v.ruin_id,"cause_id":cause_id})
	return {"ok":true,"code":"OK"}
