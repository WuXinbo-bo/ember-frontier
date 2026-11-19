extends "res://tests/gameplay/factory_quality_normal.gd"
## A runs fresh once in the final exact candidate. Never called in this preflight.
var joint_stage:int=0
func finish()->void:
	if branch=="parse" or checks.any(func(c:Dictionary)->bool:return not c.ok):return super.finish()
	if joint_stage==0:
		joint_stage=1;save(live,"joint-restored-original-output")
		return normal_relocate()
	if joint_stage==1:
		joint_stage=2;save(live,"joint-new-family-paid-output")
		return normal_cooperate()
	super.finish()
