extends "res://tests/integration/run_gameplay.gd"
## Actual generated body/terrain queries. Spatial and damaged-save fixtures are
## explicit; never a completed travel/combat/player route.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")

func finish(output:String)->void:
	if runtime!=null and checks.all(func(c:Dictionary)->bool:return c.ok):regression()
	super.finish(output)

func mount(capture:Dictionary)->bool:
	var built:Dictionary=host._assemble(capture)
	check("encounter fixture uses formal assembler and current real services",built.ok,built.get("reason"))
	if built.ok:runtime=built.runtime
	return built.ok

func partial_site()->Dictionary:
	var query:RefCounted=runtime._services.buildings.current_space()
	for entity:Dictionary in runtime.world.entities("RH-HOME"):
		if entity.get("kind")!="structure":continue
		var center:Dictionary=Geometry.location(entity)
		var first:=center.duplicate(true);first.x-=0.7
		var feet:Dictionary=query.standing_point(first)
		if not feet.is_empty() and query.standing_point(center).is_empty():return {"center":center,"first":feet}
	return {}

func regression()->void:
	var generated:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("real generated world prepared for bad-ground cases",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):return
	var baseline:Dictionary=runtime.capture_checkpoint()
	var query:RefCounted=runtime._services.buildings.current_space()
	var sight_pair:Dictionary={}
	for piece:Dictionary in runtime._services.buildings.structures().instances:
		if piece.definitionId!="window":continue
		var points:Array=query.use_points(piece)
		if points.size()!=2:continue
		var a:Dictionary=query.standing_point(points[0]);var b:Dictionary=query.standing_point(points[1])
		if a.is_empty() or b.is_empty():continue
		var raised_a:=a.duplicate(true);var raised_b:=b.duplicate(true)
		raised_a.y+=1.15;raised_b.y+=1.15
		if query.line_clear(a,b,"") and not query.line_clear(raised_a,raised_b,""):sight_pair={"from":a,"to":b,"window_id":piece.id};break
	check("real generated window distinguishes actual eye height from double raising",not sight_pair.is_empty(),sight_pair)
	if not sight_pair.is_empty():check("gameplay uses B eye-height LOS at real window",runtime._services.gameplay._clear(sight_pair.from,sight_pair.to))
	var roster_tx:=Draft.new(runtime._services.gameplay.context)
	var dead_id:="infected:roster-fixture:0"
	var dead:Dictionary=Initial.actor(dead_id,"explicit dead roster fixture",Geometry.location(runtime.actor("player")),{},{});dead.faction="infected";dead.appearance_id="infected_walker";dead.encounter_id="roster-fixture";dead.hp=0.0
	roster_tx.staged.actors.append(dead)
	for ids:Variant in [[dead_id,dead_id],[dead_id,1],"invalid-roster"]:
		check("duplicate or malformed roster never counts as two actual deaths",not runtime._services.gameplay._cleared(roster_tx,{"id":"roster-fixture","actors":ids},2),ids)
	var partial:Dictionary=partial_site()
	check("actual terrain/building provides first-safe second-blocked site",not partial.is_empty(),partial)
	if partial.is_empty():return
	var tx:=Draft.new(runtime._services.gameplay.context)
	var encounter:Dictionary={"id":"fixture-partial","position":partial.center,"actors":[],"spawned":false,"cleared":false,"choice_issued":false}
	var count:int=tx.staged.actors.size()
	var result:Dictionary=runtime._services.gameplay._spawn(tx,encounter)
	check("one invalid body rejects the complete group",not result.ok and result.code=="NO_ENCOUNTER_GROUND",result)
	check("partial preparation creates zero actors and no spawned fact",tx.staged.actors.size()==count and encounter.actors.is_empty() and not encounter.spawned)
	var fixture:Dictionary=baseline.duplicate(true)
	fixture.facts.actors[0].merge(partial.first,true)
	var gameplay:Dictionary=fixture.world.extensions[Gameplay.KEY]
	gameplay.encounters=[encounter.duplicate(true)]
	gameplay.exploration.status="running";gameplay.exploration.run_id="explicit-ground-fixture"
	if mount(fixture):
		runtime.tick(0.1)
		var state:Dictionary=runtime.world.extension(Gameplay.KEY)
		check("failed spawn stays uncleared and never offers a choice",not state.encounters[0].spawned and not state.encounters[0].cleared and state.exploration.candidates.is_empty() and int(state.exploration.stages)==0,state.encounters[0])
		check("real refusal is persisted and projected to existing UI text",state.encounters[0].spawn_error.code=="NO_ENCOUNTER_GROUND" and str(runtime._services.gameplay.display().exploration.description).contains("遭遇站位"))
		var retry_at:float=state.encounters[0].next_spawn_attempt
		runtime.tick(0.1)
		check("failed geometry is not retried every fixed tick",float(runtime.world.extension(Gameplay.KEY).encounters[0].next_spawn_attempt)==retry_at)
		var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
		var decoded:Dictionary=Store.decode(encoded.get("text",""))
		check("refused encounter survives native save roundtrip",encoded.ok and decoded.ok)
		if decoded.ok and mount(decoded.capture):
			runtime.tick(0.1)
			check("reload cannot turn refused ground into free rewards",not runtime.world.extension(Gameplay.KEY).encounters[0].cleared and runtime.world.extension(Gameplay.KEY).exploration.candidates.is_empty())
	# Explicit damaged-save cases: empty and missing actor references are not deaths.
	for ids:Array in [[],["infected:absent:0","infected:absent:1"]]:
		fixture=baseline.duplicate(true)
		gameplay=fixture.world.extensions[Gameplay.KEY]
		gameplay.exploration.status="running"
		gameplay.encounters[0].spawned=true;gameplay.encounters[0].actors=ids.duplicate()
		gameplay.defense.status="active";gameplay.defense.actors=[]
		if mount(fixture):
			runtime.tick(0.1)
			var state:Dictionary=runtime.world.extension(Gameplay.KEY)
			check("empty/missing encounter roster cannot clear",not state.encounters[0].cleared and state.exploration.candidates.is_empty(),ids)
			check("empty defense cannot clear or unlock radio",state.defense.status=="active" and not request("radio","",{"operation":"transmit"}).ok)
	fixture=baseline.duplicate(true)
	fixture.facts.actors[0].merge(partial.first,true)
	gameplay=fixture.world.extensions[Gameplay.KEY]
	gameplay.layout.defense_position=partial.center.duplicate(true)
	gameplay.defense={"status":"warning","arrival_at":0.0,"warning_at":0.0,"actors":[]}
	if mount(fixture):
		runtime.tick(0.1)
		var state:Dictionary=runtime.world.extension(Gameplay.KEY)
		check("invalid defense bodies preserve warning and create no partial wave",state.defense.status=="warning" and state.defense.actors.is_empty() and state.defense.get("spawn_error",{}).get("code")=="NO_ENCOUNTER_GROUND",state.defense)
		check("invalid wave has no infected/drop or false defense reward",runtime.facts().actors.size()==3 and not state.flags.get("radio_connected",false))
