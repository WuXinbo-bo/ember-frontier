extends SceneTree
## Exact-ID coverage reached through real C terrain -> A clock/pack -> UI.
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Direct = preload("res://scripts/input/direct_interaction.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
class Router extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(25).timeout.connect(func(): finish(2,{}))
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: push_error(label + " " + str(detail))

func all_slots(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button and child.get("slot") is Dictionary: result.append(child)
		result.append_array(all_slots(child))
	return result

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var world := World.new()
	check("actual finite world loads",world.load_snapshot(Generator.generate(713)).get("ok",false))
	check("road and gravel both declare actual gravel inventory ID",Data.MATERIALS[4].item=="gravel_m3" and Data.MATERIALS[6].item=="gravel_m3" and Data.MATERIALS[6].diggable)
	var before_material := world.cell_at(55,-1,86)
	check("unmodified rural generation contains reachable gravel surface",before_material==6,before_material)
	var buildings := Building.new()
	var fixture := Production.empty_state()
	fixture.tools=[{"id":"ui-gravel:shovel","kind":"shovel","holderId":"pack:player","durability":90.0}]
	var runtime := Runtime.new()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	var actor := {"id":"player","name":"explicit isolated gravel audit","x":26.9,"y":0.0,"z":43.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"stamina":100.0,"pack":{},"skills":{"crafting":2},"relationship":{"consent":true},"intent":null}
	check("same A B C services configure",runtime.configure({"world":world,"definitions":catalog,"services":{"buildings":buildings,"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()},"facts":{"actors":[actor],"stocks":[],"quests":[],"actions":[],"time":0.0,"status":"playing"}}).get("ok",false))
	var prepared := world.prepare_changes([buildings.extension_change(Production.KEY,fixture)],world.get_revision())
	check("explicit shovel fixture commits only through C capability",prepared.get("ok",false) and world.commit_prepared(prepared.capability).get("ok",false))
	var router := Router.new();root.add_child(router);router.configure(runtime)
	var brush := {"material":2,"height":0.0,"brush_cells":1}
	var payload := Direct.terrain_payload({"cell":{"x":55,"y":-1,"z":86},"normal":Vector3.UP},brush,"dig",0.5)
	payload.merge({"tool_id":"ui-gravel:shovel","held":true,"requires_hold":true},true)
	var receipt := router.request("terrain","terrain:55:-1:86",payload)
	check("dig accepted through actual input/runtime contract",receipt.get("ok",false),receipt)
	check("no material awarded before real work completes",not runtime.actor("player").pack.has("gravel_m3") and world.cell_at(55,-1,86)==6)
	for i in 16: runtime.tick(0.1)
	check("real work completes cell and exact .125m3 reward",world.cell_at(55,-1,86)==0 and is_equal_approx(float(runtime.actor("player").pack.get("gravel_m3",0)),0.125) and runtime.actor("player").intent==null,runtime.actor("player"))
	check("gravel is not stone/soil/scrap and shovel wear is real",runtime.actor("player").pack.size()==1 and is_equal_approx(float(runtime.tool("ui-gravel:shovel").durability),89.9))
	var ui := Mount.mount(root,runtime,router)
	await process_frame;await process_frame
	ui.open_panel("inventory")
	await process_frame;await process_frame
	var snapshot: Dictionary = runtime.snapshot()
	var entry := P.entry(P.player_stock(snapshot),snapshot,{"kind":"item","item_id":"gravel_m3"})
	check("snapshot projects exact gravel reference/quantity/step",entry.get("reference",{}).get("item_id")=="gravel_m3" and is_equal_approx(float(entry.get("quantity",0)),0.125) and entry.get("step")==0.001,entry)
	check("gravel has its own readable Chinese name",entry.get("name")=="碎石",entry.get("name"))
	var icon := Icons.descriptor(entry)
	check("gravel icon never impersonates stone or scrap",icon.id=="gravel_m3" and icon.path.ends_with("/gravel_m3.png"),icon)
	var visible: Dictionary = {}
	for slot in all_slots(ui._body):
		if P.reference_key(slot.slot.get("reference",{}))=="item:gravel_m3":
			visible={"entry":slot.slot.entry,"quantity":slot.slot.quantity,"visual":slot.visual_state,"tooltip":slot.tooltip_text}
	check("actual inventory creates readable fractional gravel slot",visible.get("entry",{}).get("name")=="碎石" and visible.get("quantity")==0.125,visible)
	check("volume tooltip retains actual cubic-metre precision",str(visible.get("tooltip","")).contains("0.125 m³"),visible.get("tooltip"))
	check("missing art remains explicit native fallback",icon.available or icon.reason=="图标待补")
	finish(0 if checks.all(func(row):return row.ok) else 1,{"cell":{"x":55,"y":-1,"z":86,"before":before_material,"after":world.cell_at(55,-1,86)},"stock":P.player_stock(snapshot),"entry":entry,"icon":icon,"visible_slot":visible})

func finish(code: int, evidence: Dictionary) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"evidence":evidence,"fixture":"one explicit shovel, no initial gravel or terrain edits; original rural generator; actual A/B/C transactions and A clock","formal_application_launched":false,"route_acceptance":false,"visual_acceptance":false},"  "));file.close()
	quit(code)
