extends RefCounted
## One request, existing reservations, original navigation and paid labor.
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Contact=preload("res://scripts/modules/module_contact.gd")

static func deny(code:String,reason:String,materials:Array=[],tool:Dictionary={})->Dictionary:
	var result:=Data.reject(code,reason)
	result.materials=materials;result.tool=tool;result.auto_approach=true
	return result

static func resolve(host:RefCounted,tx:RefCounted,a:Dictionary,v:Dictionary,payload:Dictionary,project_id:String="",required_cost:Variant=null)->Dictionary:
	var prod:Variant=host._production.get_ref() if host._production!=null else null
	if prod==null:return deny("PRODUCTION_UNAVAILABLE","实际生产服务尚未就绪")
	var source_id:String=str(payload.get("source_id","pack:"+str(a.id)))
	var source:Dictionary=tx.stock(source_id)
	if source.is_empty() or not source.get("searched",true) or not host.permitted(a,source.get("owner")):return deny("MODULE_SOURCE_PERMISSION","材料来源未搜索或没有使用许可")
	var materials:Array=[];var missing:Array=[];var cost:Dictionary=required_cost if required_cost is Dictionary else Restoration.cost(v)
	for item:String in cost:
		var required:float=float(cost[item])
		var available:float=maxf(0,prod.available_for(source_id,item,"work",project_id,tx))
		var shortfall:float=maxf(0,required-available)
		materials.append({"item_id":item,"required":required,"available":available,"missing":shortfall})
		if shortfall>0.000001:missing.append("%s 缺 %s（需要 %s，可用 %s）"%[Content.item_definition(item).get("name",item),str(shortfall),str(required),str(available)])
	var tool_id:String=str(payload.get("tool_id",""))
	if payload.has("tool_ids"):
		if payload.has("tool_id") or not payload.tool_ids is Array or payload.tool_ids.size()!=1:return deny("MODULE_TOOL_REQUIRED","请选择一把可用的锤子",materials)
		tool_id=str(payload.tool_ids[0])
	var tools:Array=tx.extension(prod.KEY,prod.empty_state()).tools
	var selected:Dictionary={}
	if not tool_id.is_empty():selected=Draft.find(tools,tool_id)
	else:
		for candidate:Dictionary in tools:
			if candidate.holderId!="pack:"+str(a.id) or float(candidate.get("durability",0))<=0 or float(prod.tool_qualities(candidate).get("hammering",0))<1 or prod.tool_unavailable(str(candidate.id),project_id,tx):continue
			selected=candidate;break
	var tool:Dictionary={"name":"锤子","available":false,"id":str(selected.get("id",""))}
	if not selected.is_empty() and float(selected.get("durability",0))>0 and float(prod.tool_qualities(selected).get("hammering",0))>=1 and not prod.tool_unavailable(str(selected.id),project_id,tx):
		var holder:Dictionary=tx.stock(str(selected.get("holderId","")))
		tool.available=not holder.is_empty() and holder.get("searched",true) and host.permitted(a,holder.get("owner"))
	if not missing.is_empty():
		var failure:=deny("MODULE_MATERIALS","；".join(missing),materials,tool)
		failure.missing=materials.filter(func(row:Dictionary)->bool:return row.missing>0.000001)
		return failure
	if not tool.available:return deny("MODULE_TOOL_REQUIRED","需要一把随身携带、耐久充足且未被占用的锤子",materials,tool)
	var bound:Dictionary=payload.duplicate(true);bound.erase("tool_ids");bound.source_id=source_id;bound.tool_id=selected.id
	return {"ok":true,"code":"OK","reason":"","payload":bound,"materials":materials,"tool":tool,"auto_approach":true}

static func approach(host:RefCounted,tx:RefCounted,a:Dictionary,p:Dictionary,v:Dictionary,command_id:String)->Dictionary:
	var actions:Variant=host._actions.get_ref() if host._actions!=null else null
	var prod:Variant=host._production.get_ref() if host._production!=null else null
	if actions==null or prod==null:return deny("MODULE_ROUTE_UNAVAILABLE","实际移动服务尚未就绪")
	if host.context.get("region_is_detailed") is Callable and (not host.context.region_is_detailed.call(str(v.region)) or not host.context.region_is_detailed.call(str(a.regionId))):return deny("REGION_PAUSED","目标地区尚未加载完成，请稍后重试")
	# Hypothetical reach is checked only on a detached actor. Execution always
	# uses actions.route + move_step; no position is copied into the live actor.
	var probe:=Draft.new(host.context);probe.initial=tx.staged.duplicate(true);probe.staged=tx.staged.duplicate(true);probe.extensions=tx.extensions.duplicate(true)
	var pa:Dictionary=probe.actor(str(a.id));var query:RefCounted=host.context.spatial.current_space()
	var best:Dictionary={};var best_distance:float=INF
	var work_instance:Dictionary=v
	if p.operation=="upgrade":work_instance=v.duplicate(true);work_instance.definition_id=p.target_definition_id
	for feet:Dictionary in Contact.points(query,G.location(a),work_instance,Contact.DISTANCE,true):
		pa.merge(feet,true)
		if prod.reach(str(a.id),str(p.source_id),probe.stock(str(p.source_id)),"stock",probe)!=null:continue
		var tool:Dictionary=Draft.find(probe.extension(prod.KEY,prod.empty_state()).tools,str(p.tool_id))
		if tool.is_empty() or prod.reach(str(a.id),str(tool.holderId),probe.stock(str(tool.holderId)),"stock",probe)!=null:continue
		var distance:float=G.point(G.location(a)).distance_squared_to(G.point(feet))
		if distance>=best_distance:continue
		var route:Dictionary=actions.route(str(a.id),G.location(a),feet)
		if not route.get("ok",false):continue
		best_distance=distance;best={"steps":route.steps,"location":feet.duplicate(true),"port_id":"building-nearby"}
	if best.is_empty():return deny("MODULE_SERVICE_UNREACHABLE","建筑周边没有安全可达路线，或现场无法接触所选材料和锤子")
	p.auto_approach=true;p.status="active";p.paused_reason="";p.effective_work=0.0
	a.intent={"schema_version":1,"owner":"actions","kind":"module_approach","id":command_id,"project_id":p.id,"steps":best.steps,"step":0,"held":true,"workforce_candidate_id":"module-project:"+str(p.id)}
	a.activity="走近建筑"
	return {"ok":true,"code":"OK","destination":best.location,"port_id":best.port_id}

static func reason(code:String)->String:
	if code=="MODULE_REBUILD_STORAGE":return "残骸缓存的物资超出原建筑储位，请先转移多余物资"
	if code=="MODULE_RUIN_CHANGED":return "残骸已经改变，请重新选择建筑"
	if code=="awaiting_worker":return "蓝图已放置，等待安排施工者"
	if code=="paused":return "施工已暂停，材料与进度保留"
	if code=="operator_not_at_port":return "请靠近建筑后继续施工"
	return {"approaching":"正在走近建筑","actor_unavailable":"角色受伤失能，或未同意参加劳动","production_unavailable":"实际生产服务尚未就绪","region_paused":"目标地区尚未加载完成","missing_operator":"工人已离开，请继续或安排同伴接手","paused":"修复已暂停，材料与进度保留","safe_handoff":"工人已交回任务，材料与进度保留","operator_not_at_port":"请靠近建筑后继续修复","missing_input":"预留材料不足，请补足材料后继续","missing_tool":"锤子损坏、被占用或无法接触","stamina_or_tool":"体力不足或锤子耐久耗尽，休息或更换工具后继续","MODULE_LIVE_ACTOR_OCCUPIED":"有人站在建筑施工范围内，请先让开","MODULE_MATERIALS_CHANGED":"材料已经变化，请重新检查库存","permission":"没有使用许可"}.get(code,code)

static func construction(p:Dictionary,v:Dictionary,d:Dictionary,facts:Dictionary)->Dictionary:
	if p.is_empty():return {}
	var a:Dictionary=Draft.find(facts.get("actors",[]),str(p.actor_id));var intent:Variant=a.get("intent")
	var held:bool=intent is Dictionary and bool(intent.get("held",true))
	var approaching:bool=intent is Dictionary and intent.get("owner")=="actions" and intent.get("kind")=="module_approach" and intent.get("workforce_candidate_id")=="module-project:"+str(p.id)
	var paused_code:String=str(p.get("paused_reason",""))
	var phase:String="completed" if p.status=="completed" else "cancelled" if p.status=="cancelled" else "queued" if p.status=="queued" else "paused" if not held else "approaching" if approaching else "working" if p.status=="active" else "paused"
	return {"active":phase=="working" and float(p.get("effective_work",0))>0,"project_id":p.id,"operation":p.operation,"rebuild":p.has("rebuild_ruin_id"),"phase":phase,"actor_id":p.actor_id,"held":held,"progress_seconds":p.progress_seconds,"duration_seconds":p.duration_seconds,"anchor_id":"condition","paused_code":paused_code,"paused_reason":reason(paused_code),"footprint":G.json_box(Shape.transform_box(v,G.aabb(d.footprint)))}
