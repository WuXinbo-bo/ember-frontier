extends "res://tests/integration/chapter20_supply_journey.gd"
## Ordinary opening through paid restoration, actual production and transmission.
const ChapterAssembly=preload("res://scripts/runtime/factory_assembly.gd")
const ChapterOpening=preload("res://scripts/runtime/playtest_profile.gd")
const ChapterVillage=preload("res://scripts/runtime/village_progression.gd")
const ChapterShape=preload("res://scripts/modules/module_geometry.gd")
const ChapterData=preload("res://scripts/world/world_data.gd")
const YARD="RH-HOME:stockyard-content:container"
const HOME20="r34:generated:RH-HOME:home"
const BENCH20="r34:generated:RH-HOME:woodwork"
const STORE20="r34:generated:RH-HOME:village-warehouse"
const MILL20="RH-HOME:woodshop-old-frame"
var chapter_runtime:RefCounted
var chapter_host:Node
var seed20:int=713
var content_version:int=20
var started20:int

func run()->void:
	started20=Time.get_ticks_msec()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):seed20=int(arg.trim_prefix("--seed="))
		if arg=="--content=21":content_version=21
	var profiles:=ChapterAssembly.generation_profiles(content_version)
	var opening:=ChapterAssembly.prepare(ChapterAssembly.generate(seed20,profiles.profiles,content_version))
	check("content %d opens from ordinary generation" % content_version,opening.ok,opening.get("code"))
	if not opening.ok:return finish()
	chapter_host=Native.new()
	var built:Dictionary=chapter_host._assemble(ChapterOpening.prepare_opening(opening.capture,"normal"))
	check("normal opening assembles",built.ok,built.get("reason"))
	if not built.ok:return finish()
	chapter_runtime=built.runtime
	var opening_village: Dictionary = chapter_runtime.hud_snapshot().village
	check("HUD projection starts from canonical quest and radio state", opening_village == ChapterVillage.snapshot(chapter_runtime.facts(),chapter_runtime.world))
	opening_village.radio.status="mutated test copy"
	check("HUD projection returns detached nested radio data", chapter_runtime.hud_snapshot().village.radio.status != opening_village.radio.status)
	var result := play_chapter(chapter_runtime)
	check("ordinary resources and commands finish the chapter",result)
	if content_version == 21 and result:
		for kind: String in ["salvaged_axe","hammer","hand_saw"]:
			var tool: Dictionary = chapter_runtime.tool(BENCH20+":tool:"+kind)
			check("used %s never wears" % kind, float(tool.get("durability",0)) == 100.0, tool)
	finish()

func play_chapter(runtime:RefCounted)->bool:
	var workshop:Dictionary=runtime._services.modules.instance(BENCH20)
	var station:String=str(workshop.config.workbench_id)
	var saw:String=BENCH20+":tool:hand_saw";var hammer:String=BENCH20+":tool:hammer"
	var axe:String=BENCH20+":tool:salvaged_axe";var tools:String=str(workshop.stock_refs.tools)
	if not take_source(runtime,tools,{"book_woodwork":1,"book_tool_repair":1,"scrap":2},[saw,hammer]):return false
	for record:String in ["book_woodwork","book_tool_repair"]:
		if not complete15(runtime,"study",BENCH20+":record:"+record,{"direct":false}):return false
	if not take_source(runtime,YARD,{"scrap":12,"cloth":4,"tool_handle":1,"r34:salvaged_drive_unit":1}):return false
	var home:Dictionary=runtime._services.modules.instance(HOME20)
	if not take_source(runtime,str(home.stock_refs.values()[0]),{"food":3,"water":4}):return false
	var wood:Dictionary=runtime.stock(str(workshop.stock_refs.tools))
	var lumber:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	var origin:=Geometry.point(Geometry.location(runtime.actor("player")))
	lumber.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return origin.distance_squared_to(Geometry.point(a.position))<origin.distance_squared_to(Geometry.point(b.position)))
	var felled:int=0
	for tree:Dictionary in lumber:
		if felled>=5:break
		if not care(runtime,45):return false
		var started:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[axe]})
		if not started.ok:continue
		if not progress(runtime,1200).finished or runtime.world.entity(tree.id).data.harvest.phase!="stump":continue
		var output_id:String=str(tree.data.outputId)
		var logs:float=float(runtime.stock(output_id).get("items",{}).get("log",0))
		if logs<=0 or not take_source(runtime,output_id,{"log":logs}):return false
		felled+=1
	check("nearby trees fund actual work and fuel",float(runtime.actor("player").pack.get("log",0))>=11,felled)
	if float(runtime.actor("player").pack.get("log",0))<11:return false
	for i:int in 6:
		if not complete15(runtime,"craft",station,{"direct":false,"recipe_id":"r34:saw_timber_v2","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]}):return false
	for id:String in [HOME20,STORE20]:
		if not restore20(runtime,id,hammer):return false
	var village:Dictionary=runtime.chapter_stock_snapshot()
	check("stock view is available without including the player pack",village.available and village.rows.all(func(row:Dictionary)->bool:return row.sources.all(func(source:Dictionary)->bool:return source.id!="pack:player") and is_equal_approx(float(row.total),float(row.available)+float(row.reserved)+float(row.protected))))
	if not supply20(runtime):return false
	if float(runtime.actor("player").pack.get("scrap",0))<12:
		var left:Dictionary=runtime.stock(str(wood.id)).items
		var need:float=minf(float(left.get("scrap",0)),12.0-float(runtime.actor("player").pack.get("scrap",0)))
		if need>0 and not take_source(runtime,str(wood.id),{"scrap":need}):return false
	if not restore20(runtime,MILL20,hammer):return false
	var mill:Dictionary=runtime._services.modules.instance(MILL20)
	for buffer:String in ["input","fuel"]:
		var endpoint:String=str(mill.stock_refs[buffer])
		if not near_stock(runtime,endpoint):return false
		var put:Dictionary=send(runtime,"deposit",endpoint,{"items":{"log":1}})
		check("real log enters mill "+buffer,put.ok,put.get("reason"))
		if not put.ok:return false
	var order:Dictionary=send(runtime,"factory.configure",MILL20,{"recipe_id":"saw_timber","batches":1})
	check("restored mill accepts an actual order",order.ok,order.get("reason"))
	if not order.ok:return false
	for tick_index:int in 250:
		runtime.tick(.1)
		if float(runtime.stock(mill.stock_refs.output).items.get("timber",0))>=4:break
	var output:Dictionary=runtime.stock(mill.stock_refs.output).items
	check("the restored mill settles four real boards",float(output.get("timber",0))==4,runtime.world.extension("r34:production").get("orders",[]))
	# Production settles after the gameplay observer in the single clock step.
	runtime.tick(.1)
	var missing:=ChapterVillage.radio_missing(runtime.world.extension("r34:gameplay"))
	check("all true progress reaches the radio gate",missing.is_empty(),missing)
	if not missing.is_empty():return false
	for point:Dictionary in runtime._services.buildings.current_space().use_points(runtime._services.buildings.instance(station)):
		if walk(runtime,point).ok:break
	if not complete15(runtime,"radio",station,{"operation":"repair","tool_id":hammer},500):return false
	check("HUD projection follows actual workshop, tool and radio repair changes", runtime.hud_snapshot().village == ChapterVillage.snapshot(runtime.facts(),runtime.world))
	if not complete15(runtime,"radio",station,{"operation":"transmit"},550):return false
	var chapter:Dictionary=ChapterVillage.snapshot(runtime.facts(),runtime.world).chapter_one
	var display: Dictionary = runtime.snapshot()
	check("HUD and full display both publish the new radio and quest recap", runtime.hud_snapshot().village.chapter_one == chapter and display.village.chapter_one == chapter)
	check("factory layout without a legacy home id still publishes gather targets", display.work_targets.any(func(row: Dictionary) -> bool: return row.get("job") == "gather"))
	check("chapter recap comes from actual settled milestones",chapter.completed and chapter.summary.size()==5 and float(chapter.signal_at)>0,chapter)
	var data:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(data.get("text","")) if data.ok else data
	if not decoded.ok:return false
	var reopened:Dictionary=chapter_host._assemble(decoded.capture)
	if not reopened.ok:return false
	var saved:Dictionary=ChapterVillage.snapshot(reopened.runtime.facts(),reopened.world).chapter_one
	check("HUD projection reads loaded chapter state", reopened.runtime.hud_snapshot().village.chapter_one == saved)
	var persisted:bool=saved.completed and saved.signal_at==chapter.signal_at
	check("chapter recap survives a real cold mount",persisted,saved)
	var delivered:bool=persisted and carry_save20(reopened.runtime,str(mill.stock_refs.output))
	reopened.runtime.retire()
	return delivered

func carry_save20(runtime:RefCounted,source:String)->bool:
	var warehouse:Dictionary=runtime._services.modules.instance(STORE20)
	var destination:String=str(warehouse.stock_refs.storage)
	var original_source:float=timber20(runtime.stock(source))
	var original_destination:float=timber20(runtime.stock(destination))
	var before_ids:Array=runtime.world.extension("r34:logistics").tasks.map(func(row:Dictionary)->String:return row.id)
	var create:Dictionary=send(runtime,"logistics.create","",{"source_id":source,"destination_id":destination,"items":{"timber":1},"repeat":false})
	var queued:bool=create.ok and timber20(runtime.stock(source))==original_source and timber20(runtime.stock(destination))==original_destination
	check("normal logistics queues one machine board without moving it",queued,create)
	if not queued:return false
	var tasks:Array=runtime.world.extension("r34:logistics").tasks.filter(func(row:Dictionary)->bool:return not before_ids.has(row.id))
	check("exactly one new transport task is created",tasks.size()==1,tasks)
	if tasks.size()!=1:return false
	var id:String=str(tasks[0].id)
	var task:Dictionary={}
	for tick_index:int in 1200:
		runtime.tick(.1)
		task=haul20(runtime,id)
		if task.get("phase")=="deliver" and not str(task.get("actor_id","")).is_empty():break
	var carrier:String=str(task.get("actor_id",""))
	var picked:bool=carrier in ["village-resident","repair-resident"] and task.get("phase")=="deliver" and task.get("trips")==0 and timber20(runtime.stock("pack:"+carrier))==1 and timber20(runtime.stock(source))==original_source-1 and timber20(runtime.stock(destination))==original_destination
	check("a real opening companion has physically picked up the board",picked,task)
	if not picked:return false
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.get("text","")) if encoded.ok else encoded
	var reopened:Dictionary=chapter_host._assemble(decoded.capture) if decoded.ok else decoded
	check("mid-carry native save cold mounts with the original task",reopened.ok,reopened.get("code"))
	if not reopened.ok:return false
	var restored:RefCounted=reopened.runtime
	var loaded:Dictionary=haul20(restored,id)
	var prior_experience:int=int(restored.actor(carrier).get("skills",{}).get("village_hauling",0))
	var actual:Array=[timber20(restored.stock("pack:"+carrier)),timber20(restored.stock(source)),timber20(restored.stock(destination))]
	var expected:Array=[1.0,original_source-1,original_destination]
	var preserved:bool=ChapterData.json_equal(loaded,task) and actual==expected
	check("cold mount preserves companion cargo without an early delivery",preserved,{"task":loaded,"actual_timber":actual,"expected_timber":expected})
	if preserved:
		for tick_index:int in 1200:
			restored.tick(.1)
			if haul20(restored,id).get("status")=="completed":break
		for tick_index:int in 20:restored.tick(.1)
	var done:Dictionary=haul20(restored,id)
	var reserved:bool=restored.world.extension("r34:logistics").reservations.any(func(row:Dictionary)->bool:return row.task_id==id)
	var exactly_once:bool=preserved and done.get("status")=="completed" and done.get("trips")==1 and timber20(restored.stock("pack:"+carrier))==0 and timber20(restored.stock(source))==original_source-1 and timber20(restored.stock(destination))==original_destination+1 and not reserved
	check("restored companion delivers the same board exactly once and releases reservations",exactly_once,done)
	var experience:int=int(restored.actor(carrier).get("skills",{}).get("village_hauling",0))
	var gained:bool=experience==prior_experience+1
	check("completed physical delivery grows the carrier's hauling experience once",gained,[prior_experience,experience])
	var finished_save:Dictionary=Store.encode(restored.capture_checkpoint())
	var finished_data:Dictionary=Store.decode(finished_save.get("text","")) if finished_save.ok else finished_save
	var finished:Dictionary=chapter_host._assemble(finished_data.capture) if finished_data.ok else finished_data
	var persistent:bool=false
	if finished.ok:
		var loaded_runtime:RefCounted=finished.runtime
		for tick_index:int in 20:loaded_runtime.tick(.1)
		persistent=int(loaded_runtime.actor(carrier).get("skills",{}).get("village_hauling",0))==experience
		loaded_runtime.retire()
	check("world reload preserves hauling experience without paying the same receipt again",persistent,finished.get("code"))
	restored.retire()
	return exactly_once and gained and persistent

func timber20(stock:Dictionary)->float:
	return float(stock.get("items",{}).get("timber",0))

func haul20(runtime:RefCounted,id:String)->Dictionary:
	for task:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if task.id==id:return task
	return {}

func restore20(runtime:RefCounted,id:String,hammer:String)->bool:
	var building:Dictionary=runtime._services.modules.instance(id)
	var ports:Array=ChapterShape.ports(building,Catalog.definition(building.definition_id))
	var reached:bool=false
	for port:Dictionary in ports:
		if port.purpose not in ["repair","service","work"]:continue
		if walk(runtime,port.location).ok:reached=true;break
	check("original building has a physically accessible repair face "+id,reached)
	if not reached:return false
	if not complete15(runtime,"module.restore",id,{"source_id":"pack:player","tool_id":hammer},1500):return false
	var restored:Dictionary=runtime._services.modules.instance(id)
	check("original building is physically restored "+id,restored.status=="operational",restored.get("restoration"))
	return restored.status=="operational"

func finish()->void:
	var failures:Array=checks.filter(func(result:Dictionary)->bool:return not result.ok)
	for item:Dictionary in failures:print("FAIL ",item)
	print("CHAPTER20_JOURNEY seed=",seed20," ",checks.size()-failures.size(),"/",checks.size()," wall_ms=",Time.get_ticks_msec()-started20)
	if chapter_runtime!=null:chapter_runtime.retire()
	if is_instance_valid(chapter_host):chapter_host.free()
	quit(0 if failures.is_empty() else 1)
