extends RefCounted
## Planning selects real endpoints. ORIGINAL logistics/guard owns execution.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Opening=preload("res://scripts/runtime/playtest_profile.gd")
const ZoneDef=preload("res://scripts/planning/zone_definitions.gd")
static func zones(host:RefCounted,tx:RefCounted)->Array:
	var state:Variant=tx.extensions["r34:zones"] if tx.extensions.has("r34:zones") else host.context.world.extension("r34:zones")
	return state.get("zones",[]) if state is Dictionary else []
static func inside(zone:Dictionary,at:Dictionary)->bool:
	if zone.region_id!=at.get("regionId"):return false
	var x:int=floori(float(at.x)*2);var z:int=floori(float(at.z)*2)
	for cell:Dictionary in zone.cells:
		if int(cell.x)==x and int(cell.z)==z and absf(float(cell.y)*.5-float(at.y))<.56:return true
	return false
static func ground_receiver(world:RefCounted,a:Dictionary,stock:Dictionary)->bool:
	return not stock.is_empty() and not world.region(str(G.location(stock).regionId)).is_empty() and stock.get("searched",false) and Factory.permitted(a,stock.get("owner")) and not str(stock.id).begins_with("pack:") and not world.entity(str(stock.id)).get("data",{}).get("dropped",false)
static func ground_sources(world:RefCounted,zone:Dictionary,stocks:Array,a:Dictionary)->Array:
	var sources:Array=[]
	var object_order:bool=zone.has("region_ids")
	var size:float=world.config().cellSize if object_order else .5
	for source:Dictionary in stocks:
		if source.get("items",{}).is_empty() or not source.get("searched",false) or not Factory.permitted(a,source.get("owner")):continue
		var at:=G.location(source)
		if object_order:
			if not zone.region_ids.has(at.regionId) or not ZoneDef.contains_xz(zone.bounds,at,size) or not world.region_is_resident(at.regionId):continue
		elif not inside(zone,at):continue
		var entity:Dictionary=world.entity(str(source.id))
		if entity.get("kind")=="container" and entity.get("data",{}).get("dropped",false):sources.append(source)
	return sources

static func _append_forestry_haul(host:RefCounted,tx:RefCounted,a:Dictionary,zone:Dictionary,rows:Array)->void:
	if zone.policy.get("worker_ids",[])!=[a.id] or not zone.has("region_ids"):return
	var dest:Dictionary=tx.stock(Opening.WORKSHOP+":stock:input")
	if not ground_receiver(host.context.world,a,dest) or not _detailed(host,str(G.location(dest).regionId)):return
	var production:RefCounted=host.production
	for source:Dictionary in ground_sources(host.context.world,zone,tx.staged.stocks,a):
		if float(source.items.get("log",0))<=0:continue
		var count:int=floori(minf(4.0,production.available_for(str(source.id),"log","work","",tx)))
		while count>0 and not production.capacity_check(str(dest.id),{"log":count},"",tx).ok:count-=1
		if count>0:
			var offer:=_haul(a,zone,source,dest,"log",count)
			# Take away each cut load before moving to the next tree.
			offer.player_priority=float(zone.policy.get("priority",2))+1.0
			rows.append(offer)

static func patrol_points(host:RefCounted,tx:RefCounted,a:Dictionary)->Array:
	var result:Array=[]
	if a.get("job")!="guard" or not host.hold_actor(a):return result
	var query:RefCounted=host.building.current_space()
	for zone:Dictionary in zones(host,tx):
		if not zone.enabled or zone.kind!="patrol" or zone.region_id!=G.location(a).regionId or zone.cells.is_empty():continue
		if not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id):continue
		var points:Array=[]
		# Four stable extremal cells, no per-cell route search or new timer.
		var selected:Dictionary={}
		for direction:Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var best:Dictionary={};var score:float=-INF
			for cell:Dictionary in zone.cells:
				var n:float=float(cell.x)*direction.x+float(cell.z)*direction.y
				if n>score:score=n;best=cell
			var key:String=str(best.x)+":"+str(best.z)
			if selected.has(key):continue
			selected[key]=true
			var at:Dictionary={"regionId":zone.region_id,"x":float(best.x)*.5+.25,"y":float(best.y)*.5,"z":float(best.z)*.5+.25,"buildingId":null,"storeyId":null};var feet:Dictionary=query.standing_point(at)
			if not feet.is_empty() and absf(float(feet.y)-float(at.y))<.01:points.append(feet)
		if points.is_empty():continue
		var nearest:int=0
		for i:int in points.size():
			if G.point(G.location(a)).distance_squared_to(G.point(points[i]))<G.point(G.location(a)).distance_squared_to(G.point(points[nearest])):nearest=i
		var index:int=(nearest+1)%points.size() if G.point(G.location(a)).distance_to(G.point(points[nearest]))<=.35 else nearest
		if G.point(G.location(a)).distance_to(G.point(points[index]))<=.2:continue
		result.append(_guard(a,str(zone.id),points[index],float(zone.policy.get("priority",2)),"patrol"))
	for m:Dictionary in Factory.modules(host.production,tx).instances:
		var d:=Catalog.definition_view(str(m.definition_id))
		if d.get("mechanism",{}).get("family")!="guard" or not m.get("discovered",false) or m.status!="operational" or float(m.hp)<float(d.hp) or m.region!=G.location(a).regionId or not Factory.permitted(a,m.owner):continue
		for port:Dictionary in Shape.ports(m,d):
			var feet:Dictionary=query.standing_point(port.location)
			if feet.is_empty() or G.point(G.location(a)).distance_to(G.point(feet))<=.2:continue
			result.append(_guard(a,str(m.id),feet,1,"guard_post"));break
	return result
static func _guard(a:Dictionary,id:String,at:Dictionary,priority:float,operation:String)->Dictionary:
	return {"id":"regional-guard:"+id,"actor_id":a.id,"kind":"guard","operation":operation,"site_id":id,"position":at.duplicate(true),"valid":float(a.get("stamina",0))>=14,"reason":"" if float(a.get("stamina",0))>=14 else "stamina","player_priority":priority,"wait_seconds":0.0,"route_cost":G.point(G.location(a)).distance_to(G.point(at)),"unblocks_output":false,"critical_supply":false,"carrying":false}
static func guard_allowed(host:RefCounted,tx:RefCounted,a:Dictionary,id:String,at:Dictionary)->bool:
	for c:Dictionary in patrol_points(host,tx,a):
		if c.valid and c.site_id==id and c.position.regionId==at.get("regionId") and G.point(c.position).distance_to(G.point(at))<.001:return true
	return false
static func stockpile(host:RefCounted,tx:RefCounted,a:Dictionary)->Array:
	var result:Array=[];var prod:RefCounted=host.production
	if not host.hold_actor(a):return result
	var stocks:Array=tx.staged.get("stocks",[])
	var fields:Array[String]=["layout"]
	var opening:Dictionary=tx.read_extension_fields("r34:gameplay",fields).get("layout",{})
	for zone:Dictionary in zones(host,tx):
		if not zone.enabled:continue
		if zone.kind=="forestry" and zone.policy.get("mode")=="harvest_only" and opening.get("cooperative_opening")==Opening.COOPERATIVE_POLICY:
			_append_forestry_haul(host,tx,a,zone,result)
			continue
		if zone.kind!="stockpile":continue
		if not zone.has("region_ids") and zone.region_id!=a.regionId and (zone.policy.get("mode")!="collect_ground" or zone.policy.get("worker_ids",[])!=[a.id] or not _detailed(host,str(zone.region_id))):continue
		if not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id):continue
		var dest:Dictionary=tx.stock(str(zone.policy.get("target_stock_id","")))
		var ground:bool=zone.policy.get("mode")=="collect_ground"
		if dest.is_empty() or not dest.get("searched",true) or not Factory.permitted(a,dest.get("owner")) or str(dest.id).begins_with("pack:"):continue
		if ground:
			if zone.policy.get("worker_ids",[])!=[a.id] or not ground_receiver(host.context.world,a,dest) or not _detailed(host,str(G.location(dest).regionId)):continue
			for source:Dictionary in ground_sources(host.context.world,zone,stocks,a):
				for item:String in source.items:
					var step:float=Content.quantity_step(item)
					if step<=0:continue
					var amount:float=minf(prod.available_for(str(source.id),item,"work","",tx),.25 if Content.item_definition(item).get("unit")=="m3" else 4.0)
					var count:int=floori((amount+.000001)/step)
					while count>0 and not prod.capacity_check(str(dest.id),{item:count*step},"",tx).ok:count-=1
					if count>0:result.append(_haul(a,zone,source,dest,item,count*step))
			continue
		if not inside(zone,G.location(dest)):continue
		var row:Dictionary=prod.StockPolicy.locate(prod,str(dest.id),tx);var policy:Dictionary=row.get("policy",{});var items:Array=zone.policy.get("item_ids",policy.get("target",{}).keys())
		for item:String in items:
			var target:float=float(zone.policy.get("target_quantity",policy.get("target",{}).get(item,0)));var missing:float=target-float(dest.items.get(item,0))-prod.capacity_reserved(str(dest.id),item,"",tx)
			if missing<=0:continue
			for source:Dictionary in stocks:
				if source.id==dest.id or not source.get("searched",true) or not Factory.permitted(a,source.get("owner")) or G.location(source).regionId!=zone.region_id or str(source.id).begins_with("pack:"):continue
				if not str(zone.policy.get("source_stock_id","")).is_empty() and zone.policy.source_stock_id!=source.id:continue
				var amount:float=minf(missing,minf(prod.available_for(str(source.id),item,"work","",tx),.25 if Content.item_definition(item).get("unit")=="m3" else 4.0));var step:float=Content.quantity_step(item);amount=floorf(amount/step)*step
				if amount<=0 or not prod.capacity_check(str(dest.id),{item:amount},"",tx).ok:continue
				result.append(_haul(a,zone,source,dest,item,amount))
				break
	return result
static func _detailed(host:RefCounted,id:String)->bool:
	return not host.context.get("region_is_detailed") is Callable or host.context.region_is_detailed.call(id)
static func _haul(a:Dictionary,zone:Dictionary,source:Dictionary,dest:Dictionary,item:String,amount:float)->Dictionary:
	var id:String="stockpile:"+str(zone.id)+":"+str(dest.id)+":"+item+":"+str(source.id)
	return {"id":id,"actor_id":a.id,"kind":"haul","valid":true,"reason":"","carrying":false,"player_priority":float(zone.policy.get("priority",2)),"wait_seconds":0.0,"route_cost":G.point(G.location(a)).distance_to(G.point(G.location(source))),"unblocks_output":false,"critical_supply":false,"source_id":source.id,"destination_id":dest.id,"items":{item:amount},"phase":"collect","status":"queued","zone_id":zone.id,"zone_revision":zone.revision}
static func prepare_stockpile(host:RefCounted,tx:RefCounted,a:Dictionary,candidate_id:String)->Dictionary:
	for c:Dictionary in stockpile(host,tx,a):
		if c.id!=candidate_id:continue
		var l:=Factory.state(host.production,Factory.LOGISTICS,tx)
		if l.tasks.any(func(t:Dictionary)->bool:return t.actor_id==a.id and t.status not in ["completed","cancelled"]):return Data.reject("HANDOFF_REQUIRED")
		if a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
		var path:Dictionary=host.ZoneSupply.stock_path(host,tx,a,tx.stock(str(c.source_id)))
		if not path.ok:return path
		var zone:=Draft.find(zones(host,tx),str(c.zone_id))
		if zone.policy.get("mode") in ["collect_ground","harvest_only"]:
			var pickup:Dictionary=a.duplicate()
			for step:Dictionary in path.steps:
				if step.get("to") is Dictionary:pickup.merge(step.to,true)
			var destination_path:Dictionary=host.ZoneSupply.stock_path(host,tx,pickup,tx.stock(str(c.destination_id)))
			if not destination_path.ok:return Data.reject("UNREACHABLE","从物资到接收仓没有可走的路线")
		var id:String="logistics:"+str(l.next_id);l.next_id=int(l.next_id)+1
		l.tasks.append({"id":id,"source_id":c.source_id,"destination_id":c.destination_id,"items":c.items.duplicate(true),"actor_id":a.id,"phase":"collect","status":"collecting","repeat":false,"priority":c.player_priority,"created_at":float(host.context.clock.call()),"trips":0,"reason":"","zone_id":c.zone_id,"zone_revision":c.zone_revision})
		a.pending_delivery={"source_id":c.source_id,"destination_id":c.destination_id,"items":c.items.duplicate(true),"phase":"collect","task_id":id};a.intent={"schema_version":1,"owner":"actions","kind":"haul","id":id+":work","steps":path.steps,"step":0,"held":true,"logistics_task_id":id};a.activity="前往取货"
		Factory.sync_logistics(l);return tx.result()
	return Data.reject("CANDIDATE_UNAVAILABLE")
