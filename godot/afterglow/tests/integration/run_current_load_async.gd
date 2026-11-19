extends SceneTree
## Real24 manual resume and explicitly isolated file/lifecycle races. No OS claim.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Router=preload("res://scripts/input/input_router.gd")
const Data=preload("res://scripts/world/world_data.gd")
class TestClient extends Native:
	var fault:String=""
	var slot:String=""
	func _ready()->void:pass
	func _prepare_mount_ready(capture:Dictionary,assembly:Dictionary={})->Dictionary:
		if fault=="readiness":
			await get_tree().process_frame
			return {"ok":false,"code":"TEST_READY_REJECTION","reason":"isolated readiness failure"}
		var candidate:Dictionary=await super._prepare_mount_ready(capture,assembly)
		if candidate.ok and fault=="active":
			var file:=FileAccess.open(store.root+"/active.json",FileAccess.WRITE);file.store_string("{}");file.close()
		elif candidate.ok and fault=="slot":
			var text:String=FileAccess.get_file_as_string(slot)
			var file:=FileAccess.open(slot,FileAccess.WRITE);file.store_string(text.replace('"format"','"xormat"'));file.close()
		return candidate
var host:Node3D
var checks:Array=[]
var output:String
var input:String
var input_sha:String
var pending:Dictionary={}
var monitor:bool=false
var frames:int=0
var gated:int=0
var last_frame:int=0
var max_gap:int=0
var close_fixture:bool=false
var observations:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func pulse()->void:
	if not monitor:return
	var now:int=Time.get_ticks_usec()
	if last_frame>0:max_gap=maxi(max_gap,now-last_frame)
	last_frame=now;frames+=1
	if host._saving and host._world_loading and host.runtime.is_paused() and host.router.state().pause_reasons.get("closing",false):gated+=1
	if close_fixture and frames==2:host._closing=true
func job(label:String)->void:pending=await host.restore_saved_world("A:current-load:"+label)
func begin(label:String)->void:
	pending={};frames=0;gated=0;last_frame=Time.get_ticks_usec();max_gap=0;monitor=true
	job(label)
func wait_job()->void:
	while pending.is_empty():await process_frame
	# Include the final synchronous assembly/activation tail in gap evidence.
	await process_frame
	monitor=false
func write(path:String,text:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0];input=args[1];input_sha=FileAccess.get_sha256(input)
	DirAccess.make_dir_recursive_absolute(output)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	check("explicit unchanged real24 source decodes",decoded.get("ok",false) and decoded.capture.world.regions.size()==24)
	if not decoded.get("ok",false):finish();return
	host=TestClient.new();root.add_child(host);host.set_process(false)
	host.store=Store.new(output+"/manual/saves");host.controls_path=output+"/controls.json"
	var built:Dictionary=host._assemble(decoded.capture)
	check("actual Native services assemble without replacing source facts",built.get("ok",false) and Data.json_equal(built.runtime.facts(),decoded.capture.facts))
	if not built.get("ok",false):finish();return
	host.world=built.world;host.runtime=built.runtime;host._world_epoch=1
	host.router=Router.new();host.router.controls_path=host.controls_path;host.add_child(host.router);host.router.configure(host.runtime);host.router.set_physics_process(false);host.router.set_window_focus(true)
	var original:Dictionary=host.runtime.capture_checkpoint()
	var saved:Dictionary=await host.save_async("A:current-load:baseline")
	check("shipping asynchronous manual save produces independent exact source",saved.get("ok",false))
	if not saved.get("ok",false):finish();return
	host.slot=saved.path
	var active:String=FileAccess.get_file_as_string(host.store.root+"/active.json")
	var slot:String=FileAccess.get_file_as_string(saved.path)
	process_frame.connect(pulse)
	begin("success")
	check("loading feedback and input gate precede any read await",host._saving and host._world_loading and host.runtime.is_paused() and host._save_state.status=="loading" and host.router.state().pause_reasons.get("closing",false))
	var concurrent:Dictionary=await host.save_async("A:current-load:concurrent")
	check("same owner rejects concurrent manual save while reading",not concurrent.ok and concurrent.code=="BUSY")
	await wait_job()
	check("actual resume finishes real camera mesh and physics readiness",pending.get("ok",false) and pending.get("readiness",{}).get("ready",false),pending.get("code"))
	check("read worker yields many gated callbacks and reports assembly separately",frames>2 and gated>1 and pending.get("read_ms",0)>0 and pending.get("assembly_ms",0)>0,{"frames":frames,"gated":gated,"read_ms":pending.get("read_ms"),"assembly_ms":pending.get("assembly_ms"),"max_callback_gap_usec":max_gap})
	check("resume preserves exact people stocks tools orders knowledge receipts and clock",Data.json_equal(original.facts,host.runtime.facts()) and Data.json_equal(original.receipts,host.runtime.capture_checkpoint().receipts) and Data.json_equal(original.world.extensions,host.world.snapshot().extensions) and Data.json_equal(original.simulation,host.runtime.capture_checkpoint().simulation))
	check("read-only restore never rewrites manual active or slot",active==FileAccess.get_file_as_string(host.store.root+"/active.json") and slot==FileAccess.get_file_as_string(saved.path))
	check("completed restore releases its own load gate",not host._saving and not host._world_loading and not host.router.state().pause_reasons.get("closing",false))
	observations.append({"case":"success","frames":frames,"gated":gated,"read_ms":pending.get("read_ms"),"assembly_ms":pending.get("assembly_ms"),"max_callback_gap_usec":max_gap,"includes_read_assembly_readiness_activation":true})
	for fault:String in ["readiness","active","slot","closing","missing"]:
		host.fault=fault;close_fixture=fault=="closing"
		var before:Dictionary=host.runtime.capture_checkpoint();var authority:RefCounted=host.runtime
		var original_mode:int=host.scene_root.process_mode
		var store_root:String=host.store.root
		if fault=="missing":host.store=Store.new(output+"/missing/saves")
		begin(fault);await wait_job()
		var expected:String={"readiness":"TEST_READY_REJECTION","active":"STALE_ACTIVE","slot":"STALE_CANDIDATE","closing":"WORLD_SWITCH_CANCELLED","missing":"NO_SAVE"}[fault]
		check("explicit "+fault+" race refuses publication",not pending.get("ok",false) and pending.get("code")==expected,pending.get("code"))
		check(fault+" keeps original live authority and complete checkpoint",host.runtime==authority and Data.json_equal(before,host.runtime.capture_checkpoint()))
		check(fault+" drains worker and releases load/save ownership",not host._saving and not host._world_loading)
		check(fault+" preserves original scene processing after rejection",host.scene_root.process_mode==original_mode)
		observations.append({"case":fault,"code":pending.get("code"),"frames":frames,"max_callback_gap_usec":max_gap,"fixture":true,"readiness":pending.get("readiness",{})})
		host._closing=false;host.router.set_closing(false);close_fixture=false
		if fault=="missing":host.store=Store.new(store_root)
		write(store_root+"/active.json",active);write(saved.path,slot)
	check("all isolated races restore only test bytes; original input exact",FileAccess.get_sha256(input)==input_sha and FileAccess.get_file_as_string(host.store.root+"/active.json")==active and FileAccess.get_file_as_string(saved.path)==slot)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"input":{"path":input,"sha256":input_sha},"observations":observations,"scope":"Real24 Native manual save/resume + isolated readiness/index/same-length-slot/closing/missing-file faults. Exact authority and manual bytes preserved. Worker only read/decode; synchronous assembly/readiness and callback tail explicitly included, no renderer/OS/FPS/RSS/final acceptance."},"\t",true,true))
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
