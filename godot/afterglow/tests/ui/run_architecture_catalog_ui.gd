extends "res://tests/ui/run_os_feedback_ui.gd"
## Real Native/Runtime menu projection, GUI filtering and original placement.
## The explicit expected input distinguishes partial owner delivery from all 30.
const Catalog = preload("res://scripts/ui/factory_catalog.gd")
const Pictures = preload("res://scripts/ui/ui_images.gd")
class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass

func preview_ids() -> Array:
	var result: Array = []
	for node: Node in ui._body.find_children("*", "Button", true, false):
		var id := str(node.get_meta("ui_focus_key", ""))
		if id.begins_with("factory:preview:"): result.append(id.trim_prefix("factory:preview:"))
	return result

func card(id: String) -> Control:
	for node: Node in ui._body.find_children("*", "VBoxContainer", true, false):
		if node.get_meta("ui_catalog_definition", "") == id: return node
	return null

func choose(key_: String, value: String) -> bool:
	var control := keyed(key_) as OptionButton
	if control == null: return false
	var index := -1
	for i: int in control.item_count:
		if control.get_item_metadata(i) == value: index = i
	if index < 0: return false
	ui._scroll.ensure_control_visible(control); await idle()
	await click(control.get_global_rect().get_center())
	await key(KEY_HOME)
	# PopupMenu's Home clears the current hover focus in this headless native
	# path; the first Down focuses item 0, rather than moving from item 0.
	for i: int in index + 1: await key(KEY_DOWN)
	await key(KEY_ENTER); await idle()
	control = keyed(key_) as OptionButton
	trace.append({"stage":"native-dropdown","key":key_,"requested":value,"index":index,"selected":control.get_selected_metadata() if control != null else null,"view":ui.factory_view.duplicate(true)})
	return control != null and control.get_selected_metadata() == value

func activate(key_: String) -> bool:
	var action := keyed(key_) as Button
	if action == null or action.disabled: return false
	ui._scroll.ensure_control_visible(action); await idle()
	if not root.get_visible_rect().encloses(action.get_global_rect()): return false
	await click(action.get_global_rect().get_center()); await idle()
	return true

func type_search(value: String) -> bool:
	var entry := keyed("factory:search:catalog_search") as LineEdit
	if entry == null: return false
	ui._scroll.ensure_control_visible(entry); await idle()
	await click(entry.get_global_rect().get_center())
	for offset: int in value.length():
		var character := value.substr(offset, 1)
		var event := InputEventKey.new(); event.unicode = character.unicode_at(0); event.pressed = true
		root.push_input(event, true); await idle()
		event = InputEventKey.new(); event.unicode = character.unicode_at(0); event.pressed = false
		root.push_input(event, true)
	entry = keyed("factory:search:catalog_search") as LineEdit
	return entry != null and entry.text == value and root.gui_get_focus_owner() == entry

func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size() < 3: check("exact unchanged save and delivery expectation supplied", false); return finish(1)
	var original := FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary = Store.decode(original)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	check("original sealed capture decodes without replacement supplies", decoded.get("ok", false))
	if not decoded.get("ok", false): return finish(1)
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	host = TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var camera := Camera3D.new(); host.add_child(camera)
	var pointer := Pointer.new(); host.add_child(pointer)
	pointer.configure({"runtime":runtime, "world":world, "router":router, "camera":camera, "buildings":null, "terrain":host, "ui":ui})
	var before: Dictionary = runtime.capture_checkpoint()
	var published: Dictionary = runtime.factory_snapshot("player")
	var choices := F.build_definitions(published)
	var owner_ids: Array = published.modules.get("build_definition_ids", [])
	var delivered := choices.filter(func(row: Dictionary): return Catalog.architecture(row).get("set") == Catalog.SET)
	var delivered_ids: Array = delivered.map(func(row: Dictionary): return row.id)
	var sorted_actual := delivered_ids.duplicate(); sorted_actual.sort()
	var sorted_expected: Array = expected.get("delivered_ids", []).duplicate(); sorted_expected.sort()
	check("actual architecture delivery exactly matches labelled expectation", sorted_actual == sorted_expected, {"actual":delivered_ids,"expectation":expected})
	check("UI preserves every owner choice and its order without a numerical cap", choices.map(func(row: Dictionary): return row.id) == owner_ids and owner_ids.size() == expected.get("total_choices"), owner_ids)
	ui.open_panel("factory_catalog"); await idle(); await idle()
	check("mounted native catalogue contains all current choices exactly once", preview_ids() == owner_ids, preview_ids())
	for definition: Dictionary in delivered:
		var id := str(definition.id)
		var node := card(id)
		var shown := text_in(node) if node != null else ""
		var metadata: Dictionary = definition.architecture
		check("accurate identity geometry variant footprint and real cost " + id, node != null and node.get_meta("ui_catalog_geometry") == definition.geometry_version and shown.contains(str(metadata.variant_label)) and shown.contains(Catalog.footprint_text(definition)) and shown.contains("建设"), shown)
		if metadata.family == "home":
			check("design capacity is not presented as occupancy " + id, shown.contains(Catalog.capacity_text(definition)) and shown.contains("不代表实际入住或床位") and not shown.contains("已住"), shown)
		else:
			check("non-residential building never receives a housing count " + id, not shown.contains("设计容量") and not shown.contains("入住"), shown)
		check("actual owner structural difference and no invented upgrade " + id, shown.contains(str(metadata.description)) and not shown.contains("升级此建筑"), shown)
		check("new shape has a truthful missing-image state " + id, Pictures.module_texture(definition) == null and shown.contains("缩图待交付"))
		var changed: Dictionary = definition.duplicate(true); changed.geometry_version += ".not-delivered"
		check("changed geometry cannot borrow an old thumbnail " + id, Pictures.module_texture(changed) == null)
	# Exercise real native dropdown input, rather than emitting item_selected.
	check("native family selector chooses residential purpose", await choose("factory:catalog:family", "home"))
	check("residential filter includes the real nine designs only", preview_ids() == delivered.filter(func(row: Dictionary): return row.architecture.family == "home").map(func(row: Dictionary): return row.id), preview_ids())
	check("native tier selector chooses small homes", await choose("factory:catalog:tier", "small"))
	check("small home view contains the actual three variants", preview_ids() == delivered.filter(func(row: Dictionary): return row.architecture.family == "home" and row.architecture.tier == "small").map(func(row: Dictionary): return row.id) and preview_ids().size() == 3, preview_ids())
	for family_: String in ["sawmill", "warehouse", "canteen", "artisan", "water", "repair", "guard"]:
		if not delivered.any(func(row: Dictionary): return row.architecture.family == family_): continue
		check("native purpose change resets incompatible housing tier " + family_, await choose("factory:catalog:family", family_) and ui.factory_view.get("catalog_tier") == "all")
		check("all real tiers remain available " + family_, preview_ids() == delivered.filter(func(row: Dictionary): return row.architecture.family == family_).map(func(row: Dictionary): return row.id) and preview_ids().size() == 3, preview_ids())
		check("native high tier filters exact definition " + family_, await choose("factory:catalog:tier", "high") and preview_ids() == delivered.filter(func(row: Dictionary): return row.architecture.family == family_ and row.architecture.tier == "high").map(func(row: Dictionary): return row.id))
	check("native family selector restores all and clears old tier", await choose("factory:catalog:family", "all") and ui.factory_view.get("catalog_tier") == "all")
	var current_id: String = str(delivered[0].id)
	check("native favourite button is reachable", await activate("factory:favorite:" + current_id))
	ui.factory_favorites["r34.module.home_service"] = true # historical preference probe only
	check("native scope selects favourites", await activate("factory:category:favorites"))
	check("favourites retain old preference without promoting its non-current definition", preview_ids() == [current_id] and ui.factory_favorites.has("r34.module.home_service"), preview_ids())
	check("native scope restores current choices", await activate("factory:category:all") and preview_ids() == owner_ids)
	var query: String = str(delivered[0].architecture.variant_label)
	check("native text typing survives each refresh and retains search focus", await type_search(query) and preview_ids().has(current_id), {"view":ui.factory_view.duplicate(true),"choices":preview_ids()})
	check("native catalogue shortcut opens exact new definition", await activate("factory:handbook:link:catalog:" + current_id) and ui.handbook.get("selection", {}).get("id") == "module:" + current_id)
	await key(KEY_ESCAPE)
	check("handbook Esc returns to the same filtered catalogue", not ui.pages.is_empty() and ui.pages.back().page == "factory_catalog" and ui.factory_view.get("catalog_search") == query and preview_ids().has(current_id))
	# Exact owner ID text search, labelled as UI preference setup. The actual
	# placement and cancellation below still use Viewport GUI/key input.
	for definition: Dictionary in delivered:
		var id := str(definition.id)
		ui.factory_view.catalog_search = id; ui.refresh(); await idle()
		check("stable ID search isolates actual owner definition " + id, preview_ids() == [id], preview_ids())
		check("native placement button reaches the original router " + id, await activate("factory:preview:" + id) and router.state().mode == "module_place" and router.state().module_definition_id == id, router.state())
		check("selection does not spend materials or create geometry " + id, Data.json_equal(before, runtime.capture_checkpoint()))
		await key(KEY_ESCAPE)
		check("original A cancellation keeps world and goods " + id, router.state().mode != "module_place" and Data.json_equal(before, runtime.capture_checkpoint()))
	ui.factory_view.catalog_search = ""; ui.refresh(); await idle()
	var old_instance: Dictionary = {}
	for instance: Dictionary in F.rows(published, "modules", "instances"):
		if not delivered_ids.has(str(instance.get("definition_id", ""))): old_instance = instance; break
	check("untouched old save retains a real historical facility", not old_instance.is_empty())
	if not old_instance.is_empty():
		ui.close_panels(); ui.open_panel("factory_module", str(old_instance.id)); await idle()
		check("old facility remains readable through full owner definitions", not F.definition(ui.factory, str(old_instance.definition_id)).is_empty() and not F.instance(ui.factory, str(old_instance.id)).is_empty())
		ui.open_handbook("module:" + str(old_instance.definition_id)); await idle()
		check("old definition handbook is retained independently of current choices", ui.handbook.get("selection", {}).get("id") == "module:" + str(old_instance.definition_id))
	if not ui.pages.is_empty(): ui.close_panels()
	ui.open_panel("factory_catalog"); await idle()
	check("native movable scope remains reachable", await activate("factory:category:movable"))
	check("existing movable cabinet is separate from architecture tiers", preview_ids().is_empty() and keyed("factory:movable:place:cabinet") != null)
	await activate("factory:category:all")
	ui.factory_view.catalog_family = "not-current"; ui.factory_view.catalog_tier = "not-current"; ui.refresh(); await idle()
	check("stale filter is explicit and cannot become a build choice", preview_ids().is_empty() and text_in(ui._body).contains("没有匹配项"))
	check("native selector recovers stale preferences", await choose("factory:catalog:family", "all") and preview_ids() == owner_ids)
	for viewport: Vector2i in [Vector2i(1280, 800), Vector2i(1000, 700)]:
		root.size = viewport; root.content_scale_size = viewport; ui.set_text_scale(1.0 if viewport.x == 1280 else 1.5); await idle(); await idle()
		ui._scroll.scroll_vertical = 0; await idle()
		check("catalogue preserves scene and viewport at " + str(viewport), root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._dialog.size.x <= viewport.x * 0.45 and preview_ids() == owner_ids, str(ui._dialog.get_global_rect()))
		check("native filters remain within narrow panel at " + str(viewport), keyed("factory:catalog:family") != null and ui._dialog.get_global_rect().encloses(keyed("factory:catalog:family").get_global_rect()) and ui._dialog.get_global_rect().encloses(keyed("factory:catalog:tier").get_global_rect()))
		var overflow: Array = []
		for control: Control in ui._body.find_children("*", "Control", true, false):
			if control is Button or control is Label or control is OptionButton:
				var rect := control.get_global_rect()
				if rect.position.x < ui._dialog.position.x or rect.end.x > ui._dialog.position.x + ui._dialog.size.x + 1: overflow.append({"key":control.get_meta("ui_focus_key", ""),"rect":str(rect)})
		check("card titles costs and actions do not spill into scene at " + str(viewport), overflow.is_empty(), overflow)
	# Explicit detached malformed description probes; never replace runtime DTOs.
	var malformed: Dictionary = delivered[0].duplicate(true); malformed.architecture.design_capacity = 2.5
	check("fractional housing count is not invented", Catalog.capacity_text(malformed) == "设计容量未提供")
	malformed.architecture.tier = "high"
	check("home cannot acquire industrial tier through malformed metadata", Catalog.tier(malformed).is_empty())
	malformed.architecture = null
	check("missing architecture never infers capacity from ID", Catalog.capacity_text(malformed).is_empty() and Catalog.family(malformed) == "legacy")
	check("all catalogue inputs preserve original capture and exact save bytes", Data.json_equal(before, runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1]) == original)
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func finish(code: int) -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"method":"Unchanged sealed save through actual Native/Runtime/UI; original router and A cancel consumer; native Viewport dropdown, pointer and Esc events; exact declared delivery expectation; explicit malformed DTO probes labelled separately","scope":"Current-source headless Control support only; no new building rendering/paid construction/lifecycle/PCK/physical OS/Retina/VA/FPS qualification"}, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(code)
