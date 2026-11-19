extends "res://tests/buildings/domain_suite.gd"
## Real C trunk/drop, B approach/harvest, finite owned axe and original rig.
## An observed gap is retained as a defect, never hidden by reach/body edits.
const ActorView=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var observations:Array=[]
func run()->void:
	for seed_value:int in [713,2026]:run_seed(seed_value)
	finish_probe()
func run_seed(seed_value:int)->void:
	world=World.new();building=Building.new();actions=Actions.new();production=Production.new();runtime=Runtime.new()
	expect("actual finite rural trunk world loads "+str(seed_value),world.load_snapshot(Generator.generate(seed_value)).ok)
	var trees:Array=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")
	expect("actual source contains real standing trunks",not trees.is_empty())
	if trees.is_empty():return
	# Start outside the original work reach, so B must select its own approach
	# rather than immediately preserving a legal but visually distant work pose.
	var tree:Dictionary=trees[0];var at:Dictionary=Geometry.location(tree);at.z+=3.2
	initialize_at(at,[],Generator.empty_resource_stocks(world))
	var tools:Dictionary=Production.empty_state();tools.tools=[{"id":"ddd:finite:axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0}]
	var draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	expect("finite original owned axe commits through sole world",draft.ok and world.commit_prepared(draft.capability).ok)
	var hints:Array=actions.work_points({"kind":"harvest","target_id":tree.id,"payload":{}})
	expect("actual harvest owner provides supported approach hints",not hints.is_empty())
	if hints.is_empty():return
	# Read B's original candidate order. This is an expected-goal query only;
	# the actual harvest command below owns route choice and body movement.
	var selected_hint:Dictionary={}
	for hint:Dictionary in hints:
		if actions.route("player",Geometry.location(runtime.actor("player")),hint).ok:selected_hint=hint;break
	expect("actual candidate order has a supported routable work point",not selected_hint.is_empty())
	if selected_hint.is_empty():return
	var started:Dictionary=command("harvest",tree.id,{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":["ddd:finite:axe"],"held":true,"direct":false})
	var approach:Variant=runtime.actor("player").intent
	expect("far real harvest delegates selection to original owner approach",started.ok and approach is Dictionary and approach.kind=="approach",started)
	if not started.ok or not approach is Dictionary or approach.kind!="approach":return
	var goal:Dictionary=approach.steps[-1].to
	expect("owner picks first routable hint without distance resort",Geometry.point(goal).is_equal_approx(Geometry.point(selected_hint)),{"goal":goal,"first_routable_hint":selected_hint})
	for i:int in 180:
		if not runtime.actor("player").intent is Dictionary or runtime.actor("player").intent.kind!="approach":break
		runtime.tick(.1)
	# B ends the final path segment inside its existing .08m arrival tolerance.
	# Keep the actual remaining offset in evidence; never snap the actor to it.
	var actual:Dictionary=runtime.actor("player");var remaining:float=Geometry.point(actual).distance_to(Geometry.point(selected_hint))
	var working:bool=actual.intent is Dictionary and actual.intent.kind=="harvest"
	expect("owner route reaches original arrival tolerance then starts real harvest",working and remaining<.08,{"remaining_m":remaining,"hint":selected_hint,"actual":Geometry.location(actual),"intent":actual.intent})
	if not working:return
	var volume:AABB=Geometry.aabb(tree.bounds);var foot:Vector3=Geometry.point(actual)
	var clearance:float=foot.distance_to(foot.max(volume.position).min(volume.end))
	expect("actual near-trunk feet retain full original body clearance",clearance>=.29999 and clearance<=.38001 and not building.current_space().standing_point(Geometry.location(actual)).is_empty(),{"clearance_m":clearance,"arrival_error_m":remaining})
	var view:=ActorView.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	var shoulder_origin:Vector3=view._arms.player.position
	if started.ok:
		var samples:Array=[];var preserved:=true;var unchanged:=true
		for i:int in 24:
			runtime.tick(.1)
			var before:Dictionary=runtime.capture_checkpoint();view.sync(0)
			unchanged=unchanged and Data.json_equal(before,runtime.capture_checkpoint())
			var row:Dictionary=view.statistics().work.player
			if not row.get("active",false) or not row.has("contact_result"):continue
			var arm:Node3D=view._arms.player;var prop:Node3D=view._props.player
			preserved=preserved and arm.position.is_equal_approx(shoulder_origin) and prop.position.is_equal_approx(Vector3(0,-.51,.06)) and arm.scale.is_equal_approx(Vector3.ONE) and prop.scale.is_equal_approx(Vector3.ONE) and view.roots.player.position.is_equal_approx(Geometry.point(runtime.actor("player"))) and is_equal_approx(arm.global_position.distance_to(prop.global_position),float(row.arm_contact.rigid_limb_m))
			samples.append({"progress":row.progress_seconds,"contact":row.contact,"arm":row.arm_contact,"result":row.contact_result,"tool_kind":prop.get_meta("tool_kind")})
		expect("real harvest owner drives all original axe contact samples",samples.size()==24 and samples.all(func(s:Dictionary)->bool:return s.tool_kind=="salvaged_axe"))
		expect("harvest solve cannot move body shoulder palm or stretch original limb",preserved and samples.all(func(s:Dictionary)->bool:return float(s.arm.shoulder_degrees)<=65.001 and float(s.result.wrist_degrees)<=35.001))
		expect("harvest display never advances original labor or stocks",unchanged)
		var strikes:Array=samples.filter(func(s:Dictionary)->bool:return float(s.arm.retraction_meters)<=.005)
		expect("actual close-trunk strike phases reach original blade surface",strikes.size()>=2 and strikes.all(func(s:Dictionary)->bool:return float(s.result.gap_meters)<=.04),strikes)
		expect("original blade never deeply penetrates actual trunk",samples.all(func(s:Dictionary)->bool:return float(s.result.signed_plane_gap)>=-.002))
		expect("actual cutting edge faces into trunk at contact",strikes.all(func(s:Dictionary)->bool:return float(s.result.normal_alignment)<-.5))
		observations.append({"seed":seed_value,"actual_actor":Geometry.location(runtime.actor("player")),"selected_hint":selected_hint,"owner_goal":goal,"arrival_error_m":remaining,"trunk_clearance_m":clearance,"tree":tree,"samples":samples,"contact_samples":samples.filter(func(s:Dictionary)->bool:return float(s.result.gap_meters)<=.04).size(),"scope":"actual current owner hint contact measurement, misses remain open"})
		expect("actual harvest cancel releases work",command("cancel").ok)
		view.sync(0)
		expect("harvest cancel removes manual pose correction",not view._manual_work.has("player"))
	view.free()
func finish_probe()->void:
	var result:Dictionary={"scope":"actual rural source/hint/harvest command with explicit finite owned axe; not normal economy, OS, package or VA contact approval","checks":checks,"failures":failures,"observations":observations}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_AXE_CONTACT "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
