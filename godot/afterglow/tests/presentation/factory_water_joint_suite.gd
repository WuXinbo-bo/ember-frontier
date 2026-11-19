extends "res://tests/modules/factory_boundary_fixture.gd"
## Real C6 generation/B registration/Native/owner work/B renderer/D consumers.
## Initial site placement, material, hammer and knowledge are explicit fixtures.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const BuildingsView=preload("res://scripts/buildings/building_view.gd")
const WaterView=preload("res://scripts/presentation/factory_water_view.gd")
const FactoryView=preload("res://scripts/presentation/factory_view.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")

func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("actual content6 C/B/A preparation",opening.ok,opening.get("reason"))
	if not opening.ok:finish();return
	var capture:Dictionary=opening.capture;var source:Dictionary=capture.world.extensions[Modules.KEY].water.sources[0]
	put_actor(capture,source.use_point)
	var a:Dictionary=Draft.find(capture.facts.actors,"player");a.pack["timber"]=2;a.pack["scrap"]=2
	capture.world.extensions["r3:production"].knowledge["player"]=["basic_tool_repair"]
	var tool_id:String=""
	for t:Dictionary in capture.world.extensions["r3:production"].tools:
		if t.kind=="hammer":t.holderId="pack:player";tool_id=t.id;break
	var mounted:Dictionary=mount(capture,"WT01 D finite input fixture")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime
	var building_view:Node3D=BuildingsView.new();root.add_child(building_view);building_view.set_process(false);building_view.service=mounted.services.buildings
	var factory_view:Node3D=FactoryView.new();root.add_child(factory_view);factory_view.set_process(false);factory_view.configure(rt)
	var actors:Node3D=Actors.new();root.add_child(actors);actors.set_process(false);actors.configure(rt)
	var e:Dictionary=rt.world.entity(source.id);var original:Dictionary=rt.capture_checkpoint()
	building_view.sync_entity_object(source.id,e)
	var fixture:Node3D=building_view.objects.get(source.id)
	check("real B entity branch mounts exactly one D fixture",fixture!=null and fixture.get_meta("water_source_id","")==source.id and building_view.objects.size()==1 and get_nodes_in_group(WaterView.GROUP).size()==1)
	if fixture==null:actors.free();factory_view.free();building_view.free();finish();return
	check("unknown real source is physical without public balance",fixture.get_meta("water_state")=="unknown" and mounted.services.modules.water_projection().sources.is_empty())
	check("B anchor agrees exactly with original world entity",fixture.global_position==G.point(e.position) and fixture.get_meta("piece")==e and not fixture.has_meta("remaining"))
	check("mount never edits authority or collisions",Data.json_equal(original,rt.capture_checkpoint()) and e.data.solid and e.data.opaque and e.blocksTerrain)
	check("real discover command accepted",command(rt,"module.water.discover",source.id).ok)
	factory_view.sync()
	check("real owner source becomes known only after discover",fixture.get_meta("public_known") and fixture.get_meta("water_state")=="needs_repair")
	var repair:Dictionary=command(rt,"module.water.repair",source.id,{"source_id":"pack:player","tool_id":tool_id},"player","D:water:repair")
	check("actual repair accepted",repair.ok,{"ok":repair.ok,"code":repair.get("code")})
	if not repair.ok:actors.free();factory_view.free();building_view.free();finish();return
	tick(rt,3);factory_view.sync();actors.sync(0)
	var work:Dictionary=rt.actor_presentation().work.player
	var point:=Vector3(work.contact.position[0],work.contact.position[1],work.contact.position[2])
	var normal:Vector3=G.point(source.use_point)-G.point(source.position);normal.y=0;normal=normal.normalized()
	check("B repair contact lies on D apparatus plate",point.is_equal_approx(G.point(source.position)+normal*.46+Vector3.UP*.73) and work.tool_id==tool_id)
	check("real B work drives D original rig and original hammer",actors._states.player=="Use" and actors._held_ids.player==tool_id and actors.statistics().work.player.active)
	check("repair display uses exact owner progress",is_equal_approx(float(fixture.get_meta("work_phase")),fposmod(float(work.progress_seconds),1.0)) and not fixture.get_node("Assembly/stream").visible)
	var held:Dictionary=command(rt,"module.water.held",source.id,{"held":false});tick(rt,1);factory_view.sync();actors.sync(0)
	check("real held pause stops work and preserves real carried pack",held.ok and rt.actor("player").intent.held==false and not fixture.get_node("Assembly/stream").visible and actors._states.player==("Carry" if Actors.is_carrying(rt.actor("player")) else "Idle"),{"actual_state":actors._states.player,"actual_carry":Actors.is_carrying(rt.actor("player")),"work":actors.statistics().work.player})
	command(rt,"module.water.held",source.id,{"held":true})
	for i:int in 170:
		rt.tick(.1)
		if rt.actor("player").intent==null:break
	factory_view.sync();actors.sync(0)
	check("actual paid completion swaps intact repaired geometry",fixture.get_meta("water_state")=="ready" and fixture.get_node("Assembly/lever").visible and not fixture.get_node("Assembly/loose").visible and rt.actor("player").pack.timber==0 and rt.actor("player").pack.scrap==0)
	var water_before:float=float(rt.actor("player").pack.get("water",0))
	check("actual draw accepted",command(rt,"module.water.draw",source.id,{"output_id":"pack:player"},"player","D:water:draw").ok)
	tick(rt,3);factory_view.sync();actors.sync(0);work=rt.actor_presentation().work.player
	point=Vector3(work.contact.position[0],work.contact.position[1],work.contact.position[2])
	var actual_grip:Vector3=fixture.get_node("Assembly").global_transform*(fixture.get_node("Assembly/lever").transform*Vector3(0,.24,0))
	check("actual draw contact follows the real moving lever grip",point.distance_to(actual_grip)<.0001 and work.tool_id=="",{"owner":point,"actual_mesh_grip":actual_grip,"gap":point.distance_to(actual_grip)})
	check("same real draw opens fixture and original bare hand",fixture.get_node("Assembly/stream").visible and actors._states.player=="Use" and not actors._props.has("player") and actors.statistics().work.player.has("hand_contact"))
	check("actual original palm meets physical lever within four cm",float(actors.statistics().work.player.hand_contact.gap_meters)<.04,actors.statistics().work.player)
	var samples:Array=[];var all_contact:=true
	for sample:int in 12:
		tick(rt,3);factory_view.sync();actors.sync(0)
		var frame:Dictionary=actors.statistics().work.player
		actual_grip=fixture.get_node("Assembly").global_transform*(fixture.get_node("Assembly/lever").transform*Vector3(0,.24,0))
		var palm:Vector3=frame.hand_contact.palm_world
		all_contact=all_contact and palm.distance_to(actual_grip)<.04 and float(frame.hand_contact.shoulder_degrees)<=110.001 and float(frame.posture.degrees)<=35.001
		samples.append({"progress":frame.progress_seconds,"actual_palm_grip_gap_m":palm.distance_to(actual_grip),"hinge_degrees":frame.posture.degrees,"shoulder_degrees":frame.hand_contact.shoulder_degrees})
	check("twelve real progress phases keep palm on physical lever with bounded joints",all_contact,samples)
	rt.set_paused(true);factory_view.sync();actors.sync(0)
	check("global pause closes flow with unchanged paid progress",not fixture.get_node("Assembly/stream").visible and is_zero_approx(actors._animations.player.speed_scale))
	rt.set_paused(false)
	for i:int in 125:
		rt.tick(.1)
		if rt.actor("player").intent==null:break
	factory_view.sync();actors.sync(0)
	check("one actual completed draw gives exactly water1 and dry idle",mounted.services.modules.water_projection().sources[0].remaining==47 and float(rt.actor("player").pack.get("water",0))==water_before+1 and not fixture.get_node("Assembly/stream").visible)
	var before_view:Dictionary=rt.capture_checkpoint();var old:WeakRef=weakref(fixture)
	building_view.sync_entity_object(source.id,e);fixture=building_view.objects[source.id];factory_view.sync()
	check("B replacement frees old node without duplicate body",old.get_ref()==null and get_nodes_in_group(WaterView.GROUP).size()==1 and fixture.get_meta("water_state")=="ready")
	var restored:Dictionary=mount(before_view,"WT01 D actual cold")
	check("cold restore preserves same finite source and actual work ledger",restored.ok and Data.json_equal(mounted.services.modules.state(),restored.services.modules.state()))
	check("all presentation refreshes leave exact facts untouched",Data.json_equal(before_view,rt.capture_checkpoint()))
	evidence.append({"source_id":source.id,"source_position":source.position,"use_point":source.use_point,"tool_id":tool_id,"repair_contact_height":.73,"draw_contact":"exact real moving lever local grip (0,.24,0)","remaining":47,"scope":"real C6/B/A commands and B physical branch, finite supplied initial inputs/site; not normal player route or unchanged22 package qualification"})
	actors.free();factory_view.free();building_view.free()
	check("released B parent leaves no water scene-group nodes",get_nodes_in_group(WaterView.GROUP).is_empty())
	finish()
