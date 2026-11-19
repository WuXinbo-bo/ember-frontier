extends RefCounted
## Same actual Native normal opening/600 STEP as A's cost route, detached capture.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run(tree:SceneTree,output:String,manifest:Dictionary)->void:
	check("exact intended Data bytes mounted before dependencies",FileAccess.get_sha256("res://scripts/world/world_data.gd")==manifest.data_sha)
	var data_script:Script=Data
	var probing:bool=manifest.probe
	check("test probe present only when requested",data_script.has_method("_id_probe_stats")==probing)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Modules.generation_profiles()))
	check("actual normal opening prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):finish(tree,output,{});return
	var host:=Native.new();var built:Dictionary=host._assemble(prepared.capture);host.free()
	check("actual Native owners assemble",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):finish(tree,output,{});return
	var runtime:RefCounted=built.runtime
	var initial:Dictionary=runtime.capture_checkpoint()
	var init_file:=FileAccess.open(output+"/initial.var",FileAccess.WRITE);init_file.store_var(initial);init_file.close()
	var initialization:Dictionary={}
	if probing:
		initialization=data_script.call("_id_probe_stats")
		data_script.call("_id_probe_reset")
	var start_clock:float=runtime.clock()
	var started:int=Time.get_ticks_usec()
	for i:int in 600:runtime.tick(0.1)
	var elapsed:int=Time.get_ticks_usec()-started
	var ids:Dictionary=data_script.call("_id_probe_stats") if probing else {}
	var costs:Dictionary=runtime.simulation_costs()
	var capture:Dictionary=runtime.capture_checkpoint()
	check("600 accepted steps with no backlog",runtime.simulation_budget().steps==600 and runtime.simulation_budget().pending_steps==0 and is_equal_approx(runtime.clock()-start_clock,60.0),runtime.simulation_budget())
	check("three original normal identities",runtime.facts().actors.size()==3 and runtime.facts().scenario=="factory-settlement-r34")
	var owner_counts:Dictionary={}
	for domain:String in ["residents","workforce","actions","modules","production","terrain","gameplay"]:
		owner_counts[domain]=costs.get(domain+".prepare",{}).get("count",0)
	check("all seven complete owner preparations remain 600",owner_counts.values().all(func(v:Variant)->bool:return v==600),owner_counts)
	var f:=FileAccess.open(output+"/final.var",FileAccess.WRITE);f.store_var(capture);f.close()
	var reference:String=manifest.get("reference","")
	if not reference.is_empty():
		var rf:=FileAccess.open(reference+"/final.var",FileAccess.READ);var expected:Variant=rf.get_var();rf.close()
		check("complete final authority strictly equals baseline",Data.json_equal(capture,expected))
		check("binary final capture byte-identical",FileAccess.get_sha256(output+"/final.var")==FileAccess.get_sha256(reference+"/final.var"))
		check("binary opening capture byte-identical",FileAccess.get_sha256(output+"/initial.var")==FileAccess.get_sha256(reference+"/initial.var"))
	finish(tree,output,{"elapsed_ms":elapsed/1000.0,"mean_tick_ms":elapsed/600000.0,"owner_counts":owner_counts,"costs":costs,"authority":runtime.authority_costs(),"ids":ids,"initialization_ids":initialization,"initial_sha":FileAccess.get_sha256(output+"/initial.var"),"final_sha":FileAccess.get_sha256(output+"/final.var")})
func finish(tree:SceneTree,output:String,measurements:Dictionary)->void:
	var report:Dictionary={"scope":"same pinned actual normal Native runtime; headless CPU, not renderer/FPS/OS/package acceptance; probe time excludes stats bookkeeping but includes two monotonic clock calls","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"measurements":measurements}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed,"mean_tick_ms":measurements.get("mean_tick_ms"),"ids":measurements.get("ids",{}).get("calls")}))
	tree.quit(1 if report.failed else 0)
