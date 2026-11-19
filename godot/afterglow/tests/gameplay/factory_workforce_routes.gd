extends "res://tests/gameplay/factory_survival.gd"
## Explicit cooperation/warning fixtures; real C points, B routes, A commits.
const FactoryGameplay=preload("res://scripts/runtime/factory_gameplay.gd")
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("actual C B E normal opening configures for route contract",opening.ok)
	if not opening.ok:return finish()
	base=opening.capture.duplicate(true);npc_fixtures(base,80,1)
	var event:Dictionary=base.world.extensions[FactoryGameplay.KEY]
	var site:Dictionary=event.layout.regional_sites[0]
	event.event_ids.append("fixture:guard-cause");event.regional_events.append({"id":"fixture:guard-cause","kind":"fixture-route-commit","time":0.0})
	for a:Dictionary in base.facts.actors:
		if a.id=="repair-resident":a.relationship.member=true;a.relationship.consent=true;a.householdId="home-residents";a.job="guard"
	event.defense={"status":"warning","site_id":site.id,"warning_id":"fixture:guard-warning","warning_at":0.0,"arrival_at":300.0,"warning_remaining":300.0,"cause_event_id":"fixture:guard-cause","actors":[],"encounter_positions":site.encounter_positions.duplicate(true)}
	if not mount(base):return finish()
	var from:Dictionary=runtime.actor("repair-resident")
	check("guard decision commits same prepared B route",advance_decision().ok)
	var guard:Dictionary=runtime.actor("repair-resident")
	check("qualified consenting guard enters actual actions guard without teleport",guard.get("intent") is Dictionary and guard.intent.owner=="actions" and guard.intent.kind=="guard" and guard.intent.guard_site_id==site.id and Geometry.point(guard)==Geometry.point(from),guard)
	check("N3 selects C persistent warning point",guard.get("intent") is Dictionary and Data.json_equal(guard.intent.get("guard_destination"),site.warning_points.approach_after))
	check("non guard is never dispatched to defense",runtime.actor("village-resident").get("intent")==null)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	check("actual guard route survives native cold checkpoint",decoded.ok and mount(decoded.capture))
	var moved:float=0;var leaps:int=0;var unsupported:int=0
	var last:Vector3=Geometry.point(runtime.actor("repair-resident"))
	for i in 900:
		runtime.tick(0.1)
		guard=runtime.actor("repair-resident")
		var at:Vector3=Geometry.point(guard);var delta:Vector3=at-last
		moved+=delta.length()
		if Vector2(delta.x,delta.z).length()>Movement.WALK_SPEED*0.1+0.001 or absf(delta.y)>0.501:leaps+=1
		if runtime._services.buildings.current_space().standing_point(Geometry.location(guard)).is_empty():unsupported+=1
		last=at
		if guard.get("intent")==null and at.distance_to(Geometry.point(site.warning_points.approach_after))<=0.2:break
	check("guard physically arrives through supported bounded B steps",moved>1 and leaps==0 and unsupported==0 and Geometry.point(guard).distance_to(Geometry.point(site.warning_points.approach_after))<=0.2,{"distance":moved,"leaps":leaps,"unsupported":unsupported,"actor":guard})
	check("B guard arrival is actual ledger event",runtime.facts().ledger.any(func(e:Dictionary)->bool:return e.kind=="guard-arrived" and e.get("actor_id")=="repair-resident"))
	var arrival:Dictionary=Geometry.location(guard)
	for i in 20:runtime.tick(0.1)
	check("N3 holds actual position instead of cycling new travel or returning home",runtime.actor("repair-resident").get("intent")==null and Data.json_equal(Geometry.location(runtime.actor("repair-resident")),arrival) and runtime.actor("repair-resident").self_routine.factory_decision.priority=="N3")
	var before:Dictionary=runtime.actor("repair-resident");var thirsty:Dictionary=before.duplicate(true);thirsty.thirst=20
	check("real guard urgent need mutation commits",runtime._commit({"fact_changes":[{"collection":"actors","id":before.id,"before":before,"after":thirsty}],"world_changes":[],"events":[{"kind":"inventory-transfer","actor_id":"player"}]}).ok)
	runtime.tick(0.1)
	guard=runtime.actor("repair-resident")
	check("urgent N2 outranks guard hold using A paid drink",guard.get("intent") is Dictionary and guard.intent.owner=="runtime" and guard.intent.kind=="drink",guard)
	for i in 25:runtime.tick(0.1)
	check("guard consumes actual finite water and resumes same warning point",runtime.actor("repair-resident").pack.get("water")==0 and runtime.actor("repair-resident").thirst>64 and runtime.actor("repair-resident").self_routine.factory_decision.priority=="N3")
	var unjoined:Dictionary=base.duplicate(true)
	for a:Dictionary in unjoined.facts.actors:
		if a.id=="repair-resident":a.relationship.member=false;a.relationship.consent=false
	if not mount(unjoined):return finish()
	advance_decision()
	check("same site never grants guard authority without consent",not (runtime.actor("repair-resident").get("intent") is Dictionary and runtime.actor("repair-resident").intent.get("kind")=="guard"))
	finish()
func finish()->void:
	var report:Dictionary={"scope":"E N3 selects C persistent guard point, B physical approach/arrival and hold, A native restore and paid urgent care; explicit cooperation/warning fixture, not normal recruitment or OS/VA/package","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));host.free();quit(1 if report.failed else 0)
