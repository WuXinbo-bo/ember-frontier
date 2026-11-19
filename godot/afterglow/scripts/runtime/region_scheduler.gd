extends RefCounted
## A's bounded owner of C pure-value jobs. One worker; one authoritative world.
const FrameCosts = preload("res://scripts/runtime/frame_costs.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Settlement=preload("res://scripts/world/settlement_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const LandUseCover=preload("res://scripts/environment/land_use_cover.gd")
const MAX_QUEUED:=2
var _runtime:RefCounted
var _building:RefCounted
var _modules:RefCounted
var _factory:=false
var _epoch:=0
var _thread:Thread
var _active:Dictionary={}
var _queue:Array=[]
var _failures:Dictionary={}
var _history:Array=[]
var _probe_elapsed:=0.0
var _camera_rect:=Rect2()
var _camera_coverage_rect := Rect2i()
var _camera_coverage_regions: Array = []
var _camera_coverage: Dictionary = {}
var _stats:Dictionary={"requested":0,"completed":0,"discarded":0,"failed":0,"peak_queue":0,"max_commit_usec":0}
var _phases:Dictionary={}

func attach(runtime:RefCounted,building:RefCounted,epoch:int,modules:RefCounted=null)->void:
	cancel();_runtime=runtime;_building=building;_epoch=epoch;_modules=modules
	_factory=str(runtime.world.identity().get("generatorVersion",""))==Factory.VERSION

func cancel()->void:
	_discard_projection()
	_epoch+=1;_runtime=null;_building=null;_modules=null;_factory=false;_queue.clear();_failures.clear();_camera_rect=Rect2()
	_camera_coverage.clear()
	_camera_coverage_regions.clear()
	# A running pure-data job is allowed to finish; poll discards its epoch.
	# Never block a world switch or free a live Thread resource.

func shutdown()->void:
	cancel()
	if _thread!=null:_thread.wait_to_finish();_thread=null
	_active.clear()

func status()->Dictionary:
	return _stats.merged({"epoch":_epoch,"active":not _active.is_empty(),"queued":_queue.size(),"queue_limit":MAX_QUEUED,"worker_limit":1,"recent":_history.duplicate(true),"phases":_phases.duplicate(true)})

func _phase(name:String,started:int)->void:
	if FrameCosts.trace_enabled: FrameCosts.end("stream/" + name, started)
	var elapsed:int=Time.get_ticks_usec()-started
	var row:Dictionary=_phases.get(name,{"count":0,"total_usec":0,"max_usec":0})
	row.count+=1;row.total_usec+=elapsed;row.max_usec=maxi(row.max_usec,elapsed);_phases[name]=row

func set_camera_interest(rect:Rect2)->void:
	_camera_rect=rect

func camera_interest_status()->Dictionary:
	if not _factory or not _camera_rect.has_area() or _runtime==null:return {"ok":true,"missing":[],"excluded":0}
	var lower := Vector2i(floori(_camera_rect.position.x / 64.0), floori(_camera_rect.position.y / 64.0))
	var upper := Vector2i(ceili(_camera_rect.end.x / 64.0), ceili(_camera_rect.end.y / 64.0))
	var covered := Rect2i(lower, upper - lower)
	var ids: Array = _runtime.world.region_ids()
	# Camera motion within the same set of grid cells cannot change the answer.
	# Only region existence matters here, including after same-revision reloads.
	# The returned list is detached because the requester sorts it by distance.
	if not _camera_coverage.is_empty() and _camera_coverage_rect == covered and _camera_coverage_regions == ids:
		return _camera_coverage.duplicate(true)
	var known: Dictionary = {}
	for id: String in ids:
		known[id] = true
	var missing: Array = []
	var excluded := 0
	for z: int in range(lower.y, upper.y):
		for x: int in range(lower.x, upper.x):
			if absi(x) > Settlement.COORD_LIMIT or absi(z) > Settlement.COORD_LIMIT:
				excluded += 1
				continue
			var coord := Vector2i(x, z)
			if not known.has(_region_id(coord)):
				missing.append(coord)
	_camera_coverage = {"ok": true, "missing": missing, "excluded": excluded}
	if missing.size() + ids.size() > Settlement.MAX_REGIONS:
		_camera_coverage.merge(_failure("GENERATION_CAPACITY", "相机覆盖所需地区已超过本版有限容量"), true)
	_camera_coverage_rect = covered
	_camera_coverage_regions = ids
	return _camera_coverage.duplicate(true)

func request_camera_frontier()->Dictionary:
	var interest:Dictionary=camera_interest_status()
	if not interest.ok or interest.missing.is_empty():return interest
	var player:Dictionary=_runtime.actor("player")
	var point:=Vector2(player.x,player.z)
	interest.missing.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return (Vector2(a)*64.0+Vector2(32,32)).distance_squared_to(point)<(Vector2(b)*64.0+Vector2(32,32)).distance_squared_to(point))
	var regions:Array=_runtime.world.regions()
	for coord:Vector2i in interest.missing:
		var adjacent:bool=regions.any(func(region:Dictionary)->bool:
			var at:Dictionary=region.get("data",{}).get("regionCoord",{})
			return not at.is_empty() and absi(int(at.x)-coord.x)+absi(int(at.z)-coord.y)==1)
		if not adjacent:continue
		return request(coord)
	return _failure("NONADJACENT_CAMERA_INTEREST","相机覆盖缺少可连续生成的相邻地区")

func request(coord:Vector2i)->Dictionary:
	if _runtime==null:return _failure("WORLD_RETIRED","没有当前生成世界")
	if _factory and (_modules==null or not _modules.has_method("generation_profiles_for_content") or not _modules.has_method("prepare_generation")):return _failure("MISSING_MODULE_GENERATION","生产世界的模块登记尚未装配")
	var world:RefCounted=_runtime.world
	var id:String=_region_id(coord)
	if not world.region(id).is_empty():return {"ok":true,"code":"ALREADY_GENERATED","region_id":id}
	if _failures.has(id):return _failures[id].duplicate(true)
	if _active.get("id")==id and _active.get("epoch")==_epoch:return {"ok":true,"code":"PENDING","region_id":id}
	for item:Dictionary in _queue:
		if item.id==id:return {"ok":true,"code":"PENDING","region_id":id}
	if _queue.size()>=MAX_QUEUED:return _failure("GENERATION_QUEUE_FULL","外围准备队列已满，请稍后重试")
	if absi(coord.x)>Settlement.COORD_LIMIT or absi(coord.y)>Settlement.COORD_LIMIT or world.region_ids().size()>=Settlement.MAX_REGIONS:return _failure("GENERATION_CAPACITY","已达到本版有限地图范围")
	var adjacent:=false
	for region:Dictionary in world.regions():
		var at:Variant=region.get("data",{}).get("regionCoord")
		if at is Dictionary and absi(int(at.x)-coord.x)+absi(int(at.z)-coord.y)==1:adjacent=true;break
	if not adjacent:return _failure("NONADJACENT_REGION","只能准备真实相邻的外围")
	_queue.append({"coord":coord,"id":id,"epoch":_epoch})
	_stats.requested+=1;_stats.peak_queue=maxi(int(_stats.peak_queue),_queue.size())
	_start_next()
	return {"ok":true,"code":"PENDING","region_id":id,"epoch":_epoch}

func _start_next()->void:
	if _thread!=null or not _active.is_empty() or _queue.is_empty() or _runtime==null:return
	var job:Dictionary=_queue.pop_front()
	var module_profiles:Array=[]
	if _factory:
		# The saved world chooses its profile set. An old world must never
		# inherit the new-entry default when it expands after a restart.
		var lock:Variant=_runtime.world.extension("generation:factory-r34")
		var content:Variant=lock.get("content_version",1) if lock is Dictionary else 1
		# Exact saved content chooses12/18/19 through the B owner. Unknown
		# versions fail closed; new defaults never change an old world's lock.
		module_profiles=_modules.generation_profiles_for_content(int(content)) if Data.integer(content) else []
	var input:Dictionary=Factory.region_generation_input(_runtime.world,module_profiles) if _factory else Rural.region_generation_input(_runtime.world,Buildings.generation_profiles())
	if not input.ok:_record(job,input);return
	job.input=input;_active=job
	_thread=Thread.new()
	var error:int=_thread.start(_generate_region.bind(input.duplicate(true),job.coord,_factory))
	if error!=OK:
		_thread=null;_active.clear();_record(job,_failure("GENERATION_THREAD","外围数据任务未能启动"))

static func _generate_region(input:Dictionary,coord:Vector2i,factory:bool)->Dictionary:
	var draft:Dictionary=Factory.draft_region_request(input,coord) if factory else Rural.draft_region_request(input,coord)
	var generated:Dictionary={"draft":draft}
	if factory and draft.ok:
		generated.fringe=LandUseCover.patches(draft.plan)
	return generated

func publication_fringe(world:RefCounted,epoch:int,region_id:String)->Variant:
	if _runtime==null or world!=_runtime.world or epoch!=_epoch or _active.get("epoch")!=epoch:
		return null
	if _active.get("id")!=region_id or _active.get("publication_revision",-1)!=world.get_revision():
		return null
	return _active.get("fringe")

func poll(delta:float=0.0,allow_commit:bool=true)->Dictionary:
	var completed:Dictionary={}
	if _thread!=null and not _thread.is_alive():
		var generated:Dictionary=_thread.wait_to_finish();_thread=null
		_active.merge(generated)
	if _active.has("draft"):
		if _runtime==null or _active.epoch!=_epoch:
			_discard_projection();_stats.discarded+=1;_active.clear()
		elif allow_commit:
			var began:int=Time.get_ticks_usec()
			completed=_advance_publication()
			var elapsed:int=Time.get_ticks_usec()-began
			_stats.max_commit_usec=maxi(int(_stats.max_commit_usec),elapsed)
			_phase("publication_unit",began)
			if not completed.is_empty():
				var job: Dictionary = _active
				if completed.get("ok", false) and not completed.get("already_generated", false) and job.has("fringe"):
					completed.presentation_fringe = job.fringe
				_discard_projection()
				_active = {}
				_record(job, completed)
	if allow_commit and _runtime!=null:
		_start_next()
		_probe_elapsed+=maxf(0.0,delta)
		if _probe_elapsed>=0.25:_probe_elapsed=0.0;_probe_boundary()
	return completed

func _discard_projection()->void:
	if _active.has("projection"):
		_active.projection_world.discard_prepared(_active.projection.capability)
		_active.erase("projection");_active.erase("projection_world")

func _prepare_generation_projection(world: RefCounted, changes: Array) -> Dictionary:
	if world.get_script() != null and world.get_script().resource_path == "res://scripts/world/world_state.gd":
		return world.prepare_runtime_changes(changes, world.get_revision())
	return world.prepare_changes(changes, world.get_revision())

func _advance_publication()->Dictionary:
	# Generation remains one atomic publication. Its speculative projection,
	# family assembly and final transaction run in separate frames. Any live
	# world change discards the proof and rederives against the current world;
	# neither stale capability nor partially generated terrain is published.
	var world:RefCounted=_runtime.world
	if _active.has("basis") and _active.basis!=world.get_revision():
		_discard_projection();_active.erase("prepared");_active.erase("family");_active.erase("basis")
	var draft:Dictionary=_active.draft
	if not draft.get("ok",false):return draft
	if not _active.has("prepared"):
		var started:int=Time.get_ticks_usec()
		var prepared:Dictionary=Factory.prepare_region_draft(world,draft,world.get_revision()) if _factory else Rural.prepare_region_draft(world,draft,world.get_revision())
		_phase("region_prepare",started)
		if not prepared.ok or prepared.get("already_generated",false):return prepared
		started=Time.get_ticks_usec()
		var projection:Dictionary=_prepare_generation_projection(world, prepared.world_changes)
		_phase("projection_prepare",started)
		if not projection.ok:return projection
		_active.merge({"prepared":prepared,"projection":projection,"projection_world":world,"basis":world.get_revision()})
		return {}
	if not _active.has("family"):
		var started:int=Time.get_ticks_usec()
		var view:RefCounted=_active.projection.view
		var family:Dictionary=_modules.prepare_generation(view,[draft.region.id]) if _factory else _building.prepare_generation(view,[draft.region.id])
		_phase("family_prepare",started)
		_discard_projection()
		if not family.ok and family.get("code")!="ALREADY_SEEDED":return family
		_active.family=family
		return {}
	return _commit_draft(draft,_active.prepared,_active.family)

func _probe_boundary()->void:
	var player:Dictionary=_runtime.actor("player")
	if player.is_empty() or player.get("buildingId")!=null:return
	if _factory and _camera_rect.has_area():
		request_camera_frontier();return
	var region:Dictionary=_runtime.world.region(str(player.regionId))
	var at:Variant=region.get("data",{}).get("regionCoord")
	if not at is Dictionary:return
	var rect:Dictionary=region.bounds;var coord:=Vector2i(int(at.x),int(at.z))
	var edges:Array=[{"distance":float(player.x)-float(rect.min.x),"offset":Vector2i.LEFT},{"distance":float(rect.max.x)-float(player.x),"offset":Vector2i.RIGHT},{"distance":float(player.z)-float(rect.min.z),"offset":Vector2i.UP},{"distance":float(rect.max.z)-float(player.z),"offset":Vector2i.DOWN}]
	edges.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.distance<b.distance)
	for edge:Dictionary in edges:
		if float(edge.distance)>14.0:break
		var next:Vector2i=coord+edge.offset
		if _runtime.world.region(_region_id(next)).is_empty():request(next);break

func _region_id(coord:Vector2i)->String:
	return Factory.region_id(coord) if _factory else Settlement.region_id(coord)

func _commit_draft(draft:Dictionary,region_plan:Dictionary={},family_plan:Dictionary={})->Dictionary:
	if not draft.get("ok",false):return draft
	var world:RefCounted=_runtime.world
	var started:int=Time.get_ticks_usec()
	var prepared:Dictionary=region_plan if not region_plan.is_empty() else (Factory.prepare_region_draft(world,draft,world.get_revision()) if _factory else Rural.prepare_region_draft(world,draft,world.get_revision()))
	_phase("region_prepare",started);started=Time.get_ticks_usec()
	if not prepared.ok or prepared.get("already_generated",false):return prepared
	# Projection only: B assembles its own parcels/dressing against C's draft.
	# Discard the temporary capability; final A transaction revalidates all.
	var family:Dictionary=family_plan
	if family.is_empty():
		var projection:Dictionary=_prepare_generation_projection(world, prepared.world_changes)
		_phase("projection_prepare",started);started=Time.get_ticks_usec()
		if not projection.ok:return projection
		family=_modules.prepare_generation(projection.view,[draft.region.id]) if _factory else _building.prepare_generation(projection.view,[draft.region.id])
		world.discard_prepared(projection.capability)
	_phase("family_prepare",started);started=Time.get_ticks_usec()
	if not family.ok and family.get("code")!="ALREADY_SEEDED":return family
	var merged:Dictionary=merge_world_changes(prepared.world_changes,family.get("world_changes",[]))
	_phase("merge",started);started=Time.get_ticks_usec()
	if not merged.ok:return merged
	var world_changes:Array=merged.changes
	var facts:Array=[];var stock_ids:Dictionary={}
	for stock:Dictionary in prepared.get("initial_stocks",[])+family.get("initial_stocks",[]):
		if stock_ids.has(stock.id) or not _runtime.stock(str(stock.id)).is_empty():return _failure("GENERATION_STOCK_COLLISION","外围库存身份已存在")
		stock_ids[stock.id]=true;facts.append({"collection":"stocks","id":stock.id,"before":null,"after":stock.duplicate(true)})
	var tools:Array=family.get("initial_tools",[]);var records:Array=family.get("initial_records",[])
	if not tools.is_empty() or not records.is_empty():
		var before:Variant=world.extension("r3:production")
		if not before is Dictionary:return _failure("MISSING_PRODUCTION","原生产事实未装配")
		var after:Dictionary=before.duplicate(true)
		for field:String in ["tools","records"]:
			var ids:Dictionary={}
			for item:Dictionary in after[field]:ids[item.id]=true
			for item:Dictionary in tools if field=="tools" else records:
				if ids.has(item.id):return _failure("GENERATION_ITEM_COLLISION","外围工具或手册身份已存在")
				ids[item.id]=true;after[field].append(item.duplicate(true))
		world_changes.append({"op":"extension.set","id":"r3:production","before_exists":true,"before":before,"after":after})
	_phase("stock_prepare",started);started=Time.get_ticks_usec()
	# Runtime notifies the view synchronously after swapping authority. Expose
	# the cosmetic result only within that commit and at its new world revision.
	var job:Dictionary=_active
	var revision:int=world.get_revision()
	if job.has("fringe") and job.get("id")==draft.region.id and job.get("basis")==revision:
		job.publication_revision=revision+1
	var result:Dictionary=_runtime._commit({"world_changes":world_changes,"fact_changes":facts,"events":[{"kind":"region_generated","region_id":draft.region.id}]}).merged({"region_id":draft.region.id})
	job.erase("publication_revision")
	_phase("runtime_commit_and_views",started)
	return result

static func merge_world_changes(base:Array,addition:Array)->Dictionary:
	var result:Array=base.duplicate(true);var targets:Dictionary={}
	for i:int in result.size():targets[str(result[i].op)+":"+str(result[i].get("id",""))]=i
	for change:Dictionary in addition:
		var key:String=str(change.op)+":"+str(change.get("id",""))
		if targets.has(key):
			var previous:Dictionary=result[targets[key]]
			if change.op!="extension.set" or not change.get("before_exists",false) or not Data.json_equal(change.get("before"),previous.get("after")):return _failure("GENERATION_CAS_CHAIN","领域草案未基于同一中间事实，外围未提交")
			previous.after=change.after.duplicate(true)
		else:
			targets[key]=result.size();result.append(change.duplicate(true))
	return {"ok":true,"changes":result}

func _record(job:Dictionary,result:Dictionary)->void:
	if result.ok:_stats.completed+=1
	else:
		_stats.failed+=1
		if _failures.size()<32:_failures[job.id]=result.duplicate(true)
	_history.append({"region_id":job.id,"epoch":job.epoch,"ok":result.ok,"code":result.get("code","OK"),"reason":result.get("reason","")})
	if _history.size()>16:_history.pop_front()
	print("Afterglow native region "+JSON.stringify(_history[-1]))

static func _failure(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
