extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Shell=preload("res://scripts/runtime/startup_shell.gd")
var checks:Array=[]
class RuntimeStub extends RefCounted:
	signal close_failed(result:Dictionary)
	signal changed(event:Dictionary)
	var paused:bool=false
	var captured_paused:bool=false
	func set_paused(value:bool)->void:paused=value
	func capture_checkpoint()->Dictionary:
		captured_paused=paused
		return {}
	func clock()->float:return 0
	func get_revision()->int:return 0
class StoreStub extends Native.Store:
	var fail:bool=false
	func begin_save(_capture:Dictionary,_fresh:bool=false,_original:String="",_activate:bool=true)->Dictionary:
		return {"ok":not fail,"code":"IO_ERROR" if fail else "OK","reason":"injected write failure" if fail else "saved"}
	func poll()->Dictionary:return {"ok":true,"code":"OK"}
class SavingFixture extends Native:
	func _ready()->void:
		_shell=Shell.new();add_child(_shell)
	func _process(_delta:float)->void:pass
class ClosingFixture extends Native:
	func _ready()->void:
		_shell=Shell.new();add_child(_shell)
	func _process(_delta:float)->void:pass
	func save_async(_request_id:String="")->Dictionary:
		return {"ok":false,"code":"IO_ERROR","reason":"injected write failure"}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	check("no arguments selects menu",not Native.startup_options([]).direct)
	check("seed alone keeps menu",not Native.startup_options(["--seed=713"]).direct)
	check("normal CLI selects direct path",Native.startup_options(["--normal-profile"]).direct)
	check("playtest CLI selects direct path",Native.startup_options(["--playtest"]).new_world_profile=="playtest")
	check("continue CLI selects direct path",Native.startup_options(["--continue"]).direct and Native.startup_options(["--continue"]).resume)
	check("conflicting opening profiles fail closed",not Native.startup_options(["--normal-profile","--playtest"]).ok)
	check("invalid seed fails closed",not Native.startup_options(["--seed=-1"]).ok)
	var args:PackedStringArray=OS.get_cmdline_user_args();var out:String=args[0] if not args.is_empty() else "user://lifecycle15"
	var node:=Native.new();node.store=preload("res://scripts/storage/native_store.gd").new(out+"/missing-save-"+str(Time.get_ticks_usec()));root.add_child(node);await process_frame
	check("actual Native ready enters menu without world authority",node.lifecycle_status().state=="menu" and node.runtime==null and not node._ready_game)
	var shell:CanvasLayer=node._shell
	check("menu contains four real native buttons",shell._buttons.get_child_count()==4)
	# Real Viewport dispatch on the presented native button, not its callback.
	shell.chosen.disconnect(node._shell_action)
	var actions:Array=[];shell.chosen.connect(func(action:String):actions.append(action))
	await process_frame;await process_frame
	var target:Button=shell._buttons.get_child(0)
	var point:Vector2=target.get_global_rect().get_center()
	var move:=InputEventMouseMotion.new();move.position=point;root.push_input(move,true);await process_frame
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=point;press.pressed=true;root.push_input(press,true);await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=point;release.pressed=false;root.push_input(release,true)
	await process_frame
	if actions.is_empty():print(JSON.stringify({"button_rect":str(target.get_global_rect()),"root_rect":str(root.get_visible_rect()),"shell_size":str(shell._root.size),"shade_size":str(shell._shade.size),"hovered":str(root.gui_get_hovered_control())}))
	check("Viewport click chooses actual normal-opening button",actions==["normal"])
	root.push_input(press,true);await process_frame;root.push_input(release,true);await process_frame
	check("rapid repeated Viewport clicks cannot start a second world",actions.size()==1)
	shell.show_menu();shell.chosen.disconnect(shell.chosen.get_connections()[0].callable);shell.chosen.connect(node._shell_action)
	await node._startup_enter({"resume":true})
	check("continue without valid save remains menu or explicit recovery",node.lifecycle_status().state=="menu" or is_instance_valid(node._startup_recovery))
	check("failed continue never silently creates new world",node.runtime==null and not node._world_loading)
	var before:int=Engine.get_process_frames()
	await node._stage_feedback("proof","Actual phase","bounded work pending")
	check("phase feedback advances render eligibility before work",Engine.get_process_frames()>=before+2 and node.lifecycle_status().phase=="proof")
	var old_ui:=Control.new();node.add_child(old_ui);old_ui.queue_free();await process_frame
	shell.show_result({"ok":true,"reason":"world ready receipt"},true)
	check("completion receipt survives disposal of old UI",is_instance_valid(shell) and shell.state=="ready" and shell._notice.visible and not shell._shade.visible)
	shell.show_result({"ok":false,"code":"CAS","reason":"original retained"},true)
	check("failed operation preserves actionable return",shell.state=="error" and shell._buttons.get_child_count()==1)
	node.queue_free();await process_frame
	var closing:=ClosingFixture.new();root.add_child(closing);await process_frame
	closing.runtime=RuntimeStub.new()
	var failures:Array=[];closing.runtime.close_failed.connect(func(result:Dictionary):failures.append(result))
	await closing._close_requested()
	check("save failure never quits and unlocks closing state",not closing._closing and closing.lifecycle_status().state=="close_failed")
	check("close failure emits one preserved receipt with shell handoff",failures.size()==1 and failures[0].get("lifecycle_shell",false))
	check("close failure offers retry and cancel",closing._shell._buttons.get_child_count()==2)
	closing.cancel_close()
	check("cancel exit dismisses shell",not closing.lifecycle_status().modal and not closing._closing)
	closing.runtime=null;closing.queue_free();await process_frame
	# Real Native save coroutine + real Router reason ownership, with explicit
	# IO/runtime stubs so this checks control policy without touching any save.
	var saving:=SavingFixture.new();root.add_child(saving);await process_frame
	var save_runtime:=RuntimeStub.new();saving.runtime=save_runtime
	var input:=Native.Router.new();input._runtime=save_runtime;saving.router=input;saving.add_child(input);input.set_physics_process(false)
	for action:String in Native.Router.DEFAULTS:input._install_action(action,int(Native.Router.DEFAULTS[action]))
	var fake_store:=StoreStub.new();saving.store=fake_store
	var saved:Dictionary=await saving.save_async("policy:running")
	check("save shell pauses capture and restores prior running router state",saved.ok and save_runtime.captured_paused and not save_runtime.paused and not input.is_paused())
	input.set_modal(true)
	saved=await saving.save_async("policy:paused")
	check("successful save preserves an existing modal pause",saved.ok and save_runtime.paused and input.is_paused() and not input.state().pause_reasons.closing)
	input.set_modal(false);fake_store.fail=true
	var rejected:Dictionary=await saving.save_async("policy:failed")
	check("failed manual save keeps shell actionable and world input blocked",not rejected.ok and saving.lifecycle_status().state=="error" and input.is_paused())
	saving._shell_action("dismiss")
	check("failed save return restores usable original running state",not input.is_paused() and not save_runtime.paused and not saving.lifecycle_status().modal)
	saving.runtime=null;saving.queue_free();await process_frame
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"lifecycle15","checks":checks,"failed":failed,"scope":"Native default menu, actual lifecycle controls, honest phase ordering, read failure and safe-exit failure. No GPU or FPS acceptance."},"\t",true,true))
	print(JSON.stringify({"suite":"lifecycle15","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
