extends RefCounted
## On-demand single-module guidance. It creates no order, reservation, search,
## inventory or authority; the existing walk command proves the route again.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Contact=preload("res://scripts/modules/module_contact.gd")
const LABELS={"input":"原料入口","output":"成品出口","tools":"工具与书籍","supplies":"生活物资","storage":"仓储服务面","fuel":"燃料入口"}

static func describe(host:RefCounted,actor_id:String,module_id:String)->Dictionary:
	var tx:=Draft.new(host.context);var actor:Dictionary=tx.actor(actor_id)
	var module:Dictionary=host.instance(module_id)
	var result:Dictionary={"available":false,"reason":"未发现设施或没有使用许可","module_id":module_id,"approaches":[]}
	if module.is_empty() or not module.get("discovered",false) or not host.permitted(actor,module.get("owner")):return result
	if float(actor.get("hp",0))<=0 or (actor_id!="player" and (not actor.get("relationship",{}).get("member",false) or not actor.get("relationship",{}).get("consent",false))):
		result.reason="角色无法执行现场行动";return result
	if module.status not in ["operational","damaged"]:result.reason="设施尚未可用";return result
	var production:Variant=host._production.get_ref() if host._production!=null else null
	var actions:Variant=host._actions.get_ref() if host._actions!=null else null
	if production==null or actions==null:result.reason="真实行动服务尚未接入";return result
	var detailed:bool=host.context.region_is_detailed.call(str(module.region)) and host.context.region_is_detailed.call(str(actor.regionId)) if host.context.get("region_is_detailed") is Callable else host.context.world.region_is_resident(str(module.region)) and host.context.world.region_is_resident(str(actor.regionId))
	if not detailed:result.reason="目标地区尚未就绪";return result
	var definition:Dictionary=Catalog.definition_view(str(module.definition_id));var ports:Array=Shape.ports(module,definition)
	var query:RefCounted=host.context.spatial.current_space();var original:Dictionary=actor.duplicate(true)
	for buffer:Dictionary in definition.buffer_specs:
		var port:Dictionary=Draft.find(ports,str(buffer.port_id));var stock_id:String=str(module.stock_refs[buffer.id])
		var at_service:bool=production.reach(actor_id,stock_id,tx.stock(stock_id),"search",tx)==null
		var row:Dictionary={"id":buffer.id,"port_id":buffer.port_id,"stock_ref":stock_id,"label":LABELS.get(buffer.id,"物资服务面"),"direction_label":"","location":{},"at_service":at_service,"available":false,"reason":"服务面无可用路径"}
		if not port.is_empty():
			var normal:=G.point(port.normal)
			row.direction_label="东侧" if normal.x>0.5 else "西侧" if normal.x< -0.5 else "南侧" if normal.z>0.5 else "北侧"
		if actor.get("intent")!=null:row.reason="先结束或取消当前行动";result.approaches.append(row);continue
		var positions:=Contact.points(query,G.location(original),module)
		if definition.get("chapter_geometry",false):
			var hints:Array=[]
			for point:Dictionary in port.get("use_points",[]):
				var standing:Dictionary=query.standing_point(point)
				if not standing.is_empty() and Contact.near(query,standing,module):hints.append(standing)
			positions=hints+positions
		for feet:Dictionary in positions:
			actor.merge(feet,true)
			var reachable:bool=production.reach(actor_id,stock_id,tx.stock(stock_id),"search",tx)==null
			actor.merge(original,true)
			if not reachable:continue
			var route:Dictionary=actions.route(actor_id,G.location(actor),feet)
			if not route.ok:row.reason=str(route.get("reason",row.reason));continue
			row.location=feet.duplicate(true);row.available=true;row.reason=""
			row.command={"kind":"walk","target_id":"","payload":{},"destination":feet.duplicate(true)}
			break
		result.approaches.append(row)
	result.available=true;result.reason="";return result
