extends RefCounted

const PREFIX="r38.module."
const HOME=PREFIX+"home"
const WORKSHOP=PREFIX+"workshop"
const WAREHOUSE=PREFIX+"warehouse"
const CHOICES=[PREFIX+"stockyard",WAREHOUSE,PREFIX+"cottage",PREFIX+"water",PREFIX+"kitchen",PREFIX+"artisan",PREFIX+"sawmill",PREFIX+"repair",PREFIX+"guard",PREFIX+"supply"]

static func id_for(kind:String,level:int)->String:
	return PREFIX+kind+(".lv%d"%level if level>1 else "")

static func derive(rows:Array)->Array:
	var sources:Dictionary={}
	for row:Dictionary in rows:sources[row.id]=row
	var result:Array=[]
	for spec:Array in specs():
		var kind:String=spec[0];var names:Array=spec[1];var roles:Array=spec[2];var ids:Array=spec[3]
		var base:Dictionary=sources[ids[0]]
		for i:int in names.size():
			var level:int=i+1
			var d:Dictionary=sources[ids[i]].duplicate(true)
			for key:String in ["architecture","geometry_source_id","design_id","village_geometry","story_front_point"]:d.erase(key)
			for key:String in ["footprint","foundation","ports","allowed_quarter_turns"]:d[key]=base[key].duplicate(true)
			if kind in ["repair","guard","supply"]:_resize(d,1.5,1.5,3.3)
			if kind=="sawmill":
				for p:Dictionary in d.ports:
					if p.id in ["log-input","board-output"]:
						p.position[2]=-.95;p.use_points=[p.position.duplicate()]
			d.id=id_for(kind,level);d.geometry_version=d.id+".geometry-v1";d.design_id=d.id
			d.name=names[i];d.village_role=roles[i];d.village_tier=level
			d.village_stage_required=maxi(level,2 if kind in ["sawmill","repair","guard","supply"] else 1)
			d.village_family_art=kind;d.geometry_family_version=4;d.visual_family="old-village"
			d.dimensions_status="village-families-v18"
			if kind!="home":d.compact_kind=kind
			d.village_geometry={"version":1,"kind":"village_sawmill" if kind=="sawmill" else kind}
			if not d.has("mechanism"):d.mechanism={"version":2,"family":"warehouse","recipes":[]}
			d.mechanism.tier=level
			d.mechanism.upgrade_to=[id_for(kind,level+1)] if level<names.size() else []
			if i>0:d.erase("village_restoration")
			if kind=="home":d.mechanism.beds=3+i;d.opening_only=true
			if kind=="cottage":d.mechanism.beds=2+i
			if kind=="workshop":d.opening_only=true
			if kind=="guard":d.hp=float(base.hp)+80*i
			if kind in ["repair","artisan"]:d.bench_offset=[0,0,-.60]
			if i>0:
				var preceding:Dictionary=result.back()
				for item:String in preceding.build_cost:d.build_cost[item]=maxf(float(d.build_cost.get(item,0)),float(preceding.build_cost[item]))
				d.build_cost.scrap=float(d.build_cost.get("scrap",0))+3
				d.build_seconds=maxf(float(d.build_seconds),float(base.build_seconds)+8*i)
				if kind in ["home","cottage","warehouse","stockyard","sawmill","supply"]:_capacity_step(d,base,i)
			result.append(d)
	return result

static func _resize(d:Dictionary,x:float,z:float,height:float)->void:
	d.footprint={"min":{"x":-x,"y":0,"z":-z},"max":{"x":x,"y":height,"z":z}}
	d.foundation={"top_offset":0,"pad_rectangles":[[-x-.5,-z-.5,x+.5,z+.5]],"max_slope":0}
	for p:Dictionary in d.ports:
		var n:Array=p.normal;var old:Array=p.position
		var use:Array=[n[0]*(x+.9) if n[0]!=0 else clampf(old[0],-x+.5,x-.5),0,n[2]*(z+.9) if n[2]!=0 else clampf(old[2],-z+.5,z-.5)]
		p.position=use;p.use_points=[use.duplicate()]

static func _capacity_step(d:Dictionary,base:Dictionary,step:int)->void:
	for b:Dictionary in d.buffer_specs:
		for original:Dictionary in base.buffer_specs:
			if original.id!=b.id:continue
			for item:String in original.limits:
				var first:float=float(original.limits[item])
				b.limits[item]=maxf(float(b.limits.get(item,0)),ceilf(first*(1.0+.5*step))) if first>1 else maxf(float(b.limits.get(item,0)),first)

static func _civic(family:String)->Array:
	return ["r34.module.%s_low_v1.mechanism-v2"%family,"r34.module.%s_mid_v1.mechanism-v2"%family,"r34.module.%s_high_v1.mechanism-v2"%family]

static func specs()->Array:
	return [
		["home",["旧宅","翻修旧宅","村舍主院"],["三处实际床位","增设第4处床位","增设第5处床位"],["r35.module.village_home","r35.module.village_home_expanded","r35.module.village_home_expanded"]],
		["cottage",["小宿屋","双铺宿屋","工人宿舍"],["两处实际床位","增设第3处床位","增设第4处床位"],["r37.module.cottage","r37.module.cottage","r37.module.cottage"]],
		["workshop",["手工作坊"],["手锯板材与电台维修"],["r37.module.workshop"]],
		["warehouse",["仓棚","分区仓棚","周转仓"],["存放建材和生活物资","增加库位，按物品设置库存保留","增加储备，配合跨区运输"],["r37.module.warehouse","r37.module.warehouse_upgrade","r37.module.warehouse_upgrade"]],
		["stockyard",["堆料场","分类堆料场","集料场"],["原木、板材及废料的近机缓冲","扩大附近生产的缓冲库位","加大原料集中缓冲"],["r37.module.stockyard","r37.module.stockyard","r37.module.stockyard"]],
		["sawmill",["锯木站","滚床锯木站","连续供料锯木站"],["燃料驱动，把原木加工成板材","增大进出料缓冲，降低缺料停机","扩大供料与成品缓冲"],["r37.module.sawmill","r37.module.sawmill","r37.module.sawmill"]],
		["water",["净水站","双滤净水站","供水站"],["原水过滤和煮沸","增加处理缓存","增加供水缓存与可用工艺"],["r37.module.water","r34.module.water_mid_v1.mechanism-v2","r34.module.water_high_v1.mechanism-v2"]],
		["kitchen",["厨房","村食堂","口粮工坊"],["薯类烹调","新增豆类和稻米加工","烹制炖菜与干粮"],["r37.module.kitchen","r34.module.canteen_mid_v1.mechanism-v2","r34.module.canteen_high_v1.mechanism-v2"]],
		["artisan",["工具作坊","木工坊","工具工坊"],["制作工具柄、撑件和水桶","增加结构木料加工","制作金属件和组装斧头"],["r37.module.artisan","r34.module.artisan_mid_v1.mechanism-v2","r34.module.artisan_high_v1.mechanism-v2"]],
		["repair",["维修棚","维修站","维修工场"],["维护现有工具","支持更多维修工作和器材库存","扩大维修储备和可用工艺"],_civic("repair")],
		["guard",["警戒岗","加固警戒岗","联防岗"],["同伴可在实际站位值守","加固结构并扩大补给容量","提高结构耐久与备用补给容量"],_civic("guard")],
		["supply",["交接棚","路线交接站","乡道货站"],["本地交接生活与建筑物资","增加路线交接缓存","增加乡道物资中转库存"],["r34.module.supply_roadside_v2","r34.module.supply_roadside_v2","r34.module.supply_roadside_v2"]]
	]
