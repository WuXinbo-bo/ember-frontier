extends SceneTree
## Published A definitions + production UI projections/Controls. The authority
## below is a controlled DTO only, not real catalog/stock transaction evidence.
const Content = preload("res://scripts/runtime/content_definitions.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Layout = preload("res://scripts/ui/inventory_layout.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
class Authority extends RefCounted:
	signal changed(value: Dictionary)
	var value: Dictionary = {}
	var commands := 0
	func snapshot() -> Dictionary: return value.duplicate(true)
	func availability(_request: Dictionary) -> Dictionary: return {"ok":true,"code":"OK"}
	func command(_request: Dictionary) -> Dictionary: commands += 1; return {"ok":true,"code":"OK"}
var checks: Array = []
var output := ""
func _initialize() -> void:
	create_timer(10).timeout.connect(func(): finish(2))
	call_deferred("run")
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail}); print(("PASS " if ok else "FAIL ") + name)
func find_key(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("ui_focus_key", "") == key: return node
	for child in node.get_children():
		var found := find_key(child, key)
		if found != null: return found
	return null
func text_in(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): text += text_in(child)
	return text
func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	var definitions := Content.item_definitions()
	for id: String in definitions:
		var definition: Dictionary = definitions[id]
		var count: float = 0.125000123456789 if definition.unit == "m3" else 3.0
		var stock := {"id":"pack:player","owner":"player","searched":true,"items":{id:count}}
		var before := stock.duplicate(true)
		var entry: Dictionary = P.entries(stock, {})[0]
		check("published definition drives actual UI item " + id, entry.name == definition.name and entry.step == definition.step and entry.unit == definition.unit and entry.stackable == definition.stackable and entry.quantity == count and not entry.legacy and stock == before, entry)
	check("m3 unit comes from the published definition", P.item_unit("soil_m3") == " m³" and P.item_unit("water").is_empty())
	var legacy := {"id":"old","searched":true,"items":{"old_unknown_m3":0.123456789123}}
	var old: Dictionary = P.entries(legacy, {})[0]
	check("legacy unknown inventory keeps ID and exact quantity without inventing a unit", old.name == "old_unknown_m3" and old.quantity == 0.123456789123 and old.step == Content.quantity_step("old_unknown_m3", true) and old.legacy and old.unit.is_empty() and P.item_unit("old_unknown_m3").is_empty(), old)
	check("formal bad building reference cannot use legacy compatibility", not P.definition_reason({"id":"bad","cost":{"old_unknown_m3":1}}).is_empty())
	check("formal bad recipe reference cannot use legacy compatibility", not P.definition_reason({"id":"bad","inputs":{"old_unknown_m3":1}}, true).is_empty())
	check("formal invalid count and output reject using A validation", not P.definition_reason({"id":"bad","cost":{"water":0.5}}).is_empty() and not P.definition_reason({"id":"bad","outputs":{"missing":1}}, true).is_empty())
	check("known fractional m3 catalog quantity remains valid without rounding", P.definition_reason({"id":"valid","cost":{"soil_m3":0.000125}}).is_empty())
	var exact := 0.125000123456789
	var stock := {"id":"precision","searched":true,"items":{"soil_m3":exact}}
	var original := stock.duplicate(true)
	var layout := Layout.new()
	check("original precise stock is preserved in first display allocation", layout.cells(stock, {})[0].quantity == exact)
	check("split uses original floats and definition step", layout.move(stock, {}, 0, 1, 0.001).is_empty())
	var cells := layout.cells(stock, {})
	check("split does not round historical fractional remainder", cells[0].quantity == exact - 0.001 and cells[1].quantity == 0.001 and absf(cells[0].quantity + cells[1].quantity - exact) < 1e-15 and stock == original, [cells[0].quantity, cells[1].quantity])
	layout.clear()
	var portion := exact - 0.000000001
	layout.move(stock, {}, 0, 1, portion)
	cells = layout.cells(stock, {})
	check("near-full move retains a real tiny remainder", cells[0].quantity == exact - portion and cells[0].quantity > 0 and cells[1].quantity == portion and stock == original, [cells[0].quantity, cells[1].quantity])
	var authority := Authority.new()
	authority.value = {"revision":1,"command_revision":1,"player":{"id":"player","stock_id":"pack:player"},"stocks":[{"id":"pack:player","owner":"player","searched":true,"items":{"soil_m3":exact}}],"catalog":{"structure_definitions":{"bad":{"id":"bad","name":"坏构件","cost":{"missing":1}}},"production_recipes":[{"id":"bad-recipe","name":"坏配方","inputs":{"missing":1}}]}}
	var host := Node.new(); root.add_child(host)
	var ui: Control = Mount.mount(host, authority, null)
	ui.open_panel("build"); await process_frame
	var bad: Button = find_key(ui, "build:bad")
	check("actual build Control rejects a bad formal definition", bad != null and bad.disabled and bad.tooltip_text.contains("物资定义无效"), bad.tooltip_text if bad != null else "missing button")
	ui.open_panel("workbench", "controlled:station"); await process_frame
	check("actual station shows bad-reference reason without a craft button", text_in(ui._body).contains("物资定义无效") and ui._body.find_children("*", "Button", true, false).is_empty(), text_in(ui._body))
	ui.open_panel("inventory"); await process_frame
	var slots: Array = ui._body.find_children("*", "Button", true, false)
	check("actual inventory tooltip reads the m3 definition", slots.any(func(button: Node): return button.tooltip_text.contains(" m³")))
	check("definition views never submit or mutate authority", authority.commands == 0 and authority.value.stocks[0].items.soil_m3 == exact)
	host.queue_free(); await process_frame
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)
func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"fixture":"real A immutable content definitions + production projection/layout/Control; controlled catalog authority; no formal app or real stock transaction","formal_application_launched":false,"route_acceptance":false}, "  ")); file.close()
	quit(code)
