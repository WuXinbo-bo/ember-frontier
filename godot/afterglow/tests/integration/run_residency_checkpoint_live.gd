extends SceneTree
## Actual Native IO with a real 24-region checkpoint. Race fixtures are explicit.
## No renderer, user saves, gifted tools, actor teleport or second clock.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Router=preload("res://scripts/input/input_router.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
class HeadlessNative extends Native:
	func _ready()->void:pass
var host:Node3D
var checks:Array=[]
var output:String
var source:String
var source_sha:String
var capture:Dictionary
var pending:Dictionary={}
var mode:String=""
var target:String=""
var last_usec:int=0
var frames:int=0
var invariant_frames:int=0
var moved:Dictionary={}
var injected:Dictionary={}
var last_facts:Dictionary={}
var observations:Dictionary={}
var preparing_frames:int=0
var checkpoint_frames:int=0
var storage_checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func mount(label:String)->bool:
	if is_instance_valid(host):host.free()
	host=HeadlessNative.new();root.add_child(host);host.set_process(false)
	host.store=Store.new(output+"/"+label+"/manual/saves")
	host._stream_store=Store.new(output+"/"+label+"/stream/saves")
	var built:Dictionary=host._assemble(capture)
	check(label+": actual Native services assemble",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return false
	host.world=built.world;host.runtime=built.runtime;host._world_epoch=1;host._residency.attach(built.runtime)
	host.router=Router.new();host.router.controls_path=output+"/"+label+"/controls.json"
	host.add_child(host.router);host.router.configure(host.runtime);host.router.set_physics_process(false)
	host.runtime.set_paused(false)
	host.runtime.changed.connect(observe_storage)
	target=""
	var pins:Dictionary=Residency.required_regions(host.runtime)
	for region:Dictionary in host.world.regions():
		if not pins.has(region.id) and not host.world.region_residency_state(region.id).paged:target=region.id;break
	check(label+": real unpinned target exists",not target.is_empty())
	return not target.is_empty()
func cold_job()->void:
	pending=await host._change_residency({"region_id":target,"resident":false})
func begin_case(label:String)->void:
	mode=label;pending={};injected={};moved={};last_facts={};frames=0;invariant_frames=0;last_usec=Time.get_ticks_usec()
	preparing_frames=0;checkpoint_frames=0;storage_checks=[]
	cold_job()
func observe_storage(changes:Dictionary)->void:
	if mode!="live" or not changes.get("events",[]).any(func(event:Dictionary)->bool:return event.get("kind")=="region-storage-changed"):return
	var facts:Dictionary=host.runtime.facts();var previous:Dictionary=last_facts.duplicate(true)
	var ledger:Array=facts.get("ledger",[]);var before_ledger:Array=previous.get("ledger",[])
	var retained:int=mini(before_ledger.size(),255)
	var exact:bool=ledger.size()==retained+1 and Data.json_equal(before_ledger.slice(before_ledger.size()-retained),ledger.slice(0,retained))
	var event:Dictionary=ledger.back() if not ledger.is_empty() else {}
	exact=exact and event.get("kind")=="region-storage-changed" and event.get("region_id")==target and event.get("resident")==false
	facts.erase("ledger");previous.erase("ledger")
	storage_checks.append({"facts_preserved":not last_facts.is_empty() and Data.json_equal(previous,facts),"exact_event":exact,"chunks":changes.get("world",[]).size(),"operations":changes.get("world",[]).all(func(row:Dictionary)->bool:return row.op=="chunk.storage" and row.after.resident==false)})
	last_facts=host.runtime.facts()
func pulse()->void:
	var now:int=Time.get_ticks_usec();var dt:float=(now-last_usec)/1000000.0;last_usec=now
	if mode.is_empty() or not is_instance_valid(host):return
	var checkpointing:bool=host._stream_state.get("checkpointing",false)
	var preparing:bool=host._stream_state.get("preparing_data",false)
	if not checkpointing and not preparing:return
	frames+=1
	if checkpointing:checkpoint_frames+=1
	if preparing:preparing_frames+=1
	if not host._stream_state.busy and not host.router.state().pause_reasons.get("streaming",false):invariant_frames+=1
	if mode=="live":
		host.runtime.tick(dt)
		if moved.is_empty() and host.runtime.clock()>float(capture.facts.time)+0.2:
			var actor:Dictionary=host.runtime.actor("player")
			for direction:Vector2 in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
				var to:Dictionary={"x":float(actor.x)+direction.x*0.04,"y":actor.y,"z":float(actor.z)+direction.y*0.04,"regionId":actor.regionId,"buildingId":actor.get("buildingId"),"storeyId":actor.get("storeyId")}
				var result:Dictionary=host.router.request("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},to)
				if result.ok:moved={"before":actor,"after":host.runtime.actor("player"),"receipt":result};break
		last_facts=host.runtime.facts()
	elif mode in ["edit","edit-preparing","edit-after-batch"] and injected.is_empty() and (mode=="edit" and checkpointing or mode=="edit-preparing" and preparing or mode=="edit-after-batch" and preparing and host.world.region_residency_state(target).page_bytes>0):
		var bounds:Dictionary=host.world.region(target).bounds
		var x:int=floori(float(bounds.min.x)*2)+5;var z:int=floori(float(bounds.min.z)*2)+5
		# First batch may already page the near column. Deliberately edit an
		# untouched far column through the original safe voxel transaction.
		if mode=="edit-after-batch":z=ceili(float(bounds.max.z)*2)-5
		var y:int=roundi(float(host.world.surface_height((x+0.5)*0.5,(z+0.5)*0.5))*2)-1
		var old:int=host.world.cell_at(x,y,z)
		var result:Dictionary=host.runtime._commit({"world_changes":[{"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":old,"after":0}]})
		injected={"result":result,"cell":{"x":x,"y":y,"z":z},"old":old,"after":host.runtime.capture_checkpoint()}
	elif mode in ["camera","camera-preparing"] and injected.is_empty() and (mode=="camera" and checkpointing or mode=="camera-preparing" and preparing):
		var bounds:Dictionary=host.world.region(target).bounds
		var focus:=Vector3((float(bounds.min.x)+float(bounds.max.x))/2,0,(float(bounds.min.z)+float(bounds.max.z))/2)
		host.camera=Camera3D.new();host.add_child(host.camera)
		host.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;host.camera.size=12
		host.camera.position=focus+Vector3(24,29,31);host.camera.look_at(focus)
		injected={"camera_fixture":true}
	elif mode=="pause" and injected.is_empty():
		host.router.set_window_focus(false);injected={"clock":host.runtime.clock()}
	elif mode=="pause":host.runtime.tick(dt)
func wait_case()->void:
	while pending.is_empty():await process_frame
	observations[mode]={"result":pending.duplicate(true),"checkpoint_frames":checkpoint_frames,"preparing_frames":preparing_frames,"background_frames":frames,"ungated_frames":invariant_frames,"storage_checks":storage_checks.duplicate(true)}
	mode=""
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[0];source=args[1];source_sha=FileAccess.get_sha256(source)
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,800)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source))
	check("explicit real checkpoint decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):finish();return
	capture=decoded.capture
	check("real source has 24 regions and original people",capture.world.regions.size()==24 and capture.facts.actors.size()==3)
	process_frame.connect(pulse)
	if not mount("live"):finish();return
	var manual:Dictionary=await host.save_async("live:manual-before")
	check("manual baseline saved independently",manual.get("ok",false))
	if not manual.get("ok",false):finish();return
	var active:String=FileAccess.get_file_as_string(host.store.root+"/active.json")
	var manual_sha:String=FileAccess.get_sha256(manual.path)
	var key:=InputEventKey.new();key.physical_keycode=KEY_D;key.pressed=true;host.router._unhandled_input(key)
	var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true;host.router._unhandled_input(button)
	begin_case("live")
	check("checkpoint yields without freezing runtime or clearing held input",host._streaming and host._stream_state.get("checkpointing",false) and not host._stream_state.busy and not host.runtime.is_paused() and host.router.state().held.primary and host.router._pressed.has("right"))
	var concurrent:Dictionary=await host.save_async("live:concurrent")
	check("one exclusive stream owner rejects concurrent manual save",not concurrent.ok and concurrent.code=="BUSY")
	await wait_case()
	check("actual worker finishes before cold data release",pending.get("ok",false) and host.world.region_residency_state(target).paged and not str(pending.get("checkpoint_sha256","")).is_empty(),pending)
	check("real background IO and page workers keep the original clock ungated",host.runtime.clock()>float(capture.facts.time)+0.1 and checkpoint_frames>1 and preparing_frames>=pending.batches and invariant_frames==frames,{"frames":frames,"checkpoint_frames":checkpoint_frames,"preparing_frames":preparing_frames,"actual_batches":pending.batches,"clock":host.runtime.clock(),"source_clock":capture.facts.time})
	check("ordinary nearby validated direct movement works during IO",not moved.is_empty() and moved.before.x!=moved.after.x or not moved.is_empty() and moved.before.z!=moved.after.z,moved)
	var current_facts:Dictionary=host.runtime.facts()
	var expected_storage_events:int=ceili(host.world.region_chunk_keys(target).size()/64.0)
	check("each bounded CAS preserves latest facts and adds exactly one storage event",Data.json_equal(last_facts,current_facts) and storage_checks.size()==expected_storage_events and storage_checks.all(func(row:Dictionary)->bool:return row.facts_preserved and row.exact_event and row.chunks>0 and row.chunks<=64 and row.operations),{"expected_storage_events":expected_storage_events,"actual":storage_checks})
	check("only the short conversion barrier releases held input",not host.router.state().held.primary and host.router._pressed.is_empty() and not host.runtime.is_paused() and not host.router.is_paused())
	check("reported checkpoint and barrier durations are separate",float(pending.get("checkpoint_ms",0))>0 and float(pending.get("barrier_ms",-1))>=0 and float(pending.get("barrier_ms",0))<float(pending.elapsed_ms),pending)
	check("working checkpoint never changes explicit manual bytes",FileAccess.get_file_as_string(host.store.root+"/active.json")==active and FileAccess.get_sha256(manual.path)==manual_sha)
	var warm:Dictionary=await host._change_residency({"region_id":target,"resident":true})
	check("original cold data warms under the same owner",warm.get("ok",false) and not host.world.region_residency_state(target).paged,warm)
	check("64-chunk policy and separate synchronous barrier costs stay explicit",pending.batch_chunks==64 and pending.batches==4 and warm.batch_chunks==64 and warm.batches==4 and pending.max_barrier_ms<=pending.barrier_ms and pending.worker_usec>0 and pending.capture_usec>0,pending)
	if not mount("edit"):finish();return
	begin_case("edit");await wait_case()
	check("explicit isolated race fixture makes a real safe voxel transaction",injected.get("result",{}).get("ok",false) and injected.get("old",0)!=0,injected.get("result"))
	check("target revision change rejects stale eviction with zero barrier",not pending.ok and pending.code=="RESIDENCY_STALE" and float(pending.barrier_ms)==0 and not host.world.region_residency_state(target).paged and host.world.region_residency_state(target).unpacked_bytes>0,pending)
	check("stale eviction preserves the complete edited authority",injected.has("after") and Data.json_equal(injected.after,host.runtime.capture_checkpoint()))
	if not mount("camera"):finish();return
	var before:Dictionary=host.runtime.capture_checkpoint()
	begin_case("camera");await wait_case()
	check("new real camera footprint pins before any conversion",not pending.ok and pending.code=="REGION_PINNED" and float(pending.barrier_ms)==0 and not host.world.region_residency_state(target).paged and host.world.region_residency_state(target).unpacked_bytes>0,pending)
	check("new camera dependency refusal preserves all authority",Data.json_equal(before,host.runtime.capture_checkpoint()))
	if not mount("edit-preparing"):finish();return
	begin_case("edit-preparing");await wait_case()
	check("target edit during detached worker rejects original guard without rebasing",injected.get("result",{}).get("ok",false) and not pending.ok and pending.code=="RESIDENCY_STALE" and pending.batches==0 and pending.barrier_ms==0,pending)
	check("worker-race refusal preserves complete edited authority",injected.has("after") and Data.json_equal(injected.after,host.runtime.capture_checkpoint()))
	if not mount("camera-preparing"):finish();return
	before=host.runtime.capture_checkpoint();begin_case("camera-preparing");await wait_case()
	check("new camera pin during detached worker prevents first CAS",not injected.is_empty() and not pending.ok and pending.code=="REGION_PINNED" and pending.batches==0 and pending.barrier_ms==0 and Data.json_equal(before,host.runtime.capture_checkpoint()),pending)
	if not mount("edit-after-batch"):finish();return
	begin_case("edit-after-batch");await wait_case()
	check("later edit stops subsequent batches without accepting arbitrary save rebase",injected.get("result",{}).get("ok",false) and not pending.ok and pending.code=="RESIDENCY_STALE" and pending.batches==1 and host.world.region_residency_state(target).page_bytes>0,pending)
	check("partial lossless storage plus edited target remains the exact authority",injected.has("after") and Data.json_equal(injected.after,host.runtime.capture_checkpoint()))
	if not mount("pause"):finish();return
	begin_case("pause");await wait_case()
	check("focus loss during checkpoint retains the existing pause reason",pending.ok and host.router.state().pause_reasons.window_focus and host.runtime.is_paused() and host.router.is_paused(),pending)
	check("only clock remains stopped after actual focus loss",injected.has("clock") and host.runtime.clock()==float(injected.clock))
	if not mount("failure"):finish();return
	var blocker:=FileAccess.open(output+"/blocked-path",FileAccess.WRITE);blocker.store_string("not a directory");blocker.close()
	host._stream_store=Store.new(output+"/blocked-path/cache")
	before=host.runtime.capture_checkpoint();begin_case("failure");await wait_case()
	check("real failed IO keeps full original authority and resident cells",not pending.ok and pending.code=="IO_ERROR" and Data.json_equal(before,host.runtime.capture_checkpoint()) and not host.world.region_residency_state(target).paged and host.world.region_residency_state(target).unpacked_bytes>0,pending)
	check("IO failure never installs or releases an input barrier",float(pending.barrier_ms)==0 and not host.runtime.is_paused() and not host.router.is_paused() and not host._streaming)
	check("original source file remains byte exact",FileAccess.get_sha256(source)==source_sha)
	finish()
func finish()->void:
	mode=""
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var report:Dictionary={"scope":"Actual source Native24/checkpoint worker/real elapsed tick/validated short step; isolated target-edit and camera/focus race fixtures. No OS input, renderer, FPS, mesh readiness or final package qualification.","checks":checks,"failed":failed,"input":{"path":source,"sha256":source_sha},"observations":observations}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
