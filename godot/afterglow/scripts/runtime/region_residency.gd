extends RefCounted
## A selects storage residency; C owns the exact lossless conversion.
## Never loads data or infers gameplay facts from rendering nodes.
const SCENARIO="factory-settlement-r34"
const PROBE_SECONDS=0.5
const RETRY_SECONDS=5.0
const COOL_DELAY_SECONDS=12.0
const COOL_MARGIN_METRES=8.0
const CameraInterest=preload("res://scripts/runtime/camera_interest.gd")
var _runtime:RefCounted
var _elapsed:=0.0
var _retry:Dictionary={}
var _unpinned_since:Dictionary={}
var _history:Array=[]
var _stats:Dictionary={"warmed":0,"cooled":0,"failed":0}

func attach(authority:RefCounted)->void:
	_runtime=authority;_elapsed=0.0;_retry.clear();_history.clear();_unpinned_since.clear()
	_stats={"warmed":0,"cooled":0,"failed":0}

static func required_regions(authority:RefCounted,camera_radius:float=18.0,camera_rect:Rect2=Rect2())->Dictionary:
	var pins:Dictionary={};var world:RefCounted=authority.world
	var actors:Array=authority.actor_states()
	# All consumers below run without yielding. Copy the region records once
	# for this exact pin computation, not once per living actor plus camera.
	var regions:Array=world.regions()
	for actor:Dictionary in actors:
		if float(actor.get("hp",0))<=0:continue
		_pin(pins,str(actor.get("regionId","")),"living_actor:"+str(actor.id))
		_locations(actor.get("intent"),pins,"active_route:"+str(actor.id))
		var radius:float=(maxf(18.0,camera_radius) if not camera_rect.has_area() else 2.5) if actor.id=="player" else 2.5
		for region:Dictionary in regions:
			var bounds:Dictionary=region.bounds
			var x:float=clampf(float(actor.x),float(bounds.min.x),float(bounds.max.x))
			var z:float=clampf(float(actor.z),float(bounds.min.z),float(bounds.max.z))
			if Vector2(x-float(actor.x),z-float(actor.z)).length()<=radius:_pin(pins,str(region.id),"body_or_camera_fringe:"+str(actor.id))
	if camera_rect.has_area():
		for region:Dictionary in regions:
			if CameraInterest.intersects_region(camera_rect,region):_pin(pins,str(region.id),"actual_camera_terrain_slab")
	for owner:String in ["production","workforce"]:
		var service:Variant=authority._services.get(owner)
		var method:String="residency_dependency_regions" if owner=="production" else "event_dependency_regions"
		if service==null or not service.has_method(method):continue
		var dependencies:Variant=service.call(method)
		if dependencies is Array:
			for id:Variant in dependencies:
				if id is String:_pin(pins,id,owner+":active_dependency")
	return pins

static func _pin(pins:Dictionary,id:String,reason:String)->void:
	if id.is_empty():return
	if not pins.has(id):pins[id]=[]
	if not pins[id].has(reason):pins[id].append(reason)

static func _locations(value:Variant,pins:Dictionary,reason:String,depth:int=0)->void:
	if depth>16:return
	if value is Dictionary:
		if value.get("regionId") is String:_pin(pins,value.regionId,reason)
		for child:Variant in value.values():_locations(child,pins,reason,depth+1)
	elif value is Array:
		for child:Variant in value:_locations(child,pins,reason,depth+1)

func poll(delta:float,allowed:bool,camera_radius:float=18.0,camera_rect:Rect2=Rect2())->Dictionary:
	if not allowed or _runtime==null or _runtime.scenario()!=SCENARIO:return {}
	_elapsed+=maxf(0.0,delta)
	if _elapsed<PROBE_SECONDS:return {}
	_elapsed=0.0
	var pins:Dictionary=required_regions(_runtime,camera_radius,camera_rect)
	var now:float=Time.get_ticks_msec()/1000.0
	var retention:Rect2=camera_rect.grow(COOL_MARGIN_METRES) if camera_rect.has_area() else Rect2()
	for id:String in pins:_unpinned_since.erase(id)
	# Warm dependencies before releasing anything. This is storage readiness;
	# NativeClient still waits for terrain mesh and physics before resuming.
	for id:String in pins:
		if _runtime.world.region(id).is_empty() or float(_retry.get(id,0))>now:continue
		if not _runtime.world.region_is_resident(id):return {"region_id":id,"resident":true,"pins":pins}
	for region:Dictionary in _runtime.world.regions():
		if pins.has(region.id):continue
		if retention.has_area() and CameraInterest.intersects_region(retention,region):
			_unpinned_since.erase(region.id)
			continue
		if not region.get("generated",false) or float(_retry.get(region.id,0))>now:continue
		if not _unpinned_since.has(region.id):_unpinned_since[region.id]=now
		if now-float(_unpinned_since[region.id])<COOL_DELAY_SECONDS:continue
		var state:Dictionary=_runtime.world.region_residency_state(str(region.id))
		if state.generated and not state.paged:return {"region_id":region.id,"resident":false,"pins":pins}
	return {}

func finish(plan:Dictionary,result:Dictionary)->void:
	var id:String=str(plan.region_id)
	if result.get("ok",false):
		_stats["warmed" if plan.resident else "cooled"]+=1
		_retry.erase(id)
	else:
		_stats.failed+=1;_retry[id]=Time.get_ticks_msec()/1000.0+RETRY_SECONDS
	_history.append({"region_id":id,"resident":plan.resident,"ok":result.get("ok",false),"code":result.get("code","OK"),"reason":result.get("reason",""),"before":result.get("state_before",{}),"after":result.get("state_after",{}),"checkpoint_sha256":result.get("checkpoint_sha256",""),"elapsed_ms":result.get("elapsed_ms",0)})
	if _history.size()>16:_history.pop_front()

func status()->Dictionary:
	var result:Dictionary=_stats.duplicate(true)
	result.policy="living-bodies-frustum-routes-logistics-event-pins-v2"
	result.recent=_history.duplicate(true)
	if _runtime!=null:
		result.regions=[]
		for region:Dictionary in _runtime.world.regions():result.regions.append(_runtime.world.region_residency_state(str(region.id)))
	return result
