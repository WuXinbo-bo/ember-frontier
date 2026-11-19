extends "res://tests/buildings/domain_suite.gd"
## Actual B orders and A atomic release; finite fixtures, no user save/app.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var seed:Dictionary={}
var tree:Dictionary={}
var hammer:String=""
var axe:String=""
var bench:Dictionary={}

func edit_actor(id:String,fields:Dictionary,extra:Array=[])->Dictionary:
	var before:=runtime.actor(id);var after:=before.duplicate(true);after.merge(fields,true)
	return runtime._commit({"fact_changes":[{"collection":"actors","id":id,"before":before,"after":after}],"world_changes":extra})

func actor_command(id:String,kind:String,target:String,payload:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"release:"+str(sequence),"actor_id":id,"kind":kind,"target_id":target,"payload":payload})

func fresh()->void:
	world=World.new();building=Building.new();actions=Actions.new();production=Production.new();runtime=Runtime.new()
	expect("release actual rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	seed=building.seed_rural(world)
	var prepared:Dictionary=world.prepare_changes(seed.world_changes,world.get_revision())
	expect("release actual structures seed",prepared.ok and world.commit_prepared(prepared.capability).ok)
	tree=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")[0]
	var at:=Geometry.location(tree);at.z+=1.2
	var friend:=resident("friend",at);friend.relationship={"member":true,"consent":true};friend.job="gather";friend.work_target_id=tree.id
	initialize_at({"x":31.2,"y":0,"z":42,"regionId":"RH-HOME","buildingId":null,"storeyId":null},[friend],seed.initial_stocks)
	var facts:=runtime.facts();facts.actors[0].pack={"timber":20,"scrap":20,"cloth":2}
	expect("finite test construction pack installs",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var p:=Production.empty_state();p.tools=seed.initial_tools;p.records=seed.initial_records;p.knowledge={"player":["basic_woodwork"],"friend":[]}
	for t:Dictionary in p.tools:
		if t.kind=="hammer":hammer=t.id;t.holderId="pack:player"
		if t.kind=="salvaged_axe":axe=t.id;t.holderId="pack:friend"
	expect("finite tools knowledge install by real CAS",runtime._commit({"world_changes":[building.extension_change(Production.KEY,p)]}).ok)
	bench=building.make_instance("cabinet","release:actual-cabinet",{"x":32,"y":0,"z":43,"regionId":"RH-HOME"})

func start_build()->Dictionary:
	return actor_command("player","structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","output_id":"pack:player","tool_id":hammer})

func start_harvest()->Dictionary:
	return actor_command("friend","harvest",tree.id,{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":[axe],"held":true})

func order_for(id:String,key:String)->Dictionary:
	var p:Variant=world.extension(key)
	if p is Dictionary:
		for o:Dictionary in p.orders:
			if o.actorId==id and Production.active(o):return o
	return {}

func only_order(id:String,key:String)->Dictionary:
	for o:Dictionary in world.extension(key).orders:
		if o.actorId==id:return o
	return {}

func release_order_case(kind:String,blocked:bool)->void:
	fresh()
	var actor_id:="player" if kind=="structure" else "friend"
	var key:="r3:structure-orders" if kind=="structure" else Production.KEY
	var result:=start_build() if kind=="structure" else start_harvest()
	expect("real order starts "+kind+str(blocked),result.ok,result)
	if not result.ok:return
	for i in 5:runtime.tick(0.1)
	if blocked:
		var p:=production.state();Draft.find(p.tools,hammer if kind=="structure" else axe).durability=0.0
		expect("finite real operator breaks "+kind,runtime._commit({"world_changes":[building.extension_change(Production.KEY,p)]}).ok)
		runtime.tick(0.1)
	var order:=order_for(actor_id,key).duplicate(true)
	expect("actual labor and blocked phase "+kind+str(blocked),not order.is_empty() and float(order.elapsed)>0 and order.status==("blocked" if blocked else "active"),order)
	var before:=runtime.capture_checkpoint();var pack:Dictionary=runtime.actor(actor_id).pack;var tools:Array=production.state().tools
	var observed:=runtime.facts();Draft.find(observed.actors,actor_id).hp=0.0
	var transitions:Array=[{"actor_id":actor_id,"kind":"incapacitated"}]
	var input_copy:=observed.duplicate(true);var transition_copy:=transitions.duplicate(true)
	var plan:=actions.prepare_actor_release(transitions,observed,[])
	expect("release pure provider "+kind+str(blocked),plan.ok and runtime.capture_checkpoint()==before and observed==input_copy and transitions==transition_copy,plan)
	result=edit_actor(actor_id,{"hp":0.0})
	var final:=only_order(actor_id,key);var expected:=order.duplicate(true);expected.status="cancelled";expected.reason=final.get("reason")
	expect("no tick atomically cancels whole order "+kind+str(blocked),result.ok and final==expected and runtime.actor(actor_id).intent==null and runtime.clock()==before.facts.time,result)
	expect("no refund reward wear or clock drift "+kind+str(blocked),runtime.actor(actor_id).pack==pack and production.state().tools==tools and building.instance(bench.id).is_empty() and world.entity(tree.id).data.harvest.phase=="standing")
	expect("all affected B holds release "+kind+str(blocked),production.all_holds().filter(func(h:Dictionary)->bool:return h.actor_id==actor_id).is_empty())
	expect("immediate recovery cannot resurrect order "+kind+str(blocked),edit_actor(actor_id,{"hp":100.0}).ok and runtime.actor(actor_id).intent==null and not Production.active(only_order(actor_id,key)))
	var encoded:=Store.encode(runtime.capture_checkpoint());var decoded:=Store.decode(encoded.get("text",""))
	expect("native recovery retains cancelled order "+kind+str(blocked),decoded.ok and world.load_snapshot(decoded.capture.world).ok and runtime.configure({"world":world,"facts":decoded.capture.facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok and not Production.active(only_order(actor_id,key)))

func overlay_and_pause()->void:
	fresh()
	expect("two independent real orders start",start_build().ok and start_harvest().ok)
	for i in 3:runtime.tick(0.1)
	var friend_order:=order_for("friend",Production.KEY).duplicate(true)
	var p:=production.state();p.nextId=19
	var pending:Array=[building.extension_change(Production.KEY,p)]
	var observed:=runtime.facts();observed.actors[0].hp=0
	var before:=runtime.capture_checkpoint();var inputs:=pending.duplicate(true)
	var plan:=actions.prepare_actor_release([{"actor_id":"player","kind":"incapacitated"}],observed,pending)
	expect("pending overlays and provider inputs remain pure",plan.ok and pending==inputs and runtime.capture_checkpoint()==before)
	var change:Dictionary=plan.world_changes.filter(func(c:Dictionary)->bool:return c.id==Production.KEY)[0]
	expect("provider keeps original CAS and unrelated overlay",change.before==world.extension(Production.KEY) and change.after.nextId==19 and change.after.orders[0]==friend_order)
	var committed:=edit_actor("player",{"hp":0.0},pending)
	expect("A composes each extension exactly once",committed.ok and committed.changes.world.filter(func(c:Dictionary)->bool:return c.id==Production.KEY).size()==1 and production.state().nextId==19,committed)
	expect("unaffected actor order remains byte equal",order_for("friend",Production.KEY)==friend_order)
	var old:=runtime.actor("friend");var active:Dictionary=old.intent
	expect("actual rest assignment fixture commits",edit_actor("friend",{"job":"rest"}).ok)
	runtime.tick(0.1)
	var suspended:=runtime.actor("friend")
	expect("real NPC transition suspends work without cancellation",suspended.has("suspended_work") and suspended.suspended_work.intent==active and Production.active(order_for("friend",Production.KEY)))
	var held:=production.all_holds().filter(func(h:Dictionary)->bool:return h.actor_id=="friend")
	expect("ordinary pause keeps original tool hold",not held.is_empty() and production.tool_unavailable(axe))
	var p_before:=production.state();var a_before:=runtime.actor("friend");var time:=runtime.clock()
	committed=edit_actor("friend",{"relationship":{"member":true,"consent":false}})
	expect("withdrawal clears suspended work in same transaction",committed.ok and not runtime.actor("friend").has("suspended_work") and runtime.actor("friend").intent==null and only_order("friend",Production.KEY).status=="cancelled" and runtime.clock()==time,committed)
	expect("withdrawal keeps carried cargo wear progress",runtime.actor("friend").pack==a_before.pack and production.state().tools==p_before.tools and only_order("friend",Production.KEY).elapsed==friend_order.elapsed)
	expect("withdrawal removes all corresponding holds",production.all_holds().filter(func(h:Dictionary)->bool:return h.actor_id=="friend").is_empty())
	expect("consent restoration does not resume stale order",edit_actor("friend",{"relationship":{"member":true,"consent":true}}).ok and runtime.actor("friend").intent==null and not runtime.actor("friend").has("suspended_work"))

func deletion_and_failure()->void:
	fresh();expect("deletion starts real harvest",start_harvest().ok)
	for i in 3:runtime.tick(0.1)
	var before:=runtime.capture_checkpoint();var removed:Dictionary={"collection":"actors","id":"friend","before":runtime.actor("friend"),"after":null}
	var result:=runtime._commit({"fact_changes":[removed]})
	expect("deletion refuses real carried tool and preserves authority",not result.ok and result.code=="ACTOR_PROPERTY_TRANSFER_REQUIRED" and runtime.capture_checkpoint()==before,result)
	var observed:=runtime.facts();observed.actors=observed.actors.filter(func(a:Dictionary)->bool:return a.id!="friend")
	var p:=production.state();p.tools=p.tools.filter(func(t:Dictionary)->bool:return t.holderId!="pack:friend")
	p.records.append({"id":"fixture:record","holderId":"pack:friend"})
	var plan:=actions.prepare_actor_release([{"actor_id":"friend","kind":"removed"}],observed,[building.extension_change(Production.KEY,p)])
	expect("removed record owner also fails closed without mutation",not plan.ok and plan.code=="ACTOR_PROPERTY_TRANSFER_REQUIRED" and runtime.capture_checkpoint()==before)
	# Move the player to the existing carrier for an actual consented handoff.
	var at:=Geometry.location(runtime.actor("friend"));at.x+=0.8
	expect("nearby finite position fixture commits",edit_actor("player",at).ok)
	expect("cancel unlocks actual physical tool",actor_command("friend","cancel","",{}).ok)
	expect("actual handoff removes old tool ownership",actor_command("player","take","pack:friend",{"tool_ids":[axe]}).ok and runtime.tool(axe).holderId=="pack:player")
	p=production.state();p.knowledge.friend=["basic_woodwork"]
	expect("finite learned NPC fixture commits",runtime._commit({"world_changes":[building.extension_change(Production.KEY,p)]}).ok)
	before=runtime.capture_checkpoint();removed.before=runtime.actor("friend");result=runtime._commit({"fact_changes":[removed]})
	expect("nonempty knowledge deletion rejected with no lost growth",not result.ok and result.code=="ACTOR_KNOWLEDGE_RETIRE_REQUIRED" and runtime.capture_checkpoint()==before,result)
	p=production.state();p.knowledge.friend=[]
	expect("explicit empty knowledge fixture commits",runtime._commit({"world_changes":[building.extension_change(Production.KEY,p)]}).ok)
	removed.before=runtime.actor("friend");result=runtime._commit({"fact_changes":[removed]})
	expect("empty departed actor removed without reinsertion or dangling knowledge",result.ok and runtime.actor("friend").is_empty() and not production.state().knowledge.has("friend") and only_order("friend",Production.KEY).status=="cancelled",result)
	expect("departed history passes actual domain references",building.validate_snapshot(world,runtime.facts()).ok)
	fresh();expect("rollback starts real construction",start_build().ok)
	for i in 3:runtime.tick(0.1)
	before=runtime.capture_checkpoint()
	var bad:Dictionary={"op":"extension.set","id":"fixture:late","before_exists":true,"before":{"stale":true},"after":{}}
	result=edit_actor("player",{"hp":0.0},[bad])
	expect("late CAS rolls back hp intent actual order costs and holds",not result.ok and runtime.capture_checkpoint()==before and Production.active(only_order("player","r3:structure-orders")) and production.tool_unavailable(hammer),result)
	var old:Dictionary=building.extension_change(Production.KEY,production.state());old.before_exists=false
	plan=actions.prepare_actor_release([{"actor_id":"player","kind":"incapacitated"}],runtime.facts(),[old])
	expect("provider rejects stale base before proposing cancellation",not plan.ok and plan.code=="CAS_MISMATCH" and runtime.capture_checkpoint()==before)
	plan=actions.prepare_actor_release([{"actor_id":"player","kind":"incapacitated"},{"actor_id":"player","kind":"removed"}],runtime.facts(),[])
	expect("conflicting transition kinds reject purely",not plan.ok and plan.code=="INVALID_LIFECYCLE_PLAN" and runtime.capture_checkpoint()==before)

func run()->void:
	var started:=Time.get_ticks_msec()
	for kind:String in ["structure","harvest"]:
		for blocked:bool in [false,true]:release_order_case(kind,blocked)
	overlay_and_pause();deletion_and_failure()
	finish(started)
