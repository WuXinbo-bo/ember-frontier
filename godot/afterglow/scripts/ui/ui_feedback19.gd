extends RefCounted
## Event-only canvas feedback. Never owns input, audio settings or game actions.
const META:="ui19_feedback"
const REVEAL_META:="ui19_reveal"
const HOVER_SECONDS:=0.10
const PRESS_SECONDS:=0.045
const RELEASE_SECONDS:=0.10

static func bind(button:BaseButton)->bool:
	if not is_instance_valid(button) or button.has_meta(META):return false
	button.set_meta(META,{"base":button.self_modulate,"hover":false,"focus":false,"down":false,"exiting":false,"tween":null,"transitions":0,"presses":0})
	var ref:WeakRef=weakref(button)
	button.mouse_entered.connect(func():_state(ref,"hover",true))
	button.mouse_exited.connect(func():_state(ref,"hover",false))
	button.focus_entered.connect(func():_state(ref,"focus",true))
	button.focus_exited.connect(func():_state(ref,"focus",false))
	button.button_down.connect(func():_state(ref,"down",true))
	button.button_up.connect(func():_state(ref,"down",false))
	button.pressed.connect(func():_pressed(ref))
	button.visibility_changed.connect(func():
		var value:Variant=ref.get_ref()
		if is_instance_valid(value) and not value.is_visible_in_tree():reset(value))
	button.tree_entered.connect(func():_lifecycle(ref,false))
	button.tree_exiting.connect(func():_lifecycle(ref,true))
	return true

static func _lifecycle(ref:WeakRef,exiting:bool)->void:
	var button:Variant=ref.get_ref()
	if not is_instance_valid(button):return
	var state:Dictionary=button.get_meta(META,{})
	if state.is_empty():return
	# Focus/mouse exit signals can follow tree_exiting while the Control still
	# reports visible/in-tree. Do not let those signals restart a bound tween.
	state.exiting=exiting
	button.set_meta(META,state)
	reset(button)

static func _state(ref:WeakRef,key:String,value:bool)->void:
	var button:Variant=ref.get_ref()
	if not is_instance_valid(button) or button.is_queued_for_deletion():return
	if button.disabled or not button.is_visible_in_tree():reset(button);return
	var state:Dictionary=button.get_meta(META,{})
	if state.is_empty():return
	if state.get("exiting",false):reset(button);return
	state[key]=value
	_animate(button,state,_color(state),PRESS_SECONDS if state.down else HOVER_SECONDS)

static func _color(state:Dictionary)->Color:
	var base:Color=state.get("base",Color.WHITE)
	if state.get("down",false):return base*Color(.94,.95,.93,1)
	if state.get("hover",false):return base*Color(1.045,1.025,.985,1)
	if state.get("focus",false):return base*Color(1.025,1.025,1.01,1)
	return base

static func _animate(button:BaseButton,state:Dictionary,target:Color,duration:float)->void:
	_stop(state)
	if not button.is_inside_tree() or not button.is_visible_in_tree():button.self_modulate=state.base;return
	state.transitions=mini(9999,int(state.get("transitions",0))+1)
	var tween:Tween=button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	state.tween=tween
	tween.tween_property(button,"self_modulate",target,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	button.set_meta(META,state)

static func _pressed(ref:WeakRef)->void:
	var button:Variant=ref.get_ref()
	if not is_instance_valid(button) or button.is_queued_for_deletion():return
	if button.disabled or not button.is_visible_in_tree():reset(button);return
	var state:Dictionary=button.get_meta(META,{})
	if state.is_empty():return
	if state.get("exiting",false):reset(button);return
	state.presses=mini(9999,int(state.get("presses",0))+1)
	state.down=false
	_animate(button,state,_color(state),RELEASE_SECONDS)

static func _stop(state:Dictionary)->void:
	var tween:Variant=state.get("tween")
	if is_instance_valid(tween):tween.kill()
	state.tween=null

static func reset(button:BaseButton)->void:
	if not is_instance_valid(button) or not button.has_meta(META):return
	var state:Dictionary=button.get_meta(META)
	_stop(state)
	button.self_modulate=state.get("base",Color.WHITE)
	state.hover=false;state.focus=false;state.down=false
	button.set_meta(META,state)

static func reveal(panel:Control)->void:
	if not is_instance_valid(panel) or not panel.is_inside_tree() or not panel.is_visible_in_tree():return
	finish_reveal(panel)
	var base:Color=panel.modulate
	var state:Dictionary={"base":base,"tween":null}
	var ref:WeakRef=weakref(panel)
	if not panel.has_meta(REVEAL_META):
		panel.tree_exiting.connect(func():
			var value:Variant=ref.get_ref()
			if is_instance_valid(value):finish_reveal(value))
	panel.set_meta(REVEAL_META,state)
	panel.modulate=Color(base.r,base.g,base.b,base.a*.86)
	var tween:Tween=panel.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	state.tween=tween
	tween.tween_property(panel,"modulate",base,.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.set_meta(REVEAL_META,state)

static func finish_reveal(panel:Control)->void:
	if not is_instance_valid(panel) or not panel.has_meta(REVEAL_META):return
	var state:Dictionary=panel.get_meta(REVEAL_META)
	_stop(state)
	panel.modulate=state.get("base",Color.WHITE)
	panel.set_meta(REVEAL_META,state)

static func statistics(button:BaseButton)->Dictionary:
	if not is_instance_valid(button) or not button.has_meta(META):return {"bound":false}
	var state:Dictionary=button.get_meta(META)
	var tween:Variant=state.get("tween")
	return {"bound":true,"transitions":state.get("transitions",0),"presses":state.get("presses",0),"active":is_instance_valid(tween) and tween.is_running(),"audio":false,"process_loop":false}
