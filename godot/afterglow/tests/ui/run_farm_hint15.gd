extends "res://tests/ui/run_controls15.gd"
## UI advice against the unmodified real dry growing crop checkpoint.
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var bytes:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(bytes)
	check("original real crop checkpoint decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var plants:Dictionary=decoded.capture.world.extensions.get("r34:ecology",{}).get("plants",{})
	var dry:Array=plants.values().filter(func(row:Dictionary):return row.get("stage")=="growing" and row.get("moisture")==0)
	check("recorded authority really has dry growing crop",not dry.is_empty(),dry)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var made:Dictionary=host._assemble(decoded.capture)
	check("same real saved village assembles",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json";host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router);await flush()
	var checkpoint:Dictionary=runtime.capture_checkpoint()
	ui.open_panel("zone_planning");await flush()
	var farms:Array=ui.zone_planning.zones().filter(func(row:Dictionary):return row.get("kind")=="farm")
	check("public region projection has actual saved farm",not farms.is_empty(),farms)
	if not farms.is_empty():
		ui.zone_planning.choose_zone(ui,str(farms[0].id));ui.refresh();await flush()
		check("actual selected farm explains staged watering without promised countdown",ui.zone_planning.selected().get("kind")=="farm" and text_in(ui._body).contains("生长分阶段耗水，土壤干燥时需再次浇水") and text_in(ui._body).contains("成熟以实际田间状态为准"))
	check("viewing advice preserves crops and all authority",Data.json_equal(checkpoint,runtime.capture_checkpoint()))
	check("original gameplay checkpoint remains byte identical",bytes==FileAccess.get_file_as_string(args[1]))
	finish()
