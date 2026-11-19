extends SceneTree
## Focused art/state regression using the real runtime. Not a formal app/OS playtest.
const P = preload("res://scripts/ui/ui_projection.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const World = preload("res://scripts/world/world_state.gd")
const Rural = preload("res://scripts/world/rural_generator.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Buildings = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Gameplay = preload("res://scripts/runtime/rural_gameplay.gd")
class Router extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var checks: Array = []
var coverage: Array = []
var failed := false
var runtime := Runtime.new()
var world := World.new()
var ui: Control
var router: Router
var definitions: Dictionary
var host: Node
var output := ""

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("Icon state check timeout"); quit(2))
	call_deferred("run")

func check(name: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"name":name, "ok":condition, "detail":detail})
	if not condition: failed = true; push_error(name + " " + str(detail))

func controls(node: Node, kind: String) -> Array:
	var result: Array = []
	if node.is_class(kind): result.append(node)
	for child in node.get_children(): result.append_array(controls(child, kind))
	return result

func all_labels(node: Node) -> String:
	return "\n".join(controls(node, "Label").map(func(label: Label): return label.text))

func passive_children(node: Node) -> bool:
	for child in node.get_children():
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE: return false
		if not passive_children(child): return false
	return true

func slot_for(id: String):
	for node in controls(ui._body, "Button"):
		if node.get("slot") is Dictionary and P.reference_key(node.slot.get("reference", {})) == id: return node
	return null

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("real C world loads", world.load_snapshot(Rural.generate(713)).get("ok", false))
	var buildings := Buildings.new()
	var production := Production.new()
	var materials := {"food":3, "water":2, "medicine":1, "log":2, "timber":6, "scrap":4, "cloth":2, "tool_handle":1, "axe_head":1, "brace":1, "book_woodwork":1, "soil_m3":0.125, "stone_m3":0.25}
	var at := {"x":30.0, "y":0.0, "z":43.0, "regionId":"RH-HOME", "buildingId":null, "storeyId":null}
	var actor := at.duplicate(true)
	actor.merge({"id":"player", "name":"explicit isolated icon fixture", "hp":83.0, "hunger":68.0, "thirst":58.0, "stamina":90.0, "fatigue":22.0, "skills":{"crafting":2, "combat":0.5}, "wounds":[{"kind":"test"}], "pack":materials, "relationship":{"member":true,"consent":true}, "activity":"自由行动", "intent":null})
	var companion := actor.duplicate(true)
	companion.merge({"id":"ui-icon:companion", "name":"隔离同伴", "pack":{"scrap":2}, "relationship":{"met":true,"member":true,"consent":true,"home_arrived":true}, "wounds":[]}, true)
	var facts := {"scenario":"rural-home-r33", "time":0.0, "status":"playing", "actors":[actor, companion], "stocks":[{"id":"ui-icon:chest", "location":at.duplicate(true), "owner":"home-residents", "searched":true, "items":{"food":4}}], "actions":[], "quests":[]}
	check("A B C real services configure", runtime.configure({"world":world, "services":{"buildings":buildings, "actions":Actions.new(), "production":production, "gameplay":Gameplay.new()}, "definitions":definitions, "facts":facts}).get("ok", false))
	var state: Dictionary = Production.empty_state()
	for id in definitions.tool_definitions:
		state.tools.append({"id":"ui-icon:axe-name:"+id, "kind":id, "name":"显示名故意包含斧头", "holderId":"pack:player", "durability":37.5})
	var draft: Dictionary = world.prepare_changes([buildings.extension_change(Production.KEY, state)], world.get_revision())
	check("six unique real tool definitions committed through C", draft.get("ok", false) and world.commit_prepared(draft.capability).get("ok", false))
	host = Node.new(); root.add_child(host)
	router = Router.new(); host.add_child(router); router.configure(runtime)
	ui = Mount.mount(host, runtime, router)
	await process_frame; await process_frame
	var before := runtime.capture_checkpoint()
	var snapshot := runtime.snapshot()
	var pack := P.player_stock(snapshot)
	for id in definitions.tool_definitions:
		var item := P.entry(pack, snapshot, {"kind":"tool", "tool_id":"ui-icon:axe-name:"+id})
		var icon := Icons.descriptor(item)
		coverage.append({"domain":"tool", "id":id, "name":definitions.tool_definitions[id].name, "icon":icon})
		check("stable definition survives projection: " + id, item.get("definition_id") == id and item.reference.tool_id == "ui-icon:axe-name:"+id and item.max_durability == 100)
		if id in ["salvaged_axe", "hammer", "shovel"]: check("existing exact tool image loads: " + id, icon.available and Icons.texture(item) != null)
		if id == "shovel": check("misleading name/instance never overrides actual shovel", icon.path.ends_with("/shovel.png"))
		if id == "legacy_tool": check("legacy tool does not inherit axe art from name", icon.path.is_empty() and not icon.available)
	for id in materials:
		var item := P.entry(pack, snapshot, {"kind":"item", "item_id":id})
		coverage.append({"domain":"item", "id":id, "name":item.name, "icon":Icons.descriptor(item)})
	for id in ["knowledge", "manual_woodwork", "manual_tool_repair", "book_woodwork", "book_tool_repair"]:
		var icon := Icons.descriptor({"reference":{"kind":"item", "item_id":id}})
		check("book aliases share real book image: " + id, icon.available and icon.path.ends_with("/knowledge_book.png"))
	var axe_head := Icons.descriptor({"reference":{"kind":"item", "item_id":"axe_head"}, "name":"斧头"})
	check("axe_head is never a whole axe", axe_head.path.ends_with("/axe_head.png") and not axe_head.path.ends_with("/axe.png"))
	for id in ["log", "cloth", "tool_handle", "axe_head", "brace", "hand_saw", "pickaxe", "soil_m3", "stone_m3"]:
		var entry := {"reference":{"kind":"item","item_id":id}} if id not in ["hand_saw","pickaxe"] else {"reference":{"kind":"tool"},"definition_id":id}
		var texture := Icons.texture(entry)
		check("new delivered PNG resolves and loads: " + id, Icons.descriptor(entry).available and texture != null and texture.get_width() == 256 and texture.get_height() == 256)
	var unknown := {"reference":{"kind":"item", "item_id":"unknown_axe"}, "name":"斧头"}
	check("unknown item remains a readable explicit missing image", not Icons.descriptor(unknown).available and Icons.descriptor(unknown).path.is_empty())
	var reused := Button.new()
	Icons.apply_button(reused, {"reference":{"kind":"item", "item_id":"food"}})
	check("known image set on reusable button", reused.icon != null)
	Icons.apply_button(reused, unknown)
	check("unmapped item clears previous image", reused.icon == null)
	reused.free()
	for id in definitions.structure_definitions:
		var ref := {"kind":"recipe", "definition_id":id}
		var item := P.hand_entry(pack, snapshot, ref)
		coverage.append({"domain":"structure", "id":id, "name":item.name, "icon":Icons.descriptor(item)})
		check("constructible has real title without invented stock: " + id, item.name == definitions.structure_definitions[id].name and item.quantity == 0 and P.entry(pack,snapshot,ref).is_empty())
	for recipe: Dictionary in definitions.production_recipes:
		coverage.append({"domain":"production_recipe", "id":recipe.id, "name":recipe.name, "inputs":recipe.inputs, "outputs":recipe.outputs, "create_tool":recipe.get("createTool",{}), "repair_tool":recipe.get("repairTool",{})})
	ui.open_panel("container", "ui-icon:chest")
	await process_frame; await process_frame
	var tool_slot = slot_for("tool:ui-icon:axe-name:shovel")
	check("actual inventory creates native slot", tool_slot != null)
	if tool_slot != null:
		check("overlays never intercept native slot input", passive_children(tool_slot) and tool_slot.mouse_filter == Control.MOUSE_FILTER_STOP and tool_slot.focus_mode == Control.FOCUS_ALL)
		var bars := controls(tool_slot, "ProgressBar")
		check("real maximum and fractional durability visible", bars.size() == 1 and bars[0].value == 37.5 and bars[0].max_value == 100 and all_labels(tool_slot).contains("37.5"))
		tool_slot.grab_focus()
		check("slot retains native keyboard focus", root.gui_get_focus_owner() == tool_slot)
	var reserved_slot = ui._slot({"kind":"inventory", "index":0, "reference":{"kind":"item","item_id":"food"}, "entry":P.entry(pack,snapshot,{"kind":"item","item_id":"food"}), "quantity":3, "available":1})
	host.add_child(reserved_slot); reserved_slot.present("食物")
	check("partial reservation is visible without disabling inspection", reserved_slot.visual_state.reserved == 2 and all_labels(reserved_slot).contains("预留2") and not reserved_slot.disabled)
	reserved_slot.slot.available = 0
	reserved_slot.present("食物")
	check("fully reserved state has an explicit label", all_labels(reserved_slot).contains("已预留") and reserved_slot.tooltip_text.contains("可用 0"))
	reserved_slot.queue_free()
	router.assign_slot(0, {"kind":"recipe","definition_id":"door"}); router.select_slot(0)
	ui.refresh()
	var held = ui._hotbar.get_child(0)
	check("hotbar uses real construction name and non-colour selection", held.visual_state.name == definitions.structure_definitions.door.name and held.visual_state.selected and all_labels(held).contains("[1]") and all_labels(held).contains("构件"))
	router.assign_slot(1, {"kind":"item","item_id":"not-in-pack"})
	ui.refresh()
	var empty = ui._hotbar.get_child(1)
	check("exhausted binding is distinct from an empty slot", empty.visual_state.exhausted and all_labels(empty).contains("已耗尽") and not ui._hotbar.get_child(2).visual_state.exhausted)
	check("exhausted binding keeps its identity instead of repeating status as title", empty.visual_state.name == "not-in-pack")
	var same_id: int = ui._hotbar.get_child(0).get_instance_id()
	ui.refresh()
	check("unchanged snapshot preserves native slot objects", same_id == ui._hotbar.get_child(0).get_instance_id())
	check("HUD reads actual needs and injuries only", ui._need_labels.hunger.label.text == "饥饿 68" and ui._need_labels.wounds.row.visible)
	check("HUD backdrop provides stable contrast without blocking world input", ui._hud_backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE and ui._hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and ui._hud_backdrop.get_theme_stylebox("panel").bg_color.a >= 0.9)
	check("HUD rounds display only while stock precision remains exact", ui._hud_number(60.375) == "60" and P.entry(pack,snapshot,{"kind":"item","item_id":"soil_m3"}).quantity == 0.125)
	check("empty HUD messages do not reserve blank text rows", not ui._scene_hint.visible and not ui._notice.visible)
	var source: Dictionary = ui.layout.cells(P.stock(ui.snapshot,"ui-icon:chest"),ui.snapshot)[0]
	source.merge({"kind":"inventory","stock_id":"ui-icon:chest","reference":source.entry.reference},true)
	var drag: Dictionary = ui._create_drag(source)
	check("drag retains a reference without removing real items", runtime.capture_checkpoint() == before and drag.reference.item_id == "food")
	ui.cancel_transient()
	check("cancel keeps world inventory and clock unchanged", runtime.capture_checkpoint() == before and ui.drag.is_empty())
	drag = ui._create_drag(source)
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":23}, drag)
	await process_frame
	var after: Dictionary = runtime.snapshot()
	check("visual slot changes preserve real take transaction", P.entry(P.player_stock(after),after,{"kind":"item","item_id":"food"}).quantity == 7 and P.entry(P.stock(after,"ui-icon:chest"),after,{"kind":"item","item_id":"food"}).is_empty(), ui._notice.text)
	var completed: Dictionary = runtime.capture_checkpoint()
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":22}, drag)
	check("replayed drop cannot duplicate stock", runtime.capture_checkpoint() == completed)
	ui.open_panel("npc", "ui-icon:companion")
	var handoffs := controls(ui._body,"Button").filter(func(node: Button):return node.get_meta("ui_focus_key", "") == "handoff:ui-icon:companion")
	check("real consenting nearby pack enables handoff entry", handoffs.size() == 1 and P.stock(runtime.snapshot(),"pack:ui-icon:companion").owner == "ui-icon:companion")
	if not handoffs.is_empty(): handoffs[0].pressed.emit()
	check("handoff opens existing inventory route with actual pack id", ui.pages.back().subject == "pack:ui-icon:companion" and ui.pages.back().page == "container")
	var companion_stock := P.stock(ui.snapshot,"pack:ui-icon:companion")
	var offered: Dictionary = ui.layout.cells(companion_stock,ui.snapshot)[0]
	offered.merge({"kind":"inventory","stock_id":companion_stock.id,"reference":offered.entry.reference},true)
	var handoff: Dictionary = ui._create_drag(offered)
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":22},handoff)
	check("handoff changes only the real two actor packs", runtime.actor("player").pack.scrap == 6 and runtime.actor("ui-icon:companion").pack.get("scrap",0) == 0 and runtime.snapshot().tools.size() == 6, ui._notice.text)
	router.assign_slot(4,{"kind":"tool","tool_id":"ui-icon:axe-name:shovel"}); ui.refresh()
	var source_tools: Array = ui.layout.cells(P.player_stock(ui.snapshot),ui.snapshot).filter(func(cell):return cell.entry.get("key") == "tool:ui-icon:axe-name:shovel")
	var offered_tool: Dictionary = source_tools[0].duplicate(true)
	offered_tool.merge({"kind":"inventory","stock_id":"pack:player","reference":offered_tool.entry.reference},true)
	var tool_drag: Dictionary = ui._create_drag(offered_tool)
	ui._drop({"kind":"inventory","stock_id":"pack:ui-icon:companion","index":18},tool_drag)
	ui.refresh()
	var absent_tool = ui._hotbar.get_child(4)
	check("actual handoff transfers the unique shovel without creating or consuming it", runtime.snapshot().tools.filter(func(t):return t.id == "ui-icon:axe-name:shovel" and t.holderId == "pack:ui-icon:companion").size() == 1 and runtime.snapshot().tools.size() == 6,ui._notice.text)
	check("missing unique tool is not falsely described as consumed", absent_tool.visual_state.unavailable and not absent_tool.visual_state.exhausted and all_labels(absent_tool).contains("不在背包"))
	completed = runtime.capture_checkpoint()
	ui.open_panel("build")
	check("build material chips use same resolver", ui._body.find_children("*","HBoxContainer",true,false).any(func(node): return node.has_meta("ui_icon") and node.get_meta("ui_icon").id == "timber"))
	ui.open_panel("workbench", "ui-icon:nonexistent-station")
	check("craft inputs and outputs name the actual metal head and handle", all_labels(ui._body).contains("斧头金属头 × 1") and all_labels(ui._body).contains("产出1批") and all_labels(ui._body).contains("工具柄 × 1"))
	check("missing station never becomes a usable craft action", controls(ui._body,"Button").filter(func(node: Button): return str(node.get_meta("ui_focus_key", "")).begins_with("craft:")).all(func(node: Button):return node.disabled))
	ui.open_panel("quests")
	check("fixed radio reflects real gameplay state without handheld art", all_labels(ui._body).contains("固定通信设备") and all_labels(ui._body).contains("尚未维修") and runtime.snapshot().radio.status == "unrepaired")
	var gameplay_fixture := Gameplay.initial()
	gameplay_fixture.exploration.loot_collected = 3
	gameplay_fixture.exploration.settled = [{"run_id":"explicit-ui-settlement-fixture", "stages":1, "loot_collected":2, "choices":1, "complete":false}]
	draft = world.prepare_changes([buildings.extension_change(Gameplay.KEY,gameplay_fixture)],world.get_revision())
	check("explicit settlement display fixture commits through C", draft.get("ok",false) and world.commit_prepared(draft.capability).get("ok",false))
	ui.refresh()
	check("settlement reads actual projected totals without claiming full completion", all_labels(ui._body).contains("本次实际收集记录 3.0") and all_labels(ui._body).contains("explicit-ui-settlement-fixture") and all_labels(ui._body).contains("尚未完成整段探索目标"))
	completed = runtime.capture_checkpoint()
	ui.open_panel("inventory")
	check("skills display reads actual actor values", all_labels(ui._body).contains("制作 2.0") and all_labels(ui._body).contains("伤势 1 处"))
	ui.open_panel("container", "ui-icon:chest")
	for scale in [1.0,1.5]:
		ui.set_text_scale(scale); ui.refresh()
		await process_frame; await process_frame
		var slots := controls(ui._body,"Button").filter(func(node): return node.get("slot") is Dictionary)
		check("inventory grid width stays inside dialog at text scale " + str(scale), slots.all(func(node): return node.global_position.x >= ui._dialog.global_position.x and node.global_position.x+node.size.x <= ui._dialog.global_position.x+ui._dialog.size.x), ui._dialog.get_global_rect())
		var overflow: Array = []
		for node in slots:
			for label: Label in controls(node,"Label"):
				if not node.get_global_rect().encloses(label.get_global_rect()): overflow.append({"text":label.text,"slot":str(node.get_global_rect()),"label":str(label.get_global_rect())})
		check("native slot contents stay inside slot at text scale " + str(scale), overflow.is_empty(), overflow)
	check("render changes do not add tools or materials", runtime.capture_checkpoint() == completed)
	host.queue_free(); await process_frame
	var result := {"ok":not failed,"checks":checks,"coverage":coverage,"formal_application_launched":false,"route_acceptance":false,"visual_acceptance":false,"fixture":"Explicit isolated materials, six tools, one nearby container; real A runtime/router, B/C and UI. No formal save used."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":not failed,"checks":checks.size(),"failed":checks.filter(func(c):return not c.ok)}))
	quit(1 if failed else 0)
