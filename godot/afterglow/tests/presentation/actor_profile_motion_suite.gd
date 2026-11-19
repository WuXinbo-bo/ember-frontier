extends "res://tests/buildings/domain_suite.gd"
## Persisted appearance remains authoritative when gameplay faction changes.
## Explicit faction/hit/HP facts are local compatibility fixtures, not new rules.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("same finite source loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	for profile:String in ["r1_resident_commuter","infected_walker"]:
		var facts:Dictionary=runtime.facts()
		var actor:Dictionary=facts.actors[0];actor.appearance_id=profile;actor.faction="infected" if profile.begins_with("r1_resident") else "human";actor.hp=100.0;actor.attack_until=0.0
		expect("saved profile and explicit changed faction accepted "+profile,runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
		view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
		var to:Dictionary=Geometry.location(runtime.actor("player"));to.x+=0.22 if actor.faction=="infected" else 0.28
		expect("actual faction movement budget accepts walk "+profile,command("direct_move","",{"movement_mode":"walk","movement_dt":0.1},to).ok)
		view.sync(0.016)
		var motion:Dictionary=runtime.actor_presentation().movement.player
		var reference:float=2.8 if profile.begins_with("r1_resident") else 2.2
		expect("gait calibration follows actual rig rather than faction "+profile,view._states.player=="Walk" and is_equal_approx(view._animations.player.speed_scale,float(motion.speed)/reference),view._animations.player.speed_scale)
		runtime.tick(0.2);view.sync(0.016)
		var tx:=Draft.new(actions.context);tx.actor("player").attack_until=runtime.clock()+0.25
		expect("existing attack timestamp commits "+profile,runtime._commit(tx.result()).ok)
		var before:Dictionary=runtime.capture_checkpoint();view.sync(0.016)
		var state:String="Use" if profile.begins_with("r1_resident") else "Attack"
		expect("attack uses existing bound model clip "+profile,view._states.player==state and view.assembly_report().ok,{"state":view._states.player,"assembly":view.assembly_report()})
		expect("attack projection preserves saved identity and faction "+profile,Data.json_equal(before,runtime.capture_checkpoint()) and view.roots.player.get_meta("profile_id")==profile)
		tx=Draft.new(actions.context);tx.actor("player").hp=0.0
		expect("same saved identity can become incapacitated "+profile,runtime._commit(tx.result()).ok)
		view.sync(0)
		var tilt:float=0.0 if profile.begins_with("r1_resident") else PI*0.5
		state="RestLying" if profile.begins_with("r1_resident") else "Idle"
		expect("incapacitation does not double rotate or leave frozen model upright "+profile,is_equal_approx(view.roots.player.rotation.z,tilt) and view._states.player==state,{"tilt":view.roots.player.rotation.z,"state":view._states.player})
		view.free()
	var result:Dictionary={"scope":"saved appearances on actual authority/original GLB; explicit faction/attack/HP fixtures, no new gameplay or VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_PROFILE_MOTION "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
