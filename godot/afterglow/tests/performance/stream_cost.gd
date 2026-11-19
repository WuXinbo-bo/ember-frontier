extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[0]))
	if not decoded.ok:push_error(str(decoded));quit(1);return
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	if not built.ok:push_error(str(built));quit(1);return
	var rt:RefCounted=built.runtime;var s:=Scheduler.new();s.attach(rt,built.services.buildings,1,built.services.modules)
	var target:=Vector2i(1,0)
	var requested:Dictionary=s.request(target)
	var times:Array=[];var result:Dictionary={}
	for i:int in 10000:
		var t:=Time.get_ticks_usec();var completed:Dictionary=s.poll(0);var us:=Time.get_ticks_usec()-t
		times.append(us)
		if not completed.is_empty():result=completed;break
		await process_frame
	var report:Dictionary={"request":requested,"result":result,"status":s.status(),"poll_max_usec":times.max(),"authority":rt.authority_costs()}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	s.shutdown();rt.retire();print("STREAM_COST "+args[1]);quit(0 if result.get("ok",false) else 1)
