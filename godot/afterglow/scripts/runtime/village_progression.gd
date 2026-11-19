extends RefCounted
## Scenario three observes the existing ledgers. It never issues stock or labor.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
static var _crafted_outputs:Dictionary={}
const KEY:="r34:gameplay"
const QUESTS:Array=[
	["V3-Q01","在破院安顿下来","early","settle","先喝水、吃一份口粮，并在旧宅真实睡位休息。三个人共用有限物资，先保住生活。"],
	["V3-Q02","让小院重新开工","early","handwork","在手工棚取工具并读木工手册，采一棵树，安排同伴实际搬运，再亲手锯出第一批板材。"],
	["V3-Q03","修好村里的仓棚","early","warehouse","把板材和废料运到破损仓棚，付料修复；仓棚恢复后才开放真实仓储容量。"],
	["V3-Q04","从应急转向日常供给","mid","supply","修复旧宅、恢复田块，并完成实际取水净化和食物加工；同伴先补给休息再劳动。"],
	["V3-Q05","把手工作业变成生产","mid","production","建成锯木生产设施，补充原木与能源完成真实批次；完成一次建筑升级，扩大已修复家园的能力。"],
	["V3-Q06","让电台重新发声","mid","radio","带维修手册、手锤、废料8和工具柄1到旧村手工棚，实际维修并完成发报。"],
	["V3-Q07","接通村外运输路线","late","routes","沿乡道调查旧设施，明确接受风险后清理阻塞与有限威胁，恢复真实运输路线。"],
	["V3-Q08","把旧院连成新村","late","village","保留生活与生产供给，完成两次付料升级并走访村外区域；此后继续建设，不自动结束世界。"]]

static func enabled(layout:Dictionary)->bool:
	return int(layout.get("opening_version",0))==3 or int(layout.get("content_version",0)) in [13,14,15,16,17,18,19,20,21]

static func first_chapter(layout:Dictionary)->bool:
	return int(layout.get("content_version",0))>=20

static func initial_quests(layout:Dictionary={})->Array:
	var result:Array=[]
	var descriptions:Dictionary={
		"V3-Q01":"在旧宅安顿；口粮、饮水和床位都可按需要使用。",
		"V3-Q02":"圈出可采伐的树，安排同伴把木头搬回手工作坊。你也可以亲手采集和加工。",
		"V3-Q03":"修好旧宅和仓棚。旧宅改善休息，仓棚开放日常储位。",
		"V3-Q04":"取原水并煮沸。在小田种土豆，收获后在灶位做一份热饭。",
		"V3-Q05":"选择修好旧锯木站或在村内新建，投入原木和燃料，完成一批机械板材。",
		"V3-Q06":"回手工作坊修电台，发出旧村的第一条信号。",
		"V3-Q07":"勘察乡道，选择是否承担风险。通路恢复后，让首趟货物送达村里。",
		"V3-Q08":"发报后的扩建：升级建筑并拓展村外供应。"}
	for spec:Array in QUESTS:
		var description:String=str(descriptions.get(spec[0],spec[4])) if first_chapter(layout) else spec[4]
		result.append({"id":spec[0],"name":spec[1],"description":description,"chapter":spec[2],"status":"进行中" if result.is_empty() else "可提前准备","completed":false,"objectives":[],"progress":"0 / 1"})
	return result

static func companions(actors:Array,layout:Dictionary={})->void:
	preload("res://scripts/runtime/actor_profiles.gd").apply_opening(actors,layout)
	for actor:Dictionary in actors:
		if actor.get("id") not in ["village-resident","repair-resident"]:continue
		actor.householdId="home-residents"
		actor.relationship={"met":true,"helped":false,"member":true,"consent":true,"home_arrived":true}
		actor.activity="与同伴一起安顿旧村"
		actor.pack={"food":1,"water":1}
		# Voluntary membership grants no goods, knowledge or automatic labor.
		actor.job="rest";actor.work_target_id="";actor.work_payload={}

static func observe(state:Dictionary,event:Dictionary)->void:
	if not enabled(state.get("layout",{})):return
	var flags:Dictionary=state.flags
	var kind:String=str(event.get("kind",""));var actor:String=str(event.get("actor_id",event.get("actorId","")))
	if kind=="life-completed" and actor=="player":
		var operation:String=str(event.get("operation",""))
		if operation in ["drink","eat"]:flags["village_"+operation]=true
		if operation in ["rest","sleep"] and not str(event.get("target_id","")).is_empty():flags.village_slept=true
	if kind=="water-collected" and float(event.get("amount",0))>0:flags.village_water_collected=true
	if kind=="zonework-completed":
		if str(event.get("operation","")) in ["harvest_crop","crop_harvest","harvest"]:flags.village_crop_harvested=true
		if event.get("operation")=="draw_raw_water":flags.village_water_collected=true
	if kind=="crafted":
		var recipe:String=str(event.get("targetId",event.get("target_id","")))
		var outputs:Dictionary=crafted_outputs(recipe)
		# Only completed production facts reach this observer. Read the actual
		# registered output semantics, so a new safe-water/meal recipe cannot
		# silently stop advancing supply while still producing usable goods.
		if float(outputs.get("water",0))>0:flags.village_clean_water=true
		for item:String in outputs:
			if float(outputs[item])>0 and not Content.consumable_definition(item,"eat").is_empty():flags.village_food_produced=true
	if kind=="logistics-delivery-completed" and actor in ["village-resident","repair-resident"]:flags.village_companion_delivery=true
	if kind=="radio-completed" and event.get("operation")=="transmit" and first_chapter(state.layout):
		flags.chapter_one_signal_at=float(event.get("time",0))

static func crafted_outputs(recipe_id:String)->Dictionary:
	if _crafted_outputs.is_empty():
		var legacy:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
		var recipes:Array=legacy.get("production_recipes",[]) if legacy is Dictionary else []
		recipes.append_array(preload("res://scripts/production/module_recipes.gd").definitions())
		for recipe:Dictionary in recipes:_crafted_outputs[str(recipe.id)]=recipe.get("outputs",{}).duplicate(true)
	return _crafted_outputs.get(recipe_id,{})

static func reconcile(tx:RefCounted,state:Dictionary)->void:
	if not enabled(state.get("layout",{})):return
	var project_fields: Array[String] = ["projects"]
	var projects: Array = tx.read_extension_fields("r34:modules", project_fields).get("projects", [])
	var instances: Dictionary = {}
	var loaded_instances := false
	var upgrades:int=0
	for project: Dictionary in projects:
		if project.get("status")!="completed" or project.get("cost",{}).is_empty():continue
		if project.get("operation")=="upgrade":upgrades+=1
		if project.get("operation")!="restore":continue
		if not loaded_instances:
			var instance_fields: Array[String] = ["instances"]
			for module: Dictionary in tx.read_extension_fields("r34:modules", instance_fields).get("instances", []):
				instances[module.get("id")] = module
			loaded_instances = true
		var module: Dictionary = instances.get(project.get("module_id"), {})
		var restoration:Dictionary=module.get("restoration",{})
		var heritage:Dictionary=module.get("heritage",{})
		var paid:bool=restoration.get("policy")=="village-heritage-v1" and restoration.get("completed",false)
		paid=paid or heritage.get("restored",false)
		if not paid:continue
		var shape:String=str(Catalog.definition(str(module.get("definition_id",""))).get("shape",""))
		if shape=="home":state.flags.village_home_restored=true
		if shape=="warehouse":state.flags.village_warehouse_restored=true
	state.flags.village_upgraded=upgrades>0
	state.flags.village_two_upgrades=upgrades>=2
	# Production facts are durable and authoritative even after ledger trimming.
	var fact_fields:Array[String]=["facts"]
	for fact:Dictionary in tx.read_extension_fields("r3:production",fact_fields).get("facts",[]):
		observe(state,fact)
		if fact.get("kind")=="tree-felled":state.flags.real_harvest=true
		if fact.get("kind")=="crafted" and fact.get("targetId") in ["saw_timber","r34:saw_timber_v2"]:
			var actor_id:String=str(fact.get("actorId",""))
			if actor_id=="player" or (state.layout.has("cooperative_opening") and actor_id in ["village-resident","repair-resident"]):state.flags.village_hand_sawn=true
	var radio_fields:Array[String]=["radio"]
	var radio:Dictionary=tx.read_extension_fields("r33:gameplay",radio_fields).get("radio",{})
	state.flags.village_radio_connected=radio.get("status")=="connected"
	state.flags.village_outward_visit=tx.read_facts().get("visited",[]).any(func(id:Variant)->bool:return str(id)!="RH-HOME")
	refresh_quests({"quests": tx.writable_collection("quests")}, state)

static func requirements(state:Dictionary)->Dictionary:
	var f:Dictionary=state.get("flags",{});var story:Dictionary=state.get("stories",{}).get("ST01",{}).get("flags",{})
	var cooperative:bool=state.get("layout",{}).has("cooperative_opening")
	var chapter:bool=first_chapter(state.get("layout",{}))
	var boards:Array=["锯出第一批板材",f.get("village_hand_sawn",false)] if cooperative else ["学会木工并亲手锯板",story.get("read_woodwork_record",false) and (story.get("real_hand_saw_work",false) or f.get("village_hand_sawn",false))]
	var route:bool=false
	for objective:Dictionary in state.get("regional_objectives",{}).values():
		if objective.get("completed",false):route=true
	var result:Dictionary={
		"V3-Q01":[["喝过真实饮水",f.get("village_drink",false)],["吃过一份口粮",f.get("village_eat",false)],["在真实睡位休息",f.get("village_slept",false)]],
		"V3-Q02":[["采伐实际木料",f.get("real_harvest",false)],boards,["同伴完成真实搬运",f.get("village_companion_delivery",false)]],
		"V3-Q03":[["付料修复原址仓棚",f.get("village_warehouse_restored",false)]],
		"V3-Q04":[["修复旧宅",f.get("village_home_restored",false)],["实际取水并净化",f.get("village_water_collected",false) and f.get("village_clean_water",false)],["收获作物或加工食物",f.get("village_crop_harvested",false) or f.get("village_food_produced",false)]],
		"V3-Q05":[["完成真实机器批次",f.get("real_machine_output",false)],["完成一次付料升级",f.get("village_upgraded",false)]],
		"V3-Q06":[["现场修复电台并发出信号",f.get("village_radio_connected",false)]],
		"V3-Q07":[["清理真实路线与对应威胁",route]],
		"V3-Q08":[["完成两次付料升级",f.get("village_two_upgrades",false)],["实际走访村外地区",f.get("village_outward_visit",false)],["保持已接通的电台与路线",f.get("village_radio_connected",false) and route]]}
	if chapter:
		result["V3-Q01"]=[["三人抵达旧村",true]]
		result["V3-Q03"].append(["付料修复旧宅",f.get("village_home_restored",false)])
		result["V3-Q04"]=[["实际取水并煮沸",f.get("village_water_collected",false) and f.get("village_clean_water",false)],["收获土豆",f.get("village_crop_harvested",false)],["在灶位做出一份热饭",f.get("village_food_produced",false)]]
		result["V3-Q05"]=[["完成真实机器批次",f.get("real_machine_output",false)]]
		result["V3-Q07"].append(["外部货物送到村里",f.get("chapter_route_delivered",false)])
	return result

static func refresh_quests(facts:Dictionary,state:Dictionary)->void:
	var needed:Dictionary=requirements(state);var previous:bool=true
	for quest:Dictionary in facts.get("quests",[]):
		if not needed.has(quest.id):continue
		var done:int=0;quest.objectives=[]
		for index:int in needed[quest.id].size():
			var entry:Array=needed[quest.id][index];var ok:bool=bool(entry[1])
			quest.objectives.append({"id":str(quest.id)+":"+str(index),"text":entry[0],"status":"已完成" if ok else "待完成"})
			if ok:done+=1
		quest.completed=bool(quest.get("completed",false)) or done==needed[quest.id].size()
		quest.status="已完成" if quest.completed else "进行中" if previous else "可提前准备"
		quest.progress="%d / %d"%[done,needed[quest.id].size()]
		previous=previous and bool(quest.completed)

static func radio_station(world:RefCounted)->String:
	# Display and radio admission need only current instances, not project,
	# registration and source-receipt histories on every HUD refresh.
	var fields:Array[String]=["instances"]
	var modules:Variant=world.extension_fields("r34:modules",fields) if world.has_method("extension_fields") else world.extension("r34:modules")
	if not modules is Dictionary:return ""
	for module:Dictionary in modules.get("instances",[]):
		if module.get("region")!="RH-HOME" or not module.get("discovered",false) or module.get("status")!="operational":continue
		if module.get("owner")!="home-residents" or Catalog.definition(str(module.get("definition_id",""))).get("shape")!="manual":continue
		return str(module.get("config",{}).get("workbench_id",""))
	return ""

static func radio_ready(state:Dictionary)->bool:
	return radio_missing(state).is_empty()

static func radio_missing(state:Dictionary)->PackedStringArray:
	var flags:Dictionary=state.get("flags",{})
	var missing:=PackedStringArray()
	var checks:Array=[["village_warehouse_restored","修好仓棚"],["real_machine_output","产出一批机械板材"]]
	if first_chapter(state.get("layout",{})):
		checks.insert(0,["village_home_restored","修好旧宅"])
		checks.append_array([["village_water_collected","到水源取水"],["village_clean_water","煮沸饮水"],["village_crop_harvested","收获土豆"],["village_food_produced","做出热饭"]])
	for row:Array in checks:
		if not flags.get(row[0],false):missing.append(row[1])
	return missing

static func snapshot(facts:Dictionary,world:RefCounted)->Dictionary:
	var fields:Array[String]=["layout","flags"]
	var state:Variant
	if world.has_method("extension_entries") and world.has_method("extension_fields"):
		# Layout also contains generated route-cell plans. Walking HUD needs
		# only the opening discriminator and its small landmark ID table.
		var flag_fields:Array[String]=["flags"]
		state=world.extension_fields(KEY,flag_fields)
		state.layout=world.extension_entries(KEY,"layout",["opening_version","content_version","opening_landmarks"])
	else:
		state=world.extension_fields(KEY,fields) if world.has_method("extension_fields") else world.extension(KEY)
	if not state is Dictionary or not enabled(state.get("layout",{})):return {"available":false}
	var quests:Array=facts.get("quests",[]).filter(func(q:Dictionary)->bool:return str(q.get("id","")).begins_with("V3-"))
	var current:Dictionary={};var spec:Array=QUESTS[-1]
	for quest:Dictionary in quests:
		if not quest.get("completed",false):current=quest;break
	if not current.is_empty():
		for entry:Array in QUESTS:
			if entry[0]==current.id:spec=entry;break
	var station:String=radio_station(world)
	var radio_fields:Array[String]=["radio"];var legacy:Variant=world.extension_fields("r33:gameplay",radio_fields) if world.has_method("extension_fields") else world.extension("r33:gameplay")
	var radio:Dictionary=legacy.get("radio",{}) if legacy is Dictionary else {}
	var status:String=str(radio.get("status","unrepaired"));var choices:Array=[];var hammer:String=""
	var tool_fields:Array[String]=["tools"];var production:Variant=world.extension_fields("r3:production",tool_fields) if world.has_method("extension_fields") else world.extension("r3:production")
	if production is Dictionary:
		for tool:Dictionary in production.get("tools",[]):
			if tool.get("kind")=="hammer" and tool.get("holderId")=="pack:player" and float(tool.get("durability",0))>0:hammer=str(tool.id);break
	if not station.is_empty() and status!="connected":
		var repair:bool=status=="unrepaired"
		choices.append({"id":"village-radio-repair" if repair else "village-radio-transmit","label":"现场维修电台 · 废料8 / 工具柄1 / 手锤 / 20秒" if repair else "现场发报 · 30秒","command":{"kind":"radio","target_id":station,"payload":{"operation":"repair" if repair else "transmit","tool_id":hammer}}})
	var missing:=radio_missing(state)
	var flags:Dictionary=state.get("flags",{})
	var summary:Array=[]
	for check:Array in [["village_home_restored","旧宅"],["village_warehouse_restored","仓棚"],["village_clean_water","饮水"],["village_food_produced","热饭"],["real_machine_output","机械板材"]]:
		if flags.get(check[0],false):summary.append({"label":check[1],"value":"已恢复" if check[0].ends_with("restored") else "已产出"})
	var chapter:Dictionary={"active":first_chapter(state.layout),"completed":status=="connected","summary":summary,"heading":"第一章 · 旧村复兴","caption":"信号传出了山谷。你可以留在村里经营，也可以沿乡道打开新的货路。","signal_at":flags.get("chapter_one_signal_at",0.0)}
	return {"available":true,"version":3,"phase":spec[3],"chapter":spec[2],"chapter_one":chapter,"title":current.get("name","旧村已重新运转"),"next_step":current.get("description","继续扩建、维持供给并探索其他乡野区域。"),"objectives":current.get("objectives",[]).duplicate(true),"quests":quests.duplicate(true),"radio":{"status":status,"station_id":station,"unlocked":missing.is_empty(),"unlock_hint":"尚需："+"、".join(missing) if not missing.is_empty() else "回手工作坊整备通信。","choices":choices},"landmarks":state.get("layout",{}).get("opening_landmarks",{}).duplicate(true)}
