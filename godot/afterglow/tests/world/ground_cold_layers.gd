extends SceneTree
const Profile=preload("res://tests/world/fixtures/ground_layer_profile.gd")
const Live=preload("res://scripts/environment/environment_view.gd")
const Mats=preload("res://tests/world/fixtures/ground_material_profile.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func signature(view:Node3D,key:String)->Array:
	var rows:Array=[]
	for collection:Dictionary in [view._ground,view._contacts,view._fields]:
		if not collection.has(key):rows.append([]);continue
		var item:MeshInstance3D=collection[key];var surfaces:Array=[]
		for i in item.mesh.get_surface_count():surfaces.append(item.mesh.surface_get_arrays(i))
		rows.append([surfaces,item.get_meta("foundation_ids",[]),item.get_meta("actual_support_cells",[]),item.get_meta("shoulder_materials",[])])
	return rows
func run()->void:
	var args:=OS.get_cmdline_user_args();var rows:Array=[]
	for path:String in args.slice(1):
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path));var native:=Native.new()
		var built:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
		check("actual fixed native input assembles "+path.get_file(),built.ok,built.get("reason"))
		if not built.ok:continue
		var world:RefCounted=built.world;var facts:Dictionary=built.runtime.facts();var before:Dictionary=world.snapshot()
		var mats:=Mats.new();mats.set_world_style(str(world.identity().generatorVersion))
		var view:=Profile.new();root.add_child(view);view.configure({"world":world,"materials":mats})
		view.profile_rows.clear();mats.loads.clear()
		var key:="13,0,0" if world.chunk_keys().has("13,0,0") else "2,0,4"
		var cold_started:=Time.get_ticks_usec();view.rebuild_ground(key);var cold_usec:int=Time.get_ticks_usec()-cold_started
		var cold_row:Dictionary=view.profile_rows[-1].duplicate(true);var cold_loads:Array=mats.loads.duplicate(true)
		var warm_started:=Time.get_ticks_usec();view.rebuild_ground(key);var warm_usec:int=Time.get_ticks_usec()-warm_started
		var warm_row:Dictionary=view.profile_rows[-1].duplicate(true)
		view.profile_rows.clear();mats.loads.clear()
		var live:=Live.new();root.add_child(live);live.configure({"world":world,"materials":mats});var exact:=true
		for id:String in world.chunk_keys():
			view.rebuild_ground(id);live.rebuild_ground(id);exact=exact and signature(view,id)==signature(live,id)
		check("all actual resident ground arrays and support metadata unchanged "+path.get_file(),exact)
		check("profiling never mutates cells facts plan or residency "+path.get_file(),Data.json_equal(before,world.snapshot()) and Data.json_equal(facts,built.runtime.facts()))
		rows.append({"input":path,"first_key":key,"cold_total_usec":cold_usec,"cold_layers":cold_row,"cold_materials":cold_loads,"warm_total_usec":warm_usec,"warm_layers":warm_row,"all_chunk_layers":view.profile_rows.duplicate(true),"remaining_materials":mats.loads.duplicate(true)})
		view.free();live.free();await process_frame
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"rows":rows,"scope":"Existing captured real cells and production Native assembly; timing-only environment snapshot checked exact. Headless no quiet window, not Metal/FPS/hard-budget qualification."}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
