extends "res://tests/buildings/domain_suite.gd"
## Three real rigs; explicit geometry-only work samples, never owner/VA proof.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const WorkPose=preload("res://scripts/presentation/factory_work_pose.gd")
const Data=preload("res://scripts/world/world_data.gd")
func run()->void:
	expect("real finite source loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("neighbor",at.merged({"x":31},true)),resident("shopkeeper",at.merged({"x":32},true))])
	var tools:Dictionary=Production.empty_state()
	for id:String in ["player","neighbor","shopkeeper"]:
		for kind:String in ["salvaged_axe","shovel","pickaxe"]:tools.tools.append({"id":"fixture:"+id+":"+kind,"kind":kind,"holderId":"pack:"+id,"durability":100.0})
	var draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	expect("finite independent original tools commit",draft.ok and world.commit_prepared(draft.capability).ok)
	var view:=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	var before:Dictionary=runtime.capture_checkpoint()
	for id:String in ["player","neighbor","shopkeeper"]:
		for kind:String in ["salvaged_axe","shovel","pickaxe"]:probe(view,id,kind)
		expect("per-actor pose cache clears before retirement "+id,not view._work_postures.has(id))
		view._retire_actor(id)
		expect("retirement retains no joint node references "+id,not view._work_postures.has(id) and not view._manual_work.has(id) and not view._work_pose_keys.has(id) and not view._work_pose_results.has(id))
	expect("pose consumer never changes sole authority",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free()
	var result:Dictionary={"scope":"three delivered rigs, finite tools and synthetic contact geometry for dimensions/pause/idempotence/restoration; actual work contact is checked separately; not OS/VA","checks":checks,"failures":failures}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_WORK_POSTURE "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)

func probe(view:Node3D,id:String,kind:String)->void:
	var a:Dictionary=runtime.actor(id).duplicate(true);a.intent={"tool_id":"fixture:"+id+":"+kind}
	view._update_props(a,{},false,"Use")
	var arm:Node3D=view._arms[id];var torso:Node3D=arm.get_parent();var prop:Node3D=view._props[id]
	var body:Transform3D=view.roots[id].transform;var arm_origin:Vector3=arm.position;var palm:Vector3=prop.position
	var original_legs:Array=[torso.get_node("leg_l").transform,torso.get_node("leg_r").transform]
	var dimensions:=true;var feet:=true;var deterministic:=true;var bounds:=true
	var maximum_tip_drift:float=0;var maximum_joint_angle:float=0
	var work:Dictionary={"available":true,"active":true,"progress_seconds":0.1,"contact":{"position":[float(a.x)+.15,float(a.y)+(1.0 if kind=="salvaged_axe" else .5 if kind=="shovel" else 0.0),float(a.z)+.55],"normal":[0.0,0.0,-1.0] if kind=="salvaged_axe" else [0.0,1.0,0.0]}}
	view._play(id,"Use",1.0)
	for progress:float in [.1,.2,.3,.4,.5,.6,.7,.8]:
		work.progress_seconds=progress;view._sync_work_pose(id,"Use",work,false)
		dimensions=dimensions and arm.position.is_equal_approx(arm_origin) and prop.position.is_equal_approx(palm) and view.roots[id].transform.is_equal_approx(body) and torso.scale.is_equal_approx(Vector3.ONE) and arm.scale.is_equal_approx(Vector3.ONE) and prop.scale.is_equal_approx(Vector3.ONE)
		for row:Dictionary in view._work_postures[id].legs:feet=feet and row.node.global_position.distance_to(row.world.origin)<.00002 and row.node.global_basis.is_equal_approx(row.world.basis)
		bounds=bounds and work.arm_contact.shoulder_degrees<=65.001 and work.contact_result.wrist_degrees<=35.001 and work.posture.hip_bend_degrees<=100.001
		var first:Transform3D=torso.transform;var first_arm:Transform3D=arm.transform;var first_tool:Transform3D=prop.transform
		var first_tip:Vector3=prop.global_transform*Vector3(prop.get_meta("contact_point"))
		# Repeated float transforms need a metric stability bound, not bitwise
		# Basis equality. Keep physical contact/penetration limits separate.
		for repeated:int in 20:
			view._sync_work_pose(id,"Use",work,false)
			var tip:Vector3=prop.global_transform*Vector3(prop.get_meta("contact_point"))
			maximum_tip_drift=maxf(maximum_tip_drift,tip.distance_to(first_tip))
			maximum_joint_angle=maxf(maximum_joint_angle,maxf(rad_to_deg(arm.quaternion.normalized().angle_to(first_arm.basis.get_rotation_quaternion().normalized())),rad_to_deg(prop.quaternion.normalized().angle_to(first_tool.basis.get_rotation_quaternion().normalized()))))
			deterministic=deterministic and torso.transform.is_equal_approx(first) and arm.position.is_equal_approx(first_arm.origin) and prop.position.is_equal_approx(first_tool.origin) and maximum_tip_drift<.0001 and maximum_joint_angle<.1
	expect("original body palm shoulder and scales preserved "+id+" "+kind,dimensions)
	expect("original rigid feet remain planted "+id+" "+kind,feet)
	expect("twenty repeated effective-progress poses stay within explicit metric bounds "+id+" "+kind,deterministic,{"maximum_tip_drift_m":maximum_tip_drift,"maximum_joint_angle_degrees":maximum_joint_angle,"tip_tolerance_m":.0001,"joint_tolerance_degrees":.1})
	expect("authored shoulder and wrist corrections remain bounded "+id+" "+kind,bounds)
	if kind in ["shovel","pickaxe"]:
		var saved:Transform3D=prop.transform
		var tip:Vector3=Vector3(prop.get_meta("contact_point"))
		var first_tip:Vector3=prop.global_transform*tip
		var first_grip:Vector3=prop.global_position
		var axis:Vector3=(prop.basis*tip).normalized()
		var cutting:Vector3=(prop.basis*Vector3(prop.get_meta("contact_normal"))).normalized()
		var desired:Vector3=Basis(axis,deg_to_rad(22.5))*cutting
		WorkPose._roll_cutting_face(prop,tip,desired,saved.basis)
		expect("cutting roll turns true face without shifting tip or palm "+id+" "+kind,(prop.global_transform*tip).distance_to(first_tip)<.00002 and prop.global_position.distance_to(first_grip)<.00002 and prop.position.is_equal_approx(saved.origin) and (prop.basis*Vector3(prop.get_meta("contact_normal"))).normalized().dot(desired)>.9999)
		prop.transform=saved
		WorkPose._roll_cutting_face(prop,tip,Basis(axis,deg_to_rad(100))*cutting,saved.basis)
		expect("cutting roll cannot exceed original wrist allowance "+id+" "+kind,rad_to_deg(saved.basis.get_rotation_quaternion().angle_to(prop.basis.get_rotation_quaternion()))<=35.001 and (prop.global_transform*tip).distance_to(first_tip)<.00002)
		prop.transform=saved
	var old_key:String=view._work_pose_keys[id]
	work.contact.position[0]=float(work.contact.position[0])+.05
	view._sync_work_pose(id,"Use",work,false)
	expect("same-progress changed real contact invalidates derived pose "+id+" "+kind,view._work_pose_keys[id]!=old_key and Vector3(work.contact_result.surface_world).is_equal_approx(Vector3(work.contact.position[0],work.contact.position[1],work.contact.position[2])))
	old_key=view._work_pose_keys[id];view.roots[id].rotation.y=.1
	view._sync_work_pose(id,"Use",work,false)
	expect("changed body-facing transform invalidates derived pose "+id+" "+kind,view._work_pose_keys[id]!=old_key)
	view.roots[id].transform=body;view._sync_work_pose(id,"Use",work,false)
	var torso_pose:Transform3D=torso.transform;var arm_pose:Transform3D=arm.transform;var prop_pose:Transform3D=prop.transform
	view._sync_work_pose(id,"Use",work,true)
	expect("pause retains whole working pose "+id+" "+kind,torso.transform.is_equal_approx(torso_pose) and arm.transform.is_equal_approx(arm_pose) and prop.transform.is_equal_approx(prop_pose))
	view._sync_work_pose(id,"Idle",{"available":false,"active":false},false)
	expect("interruption restores original torso and legs "+id+" "+kind,not view._work_postures.has(id) and not view._work_pose_keys.has(id) and not view._work_pose_results.has(id) and torso.transform.is_equal_approx(Transform3D.IDENTITY) and torso.get_node("leg_l").transform.is_equal_approx(original_legs[0]) and torso.get_node("leg_r").transform.is_equal_approx(original_legs[1]))
