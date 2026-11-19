extends "res://tests/integration/run_resident_life.gd"
## A's generated opening, E's real decisions, B's steps, D's actual rig transforms.
## Headless transform evidence only; the formal Metal normal-camera check stays open.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")
var view:Node3D
var observations:Dictionary={}

func run()->void:
	host=Client.new()
	var generated:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("unchanged real generated opening prepares",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):finish();return
	var script:Script=Actors
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()>1:
		var original:=GDScript.new();original.source_code=FileAccess.get_file_as_string(args[1])
		check("archived source compiles for identical before comparison",original.reload()==OK)
		script=original
	view=script.new();root.add_child(view);view.configure(runtime)
	var baseline:Dictionary=runtime.capture_checkpoint()
	var visibility_errors:Array=[];var projection_changed_facts:=false
	for id:String in ["village-resident","repair-resident"]:
		observations[id]={"walking_ticks":0,"visible_walking_ticks":0,"streak":0,"max_streak":0,"post_first_cycle_poses":{},"travelled_metres":0.0}
	for i:int in 400:
		var before:Dictionary={}
		for id:String in observations:before[id]=Geometry.point(runtime.actor(id))
		runtime.tick(0.1)
		var checkpoint:Dictionary=runtime.capture_checkpoint() if i%50==0 else {}
		view.sync(0.1)
		for player:AnimationPlayer in view._animations.values():player.advance(0.1)
		var projection:Dictionary=runtime.actor_presentation()
		for id:String in observations:
			var a:Dictionary=runtime.actor(id);var sample:Dictionary=observations[id]
			var travel:Vector3=Geometry.point(a)-before[id]
			var walking:bool=Vector2(travel.x,travel.z).length_squared()>0.000001
			sample.travelled_metres+=Vector2(travel.x,travel.z).length()
			if view.roots[id].visible!=(id in projection.visible_actor_ids):visibility_errors.append({"id":id,"time":runtime.clock()})
			if walking and view._states.get(id)=="Walk":
				sample.walking_ticks+=1;sample.streak+=1;sample.max_streak=maxi(sample.max_streak,sample.streak)
				if view.roots[id].visible:sample.visible_walking_ticks+=1
				if sample.streak>12:
					var arm:Node3D=view._arms[id]
					sample.post_first_cycle_poses[str(arm.transform)]=true
			else:sample.streak=0
		if not checkpoint.is_empty() and not Data.json_equal(checkpoint,runtime.capture_checkpoint()):projection_changed_facts=true
	for id:String in observations:
		var sample:Dictionary=observations[id]
		check("real unjoined resident physically walks with original Walk "+id,sample.walking_ticks>20 and sample.travelled_metres>3,sample)
		check("actual limb transforms keep moving beyond first Walk cycle "+id,sample.max_streak>20 and sample.post_first_cycle_poses.size()>2,{"longest_walking_ticks":sample.max_streak,"distinct_post_cycle_arm_transforms":sample.post_first_cycle_poses.size()})
		check("presentation grants no membership consent or new supplies "+id,not runtime.actor(id).relationship.member and not runtime.actor(id).relationship.consent and runtime.actor(id).pack.is_empty())
	check("nearby familiar resident has true visible walking samples",observations["village-resident"].visible_walking_ticks>10,observations["village-resident"].visible_walking_ticks)
	check("every resident visibility follows actual runtime LOS exactly",visibility_errors.is_empty(),visibility_errors)
	check("animation sampling cannot mutate runtime world clock stocks or actor facts",not projection_changed_facts)
	check("untouched finite stocks remain conserved during actual autonomy",Data.json_equal(baseline.facts.stocks,runtime.facts().stocks))
	finish()

func finish()->void:
	for id:String in observations:
		observations[id].post_first_cycle_pose_count=observations[id].post_first_cycle_poses.size()
		observations[id].erase("post_first_cycle_poses")
	var report:Dictionary={"scope":"actual generated opening and autonomous routes; native rig transform sampling, no formal app/Metal/VA acceptance","checks":checks,"observations":observations,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var path:String=OS.get_cmdline_user_args()[0]
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("DDD_GENERATED_MOTION "+JSON.stringify({"checks":checks.size(),"failed":report.failed,"observations":observations}))
	if is_instance_valid(view):view.free()
	if host!=null:host.free()
	quit(1 if report.failed else 0)
