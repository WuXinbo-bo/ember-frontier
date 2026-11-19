extends SceneTree
## Real NativeClient checkpoint, C cold pages, B geometry and D consumers.
## Headless source integration only; not package/OS/RSS/performance evidence.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Policy=preload("res://scripts/runtime/region_residency.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Interest=preload("res://scripts/runtime/camera_interest.gd")
class TestClient extends Client:
	func _ready()->void:pass
var output:String
var host:Node3D
var checks:Array=[]
var timings:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800)
	host=TestClient.new();host.store=Store.new(output+"/manual/saves");host.controls_path=output+"/controls.json";root.add_child(host);host.set_process(false)
	var entry:Dictionary=await host.start_profiled_world("normal",713,"residency-opening")
	check("actual normal entry mounts with all real bodies ready",entry.ok,entry.get("reason"))
	if not entry.ok:return finish()
	host.router.set_window_focus(false)
	var pins:Dictionary=Policy.required_regions(host.runtime)
	for actor:Dictionary in host.runtime.facts().actors:
		check("living real identity pins region: "+str(actor.id),pins.has(actor.regionId))
	var rejected:Dictionary=await host._change_residency({"region_id":host.runtime.actor("player").regionId,"resident":false})
	check("cannot release player region or camera dependency",not rejected.ok and rejected.code=="REGION_PINNED")
	var camera_rect:Rect2=Interest.footprint(host.camera,host.world,Client.CAMERA_PREFETCH_METRES).get("rect",Rect2())
	var camera_pins:Dictionary=Policy.required_regions(host.runtime,18.0,camera_rect)
	var coord:=Vector2i.ZERO
	for candidate:Vector2i in [Vector2i(-1,-1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-2,-1)]:
		if not camera_pins.has(Factory.region_id(candidate)):
			coord=candidate;break
	check("peripheral fixture is outside real camera and actor pins",coord!=Vector2i.ZERO,camera_pins)
	if coord==Vector2i.ZERO:return finish()
	var id:String=Factory.region_id(coord)
	var requested:Dictionary=host._regions.request(coord)
	check("real adjacent peripheral region uses sole threaded scheduler",requested.ok,requested)
	var start:int=Time.get_ticks_msec()
	while host.world.region(id).is_empty() and Time.get_ticks_msec()-start<30000:
		host._regions.poll(0.0,true)
		await process_frame
	check("peripheral generation and real module registration commit",not host.world.region(id).is_empty())
	if host.world.region(id).is_empty():return finish()
	check("far empty region is not a fabricated actor or inventory pin",not Policy.required_regions(host.runtime).has(id))
	var region:Dictionary=host.world.region(id)
	var x:int=floori((float(region.bounds.min.x)+2.25)*2);var z:int=floori((float(region.bounds.min.z)+2.25)*2)
	var y:int=roundi(float(host.world.surface_height((x+0.5)*0.5,(z+0.5)*0.5))*2)-1
	var cell:Dictionary={"x":x,"y":y,"z":z};var old:int=host.world.cell_at(x,y,z)
	var edited:Dictionary=host.runtime._commit({"world_changes":[{"op":"voxel.set","cell":cell,"before":old,"after":0}]})
	check("one real source voxel edit passes shared safety before release",edited.ok and old!=0,edited.get("reason"))
	if not edited.ok:return finish()
	var before:Dictionary=host.runtime.capture_checkpoint()
	var manual:Dictionary=await host.save_async("before-release")
	check("explicit manual checkpoint exists before working cache",manual.ok)
	if not manual.ok:return finish()
	var active_bytes:String=FileAccess.get_file_as_string(host.store.root+"/active.json")
	var slot_bytes:String=FileAccess.get_file_as_string(manual.path)
	var cool:Dictionary=await host._change_residency({"region_id":id,"resident":false})
	timings.cold=barrier_timing(cool)
	check("shipping owner persists then commits bounded real cold conversion",cool.ok,cool.get("code"))
	if not cool.ok:return finish()
	var cold:Dictionary=host.world.region_residency_state(id)
	check("real cold region has no unpacked cells and one compressed representation",cold.paged and not cold.resident and cold.unpacked_bytes==0 and cold.page_bytes>0,cold)
	check("internal checkpoint is real but never changes manual active or slot",not str(cool.checkpoint_sha256).is_empty() and FileAccess.file_exists(host._stream_store.root+"/active.json") and active_bytes==FileAccess.get_file_as_string(host.store.root+"/active.json") and slot_bytes==FileAccess.get_file_as_string(manual.path))
	check("streaming introduces no simulation time, actor, stock or production mutation",host.runtime.clock()==float(before.facts.time) and Data.json_equal(before.facts.actors,host.runtime.facts().actors) and Data.json_equal(before.facts.stocks,host.runtime.facts().stocks) and Data.json_equal(before.world.extensions["r3:production"],host.world.extension("r3:production")))
	check("another pause reason survives internal streaming barrier",host.router.is_paused() and host.runtime.is_paused() and not host._stream_state.busy)
	var mixed:Dictionary=host.runtime.capture_checkpoint()
	var restored:Dictionary=host._assemble(mixed)
	check("formal assembly keeps unneeded far data cold instead of warming all",restored.ok and restored.world.region_residency_state(id).paged,restored.get("code"))
	check("formal assembly restores every actual living body's full region",restored.ok and restored.runtime.facts().actors.all(func(a:Dictionary)->bool:return restored.world.region_is_resident(a.regionId)))
	var warm:Dictionary=await host._change_residency({"region_id":id,"resident":true})
	timings.warm=barrier_timing(warm)
	check("real warm path restores data and waits for mesh plus physical frame",warm.ok,warm.get("reason"))
	check("warm recovers the dirty original cell instead of regeneration",host.world.cell_at(x,y,z)==0 and host.world.region_residency_state(id).resident and host.world.region_residency_state(id).page_bytes==0)
	check("warm geometry and collision readiness is actually complete",host._terrain_view.readiness(host.world.region_chunk_keys(id)).get("ready",false))
	var observed:Dictionary=warm.get("geometry_readiness",{})
	check("warm receipt exposes current actual mesh and physics completion",observed.get("ready",false) and observed.get("required")==host.world.region_chunk_keys(id).size() and observed.get("pending_count",-1)==0 and observed.get("awaiting_physics_count",-1)==0 and observed.get("cold_count",-1)==0 and observed.get("unknown_count",-1)==0,observed)
	check("warm cost evidence comes from existing terrain stage counters",warm.get("geometry_statistics",{}).get("stages",{}).has("publish"))
	check("round trip never reissues finite tools or stocks",Data.json_equal(before.facts.stocks,host.runtime.facts().stocks) and Data.json_equal(before.world.extensions["r3:production"],host.world.extension("r3:production")))
	# A failed working save is a real IO fault, not a mocked success callback.
	var blocker:=FileAccess.open(output+"/blocked-path",FileAccess.WRITE);blocker.store_string("not a directory");blocker.close()
	host._stream_store=Store.new(output+"/blocked-path/saves")
	var authority_before:Dictionary=host.runtime.capture_checkpoint()
	var failed:Dictionary=await host._change_residency({"region_id":id,"resident":false})
	check("failed checkpoint never releases or mutates any authority",not failed.ok and Data.json_equal(authority_before,host.runtime.capture_checkpoint()) and host.world.region_is_resident(id),failed.get("code"))
	check("failed checkpoint preserves explicit user's manual bytes",active_bytes==FileAccess.get_file_as_string(host.store.root+"/active.json") and slot_bytes==FileAccess.get_file_as_string(manual.path))
	finish()
func barrier_timing(receipt:Dictionary)->Dictionary:
	var result:Dictionary={}
	for field:String in ["elapsed_ms","data_ready_ms","checkpoint_ms","barrier_ms","max_barrier_ms","barrier_batches_ms","barrier_phases_ms"]:
		if receipt.has(field):result[field]=receipt[field]
	return result

func finish()->void:
	var report:Dictionary={"scope":"headless real NativeClient residency/checkpoint/rollback/terrain readiness; not OS/VA/RSS/performance qualification","checks":checks,"timings":timings,"failed":checks.filter(func(row:Dictionary)->bool:return not row.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	if is_instance_valid(host):host.free()
	quit(1 if report.failed else 0)
