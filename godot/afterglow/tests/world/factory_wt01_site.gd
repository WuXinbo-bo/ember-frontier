extends "res://tests/world/factory_mt01_source.gd"
## WT01 C scope: exact immutable policy/site and real tool-free body routes.
## Does not simulate or assert B repair/draw, water balance or E consumption.
const BeforeWaterContract=preload("res://tests/world/fixtures/generation_after_mt01.gd")
const BeforeWaterGenerator=preload("res://tests/world/fixtures/generator_before_wt01.gd")
var water_rows:Array=[]
func supported(live:RefCounted,source:Dictionary)->bool:
	var p:Dictionary=source.position;var y:int=roundi(p.y*2)-1
	for z:int in range(floori((p.z-0.6+0.00001)*2),floori((p.z+0.6-0.00001)*2)+1):
		for x:int in range(floori((p.x-0.6+0.00001)*2),floori((p.x+0.6-0.00001)*2)+1):
			if not live.is_cell_known(x,y,z) or not live.is_cell_resident(x,y,z) or live.cell_at(x,y,z)==0:return false
			for cy:int in range(y+1,y+4):
				if not live.is_cell_known(x,cy,z) or not live.is_cell_resident(x,cy,z) or live.cell_at(x,cy,z)!=0:return false
	return true
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	report_path=args[0];outdir=report_path.get_base_dir();wall_started=Time.get_ticks_msec()
	spec={"max_ticks_per_seed":4000,"max_wall_msec":95000}
	var profiles:Array=Modules.generation_profiles()
	for version:int in [1,2,3,4,5]:
		var story:int=1 if version>=3 else 0
		var old:Dictionary=BeforeWaterContract.fresh(profiles,version,story)
		var now:Dictionary=Contract.fresh(profiles,version,story)
		check("old version%d exact generation contract bytes/digest retained"%version,old.ok and now.ok and JSON.stringify(old.contract,"",true,true)==JSON.stringify(now.contract,"",true,true) and BeforeWaterContract.digest(old.contract)==Contract.digest(now.contract))
		var before:Dictionary=BeforeWaterGenerator.plan_region(713,Vector2i.ZERO,profiles,old.contract)
		var after:Dictionary=Factory.plan_region(713,Vector2i.ZERO,profiles,old.contract)
		check("old version%d entire saved plan retained, no water source"%version,before.ok and after.ok and Data.json_equal(before.plan,after.plan) and not after.plan.has("water_sources"))
	var lock:Dictionary=Contract.fresh(profiles,6,1)
	check("only content6 pins WT01 and keeps MT01 policy",lock.ok and lock.contract.water_recovery_policy=="wt01-v1" and lock.contract.tool_recovery_policy=="mt01-v1")
	for key:String in ["tool_recovery_policy","water_recovery_policy"]:
		for action:String in ["missing","tamper"]:
			var bad:Dictionary=lock.contract.duplicate(true)
			if action=="missing":bad.erase(key)
			else:bad[key]="other"
			check("content6 rejects "+key+" "+action,Contract.resolve(bad,profiles).get("code")=="FACTORY_GENERATION_POLICY_MISMATCH")
	for seed:int in [713,2026,17,999]:
		current_seed=seed
		var one:Dictionary=Factory.plan_region(seed,Vector2i.ZERO,profiles,lock.contract)
		var two:Dictionary=Factory.plan_region(seed,Vector2i.ZERO,profiles,lock.contract)
		var fringe:Dictionary=Factory.plan_region(seed,Vector2i(-1,0),profiles,lock.contract)
		check("bounded site placement deterministic and no extra peripheral tanks",one.ok and two.ok and fringe.ok and one.plan.water_sources.size()==1 and Data.json_equal(one.plan,two.plan) and fringe.plan.water_sources.is_empty(),one.get("reason"))
		if seed not in [713,2026] or not one.ok:continue
		tick_count=0
		var made:Dictionary=Assembly.prepare(Factory.generate(seed,profiles,lock.contract))
		var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.get("ok",false) else made;host.free()
		check("WT01 actual unmodified Native normal world assembles",built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var runtime:RefCounted=built.runtime;var live:RefCounted=built.world
		var source:Dictionary=live.extension("generation:RH-HOME").water_sources[0]
		var raster:String=raster_digest(live.snapshot());var start:Dictionary=Geometry.location(runtime.actor("player"))
		var feet:Dictionary=built.services.buildings.current_space().standing_point(source.use_point)
		check("real cells support whole tank, independent use mouth and no tools held",supported(live,source) and not feet.is_empty() and Geometry.point(feet)==Geometry.point(source.use_point) and toolfree(runtime),source)
		var route:Dictionary=built.services.actions.route("player",start,feet) if not feet.is_empty() else {"ok":false}
		var walked:Dictionary=walk(runtime,feet) if route.ok else route
		check("actual B navigation and command walk reaches WT01 without tools or clearing",route.ok and walked.get("ok",false) and toolfree(runtime) and raster_digest(live.snapshot())==raster,slim(walked))
		var returned:Dictionary=walk(runtime,start) if walked.get("ok",false) else {"ok":false}
		check("actual tool-free return and finite-source identity/descriptor unchanged",returned.get("ok",false) and toolfree(runtime) and source.id=="RH-HOME:emergency-water" and source.initial_remaining==48 and source.kind=="emergency-water-wt01-v1" and Data.json_equal(source,live.extension("generation:RH-HOME").water_sources[0]))
		var saved:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.text) if saved.get("ok",false) else saved
		check("canonical Native source descriptor survives save cold restore",decoded.get("ok",false) and Data.json_equal(decoded.capture.world.extensions["generation:RH-HOME"].water_sources,[source]))
		water_rows.append({"seed":seed,"source":source,"start":start,"standing":feet,"route":route,"walk":slim(walked),"return":slim(returned),"raster_sha256":raster,"actual_source_entity":live.entity(source.id),"scope":"real Native/B zero-tool path, current support and canonical save; draw/repair/finite balance not asserted by C"})
		if saved.get("ok",false):FileAccess.open(outdir+"/seed%d-wt01-route.native.json"%seed,FileAccess.WRITE).store_string(saved.text)
		runtime.retire()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"water_sites":water_rows,"scope":"C WT01 support/routes/version only; 17/999 plan checks only; no repair/draw/OS/package/G5 assertion"},"\t",true,true))
	quit(1 if failed else 0)
