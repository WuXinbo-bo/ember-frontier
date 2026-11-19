extends "res://tests/buildings/generated_camp_suite.gd"
## Bounded trace of the actual seed-12 birth-to-storage route after speed tuning.
func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(12,Building.generation_profiles()))
	expect("real courtyard prepares",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	host=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
	expect("formal courtyard assembles",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	var target:="RH-HOME:home:storage"
	var reached:=false;var traces:Array=[]
	for at:Dictionary in building.use_points(target):
		var accepted:=command("walk","",{},at)
		var trace:Dictionary={"target":at,"accepted":accepted,"initial":runtime.actor("player"),"ticks":[]}
		var unchanged:=0
		if accepted.ok:
			for tick in 600:
				var before:=runtime.actor("player")
				if before.get("intent")==null:break
				runtime.tick(0.1)
				var after:=runtime.actor("player")
				if Geometry.location(before)==Geometry.location(after) and before.get("intent")==after.get("intent"):unchanged+=1
				else:unchanged=0
				if tick%20==0 or unchanged==25:
					var row:Dictionary={"tick":tick,"actor":after,"budget":runtime.movement_budget("player",0.1,"walk")}
					trace.ticks.append(row);print("HOUSING_MOTION_TICK "+JSON.stringify(row))
				if unchanged>=25:break
		trace.final=runtime.actor("player");trace.use_reason=building.can_use("player",building.instance(target))
		traces.append(trace)
		if trace.final.get("intent")==null and trace.use_reason==null:reached=true;break
	expect("birth route reaches courtyard storage with original body and current budget",reached,traces)
	print("HOUSING_MOTION_PROBE "+JSON.stringify(traces))
	host.free();finish(started)
