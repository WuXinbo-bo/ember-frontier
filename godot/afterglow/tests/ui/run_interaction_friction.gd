extends SceneTree
## Actual UI/router/A/B/C work, with explicit test pointer targets and inventory.
## No formal application, 3D scene, user storage or OS-input qualification.
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Buildings = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Interaction = preload("res://scripts/input/direct_interaction.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const Modes = preload("res://scripts/ui/ui_work_modes.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")
class Router extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	# Keep the explicit fixture point when a native click includes screen coordinates.
	func _refresh_at(_mouse: Vector2) -> void: pass
	func _process(_delta: float) -> void: pass
var world := World.new()
var runtime := Runtime.new()
var buildings := Buildings.new()
var production := Production.new()
var services: Dictionary
var definitions: Dictionary
var router: Router
var pointer: Pointer
var ui: Control
var host: Node3D
var checks: Array = []
var opens: Array = []
var output := ""
var station := "ui-friction:bench"

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("interaction friction timeout"); finish(2))
	call_deferred("run")
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok: push_error(name + " " + str(detail))
func flush() -> void:
	await process_frame
	await process_frame
func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		root.push_input(event, true)
	await flush()
func left(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
	event.position = Vector2(1000, 500); event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event, true)
	await flush()
func by_key(node: Node, id: String) -> Control:
	if node is Control and node.get_meta("ui_focus_key", "") == id: return node
	for child in node.get_children():
		var found := by_key(child, id)
		if found != null: return found
	return null
func texts(node: Node) -> Array:
	var result: Array = [node.text] if node is Label else []
	for child in node.get_children(): result.append_array(texts(child))
	return result
func craft_payload(id: String) -> Dictionary:
	var pack := P.player_stock(ui.snapshot)
	return {"recipe_id":id,"source_id":str(pack.id),"output_id":str(pack.id),"tool_ids":Panels._tool_ids(pack,ui.snapshot)}
func craft_button(id: String) -> Button:
	return by_key(ui, "craft:" + station + ":" + str(craft_payload(id).hash())) as Button
func extension(value: Dictionary) -> bool:
	var edit := world.prepare_changes([buildings.extension_change(Production.KEY,value)],world.get_revision())
	return edit.get("ok",false) and world.commit_prepared(edit.capability).get("ok",false)
func configure_facts(facts: Dictionary) -> void:
	check("explicit isolated fixture configures through actual runtime",runtime.configure({"world":world,"services":services,"definitions":definitions,"facts":facts}).get("ok",false))
	ui.refresh()

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	check("actual rural world loads",world.load_snapshot(Generator.generate(713)).get("ok",false))
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	services = {"buildings":buildings,"production":production,"actions":Actions.new(),"terrain":Terrain.new()}
	var actor := {"id":"player","name":"isolated interaction fixture","x":23.0,"y":0.0,"z":44.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"stamina":100.0,"pack":{"log":2,"timber":8,"scrap":6,"tool_handle":2},"skills":{"crafting":2},"relationship":{"consent":true},"intent":null}
	var facts := {"time":0.0,"status":"playing","actors":[actor],"stocks":[],"actions":[],"quests":[]}
	check("same A B C configure",runtime.configure({"world":world,"services":services,"definitions":definitions,"facts":facts}).get("ok",false))
	var edit := buildings.prepare_edit([],[buildings.make_instance("workbench",station,{"x":21,"y":0,"z":44,"regionId":"RH-HOME","buildingId":null,"storeyId":null})])
	check("real B bench fixture validates",edit.get("ok",false),edit.get("reason"))
	if not edit.get("ok",false): finish(1); return
	var draft := world.prepare_changes(edit.world_changes,world.get_revision())
	check("actual C commits bench",draft.get("ok",false) and world.commit_prepared(draft.capability).get("ok",false))
	actor.merge(buildings.use_points(station)[0],true)
	var state := Production.empty_state()
	state.tools = [{"id":"ui-friction:saw","kind":"hand_saw","holderId":"pack:player","durability":90.0},{"id":"ui-friction:hammer","kind":"hammer","holderId":"pack:player","durability":90.0},{"id":"ui-friction:shovel","kind":"shovel","holderId":"pack:player","durability":90.0}]
	state.knowledge = {"player":["basic_woodwork","basic_tool_repair"]}
	check("actual C commits explicit tools and knowledge",extension(state))
	check("actual runtime uses real bench use point",runtime.configure({"world":world,"services":services,"definitions":definitions,"facts":facts}).get("ok",false))
	host = Node3D.new(); root.add_child(host)
	router = Router.new(); host.add_child(router); router.configure(runtime)
	router.open_requested.connect(func(page: String): opens.append(page))
	ui = Mount.mount(host,runtime,router)
	var camera := Camera3D.new(); host.add_child(camera)
	var surface := Node3D.new(); host.add_child(surface)
	pointer = Pointer.new(); host.add_child(pointer)
	pointer.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":buildings,"terrain":surface,"ui":ui})
	await flush()
	await menu_cases()
	await craft_cases()
	await terrain_cases()
	host.queue_free(); await flush()
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func menu_cases() -> void:
	await key(KEY_B)
	check("native B explicitly opens build route once",ui.pages.size()==1 and ui.pages.back().page=="build" and opens==["build"],opens.duplicate())
	var advanced := by_key(ui,"terrain:settings")
	check("advanced brush is optional and ordinary dig is direct",advanced is Button and advanced.text.contains("可选") and Modes.mode_hint(router.state()).contains("按住左键挖掘"))
	await key(KEY_B)
	check("B closes construction menu without opening parameters",ui.pages.is_empty() and not router.is_paused() and opens==["build"])
	ui.open_panel("inventory")
	check("backpack no longer repeats construction or brush menu",by_key(ui,"terrain:settings")==null and by_key(ui,"mode:terrain_dig")==null and by_key(ui,"mode:repair")==null)
	ui.open_panel("build")
	var dig := by_key(ui,"mode:terrain_dig") as Button
	dig.grab_focus()
	ui._render_panel() # Schedule a focus restore, then close before it executes.
	ui.select_work_mode("terrain_dig")
	await flush()
	check("mode selection closes all menus and stale focus cannot recapture scene",ui.pages.is_empty() and not router.is_paused() and root.gui_get_focus_owner()==null)
	ui.open_panel("build"); by_key(ui,"terrain:settings").pressed.emit()
	check("brush parameters open only on explicit advanced button",ui.pages.back().page=="terrain")
	ui.apply_terrain_brush("dig",6,0.0,1)
	await flush()
	check("optional apply returns to scene and names actual gravel",ui.pages.is_empty() and router.state().terrain.material==6 and Modes.brush_text(router.state()).contains("碎石") and Data.MATERIALS[6].item=="gravel_m3")
	router.set_mode("tool")
	pointer._target = {"id":station,"kind":"structure","primary":"workbench","enabled":true}
	await key(KEY_E)
	check("actual E interaction opens only true workbench route",ui.pages.size()==1 and ui.pages.back().page=="workbench" and ui.pages.back().subject==station)
	var before := runtime.capture_checkpoint()
	await key(KEY_E)
	check("E toggles workbench closed without implicit craft",ui.pages.is_empty() and not router.is_paused() and Data.json_equal(before,runtime.capture_checkpoint()))

func craft_cases() -> void:
	ui.open_panel("build"); await flush()
	ui._scroll.scroll_vertical = 900
	pointer._target = {"id":station,"kind":"structure","primary":"workbench","enabled":true}
	ui.close_panels(); await key(KEY_E)
	check("fresh explicit workbench does not inherit long catalog scroll",ui._scroll.scroll_vertical==0)
	var make := craft_button("make_handle")
	check("real recipe has one enabled action with readable requirements",make!=null and not make.disabled and " / ".join(texts(ui._body)).contains("知识 基础木工") and " / ".join(texts(ui._body)).contains("工具能力 锯切"))
	var old_count: float = runtime.actor("player").pack.tool_handle
	make.pressed.emit()
	check("one click submits actual single batch and returns to world",ui.pages.is_empty() and not router.is_paused() and production.state().orders.size()==1 and runtime.actor("player").pack.tool_handle==old_count)
	check("recent preference stores accepted recipe identity only",ui._recent_crafts.get(station,{}).get("recipe_id")=="make_handle")
	var duplicate: Dictionary = ui.execute("craft",station,craft_payload("make_handle"),true)
	check("immediate repeat is rejected with no fake queue or second order",not duplicate.get("ok",false) and production.state().orders.size()==1 and ui.pages.is_empty())
	for index in 100: runtime.tick(0.1)
	await flush()
	check("actual labor completes once without reopening recipe/menu",runtime.actor("player").pack.tool_handle==old_count+1 and production.state().orders[0].status=="completed" and ui.pages.is_empty(),production.state().orders)
	await key(KEY_E)
	var headings := texts(ui._body).filter(func(t: String): return t.begins_with("上次使用"))
	make = craft_button("make_handle")
	var saw := craft_button("saw_timber")
	check("last recipe is top and immediately repeatable with fresh preflight",headings==["上次使用 · 加工替换工具柄"] and make!=null and make.text=="再制作1批" and not make.disabled and make.get_global_rect().position.y<saw.get_global_rect().position.y and ui._scroll.scroll_vertical==0)
	for dimensions in [Vector2i(1280,800),Vector2i(1000,700)]:
		for scale_factor in [1.0,1.5]:
			root.content_scale_size=dimensions;root.size=dimensions;ui.set_text_scale(scale_factor);await flush()
			check("actual logical viewport equals requested size "+str(dimensions)+" scale "+str(scale_factor),root.get_visible_rect().size.is_equal_approx(Vector2(dimensions)) and ui.size.is_equal_approx(Vector2(dimensions)),{"viewport":str(root.get_visible_rect()),"ui_size":str(ui.size)})
			make=craft_button("make_handle")
			check("recent recipe action fits without scrolling "+str(dimensions)+" scale "+str(scale_factor),ui._scroll.get_global_rect().encloses(make.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"button":str(make.get_global_rect()),"viewport":str(ui._scroll.get_global_rect()),"body_minimum":str(ui._body.get_combined_minimum_size())})
	root.content_scale_size=Vector2i(1280,800);root.size=Vector2i(1280,800);ui.set_text_scale(1.0);await flush()
	make=craft_button("make_handle")
	make.pressed.emit()
	for index in 100: runtime.tick(0.1)
	await flush()
	check("repeat is one new actual batch rather than cached output",production.state().orders.size()==2 and runtime.actor("player").pack.tool_handle==old_count+2 and ui.pages.is_empty())
	var facts := runtime.facts(); facts.actors[0].pack.timber=0
	configure_facts(facts); await key(KEY_E)
	make=craft_button("make_handle")
	check("recent recipe still rechecks missing material with Chinese reason",make.disabled and make.tooltip_text.contains("木料") and " / ".join(texts(ui._body)).contains(make.tooltip_text),make.tooltip_text)
	var before := runtime.capture_checkpoint()
	var refused: Dictionary = ui.execute("craft",station,craft_payload("make_handle"),true)
	check("failed material submit preserves facts stays editable and shows reason",not refused.get("ok",false) and Data.json_equal(before,runtime.capture_checkpoint()) and ui.pages.back().page=="workbench" and ui._notice.text.contains("木料"))
	facts=runtime.facts(); facts.actors[0].pack.timber=5
	configure_facts(facts)
	var state := production.state(); state.knowledge.player=[]
	check("explicit isolated missing-knowledge fixture commits",extension(state)); ui.refresh()
	make=craft_button("make_handle")
	check("unknown craft is visibly blocked with named knowledge requirement",make.disabled and make.tooltip_text.contains("尚未学习") and " / ".join(texts(ui._body)).contains("知识 基础木工"),make.tooltip_text)
	state=production.state(); state.knowledge.player=["basic_woodwork","basic_tool_repair"]
	for tool: Dictionary in state.tools:
		if tool.kind=="hand_saw": tool.durability=0.0
	check("explicit isolated unusable-tool fixture commits",extension(state)); ui.refresh()
	make=craft_button("make_handle")
	check("missing usable tool blocks cached recipe with readable capability",make.disabled and make.tooltip_text.contains("工具") and " / ".join(texts(ui._body)).contains("工具能力 锯切"),make.tooltip_text)
	state=production.state()
	for tool: Dictionary in state.tools:
		if tool.kind=="hand_saw": tool.durability=90.0
	check("tool fixture restored through C",extension(state))
	ui.close_panels()

func terrain_cases() -> void:
	var facts := runtime.facts()
	facts.actors[0].merge({"x":26.9,"y":0.0,"z":43.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"intent":null},true)
	configure_facts(facts)
	router.assign_slot(2,{"kind":"tool","id":"ui-friction:shovel"})
	await key(KEY_3)
	check("native hotbar tool selection needs no mode or parameter panel",router.held_reference().id=="ui-friction:shovel" and ui.pages.is_empty())
	router.set_mode("tool")
	var cells: Array = []
	for x in [55,54,56]:
		if world.cell_at(x,-1,86)==6: cells.append({"x":x,"y":-1,"z":86})
	check("two unmodified reachable gravel cells available",cells.size()>=2,cells)
	if cells.size()<2: return
	var before: float = runtime.actor("player").pack.get("gravel_m3",0.0)
	var opens_before := opens.size()
	for index in 2:
		var cell: Dictionary = cells[index]
		var id := "terrain:%s:%s:%s" % [cell.x,cell.y,cell.z]
		pointer._point={"cell":cell,"normal":Vector3.UP}
		pointer._target={"id":id,"kind":"terrain","primary":"terrain","enabled":true}
		pointer._terrain_payload=Interaction.terrain_payload(pointer._point,router.state().terrain,"dig",0.5)
		pointer._terrain_payload.merge({"tool_id":"ui-friction:shovel","held":true,"requires_hold":true},true)
		await left(true)
		for tick in 16: runtime.tick(0.1)
		await left(false)
		check("real scene dig completes with no automatic menu: "+str(index),world.cell_at(cell.x,cell.y,cell.z)==0 and ui.pages.is_empty() and opens.size()==opens_before and not router.is_paused(),{"cell":cell,"notice":ui._notice.text,"intent":runtime.actor("player").intent})
	check("two explicit mouse works preserve real quantity and scene focus",is_equal_approx(float(runtime.actor("player").pack.get("gravel_m3",0)),before+0.25) and root.gui_get_focus_owner()==null and router.state().mode=="tool")
	ui.configure(runtime,router)
	check("world configure clears per-station UI preferences",ui._recent_crafts.is_empty())

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"explicit_router_panel_requests":opens,"fixture":"actual A runtime/router + B bench/production + C terrain; explicit isolated position/tools and pointer targets; native Viewport key/mouse events; no production 3D mount","formal_application_launched":false,"physical_os_pointer":false,"continuous_hold_acceptance":false,"route_acceptance":false,"visual_acceptance":false},"\t",true,true));file.close()
	print("UI friction checks "+str(checks.size())+" exit "+str(code))
	quit(code)
