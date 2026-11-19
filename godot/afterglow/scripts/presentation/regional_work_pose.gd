extends RefCounted
## Actual owner operation/progress only; original joints and fixed feet.
const Hinge=preload("res://scripts/presentation/factory_water_work_pose.gd")
const Work=preload("res://scripts/presentation/factory_work_pose.gd")
const OPERATIONS=["sow","water","compost","harvest_crop","collect_seed","nursery","draw_raw_water","cook"]
static func apply(arm:Node3D,work:Dictionary,length:float)->Dictionary:
	var operation:String=str(work.get("operation",""))
	if operation not in OPERATIONS or length<=0:return {}
	var contact:Variant=work.get("contact")
	if not contact is Dictionary or not contact.get("position") is Array or contact.position.size()!=3:return {}
	for v:Variant in contact.position:
		if not (v is int or v is float) or not is_finite(float(v)):return {}
	var point:=Vector3(contact.position[0],contact.position[1],contact.position[2])
	var phase:float=fposmod(float(work.progress_seconds),length)/length
	var ground_work:bool=operation in ["sow","water","compost","harvest_crop","nursery"]
	var pose:Dictionary=Hinge.apply(arm,point,75.0 if ground_work else 35.0)
	if pose.is_empty():return {}
	var reference:Basis=arm.basis
	var palm:=Vector3(0,-.51,.06)
	# Work is not continuous contact: hands lift between sow/pick strokes. Cook
	# traces a small stirring arc on the exact surface supplied by production.
	var goal:Vector3=point
	if operation=="cook":goal+=Vector3(cos(phase*TAU)*.045,0,sin(phase*TAU)*.045)
	elif ground_work:goal.y+=.08*(.5+.5*cos(phase*TAU))
	Work.rotate_joint(arm,arm.to_global(palm),goal,reference,110.0)
	work.posture={"kind":"regional_original_rigid_joints","operation":operation,"phase":phase,"hip":pose.water_posture,"scope":"no body movement, reach permission, crop or water settlement"}
	work.hand_contact={"palm_world":arm.to_global(palm),"surface_world":point,"gap_meters":arm.to_global(palm).distance_to(point),"goal_gap_meters":arm.to_global(palm).distance_to(goal),"shoulder_limit_degrees":110.0,"scope":"geometric diagnostic, not authority contact acceptance"}
	return pose
