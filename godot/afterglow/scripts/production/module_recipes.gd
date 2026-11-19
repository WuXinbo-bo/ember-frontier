extends RefCounted
## Explicit mechanism-v2 station adapter for the ORIGINAL craft order ledger.
## No second output, timer, material table or transaction owner.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Contact=preload("res://scripts/modules/module_contact.gd")
const PATH="res://data/modules/production_recipes_v2.json"
static func definitions()->Array:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value.get("production_recipes",[]) if value is Dictionary and value.get("version")==2 else []
static func configure_chapter_one(recipes:Dictionary)->void:
	# Rebalance only the save's locked content. The same recipe IDs keep the
	# existing workstations, animation, inventory and single craft authority.
	var changes:Dictionary={
		"r34:raw_boil_water_v2":{"name":"煮沸原水","inputs":{"r34:raw_water":2,"log":1},"seconds":12},
		"r34:cook_potato_v2":{"outputs":{"r34:meal_simple":3},"seconds":8},
		"r34:repair_axe_v2":{"name":"整备斧头","inputs":{"timber":1},"knowledge":[],"qualities":{},"seconds":6,"toolWear":0}
	}
	for id:String in changes:
		if recipes.has(id):recipes[id].merge(changes[id],true)
static func applies(recipe:Dictionary)->bool:return recipe.get("mechanism",{}).get("version")==2
static func module(host:RefCounted,id:String,tx:RefCounted=null)->Dictionary:
	var state:Variant=tx.extension("r34:modules",{"version":1,"instances":[],"projects":[],"source_receipts":{},"next_id":1}) if tx!=null else host.context.world.extension("r34:modules")
	if not state is Dictionary:return {}
	var direct:Dictionary=Draft.find(state.get("instances",[]),id)
	if not direct.is_empty():return direct
	# A physical workbench remains a real member of its owning module. Only
	# registered membership is an alias; callers cannot invent a station.
	for candidate:Dictionary in state.get("instances",[]):
		if candidate.get("members",[]).any(func(member:Dictionary)->bool:return member.get("id")==id):return candidate
	return {}
static func canonical_station(host:RefCounted,id:String,tx:RefCounted=null)->String:
	var owner:Dictionary=module(host,id,tx)
	return str(owner.get("id",id))
static func points(host:RefCounted,id:String,actor_id:String="player")->Array:
	var m:=module(host,id)
	if m.is_empty():return []
	var from:Dictionary=G.location(host.context.actor.call(actor_id))
	return Contact.points(host.context.spatial.current_space(),from,m)
static func problem(host:RefCounted,tx:RefCounted,a:Dictionary,o:Dictionary,r:Dictionary)->Variant:
	var m:=module(host,str(o.stationId),tx)
	if m.is_empty() or not m.get("discovered",false):return "实际功能建筑不存在或尚未发现"
	var d:=Catalog.definition_view(str(m.definition_id));var mechanism:Dictionary=d.get("mechanism",{})
	var module_state:Variant=tx.extensions.get("r34:modules",{})
	if module_state.get("projects",[]).any(func(p:Dictionary)->bool:return p.module_id==m.id and p.get("status") in ["active","blocked","paused"] and p.operation in ["upgrade","dismantle"]):return "建筑正在改造或拆卸"
	if m.status!="operational" or float(m.hp)<float(d.hp):return "建筑受损或尚未运行，请先维修"
	if mechanism.get("version")!=2 or not mechanism.get("recipes",[]).has(r.id):return "该级建筑没有此配方能力"
	var owner:Variant=m.get("owner")
	if owner!=null and owner not in [a.id,a.get("householdId"),"home-residents"]:return "没有建筑使用权限"
	if owner=="home-residents" and a.id!="player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false)):return "居民未同意使用公共工位"
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(m.region)):return "建筑所在区域尚未详细驻留"
	var q:RefCounted=host.context.spatial.current_space();var at:=G.location(a);var standing:Dictionary=q.standing_point(at)
	if standing.is_empty() or G.point(at).distance_to(G.point(standing))>.08:return "作业站位缺少身体净空或支撑"
	return null if Contact.near(q,at,m) else "需要靠近同层建筑并保持接触线畅通"
static func work_projection(host:RefCounted,a:Dictionary,o:Dictionary,r:Dictionary,problem_value:Variant)->Dictionary:
	var m:=module(host,str(o.stationId))
	if m.is_empty():return {}
	var d:=Catalog.definition_view(str(m.definition_id));var at:Dictionary={}
	for port:Dictionary in Shape.ports(m,d):
		if port.purpose in ["work","service","repair"]:at=port.location;break
	if at.is_empty():return {}
	var p:Vector3=G.point(at)+G.rotate(Vector3(0,.82,.45),int(m.quarter_turn))
	var tool_id:String=""
	for id:Variant in o.toolIds:
		var tool:=Draft.find(host.state().tools,str(id))
		if tool.get("holderId")=="pack:"+str(a.id):tool_id=str(id);break
	return {"owner":"actions","work_domain":"production","kind":"craft","operation":r.mechanism.operation,"tool_id":tool_id,"progress_seconds":o.elapsed,"duration_seconds":o.duration,"effective_work":problem_value==null and o.status=="active" and float(o.get("effective_work",0))>0,"effective_seconds":o.get("effective_work",0),"paused_reason":str(problem_value) if problem_value!=null else "","contact":{"position":[p.x,p.y,p.z],"normal":[0,1,0]}}
