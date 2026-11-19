extends SceneTree
## Native input tests for feedback only. The parent owns engine and GPU execution.
const Feedback=preload("res://scripts/ui/ui_feedback19.gd")
const Slot=preload("res://scripts/ui/inventory_slot.gd")
var checks:Array=[]
var actions:Dictionary={"button":0,"slot":0}
var input_trace:Array=[]

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func flush()->void:
	await process_frame;await process_frame;await process_frame
func diagnostics(button:BaseButton)->Dictionary:
	var focused:Control=root.gui_get_focus_owner()
	return {"actions":actions.duplicate(true),"feedback":Feedback.statistics(button),"inside_tree":button.is_inside_tree(),"exiting":button.get_meta(Feedback.META,{}).get("exiting",false),"self_modulate":str(button.self_modulate),"base_modulate":str(button.get_meta(Feedback.META,{}).get("base",Color.WHITE)),"rect":str(button.get_global_rect()),"viewport":str(root.get_visible_rect()),"viewport_size":str(root.size),"content_scale_size":str(root.content_scale_size),"focus":str(focused.get_path()) if is_instance_valid(focused) else "none","disabled":button.disabled,"visible":button.is_visible_in_tree(),"input":input_trace.duplicate(true)}
func send_input(event:InputEvent)->void:
	root.push_input(event,true)
	input_trace.append({"type":event.get_class(),"event":event.as_text(),"handled":root.is_input_handled()})
	if input_trace.size()>20:input_trace.pop_front()
func pointer(point:Vector2,down:bool)->void:
	var event:=InputEventMouseButton.new()
	event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	send_input(event)
func move_pointer(point:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point
	send_input(event)
func key(down:bool)->void:
	var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.physical_keycode=KEY_SPACE;event.pressed=down
	send_input(event)

func run()->void:
	# Match the established native input fixture: explicit logical viewport and
	# local coordinates, with layout/input settled before each following event.
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var button:=Button.new();button.text="Feedback probe"
	button.position=Vector2(24,24);button.size=Vector2(180,48)
	button.self_modulate=Color(.81,.85,.88,.93)
	button.focus_mode=Control.FOCUS_ALL;button.mouse_filter=Control.MOUSE_FILTER_STOP
	var shortcut:=Shortcut.new();var shortcut_event:=InputEventKey.new();shortcut_event.keycode=KEY_G
	shortcut.events=[shortcut_event];button.shortcut=shortcut
	button.pressed.connect(func():actions.button+=1)
	root.add_child(button)
	await flush()
	var original_rect:Rect2=button.get_rect();var original_scale:Vector2=button.scale
	var original_base:Color=button.self_modulate
	check("first binding installs feedback",Feedback.bind(button))
	var pressed_connections:int=button.pressed.get_connections().size()
	check("repeat binding is a no-op",not Feedback.bind(button) and button.pressed.get_connections().size()==pressed_connections)
	check("original callback is preserved with one visual listener",pressed_connections==2)
	check("binding preserves input and shortcut properties",button.mouse_filter==Control.MOUSE_FILTER_STOP and button.focus_mode==Control.FOCUS_ALL and button.shortcut==shortcut)
	var point:Vector2=button.get_global_rect().get_center()
	move_pointer(point);await flush()
	pointer(point,true);await flush()
	pointer(point,false);await flush()
	check("native mouse click calls original action exactly once",actions.button==1 and Feedback.statistics(button).presses==1,diagnostics(button))
	button.grab_focus();await flush()
	key(true);await flush()
	key(false);await flush()
	check("native focused keyboard action still executes once",actions.button==2 and Feedback.statistics(button).presses==2,diagnostics(button))
	check("focus feedback preserves native focus",button.has_focus())
	Feedback.reset(button);button.disabled=true
	var before_disabled:int=actions.button
	move_pointer(Vector2(4,4));await flush()
	move_pointer(point);await flush()
	pointer(point,true);await flush()
	pointer(point,false);await flush()
	key(true);await flush()
	key(false);await flush()
	check("disabled native input never runs the command",actions.button==before_disabled,diagnostics(button))
	check("disabled feedback keeps baseline and no tween",button.self_modulate.is_equal_approx(original_base) and not Feedback.statistics(button).active)
	button.disabled=false;button.release_focus();Feedback.reset(button)
	for index:int in range(12):
		button.mouse_entered.emit();button.button_down.emit();button.button_up.emit();button.mouse_exited.emit()
	var state:Dictionary=button.get_meta(Feedback.META)
	var pending:Tween=state.tween
	check("rapid transitions retain one node-bound tween",is_instance_valid(pending) and pending.is_valid() and Feedback.statistics(button).active)
	await create_timer(.16).timeout
	check("feedback is finite and returns to baseline",not Feedback.statistics(button).active and button.self_modulate.is_equal_approx(original_base))
	check("feedback never changes hit rectangle or transform",button.get_rect()==original_rect and button.scale==original_scale)
	button.mouse_entered.emit()
	root.remove_child(button)
	check("tree exit kills feedback and restores baseline",not Feedback.statistics(button).active and button.self_modulate.is_equal_approx(original_base),diagnostics(button))
	button.focus_exited.emit();button.mouse_exited.emit()
	check("late focus and hover exits cannot restart a detached tween",not Feedback.statistics(button).active and button.self_modulate.is_equal_approx(original_base),diagnostics(button))
	root.add_child(button);await process_frame
	check("reentry does not duplicate feedback listeners",not Feedback.bind(button) and button.pressed.get_connections().size()==pressed_connections)
	button.mouse_entered.emit();button.queue_free();await process_frame;await process_frame
	check("freeing active control releases node-bound feedback",not is_instance_valid(button))
	var slot:=Slot.new();slot.position=Vector2(250,24);slot.size=Vector2(80,96)
	slot.slot={"kind":"inventory","index":0,"reference":{"kind":"item","item_id":"log"}}
	slot.activate=func(_value:Dictionary):actions.slot+=1
	Feedback.bind(slot);root.add_child(slot);await flush()
	var activate_callback:Callable=slot.activate
	slot.modulate.a=.6
	slot.mouse_entered.emit();await create_timer(.12).timeout
	check("slot feedback preserves drag opacity and activation callback",is_equal_approx(slot.modulate.a,.6) and slot.activate==activate_callback)
	slot.modulate.a=1.0
	var slot_point:Vector2=slot.get_global_rect().get_center()
	move_pointer(slot_point);await flush()
	pointer(slot_point,true);await flush()
	pointer(slot_point,false);await flush()
	check("slot native click activates exactly once",actions.slot==1,diagnostics(slot))
	slot.queue_free();await process_frame
	var panel:=PanelContainer.new();panel.position=Vector2(24,180);panel.size=Vector2(180,100)
	panel.modulate=Color(.9,.8,.7,.91);root.add_child(panel);await process_frame
	var panel_rect:Rect2=panel.get_rect();var panel_base:Color=panel.modulate
	Feedback.reveal(panel);Feedback.reveal(panel)
	check("repeated reveal uses one exit connection",panel.tree_exiting.get_connections().size()==1)
	await create_timer(.20).timeout
	check("reveal completes with original modulation and geometry",panel.modulate.is_equal_approx(panel_base) and panel.get_rect()==panel_rect)
	Feedback.reveal(panel);Feedback.finish_reveal(panel)
	check("hiding a dialog cancels reveal and restores alpha",panel.modulate.is_equal_approx(panel_base) and not is_instance_valid(panel.get_meta(Feedback.REVEAL_META).tween))
	Feedback.reveal(panel);root.remove_child(panel)
	check("dialog tree exit cancels reveal",panel.modulate.is_equal_approx(panel_base) and not is_instance_valid(panel.get_meta(Feedback.REVEAL_META).tween))
	panel.free()
	var probe:=Button.new();Feedback.bind(probe)
	var stats:Dictionary=Feedback.statistics(probe)
	var helper:=Feedback.new()
	check("helper does not own audio or a process loop",not stats.audio and not stats.process_loop and not helper.has_method("_process"))
	probe.free()
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);var file:=FileAccess.open(args[0]+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Native viewport input, feedback lifecycle and inventory activation tests. Does not claim GPU quality, live game command authority or whole-game performance coverage."},"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
