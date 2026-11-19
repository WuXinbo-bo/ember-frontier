extends SceneTree
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:failures.append(label)
func part(role:String,normal:Vector3)->Dictionary:
	return {"id":"fixture:home:part","regionId":"fixture:r","data":{"module_id":"fixture:home","module_geometry_version":"r34.module.home_small_porch_v1.geometry-v2","module_room":{"version":2,"room_id":"fixture:home:room","bounds":{"min":{"x":-3,"y":0,"z":-2},"max":{"x":3,"y":2.4,"z":2}},"role":role,"normal":{"x":normal.x,"y":normal.y,"z":normal.z}}}}
func _initialize()->void:call_deferred("run")
func run()->void:
	var p:=Policy.new();var actor:Dictionary={"x":0,"y":0,"z":0,"regionId":"fixture:r"}
	var before:String=var_to_str(actor)
	expect("exact new home roof hides when physically inside room",not p.module_part_visible(part("roof",Vector3.UP),actor,0))
	expect("camera-side X wall cuts",not p.module_part_visible(part("wall",Vector3.RIGHT),actor,0))
	expect("camera-side Z trim cuts with its wall",not p.module_part_visible(part("trim",Vector3.BACK),actor,0))
	expect("rear X wall stays visible",p.module_part_visible(part("wall",Vector3.LEFT),actor,0))
	expect("rear Z wall stays visible",p.module_part_visible(part("wall",Vector3.FORWARD),actor,0))
	actor.x=-2.9;actor.z=-1.9
	expect("moving within same room does not peel different wall",not p.module_part_visible(part("wall",Vector3.RIGHT),actor,5) and p.module_part_visible(part("wall",Vector3.LEFT),actor,5))
	actor.x=4
	expect("crossing doorway retains current cut during settle",not p.module_part_visible(part("roof",Vector3.UP),actor,10))
	expect("leaving same fixed room restores roof after settle",p.module_part_visible(part("roof",Vector3.UP),actor,160))
	actor.x=0
	expect("entering doorway initially keeps previous shell",p.module_part_visible(part("roof",Vector3.UP),actor,170))
	var pending:String=p.signature();p._sample_module_rooms(actor,320)
	expect("stationary pending room transition invalidates B view cache",p.signature()!=pending and not p.module_part_visible(part("roof",Vector3.UP),actor,320))
	var old:Dictionary=part("roof",Vector3.UP);old.data.module_geometry_version="r34.module.home_small_porch_v1.geometry-v1"
	expect("old geometry1 cannot be changed by new metadata",p.module_part_visible(old,actor,400))
	old.data.module_geometry_version="r34.module.sawmill_low_v1.geometry-v2"
	expect("industrial geometry is outside home cutaway authorization",p.module_part_visible(old,actor,400))
	for key:String in ["module_geometry_version","module_room"]:
		var missing:Dictionary=part("roof",Vector3.UP);missing.data.erase(key)
		expect("missing exact owner field retains old path "+key,p.module_part_visible(missing,actor,400))
	for invalid:Variant in [null,{}, {"min":{"x":0,"y":0,"z":0},"max":{"x":NAN,"y":1,"z":1}}]:
		var bad:Dictionary=part("roof",Vector3.UP);bad.data.module_room.bounds=invalid
		expect("malformed bounds never cut unrelated structure",p.module_part_visible(bad,actor,400))
	actor.regionId="other"
	expect("other actual region is not an interior cut",p.module_part_visible(part("roof",Vector3.UP),actor,400))
	actor={"x":0,"y":0,"z":0,"regionId":"fixture:r"}
	expect("policy leaves actor and owner descriptors unchanged",var_to_str(actor)==before)
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"scope":"Exact finite B module_room DTO render-veto; no B actual module/hook, actor visibility/LOS/PCK/VA/FPS claim","checks":checks,"failures":failures},"\t"))
	print("DDD_REGIONAL_MODULE_CUTAWAY ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
