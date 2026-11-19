extends RefCounted
## WT01 public facility projection. No private balance, guessed source or clock.
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const Access = preload("res://scripts/ui/factory_service_access.gd")

static func approach(ui,parent:Node,row:Dictionary)->void:
	var command:Dictionary=Access.walk_command({"command":row.get("approach")})
	if command.is_empty():return
	var ready:Dictionary=ui.availability(ui.request("walk","",{},command.destination))
	if not ready.get("ok",false):return
	ui.add_button("走近储水设施",func():walk_near(ui,str(row.id),command),"water:nearby:"+str(row.id),"",parent)

static func walk_near(ui,id:String,expected:Dictionary)->Dictionary:
	var latest:Dictionary={}
	if is_instance_valid(ui.runtime) and ui.runtime.has_method("water_snapshot"):
		var value:Variant=ui.runtime.call("water_snapshot",str(P.player(ui.snapshot).get("id","player")),id)
		if value is Dictionary and value.get("available",false):latest=F.find(F.dictionaries(value.get("sources",[])),id)
	var command:Dictionary=Access.walk_command({"command":latest.get("approach")})
	if not latest.get("discovered",false) or command.is_empty() or command!=expected:
		ui.notify("储水设施附近通路已变化，请重新查看。",true);ui.queue_refresh()
		return {"ok":false,"code":"SERVICE_ACCESS_CHANGED"}
	return ui.execute("walk","",{},true,"",command.destination)

static func source(ui, id: String) -> Dictionary:
	var provider := F.section(ui.factory, "water")
	if provider.get("available") != true: return {}
	var row := F.find(F.dictionaries(provider.get("sources", [])), id)
	return row if row.get("discovered") == true else {}

static func project(ui, id: String) -> Dictionary:
	var intent: Variant = P.player(ui.snapshot).get("intent")
	if not intent is Dictionary or intent.get("owner") != "modules" or intent.get("kind") != "water": return {}
	var value := F.find(F.dictionaries(F.section(ui.factory, "water").get("projects", [])), str(intent.get("project_id", "")))
	return value if value.get("source_id") == id and value.get("actor_id") == "player" else {}

static func work(ui) -> Dictionary:
	var intent: Variant = P.player(ui.snapshot).get("intent")
	if not intent is Dictionary: return {}
	var current := project(ui, str(F.find(F.dictionaries(F.section(ui.factory, "water").get("projects", [])), str(intent.get("project_id", ""))).get("source_id", "")))
	if current.is_empty(): return {}
	return {"elapsed":current.get("progress_seconds"), "duration":current.get("duration_seconds"), "status":current.get("status"), "reason":current.get("paused_reason"), "operation":current.get("operation")}

static func render(ui, body: VBoxContainer, id: String) -> void:
	var provider := F.section(ui.factory, "water")
	var row := source(ui, id)
	if provider.get("available") != true:
		ui.paragraph(str(provider.get("reason", "储水设施服务尚未就绪；没有显示假储量或提交替代操作。")), body); return
	if row.is_empty():
		ui.paragraph("此设施尚未发现或已不可用，请回到现场按E查看；未知位置与储量不会公开。", body); return
	if not _quantity(row.get("remaining")) or not _quantity(row.get("reserved")) or float(row.reserved) > float(row.remaining):
		ui.paragraph("真实储量投影不完整，请稍后重试。", body); return
	var state := "待修复" if row.get("status") == "needs_repair" else "储备耗尽" if float(row.remaining) == 0 else "可手动取水"
	C.image_row(ui, body, Images.water_texture(row), state, "封闭可饮用储备 · 不会自动回满", roundi(80 * ui.text_scale))
	C.caption(ui,"靠近储水设施即可操作；距离不足时可先走近。",body)
	approach(ui,body,row)
	var balance := C.card(body)
	C.heading(ui, "有限剩余 " + P.number(row.remaining) + " 份", balance)
	C.caption(ui, "取水预约 " + P.number(row.reserved) + " · 未预约 " + P.number(float(row.remaining) - float(row.reserved)), balance)
	var allowed: Array = row.get("allowed_actions", [])
	var active := project(ui, id)
	if not str(row.get("project_id", "")).is_empty():
		if active.is_empty() or active.get("id") != row.project_id:
			ui.paragraph("此装置已有作业；当前没有可控制的本人项目。", body); return
		ui.paragraph(("修复装置" if active.get("operation") == "repair" else "手动取水") + " · " + F.state_text(active), body)
		var progress := P.progress({"elapsed":active.get("progress_seconds"), "duration":active.get("duration_seconds")})
		if not progress.is_empty():
			ui.paragraph("实际有效劳动 " + P.number(progress.value) + " / " + P.number(progress.maximum) + " 秒", body)
			var bar := ProgressBar.new(); bar.max_value = progress.maximum; bar.value = progress.value; bar.show_percentage = false; body.add_child(bar)
		if not str(active.get("paused_reason", "")).is_empty(): ui.paragraph(P.reason_text(active.paused_reason), body)
		var intent: Dictionary = P.player(ui.snapshot).intent
		if allowed.has("module.water.held"):
			_action(ui, body, "暂歇作业" if intent.get("held", true) else "恢复作业并回到现场", "held", id, {"held":not intent.get("held", true)}, not intent.get("held", true))
		ui.paragraph("取消释放未结算的物料／储水／容量预约；已付体力、工具磨损和劳动不退。", body)
		if allowed.has("module.water.cancel"): _action(ui, body, "取消本次作业", "cancel", id)
		ui.add_button("回到现场继续观察", ui.close_panels, "water:return", "", body)
		return
	var requirements: Dictionary = row.get("requirements", {})
	if allowed.has("module.water.repair"):
		var repair: Dictionary = requirements.get("repair", {})
		if repair.is_empty(): ui.paragraph("修复条件尚未提供，暂不能提交。", body); return
		_conditions(ui, body, repair, true)
		var stocks := _stocks(ui)
		var materials := Ops._choice(ui, body, "water:materials:" + id, "材料来源（需在可操作范围内）", stocks, str(P.player_stock(ui.snapshot).get("id", "")))
		var tools := _tools(ui, stocks, repair.get("qualities", {}))
		var tool := Ops._choice(ui, body, "water:tool:" + id, "独立作业工具", tools)
		if tools.is_empty(): ui.paragraph("已知公开库存中没有完好且未占用的适用手锤。请实际取到工具并到场。", body)
		_action(ui, body, "开始现场修复", "repair", id, {"source_id":materials,"tool_id":tool}, true)
	elif allowed.has("module.water.draw"):
		var draw: Dictionary = requirements.get("draw", {})
		if draw.is_empty(): ui.paragraph("取水条件尚未提供，暂不能提交。", body); return
		_conditions(ui, body, draw, false)
		var pack := P.player_stock(ui.snapshot)
		ui.paragraph("靠近储水设施即可操作；取入本人背包，提交时检查储量、预约和容量。", body)
		_action(ui, body, "手动取水 " + P.number(draw.get("amount")) + " 份", "draw", id, {"output_id":str(pack.get("id", ""))}, true)
	elif row.get("status") == "ready" and float(row.remaining) == 0:
		ui.paragraph("储备已经耗尽；修复、读档或重访不会补水。", body)
	else: ui.paragraph("当前未提供可用操作，保留真实状态。", body)

static func _quantity(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0

static func _conditions(ui, parent: Node, row: Dictionary, repair: bool) -> void:
	if repair:
		ui.item_row(row.get("materials", {}), "修复消耗（完工结算）", parent)
		for id in row.get("knowledge", []): ui.paragraph("知识 · " + P.item_name(str(id)), parent)
		for key in row.get("qualities", {}): ui.paragraph(("锤击" if key == "hammering" else "工具能力 " + str(key)) + " " + P.number(row.qualities[key]), parent)
	ui.paragraph("有效工时 " + P.number(row.get("seconds")) + " 秒 · 体力每秒 " + P.number(row.get("stamina_per_second")), parent)
	if row.has("tool_wear"): ui.paragraph("全程工具磨损 " + P.number(row.tool_wear), parent)

static func _stocks(ui) -> Array:
	var pack := P.player_stock(ui.snapshot)
	var result: Array = []
	for stock: Dictionary in P.records(ui.snapshot.get("stocks", [])):
		var id := str(stock.get("id", ""))
		if id != pack.get("id") and id.begins_with("pack:"): continue
		if not F.stock_visible(ui.factory, ui.snapshot, id) or stock.get("display_only", false): continue
		result.append({"id":id,"name":"随身背包" if id == pack.get("id") else str(stock.get("name", "已知库存")),"description":F.location(stock.get("location")),"stock":stock})
	return result

static func _tools(ui, stocks: Array, qualities: Dictionary) -> Array:
	var result: Array = []
	for stock: Dictionary in stocks:
		for entry: Dictionary in P.entries(stock.stock, ui.snapshot):
			if entry.get("reference", {}).get("kind") != "tool" or float(entry.get("available", 0)) <= 0 or float(entry.get("durability", 0)) <= 0: continue
			var definition: Dictionary = ui.snapshot.get("catalog", {}).get("tool_definitions", {}).get(str(entry.get("definition_id", "")), {})
			if not qualities.keys().all(func(key): return float(definition.get("qualities", {}).get(key, 0)) >= float(qualities[key])): continue
			result.append({"id":entry.reference.tool_id,"name":str(entry.name) + " · " + str(stock.name) + " · 耐久 " + P.number(entry.durability)})
	return result

static func _action(ui, parent: Node, title: String, operation: String, id: String, payload: Dictionary = {}, resume: bool = false) -> void:
	var kind := "module.water." + operation
	var ready: Dictionary = ui.availability(ui.request(kind, id, payload))
	ui.add_button(title, func(): ui.execute(kind, id, payload, resume), "water:command:" + operation + ":" + id, "" if ready.get("ok", false) else P.feedback_text(ready), parent)
