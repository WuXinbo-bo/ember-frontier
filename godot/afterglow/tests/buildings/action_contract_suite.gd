extends "res://tests/buildings/domain_suite.gd"
const Draft=preload("res://scripts/actions/domain_draft.gd")

func sample(kind:String)->Dictionary:
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var request:Dictionary={"command_id":"contract:1","actor_id":"player","kind":kind,"target_id":"target:1","payload":{}}
	var intent:Dictionary={"schema_version":1,"owner":"actions","kind":kind,"id":"contract:1","held":true}
	if kind in ["search","care"]:intent.target_id="target:1";intent.elapsed=0.0
	if kind=="care":intent.merge({"operation":"prepare_bed","source_id":"pack:player","cost":{"cloth":2},"duration":6.0,"target_version":0})
	if kind=="door":intent.merge({"request":request,"target_version":0,"elapsed":0.0,"duration":0.4})
	if kind in ["walk","approach","follow","guard","haul"]:
		intent.merge({"steps":[{"kind":"move","to":at},{"kind":"open-door","targetId":"door:1","at":at},{"kind":"stairs","targetId":"stairs:1","from":at,"to":at},{"kind":"cross-region","to":at}],"step":0})
	if kind in ["walk","approach","structure","craft","study","harvest"]:
		if kind=="approach":request.kind="craft"
		intent.request=request
	if kind in ["structure","craft","study","harvest"]:intent.order_id="contract:1:order"
	return intent

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real C world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":29.2,"y":0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var actor:=runtime.actor("player");var before:=runtime.capture_checkpoint()
	for kind:String in ["search","care","walk","approach","follow","guard","haul","door","structure","craft","study","harvest"]:
		var intent:=sample(kind)
		expect("valid v1 schema "+kind,actions.validate_intent(intent,actor,runtime.facts()).ok)
		var restored:Dictionary=JSON.parse_string(JSON.stringify(intent))
		expect("native JSON number roundtrip "+kind,actions.validate_intent(restored,actor,runtime.facts()).ok)
		var bad:=intent.duplicate(true);bad.schema_version=9
		expect("unknown version refused "+kind,not actions.validate_intent(bad,actor).ok)
	for kind:String in ["search","follow","guard","haul"]:
		var legacy:=sample(kind);legacy.erase("schema_version");legacy.erase("id")
		expect("explicit old v0 shape retained "+kind,actions.validate_intent(legacy,actor).ok)
	for change:Dictionary in [{"cloth":"2"},{"cloth":3},{"cloth":-2},{"cloth":2,"scrap":0},{}]:
		var intent:=sample("care");intent.cost=change
		expect("malformed care amount or extra key rejected "+JSON.stringify(change),not actions.validate_intent(intent,actor).ok)
	var bad:=sample("walk");bad.steps[0].to.x=NAN
	expect("nonfinite route rejected",not actions.validate_intent(bad,actor).ok)
	bad=sample("walk");bad.step=0.5
	expect("fractional cursor rejected",not actions.validate_intent(bad,actor).ok)
	bad=sample("craft");bad.request.actor_id="other"
	expect("wrong actor request rejected",not actions.validate_intent(bad,actor).ok)
	bad=sample("care");bad.kind="free_items"
	expect("unknown kind refused",not actions.validate_intent(bad,actor).ok)
	expect("validators pure",runtime.capture_checkpoint()==before)

	var tx:=Draft.new(production.context)
	var orders:Dictionary=tx.extension("r3:structure-orders",{"version":1,"orders":[]})
	orders.orders=[{"id":"hold:construction","actorId":"player","status":"blocked","targetId":"target:1","sourceId":"pack:player","cost":{"timber":2},"toolId":"tool:1"}]
	var p:Dictionary=tx.extension(Production.KEY,Production.empty_state())
	p.orders=[{"id":"hold:production","actorId":"player","status":"active","targetId":"saw_timber","kind":"craft","sourceId":"pack:player","stationId":"bench:1","toolIds":["tool:2"]}]
	tx.actor("player").intent=sample("care")
	expect("blocked construction holds material and actual tool",production.reserved("pack:player","timber","",tx)==2 and production.tool_unavailable("tool:1","",tx))
	expect("self exclusion exact across unified descriptors",production.reserved("pack:player","timber","hold:construction",tx)==0 and not production.tool_unavailable("tool:1","hold:construction",tx))
	expect("production inputs and work point held once",production.reserved("pack:player","log","",tx)==1 and production.use_reserved("bench:1","",tx) and not production.use_reserved("bench:1","hold:production",tx))
	expect("care uses actual material and use target",production.reserved("pack:player","cloth","",tx)==2 and production.use_reserved("target:1","",tx))
	var holds: Array=production.all_holds(tx);holds[0].cost["forged"]=999
	expect("descriptor mutation cannot modify order authority",not orders.orders[0].cost.has("forged") and not p.orders[0].has("forged"))
	tx.actor("player").hp=0
	expect("incapacitation releases all B material tool and station holds",production.all_holds(tx).is_empty())
	tx.actor("player").hp=100;tx.actor("player").intent=null
	orders.orders[0].status="cancelled";p.orders[0].status="completed"
	expect("cancellation and completion release holds",production.all_holds(tx).is_empty())
	var friend:=resident("friend",Geometry.location(actor));friend.relationship={"member":true,"consent":false}
	tx.staged.actors.append(friend);orders.orders[0].actorId="friend";orders.orders[0].status="active"
	expect("withdrawn consent releases B order hold",production.all_holds(tx).is_empty())
	tx.staged.actors.pop_back()
	expect("removed actor releases B order hold",production.all_holds(tx).is_empty())
	expect("hold query leaves world and live facts unchanged",runtime.capture_checkpoint()==before)
	# DomainDraft must use A public pure diff without sharing snapshot references.
	var draft:=Draft.new(actions.context);draft.actor("player").stamina-=1
	var result:Dictionary=draft.result();var expected:Array=runtime.facts_diff(draft.initial,draft.staged)
	expect("DomainDraft consumes public facts_diff equivalently",result.fact_changes==expected and result.fact_changes.size()==1)
	result.fact_changes[0].before.pack.forged=1
	expect("returned diff before and initial snapshot isolated",not draft.initial.actors[0].pack.has("forged") and runtime.capture_checkpoint()==before)
	finish(started)
