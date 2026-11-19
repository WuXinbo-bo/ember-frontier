extends SceneTree
## Actual Camera3D projection/viewport sizes, not a radius approximation.
const Interest=preload("res://scripts/runtime/camera_interest.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
class ConfigWorld extends RefCounted:
	func config()->Dictionary:return Data.DEFAULT_CONFIG.duplicate(true)
	func chunk_keys()->Array:return ["-2,0,-1","-1,0,-1","0,0,0","1,0,0","8,0,8"]
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var world:=ConfigWorld.new()
	for viewport_size:Vector2i in [Vector2i(1280,800),Vector2i(2520,1080),Vector2i(800,1200)]:
		var viewport:=SubViewport.new();viewport.size=viewport_size;viewport.own_world_3d=true;root.add_child(viewport)
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=0.1;camera.far=180;viewport.add_child(camera)
		for zoom:float in [12.0,24.0,40.0]:
			camera.size=zoom
			for focus:Vector3 in [Vector3(8,0.7,26),Vector3(-63.75,6.2,-0.25)]:
				camera.position=focus+Vector3(24,29,31);camera.look_at(focus,Vector3.UP)
				var sampled:Dictionary=Interest.footprint(camera,world,8)
				var good:bool=sampled.ok
				var screens:Array=[Vector2.ZERO,Vector2(viewport_size.x,0),Vector2(viewport_size),Vector2(0,viewport_size.y)]
				var expected:Array=[-4.0,20.0]
				if good:
					for screen:Vector2 in screens:
						for height:float in expected:
							var ray:Vector3=camera.project_ray_normal(screen)
							var start:Vector3=camera.project_ray_origin(screen)
							var distance:float=(height-start.y)/ray.y
							if distance<0 or distance>camera.far-camera.near:continue
							var point:Vector3=start+ray*distance
							good=good and sampled.rect.has_point(Vector2(point.x,point.z)) and camera.unproject_position(point).distance_to(screen)<0.03
				check("full physical viewport/depth slab incl negative boundary "+str(viewport_size)+" zoom="+str(zoom)+" at="+str(focus),good,str(sampled.get("rect")))
		viewport.free()
	var metadata:Dictionary=Interest.footprint(null,world)
	check("missing camera fails explicitly rather than claiming coverage",not metadata.ok)
	check("negative chunk boundaries use real metadata without loading cells",Interest.known_chunk_keys(world,Rect2(-15,-7,14,6))==["-2,0,-1","-1,0,-1"])
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.ok else profiles
	check("real current C/B/E normal source composes",prepared.ok,prepared.get("reason"))
	if prepared.ok:
		var host:=Client.new();var built:Dictionary=host._assemble(prepared.capture);host.free()
		check("same formal assembly configures sole authority",built.ok,built.get("reason"))
		if built.ok:
			var scheduler:=Scheduler.new();scheduler.attach(built.runtime,built.services.buildings,1,built.services.modules)
			var untouched:Dictionary=built.runtime.capture_checkpoint()
			scheduler.set_camera_interest(Rect2(-512,-512,1024,1024))
			var capacity:Dictionary=scheduler.camera_interest_status()
			check("finite scope is explicit and never allocates an unlimited camera map",not capacity.ok and capacity.code=="GENERATION_CAPACITY" and Data.json_equal(untouched,built.runtime.capture_checkpoint()))
			scheduler.set_camera_interest(Rect2(-16,-16,48,48))
			var before:Dictionary=built.runtime.capture_checkpoint()
			var selected:Dictionary=scheduler.request_camera_frontier()
			check("camera fringe requests a genuinely adjacent negative region",selected.ok and selected.code=="PENDING" and selected.region_id in ["R34:-1:0","R34:-1:-1"],selected)
			var began:int=Time.get_ticks_msec()
			while not scheduler.camera_interest_status().missing.is_empty() and Time.get_ticks_msec()-began<45000:
				var request:Dictionary=scheduler.request_camera_frontier()
				if not request.ok:break
				scheduler.poll(0,true);await process_frame
			check("full visible rectangle completes without diagonal island",scheduler.camera_interest_status().missing.is_empty(),scheduler.status())
			var exact:bool=true
			for key:String in before.world.chunks:
				if not Data.json_equal(before.world.chunks[key],built.world.chunk(key)):exact=false;break
			check("camera prep preserves every previously generated voxel",exact)
			check("camera prep never advances people, time, or gives held supplies",Data.json_equal(before.facts.actors,built.runtime.facts().actors) and before.facts.time==built.runtime.clock())
			check("one bounded generation worker remains authoritative",scheduler.status().worker_limit==1 and scheduler.status().peak_queue<=Scheduler.MAX_QUEUED)
			scheduler.shutdown()
			var limit_view:=SubViewport.new();limit_view.size=Vector2i(1280,800);limit_view.own_world_3d=true;root.add_child(limit_view)
			var limit_camera:=Camera3D.new();limit_camera.projection=Camera3D.PROJECTION_ORTHOGONAL;limit_camera.near=0.1;limit_camera.far=600;limit_camera.size=400;limit_view.add_child(limit_camera)
			limit_camera.position=Vector3(24,49,31);limit_camera.look_at(Vector3(0,20,0))
			var limit_host:=Client.new();limit_host._world_epoch=1
			var original:Dictionary=built.runtime.capture_checkpoint()
			var limit_candidate:Dictionary={"camera":limit_camera,"world":built.world,"runtime":built.runtime,"services":built.services,"world_epoch":1}
			var primed:Dictionary=await limit_host._prime_candidate_camera(limit_candidate)
			check("finite capacity cannot make an otherwise valid world unloadable",primed.ok and limit_candidate.get("frontier_boundary",{}).get("code")=="GENERATION_CAPACITY",primed)
			check("finite boundary preparation preserves exact existing world and people",Data.json_equal(original,built.runtime.capture_checkpoint()))
			limit_host._regions.shutdown();limit_host.free();limit_view.free()
	finish()
func finish()->void:
	var report:Dictionary={"scope":"source/headless actual camera projection and sole region scheduler; not OS/VA/FPS","checks":checks,"failed":checks.filter(func(row:Dictionary)->bool:return not row.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
