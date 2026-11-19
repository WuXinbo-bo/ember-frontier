extends "res://tests/ui/run_service_access_ui.gd"
## Real authority, counted public facade, native Controls. No renderer or app.
const Book = preload("res://scripts/ui/factory_handbook.gd")
const Prefs = preload("res://scripts/runtime/factory_display.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
class CountedAuthority extends RefCounted:
	signal changed(value: Dictionary)
	var source: RefCounted
	var queries := 0
	var reject_preference := false
	var malformed := false
	func _init(value: RefCounted) -> void:
		source = value
	func snapshot() -> Dictionary: return source.snapshot()
	func factory_snapshot(actor_id: String = "player") -> Dictionary: return source.factory_snapshot(actor_id)
	func handbook_snapshot(actor_id: String = "player", entry_id: String = "") -> Dictionary:
		queries += 1
		return {"schema":"wrong", "available":true} if malformed else source.handbook_snapshot(actor_id, entry_id)
	func availability(request: Dictionary) -> Dictionary: return source.availability(request)
	func command(request: Dictionary) -> Dictionary:
		if reject_preference and str(request.get("kind", "")).begins_with("handbook."): return {"ok":false,"code":"STALE_INPUT","reason":"测试注入：偏好提交被拒绝"}
		return source.command(request)
	func is_paused() -> bool: return source.is_paused()
var authority: CountedAuthority
var saved_capture: Dictionary
var drive_texture: Texture2D

func opaque_digest(image: Image) -> String:
	# Lossless import may fix transparent edge RGB. Opaque source pixels remain
	# exact; the immutable source ZIP separately preserves the original PNG SHA.
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	var opaque := PackedByteArray()
	for offset in range(0, bytes.size(), 4):
		if bytes[offset + 3] == 255: opaque.append_array(bytes.slice(offset, offset + 4))
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(opaque)
	return context.finish().hex_encode()

func visible_rejection(text: String) -> bool:
	# Modal notices are a persistent sibling above the scroll body, not content
	# inside it. Require actual visible native text inside the dialog bounds.
	for label: Node in ui._dialog.find_children("*", "Label", true, false):
		if label.text.contains(text) and label.is_visible_in_tree():
			var bounds: Rect2 = label.get_global_rect()
			if bounds.has_area() and ui._dialog.get_global_rect().encloses(bounds): return true
	return false

func press(key: String) -> bool:
	var control := keyed(key)
	check("button available " + key, control is Button and not control.disabled)
	if not control is Button or control.disabled: return false
	control.pressed.emit(); await flush(); return true

func run() -> void:
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	# Source runs use an explicitly disclosed native Image fixture. Exported
	# runs must use the real imported texture, never replace the resource cache.
	var icon_path := "res://themes/icons/salvaged_drive_unit.png"
	var icon_image: Image
	var raw_source := FileAccess.file_exists(icon_path)
	if raw_source:
		icon_image = Image.new()
		if icon_image.load_png_from_buffer(FileAccess.get_file_as_bytes(icon_path)) != OK: icon_image = null
		if icon_image != null:
			drive_texture = ImageTexture.create_from_image(icon_image); drive_texture.take_over_path(icon_path)
	elif ResourceLoader.exists(icon_path):
		drive_texture = load(icon_path) as Texture2D
		if drive_texture != null: icon_image = drive_texture.get_image()
	check("exact drive source PNG or imported texture decodes with original opaque pixels", icon_image != null and icon_image.get_size() == Vector2i(128,128) and opaque_digest(icon_image) == "5c94537c74a9881e09ab46a9c46c68d3f607a6e6b91893fb68b4543001aecf81" and (not raw_source or FileAccess.get_sha256(icon_path) == "14e39bf7d387bec9d326397171e5d2ae87c79e49c4c2ee4a95d754f8619cc78d"), {"raw_source_fixture":raw_source,"real_imported_resource":not raw_source,"path":icon_path})
	var icon_entry := {"reference":{"kind":"item","item_id":"r34:salvaged_drive_unit"}}
	check("exact drive item maps independently from scrap", Icons.descriptor(icon_entry).path == icon_path and Icons.texture(icon_entry) == drive_texture and Icons.descriptor({"reference":{"kind":"item","item_id":"scrap"}}).path != icon_path)
	root.size = Vector2i(1280, 800)
	var profiles: Dictionary = Assembly.generation_profiles()
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713, profiles.profiles)) if profiles.get("ok", false) else profiles
	check("normal generation prepares without grants", prepared.get("ok", false), prepared.get("reason"))
	if not prepared.get("ok", false): return finish()
	host = TestClient.new(); root.add_child(host)
	var made: Dictionary = host._assemble(prepared.capture)
	check("actual native assembly has handbook API", made.get("ok", false) and made.runtime.has_method("handbook_snapshot"))
	if not made.get("ok", false) or not made.runtime.has_method("handbook_snapshot"): return finish()
	runtime = made.runtime; router = TestRouter.new(); host.add_child(router); router.configure(runtime)
	authority = CountedAuthority.new(runtime); ui = Mount.mount(host, authority, router); await flush()
	check("HUD mount never queries handbook", authority.queries == 0)
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_handbook(); await flush()
	check("handbook opens through actual public snapshot exactly once", authority.queries == 1 and ui.handbook.get("available", false))
	check("read-only open preserves complete authority checkpoint", Data.json_equal(before, runtime.capture_checkpoint()))
	for viewport in [Vector2i(1000,700),Vector2i(1280,800)]:
		# canvas_items has a 1280x800 logical viewport even when the OS window
		# shrinks. Exercise a smaller logical canvas explicitly in headless.
		root.size = viewport; root.content_scale_size = viewport; await flush()
		ui.set_text_scale(1.5 if viewport.x == 1000 else 1.0); await flush()
		check("handbook native dialog stays inside desktop window " + str(viewport), ui._dialog.position.x >= 0 and ui._dialog.position.y >= 0 and ui._dialog.position.x + ui._dialog.size.x <= viewport.x and ui._dialog.position.y + ui._dialog.size.y <= viewport.y, {"viewport":ui.get_viewport_rect().size,"ui":ui.size,"dialog":ui._dialog.get_rect(),"minimum":ui._dialog.get_combined_minimum_size()})

	var section_ids: Array = ui.handbook.sections.map(func(row: Dictionary): return row.id)
	check("all six authoritative navigation entries mounted", section_ids == ["sources","materials","tools","modules","processes","knowledge"] and section_ids.all(func(id): return keyed("factory:book:" + id) != null), section_ids)
	check("all seven authoritative categories are present", ui.handbook.categories.size() == 7 and (keyed("factory:book:category") as OptionButton).item_count == 8)
	var process_entries: Array = ui.handbook.entries.filter(func(row: Dictionary): return row.get("source_id") == "saw_timber" and row.kind == "process")
	check("manual and machine saw entries retain distinct stable IDs and original action", process_entries.size() == 2 and process_entries.any(func(row: Dictionary): return row.id == "process:manual:saw_timber") and process_entries.any(func(row: Dictionary): return row.id == "process:machine:saw_timber"))
	check("factory general snapshot does not contain handbook table", not runtime.factory_snapshot().has("handbook") and not runtime.snapshot().has("handbook"))
	ui.open_handbook("item:r34:salvaged_drive_unit"); await flush()
	check("drive handbook detail mounts exact source-image fixture", ui._body.find_children("*","TextureRect",true,false).any(func(node): return node.texture == drive_texture))
	ui.open_handbook("tool:salvaged_axe"); await flush()
	check("real axe detail shows use specifications without irrelevant craft verdict", ui.handbook.selection.id == "tool:salvaged_axe" and text_in(ui._body).contains("采伐") and text_in(ui._body).contains("现有工具") and not text_in(ui._body).contains("当前可做") and not text_in(ui._body).contains("尚未证明"))
	check("handbook native actions use content width rather than equal full strips", ui._body.find_children("*","Button",true,false).all(func(node:Button): return node.size_flags_horizontal == Control.SIZE_SHRINK_BEGIN and node.size.x < 500 * ui.text_scale))
	check("tool sources and uses still navigate by exact public IDs", not ui.handbook.selection.sources.is_empty() and (ui.handbook.selection.sources+ui.handbook.selection.uses).all(func(row:Dictionary):return keyed("factory:handbook:link:relation:"+str(row.id))!=null))
	ui.open_handbook(); await flush()
	var calls := authority.queries
	var serial: int = ui._panel_render_serial
	for i in 4: ui.refresh(); await flush()
	check("ordinary refresh neither re-queries nor rebuilds handbook table", authority.queries == calls and ui._panel_render_serial == serial)
	var search := keyed("factory:search:handbook_search") as LineEdit
	search.grab_focus(); search.text = "木"; search.caret_column = 1; search.text_changed.emit(search.text); await flush()
	var focused: Control = root.gui_get_focus_owner()
	check("search uses cached DTO and preserves keyboard focus and caret", authority.queries == calls and focused is LineEdit and focused.get_meta("ui_focus_key", "") == "factory:search:handbook_search" and focused.caret_column == 1)
	check("search results match actual names descriptions or stable IDs", Book.filtered(ui).all(func(row: Dictionary): return (str(row.name) + str(row.description) + str(row.id)).contains("木")))
	search = keyed("factory:search:handbook_search"); search.text = ""; search.text_changed.emit(""); await flush()
	for category: Dictionary in ui.handbook.categories:
		ui.factory_view.handbook_category = str(category.id); ui.queue_refresh(); await flush()
		check("category filter is pure " + str(category.id), Book.filtered(ui).all(func(row: Dictionary): return row.category_id == category.id) and authority.queries == calls)
	ui.factory_view.handbook_category = "all"
	await press("factory:book:modules")
	var all_modules := Book.filtered(ui)
	check("module list remains bounded to sixteen cards", ui.find_children("*","Button",true,false).filter(func(node): return str(node.get_meta("ui_focus_key", "")).begins_with("factory:book:entry:")).size() <= Book.PAGE_SIZE)
	if all_modules.size() > Book.PAGE_SIZE:
		await press("factory:book:next")
		check("pagination uses cached definitions only", ui.factory_view.handbook_page == 1 and authority.queries == calls and keyed("factory:book:entry:" + str(all_modules[Book.PAGE_SIZE].id)) != null)
	await press("factory:book:sources")
	check("resource section exposes six real terrain definitions", ui.handbook.entries.filter(func(row: Dictionary): return row.kind == "terrain").size() == 6)
	ui.open_handbook("module:r34.module.fuel_woodshop"); await flush()
	check("module definition is inspectable without claiming site validity", ui.handbook.selection.id == "module:r34.module.fuel_woodshop" and ui.handbook.selection.current.can_make == null and text_in(ui._body).contains("到建造目录选址") and keyed("factory:preview:r34.module.fuel_woodshop") == null)
	check("requirements use the exact authoritative material gaps", ui.handbook.selection.current.materials.all(func(row: Dictionary): return text_in(ui._body).contains(P.number(row.required)) and text_in(ui._body).contains(P.item_name(row.item_id))))
	check("module card translates public footprint buffers and service sides", text_in(ui._body).contains("占地 " + P.number(5) + " × " + P.number(4)) and text_in(ui._body).contains("原料缓存 · 每物品上限") and text_in(ui._body).contains("供料服务面 · 西侧") and not text_in(ui._body).contains('"buffer_id"'))
	await press("factory:handbook:link:relation:item:timber")
	check("module-to-material association navigates to actual selection", ui.handbook.selection.id == "item:timber" and ui.factory_view.handbook_section == "materials")
	await press("factory:handbook:link:relation:module:r34.module.fuel_woodshop")
	check("material-to-use association is bidirectional", ui.handbook.selection.id == "module:r34.module.fuel_woodshop")
	ui.cancel_ui(); await flush()
	check("Esc returns to previous exact definition", ui.pages.back().subject == "item:timber" and ui.handbook.selection.id == "item:timber")
	before = runtime.capture_checkpoint()
	authority.reject_preference = true
	await press("factory:book:favorite:item:timber")
	check("explicit injected preference rejection is visible and atomic", visible_rejection("偏好提交被拒绝") and not ui.handbook.preferences.favorites.has("item:timber") and Data.json_equal(before, runtime.capture_checkpoint()))
	authority.reject_preference = false
	var favorite_control := keyed("factory:book:favorite:item:timber")
	favorite_control.grab_focus()
	await press("factory:book:favorite:item:timber")
	check("preference receipt rebuild retains keyboard focus", root.gui_get_focus_owner() != null and root.gui_get_focus_owner().get_meta("ui_focus_key", "") == "factory:book:favorite:item:timber")
	check("favorite reflects original command receipt only", ui.handbook.preferences.favorites.has("item:timber") and runtime.capture_checkpoint().world.extensions[Prefs.KEY].handbook.favorites.has("item:timber"))
	check("favorite success has bookmark semantics and no labor claim", ui._notice.text == "已收藏条目" and not ui._notice.text.contains("工时"))
	await press("factory:book:track:item:timber")
	check("tracked target persists through the original display owner", ui.handbook.preferences.tracked_target == "item:timber" and keyed("factory:handbook:link:tracked") != null)
	check("tracking success describes the actual preference only", ui._notice.text.contains("已固定目标") and not ui._notice.text.contains("受理") and not ui._notice.text.contains("工时"))
	await press("factory:book:list")
	await press("factory:book:favorites")
	check("favorites filter consumes only real persisted preference IDs", Book.filtered(ui).size() == 1 and Book.filtered(ui)[0].id == "item:timber")
	await press("factory:book:entry:item:timber")
	check("preferences never grant inventory knowledge or simulation time", Data.json_equal(before.facts, runtime.capture_checkpoint().facts) and Data.json_equal(before.simulation, runtime.capture_checkpoint().simulation))
	ui.close_panels(); ui.open_panel("factory_catalog"); await flush()
	if keyed("factory:handbook:link:catalog:r34.module.warehouse") == null:
		await press("fold:catalog:r34.module.warehouse")
	var catalog_opened := await press("factory:handbook:link:catalog:r34.module.warehouse")
	check("catalog shortcut targets stable definition, never instance", ui.handbook.selection.id == "module:r34.module.warehouse")
	# A real missing entry remains red but cannot abort the rest of the suite.
	if not catalog_opened: return finish()
	ui.cancel_ui(); await flush()
	check("return retains original catalog placement workflow", not ui.pages.is_empty() and ui.pages.back().page == "factory_catalog" and keyed("factory:preview:r34.module.warehouse") != null)
	ui.close_panels(); ui.open_panel("factory_module", str(ui.factory.modules.instances[0].id)); await flush()
	var definition_id: String = ui.factory.modules.instances[0].definition_id
	if keyed("factory:handbook:link:module:" + str(ui.factory.modules.instances[0].id)) == null:
		await press("fold:maintenance:" + str(ui.factory.modules.instances[0].id))
	await press("factory:handbook:link:module:" + str(ui.factory.modules.instances[0].id))
	check("actual module opens its own definition", ui.handbook.selection.id == "module:" + definition_id)
	ui.close_panels(); ui.factory_view.handbook_section = "stories"; ui.open_panel("factory_handbook"); await flush()
	check("legacy stories alias resolves to knowledge child without granting unknown places", ui.factory_view.handbook_section == "knowledge" and ui.factory_view.handbook_subview == "stories" and not text_in(ui._body).contains("临路小店") and not text_in(ui._body).contains("田边仓棚"))
	ui.close_panels()
	var source_id := "r34:generated:RH-HOME:woodwork:stock:tools"
	var source: Dictionary = runtime.stock(source_id)
	var request := {"command_id":"ui:handbook:walk","actor_id":"player","kind":"walk","target_id":"","payload":{},"destination":source.location}
	var walked: Dictionary = runtime.command(request)
	check("real normal body walks to original source", walked.get("ok", false) and progress(), walked)
	var searched: Dictionary = runtime.command({"command_id":"ui:handbook:search","actor_id":"player","kind":"search","target_id":source_id,"payload":{}})
	check("real search reveals original finite tools and record", searched.get("ok", false) and progress() and runtime.stock(source_id).searched)
	ui.open_panel("container", source_id); await flush()
	var choice := keyed("factory:handbook:stock-choice:" + source_id) as OptionButton
	check("real searched inventory exposes definition chooser without replacing slots", choice != null and choice.item_count > 0 and not ui.find_children("*","Button",true,false).filter(func(node): return node.get("slot") is Dictionary and node.slot.get("stock_id") == source_id).is_empty())
	if choice != null:
		var selected_id := str(choice.get_item_metadata(choice.selected))
		await press("factory:handbook:stock-open:" + source_id)
		check("inventory shortcut preserves original unique references", ui.handbook.selection.id == selected_id and runtime.stock(source_id).searched)
		ui.cancel_ui(); await flush()
		var slots := ui.find_children("*","Button",true,false).filter(func(node): return node.get("slot") is Dictionary and node.slot.get("stock_id") == source_id and not node.slot.get("reference", {}).is_empty())
		if not slots.is_empty():
			var carry_before: Dictionary = runtime.capture_checkpoint()
			ui._activate_slot(slots[0].slot); await flush()
			check("original inventory pickup stays a reference until transfer", not ui.carry.is_empty() and Data.json_equal(carry_before, runtime.capture_checkpoint()))
			ui.open_handbook(selected_id); await flush()
			check("handbook cannot cancel or consume carried inventory by navigation", ui.pages.back().page == "factory_inventory" and not ui.carry.is_empty())
			ui.cancel_ui(); await flush()
			check("Esc returns original picked-up reference without loss", ui.carry.is_empty() and Data.json_equal(carry_before, runtime.capture_checkpoint()))
	ui.close_panels(); ui.factory_view.handbook_section = "stories"; ui.open_panel("factory_handbook"); await flush()
	var study: Button = button_with("现场研读木工记录")
	check("knowledge stories retain the actual onsite study action", study != null and not study.disabled)
	if study != null and not study.disabled:
		study.pressed.emit(); await flush()
		check("study retains modal release and real elapsed work", ui.pages.is_empty() and runtime.actor("player").get("intent") is Dictionary)
		check("real study finishes through the only simulation clock", progress())
		runtime.tick(0.1)
	ui.open_handbook("knowledge:basic_woodwork"); await flush()
	check("real learned status is read from authority", ui.handbook.selection.get("learned") == true and text_in(ui._body).contains("已掌握"))
	check("record instance never masquerades as a module link", ui.find_children("*","Button",true,false).filter(func(node): return str(node.get_meta("ui_focus_key", "")).begins_with("factory:book:instance:")).is_empty())
	ui.close_panels(); saved_capture = runtime.capture_checkpoint()
	var encoded: Dictionary = Store.encode(saved_capture)
	var path := output + "/actual-handbook.native.json"
	if encoded.get("ok", false):
		var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(encoded.text); file.close()
	var decoded: Dictionary = Store.decode(FileAccess.get_file_as_string(path)) if encoded.get("ok", false) else encoded
	var cold: Dictionary = host._assemble(decoded.capture) if decoded.get("ok", false) else decoded
	check("real file and cold restore preserve preferences plus original facts", cold.get("ok", false) and Data.json_equal(cold.runtime.capture_checkpoint().facts, decoded.capture.facts) and cold.runtime.handbook_snapshot().preferences == ui.handbook.preferences, cold.get("reason"))
	ui.open_handbook("legacy:cabinet"); await flush()
	check("legacy card cannot offer default building placement", text_in(ui._body).contains("旧式设施") and keyed("factory:facility:preview:cabinet") == null)
	ui.open_handbook("module:unknown"); await flush()
	check("unknown definition fails clearly without rendering old selection", text_in(ui._body).contains("所选定义当前不可用") and ui.handbook.selection.is_empty())
	ui.close_panels(); authority.malformed = true; ui.open_handbook(); await flush()
	check("wrong-schema provider is not treated as available", not ui.handbook.get("available", false) and keyed("factory:book:refresh") != null)
	authority.malformed = false; await press("factory:book:refresh")
	check("explicit retry recovers actual provider", ui.handbook.get("available", false))
	if OS.get_cmdline_user_args().size() > 1: await normal_conditions(OS.get_cmdline_user_args()[1])
	finish()

func normal_conditions(path: String) -> void:
	var original := FileAccess.get_file_as_string(path)
	var decoded: Dictionary = Store.decode(original)
	check("sealed candidate22 normal economy input decodes", decoded.get("ok", false))
	if not decoded.get("ok", false) or not await mount_capture(decoded.capture): return
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_handbook("item:timber"); await flush()
	var current: Dictionary = ui.handbook.selection.current
	var sum := 0.0
	for stock: Dictionary in current.stocks: sum += float(stock.quantity.free)
	check("visible material quantities use exact public stock totals", is_equal_approx(sum, float(current.free)) and text_in(ui._body).contains("已知合计 · 实有 " + P.number(current.actual)) and text_in(ui._body).contains("原料预留 " + P.number(current.reserved)))
	check("remote inventory stays visibly distinct from onsite materials", float(current.free) > float(current.onsite_free) and text_in(ui._body).contains("需真实运到现场"))
	ui.open_handbook("module:r34.module.fuel_woodshop"); await flush()
	check("actual remote/onsite material gaps do not claim construction availability", ui.handbook.selection.current.can_make == null and ui.handbook.selection.current.materials.any(func(row: Dictionary): return float(row.known_free) > float(row.onsite_free)) and text_in(ui._body).contains("现场缺口"))
	check("normal material and requirement inspection preserves complete checkpoint", Data.json_equal(before, runtime.capture_checkpoint()))
	var module := F.find(ui.factory.modules.instances, "r34:generated:RH-HOME:woodwork")
	var approaches: Dictionary = ui.read_service_approaches(str(module.id))
	var access_rows: Array = Access.rows(approaches, module)
	var work := F.find(access_rows, "tools")
	ui.close_panels()
	var walked: Dictionary = Access.activate(ui, str(module.id), str(work.get("id", "")), Access.walk_command(work))
	check("normal body actually reaches real module work side", walked.get("ok", false) and progress(), walked)
	ui.open_handbook(); await flush()
	var handles: Array = ui.handbook.entries.filter(func(row: Dictionary): return row.kind == "process" and row.definition.get("outputs", {}).has("tool_handle"))
	check("real manual handle recipe is supplied by handbook owner", not handles.is_empty())
	if handles.is_empty(): return
	var id := str(handles[0].id)
	ui.open_handbook(id); await flush()
	var offered: Dictionary = ui.handbook.selection.current
	check("manual work uses actual availability and selected physical source", offered.get("can_make") == true and offered.get("request") is Dictionary, offered)
	if offered.get("can_make") != true or not offered.get("request") is Dictionary: return
	var craft: Dictionary = offered.request
	var accepted: Dictionary = ui.execute(str(craft.kind), str(craft.target_id), craft.payload)
	check("original craft command holds real materials before work", accepted.get("ok", false), accepted)
	ui.open_handbook("item:timber"); await flush()
	current = ui.handbook.selection.current
	check("real work reservation is visible once and excluded from free", float(current.reserved) > 0 and is_equal_approx(float(current.actual) - float(current.reserved), float(current.free)) and text_in(ui._body).contains("原料预留 " + P.number(current.reserved)))
	before = runtime.capture_checkpoint()
	ui.refresh_handbook(); await flush()
	check("refreshing active reservation does not advance work or duplicate holds", Data.json_equal(before, runtime.capture_checkpoint()))
	var cancelled: Dictionary = ui.execute("cancel", "")
	check("cancel stays with original owner", cancelled.get("ok", false), cancelled)
	ui.refresh_handbook(); await flush()
	check("explicit refresh reads released original reservation", ui.handbook.selection.current.reserved == 0 and text_in(ui._body).contains("原料预留 0"))
	check("archived candidate22 source file stays byte-identical", FileAccess.get_file_as_string(path) == original)

func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"actual Native runtime/router, counted forwarding query facade, real Control signals, real normal search/study and file cold restore; one explicit atomic command-rejection and malformed-schema test double; no renderer/OS/PCK/VA/FPS qualification"}, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
