extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	for seed:int in [713,17,48]:
		var profiles:Dictionary=Assembly.generation_profiles(16)
		var prepared:Dictionary=Assembly.prepare(Assembly.generate(seed,profiles.profiles,16))
		check("new16 normal generation retains original safety seed "+str(seed),prepared.get("ok",false),prepared.get("reason"))
		if not prepared.get("ok",false):continue
		var modules:Array=prepared.capture.world.extensions["r34:modules"].instances
		for id:String in ["village-resident","repair-resident"]:
			var feet:Dictionary=prepared.layout.spawn_points[id]
			var body:=AABB(G.point(feet)-Vector3(.26,0,.26),Vector3(.52,1.8,.52))
			var clear:bool=true
			for module:Dictionary in modules:
				if module.get("restoration") is Dictionary and not module.restoration.get("completed",false):
					if body.intersects(Shape.transform_box(module,G.aabb(Catalog.definition_view(module.definition_id).footprint))):clear=false
			check("same-village original standing companion clears every pending site "+str(seed)+" "+id,clear and feet.regionId=="RH-HOME" and G.point(feet).distance_to(G.point(prepared.layout.home))<=prepared.layout.home_radius,feet)
	var old_profiles:Dictionary=Assembly.generation_profiles(15)
	var old:Dictionary=Assembly.prepare(Assembly.generate(713,old_profiles.profiles,15))
	check("old15 original finite opening still prepares",old.get("ok",false),old.get("reason"))
	if old.get("ok",false):
		var player:Dictionary=old.layout.spawn_points.player;var repair:Dictionary=old.layout.spawn_points["repair-resident"]
		check("old15 original minus-two companion spawn is not migrated",is_equal_approx(float(repair.x),float(player.x)-2) and is_equal_approx(float(repair.z),float(player.z)),repair)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"opening-spawn16","checks":checks,"failed":failed,"scope":"Three new16 seeds through original full Assembly.prepare safety; both NPC human bodies clear all pending construction footprints on original standing candidates within home village. Old15 minus-two spawn unchanged. No runtime actor relocation or collision override; headless, not UI/FPS."},"\t",true,true))
	print(JSON.stringify({"suite":"opening-spawn16","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
