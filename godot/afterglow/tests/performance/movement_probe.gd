extends SceneTree
const Probe=preload("res://scripts/presentation/movement_frame_probe.gd")
var checks:=0
func check(value:bool)->void:
	checks+=1
	if not value:push_error("Movement observation failed: "+str(checks));quit(1)
func _initialize()->void:
	var probe:=Probe.new();var actor:Dictionary={"x":0.0,"y":0.0,"z":0.0}
	probe.observe(actor,0,10,false);actor.x=.1;probe.observe(actor,10000,10,false)
	check(probe.frames.is_empty() and probe.distance_m==0)
	actor.x=.2;probe.observe(actor,20000,10,true)
	check(probe.frames==[10.0] and is_equal_approx(probe.distance_m,.1))
	probe.observe(actor,30000,10,true);check(probe.frames.size()==2)
	probe.observe(actor,200000,170,true);check(probe.frames.size()==2)
	actor.x=.3;probe.observe(actor,500000,300,true)
	check(probe.frames[-1]==300.0) # movement stall is never capped/censored
	probe.break_continuity();actor.x=2;probe.observe(actor,600000,100,true)
	check(probe.frames.size()==3 and is_equal_approx(probe.distance_m,.2))
	actor.x=20;probe.observe(actor,700000,100,true)
	check(probe.discontinuities==1 and probe.frames.size()==3)
	actor.x=NAN;probe.observe(actor,710000,10,true)
	actor.x=0;probe.observe(actor,720000,10,true);check(probe.frames.size()==3)
	check(actor.x==0) # input dictionary is not mutated
	print("MOVEMENT_PROBE "+str(checks)+" checks passed");quit(0)
