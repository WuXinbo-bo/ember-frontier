extends RefCounted
## Public definition cards only. No positions, undiscovered objects or outputs
## are created here; C's rules and B's actual execution remain authoritative.
const Rules=preload("res://scripts/ecology/ecology_rules.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Zones=preload("res://scripts/planning/zone_definitions.gd")

static func cards()->Array:
	var result:Array=[]
	result.append(_card("source:planning","区域规划与真实作业","拖框指定林业、种植、采集、堆放、清理、地形或巡逻范围。规划只表达安排；工具、材料、走路、劳动、取送与生长都按真实世界结算。取消保留已完成的工作与实际物资。",{"zone_kinds":Zones.KINDS.duplicate(true)},[]))
	for id:String in Rules.CROPS:
		var rule:Dictionary=Rules.CROPS[id]
		var name:String=str(Content.item_definition(rule.item).get("name",rule.item))
		var description:String="在种植区整地、播种和照料。条件满足时共需%s游戏秒生长；两个生长阶段各需%s份土壤水分，每次实际收获%s份%s。保留田内种子可续种，换种前先收回留种；缺水、缺肥或地面改变会等待，不按现实离线时间免费成熟。"%[rule.seconds,rule.water,rule.yield,name]
		if id=="rice":description+="水稻还需合适平田与田埂；收获的是稻谷，必须脱壳并熟制。"
		result.append(_card("source:crop:"+id,name+"种植",description,{"ecology_kind":"crop","species_id":id,"crop_rules":rule.duplicate(true)},[["item:"+str(rule.seed),"播种与田内留种","input"],["item:r34:raw_water","真实浇灌","input"],["item:r34:compost","田畦施肥","input"],["item:"+str(rule.item),"实际收获","output"],["item:r34:crop_residue","收获残余","output"]]))
	for id:String in Rules.TREES:
		var rule:Dictionary=Rules.TREES[id]
		var name:String="阔叶林" if id=="broadleaf" else "针叶林"
		var description:String="从真实成熟母树采种，消耗树种与原水育苗，再携苗到林区实际种植；幼苗和幼树阶段分别需%s、%s游戏秒，合适地面与间距仍须成立。成熟后沿同一采伐与搬运流程产木；锯木厂加工木料，不隔空长树或自动加快树龄。"%[rule.young_seconds,rule.mature_seconds]
		result.append(_card("source:tree:"+id,name+"补种",description,{"ecology_kind":"tree","species_id":id,"tree_rules":rule.duplicate(true)},[["item:"+str(rule.seed),"母树采种","output"],["item:"+str(rule.seed),"育苗投入","input"],["item:"+str(rule.seedling),"真实育苗","output"],["item:"+str(rule.seedling),"消耗苗木栽植","input"],["item:r34:raw_water","育苗用水","input"],["item:log","成熟采伐","output"]]))
	result.append(_card("source:raw_water","原水、处理与饮水","在已发现且可达的实际水源旁，用可重复使用的桶取原水。补给上限与速率来自该水源；旧有限水源不会自动回满。原水与仅过滤的水都不能直接饮用，须经具能力水设施的真实配方处理，再把安全水运入生活库存。",{"ecology_kind":"raw_water"},[["item:r34:water_bucket","可重复使用的取水桶","input"],["item:r34:raw_water","水源实际取水","output"],["item:r34:filtered_water","过滤后仍需处理","output"],["item:water","处理与实际饮水","output"]]))
	return result

static func _card(id:String,name:String,description:String,definition:Dictionary,links:Array)->Dictionary:
	return {"id":id,"source_id":id.trim_prefix("source:"),"kind":"source","category_id":"terrain_resource","section_id":"sources","name":name,"description":description,"definition":definition,"links":links}
