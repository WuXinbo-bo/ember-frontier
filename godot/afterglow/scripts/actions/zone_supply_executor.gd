extends RefCounted
## Offers do not move goods. This adapter runs original route, holds and transfer.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const ModuleContact=preload("res://scripts/modules/module_contact.gd")
const ModuleRecipes=preload("res://scripts/production/module_recipes.gd")

static func valid(host:RefCounted,intent:Dictionary)->bool:
	var offer:Variant=intent.get("supply")
	if not offer is Dictionary or not str(offer.get("id","")).begins_with("zone-supply:") or not host.valid_id(offer.get("zone_id")) or not host.valid_number(offer.get("zone_revision")) or not host.valid_id(offer.get("source_id")) or not offer.get("items") is Dictionary or not offer.get("tool_ids") is Array:return false
	if offer.tool_ids.size()!=Draft.unique(offer.tool_ids).size() or not offer.tool_ids.all(host.valid_id):return false
	for item:Variant in offer.items:
		if not item is String or not Content.quantity_valid(item,offer.items[item]) or float(offer.items[item])<=0:return false
	return not offer.items.is_empty() or not offer.tool_ids.is_empty()

static func stock_path(host:RefCounted,tx:RefCounted,a:Dictionary,stock:Dictionary,operation:String="stock")->Dictionary:
	if stock.is_empty():return Data.reject("STOCK_MISSING")
	var at:=G.location(stock);var query:RefCounted=host.building.current_space();var points:Array=[]
	if stock.has("module_id"):
		if host.production.reach(str(a.id),str(stock.id),stock,operation,tx)==null:return {"ok":true,"steps":[]}
		var module:Dictionary=ModuleRecipes.module(host.production,str(stock.module_id),tx)
		if module.is_empty():return Data.reject("STOCK_MISSING")
		points.append_array(ModuleContact.points(query,G.location(a),module))
	var piece:Dictionary=query.by_id.get(str(stock.get("structureId",stock.id)),{})
	if not piece.is_empty():points.append_array(query.use_points(piece))
	var entity:Dictionary=host.context.world.entity(str(stock.id))
	if not entity.is_empty():
		var box:=G.aabb(entity.bounds);var center:=box.get_center()
		for direction:Vector3 in [Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT]:
			var p:Vector3=center+direction*(Vector3(box.size.x,0,box.size.z).dot(direction.abs())*.5+float(query.agent.radius)+.05);p.y=at.y
			var hint:=at.duplicate(true);hint.merge(G.json_point(p),true);points.append(hint)
	points.append(at)
	points.sort_custom(func(left:Dictionary,right:Dictionary)->bool:return G.point(left).distance_squared_to(G.point(G.location(a)))<G.point(right).distance_squared_to(G.point(G.location(a))))
	for hint:Dictionary in points:
		var feet:Dictionary=query.standing_point(hint)
		if feet.is_empty():continue
		var probe:=Draft.new();probe.context=tx.context;probe.staged=tx.staged.duplicate();probe.staged.actors=tx.staged.actors.duplicate();probe.extensions=tx.extensions.duplicate()
		var actor:Dictionary=a.duplicate(true);host.set_location(actor,feet)
		for i:int in probe.staged.actors.size():
			if probe.staged.actors[i].id==a.id:probe.staged.actors[i]=actor;break
		if host.production.reach(str(a.id),str(stock.id),stock,operation,probe)!=null:continue
		var path:Dictionary=host.route(str(a.id),G.location(a),feet)
		if path.ok:return path
	return Data.reject("UNREACHABLE","容器附近没有安全可达的位置")

static func prepare(host:RefCounted,tx:RefCounted,a:Dictionary,id:String,work_id:String)->Dictionary:
	if a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
	var zones:Variant=host.zone_work_service()
	if zones==null:return Data.reject("UNAVAILABLE")
	var offer:Dictionary=zones.supply_candidate(tx,a,id)
	if offer.is_empty():return Data.reject("CANDIDATE_UNAVAILABLE")
	if not offer.valid:return Data.reject("CANDIDATE_BLOCKED",str(offer.reason))
	if not host.valid_id(work_id):return Data.reject("INVALID_CANDIDATE")
	var path:=stock_path(host,tx,a,tx.stock(str(offer.source_id)))
	if not path.ok:return path
	a.intent={"schema_version":1,"owner":"actions","kind":"zone_supply","id":work_id,"steps":path.steps,"step":0,"held":true,"supply":offer.duplicate(true)}
	a.activity="前往实际取区域作业工具与材料";return tx.result()

static func problem(host:RefCounted,tx:RefCounted,a:Dictionary)->String:
	var intent:Dictionary=a.intent;var offer:Dictionary=intent.supply
	var state:Variant=tx.extensions["r34:zones"] if tx.extensions.has("r34:zones") else host.context.world.extension("r34:zones")
	var zone:=Draft.find(state.get("zones",[]) if state is Dictionary else [],str(offer.zone_id))
	if zone.is_empty() or not zone.enabled or zone.revision!=offer.zone_revision:return "工作区已取消或改变"
	if not zone.policy.get("worker_ids",[]).is_empty() and not zone.policy.worker_ids.has(a.id):return "工作区不再授权此角色"
	var stock:Dictionary=tx.stock(str(offer.source_id))
	if stock.is_empty() or not stock.get("searched",true) or not Factory.permitted(a,stock.get("owner")):return "来源不存在、未搜索或已撤权"
	for item:String in offer.items:
		if host.production.available_for(str(stock.id),item,"work",str(intent.id),tx)+.000001<float(offer.items[item]):return "实际取料来源已不足或被预留"
	var p:Dictionary=tx.extension(host.production.KEY,host.production.empty_state())
	for id:String in offer.tool_ids:
		var tool:=Draft.find(p.tools,id)
		if tool.is_empty() or tool.holderId!=stock.id or float(tool.durability)<=0 or host.production.tool_unavailable(id,str(intent.id),tx):return "实际工具已改变、损坏或占用"
	var cap:Dictionary=host.production.capacity_check("pack:"+str(a.id),offer.items,str(intent.id),tx)
	return "" if cap.ok else str(cap.get("reason",cap.code))

static func arrive(host:RefCounted,tx:RefCounted,a:Dictionary)->void:
	var intent:Dictionary=a.intent;var saved:Dictionary=intent.supply;var zones:Variant=host.zone_work_service()
	var offer:Dictionary=zones.supply_candidate(tx,a,str(saved.id),str(intent.id)) if zones!=null else {}
	if offer.is_empty() or not offer.valid or not Data.json_equal(offer.items,saved.items) or not Data.json_equal(offer.tool_ids,saved.tool_ids):a.intent=null;a.activity="作业需求已改变，请重新调度取料";return
	var result:Dictionary=host.transfer_in(tx,str(a.id),str(saved.source_id),"pack:"+str(a.id),{"items":saved.items,"tool_ids":saved.tool_ids},str(intent.id))
	a.intent=null;a.activity="已实际取到作业物资" if result.ok else str(result.get("reason",result.code))
	if result.ok:tx.events.append({"kind":"zone-supply-completed","actor_id":a.id,"candidate_id":saved.id,"zone_id":saved.zone_id,"source_id":saved.source_id,"items":saved.items.duplicate(true),"tool_ids":saved.tool_ids.duplicate()})
