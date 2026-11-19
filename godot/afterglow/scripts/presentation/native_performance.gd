extends Node
const PhaseCosts = preload("res://scripts/runtime/frame_costs.gd")
## Foreground render-to-render wall time. Exclusions never shorten the sample.
const WARMUP_US:=30000000
const SAMPLE_US:=60000000
var runtime:RefCounted
var _last_usec:=0
var _frames:Array[float]=[]
var _cpu:Array[float]=[]
var _physics:Array[float]=[]
var _render_cpu:Array[float]=[]
var _render_gpu:Array[float]=[]
var _render_setup:Array[float]=[]
var _viewport_rid:RID
var _scene_start:Dictionary={}
var _scene_changed:=false
var _start_usec:=0
var _active_usec:=0
var _sample_usec:=0
var _excluded_usec:=0
var _focused:=true
var _previous_active:=false
var _trace_last_usec := 0
var _slow_frames: Array[Dictionary] = []
var _sample_id:=0
var _label:="continuous"
var _session:String=str(OS.get_process_id())+":"+str(Time.get_ticks_usec())
var _region_status:Callable
var _terrain_status:Callable
var _soak_monitor:=false
var _trend_start_usec:=0
var _trend_mark_usec:=0
var _trend_active_usec:=0
var _trend_excluded_usec:=0
var _trend_frames:Array[float]=[]
var _evidence_directory:=""
var _evidence_sequence:=0
var _movement_probe:RefCounted=preload("res://scripts/presentation/movement_frame_probe.gd").new()
func configure(value:RefCounted,region_status:Callable=Callable(),terrain_status:Callable=Callable(),evidence_directory:String="")->void:
	runtime=value
	preload("res://scripts/runtime/frame_costs.gd").enabled=OS.get_cmdline_user_args().has("--profile-phases")
	_evidence_directory=evidence_directory
	_region_status=region_status
	_terrain_status=terrain_status
	_viewport_rid=get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid,true)
	_focused=get_window().has_focus()
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--benchmark-label="):_label=argument.trim_prefix("--benchmark-label=")
		elif argument=="--soak-monitor":_soak_monitor=true
		elif argument=="--profile-slow-frames":
			PhaseCosts.enabled=true
			PhaseCosts.trace_enabled=true
	reset("load")
	if _soak_monitor:
		_trend_start_usec=Time.get_ticks_usec();_trend_mark_usec=_trend_start_usec
		_trend_report("load")
	get_window().focus_exited.connect(func():_focused=false;_lifecycle("blur"))
	get_window().focus_entered.connect(func():_focused=true;_last_usec=0;_lifecycle("focus"))
func reset(reason:String)->void:
	_frames.clear();_cpu.clear();_physics.clear();_render_cpu.clear();_render_gpu.clear();_render_setup.clear()
	_movement_probe=preload("res://scripts/presentation/movement_frame_probe.gd").new()
	_scene_start={};_scene_changed=false
	_start_usec=Time.get_ticks_usec();_active_usec=0;_sample_usec=0;_excluded_usec=0;_last_usec=0
	_previous_active=false;_sample_id+=1
	_slow_frames.clear()
	_trace_last_usec=0
	print("R3.3 native performance start "+JSON.stringify({"sample":_sample_id,"label":_label,"reason":reason,"warmup_ms":WARMUP_US/1000,"window_ms":SAMPLE_US/1000,"godot":Engine.get_version_info().string,"driver":RenderingServer.get_current_rendering_driver_name(),"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"viewport":str(get_viewport().get_visible_rect().size),"screen_scale":DisplayServer.screen_get_scale(),"seed":runtime.world.identity().get("seed"),"region":runtime.actor("player").get("regionId")}))
func _lifecycle(event:String)->void:
	print("R3.3 native lifecycle "+JSON.stringify({"event":event,"wall_us":Time.get_ticks_usec(),"time":runtime.clock(),"active_ms":_active_usec/1000.0,"excluded_ms":_excluded_usec/1000.0,"collected":_frames.size()}))
func _input(event:InputEvent)->void:
	# Read-only evidence marker, including while a modal consumes gameplay input.
	# It never moves the player, changes time, captures input, or writes a save.
	if runtime!=null and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8 and event.shift_pressed and (event.ctrl_pressed or event.meta_pressed):
		print("R3.3 native observation "+JSON.stringify({"schema":"afterglow-native-observation-v2","label":_label,"wall_us":Time.get_ticks_usec(),"utc":Time.get_datetime_string_from_system(true),"scene":_scene(),"focused":_focused,"paused":runtime.is_paused(),"time":runtime.clock(),"render_method":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"screen_scale":DisplayServer.screen_get_scale(),"render_scale":get_viewport().scaling_3d_scale,"window_size":get_window().size,"window_pixels":{"x":get_window().size.x,"y":get_window().size.y},"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}))
func _process(_dt:float)->void:
	if runtime==null:return
	var now:int=Time.get_ticks_usec()
	if PhaseCosts.trace_enabled:
		_observe_frame_cost(now)
	var active:bool=_focused and not runtime.is_paused()
	if _last_usec>0:
		var interval:int=now-_last_usec
		if active and _previous_active:
			_movement_probe.observe(runtime.actor("player"),now,interval/1000.0,_active_usec>=WARMUP_US)
			# Do not split/cap a stall at the window boundary. Record its full wall
			# duration, even when the resulting valid sample exceeds 60 seconds.
			if _active_usec>=WARMUP_US:
				var camera:Camera3D=get_viewport().get_camera_3d()
				if _scene_start.is_empty():_scene_start=_scene()
				if camera!=null and (camera.global_position.distance_squared_to(_scene_start.camera_position)>0.0625 or not is_equal_approx(camera.size,_scene_start.camera_size)):_scene_changed=true
				if get_viewport().get_visible_rect().size!=_scene_start.viewport:_scene_changed=true
				_sample_usec+=interval
				_frames.append(interval/1000.0)
				_cpu.append(float(Performance.get_monitor(Performance.TIME_PROCESS))*1000)
				_physics.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))*1000)
				_render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid))
				_render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
				_render_setup.append(RenderingServer.get_frame_setup_time_cpu())
			_active_usec+=interval
		else:
			_excluded_usec+=interval
			_movement_probe.break_continuity()
		if _soak_monitor:
			if active and _previous_active:
				_trend_active_usec+=interval;_trend_frames.append(interval/1000.0)
			else:_trend_excluded_usec+=interval
	_last_usec=now;_previous_active=active
	if _soak_monitor and now-_trend_mark_usec>=60000000:_trend_report("minute")
	if _active_usec>=WARMUP_US+SAMPLE_US and _sample_duration_ms()>=60000:
		report();reset("next-continuous-window")
func _observe_frame_cost(now: int) -> void:
	var elapsed := now - _trace_last_usec
	var phases := PhaseCosts.trace
	PhaseCosts.trace = {}
	if _trace_last_usec > 0 and _focused and _active_usec >= WARMUP_US and elapsed >= 22000:
		_slow_frames.append({"wall_usec": elapsed, "inclusive_usec": phases})
		if _slow_frames.size() > 512:
			_slow_frames.pop_front()
	_trace_last_usec = now

func _sample_duration_ms()->float:
	return _sample_usec/1000.0
func _scene()->Dictionary:
	var camera:Camera3D=get_viewport().get_camera_3d()
	var player:Dictionary=runtime.actor("player")
	var identity:Dictionary=runtime.world.identity()
	var size:float=float(runtime.world.config().cellSize)
	var cell:Vector3i=Vector3i(floori(float(player.x)/size),floori(float(player.y)/size)-1,floori(float(player.z)/size))
	var position:Vector3=camera.global_position if camera!=null else Vector3.ZERO
	var rotation:Vector3=camera.global_rotation if camera!=null else Vector3.ZERO
	var viewport:Vector2=get_viewport().get_visible_rect().size
	var generation:Variant=runtime.world.extension("generation:rural2")
	var factory_generation:Variant=runtime.world.extension("generation:factory-r34")
	var provenance:Dictionary={"session":_session,"generation_configuration":generation if generation is Dictionary else {},"world_config":runtime.world.config(),"actor_count":runtime.active_positions().size(),"region_count":runtime.world.regions().size(),"region_scheduler":_region_status.call() if _region_status.is_valid() else {}}
	# Additive provenance for current factory worlds; keep the legacy field.
	provenance.factory_generation_configuration=factory_generation if factory_generation is Dictionary else {}
	return {"camera_position":position,"camera_size":camera.size if camera!=null else 0.0,"camera_rotation":rotation,"camera_position_xyz":{"x":position.x,"y":position.y,"z":position.z},"camera_rotation_xyz":{"x":rotation.x,"y":rotation.y,"z":rotation.z},"viewport":viewport,"viewport_size":{"x":viewport.x,"y":viewport.y},"player":{"x":player.x,"y":player.y,"z":player.z,"region":player.regionId,"building":player.get("buildingId"),"storey":player.get("storeyId")},"world_id":identity.worldId,"seed":identity.seed,"generator_version":identity.generatorVersion,"world_revision":runtime.world.get_revision(),"support_cell":{"x":cell.x,"y":cell.y,"z":cell.z,"material":runtime.world.cell_at(cell.x,cell.y,cell.z)}}.merged(provenance)
func _statistics(values:Array[float])->Dictionary:
	if values.is_empty():return {}
	var sorted:Array[float]=values.duplicate();sorted.sort()
	return {"count":sorted.size(),"mean":sorted.reduce(func(total:float,x:float)->float:return total+x,0.0)/sorted.size(),"p50":sorted[clampi(ceili(sorted.size()*0.5)-1,0,sorted.size()-1)],"p95":sorted[clampi(ceili(sorted.size()*0.95)-1,0,sorted.size()-1)],"p99":sorted[clampi(ceili(sorted.size()*0.99)-1,0,sorted.size()-1)],"max":sorted[-1]}
func _scene_resources()->Dictionary:
	# Once per optional wall-clock minute, count unique resources referenced by
	# the live scene. These are not every engine allocation or OS RSS, and the
	# traversal itself is outside the duration of the interval it describes.
	var meshes:Dictionary={};var materials:Dictionary={};var shapes:Dictionary={};var multimeshes:Dictionary={}
	var pending:Array[Node]=[]
	if get_parent()!=null:pending.append(get_parent())
	var nodes:int=0
	while not pending.is_empty():
		var node:Node=pending.pop_back();nodes+=1
		for child:Node in node.get_children():pending.append(child)
		var mesh:Mesh
		if node is MeshInstance3D:
			mesh=node.mesh
			if node.material_override!=null:materials[node.material_override.get_instance_id()]=true
			if node.material_overlay!=null:materials[node.material_overlay.get_instance_id()]=true
			for surface:int in node.get_surface_override_material_count():
				var material:Material=node.get_surface_override_material(surface)
				if material!=null:materials[material.get_instance_id()]=true
		elif node is MultiMeshInstance3D:
			if node.multimesh!=null:
				multimeshes[node.multimesh.get_instance_id()]=true;mesh=node.multimesh.mesh
			if node.material_override!=null:materials[node.material_override.get_instance_id()]=true
			if node.material_overlay!=null:materials[node.material_overlay.get_instance_id()]=true
		if mesh!=null:
			meshes[mesh.get_instance_id()]=true
			for surface:int in mesh.get_surface_count():
				var material:Material=mesh.surface_get_material(surface)
				if material!=null:materials[material.get_instance_id()]=true
		if node is CollisionShape3D and node.shape!=null:shapes[node.shape.get_instance_id()]=true
	return {"scope":"unique live scene references, not global resource allocations","nodes":nodes,"meshes":meshes.size(),"materials":materials.size(),"shapes":shapes.size(),"multimeshes":multimeshes.size(),"engine_resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}
func _trend_report(reason:String)->Dictionary:
	# Optional wall-clock soak diagnostics. A minute spanning movement, saving,
	# pauses or streaming is never presented as a fixed-scene performance window.
	var now:int=Time.get_ticks_usec()
	var span:int=now-_trend_mark_usec
	var frame:Dictionary=_statistics(_trend_frames)
	var row:Dictionary={"schema":"afterglow-native-trend-v1","session":_session,"pid":OS.get_process_id(),"label":_label,"event":reason,"wall_us":now,"utc":Time.get_datetime_string_from_system(true),"scene_elapsed_ms":(now-_trend_start_usec)/1000.0,"window_ms":span/1000.0,"complete_minute":reason=="minute" and span>=60000000,"active_ms":_trend_active_usec/1000.0,"excluded_ms":_trend_excluded_usec/1000.0,"focused":_focused,"paused":runtime.is_paused(),"time":runtime.clock(),"world":runtime.world.identity(),"world_revision":runtime.world.get_revision(),"runtime_revision":runtime.get_revision(),"actors":runtime.active_positions().size(),"regions":runtime.world.regions().size(),"region_scheduler":_region_status.call() if _region_status.is_valid() else {},"simulation":runtime.simulation_budget(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"frame":frame,"over250":_trend_frames.filter(func(ms:float)->bool:return ms>250).size(),"scope":"optional wall-clock resource/queue trend; mixed scenes and exclusions explicit; tracked static memory is not OS RSS; not fixed-scene or long-time acceptance by itself"}
	row.scene_resources=_scene_resources()
	row.simulation_costs=runtime.simulation_costs()
	row.terrain=_terrain_status.call() if _terrain_status.is_valid() else {}
	_emit_record("R3.3 native trend ",row)
	_trend_frames.clear();_trend_active_usec=0;_trend_excluded_usec=0;_trend_mark_usec=now
	return row
func _exit_tree()->void:
	if _soak_monitor and runtime!=null:_trend_report("retire-partial")
func report()->Dictionary:
	var frame:Dictionary=_statistics(_frames)
	var duration:float=_sample_duration_ms()
	var row:Dictionary={"schema":"afterglow-native-performance-v3","sample":_sample_id,"label":_label,"qualified_duration":duration>=60000,"sample_ms":duration,"active_ms":_active_usec/1000.0,"elapsed_ms":(Time.get_ticks_usec()-_start_usec)/1000.0,"excluded_ms":_excluded_usec/1000.0,"method":"foreground unpaused render-to-render monotonic wall clock; 30s active warmup then >=60s active sample; no dt clamp/stall censor; TIME_PROCESS separate proxy, not GPU or full CPU","fixed_scene":not _scene_changed,"scene_start":_scene_start,"scene_end":_scene(),"render_cpu_ms":_statistics(_render_cpu),"render_gpu_ms":_statistics(_render_gpu),"render_setup_cpu_ms":_statistics(_render_setup),"gpu_query_available":_render_gpu.any(func(ms:float)->bool:return ms>0),"frame":frame,"cpu_process_proxy":_statistics(_cpu),"physics":_statistics(_physics),"fps":1000.0/float(frame.get("mean",INF)),"over250":_frames.filter(func(ms:float)->bool:return ms>250).size(),"time":runtime.clock(),"region":runtime.actor("player").get("regionId"),"world_revision":runtime.world.get_revision(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	row.simulation=runtime.simulation_budget();row.authority=runtime.authority_costs();row.simulation_costs=runtime.simulation_costs()
	row.observed_movement={"schema":"afterglow-movement-frame-v1","distance_m":_movement_probe.distance_m,"discontinuities":_movement_probe.discontinuities,"frame":_statistics(_movement_probe.frames),"scope":"actual player displacement plus 120ms render/physics continuity; warmup/exclusions follow whole sample; subset never substitutes for unfiltered whole-window metrics"}
	if not _slow_frames.is_empty():row.slow_frames=_slow_frames.duplicate(true)
	_emit_record("R3.3 native performance ",row);return row

func _emit_record(prefix:String,row:Dictionary)->Dictionary:
	# Full scheduler/phase provenance can exceed the platform log message limit.
	# Only the already marked QA startup enables files; ordinary users get no
	# new disk writes. Recording happens after the measured interval, never
	# filters a stall and never changes the authority or sample eligibility.
	row.frame_costs=preload("res://scripts/runtime/frame_costs.gd").snapshot()
	var artifact:Dictionary={}
	if not _evidence_directory.is_empty():
		_evidence_sequence+=1
		var directory_error:int=DirAccess.make_dir_recursive_absolute(_evidence_directory)
		var path:String=_evidence_directory.path_join("native-%s-%d.json"%[_session.replace(":","-"),_evidence_sequence])
		if directory_error==OK and not FileAccess.file_exists(path):
			var encoded:String=JSON.stringify(row,"\t",true,true)+"\n"
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file!=null:
				file.store_string(encoded);file.flush();file.close()
				if FileAccess.get_sha256(path)==encoded.sha256_text():artifact={"path":path,"sha256":encoded.sha256_text(),"bytes":encoded.to_utf8_buffer().size()}
		if artifact.is_empty():artifact={"ok":false,"reason":"performance_artifact_write_failed"}
	var summary:Dictionary=row.duplicate(true)
	# Numeric frame/render/resource data and scene identities remain in the
	# compact log. Detailed phases/region inventories remain in the full file.
	for key:String in ["authority","simulation_costs","region_scheduler","terrain"]:summary.erase(key)
	for key:String in ["scene_start","scene_end"]:
		if summary.get(key) is Dictionary:summary[key].erase("region_scheduler")
	if not artifact.is_empty():summary.evidence_artifact=artifact
	print(prefix+JSON.stringify(summary))
	return artifact
