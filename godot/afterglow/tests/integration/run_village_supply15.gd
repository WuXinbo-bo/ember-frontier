extends "res://tests/integration/run_factory_economy.gd"
## Unfunded new15. Commands, sole normal clock, original sources and real feet.
const Profile15=preload("res://scripts/runtime/playtest_profile.gd")
const Rules15=preload("res://scripts/ecology/ecology_rules.gd")
const OpeningSources15=preload("res://scripts/world/factory_zone_production.gd")
var live15:RefCounted
var finished15:bool=false
var wall_start15:int=0
var plant15:String=""
var field15:String="supply15:potato-field"
var water15:String="supply15:raw-water"
var workshop15:Dictionary={}
var axe15:String=""
var saw15:String=""
var hammer15:String=""
var command_prefix15:String="natural15:"+str(Time.get_unix_time_from_system())+":"+str(OS.get_process_id())
var last_command15:String=""

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1;last_command15=command_prefix15+":"+str(sequence)
	return runtime.command({"command_id":last_command15,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})

func note(runtime:RefCounted,stage:String,detail:Variant=null)->void:
	super.note(runtime,stage,detail)
	print(JSON.stringify({"stage":stage,"clock":runtime.clock(),"wall_ms":Time.get_ticks_msec()-wall_start15}))
func complete15(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},limit:int=1500)->bool:
	if not care(runtime,40):check("real needs permit "+kind,false);return false
	var receipt:Dictionary=send(runtime,kind,target,payload)
	var actual_id:String=last_command15
	var done:Dictionary=progress(runtime,limit) if receipt.ok else {}
	var settled:bool=receipt.ok and done.get("finished",false)
	if settled and kind in ["craft","study"]:
		settled=runtime.world.extension("r3:production").get("orders",[]).any(func(order:Dictionary)->bool:return order.id==actual_id+":order" and order.status=="completed")
	if settled and kind=="zonework.start":
		var state:Dictionary=runtime.world.extension("r34:zonework");var rows:Array=state.get("receipts",[]).duplicate(true)
		rows.append_array(state.get("jobs",{}).values())
		settled=rows.any(func(job:Dictionary)->bool:return job.id==actual_id and job.status=="completed")
	check("real command completes "+kind+" "+str(payload.get("recipe_id",target)),settled,receipt.get("reason"))
	# Story observes the original production commit on its following fixed
	# STEP; do not demand a second owner settles in the producer's STEP.
	if receipt.ok and done.get("finished",false):runtime.tick(.1)
	return settled
func craft15(runtime:RefCounted,id:String,extra:Dictionary={})->bool:
	var tools:Array=[]
	for tool:Dictionary in runtime.world.extension("r3:production").tools:
		if tool.holderId=="pack:player" and float(tool.durability)>0:tools.append(tool.id)
	var payload:Dictionary={"direct":false,"recipe_id":id,"source_id":"pack:player","output_id":"pack:player","tool_ids":tools}
	payload.merge(extra,true)
	# Exercise the repaired old-workbench -> modern owning-module adapter.
	return complete15(runtime,"craft",str(workshop15.config.workbench_id),payload)
func labor15(runtime:RefCounted,zone_id:String,operation:String,limit:int=1800)->bool:
	if not care(runtime,45):return false
	var candidate:Dictionary={}
	for row:Dictionary in runtime._services.zonework.work_candidates("player"):
		if row.zone_id==zone_id and row.operation==operation:candidate=row;break
	check("natural region exposes actual candidate "+operation,not candidate.is_empty(),candidate.get("reason"))
	if candidate.is_empty():return false
	return complete15(runtime,"zonework.start",zone_id,{"candidate_id":candidate.id},limit)
func wait_crop15(runtime:RefCounted)->bool:
	for step:int in 6500:
		var plant:Dictionary=runtime.world.extension_entries("r34:ecology","plants",[plant15]).get(plant15,{})
		if plant.get("stage")=="mature":return true
		if plant.get("stage") in ["seedling","growing"] and int(plant.get("moisture",0))<int(Rules15.CROPS.potato.water):
			if float(runtime.actor("player").pack.get("r34:raw_water",0))<1:
				if not labor15(runtime,water15,"draw_raw_water"):return false
			if not labor15(runtime,field15,"water"):return false
		if Time.get_ticks_msec()-wall_start15>900000:check("natural route stays within fifteen-minute wall bound",false);return false
		if step%100==0 and runtime.actor("player").get("intent")==null:
			if not care(runtime,35):return false
		runtime.tick(.1)
	check("normal elapsed time produces mature potato",false,runtime.world.extension_entries("r34:ecology","plants",[plant15]));return false
func farm15(runtime:RefCounted)->bool:
	var plan:Dictionary=runtime.world.extension("generation:RH-HOME")
	var source:Dictionary=plan.ecology_sources[0]
	var reached:Dictionary=walk(runtime,source.use_point)
	check("player really returns to original raw source",reached.get("ok",false),reached.get("reason"))
	if not reached.get("ok",false):return false
	var wx:int=floori(float(source.location.x)*2);var wz:int=floori(float(source.location.z)*2)
	var water_zone:Dictionary=send(runtime,"zone.create",water15,{"spec":{"kind":"forage","region_id":"RH-HOME","bounds":{"x0":wx-2,"x1":wx+3,"z0":wz-2,"z1":wz+3},"policy":{"worker_ids":["player"]}}})
	check("actual source is covered by a real player work zone",water_zone.ok,water_zone.get("reason"))
	if not water_zone.ok:return false
	for draw:int in 4:
		if not labor15(runtime,water15,"draw_raw_water"):return false
	check("four finite original raw units enter pack with reusable bucket retained",runtime.actor("player").pack.get("r34:raw_water",0)==4 and runtime.actor("player").pack.get("r34:water_bucket",0)==1)
	if not craft15(runtime,"r34:raw_boil_water_v2"):return false
	check("actual raw boil records potable-water progress",runtime.world.extension("r34:gameplay").flags.get("village_clean_water",false))
	var field:Dictionary=plan.landforms.filter(func(f:Dictionary)->bool:return f.get("use")=="field")[0]
	var r:Array=field.xz;var found:Dictionary={}
	for z:int in range(ceili(r[1]*2)+2,floori(r[3]*2)-2,2):
		for x:int in range(ceili(r[0]*2)+2,floori(r[2]*2)-2,2):
			var spec:Dictionary={"kind":"farm","region_id":"RH-HOME","bounds":{"x0":x,"x1":x+1,"z0":z,"z1":z+1},"policy":{"crop_id":"potato","worker_ids":["player"]}}
			var preview:Dictionary=runtime._services.ecology.preview_zone(spec)
			if not preview.ok:continue
			var cell:Dictionary=preview.cells[0]
			var p:Dictionary={"x":(float(cell.x)+.5)*.5,"y":float(cell.y)*.5,"z":(float(cell.z)+.5)*.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
			if runtime._services.actions.route("player",Geometry.location(runtime.actor("player")),p).ok:found={"spec":spec,"cell":cell};break
		if not found.is_empty():break
	check("actual generated recoverable field has supported reachable planting cell",not found.is_empty())
	if found.is_empty():return false
	var created:Dictionary=send(runtime,"zone.create",field15,{"spec":found.spec})
	check("field created through original player command",created.ok,created.get("reason"))
	if not created.ok:return false
	plant15=Rules15.plant_id("RH-HOME",found.cell)
	if not labor15(runtime,field15,"till") or not labor15(runtime,field15,"sow"):return false
	for cycle:int in 2:
		if not wait_crop15(runtime) or not labor15(runtime,field15,"harvest_crop"):return false
		check("harvest retains a seed for repeat cycle "+str(cycle+1),runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].seed_reserved==1)
		if not craft15(runtime,"r34:cook_potato_v2"):return false
		check("actual edible meal output advances food objective",runtime.world.extension("r34:gameplay").flags.get("village_food_produced",false))
		if cycle==0:
			var seeds:float=float(runtime.actor("player").pack.get("r34:potato_seed",0))
			if not labor15(runtime,field15,"sow"):return false
			check("second crop consumes retained seed instead of another finite seed",runtime.actor("player").pack.get("r34:potato_seed",0)==seeds)
	# Two genuine harvest residues close fertility through the original recipe.
	if not craft15(runtime,"r34:compost_v2") or not labor15(runtime,field15,"compost"):return false
	check("two actual harvests restore future fertility via own residues",runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].fertility>=2)
	if not labor15(runtime,water15,"draw_raw_water"):return false
	check("original source continues yielding raw water after normal recharge",runtime.actor("player").pack.get("r34:raw_water",0)>=2)
	return true

func run()->void:
	wall_start15=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args();outdir=args[0] if not args.is_empty() else "user://supply15"
	DirAccess.make_dir_recursive_absolute(outdir)
	var profiles:Dictionary=Assembly.generation_profiles(15)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[]),15))
	check("untouched content15 world assembles",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var opening:Dictionary=Profile15.prepare_opening(prepared.capture,"normal")
	var host:=Native.new();var built:Dictionary=host._assemble(opening);host.free()
	check("normal15 mounts through original native authority",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;live15=runtime
	workshop15=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	axe15=str(opening.source.opening_configuration.tools.salvaged_axe)
	saw15=workshop15.id+":tool:hand_saw";hammer15=workshop15.id+":tool:hammer"
	check("normal starter axe is same registered instance immediately in pack",runtime.tool(axe15).holderId=="pack:player" and runtime.actor("player").pack.get("timber",0)==0)
	var home:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:home")
	if not take_source(runtime,str(home.stock_refs.values()[0]),{"food":3,"water":3,"cloth":2,"scrap":4}):return finish()
	if not take_source(runtime,str(workshop15.stock_refs.tools),{"scrap":6,"book_woodwork":1,"book_tool_repair":1},[saw15,hammer15]):return finish()
	for record:String in ["book_woodwork","book_tool_repair"]:
		if not complete15(runtime,"study",workshop15.id+":record:"+record,{"direct":false}):return finish()
	var anchors:Array=runtime.world.extension("generation:RH-HOME").content_anchors.filter(func(a:Dictionary)->bool:return a.purpose=="stockyard-and-recovery")
	check("initial finite recovery source exists",anchors.size()==1)
	if anchors.size()!=1:return finish()
	var yard:String=str(anchors[0].id)+":container"
	if not take_source(runtime,yard,{"scrap":4,"r34:salvaged_drive_unit":1},[yard+":tool:shovel",yard+":tool:pickaxe"]):return finish()
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var harvested:int=0
	for tree:Dictionary in trees:
		if harvested==4:break
		if not care(runtime,45):return finish()
		var command:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[axe15]})
		if not command.ok:continue
		if not progress(runtime,1500).finished:return finish()
		if not take_source(runtime,str(tree.data.outputId),{"log":3}):return finish()
		harvested+=1
	check("four original trees produce exactly twelve finite logs",harvested==4 and runtime.actor("player").pack.get("log",0)==12)
	if harvested!=4:return finish()
	for batch:int in 6:
		if not craft15(runtime,"r34:saw_timber_v2"):return finish()
	if not craft15(runtime,"r34:make_handle_v2"):return finish()
	var wear_before:float=float(runtime.tool(axe15).durability)
	if not craft15(runtime,"r34:repair_axe_v2",{"repair_tool_id":axe15,"tool_ids":[hammer15]}):return finish()
	check("real consumed handle scrap and labor restore original worn axe",float(runtime.tool(axe15).durability)>wear_before and runtime.actor("player").pack.get("tool_handle",0)==0)
	note(runtime,"finite natural tool recovery completed")
	var sources:Dictionary=OpeningSources15.opening_additions(runtime.world)
	check("one original village seed and bucket source remains",sources.get("ok",false) and sources.get("additions",[]).size()==1)
	if not sources.get("ok",false) or sources.get("additions",[]).size()!=1:return finish()
	if not take_source(runtime,str(sources.additions[0].source_id),{"r34:potato_seed":1,"r34:water_bucket":1}):return finish()
	note(runtime,"finite seed bucket physically collected outside village")
	if not farm15(runtime):return finish()
	# Consume the produced meal through the existing generic life action.
	var eating:Dictionary=send(runtime,"eat","",{"item_id":"r34:meal_simple"})
	check("produced meal uses real consumable action",eating.ok,eating.get("reason"))
	if eating.ok:progress(runtime,50)
	finished15=true
	note(runtime,"two real crop cycles potable water and maintenance closed")
	save_scene(runtime,"actual-sustainable-supply15")
	finish()
func finish()->void:
	check("complete unfunded15 supply route finishes",finished15)
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var report:Dictionary={"suite":"village-natural-supply15","seed":713,"content_version":15,"checks":checks,"failed":failed,"journey":journey,"wall_ms":Time.get_ticks_msec()-wall_start15,"scope":"Real opening source transfers, physical movement, tree felling, modern recipe at old member workbench, tool repair, original seed/bucket, two normal-clock crops, raw-source recharge, cooked meals and compost. No actor, stock, time or world injection. Not GUI or FPS acceptance."}
	if live15!=null:
		report.final_player=live15.actor("player");report.final_flags=live15.world.extension("r34:gameplay").flags
		save_scene(live15,"actual-final-supply15");live15.retire()
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"suite":report.suite,"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
