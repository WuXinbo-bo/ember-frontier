extends Node3D
const DetachedRead=preload("res://scripts/storage/detached_read.gd")
## Sole composition root, lifecycle owner and native save coordinator.
const World = preload("res://scripts/world/world_state.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const Rural = preload("res://scripts/world/rural_generator.gd")
const Buildings = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Gameplay = preload("res://scripts/runtime/rural_gameplay.gd")
const ResidentLife = preload("res://scripts/runtime/resident_life.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Initial = preload("res://scripts/runtime/initial_state.gd")
const SettlementAssembly = preload("res://scripts/runtime/settlement_assembly.gd")
const FactoryAssembly = preload("res://scripts/runtime/factory_assembly.gd")
const Playtest = preload("res://scripts/runtime/playtest_profile.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const LegacyIntents = preload("res://scripts/storage/legacy_intents.gd")
const Router = preload("res://scripts/input/input_router.gd")
const TerrainView = preload("res://scripts/terrain/terrain_view.gd")
const NativePerformance = preload("res://scripts/presentation/native_performance.gd")
const GameplayView = preload("res://scripts/presentation/gameplay_view.gd")
const Actors = preload("res://scripts/presentation/actor_view.gd")
const PlayerOcclusion = preload("res://scripts/presentation/player_occlusion.gd")
const InteriorViewPolicy = preload("res://scripts/presentation/interior_view_policy.gd")
const SceneLighting = preload("res://scripts/presentation/scene_lighting.gd")
var _settlement_lights: Dictionary = {}
var _night_tint := 0.0
var _night_tint_goal := 0.0
var _night_light_poll := 0.0
const Interaction = preload("res://scripts/input/direct_interaction.gd")
const Ui = preload("res://scripts/ui/ui_mount.gd")
const RegionScheduler=preload("res://scripts/runtime/region_scheduler.gd")
const FactoryServices=preload("res://scripts/runtime/factory_services.gd")
const FactoryView=preload("res://scripts/presentation/factory_view.gd")
const PlanningVisual=preload("res://scripts/presentation/planning_visual.gd")
const EcologyVisual=preload("res://scripts/presentation/ecology_visual.gd")
const RegionResidency=preload("res://scripts/runtime/region_residency.gd")
const CameraInterest=preload("res://scripts/runtime/camera_interest.gd")
const CAMERA_PREFETCH_METRES=8.0
const StartupShell=preload("res://scripts/runtime/startup_shell.gd")
const RESIDENCY_BATCH_CHUNKS=64
var runtime: RefCounted
var world: RefCounted
var router: Node
var camera: Camera3D
var ui: Control
var store := Store.new()
var scene_root: Node3D
var interaction: Node
var _save_state := {"ready":true,"busy":false,"status":"idle","reason":"尚未保存"}
var _saving := false
var _closing := false
var _ready_game := false
var _camera_focus: Vector3
var _camera_offset := Vector3(24,29,31)
var _interior_view_policy:RefCounted
var _world_loading:=false
var _fresh_save_required:=false
var _test_session:=false
var _new_world_profile:="normal"
var controls_path:String="user://controls.json"
var _qa_evidence_directory:=""
var _world_epoch:int=0
var mount_timeout_msec:int=60000
var _startup_recovery:Control
var _shell:CanvasLayer
var _menu_seed:int=-1
var _terrain_view:Node3D
var _regions:=RegionScheduler.new()
var _residency:=RegionResidency.new()
var _streaming:=false
var _stream_state:Dictionary={"busy":false,"region_id":"","resident":false}
var _stream_store:RefCounted
var _frontier_limit_code:String=""
var _stream_checkpoint:Dictionary={}
var _stream_checkpoint_runtime:RefCounted
var _stream_storage_commit:=false

func _ready() -> void:
	get_tree().auto_accept_quit=false
	get_window().close_requested.connect(_close_requested)
	get_window().focus_exited.connect(func():
		if router!=null:router.set_window_focus(false))
	get_window().focus_entered.connect(func():
		if router!=null:router.set_window_focus(true))
	_shell=StartupShell.new();add_child(_shell);_shell.chosen.connect(_shell_action)
	var options:Dictionary=startup_options(OS.get_cmdline_user_args())
	if not options.ok:_fatal(options);return
	var storage_options:Dictionary=configure_startup_storage(options)
	if not storage_options.ok:_fatal(storage_options);return
	_new_world_profile=options.get("new_world_profile","normal");_menu_seed=int(options.seed)
	if not options.direct:
		_shell.show_menu()
		return
	await _startup_enter(options)

func _startup_enter(options:Dictionary)->void:
	var result:Dictionary
	if options.resume:
		if _world_loading or _saving or _closing:return
		_world_loading=true
		await _stage_feedback("read","读取村庄","正在读取并校验上次保存的完整世界。")
		var worker:=Thread.new()
		var started:int=worker.start(DetachedRead.load_current.bind(store.root))
		if started!=OK:
			_world_loading=false
			_fatal({"ok":false,"code":"IO_ERROR","reason":"无法启动存档读取任务"});return
		while worker.is_alive():await get_tree().process_frame
		var restored:Dictionary=worker.wait_to_finish()
		_world_loading=false
		if _closing:return
		if restored.ok:
			result=await _startup_restore(restored)
			if not result.ok:return
		elif restored.get("code")=="RECOVERY_CHOICE_REQUIRED":
			_shell.dismiss()
			_startup_recovery=Ui.mount_recovery(self,restored.candidates,_startup_choose_recovery,_startup_fresh)
			return
		else:
			_shell.show_menu("尚无可继续的有效存档。" if restored.get("code")=="NO_SAVE" else str(restored.get("reason","读取存档未完成")))
			return
	else:
		result=await start_profiled_world(str(options.get("new_world_profile","normal")),int(options.get("seed",-1)),"first-world")
	if not result.ok:
		if not _closing:_shell.show_result(result,runtime!=null)
		return
	_ready_game=true
	print("R3.4 native ready "+JSON.stringify({"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"arch":Engine.get_architecture_name(),"world":world.identity(),"actors":runtime.facts().actors.size(),"viewport":str(get_viewport().get_visible_rect().size),"user_path":OS.get_user_data_dir()}))

func _shell_action(action:String)->void:
	if action in ["normal","playtest"]:await _startup_enter({"resume":false,"new_world_profile":action,"seed":_menu_seed})
	elif action=="continue":await _startup_enter({"resume":true})
	elif action=="quit" or action=="retry_close":_close_requested()
	elif action=="cancel_close":cancel_close()
	elif action=="dismiss":
		_shell.dismiss()
		if router!=null:router.set_closing(false)

func _stage_feedback(phase:String,title:String,reason:String)->void:
	if is_instance_valid(_shell):_shell.show_stage(phase,title,reason)
	# Let a real render occur before this phase's bounded synchronous work.
	await get_tree().process_frame
	await get_tree().process_frame

func lifecycle_status()->Dictionary:
	return _shell.snapshot() if is_instance_valid(_shell) else {"state":"hidden","phase":"","modal":false}

func _startup_restore(restored:Dictionary)->Dictionary:
	_world_loading=true;_saving=true
	await _stage_feedback("assemble","恢复村庄","正在恢复人物、仓储、生产与地区依赖。")
	var candidate:Dictionary=await _prepare_mount_ready(restored.capture)
	var result:Dictionary=candidate
	if candidate.ok:
		# Startup readiness also yields. Publish only the exact slot and active
		# pointer that --continue read, as for an explicit in-game restore.
		var basis:Dictionary=_current_read_matches(restored)
		if basis.ok:
			result=_activate_scene(candidate)
			if result.ok:_ready_game=true
		else:
			_discard_candidate(candidate)
			result=basis
	_world_loading=false;_saving=false
	if _closing:return result
	if result.ok:
		_test_session=not restored.capture.get("source",{}).get("playtest",{}).is_empty()
		result.reason="已恢复完整世界；工具、物资和热栏沿用存档。"
		if is_instance_valid(_shell):_shell.show_result(result,true)
		return result
	# A byte-valid legacy slot can still fail current domain/standing checks.
	# Keep its bytes and active pointer; offer another explicit choice or fresh
	# world rather than stranding startup on a fatal label or moving its actors.
	_save_state.merge({"busy":false,"status":"failed","reason":result.get("reason","")},true)
	var scan:Dictionary=store.list_recovery_candidates()
	result.candidates=scan.get("candidates",[])
	result.scan=scan.get("scan",{})
	if is_instance_valid(_shell):_shell.dismiss()
	_startup_recovery=Ui.mount_recovery(self,result.candidates,_startup_choose_recovery,_startup_fresh,result)
	return result

static func startup_options(args:PackedStringArray)->Dictionary:
	var result:Dictionary={"ok":true,"resume":false,"seed":-1,"direct":false}
	for arg:String in args:
		if arg=="--continue":result.resume=true;result.direct=true
		elif arg in ["--normal-profile","--playtest"]:
			var profile:String="normal" if arg=="--normal-profile" else "playtest"
			if result.has("new_world_profile") and result.new_world_profile!=profile:return {"ok":false,"code":"CONFLICTING_PROFILE","reason":"请选择一个明确的新世界配置"}
			result.new_world_profile=profile;result.direct=true
		elif arg.begins_with("--seed="):
			var value:String=arg.trim_prefix("--seed=")
			if not value.is_valid_int() or int(value)<0 or int(value)>2147483647:return {"ok":false,"code":"INVALID_SEED","reason":"种子须为0至2147483647的整数"}
			result.seed=int(value)
		elif arg.begins_with("--qa-data-root="):
			var value:String=arg.trim_prefix("--qa-data-root=")
			if result.has("qa_data_root") or not value.is_absolute_path() or value.begins_with("res://") or value.begins_with("user://") or value.simplify_path().trim_suffix("/").is_empty():return {"ok":false,"code":"INVALID_QA_ROOT","reason":"隔离验收目录须为明确的本地绝对路径"}
			result.qa_data_root=value.simplify_path().trim_suffix("/")
	return result

func configure_startup_storage(options:Dictionary)->Dictionary:
	# Opt-in OS acceptance uses the exact shipping Store/controls path, under a
	# marked test directory. Normal startup remains user://. No copy/activation,
	# world mutation, automatic save or test resources are introduced here.
	if not options.has("qa_data_root"):return {"ok":true,"isolated":false}
	var directory:String=options.qa_data_root
	var real_user:String=OS.get_user_data_dir().simplify_path().trim_suffix("/")
	if directory==real_user or directory.begins_with(real_user+"/"):
		return {"ok":false,"code":"INVALID_QA_ROOT","reason":"隔离验收目录不能指向正常用户存档目录"}
	var marker_path:String=directory.path_join("afterglow-qa-root.json")
	if not FileAccess.file_exists(marker_path):return {"ok":false,"code":"INVALID_QA_ROOT","reason":"隔离验收目录缺少明确标记，未更换保存位置"}
	var marker_file:=FileAccess.open(marker_path,FileAccess.READ)
	if marker_file==null:return {"ok":false,"code":"INVALID_QA_ROOT","reason":"无法读取隔离验收目录标记"}
	var size:int=marker_file.get_length()
	if size>4096:marker_file.close();return {"ok":false,"code":"INVALID_QA_ROOT","reason":"隔离验收目录标记超出预算"}
	var marker:Variant=JSON.parse_string(marker_file.get_as_text());marker_file.close()
	if not marker is Dictionary or marker.get("schema")!="afterglow-native-qa-root-v1":return {"ok":false,"code":"INVALID_QA_ROOT","reason":"隔离验收目录标记无效"}
	store=Store.new(directory.path_join("saves"));controls_path=directory.path_join("controls.json")
	_qa_evidence_directory=directory.path_join("metrics")
	print("R3.3 native storage "+JSON.stringify({"isolated":true,"root":directory,"saves":store.root,"controls":controls_path,"rules":"unchanged shipping runtime; explicit marked QA storage only"}))
	return {"ok":true,"isolated":true,"root":directory}

func _context(authority: RefCounted,services: Dictionary,facts: Dictionary,source: Dictionary={},revision: int=0,receipts: Dictionary={},simulation:Dictionary={},content:Dictionary={}) -> Dictionary:
	var definitions: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	return {"world":authority,"services":services,"facts":facts,"source":source,"command_revision":revision,"receipts":receipts,"simulation":simulation,"content":content,"definitions":definitions if definitions is Dictionary else {},"save_state":_save_state,"stream_state":_stream_state,"save_async":save_async,"start_new_world":start_new_world,"start_profiled_world":start_profiled_world,"restore_saved_world":restore_saved_world,"list_recovery_candidates":list_recovery_candidates,"restore_recovery_candidate":restore_recovery_candidate,"import_checkpoint":import_checkpoint,"import_checkpoint_file":import_checkpoint_file,"export_checkpoint_file":export_checkpoint_file,"retry_close":retry_close,"cancel_close":cancel_close}

func _startup_choose_recovery(candidate_id:String,sha256:String)->Dictionary:
	var result:Dictionary=await restore_recovery_candidate(candidate_id,sha256,"startup-recovery")
	if result.ok:_release_startup_recovery()
	else:
		# Re-scan read-only after a stale/failed selection. Keep the failure and
		# require another explicit choice; never auto-select a different world.
		var scan:Dictionary=store.list_recovery_candidates()
		result.candidates=scan.get("candidates",[])
		result.scan=scan.get("scan",{})
	return result

func _startup_fresh()->Dictionary:
	var result:Dictionary=await start_new_world(-1,"startup-fresh")
	if result.ok:_release_startup_recovery()
	return result

func _release_startup_recovery()->void:
	if not is_instance_valid(_startup_recovery):return
	var layer:Node=_startup_recovery.get_parent()
	if layer is CanvasLayer and layer.name=="RecoveryInterface":layer.queue_free()
	else:_startup_recovery.queue_free()
	_startup_recovery=null

func list_recovery_candidates(expected_world_id:String="")->Dictionary:
	return store.list_recovery_candidates(expected_world_id)

func restore_recovery_candidate(candidate_id:String,sha256:String,request_id:String="")->Dictionary:
	if _saving or _world_loading or _closing or _streaming:return _file_receipt({"ok":false,"code":"BUSY","reason":"保存或装配进行中"},request_id)
	var old_paused:bool=runtime.is_paused() if runtime!=null else false
	_world_loading=true;_saving=true
	if runtime!=null:runtime.set_paused(true)
	if router!=null:router.set_closing(true)
	_save_state.merge({"busy":true,"status":"loading","reason":"正在装配所选恢复档，原现场与索引保留"},true)
	await _stage_feedback("read","读取所选村庄","正在校验明确选择的恢复档和原始字节。")
	var loaded:Dictionary=store.load_recovery_candidate(candidate_id,sha256)
	if not loaded.ok:return _new_world_finished(loaded,request_id,old_paused)
	await _stage_feedback("assemble","恢复所选村庄","正在恢复原有物资、人物与地区依赖。")
	var assembly:Dictionary=await _assemble_async(loaded.capture)
	if not assembly.ok:return _new_world_finished(assembly,request_id,old_paused)
	var candidate:Dictionary=await _prepare_mount_ready(loaded.capture,assembly)
	if not candidate.ok:return _new_world_finished(candidate,request_id,old_paused)
	var activated:Dictionary=store.activate_saved(loaded.activation)
	if not activated.ok:
		_discard_candidate(candidate)
		return _new_world_finished(activated,request_id,old_paused)
	var mounted:Dictionary=_activate_scene(candidate)
	_ready_game=true;_fresh_save_required=false
	_test_session=not loaded.capture.get("source",{}).get("playtest",{}).is_empty()
	return _new_world_finished(mounted.merged({"reason":"所选完整存档已明确恢复","candidate_id":candidate_id,"activated":true},true),request_id,false,"restored")

func restore_saved_world(request_id:String="")->Dictionary:
	if _saving or _world_loading or _closing or _streaming:return _file_receipt({"ok":false,"code":"BUSY","reason":"保存或世界装配进行中"},request_id)
	_world_loading=true;_saving=true
	var old_paused:bool=runtime.is_paused() if runtime!=null else false
	if runtime!=null:runtime.set_paused(true)
	if router!=null:router.set_closing(true)
	_save_state.merge({"busy":true,"status":"loading","reason":"正在读取并校验手动保存，原现场保留"},true)
	if runtime!=null:runtime.changed.emit({"save":true})
	await _stage_feedback("read","读取村庄","正在读取并校验手动保存，原现场保留。")
	var read_started:int=Time.get_ticks_usec()
	var worker:=Thread.new()
	var started:int=worker.start(DetachedRead.load_current.bind(store.root))
	if started!=OK:return _new_world_finished({"ok":false,"code":"IO_ERROR","reason":"无法启动存档读取任务，原现场保留"},request_id,old_paused)
	# Yield even a quick read, so the loading state/input gate is observable.
	await get_tree().process_frame
	while worker.is_alive():await get_tree().process_frame
	var loaded:Dictionary=worker.wait_to_finish()
	var read_ms:float=(Time.get_ticks_usec()-read_started)/1000.0
	if _closing:return _new_world_finished({"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场与存档保留"},request_id,old_paused)
	if not loaded.ok:return _new_world_finished(loaded,request_id,old_paused)
	await _stage_feedback("assemble","恢复村庄生活","正在恢复原有库存、人物、工作和地区依赖。")
	var assembled_at:int=Time.get_ticks_usec()
	var built:Dictionary=await _assemble_async(loaded.capture)
	var assembly_ms:float=(Time.get_ticks_usec()-assembled_at)/1000.0
	if not built.ok:return _new_world_finished(built,request_id,old_paused)
	_save_state.reason="正在校验近域几何与物理，原现场保留"
	var candidate:Dictionary=await _prepare_mount_ready(loaded.capture,built)
	if not candidate.ok:return _new_world_finished(candidate,request_id,old_paused)
	# Only publish the exact explicitly read save. A later external write is
	# not permission to rebase this candidate or silently select another one.
	var basis:Dictionary=_current_read_matches(loaded)
	if not basis.ok:
		_discard_candidate(candidate)
		return _new_world_finished(basis,request_id,old_paused)
	var result:Dictionary=_activate_scene(candidate)
	result.read_ms=read_ms;result.assembly_ms=assembly_ms
	print("R3.4 native restore "+JSON.stringify({"read_ms":read_ms,"assembly_ms":assembly_ms,"assembly_costs_usec":built.get("assembly_costs_usec",{}),"scene_costs_usec":candidate.get("scene_costs_usec",{}),"promotion_usec":result.get("promotion_usec",0),"ready_msec":candidate.get("ready_msec",0),"background_read":true,"recovered_slot":loaded.get("recovered",false)}))
	_new_world_finished(result,request_id,false,"restored")
	_fresh_save_required=false
	_test_session=not loaded.capture.get("source",{}).get("playtest",{}).is_empty()
	_ready_game=true
	_save_state.merge({"busy":false,"status":"restored","reason":"已明确恢复上次手动保存；未重新发放工具"},true)
	return _file_receipt(result.merged({"reason":_save_state.reason},true),request_id)

func _current_read_matches(loaded:Dictionary)->Dictionary:
	if _closing:return {"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"}
	var active:=FileAccess.open(store.root+"/active.json",FileAccess.READ)
	if active==null:return {"ok":false,"code":"STALE_ACTIVE","reason":"手动保存索引已改变，原现场与存档保留"}
	if active.get_length()>4096:
		active.close()
		return {"ok":false,"code":"STALE_ACTIVE","reason":"手动保存索引已改变，原现场与存档保留"}
	var active_sha:String=active.get_as_text().sha256_text();active.close()
	if active_sha!=loaded.get("read_active_sha256"):
		return {"ok":false,"code":"STALE_ACTIVE","reason":"手动保存索引已改变，原现场与存档保留"}
	var path:String=str(loaded.get("path",""))
	var source:=FileAccess.open(path,FileAccess.READ) if not path.is_empty() else null
	if source==null:return {"ok":false,"code":"STALE_CANDIDATE","reason":"手动保存内容已改变，原现场与存档保留"}
	var same_length:bool=source.get_length()==loaded.get("source_bytes");source.close()
	if not same_length or FileAccess.get_sha256(path)!=loaded.get("source_sha256"):
		return {"ok":false,"code":"STALE_CANDIDATE","reason":"手动保存内容已改变，原现场与存档保留"}
	return {"ok":true}

func start_profiled_world(profile:String,seed:int=-1,request_id:String="")->Dictionary:
	if profile not in ["normal","playtest"]:return _file_receipt({"ok":false,"code":"INVALID_PROFILE","reason":"请选择正常生存或有限补给试玩"},request_id)
	if _saving or _world_loading or _closing or _streaming:return _file_receipt({"ok":false,"code":"BUSY","reason":"保存或世界装配进行中"},request_id)
	_new_world_profile=profile
	return await start_new_world(seed,request_id)

func start_new_world(seed:int=-1,request_id:String="") -> Dictionary:
	if _saving or _world_loading or _closing or _streaming:return _file_receipt({"ok":false,"code":"BUSY","reason":"保存或世界装配进行中"},request_id)
	if seed==-1:seed=int(randi() & 0x7fffffff)
	if seed<0 or seed>2147483647:return _file_receipt({"ok":false,"code":"INVALID_SEED","reason":"种子须为0至2147483647的整数"},request_id)
	var profile:String=_new_world_profile
	_world_loading=true
	var old_paused:bool=runtime.is_paused() if runtime!=null else false
	if runtime!=null:runtime.set_paused(true)
	if router!=null:router.set_closing(true)
	# A test restart is deliberately ephemeral. Existing explicit saves and
	# their active pointer are untouched, even if generation fails.
	_saving=true
	_save_state.merge({"busy":true,"status":"generating","reason":"正在准备真实地形与聚落，旧档保留"},true)
	if runtime!=null:runtime.changed.emit({"save":true})
	await _stage_feedback("generate","整理山麓农谷","正在按种子准备地形、旧村、道路与真实资源。")
	if _closing:return _new_world_finished({"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"},request_id,old_paused)
	var profiles:Dictionary=FactoryAssembly.generation_profiles()
	if not profiles.ok:return _new_world_finished(profiles,request_id,old_paused)
	var worker:=Thread.new()
	var started:int=worker.start(FactoryAssembly.generate.bind(seed,profiles.profiles))
	if started!=OK:return _new_world_finished({"ok":false,"code":"GENERATION_THREAD","reason":"无法启动世界准备任务"},request_id,old_paused)
	while worker.is_alive():await get_tree().process_frame
	var snapshot:Dictionary=worker.wait_to_finish()
	if _closing:return _new_world_finished({"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"},request_id,old_paused)
	await _stage_feedback("opening","安顿旧村","正在登记真实建筑、有限物资、同伴与开局工具。")
	var prepared:Dictionary=FactoryAssembly.prepare(snapshot)
	if not prepared.ok:return _new_world_finished(prepared,request_id,old_paused)
	prepared.capture=Playtest.prepare_opening(prepared.capture,profile)
	if prepared.capture.get("ok",true)==false:return _new_world_finished(prepared.capture,request_id,old_paused)
	await _stage_feedback("assemble","连接村庄生活","正在校验人物、生产、库存与完整空间关系。")
	var built:Dictionary=await _assemble_async(prepared.capture)
	if not built.ok:return _new_world_finished(built,request_id,old_paused)
	# Assembly validates the new authority without touching any saved world.
	var mounted:Dictionary=await _mount_ready(prepared.capture,built,profile=="playtest",true)
	if not mounted.ok:return _new_world_finished(mounted,request_id,old_paused)
	_ready_game=true
	_fresh_save_required=true;_test_session=profile=="playtest"
	var saved:Dictionary={"ok":true,"code":"OK","reason":"新试玩地图已生成；五工具已随身，仅手动保存" if _test_session else "正常新世界已生成；斧已随身，其他工具与物资来自现场，仅手动保存","profile":profile,"world_id":world.identity().get("worldId",""),"readiness":mounted.get("readiness",{}),"world_epoch":mounted.get("world_epoch",0),"ready_msec":mounted.get("ready_msec",0)}
	return _new_world_finished(saved,request_id,false)

func _new_world_finished(result:Dictionary,request_id:String,paused:bool,status:String="unsaved")->Dictionary:
	_saving=false;_world_loading=false
	_save_state.merge({"busy":false,"status":status if result.ok else "failed","reason":result.get("reason","")},true)
	if runtime!=null:runtime.set_paused(paused);runtime.changed.emit({"save":true})
	if router!=null:router.set_closing(_closing)
	if is_instance_valid(_shell) and not _closing:_shell.show_result(result,runtime!=null)
	if not result.ok and runtime!=null and is_instance_valid(_shell) and not _closing and router!=null:router.set_closing(true)
	return _file_receipt(result,request_id)

func _new_rural(seed: int) -> Dictionary:
	var next_world := World.new()
	var loaded := next_world.load_snapshot(Rural.generate(seed))
	if not loaded.ok:return loaded
	var next_runtime := Runtime.new()
	var buildings := Buildings.new()
	buildings.configure({"world":next_world,"runtime":next_runtime})
	var seeded: Dictionary=buildings.seed_rural(next_world)
	if not seeded.ok:return seeded
	var facts := Initial.facts(seeded)
	var changes: Array=seeded.world_changes.duplicate(true)
	changes.append({"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":Initial.production(seeded)})
	changes.append({"op":"extension.set","id":Gameplay.KEY,"before_exists":false,"before":null,"after":Gameplay.initial()})
	changes.append({"op":"extension.set","id":"r3:structure-orders","before_exists":false,"before":null,"after":{"version":1,"orders":[]}})
	var draft: Dictionary=next_world.prepare_changes(changes,next_world.get_revision())
	if not draft.ok:return draft
	var safe: Dictionary=buildings.validate_world_draft(draft.view,facts,changes)
	if not safe.ok:return safe
	var committed: Dictionary=next_world.commit_prepared(draft.capability)
	if not committed.ok:return committed
	return _mount({"world":next_world.snapshot(),"facts":facts,"source":{"scenario":"rural-home-r33","generator":"rural-1","initial_parameters":"finite R3.3 playtest"},"command_revision":0})

func _assemble(capture:Dictionary)->Dictionary:
	# Synchronous compatibility and probes retain the exact same validated path.
	var built:Dictionary=_assembly_base(capture)
	if not built.ok:return built
	var restored:Dictionary=_assembly_restore_sync(built)
	return _assembly_finish(capture,built) if restored.ok else restored

func _assemble_async(capture:Dictionary)->Dictionary:
	# Only the unpublished candidate is modified. The caller owns the same
	# loading gate; each original C batch/CAS is complete before yielding.
	var built:Dictionary=_assembly_base(capture)
	if not built.ok:return built
	await get_tree().process_frame
	var spent:int=0
	if built.services.has("modules"):
		for id:String in RegionResidency.required_regions(built.runtime):
			if built.world.region(id).is_empty():return _assembly_abort(built,{"ok":false,"code":"MISSING_PINNED_REGION","reason":"保存中的活动依赖地区不存在："+id})
			while not built.world.region_is_resident(id):
				if _closing:return _assembly_abort(built,{"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"})
				var began:int=Time.get_ticks_usec()
				var converted:Dictionary=_assembly_restore_batch(built.world,id)
				spent+=Time.get_ticks_usec()-began
				if not converted.ok:return _assembly_abort(built,converted)
				await get_tree().process_frame
	else:
		var began:int=Time.get_ticks_usec()
		var restored:Dictionary=_assembly_restore_legacy(built.world)
		spent=Time.get_ticks_usec()-began
		if not restored.ok:return _assembly_abort(built,restored)
	built.assembly_costs_usec.required_residency=spent
	if _closing:return _assembly_abort(built,{"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"})
	return _assembly_finish(capture,built)

func _assembly_abort(built:Dictionary,result:Dictionary)->Dictionary:
	built.runtime.retire()
	return result

func _assembly_restore_sync(built:Dictionary)->Dictionary:
	var began:int=Time.get_ticks_usec()
	if built.services.has("modules"):
		for id:String in RegionResidency.required_regions(built.runtime):
			if built.world.region(id).is_empty():return _assembly_abort(built,{"ok":false,"code":"MISSING_PINNED_REGION","reason":"保存中的活动依赖地区不存在："+id})
			while not built.world.region_is_resident(id):
				var converted:Dictionary=_assembly_restore_batch(built.world,id)
				if not converted.ok:return _assembly_abort(built,converted)
	else:
		var restored:Dictionary=_assembly_restore_legacy(built.world)
		if not restored.ok:return _assembly_abort(built,restored)
	built.assembly_costs_usec.required_residency=Time.get_ticks_usec()-began
	return {"ok":true}

func _assembly_restore_batch(next_world:RefCounted,id:String)->Dictionary:
	# Keep the exact existing 32-chunk offscreen restore policy and all checks.
	# The runtime stream's 64 policy is separate; no revision-count change here.
	var conversion:Dictionary=next_world.prepare_region_residency(id,true,next_world.get_revision(),32)
	if not conversion.ok:return conversion
	if conversion.world_changes.is_empty():return {"ok":false,"code":"REGION_RESTORE_STALLED","reason":"保存的地区未能完整回载"}
	var prepared:Dictionary=next_world.prepare_changes_without_view(conversion.world_changes,next_world.get_revision())
	return next_world.commit_prepared(prepared.capability) if prepared.ok else prepared

func _assembly_restore_legacy(next_world:RefCounted)->Dictionary:
	var residency:Array=[]
	for key in next_world.chunk_keys():
		if not next_world.chunk(key).resident:residency.append({"op":"chunk.residency","id":key,"before":false,"after":true})
	if not residency.is_empty():
		var prepared:Dictionary=next_world.prepare_changes_without_view(residency,next_world.get_revision())
		if not prepared.ok:return prepared
		var committed:Dictionary=next_world.commit_prepared(prepared.capability)
		if not committed.ok:return committed
	return {"ok":true}

func _assembly_base(capture:Dictionary)->Dictionary:
	# Validate off-screen before switching any save pointer or visible authority.
	var costs:Dictionary={};var phase_at:int=Time.get_ticks_usec()
	for field:String in ["world","facts","source","receipts","simulation","content"]:
		if not capture.get(field,{}) is Dictionary:return {"ok":false,"code":"INVALID_CHECKPOINT","reason":"装配字段须为对象："+field}
	if not capture.has("world") or not capture.has("facts"):return {"ok":false,"code":"INVALID_CHECKPOINT","reason":"检查点缺少完整世界或角色事实"}
	capture = preload("res://scripts/runtime/tool_wear_policy.gd").restore_on_load(capture)
	var next_world := World.new()
	var loaded: Dictionary=next_world.load_snapshot(capture.world)
	if not loaded.ok:return loaded
	phase_at=_load_phase(costs,"world_load",phase_at)
	var next_runtime := Runtime.new()
	var services := {"buildings":Buildings.new(),"production":Production.new(),"actions":Actions.new(),"terrain":Terrain.new(),"gameplay":Gameplay.new(),"residents":ResidentLife.new()}
	var factory_services:Dictionary=FactoryServices.attach(services,capture)
	if not factory_services.ok:return factory_services
	services=factory_services.services
	phase_at=_load_phase(costs,"service_creation",phase_at)
	var pending_legacy:bool=capture.get("source",{}).get("conversion",{}).get("active_intents")=="pending formal offscreen assembly"
	var incoming:Dictionary=capture.facts.duplicate(true)
	if pending_legacy:
		# Route planning needs the real old actors/world/services, but no legacy
		# intent is allowed to tick before its owner and continuation are valid.
		for actor:Dictionary in incoming.actors:actor.intent=null
	var configured: Dictionary=next_runtime.configure(_context(next_world,services,incoming,capture.get("source",{}),int(capture.get("command_revision",0)),capture.get("receipts",{}),capture.get("simulation",{}),capture.get("content",{})))
	if not configured.ok:return configured
	phase_at=_load_phase(costs,"runtime_configure",phase_at)
	return {"ok":true,"world":next_world,"runtime":next_runtime,"services":services,"assembly_costs_usec":costs}

func _assembly_finish(capture:Dictionary,built:Dictionary)->Dictionary:
	var next_world:RefCounted=built.world;var next_runtime:RefCounted=built.runtime
	var services:Dictionary=built.services;var costs:Dictionary=built.assembly_costs_usec
	var phase_at:int=Time.get_ticks_usec()
	var pending_legacy:bool=capture.get("source",{}).get("conversion",{}).get("active_intents")=="pending formal offscreen assembly"
	if pending_legacy:
		var converted:Dictionary=LegacyIntents.convert(capture,next_runtime,services)
		if not converted.ok:return converted
		var source:Dictionary=capture.get("source",{}).duplicate(true)
		source.conversion.active_intents="adapted once; original intent retained in legacy_extensions"
		source.conversion.activities=converted.activities
		var configured:Dictionary=next_runtime.configure(_context(next_world,services,converted.facts,source,int(capture.get("command_revision",0)),capture.get("receipts",{}),capture.get("simulation",{}),capture.get("content",{})))
		if not configured.ok:return configured
	phase_at=_load_phase(costs,"legacy_intents",phase_at)
	var checked:Dictionary=services.buildings.validate_snapshot(next_world,next_runtime.facts())
	if not checked.ok:return checked
	phase_at=_load_phase(costs,"building_snapshot",phase_at)
	# Referential/schema validity is not proof that a restored body can stand
	# or leave its building. Reuse B's full authority safety once, offscreen,
	# before staging any views or changing the active save pointer.
	var spatial:Dictionary=services.buildings.validate_structures(next_world,services.buildings.structures(next_world),next_runtime.facts())
	if not spatial.ok:return spatial
	_load_phase(costs,"building_space",phase_at)
	return {"ok":true,"world":next_world,"runtime":next_runtime,"services":services,"assembly_costs_usec":costs}

func _load_phase(costs:Dictionary,label:String,started:int)->int:
	# Diagnostic wall time only; no authority, permission or cache decisions.
	var now:int=Time.get_ticks_usec();costs[label]=now-started;return now

func _mount(capture:Dictionary,assembly:Dictionary={},fresh_profile:bool=false) -> Dictionary:
	# Synchronous compatibility hook for low-level fixtures only. Production
	# startup/restore/fresh use _mount_ready and the actual C readiness barrier.
	var built:Dictionary=_assemble(capture) if assembly.is_empty() else assembly
	if not built.ok:return built
	var candidate:Dictionary=_stage_scene(built)
	if not candidate.ok:return candidate
	return _activate_scene(candidate,fresh_profile)

func _stage_scene(built:Dictionary)->Dictionary:
	var costs:Dictionary={};var phase_at:int=Time.get_ticks_usec()
	var next_world:RefCounted=built.world
	var next_runtime:RefCounted=built.runtime
	next_runtime.set_paused(true)
	var root:=Node3D.new();root.name="CandidateWorld";root.visible=false;add_child(root)
	var terrain:Node3D=next_world.create_view({"runtime":next_runtime});root.add_child(terrain)
	terrain.set_loading_budget(true)
	terrain.environment.region_fringe_hint=_region_fringe_hint
	phase_at=_load_phase(costs,"terrain_environment",phase_at)
	var building_view:Node3D=built.services.buildings.create_view({"runtime":next_runtime});root.add_child(building_view)
	phase_at=_load_phase(costs,"legacy_buildings",phase_at)
	var factory_view:Node3D
	if built.services.has("modules"):
		factory_view=FactoryView.new();root.add_child(factory_view);factory_view.configure(next_runtime)
	phase_at=_load_phase(costs,"factory_modules",phase_at)
	var planning_visual:Node3D
	var ecology_visual:Node3D
	if built.services.has("zones"):
		planning_visual=PlanningVisual.new();root.add_child(planning_visual);planning_visual.configure(next_runtime)
	if built.services.has("ecology"):
		ecology_visual=EcologyVisual.new();root.add_child(ecology_visual);ecology_visual.configure(next_runtime)
	phase_at=_load_phase(costs,"regional_visuals",phase_at)
	var actors:=Actors.new();root.add_child(actors);actors.configure(next_runtime)
	phase_at=_load_phase(costs,"actors",phase_at)
	var gameplay_view:=GameplayView.new();root.add_child(gameplay_view);gameplay_view.configure(next_runtime,built.services.buildings)
	var combat_fx := preload("res://scripts/presentation/expedition_effects.gd").new()
	root.add_child(combat_fx)
	combat_fx.configure(next_runtime)
	phase_at=_load_phase(costs,"gameplay",phase_at)
	var next_camera:=Camera3D.new();next_camera.projection=Camera3D.PROJECTION_ORTHOGONAL;next_camera.size=24;next_camera.near=0.1;next_camera.far=180;next_camera.current=false
	root.add_child(next_camera)
	var p:Dictionary=next_runtime.actor("player")
	var focus:=Vector3(p.x,p.y+0.7,p.z)
	next_camera.position=focus+_camera_offset;next_camera.look_at(focus,Vector3.UP)
	var policy:=InteriorViewPolicy.new();policy.configure(built.services.buildings.current_space(),_camera_offset)
	building_view.call("set_view_policy",policy)
	var occlusion:=PlayerOcclusion.new();root.add_child(occlusion);occlusion.configure(next_camera,actors,building_view,terrain.environment)
	_load_phase(costs,"camera_policy",phase_at)
	return {"ok":true,"root":root,"world":next_world,"runtime":next_runtime,"services":built.services,"terrain":terrain,"building_view":building_view,"factory_view":factory_view,"planning_visual":planning_visual,"ecology_visual":ecology_visual,"actors":actors,"camera":next_camera,"policy":policy,"focus":focus,"scene_costs_usec":costs}

func _candidate_readiness(candidate:Dictionary)->Dictionary:
	var points:Array=[]
	for a:Dictionary in candidate.runtime.actor_states():
		if float(a.hp)>0:points.append(Vector3(a.x,a.y,a.z))
	if points.size()>64:return {"ready":false,"fatal":true,"code":"READY_SCOPE_LIMIT","reason":"初始活动角色超过近域装配上限"}
	var terrain:Node3D=candidate.terrain
	var strict:Dictionary=terrain.readiness_near(points,0.32,0.5,1.8)
	if strict.get("code")!=null or not strict.get("unknown",[]).is_empty() or not strict.get("cold",[]).is_empty():
		return strict.merged({"fatal":true,"code":"SPAWN_NOT_READY","reason":"角色身体范围包含未生成或未驻留地形"},true)
	var keys:Dictionary={}
	for key:String in strict.keys:keys[key]=true
	# Camera/tool fringes may extend beyond a finite map. Require every KNOWN
	# chunk there, while the stricter body envelope above may never be unknown.
	var projection:Dictionary=CameraInterest.footprint(candidate.camera,candidate.world,1.0)
	if not projection.ok:return projection.merged({"ready":false,"fatal":true,"reason":"相机地形覆盖尚未就绪"})
	var visible_keys:Array=CameraInterest.known_chunk_keys(candidate.world,projection.rect)
	var uses:Dictionary=terrain.readiness_near(points,2.5,0.5,2.0)
	for list:Array in [visible_keys,uses.get("keys",[])]:
		for key:String in list:
			if candidate.world.chunk_is_generated(key):keys[key]=true
	var result:Dictionary=terrain.readiness(keys.keys())
	result.required_keys=keys.keys();result.body_keys=strict.keys
	result.scope={"live_actors":points.size(),"body_radius":0.32,"tool_radius":2.5,"camera_policy":"actual-frustum-terrain-slab-v1","camera_rect":str(projection.rect),"camera_height_band":[projection.height_min,projection.height_max]}
	return result

func _prime_candidate_camera(candidate:Dictionary)->Dictionary:
	# The SAME scheduler/worker serves the offscreen candidate. Attaching a new
	# epoch drains/discards an old pure-value job; no second generation worker,
	# simulation clock, or published world is created.
	if not candidate.services.has("modules"):return {"ok":true}
	var interest:Dictionary=CameraInterest.footprint(candidate.camera,candidate.world,CAMERA_PREFETCH_METRES)
	if not interest.ok:return interest
	_regions.attach(candidate.runtime,candidate.services.buildings,int(candidate.world_epoch),candidate.services.modules)
	_regions.set_camera_interest(interest.rect)
	var began:int=Time.get_ticks_msec()
	while true:
		if _closing or candidate.world_epoch!=_world_epoch:return {"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"候选相机覆盖准备已取消"}
		if Time.get_ticks_msec()-began>mount_timeout_msec:return {"ok":false,"code":"CAMERA_FRONTIER_TIMEOUT","reason":"可见相邻地形尚未生成完成，原现场保留"}
		var status:Dictionary=_regions.camera_interest_status()
		if is_instance_valid(_shell):_shell.show_evidence("周围乡野准备："+str(status.get("missing",[]).size()))
		if not status.ok:
			if status.get("code")!="GENERATION_CAPACITY":return status
			# A finite-map budget must not make an otherwise valid old save
			# unloadable. Drain an old epoch without committing it, preserve
			# known cells, and expose the real boundary instead of claiming fill.
			while _regions.status().active:
				_regions.poll(0.0,false)
				if Time.get_ticks_msec()-began>mount_timeout_msec:return {"ok":false,"code":"CAMERA_FRONTIER_TIMEOUT"}
				await get_tree().process_frame
			candidate.frontier_boundary=status
			break
		if status.missing.is_empty() and not _regions.status().active:break
		var requested:Dictionary=_regions.request_camera_frontier()
		if not requested.ok:return requested
		var generated:Dictionary=_regions.poll(0.0,true)
		if not generated.is_empty() and not generated.ok:return generated
		await get_tree().process_frame
	# Existing cold pages are restored losslessly; never regenerate their
	# explored cells/dirty edits. This also primes full-body/tool dependencies.
	for id:String in RegionResidency.required_regions(candidate.runtime,18.0,interest.rect):
		while not candidate.world.region_is_resident(id):
			var conversion:Dictionary=candidate.world.prepare_region_residency(id,true,candidate.world.get_revision(),32)
			if not conversion.ok:return conversion
			if conversion.world_changes.is_empty():return {"ok":false,"code":"REGION_RESTORE_STALLED"}
			var prepared:Dictionary=candidate.world.prepare_changes_without_view(conversion.world_changes,candidate.world.get_revision())
			if not prepared.ok:return prepared
			var committed:Dictionary=candidate.world.commit_prepared(prepared.capability)
			if not committed.ok:return committed
			await get_tree().process_frame
	return {"ok":true}

func _prepare_mount_ready(capture:Dictionary,assembly:Dictionary={})->Dictionary:
	if _closing:return {"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"}
	var built:Dictionary=await _assemble_async(capture) if assembly.is_empty() else assembly
	if not built.ok:return built
	_world_epoch+=1
	var epoch:int=_world_epoch
	await _stage_feedback("geometry","修整村庄轮廓","正在装配建筑、乡野地表与人物表现。")
	if _closing:return _assembly_abort(built,{"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"应用正在关闭，原现场保留"})
	var candidate:Dictionary=_stage_scene(built)
	if not candidate.ok:return candidate
	# This candidate is unpublished and already owns the exact same mandatory
	# camera/body/tool + later-physics gate below. Frontier chunk notifications
	# must join its existing staged mesh queue, rather than synchronously build
	# every new and neighboring chunk before the gate can prioritize them.
	candidate.terrain.set_streaming_updates(true)
	# Keep the published image while the candidate prepares, but stop its
	# remaining background terrain/presentation work competing for this frame
	# budget. The world is already gated; rejection restores the exact mode.
	if is_instance_valid(scene_root):
		candidate.source_root=scene_root
		candidate.source_process_mode=scene_root.process_mode
		scene_root.process_mode=Node.PROCESS_MODE_DISABLED
	candidate.world_epoch=epoch
	var started:int=Time.get_ticks_msec()
	await _stage_feedback("frontier","展开周围乡野","正在准备相机覆盖地区和连续可达地形。")
	var camera_ready:Dictionary=await _prime_candidate_camera(candidate)
	if not camera_ready.ok:
		_discard_candidate(candidate)
		return camera_ready
	await _stage_feedback("physics","确认安全落脚","正在核对身体碰撞、建筑入口与近域物理就绪。")
	var revision:int=built.world.get_revision()
	var ready:Dictionary={};var next_readiness_msec:int=0
	while true:
		if _closing or epoch!=_world_epoch or built.world.get_revision()!=revision:
			_discard_candidate(candidate)
			return {"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"世界切换已取消或候选版本变化，原现场保留"}
		# Bodies and camera are stationary in the paused candidate. Polling the
		# full seam/readiness scope on every render frame starves mesh staging.
		# Keep the same strict barrier and current-revision checks at publication.
		if ready.is_empty() or Time.get_ticks_msec()>=next_readiness_msec:
			ready=_candidate_readiness(candidate)
			if is_instance_valid(_shell):_shell.show_evidence("地形准备：%s · 安全落脚检查：%s" % [ready.get("pending",[]).size(),ready.get("awaiting_physics",[]).size()])
			candidate.terrain.prioritize(ready.get("pending",[]))
			next_readiness_msec=Time.get_ticks_msec()+50
		if ready.get("fatal",false) or Time.get_ticks_msec()-started>mount_timeout_msec:
			_discard_candidate(candidate)
			return {"ok":false,"code":ready.get("code","WORLD_READY_TIMEOUT"),"reason":ready.get("reason","近域几何或物理未按时就绪，原现场保留"),"readiness":ready}
		if ready.get("ready",false):
			if candidate.actors.has_method("assembly_report"):
				var report:Dictionary=candidate.actors.assembly_report()
				if not report.get("ok",false):
					_discard_candidate(candidate)
					return {"ok":false,"code":"ACTOR_ASSEMBLY_FAILED","reason":"角色必需资源装配失败，原现场保留","assembly_report":report}
			candidate.terrain.set_loading_budget(false)
			candidate.readiness=ready;candidate.world_epoch=epoch;candidate.ready_msec=Time.get_ticks_msec()-started
			return candidate
		await get_tree().process_frame
	return {"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"世界切换未完成"}

func _discard_candidate(candidate:Dictionary)->void:
	if candidate.get("runtime")!=null:candidate.runtime.retire()
	if is_instance_valid(candidate.get("terrain")) and candidate.terrain.has_method("cancel_pending"):candidate.terrain.cancel_pending()
	if is_instance_valid(candidate.get("root")):
		remove_child(candidate.root);candidate.root.queue_free()
	if is_instance_valid(candidate.get("source_root")) and candidate.source_root==scene_root:
		scene_root.process_mode=candidate.source_process_mode
	# A rejected candidate must not leave the shared scheduler attached to its
	# retired authority. Restore only the still-published original world.
	if runtime!=null:
		_regions.attach(runtime,runtime._services.buildings,_world_epoch,runtime._services.get("modules"))
		if is_instance_valid(camera):
			var interest:Dictionary=CameraInterest.footprint(camera,world,CAMERA_PREFETCH_METRES)
			if interest.ok:_regions.set_camera_interest(interest.rect)
	else:_regions.cancel()

func _mount_ready(capture:Dictionary,assembly:Dictionary={},fresh_profile:bool=false,fresh_opening:bool=false)->Dictionary:
	var candidate:Dictionary=await _prepare_mount_ready(capture,assembly)
	if not candidate.ok:return candidate
	var result:Dictionary=_activate_scene(candidate,fresh_profile,fresh_opening)
	if result.ok:_ready_game=true
	return result

func _activate_scene(candidate:Dictionary,fresh_profile:bool=false,fresh_opening:bool=false)->Dictionary:
	candidate.terrain.set_loading_budget(false)
	var promoted_at:int=Time.get_ticks_usec()
	# All fallible authority/geometry/asset checks ran before this synchronous
	# promotion. No yield occurs between retiring old input and binding new UI.
	if interaction!=null:interaction.set_process(false);interaction.queue_free();interaction=null
	if router!=null:router.set_closing(true);router.queue_free();router=null
	if ui!=null:ui.get_parent().queue_free();ui=null
	if scene_root!=null:
		scene_root.process_mode=Node.PROCESS_MODE_DISABLED
		remove_child(scene_root);scene_root.queue_free()
	if runtime!=null:runtime.retire()
	world=candidate.world;runtime=candidate.runtime;scene_root=candidate.root
	_stream_checkpoint_listen()
	_frontier_limit_code=""
	_terrain_view=candidate.terrain
	scene_root.name="PersistentWorld";scene_root.visible=true
	_lighting()
	_residency.attach(runtime)
	_stream_store=Store.new(store.root.get_base_dir().path_join("stream-cache").path_join(str(world.identity().worldId).sha256_text().substr(0,24)))
	var metrics:=NativePerformance.new();scene_root.add_child(metrics);metrics.configure(runtime,_region_status,_terrain_view.statistics,_qa_evidence_directory)
	camera=candidate.camera;camera.make_current();_camera_focus=candidate.focus
	if DisplayServer.get_name() != "headless": runtime.set_night_screen_test(_night_point_visible)
	_interior_view_policy=candidate.policy
	router=Router.new();router.controls_path=controls_path;add_child(router);router.configure(runtime,fresh_profile,fresh_opening)
	ui=Ui.mount(self,runtime,router)
	var planning_visual:Variant=candidate.get("planning_visual")
	if planning_visual!=null:planning_visual.configure_planning(ui)
	# Assembly pauses the candidate. Input reasons govern the promoted world,
	# including startup --continue, which has no later new-world completion.
	runtime.set_paused(router.is_paused())
	interaction=Interaction.new();add_child(interaction);interaction.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":candidate.services.buildings,"modules":candidate.services.get("modules"),"terrain":candidate.terrain,"ui":ui,"view_policy":_interior_view_policy})
	var world_hints:Variant=candidate.get("factory_view")
	if world_hints!=null and world_hints.has_method("configure_view_hints"):
		world_hints.call("configure_view_hints",interaction)
	# Production promotion has already passed the physical-frame barrier. The
	# synchronous fixture-only hook retains synchronous edit compatibility.
	if candidate.has("readiness"):
		_terrain_view.set_budgeted_edits(true)
		_terrain_view.set_streaming_updates(true)
		candidate.building_view.set_staged_generation(true)
		candidate.factory_view.set_staged_generation(true)
		runtime.bind_readiness(_runtime_readiness)
		_regions.attach(runtime,candidate.services.buildings,_world_epoch,candidate.services.get("modules"))
		var interest:Dictionary=CameraInterest.footprint(camera,world,CAMERA_PREFETCH_METRES)
		if interest.ok:_regions.set_camera_interest(interest.rect)
	else:_regions.cancel()
	router.zoom_requested.connect(func(amount:float):camera.size=clampf(camera.size+amount*1.5,12,40))
	return {"ok":true,"code":"OK","world_epoch":candidate.get("world_epoch",0),"ready_msec":candidate.get("ready_msec",0),"readiness":candidate.get("readiness",{}),"promotion_usec":Time.get_ticks_usec()-promoted_at}

func _lighting() -> void:
	_settlement_lights = SceneLighting.mount(scene_root)
	_night_tint = 0.0
	_night_tint_goal = 0.0
	_night_light_poll = 0.0

func _runtime_readiness(request:Dictionary={})->Dictionary:
	if not is_instance_valid(_terrain_view):return {"ok":false,"ready":false,"code":"NOT_READY","reason":"地形视图尚未装配"}
	var points:Array=runtime.active_positions()
	if request.get("kind")=="direct_move" and request.get("destination") is Dictionary:
		var destination:Dictionary=request.destination
		if destination.has_all(["x","y","z"]):points.append(Vector3(destination.x,destination.y,destination.z))
	var keys:Dictionary={}
	# Unknown tool fringes at finite boundaries are excluded; actual body
	# support/obstacles remain governed by B's exact authority queries.
	# Enumerate once before filtering finite fringes. This is not a readiness
	# permit: prioritize and the current geometry/physics gate still run below.
	var near:Dictionary=_terrain_view.readiness_keys_near(points,2.5,0.5,2.0) if _terrain_view.has_method("readiness_keys_near") else _terrain_view.readiness_near(points,2.5,0.5,2.0)
	if near.get("ok",true)==false or not near.has("keys"):
		return near.merged({"ok":false,"ready":false,"reason":"地形就绪范围无效，等待有效身体位置"},true)
	for key:String in near.get("keys",[]):
		if world.chunk_is_generated(key):keys[key]=true
	var ready:Dictionary=_terrain_view.readiness(keys.keys())
	# The current readiness pass already identifies exactly the unfinished
	# keys in caller order. Re-prioritizing ready keys repeats every seam
	# proof on every step; pending keys alone produce the identical queue.
	_terrain_view.prioritize(ready.get("pending",[]))
	return ready.merged({"ok":ready.ready,"code":"OK" if ready.ready else "NOT_READY","reason":"" if ready.ready else "附近地形正在更新，几何与碰撞就绪后继续","scope":"all living body/tool neighborhoods; whole fixed step is atomic"},true)

func _process(delta: float) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("runtime/native_client.gd",measured)

func _night_point_visible(point: Vector3) -> bool:
	if not is_instance_valid(camera): return true
	var bounds := camera.get_viewport().get_visible_rect().grow(48.0)
	return bounds.has_point(camera.unproject_position(point)) or bounds.has_point(camera.unproject_position(point+Vector3.UP*1.8))

func _profiled_process(delta: float) -> void:
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var phase:int=Costs.begin()
	var can_stream:bool=_ready_game and not _world_loading and not _saving and not _closing and not _streaming and runtime!=null and not runtime.is_paused()
	var interest:Dictionary=CameraInterest.footprint(camera,world,CAMERA_PREFETCH_METRES) if _ready_game and not _world_loading and is_instance_valid(camera) else {"ok":false}
	if interest.ok:_regions.set_camera_interest(interest.rect)
	var publication_started := Time.get_ticks_usec()
	var publication: Dictionary = _regions.poll(delta,can_stream)
	if publication.has("presentation_fringe") and is_instance_valid(_terrain_view):
		_terrain_view.environment.accept_generation_fringe(str(publication.region_id), publication.presentation_fringe)
	if can_stream:
		var coverage:Dictionary=_regions.camera_interest_status()
		var limit:String=str(coverage.get("code","")) if not coverage.ok else ""
		if limit!=_frontier_limit_code:
			_frontier_limit_code=limit
			if limit=="GENERATION_CAPACITY" and ui!=null:ui.notify("已到达本版有限地图准备范围；现有地区和存档保留，边界外暂不可通行")
	var request:Dictionary=_residency.poll(delta,can_stream,18.0,interest.get("rect",Rect2()))
	if not request.is_empty():_change_residency(request)
	Costs.end("native/stream_poll",phase)
	if not _ready_game or _world_loading:return
	phase=Costs.begin()
	# Generation still commits in one transaction. When it consumes a full
	# frame, avoid stacking the first simulation step on the same frame.
	var generated: bool = publication.get("ok", false) == true and not publication.get("already_generated", false)
	var defer_steps: bool = generated and Time.get_ticks_usec() - publication_started >= 16_667
	runtime.tick(delta, defer_steps)
	Costs.end("native/fixed_steps",phase)
	phase=Costs.begin()
	_camera_update(delta)
	_update_night_light(delta)
	Costs.end("native/camera",phase)

func _region_fringe_hint(view_world:RefCounted,region_id:String)->Variant:
	return _regions.publication_fringe(view_world,_world_epoch,region_id)

func _region_status()->Dictionary:
	return _regions.status().merged({"residency":_residency.status(),"streaming":_stream_state.duplicate(true)})

func _residency_checkpoint_basis(capture:Dictionary,id:String)->Dictionary:
	# Reuse C's authoritative chunk revisions. This is a detached save basis,
	# never a second world or a cached permission to evict a region.
	var chunks:Dictionary={}
	for key:String in world.region_chunk_keys(id):
		var chunk:Dictionary=capture.world.chunks.get(key,{})
		chunks[key]={"revision":chunk.get("revision"),"resident":chunk.get("resident")}
	return {"epoch":_world_epoch,"world_id":capture.world.worldId,"region":capture.world.regions.get(id,{}).duplicate(true),"chunks":chunks}

func _residency_checkpoint_matches(basis:Dictionary,id:String)->bool:
	if basis.get("epoch")!=_world_epoch or basis.get("world_id")!=world.identity().worldId:return false
	if not WorldData.json_equal(basis.get("region",{}),world.region(id)):return false
	var keys:Array=world.region_chunk_keys(id)
	if keys.is_empty() or keys.size()!=basis.get("chunks",{}).size():return false
	for key:String in keys:
		if not basis.chunks.has(key):return false
		var current:Dictionary=world.chunk_metadata(key)
		if current.get("revision")!=basis.chunks[key].revision or current.get("resident")!=basis.chunks[key].resident:return false
	return true

func _stream_checkpoint_listen()->void:
	if _stream_checkpoint_runtime==runtime:return
	if _stream_checkpoint_runtime!=null and _stream_checkpoint_runtime.changed.is_connected(_stream_checkpoint_changed):_stream_checkpoint_runtime.changed.disconnect(_stream_checkpoint_changed)
	_stream_checkpoint={};_stream_checkpoint_runtime=runtime
	runtime.changed.connect(_stream_checkpoint_changed)

func _stream_checkpoint_changed(change:Dictionary)->void:
	if _stream_checkpoint.is_empty():return
	var ops:Array=change.get("world",[])
	var expected:int=int(_stream_checkpoint.revision)+(0 if ops.is_empty() else 1)
	# A world write outside Runtime, an unknown op, or any semantic extension
	# change invalidates the reuse proof. Only our own lossless storage CAS and
	# the explicitly derived display extension may advance this observer.
	if world.get_revision()!=expected:
		_stream_checkpoint={};return
	for op:Dictionary in ops:
		if op.get("op")=="extension.set" and op.get("id")=="r34:display":continue
		if _stream_storage_commit and op.get("op") in ["chunk.storage","chunk.residency"]:continue
		_stream_checkpoint={};return
	_stream_checkpoint.revision=expected

func _stream_checkpoint_capture(capture:Dictionary)->void:
	var regions:Dictionary={}
	for id:String in capture.world.regions:
		var entities:Array=[]
		for entity_id:String in capture.world.entities:
			var entity:Dictionary=capture.world.entities[entity_id]
			if entity.get("regionId")==id:entities.append(entity.duplicate(true))
		regions[id]={"basis":_residency_checkpoint_basis(capture,id),"entities":entities,"actors":capture.facts.actors.filter(func(a:Dictionary)->bool:return a.get("regionId")==id).duplicate(true)}
	_stream_checkpoint={"regions":regions,"stocks":capture.facts.stocks.duplicate(true),"token":world.extension_token(""),"revision":world.get_revision(),"receipt":{}}

func _stream_checkpoint_matches(id:String)->bool:
	if _stream_checkpoint.is_empty() or _stream_checkpoint.receipt.is_empty() or not _stream_checkpoint.regions.has(id):return false
	if _stream_checkpoint.token!=world.extension_token("") or _stream_checkpoint.revision!=world.get_revision():return false
	var protected:Dictionary=_stream_checkpoint.regions[id]
	if not _residency_checkpoint_matches(protected.basis,id):return false
	if not WorldData.json_equal(protected.entities,world.entities(id)):return false
	if not WorldData.json_equal(_stream_checkpoint.stocks,runtime.stock_states()):return false
	return WorldData.json_equal(protected.actors,runtime.actor_states().filter(func(a:Dictionary)->bool:return a.get("regionId")==id))

static func _verify_stream_checkpoint(receipt:Dictionary,directory:String,world_id:String)->Dictionary:
	# Detached IO only. Hash the exact already-validated complete slot, and
	# compare its active receipt; existence or a matching timestamp is no proof.
	if not receipt.get("ok",false) or not receipt.get("activated",false) or str(receipt.get("sha256","")).length()!=64:return {"ok":false}
	var file:=FileAccess.open(directory+"/active.json",FileAccess.READ)
	if file==null:return {"ok":false}
	if file.get_length()>4096:file.close();return {"ok":false}
	var pointer:Variant=JSON.parse_string(file.get_as_text());file.close()
	var expected:Dictionary={"namespace":receipt.get("namespace"),"slot":receipt.get("slot"),"checkpoint_id":receipt.get("checkpoint_id"),"world_id":world_id,"sha256":receipt.get("sha256")}
	if not WorldData.json_equal(pointer,expected):return {"ok":false}
	return {"ok":FileAccess.get_sha256(str(receipt.get("path","")))==receipt.get("sha256")}

func _residency_conversion_matches(basis:Dictionary,id:String,epoch:int)->bool:
	if epoch!=_world_epoch or not WorldData.json_equal(basis.get("identity",{}),world.identity()) or not WorldData.json_equal(basis.get("config",{}),world.config()):return false
	if not WorldData.json_equal(basis.get("region",{}),world.region(id)):return false
	var keys:Array=world.region_chunk_keys(id)
	if keys.is_empty() or keys.size()!=basis.get("chunks",{}).size():return false
	for key:String in keys:
		if not basis.chunks.has(key):return false
		var current:Dictionary=world.chunk_metadata(key);var guard:Dictionary=basis.chunks[key]
		if current.get("revision")!=guard.get("revision") or current.get("resident")!=guard.get("resident") or current.get("generated")!=guard.get("generated") or current.get("has_page")!=guard.get("has_page"):return false
	return true

func _residency_batch_limit()->int:
	# A's single policy point; test clients can compare bounded strategies
	# through the same Native owner. This is not a gameplay/user setting.
	return RESIDENCY_BATCH_CHUNKS

func _change_residency(plan:Dictionary)->Dictionary:
	if _streaming or _saving or _world_loading or _closing or runtime==null:return {"ok":false,"code":"BUSY"}
	var batch_limit:int=_residency_batch_limit()
	if batch_limit<1 or batch_limit>256:return {"ok":false,"code":"RESIDENCY_BUDGET"}
	var id:String=str(plan.region_id);var warm:bool=plan.resident
	var began:int=Time.get_ticks_usec()
	var interest:Dictionary=CameraInterest.footprint(camera,world,CAMERA_PREFETCH_METRES) if is_instance_valid(camera) else {"ok":false}
	var pins:Dictionary=RegionResidency.required_regions(runtime,18.0,interest.get("rect",Rect2()))
	if not warm and pins.has(id):return {"ok":false,"code":"REGION_PINNED"}
	_streaming=true
	# A detached checkpoint can encode/write while the real world keeps
	# running, just like manual save_async. Detached page conversion also
	# runs without a gate; only each synchronous CAS takes a short barrier.
	_stream_state.merge({"busy":false,"checkpointing":not warm,"preparing_data":false,"region_id":id,"resident":warm},true)
	var result:Dictionary={"ok":true,"code":"OK","state_before":world.region_residency_state(id)}
	var checkpoint_sha:String=""
	var checkpoint_reused:=false
	var checkpoint_basis:Dictionary={}
	var checkpoint_ms:float=0.0
	var data_ready_ms:float=0.0
	var barrier_ms:float=0.0
	var max_barrier_ms:float=0.0
	var barrier_batches_ms:Array[float]=[]
	var barrier_phases_ms:Dictionary={}
	var capture_usec:int=0
	var worker_usec:int=0
	if not warm:
		_stream_checkpoint_listen()
		if _stream_checkpoint_matches(id):
			var verify:=Thread.new()
			var verify_started:int=verify.start(_verify_stream_checkpoint.bind(_stream_checkpoint.receipt.duplicate(true),ProjectSettings.globalize_path(_stream_store.root),str(world.identity().worldId)))
			if verify_started==OK:
				while verify.is_alive():await get_tree().process_frame
				var verified:Dictionary=verify.wait_to_finish()
				if verified.ok and _stream_checkpoint_matches(id):
					checkpoint_basis=_stream_checkpoint.regions[id].basis.duplicate(true)
					checkpoint_sha=str(_stream_checkpoint.receipt.sha256);checkpoint_reused=true
		if not checkpoint_reused:
			_stream_checkpoint={}
			# Independent two-slot working checkpoint. Never switches the user's
			# explicit save namespace or presents this as a manual player save.
			var capture:Dictionary=runtime.capture_checkpoint()
			checkpoint_basis=_residency_checkpoint_basis(capture,id)
			_stream_checkpoint_capture(capture)
			var started:Dictionary=_stream_store.begin_save(capture)
			# The worker owns this dictionary until completion; drop only our local
			# reference, never clear the object passed to Thread.start.
			capture={}
			if not started.ok:result=started;_stream_checkpoint={}
			else:
				var saved:Dictionary={}
				while saved.is_empty():
					await get_tree().process_frame
					saved=_stream_store.poll()
				if not saved.ok:result=saved;_stream_checkpoint={}
				else:
					checkpoint_sha=str(saved.sha256)
					if not _stream_checkpoint.is_empty():_stream_checkpoint.receipt=saved.duplicate(true)
		checkpoint_ms=(Time.get_ticks_usec()-began)/1000.0
		# The player/NPCs may have approached, or a legitimate edit may have
		# changed the saved region during IO. Recheck current facts, not the
		# old pin set; refuse before any page is released if the basis is stale.
		if result.ok:
			interest=CameraInterest.footprint(camera,world,CAMERA_PREFETCH_METRES) if is_instance_valid(camera) else {"ok":false}
			pins=RegionResidency.required_regions(runtime,18.0,interest.get("rect",Rect2()))
			if pins.has(id):result=result.merged({"ok":false,"code":"REGION_PINNED","reason":"地区已成为实际活动依赖，保留原数据"},true)
			elif not _residency_checkpoint_matches(checkpoint_basis,id):result=result.merged({"ok":false,"code":"RESIDENCY_STALE","reason":"地区在保存期间已改变，保留原数据稍后重试"},true)
	_stream_state.checkpointing=false
	var batches:int=0
	while result.ok:
		var epoch:int=_world_epoch
		var captured:Dictionary=world.capture_region_residency(id,warm,world.get_revision(),batch_limit)
		if not captured.ok:result=captured;break
		capture_usec+=int(captured.cost.capture_usec)
		var worker:=Thread.new()
		_stream_state.preparing_data=true
		# This pure static worker owns only detached values. Do not bind the
		# live world, read its guards or mutate the DTO until after the join.
		var started:int=worker.start(World.prepare_detached_region_residency.bind(captured.input))
		if started!=OK:result={"ok":false,"code":"RESIDENCY_THREAD","reason":"未能启动地形数据准备"};break
		await get_tree().process_frame
		while worker.is_alive():await get_tree().process_frame
		var converted:Dictionary=worker.wait_to_finish()
		captured={};_stream_state.preparing_data=false
		if not converted.ok:result=converted;break
		worker_usec+=int(converted.cost.prepare_usec)
		# The simulation may have changed while the pure worker was running.
		# Accept unrelated revisions, never a stale target or a newly live pin.
		interest=CameraInterest.footprint(camera,world,CAMERA_PREFETCH_METRES) if is_instance_valid(camera) else {"ok":false}
		pins=RegionResidency.required_regions(runtime,18.0,interest.get("rect",Rect2()))
		if not warm and pins.has(id):result=result.merged({"ok":false,"code":"REGION_PINNED","reason":"地区已成为实际活动依赖，保留原数据"},true);break
		if not _residency_conversion_matches(converted.basis,id,epoch) or not warm and (not _residency_checkpoint_matches(checkpoint_basis,id) or checkpoint_reused and not _stream_checkpoint_matches(id)):result=result.merged({"ok":false,"code":"RESIDENCY_STALE","reason":"地区在后台准备期间已改变，保留原数据稍后重试"},true);break
		if not converted.world_changes.is_empty():
			var before_costs:Dictionary=runtime.authority_costs().get("phases",{})
			var barrier_started:int=Time.get_ticks_usec()
			var storage_revision:int=world.get_revision()+1
			# No yield under this gate. Original op.before and all Runtime owner,
			# safety and content validators still run against the current revision.
			_stream_state.busy=true
			_stream_storage_commit=true
			var committed:Dictionary=runtime.commit_storage_projection({"world_changes":converted.world_changes,"events":[{"kind":"region-storage-changed","region_id":id,"resident":warm}]})
			_stream_storage_commit=false
			_stream_state.busy=false
			var interval:float=(Time.get_ticks_usec()-barrier_started)/1000.0
			barrier_batches_ms.append(interval)
			barrier_ms+=interval;max_barrier_ms=maxf(max_barrier_ms,interval)
			var after_costs:Dictionary=runtime.authority_costs().get("phases",{})
			for phase:String in ["world_prepare","final_spatial_validation","world_commit","publish_and_views"]:
				var elapsed_usec:int=int(after_costs.get(phase,{}).get("total_usec",0))-int(before_costs.get(phase,{}).get("total_usec",0))
				if not barrier_phases_ms.has(phase):barrier_phases_ms[phase]=[]
				barrier_phases_ms[phase].append(elapsed_usec/1000.0)
			if not committed.ok:result=committed;break
			if not warm:
				# Advance only the metadata changed by OUR successful storage CAS.
				# Never absorb arbitrary target edits into the saved-data baseline.
				for change:Dictionary in converted.world_changes:
					checkpoint_basis.chunks[change.id]={"revision":storage_revision,"resident":change.after.resident}
			# Advance only our known storage metadata in the optional reuse proof.
			if not _stream_checkpoint.is_empty() and _stream_checkpoint.regions.has(id):
				for change:Dictionary in converted.world_changes:
					_stream_checkpoint.regions[id].basis.chunks[change.id]={"revision":storage_revision,"resident":change.after.resident}
		batches+=1
		if converted.complete:break
		if batches>256:result={"ok":false,"code":"RESIDENCY_BUDGET","reason":"地区转换超出本轮有界批次，原事实保留"};break
	data_ready_ms=(Time.get_ticks_usec()-began)/1000.0
	if result.ok and warm and is_instance_valid(_terrain_view):
		# The saved data is restored. Build the distant meshes/colliders under
		# C's budget while existing ready space remains playable; exact body
		# readiness still prevents entering an unfinished neighboring surface.
		_stream_state.busy=false;_stream_state.preparing_geometry=true
		var keys:Array=world.region_chunk_keys(id)
		_terrain_view.prioritize(keys)
		var geometry_ready:Dictionary=_terrain_view.readiness(keys)
		var geometry_frames:int=0
		var geometry_checks:int=1
		var next_geometry_check:int=Time.get_ticks_msec()+50
		while not geometry_ready.get("ready",false):
			if (Time.get_ticks_usec()-began)/1000>mount_timeout_msec:result={"ok":false,"code":"REGION_PHYSICS_TIMEOUT","reason":"地形已恢复，几何或碰撞尚未就绪"};break
			await get_tree().process_frame
			geometry_frames+=1
			# The same 256-key seam proof on every render frame competes with the
			# mesh queue it is waiting for. As during candidate startup, poll a
			# current full geometry+later-physics gate at a bounded 50ms interval.
			# A ready response exits synchronously; no old permit crosses a yield.
			if Time.get_ticks_msec()>=next_geometry_check:
				geometry_ready=_terrain_view.readiness(keys)
				geometry_checks+=1
				_terrain_view.prioritize(geometry_ready.get("pending",[]))
				next_geometry_check=Time.get_ticks_msec()+50
		# Read-only endpoint evidence distinguishes unfinished mesh work from a
		# physics registration wait. Never relax the original current ready gate.
		var geometry_summary:Dictionary={"required":keys.size(),"frames":geometry_frames,"checks":geometry_checks,"ready":geometry_ready.get("ready",false),"view_epoch":geometry_ready.get("view_epoch",-1),"world_revision":geometry_ready.get("world_revision",-1)}
		for category:String in ["pending","unknown","cold","awaiting_physics"]:
			var entries:Array=geometry_ready.get(category,[])
			geometry_summary[category+"_count"]=entries.size()
			geometry_summary[category+"_sample"]=entries.slice(0,8)
		result.geometry_readiness=geometry_summary
		result.geometry_statistics=_terrain_view.statistics()
	result.state_after=world.region_residency_state(id)
	result.checkpoint_sha256=checkpoint_sha;result.elapsed_ms=(Time.get_ticks_usec()-began)/1000.0
	result.checkpoint_ms=checkpoint_ms;result.checkpoint_reused=checkpoint_reused;result.barrier_ms=barrier_ms;result.max_barrier_ms=max_barrier_ms
	result.barrier_batches_ms=barrier_batches_ms
	result.barrier_phases_ms=barrier_phases_ms
	result.batches=batches;result.batch_chunks=batch_limit;result.capture_usec=capture_usec;result.worker_usec=worker_usec
	_stream_state.busy=false;_stream_state.checkpointing=false;_stream_state.preparing_data=false;_stream_state.preparing_geometry=false;_streaming=false
	_residency.finish(plan,result)
	print("R3.4 native residency "+JSON.stringify({"region_id":id,"resident":warm,"ok":result.ok,"code":result.get("code","OK"),"batches":batches,"batch_chunks":batch_limit,"before":result.get("state_before",{}),"after":result.state_after,"checkpoint_sha256":checkpoint_sha,"checkpoint_ms":checkpoint_ms,"barrier_ms":barrier_ms,"max_barrier_ms":max_barrier_ms,"capture_usec":capture_usec,"worker_usec":worker_usec,"data_ready_ms":data_ready_ms,"geometry_wait_ms":maxf(0.0,float(result.elapsed_ms)-data_ready_ms),"elapsed_ms":result.elapsed_ms,"geometry_readiness":result.get("geometry_readiness",{}),"geometry_statistics":result.get("geometry_statistics",{})}))
	if not result.ok and result.get("code") not in ["REGION_PINNED","RESIDENCY_STALE"] and ui!=null:ui.notify(str(result.get("reason","地区数据尚未就绪，原事实保留")),true)
	return result

func _exit_tree()->void:
	_regions.shutdown()

func _camera_update(delta: float) -> void:
	var p: Dictionary=runtime.actor("player")
	var target := Vector3(p.x,p.y+0.7,p.z)
	_camera_focus=target if delta<=0 else _camera_focus.lerp(target,1-exp(-delta*8))
	camera.position=_camera_focus+_camera_offset;camera.look_at(_camera_focus,Vector3.UP)

func save_async(request_id: String="") -> Dictionary:
	if _saving or _streaming:return _file_receipt({"ok":false,"code":"BUSY","reason":"正在保存或转换地区"},request_id)
	_saving=true;_save_state.merge({"busy":true,"status":"saving","reason":"正在校验并写入完整世界"},true);runtime.changed.emit({"save":true})
	if is_instance_valid(_shell) and router!=null:router.set_closing(true)
	await _stage_feedback("save","保存后安全退出" if _closing else "保存村庄","正在校验并写入完整世界；收到写入成功回执后才完成。")
	var captured := Time.get_ticks_usec()
	var capture: Dictionary=runtime.capture_checkpoint()
	var capture_ms: float=(Time.get_ticks_usec()-captured)/1000.0
	var started: Dictionary=store.begin_save(capture,_fresh_save_required)
	if not started.ok:
		_saving=false;_save_state.merge({"busy":false,"status":"failed","reason":started.reason},true)
		if is_instance_valid(_shell) and not _closing:_shell.show_result(started,true)
		elif router!=null:router.set_closing(_closing)
		return _file_receipt(started,request_id)
	var result: Dictionary={}
	while result.is_empty():
		await get_tree().process_frame
		result=store.poll()
	_saving=false;_save_state.merge({"busy":false,"status":"saved" if result.ok else "failed","reason":result.get("reason","")},true)
	if result.ok:_fresh_save_required=false
	result.capture_ms=capture_ms
	print("R3.3 native save "+JSON.stringify(result))
	runtime.changed.emit({"save":true})
	if is_instance_valid(_shell) and not _closing:_shell.show_result(result.merged({"reason":"村庄已完整保存。" if result.ok else result.get("reason","")},true),true)
	if router!=null and (result.ok or not is_instance_valid(_shell)):router.set_closing(_closing)
	return _file_receipt(result,request_id)

func import_checkpoint_file(path: String,request_id: String="") -> Dictionary:
	var read: Dictionary=store.read_file(path)
	if not read.ok:return _file_receipt(read,request_id)
	return await import_checkpoint(read.text,request_id)

func import_checkpoint(text: String,request_id: String="") -> Dictionary:
	if _saving or _world_loading or _closing or _streaming:return _file_receipt({"ok":false,"code":"BUSY","reason":"保存或世界装配进行中"},request_id)
	var old_paused:bool=runtime.is_paused() if runtime!=null else false
	_saving=true;_world_loading=true
	if runtime!=null:runtime.set_paused(true)
	if router!=null:router.set_closing(true)
	_save_state.merge({"busy":true,"status":"loading","reason":"导入候选正在校验；当前世界和存档仍保留"},true)
	if runtime!=null:runtime.changed.emit({"save":true})
	await _stage_feedback("read","校验导入村庄","正在解码并验证候选；通过全部校验后才切换。")
	var decoded:Dictionary=Store.decode(text)
	if not decoded.ok:return _new_world_finished(decoded,request_id,old_paused)
	await _stage_feedback("assemble","连接导入村庄","正在校验人物、库存与完整空间关系。")
	var assembly:Dictionary=await _assemble_async(decoded.capture)
	if not assembly.ok:return _new_world_finished(assembly,request_id,old_paused)
	var candidate:Dictionary=await _prepare_mount_ready(decoded.capture,assembly)
	if not candidate.ok:return _new_world_finished(candidate,request_id,old_paused)
	# Readiness and complete authority validation precede changing active. The
	# existing store still performs its atomic write and checksum readback.
	var started:Dictionary=store.begin_save(assembly.runtime.capture_checkpoint(),true,text,false)
	if not started.ok:
		_discard_candidate(candidate)
		return _new_world_finished(started,request_id,old_paused)
	var saved:Dictionary={}
	while saved.is_empty():
		await get_tree().process_frame
		saved=store.poll()
	if not saved.ok:
		_discard_candidate(candidate)
		return _new_world_finished(saved,request_id,old_paused)
	if _closing or candidate.world_epoch!=_world_epoch or not _candidate_readiness(candidate).get("ready",false):
		_discard_candidate(candidate)
		return _new_world_finished({"ok":false,"code":"WORLD_SWITCH_CANCELLED","reason":"导入已取消或候选不再就绪，原活动存档保留"},request_id,old_paused)
	var activated:Dictionary=store.activate_saved(saved)
	if not activated.ok:
		_discard_candidate(candidate)
		return _new_world_finished(activated,request_id,old_paused)
	saved=activated
	var mounted:Dictionary=_activate_scene(candidate)
	_ready_game=true
	_fresh_save_required=false;_test_session=not assembly.runtime.capture_checkpoint().get("source",{}).get("playtest",{}).is_empty()
	saved.readiness=mounted.get("readiness",{});saved.world_epoch=mounted.get("world_epoch",0)
	return _new_world_finished(saved,request_id,false,"imported")

func export_checkpoint_file(path: String,request_id: String="") -> Dictionary:
	if _saving:return _file_receipt({"ok":false,"code":"BUSY","reason":"正在保存"},request_id)
	return _file_receipt(store.export_file(path,runtime.capture_checkpoint()),request_id)

func _file_receipt(result: Dictionary,request_id: String) -> Dictionary:
	var value := result.duplicate(true)
	value.request_id=request_id
	value.time=runtime.clock() if runtime!=null else 0
	value.revision=runtime.get_revision() if runtime!=null else 0
	return value

func _close_requested() -> void:
	if _closing:return
	_closing=true
	if router!=null:router.set_closing(true)
	await _stage_feedback("closing","正在安全退出","正在等待当前保存、地区转换或世界装配完成。")
	while _saving or _streaming or _world_loading:await get_tree().process_frame
	if runtime==null:get_tree().quit();return
	if _test_session:get_tree().quit();return
	var result: Dictionary=await save_async("window-close")
	if result.ok:get_tree().quit()
	else:
		_closing=false
		if is_instance_valid(_shell):
			_shell.show_close_failed(result)
			result.lifecycle_shell=true
		runtime.close_failed.emit(result)
func retry_close() -> void:_close_requested()
func cancel_close() -> void:
	_closing=false
	if router!=null:router.set_closing(false)
	if is_instance_valid(_shell):_shell.dismiss()
func _fatal(result: Dictionary) -> void:
	push_error("R3.3 boot failed "+JSON.stringify(result))
	if is_instance_valid(_shell):_shell.show_fatal(result)

func _update_night_light(delta: float) -> void:
	if _settlement_lights.is_empty(): return
	_night_light_poll -= delta
	if _night_light_poll <= 0.0:
		_night_light_poll = 0.25
		var stage: String = runtime.night_phase()
		_night_tint_goal = 1.0 if stage in ["warning", "fighting", "between"] else 0.45 if stage == "ready" else 0.0
	if is_equal_approx(_night_tint, _night_tint_goal): return
	_night_tint = move_toward(_night_tint, _night_tint_goal, delta * 0.55)
	var sun: DirectionalLight3D = _settlement_lights.sun
	var sky: Environment = _settlement_lights.environment.environment
	sun.light_energy = lerpf(1.0, 0.46, _night_tint)
	sun.light_color = Color("ffe8c9").lerp(Color("acbbeb"), _night_tint)
	sky.ambient_light_color = Color("b4c3cd").lerp(Color("899dcb"), _night_tint)
	sky.background_color = Color("87938d").lerp(Color("3a4c62"), _night_tint)
