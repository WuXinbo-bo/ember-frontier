extends SceneTree
## Shipping Native _ready, actual menu clicks, five-tool opening and close.
## Inputs are confined to this process's Viewport, never the user's desktop.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var output:String
var host:Node3D
var checks:Array=[]
var phase_seen:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label)
func screenshot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+name+".png")
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=Native.new();host.store=Store.new(output+"/saves");host.controls_path=output+"/controls.json";root.add_child(host)
	await process_frame;await process_frame
	check("shipping default opens real main menu without creating world",host.runtime==null and host._shell.state=="menu")
	await screenshot("main-menu")
	var selected:Button=host._shell._buttons.get_child(1)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=selected.get_global_rect().get_center();event.global_position=event.position;root.push_input(event,true)
	await process_frame
	check("actual menu button starts a guarded loading operation",host._world_loading and host._shell.state=="busy")
	await screenshot("loading")
	var started:int=Time.get_ticks_msec()
	while not host._ready_game and Time.get_ticks_msec()-started<100000:
		if not phase_seen.has(host._shell.phase):phase_seen.append(host._shell.phase)
		await process_frame
	check("real five-tool opening passes published geometry and physics",host._ready_game,{"phases":phase_seen,"shell":host._shell.state})
	if not host._ready_game:return finish(false)
	host.runtime.set_paused(true)
	var actual:Array=[]
	for tool:Dictionary in host.runtime.ui_page_snapshot("factory_inventory").tools:
		if tool.holderId=="pack:player" and float(tool.durability)>0:actual.append(tool.kind)
	actual.sort()
	var expected:Array=["salvaged_axe","hand_saw","hammer","pickaxe","shovel"];expected.sort()
	check("chosen menu profile supplies all five usable physical tools",actual==expected,actual)
	check("hotbar never points at nonexistent tool",host.router.state().slots.all(func(slot:Dictionary)->bool:return slot.get("kind")!="tool" or not host.runtime.tool(str(slot.get("id",""))).is_empty()))
	check("persistent shell reports readiness then releases input",host._shell.state in ["ready","hidden"] and not host._shell.snapshot().modal and not host.router.state().pause_reasons.get("closing",false))
	await screenshot("playtest-opening")
	for down:bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_I;event.physical_keycode=KEY_I;event.pressed=down;root.push_input(event,true)
	await process_frame;await process_frame
	check("actual I key opens the chosen profile backpack",not host.ui.pages.is_empty() and host.ui.pages.back().page=="factory_inventory")
	await screenshot("playtest-inventory")
	finish(true)
func finish(close_test:bool)->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"phases":phase_seen,"scope":"Shipping menu and async five-tool startup with real Viewport click/key, actual isolated storage and geometry/physics barriers; no OS input or performance qualification"},"\t",true,true))
	print("EXPERIENCE15_MENU "+JSON.stringify({"checks":checks.size(),"failed":failed}))
	if failed or not close_test:
		if is_instance_valid(host):host.free()
		quit(1 if failed else 0)
	else:
		# Explicit test profile's shipping close path exits without saving. The
		# runner verifies process exit; the report was persisted before quit.
		host._close_requested()
