extends "res://tests/ui/run_service_access_ui.gd"
const ObjectPanel = preload("res://scripts/ui/factory_object.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const C = preload("res://scripts/ui/ui_composition.gd")

func run() -> void:
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800); root.content_scale_size = Vector2i(1280, 800)
	host = TestClient.new(); root.add_child(host)
	var profiles: Dictionary = Assembly.generation_profiles()
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713, profiles.profiles)) if profiles.get("ok", false) else profiles
	check("normal current world assembles", prepared.get("ok", false))
	if not prepared.get("ok", false) or not await mount_capture(prepared.capture): return finish()
	# A's DirectInteraction normally owns cancellation. This explicit router
	# fixture mirrors that public mode transition; it is not OS input evidence.
	router.cancel_requested.connect(func(): router.set_mode("tool"))
	var id := "r34:generated:RH-HOME:woodwork"
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_panel("module", id); await flush()
	check("module route returns exact fixed identity", ui.world_view_selection() == {"kind":"module", "id":id})
	check("object has right sidebar and world remains majority", ui._dialog.position.x > 700 and ui._dialog.size.x <= 520, ui._dialog.get_rect())
	check("no business navigation on object", keyed("factory:nav:factory_production") == null)
	check("unknown stock explained only once", text_in(ui._body).count("尚未搜索的缓存不显示内容") == 1)
	check("physical production flow and real service approaches retained", text_in(ui._body).contains("原料 → 加工 → 成品") and keyed("factory:service:"+id+":tools") != null)
	check("rendering never changes authority state", Data.json_equal(before, runtime.capture_checkpoint()))
	ui.open_panel("water", "unknown-water"); await flush()
	check("water fixed identity independent from hover", ui.world_view_selection() == {"kind":"water", "id":"unknown-water"})
	check("unknown water reveals no finite balance", not text_in(ui._body).contains("48") and text_in(ui._body).contains("尚未发现"))
	ui.cancel_ui(); await flush()
	check("Esc restores original object context", ui.world_view_selection() == {"kind":"module", "id":id})
	ui.open_panel("factory_catalog"); await flush()
	var module_id := str(F.rows(ui.factory, "modules", "definitions")[0].id)
	var ready: Dictionary = ui.begin_module_preview(module_id); await flush()
	check("catalog remains open alongside actual router placement", ready.get("ok", false) and ui.pages.back().page == "factory_catalog" and ui.planning_active())
	check("world input and simulation resume outside planning controls", not router.is_paused() and not runtime.is_paused() and ui._modal.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var search := keyed("factory:search:catalog_search") as LineEdit
	search.grab_focus(); await flush()
	check("planning search owns input without advancing world privately", router.is_paused())
	ui._dialog.grab_focus(); await flush()
	check("leaving search restores world routing", not router.is_paused())
	ui.cancel_ui(); await flush()
	check("first Esc cancels preview retaining catalog", not ui.planning_active() and ui.pages.back().page == "factory_catalog" and router.is_paused())
	ui.cancel_ui(); await flush()
	check("second Esc returns original object sidebar", ui.world_view_selection() == {"kind":"module", "id":id})
	for page: String in ["factory_module", "factory_catalog", "factory_inventory", "factory_people", "factory_logistics", "factory_alerts", "factory_handbook", "npc", "workbench", "water", "settings", "pause"]:
		for viewport in [Vector2i(1280,800), Vector2i(1000,700)]:
			root.size = viewport; root.content_scale_size = viewport; await flush()
			ui.set_text_scale(1.5 if viewport.x==1000 else 1.0)
			ui.open_panel(page,id if page=="factory_module" else ""); await flush()
			var rect: Rect2 = ui._dialog.get_rect()
			check("native bounds " + page + " " + str(viewport), rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=viewport.x and rect.end.y<=viewport.y, {"rect":rect,"minimum":ui._dialog.get_combined_minimum_size()})
		ui.close_panels(); await flush()
	check("closing releases fixed selection", ui.world_view_selection().is_empty())
	var definition := F.definition(ui.factory, "r34.module.fuel_woodshop")
	var actual_image := Images.module_texture(definition)
	check("exact machine geometry thumbnail loads without UI importer", actual_image != null and actual_image.get_size() == Vector2(256,256))
	check("unknown module never substitutes a machine thumbnail", Images.module_texture({"id":"r34.module.guard_post"}) == null)
	definition.geometry_version = "future-version"
	check("changed geometry cannot retain obsolete thumbnail", Images.module_texture(definition) == null)
	for code: String in ["output_full","missing_energy","paused","running"]:
		var fixture := {"state_code":code,"blockers":[]}
		check("primary cause follows new owner state " + code, ObjectPanel.main_reason(fixture) == ("" if code=="running" else F.STATE_NAMES[code]))
	finish()
