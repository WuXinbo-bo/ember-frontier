extends "res://tests/ui/run_service_access_ui.gd"
## Post17 source-only delta: real C4/1 parcel orientation and service consumer.
## Reuses native mounting helpers, not the parent's prior 35-check run.
var tested_seed := 0

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	host = TestClient.new(); root.add_child(host)
	var profiles: Dictionary = Assembly.generation_profiles()
	check("actual module generation profiles are available", profiles.get("ok", false))
	if not profiles.get("ok", false): return finish()
	for seed: int in [713, 2026]:
		tested_seed = seed
		await check_seed(seed, profiles.profiles)
	finish()

func check_seed(seed: int, profiles: Array) -> void:
	var prefix := "C4 seed " + str(seed) + " "
	var made: Dictionary = Assembly.prepare(Assembly.generate(seed, profiles))
	check(prefix + "formal unmodified new-world entry prepares", made.get("ok", false), made.get("reason"))
	if not made.get("ok", false) or not await mount_capture(made.capture): return
	var lock: Dictionary = runtime.world.extension("generation:factory-r34")
	check(prefix + "authority retains explicit4 story1 road-court lock", lock.get("content_version") == 4 and lock.get("story_clue_version") == 1 and lock.get("parcel_orientation") == "road-court-v1")
	var id := "r34:generated:RH-HOME:woodwork"
	ui.open_panel("module", id); await flush()
	var before: Dictionary = runtime.capture_checkpoint()
	var module := F.instance(ui.factory, id)
	var provider: Dictionary = ui.read_service_approaches(id, true)
	var rows := Access.rows(provider, module)
	var exact: bool = provider.get("available", false) and not rows.is_empty()
	var usable := 0
	for row: Dictionary in rows:
		var button := keyed("factory:service:" + id + ":" + str(row.id)) as Button
		var title := "前往" + str(row.direction_label) + "的" + str(row.label)
		exact = exact and button != null and button.text == title
		if row.get("available", false) and not Access.walk_command(row).is_empty(): usable += 1
	check(prefix + "every shown side label uses current B transformed provider", exact and usable > 0, {"quarter_turn":module.get("quarter_turn"), "rows":rows})
	check(prefix + "direction queries and drawing leave authority unchanged", Data.json_equal(before, runtime.capture_checkpoint()))
	var tools := F.find(rows, "tools")
	var command := Access.walk_command(tools)
	var stock_id := str(tools.get("stock_ref", ""))
	var target := keyed("factory:service:" + id + ":tools") as Button
	check(prefix + "real tools side has actionable UI without stock disclosure", target != null and not target.disabled and not command.is_empty() and not F.stock_visible(ui.factory, ui.snapshot, stock_id))
	observed.append({"seed":seed, "lock":lock, "module_id":id, "quarter_turn":module.get("quarter_turn"), "position":module.get("position"), "spawn":G.location(runtime.actor("player")), "provider":provider})
	if target == null or target.disabled or command.is_empty(): return
	var position := G.location(runtime.actor("player"))
	var stocks: Array = runtime.capture_checkpoint().facts.stocks.duplicate(true)
	target.pressed.emit(); await flush()
	var intent: Variant = runtime.actor("player").get("intent")
	check(prefix + "click uses unchanged published feet in original walk", intent is Dictionary and intent.get("owner") == "actions" and intent.get("kind") == "walk" and intent.get("request", {}).get("destination") == command.destination and G.location(runtime.actor("player")) == position)
	var arrived := progress()
	ui.refresh(); await flush()
	var reached := F.find(Access.rows(ui.read_service_approaches(id, true), F.instance(ui.factory, id)), "tools")
	check(prefix + "actual original route reaches rotated service contact", arrived and reached.get("at_service", false), {"player":G.location(runtime.actor("player")), "approach":reached})
	check(prefix + "rotated arrival neither searches nor claims resources", runtime.capture_checkpoint().facts.stocks == stocks and not runtime.stock(stock_id).searched)
	var encoded: Dictionary = Store.encode(runtime.capture_checkpoint())
	var decoded: Dictionary = Store.decode(encoded.text) if encoded.get("ok", false) else encoded
	check(prefix + "exact reached state traverses existing native codec", decoded.get("ok", false), decoded.get("reason"))
	if not decoded.get("ok", false) or not await mount_capture(decoded.capture): return
	ui.open_panel("module", id); await flush()
	var restored_module := F.instance(ui.factory, id)
	var restored := F.find(Access.rows(ui.read_service_approaches(id, true), restored_module), "tools")
	check(prefix + "new Native authority preserves orientation and explicit search affordance", restored_module.get("quarter_turn") == module.get("quarter_turn") and restored.get("direction_label") == tools.get("direction_label") and restored.get("at_service", false) and not runtime.stock(stock_id).searched)
	var search := keyed("search:" + stock_id + ":" + str({}.hash())) as Button
	check(prefix + "only a separate enabled search button starts searching", search != null and not search.disabled)
	if search == null or search.disabled: return
	search.pressed.emit(); await flush()
	var searching: Variant = runtime.actor("player").get("intent")
	check(prefix + "explicit click enters existing timed search", searching is Dictionary and searching.get("kind") == "search" and ui.pages.is_empty() and not runtime.stock(stock_id).searched)
	var complete := progress()
	ui.open_panel("module", id); await flush()
	check(prefix + "only actual search completion reveals original stock", complete and runtime.stock(stock_id).searched and F.stock_visible(ui.factory, ui.snapshot, stock_id) and button_with("查看取放") != null)

func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"Post17 CURRENT source only, two actual C4/story1 normal generations and B service provider -> native Control -> Actions.walk -> codec reassembly -> explicit timed search. No OS pointer, renderer, packaged PCK, actual save-slot or performance qualification."}, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
