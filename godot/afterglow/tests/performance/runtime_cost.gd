extends SceneTree
## Reproducible actual-authority cost probe; no renderer/FPS claims.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var rt:RefCounted
var services:Dictionary
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func measure(label:String,fn:Callable,n:int=4)->void:
	for i:int in n:
		var t:=Time.get_ticks_usec();var result:Variant=fn.call();var us:=Time.get_ticks_usec()-t
		rows.append({"name":label,"sample":i,"usec":us,"count":result.size() if result is Array or result is Dictionary else -1})
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[0]))
	if not decoded.get("ok",false):push_error(str(decoded));quit(1);return
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	if not built.get("ok",false):push_error(str(built));quit(1);return
	rt=built.runtime;services=built.services
	var zone_spec:Dictionary={"kind":"forestry","region_id":"RH-VILLAGE","bounds":{"x0":20,"z0":-96,"x1":39,"z1":-86},"policy":{"replant":true,"mature_only":true,"tree_id":"broadleaf"}}
	var receipt:Dictionary=rt.command({"kind":"zone.create","actor_id":"player","target_id":"PERF:forestry","command_id":"PERF:create","payload":{"spec":zone_spec}})
	if not receipt.get("ok",false):push_error(str(receipt));quit(1);return
	var before:Dictionary=rt.capture_checkpoint()
	measure("snapshot",func():return rt.snapshot())
	if rt.has_method("hud_snapshot"):measure("hud",func():return rt.hud_snapshot())
	measure("ecology_visual",func():return services.ecology.presentation_projection(),2)
	measure("factory_ui",func():return rt.factory_ui_snapshot())
	if rt.has_method("factory_hud_snapshot"):measure("factory_hud",func():return rt.factory_hud_snapshot())
	measure("factory_full",func():return rt.factory_snapshot(),2)
	measure("workforce_full",func():return services.workforce.projection("player"),2)
	measure("housing",func():return rt.housing_projection(),2)
	measure("zone_candidates",func():return services.zonework.work_candidates("player"),2)
	var unchanged:bool=before==rt.capture_checkpoint()
	for i:int in 30:
		var t:=Time.get_ticks_usec();rt.tick(.1);rows.append({"name":"step","sample":i,"usec":Time.get_ticks_usec()-t})
	var out:Dictionary={"rows":rows,"reads_authority_unchanged":unchanged,"valid_cells":rt.zone_records()[0].cells.size(),"simulation":rt.simulation_budget(),"candidate_costs":services.zonework.candidate_costs(),"simulation_costs":rt.simulation_costs(),"authority_costs":rt.authority_costs() if rt.has_method("authority_costs") else {}}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(out,"\t"))
	rt.retire();print("PERF_COST "+args[1]);quit(0 if unchanged else 1)
