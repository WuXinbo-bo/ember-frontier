extends "res://tests/gameplay/factory_n3_carrying.gd"
## Tests only. A schedules the 1800/3600 wall-second runs in its own window.
## The monotonic timestamp measures pacing; Runtime remains the only game clock.
## No accelerated mode, body/stock edits, reset, alternate simulation or refill.
const DRIVER_VERSION:="eee-long-mixed-v4-route-input"
var WAREHOUSE:String="r34:normal-built-warehouse:stock:storage"
var OUTPUT:String="r34:normal-built-woodshop:stock:output"
var HOME_SUPPLY:String="r34:generated:RH-HOME:home:stock:supplies"
var STORE_SUPPLY:String="r34:generated:RH-VILLAGE:store:stock:supplies"
var MACHINE:String="r34:normal-built-woodshop"
var mode:String="preflight"
var wall_seconds:float=8.0
var checkpoint_seconds:float=300.0
var cycle_seconds:float=120.0
var live_runtime:RefCounted
var bootstrapping:bool=false
var stopped:bool=false
var stop_reason:String=""
var wall_origin:int=-1
var last_feed:int=-1
var sim_origin:float=0.0
var fed_seconds:float=0.0
var pumps:int=0
var checkpoints:int=0
var mixed_cycles:int=0
var production_cycles:int=0
var next_checkpoint:float=0.0
var next_cycle:float=0.0
var last_sample:float=-INF
var initial_world:Dictionary={}
var initial_timber:float=0.0
var initial_settlements:Dictionary={}
var previous_tasks:Dictionary={}
var recent_event_ids:Dictionary={}
var event_counts:Dictionary={}
var event_tail:Array=[]
var command_tail:Array=[]
var samples:Array=[]
var rule_blocks:Array=[]
var pump_costs:Array=[]
var max_pump_usec:int=0
var max_feed_delta:float=0.0
var max_observed_backlog:float=0.0
var last_active_budget:Dictionary={}
var deadline_wall_seconds:float=0.0
var next_status:float=30.0
var coverage:Dictionary={"harvests":0,"new_machine_batches":0,"mixed_deliveries":0,"consent_withdrawals":0,"cargo_retargets":0,"cold_restores":0}

func elapsed_wall()->float:
	return 0.0 if wall_origin<0 else float(Time.get_ticks_usec()-wall_origin)/1000000.0

func parse_options()->bool:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("output directory and exact normal53 input are required");return false
	output_dir=args[0];source_path=args[1]
	var options:Dictionary={}
	for arg:String in args.slice(2):
		var pair:PackedStringArray=arg.trim_prefix("--").split("=",true,1)
		if pair.size()!=2 or pair[0] not in ["mode","wall-seconds","checkpoint-seconds","cycle-seconds","route-input"] or options.has(pair[0]):return false
		options[pair[0]]=pair[1]
	var binding:Dictionary=RouteInputs.options()
	if binding.has("error"):return false
	MACHINE=RouteInputs.module_id("machine")
	WAREHOUSE=RouteInputs.module_id("warehouse")+":stock:storage"
	OUTPUT=MACHINE+":stock:output"
	HOME_SUPPLY=RouteInputs.module_id("home")+":stock:supplies"
	STORE_SUPPLY=RouteInputs.module_id("store")+":stock:supplies"
	mode=str(options.get("mode","preflight"))
	for key:String in ["wall-seconds","checkpoint-seconds","cycle-seconds"]:
		if options.has(key) and (not str(options[key]).is_valid_float() or not is_finite(float(options[key]))):return false
	wall_seconds=float(options.get("wall-seconds","8" if mode=="preflight" else "1800"))
	checkpoint_seconds=float(options.get("checkpoint-seconds","3" if mode=="preflight" else "300"))
	cycle_seconds=float(options.get("cycle-seconds","120"))
	return mode in ["preflight","long"] and ((mode=="preflight" and wall_seconds>=3 and wall_seconds<=15) or (mode=="long" and wall_seconds in [1800.0,3600.0])) and checkpoint_seconds>=2 and checkpoint_seconds<=600 and cycle_seconds>=60 and cycle_seconds<=600

func begin_monitor(runtime:RefCounted)->void:
	var binding:Dictionary=RouteInputs.validate(runtime)
	check("explicit continuation identities resolve to original live module stock refs",binding.get("ok",false),binding)
	if not binding.get("ok",false):stopped=true;stop_reason="invalid_route_input";return
	MACHINE=RouteInputs.module_id("machine");WAREHOUSE=binding.refs["warehouse:storage"];OUTPUT=binding.refs["machine:output"];HOME_SUPPLY=binding.refs["home:supplies"];STORE_SUPPLY=binding.refs["store:supplies"]
	live_runtime=runtime;initial_world=runtime.world.identity();initial_timber=total_timber(runtime)
	for row:Dictionary in runtime.world.extension("r34:production").get("settlements",[]):initial_settlements[row.id]=true
	for event:Dictionary in runtime.facts().ledger:recent_event_ids[event.id]=true
	sim_origin=runtime.clock();wall_origin=Time.get_ticks_usec();last_feed=wall_origin
	next_checkpoint=checkpoint_seconds;next_cycle=cycle_seconds

func block(reason:String,detail:Variant=null,fatal:bool=true)->void:
	# A wall deadline may interrupt a perfectly valid in-flight action. Keep
	# that pending action for the final checkpoint, not a fake rule failure.
	if stopped and stop_reason=="wall_deadline":return
	var row:Dictionary={"wall_seconds":elapsed_wall(),"simulation_time":live_runtime.clock() if live_runtime!=null else null,"reason":reason,"detail":detail}
	if rule_blocks.size()<64:rule_blocks.append(row)
	if fatal:stopped=true;stop_reason=reason

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	if stopped:return {"ok":false,"code":"DRIVER_STOPPED","reason":stop_reason}
	sequence+=1
	var result:Dictionary=runtime.command({"command_id":"r34:e:long-mixed:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
	command_tail.append({"wall_seconds":elapsed_wall(),"time":runtime.clock(),"kind":kind,"target":target,"ok":result.get("ok",false),"code":result.get("code"),"reason":result.get("reason")})
	if command_tail.size()>64:command_tail.pop_front()
	return result

func step(runtime:RefCounted,count:int=1)->void:
	if wall_origin<0:begin_monitor(runtime)
	live_runtime=runtime
	for i:int in count:
		if stopped:return
		var target:float=runtime.clock()+0.1
		# Pump like a serial host frame loop. Returning after one actual fixed
		# step preserves the inherited helpers' bounds. Runtime owns catch-up
		# and debt; save/command cost is included in the next measured delta.
		while runtime.clock()<target-0.000001:
			var due:int=last_feed+16667
			while Time.get_ticks_usec()<due:
				OS.delay_usec(maxi(0,mini(10000,due-Time.get_ticks_usec())))
			var now:int=Time.get_ticks_usec()
			if float(now-wall_origin)/1000000.0>=wall_seconds:
				deadline_wall_seconds=float(now-wall_origin)/1000000.0
				stopped=true;stop_reason="wall_deadline";return
			var delta:float=float(now-last_feed)/1000000.0
			last_feed=now;fed_seconds+=delta;max_feed_delta=maxf(max_feed_delta,delta)
			var started:int=Time.get_ticks_usec();var before:float=runtime.clock()
			runtime.tick(delta)
			var cost:int=Time.get_ticks_usec()-started
			max_pump_usec=maxi(max_pump_usec,cost);pump_costs.append(cost)
			if pump_costs.size()>512:pump_costs.pop_front()
			pumps+=1
			if runtime.clock()!=before or elapsed_wall()-last_sample>=1.0:observe(runtime)
			if stopped:return

func progress(runtime:RefCounted,limit:int=1200)->Dictionary:
	var start:float=runtime.clock();var iterations:int=0
	while not stopped and runtime.actor("player").get("intent")!=null and iterations<limit:
		step(runtime);iterations+=1
	return {"finished":not stopped and runtime.actor("player").get("intent")==null,"sim_seconds":runtime.clock()-start,"iterations":iterations}

func observe(runtime:RefCounted)->void:
	live_runtime=runtime
	if wall_origin<0:begin_monitor(runtime)
	if bootstrapping:super.observe(runtime)
	var facts:Dictionary=runtime.facts();var actors:Array=facts.actors
	var people:Array=actors.filter(func(a:Dictionary)->bool:return a.get("faction")!="infected")
	var ids:Array=people.map(func(a:Dictionary)->String:return a.id);ids.sort()
	if ids!=["player","repair-resident","village-resident"] or runtime.world.identity()!=initial_world:block("original_identity_changed",ids);return
	if people.any(func(a:Dictionary)->bool:return float(a.hp)<=0):block("real_original_person_incapacitated",people);return
	for row:Dictionary in facts.stocks:
		for item:String in row.items:
			if not is_finite(float(row.items[item])) or float(row.items[item])<0:block("invalid_stock_quantity",{"stock":row.id,"item":item});return
	for a:Dictionary in actors:
		for item:String in a.pack:
			if not is_finite(float(a.pack[item])) or float(a.pack[item])<0:block("invalid_pack_quantity",{"actor":a.id,"item":item});return
		for field:String in ["hp","hunger","thirst","stamina","fatigue","x","y","z"]:
			if not is_finite(float(a.get(field,0))):block("nonfinite_actor_field",{"actor":a.id,"field":field});return
	var current_events:Dictionary={}
	for event:Dictionary in facts.ledger:
		current_events[event.id]=true
		if recent_event_ids.has(event.id):continue
		var key:String=str(event.kind)+":"+str(event.get("actor_id",""))+":"+str(event.get("operation",""))
		event_counts[key]=int(event_counts.get(key,0))+1
		if event.kind in ["factory-batch-completed","logistics-delivery-completed","life-completed","combat-hit","inventory-transfer"]:
			event_tail.append(event.duplicate(true))
			if event_tail.size()>64:event_tail.pop_front()
	recent_event_ids=current_events
	var logistics:Dictionary=runtime.world.extension("r34:logistics");var owners:Dictionary={}
	for task_row:Dictionary in logistics.tasks:
		var previous:Dictionary=previous_tasks.get(task_row.id,{})
		if not previous.is_empty() and int(task_row.trips)<int(previous.trips):block("task_trip_regressed",task_row);return
		if task_row.phase=="deliver" and not str(task_row.actor_id).is_empty():
			if owners.has(task_row.actor_id):block("multiple_physical_cargo_tasks",task_row);return
			owners[task_row.actor_id]=task_row.id
			var a:Dictionary=runtime.actor(str(task_row.actor_id))
			for item:String in task_row.items:
				if float(a.pack.get(item,0))+0.000001<float(task_row.items[item]):block("original_task_cargo_missing",task_row);return
		if task_row.status=="cargo_held" and logistics.reservations.any(func(r:Dictionary)->bool:return r.task_id==task_row.id):block("paused_cargo_keeps_reservation",task_row);return
		previous_tasks[task_row.id]={"trips":task_row.trips,"actor_id":task_row.actor_id}
	var new_timber:float=0.0;var settlement_ids:Dictionary={}
	for settlement:Dictionary in runtime.world.extension("r34:production").get("settlements",[]):
		if settlement_ids.has(settlement.id):block("duplicate_batch_settlement",settlement);return
		settlement_ids[settlement.id]=true
		if not initial_settlements.has(settlement.id):new_timber+=float(settlement.outputs.get("timber",0))
	if absf(total_timber(runtime)-initial_timber-new_timber)>0.000001:block("finite_timber_without_paid_settlement",{"actual":total_timber(runtime),"initial":initial_timber,"paid_output":new_timber});return
	coverage.new_machine_batches=settlement_ids.size()-initial_settlements.size()
	var defense:Dictionary=runtime.world.extension(Gameplay.KEY).defense
	if defense.status=="cleared" and (defense.actors.size()!=3 or defense.actors.any(func(id:String)->bool:return runtime.actor(id).get("hp",1)>0)):block("false_encounter_clearance",defense);return
	var budget:Dictionary=runtime.simulation_budget();last_active_budget=budget.duplicate(true);max_observed_backlog=maxf(max_observed_backlog,float(budget.backlog_seconds))
	if runtime.clock()-sim_origin>fed_seconds+0.10001:block("simulation_ahead_of_measured_feed",{"fed":fed_seconds,"advanced":runtime.clock()-sim_origin});return
	if elapsed_wall()-last_sample>=1.0:
		last_sample=elapsed_wall()
		var bodies:Array=[]
		for a:Dictionary in people:bodies.append({"id":a.id,"hp":a.hp,"hunger":a.hunger,"thirst":a.thirst,"stamina":a.stamina,"fatigue":a.fatigue,"location":Geometry.location(a),"pack":a.pack})
		var sample:Dictionary={"wall_seconds":last_sample,"simulation_time":runtime.clock(),"fed_seconds":fed_seconds,"budget":budget,"actors":bodies,"tasks":logistics.tasks.size(),"batches":runtime.world.extension("r34:production").batches.size(),"ledger":facts.ledger.size(),"monitors":{"memory_static":Performance.get_monitor(Performance.MEMORY_STATIC),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}}
		var stream:=FileAccess.open(output_dir+"/samples.jsonl",FileAccess.READ_WRITE);stream.seek_end();stream.store_line(JSON.stringify(sample))
		samples.append(sample)
		if samples.size()>64:samples.pop_front()
		if last_sample>=next_status:
			print(JSON.stringify({"driver":DRIVER_VERSION,"wall_seconds":last_sample,"simulation_seconds":runtime.clock()-sim_origin,"backlog_seconds":budget.backlog_seconds,"coverage":coverage}))
			next_status=last_sample+30.0

func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var result:Dictionary=super.cold_restore(runtime,label)
	if result.get("ok",false):
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(output_dir+"/"+label+".native.json"))
		if not RouteInputs.options().is_empty():
			var complete:Dictionary=preload("res://tests/gameplay/factory_route_cold.gd").compare(decoded.capture,result.runtime,int(RouteInputs.options().get("native_residency_batch",0)))
			check("explicit route preserves entire canonical capture and exact Native residency "+label,complete.get("ok",false),complete)
			if not complete.get("ok",false):block("complete_canonical_restore_failed",complete);return {"ok":false}
		var debt_same:bool=decoded.get("ok",false) and Data.json_equal(decoded.capture.simulation,result.runtime.capture_checkpoint().simulation)
		check("wall driver cold restore retains canonical Runtime debt "+label,debt_same)
		if not debt_same:block("canonical_simulation_debt_changed");return {"ok":false}
		live_runtime=result.runtime;coverage.cold_restores+=1
	else:block("canonical_cold_restore_failed",result.get("reason"))
	return result

func checkpoint_now()->void:
	checkpoints+=1
	var restored:Dictionary=cold_restore(live_runtime,"long-checkpoint-%02d"%checkpoints)
	if restored.get("ok",false):observe(restored.runtime)
	write_report(false)

func close_enough(runtime:RefCounted,id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	if stock.is_empty():return false
	if runtime._services.production.reach("player",id,stock,"search")==null:return true
	for offset:Vector2 in [Vector2(0,-1.2),Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,1.2),Vector2.ZERO]:
		var at:Dictionary=stock.location.duplicate(true);at.x+=offset.x;at.z+=offset.y
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if feet.is_empty():continue
		if walk(runtime,feet).get("ok",false) and runtime._services.production.reach("player",id,runtime.stock(id),"search")==null:return true
	return false

func take_finite(id:String,items:Dictionary)->bool:
	var runtime:RefCounted=live_runtime
	if not close_enough(runtime,id):block("real_finite_source_unreachable",id);return false
	if not runtime.stock(id).get("searched",false):
		var searched:Dictionary=send(runtime,"search",id)
		if not searched.get("ok",false) or not progress(runtime,100).finished:block("normal_finite_search_refused",searched);return false
	var result:Dictionary=send(runtime,"take",id,{"items":items})
	if not result.get("ok",false):block("finite_take_refused",{"source":id,"result":result})
	return result.get("ok",false)

func self_care()->bool:
	var runtime:RefCounted=live_runtime
	for spec:Array in [["thirst","water","drink"],["hunger","food","eat"]]:
		if float(runtime.actor("player")[spec[0]])>=40:continue
		if float(runtime.actor("player").pack.get(spec[1],0))<1:
			var found:bool=false
			for source:String in [HOME_SUPPLY,STORE_SUPPLY]:
				if float(runtime.stock(source).get("items",{}).get(spec[1],0))<1:continue
				found=take_finite(source,{spec[1]:1});break
			if not found:block("finite_survival_supply_exhausted",spec[1]);return false
		var result:Dictionary=send(runtime,str(spec[2]))
		if not result.get("ok",false) or not progress(runtime,40).finished:block("normal_care_refused",result);return false
	if float(runtime.actor("player").stamina)<45:
		if not rest_once(runtime):block("normal_recovery_refused");return false
	return not stopped and ensure_companion_supplies()

func ensure_companion_supplies()->bool:
	# The long driver must support its real consenting workers as well as the
	# player. Use original N2 signals/ownership, never lower needs or authorize
	# companions to take the unowned village store. The player carries a finite
	# food/water reserve to the existing shared home through normal commands.
	var runtime:RefCounted=live_runtime
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.workforce.context)
	var members:int=0;var shortage:bool=false
	var home:Dictionary=runtime.stock(HOME_SUPPLY)
	for id:String in guards:
		var actor:Dictionary=tx.actor(id)
		if float(actor.get("hp",0))<=0 or not actor.get("relationship",{}).get("member",false) or not actor.relationship.get("consent",false):continue
		members+=1
		var signals:Dictionary=runtime._services.residents.factory_signals(actor,tx)
		var item:String={"drink":"water","eat":"food"}.get(str(signals.urgent_need),"")
		if not item.is_empty() and float(actor.pack.get(item,0))+float(home.get("items",{}).get(item,0))<1:shortage=true
	if not shortage:return true
	var items:Dictionary={}
	for item:String in ["water","food"]:
		var missing:int=maxi(0,members-int(home.get("items",{}).get(item,0)))
		if missing>0:items[item]=missing
	if items.is_empty():return true
	for item:String in items:
		if float(runtime.stock(STORE_SUPPLY).get("items",{}).get(item,0))<float(items[item]):block("finite_companion_supply_exhausted",{"source":STORE_SUPPLY,"item":item,"required":items[item]});return false
	if not take_finite(STORE_SUPPLY,items):return false
	if not close_enough(runtime,HOME_SUPPLY):block("real_companion_supply_destination_unreachable",HOME_SUPPLY);return false
	var delivered:Dictionary=send(runtime,"deposit",HOME_SUPPLY,{"items":items})
	if not delivered.get("ok",false):block("finite_companion_supply_delivery_refused",delivered);return false
	coverage["companion_supply_deliveries"]=int(coverage.get("companion_supply_deliveries",0))+1
	return true

func social_contact(runtime:RefCounted,id:String,enabled:bool)->bool:
	# Same normal social availability/contact policy as factory_normal_mixed.
	for attempt:int in 18:
		if stopped:return false
		if runtime.life_availability({"actor_id":"player","kind":"consent","target_id":id,"payload":{"enabled":enabled}}).get("ok",false):return true
		var at:Dictionary=Geometry.location(runtime.actor(id));var offset:Vector2=Vector2.RIGHT.rotated(float(attempt%8)*PI/4)*0.9
		at.x+=offset.x;at.z+=offset.y
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if not feet.is_empty():walk(runtime,feet)
	return false

func consent_actual(id:String,enabled:bool)->bool:
	if not social_contact(live_runtime,id,enabled):block("real_social_contact_failed",id);return false
	var result:Dictionary=send(live_runtime,"consent",id,{"enabled":enabled})
	if not result.get("ok",false):block("normal_consent_refused",result);return false
	if not enabled:coverage.consent_withdrawals+=1
	return true

func create_haul(source:String,destination:String,quantity:int=1)->String:
	var before:Array=live_runtime.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var result:Dictionary=send(live_runtime,"logistics.create","",{"source_id":source,"destination_id":destination,"items":{"timber":quantity},"repeat":false})
	if not result.get("ok",false):block("normal_logistics_configuration_refused",result);return ""
	for row:Dictionary in live_runtime.world.extension("r34:logistics").tasks:
		if not before.has(row.id):return str(row.id)
	block("configured_task_id_missing");return ""

func await_task(id:String,pickup:bool=false)->bool:
	for i:int in 1200:
		if stopped:return false
		var row:Dictionary=find_task(live_runtime,id)
		if (pickup and row.get("phase")=="deliver") or (not pickup and row.get("status")=="completed"):return true
		step(live_runtime)
	block("real_task_progress_blocked",find_task(live_runtime,id));return false

func clear_completed_route_assignments()->bool:
	if RouteInputs.options().is_empty():return true
	# The explicit new-family input follows two individually assigned trips.
	# Their old N4 requests remain authoritative until cleared by the player.
	# Clear only terminal trips via the existing command, never edit the queue.
	for row:Dictionary in live_runtime.world.extension("r34:workforce").get("assignments",[]):
		if not str(row.candidate_id).begins_with("logistics:"):continue
		if find_task(live_runtime,str(row.candidate_id)).get("status") not in ["completed","cancelled"]:continue
		sequence+=1
		var result:Dictionary=live_runtime.command({"command_id":"r34:e:long:clear:%d"%sequence,"actor_id":row.actor_id,"kind":"workforce.clear"})
		command_tail.append({"time":live_runtime.clock(),"kind":"workforce.clear","actor_id":row.actor_id,"candidate_id":row.candidate_id,"result":result})
		if not result.get("ok",false):block("completed_route_assignment_clear_refused",result);return false
	return true

func mixed_cycle()->bool:
	if not clear_completed_route_assignments():return false
	if not self_care():return false
	var source:String=WAREHOUSE if float(live_runtime.stock(WAREHOUSE).items.get("timber",0))>=2 else OUTPUT
	var destination:String=OUTPUT if source==WAREHOUSE else WAREHOUSE
	if float(live_runtime.stock(source).items.get("timber",0))<2:block("finite_boards_unavailable");return false
	var first:String=create_haul(source,destination)
	if first.is_empty() or not await_task(first,true):return false
	var carrier_id:String=str(find_task(live_runtime,first).actor_id)
	var other:String="village-resident" if carrier_id=="repair-resident" else "repair-resident"
	# Cargo test's real cancellation retains the pack while the player walks
	# to the social contact; no teleport or remote consent fixture is needed.
	var cancelled:Dictionary=send(live_runtime,"logistics.cancel",first)
	if not cancelled.get("ok",false):block("real_cargo_cancel_refused",cancelled);return false
	if not consent_actual(carrier_id,false) or not consent_actual(other,false):return false
	checkpoint_now()
	if stopped:return false
	var second:String=create_haul(source,HOME_SUPPLY)
	if second.is_empty() or not consent_actual(carrier_id,true):return false
	var retarget:Dictionary=send(live_runtime,"logistics.retarget",first,{"destination_id":destination})
	if not retarget.get("ok",false):block("original_cargo_retarget_refused",retarget);return false
	coverage.cargo_retargets+=1
	sequence+=1
	var assignment:Dictionary=live_runtime.command({"command_id":"r34:e:long:assignment:%d"%sequence,"actor_id":carrier_id,"kind":"workforce.assign","payload":{"candidate_id":second}})
	if not assignment.get("ok",false):block("real_explicit_assignment_refused",assignment);return false
	if not await_task(first) or not await_task(second):return false
	var single_trips:bool=find_task(live_runtime,first).trips==1 and find_task(live_runtime,second).trips==1 and live_runtime.actor(carrier_id).pack.get("timber",0)==0
	check("long mixed retains two original single-trip tasks",single_trips)
	if not single_trips:block("original_single_trip_or_pack_mismatch");return false
	coverage.mixed_deliveries+=2;mixed_cycles+=1
	return consent_actual(other,true)

func ensure_machine_output_room()->bool:
	if not clear_completed_route_assignments():return false
	# Two actual upcoming batches produce eight boards. The mixed cargo
	# exercise alone moves only two and may even bring one back to OUTPUT.
	# Ask the original capacity owner (including WIP/reservations), then have
	# a real consenting worker clear boards to the existing finite warehouse.
	# The bounded task wait and every B pickup/delivery check stay unchanged.
	for attempt:int in 3:
		var production:RefCounted=live_runtime._services.production
		if production.capacity_check(OUTPUT,{"timber":8}).get("ok",false):return true
		var quantity:int=mini(8,int(live_runtime.stock(OUTPUT).items.get("timber",0)))
		if quantity<=0:block("real_output_capacity_blocked",production.capacity_check(OUTPUT,{"timber":8}));return false
		var capacity:Dictionary=production.capacity_check(WAREHOUSE,{"timber":quantity})
		if not capacity.get("ok",false):block("finite_board_storage_exhausted",capacity);return false
		var task:String=create_haul(OUTPUT,WAREHOUSE,quantity)
		if task.is_empty() or not await_task(task):return false
		coverage["output_clearance_deliveries"]=int(coverage.get("output_clearance_deliveries",0))+1
		coverage["output_boards_cleared"]=int(coverage.get("output_boards_cleared",0))+quantity
	if live_runtime._services.production.capacity_check(OUTPUT,{"timber":8}).get("ok",false):return true
	block("real_output_capacity_still_blocked");return false

func machine_service_contact(runtime:RefCounted,target:String)->bool:
	if close_enough(runtime,target):return true
	# A late finite tree can exceed the unchanged single-route search budget.
	# Partition the return at the already known original home. Both legs are
	# ordinary walk commands with real carried logs and original bounds.
	var home:Dictionary=runtime.world.extension(Gameplay.KEY).layout.home
	if not walk(runtime,home).get("ok",false):return false
	return close_enough(runtime,target)

func production_cycle()->bool:
	if not self_care():return false
	if not ensure_machine_output_room():return false
	var runtime:RefCounted=live_runtime;var axe:String=""
	for tool:Dictionary in runtime.world.extension("r3:production").tools:
		if tool.kind=="salvaged_axe" and tool.holderId=="pack:player" and float(tool.durability)>0:axe=tool.id
	if axe.is_empty():block("finite_harvest_tool_exhausted");return false
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var harvested:bool=false
	for tree:Dictionary in trees.slice(0,8):
		var result:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[axe]})
		if not result.get("ok",false):continue
		if not progress(runtime,1000).finished:block("real_tree_work_incomplete",tree.id);return false
		if runtime.world.entity(tree.id).data.harvest.phase!="stump":block("real_tree_did_not_fall",tree.id);return false
		if not take_finite(str(tree.data.outputId),{"log":3}):return false
		harvested=true;coverage.harvests+=1;break
	if not harvested:block("finite_supported_tree_unavailable");return false
	for spec:Array in [["input",2],["fuel",1]]:
		var target:String=route_stock(runtime,"machine",str(spec[0]))
		if not machine_service_contact(runtime,target):block("real_machine_service_unreachable",target);return false
		var deposit:Dictionary=send(runtime,"deposit",target,{"items":{"log":spec[1]}})
		if not deposit.get("ok",false):block("finite_machine_feed_refused",deposit);return false
	var configured:Dictionary=send(runtime,"factory.configure",MACHINE,{"recipe_id":"saw_timber","batches":2})
	if not configured.get("ok",false):block("real_machine_configuration_refused",configured);return false
	var previous:int=int(coverage.new_machine_batches)
	for i:int in 600:
		if stopped:return false
		step(runtime)
		if int(coverage.new_machine_batches)>=previous+2:production_cycles+=1;return true
	block("paid_machine_batches_blocked",runtime.world.extension("r34:production"));return false

func preflight()->void:
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("short driver preflight decodes exact input",decoded.get("ok",false))
	if not decoded.get("ok",false):return
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("short driver preflight restores canonical actual services",built.get("ok",false) and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world))
	if not built.get("ok",false):return
	begin_monitor(built.runtime)
	if stopped:return
	if not clear_completed_route_assignments():return
	for row:Dictionary in live_runtime.world.extension("r34:logistics").tasks:
		if row.status not in ["completed","cancelled"]:check("short preflight stops finite repeat queue normally",send(live_runtime,"logistics.cancel",str(row.id)).get("ok",false))
	var id:String=create_haul(WAREHOUSE,OUTPUT)
	check("short preflight configures actual finite cargo only",not id.is_empty())
	check("short preflight starts normal player recovery",send(live_runtime,"rest").get("ok",false))
	while not stopped:
		step(live_runtime)
		if not stopped and elapsed_wall()>=next_checkpoint:
			checkpoint_now();next_checkpoint+=checkpoint_seconds
	check("short preflight feeds measured wall time only",fed_seconds<=elapsed_wall()+0.000001 and live_runtime.clock()-sim_origin<=fed_seconds+0.10001 and pumps>0)
	check("short preflight exercises actual canonical cold restoration",int(coverage.cold_restores)>0)
	check("short preflight preserves real decreasing thirst",live_runtime.actor("player").thirst<float(decoded.capture.facts.actors[0].thirst))

func run()->void:
	if not parse_options():push_error("Expected OUT INPUT --mode=preflight [3..15 seconds] or --mode=long --wall-seconds=1800|3600; checkpoint 2..600, cycle 60..600");quit(2);return
	DirAccess.make_dir_recursive_absolute(output_dir)
	if FileAccess.file_exists(output_dir+"/results.json") or FileAccess.file_exists(output_dir+"/samples.jsonl"):push_error("Fresh output directory required; previous evidence is never overwritten");quit(2);return
	FileAccess.open(output_dir+"/samples.jsonl",FileAccess.WRITE).close()
	if mode=="preflight":preflight()
	else:
		bootstrapping=true
		# All inherited movement, supply, defense and combat use virtual step()
		# above; none of these helpers directly advances an accelerated clock.
		super.run()
		bootstrapping=false;tracked_total=-1.0
		if checks.any(func(c:Dictionary)->bool:return not c.ok):block("normal_N3_bootstrap_failed")
		if not stopped and live_runtime!=null:
			var home:Dictionary=live_runtime.world.extension(Gameplay.KEY).layout.home
			if not walk(live_runtime,home).get("ok",false):block("actual_home_return_failed")
		while not stopped:
			if not self_care():break
			if elapsed_wall()>=next_checkpoint:checkpoint_now();next_checkpoint+=checkpoint_seconds
			if not stopped and elapsed_wall()>=next_cycle:
				if not mixed_cycle() or not production_cycle():break
				next_cycle=elapsed_wall()+cycle_seconds
			if not stopped:step(live_runtime)
	if live_runtime!=null:
		var final_restore:Dictionary=cold_restore(live_runtime,"long-final")
		if final_restore.get("ok",false):live_runtime=final_restore.runtime
	if mode=="long" and stop_reason=="wall_deadline":
		check("actual long run reaches requested driving wall duration",deadline_wall_seconds>=wall_seconds)
		check("actual long run includes paid harvest production mixed cargo defense and restore",int(coverage.harvests)>0 and int(coverage.new_machine_batches)>0 and int(coverage.mixed_deliveries)>0 and int(coverage.consent_withdrawals)>0 and int(coverage.cargo_retargets)>0 and int(coverage.cold_restores)>0 and guard_hits.size()==2)
	write_report(true)
	quit(1 if checks.any(func(c:Dictionary)->bool:return not c.ok) or stop_reason!="wall_deadline" else 0)

func finish()->void:
	# Parent N3 calls finish when its finite scenario returns. Keep the SAME
	# live runtime for the tail instead of quitting or reopening the input.
	if bootstrapping:return

func write_report(final:bool)->void:
	var elapsed:float=elapsed_wall()
	var functional:bool=not checks.any(func(c:Dictionary)->bool:return not c.ok) and stop_reason=="wall_deadline"
	var report:Dictionary={"driver":DRIVER_VERSION,"mode":mode,"final":final,"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"stop_reason":stop_reason,"rule_blocks":rule_blocks,"input":{"path":source_path,"sha256":source_sha},"parameters":{"wall_seconds":wall_seconds,"checkpoint_seconds":checkpoint_seconds,"cycle_seconds":cycle_seconds,"route_input":RouteInputs.options()},"pacing":{"monotonic_wall_seconds_including_final_restore":elapsed,"driving_wall_deadline_seconds":deadline_wall_seconds,"fed_actual_delta_seconds":fed_seconds,"simulation_seconds":live_runtime.clock()-sim_origin if live_runtime!=null else 0,"pumps":pumps,"max_feed_delta":max_feed_delta,"max_backlog_seconds":max_observed_backlog,"max_pump_usec":max_pump_usec,"last_512_pump_usec":pump_costs,"last_active_budget":last_active_budget,"post_restore_budget":live_runtime.simulation_budget() if live_runtime!=null else {}},"coverage":coverage,"guard_hits":guard_hits,"guard_routes":route_observations,"initial_world":initial_world,"checkpoints":checkpoints,"mixed_cycles":mixed_cycles,"production_cycles":production_cycles,"event_counts":event_counts,"last_64_events":event_tail,"last_64_commands":command_tail,"last_64_samples":samples,"samples":"samples.jsonl","run_completed":final and functional,"actual_30min_wall_elapsed":final and mode=="long" and deadline_wall_seconds>=1800,"actual_60min_wall_elapsed":final and mode=="long" and deadline_wall_seconds>=3600,"long_coverage_complete":final and functional and mode=="long" and int(coverage.harvests)>0 and int(coverage.new_machine_batches)>0 and int(coverage.mixed_deliveries)>0 and int(coverage.cold_restores)>0 and guard_hits.size()==2,"formal_long_time_or_resource_qualified":false,"scope":"Tests-only serial actual Runtime wall-delta driver. Preflight checks driver/invariants only, never 30/60min qualification. Full runs require A exact PCK/window and independent OS/RSS/resource evidence. Engine memory_static/object monitors include harness overhead and are not OS RSS. Finite source shortages and actual rule failures stop with evidence; no silent gameplay changes."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	if final:print(JSON.stringify({"mode":mode,"checks":checks.size(),"failed":report.failed,"stop_reason":stop_reason,"wall_seconds":elapsed,"simulation_seconds":report.pacing.simulation_seconds,"formal_long_qualified":false}))
