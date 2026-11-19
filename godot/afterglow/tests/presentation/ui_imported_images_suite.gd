extends SceneTree
## Imported package resources + real public UI composition, not OS/WF/VA.
## A runs this tests-only entry against the next immutable PCK. No imports,
## fallback injection, take_over_path, source PNG loads or authority commands.
var checks: Array = []
var observed: Array = []
var output := ""
var Images: GDScript
var Identity: GDScript
var Catalog: GDScript
var Profiles: GDScript
var Panels: GDScript
var ObjectPanel: GDScript
var Water: GDScript
var ui: Control
var expected: Dictionary
var finished_sections: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":condition,"detail":detail})
	if not condition: print("FAIL ", label, " ", JSON.stringify(detail))

func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

func image_nodes(node: Node) -> Array:
	var found: Array = []
	if node is TextureRect and node.texture != null: found.append(node)
	for child: Node in node.get_children(): found.append_array(image_nodes(child))
	return found

func body() -> VBoxContainer:
	var value := VBoxContainer.new(); root.add_child(value); return value

func bound(label: String, parent: Node, paths: Array, width: int) -> void:
	var nodes := image_nodes(parent); var actual: Array = []; var options := true
	for node: TextureRect in nodes:
		# Real catalog also contains material-cost icons. Their own separate
		# pipeline is outside this eighteen-picture contract.
		if node.texture.resource_path.begins_with("res://themes/icons/"): continue
		actual.append(node.texture.resource_path)
		options = options and node.texture is CompressedTexture2D and node.custom_minimum_size == Vector2(width,width) and node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and node.expand_mode == TextureRect.EXPAND_IGNORE_SIZE
	actual.sort(); var wanted := paths.duplicate(); wanted.sort()
	check(label, actual == wanted and options, {"actual":actual,"expected":wanted,"texture_options":options})

func inspect_texture(row: Dictionary, texture: Texture2D) -> void:
	var path := str(row.resource_path)
	var width := int(row.get("width",256)); var height := int(row.get("height",256))
	var import_config := ConfigFile.new()
	var metadata_ok := import_config.load(path + ".import") == OK
	var imported := str(import_config.get_value("remap","path","")) if metadata_ok else ""
	var direct: Resource = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	check("imported resource identity " + row.id, texture is CompressedTexture2D and texture.resource_path == path and direct == texture and metadata_ok and imported.begins_with("res://.godot/imported/") and FileAccess.file_exists(imported), {"path":path,"type":texture.get_class() if texture != null else "null","imported":imported})
	if texture == null: return
	var pixels: Image = texture.get_image()
	check("decoded RGBA base image " + row.id, pixels != null and not pixels.is_empty() and pixels.get_width() == width and pixels.get_height() == height)
	if pixels == null or pixels.is_empty(): return
	pixels = pixels.duplicate()
	if pixels.is_compressed():
		var error := pixels.decompress(); check("decode compressed pixels " + row.id, error == OK)
		if error != OK: return
	pixels.clear_mipmaps(); pixels.convert(Image.FORMAT_RGBA8)
	var data := pixels.get_data(); var opaque := PackedByteArray(); var alpha := PackedByteArray()
	for offset: int in range(0,data.size(),4):
		alpha.append(data[offset+3])
		if data[offset+3] == 255: opaque.append_array(data.slice(offset,offset+4))
	var actual := {"path":path,"opaque_count":opaque.size()/4,"opaque_rgba_sha256":sha(opaque),"alpha_sha256":sha(alpha),"image_format":pixels.get_format()}
	check("formal ART opaque pixels and alpha " + row.id, data.size() == width*height*4 and actual.opaque_count == row.opaque_count and actual.opaque_rgba_sha256 == row.opaque_rgba_sha256 and actual.alpha_sha256 == row.alpha_sha256, actual)
	observed.append(actual)

func surface_pixels(texture: Texture2D) -> PackedByteArray:
	# Same base-level RGBA comparison as the original surface42 external oracle.
	# Only the independent expected values are external; runtime pixels are PCK.
	if texture == null: return PackedByteArray()
	var original: Image = texture.get_image()
	if original == null: return PackedByteArray()
	var pixels: Image = original.duplicate()
	if pixels.is_compressed() and pixels.decompress() != OK: return PackedByteArray()
	pixels.clear_mipmaps(); pixels.convert(Image.FORMAT_RGBA8)
	return pixels.get_data()

func inspect_style(label: String, style: StyleBox, row: Dictionary, texture: Texture2D, neutral: bool = true) -> void:
	check("native imported StyleBoxTexture " + label, style is StyleBoxTexture and style.texture == texture and texture is CompressedTexture2D)
	if not style is StyleBoxTexture: return
	var cuts: Array = []; var margins: Array = []
	for side: int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		cuts.append(style.get_texture_margin(side)); margins.append(style.get_content_margin(side))
	check("source pixel slices and content metrics " + label, cuts == row.slices_ltrb and margins == row.content_margins_ltrb, {"slices":cuts,"margins":margins})
	check("stretch center and independent edges " + label, style.draw_center and style.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH and style.axis_stretch_vertical == StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH)
	if neutral: check("neutral base preserves supplied colour " + label, style.modulate_color.is_equal_approx(Color.WHITE), str(style.modulate_color))

func chrome_consumers(rows: Array) -> void:
	var workshop: GDScript = load("res://scripts/ui/ui_theme.gd")
	Images = load("res://scripts/ui/ui_images.gd")
	var by_kind: Dictionary = {}
	for row: Dictionary in rows:
		by_kind[row.id] = row
		var spec: Dictionary = workshop.CHROME.get(row.id,{})
		check("independent current chrome contract " + row.id, spec.get("path") == row.resource_path and spec.get("size") == Vector2i(int(row.width),int(row.height)) and spec.get("slices") == Vector4(row.slices_ltrb[0],row.slices_ltrb[1],row.slices_ltrb[2],row.slices_ltrb[3]))
		var texture: Texture2D = workshop._chrome_texture(str(row.id))
		inspect_texture(row,texture)
		check("real theme reuses original image loader " + row.id, texture != null and Images.texture(str(row.resource_path)) == texture and workshop._chrome_texture(str(row.id)) == texture)
		inspect_style("theme API " + row.id,workshop.chrome(str(row.id),workshop.BASE if row.id == "panel" else workshop.SURFACE),row,texture)
	# The real GameUI creates its shell and Theme without an authority/router.
	# No page workflow, input, save or actual economy route is asserted here.
	var ui_script: GDScript = load("res://scripts/ui/game_ui.gd")
	ui = ui_script.new(); root.add_child(ui)
	for scale_factor: float in [1.0,1.5]:
		ui.set_text_scale(scale_factor)
		var title_plate: Control = ui._title.get_parent().get_parent()
		for pair: Array in [["panel",ui._dialog],["title",title_plate]]:
			var kind: String = pair[0]; var node: Control = pair[1]
			check("actual shell type variation " + kind + str(scale_factor), node.theme_type_variation == ("WorkshopPanel" if kind == "panel" else "WorkshopTitle"))
			inspect_style("real GameUI " + kind + str(scale_factor),node.get_theme_stylebox("panel"),by_kind[kind],workshop._chrome_texture(kind))
	var slot_script: GDScript = load("res://scripts/ui/inventory_slot.gd")
	for scale_factor: float in [1.0,1.5]:
		for selected: bool in [false,true]:
			var slot: Button = slot_script.new()
			slot.slot = {"kind":"hotbar","index":6,"entry":{},"reference":{},"quantity":0,"available":0}
			ui.add_child(slot); slot.present("consumer-only empty slot",selected,scale_factor)
			for state: String in ["normal","hover","pressed"]:
				inspect_style("real InventorySlot " + state + str(scale_factor) + str(selected),slot.get_theme_stylebox(state),by_kind.slot,workshop._chrome_texture("slot"),state == "normal" and not selected)
			check("slot native focus and selection remain separate " + str(scale_factor) + str(selected),slot.focus_mode == Control.FOCUS_ALL and slot.visual_state.selected == selected and slot.get_theme_stylebox("focus") != slot.get_theme_stylebox("normal"))
			slot.free()
	ui.free(); ui = null
	finished_sections.append("chrome")

func soil_consumers(row: Dictionary) -> void:
	var materials_script: GDScript = load("res://scripts/environment/environment_materials.gd")
	var mesher: GDScript = load("res://scripts/terrain/terrain_mesher.gd")
	var live: RefCounted = materials_script.new()
	var manifest: Dictionary = live.manifest()
	var contract: Dictionary = manifest.get("natural_soil_side",{})
	check("natural soil manifest selects exact ART source and metre contract",contract.get("resource") == row.resource_path and contract.get("sha256") == row.source_png_sha256 and contract.get("metres") == row.metres)
	var imported: Texture2D = ResourceLoader.load(str(row.resource_path)) if ResourceLoader.exists(str(row.resource_path)) else null
	inspect_texture(row,imported)
	if imported == null: return
	var direct_pixels: PackedByteArray = surface_pixels(imported)
	var base: StandardMaterial3D = live.material("natural_soil_side")
	var consumer: Texture2D = base.albedo_texture
	check("actual soil consumer preserves imported base pixels",not direct_pixels.is_empty() and surface_pixels(consumer) == direct_pixels and consumer.get_size() == imported.get_size())
	check("soil consumer actual mips and native sampler",consumer != null and consumer.get_image().has_mipmaps() and base.texture_repeat and base.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC and is_equal_approx(base.roughness,0.96))
	check("soil material remains cached without mutating native import",live.material("natural_soil_side") == base and surface_pixels(imported) == direct_pixels)
	observed.append({"kind":"soil-consumer","imported_class":imported.get_class(),"consumer_class":consumer.get_class() if consumer != null else "null","derived_mips":consumer != imported,"base_rgba_sha256":sha(surface_pixels(consumer)),"imported_base_rgba_sha256":sha(direct_pixels)})
	# Reuse the actual terrain mesher's value-only group interface. These are
	# disclosed three-vertex surface fixtures, not generated or player terrain.
	for version: int in [8,9]:
		live.set_world_style("factory-country-1",version)
		var fixtures: Array = [[1,Vector3.RIGHT,"soil_side"],[2,Vector3.RIGHT,"soil_side"],[1,Vector3.DOWN,"soil_side"],[4,Vector3.RIGHT,"soil_side"],[1,Vector3.UP,"grass_top"],[2,Vector3.UP,"soil_side"]]
		var groups: Dictionary = {}
		for index: int in fixtures.size():
			var fixture: Array = fixtures[index]; var n: Vector3 = fixture[1]
			var points := PackedVector3Array([Vector3.ZERO,Vector3.UP,Vector3.FORWARD]) if n == Vector3.RIGHT else PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
			groups[str(index)] = {"material":fixture[0],"texture":fixture[2],"vertices":points,"normals":PackedVector3Array([n,n,n]),"uvs":PackedVector2Array([Vector2.ZERO,Vector2.UP,Vector2.RIGHT]),"indices":PackedInt32Array([0,1,2])}
		var mesh: ArrayMesh = mesher.mesh({"groups":groups,"quads":0},live)
		check("real terrain mesh consumes all six surface fixtures content" + str(version),mesh.get_surface_count() == fixtures.size())
		for index: int in fixtures.size():
			var actual: Material = mesh.surface_get_material(index)
			var fixture: Array = fixtures[index]; var top: bool = fixture[1].y > 0.5
			var selected: bool = not top and fixture[0] in [1,2]
			if selected:
				check("actual natural side including downward consumer " + str(version) + ":" + str(index),actual is StandardMaterial3D and actual.albedo_texture == consumer and surface_pixels(actual.albedo_texture) == direct_pixels and actual.uv1_scale.is_equal_approx(Vector3(0.625,0.625,1)))
			elif not top:
				check("actual road side keeps prior soil texture " + str(version),actual is StandardMaterial3D and actual.albedo_texture == live.material("soil_side").albedo_texture and actual.albedo_texture != consumer)
			else:
				var prior_id: String = "soil_side" if fixture[0] == 2 else "grass_top"
				check("actual top keeps prior ground shader texture " + str(version) + ":" + str(index),actual is ShaderMaterial and actual.get_shader_parameter("ground_texture") == live.material(prior_id).albedo_texture and actual.get_shader_parameter("ground_texture") != consumer)
	# Saved-version selection is checked through the original public API only.
	for generator: String in ["rural-3","factory-country-1"]:
		for version: int in [0,1,7,10]:
			live.set_world_style(generator,version)
			var prior: Material = live.terrain_material("soil_side","side",1)
			check("unadopted/legacy selector retains original " + generator + str(version),prior is StandardMaterial3D and prior.albedo_texture == live.material("soil_side").albedo_texture and prior.albedo_texture != consumer)
	live.set_world_style("factory-country-1",9)
	var legacy: Material = live.terrain_material("soil_side","side")
	check("original two-argument terrain API never opts into new side",legacy is StandardMaterial3D and legacy.albedo_texture == live.material("soil_side").albedo_texture)
	finished_sections.append("soil")

func run_chrome_soil_increment() -> void:
	var chrome_rows: Array = []; var soil_rows: Array = []; var ids: Array = []
	for row: Dictionary in expected.get("images",[]):
		ids.append(row.get("id"))
		if row.get("kind") == "chrome": chrome_rows.append(row)
		elif row.get("kind") == "soil": soil_rows.append(row)
	ids.sort()
	check("independent increment contains exactly three chrome and one soil",ids == ["natural_soil_side","panel","slot","title"] and chrome_rows.size() == 3 and soil_rows.size() == 1)
	if chrome_rows.size() != 3 or soil_rows.size() != 1: finish(); return
	# Require real package imports before any consumer can invoke source fallback.
	var ready := true
	for row: Dictionary in expected.images:
		var path: String = row.resource_path
		var metadata := ConfigFile.new(); var ok: bool = metadata.load(path + ".import") == OK
		var remap: String = str(metadata.get_value("remap","path","")) if ok else ""
		ok = ok and metadata.get_value("remap","importer","") == "texture" and remap.begins_with("res://.godot/imported/") and FileAccess.file_exists(remap) and ResourceLoader.exists(path)
		var native: Resource = ResourceLoader.load(path) if ok else null
		ok = ok and native is CompressedTexture2D and native.resource_path == path
		check("import gate before actual consumers " + row.id,ok,{"path":path,"remap":remap,"type":native.get_class() if native != null else "null"})
		ready = ready and ok
	if not ready: finish(); return
	chrome_consumers(chrome_rows); soil_consumers(soil_rows[0])
	check("all four imported resources and both consumer sections finish",finished_sections == ["chrome","soil"] and observed.filter(func(r: Dictionary): return r.has("path")).size() == 4)
	finish()

func run_quality_six_increment() -> void:
	var rows: Array = expected.get("images",[]); var ids: Array = []
	for row: Dictionary in rows: ids.append(row.get("id"))
	ids.sort()
	check("independent six exact new module IDs",ids == ["r34.module.home_court_v3","r34.module.home_roadside_v3","r34.module.warehouse_court_v3","r34.module.warehouse_long_v3","r34.module.woodshop_long_v3","r34.module.woodshop_yard_v3"])
	if rows.size() != 6: finish(); return
	# Do not let actual UI consumers satisfy this test through source fallback.
	var ready := true
	for row: Dictionary in rows:
		var path: String = row.resource_path
		var metadata := ConfigFile.new(); var ok: bool = metadata.load(path + ".import") == OK
		var remap: String = str(metadata.get_value("remap","path","")) if ok else ""
		ok = ok and metadata.get_value("remap","importer","") == "texture" and remap.begins_with("res://.godot/imported/") and FileAccess.file_exists(remap) and ResourceLoader.exists(path)
		var native: Resource = ResourceLoader.load(path) if ok else null
		ok = ok and native is CompressedTexture2D and native.resource_path == path
		check("six import gate before actual consumers " + row.id,ok,{"path":path,"remap":remap,"type":native.get_class() if native != null else "null"})
		ready = ready and ok
	if not ready: finish(); return
	Images = load("res://scripts/ui/ui_images.gd"); Catalog = load("res://scripts/modules/module_catalog.gd")
	Panels = load("res://scripts/ui/factory_panels.gd"); ObjectPanel = load("res://scripts/ui/factory_object.gd")
	var handbook: GDScript = load("res://scripts/ui/factory_handbook.gd")
	var ui_script: GDScript = load("res://scripts/ui/game_ui.gd"); ui = ui_script.new()
	root.add_child(ui)
	var definitions: Array = []; var paths: Array = []
	for row: Dictionary in rows:
		var definition: Dictionary = Catalog.definition(str(row.id))
		check("six exact catalog identity geometry and design " + row.id,definition.get("id") == row.id and definition.get("geometry_version") == row.geometry_version and definition.get("design_id") == row.design_id and definition.get("quality_parent_definition_id") == row.parent_definition_id)
		definitions.append(definition); paths.append(row.resource_path)
		inspect_texture(row,Images.module_texture(definition))
		for version: Variant in [null,"",str(row.id)+".geometry-v1",str(row.id)+".geometry-v3",str(row.parent_definition_id)+".geometry-v1"]:
			var invalid: Dictionary = definition.duplicate(true); invalid.geometry_version = version
			check("new geometry refuses missing old sibling or future image " + row.id + " " + str(version),Images.module_texture(invalid) == null)
	# Disclosed public-projection fixtures include only these six already-known
	# definitions. No new world/stock, actual build-choice workflow or authority.
	for scale_factor: float in [1.0,1.5]:
		ui.text_scale = scale_factor
		ui.factory = {"available":true,"modules":{"available":true,"definitions":definitions,"build_definition_ids":ids,"instances":[]}}
		var host := body(); Panels.render(ui,host,{"page":"factory_catalog"})
		bound("six real catalog imported images " + str(scale_factor),host,paths,roundi(64*scale_factor)); host.free()
		for row: Dictionary in rows:
			var definition: Dictionary = Catalog.definition(str(row.id))
			var id: String = "six-image-fixture:" + str(row.id)
			ui.factory.modules.instances = [{"id":id,"definition_id":row.id,"name":definition.get("name",row.id),"status":"completed","state_code":"idle","stock_refs":{}}]
			host = body(); Panels.render(ui,host,{"page":"factory"})
			bound("six real facility list " + row.id + str(scale_factor),host,[row.resource_path],roundi(64*scale_factor)); host.free()
			host = body(); ObjectPanel.render(ui,host,id)
			bound("six real object sidebar " + row.id + str(scale_factor),host,[row.resource_path],roundi(80*scale_factor)); host.free()
			var entry: Dictionary = {"id":"module:"+str(row.id),"kind":"module","name":definition.get("name",row.id),"definition":definition}
			check("six handbook consumer shares exact image " + row.id + str(scale_factor),handbook.entry_image(entry) == Images.module_texture(definition))
			host = body(); handbook._detail(ui,host,entry)
			bound("six actual handbook detail " + row.id + str(scale_factor),host,[row.resource_path],roundi(64*scale_factor)); host.free()
	var unknown: Dictionary = {"id":"r34.module.unknown_quality","geometry_version":"r34.module.unknown_quality.geometry-v2"}
	check("unknown new module never borrows six or legacy image",Images.module_texture(unknown) == null)
	finished_sections.append("quality-six")
	check("all six imported images and actual consumer sections finish",observed.size() == 6 and finished_sections == ["quality-six"])
	ui.free(); ui = null; finish()

func render_modules(definitions: Array, images: Array) -> void:
	ui.factory = {"available":true,"modules":{"available":true,"definitions":definitions,"instances":[]}}
	var host := body(); Panels.render(ui,host,{"page":"factory_catalog"})
	bound("real catalog TextureRects bind twelve exact definitions",host,images,64); host.free()
	# Read-only public projection fixture: one disclosed instance per exact
	# catalog definition. No constructed world or player route is claimed.
	for definition: Dictionary in definitions:
		var id := "image-fixture:" + str(definition.id)
		ui.factory.modules.instances = [{"id":id,"definition_id":definition.id,"name":id,"status":"completed","state_code":"idle","stock_refs":{}}]
		host = body(); Panels.render(ui,host,{"page":"factory"})
		var path := "res://themes/modules/" + str(Images.MODULES.get(definition.id,"")) + "-front.png"
		bound("real facility list binding " + definition.id,host,[path],64); host.free()
		host = body(); ObjectPanel.render(ui,host,id)
		bound("real object sidebar binding " + definition.id,host,[path],80); host.free()
	finished_sections.append("modules")

func water_consumers(rows: Array) -> void:
	for row: Dictionary in rows:
		var state := str(row.id).trim_prefix("WT01-")
		var source := {"id":"water-image-fixture","discovered":true,"status":"needs_repair" if state == "unknown" else "ready","remaining":0 if state == "empty" else 48,"reserved":0,"allowed_actions":[]}
		inspect_texture(row,Images.water_texture(source))
		ui.factory = {"water":{"available":true,"sources":[source]}}
		var host := body(); Water.render(ui,host,str(source.id))
		bound("real WT sidebar state " + state,host,[row.resource_path],80); host.free()
		var original := source.duplicate(true)
		source.discovered = false
		check("undiscovered WT has no image " + state,Images.water_texture(source) == null)
		ui.factory.water.sources = [source]; host = body(); Water.render(ui,host,str(source.id))
		bound("undiscovered WT consumer withholds image " + state,host,[],80); host.free()
		source = original; source.reserved = source.remaining + 1
		ui.factory.water.sources = [source]; host = body(); Water.render(ui,host,str(source.id))
		bound("invalid reservation WT consumer withholds image " + state,host,[],80); host.free()
	finished_sections.append("water")

func negatives(definitions: Array) -> void:
	for definition: Dictionary in definitions:
		for version: Variant in [null,"",str(definition.id)+".geometry-v2","r34.module.warehouse.geometry-v1-wrong"]:
			var value := definition.duplicate(true); value.geometry_version = version
			check("reject absent/mismatched/future geometry " + definition.id + " " + str(version),Images.module_texture(value) == null)
	for id: String in ["r34.module.guard_post","r34.module.future","", "warehouse"]:
		check("unknown module has no substitute " + id,Images.module_texture({"id":id,"geometry_version":id+".geometry-v1"}) == null)
	for actor: Dictionary in [{},{"id":"player","name":"r1_resident_commuter"},{"appearance_id":"infected_walker"},{"appearance_id":"future-person"}]:
		check("unknown appearance has no portrait " + JSON.stringify(actor),Identity.portrait(actor) == null)
		var host := body(); Identity.header(ui,host,actor,48); bound("unknown appearance consumer no image",host,[],48); host.free()
	for remaining: Variant in [null,-1,"48",INF,NAN]:
		check("WT invalid balance no image " + str(remaining),Images.water_texture({"discovered":true,"status":"ready","remaining":remaining}) == null)
	for source: Dictionary in [{},{"status":"ready","remaining":48},{"discovered":false,"status":"needs_repair","remaining":48},{"discovered":true,"status":"future","remaining":48}]:
		check("WT unknown or undiscovered no image " + JSON.stringify(source),Images.water_texture(source) == null)
	finished_sections.append("negatives")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1: push_error("requires output directory [expected JSON]"); quit(2); return
	output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	var oracle: String = args[1] if args.size() > 1 else str(get_script().resource_path).get_base_dir().path_join("ui_imported_images_expected.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(oracle))
	check("independent oracle loads",parsed is Dictionary and parsed.get("schema") in ["afterglow-ui-imported-images-expectations-v1","afterglow-imported-chrome-soil-increment-v1","afterglow-imported-quality-six-increment-v1"])
	if not parsed is Dictionary: finish(); return
	expected = parsed
	if expected.get("schema") == "afterglow-imported-chrome-soil-increment-v1": run_chrome_soil_increment(); return
	if expected.get("schema") == "afterglow-imported-quality-six-increment-v1": run_quality_six_increment(); return
	Images = load("res://scripts/ui/ui_images.gd"); Identity = load("res://scripts/ui/ui_identity.gd")
	Catalog = load("res://scripts/modules/module_catalog.gd"); Profiles = load("res://scripts/runtime/actor_profiles.gd")
	Panels = load("res://scripts/ui/factory_panels.gd"); ObjectPanel = load("res://scripts/ui/factory_object.gd"); Water = load("res://scripts/ui/factory_water.gd")
	var ui_script: GDScript = load("res://scripts/ui/game_ui.gd"); ui = ui_script.new()
	# Detached actual GameUI helper instance; not added to tree, configured,
	# ticked or bound to an authority. Public consumers create native controls.
	var definitions: Array = Catalog.definitions(); var ids: Array = []; var paths: Array = []; var water_rows: Array = []; var portraits: Array = []
	for row: Dictionary in expected.get("images",[]):
		if row.kind == "module": ids.append(row.id); paths.append(row.resource_path)
		elif row.kind == "water": water_rows.append(row)
		else: portraits.append(row)
	var catalog_ids: Array = definitions.map(func(d: Dictionary): return d.id); catalog_ids.sort(); ids.sort()
	var mapped: Array = Images.MODULES.keys(); mapped.sort()
	check("twelve exact formal IDs equal public MODULES and actual catalog",ids.size() == 12 and ids == mapped and ids == catalog_ids,{"expected":ids,"MODULES":mapped,"catalog":catalog_ids})
	check("independent oracle exactly eighteen resources",expected.get("images",[]).size() == 18 and portraits.size() == 3 and water_rows.size() == 3)
	for row: Dictionary in expected.get("images",[]):
		if row.kind == "module":
			var definition: Dictionary = Catalog.definition(str(row.id))
			check("formal geometry version " + row.id,definition.get("geometry_version") == row.geometry_version)
			inspect_texture(row,Images.module_texture(definition))
	var portrait_ids: Array = Identity.PORTRAITS.keys(); portrait_ids.sort(); var wanted: Array = []
	for row: Dictionary in portraits:
		wanted.append(row.id)
		check("actual permanent actor appearance " + row.actor_id,Profiles.for_new_actor(str(row.actor_id)) == row.id and Identity.PORTRAITS.get(row.id) == row.resource_path)
		var actor := {"id":row.actor_id,"appearance_id":Profiles.for_new_actor(str(row.actor_id)),"name":row.actor_id}
		inspect_texture(row,Identity.portrait(actor))
		var host := body(); Identity.header(ui,host,actor,48); bound("actual permanent portrait header " + row.actor_id,host,[row.resource_path],48); host.free()
	wanted.sort(); check("public portraits contain exactly three permanent appearances",wanted == portrait_ids)
	render_modules(definitions,paths); water_consumers(water_rows); negatives(definitions)
	check("all native consumer sections finish and all eighteen decoded",finished_sections == ["modules","water","negatives"] and observed.size() == 18,{"sections":finished_sections,"observed":observed.size()})
	ui.free(); finish()

func finish() -> void:
	var failures := checks.filter(func(value: Dictionary): return not value.ok)
	var result := {"schema":"afterglow-ui-imported-images-result-v1","oracle_schema":expected.get("schema","invalid"),"ok":failures.is_empty(),"checks":checks,"observed_images":observed,"scope":"immutable PCK imported images + actual native consumer bindings with disclosed UI/mesh fixtures; no renderer, player route, OS, WF or VA qualification"}
	var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result,"\t")+"\n"); file.close()
	print("UI_IMPORTED_IMAGES ",JSON.stringify({"checks":checks.size(),"failed":failures.size(),"observed":observed.size()}))
	quit(0 if failures.is_empty() else 1)
