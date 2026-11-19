extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Only newly adopted GPU PNG loader and actual native image consumers.
## No repeat of the original325/45 catalogue/input suites or geometry checks.
func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size() < 3: check("sealed save and exact image adoption expectation supplied", false); return finish(1)
	var original := FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary = Store.decode(original)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	check("original save decodes for image consumer review", decoded.get("ok", false))
	if not decoded.get("ok", false): return finish(1)
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	host = TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var before: Dictionary = runtime.capture_checkpoint()
	var adopted: Array = expected.get("entries", [])
	var pending: Array = expected.get("pending", [])
	var definitions := F.build_definitions(runtime.factory_snapshot("player"))
	check("new image map contains only exactly delivered definitions", Pictures.ARCHITECTURE_MODULES.keys().size() == adopted.size() and adopted.all(func(row: Dictionary): return Pictures.ARCHITECTURE_MODULES.has(row.definition_id)))
	check("image additions do not change existing definition choice source", definitions.size() == 40)
	for entry: Dictionary in adopted:
		var id := str(entry.definition_id)
		var definition := F.definition(ui.factory, id)
		var texture := Pictures.module_texture(definition)
		var source := Image.load_from_file(str(entry.image_path))
		check("exact definition geometry resolves delivered256 texture " + id, definition.get("geometry_version") == entry.geometry_version and texture != null and texture.get_size() == Vector2(256, 256))
		if texture != null and source != null:
			check("loader preserves exact source PNG RGBA pixels " + id, texture.get_image().get_format() == Image.FORMAT_RGBA8 and texture.get_image().get_data() == source.get_data())
		var changed := definition.duplicate(true); changed.geometry_version += ".not-delivered"
		check("geometry mismatch fails closed without old-image fallback " + id, Pictures.module_texture(changed) == null)
	for entry: Dictionary in pending:
		var definition := F.definition(ui.factory, str(entry.definition_id))
		check("manual image remains unbound pending complete source " + str(entry.definition_id), not Pictures.ARCHITECTURE_MODULES.has(entry.definition_id) and Pictures.module_texture(definition) == null)
	for entry: Dictionary in expected.get("legacy", []):
		var definition := F.definition(ui.factory, str(entry.definition_id))
		check("original thumbnail identity and cached texture preserved " + str(entry.definition_id), definition.get("geometry_version") == entry.geometry_version and Pictures.module_texture(definition) == Pictures.texture(str(entry.image_path)))
	ui.open_panel("factory_catalog"); await idle(); await idle()
	for viewport: Vector2i in [Vector2i(1280, 800), Vector2i(1000, 700)]:
		root.size = viewport; root.content_scale_size = root.size; ui.set_text_scale(1.0 if viewport.x == 1280 else 1.5); await idle(); await idle()
		for entry: Dictionary in adopted:
			var id := str(entry.definition_id)
			var node := card(id)
			var picture: TextureRect
			if node != null:
				var texture := Pictures.module_texture(F.definition(ui.factory, id))
				for child: Node in node.find_children("*", "TextureRect", true, false):
					if child.texture == texture: picture = child; break
			var frame: Rect2 = ui._dialog.get_global_rect()
			check("actual native card uses exact image and removes pending label " + id + str(viewport), picture != null and not text_in(node).contains("缩图待交付") and picture.custom_minimum_size == Vector2.ONE * roundi(64 * ui.text_scale) and picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
			if picture != null:
				var bounds := picture.get_global_rect()
				check("actual image fits narrow scene-side panel " + id + str(viewport), bounds.position.x >= frame.position.x and bounds.end.x <= frame.end.x and absf(bounds.size.x - bounds.size.y) <= 1.0, str(bounds))
		for entry: Dictionary in pending:
			var node := card(str(entry.definition_id))
			check("pending manual card keeps explicit text " + str(entry.definition_id) + str(viewport), node != null and text_in(node).contains("缩图待交付"))
		var overflow: Array = []
		var hidden_images: Array = []
		for control: Control in ui._body.find_children("*", "Control", true, false):
			if control is Button or control is Label or control is TextureRect:
				# OptionButton owns hidden PopupMenu scroll decorations with their
				# own canvas coordinates. They are not catalogue image content.
				if not control.is_visible_in_tree():
					if control is TextureRect: hidden_images.append({"path":str(control.get_path()),"rect":str(control.get_global_rect()),"visible":false})
					continue
				var rect := control.get_global_rect(); var frame: Rect2 = ui._dialog.get_global_rect()
				if rect.position.x < frame.position.x or rect.end.x > frame.end.x + 1: overflow.append({"type":control.get_class(), "key":control.get_meta("ui_focus_key", ""), "rect":str(rect)})
		trace.append({"stage":"hidden-popup-decorations","viewport":str(viewport),"images":hidden_images})
		check("new images preserve actual text and action width " + str(viewport), overflow.is_empty() and root.get_visible_rect().encloses(ui._dialog.get_global_rect()), overflow)
	# One real handbook view per adopted purpose validates the shared loader
	# consumer without repeating handbook commands/history tests from325.
	var families: Dictionary = {}
	for entry: Dictionary in adopted:
		if families.has(entry.family): continue
		families[entry.family] = true
		ui.close_panels(); ui.open_handbook("module:" + str(entry.definition_id)); await idle(); await idle()
		var texture := Pictures.module_texture(F.definition(ui.factory, str(entry.definition_id)))
		var found := false
		for child: Node in ui._body.find_children("*", "TextureRect", true, false):
			if child.texture == texture: found = true
		check("actual handbook consumes same exact family thumbnail " + str(entry.family), found and ui.handbook.get("selection", {}).get("id") == "module:" + str(entry.definition_id))
	check("image display preserves original world and save bytes", Data.json_equal(before, runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1]) == original)
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func finish(code: int) -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"method":"New GPU thumbnail delta only: original sealed A save through actual Native/Runtime, exact source RGBA loading, real catalogue card/handbook TextureRects at100/150%, explicit pending manual fallback and legacy identity preservation","scope":"Current-source headless native Controls/source PNG fallback; no new PCK/imported texture/physicalOS/Retina/geometry/VA/FPS acceptance"}, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(code)
