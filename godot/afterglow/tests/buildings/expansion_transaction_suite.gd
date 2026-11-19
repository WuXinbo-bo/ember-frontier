extends "res://tests/buildings/generated_camp_suite.gd"
## B's actual consumers of A's production expansion transaction. No parallel
## composer or preview. Explicit CAS/depletion fixtures are not player routes.
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const Data=preload("res://scripts/world/world_data.gd")
class LateCASBuilding extends "res://scripts/buildings/building_service.gd":
	func prepare_generation(view:RefCounted,regions:Array=[])->Dictionary:
		var result:Dictionary=super.prepare_generation(view,regions)
		if result.ok:
			var op:Dictionary=extension_change("r3:building-generation",view.extension("r3:building-generation"),view)
			op.before={"invalid_late_CAS_fixture":true};result.world_changes.append(op)
		return result

func run()->void:
	var started:=Time.get_ticks_msec()
	for seed_value:int in [713,973339546]:
		host=Client.new()
		var opening:Dictionary=Assembly.prepare(Assembly.generate(seed_value,Building.generation_profiles()))
		expect("real same-engine opening prepares seed "+str(seed_value),opening.ok,opening.get("reason"))
		if not opening.ok:host.free();continue
		var mounted:Dictionary=host._assemble(opening.capture)
		expect("formal assembler installs all existing services seed "+str(seed_value),mounted.ok,mounted.get("reason"))
		if not mounted.ok:host.free();continue
		world=mounted.world;runtime=mounted.runtime;building=mounted.services.buildings;actions=mounted.services.actions;production=mounted.services.production
		if seed_value==713:
			if not reach_stock("RH-HOME:shed:storage"):host.free();continue
			if not perform("actual search before expansion","search","RH-HOME:shed:storage"):host.free();continue
			if not perform("actual finite manuals and saw transfer before expansion","take","RH-HOME:shed:storage",{"items":{"book_woodwork":1,"book_tool_repair":1},"tool_ids":["RH-HOME:shed:hand_saw"]}):host.free();continue
			if not perform("actual learning creates retained knowledge and completed order","study","RH-HOME:shed:record:woodwork",{"record_id":"RH-HOME:shed:record:woodwork"}):host.free();continue
			expect("actual second study stays active during expansion",command("study","RH-HOME:shed:record:repair",{"record_id":"RH-HOME:shed:record:repair"}).ok)
			runtime.tick(0.1)
			expect("nonempty old knowledge orders and exact physical book holders",not production.state().knowledge.is_empty() and production.state().orders.size()>=2 and runtime.actor("player").get("intent")!=null and runtime.actor("player").pack.book_tool_repair==1)
		await expansion(seed_value)
		host.free();host=null
	finish(started)

func expansion(seed_value:int)->void:
	var input:Dictionary=Generator.region_generation_input(world,Building.generation_profiles())
	var draft:Dictionary=Generator.draft_region_request(input,Vector2i(1,0)) if input.ok else input
	expect("C detached finite adjacent draft seed "+str(seed_value),draft.ok,draft.get("reason"))
	if not draft.ok:return
	var region_id:String=draft.region.id
	var old:Dictionary=runtime.capture_checkpoint()
	var old_production:Dictionary=production.state()
	var old_buildings:Dictionary=building.structures()
	var jobs:=Scheduler.new();jobs.attach(runtime,building,9)
	# The scheduler itself merges C's original before with B's final after,
	# discards its projection capability and submits one Runtime transaction.
	var outcome:Dictionary=jobs._commit_draft(draft)
	expect("production scheduler actually commits C terrain B buildings and finite facts seed "+str(seed_value),outcome.ok,outcome)
	if not outcome.ok:jobs.shutdown();return
	expect("expansion has one authority revision and no simulation time advance",runtime.get_revision()==int(old.command_revision)+1 and runtime.clock()==old.facts.time and world.get_revision()==int(old.world.revision)+1)
	var now:Dictionary=runtime.facts()
	var expected_facts:Dictionary=old.facts.duplicate(true)
	# This real transaction legitimately appends region_generated to A's
	# existing bounded ledger. Compare that precise append/trim, not an
	# impossible no-event expectation or a comparison that erases the ledger.
	if not expected_facts.has("ledger"):expected_facts.ledger=[]
	expected_facts.ledger.append({"kind":"region_generated","region_id":region_id,"id":"event:%s:0"%runtime.get_revision(),"revision":runtime.get_revision(),"time":old.facts.time})
	while expected_facts.ledger.size()>256:expected_facts.ledger.pop_front()
	var original_facts:Dictionary=now.duplicate(true);original_facts.stocks=now.stocks.filter(func(s:Dictionary)->bool:return old.facts.stocks.any(func(v:Dictionary)->bool:return v.id==s.id))
	expect("all old facts retained with exactly the bounded generation event",original_facts==expected_facts,differences(expected_facts,original_facts,"facts",[]))
	var retained:=true
	for field:String in old_production:
		if field in ["tools","records"]:
			for entry:Dictionary in old_production[field]:
				if not production.state()[field].has(entry):retained=false
		else:
			if production.state().get(field)!=old_production[field]:retained=false
	expect("production retains knowledge elapsed orders trees ledger and nextId",retained)
	var stable:=true
	for entry:Dictionary in old_buildings.instances:
		if building.instance(str(entry.id))!=entry:stable=false
	for entry:Dictionary in old_buildings.storeys:
		if not building.structures().storeys.has(entry):stable=false
	for key:String in old.world.entities:
		if world.entity(key)!=old.world.entities[key]:stable=false
	for key:String in old.world.chunks:
		if world.chunk(key)!=old.world.chunks[key]:stable=false
	expect("all old entities geometry versions storeys and terrain remain exact",stable)
	var plan:Dictionary=world.extension("generation:"+region_id)
	var added:Array=now.stocks.filter(func(s:Dictionary)->bool:return not old.facts.stocks.any(func(v:Dictionary)->bool:return v.id==s.id))
	var unique:Dictionary={};var correct:=not added.is_empty()
	for stock:Dictionary in added:
		if unique.has(stock.id) or stock.location.regionId!=region_id:correct=false
		unique[stock.id]=true
	for site:Dictionary in plan.resource_sites:
		var stock:Dictionary=runtime.stock(str(site.output_id))
		if stock.is_empty() or stock.items!={} or stock.location.regionId!=region_id:correct=false
	expect("each new finite tree output gets exactly one empty real ground stock",correct,{"new_stocks":added.size(),"sites":plan.resource_sites.size()})
	var new_structures:Array=building.structures().instances.filter(func(v:Dictionary)->bool:return v.regionId==region_id)
	expect("actual peripheral obeys C persisted parcel presence and true coordinates",(not new_structures.is_empty() if not plan.parcels.is_empty() else new_structures.is_empty()) and world.region(region_id).bounds.min.x==64,{"structures":new_structures.size(),"parcels":plan.parcels.size(),"scope":"current C peripheral has no building parcels; do not fabricate houses"})
	var query:RefCounted=building.current_space();var uses_ok:=true;var count:=0
	for v:Dictionary in new_structures:
		if building.geometry.definition(v).kind not in ["door","cabinet","workbench"]:continue
		var usable:=false
		for point:Dictionary in query.use_points(v):
			if not query.standing_point(point).is_empty():usable=true
		uses_ok=uses_ok and usable;count+=1
	if not new_structures.is_empty():expect("new actual furniture and entrances provide supported body-sized use points",uses_ok and count>0,{"checked":count})
	else:expect("empty peripheral parcel plan cannot create furniture or tool rewards",production.state().tools==old_production.tools and production.state().records==old_production.records)
	# Explicit finite depletion fixture, committed via the real CAS boundary;
	# not a claim that the original player walked to or looted this source.
	var stocked:Array=added.filter(func(s:Dictionary)->bool:return not s.items.is_empty())
	if not stocked.is_empty():
		var before:Dictionary=stocked[0];var after:=before.duplicate(true);after.items={}
		expect("explicit finite depletion fixture uses one atomic stock CAS",runtime._commit({"fact_changes":[{"collection":"stocks","id":before.id,"before":before,"after":after}]}).ok)
	var revisiting:Dictionary=runtime.capture_checkpoint()
	var again:Dictionary=jobs._commit_draft(draft)
	var families:Dictionary=building.prepare_generation(world,[region_id])
	expect("repeat draft and B parcels cannot restock respawn or modify existing state",again.ok and again.get("already_generated",false) and not families.ok and families.code=="ALREADY_SEEDED" and runtime.capture_checkpoint()==revisiting,{"repeat":again.get("code"),"family":families.get("code")})
	var saved:Dictionary=Store.encode(revisiting);var decoded:Dictionary=Store.decode(saved.get("text",""))
	var restored:Dictionary=host._assemble(decoded.capture) if saved.ok and decoded.ok else {"ok":false,"reason":decoded.get("reason")}
	expect("expanded active production and finite depletion survive native formal restore",restored.ok,restored.get("reason"))
	if restored.ok:
		var canonical:Dictionary=JSON.parse_string(JSON.stringify(revisiting,"",true,true))
		expect("native representation preserves exact facts production and geometry identity",Data.json_equal(restored.runtime.facts(),canonical.facts) and Data.json_equal(restored.world.extension(Production.KEY),canonical.world.extensions[Production.KEY]) and Data.json_equal(restored.world.extension(building.EXTENSION),canonical.world.extensions[building.EXTENSION]))
		var repeat_jobs:=Scheduler.new();repeat_jobs.attach(restored.runtime,restored.services.buildings,10)
		var restored_before:Dictionary=restored.runtime.capture_checkpoint();again=repeat_jobs._commit_draft(draft)
		expect("revisit after restore is idempotent including active orders and depleted stock",again.ok and again.get("already_generated",false) and restored.runtime.capture_checkpoint()==restored_before)
		repeat_jobs.shutdown()
	if seed_value==713:
		var next_input:Dictionary=Generator.region_generation_input(world,Building.generation_profiles())
		var next_draft:Dictionary=Generator.draft_region_request(next_input,Vector2i(-1,0))
		var faulty:=LateCASBuilding.new();faulty.configure({"world":world,"runtime":runtime})
		var bad_jobs:=Scheduler.new();bad_jobs.attach(runtime,faulty,11)
		var before:Dictionary=runtime.capture_checkpoint();var rejected:Dictionary=bad_jobs._commit_draft(next_draft)
		expect("late B extension CAS failure rolls back C region buildings resources and stocks",not rejected.ok and runtime.capture_checkpoint()==before and world.region("R2:-1:0").is_empty(),rejected)
		bad_jobs.shutdown()
		var merge:Dictionary=Scheduler.merge_world_changes([{"op":"extension.set","id":"generation:fixture","before_exists":false,"before":null,"after":{"v":1}}],[{"op":"extension.set","id":"generation:fixture","before_exists":true,"before":{"v":2},"after":{"v":3}}])
		expect("production merge refuses a domain based on a different projection",not merge.ok and merge.code=="GENERATION_CAS_CHAIN")
	jobs.shutdown()
