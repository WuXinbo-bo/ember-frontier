extends "res://tests/modules/normal_module_lifecycle.gd"
## Exact old finite normal save -> real current Native/Runtime -> public zone
## commands and actual mature mother-tree labor. No material/position grants.
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];DirAccess.make_dir_recursive_absolute(outdir)
	var decoded:=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("original finite normal save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var native:=Native.new();live=native._assemble(decoded.capture);native.free()
	check("real current Native mounts all zone owners",live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var service:Variant=rt.domain_service("zonework")
	check("real zonework and ecology services attached",service!=null and rt.domain_service("ecology")!=null)
	if service==null:return finish()
	var unknown:=send(rt,"zonework.start","unknown",{"candidate_id":"zonework:forged","job":{"cost":{},"duration":0}})
	check("untrusted candidate injection rejected without work",not unknown.ok and service.state().jobs.is_empty(),unknown)
	var chosen:Dictionary={};var candidates:Array=[]
	var region:String=Geometry.location(rt.actor("player")).regionId
	var trees:Array=rt.world.entities(region).filter(func(e:Dictionary)->bool:return e.kind=="tree" and e.get("data",{}).get("harvest",{}).get("phase")=="standing" and e.get("data",{}).get("appearance",{}).get("model","")!="dead_tree")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(rt.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(rt.actor("player"))))
	for tree:Dictionary in trees.slice(0,20):
		var x:int=floori(float(tree.position.x)/.5);var z:int=floori(float(tree.position.z)/.5)
		var id:String="B:zone:mother:"+str(tree.id)
		var create:=send(rt,"zone.create",id,{"spec":{"kind":"forestry","region_id":region,"bounds":{"x0":x-2,"z0":z-2,"x1":x+3,"z1":z+3},"policy":{"mature_only":true,"replant":false}}})
		if not create.ok:continue
		candidates=service.work_candidates("player")
		for c:Dictionary in candidates:
			if c.zone_id==id and c.operation=="collect_seed" and c.valid:
				var request:Dictionary=c.command.duplicate(true);request.actor_id="player";request.command_id="B:zone:actual-seed:"+str(sequence)
				var result:Dictionary=rt.command(request);commands.append({"request":request,"result":result})
				if result.ok:chosen=c;break
		if not chosen.is_empty():break
		send(rt,"zone.cancel",id)
	check("actual generated mother tree offers executable local labor",not chosen.is_empty(),{"trees":trees.size(),"candidates":candidates})
	if chosen.is_empty():return finish()
	var seed:String="r34:conifer_seed" if chosen.job.get("tree_id")=="conifer" else "r34:broadleaf_seed"
	var initial_seed:float=float(rt.actor("player").pack.get(seed,0));var work_id:String=rt.actor("player").intent.id
	for step:int in 900:
		rt.tick(.1)
		var w:Dictionary=service.state().jobs.get(work_id,{})
		if not w.is_empty() and float(w.elapsed)>.2:break
	var work:Dictionary=service.state().jobs.get(work_id,{})
	check("real route completes before any nonzero labor",not work.is_empty() and float(work.elapsed)>.2 and Geometry.point(Geometry.location(rt.actor("player"))).distance_to(Geometry.point(work.location))<.25,{"work":work,"actor":rt.actor("player")})
	if work.is_empty():return finish()
	check("no seeds credited before labor completion",float(rt.actor("player").pack.get(seed,0))==initial_seed)
	var paused:=send(rt,"zonework.pause")
	var before:float=float(service.state().jobs[work_id].elapsed)
	for i:int in 8:rt.tick(.1)
	check("manual pause consumes no labor or output",paused.ok and float(service.state().jobs[work_id].elapsed)==before and rt.actor("player").pack.get(seed,0)==initial_seed)
	var handed:Dictionary=service.safe_handoff("player")
	# Use the original Runtime dispatcher/commit bridge, not a World write.
	var resumed:=send(rt,"zonework.resume","",{"work_id":work_id})
	check("original standard held resume keeps exact work identity",resumed.ok and rt.actor("player").intent.id==work_id and float(service.state().jobs[work_id].elapsed)==before,{"handoff_plan_only":handed.ok,"resume":resumed})
	cold("actual-zone-work-paused-progress")
	rt=live.runtime;service=rt.domain_service("zonework")
	check("cold job and current intent preserve exact elapsed",service.state().jobs.has(work_id) and float(service.state().jobs[work_id].elapsed)==before and rt.actor("player").intent.id==work_id)
	for i:int in 250:
		rt.tick(.1)
		if rt.actor("player").get("intent")==null:break
	check("one real mother-tree job credits exactly two seeds once",rt.actor("player").get("intent")==null and float(rt.actor("player").pack.get(seed,0))==initial_seed+2 and not service.state().jobs.has(work_id),{"jobs":service.state(),"ecology":rt.domain_service("ecology").state(),"actor":rt.actor("player")})
	var replay:=send(rt,"zonework.start",chosen.zone_id,{"candidate_id":chosen.id})
	check("mother-tree cooldown and candidate identity reject replay",not replay.ok and float(rt.actor("player").pack.get(seed,0))==initial_seed+2,replay)
	cold("actual-zone-seed-completed")
	live.runtime.retire();live={};finish()

func finish()->void:
	var report:Dictionary={"checks":checks,"commands":commands,"scope":"Exact original finite normal save, no grants/teleport/capture edits; current actual Native/Runtime public zone and labor commands, real supported movement, pause, cold restore, C sole settlement, replay rejection. Domain source only, not package/VA/OS/FPS."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(0 if not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
