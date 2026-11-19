extends "res://tests/ui/run_controls15.gd"
## Actual public stock, native preview slot click and original transfer ledger.
const MODULE18 := "r34:generated:RH-HOME:woodwork"
func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	if args.size() < 2: check("explicit finite checkpoint", false); return finish()
	var source_text := FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary = Store.decode(source_text)
	check("unmodified finite checkpoint decodes", decoded.get("ok", false))
	if not decoded.get("ok", false): return finish()
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	host = ControlsHost.new(); root.add_child(host)
	var made: Dictionary = host._assemble(decoded.capture)
	check("actual Native assembly", made.get("ok", false))
	if not made.get("ok", false): return finish()
	runtime = made.runtime; router = RealRouter.new(); router.controls_path = output + "/controls.json"
	host.add_child(router); router.configure(runtime); ui = Mount.mount(host, runtime, router); await flush()
	ui.open_panel("factory_module", MODULE18); await flush()
	var module := F.instance(ui.factory, MODULE18)
	var initial_stock: Dictionary = F.visible_stock(ui.factory, ui.snapshot, str(module.get("stock_refs", {}).get("tools", "")))
	check("far building stock is never a local draggable source", initial_stock.is_empty() or initial_stock.get("display_only", false) or not initial_stock.get("searched", false))
	var provider: Dictionary = ui.read_service_approaches(MODULE18, true)
	var walk: Dictionary = {}
	for row: Dictionary in Access.rows(provider, module):
		if row.get("at_service", false): break
		if Access.access_reason(provider, row).is_empty(): walk = Access.walk_command(row)
		if not walk.is_empty(): break
	if not walk.is_empty():
		ui.close_panels(); runtime.set_paused(false)
		walk.merge({"command_id":"storage18-walk", "actor_id":"player"}, true)
		var started: Dictionary = runtime.command(walk)
		check("original walk admitted", started.get("ok", false), started)
		check("original walk completes", progress())
	ui.open_panel("factory_module", MODULE18); await flush()
	module = F.instance(ui.factory, MODULE18)
	var stock_id := str(module.get("stock_refs", {}).get("tools", ""))
	await click_key("building:stock-select:" + stock_id)
	check("inline inventory binds exact stock endpoint", ui._inventory_subject() == stock_id)
	if not runtime.stock(stock_id).get("searched", false):
		if not await click_key("search:" + stock_id + ":" + str({}.hash())): return finish()
		check("original explicit search completes", progress() and runtime.stock(stock_id).get("searched", false))
		ui.open_panel("factory_module", MODULE18); await flush()
		await click_key("building:stock-select:" + stock_id)
	var stock: Dictionary = F.visible_stock(ui.factory, ui.snapshot, stock_id)
	check("building contact works beyond old container-center distance", G.point(G.location(runtime.actor("player"))).distance_to(G.point(runtime.stock(stock_id).get("location", {}))) > 3.0)
	check("actual searched stock is locally usable", not stock.is_empty() and stock.get("searched", false) and not stock.get("display_only", false), {"stock":stock,"player":G.location(runtime.actor("player")),"provider":ui.read_service_approaches(MODULE18,true),"snapshot_stocks":ui.snapshot.get("stocks",[])})
	var before_pack: Dictionary = runtime.actor("player").pack.duplicate(true)
	var before_stock: Dictionary = runtime.stock(stock_id)
	var amount := float(before_stock.get("items", {}).get("scrap", 0))
	var key := ""
	for cell: Dictionary in ui.layout.cells(stock, ui.snapshot):
		if cell.get("entry", {}).get("reference", {}).get("item_id") == "scrap": key = stock_id + ":" + str(cell.index) + ":inventory"; break
	check("original finite stock contains visible scrap slot", amount > 0 and not key.is_empty(), {"amount":amount,"key":key,"authority":before_stock})
	if key.is_empty(): return finish()
	await click_key(key)
	check("ordinary slot click offers direct take to backpack", not ui.carry.is_empty() and keyed("building:transfer:" + stock_id) != null)
	await click_key("building:transfer:" + stock_id)
	check("direct preview take clears only UI carry", ui.carry.is_empty())
	check("real transfer credits backpack once", is_equal_approx(float(runtime.actor("player").pack.get("scrap", 0)), float(before_pack.get("scrap", 0)) + amount))
	check("real transfer debits exact selected stock", is_zero_approx(float(runtime.stock(stock_id).get("items", {}).get("scrap", 0))))
	check("preview remains on original building", ui.pages.back().page == "factory_module" and ui.pages.back().subject == MODULE18)
	var checkpoint: Dictionary = runtime.capture_checkpoint()
	ui.factory_view["building-stock:" + MODULE18] = "pack:player"
	check("foreign endpoint cannot become inline inventory subject", ui._inventory_subject().is_empty())
	var refused: Dictionary = ui.take_all_current()
	check("foreign endpoint take all refused without state changes", not refused.get("ok", false) and Data.json_equal(checkpoint, runtime.capture_checkpoint()))
	check("input checkpoint bytes remain unchanged", FileAccess.get_file_as_string(args[1]) == source_text)
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks, "failed":failed, "scope":"Isolated real finite authority; actual walk and Viewport inventory slot/button clicks, exact debit/credit, no material or position injection."}, "\t", true, true)); file.close()
	if runtime != null: runtime.retire()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(), "failed":failed})); quit(1 if failed else 0)
