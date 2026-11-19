extends "res://tests/gameplay/factory_long_mixed.gd"
## Only bounded fixed-STEP wiring checks here, never wall-clock long evidence.
var probe_options:Dictionary={}
var native_batch:int=0
var test_steps:int=0
var commands:Array=[]
func step(runtime:RefCounted,count:int=1)->void:
	for i:int in count:
		if test_steps>=8000:block("bounded_joint_precheck");return
		runtime.tick(0.1);test_steps+=1;observe(runtime)
func observe(runtime:RefCounted)->void:
	live_runtime=runtime
	# Parent wall-feed oracle is only for actual wall runs; no fake wall pacing.
	for actor:Dictionary in runtime.facts().actors:
		if actor.get("faction")!="infected" and actor.hp!=100:block("original_person_hp_changed",actor)
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	var result:Dictionary=super.send(runtime,kind,target,payload,destination)
	commands.append({"time":runtime.clock(),"kind":kind,"target":target,"payload":payload,"result":result})
	return result
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	probe_options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var raw:String=FileAccess.get_file_as_string(source_path);source_sha=raw.sha256_text()
	var decoded:Dictionary=Store.decode(raw);var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("unchanged actual success checkpoint mounts",built.get("ok",false))
	if not built.get("ok",false):return finish()
	live_runtime=built.runtime
	var bound:Dictionary=RouteInputs.validate(live_runtime)
	check("explicit real module refs bind without authority mutation",bound.get("ok",false),bound)
	if not bound.get("ok",false):return finish()
	MACHINE=RouteInputs.module_id("machine");OUTPUT=bound.refs["machine:output"];WAREHOUSE=bound.refs["warehouse:storage"];HOME_SUPPLY=bound.refs["home:supplies"];STORE_SUPPLY=bound.refs["store:supplies"]
	var before:float=total_timber(live_runtime)
	if probe_options.get("probe_mode")=="mixed":
		check("original mixed cargo commands resume actual new family",mixed_cycle())
		check("mixed continuation preserves all finite boards",total_timber(live_runtime)==before)
	elif probe_options.get("probe_mode")=="supply":
		check("original lawful finite companion supply function accepts actual new source",ensure_companion_supplies())
	else:
		check("original capacity-owner clearance supports new output refs",ensure_machine_output_room())
	var restored:Dictionary=cold_restore(live_runtime,"joint-continuation-cold")
	if restored.get("ok",false):live_runtime=restored.runtime
	finish()
func finish()->void:
	if live_runtime!=null:save(live_runtime,"joint-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"input":{"path":source_path,"sha256":source_sha},"route_input":RouteInputs.options(),"options":probe_options,"fixed_steps":test_steps,"commands":commands,"coverage":coverage,"rule_blocks":rule_blocks,"scope":"Bounded fixed-STEP affected tests-only wiring. No wall-time/FPS/long/defense/repair qualification; no fixture or capture mutation."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
