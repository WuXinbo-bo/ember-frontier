extends "res://tests/buildings/continuous_boundary_suite.gd"
## A's input/social projection must consume B/C continuous outdoor proof too.
const Direct=preload("res://scripts/input/direct_interaction.gd")
const Router=preload("res://scripts/input/input_router.gd")
class TestRouter extends Router:
	func _persist_bindings()->bool:return true
func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(713,Building.generation_profiles()))
	expect("actual current generated assembly prepares",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	host=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
	expect("formal native assembler configures",assembled.ok)
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;host_services=assembled.services
	building=host_services.buildings;actions=host_services.actions;production=host_services.production
	var candidates:=shared_candidates(world.region("RH-HOME"),world.region("RH-VILLAGE"))
	expect("real seam supports close actors away from exit",not candidates.is_empty())
	if candidates.is_empty():host.free();finish(started);return
	var pair:Dictionary=candidates[0];var capture:=runtime.capture_checkpoint()
	for actor:Dictionary in capture.facts.actors:
		if actor.id=="player":actor.merge(pair.from,true);actor.intent=null
		elif actor.id=="village-resident":actor.merge(pair.to,true);actor.intent=null
	runtime.configure({"world":world,"facts":capture.facts,"source":capture.source,"services":host_services})
	var ready:=runtime.availability({"kind":"talk","actor_id":"player","target_id":"village-resident"})
	expect("near resident across continuous outdoor boundary can talk",ready.ok,ready)
	expect("same visible resident enters render and UI projection","village-resident" in runtime.actor_presentation().visible_actor_ids and runtime.snapshot().actors.any(func(a:Dictionary)->bool:return a.id=="village-resident"))
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Geometry.point(pair.from)+Vector3(12,18,14);camera.look_at(Geometry.point(pair.to));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	var router:=TestRouter.new();root.add_child(router);router.configure(runtime);router.set_physics_process(false)
	var direct:=Direct.new();direct.runtime=runtime;direct.world=world;direct.buildings=building;direct.router=router;direct.camera=camera;direct._entities=world.entities()
	var target:Dictionary=direct._nearby_target(runtime.actor("player"),runtime.actor_presentation(),camera.unproject_position(Geometry.point(pair.to)))
	expect("nearby input no longer filters resident solely by region ID",target.get("primary")=="npc" and target.get("id")=="village-resident" and target.get("enabled",false),target)
	var result:=command("talk","village-resident")
	expect("real social command commits without teleport or free consent",result.ok and runtime.actor("village-resident").relationship.met and not runtime.actor("village-resident").relationship.member,result)
	var from:=Geometry.point(pair.from);var to:=Geometry.point(pair.to);var middle:=from.lerp(to,0.5)
	var owner:Dictionary=world.region_at(Geometry.json_point(middle))
	var wall:Dictionary={"id":"fixture:social-wall","kind":"prop","regionId":owner.id,"position":Geometry.json_point(middle),"bounds":Geometry.json_box(AABB(middle+Vector3(-0.05,0,-0.05),Vector3(0.10,2,0.10))),"revision":0,"data":{"solid":true,"opaque":true}}
	var draft:Dictionary=world.prepare_changes([{"op":"entity.put","id":wall.id,"before_exists":false,"before":null,"after":wall}],world.get_revision())
	expect("actual opaque obstruction fixture commits",draft.ok and world.commit_prepared(draft.capability).ok)
	var before:=runtime.capture_checkpoint();ready=runtime.availability({"kind":"talk","actor_id":"player","target_id":"village-resident"})
	expect("continuous partition cannot bypass real social LOS or change facts",not ready.ok and runtime.capture_checkpoint()==before,ready)
	expect("opaque boundary still hides unknown resident","village-resident" not in runtime.actor_presentation().visible_actor_ids)
	direct.free();router.free();camera.free();host.free();host=null;finish(started)
