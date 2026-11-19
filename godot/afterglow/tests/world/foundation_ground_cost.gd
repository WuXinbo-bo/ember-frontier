extends SceneTree
const Before=preload("res://tests/world/fixtures/foundation_ground_before.gd")
const After=preload("res://scripts/environment/environment_view.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Materials=preload("res://scripts/environment/environment_materials.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func signature(view:Node3D,key:String)->Array:
	var rows:Array=[]
	for collection:Dictionary in [view._ground,view._contacts,view._fields]:
		if not collection.has(key):rows.append([]);continue
		var node:MeshInstance3D=collection[key];var surfaces:Array=[]
		for i in node.mesh.get_surface_count():surfaces.append(node.mesh.surface_get_arrays(i))
		rows.append(surfaces)
	return rows
func run()->void:
	var catalog:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var world:=State.new();check("actual v4 source loaded",world.load_snapshot(Landscape.generate(973339546,catalog)).ok)
	var mats:=Materials.new();var before:=Before.new();var after:=After.new()
	root.add_child(before);root.add_child(after);before.configure({"world":world,"materials":mats});after.configure({"world":world,"materials":mats})
	var exact:=true;var rows:Array=[]
	for key:String in world.chunk_keys():
		var start:=Time.get_ticks_usec();before.rebuild_ground(key);var old_time:int=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();after.rebuild_ground(key);var new_time:int=Time.get_ticks_usec()-start
		exact=exact and signature(before,key)==signature(after,key)
		rows.append({"key":key,"before_usec":old_time,"after_usec":new_time})
	check("all 512 chunk shoulder contact field arrays exact",exact)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.before_usec>b.before_usec)
	var keys:Array=rows.slice(0,16).map(func(r:Dictionary)->String:return r.key)
	var old_samples:Array=[];var new_samples:Array=[]
	for iteration in 6:
		var old_total:=0;var new_total:=0
		for key:String in keys:
			if iteration%2==0:
				var start:=Time.get_ticks_usec();before.rebuild_ground(key);old_total+=Time.get_ticks_usec()-start
				start=Time.get_ticks_usec();after.rebuild_ground(key);new_total+=Time.get_ticks_usec()-start
			else:
				var start:=Time.get_ticks_usec();after.rebuild_ground(key);new_total+=Time.get_ticks_usec()-start
				start=Time.get_ticks_usec();before.rebuild_ground(key);old_total+=Time.get_ticks_usec()-start
		old_samples.append(old_total);new_samples.append(new_total)
		await process_frame
	var old_sorted:=old_samples.duplicate();old_sorted.sort();var new_sorted:=new_samples.duplicate();new_sorted.sort()
	var cost:Dictionary={"slowest_16_keys":keys,"before_usec":old_samples,"after_usec":new_samples,"before_median_usec":(old_sorted[2]+old_sorted[3])*0.5,"after_median_usec":(new_sorted[2]+new_sorted[3])*0.5,"scope":"same input alternating headless CPU ground only, not quiet/Metal/FPS; geometry/quality unchanged"}
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"costs":cost}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	before.free();after.free();print(JSON.stringify(report));quit(1 if failed else 0)
