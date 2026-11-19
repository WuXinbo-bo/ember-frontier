extends "res://tests/buildings/domain_suite.gd"
## Actual A runtime + B executor: no alternate clock, movement or charge API.
const Draft = preload("res://scripts/actions/domain_draft.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const ORIGIN = {"x":30.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}

func fixture(mode:String="human",stamina:float=100.0,fatigue:float=0.0)->void:
	var a:=resident("player",ORIGIN.duplicate(true))
	a.stamina=stamina;a.fatigue=fatigue
	if mode=="infected":a.faction="infected"
	var configured:=runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":{"time":0.0,"status":"playing","actors":[a],"stocks":[],"actions":[],"quests":[]}})
	expect("real runtime fixture configures "+mode,configured.ok,configured)

func destination(dx:float,dz:float=0.0)->Dictionary:
	var p:=Geometry.location(runtime.actor("player"));p.x+=dx;p.z+=dz
	return p

func distance(a:Dictionary,b:Dictionary)->float:
	return Vector2(float(b.x)-float(a.x),float(b.z)-float(a.z)).length()

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("actual retained rural terrain loads",world.load_snapshot(Generator.generate(713)).ok)
	fixture()
	var before:=runtime.capture_checkpoint()
	var request:Dictionary={"actor_id":"player","kind":"direct_move","destination":destination(0.46),"payload":{"movement_dt":0.1,"movement_mode":"run"}}
	var preview:=actions.prepare(request)
	expect("preview computes accepted movement without spending or ticking",preview.ok and preview.events.size()==1 and preview.events[0].kind=="actor-moved" and preview.events[0].mode=="run" and is_equal_approx(float(preview.events[0].elapsed),0.1) and runtime.capture_checkpoint()==before,preview)
	var from:=runtime.actor("player")
	var accepted:=command("direct_move","",request.payload,request.destination)
	expect("runtime commits exact authority run distance",accepted.ok and is_equal_approx(distance(from,runtime.actor("player")),0.46),accepted)
	expect("run charges exactly once in A, B has no extra debit",is_equal_approx(float(runtime.actor("player").stamina),99.632),runtime.actor("player").stamina)
	var display:Dictionary=runtime.actor_presentation().movement.player
	expect("actual movement presentation reports run and true speed",display.moving and display.mode=="run" and is_equal_approx(float(display.speed),4.6),display)
	before=runtime.capture_checkpoint()
	var exhausted:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},destination(0.01))
	expect("second command cannot reuse this tick allowance or spend stamina",not exhausted.ok and runtime.capture_checkpoint()==before,exhausted)
	runtime.tick(0.1)
	expect("successful run does not get idle recovery in its life tick",float(runtime.actor("player").stamina)<=99.632001,runtime.actor("player").stamina)

	fixture()
	from=runtime.actor("player")
	expect("legacy syntax still moves through one authority budget",command("move","",{},destination(0.99)).ok)
	expect("legacy far destination cannot bypass 0.1s walk allowance",is_equal_approx(distance(from,runtime.actor("player")),0.28))
	before=runtime.capture_checkpoint()
	expect("old greater-than-one-metre command remains rejected",not command("move","",{},destination(1.01)).ok and runtime.capture_checkpoint()==before)
	for invalid:Variant in [0.0,-0.1,0.10001,INF,"0.1",true]:
		fixture()
		before=runtime.capture_checkpoint()
		var rejected:=command("direct_move","",{"movement_dt":invalid,"movement_mode":"walk"},destination(0.01))
		expect("malformed duration rejected without authority mutation "+str(invalid),not rejected.ok and runtime.capture_checkpoint()==before,rejected)
	fixture()
	before=runtime.capture_checkpoint()
	expect("new explicit overspeed rejected without cancellation or cost",not command("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},destination(0.46)).ok and runtime.capture_checkpoint()==before)
	var still:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},destination(0.0))
	expect("stationary input has no movement event or run cost",still.ok and not still.get("changes",{}).get("events",[]).any(func(e:Dictionary)->bool:return e.kind=="actor-moved") and runtime.actor("player").stamina==100.0,still)

	fixture("human",9.0)
	from=runtime.actor("player")
	var fallback:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},destination(0.28))
	expect("low-stamina run requests use authority walk without run cost",fallback.ok and is_equal_approx(distance(from,runtime.actor("player")),0.28) and runtime.actor("player").stamina==9.0 and runtime.actor_presentation().movement.player.mode=="walk",fallback)
	fixture("human",11.0)
	var run_ticks:=0;var walk_ticks:=0;var charges_exact:=true
	for n in 26:
		var budget:Dictionary=runtime.movement_budget("player",0.1,"run")
		from=runtime.actor("player")
		var requested:=destination(float(budget.max_distance)*(1 if n%2==0 else -1))
		var moved:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},requested)
		var travelled:=distance(from,runtime.actor("player"))
		var cost:=travelled*0.8 if budget.mode=="run" else 0.0
		charges_exact=charges_exact and moved.ok and absf(float(runtime.actor("player").stamina)-(float(from.stamina)-cost))<0.00001
		if budget.mode=="run":run_ticks+=1
		else:walk_ticks+=1
		runtime.tick(0.1)
	expect("held run naturally reaches fallback across real shared-clock ticks with one debit",charges_exact and run_ticks>=2 and walk_ticks>0,{"run_ticks":run_ticks,"walk_ticks":walk_ticks,"stamina":runtime.actor("player").stamina})
	expect("depleted runner above initial threshold remains in recovery hysteresis",runtime.actor("player").get("run_recovering",false) and float(runtime.actor("player").stamina)>=10.0 and not runtime.movement_budget("player",0.1,"run").can_run,runtime.actor("player"))
	var saved:=runtime.capture_checkpoint()
	var encoded:=Store.encode(saved)
	var decoded:=Store.decode(encoded.get("text",""))
	expect("actual movement depletion encodes and decodes without user saves",encoded.ok and decoded.ok)
	if decoded.ok:
		var restored:=Runtime.new()
		var loaded:=restored.configure({"world":world,"facts":decoded.capture.facts,"source":decoded.capture.get("source",{}),"command_revision":decoded.capture.get("command_revision",0),"receipts":decoded.capture.get("receipts",{}),"services":{"buildings":Building.new(),"actions":Actions.new(),"production":Production.new()}})
		var saved_actor:=Draft.find(decoded.capture.facts.actors,"player")
		expect("restore retains exactly persisted stamina and no held-run state",loaded.ok and restored.actor("player").stamina==saved_actor.stamina and restored.actor("player").intent==null and not restored.actor_presentation().movement.player.moving and restored.actor_presentation().movement.player.mode=="idle")
		expect("native codec retains actual recovery latch without restoring held input",restored.actor("player").get("run_recovering",false)==saved_actor.get("run_recovering",false) and not restored.movement_budget("player",0.1,"run").can_run)
	var resumed:=false;var stable_recovery:=true;var resume_stamina:=0.0
	for n in 300:
		var budget:Dictionary=runtime.movement_budget("player",0.1,"run")
		from=runtime.actor("player")
		if budget.mode=="run":
			resumed=true;resume_stamina=float(from.stamina);break
		stable_recovery=stable_recovery and from.get("run_recovering",false) and not budget.can_run
		var moved:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},destination(float(budget.max_distance)*(1 if n%2==0 else -1)))
		stable_recovery=stable_recovery and moved.ok and runtime.actor("player").stamina==from.stamina and runtime.actor_presentation().movement.player.mode=="walk"
		runtime.tick(0.1)
	expect("continuous held run stays walk through 10 to 20 and resumes only at authority recovery threshold",stable_recovery and resumed and resume_stamina>=20.0 and not runtime.actor("player").get("run_recovering",true),{"resumed":resumed,"resume_stamina":resume_stamina})
	fixture("infected")
	from=runtime.actor("player")
	var infected:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},destination(0.22))
	expect("existing infected movement keeps 2.2 walk and no human run debit",infected.ok and is_equal_approx(distance(from,runtime.actor("player")),0.22) and runtime.actor("player").stamina==100.0 and runtime.actor_presentation().movement.player.mode=="walk",infected)

	fixture()
	var goal:=destination(2.0)
	expect("path starts through original planner",command("walk","",{"movement_mode":"run"},goal).ok)
	from=runtime.actor("player");runtime.tick(0.1)
	expect("original advance_path consumes same real run budget",is_equal_approx(distance(from,runtime.actor("player")),0.46) and is_equal_approx(float(runtime.actor("player").stamina),99.632),runtime.actor("player"))
	fixture()
	goal=destination(2.0)
	expect("ordinary path starts without new fields",command("walk","",{},goal).ok)
	from=runtime.actor("player");runtime.tick(0.1)
	expect("default path uses same 2.8 walk instead of a second speed",is_equal_approx(distance(from,runtime.actor("player")),0.28),runtime.actor("player"))

	# Rest assignments must terminate at fatigue-adjusted authority cap, not 95.
	fixture("human",55.0,100.0)
	var friend:=resident("friend",ORIGIN.merged({"z":44.0},true))
	friend.relationship={"member":true,"consent":true};friend.stamina=55.0;friend.fatigue=100.0;friend.job="rest"
	var facts:=runtime.facts();facts.actors.append(friend)
	expect("high-fatigue cooperative actor configures",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var ready:=actions.advance(0.1)
	var revised:=runtime.actor("friend")
	for change:Dictionary in ready.get("fact_changes",[]):
		if change.get("collection")=="actors" and change.id=="friend":revised=change.after
	expect("at-cap rest assignment does not restart an impossible 95-point recovery",ready.ok and revised.get("intent")==null and not actions.below_stamina_cap(revised),revised)

	# Use a real standing trunk approach, then prove a blocked sweep emits no move.
	var tree:Dictionary=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")[0]
	var query:RefCounted=building.current_space();var blocked_request:Dictionary={}
	for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var at:=Geometry.location(tree);at.x+=direction.x*0.65;at.z+=direction.y*0.65
		var feet:Dictionary=query.standing_point(at)
		if feet.is_empty():continue
		var to:=feet.duplicate(true);to.x-=direction.x*0.46;to.z-=direction.y*0.46
		if query.direct_move("player",feet,to).ok:continue
		blocked_request={"from":feet,"to":to};break
	expect("actual tree supplies supported blocked-body fixture",not blocked_request.is_empty())
	if not blocked_request.is_empty():
		initialize_at(blocked_request.from)
		before=runtime.capture_checkpoint()
		var blocked:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"run"},blocked_request.to)
		expect("blocked real sweep leaves position stamina time and events unchanged",not blocked.ok and runtime.capture_checkpoint()==before,blocked)
	finish(started)
