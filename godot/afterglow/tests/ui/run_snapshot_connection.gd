extends SceneTree
## Focused continuation: production A/B/C/UI plus A's actual storage callbacks.
## Headless isolated fixture only; not the formal application or physical input route.
const World = preload("res://scripts/world/world_state.gd")
const Rural = preload("res://scripts/world/rural_generator.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Buildings = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Router = preload("res://scripts/input/input_router.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")

class StorageHost extends "res://scripts/runtime/native_client.gd":
	# Reuse actual save coordinator without starting/mounting the formal application.
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var checks: Array = []
var failed := false
var output := ""
var host: StorageHost
var world := World.new()
var runtime := Runtime.new()
var buildings := Buildings.new()
var actions := Actions.new()
var production := Production.new()
var router: Node
var ui: Control
var station := "ui-snapshot:bench"
var services: Dictionary

func _initialize() -> void:
	create_timer(55).timeout.connect(func(): push_error("UI snapshot check timeout"); quit(2))
	call_deferred("run")

func check(name: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"name":name, "ok":condition, "detail":detail.duplicate(true) if detail is Dictionary or detail is Array else detail})
	if not condition: failed = true; push_error(name + " " + str(detail))

func command(kind: String, target: String = "", payload: Dictionary = {}) -> Dictionary:
	return ui.execute(kind, target, payload)

func button_key(node: Node, key: String) -> Button:
	if node is Button and str(node.get_meta("ui_focus_key", "")) == key: return node
	for child in node.get_children():
		var found := button_key(child, key)
		if found != null: return found
	return null

func controls(node: Node, kind: String) -> Array:
	var result: Array = []
	if node.is_class(kind): result.append(node)
	for child in node.get_children(): result.append_array(controls(child, kind))
	return result

func craft_payload(recipe: String, repair_id: String = "") -> Dictionary:
	var p := P.player_stock(ui.snapshot)
	var value := {"recipe_id":recipe, "source_id":str(p.id), "output_id":str(p.id), "tool_ids":Panels._tool_ids(p, ui.snapshot, repair_id)}
	if not repair_id.is_empty(): value.repair_tool_id = repair_id
	return value

func craft_button(payload: Dictionary) -> Button:
	return button_key(ui, "craft:" + station + ":" + str(payload.hash()))

func patch_pack(values: Dictionary) -> void:
	var facts: Dictionary = runtime.facts()
	facts.actors[0].pack.merge(values, true)
	var result: Dictionary = runtime.configure(host._context(world, services, facts, {}, runtime.get_revision()))
	check("isolated fixture fact configure", result.get("ok", false), result.get("reason"))
	ui.refresh()

func commit_extension(key: String, value: Dictionary) -> bool:
	var prepared: Dictionary = world.prepare_changes([buildings.extension_change(key, value)], world.get_revision())
	return prepared.get("ok", false) and world.commit_prepared(prepared.capability).get("ok", false)

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): push_error("explicit isolated output directory required"); quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	check("real C rural world loads", world.load_snapshot(Rural.generate(713)).get("ok", false))
	host = StorageHost.new()
	host.store = Store.new(output + "/slots")
	root.add_child(host)
	host.runtime = runtime
	host.world = world
	services = {"buildings":buildings, "actions":actions, "production":production}
	var at := {"x":30.0, "y":0.0, "z":43.0, "regionId":"RH-HOME", "buildingId":null, "storeyId":null}
	var actor := at.duplicate(true)
	actor.merge({"id":"player", "name":"隔离接线检查", "hp":100.0, "hunger":100.0, "thirst":100.0, "stamina":100.0, "fatigue":0.0, "skills":{"crafting":2}, "pack":{"log":1,"timber":8,"scrap":6,"tool_handle":1,"book_woodwork":1}, "relationship":{"member":true,"consent":true}, "intent":null})
	var facts := {"time":0.0,"status":"playing","actors":[actor],"stocks":[],"actions":[],"quests":[]}
	check("real A context includes catalog and actual storage", runtime.configure(host._context(world, services, facts)).get("ok", false))
	var piece: Dictionary = buildings.make_instance("workbench", station, {"x":21,"y":0,"z":44,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var prepared: Dictionary = buildings.prepare_edit([], [piece])
	check("B validates isolated real workbench fixture", prepared.get("ok", false), prepared.get("reason"))
	if not prepared.get("ok", false): finish(); return
	var draft: Dictionary = world.prepare_changes(prepared.world_changes, world.get_revision())
	check("C commits B workbench fixture", draft.get("ok", false) and world.commit_prepared(draft.capability).get("ok", false))
	actor.merge(buildings.use_points(station)[0], true)
	var state: Dictionary = Production.empty_state()
	state.tools = [{"id":"ui-snapshot:saw","kind":"hand_saw","holderId":"pack:player","durability":90.0},{"id":"ui-snapshot:hammer","kind":"hammer","holderId":"pack:player","durability":90.0},{"id":"ui-snapshot:axe","kind":"salvaged_axe","holderId":"pack:player","durability":20.0}]
	state.records = [{"id":"ui-snapshot:book","holderId":"pack:player","itemId":"book_woodwork","grants":["basic_woodwork"],"seconds":12.0}]
	state.knowledge = {"player":["basic_woodwork","basic_tool_repair"]}
	check("C commits explicit production fixture once", commit_extension(Production.KEY, state))
	check("real services configured at actual bench use point", runtime.configure(host._context(world, services, facts)).get("ok", false))
	router = Router.new(); root.add_child(router); router.configure(runtime)
	host.router = router
	ui = Mount.mount(root, runtime, router)
	await process_frame
	ui.open_panel("workbench", station)
	var snapshot: Dictionary = runtime.snapshot()
	check("real Dictionary catalog exposes recipes tools structures", snapshot.catalog is Dictionary and snapshot.catalog.production_recipes.size() > 0 and snapshot.catalog.tool_definitions.has("salvaged_axe") and snapshot.catalog.buildings.size() > 0)
	check("UI uses actual catalog and records", Panels._catalog(ui, "recipes").size() == snapshot.catalog.production_recipes.size() and snapshot.records.size() == 1)
	var labels: Array = controls(ui._body, "Label").map(func(node: Label): return node.text)
	var buttons: Array = controls(ui._body, "Button").map(func(node: Button): return node.text)
	check("book identity and physical source shown readably", buttons.has("研读 木工手册") and labels.has("随身背包 · 研读工时 12.0秒"), {"buttons":buttons,"source_labels":labels.filter(func(t: String): return t.contains("研读工时"))})
	await progress_cases()
	await production_cases()
	await storage_cases()
	ui.get_parent().queue_free(); router.queue_free(); host.queue_free()
	await process_frame
	finish()

func progress_cases() -> void:
	ui.close_panels()
	runtime.set_target({"id":station,"name":"真实工位","kind":"workbench","enabled":true,"progress":0.375,"projected_position":{"x":500,"y":400}})
	ui.refresh()
	check("scalar target progress rendered from real runtime target", ui._progress.visible and is_equal_approx(ui._progress.max_value, 1.0) and is_equal_approx(ui._progress.value, 0.375), {"visible":ui._progress.visible,"maximum":ui._progress.max_value,"value":ui._progress.value,"target":runtime.snapshot().target})
	runtime.set_target({"id":station,"enabled":true,"progress":{"seconds":8.0,"elapsed":3.0}}); ui.refresh()
	check("dictionary seconds target remains supported", ui._progress.visible and ui._progress.max_value == 8.0 and ui._progress.value == 3.0)
	check("nonfinite progress hidden and overshoot clamped", P.progress(NAN).is_empty() and P.progress({"duration":INF}).is_empty() and P.progress({"seconds":4,"elapsed":8}).value == 4 and P.progress(-1).value == 0)
	var order := {"id":"ui-snapshot:structure-order","actorId":"player","kind":"place","status":"cancelled","seconds":6.0,"elapsed":2.0,"cost":{}}
	check("actual C structure order extension publishes", commit_extension("r3:structure-orders", {"version":1,"orders":[order]}))
	ui.open_panel("quests")
	var bars := controls(ui._body, "ProgressBar")
	check("actual structure seconds order renders bar", bars.any(func(bar: ProgressBar): return bar.max_value == 6.0 and bar.value == 2.0), bars.size())
	ui.close_panels()
	await process_frame

func production_cases() -> void:
	ui.open_panel("workbench", station)
	var payload := craft_payload("saw_timber")
	var ready := craft_button(payload)
	check("real one-batch craft button enabled", ready != null and not ready.disabled, ready.tooltip_text if ready != null else "missing button")
	patch_pack({"log":0})
	var empty := craft_button(craft_payload("saw_timber"))
	check("missing material disables UI with authoritative reason", empty != null and empty.disabled and empty.tooltip_text.contains("材料"), empty.tooltip_text if empty != null else "missing")
	var before: Dictionary = runtime.capture_checkpoint()
	var rejected := command("craft", station, craft_payload("saw_timber"))
	check("missing-material submit keeps facts tools and world unchanged", not rejected.get("ok", false) and before == runtime.capture_checkpoint(), rejected)
	patch_pack({"log":1})
	payload = craft_payload("saw_timber")
	ready = craft_button(payload)
	if ready != null and not ready.disabled: ready.pressed.emit()
	await process_frame
	var orders: Array = production.state().orders
	check("UI button starts real production order without consuming reserved material", orders.size() == 1 and orders[0].kind == "craft" and runtime.actor("player").pack.log == 1, ui._notice.text)
	ui.open_panel("workbench", station)
	var pack := P.player_stock(ui.snapshot)
	check("real material reservation projected as unavailable", P.entry(pack, ui.snapshot, {"kind":"item","item_id":"log"}).get("available", -1) == 0, pack.get("reserved"))
	check("real tool reservation excluded from UI selection", not Panels._tool_ids(pack, ui.snapshot).has("ui-snapshot:saw") and P.entry(pack, ui.snapshot, {"kind":"tool","tool_id":"ui-snapshot:saw"}).get("available", -1) == 0)
	before = runtime.capture_checkpoint()
	rejected = command("craft", station, craft_payload("saw_timber"))
	check("reserved repeat fails without extra order or consumption", not rejected.get("ok", false) and before == runtime.capture_checkpoint(), rejected)
	check("cancel uses real service to release holds", command("cancel_work").get("ok", false))
	ui.refresh()
	check("cancel restores available material and same tool identity", P.entry(P.player_stock(ui.snapshot), ui.snapshot, {"kind":"item","item_id":"log"}).get("available") == 1 and Panels._tool_ids(P.player_stock(ui.snapshot), ui.snapshot).has("ui-snapshot:saw"))
	# Another actor's real construction extension reserves the remaining log/hammer.
	var hold := {"id":"ui-snapshot:other-hold","actorId":"other","sourceId":"pack:player","status":"active","cost":{"log":1},"toolId":"ui-snapshot:hammer","seconds":4.0,"elapsed":0.0}
	check("C commits isolated cross-domain hold fixture", commit_extension("r3:structure-orders", {"version":1,"orders":[hold]}))
	ui.refresh(); pack = P.player_stock(ui.snapshot)
	check("construction material and tool holds reach actual UI", P.entry(pack, ui.snapshot, {"kind":"item","item_id":"log"}).get("available") == 0 and not Panels._tool_ids(pack, ui.snapshot).has("ui-snapshot:hammer"))
	var reserved_button := craft_button(craft_payload("saw_timber"))
	check("other order material reservation disables craft with reason", reserved_button != null and reserved_button.disabled and reserved_button.tooltip_text.contains("预留"), reserved_button.tooltip_text if reserved_button != null else "missing")
	check("isolated hold removed through C", commit_extension("r3:structure-orders", {"version":1,"orders":[]}))
	ui.refresh()
	var repair := craft_payload("repair_axe", "ui-snapshot:axe")
	check("repair payload separates target from operating tools", not repair.tool_ids.has(repair.repair_tool_id) and repair.tool_ids.has("ui-snapshot:hammer"), repair)
	var repair_button := craft_button(repair)
	check("actual tool repair option is reachable", repair_button != null and not repair_button.disabled, repair_button.tooltip_text if repair_button != null else "missing")
	if repair_button != null and not repair_button.disabled: repair_button.pressed.emit()
	await process_frame
	orders = production.state().orders
	var last: Dictionary = orders[-1] if not orders.is_empty() else {}
	check("repair UI reaches actual B order with separate unique target", last.get("repairToolId") == "ui-snapshot:axe" and last.get("toolIds", []).has("ui-snapshot:hammer") and not last.get("toolIds", []).has("ui-snapshot:axe"), last)
	check("repair acceptance does not fake completion", runtime.tool("ui-snapshot:axe").durability == 20.0 and runtime.actor("player").pack.tool_handle == 1)
	check("repair cancel preserves original durability materials and identity", command("cancel_work").get("ok", false) and runtime.tool("ui-snapshot:axe").durability == 20.0 and runtime.actor("player").pack.tool_handle == 1)
	ui.close_panels()

func storage_cases() -> void:
	ui.open_panel("pause")
	check("actual ready storage unlocks UI", ui.storage_reason("save_async").is_empty() and not button_key(ui, "pause:save").disabled)
	# Start outside UI, just like closing/Cmd-S, using A's production coordinator.
	host.save_async("external-ui-contract")
	check("actual save publishes busy before completion", host._save_state.busy)
	ui.refresh()
	check("external saving is shown and all file actions disabled", ui._storage_status.visible and button_key(ui,"pause:save").disabled and button_key(ui,"pause:export").disabled and button_key(ui,"pause:import").disabled, ui._storage_status.text)
	var serial_before: int = ui._serial
	ui.save_world()
	check("UI blocks external-busy duplicate before request allocation", ui._serial == serial_before and not ui.saving)
	ui._file_operation = "export"
	await ui._file_selected(output + "/busy-must-not-export.json")
	check("file callback rechecks actual busy state", ui._serial == serial_before and not FileAccess.file_exists(output + "/busy-must-not-export.json"))
	while host._saving: await process_frame
	ui.refresh()
	check("real atomic save unlocks UI after receipt", host._save_state.status == "saved" and not button_key(ui,"pause:save").disabled, ui._storage_status.text)
	var good_store: RefCounted = host.store
	var active_path := output + "/slots/active.json"
	var prior_bytes := FileAccess.get_file_as_bytes(active_path)
	check("actual isolated save created pointer", not prior_bytes.is_empty())
	# Deterministic real I/O refusal: parent path is a file, never a user save path.
	var blocker := FileAccess.open(output + "/blocked-parent", FileAccess.WRITE)
	blocker.store_string("UI storage failure fixture"); blocker.close()
	host.store = Store.new(output + "/blocked-parent/slots")
	var before: Dictionary = runtime.capture_checkpoint()
	await ui.save_world()
	ui.refresh()
	check("UI shows actual native write failure and permits retry", host._save_state.status == "failed" and ui._notice.text.contains("无法") and ui._storage_status.text.begins_with("保存失败") and not button_key(ui,"pause:save").disabled, {"notice":ui._notice.text,"save":host._save_state})
	check("failed save keeps live facts and previous real save bytes", before == runtime.capture_checkpoint() and prior_bytes == FileAccess.get_file_as_bytes(active_path))
	var failure_receipt := {"ok":false,"code":"IO_ERROR","reason":host._save_state.reason,"request_id":"window-close"}
	host._closing = true; router.set_closing(true); router.set_window_focus(false)
	runtime.close_failed.emit(failure_receipt)
	check("actual close failure signal opens retry and return", ui.pages.back().page == "close_failed" and button_key(ui,"close:retry") != null and button_key(ui,"close:return") != null)
	ui.cancel_close()
	check("return uses A callback and preserves independent focus pause", not host._closing and ui.pages.is_empty() and not router.state().pause_reasons.closing and router.state().pause_reasons.window_focus)
	router.set_window_focus(true)
	ui.open_panel("pause")
	host.store = good_store
	await ui.save_world(); ui.refresh()
	check("retry only reports success after actual save", host._save_state.status == "saved" and ui._notice.text == "完整世界已保存" and not ui.saving, ui._notice.text)
	var restored: Dictionary = host.store.load_current()
	check("real saved facts and tools reload without duplicate authority", restored.get("ok", false) and Data.json_equal(restored.capture.facts, runtime.facts()) and restored.capture.world.extensions[Production.KEY].tools.size() == 3, {"reason":restored.get("reason"),"restored":restored.get("capture",{}).get("facts"),"live":runtime.facts(),"tool_count":restored.get("capture",{}).get("world",{}).get("extensions",{}).get(Production.KEY,{}).get("tools",[]).size()})
	var export_path := output + "/中文-检查点.json"
	ui._file_operation = "export"
	await ui._file_selected(export_path)
	var exported := FileAccess.get_file_as_bytes(export_path)
	check("UI export reaches actual native writer for Chinese path", not exported.is_empty() and ui._notice.text.contains("实际写出"), ui._notice.text)
	ui._file_operation = "export"
	await ui._file_selected(export_path)
	check("duplicate export shows FILE_EXISTS and keeps original bytes", ui._notice.text.contains("已存在") and FileAccess.get_file_as_bytes(export_path) == exported, ui._notice.text)
	var bad_path := output + "/bad-checkpoint.json"
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string(JSON.stringify({"format":"afterglow-native-v1","payload":"damaged","sha256":"invalid"})); bad_file.close()
	ui._file_operation = "import"
	await ui._file_selected(bad_path)
	check("invalid import refuses actual non-checkpoint preserving world", not ui.importing and before == runtime.capture_checkpoint() and not ui._notice.text.contains("已验证并导入"), ui._notice.text)
	ui._file_cancelled()
	check("file cancel releases only dialog reason preserving modal", router.state().pause_reasons.modal and not router.state().pause_reasons.file_dialog)
	ui.close_panels()

func finish() -> void:
	var report := {"scope":"focused actual A/B/C/UI and native coordinator/store in isolated headless fixture; no formal app/physical input acceptance", "ok":not failed, "checks":checks}
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print(JSON.stringify(report))
	quit(1 if failed else 0)
