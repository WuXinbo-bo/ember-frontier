extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## Continue A's successful immutable19 adverse save. Recovery adds no fixture.
const AXE=SHED+":tool:salvaged_axe"
const YARD="RH-HOME:stockyard-content:container"
const MACHINE="r34:normal-built-woodshop"
var active_runtime:RefCounted
var operations:Array=[]
var original_defense:Dictionary={}
var original_wounds:Array=[]
var original_ids:Array=[]
var trip_counts:Dictionary={}
var recording:bool=false
var invariants:Array=[]
var invariant_failed:bool=false
var log_base:float=0.0
var timber_base:float=0.0
var initial_settlements:Array=[]
var harvested_id:String=""
var recovery_stages:Array=[]
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var receipt:Dictionary=runtime.command({"command_id":"r34:e:recovery19:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
	operations.append({"sequence":sequence,"time":runtime.clock(),"kind":kind,"target":target,"payload":payload.duplicate(true),"destination":destination.duplicate(true),"receipt":{"ok":receipt.get("ok"),"code":receipt.get("code"),"reason":receipt.get("reason")},"player":{"location":Geometry.location(runtime.actor("player")),"pack":runtime.actor("player").pack,"stamina":runtime.actor("player").stamina}})
	return receipt
func amount(runtime:RefCounted,item:String)->float:
	var n:float=0.0
	for a:Dictionary in runtime.facts().actors:n+=float(a.pack.get(item,0))
	for s:Dictionary in runtime.facts().stocks:n+=float(s.items.get(item,0))
	return n
func observe(runtime:RefCounted)->void:
	active_runtime=runtime
	if not recording:return
	var errors:Array=[]
	var ids:Array=runtime.facts().actors.map(func(a:Dictionary)->String:return a.id);ids.sort()
	if ids!=original_ids:errors.append("original_actor_identity_changed")
	if runtime.actor("village-resident").hp!=52 or not Data.json_equal(original_wounds,runtime.actor("village-resident").wounds):errors.append("original_wounded_body_changed")
	if runtime.actor("repair-resident").relationship.consent:errors.append("withdrawal_reversed")
	if runtime.tool(SAW).durability!=0:errors.append("broken_saw_repaired_or_replaced_by_fixture")
	if runtime.stock(CACHE).items.get("timber")!=15:errors.append("near_full_cache_changed")
	if not Data.json_equal(original_defense,runtime.world.extension(Gameplay.KEY).defense):errors.append("defense_event_reset")
	for t:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if trip_counts.has(t.id) and float(t.trips)<float(trip_counts[t.id]):errors.append("trip_regressed")
	for a:Dictionary in runtime.facts().actors:
		for field:String in ["hp","stamina","hunger","thirst","fatigue"]:
			if not is_finite(float(a.get(field,0))):errors.append("nonfinite_body")
	for stock:Dictionary in runtime.facts().stocks:
		for item:String in stock.items:
			if not is_finite(float(stock.items[item])) or float(stock.items[item])<0:errors.append("invalid_inventory")
	if not errors.is_empty() and not invariant_failed:
		invariant_failed=true;invariants.append({"time":runtime.clock(),"errors":errors});save(runtime,"failure-invariant");check("original adverse state invariants every tick",false,errors)
func mark(runtime:RefCounted,label:String)->void:
	observe(runtime)
	recovery_stages.append({"stage":label,"time":runtime.clock(),"pack":runtime.actor("player").pack,"axe":runtime.tool(AXE),"hammer":runtime.tool(HAMMER),"saw":runtime.tool(SAW),"machine":runtime._services.production.factory_projection(),"log_total":amount(runtime,"log"),"timber_total":amount(runtime,"timber"),"actors":runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")!="infected")})
	print("RECOVERY_STAGE "+label+" "+str(runtime.clock()))
func order(runtime:RefCounted,id:String)->Dictionary:
	for o:Dictionary in runtime.world.extension("r3:production").orders:
		if o.id==id:return o
	return {}
func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var restored:Dictionary=super.cold_restore(runtime,label)
	if restored.get("ok",false):observe(restored.runtime)
	return restored
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text();sources.append({"path":source_path,"sha256":source_sha})
	var decoded:Dictionary=Store.decode(text)
	check("unaltered A qualified19 mixed recovery source decodes",decoded.ok)
	if not decoded.ok:return finish()
	var n:=Native.new();var built:Dictionary=n._assemble(decoded.capture);n.free()
	check("immutable19 assembles original adverse source",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;active_runtime=runtime
	check("source retains broken saw wounded52 withdrawn companion near-full cache and finite unspent handle",runtime.tool(SAW).durability==0 and runtime.actor("village-resident").hp==52 and not runtime.actor("repair-resident").relationship.consent and runtime.stock(CACHE).items.get("timber")==15 and runtime.stock(YARD).items.get("tool_handle")==1,{"axe":runtime.tool(AXE),"pack":runtime.actor("player").pack})
	original_defense=runtime.world.extension(Gameplay.KEY).defense
	original_wounds=runtime.actor("village-resident").wounds.duplicate(true)
	original_ids=runtime.facts().actors.map(func(a:Dictionary)->String:return a.id);original_ids.sort()
	for t:Dictionary in runtime.world.extension("r34:logistics").tasks:trip_counts[t.id]=t.trips
	log_base=amount(runtime,"log");timber_base=amount(runtime,"timber")
	initial_settlements=runtime.world.extension("r34:production").settlements.map(func(s:Dictionary)->String:return s.id)
	recording=true;mark(runtime,"unchanged-adverse-source")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("19 recovery uses supported axe repair and existing machine alternative; no saw repair invented",catalog.production_recipes.any(func(r:Dictionary)->bool:return r.id=="repair_axe") and not catalog.production_recipes.any(func(r:Dictionary)->bool:return r.get("repairTool",{}).get("kind")=="hand_saw"))
	# Original missing-input stop is retained; queue a new target without any feed.
	var configured:Dictionary=send(runtime,"factory.configure",MACHINE,{"recipe_id":"saw_timber","batches":2})
	step(runtime,5)
	var outage:Array=runtime._services.production.factory_projection().orders.filter(func(o:Dictionary)->bool:return o.module_id==MACHINE)
	check("real machine remains missing input before lawful replenishment",configured.ok and outage.size()==1 and outage[0].blockers.has("missing_input") and amount(runtime,"timber")==timber_base,outage)
	if not configured.ok:return finish()
	# Real searched book and historical handle; no generated replacement tool.
	if not transfer(runtime,"take",TOOLSTOCK,{"book_tool_repair":1}):return finish()
	var study:Dictionary=send(runtime,"study",SHED+":record:book_tool_repair",{"direct":false})
	var read:Dictionary=progress(runtime,400) if study.ok else {}
	check("physically obtained original repair book is actually studied",study.ok and read.get("finished",false) and runtime.world.extension("r3:production").knowledge.get("player",[]).has("basic_tool_repair"),study)
	if not study.ok or not read.get("finished",false):return finish()
	if not transfer(runtime,"take",YARD,{"tool_handle":1}):return finish()
	if not contact(runtime,TOOLSTOCK):check("real return to existing operating bench",false);return finish()
	var axe_before:float=runtime.tool(AXE).durability;var hammer_before:float=runtime.tool(HAMMER).durability
	var pack_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	check("finite actual axe is low enough for unmaxed60 repair and real payment exists",axe_before>0 and axe_before<40 and pack_before.get("tool_handle",0)==1 and pack_before.get("scrap",0)>=1,{"durability":axe_before,"pack":pack_before})
	var payload:Dictionary=craft_request("repair_axe",HAMMER);payload.repair_tool_id=AXE
	var repair:Dictionary=send(runtime,"craft",SHED+":workbench",payload)
	var repair_id:String=""
	for i:int in 400:
		step(runtime)
		for o:Dictionary in runtime.world.extension("r3:production").orders:
			if o.targetId=="repair_axe" and o.status=="active" and float(o.elapsed)>=4 and float(o.elapsed)<12:repair_id=o.id
		if not repair_id.is_empty():break
	check("repair really begins paid hammer labor before any material settlement",repair.ok and not repair_id.is_empty() and runtime.tool(HAMMER).durability<hammer_before and runtime.tool(AXE).durability==axe_before and Data.json_equal(pack_before,runtime.actor("player").pack),repair)
	if repair_id.is_empty():save(runtime,"failure-repair-start");return finish()
	mark(runtime,"repair-in-progress")
	var restored:Dictionary=cold_restore(runtime,"repair-in-progress")
	if not restored.ok:return finish()
	runtime=restored.runtime
	check("cold preserves same paid repair order and reserved original handle",order(runtime,repair_id).status=="active" and runtime._services.production.reserved("pack:player","tool_handle")==1 and runtime.tool(AXE).durability==axe_before)
	var finished:Dictionary=progress(runtime,300)
	var axe_after:float=runtime.tool(AXE).durability
	check("original recipe repairs same axe exactly60 below full and charges one handle one scrap",finished.finished and order(runtime,repair_id).status=="completed" and absf(axe_after-axe_before-60)<0.000001 and axe_after<100 and runtime.actor("player").pack.get("tool_handle")==pack_before.tool_handle-1 and runtime.actor("player").pack.get("scrap")==pack_before.scrap-1 and absf(hammer_before-runtime.tool(HAMMER).durability-1)<0.000001,{"order":order(runtime,repair_id),"axe_before":axe_before,"axe_after":axe_after,"pack":runtime.actor("player").pack})
	if order(runtime,repair_id).status!="completed":save(runtime,"failure-repair-settlement");return finish()
	mark(runtime,"paid-repair-completed")
	# Original supported standing trees; walk/harvest/take uses B's same executor.
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var drop:String=""
	for tree:Dictionary in trees.slice(0,8):
		var harvest:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[AXE]})
		if not harvest.ok:continue
		var cut:Dictionary=progress(runtime,1200)
		if cut.finished and runtime.world.entity(tree.id).data.harvest.phase=="stump":harvested_id=tree.id;drop=tree.data.outputId;break
		check("real repaired-axe tree labor completes",false,{"tree":tree.id,"progress":cut});save(runtime,"failure-harvest");return finish()
	check("same repaired axe really fells original persistent tree with finite three-log drops",not drop.is_empty() and runtime.stock(drop).items.get("log")==3 and runtime.tool(AXE).durability<axe_after and amount(runtime,"log")==log_base+3,{"tree":harvested_id,"drop":drop,"axe":runtime.tool(AXE)})
	if drop.is_empty():save(runtime,"failure-no-reachable-tree");return finish()
	if not transfer(runtime,"take",drop,{"log":3}):return finish()
	check("three harvested logs physically carried; near-full boards and damaged saw untouched",runtime.actor("player").pack.get("log")==3 and runtime.tool(SAW).durability==0 and runtime.stock(CACHE).items.get("timber")==15)
	# Do not let machine start until BOTH actual service-face deposits complete.
	var paused:Dictionary=send(runtime,"factory.pause",MACHINE)
	check("original pause permits finite input and fuel loading with no remote labor",paused.ok,paused)
	if not transfer(runtime,"deposit",MACHINE+":stock:input",{"log":2}):return finish()
	if not transfer(runtime,"deposit",MACHINE+":stock:fuel",{"log":1}):return finish()
	check("actual service walks load exactly two raw logs and one fuel from harvested pack",runtime.actor("player").pack.get("log")==0 and runtime.stock(MACHINE+":stock:input").items.get("log")==2 and runtime.stock(MACHINE+":stock:fuel").items.get("log")==1 and amount(runtime,"log")==log_base+3)
	mark(runtime,"real-refeed-before-resume")
	restored=cold_restore(runtime,"real-refeed-before-resume")
	if not restored.ok:return finish()
	runtime=restored.runtime
	var output_before:float=runtime.stock(BOARDS).items.get("timber",0)
	var resumed:Dictionary=send(runtime,"factory.resume",MACHINE)
	var running_batch:String=""
	for i:int in 100:
		step(runtime)
		for batch:Dictionary in runtime.world.extension("r34:production").batches:
			if not initial_settlements.has(str(batch.id)+":settlement") and batch.status=="active" and float(batch.elapsed)>=3 and float(batch.elapsed)<10:running_batch=batch.id
		if not running_batch.is_empty():break
	check("refilled original machine actually consumes fuel and works new batch",resumed.ok and not running_batch.is_empty() and runtime.stock(MACHINE+":stock:fuel").items.get("log")==0 and runtime.stock(BOARDS).items.get("timber")==output_before,{"batch":running_batch,"machine":runtime._services.production.factory_projection()})
	if running_batch.is_empty():save(runtime,"failure-machine-not-running");return finish()
	restored=cold_restore(runtime,"recovered-machine-in-progress")
	if not restored.ok:return finish()
	runtime=restored.runtime
	for i:int in 350:
		step(runtime)
		if runtime.world.extension("r34:production").settlements.size()>=initial_settlements.size()+2:break
	var settlements:Array=runtime.world.extension("r34:production").settlements.filter(func(s:Dictionary)->bool:return not initial_settlements.has(s.id))
	check("two real restored batches settle exactly8 boards with unique paid identities",settlements.size()==2 and settlements.all(func(s:Dictionary)->bool:return s.module_id==MACHINE and s.outputs=={"timber":4.0}) and settlements[0].id!=settlements[1].id and runtime.stock(BOARDS).items.get("timber")==output_before+8 and amount(runtime,"timber")==timber_base+8,settlements)
	check("three finite harvested logs are fully consumed by two inputs and fuel",runtime.stock(MACHINE+":stock:input").items.get("log")==0 and runtime.stock(MACHINE+":stock:fuel").items.get("log")==0 and runtime.actor("player").pack.get("log")==0 and amount(runtime,"log")==log_base)
	var final_orders:Array=runtime._services.production.factory_projection().orders.filter(func(o:Dictionary)->bool:return o.module_id==MACHINE)
	check("completed target leaves no new WIP and admits no free third batch",final_orders.size()==1 and final_orders[0].remaining==0 and final_orders[0].blockers.has("target_met"),final_orders)
	var stable_timber:float=amount(runtime,"timber");var count:int=runtime.world.extension("r34:production").settlements.size()
	step(runtime,30)
	check("recovery does not duplicate settlement on further authoritative time",amount(runtime,"timber")==stable_timber and runtime.world.extension("r34:production").settlements.size()==count)
	mark(runtime,"actual-production-recovered")
	restored=cold_restore(runtime,"actual-production-recovered")
	check("final successful native keeps paid repair and two new settlements",restored.ok and order(restored.runtime,repair_id).status=="completed" and restored.runtime.world.extension("r34:production").settlements.size()==count and amount(restored.runtime,"timber")==timber_base+8)
	check("every observed tick preserves original52 wounds withdrawal event cache saw and people",not invariant_failed,{"ticks":ticks,"errors":invariants})
	finish()
func finish()->void:
	if active_runtime!=null:save(active_runtime,"actual-final-success" if checks.all(func(c:Dictionary)->bool:return c.ok) else "actual-final-failure")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"sources":sources,"operations":operations,"stages":recovery_stages,"invariant_errors":invariants,"ticks":ticks,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"prior_fixture":"A19 E41 output continues original18 real1800 journey. Existing downward saw88->0.25 then real wear->0 retained; separate learned-station-ruin branch was not merged. This new recovery adds ZERO fixture/capture edits; remains an isolated adverse continuation, not a wholly natural fresh opening.","scope":"Immutable19 bounded headless functional recovery only. Original finite book/handle/scrap, paid same-axe repair+60 below full, actual tree3logs, original machine two inputs+one fuel ->2 paid batches8boards; machine substitutes broken hand-saw process, no unsupported saw-repair claim. Preserve wounded52 withdrawal needs events stocks costs. No OS/VA/FPS/resource/long-time or whole R34-56/60 qualification."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
