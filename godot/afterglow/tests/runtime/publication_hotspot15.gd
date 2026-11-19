extends SceneTree
## One saved real content15 world, one real adjacent generation and storage CAS.
## No UI/mesh callbacks: attributes authority CPU, not rendered performance.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
var checks:Array=[]
var rows:Array=[]
var callback_costs:Dictionary={}
var callback_probes:Array=[]
class CallbackProbe extends RefCounted:
	var original:Callable
	var owner:SceneTree
	var label:String
	func invoke(change:Dictionary)->void:owner.measured_callback(change,original,label)
class StagedNative extends Native:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
func measured_callback(change:Dictionary,original:Callable,label:String)->void:
	var started:int=Time.get_ticks_usec()
	original.call(change)
	var elapsed:int=Time.get_ticks_usec()-started
	var row:Dictionary=callback_costs.get(label,{"count":0,"total_usec":0,"max_usec":0})
	row.count+=1;row.total_usec+=elapsed;row.max_usec=maxi(int(row.max_usec),elapsed);callback_costs[label]=row
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func difference(before:Dictionary,after:Dictionary)->Dictionary:
	var phases:Dictionary={}
	for name:String in after.get("phases",{}):
		var a:Dictionary=after.phases[name];var b:Dictionary=before.get("phases",{}).get(name,{})
		phases[name]={"count":int(a.get("count",0))-int(b.get("count",0)),"total_usec":int(a.get("total_usec",0))-int(b.get("total_usec",0)),"max_usec":a.max_usec}
	return {"count":int(after.count)-int(before.count),"total_usec":int(after.total_usec)-int(before.total_usec),"phases":phases}
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var out:String=args[0];var source:String=args[1]
	DirAccess.make_dir_recursive_absolute(out)
	var loaded:Dictionary=Store.new(source).load_current()
	check("exact saved content15 source decodes",loaded.ok)
	if not loaded.ok:return finish(out)
	var host:=StagedNative.new();root.add_child(host);var built:Dictionary=host._assemble(loaded.capture)
	check("original Native full authority assembles",built.ok)
	if not built.ok:return finish(out)
	var runtime:RefCounted=built.runtime;runtime.set_paused(true)
	var candidate:Dictionary={}
	if args.size()>2 and args[2]=="--callbacks":
		candidate=host._stage_scene(built);check("real Native candidate views attach",candidate.ok)
		if args.has("--budgeted-candidate"):candidate.terrain.set_streaming_updates(true)
		var index:int=0
		var all_connected:bool=true
		for connection:Dictionary in runtime.changed.get_connections():
			var original:Callable=connection.callable;var object:Object=original.get_object()
			var script:Script=object.get_script() if object!=null else null
			var label:String=str(index)+":"+(script.resource_path if script!=null else str(object))+":"+str(original.get_method())
			var probe:=CallbackProbe.new();probe.original=original;probe.owner=self;probe.label=label;callback_probes.append(probe)
			runtime.changed.disconnect(original)
			all_connected=runtime.changed.connect(probe.invoke,connection.flags)==OK and all_connected
			index+=1
		check("all original callbacks retain distinct receivers and order",all_connected and runtime.changed.get_connections().size()==index)
	var scheduler:=Scheduler.new();scheduler.attach(runtime,built.services.buildings,1,built.services.modules)
	var original_actors:Array=runtime.actor_states();var before:Dictionary=runtime.authority_costs()
	var requested:Dictionary=scheduler.request(Vector2i(2,0));check("real adjacent generation request accepted",requested.ok)
	var completed:Dictionary={};var deadline:int=Time.get_ticks_msec()+60000
	while completed.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;completed=scheduler.poll(0,true)
	check("one real region atomically publishes",completed.get("ok",false) and not runtime.world.region("R34:2:0").is_empty())
	rows.append({"kind":"region_generation","receipt":{"ok":completed.get("ok",false),"code":completed.get("code"),"region_id":completed.get("region_id")},"scheduler":scheduler.status(),"authority":difference(before,runtime.authority_costs()),"callbacks":callback_costs.duplicate(true)})
	callback_costs.clear()
	var region:String="R34:2:0"
	if completed.get("ok",false):
		var captured:Dictionary=runtime.world.capture_region_residency(region,false,runtime.world.get_revision(),64)
		var converted:Dictionary=Native.World.prepare_detached_region_residency(captured.input) if captured.ok else captured
		check("real64 chunk storage conversion prepares",converted.ok)
		if converted.ok:
			before=runtime.authority_costs()
			var stored:Dictionary=runtime.commit_storage_projection({"world_changes":converted.world_changes,"events":[{"kind":"region-storage-changed","region_id":region,"resident":false}]})
			rows.append({"kind":"storage_cold64","receipt":stored.get("code"),"authority":difference(before,runtime.authority_costs()),"callbacks":callback_costs.duplicate(true)})
			check("real storage CAS commits",stored.ok)
	check("generation and storage retain every original actor",runtime.actor_states()==original_actors)
	if not candidate.is_empty() and args.has("--budgeted-candidate"):
		host._world_epoch=1;candidate.world_epoch=1
		var prime:Dictionary=await host._prime_candidate_camera(candidate)
		check("original production camera frontier and cold-page prime succeeds",prime.ok)
		var ready:Dictionary=host._candidate_readiness(candidate)
		check("cold or unfinished terrain never receives a ready permit",not ready.get("ready",false) or (ready.get("cold",[]).is_empty() and ready.get("pending",[]).is_empty()))
		var deadline_ready:int=Time.get_ticks_msec()+60000
		var next_check:int=0
		while not ready.get("ready",false) and not ready.get("fatal",false) and Time.get_ticks_msec()<deadline_ready:
			candidate.terrain.prioritize(ready.get("required_keys",[]))
			await process_frame
			if Time.get_ticks_msec()>=next_check:
				ready=host._candidate_readiness(candidate);next_check=Time.get_ticks_msec()+50
		check("unchanged real camera body tool and later-physics gate succeeds",ready.get("ready",false) and ready.get("geometry_ready",false) and ready.get("physics_ready",false))
		rows.append({"kind":"candidate_actual_readiness","result":ready,"terrain":candidate.terrain.statistics()})
	scheduler.shutdown();runtime.retire();host.queue_free();await process_frame;finish(out)
func finish(out:String)->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"Actual saved content15 Native authority, one adjacent region, one64 chunk storage commit, complete validators. Optional real Native staged subscribers measured in original signal order; no GPU or FPS acceptance."},"\t",true,true))
	print(JSON.stringify({"suite":"publication-hotspot15","checks":checks.size(),"failed":failed,"timed_rows":rows.filter(func(row:Dictionary)->bool:return row.has("authority"))}));quit(1 if failed else 0)
