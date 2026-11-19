extends "res://tests/gameplay/factory_normal_cooperative.gd"
## R34-56 actual N3 cargo pause, paid defense and original delivery resumption.
var tracked_task:String=""
var tracked_actor:String=""
var tracked_total:float=-1.0
var invariant_failures:Array=[]
var actual_delivery_events:Dictionary={}
var paused_seen:bool=false
var paid_need_events:Dictionary={}
func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=save(runtime,label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	var same:bool=restored.get("ok",false) and persisted_restore_equal(decoded.capture,restored.runtime.facts(),restored.world)
	check("canonical N3 interrupted state restores complete facts all extensions and entities "+label,same,restored.get("reason"))
	return restored if same else {"ok":false}
func observe(runtime:RefCounted)->void:
	super.observe(runtime)
	for event:Dictionary in runtime.facts().ledger:
		if event.kind=="logistics-delivery-completed" and event.get("task_id")==tracked_task:actual_delivery_events[event.id]=event.duplicate(true)
		if event.kind=="life-completed" and event.get("actor_id")==tracked_actor:paid_need_events[event.id]=event.duplicate(true)
	if tracked_total>=0:
		var task:Dictionary=find_task(runtime,tracked_task)
		if total_timber(runtime)!=tracked_total:invariant_failures.append({"at":runtime.clock(),"reason":"finite_timber_changed"})
		if task.get("phase")=="deliver" and task.get("actor_id")!=tracked_actor:invariant_failures.append({"at":runtime.clock(),"reason":"carrier_changed"})
		if task.get("trips",0)>1:invariant_failures.append({"at":runtime.clock(),"reason":"duplicate_trip"})
		if task.get("status")=="cargo_held" and task.get("reason")=="safe_handoff":
			paused_seen=true
			var reservation:bool=runtime.world.extension("r34:logistics").reservations.any(func(row:Dictionary)->bool:return row.task_id==tracked_task)
			if reservation:invariant_failures.append({"at":runtime.clock(),"reason":"paused_reservation_retained"})
	for actor:Dictionary in runtime.facts().actors:
		if actor.get("intent") is Dictionary and actor.intent.get("kind")=="guard" and actor.pack.get("timber",0)==1:
			costs.get_or_add("carrying_guard_ids",{})[actor.id]=true
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"stages":stage_rows,"guard_hits":guard_hits,"guard_routes":route_observations,"costs":costs,"cargo_invariants":{"violations":invariant_failures,"original_task":tracked_task,"original_actor":tracked_actor,"original_total":tracked_total,"paused_by_B":paused_seen,"delivery_events":actual_delivery_events,"paid_need_events":paid_need_events},"prerequisite":{"path":source_path,"sha256":source_sha},"scope":"R34-56 actual C4 normal53 continuation; real finite cargo, onsite risk, B safe pause, N3 guard/combat, N2 original care and original cargo resumption. No fixture body, task, clock or stock. Source/headless only."},"	",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
func total_timber(runtime:RefCounted)->float:
	var total:float=0
	for row:Dictionary in runtime.facts().stocks:total+=float(row.items.get("timber",0))
	for row:Dictionary in runtime.facts().actors:total+=float(row.pack.get("timber",0))
	return total
func find_task(runtime:RefCounted,id:String)->Dictionary:
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.id==id:return row
	return {}
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("explicit A normal-economy prerequisite decodes without fact edits",decoded.ok,decoded.get("reason"))
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("normal economic success save reassembles actual services",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world;var query:RefCounted=built.services.buildings.current_space()
	for region_id:String in ["RH-HOME","RH-VILLAGE"]:
		var warming:Array=[]
		while not world.region_is_resident(region_id):
			var warm:Dictionary=world.prepare_region_residency(region_id,true,world.get_revision(),32)
			var committed:Dictionary=runtime._commit({"world_changes":warm.get("world_changes",[]),"fact_changes":[],"events":[]}) if warm.get("ok",false) else warm
			warming.append({"prepare":warm.get("cost"),"commit":committed.get("ok"),"remaining":warm.get("remaining_chunks")})
			if not committed.get("ok",false):check("actual persisted C pages warm target region "+region_id,false,committed);return finish()
		costs["page_warm:"+region_id]=warming
	var people:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")!="infected")
	check("prerequisite has only original three living people with real consent and returned home",people.size()==3 and people.all(func(a:Dictionary)->bool:return a.hp>0 and (a.id=="player" or (a.relationship.member and a.relationship.consent and a.relationship.home_arrived))))
	if people.size()!=3:return finish()
	note(runtime,"restored explicit normal economy prerequisite")
	for task:Dictionary in world.extension("r34:logistics").tasks:
		if task.status in ["cancelled","completed"]:continue
		var cancelled:Dictionary=send(runtime,"logistics.cancel",str(task.id))
		check("completed repeat logistics yields through original cancel command",cancelled.ok,cancelled)
		if not cancelled.ok:return finish()
	if not prepare_defense_supplies(runtime):return finish()
	var pickaxe:String="RH-HOME:stockyard-content:container:tool:pickaxe"
	var combat_tool:String=pickaxe
	for tool:Dictionary in world.extension("r3:production").tools:
		if tool.kind=="pickaxe" and tool.holderId=="pack:player":pickaxe=tool.id
		if tool.kind=="salvaged_axe" and tool.holderId=="pack:player":combat_tool=tool.id
	check("clearance uses the original paid normal pickaxe in player pack",runtime.tool(pickaxe).get("holderId")=="pack:player")
	var site:Dictionary=world.extension("generation:RH-VILLAGE").regional_sites[0]
	costs.route_context={"home_detailed":runtime.region_is_detailed("RH-HOME"),"village_detailed":runtime.region_is_detailed("RH-VILLAGE"),"home_resident":world.region_is_resident("RH-HOME"),"village_resident":world.region_is_resident("RH-VILLAGE"),"home_paths":world.extension("generation:RH-HOME").paths,"village_paths":world.extension("generation:RH-VILLAGE").paths}
	save(runtime,"actual-before-survey-route")
	note(runtime,"finite companion supplies delivered before survey route")
	var approached:Dictionary=walk(runtime,site.survey_point)
	check("normal cooperative player physically reaches original stone survey",approached.get("ok",false),{"route":approached,"from":stage_rows[-1].actors[0].location,"to":site.survey_point})
	if not approached.get("ok",false):return finish()
	var surveyed:Dictionary=send(runtime,"settlement.survey","",{"site_id":site.id})
	check("normal cooperative survey is an actual onsite committed command",surveyed.ok,surveyed)
	if not surveyed.ok:return finish()
	note(runtime,"onsite surveyed before accepting risk")
	var guard_targets:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.job=="guard")
	var guard_route_probe:Array=[]
	for id:String in guards:
		var actor:Dictionary=runtime.actor(id)
		var route:Dictionary=runtime._services.actions.route(id,Geometry.location(actor),site.warning_points.approach_after)
		guard_route_probe.append({"actor_id":id,"actor":actor,"destination":site.warning_points.approach_after,"route":route,"standing":query.standing_point(site.warning_points.approach_after),"region_detailed":runtime.region_is_detailed(str(actor.regionId))})
	var guard_page:Dictionary={"world_identity":world.identity(),"world_revision":world.get_revision(),"runtime_revision":runtime.get_revision(),"actors":runtime.facts().actors,"site":site,"home":world.extension(Gameplay.KEY).layout.home,"regional_event":runtime._services.workforce.projection("*").regional_event,"work_targets":runtime.work_targets(),"guard_route_probe":guard_route_probe,"region_home":world.region("RH-HOME"),"region_village":world.region("RH-VILLAGE"),"residency":{"home":world.region_residency_state("RH-HOME"),"village":world.region_residency_state("RH-VILLAGE")}}
	costs.guard_page=guard_page
	check("normal UI job selector exposes a real surveyed regional guard target",not guard_targets.is_empty(),{"guard_targets":guard_targets,"guard_route_probe":guard_route_probe})
	if guard_targets.is_empty():stage_failure="normal guard target unavailable after real survey; see guard_page";return finish()
	var target:Dictionary=guard_targets.filter(func(t:Dictionary)->bool:return t.get("actual_target_id")==site.id or t.id==site.id or t.get("work_payload",{}).get("site_id")==site.id)[0] if guard_targets.any(func(t:Dictionary)->bool:return t.get("actual_target_id")==site.id or t.id==site.id or t.get("work_payload",{}).get("site_id")==site.id) else guard_targets[0]
	for id:String in guards:
		var assigned:Dictionary=send(runtime,"job",id,{"job":"guard","work_target_id":target.id})
		check("real consenting original companion assigned guard by normal Runtime job "+id,assigned.ok,assigned)
		if not assigned.ok:return finish()
	# Real finite cargo is taken before the informed regional warning.
	var cargo_source:String=route_stock(runtime,"warehouse","storage")
	var cargo_destination:String=route_stock(runtime,"machine","output")
	var cargo_before:float=float(runtime.stock(cargo_source).items.get("timber",0))
	var cargo_total:float=total_timber(runtime)
	var cargo_ids:Array=world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var cargo_created:Dictionary=send(runtime,"logistics.create","",{"source_id":cargo_source,"destination_id":cargo_destination,"items":{"timber":1},"repeat":false})
	check("N3 setup configures one finite real board without moving it",cargo_created.ok and total_timber(runtime)==cargo_total and runtime.stock(cargo_source).items.timber==cargo_before,cargo_created)
	var cargo_task_id:String=""
	for row:Dictionary in world.extension("r34:logistics").tasks:
		if not cargo_ids.has(row.id):cargo_task_id=row.id
	var cargo_actor:String=""
	for i:int in 700:
		step(runtime)
		var cargo_row:Dictionary=find_task(runtime,cargo_task_id)
		if cargo_row.get("phase")=="deliver" and not str(cargo_row.get("actor_id","" )).is_empty():cargo_actor=str(cargo_row.actor_id);break
	check("N3 setup obtains real finite cargo in an original companion pack",cargo_actor in guards and runtime.actor(cargo_actor).pack.get("timber")==1 and total_timber(runtime)==cargo_total,{"task":find_task(runtime,cargo_task_id),"actor":cargo_actor})
	if cargo_actor.is_empty():return finish()
	tracked_task=cargo_task_id;tracked_actor=cargo_actor;tracked_total=cargo_total
	var risk:Dictionary=send(runtime,"settlement.begin_route_work","",{"site_id":site.id,"accept_risk":true})
	check("onsite informed normal cooperative risk opens finite warning",risk.ok,risk)
	if not risk.ok:return finish()
	step(runtime);note(runtime,"risk accepted and dispatch requested")
	var n3_actor:Dictionary=runtime.actor(cargo_actor)
	var n3_decision:Dictionary=n3_actor.get("self_routine",{}).get("factory_decision",{})
	var n3_task:Dictionary=find_task(runtime,cargo_task_id)
	check("N3 carrying observation retains the real pack and task identity",n3_actor.pack.get("timber")==1 and n3_task.actor_id==cargo_actor and n3_task.phase=="deliver" and total_timber(runtime)==cargo_total,{"actor":n3_actor,"task":n3_task,"decision":n3_decision})
	check("N3 carrying observation records a real defense decision or explicit B handoff block",n3_decision.get("priority")=="N3" or n3_actor.get("self_routine",{}).get("last_failure",{}).get("code")=="CARGO_HANDOFF_REQUIRED",{"decision":n3_decision,"actor":n3_actor})

	var home:Dictionary=world.extension(Gameplay.KEY).layout.home
	var returned:Dictionary=walk(runtime,home)
	check("normal cooperative player really returns for finite preparation",returned.get("ok",false),returned)
	if not returned.get("ok",false):return finish()
	for kind:String in ["drink","eat"]:
		var care:Dictionary=send(runtime,kind)
		check("normal cooperative player pays finite "+kind,care.ok and progress(runtime,20).finished,care)
	check("normal cooperative preparation uses original twelve second rest",rest_once(runtime))
	check("B emergency pause holds same original cargo and releases its capacity reservation",paused_seen and runtime.actor(cargo_actor).pack.get("timber")==1 and find_task(runtime,cargo_task_id).status=="cargo_held" and find_task(runtime,cargo_task_id).reason=="safe_handoff" and find_task(runtime,cargo_task_id).trips==0,{"task":find_task(runtime,cargo_task_id),"actor":runtime.actor(cargo_actor)})
	note(runtime,"home finite supplies and recovery complete")
	var restored:Dictionary=cold_restore(runtime,"prepared-guards-enroute")
	if not restored.ok:return finish()
	runtime=restored.runtime;world=restored.world;query=restored.services.buildings.current_space()
	var deployed:Dictionary=walk(runtime,site.warning_points.approach_after)
	check("normal prepared player reaches C real defense point through bypass",deployed.get("ok",false),deployed)
	if not deployed.get("ok",false):return finish()
	check("normal defender finishes one necessary recovery action",rest_once(runtime))
	note(runtime,"player at defense after necessary preparation")
	var remaining:float=world.extension(Gameplay.KEY).defense.get("warning_remaining",0)
	check("warning covers actual return supply recovery and field deployment",world.extension(Gameplay.KEY).defense.status=="warning" and remaining>=10,remaining)
	var field:Dictionary=site.warning_points.approach_after.duplicate(true);field.z-=8.0;field=query.standing_point(field)
	var field_walk:Dictionary=walk(runtime,field) if not field.is_empty() else {"ok":false}
	check("normal player takes supported open ground beyond the stone defense",field_walk.get("ok",false),field_walk)
	if not field_walk.get("ok",false):return finish()
	remaining=world.extension(Gameplay.KEY).defense.get("warning_remaining",0)
	for i in ceili(remaining*10)+5:
		step(runtime)
		if world.extension(Gameplay.KEY).defense.status=="active":break
	note(runtime,"finite original enemies arrive")
	var state:Dictionary=world.extension(Gameplay.KEY)
	check("actual finite warning spawns original three without waiting for home",state.defense.status=="active" and state.defense.actors.size()==3,state.defense)
	check("original cargo carrier actually traverses B guard route with original board",costs.get("carrying_guard_ids",{}).has(cargo_actor),costs.get("carrying_guard_ids"))
	check("both normal guards traverse B actual route toward the real defense point",route_observations.size()==2,route_observations)
	if state.defense.status!="active":return finish()
	var partial_saved:bool=false
	for i in 1000:
		state=world.extension(Gameplay.KEY)
		var alive:Array=state.defense.actors.filter(func(id:String)->bool:return runtime.actor(id).hp>0)
		if alive.is_empty() or runtime.actor("player").hp<=0:break
		var player:Dictionary=runtime.actor("player")
		if not partial_saved and guard_hits.size()>0:
			partial_saved=true;note(runtime,"actual guard combat before cold restoration")
			restored=cold_restore(runtime,"actual-companion-partial-combat")
			if not restored.ok:return finish()
			runtime=restored.runtime;world=restored.world;query=restored.services.buildings.current_space()
		if player.get("intent")!=null:step(runtime);continue
		alive.sort_custom(func(a:String,b:String)->bool:return Geometry.point(runtime.actor(a)).distance_squared_to(Geometry.point(player))<Geometry.point(runtime.actor(b)).distance_squared_to(Geometry.point(player)))
		var enemy:Dictionary=runtime.actor(str(alive[0]));var distance:float=Geometry.point(enemy).distance_to(Geometry.point(player))
		if distance>3.0:
			var direction:Vector3=(Geometry.point(enemy)-Geometry.point(player)).normalized()
			var approach:Dictionary=Geometry.location(player);approach.x+=direction.x*minf(2.5,distance-2.6);approach.z+=direction.z*minf(2.5,distance-2.6)
			approach=query.standing_point(approach)
			var advanced:Dictionary=walk(runtime,approach) if not approach.is_empty() else {"ok":false}
			costs.get_or_add("combat_approaches",[]).append({"time":runtime.clock(),"ok":advanced.get("ok",false),"reason":advanced.get("reason"),"from":Geometry.location(player),"to":approach})
			if not advanced.get("ok",false):break
			continue
		if player.stamina<28:
			for retreat in 6:
				if not evade(runtime,query,alive):break
			var recovery:Dictionary=send(runtime,"rest")
			if recovery.ok:progress(runtime,120)
			continue
		if distance<=2.0 and float(player.get("cooldown",0))<=0:
			var struck:Dictionary=send(runtime,"attack",str(alive[0]),{"tool_id":combat_tool})
			costs.get_or_add("player_strikes",[]).append({"time":runtime.clock(),"request":struck,"stamina":runtime.actor("player").stamina})
			if not struck.ok:break
			var living:Array=alive.filter(func(id:String)->bool:return runtime.actor(id).hp>0)
			if not living.is_empty():evade(runtime,query,living)
		else:step(runtime)
	step(runtime);note(runtime,"cooperative defense outcome")
	state=world.extension(Gameplay.KEY)
	check("normal cooperation uses actual companion paid combat rather than assigned labor label",guard_hits.size()>0,guard_hits)
	check("normal cooperative finite defense ends only after all actual enemies die",state.defense.status=="cleared" and guards.all(func(id:String)->bool:return runtime.actor(id).hp>0) and runtime.actor("player").hp>0,state.defense)
	if state.defense.status!="cleared" or runtime.actor("player").hp<=0:return finish()
	var original_pack:float=float(runtime.actor(cargo_actor).pack.get("timber",0))
	check("actual paid defense never loses or duplicates finite carried boards",total_timber(runtime)==cargo_total and original_pack in [0.0,1.0],{"actor":runtime.actor(cargo_actor),"task":find_task(runtime,cargo_task_id)})
	for i:int in 1400:
		step(runtime)
		if find_task(runtime,cargo_task_id).status=="completed":break
	var final_task:Dictionary=find_task(runtime,cargo_task_id)
	check("after real threat original carrier resumes and delivers original cargo once",final_task.status=="completed" and final_task.trips==1 and runtime.actor(cargo_actor).pack.get("timber",0)==0 and total_timber(runtime)==cargo_total,{"actor":runtime.actor(cargo_actor),"task":final_task})
	check("every observed fixed step preserves one cargo owner and exact finite total",invariant_failures.is_empty(),invariant_failures)
	check("only the original carrier records exactly one original-task delivery",actual_delivery_events.size()==1 and actual_delivery_events.values()[0].actor_id==cargo_actor,actual_delivery_events)
	note(runtime,"N3 original cargo after actual cleared threat")
	var final_restore:Dictionary=cold_restore(runtime,"n3-original-cargo-resumed")
	check("final native restore retains original single delivered trip and all boards",final_restore.ok and find_task(final_restore.runtime,cargo_task_id).trips==1 and total_timber(final_restore.runtime)==cargo_total)
	finish()
