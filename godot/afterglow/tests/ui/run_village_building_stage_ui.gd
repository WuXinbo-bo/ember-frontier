extends "res://tests/ui/run_service_access_ui.gd"

const Profile = preload("res://scripts/runtime/playtest_profile.gd")
const Warehouse := "r34:generated:RH-HOME:village-warehouse"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else OS.get_user_data_dir() + "/village-stage-ui-test"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	host = TestClient.new()
	root.add_child(host)
	var profiles := Assembly.generation_profiles(18)
	var prepared := Assembly.prepare(Assembly.generate(713, profiles.profiles, 18))
	check("fresh content 18 prepares", prepared.get("ok", false), prepared.get("reason"))
	if not prepared.get("ok", false) or not await mount_capture(Profile.prepare_opening(prepared.capture, "normal")):
		return finish()
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_panel("factory_catalog")
	await flush()
	var catalog := text_in(ui._body)
	check("real catalogue shows current and next stage with restoration requirements", catalog.contains("旧村安顿") and catalog.contains("生产街") and catalog.contains("修好旧宅") and catalog.contains("修好仓棚"), catalog)
	var sawmill := keyed("factory:preview:r38.module.sawmill") as Button
	check("sawmill stays visible but blocked until production street", sawmill != null and sawmill.disabled and sawmill.tooltip_text.contains("生产街"))
	var stockyard := keyed("factory:preview:r38.module.stockyard") as Button
	check("opening stockyard is selectable", stockyard != null and not stockyard.disabled)
	ui.close_panels()
	ui.factory_view["building_tab:" + Warehouse] = "manage"
	ui.factory_view["fold:upgrade:" + Warehouse] = true
	ui.open_panel("factory_module", Warehouse)
	await flush()
	var warehouse := text_in(ui._body)
	check("warehouse manages the real tier-2 proposal and benefit", warehouse.contains("建筑升级 · 1 级") and warehouse.contains("2 级 · 分区仓棚") and warehouse.contains("增加库位"), warehouse)
	check("unfinished restoration cannot start an upgrade", keyed("factory:command:module.upgrade:" + Warehouse + ":r38.module.warehouse.lv2") == null)
	check("viewing stage and upgrade panels does not change the world", Data.json_equal(before, runtime.capture_checkpoint()))
	finish()
