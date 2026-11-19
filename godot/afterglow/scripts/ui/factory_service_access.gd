extends RefCounted
## Read B's detached service-access proof. Never derive feet or search on arrival.
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")

static func rows(provider: Dictionary, module: Dictionary) -> Array:
	if module.is_empty() or provider.get("module_id") != module.get("id"): return []
	var refs: Variant = module.get("stock_refs", {})
	if not refs is Dictionary: return []
	return F.dictionaries(provider.get("approaches", [])).filter(func(row: Dictionary):
		return row.get("id") is String and not row.id.is_empty() and refs.values().has(row.get("stock_ref")))

static func walk_command(row: Dictionary) -> Dictionary:
	var command: Variant = row.get("command")
	if not command is Dictionary or command.get("kind") != "walk" or command.get("target_id") != "" or command.get("payload") != {}: return {}
	var destination: Variant = command.get("destination")
	if not destination is Dictionary or not destination.get("regionId") is String or str(destination.regionId).is_empty(): return {}
	for key: String in ["x", "y", "z"]:
		if not (destination.get(key) is int or destination.get(key) is float) or not is_finite(float(destination[key])): return {}
	return command.duplicate(true)

static func access_reason(provider: Dictionary, row: Dictionary) -> String:
	if provider.get("available") != true:
		var reason := str(provider.get("reason", "")).strip_edges()
		return reason if not reason.is_empty() else "建筑暂不可操作"
	if row.get("available") != true:
		var reason := str(row.get("reason", "")).strip_edges()
		return reason if not reason.is_empty() else "暂时无法走近建筑"
	return ""

static func nearby(ui,parent:Node,module:Dictionary,provider:Dictionary)->void:
	ui.paragraph("靠近建筑即可操作；材料、工具与库存容量仍需满足。",parent)
	var candidates:Array=rows(provider,module)
	if candidates.any(func(row:Dictionary):return provider.get("available",false) and row.get("at_service",false)):return
	for row:Dictionary in candidates:
		var command:Dictionary=walk_command(row)
		if not access_reason(provider,row).is_empty() or command.is_empty():continue
		var ready:Dictionary=ui.availability(ui.request("walk","",{},command.destination))
		if not ready.get("ok",false):continue
		ui.add_button("走近建筑",func():activate(ui,str(module.id),str(row.id),command),"factory:nearby:"+str(module.id),"",parent)
		return

static func guide(ui, parent: Node, module: Dictionary, stock_id: String, provider: Dictionary, searched: bool, compact: bool = false) -> void:
	var candidates: Array = rows(provider, module).filter(func(row: Dictionary): return row.stock_ref == stock_id)
	if candidates.is_empty(): return
	for row: Dictionary in candidates:
		var name := str(row.get("label", "物资缓存"))
		var guidance: Dictionary = ui.factory_view.get("service_walk", {})
		var intent: Variant = P.player(ui.snapshot).get("intent")
		if guidance.get("world_id") == ui.factory.get("world_id") and guidance.get("module_id") == module.id and guidance.get("approach_id") == row.id and intent is Dictionary and intent.get("owner") == "actions" and intent.get("kind") == "walk" and intent.get("request", {}).get("destination") == guidance.get("destination"):
			ui.paragraph("正在走近建筑，到达后可操作；行走不会自动搜索或取物。", parent)
			Panels._action(ui, "取消走近建筑", "cancel_work", "", {}, parent, true)
		if provider.get("available", false) and row.get("at_service", false):
			ui.paragraph("已靠近建筑" + ("；搜索后才能取放。" if not searched else "，可查看取放。"), parent)
			if not searched: Panels._action(ui, "搜索此缓存", "search", stock_id, {}, parent, true)
			continue
		var command := walk_command(row)
		var reason := access_reason(provider, row)
		if command.is_empty() and reason.is_empty(): reason = "建筑附近尚无可用的到达路径"
		if reason.is_empty():
			var ready: Dictionary = ui.availability(ui.request("walk", "", {}, command.destination))
			if not ready.get("ok", false): reason = P.feedback_text(ready, {}, "暂时无法前往")
		var title := "走近建筑" if compact else "走近建筑 · " + name
		ui.add_button(title, func(): activate(ui, str(module.id), str(row.id), command), "factory:service:" + str(module.id) + ":" + str(row.id), reason, parent)

static func activate(ui, module_id: String, approach_id: String, expected: Dictionary) -> Dictionary:
	# Re-resolve the public proof when clicked. Never silently substitute a new
	# destination after movement, reconstruction, ownership or region changes.
	var provider: Dictionary = ui.read_service_approaches(module_id, true)
	var module := F.instance(ui.factory, module_id)
	var row := F.find(rows(provider, module), approach_id)
	var command := walk_command(row)
	var reason := access_reason(provider, row)
	if provider.get("available") == true and row.is_empty(): reason = "建筑附近通路已变化，请重新选择"
	elif reason.is_empty() and (command.is_empty() or command != expected): reason = "建筑附近通路已变化，请重新选择"
	if not reason.is_empty():
		ui.notify(reason, true); ui.queue_refresh()
		return {"ok":false, "code":"SERVICE_ACCESS_CHANGED", "reason":reason}
	var result: Dictionary = ui.execute("walk", "", {}, true, "", command.destination)
	if result.get("ok", false):
		# View-only reference for the cancel affordance; actual intent must match.
		ui.factory_view.service_walk = {"world_id":ui.factory.get("world_id"), "module_id":module_id, "approach_id":approach_id, "destination":command.destination.duplicate(true)}
		ui.notify("正在走近建筑 · 到达后即可查看、搜索与取放")
	else:
		ui.notify(P.feedback_text(result, {}, "暂时无法走近建筑"), true)
		ui.queue_refresh()
	return result
