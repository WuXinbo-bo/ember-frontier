extends SceneTree

const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const WorldView=preload("res://scripts/world/world_view.gd")
const EPOCH=34
const COORD=Vector2i(1,0)

var failures:int=0

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,label:String)->void:
	if not condition:
		failures+=1
		push_error(label)

func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[]))) if profiles.ok else profiles
	check(opening.ok,"Factory opening assembles")
	if not opening.ok:
		quit(1)
		return
	var host:=Client.new()
	var built:Dictionary=host._assemble(opening.capture)
	check(built.ok,"Native client assembles the factory runtime")
	if built.ok:
		await verify_publication(host,built)
	host.free()
	print("Factory worker fringe failures: ",failures)
	quit(0 if failures==0 else 1)

func verify_publication(host:Node3D,built:Dictionary)->void:
	var world:RefCounted=built.world
	var runtime:RefCounted=built.runtime
	var region_id:String=Factory.region_id(COORD)
	var original_revision:int=world.get_revision()
	var foreign_state:Dictionary=world.identity()
	foreign_state.revision=original_revision+1
	var foreign_world:=WorldView.new(foreign_state)
	var jobs:RefCounted=host._regions
	host._world_epoch=EPOCH
	jobs.attach(runtime,built.services.buildings,EPOCH,built.services.modules)

	# Both consumers receive the real synchronous terrain notification. Keep
	# their unrelated chunk rebuild queues idle during this test.
	var hinted:Node3D=world.create_view({"runtime":runtime})
	var baseline:Node3D=world.create_view({"runtime":runtime,"materials":hinted.materials})
	for terrain:Node3D in [hinted,baseline]:
		terrain.process_mode=Node.PROCESS_MODE_DISABLED
		terrain.set_streaming_updates(true)
		root.add_child(terrain)
	var observed:Dictionary={"hits":0,"notifications":0}
	hinted.environment.region_fringe_hint=func(subject:RefCounted,id:String)->Variant:
		var rows:Variant=host._region_fringe_hint(subject,id)
		if id==region_id and rows is Array:
			observed.hits+=1
		return rows
	var probe:=func(change:Dictionary)->void:
		var events:Array=change.get("events",[])
		if not events.any(func(event:Dictionary)->bool:return event.get("kind")=="region_generated" and event.get("region_id")==region_id):
			return
		observed.notifications+=1
		check(host._region_fringe_hint(world,region_id) is Array,"Current world, epoch and revision admit the hint during publication")
		check(host._region_fringe_hint(foreign_world,region_id)==null,"A different world object with the same identity and revision cannot use the hint")
		check(jobs.publication_fringe(world,EPOCH+1,region_id)==null,"A different epoch cannot use the hint")
		check(host._region_fringe_hint(world,"RH-HOME")==null,"A different region cannot use the hint")
		# Force a revision mismatch with world, region, epoch and scope fixed.
		var job:Dictionary=jobs._active
		var stamp:int=int(job.get("publication_revision",-1))
		check(stamp==world.get_revision(),"The hint targets the committed world revision")
		if stamp>=0:
			job.publication_revision=stamp+1
			check(host._region_fringe_hint(world,region_id)==null,"A different revision cannot use the hint")
			job.publication_revision=stamp
	runtime.changed.connect(probe)

	var request:Dictionary=jobs.request(COORD)
	check(request.ok,"Factory region worker starts")
	var deadline:int=Time.get_ticks_msec()+60000
	while request.ok and not jobs._active.has("draft") and Time.get_ticks_msec()<deadline:
		await process_frame
		jobs.poll(0.0,false)
	check(jobs._active.has("draft") and jobs._active.get("fringe") is Array,"Worker returns a detached fringe beside the region draft")
	if jobs._active.has("draft"):
		for stage:String in ["prepared","family"]:
			await process_frame
			var pending:Dictionary=jobs.poll(0.0,true)
			check(pending.is_empty() and jobs._active.has(stage) and world.get_revision()==original_revision,"Stage %s leaves authority unpublished"%stage)
			check(host._region_fringe_hint(world,region_id)==null,"Hint stays private during stage %s"%stage)
		await process_frame
		var result:Dictionary=jobs.poll(0.0,true)
		check(result.get("ok",false) and result.get("region_id")==region_id and world.get_revision()==original_revision+1,"Final stage commits the requested region once")
		check(observed.notifications==1 and observed.hits==1,"The hinted view consumes the worker fringe during its first notification")
		var actual:Node3D=hinted.environment
		var expected:Node3D=baseline.environment
		var expected_rows:Array=expected._presentation_layouts.get(region_id,[])
		check(not expected_rows.is_empty() and actual._presentation_layouts.get(region_id)==expected_rows,"Worker and synchronous paths produce the same ordered layout")
		var visible:Dictionary={}
		for node:Node3D in actual._ecology.values():
			for id:String in node.get_meta("presentation_patch_ids",[]):
				visible[id]=true
		check(expected_rows.any(func(row:Dictionary)->bool:return visible.has(row.id)),"The fixture includes visible fringe in the newly published region")
		check(actual._ecology_signatures==expected._ecology_signatures,"Both views keep identical visible patches after live soil and coverage checks")
		check(host._region_fringe_hint(world,region_id)==null,"The hint expires when the synchronous commit returns")
		print("Factory publication environment usec: ",{"worker_hint":hinted.statistics().last_environment_sync_usec,"synchronous":baseline.statistics().last_environment_sync_usec})

	runtime.changed.disconnect(probe)
	jobs.shutdown()
	hinted.free()
	baseline.free()
