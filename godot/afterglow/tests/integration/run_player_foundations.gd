extends SceneTree
## Production player entry and movement under an isolated store; never live saves.
const Client=preload("res://scripts/runtime/native_client.gd")
const Router=preload("res://scripts/input/input_router.gd")
const State=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Movement=preload("res://scripts/runtime/movement_policy.gd")
class TestClient extends Client:
	func _ready()->void:pass
class TestRouter extends Router:
	func _persist_bindings()->bool:return true
var checks:Array=[]
var host:Node3D
var output:String
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+name+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	check("startup defaults to fresh random map",Client.startup_options([])=={"ok":true,"resume":false,"seed":-1})
	check("explicit continue and fixed seed are independent",Client.startup_options(["--continue","--seed=12"])=={"ok":true,"resume":true,"seed":12})
	check("invalid seed rejected",not Client.startup_options(["--seed=wrong"]).ok)
	check("relative QA root rejected",not Client.startup_options(["--qa-data-root=relative"]).ok)
	check("resource QA root rejected",not Client.startup_options(["--qa-data-root=user://qa"]).ok)
	var qa_root:String=output+"/marked-qa"
	var options:Dictionary=Client.startup_options(PackedStringArray(["--qa-data-root="+qa_root,"--seed=713"]))
	check("absolute QA root is explicit opt-in",options.ok and options.qa_data_root==qa_root and options.seed==713)
	var storage_host:=TestClient.new()
	var original_store:RefCounted=storage_host.store
	check("missing QA marker refuses without touching normal paths",not storage_host.configure_startup_storage(options).ok and storage_host.store==original_store and storage_host.controls_path=="user://controls.json")
	DirAccess.make_dir_recursive_absolute(qa_root)
	var qa_marker:=FileAccess.open(qa_root+"/afterglow-qa-root.json",FileAccess.WRITE)
	qa_marker.store_string('{"schema":"wrong"}');qa_marker.close()
	check("invalid QA marker refuses",not storage_host.configure_startup_storage(options).ok and storage_host.store==original_store)
	qa_marker=FileAccess.open(qa_root+"/afterglow-qa-root.json",FileAccess.WRITE)
	qa_marker.store_string('{"schema":"afterglow-native-qa-root-v1"}');qa_marker.close()
	check("marked QA root redirects both Store and controls",storage_host.configure_startup_storage(options).ok and storage_host.store.root==qa_root+"/saves" and storage_host.controls_path==qa_root+"/controls.json")
	check("QA root cannot alias normal user root",not storage_host.configure_startup_storage({"qa_data_root":OS.get_user_data_dir()}).ok)
	storage_host.free()
	var exhausted:Dictionary={"hp":100.0,"stamina":10.2,"fatigue":0,"run_recovering":true}
	check("recovery hysteresis avoids run walk threshold flicker",Movement.budget(exhausted,0.1,"run",0).mode=="walk")
	exhausted.stamina=20.0
	check("recovered stamina permits run again",Movement.budget(exhausted,0.1,"run",0).mode=="run")
	var w:=State.new();w.load_snapshot(Rural.generate(713))
	var a:Dictionary={"id":"player","name":"movement fixture","x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":90.0,"thirst":90.0,"stamina":80.0,"fatigue":0.0,"pack":{},"intent":null}
	var r:=Runtime.new();check("movement fixture uses real action runtime",r.configure({"world":w,"facts":{"actors":[a],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"buildings":Buildings.new(),"actions":Actions.new(),"production":Production.new()}}).ok)
	var dest:=Geometry.location(a);dest.x+=0.46
	var moved:Dictionary=r.command({"command_id":"actual-run","kind":"direct_move","actor_id":"player","destination":dest,"payload":{"movement_dt":0.1,"movement_mode":"run"}})
	check("run moves real swept body and charges distance once at 0.8 per metre",moved.ok and is_equal_approx(r.actor("player").x,29.66) and is_equal_approx(r.actor("player").stamina,79.632),moved)
	var same:Dictionary=r.command({"command_id":"actual-run","kind":"direct_move","actor_id":"player","destination":dest,"payload":{"movement_dt":0.1,"movement_mode":"run"}})
	check("command receipt replay cannot double charge",same.ok and is_equal_approx(r.actor("player").stamina,79.632))
	check("same clock has no extra distance budget",is_zero_approx(r.movement_budget("player",0.1,"run").max_distance))
	check("presentation derives run from real motion",r.actor_presentation().movement.player.moving and r.actor_presentation().movement.player.mode=="run")
	r.tick(0.1)
	check("run does not receive idle recovery",is_equal_approx(r.actor("player").stamina,79.632),r.actor("player").stamina)
	r.tick(0.2)
	check("idle resumes recovery and stops motion",r.actor("player").stamina>79.632 and not r.actor_presentation().movement.player.moving)
	var router:=TestRouter.new();root.add_child(router);router.configure(r);router.set_physics_process(false)
	var shift:=InputEventKey.new();shift.physical_keycode=KEY_SHIFT;shift.pressed=true;shift.shift_pressed=true
	var forward:=InputEventKey.new();forward.physical_keycode=KEY_W;forward.pressed=true;forward.shift_pressed=true
	router._unhandled_input(shift);router._unhandled_input(forward)
	check("Shift then W holds independent run and forward",router.state().held.run and router._pressed.has("up"),router._pressed)
	router.set_modal(true);router.set_modal(false)
	check("panel release clears run and movement",not router.state().held.run and router._pressed.is_empty())
	router._unhandled_input(shift);router.set_window_focus(false);router.set_window_focus(true)
	check("focus release does not resume run",not router.state().held.run)
	router.free()
	host=TestClient.new();host.controls_path=output+"/isolated-controls.json";root.add_child(host);host.store=Store.new(output+"/isolated-saves")
	check("old fixture mounts",host._new_rural(713).ok)
	host.runtime.set_paused(true);var oldsave:Dictionary=await host.save_async("fixture")
	check("old fixture explicitly saved",oldsave.ok)
	var pointer_path:String=output+"/isolated-saves/active.json"
	var original_pointer:String=FileAccess.get_file_as_string(pointer_path)
	var oldbytes:String=FileAccess.get_file_as_string(oldsave.path)
	var fresh:Dictionary=await host.start_new_world(12,"fresh-ready-test")
	check("new generated test world mounts",fresh.ok,fresh)
	if fresh.ok:
		host.runtime.set_paused(true)
		check("fresh map never writes active pointer or old slot",FileAccess.get_file_as_string(pointer_path)==original_pointer and FileAccess.get_file_as_string(oldsave.path)==oldbytes)
		var tools:Array=host.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player")
		check("five real unique durable tools are in player pack",tools.size()==5 and tools.all(func(t:Dictionary)->bool:return float(t.durability)==100.0),tools)
		check("shovel selected in real shortcut bar",host.router.held_reference().id=="playtest:player:shovel" and host.runtime.tool(host.router.held_reference().id).holderId=="pack:player")
		check("finite food water and materials disclosed",host.runtime.snapshot().playtest.id=="ready-to-test-v1" and host.runtime.actor("player").pack.food==4 and host.runtime.actor("player").pack.soil_m3==2.0)
		host.runtime.set_paused(false)
		var eat:Dictionary=host.runtime.command({"kind":"eat","actor_id":"player","command_id":"eat-test"})
		for i:int in 13:host.runtime.tick(0.1)
		check("eating consumes exactly one real ration",eat.ok and host.runtime.actor("player").pack.food==3)
		host.runtime.set_paused(true)
		var saved:Dictionary=await host.save_async("manual-test")
		check("first manual save gets fresh namespace",saved.ok and FileAccess.get_file_as_string(pointer_path)!=original_pointer and FileAccess.get_file_as_string(oldsave.path)==oldbytes,saved)
		var restored:Dictionary=host.store.load_current()
		var built:Dictionary=host._assemble(restored.capture) if restored.ok else restored
		check("explicit restore keeps tool IDs wear and ration without grant",built.ok and built.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player").size()==5 and built.runtime.actor("player").pack.food==3)
		var restored_ui:Dictionary=await host.runtime.restore_saved_world("explicit-visible-restore")
		check("visible restore callback mounts actual saved authority without regrant",restored_ui.ok and host.runtime.actor("player").pack.food==3 and host.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player").size()==5,restored_ui)
	finish()
func finish()->void:
	var report:Dictionary={"scope":"actual production input/runtime/fresh async entry/manual save in isolated store; not OS/app/VA","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));if host!=null:host.free()
	quit(1 if report.failed else 0)
