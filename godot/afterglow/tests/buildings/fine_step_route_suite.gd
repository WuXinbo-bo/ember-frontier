extends "res://tests/buildings/generated_camp_suite.gd"
## Planned topology is only a guide: every 7.3cm goes through the same runtime
## direct_move command as WASD. No teleports, free items or fake door changes.
var fine_rows:Array=[]
var total_steps:=0

func fine_walk(goal:Dictionary,label:String)->bool:
	var result:Dictionary={};var replan:=true;var steps:Array=[];var index:=0;var opens:=0;var moves:=0
	var started:=Time.get_ticks_usec()
	for attempt in 4000:
		var from:=Geometry.location(runtime.actor("player"))
		if from.regionId==goal.regionId and Geometry.point(from).distance_to(Geometry.point(goal))<0.08:
			expect(label+" reaches target by actual input-sized runtime steps",true)
			fine_rows.append({"label":label,"ok":true,"moves":moves,"opened_doors":opens,"from_origin":goal,"actual":from,"cpu_ms":float(Time.get_ticks_usec()-started)/1000})
			return true
		if replan:
			result=actions.route("player",from,goal)
			if not result.ok:break
			steps=result.steps;index=0;replan=false
		if index>=steps.size():result={"ok":false,"reason":"empty or exhausted candidate route before real arrival"};break
		var step:Dictionary=steps[index]
		if step.kind=="open-door":
			result=command("door",str(step.targetId),{"operation":"open"})
			if not result.ok:break
			for n in 8:
				if runtime.actor("player").get("intent")==null:break
				runtime.tick(0.1)
			if not building.instance(str(step.targetId)).door.open:result={"ok":false,"reason":"actual timed door did not open"};break
			opens+=1;replan=true;continue
		if step.kind not in ["move","stairs","cross-region"]:result={"ok":false,"reason":"unknown candidate kind","step":step};break
		var to:=Geometry.location(step.to)
		var distance:=Vector2(to.x-from.x,to.z-from.z).length()
		if distance<0.015 and absf(float(to.y)-float(from.y))<0.025:index+=1;continue
		var desired:=from.duplicate(true);var fraction:=minf(1,0.0733333333/maxf(distance,0.000001))
		desired.x=lerpf(from.x,to.x,fraction);desired.z=lerpf(from.z,to.z,fraction)
		result=command("direct_move","",{},desired)
		if not result.ok:
			result.evidence={"from":from,"desired":desired,"candidate":step,"route_index":index};break
		moves+=1;total_steps+=1
		# Same fixed runtime clock/NPCs/needs, 2.2m/s motion at 30Hz input.
		runtime.tick(1.0/30.0)
		if Geometry.point(Geometry.location(runtime.actor("player"))).distance_to(Geometry.point(to))<0.025:index+=1
	expect(label+" reaches target by actual input-sized runtime steps",false,result)
	fine_rows.append({"label":label,"ok":false,"moves":moves,"opened_doors":opens,"failure":result,"cpu_ms":float(Time.get_ticks_usec()-started)/1000})
	return false

func run()->void:
	var started:=Time.get_ticks_msec()
	for seed_value:int in [713,2026]:
		host=Client.new();var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(seed_value,Building.generation_profiles()))
		expect("actual finite world for input-sized route "+str(seed_value),prepared.ok,prepared.get("reason"))
		if not prepared.ok:host.free();continue
		var assembled:Dictionary=host._assemble(prepared.capture)
		expect("formal complete services for input route "+str(seed_value),assembled.ok,assembled.get("reason"))
		if not assembled.ok:host.free();continue
		world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
		var home:="RH-HOME:home";var query:RefCounted=building.current_space()
		var plan:Dictionary=world.extension("generation:RH-HOME")
		var goal:=Geometry.location(plan.anchors.home);goal.regionId="RH-HOME"
		if not fine_walk(goal,"seed%d spawn to actual elevated home"%seed_value):host.free();continue
		var stock:="RH-HOME:home:storage"
		var point:Dictionary=query.standing_point(building.use_points(stock)[0])
		if point.is_empty():expect("real stock use region supports input-sized route",false);host.free();continue
		if not fine_walk(point,"seed%d home entrance through actual rooms to storage"%seed_value):host.free();continue
		expect("seed%d normal endpoint supports actual finite inventory transfer"%seed_value,command("take",stock,{"items":{"water":1}}).ok)
		var village:Dictionary=world.extension("generation:RH-VILLAGE")
		goal=Geometry.location(village.anchors.arrival);goal.regionId="RH-VILLAGE"
		if fine_walk(goal,"seed%d home to true adjacent village via physical connection"%seed_value):
			var arrival:=Geometry.location(plan.anchors.arrival);arrival.regionId="RH-HOME"
			fine_walk(arrival,"seed%d village back to original arrival"%seed_value)
		expect("seed%d input routes never add starting items or learning"%seed_value,production.state().knowledge.is_empty() and runtime.actor("player").pack.food==1 and runtime.actor("player").pack.water==2)
		host.free();host=null
	print("ACTUAL_FINE_STEP_ROUTES "+JSON.stringify({"total_runtime_move_commands":total_steps,"routes":fine_rows,"scope":"headless command-level fine movement, not OS WASD/input or visual/FPS pass"}))
	finish(started)
