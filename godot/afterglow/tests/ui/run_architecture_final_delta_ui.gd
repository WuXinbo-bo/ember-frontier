extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Only final30's new manual9 and changed guard image; no repeat of21/325/45.
func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size()<3: check("exact capture and final image manifest supplied",false); return finish(1)
	var original := FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary = Store.decode(original)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	check("original sealed capture decodes",decoded.get("ok",false))
	if not decoded.get("ok",false): return finish(1)
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	host=TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var before: Dictionary = runtime.capture_checkpoint()
	var entries: Array = expected.entries
	check("final30 exact map contains every delivered ID once",entries.size()==30 and Pictures.ARCHITECTURE_MODULES.size()==30 and entries.all(func(row:Dictionary):return Pictures.ARCHITECTURE_MODULES.has(row.definition_id)))
	var delta: Array = entries.filter(func(row:Dictionary):return str(Pictures.ARCHITECTURE_MODULES[row.definition_id].path).contains("architecture-final-v1/"))
	check("only manual9 and changed guard have new targets",delta.size()==10 and delta.filter(func(row:Dictionary):return str(row.definition_id).contains("guard_")).map(func(row:Dictionary):return row.definition_id)==["r34.module.guard_low_v1"])
	for entry: Dictionary in delta:
		var definition := F.definition(ui.factory,str(entry.definition_id))
		var picture := Pictures.module_texture(definition)
		var original_pixels := Image.load_from_file(str(entry.image_path))
		check("new exact256 RGBA texture "+str(entry.definition_id),picture!=null and picture.get_size()==Vector2(256,256) and picture.get_image().get_data()==original_pixels.get_data())
		var wrong := definition.duplicate(true); wrong.geometry_version+=".not-delivered"
		check("geometry mismatch refuses new complete image "+str(entry.definition_id),Pictures.module_texture(wrong)==null)
	ui.open_panel("factory_catalog"); await idle(); await idle()
	for viewport: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport; root.content_scale_size=viewport; ui.set_text_scale(1.0 if viewport.x==1280 else 1.5); await idle(); await idle()
		for entry: Dictionary in delta:
			var node := card(str(entry.definition_id)); var found := false
			if node!=null:
				for texture: TextureRect in node.find_children("*","TextureRect",true,false):
					if texture.texture==Pictures.module_texture(F.definition(ui.factory,str(entry.definition_id))):
						found=texture.custom_minimum_size==Vector2.ONE*roundi(64*ui.text_scale) and texture.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			check("actual catalogue complete image at scale "+str(entry.definition_id)+str(viewport),found and not text_in(node).contains("缩图待交付"))
		check("updated catalogue stays within scene-side allocation "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._dialog.size.x<=viewport.x*.45)
	for family: String in ["sawmill","artisan","repair"]:
		var entry: Dictionary = delta.filter(func(row:Dictionary):return row.family==family)[0]
		ui.close_panels(); ui.open_handbook("module:"+str(entry.definition_id)); await idle(); await idle()
		var texture := Pictures.module_texture(F.definition(ui.factory,str(entry.definition_id)))
		check("actual handbook uses complete workbench-family image "+family,ui._body.find_children("*","TextureRect",true,false).any(func(node):return node.texture==texture))
	check("image delta preserves exact authority and original file",Data.json_equal(before,runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
