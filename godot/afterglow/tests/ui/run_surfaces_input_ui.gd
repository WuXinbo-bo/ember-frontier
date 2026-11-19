extends "res://tests/ui/run_os_feedback_ui.gd"
## Affected native layout/input regression after the candidate25 sidebar fix.
## Actual new9 generation/owners, native Viewport events and original router.
class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass

var emitted := {"movement":0,"interact":0,"primary":0,"secondary":0,"zoom":0}
var directions: Array = []

func assemble_capture(capture: Dictionary) -> bool:
	if is_instance_valid(ui): ui.get_parent().free()
	if is_instance_valid(router): router.free()
	var made: Dictionary = host._assemble(capture)
	check("actual Native assembles the one owner set", made.get("ok",false), made.get("reason"))
	if not made.get("ok",false): return false
	runtime = made.runtime; world = made.world
	router = Router.new(); router.controls_path = output+"/isolated-controls.json"; host.add_child(router); router.configure(runtime)
	ui = Mount.mount(host,runtime,router); await idle(); await idle(); return true

func send_key(code: Key, down: bool, meta: bool = false) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.keycode = code
	event.pressed = down; event.meta_pressed = meta; root.push_input(event,true); await idle()

func tap(code: Key, meta: bool = false) -> void:
	await send_key(code,true,meta); await send_key(code,false,meta)

func pointer_event(index: MouseButton, ctrl: bool = false) -> void:
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new(); event.position = Vector2(4,400); event.global_position = event.position
		event.button_index = index; event.pressed = down; event.ctrl_pressed = ctrl; root.push_input(event,true); await idle()

func press(key: String) -> bool:
	var button := keyed(key) as Button
	check("native action reachable "+key, button != null and not button.disabled)
	if button == null or button.disabled: return false
	ui._scroll.ensure_control_visible(button); await idle()
	await click(button.get_global_rect().get_center()); return true

func observe_router() -> void:
	router.movement_requested.connect(func(direction:Vector2,_delta:float): emitted.movement+=1;directions.append(direction))
	router.interact_requested.connect(func():emitted.interact+=1)
	router.primary_requested.connect(func(down:bool):
		if down:emitted.primary+=1)
	router.secondary_requested.connect(func():emitted.secondary+=1)
	router.zoom_requested.connect(func(_amount:float):emitted.zoom+=1)

func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.get("ok",false) else profiles
	check("current formal new-world entry prepares",prepared.get("ok",false))
	if not prepared.get("ok",false) or not await assemble_capture(prepared.capture):return finish(1)
	observe_router()
	var original:Dictionary=runtime.capture_checkpoint()
	var published:Dictionary=runtime.factory_snapshot("player")
	var home:Dictionary={}
	for row:Dictionary in F.rows(published,"modules","instances"):
		if F.definition(published,str(row.definition_id)).get("generation_role")=="home":home=row;break
	check("current opening exposes real quality home and owner choices",not home.is_empty() and F.definition(published, str(home.get("definition_id", ""))).get("generation_role") == "home" and not F.build_definitions(published).is_empty() and F.build_definitions(published).size()==published.modules.get("build_definition_ids",[]).size(),home.get("definition_id"))
	if home.is_empty():return finish(1)
	var id:=str(home.id)
	var hud_bounds: Rect2 = ui._hud_backdrop.get_global_rect()
	var scene_center := Rect2(Vector2(384, 180), Vector2(512, 400))
	check("HUD keeps native shortcuts and avoids the central action area", router.state().slots.size() == 9 and ui._hotbar.visible and not hud_bounds.intersects(scene_center) and not hud_bounds.intersects(ui._hotbar.get_global_rect()), str(hud_bounds))
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5)
		for page:String in ["factory","factory_catalog","factory_module","factory_inventory","factory_production","factory_logistics","factory_people","factory_alerts","factory_handbook","settings","pause"]:
			ui.close_panels();ui.open_panel(page,id if page=="factory_module" else "");await idle();await idle()
			check("actual six-group surface retains title and readable native bounds "+page+str(viewport),not text_in(ui._body).is_empty() and not ui._title.text.is_empty() and root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and root.get_visible_rect().encloses(ui._back_button.get_global_rect()),str(ui._dialog.get_global_rect()))
			var overflow: Array = []
			for action: Button in ui._body.find_children("*","Button",true,false):
				if action.size.x > ui._scroll.size.x: overflow.append({"text":action.text,"size":str(action.size)})
			check("native action rows stay within readable width "+page+str(viewport),overflow.is_empty(),overflow)
			var back_natural:Vector2=ui._back_button.get_theme_font("font").get_string_size(ui._back_button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,ui._back_button.get_theme_font_size("font_size"))
			check("native short return stays one readable row "+page+str(viewport),ui._back_button.size.x>=back_natural.x and ui._back_button.size.y<=44*ui.text_scale,str(ui._back_button.size))
			var live:bool=page=="factory_alerts"
			check("surface owns input and uses sole correct clock policy "+page+str(viewport),router.is_paused() and runtime.is_paused()!=live and router.world_is_paused()!=live)
			var prior:Dictionary=emitted.duplicate();var selected:int=router.state().selected
			await tap(KEY_W);await tap(KEY_9);await pointer_event(MOUSE_BUTTON_LEFT);await pointer_event(MOUSE_BUTTON_RIGHT);await pointer_event(MOUSE_BUTTON_WHEEL_DOWN)
			if page!="factory_module":await tap(KEY_E)
			check("surface consumes world movement tools interaction and hotbar "+page+str(viewport),emitted==prior and router.state().selected==selected and not router.state().held.primary,emitted)
			check("surface input leaves real bodies stock time and owners unchanged "+page+str(viewport),Data.json_equal(original,runtime.capture_checkpoint()))
			await tap(KEY_ESCAPE)
			check("one real Escape closes this surface without passing an action "+page+str(viewport),ui.pages.is_empty() and not router.is_paused() and not runtime.is_paused() and not router.state().held.primary)
	# Object E is intentionally a close key. It must not forward an interaction.
	ui.open_panel("module",id);await idle();var e_before:int=emitted.interact
	await tap(KEY_E)
	check("object E returns to scene without repeating a world interaction",ui.pages.is_empty() and emitted.interact==e_before and Data.json_equal(original,runtime.capture_checkpoint()))
	# Direction observations qualify routing, not real collision or OS movement.
	for spec:Array in [[KEY_W,Vector2.UP],[KEY_A,Vector2.LEFT],[KEY_S,Vector2.DOWN],[KEY_D,Vector2.RIGHT]]:
		directions.clear();await send_key(spec[0],true);router._physics_process(0.1);await send_key(spec[0],false)
		check("physical WASD emits original screen-axis direction "+str(spec[0]),not directions.is_empty() and directions.all(func(value:Vector2):return value==spec[1]),directions)
	var selected:int=router.state().selected;await tap(KEY_9)
	check("scene number key selects the ninth shared reference",router.state().selected==8)
	await pointer_event(MOUSE_BUTTON_WHEEL_DOWN)
	check("scene wheel cycles original nine slots",router.state().selected==0)
	var zoom_before:int=emitted.zoom;await pointer_event(MOUSE_BUTTON_WHEEL_UP,true)
	check("Ctrl wheel routes zoom without changing held item",emitted.zoom==zoom_before+1 and router.state().selected==0)
	router.select_slot(selected);ui.refresh();await idle()
	# Real settings buttons + physical events. TestRouter only suppresses disk
	# preference persistence; original conflict/reserved/reset rules stay intact.
	ui.open_panel("settings");await idle()
	var bindings:Dictionary=router.state().bindings.duplicate(true)
	if await press("bind:inventory"):
		await tap(KEY_W)
		check("conflicting remap stays in capture and explains refusal",ui.capture_action=="inventory" and router.state().bindings==bindings and ui._panel_notice.is_visible_in_tree() and not ui._panel_notice.text.is_empty())
		await tap(KEY_Q,true)
		check("macOS reserved Command Q is refused without rebinding",ui.capture_action=="inventory" and router.state().bindings==bindings and ui._panel_notice.is_visible_in_tree())
		await tap(KEY_Y,true)
		check("permitted physical modifier remap updates original router",ui.capture_action.is_empty() and router.state().bindings.inventory.keycode==int(KEY_Y|KEY_MASK_META))
	if await press("bind:build"):
		await tap(KEY_ESCAPE)
		check("first Escape cancels capture while keeping settings",ui.capture_action.is_empty() and not ui.pages.is_empty() and ui.pages.back().page=="settings")
	if await press("bind:reset"):
		check("real default button restores all original bindings",router.state().bindings==bindings and ui._panel_notice.text.contains("恢复默认"))
	ui.close_panels();ui.open_panel("factory_alerts");await idle()
	var before_time:float=runtime.clock();runtime.tick(0.1)
	check("map advances the one real runtime clock",runtime.clock()>before_time and not runtime.is_paused())
	var map_before:Dictionary=runtime.capture_checkpoint()
	ui.open_panel("factory_confirm");await idle()
	check("nested confirmation pauses same clock",runtime.is_paused())
	await tap(KEY_ESCAPE)
	check("confirmation Escape returns same live map",ui.pages.back().page=="factory_alerts" and not runtime.is_paused())
	router.set_window_focus(false);ui._on_focus_exited();await idle()
	check("focus loss clears held actions and pauses original world",runtime.is_paused() and not router.state().held.primary and ui.capture_action.is_empty() and ui.carry.is_empty() and ui.drag.is_empty())
	router.set_window_focus(true);await idle()
	check("focus return retains live map input barrier",not runtime.is_paused() and router.is_paused() and not router.state().held.primary)
	router.set_file_dialog(true);await idle();check("file barrier overrides live viewing",runtime.is_paused())
	router.set_file_dialog(false);await idle();check("file return restores live map",not runtime.is_paused() and ui.pages.back().page=="factory_alerts")
	ui.close_panels();await idle()
	check("all transient navigation leaves post-tick authority intact",Data.json_equal(map_before,runtime.capture_checkpoint()) and not router.is_paused())
	# Global short-action sizing must retain actual catalog clicks and the
	# shipping cancellation consumer, not only page bounds. Current choices
	# are read from the owner: a later repair definition is not a UI authority.
	var camera:=Camera3D.new();host.add_child(camera)
	var pointer:=Pointer.new();host.add_child(pointer)
	pointer.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":runtime._services.buildings,"terrain":host,"ui":ui})
	ui.open_panel("factory_catalog");await idle();await idle()
	var choices:Array=F.build_definitions(ui.factory)
	check("actual catalog exposes current owner choices",not choices.is_empty())
	if not choices.is_empty():
		var selected_id:=str(choices[0].id)
		if await press("factory:preview:"+selected_id):
			check("readable catalog click selects original placement owner",router.state().mode=="module_place" and router.state().module_definition_id==selected_id)
			await tap(KEY_ESCAPE)
			check("original Escape cancels actual placement without spending or creating",router.state().mode!="module_place" and Data.json_equal(map_before,runtime.capture_checkpoint()))
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int) -> void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"method":"Current-source post25 density regression; actual formal generator/Native owners and eleven surfaces in six groups at100/150%; native Viewport input and original InputRouter conflict/macOS/reset/modal/focus/file rules. TestRouter suppresses preference disk writes only, with isolated controls path; movement is original routing observation, not collision/real OS play.","scope":"Current-source/headless Control support; not complete WF/UI-U/normal economic route/OS/Retina/VA/FPS/G5 acceptance"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
