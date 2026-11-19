extends "res://tests/ui/run_service_access_ui.gd"
## Real Runtime notification shapes, native mounted UI refresh counts.
## Replays only display notifications after one lawful move/STEP; not FPS.
const UIScene=preload("res://scenes/ui/game_ui.tscn")
var emitted:Array=[]
var measurement:Dictionary={}

func instrument(source:String)->GDScript:
	var code:String=source.replace("func refresh() -> void:","func _probe_original_refresh() -> void:")
	code+="\nvar _probe_refresh_calls: int = 0\nfunc refresh() -> void:\n\t_probe_refresh_calls += 1\n\t_probe_original_refresh()\n"
	var script:=GDScript.new();script.source_code=code
	var result:Error=script.reload()
	check("counter-only in-memory UI script compiles",result==OK,result)
	return script if result==OK else null

func install(script:GDScript)->void:
	if is_instance_valid(ui):ui.get_parent().free()
	var layer:=CanvasLayer.new();layer.layer=20
	ui=UIScene.instantiate();ui.set_script(script);ui.configure(runtime,router)
	layer.add_child(ui);host.add_child(layer);await flush()

func replay(label:String,clock:Dictionary,movement:Dictionary)->void:
	ui.refresh();await flush();ui._probe_refresh_calls=0
	var started:int=Time.get_ticks_usec()
	for index:int in 60:
		runtime.changed.emit(clock);runtime.changed.emit(movement);await process_frame
	var elapsed:int=Time.get_ticks_usec()-started
	await create_timer(0.14).timeout
	measurement[label]={"frames":60,"notifications":120,"elapsed_usec":elapsed,"refresh_calls":ui._probe_refresh_calls}

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	if args.size()<3:check("normal-save and exact preimage supplied",false);return finish()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var original:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(original)
	check("unchanged normal-economy input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	host=TestClient.new();root.add_child(host)
	if not await mount_capture(decoded.capture):return finish()
	runtime.changed.connect(func(change:Dictionary):emitted.append(change.duplicate(true)))
	runtime.tick(0.1)
	var clock:Dictionary={};var movement:Dictionary={}
	for change:Dictionary in emitted:
		if change.has("clock") and change.has("simulation"):clock=change
	var position:Dictionary=G.location(runtime.actor("player"))
	for direction:Vector2 in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		var destination:Dictionary=position.duplicate(true);destination.x+=direction.x*0.02;destination.z+=direction.y*0.02
		var receipt:Dictionary=runtime.command({"command_id":"ui:notification:move:"+str(direction),"actor_id":"player","kind":"direct_move","target_id":"","destination":destination,"payload":{"movement_dt":0.1,"movement_mode":"walk"}})
		if receipt.get("ok",false):
			var changes:Dictionary=receipt.get("changes",{})
			if not changes.get("events",[]).is_empty():movement=changes
			break
	check("actual Runtime STEP emits clock with current diagnostic projection",not clock.is_empty() and clock.simulation is Dictionary,clock)
	check("actual lawful movement emits empty lifecycle list",not movement.is_empty() and movement.get("actor_transitions") is Array and movement.actor_transitions.is_empty() and movement.events[0].kind=="actor-moved",movement)
	if clock.is_empty() or movement.is_empty():return finish()
	measurement.actual_notifications={"clock":clock.duplicate(true),"movement":movement.duplicate(true)}
	var checkpoint:Dictionary=runtime.capture_checkpoint()
	var current:String=FileAccess.get_file_as_string("res://scripts/ui/game_ui.gd")
	var preimage:String=FileAccess.get_file_as_string(args[2])
	var marker:="func _temporal_change_only("
	var old_begin:int=preimage.find(marker);var old_end:int=preimage.find("\nfunc ",old_begin+marker.length())
	var new_begin:int=current.find(marker);var new_end:int=current.find("\nfunc ",new_begin+marker.length())
	check("exact isolated function preimage located",old_begin>=0 and old_end>old_begin and new_begin>=0 and new_end>new_begin)
	if old_begin<0 or old_end<0:return finish()
	var baseline:String=current.substr(0,new_begin)+preimage.substr(old_begin,old_end-old_begin)+current.substr(new_end)
	var old_script:=instrument(baseline)
	if old_script==null:return finish()
	await install(old_script)
	check("exact preimage reproduces rejection of both real notification shapes",not ui._temporal_change_only(clock) and not ui._temporal_change_only(movement))
	await replay("exact_function_preimage",clock,movement)
	check("preimage confirms frame-frequency refreshes for these real shapes",measurement.exact_function_preimage.refresh_calls>=55,measurement.exact_function_preimage)
	var new_script:=instrument(current)
	if new_script==null:return finish()
	await install(new_script)
	check("actual clock and empty-transition movement now use original pacing",ui._temporal_change_only(clock) and ui._temporal_change_only(movement))
	await replay("current_function",clock,movement)
	var count:int=measurement.current_function.refresh_calls
	check("same notifications respect existing 100ms display budget plus trailing refresh",count<=ceili(float(measurement.current_function.elapsed_usec)/100000.0)+2,measurement.current_function)
	check("same-shape native refresh count falls from the exact preimage",count*3<int(measurement.exact_function_preimage.refresh_calls),measurement)
	var malformed:Dictionary=clock.duplicate(true);malformed.simulation.steps="unvalidated"
	var unknown:Dictionary=clock.duplicate(true);unknown.simulation["inventory_changed"]=true
	var lifecycle:Dictionary=movement.duplicate(true);lifecycle.actor_transitions=[{"actor_id":"player","state":"incapacitated"}]
	var inventory:Dictionary=movement.duplicate(true);inventory.facts=[{"collection":"stocks","id":"pack:player"}]
	var completion:Dictionary=movement.duplicate(true);completion.events=[{"kind":"crafted","actor_id":"player","id":"ui:explicit-completion-dto"}]
	for sample:Dictionary in [{"name":"unknown diagnostics","change":unknown},{"name":"malformed diagnostics","change":malformed},{"name":"nonempty lifecycle","change":lifecycle},{"name":"inventory","change":inventory},{"name":"new action event","change":completion},{"name":"save","change":{"save":true}},{"name":"unknown top field","change":{"future_state":true}},{"name":"router old empty format","change":{}}]:
		ui.refresh();await flush();ui._probe_refresh_calls=0
		# Queue a low-priority update immediately before an urgent one.
		ui._last_refresh_us=Time.get_ticks_usec();runtime.changed.emit(clock);runtime.changed.emit(sample.change);await flush()
		check("urgent notification bypasses timer "+str(sample.name),not ui._temporal_change_only(sample.change) and ui._probe_refresh_calls>=1,ui._probe_refresh_calls)
	var immediate:int=ui._probe_refresh_calls;await create_timer(0.14).timeout
	check("urgent refresh consumes queued temporal update without duplicate",ui._probe_refresh_calls==immediate,{"immediate":immediate,"after":ui._probe_refresh_calls})
	var legacy_clock:Dictionary={"clock":clock.clock,"revision":clock.revision}
	var legacy_move:Dictionary=movement.duplicate(true);legacy_move.erase("actor_transitions")
	check("legacy clock and move formats remain paced",ui._temporal_change_only(legacy_clock) and ui._temporal_change_only(legacy_move))
	check("replay and urgent render DTOs preserve all authority facts and time",Data.json_equal(checkpoint,runtime.capture_checkpoint()))
	check("original save bytes preserved",FileAccess.get_file_as_string(args[1])==original)
	finish()

func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"measurement":measurement,"scope":"Counter-only in-memory scripts on real native Control; exact function preimage comparison; real notification shapes captured after lawful 0.02m move and one STEP. Notifications replayed without further world ticks. Not OS/renderer/PCK/FPS/quiet-window or global performance acceptance."},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
