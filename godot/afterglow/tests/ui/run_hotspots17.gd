extends "res://tests/ui/run_controls15.gd"
## In-memory per-method instrumentation over the actual native UI script.
## One unchanged real authority; no 3D renderer, no artificial state changes.
var samples:Array=[]
func instrument(source:String)->GDScript:
	var code:String=source
	code=code.replace("\tvar reused:bool=_select_panel_body(route,_panel_signature)","\tvar _phase_start:int=Time.get_ticks_usec()\n\tvar reused:bool=_select_panel_body(route,_panel_signature)")
	code=code.replace("\tif not capture_action.is_empty(): paragraph(\"正在改键：", "\t_ui_phases.append({\"phase\":\"select-and-navigation\",\"us\":Time.get_ticks_usec()-_phase_start})\n\t_phase_start=Time.get_ticks_usec()\n\tif not capture_action.is_empty(): paragraph(\"正在改键：")
	code=code.replace("\tif _body.get_parent()!=_scroll:_scroll.add_child(_body)","\t_ui_phases.append({\"phase\":\"content-off-tree\",\"us\":Time.get_ticks_usec()-_phase_start})\n\t_phase_start=Time.get_ticks_usec()\n\tif _body.get_parent()!=_scroll:_scroll.add_child(_body)\n\t_ui_phases.append({\"phase\":\"attach-native-tree\",\"us\":Time.get_ticks_usec()-_phase_start})")
	var specs:Array=[
		["_profiledrefresh","","","void"], ["_render_target","","","void"],
		["_render_hotbar","","","void"], ["_render_panel","","","void"],
		["_refresh_factory_hud","actor: Dictionary","actor","void"],
		["_hand_hint","hand: Dictionary","hand","String"],
		["_size_dialog","","","void"], ["_wire_choice_popups","","","void"],
		["_visible_panel_signature","","","int"], ["_sync_modal","","","void"],
		["inventory_grid","stock: Dictionary, parent: Node","stock,parent","void"]]
	if source.contains("func _read_page("):specs.append(["_read_page","page:String,subject:String","page,subject","Dictionary"])
	code+="\nvar _ui_costs:Dictionary={}\nvar _ui_phases:Array=[]\n"
	for spec:Array in specs:
		var method:String=spec[0]
		code=code.replace("func "+method+"(","func _original"+method+"(")
		code+="\nfunc "+method+"("+str(spec[1])+")->"+str(spec[3])+":\n\tvar started:int=Time.get_ticks_usec()\n"
		code+=("\t_original"+method+"("+str(spec[2])+")\n") if spec[3]=="void" else ("\tvar result:"+str(spec[3])+"=_original"+method+"("+str(spec[2])+")\n")
		code+="\tif not _ui_costs.has(\""+method+"\"):_ui_costs[\""+method+"\"]=[]\n\t_ui_costs[\""+method+"\"].append(Time.get_ticks_usec()-started)\n"
		if spec[3]!="void":code+="\treturn result\n"
	var script:=GDScript.new();script.source_code=code
	check("actual UI in-memory measurement compiles",script.reload()==OK)
	return script
func stats(values:Array)->Dictionary:
	if values.is_empty():return {"count":0,"total_us":0,"mean_us":0,"max_us":0}
	var total:int=0;var maximum:int=0
	for value:int in values:total+=value;maximum=maxi(maximum,value)
	return {"count":values.size(),"total_us":total,"mean_us":float(total)/values.size(),"max_us":maximum}
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles();var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("actual current opening prepares",prepared.get("ok",false))
	if not prepared.get("ok",false):return finish()
	var made:Dictionary=host._assemble(Opening.prepare_opening(prepared.capture,"normal"))
	check("actual Native owner assembly",made.get("ok",false))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json";host.add_child(router);router.configure(runtime,false,true)
	var source_path:String=args[1] if args.size()>1 else "res://scripts/ui/game_ui.gd"
	var source:String=FileAccess.get_file_as_string(source_path)
	var backup:=FileAccess.open(output+"/measured-game-ui.gd",FileAccess.WRITE);backup.store_string(source);backup.close()
	ui=load("res://scenes/ui/game_ui.tscn").instantiate();ui.set_script(instrument(source));ui.configure(runtime,router);host.add_child(ui);await flush()
	var original:Dictionary=runtime.capture_checkpoint()
	for page:String in ["pause","inventory","factory_catalog","factory_people","factory_alerts"]:
		for repetition:int in 3:
			ui.close_panels();await flush();ui._ui_costs.clear();ui._ui_phases.clear()
			var start:int=Time.get_ticks_usec();ui.open_panel(page);var synchronous:int=Time.get_ticks_usec()-start
			await flush()
			var costs:Dictionary={}
			for key:String in ui._ui_costs:costs[key]=stats(ui._ui_costs[key])
			samples.append({"page":page,"sample":repetition,"sync_us":synchronous,"costs":costs,"phases":ui._ui_phases.duplicate(true),"render_serial":ui._panel_render_serial})
	ui.close_panels();await flush();ui._ui_costs.clear()
	for index:int in 20:ui.refresh()
	var stable:Dictionary={}
	for key:String in ui._ui_costs:stable[key]=stats(ui._ui_costs[key])
	check("all displayed pages preserve exact authority",Data.json_equal(original,runtime.capture_checkpoint()))
	var file:=FileAccess.open(output+"/measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":samples,"stationary_refresh":stable,"scope":"Headless UI source CPU method attribution; includes original Native read APIs. No GPU/FPS/packaged claims. In-memory measurement wrappers preserve original rendering and authority."},"\t",true,true));file.close()
	finish()
