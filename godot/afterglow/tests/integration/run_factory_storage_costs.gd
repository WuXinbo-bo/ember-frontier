extends SceneTree
## Real immutable-package Native save/paging attribution. No renderer/FPS claim.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
class HeadlessNative extends Native:
	func _ready()->void:pass
var output:String
var input_path:String
var input_sha:String
var host:Node3D
var checks:Array=[]
var phases:Dictionary={}
var frame_usec:Array=[]
var last_frame:int=0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func pulse()->void:
	var now:int=Time.get_ticks_usec()
	if last_frame>0:frame_usec.append(now-last_frame)
	last_frame=now
func begin_phase()->int:
	frame_usec.clear();last_frame=Time.get_ticks_usec()
	return last_frame
func end_phase(label:String,started:int,details:Dictionary={})->void:
	var maximum:int=0
	for span:int in frame_usec:maximum=maxi(maximum,span)
	phases[label]={"wall_usec":Time.get_ticks_usec()-started,"process_frames":frame_usec.size(),"max_callback_gap_usec":maximum,"details":details}
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[0];input_path=args[1];input_sha=FileAccess.get_sha256(input_path)
	DirAccess.make_dir_recursive_absolute(output)
	process_frame.connect(pulse)
	var started:int=begin_phase()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input_path))
	end_phase("synchronous_input_decode",started)
	check("exact explicitly supplied Native input decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):finish();return
	host=HeadlessNative.new();host.store=Store.new(output+"/isolated-manual/saves");host.controls_path=output+"/controls.json"
	root.add_child(host);host.set_process(false);host.set_physics_process(false)
	started=begin_phase()
	var built:Dictionary=host._assemble(decoded.capture)
	end_phase("synchronous_native_assembly",started)
	check("all real services and canonical facts assemble",built.get("ok",false) and Data.json_equal(decoded.capture.facts,built.get("runtime").facts()) if built.get("ok",false) else false,built.get("reason"))
	if not built.get("ok",false):finish();return
	host.world=built.world;host.runtime=built.runtime;host._world_epoch=1
	host._stream_store=Store.new(output+"/isolated-stream/saves");host._residency.attach(built.runtime)
	var before:Dictionary=host.runtime.capture_checkpoint()
	started=begin_phase()
	var capture:Dictionary=host.runtime.capture_checkpoint()
	end_phase("synchronous_capture_only",started)
	check("capture is detached and authority exact",Data.json_equal(before,capture))
	capture={}
	await process_frame
	started=begin_phase()
	var saved:Dictionary=await host.save_async("A:storage-costs:manual")
	end_phase("actual_native_manual_save",started,saved)
	check("real asynchronous Native save writes valid exact bytes",saved.get("ok",false) and FileAccess.file_exists(str(saved.get("path",""))) and FileAccess.get_sha256(str(saved.get("path","")))==saved.get("sha256"),saved)
	check("manual save yields process frames while worker runs",frame_usec.size()>0)
	check("manual save does not advance clock or mutate authority",Data.json_equal(before,host.runtime.capture_checkpoint()))
	if not saved.get("ok",false):finish();return
	var active_bytes:String=FileAccess.get_file_as_string(host.store.root+"/active.json")
	var saved_bytes:String=FileAccess.get_file_as_string(saved.path)
	var pins:Dictionary=Residency.required_regions(host.runtime)
	var id:String=""
	for region:Dictionary in host.world.regions():
		if not pins.has(region.id) and not host.world.region_residency_state(region.id).paged:id=region.id
	check("real input contains an unpinned pageable peripheral region",not id.is_empty(),pins.keys())
	if id.is_empty():finish();return
	started=begin_phase()
	var cooled:Dictionary=await host._change_residency({"region_id":id,"resident":false})
	end_phase("actual_native_cold_storage",started,cooled)
	check("actual cold owner persists then commits physical data pages",cooled.get("ok",false) and host.world.region_residency_state(id).paged,cooled)
	check("cold conversion yields process frames",frame_usec.size()>0)
	check("internal working cache preserves manual save bytes",active_bytes==FileAccess.get_file_as_string(host.store.root+"/active.json") and saved_bytes==FileAccess.get_file_as_string(saved.path))
	check("paging preserves time original actors stocks production and receipts",host.runtime.clock()==before.facts.time and Data.json_equal(before.facts.actors,host.runtime.facts().actors) and Data.json_equal(before.facts.stocks,host.runtime.facts().stocks) and Data.json_equal(before.world.extensions["r34:production"],host.world.extension("r34:production")) and Data.json_equal(before.receipts,host.runtime.capture_checkpoint().receipts))
	if cooled.get("ok",false):
		started=begin_phase()
		var warmed:Dictionary=await host._change_residency({"region_id":id,"resident":true})
		end_phase("actual_native_warm_data",started,warmed)
		check("actual warm owner restores unpacked cells",warmed.get("ok",false) and not host.world.region_residency_state(id).paged,warmed)
	check("source Native file remains byte exact",FileAccess.get_sha256(input_path)==input_sha)
	finish()
func finish()->void:
	var report:Dictionary={"scope":"Actual Native save and paging API, real process-frame callbacks, no runtime tick, no renderer/UI/OS frame or performance qualification; callback gaps include headless scheduling and concurrent work. Cold warm here has no terrain view, so data-only readiness.","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"input":{"path":input_path,"sha256":input_sha},"phases":phases,"regions":host.world.regions().size() if is_instance_valid(host) and host.world!=null else 0,"chunks":host.world.chunk_keys().size() if is_instance_valid(host) and host.world!=null else 0,"performance_qualified":false}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed,"phases":phases}))
	quit(1 if report.failed else 0)
