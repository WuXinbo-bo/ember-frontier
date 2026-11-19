extends Node
## One physical-key map and one held-input owner. UI owns its local modal navigation.
signal changed
signal open_requested(page: String)
signal save_requested
signal primary_requested(pressed: bool)
signal secondary_requested
signal confirm_requested
signal retract_placement_requested
signal consume_requested
signal combat_ready_changed
signal rotate_requested
signal cancel_requested
signal movement_requested(direction: Vector2,delta: float)
signal interact_requested
signal zoom_requested(amount: float)
signal structure_action_requested(operation: String,target_id: String)
signal module_placement_requested(definition_id:String)
signal facility_placement_requested(definition_id:String)
const DEFAULTS := {"up":KEY_W,"down":KEY_S,"left":KEY_A,"right":KEY_D,"run":KEY_SHIFT,"interact":KEY_E,"inventory":KEY_TAB,"build":KEY_B,"neighbors":KEY_T,"map":KEY_M,"rotate":KEY_R,"cancel":KEY_ESCAPE,"auto_pickup":KEY_G,"consume":KEY_F}
var _runtime: RefCounted
var controls_path:String="user://controls.json"
var _bindings: Dictionary = {}
var _reasons: Dictionary = {"modal":false,"window_focus":false,"file_dialog":false,"closing":false}
var _modal_pauses_world:=true
var _slots: Array = [{"kind":"item","id":"water"},{"kind":"item","id":"food"},{},{},{},{},{},{},{}]
var _auto_pickup:=false
var _selected: int = 0
var _recipe_disarmed:=false
var _mode: String = "tool"
var _primary: bool = false
var _combat_ready:=false
var _combat_toggle:=false
var _secondary_down:=false
var _world_pointer_consumer:Callable
var _zone_confirmation_active: Callable
var secondary_position:Variant=null
var _pressed: Dictionary = {}
var _sequence: int = 0
var _structure_target := ""
var _module_definition_id:=""
var _module_worker_id:=""
var _facility_definition_id:=""
var _terrain := {"operation":"dig","material":2,"height":0.0,"brush_cells":1}
const MODES := ["tool","demolish","destroy","repair","move","terrain_dig","terrain_fill","terrain_level","module_place","facility_place"]

func set_world_pointer_consumer(consumer: Callable, zone_confirmation_active := Callable()) -> void:
	_world_pointer_consumer = consumer
	_zone_confirmation_active = zone_confirmation_active

func configure(runtime: RefCounted,fresh_profile:bool=false,fresh_opening:bool=false) -> void:
	_runtime=runtime
	_bindings=DEFAULTS.duplicate()
	if FileAccess.file_exists(controls_path):
		var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(controls_path))
		if saved is Dictionary:
			var raw_keys:Variant=saved.get("bindings",saved)
			var keys:Dictionary=raw_keys if raw_keys is Dictionary else {}
			var candidate:Dictionary=DEFAULTS.duplicate()
			for key:String in DEFAULTS:
				if keys.get(key) is float or keys.get(key) is int:candidate[key]=int(keys[key])
			# F may belong to an existing custom action. Preserve that layout and
			# leave the new shortcut unbound until the player assigns a free key.
			if not keys.has("consume"):
				for action:String in candidate.keys():
					if action!="consume" and candidate[action]==KEY_F:
						candidate.erase("consume")
						break
			var valid:bool=true
			var used:Dictionary={}
			for key:String in candidate:
				var packed:int=int(candidate[key])
				if _reserved_key(packed,key) or used.has(packed):valid=false;break
				used[packed]=true
			if valid:_bindings=candidate
			if saved.get("slots") is Array and saved.slots.size()==9:
				for index in 9:
					var ref:Variant=saved.slots[index]
					if ref is Dictionary and (ref.is_empty() or ref.get("kind") in ["item","tool","recipe"] and ref.get("id") is String):_slots[index]=ref.duplicate()
			_auto_pickup=bool(saved.get("auto_pickup",false))
			_combat_toggle=bool(saved.get("combat_toggle",false))
			_selected=clampi(int(saved.get("selected",0)),0,8)
	for key: String in _bindings: _install_action(key,int(_bindings[key]))
	if fresh_profile or fresh_opening:
		_slots=_opening_slots(fresh_profile);_selected=0
		_persist_bindings()
	else:
		# Global controls may refer to a tool owned by a different save. Keep
		# keys/item shortcuts, but never present that stale ID as a real tool.
		for index:int in _slots.size():
			var ref:Dictionary=_slots[index]
			if ref.get("kind")=="tool" and _runtime.tool(str(ref.get("id",""))).get("holderId")!="pack:player":_slots[index]={}
	_sync_hand()

func _opening_slots(playtest:bool)->Array:
	var value:Variant=_runtime.call("hud_snapshot" if _runtime.has_method("hud_snapshot") else "snapshot")
	var tools:Array=value.get("tools",[]) if value is Dictionary else []
	var kinds:Array=["salvaged_axe","shovel","pickaxe","hammer","hand_saw"] if playtest else ["salvaged_axe"]
	var result:Array=[]
	for kind:String in kinds:
		var reference:Dictionary={}
		for tool:Dictionary in tools:
			if str(tool.get("holderId",tool.get("holder_id","")))=="pack:player" and str(tool.get("kind",tool.get("definitionId",tool.get("definition_id",""))))==kind:
				reference={"kind":"tool","id":str(tool.id)};break
		result.append(reference)
	result.append_array([{"kind":"item","id":"food"},{"kind":"item","id":"water"}])
	while result.size()<9:result.append({})
	return result
func _install_action(action: String,packed: int) -> void:
	var name: String="afterglow_"+action
	if not InputMap.has_action(name): InputMap.add_action(name)
	InputMap.action_erase_events(name)
	InputMap.action_add_event(name,_key_event(packed))
func _key_event(packed: int) -> InputEventKey:
	var event:=InputEventKey.new()
	event.physical_keycode=packed & KEY_CODE_MASK
	event.shift_pressed=bool(packed & KEY_MASK_SHIFT)
	event.ctrl_pressed=bool(packed & KEY_MASK_CTRL)
	event.alt_pressed=bool(packed & KEY_MASK_ALT)
	event.meta_pressed=bool(packed & KEY_MASK_META)
	return event
func bind_key(action: String,keycode: int) -> Dictionary:
	if not DEFAULTS.has(action): return _receipt(false,"UNKNOWN_ACTION","未知操作")
	if _reserved_key(keycode,action):return _receipt(false,"RESERVED_KEY","该按键由系统或保存操作保留")
	for other: String in _bindings:
		if other!=action and int(_bindings[other])==keycode: return _receipt(false,"KEY_CONFLICT","按键已用于其他操作")
	if action!="inventory" and keycode==KEY_I and int(_bindings.get("inventory",KEY_TAB))==KEY_TAB:return _receipt(false,"KEY_CONFLICT","I已用于背包兼容键；先修改背包主键")
	if action=="inventory" and keycode==KEY_TAB:
		for other:String in _bindings:
			if other!="inventory" and int(_bindings[other])==KEY_I:return _receipt(false,"KEY_CONFLICT","I已用于其他操作，无法同时启用Tab/I背包键")
	var previous: Dictionary=_bindings.duplicate()
	_bindings[action]=keycode
	if not _persist_bindings(): _bindings=previous;return _receipt(false,"IO_ERROR","键位保存失败，保留原映射")
	_release();_install_action(action,keycode);_sync_hand();changed.emit();return _receipt(true)
func set_auto_pickup(enabled:bool)->Dictionary:
	var before:bool=_auto_pickup;_auto_pickup=enabled
	if not _persist_bindings():_auto_pickup=before;return _receipt(false,"IO_ERROR","拾取设置保存失败")
	_sync_hand();changed.emit();return _receipt(true)
func set_combat_toggle(enabled:bool)->Dictionary:
	var previous:bool=_combat_toggle
	_combat_toggle=enabled
	if not _persist_bindings():
		_combat_toggle=previous
		return _receipt(false,"IO_ERROR","战备设置保存失败")
	_release()
	_sync_hand()
	changed.emit()
	return _receipt(true)

func reset_bindings() -> Dictionary:
	var previous: Dictionary=_bindings.duplicate()
	_bindings=DEFAULTS.duplicate()
	if not _persist_bindings(): _bindings=previous;return _receipt(false,"IO_ERROR","键位保存失败")
	_release()
	for action: String in _bindings: _install_action(action,int(_bindings[action]))
	_sync_hand();changed.emit();return _receipt(true)
func _reserved_key(keycode: int,action:String="") -> bool:
	var plain:int=keycode & KEY_CODE_MASK
	if action=="run" and keycode==KEY_SHIFT:return false
	return plain in [KEY_NONE,KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META] or (plain==KEY_S and keycode & (KEY_MASK_CTRL|KEY_MASK_META)) or (keycode & KEY_MASK_META and plain in [KEY_Q,KEY_H,KEY_TAB]) or (keycode & KEY_MASK_META and keycode & KEY_MASK_CTRL and plain==KEY_Q)
func _persist_bindings() -> bool:
	var file:=FileAccess.open(controls_path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify({"schema":"afterglow-controls-v1","bindings":_bindings,"slots":_slots,"selected":_selected,"auto_pickup":_auto_pickup,"combat_toggle":_combat_toggle}));file.flush();file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(controls_path+".tmp"),ProjectSettings.globalize_path(controls_path))==OK
func set_modal(active: bool) -> void:
	set_modal_policy(active,true)
func set_modal_policy(active:bool,pause_world:bool=true)->void:
	# A live map still consumes all world input. Only its simulation policy
	# differs; window/file/closing/streaming reasons always pause the one clock.
	_modal_pauses_world=pause_world if active else true
	_set_reason("modal",active)
func set_file_dialog(active: bool) -> void:
	_set_reason("file_dialog",active)
func set_window_focus(focused: bool) -> void:
	_set_reason("window_focus",not focused)
func set_closing(active: bool) -> void:
	_set_reason("closing",active)
func set_streaming(active: bool) -> void:
	_set_reason("streaming",active)
func _set_reason(reason: String,active: bool) -> void:
	_reasons[reason]=active
	if active: _release()
	if _runtime!=null: _runtime.set_paused(world_is_paused())
	changed.emit()
func is_paused() -> bool:
	return _reasons.values().has(true)
func world_is_paused()->bool:
	for reason:String in _reasons:
		if _reasons[reason] and (reason!="modal" or _modal_pauses_world):return true
	return false
func _release() -> void:
	_pressed.clear()
	_secondary_down=false
	for action:String in _bindings:
		var input_action := "afterglow_" + action
		if InputMap.has_action(input_action):Input.action_release(input_action)
	_release_primary()
	_set_combat_ready(false)

func _release_primary()->void:
	_primary=false
	primary_requested.emit(false)

func _set_combat_ready(value:bool)->void:
	if _combat_ready==value:return
	_combat_ready=value
	combat_ready_changed.emit()

func combat_ready()->bool:
	return _combat_ready

func begin_world_combat_hold()->void:
	_secondary_down=true
	_set_combat_ready(not _combat_ready if _combat_toggle else true)

func finish_world_context_click()->void:
	if _combat_toggle:_set_combat_ready(not _combat_ready)

func mode()->String:
	return _mode

func is_placement()->bool:
	return _mode in ["module_place","facility_place"] or (_mode=="move" and not _structure_target.is_empty()) or (_mode=="tool" and _slots[_selected].get("kind")=="recipe" and not _recipe_disarmed)
func state() -> Dictionary:
	var bindings: Dictionary={}
	for action: String in _bindings:
		bindings[action]={"keycode":_bindings[action],"physical":true,"label":_key_event(int(_bindings[action])).as_text_physical_keycode()}
		if action=="inventory":bindings[action].aliases=[{"keycode":KEY_I,"label":"I"}] if _inventory_alias_enabled() else []
	if not bindings.has("consume"):bindings.consume={"keycode":KEY_NONE,"physical":true,"label":"未绑定"}
	return {"bindings":bindings,"pause_reasons":_reasons.duplicate(),"paused":is_paused(),"world_paused":world_is_paused(),"modal_pauses_world":_modal_pauses_world,"auto_pickup":_auto_pickup,"combat_toggle":_combat_toggle,"slots":_slots.duplicate(true),"selected":_selected,"recipe_disarmed":_recipe_disarmed,"mode":_mode,"modes":MODES.duplicate(),"structure_target_id":_structure_target,"module_definition_id":_module_definition_id,"module_worker_id":_module_worker_id,"facility_definition_id":_facility_definition_id,"terrain":_terrain.duplicate(),"held":{"primary":_primary,"run":_pressed.has("run")}}

func interaction_state() -> Dictionary:
	# Targeting needs current controls without rebuilding localized key labels,
	# shortcut slots and pause diagnostics for every query.
	return {
		"mode": _mode,
		"terrain": _terrain.duplicate(),
		"auto_pickup": _auto_pickup,
		"module_definition_id": _module_definition_id,
		"module_worker_id": _module_worker_id,
		"facility_definition_id": _facility_definition_id,
	}

func run_held() -> bool:
	return _pressed.has("run")

func select_slot(index: int) -> Dictionary:
	if index<0 or index>=9: return _receipt(false,"INVALID_SLOT","快捷格无效")
	if _mode=="facility_place":_mode="tool";_facility_definition_id=""
	_release();_recipe_disarmed=false;_selected=index;_persist_bindings();_sync_hand();changed.emit();return _receipt(true)
func assign_slot(index: int,reference: Dictionary) -> Dictionary:
	if index<0 or index>=9: return _receipt(false,"INVALID_SLOT","快捷格无效")
	if not reference.is_empty():
		var kind: String=str(reference.get("kind",""))
		var field: String={"item":"item_id","tool":"tool_id","recipe":"definition_id"}.get(kind,"")
		var id: String=str(reference.get(field,reference.get("id","")))
		if not kind in ["item","tool","recipe"] or id.is_empty(): return _receipt(false,"INVALID_REFERENCE","物品引用无效")
		if _runtime!=null and kind=="tool":
			var item: Dictionary=_runtime.tool(id)
			if item.is_empty() or item.get("holderId")!="pack:player": return _receipt(false,"UNAVAILABLE_TOOL","工具不在随身背包")
		_slots[index]={"kind":kind,"id":id}
	else: _slots[index]={}
	if index==_selected:_recipe_disarmed=false
	_persist_bindings();_sync_hand();changed.emit();return _receipt(true)
func set_mode(value: String) -> Dictionary:
	if not value in MODES:return _receipt(false,"INVALID_MODE","操作模式无效")
	_release();_mode=value;_structure_target=""
	if value!="module_place":_module_definition_id="";_module_worker_id=""
	if value!="facility_place":_facility_definition_id=""
	if value.begins_with("terrain_"):_terrain.operation=value.trim_prefix("terrain_")
	_sync_hand();changed.emit();return _receipt(true)
func begin_module_placement(definition_id:String,worker_id:String="")->Dictionary:
	if _runtime==null:return _receipt(false,"UNAVAILABLE","世界尚未装配")
	var factory:Dictionary=_runtime.factory_page_snapshot("player","factory_catalog") if _runtime.has_method("factory_page_snapshot") else _runtime.factory_snapshot()
	if not factory.get("capabilities",{}).get("modules",false):return _receipt(false,"UNAVAILABLE","完整模块尚未装配")
	if not factory.modules.definitions.any(func(d:Dictionary)->bool:return d.get("id")==definition_id):return _receipt(false,"UNKNOWN_MODULE","完整模块定义不存在")
	if not worker_id.is_empty():
		var worker:Dictionary=_runtime.actor(worker_id)
		if worker_id=="player" or worker.is_empty() or float(worker.get("hp",0))<=0 or not worker.get("relationship",{}).get("member",false) or not worker.get("relationship",{}).get("consent",false):return _receipt(false,"WORKER_UNAVAILABLE","同伴目前无法接单")
		if not factory.modules.definitions.any(func(d:Dictionary)->bool:return d.get("id")==definition_id and d.get("shape")=="home"):return _receipt(false,"UNSUPPORTED_BLUEPRINT","请选择住宅蓝图")
	var result:Dictionary=set_mode("module_place")
	_module_definition_id=definition_id;_module_worker_id=worker_id;_sync_hand();changed.emit();module_placement_requested.emit(definition_id)
	return result
func begin_facility_placement(definition_id:String)->Dictionary:
	if _runtime==null:return _receipt(false,"UNAVAILABLE","世界尚未装配")
	# MV01 exposes one existing movable facility, not the legacy furniture set.
	if definition_id!="cabinet":return _receipt(false,"UNKNOWN_FACILITY","当前只支持可搬移储物柜")
	var found:bool=false
	for definition:Dictionary in _runtime.snapshot().get("catalog",{}).get("buildings",[]):
		if definition.get("id",definition.get("definition_id",""))==definition_id:found=true;break
	if not found:return _receipt(false,"UNKNOWN_FACILITY","实际储物柜定义尚未装配")
	var result:Dictionary=set_mode("facility_place")
	_facility_definition_id=definition_id;_sync_hand();changed.emit();facility_placement_requested.emit(definition_id)
	return result
func begin_structure_action(operation: String,target_id: String="") -> Dictionary:
	if operation not in ["repair","move","demolish","destroy"]:return _receipt(false,"INVALID_MODE","施工模式无效")
	if not target_id.is_empty() and _runtime.world.entity(target_id).get("kind")!="structure":return _receipt(false,"MISSING_TARGET","实际构件不存在")
	var ready:=set_mode(operation)
	_structure_target=target_id;_sync_hand();changed.emit()
	structure_action_requested.emit(operation,target_id)
	return ready
func set_terrain_brush(operation: String,material: int=2,height: float=0.0,brush_cells: int=1) -> Dictionary:
	if operation not in ["dig","fill","level"] or material not in [2,3,6] or not is_finite(height) or brush_cells not in [1,2]:return _receipt(false,"INVALID_BRUSH","地形工具参数无效")
	var size:float=float(_runtime.world.config().cellSize)
	if not is_equal_approx(height/size,roundf(height/size)):return _receipt(false,"INVALID_HEIGHT","整平高度需与体素格对齐")
	set_mode("terrain_"+operation)
	_terrain={"operation":operation,"material":material,"height":height,"brush_cells":brush_cells}
	_sync_hand();changed.emit();return _receipt(true)
func confirm_placement()->void:
	if is_placement() and not is_paused():confirm_requested.emit()

func retract_placement()->void:
	if is_placement() and not is_paused():retract_placement_requested.emit()

func cancel() -> void:
	_release();cancel_requested.emit()
func clear_recipe_selection()->void:
	_recipe_disarmed=true
	_release()
	_sync_hand()
	changed.emit()

func held_reference() -> Dictionary:
	if _recipe_disarmed and _slots[_selected].get("kind")=="recipe":return {}
	return _slots[_selected].duplicate(true)
func _sync_hand() -> void:
	if _runtime!=null: _runtime.set_hand(state())
func request(kind: String,target_id: String="",payload: Dictionary={},destination: Dictionary={}) -> Dictionary:
	_sequence+=1
	return _runtime.command({"command_id":"input:%s:%s"%[Time.get_ticks_usec(),_sequence],"actor_id":"player","kind":kind,"target_id":target_id,"payload":payload,"destination":destination,"expected_revision":_runtime.get_revision()})
func _physics_process(delta: float) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_physics_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("input/input_router.gd",measured)

func _profiled_physics_process(delta: float) -> void:
	if _runtime==null or is_paused(): return
	var direction:=Vector2(float(_pressed.has("right"))-float(_pressed.has("left")),float(_pressed.has("down"))-float(_pressed.has("up")))
	if direction.length_squared()>0: movement_requested.emit(direction.normalized(),delta)
func _inventory_alias_enabled()->bool:
	if int(_bindings.get("inventory",KEY_TAB))!=KEY_TAB:return false
	for action:String in _bindings:
		if action!="inventory" and int(_bindings[action])==KEY_I:return false
	return true

func _save_key(event:InputEventKey)->bool:
	return (event.ctrl_pressed or event.meta_pressed) and not event.alt_pressed and (event.physical_keycode==KEY_S or event.keycode==KEY_S)

func _request_save()->void:
	_release()
	if save_requested.get_connections().is_empty():_runtime.save_async()
	else:save_requested.emit()

func _input(event:InputEvent)->void:
	if _runtime==null:return
	# Releases belong to the owner of the press even over GUI controls.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT and _primary:_release_primary()
		if event.button_index==MOUSE_BUTTON_RIGHT:
			_secondary_down=false
			if not _combat_toggle:_set_combat_ready(false)
		return
	if not event is InputEventKey:return
	if not event.pressed:
		for action:String in _pressed.keys():
			if int(_bindings[action]) & KEY_CODE_MASK == event.physical_keycode:_pressed.erase(action)
		return
	# Global world shortcuts precede GUI traversal. Modal/text navigation is local.
	if event.echo or is_paused():return
	var focus:Control=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	if _save_key(event):
		get_viewport().set_input_as_handled();_request_save();return
	for action:String in ["inventory","build","neighbors","map","cancel"]:
		if not _matches_key(event,action):continue
		get_viewport().set_input_as_handled()
		if action=="cancel":cancel()
		else:
			_release()
			open_requested.emit(action)
		return

func _unhandled_input(event: InputEvent) -> void:
	if _runtime==null:return
	# A planning click is consumed before tool signals, including mouse-up.
	# The native GUI has already had first refusal at this event stage.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and not _reasons.get("window_focus",false) and not _reasons.get("file_dialog",false) and not _reasons.get("closing",false) and _world_pointer_consumer.is_valid():
		if _world_pointer_consumer.call(event):
			if _primary:_release_primary()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		if event.echo:return
		if event.pressed and _save_key(event):
			_request_save();get_viewport().set_input_as_handled();return
		if not event.pressed or is_paused():return
		var key: int = event.get_physical_keycode_with_modifiers() if event.physical_keycode != KEY_NONE else event.get_keycode_with_modifiers()
		if key in [KEY_ENTER, KEY_KP_ENTER]:
			var zone_active: bool = _zone_confirmation_active.is_valid() and bool(_zone_confirmation_active.call())
			if is_placement() or zone_active:
				get_viewport().set_input_as_handled()
				confirm_requested.emit()
				return
		for action: String in _bindings:
			if _matches_key(event,action):
				get_viewport().set_input_as_handled()
				if action in ["up","down","left","right","run"]: _pressed[action]=true
				elif action in ["inventory","build","neighbors","map"]: _release();open_requested.emit(action)
				elif action=="cancel":cancel()
				elif action=="rotate":rotate_requested.emit()
				elif action=="interact":interact_requested.emit()
				elif action=="consume":consume_requested.emit()
				elif action=="auto_pickup":set_auto_pickup(not _auto_pickup)
				return
		if not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed and event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_9:
			select_slot(event.physical_keycode-KEY_1);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if not event.pressed or is_paused():return
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not event.ctrl_pressed:
			_primary=true;primary_requested.emit(true);get_viewport().set_input_as_handled()
		elif event.pressed and (event.button_index==MOUSE_BUTTON_RIGHT or event.button_index==MOUSE_BUTTON_LEFT and event.ctrl_pressed):
			get_viewport().set_input_as_handled()
			if _mode=="tool" and not is_placement():
				if event.button_index!=MOUSE_BUTTON_RIGHT or _secondary_down:return
				_secondary_down=true
				if _primary:_release_primary()
				_set_combat_ready(not _combat_ready if _combat_toggle else true)
			else:
				secondary_position=event.position
				secondary_requested.emit()
				secondary_position=null
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if event.ctrl_pressed:zoom_requested.emit(-1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0)
			else:select_slot(posmod(_selected+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),9))
			get_viewport().set_input_as_handled()
func _matches_key(event:InputEventKey,action:String)->bool:
	if action=="inventory" and _inventory_alias_enabled() and event.get_physical_keycode_with_modifiers()==KEY_I:return true
	var packed:int=int(_bindings[action])
	if event.physical_keycode!=(packed & KEY_CODE_MASK):return false
	if action=="run" and packed==KEY_SHIFT:return not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed
	# Shift is an independent held action, including when pressed before W.
	if action in ["up","down","left","right"] and not packed & KEY_MASK_SHIFT:
		return event.ctrl_pressed==bool(packed & KEY_MASK_CTRL) and event.alt_pressed==bool(packed & KEY_MASK_ALT) and event.meta_pressed==bool(packed & KEY_MASK_META)
	return event.is_action_pressed("afterglow_"+action,false,true)
func _receipt(ok: bool,code: String="OK",reason: String="") -> Dictionary:
	return {"ok":ok,"code":code,"reason":null if reason.is_empty() else reason}
