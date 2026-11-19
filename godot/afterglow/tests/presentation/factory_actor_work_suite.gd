extends "res://tests/buildings/domain_suite.gd"
## Explicit public work projection over real runtime/GLB. Not B owner validation.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const ToolView=preload("res://scripts/presentation/held_tool_view.gd")
class PresentedRuntime extends "res://scripts/runtime/game_runtime.gd":
	var fixture:Dictionary={}
	func actor_presentation()->Dictionary:
		var result:Dictionary=super.actor_presentation()
		result.work={"player":fixture.duplicate(true)}
		return result
var view:Node3D
func run()->void:
	runtime=PresentedRuntime.new()
	expect("finite source world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var tools:Dictionary=Production.empty_state();tools.tools=[{"id":"fixture:axe","kind":"salvaged_axe","holderId":"pack:player","durability":1.0,"qualities":{}}]
	var draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	expect("finite owned contact tool is registered",draft.ok and world.commit_prepared(draft.capability).ok)
	var facts:Dictionary=runtime.facts()
	facts.actors[0].intent={"schema_version":1,"id":"fixture:work","owner":"actions","kind":"harvest","order_id":"fixture:order","tool_id":"fixture:axe","held":true,"request":{"actor_id":"player","kind":"harvest","target_id":"fixture:tree","payload":{}}}
	expect("restored explicit intent schema accepted",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	runtime.fixture={"owner":"actions","kind":"harvest","progress_seconds":0.18,"duration_seconds":4.0,"effective_work":true,"paused_reason":""}
	view=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	var animator:AnimationPlayer=view._animations.player
	expect("valid owner progress drives Use manually",view._states.player=="Use" and view.statistics().work.player.available and animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	var arm:Transform3D=view._arms.player.transform
	var time:float=animator.current_animation_position
	var before:Dictionary=runtime.capture_checkpoint()
	for delta:float in [0.016,0.25,1.0]:
		view.sync(delta)
		await process_frame
	expect("rendered frames and wall delta never advance work pose",view._arms.player.transform.is_equal_approx(arm) and is_equal_approx(animator.current_animation_position,time),{"before":str(arm),"after":str(view._arms.player.transform)})
	runtime.fixture.progress_seconds=0.42;view.sync(0)
	expect("real projection progress changes the original arm pose",not view._arms.player.transform.is_equal_approx(arm))
	var contact:Dictionary=ToolView.contact_frame(view._props.player)
	var point:Vector3=Vector3(contact.point_world)+Vector3(0.03,0,0)
	runtime.fixture.contact={"position":[point.x,point.y,point.z],"normal":[0.0,0.0,-1.0]}
	# The visual root now faces the supplied surface. Measure improvement from
	# that same faced original pose; a point sampled before turning is not a
	# guaranteed reachable target after a shoulder-offset body turns toward it.
	view._face_action(view.roots.player,runtime.actor("player"),0,{"active":true,"contact":runtime.fixture.contact})
	animator.seek(fposmod(float(runtime.fixture.progress_seconds),animator.get_animation("Use").length),true)
	view._props.player.rotation=Vector3(PI/2,0,0)
	var original_gap:float=Vector3(ToolView.contact_frame(view._props.player).point_world).distance_to(point)
	view.sync(0)
	expect("owner contact reduces faced original pose gap while retaining palm grip",view._props.player.position.is_equal_approx(Vector3(0,-0.51,0.06)) and float(view.statistics().work.player.contact_result.gap_meters)<original_gap and float(view.statistics().work.player.contact_result.wrist_degrees)<=35.001,{"original_gap_m":original_gap,"corrected":view.statistics().work.player.contact_result})
	runtime.fixture.contact.position=[1000.0,1000.0,1000.0];view.sync(0)
	expect("unreachable visual contact is reported without teleport or fake hit",not view.statistics().work.player.contact_result.visual_contact and view._props.player.position.is_equal_approx(Vector3(0,-0.51,0.06)) and Data.json_equal(before,runtime.capture_checkpoint()))
	arm=view._arms.player.transform;runtime.set_paused(true);runtime.fixture.effective_work=false;runtime.fixture.paused_reason="paused"
	var tool_pose:Transform3D=view._props.player.transform
	view.sync(0.2);await process_frame
	expect("global pause freezes corrected shoulder wrist and effective pose",view._states.player=="Use" and view._arms.player.transform.is_equal_approx(arm) and view._props.player.transform.is_equal_approx(tool_pose) and is_zero_approx(animator.speed_scale))
	runtime.set_paused(false)
	for reason:String in ["missing_input","missing_operator","region_paused","target_destroyed"]:
		runtime.fixture.paused_reason=reason;runtime.fixture.effective_work=false;view.sync(0)
		expect("real work blocker stops Use "+reason,view._states.player=="Idle" and not view.statistics().work.player.active and animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)
	runtime.fixture.paused_reason="";runtime.fixture.effective_work=true;view.sync(0)
	expect("cleared owner blocker resumes from real progress",view._states.player=="Use" and is_equal_approx(animator.current_animation_position,fposmod(0.42,animator.get_animation("Use").length)))
	runtime.fixture={};view.sync(0)
	expect("missing owner provider remains explicit ordinary clip fallback",view._states.player=="Use" and not view.statistics().work.player.available and animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)
	runtime.fixture={"owner":"workforce","kind":"harvest","progress_seconds":1.0,"duration_seconds":4.0,"effective_work":true,"paused_reason":""};view.sync(0)
	expect("different owner cannot drive a work contact",not view.statistics().work.player.available)
	expect("display never changes real labor clock tool stock or intent",Data.json_equal(before,runtime.capture_checkpoint()))
	facts=runtime.facts();facts.actors[0].intent=null
	expect("actual intent interruption accepted",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("stale progress cannot continue an interrupted action",view._states.player=="Idle" and not view.statistics().work.player.available and not view._manual_work.has("player"))
	view.free();await process_frame
	var result:Dictionary={"scope":"explicit public work DTO over actual runtime and original GLB; not actual B work provider, action reach/settlement or OS/VA","checks":checks,"failures":failures}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_FACTORY_ACTOR_WORK ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
