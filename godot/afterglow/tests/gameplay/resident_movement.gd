extends "res://tests/gameplay/generated_cooperation.gd"
## Real generated routes and A's one movement policy. High fatigue/prepared
## bed/visible stunned threat are explicit fixtures, not natural play claims.

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="generated-resident-motion-with-explicit-fatigue-bed-threat-fixtures"
	host=Client.new()
	var generated:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("current real generated settlement prepares for shared motion",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):finish();return
	check("A shared movement budget is actually installed",runtime.has_method("movement_budget"))
	if not runtime.has_method("movement_budget"):finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	write_json("unmodified-opening-capture.json",baseline)
	bed_route(baseline)
	no_bed_and_cap(baseline)
	avoid_motion(baseline,false)
	avoid_motion(baseline,true)
	finish()

func tired_fixture(baseline:Dictionary,prepared:bool)->Dictionary:
	var fixture:Dictionary=baseline.duplicate(true)
	for entity:Dictionary in fixture.world.entities.values():
		if entity.get("data",{}).get("sleeping",false) and entity.data.get("owner")=="village-resident":entity.data.prepared=prepared
	for a:Dictionary in fixture.facts.actors:
		if a.id=="village-resident":
			a.fatigue=75.0;a.stamina=Movement.stamina_max(a);a.intent=null;a.erase("self_routine")
	return fixture

func bed_route(baseline:Dictionary)->void:
	if not mount(tired_fixture(baseline,true)):return
	var id:="village-resident"
	var start:Vector3=Geometry.point(runtime.actor(id))
	var actual_stocks:Array=runtime.facts().stocks.duplicate(true)
	var walked:=false;var used_bed:=false;var done:=false;var wrong_recovery:Array=[];var over_cap:Array=[]
	var saved:=false
	for i:int in 1800:
		var before:Dictionary=runtime.actor(id);var old_intent:Variant=before.get("intent")
		step()
		var a:Dictionary=runtime.actor(id);var intent:Variant=a.get("intent")
		if intent is Dictionary and intent.get("owner")=="residents" and intent.get("purpose")=="bed":
			walked=true
			if intent.get("movement_mode")!="walk":wrong_recovery.append("ordinary bed route requested run")
			if not saved and i>20:
				saved=true
				if not roundtrip("in-progress real tired-resident bed route"):return
		if intent is Dictionary and intent.get("owner")=="runtime" and intent.get("kind")=="rest" and not str(intent.get("target_id","")).is_empty():used_bed=true
		var cap:float=float(runtime.movement_budget(id,0.1,"walk").stamina_max)
		if float(a.stamina)>cap+0.000001:over_cap.append({"stamina":a.stamina,"cap":cap})
		if float(a.fatigue)<float(before.fatigue)-0.000001 and not (old_intent is Dictionary and old_intent.get("owner")=="runtime" and old_intent.get("kind")=="rest" and not str(old_intent.get("target_id","")).is_empty()):wrong_recovery.append({"before":before,"after":a})
		if float(a.fatigue)<=40.0:done=true;break
	check("fatigue-only request physically crosses original route to real prepared bed",walked and used_bed and Geometry.point(runtime.actor(id)).distance_to(start)>20.0)
	check("A bed rest alone lowers fatigue to policy exit, no duplicate recovery",done and wrong_recovery.is_empty(),wrong_recovery)
	check("all tired walk/rest states remain at A effective stamina ceiling",over_cap.is_empty(),over_cap)
	check("sleep never consumes team stock or grants recruitment",Data.json_equal(actual_stocks,runtime.facts().stocks) and not runtime.actor(id).relationship.member and not runtime.actor(id).relationship.consent)
	check("bed route has actual in-progress native save/restore",saved)
	step()
	check("sleep decision exits its hysteresis after genuine fatigue recovery",not runtime.actor(id).self_routine.get("seeking_sleep",false))

func no_bed_and_cap(baseline:Dictionary)->void:
	var fixture:Dictionary=tired_fixture(baseline,false)
	for a:Dictionary in fixture.facts.actors:
		if a.id=="village-resident":a.fatigue=100.0;a.stamina=30.0
	if not mount(fixture):return
	var id:="village-resident";var life:RefCounted=runtime._services.residents
	check("need uses A cap instead of impossible absolute rest target",life._need(runtime.actor(id))=="bed")
	for i:int in 5:step()
	var a:Dictionary=runtime.actor(id)
	check("unprepared beds give real NO_BED without fake sleep or fatigue recovery",a.intent==null and a.self_routine.last_failure.code=="NO_BED" and float(a.fatigue)>=100.0,a)
	var joined:Dictionary=a.duplicate(true);joined.relationship={"member":true,"consent":true};joined.job="rest"
	check("voluntary rest may use self-care without claiming active B work",life._available_for_self(joined))
	joined.suspended_work={"intent":{"order_id":"explicit-guard-only-fixture"}}
	check("existing B suspended order excludes E self-care",not life._available_for_self(joined))
	joined.erase("suspended_work");joined.pending_delivery={"phase":"deliver"}
	check("actual held delivery excludes E self-care",not life._available_for_self(joined))
	joined.erase("pending_delivery");joined.job="craft"
	check("cooperative work stays with B executor",not life._available_for_self(joined))
	var resting:Dictionary=baseline.duplicate(true)
	for person:Dictionary in resting.facts.actors:
		if person.id==id:person.relationship={"member":true,"consent":true,"home_arrived":true};person.job="rest"
	if mount(resting):
		var at:Vector3=Geometry.point(runtime.actor(id))
		for i:int in 20:step()
		var intent:Variant=runtime.actor(id).intent
		check("actual voluntary rest does not restart pre-joining patrol",not (intent is Dictionary and intent.get("owner")=="residents") and Geometry.point(runtime.actor(id)).distance_to(at)<0.001,runtime.actor(id))

func avoid_motion(baseline:Dictionary,exhausted:bool)->void:
	if not mount(baseline):return
	var id:="village-resident";var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.residents.context)
	var a:Dictionary=tx.actor(id)
	if exhausted:a.stamina=1.0
	var points:Array=runtime._services.residents._destinations(a,runtime._services.residents._routine(a),tx)
	points=points.filter(func(p:Dictionary)->bool:return Geometry.point(p).distance_to(Geometry.point(a))>=0.6 and Geometry.point(p).distance_to(Geometry.point(a))<6.0 and runtime._services.buildings.current_space().line_clear(Geometry.location(a),p,""))
	check("real nearby supported LOS threat fixture exists "+str(exhausted),not points.is_empty())
	if points.is_empty():return
	var enemy:Dictionary=Initial.actor("infected:E-motion-fixture","explicit visible stunned threat",points[0],points[0],{})
	enemy.faction="infected";enemy.appearance_id="infected_walker";enemy.stunned_until=1000.0;tx.staged.actors.append(enemy)
	check("explicit stunned threat installs through one valid runtime transaction "+str(exhausted),runtime._commit(tx.result()).ok)
	var moved:=false;var invalid:Array=[];var run_requested:=false
	for i:int in 18:
		var before:Dictionary=runtime.actor(id)
		step()
		var after:Dictionary=runtime.actor(id)
		if after.get("intent") is Dictionary and after.intent.get("purpose")=="avoid":run_requested=run_requested or after.intent.get("movement_mode")=="run"
		var distance:float=Vector2(float(after.x)-float(before.x),float(after.z)-float(before.z)).length()
		if distance<=0.000001:continue
		moved=true
		var display:Dictionary=runtime.actor_presentation().movement[id]
		if exhausted:
			if display.mode!="walk" or distance>Movement.WALK_SPEED*0.1+0.001:invalid.append(display)
		elif display.mode!="run" or absf(float(before.stamina)-float(after.stamina)-distance*0.8)>0.00001:invalid.append({"before":before.stamina,"after":after.stamina,"distance":distance,"display":display})
	check("only genuine avoidance requests run "+str(exhausted),run_requested)
	check("exhaustion downgrades actual avoidance via A budget" if exhausted else "actual avoidance pays A run cost exactly once without idle recovery",moved and invalid.is_empty(),invalid)
	runtime.set_paused(true);var frozen:Dictionary=runtime.capture_checkpoint();runtime.tick(5)
	check("pause freezes one motion clock and all real facts "+str(exhausted),Data.json_equal(frozen,runtime.capture_checkpoint()))
	runtime.set_paused(false)
