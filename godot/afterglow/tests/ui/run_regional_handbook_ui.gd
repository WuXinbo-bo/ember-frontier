extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Public A handbook DTO/card consumer. No copied ecology rules or settlement.

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("actual new12 original input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var before:=runtime.capture_checkpoint()
	for id:String in ["source:planning","source:crop:potato","source:crop:bean","source:crop:rice","source:tree:broadleaf","source:tree:conifer","source:raw_water"]:
		ui.open_handbook(id);await idle();await idle()
		var selection:Dictionary=ui.handbook.get("selection",{});var rule:Dictionary=selection.get("definition",{})
		check("exact public regional source card renders "+id,selection.get("id")==id and text_in(ui._body).contains(str(selection.get("name"))))
		if rule.get("crop_rules") is Dictionary:
			check("source crop specifications consume published numeric rule "+id,text_in(ui._body).contains(P.number(rule.crop_rules.seconds)) and text_in(ui._body).contains("每阶段需要的土壤水分") and text_in(ui._body).contains("规则规格，非现有库存"))
		if rule.get("tree_rules") is Dictionary:
			check("source tree stages consume published numeric rule "+id,text_in(ui._body).contains(P.number(rule.tree_rules.young_seconds)) and text_in(ui._body).contains(P.number(rule.tree_rules.mature_seconds)))
		check("source card contains no obsolete unimplemented claim "+id,not text_in(ui._body).contains("未接栽植") and not text_in(ui._body).contains("未接再生"))
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);ui.open_handbook("source:crop:rice");await idle();await idle()
		check("regional handbook fits native viewport "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1)
	await key(KEY_W);await key(KEY_E)
	check("regional source reading consumes modal movement and interaction",Data.json_equal(before,runtime.capture_checkpoint()))
	check("input file remains exact",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
