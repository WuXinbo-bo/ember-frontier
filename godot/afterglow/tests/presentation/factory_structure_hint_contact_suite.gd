extends "res://tests/presentation/actor_motion_suite.gd"
## Same actual finite structure owner; route the unchanged body to its true hint.
func prepare_structure_position(bench:Dictionary)->bool:
	var hints:Array=actions.work_points({"kind":"structure","target_id":bench.id,"payload":{"kind":"place","instance":bench}})
	var from:Vector3=Geometry.point(runtime.actor("player"))
	hints.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a).distance_squared_to(from)<Geometry.point(b).distance_squared_to(from))
	expect("actual structure owner exposes real use hints",not hints.is_empty(),hints)
	if hints.is_empty():return false
	var moved:Dictionary=command("walk","",{},hints[0])
	expect("same body accepts real structure hint route",moved.ok,moved)
	if not moved.ok:return false
	for i:int in 30:runtime.tick(0.1)
	var at:Dictionary=runtime.actor("player")
	var reached:bool=Geometry.point(at).distance_to(Geometry.point(hints[0]))<0.02
	expect("actual body reaches owner hint before hammer labor",reached,{"hint":hints[0],"actual":Geometry.location(at)})
	return reached
