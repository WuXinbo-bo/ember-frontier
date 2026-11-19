extends "res://tests/buildings/domain_suite.gd"
## Actual structure/held/rest commands, original rigs and shared runtime facts.
## This diagnoses presentation; it does not replace normal-camera VA.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D
func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("actual C rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":33.3,"y":0,"z":40.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at)
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision()) if seeded.ok else seeded
	expect("actual B buildings committed",draft.ok and world.commit_prepared(draft.capability).ok)
	if not draft.ok:finish(started);return
	initialize_at(at,[],seeded.initial_stocks)
	var facts:Dictionary=runtime.facts();facts.actors[0].pack={"timber":8,"scrap":8}
	var tools:Dictionary=Production.empty_state();tools.tools=seeded.initial_tools;tools.records=seeded.initial_records;tools.knowledge={"player":["basic_woodwork"]}
	for tool:Dictionary in tools.tools:tool.holderId="pack:player"
	draft=world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	expect("same finite owned tools and material fixture registered",draft.ok and world.commit_prepared(draft.capability).ok)
	expect("same actual runtime accepts facts",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view=Actors.new();root.add_child(view);view.configure(runtime)
	var animator:AnimationPlayer=view._animations.player
	var rig:Node3D=animator.get_node(animator.root_node).get_node(animator.get_animation("RestLying").track_get_path(0))
	var standing:Transform3D=rig.transform
	var bench:Dictionary=building.make_instance("workbench","ddd:motion-bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	if not prepare_structure_position(bench):finish(started);return
	var work:Dictionary=command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"})
	expect("real finite construction starts",work.ok,work.get("reason"))
	if not work.ok:finish(started);return
	runtime.tick(0.1)
	view.sync(0.1);settle(animator)
	expect("actual held construction binds original Use and owned hammer",view._states.get("player")=="Use" and view._props.has("player"))
	var work_frame:Dictionary=runtime.actor_presentation().work.player
	expect("actual B owner provides effective work through A public facade",work_frame.owner=="actions" and work_frame.work_domain=="structure" and work_frame.effective_work and work_frame.paused_reason.is_empty() and work_frame.progress_seconds>0,work_frame)
	view.sync(0)
	var pose:Transform3D=view._arms.player.transform
	await process_frame;await process_frame;view.sync(0.2)
	expect("wall frames cannot advance actual effective work pose",view._arms.player.transform.is_equal_approx(pose) and animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	runtime.tick(0.2);view.sync(0)
	expect("actual B work progress moves original Use with real contact diagnostic",not view._arms.player.transform.is_equal_approx(pose) and view.statistics().work.player.has("contact_result"),view.statistics().work.player)
	var samples:Array=[];var minimum_gap:float=INF;var maximum_gap:float=0
	for i:int in 12:
		runtime.tick(0.1);view.sync(0)
		var measured:Dictionary=view.statistics().work.player
		if measured.has("contact_result"):
			var gap:float=float(measured.contact_result.gap_meters)
			minimum_gap=minf(minimum_gap,gap);maximum_gap=maxf(maximum_gap,gap)
			samples.append({"progress":measured.progress_seconds,"gap":gap,"shoulder":measured.arm_contact.shoulder_degrees,"wrist":measured.contact_result.wrist_degrees})
	expect("actual effective stroke preserves pivot and reports finite surface gaps",samples.size()==12 and is_finite(minimum_gap) and view._arms.player.position.is_finite(),{"minimum_gap_m":minimum_gap,"maximum_gap_m":maximum_gap,"samples":samples,"acceptance":"geometry observation only; not normal camera contact VA"})
	expect("all sustained delivered states loop while transient Hit stays single",["Idle","Walk","Run","Carry","CarryWalk","RestLying"].all(func(name:String)->bool:return animator.get_animation(name).loop_mode==Animation.LOOP_LINEAR) and animator.get_animation("Hit").loop_mode==Animation.LOOP_NONE)
	var original:Node3D=load(Actors.MODEL_PATHS[0]).instantiate()
	var source_player:AnimationPlayer=view._find_animation(original)
	expect("derived loop binding never modifies the imported source animation",source_player.get_animation("Use").loop_mode==Animation.LOOP_NONE)
	original.free()
	var contact_point:Array=runtime.actor_presentation().work.player.contact.position
	var direction:Vector3=Vector3(contact_point[0],contact_point[1],contact_point[2])-view.roots.player.position;direction.y=0;direction=direction.normalized()
	expect("stationary labor faces owner actual work surface",view.roots.player.basis.z.normalized().dot(direction)>0.99,{"forward":str(view.roots.player.basis.z),"target_direction":str(direction)})
	var paused:Dictionary=command("held","",{"held":false})
	expect("real held command pauses the same construction",paused.ok and not runtime.actor("player").intent.held,paused.get("reason"))
	var elapsed:float=runtime.actor("player").intent.get("elapsed",0.0)
	for i:int in 3:runtime.tick(0.1)
	expect("paused labor does not progress in authority",is_equal_approx(float(runtime.actor("player").intent.get("elapsed",0.0)),elapsed))
	var before:Dictionary=runtime.capture_checkpoint()
	view.sync(0.1);settle(animator)
	var interrupted_state:String="Carry" if Actors.is_carrying(runtime.actor("player")) else "Idle"
	expect("paused actual labor stops Use and retains actual material load",view._states.get("player")==interrupted_state,view.statistics())
	var arm:Transform3D=view._arms.player.transform
	animator.advance(0.25);animator.advance(0.25)
	expect("paused work arm stays in original non-work pose",view._arms.player.transform.is_equal_approx(arm),{"before":str(arm),"after":str(view._arms.player.transform)})
	expect("pose updates cannot advance labor clock stocks or reservations",Data.json_equal(before,runtime.capture_checkpoint()))
	expect("same actual held command resumes labor",command("held","",{"held":true}).ok)
	runtime.tick(0.1)
	view.sync(0.1);settle(animator)
	expect("resumed actual labor recovers original Use",view._states.get("player")=="Use")
	expect("actual cancel clears construction",command("cancel").ok and runtime.actor("player").intent==null)
	expect("actual rest command starts",command("rest").ok)
	view.sync(0.1);settle(animator)
	expect("original rest animation visibly changes the rig pose",view._states.get("player")=="RestLying" and not rig.transform.is_equal_approx(standing),str(rig.transform))
	expect("actual rest cancellation succeeds",command("cancel").ok)
	view.sync(0.1);settle(animator)
	var restored_state:String="Carry" if Actors.is_carrying(runtime.actor("player")) else "Idle"
	expect("native original blend restores standing and actual load after rest",view._states.get("player")==restored_state and rig.transform.is_equal_approx(standing),str(rig.transform))
	finish(started)
func prepare_structure_position(_bench:Dictionary)->bool:
	return true
func settle(animator:AnimationPlayer)->void:
	if animator.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:return
	animator.advance(0);animator.advance(0.4);animator.advance(0.01)
func finish(started:int)->void:
	if is_instance_valid(view):view.free()
	print("DDD_MOTION "+JSON.stringify({"scope":"original rig and actual runtime work/held/rest commands; not formal app or VA","checks":checks,"failures":failures,"ok":failures.is_empty(),"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)
