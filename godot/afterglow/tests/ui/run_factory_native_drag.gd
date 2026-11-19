extends "res://tests/ui/run_native_drag.gd"
## Native Viewport GUI-event continuation of an unchanged normal-economy save.
## No synthetic bodies/stocks and no direct drag/drop/force_drag calls.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
class TestNative extends Native:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
var host:Node3D

func _initialize()->void:
	create_timer(50).timeout.connect(func():check("native actual-save workflow finishes before watchdog",false);finish(2))
	call_deferred("run")

func click(at:Vector2,index:MouseButton=MOUSE_BUTTON_LEFT,shift:bool=false)->void:
	await motion(at)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=mouse;event.global_position=mouse
		event.button_index=index;event.pressed=down;event.shift_pressed=shift
		event.button_mask=(MOUSE_BUTTON_MASK_LEFT if index==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
		root.push_input(event,true);await idle()

func keyed(key:String)->Control:
	for node in ui.find_children("*","Control",true,false):
		if node.get_meta("ui_focus_key","")==key:return node
	return null

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	if args.size()<2:check("exact normal-economy input supplied",false);return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("untouched normal save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	host=TestNative.new();root.add_child(host)
	var made:Dictionary=host._assemble(decoded.capture)
	check("same Native runtime configures all real owners",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish(1)
	runtime=made.runtime;world=made.world
	router=Router.new();host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router);await idle()
	var subject:="r34:generated:RH-HOME:home:stock:supplies"
	ui.open_panel("container",subject);await idle()
	var before:Dictionary=runtime.capture_checkpoint()
	var source:=cell("inventory",subject,-1,"item:water")
	check("real household paired inventory publishes actual water",source!=null and source.slot.quantity==runtime.stock(subject).items.water)
	if source==null:return finish(1)
	var amount:float=source.slot.quantity;var pack_water:float=runtime.actor("player").pack.get("water",0)
	check("real household native drag begins through engine callbacks",await start(source))
	var destination:=cell("inventory","pack:player",-1,"item:water")
	check("real paired-grid destination is visible",destination!=null and root.get_visible_rect().encloses(destination.get_global_rect()))
	if destination==null:return finish(1)
	await motion(destination.get_global_rect().get_center());await button(false)
	check("native release transfers original finite water exactly once",runtime.stock(subject).items.water==0 and runtime.actor("player").pack.water==pack_water+amount and ui.drag.is_empty() and ui.carry.is_empty())
	var after_water:Dictionary=runtime.capture_checkpoint()
	check("household transfer changes neither time nor people identity",after_water.facts.time==before.facts.time and after_water.facts.actors.size()==before.facts.actors.size())
	var food:=cell("inventory",subject,-1,"item:food")
	check("real Shift-click food source exists",food!=null)
	if food!=null:
		var food_amount:float=food.slot.quantity;var pack_food:float=runtime.actor("player").pack.get("food",0)
		await click(food.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
		check("native Shift-click transfers only real unreserved quantity",runtime.stock(subject).items.food==0 and runtime.actor("player").pack.food==pack_food+food_amount and ui.drag.is_empty() and ui.carry.is_empty())
	var paid:Dictionary=runtime.capture_checkpoint()
	var water:=cell("inventory","pack:player",-1,"item:water")
	if water==null:check("water is still shown in authoritative pack",false);return finish(1)
	await click(water.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT)
	check("native right-click opens split without spending inventory",is_instance_valid(ui._split_layer) and Data.json_equal(paid,runtime.capture_checkpoint()))
	var split:=keyed("split:confirm") as Button
	check("split confirmation is reachable with native pointer",split!=null and root.get_visible_rect().encloses(split.get_global_rect()),str(split.get_global_rect()) if split!=null else "missing")
	if split!=null:
		stamp("before_split_confirm",{"rect":str(split.get_global_rect()),"layer":str(ui._split_layer.get_global_rect())})
		await click(split.get_global_rect().get_center())
		stamp("after_split_confirm")
		check("native split picks an exact subset of original water",not ui.carry.is_empty() and ui.carry.reference.item_id=="water" and ui.carry.amount>0 and ui.carry.amount<pack_water+amount,{"carry":ui.carry.duplicate(true),"notice":ui._notice.text})
		await key(KEY_ESCAPE)
		check("Esc returns split to original holder and retains container page",ui.carry.is_empty() and ui.drag.is_empty() and not ui.pages.is_empty() and Data.json_equal(paid,runtime.capture_checkpoint()))
	check("outside-release starts from actual current pack",await start(cell("inventory","pack:player",-1,"item:water")))
	await motion(Vector2(5,5));await button(false)
	check("outside native release returns original goods without loss",not root.gui_is_dragging() and ui.drag.is_empty() and ui.carry.is_empty() and Data.json_equal(paid,runtime.capture_checkpoint()))
	check("native Tab-close starts with real held item",await start(cell("inventory","pack:player",-1,"item:water")))
	await key(KEY_TAB);await button(false)
	check("native close cancels drag releases only modal and keeps goods",not root.gui_is_dragging() and ui.pages.is_empty() and ui.drag.is_empty() and ui.carry.is_empty() and not router.state().pause_reasons.modal and Data.json_equal(paid,runtime.capture_checkpoint()))
	ui.open_panel("container",subject);await idle()
	check("native focus-loss case starts from real goods",await start(cell("inventory","pack:player",-1,"item:water")))
	ui._on_focus_exited();await button(false)
	check("focus-loss callback returns actual drag without transfer",not root.gui_is_dragging() and ui.drag.is_empty() and ui.carry.is_empty() and Data.json_equal(paid,runtime.capture_checkpoint()))
	ui.close_panels();await idle()
	root.size=Vector2i(1000,700);root.content_scale_size=root.size;ui.text_scale=1.5
	ui._panel_signature=0;ui._hotbar_signature=0
	ui.open_panel("inventory");await idle()
	source=cell("inventory","pack:player",-1,"item:water")
	check("small 150-percent single inventory source remains visible",source!=null and root.get_visible_rect().encloses(source.get_global_rect()))
	check("small 150-percent native drag begins",await start(source))
	destination=cell("hotbar","pack:player",6)
	check("small 150-percent actual hotbar target is within logical viewport",destination!=null and root.get_visible_rect().encloses(destination.get_global_rect()))
	if destination!=null:await motion(destination.get_global_rect().get_center());await button(false)
	check("small native binding stores same item reference with no cloned item",P.reference_key(router.state().slots[6])=="item:water" and Data.json_equal(paid,runtime.capture_checkpoint()))
	source=cell("inventory","pack:player",-1,"item:water")
	if source!=null:
		await click(source.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT)
		split=keyed("split:confirm") as Button
		check("small 150-percent split confirmation remains fully visible",split!=null and root.get_visible_rect().encloses(split.get_global_rect()),str(split.get_global_rect()) if split!=null else "missing")
		await key(KEY_W);await key(KEY_E)
		check("split text focus consumes movement and interaction without world change",Data.json_equal(paid,runtime.capture_checkpoint()) and not ui.pages.is_empty())
		root.size=Vector2i(1280,800);root.content_scale_size=root.size;await idle()
		check("resizing an open split keeps its actual panel centered",is_instance_valid(ui._split_layer) and root.get_visible_rect().encloses(ui._split_layer.get_global_rect()) and ui._split_layer.get_global_rect().get_center().distance_to(root.get_visible_rect().get_center())<1.0)
		await key(KEY_ESCAPE)
		check("resized split cancels without losing original allocation",not is_instance_valid(ui._split_layer) and ui.carry.is_empty() and Data.json_equal(paid,runtime.capture_checkpoint()))
	check("normal sealed input remains byte-identical",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row):return row.ok) else 1)

func finish(code:int)->void:
	var failed:int=checks.filter(func(row):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"method":"Real unchanged normal-economy save with Native owners and Viewport.push_input/native GUI callbacks; focus-loss callback explicitly simulated","scope":"Current source headless native GUI-event support only, not physical OS/Retina/VA/PCK/WF/G5"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
