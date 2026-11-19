extends RefCounted
## Instance-only rigid poses over the delivered rig. No movement or work facts.
const Tool=preload("res://scripts/presentation/held_tool_view.gd")
const KINDS=["salvaged_axe","shovel","pickaxe"]

static func apply(arm:Node3D,prop:Node3D,work:Dictionary,length:float,foot_y:float)->Dictionary:
	var kind:String=str(prop.get_meta("tool_kind",""))
	if kind not in KINDS:return {}
	var contact:Variant=work.get("contact")
	if not contact is Dictionary or not contact.get("position") is Array or contact.position.size()!=3:return {}
	if not contact.get("normal") is Array or contact.normal.size()!=3:return {}
	for value:Variant in contact.position+contact.normal:
		if not (value is float or value is int) or not is_finite(float(value)):return {}
	var point:=Vector3(contact.position[0],contact.position[1],contact.position[2])
	if not point.is_finite() or Vector3(contact.normal[0],contact.normal[1],contact.normal[2]).length_squared()<.000001:return {}
	var torso:Node3D=arm.get_parent();var joints:Array=[];var legs:Array=[]
	for name:String in ["arm_l","arm_r","head","leg_l","leg_r"]:
		var joint:Node3D=torso.get_node_or_null(name)
		if joint==null:continue
		var row:Dictionary={"node":joint,"local":joint.transform,"world":joint.global_transform}
		joints.append(row)
		if name.begins_with("leg_"):legs.append(row)
	if kind!="salvaged_axe" and legs.size()!=2:return {}
	var pose:Dictionary={"torso":torso,"base":torso.transform,"joints":joints,"legs":legs,"arm_basis":arm.basis}
	# The generic Use clip raises this rigid arm above a close trunk/low spade
	# surface. Author a smaller shoulder swing; retain its phase and all lengths.
	var amplitude:float=.45 if kind=="salvaged_axe" else .65 if kind=="shovel" else 1.0
	arm.quaternion=Quaternion.IDENTITY.slerp(arm.quaternion,amplitude)
	var bend:float=0.0
	if kind in ["shovel","pickaxe"]:
		var phase:float=fposmod(float(work.progress_seconds),length)/length
		bend=deg_to_rad(clampf((1.0-(point.y-foot_y))*100.0,0,100))*(.875-.125*cos(phase*TAU))
		# Hinge the original torso at the delivered hip height. Both original
		# rigid legs stay planted in their unmodified world transforms; no fake
		# knee, body translation, mesh scaling or shoulder-pivot offset is added.
		var hip:=Vector3(0,float(legs[0].local.origin.y+legs[1].local.origin.y)*.5,0)
		var rotation:=Basis(Vector3.RIGHT,bend)
		torso.transform=pose.base*Transform3D(rotation,hip-rotation*hip)
		for row:Dictionary in legs:row.node.global_transform=row.world
		var head:Node3D=torso.get_node_or_null("head")
		if head!=null:head.basis=Basis(Vector3.RIGHT,-bend*.5)*head.basis
		var free_arm:Node3D=torso.get_node_or_null("arm_l")
		if free_arm!=null:free_arm.basis=Basis(Vector3.RIGHT,-bend)*free_arm.basis
	work.posture={"kind":"rigid_hip_hinge" if kind!="salvaged_axe" else "close_trunk_swing","hip_bend_degrees":rad_to_deg(bend),"shoulder_clip_amplitude":amplitude,"scope":"derived original joints; feet/body/tool dimensions unchanged"}
	return pose

static func restore(pose:Dictionary)->void:
	if not is_instance_valid(pose.get("torso")):return
	pose.torso.transform=pose.base
	for row:Dictionary in pose.joints:
		if is_instance_valid(row.node):row.node.transform=row.local

static func rotate_joint(node:Node3D,tip:Vector3,goal:Vector3,reference:Basis,limit_degrees:float)->void:
	var inverse:Transform3D=node.get_parent().global_transform.affine_inverse()
	_rotate_local(node,inverse*tip,inverse*goal,reference,limit_degrees)

static func _rotate_local(node:Node3D,tip:Vector3,goal:Vector3,reference:Basis,limit_degrees:float)->void:
	var from_pivot:Vector3=tip-node.position
	var to_goal:Vector3=goal-node.position
	if from_pivot.length_squared()<0.000001 or to_goal.length_squared()<0.000001:return
	var candidate:Basis=Basis(Quaternion(from_pivot.normalized(),to_goal.normalized()))*node.basis
	var origin:Quaternion=reference.get_rotation_quaternion()
	var rotation:Quaternion=candidate.get_rotation_quaternion()
	var angle:float=origin.angle_to(rotation)
	if angle>deg_to_rad(limit_degrees):rotation=origin.slerp(rotation,deg_to_rad(limit_degrees)/angle)
	node.basis=Basis(rotation).scaled(reference.get_scale())

static func solve(arm:Node3D,prop:Node3D,point:Vector3,normal:Vector3,goal:Vector3,arm_reference:Basis,tool_reference:Basis)->void:
	var best_arm:Basis=arm.basis;var best_tool:Basis=prop.basis
	var best_error:float=INF
	# Solve in the original rig frame. Repeated world->joint round trips at
	# distant coordinates lose precision and can flip a constrained candidate.
	var inverse:Transform3D=arm.get_parent().global_transform.affine_inverse()
	var goal_local:Vector3=inverse*goal;var point_local:Vector3=inverse*point
	var normal_local:Vector3=(inverse.basis*normal).normalized()
	var tip:Vector3=prop.get_meta("contact_point")
	# Keep the best actual geometry, including intermediate wrist/shoulder
	# states. The last constrained CCD step can be worse or inside the surface.
	for step:int in 7:
		for joint:int in 2:
			var actual:Vector3=arm.transform*(prop.transform*tip)
			var signed_gap:float=(actual-point_local).dot(normal_local)
			var error:float=actual.distance_squared_to(goal_local)+pow(maxf(0,-signed_gap-.001),2)*100.0
			if error<best_error:
				best_error=error;best_arm=arm.basis;best_tool=prop.basis
			if joint==0:_rotate_local(prop,prop.transform*tip,arm.transform.affine_inverse()*goal_local,tool_reference,35.0)
			else:_rotate_local(arm,actual,goal_local,arm_reference,65.0)
	arm.basis=best_arm;prop.basis=best_tool
	if prop.get_meta("tool_kind","") not in ["shovel","pickaxe"]:return
	# Rolling about the palm-to-tip line turns the cutting face without moving
	# either endpoint. Use the remaining original wrist bound before the arm.
	_roll_cutting_face(prop,tip,arm.basis.inverse()*(-normal_local),tool_reference)
	# A roll about the actual shoulder-to-tip line preserves the contact point
	# while turning the cutting face toward the ground, within the same bound.
	var axis:Vector3=(arm.transform*(prop.transform*tip)-arm.position).normalized()
	var cutting_normal:Vector3=(arm.basis*prop.basis*Vector3(prop.get_meta("contact_normal"))).normalized()
	var from_normal:Vector3=cutting_normal-axis*cutting_normal.dot(axis)
	var to_normal:Vector3=-normal_local-axis*(-normal_local).dot(axis)
	if from_normal.length_squared()<.000001 or to_normal.length_squared()<.000001:return
	var roll:float=from_normal.signed_angle_to(to_normal,axis)
	var saved:Basis=arm.basis
	var lo:float=0;var hi:float=1
	for probe:int in 9:
		var fraction:float=(lo+hi)*.5
		var proposed:Basis=Basis(axis,roll*fraction)*saved
		if arm_reference.get_rotation_quaternion().angle_to(proposed.get_rotation_quaternion())<=deg_to_rad(65):lo=fraction
		else:hi=fraction
	arm.basis=Basis(axis,roll*lo)*saved

static func _roll_cutting_face(prop:Node3D,tip:Vector3,normal:Vector3,reference:Basis)->void:
	var axis:Vector3=prop.basis*tip
	if axis.length_squared()<.000001:return
	axis=axis.normalized()
	var cutting:Vector3=(prop.basis*Vector3(prop.get_meta("contact_normal"))).normalized()
	var from_normal:Vector3=cutting-axis*cutting.dot(axis)
	var to_normal:Vector3=normal-axis*normal.dot(axis)
	if from_normal.length_squared()<.000001 or to_normal.length_squared()<.000001:return
	var roll:float=from_normal.signed_angle_to(to_normal,axis)
	var saved:Basis=prop.basis;var best:Basis=saved;var best_dot:float=cutting.dot(normal)
	# Fixed bounded probes include the unchanged pose. Never spend an extra
	# wrist allowance on top of the reference used by the contact solver.
	for probe:int in 33:
		var proposed:Basis=Basis(axis,roll*float(probe)/32.0)*saved
		if reference.get_rotation_quaternion().angle_to(proposed.get_rotation_quaternion())>deg_to_rad(35):continue
		var score:float=(proposed*Vector3(prop.get_meta("contact_normal"))).normalized().dot(normal)
		if score>best_dot:best=proposed;best_dot=score
	prop.basis=best
