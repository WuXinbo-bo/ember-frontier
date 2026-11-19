extends SceneTree
## Actual normal three-person factory runtime CPU attribution; no renderer/FPS claim.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Modules.generation_profiles()))
	check("actual normal factory source assembles",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish({})
	var host:=Native.new();var built:Dictionary=host._assemble(prepared.capture);host.free()
	check("actual native services configure without rendering",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish({})
	var runtime:RefCounted=built.runtime
	var start_clock:float=runtime.clock()
	var started:int=Time.get_ticks_usec()
	for i:int in 600:runtime.tick(0.1)
	var elapsed:int=Time.get_ticks_usec()-started
	check("all sixty accepted seconds are simulated once",is_equal_approx(runtime.clock()-start_clock,60.0) and runtime.simulation_budget().steps==600 and runtime.simulation_budget().pending_steps==0,runtime.simulation_budget())
	check("normal three identities and unique authority persist",runtime.facts().actors.size()==3 and runtime.facts().scenario=="factory-settlement-r34")
	var costs:Dictionary=runtime.simulation_costs()
	check("every installed owner is attributed exactly once per step",["residents","workforce","actions","modules","production","terrain","gameplay"].all(func(domain:String)->bool:return costs.get(domain+".prepare",{}).get("count",0)==600),costs)
	var source:Dictionary=runtime.capture_checkpoint()
	var detached:Dictionary=runtime.simulation_costs();detached.clear()
	check("reading diagnostic costs cannot mutate authority or counters",not runtime.simulation_costs().is_empty() and Data.json_equal(source,runtime.capture_checkpoint()))
	finish({"elapsed_ms":elapsed/1000.0,"mean_tick_ms":elapsed/600000.0,"simulation":runtime.simulation_budget(),"simulation_costs":costs,"authority":runtime.authority_costs(),"actors":runtime.facts().actors})
func finish(costs:Dictionary)->void:
	var report:Dictionary={"scope":"actual normal source/headless three-person 60 simulated seconds; CPU attribution, not foreground frame/FPS/GPU/VA or final package qualification","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"costs":costs}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed,"costs":costs}))
	quit(1 if report.failed else 0)
