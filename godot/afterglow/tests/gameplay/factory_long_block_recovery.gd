extends "res://tests/gameplay/factory_long_mixed.gd"
## Bounded regression of A's actual failed21 save. This test overrides wall
## pacing with accepted Runtime fixed steps only; it is never a long-run mode.
## Original bodies/needs/consent/stock/event/capture are not edited.
var diagnostic:Array=[]
var paid_events:Dictionary={}
var fixed_steps:int=0
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	# The original failure contains the long driver's receipts. A bounded
	# continuation needs its own command namespace, never replay old success.
	sequence+=1
	var request:Dictionary={"command_id":"r34:e:long-block-probe:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request)
	command_tail.append({"time":runtime.clock(),"request":request,"result":result})
	return result
func step(runtime:RefCounted,count:int=1)->void:
	for i:int in count:
		if stopped:return
		runtime.tick(0.1);fixed_steps+=1;observe(runtime)
func observe(runtime:RefCounted)->void:
	live_runtime=runtime
	for a:Dictionary in runtime.facts().actors:
		if a.id in guards and float(a.hp)!=(52.0 if a.id=="village-resident" else 100.0):invariant_failures.append({"time":runtime.clock(),"reason":"original_hp_changed","actor":a.id})
		for item:String in a.pack:
			if float(a.pack[item])<0:invariant_failures.append({"reason":"negative_pack"})
	for s:Dictionary in runtime.facts().stocks:
		for item:String in s.items:
			if float(s.items[item])<0:invariant_failures.append({"reason":"negative_stock"})
	for e:Dictionary in runtime.facts().ledger:
		if e.kind in ["life-completed","logistics-delivery-completed","inventory-transfer"]:paid_events[e.id]=e
func mount_original(capture:Dictionary)->bool:
	if live_runtime!=null:live_runtime.retire()
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free()
	check("actual failed21 input restores without fact edits",built.get("ok",false) and Data.json_equal(capture.facts,built.runtime.facts()))
	if not built.get("ok",false):return false
	live_runtime=built.runtime;stopped=false;stop_reason="";return true
func inquiry(label:String)->void:
	var runtime:RefCounted=live_runtime;var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.workforce.context)
	var rows:Array=[]
	for id:String in guards:
		var a:Dictionary=tx.actor(id)
		rows.append({"actor":a.duplicate(true),"signals":runtime._services.residents.factory_signals(a,tx),"candidates":runtime._services.actions.workforce_candidates(id,tx.staged,tx.extensions)})
	var workforce:Dictionary=runtime.world.extension("r34:workforce");workforce.erase("layout")
	diagnostic.append({"stage":label,"time":runtime.clock(),"task":find_task(runtime,"logistics:20.0"),"workforce":workforce,"people":rows,"home":runtime.stock(HOME_SUPPLY),"store":runtime.stock(STORE_SUPPLY),"output":runtime.stock(OUTPUT),"warehouse":runtime.stock(WAREHOUSE)})
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1];source_sha=FileAccess.get_sha256(source_path)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path))
	check("exact failed input decodes",decoded.get("ok",false));if not decoded.get("ok",false):return finish()
	if not mount_original(decoded.capture):return finish()
	inquiry("original failure before any command")
	check("original task20 is queued and finite source/receiver exist",find_task(live_runtime,"logistics:20.0").status=="queued" and float(live_runtime.stock(OUTPUT).items.timber)>=1)
	check("both original consent and urgent unmet needs remain",guards.all(func(id:String)->bool:return live_runtime.actor(id).relationship.consent and live_runtime.actor(id).pack.get("water",0)==0 and live_runtime.actor(id).thirst<35))
	var before_steps:int=fixed_steps;var progressed:bool=await_task("logistics:20.0")
	check("original no-command branch stalls at unchanged1200 bound",not progressed and stop_reason=="real_task_progress_blocked" and fixed_steps-before_steps==1200 and find_task(live_runtime,"logistics:20.0").trips==0)
	inquiry("original no-command1200 unchanged limit")
	save(live_runtime,"baseline-still-blocked")
	if not mount_original(decoded.capture):return finish()
	var assigned:Dictionary=live_runtime.command({"command_id":"r34:e:block-probe:assign-only","actor_id":"repair-resident","kind":"workforce.assign","payload":{"candidate_id":"logistics:20.0"}})
	check("real fresh task20 explicit assignment is admissible",assigned.get("ok",false),assigned)
	before_steps=fixed_steps;progressed=await_task("logistics:20.0")
	check("fresh explicit assignment cannot override original unmetN2",not progressed and fixed_steps-before_steps==1200 and find_task(live_runtime,"logistics:20.0").trips==0 and live_runtime.actor("repair-resident").self_routine.factory_decision.priority=="N2")
	inquiry("assignment-only1200 original needs still block")
	save(live_runtime,"assignment-only-still-blocked")
	if not mount_original(decoded.capture):return finish()
	var old_timber:float=total_timber(live_runtime);var store_items:Dictionary=live_runtime.stock(STORE_SUPPLY).items.duplicate(true)
	var supplied:bool=self_care()
	check("revised long helper carries finite store supplies home legally",supplied and int(coverage.get("companion_supply_deliveries",0))==1,rule_blocks)
	if not supplied:return finish()
	inquiry("paid home supply delivery before resumed task")
	check("original source pays exactly two water and two food",float(live_runtime.stock(STORE_SUPPLY).items.water)==float(store_items.water)-2 and float(live_runtime.stock(STORE_SUPPLY).items.food)==float(store_items.food)-2)
	progressed=await_task("logistics:20.0")
	check("original task20 completes through original1200 bound after paid care",progressed and find_task(live_runtime,"logistics:20.0").trips==1 and total_timber(live_runtime)==old_timber,find_task(live_runtime,"logistics:20.0"))
	check("both original consent and52HP survive paid autonomous recovery",live_runtime.actor("village-resident").hp==52 and guards.all(func(id:String)->bool:return live_runtime.actor(id).relationship.consent and live_runtime.actor(id).thirst>=35 and live_runtime.actor(id).hunger>=35))
	inquiry("original task20 delivered after autonomousN2")
	var cold:Dictionary=cold_restore(live_runtime,"recovered-original-task20")
	check("paid recovery restores task20 single trip and exact originalHP",cold.get("ok",false) and find_task(cold.runtime,"logistics:20.0").trips==1 and cold.runtime.actor("village-resident").hp==52)
	check("bounded diagnostic original supplies never go negative or healHP",invariant_failures.is_empty(),invariant_failures)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"diagnostic":diagnostic,"commands":command_tail,"rule_blocks":rule_blocks,"paid_events":paid_events,"fixed_steps":fixed_steps,"invariant_failures":invariant_failures,"source":{"path":source_path,"sha256":source_sha},"scope":"Exact failed21 Native and unchanged21 PCK. Three independent original-input mounts: unchanged1200 no-command, admissible fresh assignment1200, real finite source recovery. Only bounded diagnostic pacing uses Runtime.tick(0.1), never a wall-time long test. No gameplay/body/stock/consent/clock injection; original red retained, no3600 pass."},"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
