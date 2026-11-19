extends RefCounted
## Read-only presentation of the published companion and workforce state.
const P = preload("res://scripts/ui/ui_projection.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Identity = preload("res://scripts/ui/ui_identity.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")

static func present(actor: Dictionary, factory: Dictionary) -> Dictionary:
	var id := str(actor.get("id", ""))
	var member := F.find(F.rows(factory, "workforce", "members"), id, "actor_id")
	var order := F.find(F.rows(factory, "workforce", "assignments"), id, "actor_id")
	var delivery: Dictionary = actor.get("pending_delivery", {})
	var relationship: Dictionary = actor.get("relationship", {})
	var routine: Dictionary = actor.get("self_routine", {})
	var decision: Dictionary = routine.get("factory_decision", {})
	var phase := str(order.get("building_phase", order.get("work_phase", "")))
	var carrying: bool = delivery.get("phase") == "deliver"
	var cargo := PackedStringArray()
	if carrying:
		var items: Dictionary = delivery.get("items", {})
		for item_id: String in items:
			cargo.append(P.item_name(item_id) + " × " + P.number(items[item_id]))
	var activity := str(member.get("activity", ""))
	var current := P.activity_text(actor.merged({"activity":activity}, true)) if not activity.is_empty() else P.activity_text(actor)
	var consent := ""
	if float(actor.get("hp", 0)) <= 0: consent = "这名同伴当前无法行动。"
	elif not relationship.get("member", false): consent = "尚未同行，可先交谈。"
	elif not relationship.get("consent", false): consent = "尚未同意工作，可在「人物与合作」请求授权。"
	elif not F.enabled(factory): consent = "当前世界未开放村务派工。"
	var module_id := str(order.get("module_id", ""))
	var module := F.instance(factory, module_id) if not module_id.is_empty() else {}
	var order_kind := "建筑工程" if order.has("building_phase") else "运输工单" if order.get("work_kind") == "transport_order" else "生产工单"
	var order_title := order_kind + (" · " + str(module.get("name", "")) if not str(module.get("name", "")).is_empty() else "")
	var phase_text := str({"queued":"待接单", "accepted":"已接单", "blocked":"受阻", "completed":"已完成", "ended":"已结束"}.get(phase, "已安排"))
	var assignment_id := str(member.get("assignment_id", order.get("id", "")))
	var assignment := ""
	if not order.is_empty(): assignment = order_title + " · " + phase_text
	elif not assignment_id.is_empty(): assignment = "已接到工作"
	var reason := ""
	if phase in ["blocked", "ended"]:
		reason = str(order.get("building_reason", order.get("work_reason", "")))
		if not reason.is_empty(): reason = P.reason_text(reason)
	var next_step := ""
	if carrying:
		next_step = "先交付手上货物。交付受阻时，货物仍由本人保管。"
	elif delivery.get("phase") == "collect":
		next_step = "先前往来源取货，再送往指定接收点。"
	elif phase == "blocked":
		next_step = "原工作保留。条件恢复后会重试，期间可接其他工作。"
	elif phase == "queued":
		next_step = "工单已排入。开工前会先核对工具、材料和路线。"
	elif phase == "accepted" and order.has("building_phase"):
		next_step = Ops.building_order_status(order)
	elif not decision.is_empty() and decision.get("action") != "idle":
		next_step = Identity.decision_text(decision)
	if next_step.is_empty() and not assignment_id.is_empty() and phase not in ["completed", "ended"]:
		next_step = "点工作目标查看进度。"
	return {"current":current, "assignment":assignment, "reason":reason, "next":next_step,
		"consent":consent, "carrying":carrying, "cargo":"、".join(cargo), "assignment_id":assignment_id,
		"project":module_id if order.has("building_phase") else ""}

static func render(ui, parent: VBoxContainer, id: String, state: Dictionary) -> void:
	var actor := P.find(ui.snapshot.get("actors", []), id)
	if actor.is_empty():
		C.caption(ui, "找不到这名同伴", parent)
		return
	var status := C.card(parent, true)
	C.image_row(ui, status, Identity.portrait(actor), "正在 · " + str(state.current), Identity.needs(actor), roundi(40 * ui.text_scale))
	if not str(state.assignment).is_empty(): ui.paragraph(str(state.assignment), status)
	if not str(state.cargo).is_empty(): ui.paragraph("正在携带 · " + str(state.cargo), status)
	_add_live_work(ui, status, id)
	if not str(state.reason).is_empty(): C.reason(ui, status, "受阻原因 · " + str(state.reason))
	if not str(state.next).is_empty(): C.caption(ui, "下一步 · " + str(state.next), status)
	if not str(state.consent).is_empty(): C.reason(ui, status, str(state.consent))
	if not str(state.project).is_empty():
		ui.add_button("查看工程", func(): ui.open_panel("factory_module", str(state.project)), "npc:building:open:" + id, "", status)
	if not str(state.assignment_id).is_empty():
		var clear: Dictionary = ui.request("workforce.clear", "")
		clear.actor_id = id
		var check: Dictionary = ui.availability(clear)
		var reason := "" if check.get("ok", false) else P.action_feedback(check, "workforce.clear")
		ui.add_button("解除当前岗位", func(): ui.execute("workforce.clear", "", {}, false, id), "npc:order:clear:" + id, reason, status)
		C.caption(ui, "解除岗位将取消指派。已有工程、工程进度和实际库存会保留。", status)
	if str(state.consent).is_empty():
		_render_dispatch(ui, parent, id)
	var skills: Dictionary = actor.get("skills", {})
	if skills.has("village_hauling") or skills.has("village_building"):
		var experience := C.fold(ui, parent, "npc:experience:" + id, "工作经验")
		if experience != null:
			C.caption(ui, "搬运 %s · 施工 %s" % [_skill_text(int(skills.get("village_hauling", 0))), _skill_text(int(skills.get("village_building", 0)))], experience)
			C.caption(ui, "完成交付与工程会积累经验。自动派工时，熟练者优先接手同一项工作。", experience)

static func _render_dispatch(ui, parent: VBoxContainer, id: String) -> void:
	var key := "npc:dispatch:" + id
	var mode := str(ui.factory_view.get(key, ""))
	var picking: bool = ui.is_companion_building_pick()
	if picking:
		C.caption(ui, "点选场景中的建筑，查看可安排的工作。", parent)
		ui.add_button("取消选择", ui.cancel_ui, "npc:building:pick:cancel", "", parent)
		return
	var row := HFlowContainer.new()
	parent.add_child(row)
	C.primary(ui.add_button("划区工作", func(): _toggle_dispatch(ui, key, "area"), "npc:work", "", row))
	C.primary(ui.add_button("建筑工作", func(): _toggle_dispatch(ui, key, "building"), "npc:building", "", row))
	if mode == "area":
		ui.add_button("砍树", func(): ui.start_companion_area(id, "forestry"), "npc:area:forestry", "", parent)
		ui.add_button("搬运地面物资", func(): ui.start_companion_area(id, "haul"), "npc:area:haul", "", parent)
	elif mode == "building":
		ui.add_button("选择现有建筑", func(): ui.begin_companion_building_pick(id), "npc:building:pick", "", parent)
		ui.add_button("建造住宅", func(): ui.open_companion_home_catalog(id), "npc:home:blueprint", "", parent)

static func _toggle_dispatch(ui, key: String, choice: String) -> void:
	ui.factory_view[key] = "" if ui.factory_view.get(key) == choice else choice
	ui.queue_refresh()

static func _skill_text(points: int) -> String:
	var level := "老练" if points >= 6 else "熟练" if points >= 2 else "新手"
	return "%s（%d）" % [level, points]

static func _add_live_work(ui, parent: VBoxContainer, id: String) -> void:
	if not is_instance_valid(ui.runtime) or not ui.runtime.has_method("actor_work_snapshot"): return
	var runtime: Object = ui.runtime
	var live := VBoxContainer.new()
	parent.add_child(live)
	var caption: Label = C.caption(ui, "", live)
	var progress := ProgressBar.new()
	progress.show_percentage = false
	live.add_child(progress)
	var update := func() -> void:
		if not is_instance_valid(runtime): return
		var work: Dictionary = runtime.actor_work_snapshot(id)
		live.visible = not work.is_empty()
		if work.is_empty(): return
		progress.max_value = float(work.duration_seconds)
		progress.value = float(work.progress_seconds)
		var reason := str(work.get("paused_reason", ""))
		var action := "正在施工" if work.kind == "construction" else "正在作业"
		if work.get("phase") == "queued": action = "等待开工"
		if not reason.is_empty(): action = P.reason_text(reason)
		caption.text = "%s · %s / %s 秒" % [action, P.number(progress.value), P.number(progress.max_value)]
	update.call()
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(update)
	live.add_child(timer)

static func footer(ui, parent: VBoxContainer, id: String, state: Dictionary) -> void:
	var actor := P.find(ui.snapshot.get("actors", []), id)
	if actor.is_empty(): return
	var row := HFlowContainer.new()
	parent.add_child(row)
	if str(state.consent).is_empty():
		ui.add_button("村务总览", func(): ui.open_panel("factory_people", id), "npc:workforce", "", row)
	var check: Dictionary = ui.availability(ui.request("talk", id))
	var reason := "" if check.get("ok", false) else P.action_feedback(check, "talk")
	var talk: Button = ui.button("交谈", func(): ui.execute("talk", id, {}, true), "npc:talk:" + id, reason)
	row.add_child(talk)
	if not str(state.consent).is_empty() and not talk.disabled: C.primary(talk)
	ui.add_button("人物与合作", func(): ui.open_panel("npc", id), "npc:details", "", row)
	if not reason.is_empty(): C.caption(ui, reason, parent)
