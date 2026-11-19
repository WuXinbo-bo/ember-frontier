extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Current=preload("res://scripts/buildings/building_space.gd")
const Original=preload("res://tests/buildings/saved_route_reference/building_space.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	var input:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var source:Dictionary=evidence.rows[0].profile.actions.route.slow[0]
	var native:=Native.new();var built:Dictionary=native._assemble(input.capture);native.free()
	if not built.get("ok",false):print(JSON.stringify({"checks":[{"name":"Native actual input","ok":false}]}));quit(1);return
	var rt:RefCounted=built.runtime;var b:RefCounted=rt._services.buildings;var before:Dictionary=rt.capture_checkpoint();var rows:Array=[]
	for mode:String in ["original","current","current","original"]:
		var q:RefCounted=Original.new() if mode=="original" else Current.new()
		q.configure(built.world,b.structures(),b.geometry,b.permission)
		var t:int=Time.get_ticks_usec();var route:Dictionary=q.route(source.actor_id,source.from,source.to);var cold:int=Time.get_ticks_usec()-t
		t=Time.get_ticks_usec();var hot:Dictionary=q.route(source.actor_id,source.from,source.to);var warm:int=Time.get_ticks_usec()-t
		checks.append({"name":mode+" cold/hot entire exact route "+str(rows.size()),"ok":Data.json_equal(route,source.result) and Data.json_equal(hot,source.result)})
		rows.append({"mode":mode,"cold_us":cold,"hot_us":warm,"route":route})
	checks.append({"name":"all authority unchanged","ok":Data.json_equal(before,rt.capture_checkpoint())})
	FileAccess.open(output+"/detail.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows},"\t",true,true))
	print(JSON.stringify({"checks":checks,"rows":rows.map(func(r:Dictionary)->Dictionary:return {"mode":r.mode,"cold_us":r.cold_us,"hot_us":r.hot_us})}));rt.retire();quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
