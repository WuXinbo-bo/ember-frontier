extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## MT01 old normal22: two real repairs exhaust its original two scraps.
## No extreme-wear fixture, new source injection or arbitrary tool creation.
var commands:Array=[]
var records:Array=[]
var runtime_live:RefCounted
var mode:String="baseline"
var violations:Array=[]
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"r34:e:mt01:"+mode+":%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request);commands.append({"time":runtime.clock(),"request":request,"result":result});return result
func observe(runtime:RefCounted)->void:
	for a:Dictionary in runtime.facts().actors:
		if a.hp!=100:violations.append({"time":runtime.clock(),"reason":"original_hp_changed","actor_id":a.id})
		for item:String in a.pack:
			if float(a.pack[item])<0:violations.append({"reason":"negative_pack"})
	for s:Dictionary in runtime.facts().stocks:
		for item:String in s.items:
			if float(s.items[item])<0:violations.append({"reason":"negative_stock"})
func mark(label:String)->void:
	records.append({"label":label,"time":runtime_live.clock(),"facts":runtime_live.facts(),"production":runtime_live.world.extension("r3:production"),"story":runtime_live.world.extension("r34:gameplay")})
func repair_request(recipe:String,target:String,operators:Array)->Dictionary:
	return {"direct":true,"recipe_id":recipe,"source_id":"pack:player","output_id":"pack:player","repair_tool_id":target,"tool_ids":operators}
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1];source_sha=FileAccess.get_sha256(source_path)
	mode=str(JSON.parse_string(FileAccess.get_file_as_string(args[2])).get("probe_mode","baseline"));DirAccess.make_dir_recursive_absolute(output_dir)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path));check("actual own22 normal input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("old22 normal mounts complete unedited canonical facts",built.get("ok",false) and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world))
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;runtime_live=r
	mark("exact old22 normal source")
	check("old save only original five tool identities and two scraps",r.world.extension("r3:production").tools.size()==5 and r.actor("player").pack.scrap==2)
	check("old save has not learned repair from carrying real equipment",not r.world.extension("r3:production").knowledge.player.has("basic_tool_repair"))
	if mode=="baseline":
		for id:String in ["repair_hand_saw","repair_hammer","repair_shovel","repair_pickaxe"]:
			var refused:Dictionary=send(r,"craft",SHED+":workbench",repair_request(id,SAW,[HAMMER]))
			check("original22 has no executable "+id,not r._services.production.recipes.has(id) and not refused.get("ok",false) and refused.get("code")=="INVALID",refused)
		return finish()
	for row:Dictionary in r.world.extension("r34:logistics").tasks:
		if row.status not in ["completed","cancelled"]:
			check("original repeating task cancels legally before maintenance",send(r,"logistics.cancel",row.id).get("ok",false))
	if not social_contact(r,"repair-resident",false):check("real consent contact",false);return finish()
	check("one original NPC unavailable through actual consent withdrawal",send(r,"consent","repair-resident",{"enabled":false}).get("ok",false))
	if not transfer(r,"take",HOME,{"cloth":1}):return finish()
	if not transfer(r,"take",TOOLSTOCK,{"book_tool_repair":1}):return finish()
	var study:Dictionary=send(r,"study",SHED+":record:book_tool_repair",{"direct":false})
	check("original finite book teaches through actual12 second study",study.get("ok",false) and progress(r,400).finished and r.world.extension("r3:production").knowledge.player.has("basic_tool_repair"),study)
	if not study.get("ok",false):return finish()
	if not transfer(r,"deposit",HOME,{},[HAMMER]):return finish()
	if not contact(r,TOOLSTOCK):check("returns to workshop while hammer stays at home",false);return finish()
	var missing:Dictionary=send(r,"craft",SHED+":workbench",repair_request("repair_hand_saw",SAW,[HAMMER]))
	check("remote home-held original hammer cannot operate player repair",not missing.get("ok",false) and r.tool(HAMMER).holderId==HOME,missing)
	if not missing.get("ok",false):
		if not transfer(r,"take",HOME,{},[HAMMER]):return finish()
	else:return finish()
	if not contact(r,TOOLSTOCK):check("retrieved actual hammer returns to workshop",false);return finish()
	check("missing key tool returns by legal onsite take same identity",r.tool(HAMMER).holderId=="pack:player")
	mark("oneNPC unavailable knowledge learned original hammer retrieved")
	var old_saw:float=r.tool(SAW).durability;var old_hammer:float=r.tool(HAMMER).durability;var before_pack:Dictionary=r.actor("player").pack.duplicate(true)
	var repaired:Dictionary=send(r,"craft",SHED+":workbench",repair_request("repair_hand_saw",SAW,[HAMMER]))
	check("real damaged saw repair starts with original hammer",repaired.get("ok",false),repaired)
	if not repaired.get("ok",false):return finish()
	step(r,40)
	check("four actual seconds wear operator but reserve unsettled materials",r.actor("player").intent!=null and r.tool(SAW).durability==old_saw and r.tool(HAMMER).durability<old_hammer and Data.json_equal(before_pack,r.actor("player").pack))
	var cold:Dictionary=cold_restore(r,"paid-saw-repair-in-progress")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;runtime_live=r
	check("same saw repaired with capped60 and real cloth scrap hammer wear",progress(r,300).finished and r.tool(SAW).durability==minf(100,old_saw+60) and r.actor("player").pack.scrap==before_pack.scrap-1 and r.actor("player").pack.cloth==before_pack.cloth-1 and absf(old_hammer-r.tool(HAMMER).durability-1)<0.000001)
	var hammer_before_pack:Dictionary=r.actor("player").pack.duplicate(true);var hammer_before:float=r.tool(HAMMER).durability
	var hammer_repair:Dictionary=send(r,"craft",SHED+":workbench",repair_request("repair_hammer",HAMMER,[]))
	check("same worn hammer uses locked nooperator recipe",hammer_repair.get("ok",false) and progress(r,300).finished,hammer_repair)
	check("hammer pays original timber scrap and capped60 no invented operator",r.tool(HAMMER).durability==minf(100,hammer_before+60) and r.actor("player").pack.scrap==0 and r.actor("player").pack.timber==hammer_before_pack.timber-1)
	mark("two paid repairs exhaust original two scraps")
	var saw_before:float=r.tool(SAW).durability;var boards_before:float=r.actor("player").pack.timber;var handles_before:float=r.actor("player").pack.get("tool_handle",0)
	var craft:Dictionary=send(r,"craft",SHED+":workbench",{"direct":true,"recipe_id":"make_handle","source_id":"pack:player","output_id":"pack:player","tool_ids":[SAW]})
	check("repaired saw actually resumes original paid handle production",craft.get("ok",false) and progress(r,300).finished and r.actor("player").pack.timber==boards_before-1 and r.actor("player").pack.tool_handle==handles_before+1 and absf(saw_before-r.tool(SAW).durability-1)<0.000001,craft)
	check("original tool identity count knowledge and withdrawnNPC persist",r.world.extension("r3:production").tools.size()==5 and not r.actor("repair-resident").relationship.consent and r.actor("village-resident").relationship.consent and r.world.extension("r3:production").knowledge.player.has("basic_tool_repair"))
	mark("real restored saw production")
	var final_cold:Dictionary=cold_restore(r,"two-paid-repairs-real-production")
	check("complete maintenance and production cold restore",final_cold.get("ok",false))
	check("original people and all finite material invariants",violations.is_empty(),violations)
	finish()
func finish()->void:
	if runtime_live!=null:save(runtime_live,"maintenance-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"mode":mode,"commands":commands,"stages":records,"violations":violations,"fixed_steps":ticks,"source":{"path":source_path,"sha256":source_sha},"scope":"Old own22 actual normal finite resources, physical book and actual consent. MT01 catalog overlay only; other production GD frozen22 except catalog path mapping. Only two worn tools restored; no severe/zero wear or full five repair journey claimed, no content5 reserve injected into old save."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
