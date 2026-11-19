extends RefCounted
## Original rigid body only. Solve a small forward hip hinge, never foot motion.
## Owner gives the real lever contact; this helper cannot change work reach.
static func apply(arm:Node3D,point:Vector3,max_degrees:float=35.0)->Dictionary:
	var torso:Node3D=arm.get_parent();var joints:Array=[];var legs:Array=[]
	for name:String in ["arm_l","arm_r","head","leg_l","leg_r"]:
		var joint:Node3D=torso.get_node_or_null(name)
		if joint==null:continue
		var row:Dictionary={"node":joint,"local":joint.transform,"world":joint.global_transform}
		joints.append(row)
		if name.begins_with("leg_"):legs.append(row)
	if legs.size()!=2:return {}
	var pose:Dictionary={"torso":torso,"base":torso.transform,"joints":joints,"legs":legs,"arm_basis":arm.basis}
	var hip:=Vector3(0,float(legs[0].local.origin.y+legs[1].local.origin.y)*.5,0)
	var palm:=Vector3(0,-.51,.06);var length:float=(arm.basis*palm).length()
	var best:Transform3D=torso.transform;var error:float=INF;var best_angle:float=0
	for step:int in 65:
		var angle:float=deg_to_rad(clampf(max_degrees,0,75))*float(step)/64.0;var rotation:=Basis(Vector3.RIGHT,angle)
		var candidate:Transform3D=pose.base*Transform3D(rotation,hip-rotation*hip)
		var shoulder:Vector3=torso.get_parent().global_transform*(candidate*arm.position)
		var delta:float=absf(shoulder.distance_to(point)-length)
		if delta<error:error=delta;best=candidate;best_angle=angle
	torso.transform=best
	for row:Dictionary in legs:row.node.global_transform=row.world
	var head:Node3D=torso.get_node_or_null("head")
	if head!=null:head.basis=Basis(Vector3.RIGHT,-best_angle*.5)*head.basis
	pose.water_posture={"kind":"original_rigid_hip_hinge","degrees":rad_to_deg(best_angle),"radial_error_m":error,"feet_preserved":true,"scope":"visual pose only; original body/limbs, no reach permission"}
	return pose
