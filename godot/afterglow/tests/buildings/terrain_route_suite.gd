extends "res://tests/buildings/domain_suite.gd"
## Exact C high-grade repro. Road/plan heights are hints; the original frozen
## B movement predicates re-prove every actual returned segment.
const OldNavigation=preload("res://tests/buildings/terrain_route_reference.gd")
const CurrentNavigation=preload("res://scripts/buildings/building_navigation.gd")
const Data=preload("res://scripts/world/world_data.gd")

func location(point:Dictionary)->Dictionary:
	var result:=Geometry.location(point);result.regionId="RH-HOME";return result

func check_route(query:RefCounted,from:Dictionary,to:Dictionary,label:String,network:bool=true)->void:
	var before:=world.snapshot();var facts:=runtime.facts()
	var started:=Time.get_ticks_usec()
	var route:Dictionary
	if network:route=query.route("player",from,to)
	else:
		var navigator:=CurrentNavigation.new();navigator.space=query;navigator.actor_id="player";navigator.nodes=[from,to]
		route=navigator.grid_plan(from,to)
	var elapsed:float=float(Time.get_ticks_usec()-started)/1000
	expect(label+" finds actual multi-elevation path",route.ok,{"reason":route.get("reason"),"ms":elapsed,"steps":route.get("steps",[]).size()})
	if not route.ok:return
	var current:=from;var failures:Array=[];var levels:Dictionary={from.y:true};var moves:=0
	for step:Dictionary in route.steps:
		if step.kind=="move":
			var result:Dictionary=query.walk("player",current,step.to,true)
			if not result.ok or not CurrentNavigation.same(result.location,step.to):failures.append({"from":current,"to":step.to,"reason":result.get("reason")})
			else:current=result.location
			levels[current.y]=true;moves+=1
		elif step.kind=="open-door":
			var door:Dictionary=query.by_id.get(step.targetId,{})
			if door.is_empty() or door.door.locked or door.door.blocked or query.permission.call("player",door.id,"open",door)!=null:failures.append(step)
		elif step.kind=="stairs":
			if not query.stair_clear(query.by_id[step.targetId]):failures.append(step)
			current=step.to
		else:failures.append(step)
	expect(label+" every returned segment retains exact body/door/ground proof",failures.is_empty() and CurrentNavigation.same(current,to),{"failures":failures,"levels":levels.keys(),"moves":moves,"final":current,"ms":elapsed})
	expect(label+" reads no second world and never mutates facts",Data.json_equal(world.snapshot(),before) and Data.json_equal(runtime.facts(),facts))

func run()->void:
	var started:=Time.get_ticks_msec()
	for seed_value in [713,2026]:
		world=World.new();building=Building.new();actions=Actions.new();production=Production.new();runtime=Runtime.new()
		expect("exact preserved C rural-2 repro loads seed"+str(seed_value),world.load_snapshot(Generator.generate_settlement(seed_value,Building.generation_profiles(),"rural-2")).ok)
		var plan:Dictionary=world.extension("generation:RH-HOME")
		var from:=location(plan.anchors.arrival);var to:=location(plan.anchors.home)
		initialize_at(from,[],Generator.empty_resource_stocks(world))
		var query:RefCounted=building.current_space()
		if seed_value==713:
			expect("C exact failing stations retained",Geometry.point(from)==Vector3(34,3,33) and Geometry.point(to)==Vector3(11,5,24.8),{"from":from,"to":to})
			var old:=OldNavigation.new();var result:Dictionary=old.plan(query,"player",from,to)
			expect("frozen prior navigation reproduces real UNREACHABLE",not result.ok,result)
		check_route(query,from,to,"seed%d actual terrain outward"%seed_value)
		check_route(query,to,from,"seed%d actual terrain reverse"%seed_value)
		if seed_value==713:check_route(query,from,to,"seed713 no-road-hints fallback",false)
		var prepared:Dictionary=building.prepare_generation(world)
		expect("same C world consumes actual building families "+str(seed_value),prepared.ok,prepared.get("reason"))
		if not prepared.ok:continue
		var facts:=runtime.facts();facts.stocks.append_array(prepared.initial_stocks)
		var p:=Production.empty_state();p.tools=prepared.initial_tools;p.records=prepared.initial_records
		var changes:Array=prepared.world_changes.duplicate(true);changes.append(building.extension_change(Production.KEY,p))
		var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
		var valid:Dictionary=building.validate_world_draft(draft.view,facts,changes) if draft.ok else draft
		expect("full family graph safety "+str(seed_value),valid.ok,valid.get("reason"))
		if not valid.ok:continue
		expect("same authority atomically commits families "+str(seed_value),world.commit_prepared(draft.capability).ok)
		expect("finite stocks and services reconfigure "+str(seed_value),runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
		check_route(building.current_space(),from,to,"seed%d populated settlement outward"%seed_value)
		check_route(building.current_space(),to,from,"seed%d populated settlement reverse"%seed_value)
	finish(started)
