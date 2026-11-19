extends RefCounted
## One-time v5 activity adapter. B owns navigation/labor; keep existing orders,
## elapsed work, IDs and reservations. No tick, reward, FileAccess or commit here.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const LIFE=["eat","drink","medicine","rest","sleep"]
const WORK=["structure","craft","study","harvest"]
const DISPATCH=["take","deposit","talk"]
static func failure(actor_id:String,reason:String)->Dictionary:
	return {"ok":false,"code":"UNSUPPORTED_LEGACY_ACTIVITY","reason":"旧档角色 "+actor_id+"："+reason+"；原文件和当前存档保留"}
static func valid(old:Dictionary)->bool:
	return Data.valid_id(old.get("id")) and old.get("kind") is String and old.get("phase") in ["approaching","working"] and old.get("payload") is Dictionary and old.get("path") is Array and Data.vec(old.get("destination")) and Data.valid_id(old.destination.get("regionId")) and number(old.get("elapsed")) and number(old.get("duration")) and float(old.elapsed)>=0 and float(old.duration)>=0 and float(old.elapsed)<=float(old.duration)+0.000001
static func number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value))
static func request_for(a:Dictionary,old:Dictionary,runtime:RefCounted)->Dictionary:
	var payload:Dictionary=old.payload.duplicate(true)
	for source:String in ["sourceId","outputId","toolId","toolIds","recordId","recipeId","repairToolId"]:
		if payload.has(source):payload[source.to_snake_case()]=payload[source];payload.erase(source)
	if payload.has("requiresHeld"):payload.requires_hold=payload.requiresHeld;payload.erase("requiresHeld")
	# A held mouse is session input. Keep the order and its elapsed work paused.
	if a.id=="player" and payload.get("direct",false) and payload.get("requires_hold",false):payload.held=false
	var target:String=str(old.get("targetId","")) if old.get("targetId")!=null else ""
	if old.kind in ["take","deposit"] and not payload.has("items"):
		var stock:Dictionary=runtime.stock(target if old.kind=="take" else "pack:"+str(a.id))
		payload.items={}
		for item:String in stock.get("items",{}):
			if float(stock.items[item])>0:payload.items[item]=stock.items[item]
	return {"command_id":old.id,"actor_id":a.id,"kind":old.kind,"target_id":target,"payload":payload,"destination":old.destination.duplicate(true)}
static func life_intent(old:Dictionary)->Dictionary:
	return {"owner":"runtime","kind":old.kind,"id":old.id,"target_id":str(old.targetId) if old.get("targetId")!=null else "","elapsed":float(old.elapsed),"duration":float(old.duration),"legacy_v5":true,"legacy_destination":old.destination.duplicate(true)}
static func convert(capture:Dictionary,runtime:RefCounted,services:Dictionary)->Dictionary:
	var facts:Dictionary=capture.facts.duplicate(true)
	var report:Array=[]
	for a:Dictionary in facts.actors:
		var old:Variant=a.get("intent")
		if old==null:continue
		if not old is Dictionary or not valid(old):return failure(str(a.id),"活动意图格式无效")
		if old.has("owner"):return failure(str(a.id),"v5意图含未知运行时归属，不能猜测重放")
		if old.kind not in LIFE+WORK+DISPATCH+["move","cross","door","search"]:return failure(str(a.id),"尚未适配活动 "+str(old.kind))
		var request:Dictionary=request_for(a,old,runtime)
		if old.phase=="approaching" or old.kind in ["move","cross"]:
			var destination:Dictionary=old.destination.duplicate(true)
			# Old travel first walks to this region's exit, then changes the same
			# intent into cross. Keep that destination, rather than silently ending
			# a restored trip at the near side of the boundary.
			if old.kind=="move" and old.payload.has("nextRegion"):
				if not old.payload.nextRegion is String:return failure(str(a.id),"相邻地区标识无效")
				var destination_region:Dictionary=runtime.world.region(old.payload.nextRegion)
				var returning:Dictionary={}
				for exit:Dictionary in destination_region.get("exits",[]):
					if exit.get("toRegionId")==old.destination.regionId:returning=exit;break
				if returning.is_empty():return failure(str(a.id),"相邻地区没有已生成的真实返回连接")
				destination=Geometry.location(returning.position)
				destination.regionId=old.payload.nextRegion
				request.destination=destination.duplicate(true)
			var plan:Dictionary=services.actions.route(str(a.id),Geometry.location(a),destination)
			if not plan.ok:return failure(str(a.id),"不能从原站位重建真实通路："+str(plan.get("reason","")))
			a.intent={"owner":"actions","id":str(old.id)+":route","kind":"walk","steps":plan.steps,"step":0,"request":{"command_id":str(old.id)+":route","actor_id":a.id,"kind":"walk","destination":destination.duplicate(true),"payload":{}},"held":true}
			if old.kind not in ["move","cross"]:
				var remaining:Dictionary=old.duplicate(true);remaining.phase="working";remaining.elapsed=0.0
				a.migration_resume={"request":request,"legacy":remaining}
		elif old.kind in LIFE:
			a.intent=life_intent(old)
		elif old.kind in WORK:
			var key:String="r3:structure-orders" if old.kind=="structure" else "r3:production"
			var order_id:String=str(old.payload.get("orderId",""))
			var found:Dictionary={}
			for order:Dictionary in capture.world.extensions.get(key,{}).get("orders",[]):
				if order.get("id")==order_id:found=order;break
			if found.is_empty() or found.get("actorId")!=a.id or found.get("status") not in ["active","blocked"]:return failure(str(a.id),"原活动订单不存在、已结束或物主不匹配")
			a.intent={"owner":"actions","kind":old.kind,"id":old.id,"order_id":order_id,"request":request,"held":request.payload.get("held",true)}
			if a.id!="player":
				a.work_target_id=request.target_id
				a.work_payload=request.payload.duplicate(true)
		elif old.kind=="search":
			a.intent={"owner":"actions","kind":"search","target_id":request.target_id,"elapsed":float(old.elapsed),"held":true}
		elif old.kind=="door":
			var door:Dictionary=services.buildings.instance(request.target_id)
			if not door.has("door"):return failure(str(a.id),"实际门已经缺失")
			if not request.payload.has("operation"):request.payload.operation="close" if door.door.open else "open"
			a.intent={"owner":"actions","kind":"door","id":old.id,"request":request,"elapsed":float(old.elapsed),"duration":float(old.duration),"target_version":door.version,"held":true}
		else:
			# Preserve the remaining legacy interaction time before the normal
			# native command revalidates reach, ownership, materials and consent.
			a.intent={"owner":"runtime","kind":"legacy_dispatch","id":old.id,"elapsed":float(old.elapsed),"duration":float(old.duration),"resume":{"request":request,"legacy":old.duplicate(true)}}
		report.append({"actor_id":a.id,"intent_id":old.id,"kind":old.kind,"phase":old.phase,"original_elapsed":old.elapsed,"original_duration":old.duration,"route":"replanned by B, no teleport" if old.phase=="approaching" else "existing order/time retained"})
	return {"ok":true,"facts":facts,"activities":report}
