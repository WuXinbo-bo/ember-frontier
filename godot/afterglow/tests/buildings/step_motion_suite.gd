extends "res://tests/buildings/domain_suite.gd"
## Explicit .5m/1m/void fixtures edited through C's real voxel CAS, then real
## A/B movement commands. Original radius, sweep and support rules stay intact.
var routes:Array=[]

func apply_fixture(changes:Array,label:String)->bool:
	var prepared:=world.prepare_changes(changes,world.get_revision())
	var ok:bool=prepared.ok and world.commit_prepared(prepared.capability).ok
	expect(label,ok,prepared.get("reason"))
	return ok

func move_sequence(origin:Dictionary,direction:Vector2,mode:String,label:String)->void:
	initialize_at(origin)
	var started:=Geometry.location(runtime.actor("player"));var highest:=float(started.y);var all_safe:=true;var failure:Dictionary={};var moves:=0
	for sign_value:int in [1,-1]:
		for n in 6:
			var from:=Geometry.location(runtime.actor("player"))
			var budget:Dictionary=runtime.movement_budget("player",0.1,mode)
			var to:=from.duplicate(true);to.x+=direction.x*float(budget.max_distance)*sign_value;to.z+=direction.y*float(budget.max_distance)*sign_value
			var accepted:=command("direct_move","",{"movement_dt":0.1,"movement_mode":mode},to)
			if not accepted.ok:all_safe=false;failure={"n":n,"sign":sign_value,"from":from,"to":to,"result":accepted};break
			var at:=Geometry.location(runtime.actor("player"));highest=maxf(highest,float(at.y));moves+=1
			if absf(float(at.y)-float(from.y))>0.550001 or building.current_space().standing_point(at).is_empty():all_safe=false;failure={"unsupported_after":at};break
			runtime.tick(0.1)
		if not all_safe:break
	var last:=Geometry.location(runtime.actor("player"))
	expect(label+" uses real commands up and down exact .5m without changing body",all_safe and moves==12 and highest==0.5 and absf(float(last.y))<0.000001 and Geometry.point(last).distance_to(Geometry.point(started))<0.0001,failure)
	routes.append({"label":label,"commands":moves,"highest":highest,"actual":last,"origin":started,"ok":all_safe,"failure":failure})

func reject_edge(origin:Dictionary,direction:Vector2,label:String)->void:
	initialize_at(origin)
	var rejected:=false;var evidence:Dictionary={}
	for n in 6:
		var from:=Geometry.location(runtime.actor("player"));var to:=from.duplicate(true)
		to.x+=direction.x*0.28;to.z+=direction.y*0.28
		var before:=runtime.capture_checkpoint()
		var accepted:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},to)
		if not accepted.ok:
			rejected=runtime.capture_checkpoint()==before;evidence=accepted;break
		runtime.tick(0.1)
	expect(label+" rejects before crossing and leaves all authority unchanged",rejected,evidence)

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("original retained flat rural terrain loads for explicit edit fixtures",world.load_snapshot(Generator.generate(713)).ok)
	var changes:Array=[]
	# A 4x4m plateau at .5m, a separate 1m riser and a 1m-deep unsupported gap.
	for x in range(64,72):
		for z in range(60,68):changes.append({"op":"voxel.set","cell":{"x":x,"y":0,"z":z},"before":world.cell_at(x,0,z),"after":1})
	for x in range(80,88):
		for z in range(60,68):
			for y in [0,1]:changes.append({"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":world.cell_at(x,y,z),"after":1})
	for x in range(64,72):
		for z in range(80,88):
			for y in [-1,-2]:changes.append({"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":world.cell_at(x,y,z),"after":0})
	if not apply_fixture(changes,"real C voxel preparation commits only explicit step fixtures"):finish(started);return
	for mode:String in ["walk","run"]:
		for example:Dictionary in [{"x":31.4,"z":32.0,"d":Vector2.RIGHT},{"x":36.6,"z":32.0,"d":Vector2.LEFT},{"x":34.0,"z":29.4,"d":Vector2.DOWN},{"x":34.0,"z":34.6,"d":Vector2.UP},{"x":31.4,"z":29.4,"d":Vector2(1,1).normalized()},{"x":36.6,"z":34.6,"d":Vector2(-1,-1).normalized()}]:
			var p:Dictionary={"x":example.x,"y":0.0,"z":example.z,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
			move_sequence(p,example.d,mode,mode+" approach "+str([example.x,example.z]))
	reject_edge({"x":39.4,"y":0.0,"z":32.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null},Vector2.RIGHT,"one metre tall riser")
	reject_edge({"x":31.4,"y":0.0,"z":42.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null},Vector2.RIGHT,"one metre support gap")
	print("STEP_ROUTES "+JSON.stringify(routes))
	finish(started)
