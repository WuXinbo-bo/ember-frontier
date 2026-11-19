extends "res://tests/ui/run_service_access_ui.gd"
## Actual normal source -> formal controls -> paid cabinet -> original loaded move.
## Pointer rays and Control signals are explicit, not OS/renderer qualification.
const Movable = preload("res://scripts/ui/factory_movable.gd")
const Slot = preload("res://scripts/ui/inventory_slot.gd")
class PointerProbe extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _refresh_at(_mouse: Vector2) -> void: pass
	func _process(_delta: float) -> void: pass
var direct: Node
var camera: Camera3D
var surface: Node3D
var input_path := ""
var input_sha := ""
var cabinet_id := ""

func find_slot(stock_id: String, kind: String, id: String, node: Node = null) -> Button:
	if node == null: node = ui._body
	if node is Slot and node.slot.get("stock_id") == stock_id:
		var reference: Dictionary = node.slot.get("reference", {})
		if reference.get("kind") == kind and reference.get("tool_id" if kind == "tool" else "item_id") == id: return node
	for child in node.get_children():
		var found: Button = find_slot(stock_id, kind, id, child)
		if found != null: return found
	return null

func quick_transfer(stock_id: String, kind: String, id: String) -> bool:
	var cell: Button = find_slot(stock_id, kind, id)
	if cell == null: return false
	cell._click_shift = true; cell.pressed.emit(); await flush()
	return ui.carry.is_empty()

func attach_pointer() -> void:
	camera = Camera3D.new(); host.add_child(camera)
	surface = Node3D.new(); host.add_child(surface)
	direct = PointerProbe.new(); host.add_child(direct)
	direct.configure({"runtime":runtime,"world":runtime.world,"router":router,"camera":camera,"buildings":runtime._services.buildings,"terrain":surface,"ui":ui})

func detach_pointer() -> void:
	if is_instance_valid(direct): direct.free()
	if is_instance_valid(surface): surface.free()
	if is_instance_valid(camera): camera.free()

func aim(point: Vector3) -> void:
	direct._point = {"distance":10.0,"unknown":false}
	direct._update_preview(router.held_reference(), point + Vector3.UP * 10.0, Vector3.DOWN)

func fix_position() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	router._unhandled_input(event)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	router._unhandled_input(event)

func confirm_position() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	router._unhandled_input(event)

func open_cabinet() -> void:
	router.set_mode("tool")
	direct._target = direct._describe(runtime.world.entity(cabinet_id))
	router.interact_requested.emit(); await flush()

func walk_to(at: Dictionary) -> bool:
	ui.close_panels(); await flush()
	var start: Dictionary = router.request("walk", "", {}, at)
	return start.get("ok", false) and progress() and G.point(runtime.actor("player")).distance_to(G.point(at)) < 0.2

func cold_restore(label: String) -> bool:
	var encoded: Dictionary = Store.encode(runtime.capture_checkpoint())
	if not encoded.get("ok", false): return false
	var path := output + "/" + label + ".native.json"
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(encoded.text); file.close()
	var decoded: Dictionary = Store.decode(FileAccess.get_file_as_string(path))
	if not decoded.get("ok", false): return false
	detach_pointer()
	if not await mount_capture(decoded.capture): return false
	attach_pointer()
	return Data.json_equal(decoded.capture.facts, runtime.facts())

func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; input_path = args[1]
	DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	input_sha = FileAccess.get_sha256(input_path)
	var decoded: Dictionary = Store.decode(FileAccess.get_file_as_string(input_path))
	check("immutable successful normal economy source decodes", decoded.get("ok", false))
	if not decoded.get("ok", false): finish(); return
	host = TestClient.new(); root.add_child(host)
	if not await mount_capture(decoded.capture): finish(); return
	attach_pointer()
	check("normal source follows both paid machine batches and physical delivery", runtime.snapshot().get("opening_profile") == "normal" and runtime.stock("r34:normal-built-warehouse:stock:storage").items.get("timber") == 8.0 and runtime.actor("player").pack.get("timber") == 2.0)
	var drink: Dictionary = ui.execute("drink", "", {}, true)
	check("original carried water pays personal care through real action", drink.get("ok", false) and progress())
	if not drink.get("ok", false): finish(); return
	var warehouse := "r34:normal-built-warehouse"
	var source_id := warehouse + ":stock:storage"
	ui.open_panel("module", warehouse); await flush()
	var service: Dictionary = ui.read_service_approaches(warehouse, true)
	var approach: Dictionary = {}
	for row: Dictionary in service.get("approaches", []):
		if row.get("stock_ref") == source_id and row.get("available", false): approach = row; break
	var button: Button = keyed("factory:service:" + warehouse + ":" + str(approach.get("id", "")))
	check("actual warehouse offers formal public service walk button", button != null and not button.disabled, service)
	if button == null or button.disabled: finish(); return
	var location: Dictionary = G.location(runtime.actor("player"))
	button.pressed.emit(); await flush()
	check("service button starts original walk without teleport", G.location(runtime.actor("player")) == location and runtime.actor("player").get("intent") != null and ui.pages.is_empty())
	check("real body completes public warehouse service route", progress() and runtime._services.production.reach("player", source_id, runtime.stock(source_id), "search") == null)
	ui.open_panel("container", source_id); await flush()
	check("ordinary complete module inventory never offers cabinet move", keyed("factory:movable:move:" + source_id) == null)
	var timber: Button = find_slot(source_id, "item", "timber")
	check("real produced timber is available in actual inventory Control", timber != null)
	if timber == null: finish(); return
	timber.split.call(timber.slot); await flush()
	var amount: SpinBox = ui._split_layer.find_children("*", "SpinBox", true, false)[0]
	amount.value = 1.0
	var split_confirm: Button = keyed("split:confirm", ui)
	check("native split overlay exposes confirm control", split_confirm != null)
	if split_confirm == null: finish(); return
	split_confirm.pressed.emit(); await flush()
	var transfer: Button = keyed("factory:inventory:transfer")
	check("formal split chooses one existing board with no inventory deduction yet", ui.carry.get("amount") == 1.0 and runtime.stock(source_id).items.timber == 8.0 and transfer != null)
	if transfer == null: finish(); return
	transfer.pressed.emit(); await flush()
	check("formal take pays one real produced board source and supplies cabinet cost", runtime.actor("player").pack.timber == 3.0 and runtime.stock(source_id).items.timber == 7.0 and ui.carry.is_empty())
	# B cabinet-normal-v3 measured this actual external C4 support/use-point pair.
	check("original body really walks to measured woodwork yard feet", await walk_to({"x":10.0,"y":0.5,"z":3.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}))
	var original_pack: Dictionary = runtime.actor("player").pack.duplicate(true)
	var hand: Dictionary = router.state()
	ui.factory_view.catalog_category = "movable"; ui.open_panel("build"); await flush()
	keyed("factory:movable:place:cabinet").pressed.emit(); await flush()
	aim(Vector3(10, 0.5, 4))
	cabinet_id = str(direct._preview.get("instance", {}).get("id", ""))
	check("formal catalogue and real ghost agree on legal original cabinet placement", not cabinet_id.is_empty() and runtime.snapshot().target.get("enabled", false) and direct._preview.get("kind") == "place", runtime.snapshot().target)
	if cabinet_id.is_empty() or not runtime.snapshot().target.get("enabled", false): finish(); return
	var clock: float = runtime.clock()
	fix_position()
	confirm_position()
	check("Enter starts original timed paid construction", runtime.actor("player").get("intent") != null)
	check("eight real seconds create actual cabinet and original stock", progress() and is_equal_approx(runtime.clock() - clock, 8.0) and not runtime._services.buildings.instance(cabinet_id).is_empty() and runtime.stock(cabinet_id).get("structureId") == cabinet_id)
	var paid: Dictionary = original_pack.duplicate(true); paid.timber -= 3.0; paid.scrap -= 1.0
	check("only actual construction pays original materials and preserves hotbar", Data.json_equal(paid, runtime.actor("player").pack) and router.state().slots == hand.slots and router.state().selected == hand.selected)
	await open_cabinet()
	check("actual pointed E opens same cabinet inventory with contextual move", not ui.pages.is_empty() and ui.pages.back().subject == cabinet_id and keyed("factory:movable:move:" + cabinet_id) != null)
	var axe := "r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
	var hammer := "r34:generated:RH-HOME:woodwork:tool:hammer"
	check("formal Shift transfer stores own scrap book and unique axe", await quick_transfer("pack:player", "item", "scrap") and await quick_transfer("pack:player", "item", "book_woodwork") and await quick_transfer("pack:player", "tool", axe) and runtime.tool(axe).holderId == cabinet_id and runtime.stock(cabinet_id).items.get("scrap") == 1.0)
	check("own hammer can be stored through same real UI", await quick_transfer("pack:player", "tool", hammer) and runtime.tool(hammer).holderId == cabinet_id)
	var move_button: Button = keyed("factory:movable:move:" + cabinet_id)
	check("missing carried hammer disables actual move button with visible reason", move_button != null and move_button.disabled and not move_button.tooltip_text.is_empty() and text_in(ui._body).contains(move_button.tooltip_text), move_button.tooltip_text if move_button != null else "missing")
	check("taking original hammer restores move capability", await quick_transfer(cabinet_id, "tool", hammer) and runtime.tool(hammer).holderId == "pack:player" and not keyed("factory:movable:move:" + cabinet_id).disabled)
	var before: Dictionary = runtime.capture_checkpoint()
	var stale: Dictionary = Movable.begin_move(ui, cabinet_id, "stale:other-structure")
	check("stale contextual identity fails without retargeting or closing UI", not stale.get("ok", false) and not ui.pages.is_empty() and Data.json_equal(before, runtime.capture_checkpoint()))
	check("unknown stock public facade cannot expose or start another structure", not Movable.read_container(ui, "not:a:public:stock").get("available", false))
	keyed("factory:movable:move:" + cabinet_id).pressed.emit(); await flush()
	check("context button binds original actual structure and releases modal", router.state().mode == "move" and router.state().structure_target_id == cabinet_id and direct._moving_target == cabinet_id and ui.pages.is_empty() and Data.json_equal(before, runtime.capture_checkpoint()))
	aim(Vector3(8, 0.5, 8))
	before = runtime.capture_checkpoint()
	fix_position()
	confirm_position()
	await flush()
	check("blocked or distant destination fails visibly and preserves loaded original", Data.json_equal(before, runtime.capture_checkpoint()) and not ui._notice.text.is_empty(), ui._notice.text)
	router.retract_placement()
	aim(Vector3(11, 0.5, 4))
	check("same original cabinet previews legal nearby destination", runtime.snapshot().target.get("enabled", false) and direct._preview.destination.id == cabinet_id, runtime.snapshot().target)
	var original: Dictionary = runtime._services.buildings.instance(cabinet_id)
	var stock: Dictionary = runtime.stock(cabinet_id)
	var after_deposit: Dictionary = runtime.actor("player").pack.duplicate(true)
	fix_position()
	var destination: Dictionary = direct._preview.destination.position.duplicate(true)
	aim(Vector3(8, 0.5, 8))
	check("fixed move keeps the original destination and cabinet after pointer motion", direct._placement_locked() and direct._preview.destination.position == destination and direct._preview.destination.id == cabinet_id)
	confirm_position()
	for step in 10: runtime.tick(0.1)
	router.cancel(); await flush()
	check("cancelled partial labor keeps original cabinet and all stored identities", runtime.actor("player").get("intent") == null and Data.json_equal(original, runtime._services.buildings.instance(cabinet_id)) and Data.json_equal(stock, runtime.stock(cabinet_id)) and Data.json_equal(after_deposit, runtime.actor("player").pack))
	await open_cabinet(); keyed("factory:movable:move:" + cabinet_id).pressed.emit(); await flush()
	aim(Vector3(11, 0.5, 4))
	fix_position()
	confirm_position()
	for step in 20: runtime.tick(0.1)
	ui.close_panels()
	check("actual file cold restore keeps pending loaded move", await cold_restore("ui-actual-mv01-moving") and runtime.actor("player").get("intent") != null)
	check("remaining original move labor completes after cold restore", progress())
	var moved: Dictionary = runtime._services.buildings.instance(cabinet_id)
	check("move preserves same one cabinet owner inventory and original references", moved.id == original.id and int(moved.version) == int(original.version) + 1 and float(moved.position.x) == 11.0 and runtime.stock(cabinet_id).structureId == cabinet_id and runtime.stock(cabinet_id).items == stock.items and runtime.stock(cabinet_id).owner == stock.owner and runtime.tool(axe).holderId == cabinet_id and Data.json_equal(after_deposit, runtime.actor("player").pack))
	check("real body walks to moved cabinet use point", await walk_to(runtime._services.buildings.use_points(cabinet_id)[0]))
	await open_cabinet()
	check("same formal grid returns original stored goods book and axe", await quick_transfer(cabinet_id, "item", "scrap") and await quick_transfer(cabinet_id, "item", "book_woodwork") and await quick_transfer(cabinet_id, "tool", axe) and runtime.tool(axe).holderId == "pack:player" and runtime.actor("player").pack.get("scrap") == 1.0 and runtime.actor("player").pack.get("book_woodwork") == 1.0)
	ui.close_panels(); await flush()
	check("final file cold restore preserves exact decoded authority and cabinet", await cold_restore("ui-actual-mv01-completed") and Data.json_equal(moved, runtime._services.buildings.instance(cabinet_id)) and runtime.tool(axe).holderId == "pack:player")
	await open_cabinet()
	check("restored actual cabinet retains contextual move control", keyed("factory:movable:move:" + cabinet_id) != null)
	check("original source save remains byte identical", FileAccess.get_sha256(input_path) == input_sha)
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"input_sha256":input_sha,"cabinet_id":cabinet_id,"scope":"normal53 real source, original paid materials and labor, formal native UI Control signals and explicit pointer rays; actual file cold restores; no source-world grants/teleport/second inventory; not OS/renderer/PCK/VA/FPS qualification"}, "\t", true, true)); file.close()
	detach_pointer()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
