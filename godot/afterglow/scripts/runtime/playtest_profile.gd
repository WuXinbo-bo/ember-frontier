extends RefCounted
## Applied only to a freshly generated capture, never to a loaded save.
const TOOL_KINDS:Array=["salvaged_axe","shovel","pickaxe","hammer","hand_saw"]
const ITEMS:Dictionary={"food":4,"water":4,"timber":12,"scrap":8,"cloth":4,"soil_m3":2.0}
const OPENING_POLICY:="village-opening-v15"
const Draft=preload("res://scripts/actions/domain_draft.gd")
const COOPERATIVE_POLICY:="old-village-cooperative-v1"
const BOARD_PROGRAM:="old-village:construction-boards"
const WORKSHOP:="r34:generated:RH-HOME:woodwork"
static func prepare_opening(capture:Dictionary,profile:String="normal")->Dictionary:
	if profile not in ["normal","playtest"]:return {"ok":false,"code":"INVALID_OPENING_PROFILE","reason":"开局配置无效"}
	var generation:Dictionary=capture.get("world",{}).get("extensions",{}).get("generation:factory-r34",{})
	var content_version:int=int(generation.get("content_version",0))
	if content_version not in [15,16,17,18,19,20,21]:
		var historical:Dictionary=apply(capture) if profile=="playtest" else capture.duplicate(true)
		if not historical.has("source"):historical.source={}
		historical.source.opening_profile=profile
		return historical
	var result:Dictionary=capture.duplicate(true)
	if not result.has("source"):result.source={}
	# A persisted receipt prevents a resumed capture or repeated composition
	# from replenishing goods or moving a tool away from its current holder.
	var policy:String="village-opening-v%d"%content_version
	if result.source.get("opening_configuration",{}).get("id")==policy:return result
	var actors:Array=result.get("facts",{}).get("actors",[])
	var player:Dictionary={}
	for actor:Dictionary in actors:
		if actor.get("id")=="player":player=actor;break
	var production:Dictionary=result.get("world",{}).get("extensions",{}).get("r3:production",{})
	if player.is_empty() or not player.get("pack") is Dictionary or not production.get("tools") is Array:return {"ok":false,"code":"INVALID_OPENING_CONTENT","reason":"开局人物或工具登记缺失，未创建世界"}
	var kinds:Array=TOOL_KINDS if profile=="playtest" else ["salvaged_axe"]
	var selected:Dictionary={};var transfers:Array=[]
	for kind:String in kinds:
		var chosen:Dictionary={}
		# The initial registration owns every instance. Transfer its ordinary
		# tools before the finite reserve set; never manufacture duplicates.
		for tool:Dictionary in production.tools:
			if tool.get("kind")!=kind or float(tool.get("durability",0))<=0:continue
			if str(tool.get("id","")).contains(":reserve-tool:"):continue
			chosen=tool;break
		if chosen.is_empty():return {"ok":false,"code":"MISSING_OPENING_TOOL","reason":"初始现场工具缺少："+kind+"；未创建世界"}
		selected[kind]=chosen.id
		transfers.append({"id":chosen.id,"from":chosen.holderId,"to":"pack:player"})
		chosen.holderId="pack:player"
	if content_version>=19 and profile=="normal":
		var configured:Dictionary=_configure_companions(result,transfers)
		if not configured.ok:return configured
	if profile=="playtest":
		for item:String in ITEMS:player.pack[item]=maxf(float(player.pack.get(item,0)),float(ITEMS[item]))
		result.source.playtest={"id":"ready-to-test-v%d"%content_version,"label":"测试开局 · 五工具与有限补给","tools":selected.duplicate(true),"items":ITEMS.duplicate(true),"default_fresh":false,"automatic_save":false}
	if content_version >= 21:
		for actor: Dictionary in actors:
			if actor.id != "player" and not actor.get("relationship", {}).get("member", false):
				continue
			var weapon_id: String = "village:club:" + str(actor.id)
			production.tools.append({"id": weapon_id, "kind": "club", "holderId": "pack:" + str(actor.id), "durability": 100.0})
			actor.combat_weapon = weapon_id
		selected.club = player.combat_weapon
	result.source.opening_profile=profile
	result.source.opening_configuration={"id":policy,"profile":profile,"tools":selected,"transfers":transfers,"finite_sources":true}
	return result
static func _configure_companions(capture:Dictionary,transfers:Array)->Dictionary:
	var extensions:Dictionary=capture.world.extensions
	var workshop:=Draft.find(extensions["r34:modules"].instances,WORKSHOP)
	if workshop.is_empty() or not workshop.stock_refs.has_all(["input","output","tools"]):
		return {"ok":false,"code":"MISSING_OPENING_WORKSHOP","reason":"缺少旧村手工作坊的料位"}
	var stocks:Array=capture.facts.stocks
	for stock_id:String in workshop.stock_refs.values():
		var stock:=Draft.find(stocks,stock_id)
		if stock.is_empty():return {"ok":false,"code":"MISSING_OPENING_STOCK","reason":"缺少旧村手工作坊库存"}
		stock.searched=true
	var production:Dictionary=extensions["r3:production"]
	var starting_tools:Dictionary={"salvaged_axe":"village-resident","hammer":"repair-resident","hand_saw":"repair-resident"}
	for kind:String in starting_tools:
		var holder:String="pack:"+str(starting_tools[kind])
		var chosen:Dictionary={}
		for tool:Dictionary in production.tools:
			if tool.kind!=kind or float(tool.durability)<=0:continue
			if str(tool.id).contains(":reserve-tool:"):
				chosen=tool;break
		if chosen.is_empty():return {"ok":false,"code":"MISSING_COMPANION_TOOL","reason":"缺少同伴开局工具："+kind}
		transfers.append({"id":chosen.id,"from":chosen.holderId,"to":holder})
		chosen.holderId=holder
	production.knowledge["repair-resident"]=["basic_woodwork"]
	workshop.config.recipe_orders=[{"id":BOARD_PROGRAM,"recipe_id":"r34:saw_timber_v2","mode":"target","quantity":1,"completed":0,
		"target_item":"timber","target_quantity":8,"source_id":workshop.stock_refs.input,"output_id":workshop.stock_refs.output,
		"repair_tool_id":null,"paused":false,"revision":1,"created_at":0.0,"construction_supply":true}]
	extensions["r34:gameplay"].layout.cooperative_opening=COOPERATIVE_POLICY
	var tutorial:=Draft.find(capture.facts.quests,"V3-Q02")
	tutorial.description="框选一片林地交给同伴，原木会搬回手工作坊。修复缺板材时，工匠会先锯料；也可以亲手操作作坊。"
	return {"ok":true}

static func apply(capture:Dictionary)->Dictionary:
	if int(capture.get("world",{}).get("extensions",{}).get("generation:factory-r34",{}).get("content_version",0)) in [15,16,17,18,19,20,21]:return prepare_opening(capture,"playtest")
	var result:Dictionary=capture.duplicate(true)
	if not result.get("source",{}).get("playtest",{}).is_empty():return result
	# The normal village opening must preserve its first harvest/saw/repair loop.
	var village:Variant=result.get("world",{}).get("extensions",{}).get("r34:gameplay",{})
	if village is Dictionary and preload("res://scripts/runtime/village_progression.gd").enabled(village.get("layout",{})):
		return result
	var production:Dictionary=result.world.extensions["r3:production"]
	for kind:String in TOOL_KINDS:
		production.tools.append({"id":"playtest:player:"+kind,"kind":kind,"holderId":"pack:player","durability":100.0})
	for actor:Dictionary in result.facts.actors:
		if actor.id=="player":actor.pack.merge(ITEMS,true)
	result.source.playtest={"id":"ready-to-test-v1","label":"试玩配置 · 随身工具与有限测试物资","tools":TOOL_KINDS.duplicate(),"items":ITEMS.duplicate(),"default_fresh":true,"automatic_save":false}
	return result
static func slots()->Array:
	var result:Array=[]
	for kind:String in TOOL_KINDS:result.append({"kind":"tool","id":"playtest:player:"+kind})
	result.append_array([{"kind":"item","id":"food"},{"kind":"item","id":"water"},{},{}])
	return result
