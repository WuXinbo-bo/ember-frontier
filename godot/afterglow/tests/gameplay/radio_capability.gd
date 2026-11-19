extends "res://tests/gameplay/generated_cooperation.gd"
## Actual retained bench and B approach. Repaired-radio prerequisite and
## staged stamina/timing are explicit diagnostic fixtures, not an RH route.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	command_prefix="E-radio-capability:"+output_dir.get_base_dir().get_file()+":"
	evidence_kind="actual-retained-bench-explicit-radio-staged-work-budget"
	host=Client.new()
	if args.size()!=2:check("recorded actual bench capture supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	var benches:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("definitionId")=="workbench")
	check("actual historical built bench exists",benches.size()==1)
	if benches.size()!=1:finish();return
	var bench:String=benches[0].id
	var points:Array=runtime._services.buildings.use_points(bench)
	if points.is_empty() or not walk(points[0],"actual B route to existing radio bench"):finish();return
	var fixture:Dictionary=runtime.capture_checkpoint()
	fixture.world.extensions[Gameplay.KEY].defense.status="cleared"
	fixture.world.extensions[Gameplay.KEY].radio={"status":"repaired","station_id":bench,"signal":0.0}
	if not mount(fixture):finish();return
	var started:Dictionary=send("radio",bench,{"operation":"transmit"})
	check("original transmission variant starts canonical command",started.ok,started)
	if not started.ok:finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	for amount:float in [0.0,0.01,0.05,10.0]:
		var tx:=Draft.new(runtime._services.gameplay.context)
		var a:Dictionary=tx.actor("player");a.stamina=amount
		var state:Dictionary=tx.extension(Gameplay.KEY)
		runtime._services.gameplay._radio_step(tx,a,state,0.1)
		var expected:float=minf(0.1,amount/0.5)
		check("radio work is bounded by real staged stamina "+str(amount),a.intent!=null and is_equal_approx(float(a.intent.elapsed),expected) and is_equal_approx(float(a.stamina),amount-expected*0.5) and is_equal_approx(float(state.radio.signal),expected),{"actor":a,"expected_work":expected})
		check("partial radio work never rewards or changes actual authority "+str(amount),a.pack==runtime.actor("player").pack and a.skills==runtime.actor("player").skills and Data.json_equal(baseline,runtime.capture_checkpoint()))
	var tx:=Draft.new(runtime._services.gameplay.context)
	var a:Dictionary=tx.actor("player");a.stamina=10.0;a.intent.elapsed=29.99
	var state:Dictionary=tx.extension(Gameplay.KEY);state.radio.signal=29.99
	runtime._services.gameplay._radio_step(tx,a,state,0.1)
	check("final partial tick charges only remaining original labor",a.intent==null and state.radio.status=="connected" and is_equal_approx(float(a.stamina),9.995) and is_equal_approx(float(state.radio.signal),30.0))
	check("completed radio gives exactly original single reward",float(a.skills.crafting)==float(runtime.actor("player").skills.crafting)+1.0 and tx.events.filter(func(e:Dictionary)->bool:return e.kind=="radio-completed").size()==1 and a.pack==runtime.actor("player").pack)
	check("work reads only existing neutral shared effects",Content.actor_effects(a).labor_multiplier==1.0 and Content.actor_effects(a).recovery_multiplier==1.0)
	finish()
