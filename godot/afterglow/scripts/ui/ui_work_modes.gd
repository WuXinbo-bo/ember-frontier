extends RefCounted
## Native work-mode view over A's router state; no world targets or work facts.
const P = preload("res://scripts/ui/ui_projection.gd")
const NAMES := {"tool":"手持工具／使用", "repair":"维修", "move":"搬移", "demolish":"拆卸", "destroy":"破坏", "terrain_dig":"挖掘", "terrain_fill":"填土", "terrain_level":"整平", "facility_place":"可搬设施选址"}
const MATERIALS := {2:"土", 3:"石", 6:"碎石"}

static func key(hand: Dictionary, action: String, fallback: int) -> String:
	var bindings: Dictionary = hand.get("bindings", {})
	return P.binding_label(bindings.get(action, fallback))

static func keys(hand:Dictionary,action:String,fallback:int)->String:
	var binding:Variant=hand.get("bindings",{}).get(action,fallback)
	var labels:Array[String]=[P.binding_label(binding)]
	if binding is Dictionary:
		for alias:Variant in binding.get("aliases",[]):labels.append(P.binding_label(alias))
	return " / ".join(labels)

static func matches(event:InputEventKey,hand:Dictionary,action:String,fallback:int)->bool:
	var binding:Variant=hand.get("bindings",{}).get(action,fallback)
	var code:int=P.physical_key(event)
	if code==P.binding_code(binding,fallback):return true
	if binding is Dictionary:
		for alias:Variant in binding.get("aliases",[]):
			if code==P.binding_code(alias):return true
	return false

static func modes(hand: Dictionary) -> Array:
	# Older A routers only published tool/demolish. New modes require explicit state.
	return hand.modes.duplicate() if hand.get("modes") is Array else ["tool", "demolish"]

static func title(mode: String) -> String:
	return str(NAMES.get(mode, mode))

static func mode_hint(hand: Dictionary) -> String:
	var mode := str(hand.get("mode", "tool"))
	var cancel := key(hand, "cancel", KEY_ESCAPE) + "取消"
	match mode:
		"facility_place": return "左键固定位置 · Enter确认 · " + key(hand, "rotate", KEY_R) + "旋转 · " + cancel
		"repair", "demolish", "destroy": return "按住左键" + title(mode) + " · 松开暂停 · " + cancel
		"move":
			return ("左键选取构件 → 指向同层目的地" if str(hand.get("structure_target_id", "")).is_empty() else "左键固定同层目的地 · Enter确认") + " · " + key(hand, "rotate", KEY_R) + "旋转 · " + cancel
		"terrain_fill": return "选中铲／镐 · 右键填土 · " + cancel
		"terrain_level": return "选中铲 · " + key(hand, "interact", KEY_E) + "取样基准 · 按住左键整平 · " + cancel
		"terrain_dig": return "选中铲／镐 · 按住左键挖掘 · 松开暂停 · " + cancel
	return "铲／镐指向地面，按住左键挖掘 · 右键使用／放置 · " + key(hand, "build", KEY_B) + "构件与作业"

static func brush_text(hand: Dictionary) -> String:
	var brush: Dictionary = hand.get("terrain", {}) if hand.get("terrain") is Dictionary else {}
	if brush.is_empty(): return "地形笔刷状态尚未发布"
	return "%s · %s×%s格 · 整平基准 %sm" % [str(MATERIALS.get(int(brush.get("material", 0)), "未知材料")), int(brush.get("brush_cells", 1)), int(brush.get("brush_cells", 1)), P.number(brush.get("height"))]

static func door_proof_state(target: Dictionary, hand: Dictionary) -> String:
	# Entity kind remains structure for real doors. Do not relabel tool work
	# on the same object as an E-door action or derive authority from enabled.
	if target.get("kind") != "door" and target.get("primary") != "door": return ""
	if hand.get("mode", "tool") in ["repair", "move", "demolish", "destroy"]: return ""
	return str(target.get("proof_state", ""))

static func held_work_hint(intent: Dictionary, hand: Dictionary) -> String:
	# A held-false order still owns its original tool and work. Do not describe
	# it as an asynchronous request or infer completion from mouse release.
	var payload: Dictionary = intent.get("request", {}).get("payload", {})
	if intent.get("kind") != "harvest" or not payload.get("requires_hold", false): return ""
	var text := "采伐中 · 松开左键暂停"
	if intent.get("held") == false:
		var slots: Array = hand.get("slots", [])
		var selected := int(hand.get("selected", 0))
		var reference := P.normalize_reference(slots[selected]) if selected >= 0 and selected < slots.size() and slots[selected] is Dictionary else {}
		var same_tool: bool = hand.get("mode", "tool") == "tool" and reference.get("kind") == "tool" and reference.get("tool_id") == payload.get("tool_id")
		text = "已暂停 · 采伐，" + ("按住左键继续" if same_tool else "选回原作业工具后按住左键继续")
	return text + " · " + key(hand, "cancel", KEY_ESCAPE) + "取消"

static func repair_work_hint(work:Dictionary)->String:
	if work.get("operation")!="restore":return ""
	var phase:String=str(work.get("phase",""))
	var reason:String=str(work.get("paused_reason",""))
	if reason.is_empty():reason=str(work.get("paused_code",""))
	if phase=="approaching":return "正在走向修复位置"
	if not reason.is_empty():return "修复暂停 · "+P.reason_text(reason)
	if phase=="completed":return "修复完成"
	if phase=="cancelled":return "修复已取消"
	if phase=="paused" or work.get("held")==false:return "修复已暂停 · 查看施工详情继续"
	if work.get("effective_work",false):return "正在修复"
	return "修复准备中"

static func target_hint(target: Dictionary, hand: Dictionary) -> String:
	var kind := str(target.get("kind", ""))
	var mode := str(hand.get("mode", "tool"))
	if target.get("primary") == "pickup": return key(hand, "interact", KEY_E) + " 拾取入包 · 容量不足时保留原物"
	if kind == "placement":
		var rotate := key(hand, "rotate", KEY_R) + "旋转"
		if target.get("placement_locked", false):return "Enter确认 · 右键解除 · " + rotate
		return "左键固定 · " + rotate + " · " + key(hand, "cancel", KEY_ESCAPE) + "退出"
	if target.get("focus_source") == "nearby" and target.get("primary") not in ["harvest", "pickup"]:
		return key(hand, "interact", KEY_E) + " " + str(target.get("action", "交互")) + " · 就近目标"
	if door_proof_state(target, hand) == "pending":
		# A may already label the action as an attempt. This is presentation
		# only; neither wording nor enabled grants command authorization.
		var action := str(target.get("action", "操作门"))
		if not action.begins_with("尝试"): action = "尝试" + action
		return key(hand, "interact", KEY_E) + action + " · 提交时验证通路与安全"
	if target.get("hint") is String and not target.hint.is_empty(): return target.hint
	if kind == "terrain":
		var terrain_hand := hand.duplicate(true)
		if not mode.begins_with("terrain_"): terrain_hand.mode = "terrain_dig"
		return mode_hint(terrain_hand)
	if kind == "structure" and mode in ["repair", "move", "demolish", "destroy"]: return mode_hint(hand)
	if kind in ["tree", "harvest"] or target.get("primary") == "harvest":
		if target.get("active_work", false) and target.get("work_paused") is bool:
			return str(target.get("action", "左键继续采伐" if target.work_paused else "采伐中")) + " · " + key(hand, "cancel", KEY_ESCAPE) + "取消"
		return "左键采伐 · 右键拖框"
	return key(hand, "interact", KEY_E) + " " + str(target.get("action", target.get("kind", "交互")))

static func render(ui, body: VBoxContainer) -> void:
	var hand: Dictionary = ui.snapshot.get("hand", {})
	var available := modes(hand)
	ui.paragraph("场景作业 · 当前 " + title(str(hand.get("mode", "tool"))), body)
	var row := HFlowContainer.new()
	body.add_child(row)
	for id in ["tool", "repair", "move", "demolish", "destroy"]:
		if not available.has(id): continue
		var mode := str(id)
		ui.add_button(title(mode), func(): ui.select_work_mode(mode), "mode:" + mode, "", row)
	var terrain_row := HFlowContainer.new()
	body.add_child(terrain_row)
	var has_terrain := false
	for id in ["terrain_dig", "terrain_fill", "terrain_level"]:
		if not available.has(id): continue
		has_terrain = true
		var mode := str(id)
		ui.add_button(title(mode), func(): ui.select_work_mode(mode), "mode:" + mode, "", terrain_row)
	if has_terrain:
		ui.add_button("高级笔刷参数…（可选）", func(): ui.open_panel("terrain"), "terrain:settings", "", terrain_row)
		ui.paragraph("普通挖掘：快捷栏选铲／镐，回场景指地按住左键即可；不必先打开笔刷参数。", body)
	ui.paragraph(mode_hint(hand), body)
	if str(hand.get("mode", "")).begins_with("terrain_"): ui.paragraph(brush_text(hand), body)

static func terrain_panel(ui, body: VBoxContainer) -> void:
	var hand: Dictionary = ui.snapshot.get("hand", {})
	var brush: Dictionary = hand.get("terrain", {}) if hand.get("terrain") is Dictionary else {}
	if brush.is_empty(): ui.paragraph("真实地形笔刷状态尚未发布，保留当前模式。", body); return
	ui.paragraph("当前真实笔刷：" + brush_text(hand), body)
	ui.paragraph("这里只设置手持操作。回到场景后指向实际格，材料、工具、通路与施工安全均由世界预检；取消编辑不改变当前笔刷。", body)
	ui.paragraph("作业", body)
	var operation := OptionButton.new()
	operation.set_meta("ui_focus_key", "terrain:operation")
	for value in ["dig", "fill", "level"]:
		if not modes(hand).has("terrain_" + value): continue
		operation.add_item(title("terrain_" + value))
		operation.set_item_metadata(operation.item_count - 1, value)
		if brush.get("operation") == value: operation.select(operation.item_count - 1)
	body.add_child(operation)
	ui.paragraph("填充材料", body)
	var material := OptionButton.new()
	material.set_meta("ui_focus_key", "terrain:material")
	for id in MATERIALS:
		material.add_item(str(MATERIALS[id]), id)
		if int(brush.get("material", 2)) == id: material.select(material.item_count - 1)
	body.add_child(material)
	ui.paragraph("笔刷范围", body)
	var cells := OptionButton.new()
	cells.set_meta("ui_focus_key", "terrain:cells")
	for count in [1, 2]:
		cells.add_item("%s×%s格" % [count, count], count)
		if int(brush.get("brush_cells", 1)) == count: cells.select(cells.item_count - 1)
	body.add_child(cells)
	ui.paragraph("整平基准高度（米，0.5m一档；也可回场景按%s取样）" % key(hand, "interact", KEY_E), body)
	var height := SpinBox.new()
	height.set_meta("ui_focus_key", "terrain:height")
	height.min_value = -10000
	height.max_value = 10000
	height.step = 0.5
	height.value = float(brush.get("height", 0))
	height.suffix = " m"
	body.add_child(height)
	ui.add_button("应用并回到场景", func():
		ui.apply_terrain_brush(str(operation.get_item_metadata(operation.selected)), material.get_selected_id(), height.value, cells.get_selected_id()), "terrain:apply", "没有已发布的地形模式" if operation.item_count == 0 else "", body)
