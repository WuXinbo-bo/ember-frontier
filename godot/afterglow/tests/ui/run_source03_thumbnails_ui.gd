extends "res://tests/ui/run_factory_build_choices_ui.gd"
## Independent six-image increment. Uses the actual ART manifest/PNGs as the
## external oracle and the original runtime/router/Control consumers.

func images_in(node: Node, texture: Texture2D) -> Array:
	var found: Array = []
	for child: Node in node.get_children():
		if child is TextureRect and child.texture == texture: found.append(child)
		found.append_array(images_in(child, texture))
	return found

func same_pixels(texture: Texture2D, oracle: Image) -> bool:
	if texture == null or oracle == null: return false
	var pixels := texture.get_image()
	if pixels == null or pixels.get_size() != oracle.get_size(): return false
	pixels.convert(Image.FORMAT_RGBA8); oracle.convert(Image.FORMAT_RGBA8)
	return pixels.get_data() == oracle.get_data()

func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size() < 3: check("actual normal save and ART manifest supplied", false); return finish(1)
	var manifest_bytes := FileAccess.get_file_as_string(args[2])
	var manifest: Dictionary = JSON.parse_string(manifest_bytes)
	check("external source03 art manifest contains exactly six items", manifest.get("items", []).size() == 6)
	var original := FileAccess.get_file_as_string(args[1]); var decoded: Dictionary = Store.decode(original)
	check("unchanged real normal-economy save decodes", decoded.get("ok", false))
	if not decoded.get("ok", false): return finish(1)
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	host = TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var camera := Camera3D.new(); host.add_child(camera)
	var pointer := Pointer.new(); host.add_child(pointer)
	pointer.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":null,"terrain":host,"ui":ui})
	var before: Dictionary = runtime.capture_checkpoint()
	var published: Dictionary = runtime.factory_snapshot("player")
	var owner_ids: Array = published.modules.get("build_definition_ids", [])
	check("same owner retains eighteen definitions and ten current choices", F.rows(published,"modules","definitions").size() == 18 and owner_ids.size() == 10)
	var textures: Dictionary = {}
	for item: Dictionary in manifest.get("items", []):
		var id := str(item.object_id); var definition: Dictionary = F.definition(published, id)
		check("runtime definition has exact ART geometry and design " + id, owner_ids.has(id) and definition.get("geometry_version") == item.geometry_version and definition.get("design_id") == item.design_id)
		var source_path: String = str(args[2]).get_base_dir().path_join(str(item.file))
		var bytes := FileAccess.get_file_as_bytes(source_path)
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
		check("external PNG identity is the adopted manifest identity " + id, hash.finish().hex_encode() == str(item.sha256))
		var oracle := Image.load_from_file(source_path)
		var texture: Texture2D = Pictures.module_texture(definition); textures[id] = texture
		check("real loader consumes exact 256 RGBA pixels including alpha " + id, oracle != null and oracle.get_size() == Vector2i(256,256) and same_pixels(texture, oracle))
		check("six new images use source fallback before A import " + id, texture is ImageTexture and not FileAccess.file_exists("res://themes/modules/"+str(item.mapping_stem)+"-front.png.import"))
		var invalid: Dictionary = definition.duplicate(true); invalid.geometry_version = id + ".geometry-v1"
		var previous_rejected: bool = Pictures.module_texture(invalid) == null
		invalid.geometry_version = id + ".geometry-v3"; var future_rejected: bool = Pictures.module_texture(invalid) == null
		invalid.erase("geometry_version")
		check("previous future and missing geometry cannot alias a new image " + id, previous_rejected and future_rejected and Pictures.module_texture(invalid) == null)
	var unknown: Dictionary = F.definition(published, str(manifest.items[0].object_id)).duplicate(true); unknown.id = "r34.module.not-a-real-building"
	check("unknown identity cannot borrow a valid six-image geometry", Pictures.module_texture(unknown) == null)
	for viewport: Vector2i in [Vector2i(1280,800), Vector2i(1000,700)]:
		root.size = viewport; root.content_scale_size = viewport; ui.set_text_scale(1.0 if viewport.x == 1280 else 1.5)
		for item: Dictionary in manifest.items:
			var id := str(item.object_id)
			ui.close_panels(); ui.open_panel("factory_catalog"); await idle(); await idle()
			check("actual catalog retains owner order " + id + str(viewport), preview_ids() == owner_ids)
			var action := keyed("factory:preview:"+id) as Button
			check("exact new catalog action exists " + id + str(viewport), action != null and not action.disabled)
			if action == null: continue
			var card: Node = action.get_parent().get_parent()
			var images: Array = images_in(card, textures[id])
			check("actual card consumes unique correct image and original name " + id + str(viewport), images.size() == 1 and text_in(card).contains(str(item.name)))
			check("actual card preserves useful role text " + id + str(viewport), text_in(card).contains("独立机器加工" if item.generation_role == "machine" else "生活与补给" if item.generation_role == "home" else "存放与转运"))
			if images.size() == 1:
				var image: TextureRect = images[0]; ui._scroll.ensure_control_visible(image); await idle()
				var width := roundi(64 * ui.text_scale)
				check("normal-scale image keeps aspect without per-object magnification " + id + str(viewport), image.custom_minimum_size == Vector2(width,width) and is_equal_approx(image.size.x,width) and image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and image.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and image.mouse_filter == Control.MOUSE_FILTER_IGNORE and root.get_visible_rect().encloses(image.get_global_rect()), str(image.get_global_rect()))
			ui._scroll.ensure_control_visible(action); await idle()
			await click(action.get_global_rect().get_center())
			check("native card pointer selects exact original placement owner " + id + str(viewport), router.state().mode == "module_place" and router.state().module_definition_id == id and Data.json_equal(before,runtime.capture_checkpoint()))
			await key(KEY_ESCAPE)
			check("original cancellation preserves world and materials " + id + str(viewport), router.state().mode != "module_place" and Data.json_equal(before,runtime.capture_checkpoint()))
	ui.close_panels(); ui.open_handbook("module:"+str(manifest.items[0].object_id)); await idle(); await idle()
	check("real handbook uses new exact definition and same image consumer", ui.handbook.get("selection",{}).get("id") == "module:"+str(manifest.items[0].object_id) and not images_in(ui._body,textures[str(manifest.items[0].object_id)]).is_empty())
	check("source bytes and complete authority remain unchanged", FileAccess.get_file_as_string(args[1]) == original and FileAccess.get_file_as_string(args[2]) == manifest_bytes and Data.json_equal(before,runtime.capture_checkpoint()))
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func finish(code: int) -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	if not output.is_empty():
		var file := FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"method":"Six source03 ART PNGs as external pixel+alpha oracle; actual runtime eighteen definitions/current ten; Native mounted UI/router original cancellation consumer with ray/3D refresh disabled; native pointer selection at 100/150 percent; real handbook. No direct action callback or alternate state.","scope":"Current-source headless Control + source ImageTexture support only; no imported/PCK/OS/renderer/Retina/VA/WF/FPS/G5 acceptance"},"\t",true,true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(code)
