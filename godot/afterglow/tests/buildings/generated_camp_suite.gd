extends "res://tests/buildings/rural_route_suite.gd"
## Two actual C settlements, finite opening inventory and sole production runtime.
## Command-level domain evidence, never an OS-input or formal-app qualification.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")

func generated_opening()->void:
	var home:="RH-HOME:home"
	var shed:="RH-HOME:shed"
	var pack:="pack:player"
	var anchors:Dictionary=building.life_anchors()
	expect("generated live household anchors follow actual owned objects",anchors.has(home) and anchors[home].has_all(["stock","sleep","yard-entrance"]) and building.instance("RH-VILLAGE:neighbor:storage").owner=="village-resident",anchors.keys())
	if not reach_stock(home+":storage"):return
	expect("delivery chooses searched actual home stock rather than neighbor or shed",actions.home_delivery_stock(runtime.facts())==home+":storage")
	if not perform("take finite bedding and drinking water from generated home","take",home+":storage",{"items":{"cloth":2,"water":1}}):return
	var bed:Dictionary=world.entity(anchors[home].sleep.target_id)
	var bed_at:=Geometry.location(bed)
	var reached:=false
	for offset:Vector3 in [Vector3(1.1,0,0),Vector3(-1.1,0,0),Vector3(0,0,1.1),Vector3(0,0,-1.1)]:
		var near:=bed_at.duplicate(true);near.x+=offset.x;near.z+=offset.z
		if building.current_space().standing_point(near).is_empty():continue
		var attempt:=command("walk","",{},near)
		if attempt.ok and completed():reached=true;break
	expect("real supported route reaches generated sleeping place",reached)
	if not reached:return
	if not perform("prepare actual generated bed using taken cloth","care",bed.id,{"source_id":pack}):return
	if not perform("rest at prepared generated bed","rest",bed.id):return
	if not reach_stock(shed+":storage"):return
	if not perform("search real generated shed cabinet","search",shed+":storage"):return
	if not perform("take finite generated tools manuals and materials","take",shed+":storage",{"items":{"timber":8,"scrap":6,"book_woodwork":1,"book_tool_repair":1},"tool_ids":[shed+":hammer",shed+":hand_saw",shed+":salvaged_axe"]}):return
	if not perform("learn woodworking from carried physical generated manual","study",shed+":record:woodwork",{"record_id":shed+":record:woodwork"}):return
	if not perform("learn repair from carried physical generated manual","study",shed+":record:repair",{"record_id":shed+":record:repair"}):return
	var gate:Dictionary=building.instance(home+":yard-gate")
	if not perform("walk back along true elevation to generated damaged gate","walk","",{},building.use_points(gate.id)[0]):return
	if not perform("repair generated yard gate with actual labor and finite tools","structure",gate.id,{"kind":"repair","source_id":pack,"output_id":pack,"tool_id":shed+":hammer"}):return
	var candidates:Array=actions.camp_work_targets().filter(func(t:Dictionary)->bool:return str(t.id).begins_with("work:build:"))
	expect("only owned generated home offers initial construction reservation",candidates.size()==1 and candidates[0].actual_target_id==home+":workbench-reservation",candidates)
	if candidates.size()!=1:return
	var bench:Dictionary=candidates[0].work_payload.instance
	var use:Dictionary=building.current_space().use_points(bench)[0]
	if not perform("walk into actual reserved generated workshop position","walk","",{},use):return
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not perform("construct learned generated workbench with finite material","structure",bench.id,{"kind":"place","instance":bench,"source_id":pack,"output_id":pack,"tool_id":shed+":hammer"}):return
	expect("generated construction debits exactly four timber and two scrap",runtime.actor("player").pack.timber==before.timber-4 and runtime.actor("player").pack.scrap==before.scrap-2)
	if not perform("make actual handle at constructed generated workbench","craft",bench.id,{"recipe_id":"make_handle","source_id":pack,"output_id":pack,"tool_ids":[shed+":hand_saw"]}):return
	expect("generated initial camp yields one physical handle without free stock",runtime.actor("player").pack.get("tool_handle",0)==1 and production.state().knowledge.get("player",[]).has("basic_woodwork") and runtime.stock(shed+":storage").items.get("timber",-1)==0)
	if not relocate_generated_stock(home+":storage",shed+":hammer"):return
	if not perform("walk back to constructed generated workbench before dismantling","walk","",{},use):return
	if not perform("dismantle actual generated workbench and settle physical salvage","structure",bench.id,{"kind":"remove","output_id":pack,"tool_id":shed+":hammer"}):return
	expect("dismantled generated workbench leaves a retired consumed reservation",building.instance(bench.id).is_empty() and not actions.camp_work_targets().any(func(t:Dictionary)->bool:return str(t.id).begins_with("work:build:")))
	var capture:=runtime.capture_checkpoint()
	var encoded:=Store.encode(capture);var decoded:=Store.decode(encoded.get("text",""))
	var restored:Dictionary=host._assemble(decoded.capture) if encoded.ok and decoded.ok else {"ok":false,"reason":encoded.get("reason",decoded.get("reason"))}
	expect("generated finite camp route survives native codec and formal assembler",restored.ok,restored.get("reason"))
	if restored.ok:
		# Compare the actual canonical JSON representation which Store persists;
		# do not mistake its last-bit float formatting for inventory tolerance.
		var canonical:Dictionary=JSON.parse_string(JSON.stringify(capture,"",true,true))
		var changes:Array=differences(canonical.facts,restored.runtime.facts(),"facts",[])
		changes.append_array(differences(canonical.world.extensions[Production.KEY],restored.world.extension(Production.KEY),"production",[]))
		expect("generated native restore preserves inventory tools books orders and learning",changes.is_empty(),changes)
		var altered:Dictionary=canonical.facts.duplicate(true);altered.actors[0].pack.tool_handle+=1
		expect("canonical comparison still rejects an extra physical product",not differences(canonical.facts,altered,"facts",[]).is_empty())
		expect("generated restore preserves repaired gate and prepared bed",restored.world.entity(bed.id).data.prepared and restored.services.buildings.instance(gate.id).hp==120)
		expect("generated completed reservation never reappears after restore",not restored.services.actions.camp_work_targets().any(func(t:Dictionary)->bool:return str(t.id).begins_with("work:build:")))
		var repeat:Dictionary=restored.services.buildings.prepare_generation(restored.world)
		expect("completed generated camp cannot redraw world or replenish sources",not repeat.ok and repeat.code=="ALREADY_SEEDED")

func relocate_generated_stock(id:String,hammer:String)->bool:
	if not reach_stock(id):return false
	var before:Dictionary=runtime.stock(id)
	var piece:Dictionary=building.instance(id)
	var accepted:Dictionary={};var attempts:Array=[]
	for offset:Vector3 in [Vector3(0,0,1.5),Vector3(0,0,-1.5),Vector3(-1.5,0,0),Vector3(1.5,0,0)]:
		var moved:=piece.duplicate(true);moved.position=Geometry.json_point(Geometry.point(piece.position)+offset)
		var safe:Dictionary=building.prepare_edit([id],[moved],runtime.facts())
		if not safe.ok:attempts.append(safe.get("reason"));continue
		var payload:Dictionary={"kind":"move","destination":{"position":moved.position,"quarterTurn":moved.quarterTurn},"tool_id":hammer}
		var request:Dictionary={"kind":"structure","actor_id":"player","target_id":id,"payload":payload}
		var preview:Dictionary=actions.availability(request)
		if not preview.ok:attempts.append(preview.get("reason"));continue
		accepted=payload;break
	expect("generated cabinet has a safe reachable same-floor move",not accepted.is_empty(),attempts)
	if accepted.is_empty():return false
	if not perform("move actual loaded generated cabinet with real labor","structure",id,accepted):return false
	var after:Dictionary=runtime.stock(id)
	var current:Dictionary=building.instance(id)
	expect("moving generated stock preserves contents identity and true position",after.id==before.id and after.items==before.items and after.location==Geometry.location(current) and current.position!=piece.position)
	var live:Dictionary=building.life_anchors()["RH-HOME:home"].stock
	expect("generated home stock anchor immediately follows actual relocation",live.target_id==id and live.position==Geometry.location(current))
	var forbidden:Dictionary=command("structure",id,{"kind":"remove","output_id":"pack:player","tool_id":hammer})
	expect("loaded generated cabinet cannot be dismantled and lose stored goods",not forbidden.ok and runtime.stock(id).items==before.items,forbidden.get("reason"))
	return true

func seeds_to_check()->Array:
	return [713,2026]

func expected_home_profile(_seed:int)->String:
	return ""

func verify_domestic_route()->void:
	pass

func run()->void:
	var started:=Time.get_ticks_msec()
	var families:Array=[]
	for seed_value:int in seeds_to_check():
		host=Client.new()
		var source:Dictionary=Generator.generate_settlement(seed_value,Building.generation_profiles())
		var prepared:Dictionary=Assembly.prepare(source)
		expect("formal generated composition validates and commits finite opening seed "+str(seed_value),prepared.ok,prepared.get("reason"))
		if not prepared.ok:host.free();continue
		var assembled:Dictionary=host._assemble(prepared.capture)
		expect("generated opening formal assembler seed "+str(seed_value),assembled.ok,assembled.get("reason"))
		if not assembled.ok:host.free();continue
		world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
		var actual_profile:String=world.extension("r3:building-generation").parcels["RH-HOME:home"].profile_id
		families.append(actual_profile)
		if not expected_home_profile(seed_value).is_empty():expect("actual persistent plan uses intended authored residence seed "+str(seed_value),actual_profile==expected_home_profile(seed_value),actual_profile)
		expect("generated original pack and no learned home workbench seed "+str(seed_value),runtime.actor("player").pack=={"food":1,"water":1} and production.state().knowledge.is_empty() and building.instance("RH-HOME:home:workbench-reservation").is_empty())
		verify_domestic_route()
		await generated_opening()
		host.free();host=null
	print("GENERATED_OPENING_ROUTE "+JSON.stringify({"families":families,"steps":route_steps}))
	finish(started)
