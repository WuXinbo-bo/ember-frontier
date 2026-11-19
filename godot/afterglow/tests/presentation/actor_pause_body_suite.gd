extends "res://tests/buildings/domain_suite.gd"
## Real authority/GLB, explicit HP lifecycle fixtures. No native frame/VA claim.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Definitions=preload("res://scripts/runtime/content_definitions.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")

class DescriptorFixture:
	extends "res://scripts/presentation/actor_view.gd"
	var descriptor:Dictionary={}
	func _body_definition(_id:String)->Dictionary:
		return descriptor.duplicate(true)

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("same finite source world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var facts:Dictionary=runtime.facts();facts.actors[0].faction="infected";facts.actors[0].appearance_id="infected_walker"
	expect("explicit living infected uses actual authority",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var view:=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	var body:Dictionary=Definitions.body_definition(runtime.actor("player").body_profile_id)
	var shapes:Array=view.roots.player.find_children("*","CollisionShape3D",true,false)
	expect("actual original rig mounts one selection shape",shapes.size()==1)
	if shapes.size()!=1:view.free();finish(started);return
	var capsule:CapsuleShape3D=shapes[0].shape
	expect("selection capsule consumes same public body dimensions",is_equal_approx(capsule.radius,float(body.radius)) and is_equal_approx(capsule.height,float(body.height)))
	expect("selection capsule centre uses same public body height",is_equal_approx(shapes[0].position.y,float(body.height)*0.5))
	var tx:=Draft.new(actions.context);tx.actor("player").hp=0.0
	expect("explicit HP transition commits through actual lifecycle",runtime._commit(tx.result()).ok)
	view.sync(0.025)
	var tilt:float=view.roots.player.rotation.z
	expect("live incapacitation has a partial interpolated tilt",tilt>0.0 and tilt<PI*0.5,tilt)
	runtime.set_paused(true)
	var frozen:Transform3D=view.roots.player.transform
	var before:Dictionary=runtime.capture_checkpoint()
	for dt:float in [0.016,0.05,0.2,0.016]:view.sync(dt)
	expect("paused incapacitation freezes whole root pose",view.roots.player.transform.is_equal_approx(frozen),{"before":str(frozen),"after":str(view.roots.player.transform)})
	expect("paused fallback clip remains frozen",is_zero_approx(view._animations.player.speed_scale))
	expect("paused rendering writes no HP position clock or intent",Data.json_equal(before,runtime.capture_checkpoint()))
	runtime.set_paused(false);view.sync(0.025)
	expect("resume continues from frozen partial tilt",view.roots.player.rotation.z>tilt and view.roots.player.rotation.z<PI*0.5,view.roots.player.rotation.z)
	view.free();view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	expect("restored incapacitated infected starts lying at sync zero",is_equal_approx(view.roots.player.rotation.z,PI*0.5),view.roots.player.rotation.z)
	runtime.set_paused(true);view.free();view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	expect("mounting paused incapacitated snapshot still establishes lying pose",is_equal_approx(view.roots.player.rotation.z,PI*0.5) and is_zero_approx(view._animations.player.speed_scale))
	runtime.set_paused(false)
	tx=Draft.new(actions.context);tx.actor("player").hp=100.0
	expect("actual recovery accepts retained body and identity",runtime._commit(tx.result()).ok)
	view.sync(0)
	expect("recovery clears lying pose and fallback state",is_zero_approx(view.roots.player.rotation.z) and view._states.player=="Idle")
	before=runtime.capture_checkpoint();view.sync(0.025)
	expect("body consumer and recovery rendering preserve full authority",Data.json_equal(before,runtime.capture_checkpoint()))
	descriptor_cases(body)
	view.free()
	finish(started)

func descriptor_cases(source:Dictionary)->void:
	var before:Dictionary=runtime.capture_checkpoint()
	var detached:Dictionary=Definitions.body_definition(Actors.BODY_PROFILE_ID);detached.radius=9.0
	expect("public body returned copy cannot alter next consumer",Definitions.body_definition(Actors.BODY_PROFILE_ID).radius==source.radius)
	var fixture:=DescriptorFixture.new();root.add_child(fixture);fixture.runtime=runtime;fixture.set_process(false)
	var actor:Dictionary=runtime.actor("player");actor.id="ddd:body-descriptor-fixture"
	# This is a deliberately replaced provider only in a local test subclass,
	# not a registered body, new population or change to the authority's metric.
	fixture.descriptor=source.duplicate(true);fixture.descriptor.radius=0.3;fixture.descriptor.height=2.0
	var node:Node3D=fixture._spawn(actor,0)
	var shapes:Array=node.find_children("*","CollisionShape3D",true,false)
	expect("detached provider fixture proves render dimensions are not hardcoded",shapes.size()==1 and is_equal_approx(shapes[0].shape.radius,0.3) and is_equal_approx(shapes[0].shape.height,2.0) and is_equal_approx(shapes[0].position.y,1.0))
	fixture._retire_actor(str(actor.id))
	var cases:Array=[{},source.merged({"id":"wrong-body"},true)]
	for radius:Variant in [0.0,-1.0,"0.26",NAN,INF]:cases.append(source.merged({"radius":radius},true))
	for height:Variant in [0.0,-1.0,0.3,"1.8",NAN,INF]:cases.append(source.merged({"height":height},true))
	for i:int in cases.size():
		fixture.descriptor=cases[i];node=fixture._spawn(actor,0)
		var report:Dictionary=fixture.assembly_report()
		var code:String="BODY_PROFILE_UNKNOWN" if cases[i].is_empty() else "BODY_DEFINITION_INVALID"
		expect("bad body descriptor rejects assembly without selection shape "+str(i),not report.ok and node.get_child_count()==0 and report.required_errors.any(func(issue:Dictionary)->bool:return issue.code==code and issue.requirement=="body_profile_id"),report)
		fixture._retire_actor(str(actor.id))
	fixture.free()
	expect("all detached descriptor counterexamples preserve full authority",Data.json_equal(before,runtime.capture_checkpoint()))

func finish(started:int)->void:
	var result:Dictionary={"scope":"actual runtime/public body/original GLB with explicit HP fixtures; not OS or VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_PAUSE_BODY "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
