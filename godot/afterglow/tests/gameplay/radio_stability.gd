extends "res://tests/gameplay/gameplay_cursor_timers.gd"
## The bench/material route is retained evidence; repaired radio and defense
## are explicit prerequisites. Mutations below are real A world transactions.

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="real-retained-built-bench-explicit-repaired-radio-stationary-invalidations"
	command_prefix="E-radio-stability:"
	host=Client.new()
	if args.size()!=2:check("recorded material checkpoint supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	var benches:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("definitionId")=="workbench")
	check("recorded route contains actual constructed bench",benches.size()==1)
	if benches.size()!=1:finish();return
	var bench:String=benches[0].id
	var points:Array=runtime._services.buildings.use_points(bench)
	if points.is_empty() or not walk(points[0],"real B walk reaches constructed bench"):finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	baseline.world.extensions[Gameplay.KEY].defense.status="cleared"
	baseline.world.extensions[Gameplay.KEY].radio={"status":"repaired","station_id":bench,"signal":0.0}
	for mutation:String in ["owner","removed","definition","destroyed","already_completed","incapacitated"]:
		stationary_case(baseline,bench,mutation)
	station_holds(baseline,bench)
	repair_cases(baseline,bench)
	finish()

func station_holds(baseline:Dictionary,bench:String)->void:
	# Explicit transfer of the original finite saw for this occupancy fixture.
	# Knowledge/timber and bench are retained; no second tool or product is made.
	var fixture:Dictionary=baseline.duplicate(true)
	var saw:String=""
	for tool:Dictionary in fixture.world.extensions["r3:production"].tools:
		if tool.kind=="hand_saw":saw=tool.id;tool.holderId="pack:repair-resident"
	if saw.is_empty() or not mount(fixture):return
	seq+=1
	var request:Dictionary={"command_id":command_prefix+str(seq),"actor_id":"repair-resident","kind":"craft","target_id":bench,"payload":{"recipe_id":"make_handle","source_id":"pack:repair-resident","output_id":"pack:repair-resident","tool_ids":[saw]}}
	var started:Dictionary=runtime.command(request)
	check("other real actor starts original B craft command",started.ok,started)
	if not started.ok:return
	for i:int in 100:
		if runtime._services.production.use_reserved(bench):break
		runtime.tick(0.1)
	var order:Dictionary={}
	for candidate:Dictionary in runtime.world.extension("r3:production").orders:
		if candidate.actorId=="repair-resident" and candidate.status=="active":order=candidate
	check("B real craft exposes actual standard station hold",not order.is_empty() and runtime._services.production.use_reserved(bench))
	if order.is_empty():return
	var before:Dictionary=runtime.capture_checkpoint()
	var denied:Dictionary=send("radio",bench,{"operation":"transmit"})
	check("E start rejects another real B station hold atomically",not denied.ok and denied.code=="RESERVED" and Data.json_equal(before,runtime.capture_checkpoint()),denied)
	var other_intent:Dictionary=runtime.actor("repair-resident").intent.duplicate(true)
	seq+=1
	check("B canonical cancellation frees original work station",runtime.command({"command_id":command_prefix+str(seq),"actor_id":"repair-resident","kind":"cancel"}).ok and not runtime._services.production.use_reserved(bench))
	started=send("radio",bench,{"operation":"transmit"})
	check("E transmission starts after actual B hold releases",started.ok,started)
	if not started.ok:return
	var own_id:String=runtime.actor("player").intent.id
	check("active E station reservation excludes only exact intent identity",runtime._services.production.use_reserved(bench) and not runtime._services.production.use_reserved(bench,own_id) and runtime._services.production.use_reserved(bench,"player"))
	seq+=1;request.command_id=command_prefix+str(seq)
	before=runtime.capture_checkpoint();denied=runtime.command(request)
	check("B start reciprocally rejects actual E station hold",not denied.ok and denied.code=="RESERVED" and Data.json_equal(before,runtime.capture_checkpoint()),denied)
	# Explicit stale-concurrent-claim counterexample, using the actual B order
	# and intent just recorded, staged only. E must see tx overrides before work.
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
	var restored:Dictionary=preload("res://scripts/actions/domain_draft.gd").find(tx.extension("r3:production").orders,str(order.id))
	restored.merge(order,true);tx.actor("repair-resident").intent=other_intent
	var player:Dictionary=tx.actor("player")
	var elapsed:float=player.intent.elapsed
	var signal_before:float=tx.extension(Gameplay.KEY).radio.signal
	check("staged shared station query sees competing B provider",runtime._services.production.use_reserved(bench,own_id,tx) and not runtime._services.production.use_reserved(bench,own_id))
	runtime._services.gameplay._radio_step(tx,player,tx.extension(Gameplay.KEY),0.1)
	check("staged competing holder cancels E before elapsed signal or reward",player.intent==null and tx.extension(Gameplay.KEY).radio.signal==signal_before and player.pack==runtime.actor("player").pack and player.skills==runtime.actor("player").skills and elapsed==0)
	check("staged cancellation releases only E and retains actual B hold",tx.result().ok and runtime._commit(tx.result()).ok and runtime._services.production.use_reserved(bench) and not runtime._services.production.all_holds().any(func(h:Dictionary)->bool:return h.intent_id==own_id))

func repair_cases(baseline:Dictionary,bench:String)->void:
	# Explicit finite repair-input/knowledge prerequisite. The built bench is
	# actual retained labor; these prerequisites are NOT naturally earned here.
	var fixture:Dictionary=baseline.duplicate(true)
	fixture.world.extensions[Gameplay.KEY].radio={"status":"unrepaired","station_id":"","signal":0.0}
	var production:Dictionary=fixture.world.extensions["r3:production"]
	production.knowledge.player.append("basic_tool_repair")
	for a:Dictionary in fixture.facts.actors:
		if a.id=="player":a.pack["scrap"]=8;a.pack["tool_handle"]=1
	var hammer:String=""
	for tool:Dictionary in production.tools:
		if tool.holderId=="pack:player" and tool.kind=="hammer":hammer=tool.id;break
	check("repair fixture reuses original actual carried hammer",not hammer.is_empty())
	if hammer.is_empty():return
	for mutation:String in ["tool_broken","tool_quality","tool_moved","material_lost"]:
		if not mount(fixture):return
		var start:Dictionary=send("radio",bench,{"operation":"repair","tool_id":hammer})
		check(mutation+" repair fixture starts real public command",start.ok,start)
		if not start.ok:continue
		for i:int in 3:runtime.tick(0.1)
		var intent:Dictionary=runtime.actor("player").intent
		check(mutation+" B standard hold owns unpaid materials and excludes self",runtime._services.production.reserved("pack:player","scrap")==8 and runtime._services.production.reserved("pack:player","scrap",str(intent.id))==0 and runtime._services.production.tool_unavailable(hammer) and not runtime._services.production.tool_unavailable(hammer,str(intent.id)))
		var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
		var tool:Dictionary=preload("res://scripts/actions/domain_draft.gd").find(tx.extension("r3:production").tools,hammer)
		if mutation=="tool_broken":tool.durability=0.0
		elif mutation=="tool_quality":tool.qualities={"hammering":0}
		elif mutation=="tool_moved":tool.holderId=str(fixture.world.extensions[Gameplay.KEY].layout.home_building)+":storage"
		else:tx.actor("player").pack.scrap=7
		check(mutation+" explicit legitimate concurrent fact change commits",runtime._commit(tx.result()).ok)
		var before:Dictionary=runtime.actor("player")
		var plan:Dictionary=runtime._services.gameplay.advance(0.1)
		check(mutation+" continuation cancellation uses A transaction",plan.ok and runtime._commit(plan).ok)
		var after:Dictionary=runtime.actor("player")
		check(mutation+" cancels before further work material debit or reward",after.intent==null and after.pack==before.pack and after.skills==before.skills and Geometry.point(after)==Geometry.point(before) and runtime.world.extension(Gameplay.KEY).radio.status=="unrepaired")
		check(mutation+" cancelled standard material tool and station holds release",runtime._services.production.reserved("pack:player","scrap")==0 and not runtime._services.production.tool_unavailable(hammer) and not runtime._services.production.use_reserved(bench))
	if not mount(fixture):return
	var old:Dictionary=runtime.actor("player")
	var durability:float=runtime.tool(hammer).durability
	var started:Dictionary=send("radio",bench,{"operation":"repair","tool_id":hammer})
	check("explicit finite repair starts without upfront double charge",started.ok and runtime.actor("player").pack==old.pack,started)
	if not started.ok:return
	for i:int in 7:runtime.tick(0.1)
	check("cancel unpaid repair uses original cancellation policy",send("cancel").ok and runtime.actor("player").pack==old.pack and runtime.tool(hammer).durability==durability and runtime._services.production.reserved("pack:player","scrap")==0)
	if not send("radio",bench,{"operation":"repair","tool_id":hammer}).ok:return
	var replay:Dictionary=route_steps[-1].request.duplicate(true)
	for i:int in 70:runtime.tick(0.1)
	check("partially worked repair still owns original unconsumed finite materials",runtime.actor("player").pack==old.pack and runtime._services.production.reserved("pack:player","scrap")==8)
	if not roundtrip("explicit finite paid repair in-progress"):return
	for i:int in 200:
		if runtime.actor("player").intent==null:break
		runtime.tick(0.1)
	var final:Dictionary=runtime.actor("player")
	check("saved repair completes with original exact once materials and wear",runtime.world.extension(Gameplay.KEY).radio.status=="repaired" and final.intent==null and float(final.pack.scrap)==0 and float(final.pack.tool_handle)==0 and is_equal_approx(float(runtime.tool(hammer).durability),durability-2) and is_equal_approx(float(final.skills.crafting),float(old.skills.crafting)+1))
	var before:Dictionary=runtime.capture_checkpoint()
	check("replay of saved repair cannot double charge or reward",runtime.command(replay).ok and Data.json_equal(before,runtime.capture_checkpoint()))
	check("new duplicate repair is rejected without free second reward",not send("radio",bench,{"operation":"repair","tool_id":hammer}).ok and Data.json_equal(before,runtime.capture_checkpoint()))

func stationary_case(baseline:Dictionary,bench:String,mutation:String)->void:
	if not mount(baseline):return
	var started:Dictionary=send("radio",bench,{"operation":"transmit"})
	check(mutation+" real command starts transmission",started.ok,started)
	if not started.ok:return
	for i:int in 3:runtime.tick(0.1)
	var actor:Dictionary=runtime.actor("player")
	var pack:Dictionary=actor.pack.duplicate(true)
	var skills:Dictionary=actor.skills.duplicate(true)
	var at:Vector3=Geometry.point(actor)
	var progress:float=float(runtime.world.extension(Gameplay.KEY).radio.signal)
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
	if mutation=="incapacitated":tx.actor("player").hp=0.0
	elif mutation=="already_completed":tx.extension(Gameplay.KEY).radio.status="connected"
	else:
		var structures:Dictionary=tx.extension("r3:structures")
		var instance:Dictionary=preload("res://scripts/actions/domain_draft.gd").find(structures.instances,bench)
		var entity:Dictionary=runtime.world.entity(bench)
		if mutation=="removed":
			structures.instances=structures.instances.filter(func(v:Dictionary)->bool:return v.id!=bench)
			tx.extra.append({"op":"entity.remove","id":bench,"before_exists":true,"before":entity,"after":null})
		else:
			if mutation=="owner":instance.owner="unrelated:owner"
			elif mutation=="definition":instance.definitionId="cabinet"
			else:instance.hp=0.0
			var after:Dictionary=entity.duplicate(true)
			after.data.structure=instance.duplicate(true)
			after.definitionId=instance.definitionId
			tx.extra.append({"op":"entity.put","id":bench,"before_exists":true,"before":entity,"after":after})
	var committed:Dictionary=runtime._commit(tx.result())
	check(mutation+" stationary change passes A/C/B real transaction",committed.ok,committed)
	if not committed.ok:return
	# Do not depend on runtime status/death policy to exercise E cancellation.
	var cancelled:Dictionary=runtime._services.gameplay.advance(0.1)
	check(mutation+" E continuous cancellation commits",cancelled.ok and runtime._commit(cancelled).ok,cancelled.get("reason"))
	var final:Dictionary=runtime.actor("player")
	check(mutation+" no movement elapsed reward or debit after invalidation",final.intent==null and Geometry.point(final)==at and final.pack==pack and final.skills==skills and float(runtime.world.extension(Gameplay.KEY).radio.signal)==progress,final)
	var retry:Dictionary=send("radio",bench,{"operation":"transmit"})
	check(mutation+" same invalid station cannot restart",not retry.ok,retry)
	if mutation!="incapacitated":roundtrip(mutation+" cancellation and finite resources")
