extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## WT01 normal generated content6, finite source/learning/repair/draw/carry.
var commands:Array=[]
var stages:Array=[]
var live:RefCounted
var paid_events:Dictionary={}
var violations:Array=[]
var water_id:String=""
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var req:Dictionary={"command_id":"r34:e:wt01-normal:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(req);commands.append({"time":runtime.clock(),"request":req,"result":result});return result
func observe(runtime:RefCounted)->void:
	for a:Dictionary in runtime.facts().actors:
		if a.hp!=100:violations.append({"time":runtime.clock(),"reason":"original_hp_changed","id":a.id})
		for item:String in a.pack:
			if float(a.pack[item])<0:violations.append({"reason":"negative_pack"})
	for event:Dictionary in runtime.facts().ledger:
		if event.kind in ["life-completed","learned","inventory-transfer"] or str(event.kind).begins_with("water"):paid_events[event.id]=event
func mark(label:String)->void:
	stages.append({"label":label,"time":live.clock(),"facts":live.facts(),"modules":live.world.extension("r34:modules"),"production":live.world.extension("r3:production")})
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	var config:Dictionary=Contract.fresh(Modules.generation_profiles(),6,1)
	check("explicit content6 contract resolves real policies",config.get("ok",false))
	if not config.get("ok",false):return finish()
	var built:Dictionary=normal_tools(config.contract)
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;live=r
	mark("normal content6 actual tool acquisition")
	var yard:String=built.yard_stock;var reserves:Array=[]
	for kind:String in ["salvaged_axe","hand_saw","hammer","shovel","pickaxe"]:reserves.append(yard+":reserve-tool:"+kind)
	check("five finite reserve tools have exact real holder and40 durability",reserves.all(func(id:String)->bool:return r.tool(id).get("holderId")==yard and r.tool(id).get("durability")==40))
	if not transfer(r,"take",yard,{"book_tool_repair":1,"cloth":2},reserves):return finish()
	check("taking finite reserve kit grants no repair knowledge",not r.world.extension("r3:production").knowledge.get("player",[]).has("basic_tool_repair") and reserves.all(func(id:String)->bool:return r.tool(id).holderId=="pack:player"))
	var studied:Dictionary=send(r,"study",yard+":reserve-record:book_tool_repair",{"direct":false})
	check("real spare record requires actual12 second learning",studied.get("ok",false) and progress(r,400).finished and r.world.extension("r3:production").knowledge.player.has("basic_tool_repair"),studied)
	if not studied.get("ok",false):return finish()
	if not transfer(r,"take",TOOLSTOCK,{"timber":2,"scrap":2}):return finish()
	var source:Dictionary=r.world.extension("r34:modules").water.sources[0];water_id=source.id
	check("normal source is finite48 and needs real repair",source.status=="needs_repair" and source.remaining==48)
	var approach:Dictionary=walk(r,source.use_point)
	if not approach.get("ok",false):
		var home:Dictionary=r.world.extension(Gameplay.KEY).layout.home
		if walk(r,home).get("ok",false):approach=walk(r,source.use_point)
	check("player walks actual plan-supported WT service point with materials",approach.get("ok",false),approach)
	if not approach.get("ok",false):return finish()
	check("onsite original water source discovered through normal command",send(r,"module.water.discover",water_id).get("ok",false))
	var before_pack:Dictionary=r.actor("player").pack.duplicate(true);var hammer:String=yard+":reserve-tool:hammer";var before_hammer:float=r.tool(hammer).durability
	var repair:Dictionary=send(r,"module.water.repair",water_id,{"source_id":"pack:player","tool_id":hammer})
	check("real material knowledge and finite40 hammer admit water repair",repair.get("ok",false),repair)
	if not repair.get("ok",false):return finish()
	step(r,50)
	var cold:Dictionary=cold_restore(r,"water-repair-actual-labor")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;live=r
	check("same water recovery completes after actual16 seconds",progress(r,300).finished and r.world.extension("r34:modules").water.sources[0].status=="ready")
	check("water recovery pays exact original2boards2scrap and hammer1",r.actor("player").pack.timber==before_pack.timber-2 and r.actor("player").pack.scrap==before_pack.scrap-2 and absf(before_hammer-r.tool(hammer).durability-1)<0.000001 and r.world.extension("r34:modules").water.sources[0].remaining==48)
	var old_water:float=r.actor("player").pack.get("water",0)
	for i:int in 2:
		var draw:Dictionary=send(r,"module.water.draw",water_id,{"output_id":"pack:player"})
		check("actual source draw settles one after12 seconds "+str(i),draw.get("ok",false) and progress(r,200).finished and r.actor("player").pack.get("water",0)==old_water+i+1 and r.world.extension("r34:modules").water.sources[0].remaining==47-i,draw)
		if not draw.get("ok",false):return finish()
	mark("finite water repaired drawn twice and actually carried")
	check("player actually carries two drawn units back to original home",walk(r,r.world.extension(Gameplay.KEY).layout.home).get("ok",false) and r.actor("player").pack.get("water",0)==old_water+2)
	var water_before_drink:float=r.actor("player").pack.get("water",0);var thirst_before:float=r.actor("player").thirst
	var drank:Dictionary=send(r,"drink")
	check("player pays one recovered water to original drink rule",drank.get("ok",false) and progress(r,40).finished and r.actor("player").pack.water==water_before_drink-1 and r.actor("player").thirst>thirst_before)
	if not social_contact(r,"village-resident"):check("real neighbor contact after water carry",false);return finish()
	var help:Dictionary=send(r,"help","village-resident",{"items":{"water":1}})
	check("second real water delivered onsite as actual neighbor help",help.get("ok",false),help)
	if not help.get("ok",false):return finish()
	# The neighbor owns the delivered water and uses the same life rule on
	# her real need. Do not lower needs or command an unwilling person.
	var drank_by_neighbor:bool=false
	for i:int in 7500:
		step(r)
		for event:Dictionary in r.facts().ledger:
			if event.kind=="life-completed" and event.get("actor_id")=="village-resident" and event.get("operation")=="drink":drank_by_neighbor=true
		if drank_by_neighbor:break
	check("unrecruited neighbor autonomously pays delivered water on real thirst",drank_by_neighbor and not r.actor("village-resident").relationship.member and r.actor("village-resident").pack.get("water",0)==0)
	mark("two original people really drank finite recovered water")
	var final_cold:Dictionary=cold_restore(r,"normal-water-two-real-drinkers")
	check("full actual knowledge costs water46 and people cold restore",final_cold.get("ok",false) and final_cold.runtime.world.extension("r34:modules").water.sources[0].remaining==46)
	check("WT normal journey has no original HP or negative material violation",violations.is_empty(),violations)
	finish()
func finish()->void:
	if live!=null:save(live,"water-normal-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"stages":stages,"paid_events":paid_events,"violations":violations,"fixed_steps":ticks,"water_source_id":water_id,"scope":"Actual new content6 seed713 finite normal source journey with B frozen WT01 overlay. No fixture capture/body/material/tool/knowledge/position injection. Runtime0.1 diagnostic steps only, no wall long/OS/performance/QF complete qualification."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
