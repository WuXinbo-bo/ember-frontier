extends "res://tests/integration/run_factory_economy.gd"
## Actual unfunded content13. Only player commands and the normal clock mutate it.
var live_runtime:RefCounted
var completed_route:bool=false

func note(runtime:RefCounted,stage:String,detail:Variant=null)->void:
	super.note(runtime,stage,detail)
	print(JSON.stringify({"stage":stage,"clock":runtime.clock()}))

func diagnostic(runtime:RefCounted)->Dictionary:
	var people:Array=[]
	for id:String in ["player","village-resident","repair-resident"]:
		var actor:Dictionary=runtime.actor(id)
		people.append({"id":id,"location":Geometry.location(actor),"stamina":actor.get("stamina"),"hunger":actor.get("hunger"),"thirst":actor.get("thirst"),"activity":actor.get("activity"),"intent":actor.get("intent"),"job":actor.get("job"),"pack":actor.get("pack")})
	return {"clock":runtime.clock(),"people":people,"tasks":runtime.world.extension("r34:logistics").get("tasks",[]),"orders":runtime.world.extension("r3:production").get("orders",[]).slice(-5),"flags":runtime.world.extension("r34:gameplay").get("flags",{})}

func search_source(runtime:RefCounted,id:String)->bool:
	if not near_stock(runtime,id):
		check("real body reaches logistics endpoint "+id,false,diagnostic(runtime));return false
	if runtime.stock(id).get("searched",false):return true
	var searched:Dictionary=send(runtime,"search",id)
	var completed:Dictionary=progress(runtime,100) if searched.ok else {}
	var ok:bool=searched.ok and completed.get("finished",false) and runtime.stock(id).get("searched",false)
	check("real search reveals logistics endpoint "+id,ok,searched.get("reason"))
	return ok

func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0] if not args.is_empty() else "user://village-natural-route"
	DirAccess.make_dir_recursive_absolute(outdir)
	var profiles:Dictionary=Assembly.generation_profiles(13)
	var source:Dictionary=Assembly.generate(713,profiles.get("profiles",[]),13) if profiles.ok else profiles
	var prepared:Dictionary=Assembly.prepare(source) if source.get("ok",true) else source
	check("actual seed713 content13 prepares without funded fixture",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(prepared.capture);native.free()
	check("actual unfunded starting runtime assembles",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world;live_runtime=runtime
	var home:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:home")
	var workshop:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	var warehouse:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:village-warehouse")
	check("opening contains three original actors and no free construction boards",runtime.facts().actors.size()==3 and runtime.actor("player").pack.get("timber",0)==0 and runtime.stock(str(workshop.stock_refs.tools)).items.get("timber",0)==0)
	note(runtime,"actual untouched seed713 opening")
	if not take_source(runtime,str(home.stock_refs.values()[0]),{"food":3,"water":3,"cloth":1}):return finish()
	var axe:String=workshop.id+":tool:salvaged_axe";var saw:String=workshop.id+":tool:hand_saw";var hammer:String=workshop.id+":tool:hammer"
	if not take_source(runtime,str(workshop.stock_refs.tools),{"scrap":2,"book_woodwork":1},[axe,saw,hammer]):return finish()
	var studied:Dictionary=send(runtime,"study",workshop.id+":record:book_woodwork",{"direct":false})
	var completed:Dictionary=progress(runtime,300) if studied.ok else {}
	check("physically recovered manual teaches basic woodworking through paid study",studied.ok and completed.get("finished",false) and world.extension("r3:production").knowledge.get("player",[]).has("basic_woodwork"),studied.get("reason"))
	if not studied.ok or not completed.get("finished",false):return finish()
	if not search_source(runtime,str(workshop.stock_refs.input)):return finish()
	note(runtime,"tools recovered and woodworking studied")
	var trees:Array=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var harvested:Dictionary={};var rejections:Array=[]
	for tree:Dictionary in trees:
		if not care(runtime,45.0):return finish()
		var command:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[axe]})
		if not command.ok:
			rejections.append({"id":tree.id,"code":command.get("code"),"reason":command.get("reason")});continue
		completed=progress(runtime,1200)
		if completed.get("finished",false) and world.entity(tree.id).data.harvest.phase=="stump":harvested=world.entity(tree.id);break
		check("real approach and axe work finish after accepted harvest",false,diagnostic(runtime));return finish()
	check("original standing tree becomes stump and drops three finite logs",not harvested.is_empty() and runtime.stock(str(harvested.get("data",{}).get("outputId",""))).get("items",{}).get("log",0)==3,{"rejections":rejections.slice(0,8)})
	if harvested.is_empty():return finish()
	var drop:String=str(harvested.data.outputId)
	if not search_source(runtime,drop):return finish()
	note(runtime,"actual original tree harvested",harvested.id)
	var workers:Dictionary={}
	for index:int in 2:
		var created:Dictionary=send(runtime,"logistics.create","",{"source_id":drop,"destination_id":str(workshop.stock_refs.input),"items":{"log":1},"repeat":false,"priority":2-index})
		check("real finite-log haul task accepted %d"%(index+1),created.ok,created.get("reason"))
		if not created.ok:return finish()
	var transported:bool=false
	for step:int in 1800:
		runtime.tick(.1)
		for task:Dictionary in world.extension("r34:logistics").tasks:
			if not str(task.get("actor_id","")).is_empty():workers[str(task.actor_id)]=true
		transported=runtime.stock(str(workshop.stock_refs.input)).items.get("log",0)==2
		if transported:break
	check("both existing consenting companions physically deliver two original logs",transported and workers.has("village-resident") and workers.has("repair-resident"),{"workers":workers.keys(),"state":diagnostic(runtime) if not transported or workers.size()!=2 else {}})
	if not transported or workers.size()!=2:return finish()
	check("hauling conserves three original logs with no companion cargo left",runtime.stock(drop).items.get("log",0)==1 and runtime.actor("village-resident").pack.get("log",0)==0 and runtime.actor("repair-resident").pack.get("log",0)==0 and world.extension("r34:logistics").tasks.reduce(func(total:int,task:Dictionary)->int:return total+int(task.get("trips",0)),0)==2)
	note(runtime,"both original companions physically haul one log each",workers.keys())
	if not care(runtime,45.0) or not take_source(runtime,str(workshop.stock_refs.input),{"log":2}):return finish()
	for batch:int in 2:
		if not care(runtime,35.0):return finish()
		var crafted:Dictionary=send(runtime,"craft",str(workshop.config.workbench_id),{"direct":false,"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]})
		completed=progress(runtime,1000) if crafted.ok else {}
		check("actual manual saw batch %d completes"%(batch+1),crafted.ok and completed.get("finished",false),crafted.get("reason"))
		if not crafted.ok or not completed.get("finished",false):return finish()
	check("two real hand-sawn logs become exactly eight boards",runtime.actor("player").pack.get("log",0)==0 and runtime.actor("player").pack.get("timber",0)==8,runtime.actor("player").pack)
	note(runtime,"two logs hand-sawn into eight real boards")
	if not care(runtime,50.0):return finish()
	var ports:Array=ModuleShape.ports(warehouse,Catalog.definition(warehouse.definition_id)).filter(func(p:Dictionary)->bool:return p.purpose=="repair")
	check("existing damaged warehouse exposes physical repair point",ports.size()==1)
	if ports.size()!=1:return finish()
	var reached:Dictionary=walk(runtime,ports[0].location)
	check("player physically walks to original warehouse repair surface",reached.get("ok",false),reached.get("reason"))
	if not reached.get("ok",false):return finish()
	var stock_id:String=str(warehouse.stock_refs.storage)
	check("unrepaired original warehouse denies storage capacity",not runtime._services.production.capacity_check(stock_id,{"timber":1}).ok)
	var restored:Dictionary=send(runtime,"module.restore",warehouse.id,{"source_id":"pack:player","tool_id":hammer})
	check("real acquired boards scrap cloth and hammer start original-site repair",restored.ok,restored.get("reason"))
	if not restored.ok:return finish()
	completed=progress(runtime,500)
	var result:Dictionary=runtime._services.modules.instance(warehouse.id)
	check("normal clock completes paid original-site warehouse restoration",completed.get("finished",false) and result.get("restoration",{}).get("completed",false) and result.status=="operational",diagnostic(runtime) if not completed.get("finished",false) else result.get("restoration"))
	check("repair deducts exactly eight boards two scrap and one cloth",runtime.actor("player").pack.get("timber",0)==0 and runtime.actor("player").pack.get("scrap",0)==0 and runtime.actor("player").pack.get("cloth",0)==0,runtime.actor("player").pack)
	check("real restored warehouse now admits material storage",runtime._services.production.capacity_check(stock_id,{"timber":1}).ok)
	# Workforce observes module completions on the following sole fixed step.
	# Give the normal observer a bounded window; never write quest facts here.
	for observer_step:int in 5:
		if world.extension("r34:gameplay").flags.get("village_warehouse_restored",false):break
		runtime.tick(.1)
	var flags:Dictionary=world.extension("r34:gameplay").flags
	check("real events record harvesting handwork companion delivery and warehouse",flags.get("real_harvest",false) and flags.get("village_hand_sawn",false) and flags.get("village_companion_delivery",false) and flags.get("village_warehouse_restored",false),flags)
	var route_quests:Array=runtime.facts().quests.filter(func(q:Dictionary)->bool:return q.id in ["V3-Q02","V3-Q03"])
	check("actual first production and original warehouse quests complete from natural events",route_quests.size()==2 and route_quests.all(func(q:Dictionary)->bool:return q.get("completed",false)),route_quests)
	note(runtime,"natural old-village repair route completed")
	completed_route=true
	finish()

func finish()->void:
	check("complete natural village route reaches original-site restoration",completed_route)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"suite":"village-natural-route","seed":713,"content_version":13,"scope":"Actual Assembly.prepare opening; real walk/search/take/study/harvest/voluntary companion logistics/manual craft/paid original-site restore. No inventory, knowledge, actor, terrain or permission injection.","checks":checks,"failed":failed,"journey":journey}
	if live_runtime!=null:
		if failed>0:report.diagnostic=diagnostic(live_runtime)
		live_runtime.retire()
	DirAccess.make_dir_recursive_absolute(outdir)
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"suite":report.suite,"checks":checks.size(),"failed":failed,"output":outdir}))
	quit(1 if failed else 0)
