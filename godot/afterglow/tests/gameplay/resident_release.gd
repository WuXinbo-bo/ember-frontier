extends SceneTree
## Pure E provider contract. Deliberately unconfigured service: no live
## authority/world/clock exists here to mutate. A owns transaction integration.
const Residents=preload("res://scripts/runtime/resident_life.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]

func _initialize()->void:call_deferred("run")

func check(name:String,ok:bool)->void:
	checks.append({"name":name,"ok":ok})
	if not ok:push_error("FAIL "+name)

func actor(id:String)->Dictionary:
	return {"id":id,"hp":0.0,"x":12.0,"y":1.5,"z":30.0,"pack":{"log":3,"water":1},"intent":{"owner":"actions","kind":"haul","id":"actual-order-reference","opaque":{"step":17}},"pending_delivery":{"phase":"deliver","destination_id":"original:home:storage","items":{"log":3}},"suspended_work":{"intent":{"order_id":"original-order"}},"skills":{"gathering":2},"relationship":{"member":true,"consent":false},"self_routine":{"version":1,"origin":{"x":8.0,"y":1.5,"z":20.0,"regionId":"original-region"},"phase":3,"next_decision":9999.0,"last_failure":{"code":"OLD_ROUTE_FAILURE"},"retained_extension":{"key":"original"}}}

func run()->void:
	var service:=Residents.new()
	var id:="ordinary:release"
	var baseline:Dictionary={"time":17.0,"status":"playing","actors":[actor(id)],"stocks":[{"id":"original:home:storage","items":{"log":0}}],"ledger":[]}
	var pending:Array=[{"op":"extension.set","id":"r3:production","before_exists":true,"before":{"original":1},"after":{"opaque_request_change":true}}]
	var baseline_copy:Dictionary=baseline.duplicate(true)
	var pending_copy:Array=pending.duplicate(true)
	for kind:String in ["incapacitated","consent_revoked"]:
		var observed:Dictionary=baseline.duplicate(true)
		if kind=="consent_revoked":observed.actors[0].hp=80.0
		var transitions:Array=[{"actor_id":id,"kind":kind}]
		var transition_copy:Array=transitions.duplicate(true)
		var observed_copy:Dictionary=observed.duplicate(true)
		var plan:Dictionary=service.prepare_actor_release(transitions,observed,pending)
		check(kind+" returns one pure actor scheduling draft",plan.ok and plan.fact_changes.size()==1 and plan.world_changes.is_empty() and plan.events.is_empty())
		if not plan.ok or plan.fact_changes.size()!=1:continue
		var change:Dictionary=plan.fact_changes[0]
		check(kind+" CAS before is exact already-staged input",change.collection=="actors" and change.id==id and Data.json_equal(change.before,observed.actors[0]))
		var expected:Dictionary=observed.actors[0].duplicate(true)
		expected.self_routine.next_decision=0.0;expected.self_routine.erase("last_failure")
		check(kind+" changes only next decision and stale E failure",Data.json_equal(change.after,expected))
		check(kind+" preserves actual pack cargo orders intent skills location",Data.json_equal(change.after.pack,observed.actors[0].pack) and Data.json_equal(change.after.pending_delivery,observed.actors[0].pending_delivery) and Data.json_equal(change.after.suspended_work,observed.actors[0].suspended_work) and Data.json_equal(change.after.intent,observed.actors[0].intent))
		check(kind+" preserves origin phase and unknown routine extensions",Data.json_equal(change.after.self_routine.origin,observed.actors[0].self_routine.origin) and change.after.self_routine.phase==3 and change.after.self_routine.retained_extension.key=="original")
		check(kind+" leaves every caller argument exact",Data.json_equal(observed,observed_copy) and Data.json_equal(transitions,transition_copy) and Data.json_equal(pending,pending_copy))
		change.before.pack.log=999;change.after.pack.log=888;change.after.pending_delivery.items.log=777
		check(kind+" returned before after and nested cargo do not alias input",Data.json_equal(observed,observed_copy) and change.before.pack.log!=change.after.pack.log)
		var cleaned:Dictionary=observed.duplicate(true);cleaned.actors[0]=expected
		check(kind+" repeated scheduling cleanup is idempotent",service.prepare_actor_release(transitions,cleaned,pending).fact_changes.is_empty())
	for intent:Variant in [null,{"owner":"runtime","kind":"rest","id":"original:rest"},{"owner":"residents","kind":"walk","id":"original:walk"},{"owner":"terrain","kind":"work","id":"original:terrain"},{"owner":"gameplay","kind":"radio","id":"original:radio"}]:
		var observed:Dictionary=baseline.duplicate(true);observed.actors[0].intent=intent
		var plan:Dictionary=service.prepare_actor_release([{"actor_id":id,"kind":"incapacitated"}],observed,pending)
		check("E leaves "+str(intent.get("owner") if intent is Dictionary else "empty")+" intent to A central release",plan.ok and Data.json_equal(plan.fact_changes[0].after.intent,intent))
	var absent:Dictionary=baseline.duplicate(true);absent.actors=[]
	var removed:Dictionary=service.prepare_actor_release([{"actor_id":id,"kind":"removed"}],absent,pending)
	check("removed actor is not reinserted and no stock refund is created",removed.ok and removed.fact_changes.is_empty() and removed.world_changes.is_empty() and removed.events.is_empty() and absent.actors.is_empty())
	var no_routine:Dictionary=baseline.duplicate(true);no_routine.actors[0].erase("self_routine")
	check("unregistered routine is not invented during release",service.prepare_actor_release([{"actor_id":id,"kind":"incapacitated"}],no_routine,pending).fact_changes.is_empty())
	for routine:Variant in [{},null]:
		no_routine=baseline.duplicate(true);no_routine.actors[0].self_routine=routine
		check("empty or null routine keeps next normal decision initialization intact "+str(routine),service.prepare_actor_release([{"actor_id":id,"kind":"incapacitated"}],no_routine,pending).fact_changes.is_empty())
	check("no lifecycle transitions has no side effects",service.prepare_actor_release([],baseline,pending).fact_changes.is_empty())
	# Same request also changed finite cargo and position. CAS must use these
	# staged values, never a context/current-world read or a prior actor copy.
	var staged:Dictionary=baseline.duplicate(true);staged.actors[0].pack.log=2;staged.actors[0].pending_delivery.items.log=2;staged.actors[0].x=12.25
	var prepared:Dictionary=service.prepare_actor_release([{"actor_id":id,"kind":"incapacitated"}],staged,pending)
	check("same-request legitimate staged cargo position changes survive",prepared.ok and prepared.fact_changes[0].before.pack.log==2 and prepared.fact_changes[0].after.pack.log==2 and prepared.fact_changes[0].after.pending_delivery.items.log==2 and prepared.fact_changes[0].after.x==12.25)
	for invalid:Array in [[{"actor_id":id,"kind":"revive"}],[{"actor_id":"","kind":"incapacitated"}],[{"actor_id":42,"kind":"incapacitated"}],["invalid"],[{"actor_id":id,"kind":"removed"}],[{"actor_id":"absent:person","kind":"incapacitated"}],[{"actor_id":id,"kind":"incapacitated"},{"actor_id":id,"kind":"consent_revoked"}],[{"actor_id":id,"kind":"incapacitated"},{"actor_id":"absent:person","kind":"incapacitated"}]]:
		var bad:Dictionary=service.prepare_actor_release(invalid,baseline,pending)
		check("malformed or inconsistent transition rejects whole E draft "+str(checks.size()),not bad.ok and bad.fact_changes.is_empty() and bad.world_changes.is_empty() and bad.events.is_empty() and Data.json_equal(baseline,baseline_copy) and Data.json_equal(pending,pending_copy))
	check("missing observed actors rejects clearly",not service.prepare_actor_release([],{"time":17.0},pending).ok)
	var mixed:Dictionary=baseline.duplicate(true);mixed.actors.append(actor("ordinary:second"))
	var batch:Dictionary=service.prepare_actor_release([{"actor_id":id,"kind":"incapacitated"},{"actor_id":"ordinary:second","kind":"consent_revoked"},{"actor_id":"ordinary:removed","kind":"removed"}],mixed,pending)
	check("multiple ordinary actors yield exactly separate scheduling CAS changes",batch.ok and batch.fact_changes.size()==2 and batch.fact_changes[0].id==id and batch.fact_changes[1].id=="ordinary:second")
	check("pure release does not change clock stocks ledger or any input",Data.json_equal(baseline,baseline_copy) and Data.json_equal(pending,pending_copy))
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"E pure post-staged lifecycle scheduling contract; A/B atomic integration is separate","checks":checks,"failed":failed},"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
