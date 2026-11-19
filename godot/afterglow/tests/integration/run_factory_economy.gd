extends "res://tests/world/factory_normal_path.gd"
## Formal normal content4: finite sources -> trees -> hand saw -> paid
## warehouse/woodshop -> two batches. No stock/actor/permission injection.
const ModuleShape=preload("res://scripts/modules/module_geometry.gd")
var journey:Array=[]
var outdir:String

func save_scene(runtime:RefCounted,label:String)->void:
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	if encoded.get("ok",false):
		var file:=FileAccess.open(outdir+"/"+label+".native.json",FileAccess.WRITE)
		file.store_string(encoded.text);file.close()

func note(runtime:RefCounted,stage:String,detail:Variant=null)->void:
	var player:Dictionary=runtime.actor("player")
	journey.append({"stage":stage,"clock":runtime.clock(),"location":Geometry.location(player),"hp":player.hp,"stamina":player.stamina,"fatigue":player.fatigue,"pack":player.pack.duplicate(true),"detail":detail})

func care(runtime:RefCounted,rest_below:float=40.0)->bool:
	for spec:Array in [["thirst","water","drink"],["hunger","food","eat"]]:
		var player:Dictionary=runtime.actor("player")
		if float(player[spec[0]])<40 and float(player.pack.get(spec[1],0))>=1:
			var action:Dictionary=send(runtime,spec[2])
			if not action.ok or not progress(runtime,30).finished:return false
	if float(runtime.actor("player").stamina)<rest_below:
		var action:Dictionary=send(runtime,"rest")
		if not action.ok or not progress(runtime,150).finished:return false
		note(runtime,"paid twelve-second rest")
	return true

func near_stock(runtime:RefCounted,id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	if stock.is_empty():return false
	if runtime._services.production.reach("player",id,stock,"search")==null:return true
	var points:Array=[stock.location.duplicate(true)]
	for offset:Vector2 in [Vector2(0,-1.2),Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,1.2)]:
		var point:Dictionary=stock.location.duplicate(true);point.x+=offset.x;point.z+=offset.y;points.append(point)
	for point:Dictionary in points:
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(point)
		if feet.is_empty():continue
		var reached:Dictionary=walk(runtime,feet)
		if reached.get("ok",false) and runtime._services.production.reach("player",id,runtime.stock(id),"search")==null:return true
	return false

func take_source(runtime:RefCounted,id:String,items:Dictionary,tools:Array=[])->bool:
	if not near_stock(runtime,id):check("actual body reaches finite source "+id,false);return false
	if not runtime.stock(id).get("searched",false):
		var search:Dictionary=send(runtime,"search",id)
		if not search.ok or not progress(runtime,80).finished:check("finite source search completes "+id,false,search);return false
	var taken:Dictionary=send(runtime,"take",id,{"items":items,"tool_ids":tools})
	check("actual searched source transfers selected finite contents "+id,taken.ok,taken.get("reason"))
	return taken.ok

func build_module(runtime:RefCounted,definition:String,id:String,hammer:String)->Dictionary:
	if not care(runtime,70.0):return {}
	var choice:Dictionary={};var tried:Dictionary={}
	for z:int in range(10,57,2):
		for x:int in range(18,57,2):
			var position:Dictionary={"x":float(x),"y":runtime.world.surface_height(x,z),"z":float(z),"regionId":"RH-HOME"}
			var request:Dictionary={"kind":"module.plan","actor_id":"player","command_id":id+":plan","target_id":id,"payload":{"definition_id":definition,"position":position,"quarter_turn":0,"source_id":"pack:player","tool_id":hammer}}
			var preview:Dictionary=runtime._services.modules.preview(request)
			if not preview.ok:
				tried[preview.get("code","unknown")]=int(tried.get(preview.get("code","unknown"),0))+1;continue
			for port:Dictionary in preview.ports:
				if port.purpose not in ["work","repair","input","service"]:continue
				var route:Dictionary=runtime._services.actions.route("player",Geometry.location(runtime.actor("player")),port.location)
				if route.ok:choice={"request":request,"port":port.location};break
			if not choice.is_empty():break
		if not choice.is_empty():break
	check("real generated unmodified land admits supported module "+definition,not choice.is_empty(),tried)
	if choice.is_empty():return {}
	var walked:Dictionary=walk(runtime,choice.port)
	check("builder actually walks to legal module work surface",walked.get("ok",false),walked.get("reason"))
	if not walked.get("ok",false):return {}
	var planned:Dictionary=runtime.command(choice.request)
	check("finite normal resources reserve a real complete module",planned.ok,planned.get("reason"))
	if not planned.ok:return {}
	var completed:Dictionary=progress(runtime,1200)
	var module:Dictionary=runtime._services.modules.instance(id)
	check("normal held construction completes by sole fixed clock",completed.finished and module.get("status")=="operational",{"actor":runtime.actor("player").get("intent"),"project":runtime._services.modules.state().projects[-1]})
	if not completed.finished or module.get("status")!="operational":return {}
	note(runtime,"built "+definition,{"id":id,"position":module.position})
	return module

func recruit(runtime:RefCounted,id:String)->bool:
	var approached:bool=false
	for attempt:int in 16:
		var ready:Dictionary=runtime.availability({"kind":"talk","actor_id":"player","target_id":id})
		if ready.get("ok",false):approached=true;break
		var other:Dictionary=runtime.actor(id);var point:Dictionary=Geometry.location(other);point.x+=0.9
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(point)
		if feet.is_empty():continue
		walk(runtime,feet)
	check("player actually approaches original living NPC "+id,approached)
	if not approached:return false
	var talked:Dictionary=send(runtime,"talk",id)
	var helped:Dictionary=send(runtime,"help",id,{"items":{"food":1}})
	var invited:Dictionary=send(runtime,"invite",id) if helped.ok else helped
	check("finite food and real hammer enable voluntary cooperation "+id,talked.ok and helped.ok and invited.ok and runtime.actor(id).relationship.get("member",false) and runtime.actor(id).relationship.get("consent",false),{"talk":talked.get("reason"),"help":helped.get("reason"),"invite":invited.get("reason")})
	return invited.ok

func run()->void:
	outdir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(outdir)
	var locked:Dictionary=Contract.fresh(Modules.generation_profiles(),4,1)
	var opening:Dictionary=normal_tools(locked.contract)
	if not opening.ok:return finish()
	var runtime:RefCounted=opening.runtime;var world:RefCounted=opening.world
	note(runtime,"actual normal three-person opening; original tools recovered")
	if not take_source(runtime,opening.yard_stock,{"scrap":4,"r34:salvaged_drive_unit":1}):return finish()
	var workshop:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	var saw:String=workshop.id+":tool:hand_saw";var hammer:String=workshop.id+":tool:hammer"
	if not take_source(runtime,opening.tool_stock,{"timber":8,"scrap":6,"book_woodwork":1},[saw,hammer]):return finish()
	var study:Dictionary=send(runtime,"study",workshop.id+":record:book_woodwork",{"direct":false})
	var studied:Dictionary=progress(runtime,200) if study.ok else {}
	check("physical recovered book teaches through real twelve-second study",study.ok and studied.get("finished",false) and world.extension("r3:production").knowledge.get("player",[]).has("basic_woodwork"),study.get("reason"))
	if not study.ok or not studied.get("finished",false):return finish()
	var home:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:home")
	if not take_source(runtime,str(home.stock_refs.values()[0]),{"timber":2,"scrap":1}):return finish()
	var store:Dictionary=runtime._services.modules.instance("r34:generated:RH-VILLAGE:store")
	if not take_source(runtime,str(store.stock_refs.values()[0]),{"scrap":3,"food":2,"water":2}):return finish()
	check("all fourteen scrap and ten seed boards have actual finite sources",runtime.actor("player").pack.scrap==14 and runtime.actor("player").pack.timber==10 and runtime.actor("player").pack["r34:salvaged_drive_unit"]==1)
	var trees:Array=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var felled:int=0
	for tree:Dictionary in trees:
		if felled>=3:break
		if not care(runtime,45.0):return finish()
		if felled==0:save_scene(runtime,"actual-before-first-tree")
		var harvest:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[opening.axe]})
		if not harvest.ok:journey.append({"stage":"tree route rejected","id":tree.id,"code":harvest.get("code"),"reason":harvest.get("reason")});continue
		var completed:Dictionary=progress(runtime,1000)
		var stump:bool=world.entity(tree.id).data.harvest.phase=="stump"
		check("real generated tree fells with actual old axe",completed.finished and stump,{"progress":completed,"tree":world.entity(tree.id),"orders":world.extension("r3:production").get("orders",[]),"events":runtime.facts().get("events",[])})
		if not completed.finished or not stump:save_scene(runtime,"actual-failed-first-tree");return finish()
		if not take_source(runtime,str(tree.data.outputId),{"log":3}):return finish()
		felled+=1;note(runtime,"harvested actual tree",tree.id)
	check("three finite generated trees yield nine actual logs",felled==3 and runtime.actor("player").pack.get("log",0)==9)
	if felled!=3:return finish()
	var station:String=str(workshop.config.workbench_id)
	for batch:int in 6:
		if not care(runtime,30.0):return finish()
		var crafted:Dictionary=send(runtime,"craft",station,{"direct":false,"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]})
		var completed:Dictionary=progress(runtime,1000) if crafted.ok else {}
		check("normal finite hand saw batch %d completes"%(batch+1),crafted.ok and completed.get("finished",false),crafted.get("reason") if not crafted.ok else runtime.actor("player").get("intent"))
		if not crafted.ok or not completed.get("finished",false):return finish()
	check("six hand batches consume six logs and create twenty-four boards",runtime.actor("player").pack.get("log",0)==3 and runtime.actor("player").pack.timber==34 and is_equal_approx(float(runtime.tool(saw).durability),88.0),{"pack":runtime.actor("player").pack,"saw_durability":runtime.tool(saw).durability})
	note(runtime,"six manual batches paid by real labor and durability")
	var storage:Dictionary=build_module(runtime,"r34.module.warehouse_long_v2","r34:normal-built-warehouse",hammer)
	if storage.is_empty():return finish()
	var machine:Dictionary=build_module(runtime,"r34.module.woodshop_long_v2","r34:normal-built-woodshop",hammer)
	if machine.is_empty():return finish()
	check("both paid normal modules leave exact two boards two scrap and no extra drive",runtime.actor("player").pack.timber==2 and runtime.actor("player").pack.scrap==2 and runtime.actor("player").pack["r34:salvaged_drive_unit"]==0)
	for spec:Array in [["input",2],["fuel",1]]:
		var stock_id:String=str(machine.stock_refs[spec[0]])
		var reached:bool=near_stock(runtime,stock_id)
		var deposit:Dictionary=send(runtime,"deposit",stock_id,{"items":{"log":spec[1]}}) if reached else {"ok":false,"reason":"service point unreachable"}
		check("actual player supplies machine "+str(spec[0])+" from final three logs",deposit.ok,deposit.get("reason"))
		if not deposit.ok:return finish()
	var configured:Dictionary=send(runtime,"factory.configure",machine.id,{"recipe_id":"saw_timber","batches":2})
	check("real constructed machine accepts two batches",configured.ok,configured.get("reason"))
	if not configured.ok:return finish()
	for step:int in 400:
		runtime.tick(0.1)
		if runtime.stock(machine.stock_refs.output).items.get("timber",0)==8:break
	var production:Dictionary=runtime.factory_snapshot().production
	check("normal two autonomous batches create exactly eight boards",production.batches.filter(func(b:Dictionary)->bool:return b.module_id==machine.id and b.status=="completed").size()==2 and runtime.stock(machine.stock_refs.output).items.get("timber",0)==8,production.orders)
	check("machine uses two actual feed logs plus one actual fuel log",runtime.actor("player").pack.log==0 and runtime.stock(machine.stock_refs.input).items.log==0 and runtime.stock(machine.stock_refs.fuel).items.log==0)
	note(runtime,"normal paid production chain reaches two settled batches")
	for id:String in ["village-resident","repair-resident"]:
		if not recruit(runtime,id):return finish()
	var home_walk:Dictionary=walk(runtime,runtime.world.extension("r34:gameplay").layout.home)
	check("original player walks home with both invited companions",home_walk.get("ok",false),home_walk.get("reason"))
	if not home_walk.get("ok",false):return finish()
	var arrived:bool=false
	for step:int in 900:
		runtime.tick(0.1)
		arrived=["village-resident","repair-resident"].all(func(id:String)->bool:return Geometry.point(runtime.actor(id)).distance_to(Geometry.point(runtime.world.extension("r34:gameplay").layout.home))<5.0 or runtime.actor(id).relationship.get("home_arrived",false))
		if arrived:break
	check("both real original companions physically return before work",arrived)
	if not arrived:return finish()
	var destination:String=str(storage.stock_refs.storage)
	for queue:int in 2:
		var created:Dictionary=send(runtime,"logistics.create","",{"source_id":str(machine.stock_refs.output),"destination_id":destination,"items":{"timber":2},"repeat":true,"priority":2-queue})
		check("normal logistics queues original physical output without moving goods",created.ok,created.get("reason"))
		if not created.ok:return finish()
	var actual_workers:Dictionary={};var transported:bool=false
	for step:int in 1500:
		runtime.tick(0.1)
		for task:Dictionary in runtime.world.extension("r34:logistics").tasks:
			if not str(task.actor_id).is_empty():actual_workers[str(task.actor_id)]=true
		transported=runtime.stock(destination).items.get("timber",0)==8 and runtime.stock(machine.stock_refs.output).items.get("timber",0)==0
		if transported:break
	check("two consenting original NPCs physically execute repeated hauling",transported and actual_workers.has("village-resident") and actual_workers.has("repair-resident"),{"workers":actual_workers.keys(),"tasks":runtime.world.extension("r34:logistics").tasks,"destination":runtime.stock(destination),"people":runtime.factory_snapshot().workforce.people})
	if not transported:return finish()
	check("repeat trips conserve all eight output boards without phantom cargo",runtime.actor("village-resident").pack.get("timber",0)==0 and runtime.actor("repair-resident").pack.get("timber",0)==0 and runtime.world.extension("r34:logistics").tasks.reduce(func(total:int,task:Dictionary)->int:return total+int(task.trips),0)==4)
	note(runtime,"two voluntary original NPCs finish four physical two-board trips")
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("whole actual economy cold-restores exact stocks tools modules and settlements",restored.get("ok",false) and Data.json_equal(restored.runtime.actor("player").pack,runtime.actor("player").pack) and restored.runtime.stock(destination).items.get("timber",0)==8 and restored.runtime._services.modules.instance(storage.id).status=="operational" and Data.json_equal(restored.world.extension("r34:logistics"),runtime.world.extension("r34:logistics")),restored.get("reason"))
	if encoded.ok:FileAccess.open(outdir+"/actual-normal-economy.native.json",FileAccess.WRITE).store_string(encoded.text)
	finish()

func finish()->void:
	if outdir.is_empty():outdir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(outdir)
	var report:Dictionary={"scope":"actual normal content3 finite economy, physical commands, voluntary original NPC hauling and sole clock; no actor/item/permission injection; not GUI/OS/VA/final package acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"journey":journey}
	var file:=FileAccess.open(outdir+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
