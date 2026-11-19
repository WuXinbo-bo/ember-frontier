extends SceneTree
## Real scene/terrain worker/physics barrier and actual isolated store.
## The explicit readiness gate injects wait/timeout, never fakes success.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
class TestClient extends Client:
	var block_ready:=false
	var polls:=0
	var last_real:Dictionary={}
	var outcome:Dictionary={}
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _candidate_readiness(candidate:Dictionary)->Dictionary:
		polls+=1;last_real=super._candidate_readiness(candidate)
		var result:Dictionary=last_real.duplicate(true)
		if block_ready:result.ready=false
		return result
	func test_restore()->void:outcome=await restore_saved_world("ready:restore")
	func test_import(text:String)->void:outcome=await import_checkpoint(text,"ready:import")

var checks:Array=[]
var output:String
var host:TestClient
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func wait_candidate()->void:
	var until:int=Time.get_ticks_msec()+20000
	while host.polls==0 and host.outcome.is_empty() and Time.get_ticks_msec()<until:await process_frame
func wait_done()->void:
	var until:int=Time.get_ticks_msec()+70000
	while host.outcome.is_empty() and Time.get_ticks_msec()<until:await process_frame
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	host=TestClient.new();host.controls_path=output+"/controls.json";host.store=Store.new(output+"/saves");root.add_child(host)
	check("real retained-world fixture mounts",host._new_rural(713).ok)
	var saved:Dictionary=await host.save_async("ready:baseline")
	check("explicit isolated baseline save is valid",saved.ok,saved)
	if not saved.ok:finish();return
	var pointer_path:String=output+"/saves/active.json"
	var pointer:PackedByteArray=FileAccess.get_file_as_bytes(pointer_path)
	var old_world:RefCounted=host.world;var old_runtime:RefCounted=host.runtime;var old_scene:Node3D=host.scene_root
	var old_fact:Dictionary=old_runtime.actor("player");var changed:Dictionary=old_fact.duplicate(true);changed.pack.water=0
	check("unsaved fixture difference commits normally",old_runtime._commit({"fact_changes":[{"collection":"actors","id":"player","before":old_fact,"after":changed}]}).ok)
	host.block_ready=true;host.mount_timeout_msec=120;host.call_deferred("test_restore")
	await wait_candidate()
	check("pending candidate retains old live authority and visible root",host.polls>0 and host.world==old_world and host.runtime==old_runtime and is_instance_valid(old_scene) and old_scene.get_parent()==host and old_scene.visible)
	check("pending candidate gates input and old clock",host._world_loading and host._save_state.busy and host.router.is_paused() and old_runtime.is_paused())
	check("pending restore does not alter active bytes",FileAccess.get_file_as_bytes(pointer_path)==pointer)
	var waiting:Dictionary=old_runtime.capture_checkpoint()
	check("authority itself rejects late life input during loading",old_runtime.command({"kind":"eat","command_id":"stale:loading","actor_id":"player"}).code=="NOT_READY" and old_runtime.capture_checkpoint()==waiting)
	await wait_done()
	check("forced readiness timeout fails with explicit code",not host.outcome.is_empty() and not host.outcome.ok and host.outcome.code=="WORLD_READY_TIMEOUT",host.outcome)
	await process_frame
	check("timeout retains exact old unsaved world and frees candidate",host.world==old_world and host.runtime==old_runtime and host.runtime.actor("player").pack.water==0 and host.get_children().filter(func(n:Node)->bool:return n is Node3D and n!=old_scene).is_empty())
	check("timeout releases loading lock and preserves save",not host._world_loading and not host._saving and not host._save_state.busy and FileAccess.get_file_as_bytes(pointer_path)==pointer)
	# The released gate now permits ONLY actual C readiness + physics barrier.
	host.block_ready=false;host.mount_timeout_msec=60000
	var restored:Dictionary=await host.restore_saved_world("ready:success")
	check("real terrain geometry AND physics gate succeeds",restored.ok and restored.get("readiness",{}).get("geometry_ready",false) and restored.readiness.get("physics_ready",false),restored)
	check("promoted runtime pause follows the input owner",host.runtime.is_paused()==host.router.is_paused())
	check("promotion changes authority only after ready and restores ration",host.world!=old_world and host.runtime!=old_runtime and host.runtime.actor("player").pack.water==1 and host._ready_game and not host._world_loading)
	await process_frame
	check("old scene retires after successful promotion",not is_instance_valid(old_scene))
	check("explicit restore still never modifies active bytes",FileAccess.get_file_as_bytes(pointer_path)==pointer)
	check("retired authority rejects stale input and storage callback",old_runtime.command({"kind":"eat","command_id":"stale:retired","actor_id":"player"}).code=="WORLD_RETIRED" and (await old_runtime.save_async("stale:save")).code=="WORLD_RETIRED" and FileAccess.get_file_as_bytes(pointer_path)==pointer)
	# Import must also preserve active until its candidate is actually ready.
	old_world=host.world;old_runtime=host.runtime;old_scene=host.scene_root
	var encoded:Dictionary=Store.encode(host.runtime.capture_checkpoint())
	host.outcome={};host.polls=0;host.block_ready=true;host.mount_timeout_msec=120
	host.call_deferred("test_import",encoded.text);await wait_candidate()
	check("pending import retains active bytes and original scene",host.world==old_world and host.runtime==old_runtime and old_scene.get_parent()==host and FileAccess.get_file_as_bytes(pointer_path)==pointer)
	await wait_done();await process_frame
	check("failed import readiness never saves or activates candidate",not host.outcome.ok and host.outcome.code=="WORLD_READY_TIMEOUT" and FileAccess.get_file_as_bytes(pointer_path)==pointer and host.runtime==old_runtime,host.outcome)
	host.block_ready=false;host.mount_timeout_msec=60000
	var imported:Dictionary=await host.import_checkpoint(encoded.text,"ready:import-success")
	check("ready import writes verified namespace and explicitly activates",imported.ok and imported.get("activated",false) and host.runtime!=old_runtime and FileAccess.get_file_as_bytes(pointer_path)!=pointer,imported)
	var loaded:Dictionary=host.store.load_current()
	check("activated import reads back complete matching authority",loaded.ok and loaded.capture.facts.actors[0].pack==host.runtime.actor("player").pack)
	var choices:Dictionary=host.store.list_recovery_candidates()
	var picked:Dictionary=choices.candidates[0]
	var active_before:PackedByteArray=FileAccess.get_file_as_bytes(pointer_path)
	var live_before:RefCounted=host.runtime
	host._startup_recovery=Client.Ui.mount_recovery(host,choices.candidates,host._startup_choose_recovery,host._startup_fresh)
	var recovery_layer:Node=host._startup_recovery.get_parent()
	var stale:Dictionary=await host._startup_choose_recovery(picked.candidate_id,"0".repeat(64))
	check("startup stale selection returns freshly scanned candidate identities",stale.code=="STALE_CANDIDATE" and stale.get("candidates")==choices.candidates and stale.get("scan")==choices.scan,stale.get("code"))
	check("failed startup choice retains recovery layer, authority and active bytes",is_instance_valid(host._startup_recovery) and not recovery_layer.is_queued_for_deletion() and host.runtime==live_before and FileAccess.get_file_as_bytes(pointer_path)==active_before)
	var chosen:Dictionary=await host._startup_choose_recovery(picked.candidate_id,picked.sha256)
	check("explicit startup choice promotes actual ready candidate",chosen.ok and chosen.get("activated",false) and host.runtime!=live_before,chosen.get("code"))
	await process_frame
	check("successful startup releases complete recovery layer",host._startup_recovery==null and not is_instance_valid(recovery_layer))
	check("startup restored runtime is live without needing a focus event",not host.runtime.is_paused() and not host.router.is_paused())
	# Store-only stale-active and tamper counterexamples use another directory.
	var store:=Store.new(output+"/activation")
	check("staged store write begins without active",store.begin_save(host.runtime.capture_checkpoint(),true,"",false).ok)
	var staged:Dictionary={}
	while staged.is_empty():await process_frame;staged=store.poll()
	check("staged write creates slot but no active pointer",staged.ok and not staged.activated and not FileAccess.file_exists(output+"/activation/active.json"))
	var fake:=FileAccess.open(output+"/activation/active.json",FileAccess.WRITE);fake.store_string("external changed active");fake.close()
	check("stale active refuses activation and preserves external bytes",store.activate_saved(staged).code=="STALE_ACTIVE" and FileAccess.get_file_as_string(output+"/activation/active.json")=="external changed active")
	DirAccess.remove_absolute(output+"/activation/active.json")
	var tamper:=FileAccess.open(staged.path,FileAccess.WRITE);tamper.store_string("tampered");tamper.close()
	check("tampered candidate refuses activation without active",store.activate_saved(staged).code=="INVALID_CANDIDATE" and not FileAccess.file_exists(output+"/activation/active.json"))
	finish()

func finish()->void:
	var report:Dictionary={"scope":"source headless actual scene/terrain/physics/store; explicit delayed-gate and disk-tamper fixtures; not OS-input/PCK/VA/performance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));host.free();quit(1 if report.failed else 0)
