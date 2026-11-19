extends "res://tests/buildings/domain_suite.gd"
## Real delivered actor rig + explicit public WT01 work DTO. No owner grant.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
class PresentedRuntime extends "res://scripts/runtime/game_runtime.gd":
	var presented_intent:Variant=null
	var fixture:Dictionary={}
	func actor_presentation()->Dictionary:
		var result:Dictionary=super.actor_presentation()
		for a:Dictionary in result.actors:
			if a.id=="player":a.intent=presented_intent
		result.work={"player":fixture.duplicate(true)}
		return result

func run()->void:
	runtime=PresentedRuntime.new()
	expect("finite rural source accepted",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var state:Dictionary=Production.empty_state()
	for kind:String in ["hammer","salvaged_axe"]:state.tools.append({"id":"water-fixture:"+kind,"kind":kind,"holderId":"pack:player","durability":1.0,"qualities":{}})
	var prepared:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,state)],world.get_revision())
	expect("finite real tool identities accepted",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var before:Dictionary=runtime.capture_checkpoint()
	runtime.presented_intent={"id":"water-fixture:intent","schema_version":1,"owner":"modules","kind":"water","project_id":"water-fixture:project","held":true}
	runtime.fixture={"owner":"modules","kind":"water","operation":"repair","tool_id":"water-fixture:hammer","progress_seconds":.25,"duration_seconds":16.0,"effective_work":true,"effective_seconds":.1,"paused_reason":"","contact":{"position":[30.0,.73,42.34],"normal":[0.0,0.0,1.0]}}
	var view:Node3D=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	var player:AnimationPlayer=view._animations.player
	expect("real water repair chooses original Use clip",view._states.player=="Use" and player.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	expect("hammer comes from actual work projection not missing intent field",view._held_ids.player=="water-fixture:hammer" and view._props.player.get_meta("tool_kind")=="hammer")
	var arm:Transform3D=view._arms.player.transform
	var progress:float=player.current_animation_position
	for delta:float in [.016,.4,1.0]:view.sync(delta)
	expect("same public repair progress never accrues wall animation",view._arms.player.transform.is_equal_approx(arm) and is_equal_approx(progress,player.current_animation_position))
	runtime.fixture.progress_seconds=.55;view.sync(0)
	expect("accepted repair progress changes original arm pose",not view._arms.player.transform.is_equal_approx(arm))
	for reason:String in ["missing_tool","material_not_at_site","output_full","region_paused","operator_not_at_water"]:
		runtime.fixture.effective_work=false;runtime.fixture.paused_reason=reason;view.sync(0)
		expect("water blocker stops real actor Use "+reason,view._states.player=="Idle" and not view.statistics().work.player.active)
	runtime.fixture.effective_work=true;runtime.fixture.paused_reason="";runtime.fixture.operation="draw";runtime.fixture.tool_id="";runtime.fixture.duration_seconds=12.0
	var angle:float=-.32-.08*sin(float(runtime.fixture.progress_seconds)*TAU)
	runtime.fixture.contact.position=[30.0,.86+.24*cos(angle),41.8+.46-.24*sin(angle)]
	var leg:Node3D=view.roots.player.find_child("leg_r",true,false);var foot:Transform3D=leg.global_transform
	view.sync(0)
	expect("draw uses actual original actor clip",view._states.player=="Use")
	expect("draw never waves selected or previous tool",view._held_ids.player=="" and not view._props.has("player"))
	expect("draw palm targets actual public tap without a fake bucket",view.statistics().work.player.has("hand_contact"))
	expect("original draw hand reaches real lever without foot movement",float(view.statistics().work.player.hand_contact.gap_meters)<.04 and leg.global_transform.is_equal_approx(foot),view.statistics().work.player)
	arm=view._arms.player.transform;view.sync(.4)
	expect("same actual draw progress preserves palm pose",view._arms.player.transform.is_equal_approx(arm))
	runtime.set_paused(true);view.sync(.1)
	expect("global pause freezes original draw arm",view._arms.player.transform.is_equal_approx(arm) and is_zero_approx(player.speed_scale))
	runtime.set_paused(false);runtime.fixture={};view.sync(0)
	expect("absent public provider cannot fabricate water work",view._states.player=="Idle" and not view.statistics().work.player.available)
	runtime.fixture={"owner":"actions","kind":"water","operation":"repair","tool_id":"water-fixture:hammer","progress_seconds":.5,"duration_seconds":16.0,"effective_work":true,"paused_reason":""};view.sync(0)
	expect("wrong owner cannot drive water work or tool",view._states.player=="Idle" and view._held_ids.player=="")
	runtime.presented_intent=null;runtime.fixture={};view.sync(0)
	expect("interruption stops manual work callback",not view._manual_work.has("player") and view._states.player=="Idle")
	expect("public consumer never changes body clock tool stock or authority intent",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free();await process_frame
	var result:Dictionary={"checks":checks,"failures":failures,"scope":"post22 D actor source overlay + immutable22 real GLB/runtime, synthetic presented intent/work DTO; not B labor validation or normal player route/VA"}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WT01_ACTOR "+str(checks.size())+" checks / "+str(failures.size())+" failures");quit(0 if failures.is_empty() else 1)
