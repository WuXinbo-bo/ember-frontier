extends RefCounted
## S02 uses the original study order, holds, knowledge and clock.
const G=preload("res://scripts/buildings/building_geometry.gd")
const TEACHER="repair-resident"
const KNOWLEDGE="basic_tool_repair"
static func valid_order(o:Dictionary)->bool:
	var source:Variant=o.get("learning_source","book")
	if source=="book":return not o.has("teacher_id") and not o.has("knowledge_id")
	return source=="teacher" and o.get("kind")=="study" and o.get("actorId")=="player" and o.get("targetId")==TEACHER and o.get("teacher_id")==TEACHER and o.get("knowledge_id")==KNOWLEDGE and o.get("duration")==12 and o.get("toolIds")==[] and o.get("sourceId")==null and o.get("outputId")==null and o.get("stationId")==null and o.get("repairToolId")==null
static func problem(host:RefCounted,tx:RefCounted,o:Dictionary)->Variant:
	if not valid_order(o):return "教学来源无效"
	var a:Dictionary=tx.actor(str(o.actorId));var teacher:Dictionary=tx.actor(TEACHER)
	if a.get("id")!="player" or float(a.get("hp",0))<=0 or teacher.is_empty() or float(teacher.get("hp",0))<=0:return "教学双方须能正常交流"
	if not teacher.get("relationship",{}).get("met",false) or not teacher.get("relationship",{}).get("helped",false):return "先认识并实际帮助这位居民"
	if teacher.get("intent")!=null:return "居民正在行动，暂时不能教学"
	if host.context.get("region_is_detailed") is Callable:
		for region:String in [str(a.regionId),str(teacher.regionId)]:
			if not host.context.region_is_detailed.call(region):return "教学地点尚未详细驻留"
	if a.regionId!=teacher.regionId or absf(float(a.y)-float(teacher.y))>.55:return "需要与居民在同层现场交流"
	var q:RefCounted=host.context.spatial.current_space()
	if q.standing_point(G.location(a)).is_empty() or q.standing_point(G.location(teacher)).is_empty():return "教学站位失去支撑或净空"
	if G.point(G.location(a)).distance_to(G.point(G.location(teacher)))>2.25 or not q.contact_clear(G.location(a),G.location(teacher),TEACHER):return "需要靠近居民且交流线无遮挡"
	return null
static func work_points(host:RefCounted,request:Dictionary)->Array:
	if request.get("actor_id")!="player" or request.get("target_id")!=TEACHER or request.get("payload",{}).get("knowledge_id")!=KNOWLEDGE:return []
	var teacher:Dictionary=host.context.actor.call(TEACHER)
	if teacher.is_empty() or not teacher.get("relationship",{}).get("met",false):return []
	var q:RefCounted=host.context.spatial.current_space();var points:Array=[]
	for i:int in 12:
		var at:Dictionary=G.location(teacher);var angle:float=TAU*i/12
		at.x+=cos(angle)*1.2;at.z+=sin(angle)*1.2
		var supported:Dictionary=q.standing_point(at)
		if not supported.is_empty() and q.contact_clear(supported,G.location(teacher),TEACHER):points.append(supported)
	return points
static func projection(host:RefCounted,actor_id:String,teacher_id:String)->Dictionary:
	if actor_id!="player":return {"available":false,"offers":[]}
	var a:Dictionary=host.context.actor.call(actor_id);var teacher:Dictionary=host.context.actor.call(TEACHER)
	if a.is_empty() or float(a.get("hp",0))<=0 or (not teacher_id.is_empty() and teacher_id!=TEACHER):return {"available":false,"offers":[]}
	if teacher.is_empty() or not teacher.get("relationship",{}).get("met",false):return {"available":true,"offers":[]}
	var request:Dictionary={"kind":"study","actor_id":"player","target_id":TEACHER,"payload":{"learning_source":"teacher","knowledge_id":KNOWLEDGE}}
	var ready:Dictionary=host.prepare(request);var known:bool=host.state().knowledge.get(actor_id,[]).has(KNOWLEDGE)
	return {"available":true,"offers":[{"teacher_id":TEACHER,"knowledge_id":KNOWLEDGE,"name":"学习基础工具维修","seconds":12,"known":known,"can_start":ready.ok,"code":ready.get("code","OK"),"reason":ready.get("reason",""),"command":request}]}
