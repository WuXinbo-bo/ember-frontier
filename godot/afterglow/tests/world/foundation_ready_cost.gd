extends SceneTree
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const State=preload("res://scripts/world/world_state.gd")
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:push_error("FAIL "+label)
func summary(samples:Array)->Dictionary:
	var sorted:=samples.duplicate();sorted.sort()
	return {"samples_usec":samples,"median_usec":sorted[sorted.size()/2],"p95_usec":sorted[int((sorted.size()-1)*0.95)],"max_usec":sorted[-1]}
func run()->void:
	var assembled:=Assembly.prepare(Landscape.generate(973339546,Buildings.generation_profiles()))
	check("actual complete A/B source assembled",assembled.ok)
	if not assembled.ok:quit(1);return
	var world:=State.new();world.load_snapshot(assembled.capture.world)
	var terrain:=Terrain.new();root.add_child(terrain);terrain.configure({"world":world,"budgeted_edits":true,"stream_updates":true});terrain.set_process(false)
	var points:Array=[]
	for a:Dictionary in assembled.capture.facts.actors:
		if float(a.hp)>0:points.append(Vector3(a.x,a.y,a.z))
	var initial:=terrain.readiness_near(points,2.5,0.5,2.0)
	check("real nearby initially pending instead of optimistic ready",not initial.ready and not initial.pending.is_empty())
	terrain.prioritize(initial.keys)
	var process_samples:Array=[];var calls:=0
	while calls<4096:
		var start:=Time.get_ticks_usec();terrain.process_budget(4000);process_samples.append(Time.get_ticks_usec()-start);calls+=1
		await process_frame
		if terrain.readiness_near(points,2.5,0.5,2.0).geometry_ready:break
	await physics_frame;await process_frame
	check("same body/tool neighborhood has actual physics barrier",terrain.readiness_near(points,2.5,0.5,2.0).ready)
	var runtime:=Runtime.new()
	check("actual runtime facts configure for A current provider",runtime.configure({"world":world,"facts":assembled.capture.facts,"services":{"buildings":Buildings.new(),"actions":Actions.new(),"production":Production.new()}}).ok)
	# Do not add the composition root to the tree or invoke _ready: no app,
	# startup, user-save/controls IO or preview. Call the actual pure provider.
	var native:=Native.new();native.runtime=runtime;native.world=world;native._terrain_view=terrain
	var provider_times:Array=[];var provider_ok:=true
	for sample in 102:
		var start:=Time.get_ticks_usec();var ready:Dictionary=native._runtime_readiness()
		var usec:=Time.get_ticks_usec()-start
		provider_ok=provider_ok and ready.ready and ready.ok
		if sample>=2:provider_times.append(usec)
	check("actual A provider always consumes current C readiness",provider_ok)
	native.free()
	var keys:Dictionary={};var rows:Array=[]
	for radius:float in [0.32,2.5]:
		var samples:Array=[];var correct:=true
		for sample in 102:
			var start:=Time.get_ticks_usec();var ready:=terrain.readiness_near(points,radius,0.5,2.0)
			var usec:=Time.get_ticks_usec()-start
			correct=correct and ready.ready
			if sample>=2:samples.append(usec)
			keys[str(radius)]=ready.keys.size()
		check("all actual ready queries exact for radius "+str(radius),correct)
		rows.append({"radius_m":radius,"actors":points.size(),"keys":keys[str(radius)],"timing":summary(samples)})
	check("more than64 points rejected",not terrain.readiness_near(Array(range(65)),2.5).get("ready",false))
	check("unbounded radius rejected",terrain.readiness_near(points,16.01).get("code")=="INVALID_READY_BOUNDS")
	check("nonfinite position rejected",terrain.readiness_near([Vector3(INF,0,0)]).get("code")=="INVALID_READY_POINT")
	var before_revision:=world.get_revision();terrain.cancel_pending()
	check("cancellation changes no world fact or revision",world.get_revision()==before_revision and terrain.statistics().pending==0)
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary):return not c.ok).size(),"queries":rows,"A_actual_provider":summary(provider_times),"initial_drain":{"calls":calls,"process":summary(process_samples)},"stages":terrain.statistics().stages,"scope":"Actual current A/B assembled three live actors and native C mesh/collision/physics in isolated headless; 2 warmups +100 query samples. Actual A _runtime_readiness called without adding NativeClient to tree or starting it; no saves/controls/preview. Not A full fixed-step timing, Metal/FPS/VA or a hard4ms guarantee."}
	terrain.free()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if result.failed else 0)
