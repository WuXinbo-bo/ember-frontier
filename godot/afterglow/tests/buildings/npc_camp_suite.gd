extends "res://tests/buildings/domain_suite.gd"
## Finite actor/tool/material fixture, real C world and A clock, no preview.
func work_job(target:String,payload:Dictionary)->Dictionary:
	if payload.get("action_kind")=="study":
		return command("job","friend",{"job":"craft","work_target_id":"work:study:"+target})
	if payload.get("action_kind")=="structure" and payload.get("kind")=="repair":
		return command("job","friend",{"job":"craft","work_target_id":"work:repair:"+target})
	if payload.get("action_kind")=="structure":
		return command("job","friend",{"job":"craft","work_target_id":"work:build:"+target})
	return command("job","friend",{"job":"craft","work_target_id":"work:craft:"+target+":"+str(payload.recipe_id),"work_payload":payload})

func configure_fixture(f:Dictionary)->Dictionary:
	return runtime.configure({"world":world,"facts":f,"services":{"buildings":building,"actions":actions,"production":production},"definitions":{"production_recipes":production.recipes.values()}})

func until_complete(kind:String,target:String,limit:int=400)->bool:
	for n in range(limit):
		runtime.tick(0.1)
		var data:Variant=world.extension("r3:structure-orders") if kind=="structure" else production.state()
		if data is Dictionary and data.get("orders",[]).any(func(o:Dictionary)->bool:return o.actorId=="friend" and o.status=="completed" and o.targetId==target):return true
	return false

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real world loaded",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("real seed commits",draft.ok and world.commit_prepared(draft.capability).ok)
	var at:Dictionary={"x":20.2,"y":0,"z":42.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var friend:=resident("friend",at);friend.relationship={"member":true,"consent":true};friend.job="rest"
	friend.pack={"book_woodwork":1,"timber":10,"scrap":6,"log":1,"food":1,"water":1}
	friend.stamina=100
	initialize_at({"x":21,"y":0,"z":42.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null},[friend],seeded.initial_stocks)
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records
	for tool in p.tools:tool.holderId="pack:friend"
	# One physical book has moved into the fixture pack; it is not duplicated.
	var f:=runtime.facts()
	for stock in f.stocks:
		if stock.id=="rural:v1:RH-HOME:shed:storage":stock.items.book_woodwork=0
	for record in p.records:
		if record.itemId=="book_woodwork":record.holderId="pack:friend"
	configure_fixture(f)
	draft=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("single finite production state",draft.ok and world.commit_prepared(draft.capability).ok)
	var wood_record:Dictionary=p.records.filter(func(v:Dictionary)->bool:return v.itemId=="book_woodwork")[0]
	expect("camp catalogue offers actual accessible manual and damaged gate",actions.camp_work_targets().any(func(t:Dictionary)->bool:return t.actual_target_id==wood_record.id) and actions.camp_work_targets().any(func(t:Dictionary)->bool:return t.id=="work:repair:rural:v1:RH-HOME:old-house:yard-gate"))
	expect("sole runtime selector assigns actual physical manual",work_job(wood_record.id,{"action_kind":"study","record_id":wood_record.id}).ok)
	expect("NPC learns only after actual twelve second order",until_complete("study",wood_record.id) and production.state().knowledge.get("friend",[]).has("basic_woodwork"))
	var bench:Dictionary=actions.camp_work_targets().filter(func(t:Dictionary)->bool:return t.id.begins_with("work:build:"))[0].work_payload.instance
	var hammer:="rural:v1:RH-HOME:shed:hammer"
	var saw:="rural:v1:RH-HOME:shed:hand_saw"
	var before:Dictionary=runtime.actor("friend").pack.duplicate(true)
	expect("sole runtime selector assigns actual learned construction reservation",work_job(bench.id,{"action_kind":"structure","kind":"place","instance":bench,"source_id":"pack:friend","tool_id":hammer}).ok)
	expect("NPC arrives and builds actual workbench",until_complete("structure",bench.id) and not building.instance(bench.id).is_empty())
	expect("completed real workbench removes initial build choice",not actions.camp_work_targets().any(func(t:Dictionary)->bool:return t.id.begins_with("work:build:")))
	expect("NPC construction exact material debit",runtime.actor("friend").pack.timber==before.timber-4 and runtime.actor("friend").pack.scrap==before.scrap-2)
	expect("NPC starts same saw recipe",work_job(bench.id,{"recipe_id":"saw_timber","source_id":"pack:friend","output_id":"pack:friend","tool_ids":[saw,hammer]}).ok)
	var active:=false
	for n in range(80):
		runtime.tick(0.1)
		var intent:Variant=runtime.actor("friend").get("intent")
		if intent is Dictionary and intent.get("kind")=="craft":active=true;break
	expect("NPC craft reaches actual station",active,{"actor":runtime.actor("friend"),"orders":production.state().orders})
	for n in range(10):runtime.tick(0.1)
	var order:Dictionary=production.state().orders[-1]
	var elapsed:float=order.elapsed
	var wear:float=runtime.tool(saw).durability
	expect("rest assignment without work target accepted during actual craft",command("job","friend",{"job":"rest"}).ok)
	for n in range(20):runtime.tick(0.1)
	expect("rest suspends exact work without output or wear",runtime.actor("friend").has("suspended_work") and production.state().orders[-1].elapsed==elapsed and runtime.tool(saw).durability==wear and runtime.actor("friend").pack.log==1)
	var capture:=runtime.capture_checkpoint()
	expect("suspended work saved and restored in sole world",world.load_snapshot(capture.world).ok and configure_fixture(capture.facts).ok)
	var timber_before:float=runtime.actor("friend").pack.timber
	expect("same job resumes after rest",work_job(bench.id,{"recipe_id":"saw_timber","source_id":"pack:friend","output_id":"pack:friend","tool_ids":[saw]}).ok)
	expect("same order eventually completes exact one log recipe",until_complete("craft","saw_timber",600) and runtime.actor("friend").pack.log==0 and runtime.actor("friend").pack.timber==timber_before+4)
	expect("resume does not create second craft order",production.state().orders.filter(func(o:Dictionary)->bool:return o.actorId=="friend" and o.kind=="craft").size()==1)
	var gate:="rural:v1:RH-HOME:old-house:yard-gate"
	var repair_before:Dictionary=runtime.actor("friend").pack.duplicate(true)
	expect("sole runtime selector assigns actual damaged gate repair",work_job(gate,{"action_kind":"structure","kind":"repair"}).ok)
	expect("NPC physically arrives and repairs gate through same order",until_complete("structure",gate,800) and building.instance(gate).hp==120,{"actor":runtime.actor("friend"),"gate":building.instance(gate)})
	expect("NPC repair consumes exact one timber and scrap",runtime.actor("friend").pack.timber==repair_before.timber-1 and runtime.actor("friend").pack.scrap==repair_before.scrap-1)
	# Revoke consent during a second real reserved order, release all actual holds.
	f=runtime.facts();f.actors[1].pack.log=1;f.actors[1].intent=null;f.actors[1].job="rest";f.actors[1].stamina=100
	configure_fixture(f)
	work_job(bench.id,{"recipe_id":"saw_timber","source_id":"pack:friend","output_id":"pack:friend","tool_ids":[saw]})
	for n in range(60):
		runtime.tick(0.1)
		if production.tool_reserved(saw):break
	expect("new real craft holds saw",production.tool_reserved(saw))
	var log_before:float=runtime.actor("friend").pack.log
	expect("consent withdrawal accepted",command("consent","friend",{"enabled":false}).ok)
	runtime.tick(0.1)
	expect("revocation cancels order and releases tool/material",not production.tool_reserved(saw) and production.reserved("pack:friend","log")==0 and runtime.actor("friend").pack.log==log_before and runtime.actor("friend").intent==null)
	var unconsented:Dictionary=actions.prepare({"kind":"structure","actor_id":"friend","target_id":bench.id,"payload":{"kind":"repair","source_id":"pack:friend","tool_id":hammer}})
	expect("unconsenting NPC cannot be made to repair via direct command",not unconsented.ok and str(unconsented.get("reason","")).contains("同意"),unconsented)
	var final:=building.validate_snapshot(world,runtime.facts())
	expect("final NPC camp snapshot references valid",final.ok,final)
	finish(started)
