extends RefCounted
## C owns the stone cells, B terrain executes, A commits; E gates informed intent.
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Movement=preload("res://scripts/runtime/movement_policy.gd")
static func bad(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
static func generation_fields(context:Dictionary,region_id:String,fields:Array[String])->Dictionary:
	# C returns isolated selected fields. Older hosts keep the same complete
	# plan fallback; no source identity, discovery or update cadence changes.
	var key:String="generation:"+region_id
	if context.world.has_method("extension_fields"):return context.world.extension_fields(key,fields)
	var value:Variant=context.world.extension(key)
	return value if value is Dictionary else {}
static func sites(context:Dictionary,layout:Dictionary)->Array:
	var result:Array=[]
	var fields:Array[String]=["regional_sites"]
	for value:Variant in layout.get("regional_sites",[]):
		if not value is Dictionary or not site_valid(value):continue
		var plan:Dictionary=generation_fields(context,str(value.region_id),fields)
		for original:Variant in plan.get("regional_sites",[]):
			if original is Dictionary and Data.json_equal(original,value):result.append(value.duplicate(true));break
	return result
static func location(value:Variant)->bool:return value is Dictionary and Data.vec(value) and Data.valid_id(value.get("regionId"))
static func cells_valid(values:Variant,material:int=-1)->bool:
	if not values is Array or values.is_empty() or values.size()>4096:return false
	var seen:Dictionary={}
	for value:Variant in values:
		if not value is Dictionary or not [value.get("x"),value.get("y"),value.get("z")].all(Data.integer):return false
		var key:String=Data.key(Vector3i(value.x,value.y,value.z))
		if seen.has(key) or (material>=0 and value.get("material")!=material):return false
		seen[key]=true
	return true
static func site_valid(site:Dictionary)->bool:
	if not Data.valid_id(site.get("id")) or site.get("kind")!="stone-roadfall-v1" or site.get("generation_content_version")!=2 or not Data.valid_id(site.get("region_id")) or not location(site.get("survey_point")):return false
	if site.survey_point.regionId!=site.region_id or not cells_valid(site.get("obstacle_cells"),3):return false
	for cell:Dictionary in site.obstacle_cells:
		if cell.get("clear_material")!=0:return false
	var corridor:Variant=site.get("goal_corridor")
	if not corridor is Dictionary or not cells_valid(corridor.get("base_cells"),4) or not cells_valid(corridor.get("clear_cells")):return false
	if not location(corridor.get("approach_before")) or not location(corridor.get("approach_after")) or not (corridor.get("width_m") is int or corridor.get("width_m") is float) or not is_finite(float(corridor.width_m)) or float(corridor.width_m)<1:return false
	if not site.get("encounter_positions") is Array or site.encounter_positions.is_empty() or site.encounter_positions.size()>16:return false
	for point:Variant in site.encounter_positions:
		if not location(point):return false
	return true
static func validate_objectives(state:Dictionary)->Dictionary:
	var objectives:Variant=state.get("regional_objectives",{})
	if not objectives is Dictionary or objectives.size()>64:return bad("INVALID_REGIONAL_OBJECTIVE","地区目标状态无效")
	for id:Variant in objectives:
		var item:Variant=objectives[id]
		if not Data.valid_id(id) or not item is Dictionary or item.get("site_id")!=id or not item.get("surveyed") is bool or not item.get("risk_accepted") is bool or not item.get("corridor_clear") is bool:return bad("INVALID_REGIONAL_OBJECTIVE","地区勘察／承诺身份无效")
		if item.risk_accepted and not item.surveyed:return bad("INVALID_REGIONAL_OBJECTIVE","未勘察不能确认清障风险")
		if item.has("completed") and not item.completed is bool:return bad("INVALID_REGIONAL_OBJECTIVE","地区完成状态无效")
		if item.risk_accepted and (not (item.get("warning_seconds") is int or item.get("warning_seconds") is float) or not is_finite(float(item.warning_seconds)) or float(item.warning_seconds)<60 or float(item.warning_seconds)>3600):return bad("INVALID_REGIONAL_OBJECTIVE","地区预告缺少返程准备时长")
		for key:String in ["surveyed_at","started_at"]:
			if not (item.get(key) is int or item.get(key) is float) or not is_finite(float(item[key])) or float(item[key])<0:return bad("INVALID_REGIONAL_OBJECTIVE","地区目标时间无效")
	return {"ok":true}
static func find_site(context:Dictionary,layout:Dictionary,id:String)->Dictionary:
	for site:Dictionary in sites(context,layout):
		if site.id==id:return site
	return {}
static func permission(context:Dictionary,state:Dictionary,request:Dictionary)->Dictionary:
	if request.get("kind")!="terrain":return {"ok":true,"code":"OK","reason":null}
	var payload:Variant=request.get("payload",{})
	if not payload is Dictionary:return {"ok":true}
	var edit:Variant=payload.get("edit",payload)
	if not edit is Dictionary:return {"ok":true}
	for site:Dictionary in sites(context,state.get("layout",{})):
		var protected:Array=site.obstacle_cells.duplicate(true);protected.append_array(site.goal_corridor.base_cells);protected.append_array(site.goal_corridor.clear_cells)
		var touches:=false
		for cell:Dictionary in protected:
			for value:Variant in edit.get("cells",[]) if edit.get("cells",[]) is Array else []:
				if value is Dictionary and value.get("x")==cell.x and value.get("y")==cell.y and value.get("z")==cell.z:touches=true;break
			var area:Variant=edit.get("area",{})
			if edit.get("operation")=="level" and area is Dictionary and area.has_all(["minI","maxI","minK","maxK"]) and [area.minI,area.maxI,area.minK,area.maxK].all(Data.integer):
				if cell.x>=area.minI and cell.x<area.maxI and cell.z>=area.minK and cell.z<area.maxK:touches=true
			if touches:break
		if touches and not state.get("regional_objectives",{}).get(site.id,{}).get("risk_accepted",false):
			var result:Dictionary=bad("SITE_CONFIRMATION_REQUIRED","先在真实勘察点确认地形与预告风险，再开始清障")
			result.site_id=site.id
			return result
	return {"ok":true,"code":"OK","reason":null}
static func availability(context:Dictionary,state:Dictionary,request:Dictionary)->Dictionary:
	if request.get("kind") not in ["settlement.survey","settlement.begin_route_work"]:return bad("UNKNOWN_SETTLEMENT_COMMAND","未知地区行动")
	var payload:Variant=request.get("payload",{})
	if not payload is Dictionary or not Data.valid_id(payload.get("site_id")):return bad("INVALID_REGIONAL_SITE","需要真实地区地点身份")
	var site:Dictionary=find_site(context,state.get("layout",{}),str(payload.site_id))
	if site.is_empty():return bad("REGIONAL_EVENT_SITE_UNAVAILABLE","真实障碍／清障地点尚未装配")
	var actor:Dictionary=context.actor.call(str(request.get("actor_id","")))
	if actor.is_empty() or actor.id!="player" or float(actor.get("hp",0))<=0:return bad("ACTOR_UNAVAILABLE","地区风险须由玩家知情确认")
	if not context.region_is_detailed.call(str(site.region_id)) or not context.region_is_detailed.call(str(actor.regionId)):return bad("REGION_PAUSED","勘察地区未详细模拟")
	if actor.get("intent")!=null:return bad("BUSY","先结束当前行动再勘察或确认风险")
	if G.point(actor).distance_to(G.point(site.survey_point))>2.2 or not context.world.continuous_outdoor_segment(G.location(actor),site.survey_point,2.2,true).ok or not context.spatial.current_space().line_clear(G.location(actor),site.survey_point,""):return bad("OUT_OF_REACH","需要实际走到可看清塌石的勘察点")
	if request.kind=="settlement.begin_route_work":
		var objective:Dictionary=state.get("regional_objectives",{}).get(site.id,{})
		if not objective.get("surveyed",false) or payload.get("accept_risk")!=true:return bad("SITE_CONFIRMATION_REQUIRED","先完成实地勘察，并明确接受清障作业会招来当地威胁")
		if objective.get("risk_accepted",false):return bad("REGIONAL_EVENT_ALREADY_STARTED","同一地点已接受风险，不重复预告或生成")
		if state.get("defense",{}).get("status")!="dormant":return bad("REGIONAL_EVENT_ACTIVE","先处理当前地区事件")
	return {"ok":true,"site":site}
static func prepare(tx:RefCounted,state:Dictionary,request:Dictionary,actions:RefCounted)->Dictionary:
	var ready:Dictionary=availability(tx.context,state,request)
	if not ready.ok:return ready
	var site:Dictionary=ready.site;var now:float=tx.context.clock.call()
	if not state.has("regional_objectives"):state.regional_objectives={}
	var objective:Dictionary=state.regional_objectives.get(site.id,{"site_id":site.id,"surveyed":false,"risk_accepted":false,"corridor_clear":false,"surveyed_at":0.0,"started_at":0.0})
	if request.kind=="settlement.survey":
		objective.surveyed=true;objective.surveyed_at=now
		tx.events.append({"kind":"settlement-site-surveyed","actor_id":"player","site_id":site.id})
	else:
		var player:Dictionary=tx.actor("player");var home:Variant=state.get("layout",{}).get("home")
		if not location(home):return bad("RETURN_ROUTE_UNAVAILABLE","缺少真实据点返程点，不能暗中锁预告时间")
		var route:Dictionary=actions.route("player",G.location(player),home)
		if not route.ok:return bad("RETURN_ROUTE_UNAVAILABLE","无法证明当前返程准备路线："+str(route.get("reason","")))
		var defense_position:Variant=site.get("warning_points",{}).get("approach_after")
		if not location(defense_position):return bad("DEFENSE_ROUTE_UNAVAILABLE","缺少真实可作战警戒点，不能以回到勘察点代替防守准备")
		var deployment:Dictionary=actions.route("player",home,defense_position)
		if not deployment.ok:return bad("DEFENSE_ROUTE_UNAVAILABLE","无法证明准备后到真实防守点的通路："+str(deployment.get("reason","")))
		var returning:Dictionary=route_time(route,G.location(player));var outward:Dictionary=route_time(deployment,home)
		var basis:Dictionary={"route_distance_m":returning.distance_m,"return_seconds":returning.seconds,"defense_position":defense_position.duplicate(true),"defense_route_distance_m":outward.distance_m,"defense_route_seconds":outward.seconds,"interruption_seconds":1.0,"preparation_seconds":35.0,"preparation_components":{"food_water_seconds":2.6,"rest_seconds":12.0,"necessary_action_seconds":10.0,"local_operations_margin":10.4},"margin":1.25,"status":"initial_tuning_pending_normal_route_acceptance"}
		var warning:float=maxf(60.0,ceilf((float(basis.return_seconds)+float(basis.defense_route_seconds)+float(basis.interruption_seconds)+float(basis.preparation_seconds))*float(basis.margin)))
		objective.risk_accepted=true;objective.started_at=now;objective.warning_seconds=warning;objective.warning_basis=basis
		tx.events.append({"kind":"settlement-route-work-started","actor_id":"player","site_id":site.id,"warning_seconds":warning})
	state.regional_objectives[site.id]=objective
	return {"ok":true}
static func route_time(route:Dictionary,origin:Dictionary)->Dictionary:
	var distance:float=0;var cursor:Vector3=G.point(origin);var doors:float=0
	for step:Dictionary in route.get("steps",[]):
		if step.get("kind")=="open-door":doors+=2.5
		elif location(step.get("to")):distance+=cursor.distance_to(G.point(step.to));cursor=G.point(step.to)
	return {"distance_m":distance,"seconds":distance/Movement.WALK_SPEED+doors}
static func corridor_clear(context:Dictionary,site:Dictionary)->bool:
	if not context.region_is_detailed.call(str(site.region_id)):return false
	for cell:Dictionary in site.goal_corridor.base_cells:
		if not context.world.is_cell_known(cell.x,cell.y,cell.z) or context.world.cell_at(cell.x,cell.y,cell.z)!=int(cell.material):return false
	for cell:Dictionary in site.goal_corridor.clear_cells:
		if not context.world.is_cell_known(cell.x,cell.y,cell.z) or context.world.cell_at(cell.x,cell.y,cell.z)!=0:return false
	var query:RefCounted=context.spatial.current_space()
	var before:Dictionary=query.standing_point(site.goal_corridor.approach_before)
	var after:Dictionary=query.standing_point(site.goal_corridor.approach_after)
	return not before.is_empty() and not after.is_empty() and query.route("player",before,after).ok
