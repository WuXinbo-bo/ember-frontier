extends SceneTree
## Engine GUI-event regression, not OS pointer/native application acceptance.
## No _create_drag/_drop/force_drag calls: the Viewport invokes native callbacks.
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Buildings = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
class Router extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var runtime := Runtime.new()
var world := World.new()
var ui: Control
var router: Router
var checks: Array = []
var trace: Array = []
var output := ""
var mouse := Vector2.ZERO
var held := false

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("GUI drag check timeout"); finish(2))
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: push_error(label + " " + str(detail))

func stamp(stage: String, detail: Variant = null) -> void:
	var hovered := root.gui_get_hovered_control()
	trace.append({"stage":stage,"ticks_us":Time.get_ticks_usec(),"mouse":str(mouse),"native_drag":root.gui_is_dragging(),"drag":ui.drag.duplicate(true) if is_instance_valid(ui) else {},"carry":ui.carry.duplicate(true) if is_instance_valid(ui) else {},"hovered":str(hovered.get_path()) if is_instance_valid(hovered) else "","detail":detail})

func idle() -> void:
	await process_frame
	await process_frame

func motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position; event.global_position = position
	event.relative = position - mouse; event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	mouse = position
	root.push_input(event, true)
	await idle()

func button(down: bool) -> void:
	held = down
	var event := InputEventMouseButton.new()
	event.position = mouse; event.global_position = mouse
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await idle()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true
	root.push_input(event, true)
	event = InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = false
	root.push_input(event, true)
	await idle()

func slots(parent: Node) -> Array:
	var result: Array = []
	for child in parent.get_children():
		if child is Button and child.get("slot") is Dictionary: result.append(child)
		result.append_array(slots(child))
	return result

func cell(kind: String, stock_id: String, index: int = -1, reference: String = "") -> Button:
	for node in slots(ui):
		if not node.is_visible_in_tree() or node.slot.get("kind") != kind: continue
		if not stock_id.is_empty() and node.slot.get("stock_id") != stock_id: continue
		if index >= 0 and node.slot.get("index") != index: continue
		if not reference.is_empty() and P.reference_key(node.slot.get("reference",{})) != reference: continue
		return node
	return null

func observe(node: Button, label: String) -> void:
	if node == null: return
	var start: Callable = node.create_drag
	var end: Callable = node.receive
	node.create_drag = func(data):
		stamp("native_get_drag_data:" + label)
		return start.call(data)
	node.receive = func(destination, data):
		stamp("native_drop_data:" + label)
		end.call(destination, data)
	node.button_down.connect(func(): stamp("button_down:" + label))
	node.pressed.connect(func(): stamp("pressed:" + label))

func start(source: Button) -> bool:
	if source == null: check("source exists", false); return false
	observe(source,"source")
	var center := source.get_global_rect().get_center()
	await motion(center)
	stamp("before_press",{"source_rect":str(source.get_global_rect()),"source_id":source.get_instance_id()})
	await button(true)
	stamp("after_press",{"source_alive":is_instance_valid(source)})
	await motion(center + Vector2(18,0))
	stamp("after_threshold",{"source_alive":is_instance_valid(source)})
	return root.gui_is_dragging() and not ui.drag.is_empty()

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	check("real rural world loads",world.load_snapshot(Generator.generate(713)).get("ok",false))
	var at := {"x":30.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var actor := at.duplicate(true)
	actor.merge({"id":"player","name":"explicit GUI-event fixture","hp":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"stamina":100.0,"pack":{"food":2,"water":1},"skills":{"crafting":2},"relationship":{"consent":true},"intent":null})
	check("A B C runtime configures",runtime.configure({"world":world,"services":{"buildings":Buildings.new(),"actions":Actions.new(),"production":Production.new()},"facts":{"actors":[actor],"stocks":[{"id":"ui-drag:chest","owner":"home-residents","searched":true,"items":{"food":4},"location":at}],"actions":[],"quests":[],"time":0.0,"status":"playing"}}).get("ok",false))
	router = Router.new();root.add_child(router);router.configure(runtime)
	ui = Mount.mount(root,runtime,router)
	await idle()
	ui.open_panel("inventory")
	await idle()
	var before := runtime.capture_checkpoint()
	var source := cell("inventory","pack:player",-1,"item:food")
	check("native engine starts drag beyond threshold",await start(source))
	var destination := cell("hotbar","pack:player",4)
	check("modal shortcut destination exists",destination != null)
	if destination != null:
		observe(destination,"hotbar5")
		await motion(destination.get_global_rect().get_center())
		stamp("over_hotbar")
		await button(false)
	stamp("after_release")
	check("native release binds the actual food reference",P.reference_key(router.state().slots[4])=="item:food")
	check("drop ends without accidental click carry",ui.drag.is_empty() and ui.carry.is_empty() and not root.gui_is_dragging())
	check("shortcut drag does not mutate world facts",runtime.capture_checkpoint()==before)
	source = cell("inventory","pack:player",-1,"item:food")
	check("native same-pack drag starts",await start(source))
	destination = cell("inventory","pack:player",2)
	if destination != null:
		observe(destination,"same-pack-cell2")
		await motion(destination.get_global_rect().get_center())
		await button(false)
	var visible_cell := cell("inventory","pack:player",2)
	check("same-pack drop refreshes visible destination without world revision",visible_cell != null and P.reference_key(visible_cell.slot.reference)=="item:food",ui.layout.cells(P.player_stock(runtime.snapshot()),runtime.snapshot())[2])
	check("same-pack sort conserves authoritative pack",runtime.capture_checkpoint()==before and ui.drag.is_empty() and ui.carry.is_empty())
	check("visible source is now empty",cell("inventory","pack:player",0).slot.reference.is_empty())
	# The engine, not a direct _drop call, owns outside release and drag end.
	check("outside-release drag starts",await start(cell("inventory","pack:player",-1,"item:food")))
	await motion(Vector2(8,8));await button(false)
	check("outside drop cancels without world loss or stale carry",not root.gui_is_dragging() and ui.drag.is_empty() and ui.carry.is_empty() and runtime.capture_checkpoint()==before)
	check("Esc-cancel drag starts",await start(cell("inventory","pack:player",-1,"item:food")))
	await key(KEY_ESCAPE)
	check("first Esc cancels drag and keeps inventory open",not root.gui_is_dragging() and ui.drag.is_empty() and ui.carry.is_empty() and not ui.pages.is_empty() and router.is_paused())
	await button(false)
	check("Esc then release cannot activate click-carry",ui.carry.is_empty() and runtime.capture_checkpoint()==before)
	check("Tab-close drag starts",await start(cell("inventory","pack:player",-1,"item:food")))
	await key(KEY_TAB);await button(false)
	check("closing during native drag returns item and unpauses modal",not root.gui_is_dragging() and ui.drag.is_empty() and ui.carry.is_empty() and ui.pages.is_empty() and not router.state().pause_reasons.modal and runtime.capture_checkpoint()==before)
	ui.open_panel("container","ui-drag:chest");await idle()
	check("real container native drag starts",await start(cell("inventory","ui-drag:chest",-1,"item:food")))
	destination = cell("inventory","pack:player",3)
	check("actual paired-grid drop target exists",destination != null)
	if destination != null:
		observe(destination,"pack-cell3")
		await motion(destination.get_global_rect().get_center());await button(false)
	check("native container drop commits one real transfer",runtime.actor("player").pack.food==6 and runtime.stock("ui-drag:chest").items.food==0)
	var after_transfer := runtime.capture_checkpoint()
	check("real transfer updates visible destination",cell("inventory","pack:player",3).slot.quantity==4)
	check("second native drag starts after real transfer",await start(cell("inventory","pack:player",3)))
	ui._on_focus_exited();await button(false)
	check("simulated focus-loss callback cancels without loss",not root.gui_is_dragging() and ui.drag.is_empty() and ui.carry.is_empty() and runtime.capture_checkpoint()==after_transfer)
	ui.close_panels();await idle()
	check("closing releases only modal pause",not router.state().pause_reasons.modal and ui.pages.is_empty())
	for dimensions in [Vector2i(1000,700),Vector2i(1280,800)]:
		root.size = dimensions
		ui.text_scale = 1.5
		ui._panel_signature = 0;ui._hotbar_signature = 0
		await idle()
		ui.open_panel("inventory");await idle()
		var facts_before := runtime.capture_checkpoint()
		check("resized 150 percent native drag starts: " + str(dimensions),await start(cell("inventory","pack:player",-1,"item:food")))
		destination = cell("hotbar","pack:player",6)
		check("resized modal shortcut is fully within viewport: " + str(dimensions),destination != null and root.get_visible_rect().encloses(destination.get_global_rect()))
		if destination != null:
			observe(destination,"resized-hotbar7")
			await motion(destination.get_global_rect().get_center());await button(false)
		check("resized native drop succeeds without inventory mutation: " + str(dimensions),P.reference_key(router.state().slots[6])=="item:food" and runtime.capture_checkpoint()==facts_before and ui.carry.is_empty() and ui.drag.is_empty())
		ui.close_panels();await idle()
	finish(0 if checks.all(func(row):return row.ok) else 1)

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"trace":trace,"method":"Viewport.push_input with logical coordinates; native GUI callbacks; no direct drag/drop invocation","formal_application_launched":false,"physical_os_pointer":false,"route_acceptance":false,"visual_acceptance":false},"  "));file.close()
	quit(code)
