extends "res://tests/buildings/domain_suite.gd"
## Compare authority receipts/checkpoints and CPU costs through the real rural sweep.
var samples:Array=[]
func run()->void:
	var at:Dictionary={"x":30.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var started:int=Time.get_ticks_msec()
	if not world.load_snapshot(Generator.generate(713)).ok:quit(1);return
	initialize_at(at)
	var seed:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seed.world_changes,world.get_revision())
	if not (draft.ok and world.commit_prepared(draft.capability).ok):quit(1);return
	var feet:Dictionary=building.current_space().standing_point(at)
	if feet.is_empty():quit(1);return
	var initial_world:Dictionary=world.snapshot()
	var reference:Dictionary={}
	for fast:bool in [false,true,true,false]:
		if not world.load_snapshot(initial_world).ok:quit(1);return
		runtime.retire()
		runtime=Runtime.new()
		initialize_at(feet,[],seed.initial_stocks)
		runtime._use_idle_direct_move=fast
		sequence=0
		var replies:Array=[]
		var times:Array=[]
		var prior_rev:int=runtime.get_revision()
		var which:int=samples.size()
		for i:int in 180:
			if i%3==0:runtime.tick(.1)
			var to:Dictionary=Geometry.location(runtime.actor("player"))
			var running:bool=i%12 in [2,3,6,7]
			to.x+=(.09 if running else .048)*(1 if i%2==0 else -1)
			var begin:int=Time.get_ticks_usec()
			var reply:Dictionary=command("direct_move","",{"movement_dt":.02,"movement_mode":"run" if running else "walk"},to)
			times.append(Time.get_ticks_usec()-begin)
			replies.append(reply)
		var bad:Dictionary=Geometry.location(runtime.actor("player"));bad.x+=20
		var failed:Dictionary=command("direct_move","",{"movement_dt":.02,"movement_mode":"walk"},bad)
		expect("all real inputs admitted",replies.all(func(r:Dictionary)->bool:return r.ok),which)
		expect("out-of-budget position rejects",not failed.ok,failed)
		var resting:Dictionary=command("rest")
		expect("existing rest intent enabled",resting.ok)
		runtime.tick(.1)
		var leave:Dictionary=Geometry.location(runtime.actor("player"));leave.x+=.048
		var interrupted:Dictionary=command("direct_move","",{"movement_dt":.02,"movement_mode":"walk"},leave)
		expect("move cancels active rest through the standard path",interrupted.ok and runtime.actor("player").intent==null,interrupted)
		var result:Dictionary={"capture":runtime.capture_checkpoint(),"replies":replies,"failed":failed,"interrupt":interrupted,"revision_delta":runtime.get_revision()-prior_rev}
		if reference.is_empty():reference=result
		else:
			var diff:Array=[]
			for key:String in reference:
				if reference[key]!=result[key]:diff.append(key)
			if reference.replies[0]!=result.replies[0]:print("FIRST_MOTION_DIFF ",JSON.stringify([reference.replies[0],result.replies[0]]))
			if reference.capture!=result.capture:print("CAPTURE_DIFF ",str(reference.capture.keys().filter(func(k:Variant)->bool:return reference.capture[k]!=result.capture.get(k))))
			expect("full receipt and checkpoint equality",diff.is_empty(),[which,diff])
		times.sort()
		var total:int=0
		for value:int in times:total+=value
		var hits:int=int(runtime.authority_costs().phases.get("idle_direct_move",{}).get("count",0))
		expect("first move initializes legacy orders, then takes the fast path",hits==179 if fast else hits==0,hits)
		samples.append({"fast":fast,"median_ms":times[90]/1000.0,"p95_ms":times[170]/1000.0,"mean_ms":total/180000.0,"hits":hits})
	print("DIRECT_MOTION_ABBA "+JSON.stringify({"checks":checks.size(),"failures":failures,"samples":samples,"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)
