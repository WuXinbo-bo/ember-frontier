extends "res://tests/integration/run_village_supply15.gd"
## One untouched normal16 world: finite recovery -> tree -> boards -> home.
var finished16:bool=false
var restored_home16:String="r34:generated:RH-HOME:home"
var content_version:int=16

func home_project16(runtime:RefCounted)->Dictionary:
	var home:Dictionary=runtime._services.modules.instance(restored_home16)
	var opening_box:AABB=ModuleShape.transform_box(home,Geometry.aabb(runtime._services.modules.definition(home.definition_id).footprint))
	check("new16 idle companions start outside home construction footprint",["repair-resident","village-resident"].all(func(id:String)->bool:return not opening_box.intersects(AABB(Geometry.point(Geometry.location(runtime.actor(id)))-Vector3(.26,0,.26),Vector3(.52,1.8,.52)))))
	for project:Dictionary in runtime.world.extension("r34:modules").projects:
		if project.id==home.get("project_id",""):return project
	return {}

func run()->void:
	wall_start15=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args();outdir=args[0] if not args.is_empty() else "user://natural-opening16"
	DirAccess.make_dir_recursive_absolute(outdir)
	if args.has("--compact"):content_version=17
	var profiles:Dictionary=Assembly.generation_profiles(content_version)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[]),content_version))
	check("untouched finite world prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var opening:Dictionary=Profile15.prepare_opening(prepared.capture,"normal")
	var host:=Native.new();var built:Dictionary=host._assemble(opening);host.free()
	check("normal16 mounts through original native authority",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;live15=runtime
	workshop15=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	axe15=str(opening.source.opening_configuration.tools.salvaged_axe)
	saw15=workshop15.id+":tool:hand_saw";hammer15=workshop15.id+":tool:hammer"
	var home:Dictionary=runtime._services.modules.instance(restored_home16)
	check("one original axe and finite food-water start without free boards",runtime.tool(axe15).holderId=="pack:player" and runtime.actor("player").pack.get("timber",0)==0 and runtime.actor("player").pack.get("food",0)==1 and runtime.actor("player").pack.get("water",0)==1)
	note(runtime,"untouched normal16 spawn")
	if not take_source(runtime,str(home.stock_refs.values()[0]),{"food":2,"water":2}):return finish()
	if not take_source(runtime,str(workshop15.stock_refs.tools),{"scrap":1,"book_woodwork":1},[saw15,hammer15]):return finish()
	check("actual searched workshop transfers original saw and hammer without boards",runtime.tool(saw15).holderId=="pack:player" and runtime.tool(hammer15).holderId=="pack:player" and runtime.actor("player").pack.get("timber",0)==0)
	if not complete15(runtime,"study",workshop15.id+":record:book_woodwork",{"direct":false}):return finish()
	check("physically recovered record teaches original basic woodworking",runtime.world.extension("r3:production").knowledge.get("player",[]).has("basic_woodwork"))
	note(runtime,"finite original tools and knowledge recovered")
	var before_axe:float=float(runtime.tool(axe15).durability)
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("kind")=="tree" and e.get("data",{}).get("harvest",{}).get("phase")=="standing" and float(e.data.harvest.seconds)==3.0)
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var selected:Dictionary={};var receipt:Dictionary={}
	for tree:Dictionary in trees:
		receipt=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[axe15]})
		if receipt.ok:selected=tree;break
	check("same new16 player finds actual route to original small tree",not selected.is_empty(),receipt)
	if selected.is_empty():return finish()
	var harvest_done:Dictionary=progress(runtime,1500)
	var orders:Array=runtime.world.extension("r3:production").orders.filter(func(o:Dictionary)->bool:return o.targetId==selected.id)
	check("same small tree completes exactly three seconds of real labor",harvest_done.get("finished",false) and orders.size()==1 and orders[0].status=="completed" and is_equal_approx(float(orders[0].duration),3) and is_equal_approx(float(orders[0].elapsed),3),orders)
	if not harvest_done.get("finished",false):return finish()
	check("half-time harvest retains original total axe wear",is_equal_approx(float(runtime.tool(axe15).durability),before_axe-3))
	if not take_source(runtime,str(selected.data.outputId),{"log":3}):return finish()
	check("same finite tree gives three physically collected logs",runtime.actor("player").pack.get("log",0)==3 and runtime.stock(selected.data.outputId).items.get("log",0)==0)
	for batch:int in 2:
		if not craft15(runtime,"r34:saw_timber_v2"):return finish()
	check("two original hand-saw batches supply eight boards from two logs",runtime.actor("player").pack.get("timber",0)==8 and runtime.actor("player").pack.get("log",0)==1)
	note(runtime,"same-tree boards produced at original hand workshop")
	save_scene(runtime,"actual16-ready-home-restore")
	var pack_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	var hammer_before:float=float(runtime.tool(hammer15).durability)
	var start:Dictionary=send(runtime,"module.restore",restored_home16,{})
	check("empty-payload home restore starts through original command authority",start.ok,start)
	if not start.ok:return finish()
	check("one click automatically approaches with original pack and hammer reserved",runtime.actor("player").intent.kind=="module_approach" and runtime.actor("player").pack==pack_before and home_project16(runtime).progress_seconds==0)
	var max_step:float=0
	for step:int in 500:
		var previous:Vector3=Geometry.point(Geometry.location(runtime.actor("player")))
		runtime.tick(.1)
		max_step=maxf(max_step,previous.distance_to(Geometry.point(Geometry.location(runtime.actor("player")))))
		if home_project16(runtime).get("status")=="completed":break
		if runtime.actor("player").get("intent")==null:break
	var project:Dictionary=home_project16(runtime)
	check("actual home restoration finishes eighteen seconds at a real work port",project.get("status")=="completed" and is_equal_approx(float(project.get("progress_seconds",0)),18),project)
	check("automatic approach retains ordinary physical movement",max_step>0 and max_step<1,max_step)
	check("same-tree boards pay one original six-board one-scrap home cost",runtime.actor("player").pack.get("timber",0)==pack_before.get("timber",0)-6 and runtime.actor("player").pack.get("scrap",0)==pack_before.get("scrap",0)-1 and runtime.actor("player").pack.get("log",0)==1)
	check("original recovered hammer pays exactly eighteen seconds of wear",is_equal_approx(float(runtime.tool(hammer15).durability),hammer_before-18*.15))
	note(runtime,"same finite opening restores original home",project)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("same natural16 journey uses original checksummed cold storage",encoded.get("ok",false) and decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var cold_host:=Native.new();var restored:Dictionary=cold_host._assemble(decoded.capture);cold_host.free()
	check("same natural16 journey cold-mounts original domains",restored.get("ok",false),restored.get("reason"))
	if not restored.get("ok",false):return finish()
	var cold_runtime:RefCounted=restored.runtime
	check("cold mount retains completed original project and exact paid pack",Data.json_equal(cold_runtime.actor("player").pack,runtime.actor("player").pack) and Data.json_equal(home_project16(cold_runtime),project) and is_equal_approx(float(cold_runtime.tool(hammer15).durability),float(runtime.tool(hammer15).durability)))
	var repeat:Dictionary=send(cold_runtime,"module.restore",restored_home16,{})
	check("cold completed home cannot consume a second repair cost",not repeat.ok and repeat.get("code")=="MODULE_NOT_RESTORABLE" and Data.json_equal(cold_runtime.actor("player").pack,runtime.actor("player").pack),repeat)
	cold_runtime.retire()
	finished16=project.get("status")=="completed"
	save_scene(runtime,"actual16-restored-home")
	finish()

func finish()->void:
	check("continuous unfunded normal16 opening-to-restored-home route finishes",finished16)
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var report:Dictionary={"suite":"village-natural-opening%d"%content_version,"seed":713,"content_version":content_version,"checks":checks,"failed":failed,"journey":journey,"wall_ms":Time.get_ticks_msec()-wall_start15,"scope":"Untouched normal opening, finite tools and record, one three-second tree, two hand-saw batches, paid home restoration and checksummed cold mount. Headless; not GUI/FPS acceptance."}
	if live15!=null:
		report.final_player=live15.actor("player");report.final_flags=live15.world.extension("r34:gameplay").flags
		save_scene(live15,"actual16-final-natural-opening");live15.retire()
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"suite":report.suite,"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
