extends "res://tests/gameplay/factory_long_output_recovery.gd"
## Actual next-tree failure: compare direct budget refusal with real home leg.
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1];source_sha=FileAccess.get_sha256(source_path);probe_mode="route"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path));check("actual next-tree failure decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("actual failed route input mounts without edits",built.get("ok",false) and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world))
	if not built.get("ok",false):return finish()
	live_runtime=built.runtime;sim_origin=live_runtime.clock();initial_total=total_timber(live_runtime);initial_paid=live_runtime.world.extension("r34:production").settlements.size()
	snapshot("actual three carried logs before route")
	check("original player carries three harvested logs at exact tree",live_runtime.actor("player").pack.get("log",0)==3 and live_runtime.actor("player").x>45 and live_runtime.actor("player").z>58)
	var direct:bool=close_enough(live_runtime,MACHINE+":stock:input")
	check("original direct input contact still refuses without teleport",not direct and command_tail[-1].result.get("code")=="UNREACHABLE",command_tail[-1])
	var home:Dictionary=live_runtime.world.extension(Gameplay.KEY).layout.home
	var home_walk:Dictionary=walk(live_runtime,home)
	check("real original home waypoint walk completes with cargo",home_walk.get("ok",false) and live_runtime.actor("player").pack.get("log",0)==3,home_walk)
	if not home_walk.get("ok",false):return finish()
	for spec:Array in [["input",2],["fuel",1]]:
		var target:String=MACHINE+":stock:"+str(spec[0])
		var contact:bool=close_enough(live_runtime,target)
		check("home leg reaches original machine "+str(spec[0]),contact)
		if not contact:return finish()
		var deposit:Dictionary=send(live_runtime,"deposit",target,{"items":{"log":spec[1]}})
		check("original carried logs deposit through onsite command "+str(spec[0]),deposit.get("ok",false),deposit)
		if not deposit.get("ok",false):return finish()
	var config:Dictionary=send(live_runtime,"factory.configure",MACHINE,{"recipe_id":"saw_timber","batches":2})
	check("original paid machine configured normally",config.get("ok",false),config)
	for i:int in 600:
		if int(coverage.new_machine_batches)>=2:break
		step(live_runtime)
	check("next original tree produces two batches through original600 bound",int(coverage.new_machine_batches)==2 and total_timber(live_runtime)==initial_total+8)
	snapshot("real waypoint and production completion")
	var cold:Dictionary=cold_restore(live_runtime,"actual-home-waypoint-production")
	check("actual waypoint production full canonical cold restore",cold.get("ok",false))
	check("waypoint retains original bodies consent and paid materials",invariant_failures.is_empty(),invariant_failures)
	finish()
