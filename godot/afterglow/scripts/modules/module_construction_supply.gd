extends RefCounted
## Stock access, movement, and transfer stay with the action authority.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const StockPath=preload("res://scripts/actions/zone_supply_executor.gd")
const RestoreAction=preload("res://scripts/modules/module_restoration_action.gd")

static func prepare(host:RefCounted,tx:RefCounted,actor:Dictionary,module:Dictionary,cost:Dictionary,command_id:String,project_id:String)->Dictionary:
	var ready:=RestoreAction.resolve(host,tx,actor,module,{},project_id,cost)
	if ready.ok:return ready
	if str(ready.code) not in ["MODULE_MATERIALS","MODULE_TOOL_REQUIRED"]:return ready
	var actions:Variant=host._actions.get_ref() if host._actions!=null else null
	var production:Variant=host._production.get_ref() if host._production!=null else null
	if actions==null or production==null or actor.get("intent")!=null:return ready
	var pack_id:String="pack:"+str(actor.id)
	var missing:Dictionary={}
	for row:Dictionary in ready.materials:
		if float(row.missing)>.000001:missing[str(row.item_id)]=float(row.missing)
	var need_hammer:bool=not ready.tool.get("available",false)
	var state:Dictionary=host.state(tx.extensions)
	var stocks:Array=[]
	var from:=Geometry.point(Geometry.location(actor))
	for stock:Dictionary in tx.staged.stocks:
		if not _can_source(host,stock,actor,state):continue
		stocks.append(stock)
	stocks.sort_custom(func(left:Dictionary,right:Dictionary)->bool:
		var dl:=from.distance_squared_to(Geometry.point(Geometry.location(left)))
		var dr:=from.distance_squared_to(Geometry.point(Geometry.location(right)))
		return str(left.id)<str(right.id) if dl==dr else dl<dr)
	var tools:Dictionary={}
	if need_hammer:
		for tool:Dictionary in tx.extension(production.KEY,production.empty_state()).tools:
			if float(tool.get("durability",0))>0.0 and float(production.tool_qualities(tool).get("hammering",0))>=1.0 and not production.tool_unavailable(str(tool.id),project_id,tx):
				if not tools.has(tool.holderId) or str(tool.id)<str(tools[tool.holderId]):tools[tool.holderId]=tool.id
	var failure:Dictionary={}
	for stock:Dictionary in stocks:
		var id:=str(stock.id)
		var items:Dictionary={}
		for item:String in missing:
			var step:=Content.quantity_step(item)
			if step<=0.0:continue
			var amount:=floorf((minf(float(missing[item]),float(production.available_for(id,item,"work","",tx)))+.0000001)/step)*step
			if amount>0.0:items[item]=amount
		var tool_ids:Array=[tools[id]] if tools.has(id) else []
		if items.is_empty() and tool_ids.is_empty():continue
		var capacity:Dictionary=production.capacity_check(pack_id,items,"",tx)
		if not capacity.ok:
			failure=RestoreAction.deny(str(capacity.code),"施工材料装不下，请腾出随身空间",ready.materials,ready.tool)
			if tool_ids.is_empty():continue
			items.clear()
		if production.reach(str(actor.id),id,stock,"stock",tx)==null:
			var transfer:Dictionary=actions.transfer_in(tx,str(actor.id),id,pack_id,{"items":items,"tool_ids":tool_ids})
			if not transfer.ok:return transfer
			actor.activity="已取到施工工具或材料"
			tx.events.append({"kind":"module-supplies-collected","module_id":module.id,"actor_id":actor.id,"source_id":id,"items":items,"tool_ids":tool_ids})
			var result:Dictionary=tx.result();result.preparing=true;return result
		var route:=StockPath.stock_path(actions,tx,actor,stock)
		if not route.ok or route.steps.is_empty():
			failure=RestoreAction.deny("MODULE_SUPPLY_UNREACHABLE","施工材料或锤子所在的存放点无法到达",ready.materials,ready.tool)
			continue
		var destination:Dictionary=route.steps[-1].get("to",{})
		if destination.is_empty():continue
		var request:Dictionary={"kind":"walk","actor_id":actor.id,"target_id":"","command_id":command_id,"destination":destination,"payload":{}}
		actor.intent={"schema_version":1,"owner":"actions","id":command_id,"kind":"walk","steps":route.steps,"step":0,"request":request,"held":true}
		actor.activity="前往存放点领取施工材料或锤子"
		var result:Dictionary=tx.result();result.preparing=true;return result
	return failure if not failure.is_empty() else ready

static func _can_source(host:RefCounted,stock:Dictionary,actor:Dictionary,state:Dictionary)->bool:
	if str(stock.id).begins_with("pack:") or not stock.get("searched",true) or not host.permitted(actor,stock.get("owner")):return false
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(Geometry.location(stock).get("regionId",""))):return false
	if not stock.has("module_id"):return true
	var module:=Draft.find(state.instances,str(stock.module_id))
	return module.get("discovered",false) and module.get("status") in ["operational","damaged"] and module.stock_refs.values().has(stock.id) and host.permitted(actor,module.owner)
