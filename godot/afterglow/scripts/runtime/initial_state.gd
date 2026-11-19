extends RefCounted
## Finite starting facts and narrative, not a second simulation or generated rewards.
const Production = preload("res://scripts/production/production_service.gd")
const ActorProfiles=preload("res://scripts/runtime/actor_profiles.gd")

static func actor(id: String,name: String,position: Dictionary,home: Dictionary,pack: Dictionary) -> Dictionary:
	var value := position.duplicate(true)
	value.merge({"id":id,"name":name,"home":home.duplicate(true),"hp":100.0,"hunger":68.0,"thirst":58.0,"stamina":90.0,"fatigue":22.0,"cooldown":0.0,"pack":pack.duplicate(true),"intent":null,"activity":"自由行动","job":"rest","householdId":"home-residents" if id=="player" else id,"skills":{"survival":0,"gathering":0,"crafting":0,"combat":0},"wounds":[],"relationship":{"met":false,"helped":false,"member":false,"consent":false},"nextDecision":0.0,"work_target_id":"","work_payload":{}},true)
	value.appearance_id=ActorProfiles.for_new_actor(id);value.body_profile_id=ActorProfiles.BODY_ID
	return value

static func facts(seed_result: Dictionary) -> Dictionary:
	var spawns: Dictionary=seed_result.spawn_points
	var home: Dictionary=seed_result.get("home",{"x":22.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}).duplicate(true)
	var actors := [actor("player","归乡者",spawns.player,home,{"food":1,"water":1}),actor("village-resident","周婶",spawns["village-resident"],home,{}),actor("repair-resident","老许",spawns["repair-resident"],home,{})]
	actors[1].householdId="village-resident"
	actors[2].householdId="repair-resident"
	var quests: Array=[]
	var definitions := [
		["RH-Q01","回到旧宅","离开城市的第三天，你终于找到了回家的旧路。先找到睡位与饮水，修好一处入口。"],
		["RH-Q02","找到熟人","到村口联系熟识的村民。实际提供帮助，再邀请对方沿路回家。"],
		["RH-Q03","村口补给","小卖部还可能留有食水。亲自取回物资，留意修理铺的线索。"],
		["RH-Q04","带回工具","棚屋有旧工具与手册；修理铺幸存者也需要帮助。基础建设不依赖某个人存活。"],
		["RH-Q05","让家能工作","学习木工，建成可用工位和存放点，制作一件真实装备。"],
		["RH-Q06","带着准备再出去","从据点开始一次探索，在遭遇中选择临时技巧，携物返回后明确结算。"],
		["RH-Q07","守住这一晚","观察威胁预警，修补入口，处理一轮有限来袭。"],
		["RH-Q08","电台里的声音","用实际零件与劳动修复通信设备。收到线索后仍可继续生活。"]]
	for definition in definitions:quests.append({"id":definition[0],"name":definition[1],"description":definition[2],"status":"active" if definition[0]=="RH-Q01" else "available","completed":false})
	return {"version":5,"scenario":"rural-home-r33","time":0.0,"status":"playing","actors":actors,"stocks":seed_result.initial_stocks.duplicate(true),"actions":[],"quests":quests,"ledger":[],"log":[{"id":"opening","text":definitions[0][2],"time":0}],"visited":["RH-HOME"],"milestones":{},"nextId":1}

static func production(seed_result: Dictionary) -> Dictionary:
	var state:Dictionary=Production.empty_state()
	state.tools=seed_result.get("initial_tools",[]).duplicate(true)
	state.records=seed_result.get("initial_records",[]).duplicate(true)
	return state
