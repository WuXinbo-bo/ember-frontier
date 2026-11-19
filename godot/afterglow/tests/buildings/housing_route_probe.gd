extends "res://tests/buildings/generated_camp_suite.gd"
## Exact seed-12 endpoints, followed by real committed door/route execution.
## A planned suffix after open-door is provisional: ActionService commits the
## door CAS, then replans from the actual off-axis handle. Prove that contract,
## never execute its stale suffix as if a permission check opened a door.
const Navigation=preload("res://scripts/buildings/building_navigation.gd")

func trace_to(target:Dictionary,label:String)->bool:
	var result:=command("walk","",{},target)
	if not result.ok:
		expect(label+" starts actual route",false,result);return false
	var bad:Array=[];var moved_steps:=0;var ticks:=0
	while runtime.actor("player").get("intent")!=null and ticks<3000:
		var before:=Geometry.location(runtime.actor("player"))
		var query:RefCounted=building.current_space()
		runtime.tick(0.1);ticks+=1
		var after:=Geometry.location(runtime.actor("player"))
		if Navigation.same(before,after):continue
		var proof:Dictionary=query.direct_move("player",before,after)
		if not proof.ok or not Navigation.same(proof.location,after):
			bad.append({"from":before,"to":after,"proof":proof});break
		moved_steps+=1
	var final:=Geometry.location(runtime.actor("player"))
	# Match the existing executor's explicit <0.08m arrival rule, not the
	# planner's <0.025m graph-node identity. Also re-prove the actual final feet.
	var supported:Dictionary=building.current_space().standing_point(final)
	var distance:float=Geometry.point(final).distance_to(Geometry.point(target))
	var arrived:bool=final.regionId==target.regionId and final.get("buildingId")==target.get("buildingId") and final.get("storeyId")==target.get("storeyId") and distance<0.08
	var ok:bool=bad.is_empty() and runtime.actor("player").get("intent")==null and arrived and not supported.is_empty() and Navigation.same(supported,final)
	expect(label+" arrives through actual committed doors and original body/ground checks",ok,{"first_failure":bad,"ticks":ticks,"actual_moves":moved_steps,"final":final,"distance":distance,"arrival_contract_m":0.08,"activity":runtime.actor("player").activity})
	return ok

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(12,Building.generation_profiles()))
	expect("actual courtyard composition prepares",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	host=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
	expect("formal courtyard assembly supplies real services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	var query:RefCounted=building.current_space()
	var from:Dictionary=building.use_points("RH-HOME:shed:storage")[0]
	var gate:Dictionary=building.instance("RH-HOME:home:yard-gate")
	var rows:Array=[]
	var targets:Array=building.use_points(gate.id)
	for port:Dictionary in world.extension("generation:RH-HOME").parcels[0].entrance_ports:targets.append(Geometry.location(port.position))
	for target:Dictionary in targets:
		target.regionId="RH-HOME"
		var feet:Dictionary=query.standing_point(target)
		var result:Dictionary=query.route("player",from,target)
		rows.append({"from":from,"target":target,"standing":feet,"route":result})
		expect("exact supported outdoor gate/house portal is truly reachable "+str(target),result.ok,result.get("reason"))
		if not result.ok:continue
		var current:=from;var bad:Array=[];var replan_required:=false
		for step:Dictionary in result.steps:
			if step.kind=="move":
				var walk:Dictionary=query.walk("player",current,step.to,true)
				if not walk.ok or not Navigation.same(walk.location,step.to):
					bad.append({"from":current.duplicate(true),"step":step,"walk":walk})
					break
				else:current=walk.location
			elif step.kind=="open-door":
				var door:Dictionary=query.by_id.get(step.targetId,{})
				if door.is_empty() or door.door.locked or door.door.blocked or query.permission.call("player",door.id,"open",door)!=null or not Navigation.same(current,step.at):bad.append(step)
				replan_required=true
				break
			else:bad.append(step)
		expect("planned prefix proves every body segment up to its actual door transaction or destination",bad.is_empty() and (replan_required or Navigation.same(current,target)),bad)
	print("ACTUAL_HOUSING_GATE_PROBE "+JSON.stringify(rows))
	expect("exact gate interior and exterior use sides remain actual supported destinations",not query.standing_point(building.use_points(gate.id)[0]).is_empty() and not query.standing_point(building.use_points(gate.id)[1]).is_empty())
	if trace_to(from,"actual arrival to original shed handle"):
		for target:Dictionary in targets:
			if not trace_to(target,"actual shed/gate/house portal "+str(target)):break
			if target in building.use_points(gate.id):expect("actual reached gate remains usable through original contact/LOS authority",building.can_use("player",building.instance(gate.id))==null)
	host.free();finish(started)
