extends RefCounted
## Local selection draft only. A owns hits/zones/transactions, C owns valid cells,
## and D draws the original preview DTO. No raycast, resource or work settlement.
const C = preload("res://scripts/ui/ui_composition.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Work = preload("res://scripts/ui/zone_work_panel.gd")
const Assignments = preload("res://scripts/ui/zone_assignments.gd")
const Regional = preload("res://scripts/actions/regional_workforce.gd")
const Content = preload("res://scripts/runtime/content_definitions.gd")
const KIND_NAMES := {"forestry":"林业", "farm":"农田", "forage":"采集", "stockpile":"堆放", "clear":"清场", "terrain":"整地", "patrol":"巡逻"}
const TOOL_NAMES := {"create":"新建", "append":"追加", "erase":"擦除"}
const PREVIEW_INTERVAL_USEC := 100000
const QUICK_CLEAR_MAX_CELLS := 144
var projection: Dictionary = {}
var preview: Dictionary = {}
var receipt: Dictionary = {}
var kind := "forestry"
var tool := "create"
var selected_id := ""
var policy: Dictionary = {}
var anchor: Dictionary = {}
var pointer: Dictionary = {}
var bounds: Dictionary = {}
var region_id := ""
var drawing := false
var confirming_cancel := false
var _cancel_zone_id := ""
var companion_id := ""
var companion_purpose := ""
var player_clearing := ""
var clearing_feedback: Dictionary = {}
var _spec: Dictionary = {}
var _world_id := ""
var _basis: Array = []
var _preview_key: Array = []
var _queued := false
var _generation := 0
var _last_preview_us := 0
var _query_key: Array = []
var _authority_serial := 0
var _queried_serial := -1
var _view_serial := 0
var projection_reads := 0
var work_panel := Work.new()
var _confirm_router: WeakRef
var _confirm_callback: Callable

func invalidate() -> void:
	# Unknown authority/permission notifications must be observed immediately.
	# Router hover, focus, clock and local style refreshes are not authority edits.
	_authority_serial += 1

func reset() -> void:
	_unbind_confirm()
	_generation += 1
	projection.clear(); selected_id = ""; _world_id = ""; _basis.clear()
	_query_key.clear(); _queried_serial = -1; invalidate()
	work_panel.reset()
	kind = "forestry"; tool = "create"; policy.clear(); receipt.clear()
	clear_preview()
	end_companion()

func begin_companion(id: String, purpose: String) -> void:
	end_companion()
	clear_preview(); receipt.clear(); selected_id=""; tool="create"
	companion_id=id; companion_purpose=purpose
	kind="stockpile" if purpose=="haul" else "forestry"
	policy={"worker_ids":[id],"priority":4,"standing_order":true}
	if purpose=="haul":policy["mode"]="collect_ground"
	else:policy["mode"]="harvest_only";policy["replant"]=false;policy["mature_only"]=true
	invalidate()

func begin_player_clearing(earthwork: bool = false) -> void:
	end_companion()
	clear_preview()
	receipt.clear()
	selected_id = ""
	tool = "create"
	player_clearing = "terrain" if earthwork else "clear"
	kind = player_clearing
	policy = {"worker_ids": ["player"], "priority": 4, "mode": "cut" if earthwork else "player_clear"}
	invalidate()

func set_scoped_target(ui, region: String, x: int, z: int) -> void:
	region_id = region
	bounds = {"x0":x,"x1":x+1,"z0":z,"z1":z+1}
	_read_preview(ui, make_spec())
	ui.queue_refresh()

func end_companion() -> void:
	if companion_id.is_empty() and player_clearing.is_empty(): return
	companion_id=""; companion_purpose=""
	player_clearing = ""
	clearing_feedback.clear()
	selected_id=""; tool="create"; kind="forestry"; policy.clear(); receipt.clear()
	clear_preview(); invalidate()

func clear_preview() -> void:
	_generation += 1
	anchor.clear(); pointer.clear(); bounds.clear(); preview.clear(); _spec.clear()
	_preview_key.clear(); drawing = false; _queued = false; confirming_cancel = false
	_cancel_zone_id = ""
	_view_serial += 1

func _unbind_confirm() -> void:
	var router: Object = _confirm_router.get_ref() if _confirm_router != null else null
	if is_instance_valid(router) and router.is_connected("confirm_requested", _confirm_callback):
		router.disconnect("confirm_requested", _confirm_callback)
	_confirm_router = null
	_confirm_callback = Callable()

func _bind_confirm(ui) -> void:
	var router: Object = ui.input_router
	if not is_instance_valid(router) or not router.has_signal("confirm_requested"): return
	if _confirm_router != null and _confirm_router.get_ref() == router: return
	_unbind_confirm()
	_confirm_router = weakref(router)
	_confirm_callback = _confirm_from_router.bind(weakref(ui))
	router.connect("confirm_requested", _confirm_callback)

func _confirm_from_router(ui_ref: WeakRef) -> void:
	var ui: Variant = ui_ref.get_ref()
	if not is_instance_valid(ui) or not ui.is_zone_planning() or confirming_cancel: return
	if not bounds.is_empty(): submit(ui)
	elif not player_clearing.is_empty() and receipt.get("ok", false): _start_player_clearing(ui)

func sync(ui) -> void:
	_bind_confirm(ui)
	var identity := str(ui.factory.get("world_id", ""))
	var actor := P.player(ui.snapshot)
	var key: Array = [ui.runtime.get_instance_id() if is_instance_valid(ui.runtime) else 0, identity, ui.factory.get("world_revision"), selected_id, float(actor.get("hp",0))>0, ui.snapshot.get("status")]
	var authority_basis: Dictionary = {}
	if is_instance_valid(ui.runtime) and ui.runtime.has_method("zone_view_basis"):
		var raw: Variant = ui.runtime.call("zone_view_basis", "player")
		if raw is Dictionary: authority_basis = raw
		key = [authority_basis.get("runtime_generation"),authority_basis.get("world_generation"),authority_basis.get("zones_revision"),authority_basis.get("zones_generation",{}),authority_basis.get("available"),selected_id]
	var next_basis: Array = [identity, authority_basis.get("world_revision",ui.factory.get("world_revision")), authority_basis.get("zones_revision"), authority_basis.get("zones_generation",{}), _authority_serial]
	if next_basis != _basis:
		_basis = next_basis.duplicate(true)
		if not bounds.is_empty() and player_clearing.is_empty() and not policy.get("standing_order", false): queue_preview(ui)
	work_panel.sync(ui,selected_id,authority_basis)
	if key == _query_key and _queried_serial == _authority_serial: return
	_query_key = key.duplicate(true); _queried_serial = _authority_serial
	var value: Variant = ui.runtime.call("zone_projection", "player", selected_id) if is_instance_valid(ui.runtime) and ui.runtime.has_method("zone_projection") else null
	projection_reads += 1
	# Runtime's query already returns a detached display DTO. Keep it without
	# another full deep copy of all zones/cells on each consumer refresh.
	projection = value if value is Dictionary else {"available":false, "reason":"区域服务尚未接入", "zones":[]}
	identity = str(projection.get("world_id", identity))
	if not _world_id.is_empty() and _world_id != identity:
		reset()
		projection = value if value is Dictionary else {"available":false, "zones":[]}
	_world_id = identity
	if not selected_id.is_empty() and selected().is_empty():
		selected_id = ""; tool = "create"; clear_preview()
	_view_serial += 1

func zones() -> Array:
	return F.dictionaries(projection.get("zones", []))

func selected() -> Dictionary:
	var selection: Variant = projection.get("selection")
	if selection is Dictionary and selection.get("id") == selected_id: return selection
	return F.find(zones(), selected_id)

func signature() -> int:
	return [_view_serial, receipt, kind, tool, selected_id, policy, bounds, drawing, confirming_cancel, _queued, player_clearing, clearing_feedback, work_panel.signature()].hash()

func panel_signature(ui) -> int:
	# Live NPC positions, clock and global factory candidates are not this
	# editor's content. Rebuild only when its displayed facts or drafts change.
	var workers: Array=[]
	for member: Dictionary in ui.factory.get("workforce",{}).get("members",[]):
		workers.append([member.get("actor_id"),member.get("alive"),member.get("consent")])
	var actors: Array=[]
	for actor: Dictionary in ui.snapshot.get("actors",[]):
		actors.append([actor.get("id"),actor.get("name"),float(actor.get("hp",0))>0])
	var clearing_active: bool = not player_clearing.is_empty() and P.player(ui.snapshot).get("intent") != null
	return [ui.pages,signature(),ui.factory_view,ui.text_scale,workers,actors,clearing_active,ui.snapshot.get("stocks"),ui.snapshot.get("tools"),ui.snapshot.get("status"),ui.snapshot.get("save"),ui._notice.text].hash()

func view(active: bool) -> Dictionary:
	var published := preview.duplicate(true) if active else {}
	if not published.is_empty() and not published.has("region_id"): published.region_id = region_id
	return {"active":active, "zone_id":selected_id, "operation":tool, "drawing":drawing, "bounds":bounds.duplicate(true) if active else {}, "draft_y":float(anchor.get("height_m",0.0)), "preview":published}

func _hit(hit: Dictionary) -> Dictionary:
	if hit.get("unknown", false) or hit.get("ok") == false: return {}
	var cell: Variant = hit.get("cell")
	if not cell is Dictionary: return {}
	for key: String in ["x", "y", "z"]:
		if not (cell.get(key) is int or cell.get(key) is float) or not is_finite(float(cell[key])) or float(cell[key]) != floorf(float(cell[key])): return {}
	var region := str(hit.get("region_id", hit.get("regionId", "")))
	if region.is_empty(): return {}
	var result := {"x":int(cell.x), "y":int(cell.y), "z":int(cell.z), "region_id":region}
	var position: Variant=hit.get("position")
	if position is Dictionary and (position.get("y") is int or position.get("y") is float) and is_finite(float(position.y)):result.height_m=float(position.y)
	return result

func handle_world_click(ui, hit: Dictionary, event: InputEvent) -> bool:
	# A invokes this before ordinary clicks. Never manufacture hits over UI.
	if event is InputEventMouseButton:
		if not player_clearing.is_empty() and receipt.get("ok", false):
			return event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and cancel_draft(): ui.queue_refresh()
			return true
		if event.button_index != MOUSE_BUTTON_LEFT: return false
		if event.pressed:
			var point := _hit(hit)
			if point.is_empty():
				receipt = {"ok":false, "reason":"请在已知且已加载的地面开始拖框"}
				ui.queue_refresh(); return true
			if tool != "create" and selected().is_empty():
				receipt = {"ok":false, "reason":"请先选择要追加或擦除的区域"}
				ui.queue_refresh(); return true
			if kind == "terrain" and tool == "create" and (not policy.has("target_height") or player_clearing == "terrain"):
				if not point.has("height_m"):
					receipt={"ok":false,"reason":"尚未收到真实地表高度，请重新指向地面"};ui.queue_refresh();return true
				policy["target_height"]=float(point.height_m)
			clear_preview(); receipt.clear(); anchor = point; pointer = point.duplicate()
			region_id = str(point.region_id); drawing = true
			_update_bounds(); queue_preview(ui)
		else:
			finish_pointer(ui,hit)
		return true
	if event is InputEventMouseMotion and drawing:
		var point := _hit(hit)
		if _accept_endpoint(point) and point != pointer:
			pointer = point; _update_bounds(); _view_serial+=1
		return true
	return false

func _target_order()->bool:
	return tool=="create" and (not companion_id.is_empty() or (kind=="forestry" and policy.get("mode")=="harvest_only") or (kind=="stockpile" and policy.get("mode")=="collect_ground"))

func _accept_endpoint(point:Dictionary)->bool:
	return not point.is_empty() and (_target_order() or point.region_id==region_id)

func finish_pointer(ui, hit:Dictionary={}) -> void:
	if not drawing:return
	var point:=_hit(hit)
	drawing=false
	if _accept_endpoint(point):pointer=point;_update_bounds()
	queue_preview(ui)
	ui.queue_refresh()

func _update_bounds() -> void:
	bounds = {"x0":mini(int(anchor.x),int(pointer.x)), "z0":mini(int(anchor.z),int(pointer.z)), "x1":maxi(int(anchor.x),int(pointer.x))+1, "z1":maxi(int(anchor.z),int(pointer.z))+1}

func make_spec() -> Dictionary:
	var record := selected()
	var draft_policy: Dictionary=projection.get("defaults",{}).get(kind,{}).duplicate(true)
	draft_policy.merge(policy,true)
	var result := {"kind":kind if tool == "create" else str(record.get("kind", kind)), "region_id":region_id, "bounds":bounds.duplicate(true), "policy":draft_policy if tool == "create" else record.get("policy", {}).duplicate(true), "station_id":"" if tool == "create" else str(record.get("station_id", "")), "enabled":true}
	if tool != "create": result.id = selected_id; result.operation = tool
	return result

func queue_preview(ui) -> void:
	if drawing or _queued or bounds.is_empty(): return
	_queued = true
	var delay := PREVIEW_INTERVAL_USEC - (Time.get_ticks_usec()-_last_preview_us)
	if delay <= 0: ui.call_deferred("_flush_zone_preview", _generation)
	else: ui.get_tree().create_timer(float(delay)/1000000.0,true).timeout.connect(ui._flush_zone_preview.bind(_generation))

func flush_preview(ui, generation: int) -> void:
	if generation != _generation: return
	_queued = false
	if drawing or bounds.is_empty() or not ui.is_zone_planning(): return
	var spec := make_spec()
	var key: Array = [spec, _basis, tool]
	if key == _preview_key: return
	_read_preview(ui, spec)
	ui.queue_refresh()

func _read_preview(ui, spec: Dictionary) -> void:
	_preview_key = [spec, _basis, tool].duplicate(true)
	_spec = spec.duplicate(true)
	_last_preview_us = Time.get_ticks_usec()
	if not player_clearing.is_empty():
		var area: int = (int(bounds.x1) - int(bounds.x0)) * (int(bounds.z1) - int(bounds.z0))
		if area > QUICK_CLEAR_MAX_CELLS:
			preview = {"ok": false, "reason": "单次清理最多 %d 格，请缩小范围" % QUICK_CLEAR_MAX_CELLS, "cells": [], "excluded": []}
			_view_serial += 1
			return
	var value: Variant = ui.runtime.call("zone_preview", spec) if is_instance_valid(ui.runtime) and ui.runtime.has_method("zone_preview") else null
	preview = value.duplicate(true) if value is Dictionary else {"ok":false, "reason":"未收到真实区域预览", "cells":[], "excluded":[]}
	_view_serial += 1

func cancel_draft() -> bool:
	if confirming_cancel:
		confirming_cancel = false
		_cancel_zone_id = ""
		return true
	if drawing or not bounds.is_empty() or not preview.is_empty():
		clear_preview()
		receipt.clear()
		return true
	return false

func choose_zone(ui, id: String) -> void:
	clear_preview(); receipt.clear(); selected_id = id
	invalidate(); sync(ui)
	var record := selected()
	if not record.is_empty(): kind = str(record.get("kind", "forestry")); policy = record.get("policy", {}).duplicate(true); tool="append"
	else: tool = "create"; policy.clear()
	ui.queue_refresh()

func choose_tool(ui, value: String) -> void:
	clear_preview(); receipt.clear(); tool = value
	if value == "create": selected_id=""; policy.clear()
	ui.queue_refresh()

func submit(ui) -> Dictionary:
	if not ui.is_zone_planning() or confirming_cancel: return {"ok":false}
	if not companion_id.is_empty() and receipt.get("ok", false): return receipt
	if not player_clearing.is_empty() and receipt.get("ok", false): return receipt
	var reason := _submission_reason(ui)
	if not reason.is_empty(): return _reject(ui, reason)
	if not _preview_ready():
		var note := "等候本次预检完成" if _queued else str(preview.get("reason", "请先拖框并完成预览"))
		return _reject(ui, note)
	var shown := _review_facts(preview)
	_read_preview(ui, make_spec())
	if not _preview_ready(): return _reject(ui, str(preview.get("reason", "选区已不可用，请调整范围")))
	if not player_clearing.is_empty() and _clearing_count() == 0:
		return _reject(ui, "范围内没有需要削平的地面" if player_clearing == "terrain" else "范围内没有可清理的成熟树木或树桩")
	# A standing order approves a fixed rectangle. The worker checks the live
	# resource on admission, so a changing tree or drop count is not a new order.
	if not preview.get("standing_order", false) and shown != _review_facts(preview):
		return _reject(ui, "选区结果已变化，请查看更新后再确认")
	var command := "zone.create"
	var payload := {"spec":_spec.duplicate(true)}
	if tool != "create":
		if selected().is_empty(): return _reject(ui, "原区域已不可用")
		if tool == "erase": command = "zone.erase"; payload = {"cells":preview.cells.duplicate(true)}
		else:
			command = "zone.update"
			# A's append operation must preserve existing erased holes. Never
			# replace the record with a UI-merged cell list or enclosing rectangle.
			payload = {"patch":{"append_bounds":_spec.bounds.duplicate(true)}}
	receipt = ui.execute(command, "" if tool == "create" else selected_id, payload)
	if receipt.get("ok", false):
		if tool == "create":
			selected_id = str(receipt.get("zone_id", ""))
			for event: Dictionary in F.dictionaries(receipt.get("changes",{}).get("events",[])):
				if event.get("kind")=="zone-changed": selected_id=str(event.get("zone_id",selected_id))
		clear_preview(); invalidate(); sync(ui)
		if not selected().is_empty(): policy = selected().get("policy",{}).duplicate(true)
		if not player_clearing.is_empty(): _start_player_clearing(ui)
	ui.queue_refresh(); return receipt

func _reject(ui, reason: String) -> Dictionary:
	receipt = {"ok":false, "reason":reason}
	ui.queue_refresh()
	return receipt

func _clearing_count() -> int:
	var estimate: Dictionary = preview.get("estimate", {})
	return int(estimate.get("voxel_operations", 0)) if player_clearing == "terrain" else int(estimate.get("trees", 0)) + int(estimate.get("stumps", 0))

func _start_player_clearing(ui) -> void:
	if selected_id.is_empty(): return
	var actor: Dictionary = ui.runtime.actor("player")
	if actor.get("intent") != null:
		clearing_feedback = {"ok": false, "reason": "请先完成或停止正在进行的动作"}
		ui.queue_refresh()
		return
	var work: Variant = ui.runtime.domain_service("zonework")
	if work == null: return
	var candidates: Array = work.work_candidates("player", {}, {}, selected_id)
	var operations: Array = ["terrain_dig"] if player_clearing == "terrain" else ["harvest_tree", "clear_stump"]
	candidates = candidates.filter(func(row: Dictionary) -> bool:
		return row.get("kind") == "zonework" and operations.has(row.get("operation")))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var dist_a := float(a.get("route_cost", 0))
		var dist_b := float(b.get("route_cost", 0))
		return dist_a < dist_b if dist_a != dist_b else str(a.id) < str(b.id))
	var next: Dictionary = {}
	for candidate: Dictionary in candidates:
		if candidate.get("valid", false):
			next = candidate
			break
	if next.is_empty():
		var reason := "当前没有可继续的清理目标" if candidates.is_empty() else str(candidates[0].get("reason", "当前无法开工"))
		clearing_feedback = {"ok": false, "reason": reason}
	else:
		clearing_feedback = ui.execute("zonework.start", selected_id, {"candidate_id": str(next.id)})
	ui.queue_refresh()

func _retire_player_clearing(ui, redraw: bool) -> void:
	if selected_id.is_empty(): return
	var result: Dictionary = ui.execute("zone.cancel", selected_id)
	if not result.get("ok", false):
		clearing_feedback = result
		ui.queue_refresh()
		return
	var earthwork := player_clearing == "terrain"
	if redraw:
		begin_player_clearing(earthwork)
		ui.queue_refresh()
	else:
		end_companion()
		ui.cancel_ui()

func _submission_reason(ui) -> String:
	if companion_id.is_empty(): return ""
	var actor: Dictionary = ui.runtime.actor(companion_id)
	if actor.is_empty() or float(actor.get("hp", 0)) <= 0: return "同伴目前无法行动"
	var relationship: Dictionary = actor.get("relationship", {})
	if not relationship.get("member", false) or not relationship.get("consent", false): return "同伴尚未同意工作"
	if companion_purpose != "haul": return ""
	var id := str(policy.get("target_stock_id", ""))
	if id.is_empty(): return "请选择接收物资的仓库"
	var stock: Dictionary = ui.runtime.stock(id)
	if not Regional.ground_receiver(ui.runtime.world, actor, stock): return "原目的地已不可用，请重新选择"
	return ""

static func _review_facts(value: Dictionary) -> Array:
	return [value.get("cells", []), value.get("excluded", []), value.get("target_count"), value.get("waiting_count"), value.get("region_ids")]

func _preview_ready()->bool:
	return not drawing and not _queued and not _spec.is_empty() and _spec==make_spec() and preview.get("ok")==true and (preview.has("target_mode") or (preview.get("cells") is Array and not preview.cells.is_empty()))

func apply_policy(ui) -> Dictionary:
	if selected().is_empty(): return {"ok":false, "reason":"请先选择区域"}
	receipt = ui.execute("zone.policy", selected_id, {"patch":{"policy":policy.duplicate(true)}})
	if receipt.get("ok",false): clear_preview(); invalidate(); sync(ui)
	ui.queue_refresh(); return receipt

func cancel_zone(ui) -> Dictionary:
	receipt = ui.execute("zone.cancel", selected_id)
	if receipt.get("ok",false): clear_preview(); invalidate(); sync(ui)
	ui.queue_refresh(); return receipt

func _choice(ui, parent: Node, key: String, rows: Array, current: String, callback: Callable) -> void:
	var input := OptionButton.new(); input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; input.clip_text = true
	input.set_meta("ui_focus_key", key)
	for row: Dictionary in rows:
		input.add_item(str(row.get("name", row.id))); input.set_item_metadata(input.item_count-1, str(row.id))
		input.set_item_tooltip(input.item_count-1,str(row.get("description",row.id)))
		if row.id == current: input.select(input.item_count-1)
	input.disabled = rows.is_empty(); parent.add_child(input)
	input.item_selected.connect(func(index: int): callback.call(str(input.get_item_metadata(index))))

func _toggle(ui, parent: Node, key: String, title: String, default: bool) -> void:
	var input := CheckBox.new(); input.text = title; input.button_pressed = policy.get(key, default)
	input.set_meta("ui_focus_key", "zone:policy:"+key); parent.add_child(input)
	input.toggled.connect(func(value: bool): policy[key] = value; _preview_key.clear(); queue_preview(ui))

func render(ui, body: VBoxContainer) -> void:
	if not companion_id.is_empty():
		_render_companion(ui,body)
		return
	if not player_clearing.is_empty():
		_render_player_clearing(ui, body)
		return
	body.set_meta("ui_zone_planning", true)
	var clearing_choices := HFlowContainer.new()
	body.add_child(clearing_choices)
	ui.add_button("清理树木", func(): begin_player_clearing(); ui.queue_refresh(), "zone:player:clear", "", clearing_choices)
	ui.add_button("削平地面", func(): begin_player_clearing(true); ui.queue_refresh(), "zone:player:grade", "", clearing_choices)
	C.caption(ui, "在场景拖框，查看有效格后确认；规划不会生成资源", body)
	if projection.get("available") == false:
		C.reason(ui, body, str(projection.get("reason", "区域服务尚未就绪")))
	var source := [{"id":"", "name":"新建区域"}]
	var records := zones()
	for index in records.size():
		var record: Dictionary = records[index]
		source.append({"id":str(record.id), "name":str(record.get("name", KIND_NAMES.get(record.get("kind"), "区域")))+" · "+str(index+1), "description":str(record.id)})
	_choice(ui, body, "zone:selected", source, selected_id, func(id: String): choose_zone(ui,id))
	var kinds: Array = []
	for id: String in KIND_NAMES: kinds.append({"id":id,"name":KIND_NAMES[id]})
	if selected_id.is_empty():
		_choice(ui, body, "zone:kind", kinds, kind, func(value: String): kind=value; policy.clear(); clear_preview(); ui.queue_refresh())
	else:
		C.heading(ui, str(KIND_NAMES.get(selected().get("kind"), "区域")), body, ("启用" if selected().get("enabled",false) else "已停止安排")+" · 实际格数 "+str(selected().get("cell_count",selected().get("cells",[]).size())))
	var tools := HBoxContainer.new(); tools.add_theme_constant_override("separation",4); body.add_child(tools)
	for value: String in TOOL_NAMES:
		# Disabled reasons belong on their own row, never inside this button row.
		var button: Button = ui.button(TOOL_NAMES[value],func():choose_tool(ui,value),"zone:tool:"+value,"请先选择已有区域" if value != "create" and selected_id.is_empty() else "")
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.clip_text=true
		tools.add_child(button)
		button.toggle_mode = true; button.set_pressed_no_signal(tool==value)
	if selected_id.is_empty(): C.caption(ui,"选择已有区域后可追加或擦除",body)
	var options := C.card(body)
	C.heading(ui, "作业策略", options)
	var priority := SpinBox.new(); priority.min_value=0;priority.max_value=5;priority.step=1;priority.value=float(policy.get("priority",projection.get("defaults",{}).get(kind,{}).get("priority",2)));priority.prefix="优先级 "
	priority.get_line_edit().set_meta("ui_focus_key","zone:priority");options.add_child(priority)
	priority.value_changed.connect(func(value:float):policy["priority"]=int(value);_preview_key.clear();queue_preview(ui))
	if kind == "forestry":
		_choice(ui,options,"zone:policy:mode",[{"id":"sustainable","name":"经营林 · 采伐与补种"},{"id":"nursery","name":"育苗 · 使用真实树种与原水"}],str(policy.get("mode",projection.get("defaults",{}).get(kind,{}).get("mode","sustainable"))),func(value:String):policy["mode"]=value;_preview_key.clear();queue_preview(ui))
		_toggle(ui,options,"mature_only","只采成熟树",true)
		_toggle(ui,options,"replant","采后补种（实际消耗苗木）",true)
		_toggle(ui,options,"conserve","保育母树 · 不安排采伐",false)
	if kind == "farm":
		C.caption(ui,"生长分阶段耗水，土壤干燥时需再次浇水。成熟以实际田间状态为准。",options)
		_toggle(ui,options,"replant","收获后续种（保留真实种子）",true)
		C.caption(ui,"每畦收获保留种子",options)
		var reserve := SpinBox.new();reserve.min_value=0;reserve.max_value=1000000;reserve.step=1;reserve.value=float(policy.get("reserve_seed",projection.get("defaults",{}).get(kind,{}).get("reserve_seed",1)))
		reserve.get_line_edit().set_meta("ui_focus_key","zone:reserve_seed");options.add_child(reserve)
		reserve.value_changed.connect(func(value:float):policy["reserve_seed"]=int(value);_preview_key.clear();queue_preview(ui))
	if kind in ["farm","forestry"]:
		var field := "crop_id" if kind == "farm" else "tree_id"
		var available: Array = species_choices(projection.get("crops" if kind == "farm" else "trees",{}))
		if not available.is_empty(): _choice(ui,options,"zone:policy:"+field,available,str(policy.get(field,"")),func(value:String):policy[field]=value;_preview_key.clear();queue_preview(ui))
		else: C.caption(ui,"作物/树种沿真实服务默认；未发布的选项不补造",options)
	if kind == "terrain":
		_choice(ui,options,"zone:terrain:mode",[{"id":"cut","name":"削平 · 只挖高处"},{"id":"fill","name":"填平 · 只填低处"},{"id":"balance","name":"平衡挖填"},{"id":"ramp_x","name":"沿东西方向缓坡"},{"id":"ramp_z","name":"沿南北方向缓坡"}],str(policy.get("mode",projection.get("defaults",{}).get(kind,{}).get("mode","balance"))),func(value:String):policy["mode"]=value;_preview_key.clear();queue_preview(ui))
		_choice(ui,options,"zone:terrain:fill",[{"id":"2","name":"土方填筑"},{"id":"3","name":"石方填筑"},{"id":"6","name":"沙料填筑"}],str(policy.get("fill_material",2)),func(value:String):policy["fill_material"]=int(value);_preview_key.clear();queue_preview(ui))
		C.caption(ui,"按实际工程量挖运填筑；保留基础、水源和出口，取消保留已完成部分",options)
		C.caption(ui,"目标高度（米，0.5米一档）",options)
		var height := SpinBox.new(); height.min_value=-10000; height.max_value=10000; height.step=0.5; height.value=float(policy.get("target_height",0)); height.suffix=" m"
		height.editable=policy.has("target_height");height.visible=policy.has("target_height")
		if not policy.has("target_height"):C.caption(ui,"先在真实地面拖框；以首个起点表面高度初始化，不默认削至零米",options)
		height.get_line_edit().set_meta("ui_focus_key","zone:height"); options.add_child(height)
		height.value_changed.connect(func(value:float):policy["target_height"]=value;_preview_key.clear();queue_preview(ui))
	Assignments.render(ui,options,self)
	if not selected_id.is_empty():
		ui.add_button("保存区域策略",func():apply_policy(ui),"zone:policy:apply","",options)
	work_panel.render(ui,body,selected_id)
	C.caption(ui, "左键拖框 · Enter确认 · 右键撤草框 · Esc返回", body)
	if bounds.is_empty():
		C.caption(ui, "尚未选择地面；拖框期间不会砍伐、挖掘或支付材料", body)
	else:
		var summary := C.card(body,true)
		C.heading(ui,"正在拖框" if drawing else "本次预览",summary)
		C.caption(ui,"%s × %s 格%s" % [int(bounds.x1)-int(bounds.x0),int(bounds.z1)-int(bounds.z0)," · 起点地表 "+P.number(anchor.height_m)+" m" if anchor.has("height_m") else ""],summary)
		if _queued: C.caption(ui,"正在读取实际地形与冲突",summary)
		elif preview.is_empty(): C.caption(ui,"尚未收到实际预览",summary)
		else:
			_render_exclusions(ui, summary)
			if preview.get("ok") != true: C.reason(ui,summary,P.feedback_text(preview))
			var estimate: Variant = preview.get("estimate",{})
			if estimate is Dictionary:
				for key in ["work_seconds","minimum_labor_seconds","voxel_operations","volume_m3","cut_m3","fill_m3","net_material","soil_m3","water_units"]:
					if not estimate.has(key):continue
					var title:=str({"work_seconds":"预计劳动秒","minimum_labor_seconds":"最低有效劳动秒","voxel_operations":"逐格作业次数","volume_m3":"工程量 m³","cut_m3":"预计挖出（分材料）","fill_m3":"预计消耗（分材料）","net_material":"挖出减填入（负数为需补料）","soil_m3":"预计土方 m³","water_units":"预计用水份数"}[key])
					if estimate[key] is Dictionary:ui.item_row(estimate[key],title,summary)
					elif estimate[key] is int or estimate[key] is float:C.caption(ui,title+" · "+P.number(estimate[key]),summary)
				if estimate.get("cost") is Dictionary: ui.item_row(estimate.cost,"预计材料（尚未支付）",summary)
	if not selected_id.is_empty():
		var maintenance := C.fold(ui,body,"zone:maintenance","停止与后果")
		if maintenance != null:
			C.caption(ui,"仅停止未执行安排，已砍树、作物、搬运及已付劳动保持；不会恢复世界",maintenance)
			if confirming_cancel:
				ui.add_button("确认停止区域安排",func():cancel_zone(ui),"zone:cancel:confirm","",maintenance)
				ui.add_button("保留安排",func():confirming_cancel=false;ui.queue_refresh(),"zone:cancel:back","",maintenance)
			else: ui.add_button("停止安排…",func():confirming_cancel=true;ui.queue_refresh(),"zone:cancel","",maintenance)

func _render_player_clearing(ui, body: VBoxContainer) -> void:
	var earthwork := player_clearing == "terrain"
	C.heading(ui, "削平地面" if earthwork else "清理树木", body)
	if not receipt.get("ok", false):
		C.caption(ui, "从目标高度的地面拖向高处。带上挖掘工具，逐格挖除高出的土石。" if earthwork else "框选成熟树木和树桩。确认后，主角会带着手上的工具前往作业。", body)
		if not bounds.is_empty() and not drawing and not _queued: _render_exclusions(ui, body)
		return
	if not clearing_feedback.is_empty():
		if clearing_feedback.get("ok", false):
			var player := P.player(ui.snapshot)
			C.caption(ui, P.activity_text(player) if player.get("intent") != null else "可继续清理，或结束这次安排", body)
		else: C.reason(ui, body, P.feedback_text(clearing_feedback))
	work_panel.render(ui, body, selected_id)

func _render_exclusions(ui, parent: Node) -> void:
	var exclusions: Dictionary = {}
	for row: Dictionary in F.dictionaries(preview.get("excluded", [])):
		var text := reason_text(str(row.get("code", ""))) if row.has("code") else P.feedback_text(row)
		exclusions[text] = int(exclusions.get(text, 0)) + 1
	for text: String in exclusions.keys().slice(0, 4):
		C.reason(ui, parent, "%s · %d 格" % [text, exclusions[text]])
	if exclusions.size() > 4:
		C.caption(ui, "另有 %d 类排除原因" % (exclusions.size() - 4), parent)

func _render_companion(ui, body: VBoxContainer) -> void:
	var actor:=P.find(ui.snapshot.get("actors",[]),companion_id)
	C.heading(ui, "划区 · " + str(actor.get("name", "同伴")), body, "搬运地面物资" if companion_purpose == "haul" else "采伐成熟树木")
	if not bounds.is_empty() and not drawing and not _queued: _render_exclusions(ui, body)
	var stocks:Array=ui.runtime.stock_states() if companion_purpose=="haul" else []
	if not receipt.get("ok",false) and companion_purpose=="haul":
		var choices:Array=[{"id":"","name":"请选择仓库"}]
		for stock:Dictionary in stocks:
			var id:=str(stock.get("id",""))
			var facility:=F.instance(ui.factory,str(stock.get("module_id","")))
			if facility.is_empty() and P.stock(ui.snapshot,id).is_empty():continue
			if not Regional.ground_receiver(ui.runtime.world,actor,stock):continue
			choices.append({"id":id,"name":_receiver_name(ui, stock)})
		Assignments._stock_choice(ui,body,self,"target_stock_id","送到",choices)
		if choices.size()==1:C.caption(ui,"没有已知且可用的接收仓库",body)
	if receipt.get("ok",false):
		if not selected_id.is_empty() and companion_purpose=="haul":C.caption(ui,_haul_status(ui,actor,selected(),stocks),body)
		if companion_purpose!="haul" and not selected_id.is_empty():
			var plan:Dictionary=ui.runtime.zone_projection("player",selected_id).get("selection",{})
			if not plan.is_empty():C.caption(ui,_harvest_status(plan,actor),body)
		if selected().get("enabled", false): _render_stop(ui, body, selected_id)
		ui.add_button("返回同伴",ui.cancel_ui,"zone:companion:back","",body)
		return
	for row:Dictionary in zones():
		if (not row.get("enabled",false) and not row.get("completed",false)) or row.get("policy",{}).get("worker_ids",[])!=[companion_id]:continue
		if row.get("kind")!=kind or (kind=="stockpile" and row.policy.get("mode")!="collect_ground"):continue
		var zone_id:=str(row.id)
		if companion_purpose=="haul":
			var plan:Dictionary=ui.runtime.zone_projection("player",zone_id).get("selection",{})
			if not plan.is_empty():C.caption(ui,_haul_status(ui,actor,plan,stocks),body)
		else:
			var plan:Dictionary=ui.runtime.zone_projection("player",zone_id).get("selection",{})
			if not plan.is_empty():C.caption(ui,_harvest_status(plan,actor),body)
		if row.get("completed",false):continue
		_render_stop(ui, body, zone_id)

func _receiver_name(ui, stock: Dictionary) -> String:
	if stock.is_empty(): return "原目的地不可用"
	var facility := F.instance(ui.factory, str(stock.get("module_id", "")))
	var title := str(facility.get("name", stock.get("name", "储物箱")))
	var buffer := str(stock.get("buffer_id", ""))
	if not buffer.is_empty():
		title += " · " + str({"input":"进料", "output":"出料", "tools":"工具", "fuel":"燃料", "storage":"库存"}.get(buffer, "储物"))
	return title

func _render_stop(ui, parent: Node, zone_id: String) -> void:
	if confirming_cancel and _cancel_zone_id == zone_id:
		C.caption(ui, "停止后续取货。已搬出的物资继续按原任务交付，若无法交付则保留在同伴背包中。", parent)
		ui.add_button("确认停止安排", func(): _stop_companion(ui, zone_id), "zone:companion:stop:confirm:" + zone_id, "", parent)
		ui.add_button("保留安排", func(): cancel_draft(); ui.queue_refresh(), "zone:companion:stop:back:" + zone_id, "", parent)
	else:
		ui.add_button("停止安排…", func():
			confirming_cancel = true
			_cancel_zone_id = zone_id
			ui.queue_refresh(), "zone:companion:stop:" + zone_id, "", parent)

func _stop_companion(ui, zone_id: String) -> void:
	var result: Dictionary = ui.execute("zone.cancel", zone_id, {})
	if result.get("ok", false):
		confirming_cancel = false
		_cancel_zone_id = ""
		if zone_id == selected_id: receipt.clear()
		invalidate()
		sync(ui)
	else:
		receipt = result
	ui.queue_refresh()

func _harvest_status(row:Dictionary,actor:Dictionary)->String:
	if row.get("completed",false):return "本次采伐完成"
	var total:int=int(row.get("total_targets",0));var left:int=int(row.get("remaining_targets",0))
	var action:String=str(actor.get("activity",""))
	if row.get("policy",{}).get("standing_order",false):
		if left==0:return "当前无成熟树木 · 保留工作区"
		return "%d 棵成熟树木 · %s" % [left,action if not action.is_empty() else "等待接单"]
	return "剩余 %d / %d 棵 · %s" % [left,total,action if not action.is_empty() else "等待接单"]

func _haul_status(ui, actor:Dictionary, row:Dictionary, stocks:Array)->String:
	if row.is_empty():return "等待安排记录"
	var to:=str(row.policy.get("target_stock_id",""))
	if not Regional.ground_receiver(ui.runtime.world,actor,F.find(stocks,to)):return "接收仓不可用"
	var pending:Dictionary=actor.get("pending_delivery",{})
	if pending.get("destination_id")==to:return "送货途中" if pending.get("phase")=="deliver" else "前往取货"
	var sources:Array=Regional.ground_sources(ui.runtime.world,row,stocks,actor)
	if sources.is_empty():return "框内没有待搬物资"
	var production:Variant=ui.runtime.domain_service("production")
	if production==null:return "等待搬运"
	for source:Dictionary in sources:
		for item:String in source.items:
			var step:float=Content.quantity_step(item)
			if step>0 and production.available_for(str(source.id),item,"work")>=step and production.capacity_check(to,{item:step}).ok:return "等待同伴接单"
	return "仓库满、不收这类物资，或物资已预留"

func render_footer(ui, parent: VBoxContainer) -> void:
	var summary:=C.card(parent,true)
	if not player_clearing.is_empty() and receipt.get("ok", false):
		var busy := "请先完成正在进行的动作" if P.player(ui.snapshot).get("intent") != null else ""
		C.primary(ui.add_button("继续清理 · Enter", func(): _start_player_clearing(ui), "zone:player:continue", busy, summary))
		ui.add_button("完成并关闭", func(): _retire_player_clearing(ui, false), "zone:player:finish", busy, summary)
		ui.add_button("另选区域", func(): _retire_player_clearing(ui, true), "zone:player:redraw", busy, summary)
		return
	if not companion_id.is_empty():
		var actor := P.find(ui.snapshot.get("actors", []), companion_id)
		var assignment := "执行 · " + str(actor.get("name", "同伴"))
		if companion_purpose == "haul":
			var stock_id := str(policy.get("target_stock_id", ""))
			assignment += " → " + (_receiver_name(ui, ui.runtime.stock(stock_id)) if not stock_id.is_empty() else "待选目的地")
		C.caption(ui, assignment, summary)
		if receipt.get("ok", false):
			C.caption(ui, "安排已提交 · 接单后开始作业", summary)
			return
	var reason := _submission_reason(ui)
	var ready := _preview_ready() and reason.is_empty() and not confirming_cancel
	if ready and not player_clearing.is_empty() and _clearing_count() == 0:
		ready = false
		reason = "范围内没有高出起点的可挖土石" if player_clearing == "terrain" else "范围内没有可清理的成熟树木或树桩"
	var headline := "在场景中左键拖框"
	if not bounds.is_empty():
		headline = "%s × %s 格" % [int(bounds.x1) - int(bounds.x0), int(bounds.z1) - int(bounds.z0)]
		if not drawing and not _queued and not preview.is_empty():
			if preview.has("target_mode"):
				var unit := "处地面物资" if preview.target_mode == "collect_ground" else "棵可采伐树木"
				headline += " · 已核查 %d %s" % [int(preview.get("target_count", 0)), unit]
				if int(preview.get("waiting_count", 0)) > 0: headline += " · %d 个地区待核查" % int(preview.waiting_count)
			elif preview.has("valid_count") and preview.has("excluded_count"):
				headline += " · 有效 %d · 排除 %d" % [int(preview.valid_count), int(preview.excluded_count)]
		if not drawing and not _queued and preview.get("ok", false) and not player_clearing.is_empty():
			var estimate: Dictionary = preview.get("estimate", {})
			headline += " · 挖除 %d 格" % int(estimate.get("voxel_operations", 0)) if player_clearing == "terrain" else " · 树木 %d · 树桩 %d" % [int(estimate.get("trees", 0)), int(estimate.get("stumps", 0))]
	var counts := C.caption(ui, headline, summary)
	counts.set_meta("ui_focus_key", "zone:preview:counts")
	var status := "左键拖框 · 右键撤回 · Esc退出"
	if drawing: status = "松开左键完成草框"
	elif _queued: status = "正在重新核查选区"
	elif confirming_cancel: status = "请先完成或返回停止确认"
	elif not reason.is_empty(): status = reason
	elif ready and preview.has("target_mode") and int(preview.get("target_count", 0)) == 0:
		status = "Enter确认 · 有目标后开始工作" if preview.get("standing_order", false) else "等地区加载后再核查框内目标"
	elif ready: status = "Enter确认 · 右键撤回草框"
	elif not preview.is_empty(): status = P.feedback_text(preview)
	var disabled_reason := "" if ready else status
	if not receipt.is_empty() and not _queued and not drawing:
		status = "区域已提交" if receipt.get("ok", false) else P.feedback_text(receipt)
	var note := C.caption(ui, status, summary)
	note.max_lines_visible = 2
	note.tooltip_text = status
	var row := HFlowContainer.new()
	summary.add_child(row)
	var action_text := "安排搬运" if companion_purpose == "haul" else "安排采伐" if companion_purpose == "forestry" else "确认" + str(TOOL_NAMES.get(tool, "区域"))
	if not player_clearing.is_empty(): action_text = "开始清理"
	var confirm: Button = ui.button(action_text + " · Enter", func(): submit(ui), "zone:submit", disabled_reason)
	C.primary(confirm)
	row.add_child(confirm)
	var retract: Button = ui.button("撤回草框", func(): cancel_draft(); ui.queue_refresh(), "zone:draft:cancel", "" if not bounds.is_empty() and not confirming_cancel else "当前没有可撤回的草框")
	row.add_child(retract)

static func reason_text(code: String) -> String:
	return str({"REGION_NOT_DETAILED":"该地区尚未详细加载", "UNKNOWN_CELL":"尚未探索的地面", "UNLOADED_CELL":"地面尚未加载", "PROTECTED_ROAD":"保留道路与通路", "UNSUITABLE_SOIL":"土壤不适合当前用途", "OCCUPIED_OR_PROTECTED":"已有对象或受保护土地", "PROTECTED_SERVICE_EXIT":"保留设施服务出口", "PROTECTED_OBJECT_OR_FOUNDATION":"保留现有对象和建筑基础", "PROTECTED_REGION_EXIT":"保留地区出口", "PROTECTED_WATER_OUTLET":"保留水源取水口", "PROTECTED_TERRAIN_LAYER":"下方有受保护地层", "INVALID_BATCH_GRADE":"目标高度或缓坡坡度不合法", "HEIGHT_LIMIT":"已到可施工高程边界", "RICE_REQUIRES_LEVEL_BED":"水稻需要平整田畦", "ZONE_OVERLAP":"与其他工作区重叠", "NO_ZONE_CELLS":"选区内没有原规划格"}.get(code,P.reason_text(code)))

static func species_choices(value: Variant) -> Array:
	if value is Array: return F.dictionaries(value)
	var result: Array=[]
	if not value is Dictionary:return result
	for id: String in value:
		var row: Dictionary=value[id] if value[id] is Dictionary else {}
		result.append({"id":id,"name":str({"potato":"马铃薯","bean":"菜豆","rice":"水稻","broadleaf":"阔叶树","conifer":"针叶树"}.get(id,row.get("name",id))),"description":P.item_name(str(row.get("seed","")))+" · "+("育苗需原水，种植消耗苗木" if row.has("seedling") else "实际翻土、供水与留种")})
	return result
