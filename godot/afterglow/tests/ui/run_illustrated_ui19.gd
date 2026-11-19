extends "res://tests/ui/run_controls15.gd"
## Illustrated UI19: real village authority, delivered textures and multi-page Viewport inspection.
const RecipeActions18 = preload("res://scripts/ui/building_recipe_actions.gd")
class GraphicsHost extends Client:
	func _ready() -> void: pass
var images18: Array = []
var observations18: Array = []
var graphics18: bool = false

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): check("suite finishes before watchdog", false); finish())
	call_deferred("run")

func meta_nodes18(node: Node, key: String) -> Array:
	var result: Array = [node] if node.has_meta(key) else []
	for child: Node in node.get_children(): result.append_array(meta_nodes18(child, key))
	return result

func capture18(label: String) -> void:
	if not graphics18: return
	await flush()
	await RenderingServer.frame_post_draw
	var path := output + "/" + label + ".png"
	var result := root.get_texture().get_image().save_png(path)
	images18.append({"path":path, "error":result})
	check("rendered screenshot " + label, result == OK)

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	graphics18 = OS.get_cmdline_user_args().has("--graphics") and DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	if graphics18:
		host = GraphicsHost.new(); host.store = Store.new(output + "/isolated-saves"); host.controls_path = output + "/controls.json"; root.add_child(host)
		var started: Dictionary = await host.start_profiled_world("normal", 713, "building18-ui")
		check("shipping scene mounts with original physics/readiness", started.get("ok", false), started)
		if not started.get("ok", false): return finish()
		runtime = host.runtime; router = host.router; ui = host.ui
	else:
		host = ControlsHost.new(); root.add_child(host)
		var profiles: Dictionary = Assembly.generation_profiles()
		var prepared: Dictionary = Assembly.prepare(Assembly.generate(713, profiles.profiles))
		check("original finite village prepares", prepared.get("ok", false))
		if not prepared.get("ok", false): return finish()
		var made: Dictionary = host._assemble(Opening.prepare_opening(prepared.capture, "normal"))
		check("actual original authority assembles", made.get("ok", false))
		if not made.get("ok", false): return finish()
		runtime = made.runtime; router = RealRouter.new(); router.controls_path = output + "/controls.json"
		host.add_child(router); router.configure(runtime, false, true); ui = Mount.mount(host, runtime, router)
	runtime.set_paused(true)
	await flush()
	var original: Dictionary = runtime.capture_checkpoint()
	for suffix: String in ["village-workshop", "village-home", "village-warehouse"]:
		var id := "r34:generated:RH-HOME:" + suffix
		ui.close_panels(); ui.open_panel("factory_module", id); await flush()
		var module := F.instance(ui.factory, id)
		if module.is_empty():
			# Find by actual public definition for any generator instance naming.
			var wanted: String = {"village-workshop":"workshop", "village-home":"home", "village-warehouse":"warehouse"}[suffix]
			for row: Dictionary in F.rows(runtime.factory_snapshot("player"), "modules", "instances"):
				if str(row.get("definition_id", "")).contains("village_" + str(wanted)):
					id = str(row.id); break
			ui.close_panels(); ui.open_panel("factory_module", id); await flush(); module = F.instance(ui.factory, id)
		check("actual building opens " + suffix, not module.is_empty(), id)
		if module.is_empty(): continue
		check("functional first page " + suffix, ui._body.has_meta("ui_building_actions") and not meta_nodes18(ui._body,"ui_building_identity").is_empty())
		check("functional names avoid architectural jargon " + suffix, ui._title.text in ["工作棚", "住宅", "仓库"], ui._title.text)
		var heroes19 := meta_nodes18(ui._body, "ui_building_hero19")
		check("live illustrated building header " + suffix, heroes19.size() == 1 and heroes19[0].get_meta("ui_hero_art_kind") == "function-illustration")
		check("advanced machinery prose hidden " + suffix, not text_in(ui._body).contains("有效工作秒") and not text_in(ui._body).contains("库存分类、保留量与目标"))
		if suffix == "village-workshop":
			var recipes := meta_nodes18(ui._body, "ui_building_recipe")
			var available_recipes := RecipeActions18.choices(module, F.definition(ui.factory, str(module.definition_id)), ui.factory, ui.snapshot)
			var first_group: String = RecipeActions18.category(available_recipes[0]) if not available_recipes.is_empty() else ""
			var expected_count := available_recipes.filter(func(choice: Dictionary): return RecipeActions18.category(choice) == first_group).size()
			check("workshop directly displays exact recipe group", recipes.size() == expected_count and expected_count > 0, recipes.size())
			check("only one recipe form shown", meta_nodes18(ui._body, "ui_building_selected_recipe").size() == 1)
			if not available_recipes.is_empty():
				var recipe: Dictionary = available_recipes[0].recipe
				var craft := keyed("building:craft:" + id + ":" + str(recipe.id)) as Button
				var shortage: bool = false
				var pack: Dictionary = ui.snapshot.get("player_stock", {})
				for stock: Dictionary in ui.snapshot.get("stocks", []):
					if stock.get("id") == "pack:player": pack = stock; break
				for item: String in recipe.get("inputs", {}):
					if float(pack.get("items", {}).get(item, 0)) < float(recipe.inputs[item]): shortage = true
				check("visible missing ingredients keep craft unavailable before walking", shortage and craft != null and craft.disabled and text_in(ui._body).contains("缺"))
			if recipes.size() > 1:
				var chosen := str(recipes[1].get_meta("ui_building_recipe"))
				var focus_key := str(recipes[1].get_meta("ui_focus_key"))
				await click_key(focus_key)
				check("native click selects exact recipe", str(meta_nodes18(ui._body,"ui_building_selected_recipe")[0].get_meta("ui_building_selected_recipe")) == chosen)
			for group: String in ["woodwork", "tools", "life"]:
				var expected := available_recipes.filter(func(choice: Dictionary): return RecipeActions18.category(choice) == group).size()
				if expected == 0: continue
				await click_key("building:recipe-group:" + id + ":" + group)
				check("native category exposes exact supported recipes " + group, meta_nodes18(ui._body, "ui_building_recipe").size() == expected)
			if not first_group.is_empty(): await click_key("building:recipe-group:" + id + ":" + first_group)
		if suffix == "village-home": check("actual home shows physical beds", not meta_nodes18(ui._body, "ui_building_life_bed").is_empty())
		if suffix == "village-warehouse": check("damaged warehouse has direct repair action", keyed("factory:command:module.restore:" + id) != null)
		await capture18(suffix + "-1280")
		await click_key("building:tab:manage:" + id)
		check("native management tab remains reachable " + suffix, not ui._body.has_meta("ui_building_actions") and button_with("可用功能") != null)
		await click_key("building:tab:use:" + id)
		check("native action tab restores functional first page " + suffix, ui._body.has_meta("ui_building_actions"))
		observations18.append({"id":id,"title":ui._title.text,"recipe_cards":meta_nodes18(ui._body,"ui_building_recipe").size(),"beds":meta_nodes18(ui._body,"ui_building_life_bed").size()})
		if graphics18:
			root.size = Vector2i(1000, 700); root.content_scale_size = root.size; await flush()
			check("small window panel fits " + suffix, ui._dialog.get_global_rect().end.x <= root.size.x + 1 and ui._dialog.size.x > 0, ui._dialog.get_global_rect())
			await capture18(suffix + "-1000")
			root.size = Vector2i(1280, 800); root.content_scale_size = root.size; await flush()
	if graphics18:
		for page19: String in ["factory_inventory","factory_catalog","factory_production","factory_people","settings","pause"]:
			ui.close_panels(); ui.open_panel(page19, "pack:player" if page19=="factory_inventory" else ""); await flush()
			check("real live page opens " + page19, not ui.pages.is_empty() and ui.pages.back().page == page19)
			for size19: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
				root.size = size19; root.content_scale_size = root.size; await flush()
				check("page stays within viewport " + page19 + str(size19.x), ui._dialog.get_global_rect().end.x <= root.size.x+1)
				await capture18(page19+"-"+str(size19.x))
			root.size = Vector2i(1280,800); root.content_scale_size = root.size; await flush()
	check("inspection and recipe/tab selection preserve all authority facts", Data.json_equal(original, runtime.capture_checkpoint()))
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observations18,"images":images18,"scope":"Illustrated19 native UI and actual finite opening; delivered art on three building banners and global multi-page skin; Viewport input and two-size shipping-renderer captures. No FPS or all-seed qualification."},"\t",true,true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
