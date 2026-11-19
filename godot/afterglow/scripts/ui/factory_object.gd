extends RefCounted
## Object inspection follows the physical flow; no recipes, costs or state are
## calculated here. Every number below is from B's current public projection.
const Images = preload("res://scripts/ui/ui_images.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")
const Access = preload("res://scripts/ui/factory_service_access.gd")
const Book = preload("res://scripts/ui/factory_handbook.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const LifeCare = preload("res://scripts/ui/life_care.gd")
const Mechanisms = preload("res://scripts/ui/factory_mechanisms.gd")
const Identity18 = preload("res://scripts/ui/building_identity.gd")
const Recipes18 = preload("res://scripts/ui/building_recipe_actions.gd")
const Life18 = preload("res://scripts/ui/building_life_actions.gd")
const Storage18 = preload("res://scripts/ui/building_storage_actions.gd")
const Hero19 = preload("res://scripts/ui/building_hero19.gd")
const BUFFER_NAMES := {"input":"原料箱", "output":"成品箱", "fuel":"燃料箱", "tools":"工具架", "supplies":"生活物资", "storage":"仓储"}

static func main_reason(row: Dictionary) -> String:
	var blockers: Variant = row.get("blockers", [])
	if blockers is Array and not blockers.is_empty():
		var first: Variant = blockers[0]
		var raw := str(first.get("reason", first.get("label", first.get("code", "")))) if first is Dictionary else str(first)
		return str(F.STATE_NAMES.get(raw, P.reason_text(raw)))
	var code := str(row.get("state_code", row.get("status", "")))
	return str(row.get("state_label", F.STATE_NAMES.get(code, ""))) if code not in ["running", "idle", "target_met", "active", "completed"] else ""

static func render(ui, body: VBoxContainer, id: String) -> void:
	if body.has_meta("ui_building_actions"): body.remove_meta("ui_building_actions")
	var module := F.instance(ui.factory, id)
	if module.is_empty():
		C.reason(ui, body, "建筑当前不可见，请重新选择。")
		return
	var definition := F.definition(ui.factory, str(module.get("definition_id", "")))
	Hero19.render(ui, body, module, definition)
	var work: Dictionary = module.get("visuals", {}).get("construction", {})
	var rebuilding: bool = module.get("repair_action", {}).get("rebuild", false) or (
		work.get("rebuild", false) and (_active_maintenance(work, "repair") or _active_maintenance(work, "restore")))
	var restoring := not rebuilding and _is_restoring(module, work)
	var repairing := rebuilding or _is_repairing(module, work)
	_render_integrity(ui, body, module, restoring)
	if restoring or repairing:
		body.set_meta("ui_building_actions", id)
		_render_repair(ui, body, module, definition, work, restoring, rebuilding)
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	var key := "building_tab:" + id
	var selected := str(ui.factory_view.get(key, "use"))
	for spec: Array in [["use", "可用功能"], ["manage", "管理与维护"]]:
		var tab_id := str(spec[0])
		var tab: Button = ui.add_button(str(spec[1]), func():
			ui.cancel_transient()
			ui.factory_view[key] = tab_id
			ui.queue_refresh(), "building:tab:" + tab_id + ":" + id, "", tabs)
		tab.toggle_mode = true
		tab.set_pressed_no_signal(selected == tab_id)
		tab.theme_type_variation = "PrimaryButton" if selected == tab_id else "QuietButton"
	if selected == "manage":
		_details(ui, body, id)
		return
	if restoring or rebuilding: return
	body.set_meta("ui_building_actions", id)
	if not repairing and not work.is_empty() and work.get("phase") != "completed":
		var progress := C.card(body, true)
		_work_status(ui, progress, module, work)
		Ops.module_work(ui, progress, module)
	if not repairing: Ops.companion_project(ui, body, module)
	_expedition_preparation(ui, body, module)
	Life18.render(ui, body, module, definition)
	Recipes18.render(ui, body, module, definition)
	Storage18.render(ui, body, module, definition)
	var preferred:String=ui.building_dispatch_actor() if ui.has_method("building_dispatch_actor") else ""
	if module.get("status")=="operational" and preferred.is_empty():
		var has_recipe:bool=not module.get("recipe_management",{}).get("recipes",[]).is_empty()
		var has_buffer:bool=F.section(ui.factory,"logistics").get("available",false) and F.known_stocks(ui.factory,ui.snapshot,module).any(func(ref:Dictionary)->bool:return ref.get("stock",{}).get("searched",false))
		var workers:=Ops.worker_choices(ui) if has_recipe or has_buffer else []
		if not workers.is_empty():
			var dispatch:=C.fold(ui,body,"building:assign:"+id,"安排同伴")
			if dispatch!=null:
				for worker:Dictionary in workers:
					var actor_id:String=str(worker.id)
					ui.add_button(str(worker.name),func():ui.open_panel("factory_module",id,actor_id),"building:pick-worker:"+actor_id+":"+id,"",dispatch)
	if module.get("status")=="operational" and not preferred.is_empty():
		var worker:=P.find(ui.snapshot.get("actors",[]),preferred)
		C.heading(ui,"安排"+str(worker.get("name","同伴")),body)
		Mechanisms.recipes(ui,body,module,true)
		if F.section(ui.factory,"logistics").get("available",false):
			for ref:Dictionary in F.known_stocks(ui.factory,ui.snapshot,module):
				if not ref.get("stock",{}).get("searched",false):continue
				var buffer_id:String=str(ref.get("buffer_id",""));var stock_id:String=str(ref.stock_id)
				if buffer_id in ["storage","output"]:ui.add_button("从此处运出",func():begin_logistics(ui,module,ref,true,preferred),"building:dispatch:out:"+stock_id,"",body)
				if buffer_id in ["storage","input","fuel","supplies"]:ui.add_button("送到"+str(BUFFER_NAMES.get(buffer_id,"此处")),func():begin_logistics(ui,module,ref,false,preferred),"building:dispatch:in:"+stock_id,"",body)
	var links := HFlowContainer.new()
	body.add_child(links)
	Book.shortcut(ui, links, "module:" + str(module.get("definition_id", "")), "module:" + id, "用途与帮助")

static func _is_restoring(module: Dictionary, work: Dictionary) -> bool:
	return module.get("state_code") == "needs_restoration" or module.get("structural_integrity", {}).get("state_code") == "needs_restoration" or _active_maintenance(work, "restore")

static func _is_repairing(module: Dictionary, work: Dictionary) -> bool:
	return not module.get("repair_action", {}).is_empty() or _active_maintenance(work, "repair")

static func _active_maintenance(work: Dictionary, operation: String) -> bool:
	return work.get("operation") == operation and work.get("phase") not in ["completed", "cancelled"]

static func _render_integrity(ui, body: VBoxContainer, module: Dictionary, restoring: bool) -> void:
	var integrity: Dictionary = module.get("structural_integrity", {})
	var maximum := float(integrity.get("max_hp", 0))
	var state := str(integrity.get("state_code", ""))
	if maximum <= 0 or state in ["planned", "constructing", "dismantled"]: return
	var hp := float(integrity.get("hp", 0))
	var percent := floori(clampf(hp / maximum, 0.0, 1.0) * 100.0)
	var label := "待首次修缮" if restoring else "残骸" if state == "ruined" else "受损" if hp < maximum else "完好"
	var status := C.caption(ui, "结构完好度 %d%% · %s" % [percent, label], body)
	status.set_meta("ui_structural_integrity", str(module.id))

static func _render_repair(ui, body: VBoxContainer, module: Dictionary, definition: Dictionary, work: Dictionary, restoring: bool, rebuilding: bool) -> void:
	var id := str(module.id)
	var verb := "原地重建" if rebuilding else "修缮" if restoring else "维修"
	var card := C.card(body, true)
	card.set_meta("ui_restoration_card" if restoring else "ui_damage_repair_card", id)
	C.heading(ui, "原地重建 · " + Identity18.instance_name(definition, module) if rebuilding else verb + Identity18.instance_name(definition, module), card)
	if rebuilding:
		C.caption(ui, "按原占地与朝向重建。完工后恢复建筑用途。", card)
	elif restoring:
		var benefit := str({
			"home": "恢复住宿与休息",
			"warehouse": "恢复仓储与物资取放",
			"sawmill": "恢复木材加工设备",
		}.get(Identity18.family(definition), Identity18.purpose(definition)))
		C.caption(ui, "修缮后 · " + benefit, card)
	else:
		C.caption(ui, "维修后恢复建筑耐久。", card)
	if _active_maintenance(work, "restore" if restoring else "repair") or (rebuilding and _active_maintenance(work, "restore")):
		if restoring:
			Ops.restoration(ui, card, module, true)
		else:
			_work_status(ui, card, module, work)
			_repair_project_controls(ui, card, module, work, "重建" if rebuilding else "维修")
		var pending: bool = F.section(ui.factory, "workforce").get("building_queue", []).has(id)
		if not rebuilding or work.get("phase") == "paused" or pending or _has_building_order(ui, id):
			Ops.companion_project(ui, card, module)
		return
	var requirements: Dictionary = module.get("restoration_requirements", {})
	var ready: Dictionary = module.get("restoration_action" if restoring else "repair_action", {})
	var request: Dictionary = ready.get("command", {})
	var kind := "module.restore" if restoring else "module.repair"
	if request.get("kind") != kind or request.get("target_id") != id:
		C.reason(ui, card, "该建筑的" + verb + "条件暂不可查看。")
		return
	var seconds := float(requirements.get("seconds", 0)) if restoring else float(ready.get("duration_seconds", 0))
	if seconds > 0: C.caption(ui, "现场工时 " + P.number(seconds) + " 秒", card)
	var payload: Dictionary = request.get("payload", {})
	var actions := HFlowContainer.new()
	card.add_child(actions)
	var preflight: Dictionary = ready
	if ready.get("available", false): preflight = ui.availability(ui.request(kind, id, payload))
	var blocked := "" if preflight.get("ok", false) else P.feedback_text(preflight)
	var restore: Button = ui.button("亲自" + verb, func(): ui.execute(kind, id, payload, true), "factory:command:" + kind + ":" + id, blocked)
	C.primary(restore)
	actions.add_child(restore)
	var preferred: String = ui.building_dispatch_actor() if ui.has_method("building_dispatch_actor") else ""
	var workforce := F.section(ui.factory, "workforce")
	var has_order: bool = workforce.get("building_queue", []).has(id) or _has_building_order(ui, id)
	var assign_ready: Dictionary = {}
	if not has_order and preferred.is_empty():
		assign_ready = ui.availability(ui.request("workforce.queue_building", id))
	if has_order:
		Ops.companion_project(ui, card, module)
	elif preferred.is_empty():
		var reason := "" if assign_ready.get("ok", false) else P.feedback_text(assign_ready)
		var assign: Button = ui.button("安排" + verb, func():
			var result: Dictionary = ui.execute("workforce.queue_building", id, {}, true)
			if result.get("ok", false): ui.notify("已加入村务待办 · 同伴有空时接手"), "building:worker:auto:" + id, reason)
		actions.add_child(assign)
		if not reason.is_empty(): C.reason(ui, card, reason)
		var workers := Ops.worker_choices(ui)
		if not workers.is_empty():
			var picker := C.fold(ui, card, "repair-workers:" + id, "指定同伴")
			if picker != null:
				for worker: Dictionary in workers: _assign_repair(ui, picker, id, verb, str(worker.id), str(worker.name))
	else:
		var worker := P.find(ui.snapshot.get("actors", []), preferred)
		var assignment_problem := _assign_repair(ui, actions, id, verb, preferred, str(worker.get("name", "同伴")))
		if not assignment_problem.is_empty(): C.reason(ui, card, assignment_problem)
	if not blocked.is_empty(): C.reason(ui, card, blocked)
	elif ready.get("auto_approach", false): C.caption(ui, "亲自" + verb + "会自动走近建筑。", card)
	for material: Dictionary in ready.get("materials", []):
		var line := "%s · 需要 %s / 随身可用 %s" % [P.item_name(str(material.get("item_id", ""))), P.number(material.get("required")), P.number(material.get("available"))]
		if float(material.get("missing", 0)) > 0: line += " · 还缺 " + P.number(material.missing)
		C.caption(ui, line, card)
	if restoring and ready.get("materials", []).is_empty():
		C.materials(ui, card, requirements.get("cost", {}), P.player_stock(ui.snapshot), "修缮材料", false)
	var tool: Dictionary = ready.get("tool", {})
	if not tool.is_empty(): C.caption(ui, str(tool.get("name", "锤子")) + " · " + ("随身可用" if tool.get("available", false) else "随身缺少可用工具"), card)

static func _assign_repair(ui, parent: Node, id: String, verb: String, actor_id: String, actor_name: String) -> String:
	var payload := {"candidate_id": "building-order:" + id}
	var command: Dictionary = ui.request("workforce.assign", "", payload)
	command.actor_id = actor_id
	var ready: Dictionary = ui.availability(command)
	var reason := "" if ready.get("ok", false) else P.feedback_text(ready)
	var assign: Button = ui.button("安排" + verb + " · " + actor_name, func():
		var result: Dictionary = ui.execute("workforce.assign", "", payload, true, actor_id)
		if result.get("ok", false): ui.notify("已安排" + verb), "building:worker:" + actor_id + ":" + id, reason)
	parent.add_child(assign)
	if not reason.is_empty() and not parent is HFlowContainer: C.reason(ui, parent, reason)
	return reason

static func _repair_project_controls(ui, card: VBoxContainer, module: Dictionary, work: Dictionary, verb: String) -> void:
	var id := str(module.id)
	var project_id := str(work.get("project_id", ""))
	var allowed: Array = module.get("allowed_actions", [])
	var player := P.player(ui.snapshot)
	var intent: Variant = player.get("intent")
	var owns: bool = work.get("actor_id") == player.get("id") and intent is Dictionary and not project_id.is_empty() and (
		(intent.get("owner") == "modules" and intent.get("project_id") == project_id)
		or (intent.get("owner") == "actions" and intent.get("workforce_candidate_id") == "module-project:" + project_id)
	)
	if owns and allowed.has("module.held"):
		var held: bool = intent.get("held", true)
		C.primary(Ops.action(ui, card, ("暂停" if held else "继续") + verb, "module.held", id, {"held": not held}))
	elif work.get("phase") in ["paused", "queued"] and allowed.has("module.work"):
		C.primary(Ops.action(ui, card, "接续" + verb, "module.work", id))
	if allowed.has("module.cancel"):
		Ops.action(ui, card, "取消" + verb + "…", "module.cancel", id, {}, "", "结束本次工程并释放尚未消费的材料与工具预约。")

static func _has_building_order(ui, id: String) -> bool:
	return F.rows(ui.factory, "workforce", "assignments").any(func(order: Dictionary) -> bool:
		return order.has("building_phase") and order.get("module_id") == id and order.building_phase not in ["completed", "ended"])

static func _expedition_preparation(ui, body: VBoxContainer, module: Dictionary) -> void:
	if module.id != "r34:generated:RH-HOME:woodwork":
		return
	var expedition: Dictionary = ui.snapshot.get("expedition", {})
	if not expedition.get("may_prepare", false):
		return
	var card := C.card(body, true)
	C.heading(ui, "下次出征", card)
	if not str(expedition.get("prepared", "")).is_empty():
		C.caption(ui, "已备好" + str(expedition.prepared_label) + " · 下一趟首波生效", card)
		return
	C.caption(ui, "急救包在首波恢复生命并降低本趟伤害。硬头箭能穿过第一只感染者。每趟任选一种。", card)
	for choice: Array in [["medical", "急救包"], ["tipped", "硬头箭"]]:
		var payload := {"preparation": choice[0]}
		var ready: Dictionary = ui.availability(ui.request("expedition.prepare", "", payload))
		var reason := "" if ready.get("ok", false) else P.feedback_text(ready)
		ui.add_button(str(choice[1]) + " · 3 废料", func():
			ui.execute("expedition.prepare", "", payload), "expedition:prepare:" + str(choice[0]), reason, card)

static func _work_status(ui, parent: Node, module: Dictionary, work: Dictionary) -> void:
	var phase := str(work.get("phase", ""))
	var reason := str(work.get("paused_reason", "") if work.get("paused_reason") != null else "")
	var title := str({
		"working":"现场施工中", "approaching":"前往施工点", "paused":"施工暂停",
		"cancelled":"工程已取消", "queued":"等待安排施工",
	}.get(phase, "待施工" if module.get("status") == "planned" else "施工进度"))
	C.heading(ui, title, parent)
	var progress := F.progress(work)
	if not progress.is_empty():
		var bar := ProgressBar.new()
		bar.value = float(progress.value) * 100.0
		bar.show_percentage = false
		parent.add_child(bar)
		C.caption(ui, str(progress.text), parent)
	if not reason.is_empty(): C.reason(ui, parent, P.reason_text(reason))

static func _details(ui, body: VBoxContainer, id: String) -> void:
	var row := F.instance(ui.factory, id)
	if row.is_empty():
		C.reason(ui, body, "原设施已不可见或不存在。请返回设施列表。")
		return
	var definition := F.definition(ui.factory, str(row.get("definition_id", "")))
	var modes: Array = definition.get("recipe_modes", [])
	var machine := modes.has("machine")
	var manual := modes.has("manual") or modes.has("labor")
	var access:Dictionary=ui.read_service_approaches(id)
	Access.nearby(ui,body,row,access)
	var reason := main_reason(row)
	var work_dto:Dictionary=row.get("visuals",{}).get("construction",{})
	var restoring := _is_restoring(row, work_dto)
	var repairing := _is_repairing(row, work_dto)
	var has_repair_card := restoring or repairing
	if not reason.is_empty() and not has_repair_card: C.reason(ui, body, reason)
	var construction := F.progress(row.get("visuals", {}).get("construction", {}))
	if not construction.is_empty() and not has_repair_card:
		C.caption(ui, "现场作业 · " + str(construction.text), body)
		var bar := ProgressBar.new(); bar.value = construction.value * 100; bar.show_percentage = false; body.add_child(bar)
		if not str(construction.reason).is_empty(): C.reason(ui, body, P.reason_text(construction.reason))
	var order := F.find(F.rows(ui.factory, "production", "orders"), id, "module_id")
	if not order.is_empty():
		C.caption(ui, "目标 · " + ("持续生产" if int(order.get("remaining", 0)) < 0 else "剩余 " + P.number(order.get("remaining")) + " 批") + " / 已完成 " + P.number(order.get("completed")) + " 批", body)
	var stocks := F.known_stocks(ui.factory, ui.snapshot, row)
	var unknown: Array = stocks.filter(func(ref: Dictionary): return ref.stock.is_empty() or not ref.stock.get("searched", false))
	if not unknown.is_empty():
		var undiscovered := C.card(body)
		C.caption(ui, "尚未搜索的缓存不显示内容。靠近建筑即可搜索与取放。", undiscovered)
		# One shared explanation, while preserving each actual endpoint action.
		for ref: Dictionary in unknown:
			C.caption(ui, str(BUFFER_NAMES.get(ref.buffer_id, "设施缓存")), undiscovered)
			Access.guide(ui, undiscovered, row, ref.stock_id, access, false)
	if machine:
		var flow := C.card(body)
		C.heading(ui, "原料 → 加工 → 成品", flow)
		_buffer(ui, flow, row, stocks, "input", access)
		var batches := F.rows(ui.factory, "production", "batches").filter(func(batch: Dictionary): return batch.get("module_id") == id and batch.get("status") in ["active", "blocked", "refund_pending"])
		if batches.is_empty(): C.caption(ui, "尚无在制批次", flow)
		for batch: Dictionary in batches: Ops.batch(ui, flow, batch)
		_buffer(ui, flow, row, stocks, "output", access)
		var energy := C.card(body)
		C.heading(ui, "燃料与设备", energy)
		if order.has("energy_seconds"): C.caption(ui, "本地能量 · " + P.number(order.energy_seconds) + " 有效工作秒", energy)
		_buffer(ui, energy, row, stocks, "fuel", access)
		_buffer(ui, body, row, stocks, "tools", access)
		if row.get("state_code") != "needs_restoration":
			var configure := C.fold(ui, body, "configure:" + id, "配方与生产目标", order.is_empty())
			if configure != null: Ops.machine(ui, configure, id)
	elif manual:
		var work := C.card(body)
		C.heading(ui, "手工作业与工具", work)
		C.caption(ui, "靠近建筑即可选择工位配方；每次制作一批，受理后回到场景劳动。", work)
		for key: String in ["tools", "input", "output"]: _buffer(ui, work, row, stocks, key, access)
		var stations: Dictionary = {}
		var members: Array = row.get("members", []).map(func(member): return str(member.get("id", "")))
		for target: Dictionary in P.records(ui.snapshot.get("work_targets", [])):
			var station := str(target.get("actual_target_id", ""))
			if members.has(station) and target.get("work_payload", {}).get("action_kind") == "craft": stations[station] = true
		for station: String in stations:
			C.primary(ui.add_button("查看工位配方", func(): ui.open_panel("workbench", station), "factory:workbench:" + station, "", work))
	else:
		var storage := C.card(body)
		var home: bool = definition.get("generation_role") == "home"
		C.heading(ui, "生活补给" if home else "容量与取放", storage)
		for ref: Dictionary in stocks: _buffer(ui, storage, row, stocks, str(ref.buffer_id), access)
		if home:
			ui.housing_view.render(ui,body,id)
			var care := C.card(body)
			C.heading(ui, "自身照料与同伴", care)
			C.caption(ui, "随身物资和实际寝具仍按现场条件校验。", care)
			LifeCare.render(ui,care)
			ui.add_button("查看同伴与岗位", func(): ui.open_panel("factory_people"), "factory:home:people:" + id, "", care)
	if F.section(ui.factory, "logistics").get("available", false) and not stocks.is_empty():
		var workers := C.fold(ui, body, "workers:" + id, "取送与人员安排")
		if workers != null:
			var tasks := F.rows(ui.factory, "logistics", "tasks").filter(func(task: Dictionary): return row.get("stock_refs", {}).values().has(task.get("source_id")) or row.get("stock_refs", {}).values().has(task.get("destination_id")))
			if tasks.is_empty(): C.caption(ui, "尚未安排真实取送", workers)
			for task: Dictionary in tasks:
				var actor := P.find(ui.snapshot.get("actors", []), str(task.get("actor_id", "")))
				C.caption(ui, str(actor.get("name", "待分配")) + " · " + F.state_text(task), workers)
				if task.get("phase")=="deliver" and task.get("status") not in ["completed","cancelled"]:
					ui.item_row(task.get("items",{}),"在途（尚未加入此处可用量）",workers)
			ui.add_button("完整物流与岗位", func(): ui.open_panel("factory_logistics", id), "factory:logistics:" + id, "", workers)
	Mechanisms.recipes(ui,body,row)
	Mechanisms.stock_policies(ui,body,row)
	Mechanisms.upgrades(ui,body,row)
	# Reference material follows the object's primary work/supplies, rather
	# than occupying an action row between identity and its useful content.
	var links := HFlowContainer.new(); body.add_child(links)
	Book.shortcut(ui, links, "module:" + str(row.get("definition_id", "")), "module:" + id, "查阅手册")
	var maintenance := C.fold(ui, body, "maintenance:" + id, "维护、拆迁与设施详情", row.get("status") in ["planned", "building", "ruined"] or not str(row.get("project_id", "")).is_empty())
	if maintenance != null:
		C.caption(ui, F.location(row.get("location")), maintenance)
		var damage: Dictionary = row.get("visuals", {}).get("damage", {})
		if damage.has("hp"): C.caption(ui, "耐久 " + P.number(damage.hp) + " / " + P.number(damage.get("max_hp")), maintenance)
		if not has_repair_card:
			Ops.module_work(ui, maintenance, row)
		elif not restoring and not _active_maintenance(work_dto, "repair"):
			var other_actions := row.duplicate()
			var allowed: Array = row.get("allowed_actions", [])
			other_actions.allowed_actions = allowed.filter(func(operation: String) -> bool: return operation != "module.repair")
			Ops.module_work(ui, maintenance, other_actions)
	if machine:
		var history := C.fold(ui, body, "history:" + id, "批次记录与下一批条件")
		if history != null:
			for batch: Dictionary in F.rows(ui.factory, "production", "batches"):
				if batch.get("module_id") == id and batch.get("status") not in ["active", "blocked", "refund_pending"]: Ops.batch(ui, history, batch)
			for blocker: Dictionary in F.dictionaries(row.get("next_batch_blockers", [])): C.caption(ui, str(blocker.get("reason", blocker.get("label", ""))), history)

static func _buffer(ui, parent: Node, module: Dictionary, stocks: Array, key: String, access: Dictionary) -> void:
	var matches := stocks.filter(func(ref: Dictionary): return ref.buffer_id == key and not ref.stock.is_empty() and ref.stock.get("searched", false))
	for ref: Dictionary in matches:
		C.caption(ui, str(BUFFER_NAMES.get(key, "设施缓存")), parent)
		var actions := HFlowContainer.new(); parent.add_child(actions)
		var taking := key == "output"
		C.primary(ui.add_button("取放成品" if taking else "取放" + str(BUFFER_NAMES.get(key, "缓存")), func(): ui.open_panel("factory_inventory", str(ref.stock_id)), "factory:stock:" + str(ref.stock_id), "", actions))
		if F.section(ui.factory, "logistics").get("available", false) and key in ["input", "output", "fuel"]:
			ui.add_button("安排清运" if taking else "安排供料", func(): begin_logistics(ui, module, ref, taking), "factory:arrange:" + str(ref.stock_id), "", actions)
		for buffer: Dictionary in F.stock_buffers(ui.factory, str(ref.stock_id)):
			ui.paragraph(F.buffer_text(buffer), parent)
		var visit := C.fold(ui, parent, "access:" + str(ref.stock_id), "走近建筑与取放")
		if visit != null: Access.guide(ui, visit, module, ref.stock_id, access, true)

static func begin_logistics(ui, module: Dictionary, ref: Dictionary, taking: bool, worker_id:String="") -> void:
	# Prefill only actual endpoint identities. Other choices remain the player's,
	# and B rechecks ownership, cargo, contact and capacities on every command.
	ui.factory_view["logistics_source" if taking else "logistics_destination"] = str(ref.stock_id)
	ui.factory_view.erase("logistics_destination" if taking else "logistics_source")
	var buffers := F.stock_buffers(ui.factory, str(ref.stock_id))
	if not buffers.is_empty(): ui.factory_view.logistics_item = str(buffers[0].get("item_id", ""))
	ui.factory_view.logistics_context = {"module_id":module.id, "stock_id":ref.stock_id, "direction":"out" if taking else "in"}
	if worker_id.is_empty():ui.open_panel("factory_logistics", str(module.id))
	else:ui.open_panel("factory_logistics",str(module.id),worker_id)
