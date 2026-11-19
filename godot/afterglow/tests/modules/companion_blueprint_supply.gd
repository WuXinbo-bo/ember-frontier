extends "res://tests/modules/run_mechanism_production.gd"
## Isolated terrain and inventory fixture; commands use the real runtime.
const WORKER="village-resident"
const HOME="B:companion-blueprint:home"
const ABANDONED="B:companion-blueprint:abandoned"
const DEPOT="B:companion-blueprint:depot"
const DEFINITION="r34.module.home_small_porch_v1.mechanism-v2"

func run()->void:
	var fixture:=flat_base()
	check("bounded construction fixture",fixture.ok,fixture.get("code"))
	if not fixture.ok:return finish()
	var capture:Dictionary=fixture.capture
	var definition:=Catalog.definition(DEFINITION)
	var at:Dictionary={"x":40,"y":0,"z":40,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var depot:=at.merged({"x":49,"z":49},true)
	var player:=Draft.find(capture.facts.actors,"player")
	player.merge(at.merged({"x":33,"z":51},true),true);player.intent=null
	var companion:=Draft.find(capture.facts.actors,WORKER)
	companion.merge(at.merged({"x":35,"z":50},true),true);companion.intent=null
	companion.householdId="home-residents"
	companion.relationship.merge({"met":true,"helped":true,"member":true,"consent":true,"home_arrived":true},true)
	companion.thirst=100;companion.hunger=100;companion.fatigue=0;companion.stamina=100
	for stock:Dictionary in capture.facts.stocks:
		for item:String in definition.build_cost:stock.items.erase(item)
	for actor:Dictionary in capture.facts.actors:
		for item:String in definition.build_cost:actor.pack.erase(item)
	var hammer_id:String=""
	for tool:Dictionary in capture.world.extensions["r3:production"].tools:
		if tool.kind=="hammer":tool.holderId="pack:player";hammer_id=tool.id
	capture.facts.stocks.append({"id":DEPOT,"items":{},"owner":"home-residents","searched":true,"location":depot})
	var host:=Native.new()
	var mounted:=host._assemble(capture)
	check("fixture assembles",mounted.ok,mounted.get("code"))
	if not mounted.ok:host.free();return finish()
	var rt:RefCounted=mounted.runtime
	var modules:RefCounted=mounted.services.modules
	var plan:Dictionary={"definition_id":DEFINITION,"position":at,"quarter_turn":0,"plan_only":true}
	var placed:=send(rt,"module.plan",ABANDONED,plan)
	check("unfunded blueprint is placeable",placed.ok,placed.get("code"))
	if not placed.ok:rt.retire();host.free();return finish()
	var abandoned:Dictionary=modules.instance(ABANDONED)
	var cancelled:=send(rt,"module.cancel",ABANDONED)
	check("empty blueprint cancellation removes entity, project, and buffers",cancelled.ok and modules.instance(ABANDONED).is_empty() and mounted.world.entity(ABANDONED).is_empty() and Draft.find(modules.state().projects,str(abandoned.project_id)).is_empty() and abandoned.stock_refs.values().all(func(id:String)->bool:return rt.stock(id).is_empty()),cancelled.get("code"))
	placed=send(rt,"module.plan",HOME,plan)
	check("cancelled footprint is immediately reusable",placed.ok,placed.get("code"))
	if not placed.ok:rt.retire();host.free();return finish()
	var project_id:String=modules.instance(HOME).project_id
	var queued:=Draft.find(modules.state().projects,project_id)
	check("blueprint has no payment, worker intent, or usable beds",queued.status=="queued" and queued.source_id.is_empty() and queued.tool_id.is_empty() and rt.actor("player").intent==null and not Draft.find(modules.housing_projection(WORKER).homes,HOME).get("usable",false),queued)
	var assigned:Dictionary=rt.command({"kind":"workforce.assign","actor_id":WORKER,"command_id":"B:blueprint:assignment","target_id":"","payload":{"candidate_id":"building-order:"+HOME}})
	check("unfunded blueprint accepts explicit worker order",assigned.ok,assigned.get("code"))
	for i:int in 40:rt.tick(.1)
	var row:=_assignment(mounted)
	check("order remains blocked without reserving resources",row.get("building_phase")=="blocked" and Draft.find(modules.state().projects,project_id).status=="queued",row)
	var saved:=Store.encode(rt.capture_checkpoint())
	var decoded:=Store.decode(saved.get("text",""))
	check("queued blueprint and order survive native encode/decode",decoded.ok,decoded.get("code"))
	if not decoded.ok:rt.retire();host.free();return finish()
	Draft.find(decoded.capture.facts.stocks,DEPOT).items=definition.build_cost.duplicate(true)
	Draft.find(decoded.capture.world.extensions["r3:production"].tools,hammer_id).holderId=DEPOT
	rt.retire();mounted=host._assemble(decoded.capture)
	check("queued blueprint reloads with distant fixture supplies",mounted.ok,mounted.get("code"))
	if not mounted.ok:host.free();return finish()
	rt=mounted.runtime;modules=mounted.services.modules
	var started_at:float=rt.clock()
	var walked:=false;var picked_up:=false;var building:=false
	# Two obstacle-aware trips plus the catalogue's 40 seconds of on-site work.
	for i:int in 1200:
		rt.tick(.1)
		var worker:Dictionary=rt.actor(WORKER)
		var intent:Variant=worker.intent
		var stock:Dictionary=rt.stock(DEPOT)
		if intent is Dictionary and intent.get("kind")=="walk" and float(stock.items.get("timber",0))>0:walked=true
		if not picked_up and float(stock.items.get("timber",0))==0:
			picked_up=true
			check("goods and hammer transfer only within real contact",walked and G.point(G.location(worker)).distance_to(G.point(depot))<2.0 and Data.json_equal(definition.build_cost,stock_cost(worker.pack,definition.build_cost)) and Draft.find(mounted.world.extension("r3:production").tools,hammer_id).holderId=="pack:"+WORKER,[G.location(worker),worker.pack])
		if modules.instance(HOME).status=="constructing":building=true
		if modules.instance(HOME).status=="operational":break
	var home:Dictionary=modules.instance(HOME)
	var worker:Dictionary=rt.actor(WORKER)
	var final_project:=Draft.find(modules.state().projects,project_id)
	var diagnostic:Dictionary={"home_status":home.status,"project":final_project,"assignment":_assignment(mounted),"elapsed":rt.clock()-started_at,"activity":worker.activity,"intent":worker.intent,"stamina":worker.stamina,"worker_location":G.location(worker),"tool":Draft.find(mounted.world.extension("r3:production").tools,hammer_id),"readiness":rt.spatial_readiness()}
	check("same worker and project finish real housing",picked_up and building and home.status=="operational" and home.project_id==project_id and final_project.actor_id==WORKER and Data.json_equal(home.get("paid_cost",{}),definition.build_cost),diagnostic)
	var housing:=Draft.find(modules.housing_projection(WORKER).homes,HOME)
	check("prepared, reachable beds usable after completion",housing.get("usable",false) and int(housing.get("available_bed_count",0))>0,housing)
	for i:int in 20:rt.tick(.1)
	row=_assignment(mounted)
	check("completion consumes the finite pack cost once",row.get("building_phase")=="completed" and row.get("project_id")==project_id and stock_cost(rt.actor(WORKER).pack,definition.build_cost).values().all(func(amount:Variant)->bool:return float(amount)==0.0),row)
	rt.retire();host.free();finish()

func _assignment(mounted:Dictionary)->Dictionary:
	var state:Variant=mounted.world.extension("r34:workforce")
	if not state is Dictionary:return {}
	for row:Dictionary in state.assignments:
		if row.get("actor_id")==WORKER and row.get("module_id")==HOME:return row
	return {}

func stock_cost(pack:Dictionary,cost:Dictionary)->Dictionary:
	var result:Dictionary={}
	for item:String in cost:result[item]=pack.get(item,0)
	return result

func finish()->void:
	var passed:int=checks.filter(func(row:Dictionary)->bool:return row.ok).size()
	print("COMPANION_BLUEPRINT ",passed,"/",checks.size())
	quit(0 if passed==checks.size() else 1)
