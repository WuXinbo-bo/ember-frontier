extends "res://tests/buildings/domain_suite.gd"
## Real generated rural-3 and B sight; explicit workbench/obstacle facts.
## No player construction, native frame, or VA is implied by these fixtures.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Device=preload("res://scripts/presentation/gameplay_view.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Data=preload("res://scripts/world/world_data.gd")

func commit(changes:Array,label:String)->bool:
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	var accepted:bool=draft.ok and world.commit_prepared(draft.capability).ok
	expect(label,accepted,draft.get("reason"))
	return accepted

func find_pair()->Dictionary:
	var edge:float=float(world.region("RH-HOME").bounds.min.z)
	var query:RefCounted=building.current_space()
	for x:int in range(3,61):
		var points:Array=[]
		for side:float in [1.0,-1.0]:
			var z:float=edge+side*3.0
			var y:Variant=world.surface_height(x,z)
			if y==null:continue
			var feet:Dictionary=query.standing_point({"x":float(x),"y":float(y),"z":z,"regionId":"RH-HOME" if side>0 else "RH-VILLAGE","buildingId":null,"storeyId":null})
			if not feet.is_empty() and feet.get("buildingId")==null:points.append(feet)
		if points.size()!=2 or not query.line_clear(points[0],points[1]):continue
		var bench:Dictionary=building.make_instance("workbench","ddd:boundary-station",points[1])
		if building.supported(query,bench):return {"from":points[0],"to":points[1],"bench":bench}
	return {}

func run()->void:
	var started:int=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	expect("actual current generated rural-3 prepares",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	expect("same C authority loads actual assembled world",world.load_snapshot(prepared.capture.world).ok)
	expect("same A authority accepts actual generated facts",runtime.configure({"world":world,"facts":prepared.capture.facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var warm:Array=[]
	for id:String in world.chunk_keys():
		if not world.chunk(id).get("resident",false):warm.append({"op":"chunk.residency","id":id,"before":false,"after":true})
	if not warm.is_empty():commit(warm,"explicit fixture warms real generated chunk residency")
	var pair:Dictionary=find_pair()
	expect("real supported clear six metre seam station exists",not pair.is_empty(),pair)
	if pair.is_empty():finish(started);return
	expect("sight coverage is independent of short hand contact",world.continuous_outdoor_segment(pair.from,pair.to,12.0,true).ok and not world.continuous_outdoor_contact(pair.from,pair.to).ok)
	var structures:Dictionary=building.structures();structures.instances.append(pair.bench)
	if not commit(building.changes_for(structures,[pair.bench],[]),"explicit supported B workbench installs through sole C capability"):finish(started);return
	var facts:Dictionary=runtime.facts()
	for a:Dictionary in facts.actors:
		if a.id=="player":a.merge(pair.from,true);a.intent=null
	expect("isolated observation uses actual runtime facts",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var device:=Device.new();root.add_child(device);device.configure(runtime,building);device.set_process(false)
	var entity:Dictionary=world.entity(pair.bench.id)
	expect("device consumer follows B sight across region labels beyond contact",device._can_observe(entity,runtime.actor("player")))
	pair.bench=device_lifecycle(device,pair.bench)
	if pair.bench.is_empty():device.free();finish(started);return
	entity=world.entity(pair.bench.id)
	var actors:=Actors.new();root.add_child(actors);actors.configure(runtime);actors.set_process(false)
	var a:Dictionary=runtime.actor("player");a.intent={"owner":"actions","kind":"structure","held":true,"target_id":entity.id}
	actors.roots.player.rotation.y=0.0
	var before:Dictionary=runtime.capture_checkpoint()
	actors._face_action(actors.roots.player,a,0)
	var direction:Vector3=Geometry.point(pair.to)-Geometry.point(pair.from)
	expect("explicit action-target facing no longer treats region label as wall",is_zero_approx(angle_difference(actors.roots.player.rotation.y,atan2(direction.x,direction.z))),{"actual":actors.roots.player.rotation.y,"expected":atan2(direction.x,direction.z)})
	var middle:Vector3=(Geometry.point(pair.from)+Geometry.point(pair.to))*0.5
	var blocker:Dictionary={"id":"ddd:boundary-sight-fixture","kind":"prop","regionId":pair.from.regionId,"position":Geometry.json_point(middle),"bounds":Geometry.json_box(AABB(middle+Vector3(-0.5,-1,-0.04),Vector3(1,4,0.08))),"revision":0,"data":{"solid":false,"opaque":true}}
	if commit([{"op":"entity.put","id":blocker.id,"before_exists":false,"before":null,"after":blocker}],"explicit opaque non-solid fixture installs"):
		expect("device remains hidden behind real opaque non-solid geometry",not device._can_observe(entity,runtime.actor("player")))
		blocker=world.entity(blocker.id)
		var clear:Dictionary=blocker.duplicate(true);clear.data={"solid":true,"opaque":false};clear.revision=1
		if commit([{"op":"entity.put","id":clear.id,"before_exists":true,"before":blocker,"after":clear}],"explicit transparent solid state replaces opaque state"):
			expect("device sight does not borrow contact rejection",device._can_observe(entity,runtime.actor("player")) and not building.current_space().contact_clear(pair.from,pair.to,entity.id))
	var cfg:Dictionary=world.config();var size:float=float(cfg.cellSize)*int(cfg.chunkCells)
	var key:String="%d,%d,%d"%[floori(middle.x/size),floori((middle.y+1.2)/size),floori(middle.z/size)]
	if commit([{"op":"chunk.residency","id":key,"before":true,"after":false}],"actual traversed chunk becomes cold in isolated fixture"):
		expect("cold cross-region data fails device sight closed",not device._can_observe(entity,runtime.actor("player")))
		actors.roots.player.rotation.y=0.0;actors._face_action(actors.roots.player,a,0)
		expect("cold data does not invent target-facing transition",is_zero_approx(actors.roots.player.rotation.y))
	before=runtime.capture_checkpoint();device._can_observe(entity,runtime.actor("player"));actors._face_action(actors.roots.player,a,0)
	expect("consumer reads leave all facts clock inventory and world unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
	actors.free();device.free();finish(started)

func device_lifecycle(device:Node3D,bench:Dictionary)->Dictionary:
	# This is a declared repaired-state fixture, not a performed RH repair.
	var state:Dictionary=world.extension(Gameplay.KEY);state.radio.status="repaired";state.radio.station_id=bench.id
	if not commit([building.extension_change(Gameplay.KEY,state)],"explicit repaired radio state installs for real station"):return {}
	device._process(0.2)
	expect("same live device consumes registered station and actual panel",device.statistics().station_id==bench.id and device.statistics().radio_visible and device.statistics().panel_registered,device.statistics())
	var old:Node3D=device._radio
	var data:Dictionary=building.structures();data.instances=data.instances.filter(func(v:Dictionary)->bool:return v.id!=bench.id)
	if not commit(building.changes_for(data,[],[bench.id]),"explicit ordinary workbench removal updates actual authority"):return {}
	device._process(0.2)
	expect("removed device leaves scene and clears all station material references",device._radio==null and device._panel==null and device._led==null and device.statistics().station_id.is_empty() and old.get_parent()==null)
	data=building.structures();data.instances.append(bench)
	var retired:Dictionary=world.prepare_changes(building.changes_for(data,[bench],[]),world.get_revision())
	expect("retired entity ID cannot be resurrected by presentation fixture",not retired.ok and retired.code=="RETIRED_ENTITY_ID",retired.get("code"))
	bench=bench.duplicate(true);bench.id=str(bench.id)+":replacement"
	data=building.structures();data.instances.append(bench);state.radio.station_id=bench.id
	var replacement_changes:Array=building.changes_for(data,[bench],[]);replacement_changes.append(building.extension_change(Gameplay.KEY,state))
	if not commit(replacement_changes,"replacement station uses a new legitimate entity ID"):return {}
	device._process(0.2)
	expect("replacement station remounts real device without configure",device._radio!=null and device._radio!=old and device.statistics().radio_visible and device.statistics().station_id==bench.id,device.statistics())
	var dead:Dictionary=bench.duplicate(true);dead.hp=0.0;dead.version=int(dead.version)+1
	data=building.structures()
	for i:int in data.instances.size():
		if data.instances[i].id==bench.id:data.instances[i]=dead
	if not commit(building.changes_for(data,[dead],[]),"explicit station HP loss uses actual structure facts"):return {}
	device._process(0.2)
	expect("destroyed station retires device instead of retaining hidden stale node",device._radio==null and device.statistics().station_id.is_empty())
	data=building.structures();var restored:Dictionary=bench.duplicate(true);restored.version=int(dead.version)+1
	for i:int in data.instances.size():
		if data.instances[i].id==bench.id:data.instances[i]=restored
	if not commit(building.changes_for(data,[restored],[]),"explicit actual station repair restores structure"):return {}
	device._process(0.2)
	expect("station HP recovery remounts state panel in same live view",device.statistics().radio_visible and device.statistics().panel_cell==1)
	return restored

func finish(started:int)->void:
	print("DDD_BOUNDARY "+JSON.stringify({"scope":"real generated source/shared C segment/B sight; explicit supported observations and obstacles, not OS/VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)
