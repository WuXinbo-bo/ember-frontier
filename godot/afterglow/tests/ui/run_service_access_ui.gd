extends SceneTree
## Current authority + native service-access UI; historical OS save is read-only.
## No renderer, OS pointer, package, visual or performance qualification.
const Client = preload("res://scripts/runtime/native_client.gd")
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Access = preload("res://scripts/ui/factory_service_access.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")
const G = preload("res://scripts/buildings/building_geometry.gd")
const Store = preload("res://scripts/storage/native_store.gd")
class TestClient extends Client:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var output := ""
var checks: Array = []
var observed: Array = []
var host: Node3D
var ui: Control
var runtime: RefCounted
var router: Node
func _initialize() -> void:
	create_timer(50).timeout.connect(func(): check("suite finishes before watchdog", false); finish())
	call_deferred("run")
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label, "ok":ok, "detail":detail})
	if not ok: print("FAIL " + label + " " + str(detail))
func flush() -> void:
	await process_frame; await process_frame; await process_frame
func text_in(node: Node) -> String:
	var value: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): value += text_in(child)
	return value
func button_with(text: String, node: Node = null) -> Button:
	if node == null: node = ui._body
	if node is Button and node.text.contains(text): return node
	for child in node.get_children():
		var found: Button = button_with(text, child)
		if found != null: return found
	return null
func keyed(key: String, node: Node = null) -> Control:
	if node == null: node = ui._body
	if node is Control and node.get_meta("ui_focus_key", "") == key: return node
	for child in node.get_children():
		var found: Control = keyed(key, child)
		if found != null: return found
	return null
func progress() -> bool:
	for index in 1400:
		if runtime.actor("player").get("intent") == null: return true
		runtime.tick(0.1)
	return runtime.actor("player").get("intent") == null
func mount_capture(capture: Dictionary) -> bool:
	if is_instance_valid(ui): ui.get_parent().free()
	if is_instance_valid(router): router.free()
	var made: Dictionary = host._assemble(capture)
	if not made.get("ok", false): check("actual Native assembles authority", false, made.get("reason")); return false
	runtime = made.runtime; router = TestRouter.new(); host.add_child(router); router.configure(runtime)
	ui = Mount.mount(host, runtime, router); await flush()
	return true
func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]
	DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	host = TestClient.new(); root.add_child(host)
	if args.size() > 1:
		var original := FileAccess.get_file_as_string(args[1])
		var decoded: Dictionary = Store.decode(original)
		check("original candidate16 OS QA save decodes read-only", decoded.get("ok", false))
		if decoded.get("ok", false) and await mount_capture(decoded.capture):
			var archived_before: Dictionary = runtime.capture_checkpoint()
			var archived_id := "r34:generated:RH-HOME:woodwork"
			ui.open_panel("module", archived_id); await flush()
			var source: Dictionary = ui.read_service_approaches(archived_id)
			observed.append({"case":"candidate16-real-backside-save", "player":G.location(runtime.actor("player")), "provider":source})
			check("real backside save offers explicit service guidance", source.get("available", false) and not Access.rows(source, F.instance(ui.factory, archived_id)).is_empty() and text_in(ui._body).contains("服务面"))
			check("backside guidance neither searches goods nor changes world", Data.json_equal(archived_before, runtime.capture_checkpoint()) and not F.stock_visible(ui.factory, ui.snapshot, archived_id + ":stock:tools"))
			var archived_tools := F.find(Access.rows(source, F.instance(ui.factory, archived_id)), "tools")
			var archived_button := keyed("factory:service:" + archived_id + ":tools") as Button
			check("exact original backside save has a usable tools-side route", not archived_tools.get("at_service", true) and archived_button != null and not archived_button.disabled)
			if archived_button != null and not archived_button.disabled:
				var archived_stocks: Array = runtime.capture_checkpoint().facts.stocks.duplicate(true)
				archived_button.pressed.emit(); await flush()
				var archived_arrived := progress()
				ui.refresh(); await flush()
				var archived_after: Dictionary = ui.read_service_approaches(archived_id, true)
				check("same OS-save player walks around wall to proven contact", archived_arrived and F.find(Access.rows(archived_after, F.instance(ui.factory, archived_id)), "tools").get("at_service", false))
				check("OS-save approach does not search or disclose goods on arrival", not runtime.stock(archived_id + ":stock:tools").searched and runtime.capture_checkpoint().facts.stocks == archived_stocks)
			check("original QA save bytes remain intact", FileAccess.get_file_as_string(args[1]) == original)
	var profiles: Dictionary = Assembly.generation_profiles()
	var made: Dictionary = Assembly.prepare(Assembly.generate(713, profiles.profiles)) if profiles.get("ok", false) else profiles
	check("current formal normal-world generation prepares", made.get("ok", false), made.get("reason"))
	if not made.get("ok", false) or not await mount_capture(made.capture): return finish()
	var id := "r34:generated:RH-HOME:woodwork"
	ui.open_panel("module", id); await flush()
	var before: Dictionary = runtime.capture_checkpoint()
	var provider: Dictionary = ui.read_service_approaches(id)
	var module := F.instance(ui.factory, id)
	var rows := Access.rows(provider, module)
	check("formal module page reads actual on-demand service provider", provider.get("available", false) and not rows.is_empty(), provider)
	if rows.is_empty(): return finish()
	var stock_id := id + ":stock:tools"
	var options: Array = rows.filter(func(row: Dictionary): return row.stock_ref == stock_id)
	check("tools buffer has an exact owner-published approach", options.size() == 1, options)
	if options.size() != 1: return finish()
	var approach: Dictionary = options[0]
	var command := Access.walk_command(approach)
	observed.append({"case":"formal-normal-source", "module_id":id, "approach":approach})
	check("source offers only walking, never search or project creation", not command.is_empty() and command.kind == "walk" and command.payload == {})
	check("reading and rendering service proof is side-effect free", Data.json_equal(before, runtime.capture_checkpoint()))
	check("unsearched goods remain hidden while guidance is visible", not F.stock_visible(ui.factory, ui.snapshot, stock_id) and text_in(ui._body).contains(str(approach.direction_label)) and button_with("搜索此缓存") == null)
	if command.is_empty(): return finish()
	var request: Dictionary = ui.request("walk", "", {}, command.destination)
	check("UI preserves exact published feet without offset", request.destination == command.destination and ui.request("search", stock_id).destination == {})
	request.destination.x += 99
	check("request owns a detached destination copy", request.destination != command.destination)
	var button := keyed("factory:service:" + id + ":" + str(approach.id)) as Button
	check("formal module page has an enabled actionable approach", button != null and not button.disabled, approach)
	if button == null or button.disabled: return finish()
	var position := G.location(runtime.actor("player"))
	var stocks: Array = runtime.capture_checkpoint().facts.stocks.duplicate(true)
	button.pressed.emit(); await flush()
	var intent: Variant = runtime.actor("player").get("intent")
	check("accepted approach closes page and resumes original clock", ui.pages.is_empty() and not runtime.is_paused() and not router.is_paused())
	check("same Actions walk uses exact provider destination", intent is Dictionary and intent.get("owner") == "actions" and intent.get("kind") == "walk" and intent.get("request", {}).get("destination") == command.destination)
	check("clicking approach never teleports or searches", G.location(runtime.actor("player")) == position and runtime.capture_checkpoint().facts.stocks == stocks)
	var busy_before: Dictionary = runtime.capture_checkpoint()
	var busy: Dictionary = Access.activate(ui, id, str(approach.id), command)
	check("duplicate approach while busy fails visibly without replacing original walk", not busy.get("ok", false) and Data.json_equal(busy_before, runtime.capture_checkpoint()) and ui._notice.text.contains("取消"))
	ui.open_panel("module", id); await flush()
	var cancel: Button = button_with("取消前往此服务面")
	check("reopening the module exposes cancellation of the same walk", cancel != null and not cancel.disabled)
	if cancel == null or cancel.disabled: return finish()
	cancel.pressed.emit(); await flush()
	check("cancel uses real action owner and keeps goods untouched", runtime.actor("player").get("intent") == null and ui.pages.is_empty() and runtime.capture_checkpoint().facts.stocks == stocks)
	ui.open_panel("module", id); await flush()
	button = keyed("factory:service:" + id + ":" + str(approach.id)) as Button
	if button == null or button.disabled: check("retry remains possible after cancellation", false); return finish()
	button.pressed.emit(); await flush()
	var arrived := progress()
	ui.refresh(); await flush()
	provider = ui.read_service_approaches(id, true)
	var current := F.find(Access.rows(provider, F.instance(ui.factory, id)), str(approach.id))
	check("original Actions really walks to proven service contact", arrived and current.get("at_service", false) and G.location(runtime.actor("player")) != position, {"player":G.location(runtime.actor("player")), "approach":current})
	check("arrival alone still does not search or transfer", runtime.capture_checkpoint().facts.stocks == stocks and not runtime.stock(stock_id).searched)
	ui.open_panel("module", id); await flush()
	var search := keyed("search:" + stock_id + ":" + str({}.hash())) as Button
	check("service contact now offers an explicit legal search", search != null and not search.disabled)
	if search == null or search.disabled: return finish()
	search.pressed.emit(); await flush()
	check("search starts real timed action and releases modal pause", runtime.actor("player").get("intent") is Dictionary and runtime.actor("player").intent.kind == "search" and ui.pages.is_empty() and not runtime.is_paused())
	var searched := progress()
	ui.open_panel("module", id); await flush()
	check("only completed actual search exposes original goods", searched and runtime.stock(stock_id).searched and F.stock_visible(ui.factory, ui.snapshot, stock_id) and button_with("查看取放") != null)
	var altered := command.duplicate(true); altered.destination.x += 1
	before = runtime.capture_checkpoint()
	var refused := Access.activate(ui, id, str(approach.id), altered)
	check("stale replaced feet fails visibly without retarget or world writes", not refused.get("ok", false) and Data.json_equal(before, runtime.capture_checkpoint()) and not ui._notice.text.is_empty())
	check("unknown module provides no guidance or private coordinates", not ui.read_service_approaches("not-a-known-module", true).get("available", false))
	check("foreign stock cannot be attached by a synthetic provider row", Access.rows({"module_id":id,"approaches":[{"id":"fake","stock_ref":"other-private-stock"}]}, module).is_empty())
	check("synthetic unavailable provider with empty reason remains blocked", not Access.access_reason({"available":false,"reason":""},{"available":true}).is_empty())
	check("synthetic unavailable approach with empty reason remains blocked", not Access.access_reason({"available":true},{"available":false,"reason":""}).is_empty())
	for invalid: Dictionary in [{"kind":"search","target_id":stock_id,"payload":{},"destination":command.destination},{"kind":"walk","target_id":"","payload":{"auto_search":true},"destination":command.destination},{"kind":"walk","target_id":"","payload":{},"destination":{"regionId":"RH-HOME","x":NAN,"y":0,"z":0}}]:
		check("synthetic malformed guidance never becomes a UI command " + str(invalid.kind), Access.walk_command({"command":invalid}).is_empty())
	finish()
func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"actual current Native authority/public service provider/formal UI actions plus explicit synthetic DTO refusal; original candidate16 QA checkpoint read-only, no OS/renderer/PCK/VA/performance qualification"}, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
