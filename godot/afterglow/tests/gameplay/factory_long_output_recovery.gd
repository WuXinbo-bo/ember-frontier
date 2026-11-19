extends "res://tests/gameplay/factory_long_mixed.gd"
## Exact failed22 continuation; fixed steps diagnose function, never wall time.
var fixed_steps:int=0
var diagnostic:Array=[]
var seen_events:Dictionary={}
var carries:Array=[]
var initial_total:float=0.0
var initial_paid:int=0
var probe_mode:String="baseline"
var expected_consent:Dictionary={}
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"r34:e:output-recovery:"+probe_mode+":%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request)
	if kind=="consent" and result.get("ok",false):expected_consent[target]=bool(payload.enabled)
	command_tail.append({"time":runtime.clock(),"request":request,"result":result})
	return result
func step(runtime:RefCounted,count:int=1)->void:
	for i:int in count:
		if stopped:return
		runtime.tick(0.1);fixed_steps+=1;observe(runtime)
func observe(runtime:RefCounted)->void:
	live_runtime=runtime
	var paid:int=runtime.world.extension("r34:production").settlements.size()
	coverage.new_machine_batches=paid-initial_paid
	if absf(total_timber(runtime)-initial_total-float(paid-initial_paid)*4)>0.000001:invariant_failures.append({"time":runtime.clock(),"reason":"unpaid_timber"})
	for a:Dictionary in runtime.facts().actors:
		if a.id in ["player","repair-resident","village-resident"] and (a.hp!=(52.0 if a.id=="village-resident" else 100.0) or (a.id!="player" and a.relationship.consent!=expected_consent.get(a.id,true))):invariant_failures.append({"time":runtime.clock(),"reason":"original_hp_or_commanded_consent_changed","actor":a.id})
		for item:String in a.pack:
			if float(a.pack[item])<0:invariant_failures.append({"reason":"negative_pack"})
	for stock:Dictionary in runtime.facts().stocks:
		for item:String in stock.items:
			if float(stock.items[item])<0:invariant_failures.append({"reason":"negative_stock"})
	for task:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if task.phase=="deliver" and not str(task.actor_id).is_empty() and not seen_events.has("carry:"+task.id):
			seen_events["carry:"+task.id]=true
			carries.append({"time":runtime.clock(),"task":task,"actor":runtime.actor(str(task.actor_id))})
	for event:Dictionary in runtime.facts().ledger:
		if event.time>=sim_origin and event.kind in ["inventory-transfer","logistics-delivery-completed","factory-batch-completed"]:seen_events[event.id]=event
func snapshot(label:String)->void:
	var runtime:RefCounted=live_runtime
	diagnostic.append({"label":label,"time":runtime.clock(),"actors":runtime.facts().actors,"output":runtime.stock(OUTPUT),"warehouse":runtime.stock(WAREHOUSE),"production":runtime.world.extension("r34:production"),"logistics":runtime.world.extension("r34:logistics"),"room_for_two":runtime._services.production.capacity_check(OUTPUT,{"timber":8})})
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1];source_sha=FileAccess.get_sha256(source_path)
	probe_mode=str(JSON.parse_string(FileAccess.get_file_as_string(args[2])).get("probe_mode","baseline"))
	DirAccess.make_dir_recursive_absolute(output_dir)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path));check("exact failed22 input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("failed22 mounts complete canonical authority unchanged",built.get("ok",false) and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world))
	if not built.get("ok",false):return finish()
	live_runtime=built.runtime;sim_origin=live_runtime.clock();initial_total=total_timber(live_runtime);initial_paid=live_runtime.world.extension("r34:production").settlements.size()
	snapshot("exact original failed22 before commands")
	var order:Dictionary=live_runtime.world.extension("r34:production").orders[0]
	check("original output62 blocks two already paid inputs without activeWIP",live_runtime.stock(OUTPUT).items.timber==62 and order.remaining==2 and order.completed==18 and order.blockers==["output_full"])
	if probe_mode=="baseline":
		step(live_runtime,600)
		order=live_runtime.world.extension("r34:production").orders[0]
		check("unchanged600 machine wait remains blocked without transport",order.remaining==2 and order.completed==18 and order.blockers==["output_full"] and fixed_steps==600)
		snapshot("unchanged600 still output_full")
		save(live_runtime,"baseline-still-output-full")
	else:
		# Calls the revised driver's real logistics plan, with its original
		# task1200 and production600 limits. No new input or fuel is supplied.
		var cleared:bool=call("ensure_machine_output_room")
		check("driver clears through real finite logistics and original bound",cleared,rule_blocks)
		if not cleared:return finish()
		snapshot("real cargo delivered and headroom checked")
		for i:int in 600:
			if live_runtime.world.extension("r34:production").orders[0].remaining==0:break
			step(live_runtime)
		order=live_runtime.world.extension("r34:production").orders[0]
		check("original order completes exactly two batches without replacement",order.id=="r34:normal-built-woodshop:machine" and order.remaining==0 and order.completed==20 and live_runtime.world.extension("r34:production").settlements.size()==initial_paid+2,order)
		check("original two input logs and one fuel are paid by B",live_runtime.stock(MACHINE+":stock:input").items.get("log",0)==0 and live_runtime.stock(MACHINE+":stock:fuel").items.get("log",0)==0 and order.energy_seconds==0)
		check("cargo remains in actual carrier pack until onsite single delivery",not carries.is_empty() and carries.all(func(row:Dictionary)->bool:return float(row.actor.pack.get("timber",0))>=float(row.task.items.timber)))
		check("paid two batch output adds exactly eight global boards",total_timber(live_runtime)==initial_total+8)
		snapshot("two original batches paid and completed")
		var restored:Dictionary=cold_restore(live_runtime,"recovered-original-output-full")
		check("cold restores original completed order and full authority",restored.get("ok",false) and restored.runtime.world.extension("r34:production").orders[0].completed==20)
	check("all observed HP consent stock and paid timber invariants hold",invariant_failures.is_empty(),invariant_failures)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	if live_runtime!=null:save(live_runtime,"probe-final")
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"mode":probe_mode,"diagnostic":diagnostic,"commands":command_tail,"carries":carries,"events":seen_events,"rule_blocks":rule_blocks,"fixed_steps":fixed_steps,"invariant_failures":invariant_failures,"input":{"path":source_path,"sha256":source_sha},"scope":"Unchanged22 PCK/exact failed22 input. Fixed Runtime0.1 bounded function only; no long/wall/OS/performance qualification. No authority edits, new capacity, material, enemy, clock or production implementation."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
