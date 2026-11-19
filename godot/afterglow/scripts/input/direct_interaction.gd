extends Node
## One pointed target and preview. All real actions are submitted to the runtime.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const TreeContact = preload("res://scripts/buildings/interaction_contact.gd")
var runtime: RefCounted
var world: RefCounted
var router: Node
var camera: Camera3D
var buildings: RefCounted
var modules: RefCounted
var terrain: Node3D
var ui: Control
var view_policy: RefCounted
var _target: Dictionary={}
var _published_target: Dictionary = {}
var _exact_target:Dictionary={}
var _pointed_person: String=""
var _press_screen: Variant=null
var _picked_screen:=Vector2.ZERO
var _point: Dictionary={}
var _terrain_pick_basis: Array = []
var _terrain_pick_hit: Dictionary = {}
var _pickup_delay:=0.0
var _delay := 0.0
var _hover_deferred := false
var _quarter := 0
var _ghost: MeshInstance3D
var _preview: Dictionary={}
var _placement_key:Array=[]
var _fixed_build_position: Dictionary = {}
var _build_view: Dictionary = {}
var _fixed_structure_location: Dictionary = {}
var _structure_candidate_location: Dictionary = {}
var _ghost_mesh:=BoxMesh.new()
var _ghost_material:=StandardMaterial3D.new()
var _pending_container := ""
var _entities: Array=[]
var _entity_revision := -1
var _moving_target := ""
var _terrain_payload: Dictionary={}
var _holding_primary := false
var _held_kind := ""
var _blocked_work_key := ""
var _move_problem := ""
const SWING_BUFFER_SECONDS := 0.15
var _buffered_swing: Dictionary = {}
var _module_preview_id:=""
var _structure_preview_id:=""
var _placement_view_hint:Dictionary={}
var _view_hint_renderer:=false
var _tree_drag:Variant=null
var _tree_rectangle:=Rect2()
var _tree_dragging:=false
var _tree_candidates:Array=[]
var _marked_trees:Array[String]=[]
var _tree_queue:Array[String]=[]
var _tree_batch_target:=""
var _tree_batch_done:=0
var _tree_batch_skipped:=0
var _tree_batch_paused:=false
var _tree_batch_wait:=0.0
var _tree_overlay:Control
var _tree_confirm:Button

func configure(context: Dictionary) -> void:
	runtime=context.runtime;world=context.world;router=context.router;camera=context.camera;buildings=context.buildings;terrain=context.terrain;ui=context.ui
	modules=context.get("modules")
	view_policy=context.get("view_policy")
	if router.has_method("set_world_pointer_consumer"):router.set_world_pointer_consumer(_planning_pointer, _confirm_shortcut_active)
	router.movement_requested.connect(_move)
	router.interact_requested.connect(_interact)
	router.primary_requested.connect(_primary)
	router.secondary_requested.connect(_secondary)
	router.confirm_requested.connect(_confirm_placement)
	router.retract_placement_requested.connect(_secondary)
	router.consume_requested.connect(_consume)
	router.combat_ready_changed.connect(_on_combat_ready_changed)
	router.changed.connect(_on_context_changed)
	router.rotate_requested.connect(func():
		if router.is_placement():
			_quarter=posmod(_quarter+1,4)
			_refresh())
	router.cancel_requested.connect(_cancel)
	router.module_placement_requested.connect(func(_id:String):_clear_placement_lock();_module_preview_id="";_quarter=0;_refresh())
	router.facility_placement_requested.connect(func(_id:String):_clear_placement_lock();_moving_target="";_module_preview_id="";_quarter=0;_refresh())
	router.structure_action_requested.connect(func(operation:String,id:String):
		_moving_target=id if operation=="move" else ""
		if not _moving_target.is_empty():_quarter=int(buildings.instance(_moving_target).get("quarterTurn",0))
		_refresh())
	_ghost=MeshInstance3D.new()
	_ghost.mesh=_ghost_mesh
	_ghost_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override=_ghost_material
	_ghost.visible=false
	camera.get_parent().add_child(_ghost)
	var layer:=CanvasLayer.new()
	layer.layer=21
	add_child(layer)
	_tree_overlay=Control.new()
	_tree_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(_tree_overlay)
	_tree_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tree_overlay.draw.connect(_draw_tree_selection)
	_tree_confirm=Button.new()
	_tree_confirm.theme=ui.theme
	_tree_confirm.focus_mode=Control.FOCUS_NONE
	_tree_confirm.theme_type_variation="PrimaryButton"
	_tree_overlay.add_child(_tree_confirm)
	_tree_confirm.pressed.connect(_confirm_tree_batch)
	_tree_confirm.hide()
	runtime.changed.connect(_harvest_feedback)
	_refresh()

func _on_combat_ready_changed() -> void:
	_buffered_swing.clear()
	if router.combat_ready():_clear_tree_selection()
	if router.combat_ready() and is_instance_valid(ui) and ui.has_method("close_companion_card_for_world_input"):
		ui.close_companion_card_for_world_input()
	_refresh()

func _on_context_changed()->void:
	_buffered_swing.clear()
	if (_tree_drag!=null or not _marked_trees.is_empty()) and (router.is_paused() or router.mode()!="tool" or _zone_confirmation_active()):_clear_tree_selection()
	if router.mode()!="move":_moving_target=""
	var state:Dictionary=router.state()
	var key:Array=[state.mode,state.structure_target_id,state.module_definition_id,state.module_worker_id,state.facility_definition_id,state.selected,router.held_reference().get("id","")]
	if router.is_paused() or not router.is_placement() or key!=_placement_key:
		_clear_placement_lock()
		_structure_preview_id=""
		_preview={}
		_placement_view_hint={}
		if is_instance_valid(_ghost):_ghost.visible=false
	_placement_key=key
	if router.mode() != "module_place" or router.is_paused():
		_publish_build_view({"active": false})
	_delay=0.0

func _zone_confirmation_active() -> bool:
	return is_instance_valid(ui) and ui.has_method("is_zone_planning") and ui.is_zone_planning()

func _confirm_shortcut_active()->bool:
	return _zone_confirmation_active() or is_instance_valid(_tree_confirm) and _tree_confirm.visible

func _clear_placement_lock() -> void:
	_fixed_build_position.clear()
	_fixed_structure_location.clear()

func _exit_tree() -> void:
	if is_instance_valid(_ghost):_ghost.queue_free()

func _planning_pointer(event:InputEvent)->bool:
	if ui==null or not is_instance_valid(ui) or not ui.has_method("is_zone_planning"):return false
	if not ui.is_zone_planning():
		if _tree_pointer(event):return true
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not event.ctrl_pressed and not router.is_paused():_press_screen=event.position
		return false
	if not ui.has_method("handle_world_click") or runtime==null or runtime.is_retired():return true
	if event is InputEventMouseMotion and not ui.zone_planning.drawing:return true
	var mouse:Vector2=event.position if event is InputEventMouse else get_viewport().get_mouse_position()
	var origin:Vector3=camera.project_ray_origin(mouse)
	var direction:Vector3=camera.project_ray_normal(mouse)
	var hit:Dictionary=terrain.pick(origin,origin+direction*160.0)
	if hit.get("cell") is Dictionary and not hit.get("unknown",false):
		var cell:Dictionary=hit.cell
		var size:float=world.config().cellSize
		var point:Vector3=Vector3((float(cell.x)+.5)*size,(float(cell.y)+1)*size,(float(cell.z)+.5)*size)
		var region:Dictionary=world.region_at(Geometry.json_point(point))
		if not region.is_empty():hit.region_id=region.id;hit.position=Geometry.json_point(point)
	return bool(ui.handle_world_click(hit,event))

func _harvest_payload(batch:bool)->Dictionary:
	return {"tool_id":_tool_id("chopping"),"direct":not batch,"held":true,"click_harvest":not batch,"pickup_yield":bool(_interaction_state().get("auto_pickup",false))}

func _tree_pointer(event:InputEvent)->bool:
	if router.is_paused() or router.mode()!="tool" or router.is_placement() or router.combat_ready() or runtime.expedition_in_combat():return false
	if event is InputEventMouseMotion and _tree_drag!=null:
		if not _tree_dragging and event.position.distance_to(_tree_drag)<10.0:return true
		if not _tree_dragging:
			_tree_dragging=true
			var at:=Geometry.point(runtime.actor("player"))
			var search:=AABB(at-Vector3(48,16,48),Vector3(96,32,96))
			_tree_candidates=world.entities_in_any_bounds([Geometry.json_box(search)]).filter(func(e:Dictionary)->bool:
				return e.get("kind")=="tree" and e.get("data",{}).get("harvest",{}).get("phase")=="standing" and runtime.region_is_detailed(str(e.regionId)))
		_update_tree_rectangle(event.position)
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		_clear_tree_selection()
		_tree_drag=event.position
		return true
	return false

func _input(event:InputEvent)->void:
	if _tree_drag==null or not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_RIGHT or event.pressed:return
	var origin:Vector2=_tree_drag
	if _tree_dragging:
		_update_tree_rectangle(event.position)
		_tree_drag=null
		_tree_dragging=false
		_tree_candidates.clear()
		if _marked_trees.is_empty():
			_clear_tree_selection()
			ui.notify("框内没有可砍的树",true)
		else:_show_tree_confirm("砍伐 %d 棵" % _marked_trees.size())
	else:
		_clear_tree_selection()
		var hovered:=get_viewport().gui_get_hovered_control()
		if is_instance_valid(hovered) and hovered.mouse_filter!=Control.MOUSE_FILTER_IGNORE:return
		_refresh_at(origin)
		if not ui.has_method("open_scene_work") or not ui.open_scene_work(_exact_target,_pointed_person):router.finish_world_context_click()

func _update_tree_rectangle(end:Vector2)->void:
	var origin:Vector2=_tree_drag
	_tree_rectangle=Rect2(origin,end-origin).abs()
	_marked_trees.clear()
	for tree:Dictionary in _tree_candidates:
		var point:=Geometry.point(tree.position)+Vector3.UP*0.9
		if not camera.is_position_in_frustum(point):continue
		if _tree_rectangle.has_point(camera.unproject_position(point)):_marked_trees.append(str(tree.id))
	if _marked_trees.size()>24:
		var at:=Geometry.point(runtime.actor("player"))
		_marked_trees.sort_custom(func(a:String,b:String)->bool:return _tree_distance(a,at)<_tree_distance(b,at))
		_marked_trees.resize(24)
	_tree_overlay.queue_redraw()

func _draw_tree_selection()->void:
	if _tree_dragging or not _marked_trees.is_empty():
		_tree_overlay.draw_rect(_tree_rectangle,Color(0.91,0.34,0.24,0.12))
		_tree_overlay.draw_rect(_tree_rectangle,Color(0.98,0.57,0.40,0.9),false,1.5)
	for id:String in _marked_trees:
		var tree:Dictionary=world.entity(id)
		if tree.is_empty():continue
		var point:=camera.unproject_position(Geometry.point(tree.position)+Vector3.UP*0.9)
		for diagonal:Vector2 in [Vector2(7,7),Vector2(7,-7)]:
			_tree_overlay.draw_line(point-diagonal,point+diagonal,Color(0.15,0.04,0.03),5,true)
			_tree_overlay.draw_line(point-diagonal,point+diagonal,Color(1.0,0.32,0.20),2.5,true)

func _clear_tree_selection()->void:
	_tree_drag=null
	_tree_dragging=false
	_tree_candidates.clear()
	_marked_trees.clear()
	_tree_rectangle=Rect2()
	if is_instance_valid(_tree_overlay):_tree_overlay.queue_redraw()
	if is_instance_valid(_tree_confirm):_tree_confirm.hide()

func _show_tree_confirm(label:String)->void:
	_tree_confirm.text=label
	_tree_confirm.size=Vector2(152,42)
	var extent:=get_viewport().get_visible_rect().size
	var x:float=_tree_rectangle.get_center().x-76 if not _tree_rectangle.size.is_zero_approx() else extent.x*0.5-76
	var y:float=_tree_rectangle.end.y+10 if not _tree_rectangle.size.is_zero_approx() else 84.0
	_tree_confirm.position=Vector2(clampf(x,8,maxf(8,extent.x-160)),clampf(y,8,maxf(8,extent.y-128)))
	_tree_confirm.show()

func _tree_distance(id:String,at:Vector3)->float:
	var tree:Dictionary=world.entity(id)
	return INF if tree.is_empty() else at.distance_squared_to(Geometry.point(tree.position))

func _confirm_tree_batch()->void:
	if _tree_batch_paused and _marked_trees.is_empty():
		_tree_batch_paused=false
		_tree_confirm.hide()
		return
	if _marked_trees.is_empty() or router.is_paused():return
	if _tool_id("chopping").is_empty():
		ui.notify("背包里需要一把斧头",true)
		return
	_stop_tree_batch(false,false)
	_tree_queue.assign(_marked_trees)
	_clear_tree_selection()
	_tree_batch_wait=0.0
	ui.notify("已安排砍伐 %d 棵树" % _tree_queue.size())

func _stop_tree_batch(completed:bool,announce:bool=true)->void:
	if not completed and not _tree_batch_target.is_empty():
		var active:Variant=runtime.actor("player").get("intent")
		if active is Dictionary and active.get("request",{}).get("target_id")==_tree_batch_target:router.request("cancel")
	if announce:
		var status:="采伐完成" if completed else "已停止批量采伐"
		if completed:status+=" · 已砍 %d 棵 · 跳过 %d 棵" % [_tree_batch_done,_tree_batch_skipped]
		ui.notify(status)
	_tree_queue.clear()
	_tree_batch_target=""
	_tree_batch_done=0
	_tree_batch_skipped=0
	_tree_batch_paused=false
	if is_instance_valid(_tree_confirm) and _marked_trees.is_empty():_tree_confirm.hide()

func _advance_tree_batch()->void:
	if runtime.expedition_in_combat() or router.combat_ready():
		_stop_tree_batch(false)
		return
	var actor:Dictionary=runtime.actor("player")
	var intent:Variant=actor.get("intent")
	if not _tree_batch_target.is_empty():
		if intent is Dictionary and intent.get("request",{}).get("target_id")==_tree_batch_target:
			if not str(actor.get("activity", "")).contains("体力或工具耐久不足"):return
			router.request("cancel")
			_tree_queue.push_front(_tree_batch_target)
			_tree_batch_target=""
			return
		var finished:Dictionary=world.entity(_tree_batch_target)
		if finished.get("data",{}).get("harvest",{}).get("phase")=="stump":_tree_batch_done+=1
		else:_tree_batch_skipped+=1
		_tree_batch_target=""
	if _tree_queue.is_empty():
		_stop_tree_batch(true)
		return
	if intent!=null:return
	if _tree_batch_paused:
		if not _tree_confirm.visible:_show_tree_confirm("继续砍伐")
		return
	if float(actor.get("stamina",0))<8.0:return
	var payload:=_harvest_payload(true)
	var production:Variant=runtime.domain_service("production")
	if payload.tool_id.is_empty() or (payload.pickup_yield and production!=null and not production.capacity_check("pack:player",{"log":1}).ok):
		_tree_batch_paused=true
		_show_tree_confirm("继续砍伐")
		ui.notify("需要一把可用的斧头" if payload.tool_id.is_empty() else "背包已满，采伐暂停",true)
		return
	var at:=Geometry.point(actor)
	_tree_queue.sort_custom(func(a:String,b:String)->bool:return _tree_distance(a,at)<_tree_distance(b,at))
	var id:String=_tree_queue.pop_front()
	var tree:Dictionary=world.entity(id)
	if tree.get("data",{}).get("harvest",{}).get("phase")!="standing" or not router.request("harvest",id,payload).ok:
		_tree_batch_skipped+=1
		if _tree_queue.is_empty():_stop_tree_batch(true)
	else:_tree_batch_target=id

func set_view_hint_renderer(enabled:bool)->void:
	# Presentation may replace the fallback box, never its authority checks.
	_view_hint_renderer=enabled
	if enabled and is_instance_valid(_ghost):_ghost.visible=false

func view_hints()->Dictionary:
	var result:Dictionary={"schema":"afterglow-world-view-hints-v1","world_id":"","world_revision":-1,"selected":{},"placement":{}}
	if runtime==null or world==null or runtime.is_retired():return result
	result.world_id=str(world.identity().get("worldId",""));result.world_revision=world.get_revision()
	# The UI supplies an identity only. Discovery, geometry and visibility are
	# resolved again here; a consumer cannot draw an unknown object's bounds.
	if ui!=null and is_instance_valid(ui) and ui.has_method("world_view_selection"):
		var selected:Variant=ui.call("world_view_selection")
		if selected is Dictionary:result.selected=_selected_view_hint(selected)
	if router!=null and router.mode()=="module_place" and _placement_view_hint.get("world_revision") == world.get_revision():
		result.placement=_placement_view_hint.duplicate(true)
	return result

func _selected_view_hint(selection:Dictionary)->Dictionary:
	var id:String=str(selection.get("id",""));var kind:String=str(selection.get("kind",""))
	if id.is_empty():return {}
	var entity:Dictionary={}
	if kind=="module":
		if modules==null:return {}
		var method:String="visual_projection" if modules.has_method("visual_projection") else "projection"
		var public:Dictionary=modules.call(method,"player",id)
		if not public.get("instances",[]).any(func(row:Dictionary)->bool:return row.get("id")==id):return {}
		entity=world.entity(id)
	elif kind=="water":
		var public:Dictionary=runtime.water_snapshot("player",id)
		if not public.get("sources",[]).any(func(row:Dictionary)->bool:return row.get("id")==id):return {}
		entity=world.entity(id)
	elif kind=="raw_water_source":
		entity=world.entity(id)
		if not _chapter_well(entity):return {}
	elif kind=="npc":
		var public:Dictionary=runtime.actor_presentation()
		if not public.get("visible_actor_ids",[]).has(id):return {}
		var actor:Dictionary=runtime.actor(id)
		if actor.is_empty():return {}
		var box:=AABB(Geometry.point(Geometry.location(actor))-Vector3(0.3,0,0.3),Vector3(0.6,1.8,0.6))
		entity={"id":id,"regionId":actor.regionId,"bounds":Geometry.json_box(box)}
	elif kind=="container":
		# Only the same searched/authorised read model used by the inventory.
		var public:Dictionary=runtime.snapshot()
		if not public.get("stocks",[]).any(func(row:Dictionary)->bool:return row.get("id")==id):return {}
		entity=world.entity(id)
	else:return {}
	if entity.is_empty() or not entity.get("bounds") is Dictionary:return {}
	var region_id:String=str(entity.get("regionId",""))
	if not runtime.region_is_detailed(region_id):return {}
	if kind!="npc" and view_policy!=null:
		# A complete outdoor module is an exterior shell. Testing sight to its
		# centre hits its own real walls and incorrectly hides the selection.
		# Match the existing shell scope; D keeps depth testing for occlusion.
		# Contents and ordinary furniture retain the stricter room/LOS policy.
		var data:Dictionary=entity.get("data",{})
		var exterior:bool=kind=="module" and data.get("module_target",false) and data.get("module_id")==id and entity.get("buildingId")==null and entity.get("storeyId")==null
		if exterior and view_policy.has_method("base_visible"):
			if not view_policy.base_visible(entity,"object"):return {}
		elif view_policy.has_method("can_observe_geometry") and not view_policy.can_observe_geometry(entity,runtime.actor("player")):return {}
	var bounds:AABB=Geometry.aabb(entity.bounds)
	return {"id":id,"kind":kind,"bounds":entity.bounds.duplicate(true),"region_id":region_id,"visible":camera!=null and camera.is_position_in_frustum(bounds.get_center())}

func _process(delta: float) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("input/direct_interaction.gd",measured)

func _profiled_process(delta: float) -> void:
	_drain_swing_buffer()
	if not router.is_paused() and (not _tree_queue.is_empty() or not _tree_batch_target.is_empty()):
		_tree_batch_wait-=delta
		if _tree_batch_wait<=0:
			_tree_batch_wait=0.12
			_advance_tree_batch()
	_pickup_delay-=delta
	if _pickup_delay<=0 and not router.is_paused():
		_pickup_delay=0.5
		if _interaction_state().get("auto_pickup",false):_auto_collect()
	_delay-=delta
	if _delay <= 0 and not router.is_paused():
		# Pointer actions and held work still refresh immediately.
		var poll_now: bool = _holding_primary or router.is_placement() or not runtime.has_method("reserve_periodic_display_frame")
		if not poll_now:
			poll_now = runtime.reserve_periodic_display_frame() or _hover_deferred
		_hover_deferred = not poll_now
		if poll_now:
			_delay = 0.1
			_refresh()
		# A completed cell releases its intent. Re-pick the real next surface,
		# then submit ONE new transaction; never replay a completed payload.
		if poll_now and _holding_primary and _held_kind=="terrain" and runtime.actor("player").get("intent")==null and _target.get("primary")=="terrain" and _target.get("enabled",false) and router.mode()!="terrain_fill":
			var key:=_work_key()
			if key!=_blocked_work_key:_perform_primary()
	if not _pending_container.is_empty():
		var s:Dictionary=runtime.stock(_pending_container)
		if s.get("searched",false):
			ui.open_panel("container",_pending_container);_pending_container=""
		elif runtime.actor("player").get("intent")==null:_pending_container=""

func _move(direction: Vector2,delta: float) -> void:
	if not _tree_queue.is_empty() or not _tree_batch_target.is_empty():_stop_tree_batch(false)
	var p:Dictionary=runtime.actor("player")
	var right:Vector3=camera.global_basis.x;right.y=0;right=right.normalized()
	var down:Vector3=camera.global_basis.z;down.y=0;down=down.normalized()
	var dt:float=minf(delta,0.1)
	var requested:String="run" if router.run_held() else "walk"
	var budget:Dictionary=runtime.movement_budget("player",dt,requested)
	if not budget.ok or float(budget.max_distance)<=0.000001:return
	var payload:Dictionary={"movement_dt":dt,"movement_mode":requested}
	var step:Vector3=(right*direction.x+down*direction.y).normalized()*float(budget.max_distance)
	var to:=Geometry.location(p);to.x+=step.x;to.z+=step.z
	var result:Dictionary=router.request("direct_move","",payload,to)
	# Project the attempted step onto each wall axis. B validates every
	# candidate with the same swept body/support/door/region rules.
	if not result.ok and result.get("code") in ["BLOCKED","UNSUPPORTED"] and absf(step.x)>0.00001 and absf(step.z)>0.00001:
		var axes:Array=[Vector3(step.x,0,0),Vector3(0,0,step.z)]
		if absf(step.z)>absf(step.x):axes.reverse()
		for axis:Vector3 in axes:
			var slide:=Geometry.location(p);slide.x+=axis.x;slide.z+=axis.z
			result=router.request("direct_move","",payload,slide)
			if result.ok:break
	var problem:String="" if result.ok else str(result.get("code"))+":"+str(result.get("reason"))
	if problem!=_move_problem:
		_move_problem=problem
		if ui.has_method("report_movement"):ui.report_movement(result)
		elif not result.ok:_feedback(result)

func _interaction_state() -> Dictionary:
	return router.interaction_state() if router.has_method("interaction_state") else router.state()

func _refresh() -> void:
	_refresh_at(get_viewport().get_mouse_position())

func _pick_terrain(origin: Vector3, direction: Vector3) -> Dictionary:
	# Reuse the exact ray only while its world revision and world generation
	# agree. Interaction availability and the final command are still live.
	if not world.has_method("extension_token"):
		return terrain.pick(origin, origin + direction * 160.0)
	var basis := [world.get_revision(), world.extension_token(""), origin, direction]
	if basis != _terrain_pick_basis:
		_terrain_pick_basis = basis
		_terrain_pick_hit = terrain.pick(origin, origin + direction * 160.0)
	return _terrain_pick_hit.duplicate(true)

func _refresh_at(mouse:Vector2) -> void:
	if runtime.is_retired():return
	if router.is_paused():return
	_picked_screen=mouse
	if router.mode()=="tool" and runtime.expedition_in_combat():
		_target={}
		_exact_target={}
		_publish_target({})
		_pointed_person = ""
		return
	var origin:Vector3=camera.project_ray_origin(mouse)
	var direction:Vector3=camera.project_ray_normal(mouse)
	if router.is_placement():
		if not _placement_locked():
			_point = _pick_terrain(origin, direction)
		_update_preview(router.held_reference(),origin,direction)
		return
	var hit: Dictionary = _pick_terrain(origin, direction)
	var nearest:float=float(hit.get("distance",160.0))
	_point=hit
	var picked:Dictionary={}
	var p:Dictionary=runtime.actor("player")
	# Exact broad phase: only boxes intersecting the ray before terrain or
	# the existing 2.8m nearby volume can ever win the original selection.
	var end:Vector3=origin+direction*nearest
	var ray:AABB=AABB(origin.min(end),origin.max(end)-origin.min(end)).grow(.001)
	var local:AABB=AABB(Geometry.point(p)-Vector3.ONE*2.8,Vector3.ONE*5.6)
	_entities=world.entities_in_any_bounds([Geometry.json_box(ray),Geometry.json_box(local)]);_entity_revision=world.get_revision()
	if view_policy!=null:view_policy.sample(p)
	for e:Dictionary in _entities:
		if not _scene_entity(e):continue
		var piece:Dictionary=buildings.instance(str(e.id)) if e.kind=="structure" else {}
		var boxes:Array=_pick_boxes(piece) if not piece.is_empty() else [Geometry.aabb(e.bounds)]
		for box:AABB in boxes:
			var at:Variant=box.intersects_ray(origin,direction)
			if at!=null and origin.distance_to(at)<nearest:nearest=origin.distance_to(at);picked=e
	var presentation: Dictionary = runtime.actor_pick_snapshot() if runtime.has_method("actor_pick_snapshot") else runtime.actor_presentation()
	if is_instance_valid(ui) and ui.has_method("observe_companion_selection"):ui.observe_companion_selection(presentation.visible_actor_ids)
	for a:Dictionary in presentation.actors:
		if a.id=="player" or a.id not in presentation.visible_actor_ids or float(a.get("hp",0.0))<=0.0:continue
		var at:Variant=AABB(Vector3(a.x-0.3,a.y,a.z-0.3),Vector3(0.6,1.8,0.6)).intersects_ray(origin,direction)
		if at!=null and origin.distance_to(at)<nearest:nearest=origin.distance_to(at);picked={"id":"npc:"+str(a.id),"kind":"npc","actor":a,"position":{"x":a.x,"y":a.y,"z":a.z}}
	_pointed_person=""
	if picked.get("kind")=="npc" and picked.actor.get("faction")!="infected" and float(picked.actor.get("hp",0))>0:_pointed_person=str(picked.actor.id)
	_target=_describe(picked)
	if router.combat_ready() and not runtime.expedition_in_combat():
		if _target.get("primary")=="combat":
			_target.focus_source="pointer"
			var anchor:Vector2=camera.unproject_position(Geometry.point(_target.location)+Vector3.UP)
			_target.projected_position={"x":anchor.x,"y":anchor.y}
		else:
			_target={"kind":"combat_aim","primary":"combat_aim","name":"战备","hint":"左键挥击 · 指向敌人以瞄准","enabled":true}
		_exact_target={}
		_publish_target(_target)
		return
	_exact_target=_target
	if not _exact_target.is_empty() and not picked.is_empty():_exact_target.entity_id=str(picked.id)
	var building_pick:bool=is_instance_valid(ui) and ui.has_method("is_companion_building_pick") and ui.is_companion_building_pick()
	if not _target.is_empty():_target.focus_source="pointer"
	if not building_pick and (_target.is_empty() or _target.get("primary")=="inspect") and router.mode()=="tool":
		var nearby:=_nearby_target(p,presentation,mouse)
		if not nearby.is_empty():
			_target=nearby
			_target.focus_source="nearby"
	_terrain_payload={}
	if _target.is_empty() and not hit.is_empty() and not hit.get("unknown",false):
		var mode:String=router.mode()
		var operation:String=mode.trim_prefix("terrain_") if mode.begins_with("terrain_") else "dig"
		_terrain_payload=terrain_payload(hit,_interaction_state().terrain,operation,float(world.config().cellSize))
		_terrain_payload.merge({"tool_id":_tool_id(),"held":true,"requires_hold":operation!="fill"},true)
		var ready:Dictionary=runtime.availability({"kind":"terrain","actor_id":"player","target_id":hit.target_id,"payload":_terrain_payload})
		_target={"id":hit.target_id,"kind":"terrain","primary":"terrain","name":{"dig":"挖掘","fill":"填土","level":"整平"}[operation],"action":"右键填土" if operation=="fill" else "按住左键作业","enabled":ready.ok,"code":ready.get("code",""),"reason":ready.get("reason"),"cell":hit.cell.duplicate(),"world_revision":hit.world_revision,"edit":_terrain_payload.edit.duplicate(true),"location":Geometry.json_point(origin+direction*nearest)}
		if ready.get("code")=="SITE_CONFIRMATION_REQUIRED" and not str(ready.get("site_id","")).is_empty():
			_target.site_id=ready.site_id;_target.action="E 查看勘察与清障风险"
	if not _target.is_empty():
		var location:Dictionary=_target.get("location",{})
		var anchor:Vector2=camera.unproject_position(Geometry.point(location)+Vector3(0,1,0))
		_target.projected_position={"x":anchor.x,"y":anchor.y}
		var intent:Variant=p.get("intent")
		if intent is Dictionary and intent.get("request",{}).get("target_id",intent.get("target_id"))==_target.id:
			var order:Dictionary={}
			var work:Dictionary=runtime.actor_work_snapshot(str(p.id)) if runtime.has_method("actor_work_snapshot") else {}
			if work.is_empty() and intent.has("order_id"):
				for o in runtime.snapshot().get("orders",[]):
					if o.id==intent.order_id:order=o;break
			var elapsed:float=float(work.get("progress_seconds",order.get("elapsed",intent.get("elapsed",0))))
			var duration:float=float(work.get("duration_seconds",order.get("seconds",intent.get("duration",0))))
			if duration>0:_target.progress=clampf(elapsed/duration,0,1)
	_publish_target(_target)

func _publish_target(target: Dictionary) -> void:
	if target == _published_target: return
	_published_target = target.duplicate(true)
	runtime.set_target(target)
	if is_instance_valid(ui) and ui.has_method("show_world_target"):
		ui.show_world_target(target)

func _pick_boxes(piece:Dictionary)->Array:
	if view_policy!=null and view_policy.has_method("pick_boxes"):return view_policy.pick_boxes(piece)
	var boxes:Array=buildings.geometry.boxes(piece)
	if view_policy==null:return boxes
	var kind:String=buildings.geometry.definition(piece).kind
	if not view_policy.base_visible(piece,kind):return []
	if kind not in ["wall","corner","door","window"] or not view_policy.cut_wall(piece):return boxes
	# Match B's visible 0.65m wall cap; hidden upper wall is not pickable.
	var clipped:Array=[]
	var top:float=float(piece.position.y)+0.65
	for box:AABB in boxes:
		if box.position.y>=top:continue
		box.size.y=minf(box.end.y,top)-box.position.y
		if box.size.y>0:clipped.append(box)
	return clipped

func _nearby_target(player:Dictionary,presentation:Dictionary,mouse:Vector2)->Dictionary:
	var candidates:Array=[]
	var feet:=Geometry.point(player)
	for e:Dictionary in _entities:
		var box:=Geometry.aabb(e.bounds)
		var closest:Vector3=feet.max(box.position).min(box.end)
		if feet.distance_to(closest)>2.8 or not _scene_entity(e):continue
		var candidate:=_describe(e)
		if candidate.get("enabled",false) and candidate.primary in ["door","container","pickup","workbench","rest","harvest","module","module_discover","water","water_discover"]:candidates.append(candidate)
	for a:Dictionary in presentation.actors:
		if a.id=="player" or a.id not in presentation.visible_actor_ids or feet.distance_to(Geometry.point(a))>2.8:continue
		var candidate:=_describe({"id":"npc:"+str(a.id),"kind":"npc","actor":a})
		if candidate.get("enabled",false) and candidate.primary=="npc":candidates.append(candidate)
	# Cursor distance is a preference, not a requirement to hit a thin trunk.
	# Only domain-approved candidates enter the list, so this grants no reach.
	if candidates.is_empty(): return {}
	var armed: bool = not _tool_id().is_empty()
	# Calculate each score once, with the same comparator and candidate order.
	var scores: Array = []
	for candidate: Dictionary in candidates:
		scores.append({"target": candidate, "score": _nearby_score(candidate, feet, mouse, armed)})
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	return scores[0].target

func _scene_entity(entity:Dictionary)->bool:
	# Solid scenery still participates in B's collision/LOS/support checks,
	# but a well/fence/car without an action is not an invisible container.
	if entity.get("data",{}).get("no_interaction",false):return false
	# C reserves an empty drop container beside each still-standing tree.
	# Its invisible future pile must not steal the axe's nearby target.
	if entity.kind=="container" and entity.get("data",{}).get("dropped",false):
		var source:Dictionary=world.entity(str(entity.data.get("sourceId","")))
		if source.get("kind")=="tree":
			return runtime.stock(str(entity.id)).get("items",{}).values().any(func(value:Variant)->bool:return float(value)>0)
	return true

func _nearby_score(candidate:Dictionary,feet:Vector3,mouse:Vector2,armed:bool)->float:
	var at:=Geometry.point(candidate.location)
	var screen:=camera.unproject_position(at+Vector3(0,0.8,0))
	var score:float=feet.distance_to(at)+minf(screen.distance_to(mouse)/160.0,2.0)
	if candidate.primary=="harvest" and armed:score-=0.8
	return score

static func terrain_payload(hit:Dictionary,brush:Dictionary,operation:String,size:float) -> Dictionary:
	var cell:Dictionary=hit.get("cell",{}).duplicate()
	var width:int=clampi(int(brush.get("brush_cells",1)),1,2)
	var normal:Vector3=hit.get("normal",Vector3.UP)
	if operation=="fill":
		cell.x=int(cell.x)+roundi(normal.x);cell.y=int(cell.y)+roundi(normal.y);cell.z=int(cell.z)+roundi(normal.z)
	var cells:Array=[]
	for u:int in width:
		for v:int in width:
			var c:Dictionary=cell.duplicate()
			if absf(normal.x)>0.5:c.y=int(c.y)+u;c.z=int(c.z)+v
			elif absf(normal.z)>0.5:c.x=int(c.x)+u;c.y=int(c.y)+v
			else:c.x=int(c.x)+u;c.z=int(c.z)+v
			cells.append(c)
	var edit:Dictionary={"operation":operation,"material":int(brush.get("material",2)),"cells":cells}
	if operation=="level":
		edit.area={"minI":int(cell.x),"maxI":int(cell.x)+width,"minK":int(cell.z),"maxK":int(cell.z)+width}
		edit.height=float(brush.get("height",(float(cell.y)+1)*size))
	return {"edit":edit}

func _chapter_well(e:Dictionary)->bool:
	if e.get("kind")!="raw_water_source" or not e.get("data",{}).has("raw_water_source"):return false
	var fields:Array[String]=["content_version"]
	var generation:Variant=world.extension_fields("generation:factory-r34",fields) if world.has_method("extension_fields") else world.extension("generation:factory-r34")
	return generation is Dictionary and int(generation.get("content_version",0))>=20

func _describe(e: Dictionary) -> Dictionary:
	if e.is_empty():return {}
	var id:=str(e.id)
	var water_id:String=str(e.get("data",{}).get("water_source_id",""))
	if not water_id.is_empty():
		var water:Dictionary=runtime.water_snapshot("player", water_id, true)
		if water.get("sources",[]).is_empty():
			var ready:Dictionary=runtime.availability({"actor_id":"player","kind":"module.water.discover","target_id":water_id,"payload":{}})
			var location:Dictionary=e.get("position",{}).duplicate(true);location.regionId=e.get("regionId","")
			return {"id":water_id,"kind":"water","primary":"water_discover","name":"未查看的储水设施","action":"查看设施","enabled":ready.get("ok",false),"code":ready.get("code",""),"reason":ready.get("reason","走近装置查看"),"location":location}
		var source:Dictionary=water.sources[0]
		return {"id":water_id,"kind":"water","primary":"water","name":"应急储水设施","action":"查看与取水","enabled":true,"reason":"修复和取水必须到现场，储水有限","location":source.location.duplicate(true)}
	if _chapter_well(e):
		# The actual draw command checks the bucket, output room and route once on use.
		return {"id":id,"kind":"raw_water_source","primary":"draw_water","name":"水井","action":"打原水","enabled":true,"location":Geometry.location(e)}
	if e.get("data",{}).get("module_target",false):
		if modules==null:return {}
		var instance: Dictionary
		if modules.has_method("interaction_label"):
			instance = modules.interaction_label("player", id)
		else:
			var method := "visual_projection" if modules.has_method("visual_projection") else "projection"
			var rows: Array = modules.call(method, "player", id).get("instances", [])
			instance = {} if rows.is_empty() else rows[0]
		if instance.is_empty():
			# A visible shell is selectable without exposing its hidden inventory
			# or granting remote management. B alone validates first contact.
			var ready:Dictionary=runtime.availability({"actor_id":"player","kind":"module.discover","target_id":id,"payload":{}})
			var location:Dictionary=e.get("position",{}).duplicate(true)
			location.regionId=e.get("regionId","")
			return {"id":id,"kind":"module","primary":"module_discover","name":"未查看的地点","action":"查看地点","enabled":ready.get("ok",false),"code":ready.get("code",""),"reason":ready.get("reason","靠近建筑查看"),"location":location}
		return {"id":id,"kind":"module","primary":"module","name":instance.get("name","功能模块"),"action":"查看与管理","enabled":true,"reason":"在建筑附近即可操作，远处会自动靠近","location":instance.location.duplicate(true)}
	if e.kind=="npc":
		var a:Dictionary=e.actor
		if a.get("faction")=="infected":
			if runtime.expedition_in_combat():
				return {"id":a.id,"kind":"npc","primary":"inspect","name":a.name,"action":"自动攻击","enabled":false,"reason":"进入武器射程后自动攻击","location":Geometry.location(a)}
			var combat:Dictionary=runtime.availability({"kind":"attack","actor_id":"player","target_id":a.id,"payload":{"tool_id":_tool_id(),"manual_aim":true}})
			return {"id":a.id,"kind":"npc","primary":"combat","name":a.name+" · "+str(ceili(float(a.hp)))+" HP","hint":("左键挥击" if router.combat_ready() else "右键进入战备 · 左键挥击"),"enabled":combat.ok,"reason":combat.get("reason"),"location":Geometry.location(a)}
		var relation:Dictionary=a.get("relationship",{})
		var member:bool=relation.get("member",false) and relation.get("consent",false) and float(a.get("hp",0))>0
		var ready:Dictionary={"ok":true} if member else runtime.availability({"kind":"talk","actor_id":"player","target_id":a.id})
		return {"id":a.id,"kind":"npc","primary":"npc","name":a.name,"action":"安排工作" if member else "交谈","enabled":ready.ok,"reason":ready.get("reason"),"location":Geometry.location(a)}
	var piece:Dictionary=buildings.instance(id) if e.kind=="structure" else {}
	var d:Dictionary=buildings.geometry.definition(piece) if not piece.is_empty() else {}
	var stock:Dictionary=runtime.stock(id)
	var primary:="door" if d.get("kind")=="door" else "workbench" if d.get("kind")=="workbench" else "container" if not stock.is_empty() else "rest" if e.data.get("sleeping",false) else "harvest" if e.kind=="tree" else "inspect"
	var location:Dictionary=Geometry.location(e)
	var ready:Dictionary={"ok":false,"reason":"使用手持工具进行作业"}
	var action:="使用工具"
	if primary=="door":
		# Hover may permit an attempt, never grant a prepared door capability.
		# E still goes through router.request and current full authority checks.
		ready=buildings.door_preview({"kind":"door","actor_id":"player","target_id":id,"payload":{"direct":true}})
		action="关门" if piece.door.open else "开门"
		if ready.get("proof_state")=="pending":
			action="尝试"+action;ready.reason="提交时验证通路与安全"
	elif primary=="container":
		if not stock.get("searched",false):
			ready=runtime.availability({"kind":"search","actor_id":"player","target_id":id,"payload":{"direct":not stock.has("module_id")}})
		else:
			var problem:Variant=buildings.can_use("player",piece if not piece.is_empty() else {},{} if not piece.is_empty() else location)
			ready={"ok":problem==null,"reason":problem}
		action="打开容器" if stock.get("searched",false) else "搜索"
		if e.data.get("dropped",false) and stock.get("searched",false):
			primary="pickup";action="拾取地面物资"
			if not stock.get("items",{}).values().any(func(n:Variant)->bool:return float(n)>0):ready={"ok":false,"reason":"地面物资已拾完"}
	elif primary in ["workbench","rest"]:
		var problem:Variant=buildings.can_use("player",piece if not piece.is_empty() else {},{} if not piece.is_empty() else location)
		ready={"ok":problem==null,"reason":problem};action="制作" if primary=="workbench" else "休息" if e.data.get("prepared",false) else "铺设寝具 · 需要布料2"
	elif primary=="harvest":
		var request:Dictionary={"kind":"harvest","actor_id":"player","target_id":id,"payload":_harvest_payload(false)}
		ready=runtime.availability(request);action="左键采伐"
		var active:Variant=runtime.actor("player").get("intent")
		if ready.get("code")=="BUSY" and active is Dictionary and active.get("kind")=="harvest" and active.get("request",{}).get("target_id")==id and (not active.request.get("payload",{}).get("requires_hold",false) or _matches_held_work({"id":id,"primary":"harvest"})):
			ready={"ok":true,"active_work":true}
			ready.work_paused=not active.get("held",true)
			action="左键继续采伐" if ready.work_paused else "采伐中"
			ready.reason="离开范围停止采伐"
	var mode:String=router.mode()
	if not piece.is_empty() and mode in ["repair","demolish","destroy","move"]:
		var operation:String={"demolish":"remove","destroy":"damage"}.get(mode,mode)
		if mode!="move":ready=runtime.availability({"kind":"structure","actor_id":"player","target_id":id,"payload":{"kind":operation,"tool_id":_tool_id("hammering"),"source_id":"pack:player","output_id":"pack:player","direct":true,"held":true,"requires_hold":true}})
		action={"repair":"按住左键维修","demolish":"按住左键拆卸","destroy":"按住左键破坏","move":"左键选取 · 再选目的地"}[mode]
	var target:Dictionary={"id":id,"kind":e.kind,"primary":primary,"name":d.get("name","树木" if primary=="harvest" else "休息点" if primary=="rest" else "物资容器"),"action":action,"enabled":ready.get("ok",false),"code":ready.get("code",""),"reason":ready.get("reason"),"location":location}
	if primary == "harvest":target.hint = "左键采伐 · 右键拖框"
	if ready.get("active_work",false):
		target.active_work=true;target.work_paused=ready.work_paused
	if primary=="door" and mode not in ["repair","demolish","destroy","move"]:
		for key:String in ["proof_state","target_version","world_revision","operation"]:
			if ready.has(key):target[key]=ready[key]
	return target

func _interact() -> void:
	if router.is_placement(): return
	if router.combat_ready():
		ui.notify("战备中 · 左键挥击 · Esc退出")
		return
	if router.mode()=="tool":
		var run: Dictionary = runtime.expedition_snapshot()
		if run.get("phase") in ["idle", "approach"] and run.get("near_site",false):
			_feedback(router.request("expedition.open", ""))
			return
		if run.get("phase") == "retreat" and run.get("near_exit",false):
			_feedback(router.request("expedition.extract", ""))
			return
	var selected:Dictionary=ui.world_view_selection() if ui.has_method("world_view_selection") else {}
	if router.mode()=="tool" and selected.get("kind")=="module":
		var target:Dictionary=modules.instance(str(selected.id)) if modules!=null else {}
		if target.get("discovered",false):
			ui.open_panel("factory_module",str(selected.id))
			return
	_refresh()
	if _target.get("code")=="SITE_CONFIRMATION_REQUIRED" and not str(_target.get("site_id","")).is_empty():
		ui.open_panel("factory_alerts",str(_target.site_id));return
	if _target.get("primary")=="terrain" and router.mode()=="terrain_level":
		var brush:Dictionary=router.state().terrain
		_feedback(router.set_terrain_brush("level",int(brush.material),(float(_point.cell.y)+1)*float(world.config().cellSize),int(brush.brush_cells)));return
	if _target.is_empty():ui.notify("附近没有可用目标",true);return
	if not _target.get("enabled",false):ui.notify(str(_target.get("reason","当前不可用")),true);return
	match str(_target.primary):
		"pickup":_collect(str(_target.id))
		"container":
			if runtime.stock(_target.id).get("searched",false):ui.open_panel("container",_target.id)
			else:
				var result:Dictionary=router.request("search",_target.id,{"direct":not runtime.stock(_target.id).has("module_id")})
				_feedback(result)
				if result.ok:_pending_container=_target.id
		"npc":
			if not ui.has_method("point_companion") or not ui.point_companion(str(_target.id)):ui.open_panel("npc",_target.id)
		"workbench","module","water":ui.open_panel(_target.primary,_target.id)
		"draw_water":
			var result:Dictionary=router.request("zonework.draw_water",_target.id)
			_feedback(result)
			if result.get("ok",false):ui.notify("已安排打水")
		"water_discover":
			var result:Dictionary=router.request("module.water.discover",_target.id)
			_feedback(result)
			if result.ok:ui.open_panel("water",_target.id)
		"module_discover":
			var result:Dictionary=router.request("module.discover",_target.id)
			_feedback(result)
			if result.ok:ui.open_panel("module",_target.id)
		"door":_feedback(router.request("door",_target.id,{"direct":true}))
		"rest":
			var prepared:bool=world.entity(_target.id).get("data",{}).get("prepared",false)
			_feedback(router.request("rest" if prepared else "prepare_bed",_target.id,{"direct":true,"source_id":"pack:player","held":true}))

func _collect(id:String,automatic:bool=false)->bool:
	var result:Dictionary=router.request("pickup",id,{"automatic":automatic})
	if result.ok:
		for event:Dictionary in result.get("changes",{}).get("events",[]):
			if event.get("kind")=="inventory-transfer":_notify_pickup(event.get("items",{}),false)
	elif not automatic:_feedback(result)
	return result.ok

func _notify_pickup(items:Dictionary,left:bool)->void:
	var text:Array[String]=[]
	if not items.is_empty() and ui.has_method("show_pickup"):ui.show_pickup(items)
	for item:String in items:
		text.append("%s +%s"%[preload("res://scripts/runtime/content_definitions.gd").item_definition(item).get("name",item),str(items[item])])
	if left:text.append("背包空间不足，剩余原木留在地上")
	if not text.is_empty():ui.notify(" · ".join(text),left)

func _harvest_feedback(changes:Dictionary)->void:
	for event:Dictionary in changes.get("events",[]):
		if event.get("kind")=="player-harvest-pickup":_notify_pickup.call_deferred(event.items,event.left)

func _auto_collect()->void:
	var actor:Dictionary=runtime.actor("player")
	if float(actor.get("hp",0))<=0:return
	var box:AABB=AABB(Geometry.point(actor)-Vector3(1.8,1.8,1.8),Vector3(3.6,3.6,3.6))
	var attempts:=0
	for entity:Dictionary in world.entities_in_any_bounds([Geometry.json_box(box)]):
		if entity.get("kind")!="container" or not entity.get("data",{}).get("dropped",false):continue
		var stock:Dictionary=runtime.stock(str(entity.id))
		if stock.get("owner")!=null or Geometry.point(actor).distance_to(Geometry.point(Geometry.location(stock)))>1.8:continue
		if not stock.get("items",{}).keys().any(func(item:Variant)->bool:return item in Actions.AUTO_PICKUP_ITEMS and float(stock.items[item])>0):continue
		attempts+=1
		if _collect(str(entity.id),true) or attempts>=8:return

func _tool_id(quality: String="") -> String:
	var ref:Dictionary=router.held_reference()
	var selected_id:String=str(ref.get("id",ref.get("tool_id",""))) if ref.get("kind")=="tool" else ""
	if quality.is_empty():return selected_id
	var display:Dictionary=runtime.hud_snapshot() if runtime.has_method("hud_snapshot") else runtime.snapshot()
	var catalog:Dictionary=display.catalog.get("tool_definitions",{})
	var fallback:String=""
	for t:Dictionary in display.tools:
		var qualities:Dictionary=t.get("qualities",catalog.get(t.get("kind"),{}).get("qualities",{}))
		if t.get("holderId")!="pack:player" or float(t.durability)<=0 or float(qualities.get(quality,0))<=0:continue
		if str(t.id)==selected_id:return selected_id
		if fallback.is_empty():fallback=str(t.id)
	return fallback

func _primary(pressed: bool) -> void:
	var mouse:Variant=_press_screen;_press_screen=null
	_holding_primary=pressed
	if not pressed:
		_held_kind=""
		if runtime!=null:
			var active:Variant=runtime.actor("player").get("intent")
			if active is Dictionary and active.get("owner") in ["actions","terrain"] and active.get("request",{}).get("payload",{}).get("requires_hold",false) and active.get("held",true):router.request("held","",{"held":false})
		return
	_blocked_work_key=""
	if _tree_drag!=null:
		var dragging:=_tree_dragging
		_clear_tree_selection()
		if dragging:return
		router.begin_world_combat_hold()
	if mouse is Vector2:_refresh_at(mouse)
	else:_refresh()
	if router.is_placement():
		_holding_primary=false
		_held_kind=""
		if _preview.is_empty():return
		if not _placement_locked():
			if _preview.has("module_id"):
				_fixed_build_position = _preview.payload.position.duplicate(true)
			elif not _structure_candidate_location.is_empty():
				_fixed_structure_location = _structure_candidate_location.duplicate(true)
			_refresh()
		return
	if router.mode()=="tool" and runtime.expedition_in_combat():
		_holding_primary = false
		return
	if router.combat_ready():
		_holding_primary=false
		_held_kind=""
		var target_id:String=str(_target.get("id","")) if _target.get("primary")=="combat" else ""
		var payload:Dictionary={"tool_id":_tool_id(),"manual_aim":true}
		if _point.has("distance") and not _point.get("unknown",false):
			var screen:Vector2=mouse if mouse is Vector2 else get_viewport().get_mouse_position()
			var point:Vector3=camera.project_ray_origin(screen)+camera.project_ray_normal(screen)*float(_point.distance)
			payload.aim=Geometry.json_point(point)
		_attempt_swing(target_id, payload)
		return
	if router.mode()=="tool" and is_instance_valid(ui) and ui.has_method("point_companion_building") and ui.point_companion_building(_exact_target):
		_holding_primary=false;_held_kind=""
		return
	if router.mode()=="tool" and not _pointed_person.is_empty() and is_instance_valid(ui) and ui.has_method("point_companion") and ui.point_companion(_pointed_person):
		_holding_primary=false;_held_kind=""
		return
	if is_instance_valid(ui) and ui.has_method("close_companion_card_for_world_input") and ui.close_companion_card_for_world_input():
		_holding_primary = false
		_held_kind = ""
		return
	if router.mode()=="tool" and is_instance_valid(ui) and ui.has_method("select_scene_target"):
		if _exact_target.get("primary") in ["module","module_discover","water","water_discover","draw_water","container"]:
			ui.select_scene_target(_exact_target)
			_holding_primary=false;_held_kind=""
			return
		var selection:Dictionary=ui.world_view_selection()
		if selection.has("entity_id"):
			ui.select_scene_target({})
			if _exact_target.is_empty():_holding_primary=false;_held_kind="";return
	_held_kind=str(_target.get("primary",""))
	_perform_primary()

func _attempt_swing(target_id: String, payload: Dictionary) -> void:
	var result: Dictionary = router.request("attack", target_id, payload)
	if result.get("code") == "COOLDOWN" and float(runtime.actor("player").get("cooldown", 0.0)) <= SWING_BUFFER_SECONDS:
		# Keep the first late-recovery edge and its original target and tool.
		if _buffered_swing.is_empty():
			_buffered_swing = {"target_id": target_id, "payload": payload, "expires_at": runtime.clock() + SWING_BUFFER_SECONDS + 0.1}
		return
	_feedback(result)

func _drain_swing_buffer() -> void:
	if _buffered_swing.is_empty(): return
	if router.is_paused() or not router.combat_ready() or runtime.expedition_in_combat() or runtime.clock() > _buffered_swing.expires_at:
		_buffered_swing.clear()
		return
	if float(runtime.actor("player").get("cooldown", 0.0)) > 0.0: return
	var pending := _buffered_swing
	_buffered_swing = {}
	_feedback(router.request("attack", pending.target_id, pending.payload))

func _work_key()->String:
	return str([_target.get("id"),world.get_revision(),router.mode(),_tool_id()])

func _matches_held_work(target:Dictionary)->bool:
	var active:Variant=runtime.actor("player").get("intent")
	if not active is Dictionary or active.get("owner") not in ["actions","terrain"]:return false
	var request:Dictionary=active.get("request",{})
	if request.get("target_id")!=target.get("id") or not request.get("payload",{}).get("requires_hold",false):return false
	var tool_id:String=str(request.get("payload",{}).get("tool_id",""))
	if tool_id.is_empty():return true
	var selected:String=_tool_id("hammering" if request.get("kind")=="structure" else "")
	var tool:Dictionary=runtime.tool(tool_id)
	return selected==tool_id and tool.get("holderId")=="pack:player" and float(tool.get("durability",0))>0

func _perform_primary() -> void:
	if router.mode() in ["facility_place","module_place"]:return
	if _target.is_empty():return
	if router.mode()=="move" and world.entity(_target.id).get("kind")=="structure":
		_feedback(router.begin_structure_action("move",_target.id));return
	if _matches_held_work(_target):
		_feedback(router.request("held","",{"held":true}));return
	var p:Dictionary={"direct":true,"held":true,"requires_hold":true,"tool_id":_tool_id()}
	if _target.primary=="harvest":
		if _exact_target.get("primary")!="harvest":
			var anchor:Dictionary=_target.get("projected_position",{})
			if anchor.is_empty() or _picked_screen.distance_to(Vector2(float(anchor.x),float(anchor.y)))>14.0:return
		var actor:Dictionary=runtime.actor("player")
		var active:Variant=actor.get("intent")
		if active is Dictionary and active.get("kind")=="harvest" and active.get("request",{}).get("target_id")==_target.id:
			if not active.get("held",true):_feedback(router.request("held","",{"held":true}))
			return
		_holding_primary=false
		_held_kind=""
		_feedback(router.request("harvest",_target.id,_harvest_payload(false)))
	elif _target.primary=="terrain" and not _point.is_empty():
		if router.mode()!="terrain_fill":
			var result:Dictionary=router.request("terrain",_target.id,_terrain_payload)
			if not result.ok:_blocked_work_key=_work_key()
			_feedback(result)
	elif world.entity(_target.id).get("kind")=="structure":
		if router.mode() not in ["repair","demolish","destroy"]:return
		p.kind="repair" if router.mode()=="repair" else "damage" if router.mode()=="destroy" else "remove"
		p.tool_id=_tool_id("hammering")
		p.source_id="pack:player";p.output_id="pack:player"
		_feedback(router.request("structure",_target.id,p))

func _consume()->void:
	if router.mode()!="tool" or router.is_placement():return
	var held:Dictionary=router.held_reference()
	if held.get("kind")!="item":
		ui.notify("请先从快捷栏选择食物、饮水或药品",true)
		return
	var item_id:String=str(held.get("id",held.get("item_id","")))
	for kind:String in ["eat","drink","medicine"]:
		for item:Dictionary in runtime.life_consumables("player",kind):
			if item.get("item_id")==item_id:
				_feedback(router.request(kind,"",{"item_id":item_id}))
				return
	ui.notify("当前物品无法直接使用，或随身数量不足",true)

func _secondary() -> void:
	if router.is_placement():
		_clear_placement_lock()
		if router.secondary_position is Vector2:_refresh_at(router.secondary_position)
		else:_refresh()
		return
	if router.mode()=="terrain_fill":
		if router.secondary_position is Vector2:_refresh_at(router.secondary_position)
		else:_refresh()
		if not _terrain_payload.is_empty():_feedback(router.request("terrain",_target.id,_terrain_payload))
		return

func _confirm_placement() -> void:
	if is_instance_valid(_tree_confirm) and _tree_confirm.visible and not _zone_confirmation_active():
		_confirm_tree_batch()
		return
	if router.is_paused() or not router.is_placement() or _zone_confirmation_active():return
	if router.mode() == "module_place":
		confirm_build_placement()
		return
	if not _placement_locked():
		ui.notify("先左键固定位置，再确认", true)
		return
	_refresh()
	if _preview.is_empty():
		ui.notify(str(_target.get("reason", "此位置已不可用，请右键解除后重新选址")), true)
		return
	var moving: bool = _preview.get("kind") == "move"
	var id: String = _moving_target if moving else str(_preview.instance.id)
	var result: Dictionary = router.request("structure", id, _preview)
	_feedback(result)
	if result.get("ok", false):
		if moving:router.set_mode("tool")
		_clear_placement_lock()
		_refresh()

func build_placement_view() -> Dictionary:
	return _build_view.duplicate(true)

func _publish_build_view(view: Dictionary) -> void:
	_build_view = view

func confirm_build_placement() -> Dictionary:
	if router.mode() != "module_place" or router.is_paused() or _zone_confirmation_active():
		return {"ok": false, "code": "BUILD_PLACEMENT_INACTIVE"}
	_refresh()
	var result := {"ok": false, "code": "BUILD_PLACEMENT_BLOCKED", "reason": "请先左键固定位置"}
	if not _fixed_build_position.is_empty():
		if not _build_view.get("valid", false):
			result.reason = _build_view.get("reason", "此处不能建造")
		else:
			var worker_id: String = _build_view.worker_id
			var module_id: String = _preview.module_id
			var request := {"actor_id": "player", "kind": "module.plan", "target_id": module_id, "payload": _preview.payload}
			result = runtime.availability(request)
			if result.get("ok", false):
				result = router.request("module.plan", module_id, request.payload)
			if result.get("ok", false):
				router.set_mode("tool")
				if not worker_id.is_empty():ui.finish_companion_blueprint(module_id, worker_id)
				_refresh()
	_feedback(result)
	return result

func _placement_locked() -> bool:
	return not _fixed_build_position.is_empty() or not _fixed_structure_location.is_empty()

func _placement_style()->String:
	return "左键固定 · R旋转 · Esc退出" if not _placement_locked() else "Enter确认 · 右键解除 · R旋转"

func _show_ghost(box:AABB,ready:bool,visible:bool=true)->void:
	var size:Vector3=box.size.max(Vector3(0.05,0.05,0.05))
	if _ghost_mesh.size!=size:_ghost_mesh.size=size
	_ghost_material.albedo_color=Color(0.3,0.75,0.48,0.26) if ready else Color(0.9,0.3,0.22,0.28)
	_ghost.position=box.get_center()
	_ghost.visible=visible

func _publish_placement(target:Dictionary)->void:
	target.placement_locked = _placement_locked()
	target.hint = _placement_style()
	if router.mode() == "module_place":
		# The construction footer and HUD consume the same target snapshot.
		target.missing = _build_view.get("missing", {}).duplicate(true)
		target.worker_name = _build_view.get("worker_name", "我")
		target.source_name = "随身背包" if _build_view.get("worker_id", "").is_empty() else "同伴随身背包"
		target.placement_state = _build_view.get("state", "blocked")
		target.action_label = "确认建造" if _build_view.get("worker_id", "").is_empty() else "建立蓝图"
	_target=target
	_exact_target={}
	_pointed_person=""
	_publish_target(target)

func _update_preview(held: Dictionary,origin: Vector3,direction: Vector3) -> void:
	_ghost.visible=false
	_preview={}
	_structure_candidate_location = {}
	_placement_view_hint={}
	_update_placement(held,origin,direction)
	if _preview.is_empty():
		var reason := "固定位置的地面已改变或未加载，请解除后重新选址" if _placement_locked() else "请指向已生成且有支撑的地面"
		if router.mode() == "module_place":_publish_build_view(_module_build_view({}, reason))
		_publish_placement({"kind": "placement", "name": "选址", "enabled": false, "reason": reason})

func _update_placement(held:Dictionary,origin:Vector3,direction:Vector3)->void:
	if router.mode()=="module_place":
		_update_module_preview(origin,direction)
		return
	var facility:bool=router.mode()=="facility_place"
	if facility:held={"kind":"recipe","id":router.state().get("facility_definition_id","")}
	var moving:bool=router.mode()=="move" and not _moving_target.is_empty()
	if held.get("kind") != "recipe" and not moving: return
	var location := _structure_location(facility, origin, direction)
	if location.is_empty(): return
	if _structure_preview_id.is_empty():_structure_preview_id="built:%s:%s"%[runtime.get_revision(),Time.get_ticks_usec()]
	var id:String=_structure_preview_id
	var instance:Dictionary=buildings.instance(_moving_target).duplicate(true) if moving else buildings.make_instance(str(held.get("id",held.get("definition_id",""))),id,location,_quarter)
	if instance.is_empty():return
	_structure_candidate_location = location
	if moving:instance.position={"x":location.x,"y":location.y,"z":location.z};instance.quarterTurn=_quarter;id=_moving_target
	_preview={"kind":"move" if moving else "place","source_id":"pack:player","output_id":"pack:player","tool_id":_tool_id("hammering"),"held":true,"requires_hold":false,"direct":true}
	if moving:_preview.destination=instance
	else:_preview.instance=instance
	var ready:Dictionary=runtime.availability({"actor_id":"player","kind":"structure","target_id":id,"payload":_preview})
	var box: AABB=buildings.geometry.bounds(instance)
	_show_ghost(box,ready.ok)
	_publish_placement({"id":id,"kind":"placement","primary":"move" if moving else "place","name":buildings.geometry.definition(instance).name,"enabled":ready.ok,"code":ready.get("code",""),"reason":ready.get("reason"),"missing":ready.get("missing",{})})

func _structure_location(facility: bool, origin: Vector3, direction: Vector3) -> Dictionary:
	if not _fixed_structure_location.is_empty():
		var fixed := _fixed_structure_location
		var region: Dictionary = world.region_at(Geometry.json_point(Geometry.point(fixed)))
		var height: Variant = world.surface_height(fixed.x, fixed.z)
		if region.get("id") != fixed.regionId or height == null or not is_equal_approx(float(height), float(fixed.y)):
			return {}
		return fixed.duplicate(true)
	if absf(direction.y) < 0.00001: return {}
	var player: Dictionary = runtime.actor("player")
	var point := origin + direction * ((float(player.y) - origin.y) / direction.y)
	if facility:
		if _point.is_empty() or _point.get("unknown", false): return {}
		point = origin + direction * float(_point.get("distance", 0.0))
	var location := Geometry.location(player)
	location.x = snappedf(point.x, 1)
	location.z = snappedf(point.z, 1)
	var height: Variant = world.surface_height(location.x, location.z)
	if height == null: return {}
	location.y = height
	var region: Dictionary = world.region_at(Geometry.json_point(Geometry.point(location)))
	if region.is_empty(): return {}
	location.regionId = region.id
	if facility:
		location.buildingId = null
		location.storeyId = null
	return location

func _module_build_view(definition: Dictionary, reason: String = "") -> Dictionary:
	var state: Dictionary = router.state()
	var worker_id: String = state.get("module_worker_id", "")
	var worker: Dictionary = runtime.actor("player" if worker_id.is_empty() else worker_id)
	return {"active": true, "fixed": not _fixed_build_position.is_empty(), "valid": false,
		"name": definition.get("name", "建造选址"), "worker_id": worker_id,
		"worker_name": "我" if worker_id.is_empty() else worker.get("name", "同伴"),
		"missing": {}, "reason": reason, "state": "blocked", "position": {}}

func _module_build_position(definition: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	if not _fixed_build_position.is_empty():return _fixed_build_position.duplicate(true)
	if _point.is_empty() or _point.get("unknown", false):return {}
	var point: Vector3 = origin + direction * float(_point.get("distance", 0))
	var size: float = 1.0 if definition.has("compact_kind") else float(world.config().cellSize)
	point.x = snappedf(point.x, size)
	point.z = snappedf(point.z, size)
	var surface: Variant = world.surface_height(point.x, point.z)
	if surface == null:return {}
	point.y = float(surface)
	var position := Geometry.json_point(point)
	var region: Dictionary = world.region_at(position)
	if region.is_empty():return {}
	position.regionId = region.id
	return position

func _update_module_preview(origin: Vector3, direction: Vector3) -> void:
	if modules == null:return
	var definition_id: String = router.state().get("module_definition_id", "")
	var definition: Dictionary = modules.definition(definition_id)
	if definition.is_empty():return
	var position := _module_build_position(definition, origin, direction)
	if position.is_empty():return
	if _module_preview_id.is_empty():_module_preview_id = "r34:built:%d:%d" % [runtime.get_revision(), Time.get_ticks_usec()]
	var view := _module_build_view(definition)
	var worker_id: String = view.worker_id
	var plan_only := not worker_id.is_empty()
	var payload := {"definition_id": definition_id, "position": position, "quarter_turn": _quarter}
	if plan_only:payload.plan_only = true
	else:
		payload.source_id = "pack:player"
		payload.tool_id = _tool_id("hammering")
	var request := {"actor_id": "player", "kind": "module.plan", "target_id": _module_preview_id, "payload": payload}
	var ready: Dictionary = modules.preview(request)
	var worker: Dictionary = runtime.actor(worker_id if plan_only else "player")
	var production: Variant = runtime.domain_service("production")
	var source_id := "pack:" + str(worker.get("id", ""))
	var cost: Dictionary = definition.get("build_cost", {})
	for item: String in cost:
		var amount: float = production.available_for(source_id, item, "work") if production != null else 0.0
		var missing := float(cost[item]) - amount
		if missing > 0.000001:view.missing[item] = missing
	var relationship: Dictionary = worker.get("relationship", {})
	var worker_ready := float(worker.get("hp", 0)) > 0
	if plan_only:worker_ready = worker_ready and relationship.get("member", false) and relationship.get("consent", false)
	var allowed := false
	if not ready.get("ok", false):view.reason = str(ready.get("reason", "此处不能建造"))
	elif not worker_ready:view.reason = "施工人目前无法接单"
	elif not plan_only and worker.get("intent") != null:view.reason = "请先结束当前工作"
	elif not plan_only and (str(payload.tool_id).is_empty() or production == null or production.tool_unavailable(str(payload.tool_id))):
		view.reason = "需要随身携带可用的锤子"
	elif not view.missing.is_empty():
		allowed = plan_only
		view.state = "shortage"
		view.reason = "同伴随身缺料，可先建立蓝图" if plan_only else "随身材料不足"
	else:
		allowed = true
		view.state = "ready"
		view.reason = "可以确认建造" if view.fixed else "左键固定位置"
	view.position = position.duplicate(true)
	view.valid = view.fixed and allowed
	_preview = {"module_id": _module_preview_id, "payload": payload}
	_placement_view_hint = {"active": true, "world_revision": world.get_revision(), "module_id": _module_preview_id,
		"request": request.duplicate(true), "quarter_turn": _quarter, "preview": ready.duplicate(true)}
	var point := Geometry.point(position)
	var local: AABB = Geometry.aabb(definition.footprint)
	var a: Vector3 = point + Geometry.rotate(local.position, _quarter)
	var b: Vector3 = point + Geometry.rotate(local.end, _quarter)
	var box := AABB(a.min(b), a.max(b) - a.min(b))
	_show_ghost(box, allowed, not _view_hint_renderer)
	if view.state == "shortage":_ghost_material.albedo_color = Color(0.82, 0.62, 0.25, 0.28)
	_publish_build_view(view)
	_publish_placement({"id": _module_preview_id, "kind": "placement", "primary": "module_plan",
		"name": view.name, "enabled": view.valid, "code": ready.get("code", ""), "reason": view.reason})

func _cancel() -> void:
	_holding_primary=false;_held_kind="";_blocked_work_key=""
	if _tree_drag!=null or not _marked_trees.is_empty():
		_clear_tree_selection()
		return
	if not _tree_queue.is_empty() or not _tree_batch_target.is_empty():
		_stop_tree_batch(false)
		return
	if _placement_locked():
		_clear_placement_lock()
		_refresh()
		return
	var module_preview:bool=router.is_placement()
	var had_preview:bool=not _moving_target.is_empty() or not _preview.is_empty() or router.mode()!="tool"
	_ghost.visible=false;_preview={};_placement_view_hint={};_pending_container="";_moving_target="";_module_preview_id=""
	if module_preview:
		if router.mode()=="tool":router.clear_recipe_selection()
		else:router.set_mode("tool")
		_refresh()
		return
	if runtime.actor("player").get("intent")!=null:_feedback(router.request("cancel"))
	elif had_preview:router.set_mode("tool")
	elif is_instance_valid(ui) and ui.has_method("select_scene_target") and ui.world_view_selection().has("entity_id"):ui.select_scene_target({})
	else:router.open_requested.emit("pause")
func _feedback(receipt: Dictionary) -> void:
	if ui.has_method("report_action"):ui.report_action(receipt)
	elif not receipt.get("ok",false):ui.notify(str(receipt.get("reason",receipt.get("code","操作未完成"))),true)
