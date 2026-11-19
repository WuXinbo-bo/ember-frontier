extends RefCounted
const LifeCare=preload("res://scripts/ui/life_care.gd")
## Native, disposable views. Every action uses runtime availability/command.
const C = preload("res://scripts/ui/ui_composition.gd")
const Identity = preload("res://scripts/ui/ui_identity.gd")
const Teaching = preload("res://scripts/ui/factory_teaching.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const WorkModes = preload("res://scripts/ui/ui_work_modes.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const JOBS := {"gather":"搜集", "craft":"制作", "guard":"守备", "rest":"休息"}
const ACTIONS := {"up":"向画面上方移动", "down":"向画面下方移动", "left":"向画面左方移动", "right":"向画面右方移动", "run":"按住跑步", "interact":"主要交互", "inventory":"背包", "build":"构件目录", "neighbors":"同伴", "map":"任务与探索", "rotate":"旋转", "cancel":"取消", "auto_pickup":"自动拾取", "consume":"使用选中的消耗品"}
const QUALITIES := {"sawing":"锯切", "hammering":"锤击", "chopping":"采伐", "shovel":"铲掘", "pickaxe":"凿岩"}

static func render(ui, body: VBoxContainer, route: Dictionary) -> void:
	match str(route.get("page", "")):
		"inventory", "container": _inventory(ui, body, route)
		"build": _build(ui, body)
		"terrain": WorkModes.terrain_panel(ui, body)
		"workbench": _workbench(ui, body, str(route.get("subject", "")))
		"npc", "neighbors": _people(ui, body, str(route.get("subject", "")))
		"quests": _quests(ui, body)
		"settings": _settings(ui, body)
		"pause": _pause(ui, body)
		"new_world": _new_world(ui, body)
		"close_failed":
			ui.paragraph(str(ui._close_receipt.get("reason", "退出前保存未完成，窗口与原档保持")), body)
			ui.add_button("重试保存并退出", ui.retry_close, "close:retry", "正在等待保存回执" if ui._closing_wait else "", body)
			ui.add_button("返回游戏", ui.cancel_close, "close:return", "", body)
		_:
			ui.paragraph("此界面尚无已装配的真实数据", body)

static func heading(ui, text: String, parent: Node) -> void:
	C.heading(ui, text, parent)

static func _inventory(ui, body: VBoxContainer, route: Dictionary) -> void:
	ui.paragraph("拖动／点击拿起 → 目的格放下 · 右键拆分 · Shift点击快速取放 · Esc归位", body)
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(pair)
	var own := VBoxContainer.new()
	pair.add_child(own)
	heading(ui, "随身物品", own)
	var pack: Dictionary = P.player_stock(ui.snapshot)
	ui.inventory_grid(pack, own)
	var subject := str(route.get("subject", ""))
	if not subject.is_empty():
		var other := VBoxContainer.new()
		pair.add_child(other)
		var stock := P.stock(ui.snapshot, subject)
		heading(ui, str(stock.get("name", "当前容器")), other)
		ui.inventory_grid(stock, other)
	else:
		ui.paragraph("从场景 E 打开容器，才能在两侧真实取放；背包格整理不移动世界物品。", body)
	if not P.playtest_profile(ui.snapshot).is_empty():
		heading(ui, P.playtest_text(ui.snapshot), body)
		ui.paragraph(P.playtest_supplies(ui.snapshot), body)
	heading(ui, "当前手持", body)
	var hand: Dictionary = ui.snapshot.get("hand", {})
	ui.paragraph("第 %s 格 · %s · 数字1—9／滚轮切换。背包物品拖到下方快捷栏即可绑定。" % [int(hand.get("selected", 0)) + 1, WorkModes.title(str(hand.get("mode", "tool")))], body)
	ui.paragraph("关包后直接使用当前快捷格；铲／镐指地长按左键挖掘。%s 打开构件与作业，高级笔刷参数为可选。" % WorkModes.key(hand, "build", KEY_B), body)
	ui.add_button("清除此快捷格的绑定", func():
		var result: Dictionary = ui.router_call("assign_slot", [int(hand.get("selected", 0)), {}])
		if not result.get("ok", false): ui.notify(str(result.get("reason", "未清除")), true), "hand:clear", "", body)
	heading(ui, "人物状态", body)
	var actor := P.player(ui.snapshot)
	ui.paragraph("体力 %s · 疲劳 %s · 当前 %s" % [P.number(actor.get("stamina")), P.number(actor.get("fatigue")), P.activity_text(actor)], body)
	if actor.get("wounds") is Array:
		ui.paragraph("伤势 %s 处" % actor.wounds.size(), body)
	if actor.get("skills") is Dictionary and not actor.skills.is_empty():
		var skills: PackedStringArray = []
		for id in actor.skills:
			var name: String = {"survival":"生存", "gathering":"采集", "crafting":"制作", "combat":"战斗"}.get(str(id), str(id))
			skills.append(name + " " + P.number(actor.skills[id]))
		ui.paragraph("技能 · " + " / ".join(skills), body)
	LifeCare.render(ui,body)
	if actor.get("intent") is Dictionary:
		_action(ui, "取消当前行动", "cancel_work" if actor.intent.get("owner") == "actions" else "cancel", "", {}, body, true)

static func _catalog(ui, key: String) -> Array:
	var catalog: Variant = ui.snapshot.get("catalog", {})
	if catalog is Array: return P.records(catalog) if key == "buildings" else []
	if not catalog is Dictionary: return []
	return P.records(catalog.get(key, catalog.get("structure_definitions" if key == "buildings" else "production_recipes", [])))

static func _build(ui, body: VBoxContainer) -> void:
	var view_hand: Dictionary = ui.snapshot.get("hand", {})
	ui.paragraph("选构件 → 回到场景指向位置 → 右键放置 · %s旋转 · %s取消；每次放置重新校验材料与通路。" % [WorkModes.key(view_hand, "rotate", KEY_R), WorkModes.key(view_hand, "cancel", KEY_ESCAPE)], body)
	WorkModes.render(ui, body)
	var definitions := _catalog(ui, "buildings")
	if definitions.is_empty():
		ui.paragraph("真实构件目录尚未发布；不会在界面内生成替代构件。", body)
		return
	for definition: Dictionary in definitions:
		var id := str(definition.get("id", definition.get("definition_id", "")))
		if id.is_empty(): continue
		heading(ui, str(definition.get("name", id)), body)
		ui.item_row(definition.get("cost", {}), "材料", body)
		ui.paragraph(_requirements(definition, false), body)
		var blocked := str(definition.get("reason", "")) if not definition.get("enabled", true) else ""
		if blocked.is_empty(): blocked = P.definition_reason(definition)
		ui.add_button("拿在手中", func():
			var hand: Dictionary = ui.snapshot.get("hand", {})
			var receipt: Dictionary = ui.router_call("assign_slot", [int(hand.get("selected", 0)), {"kind":"recipe", "definition_id":id}])
			if not receipt.get("ok", false):
				ui.notify(str(receipt.get("reason", "构件未能拿起")), true)
				return
			var mode: Dictionary = ui.router_call("set_mode", ["tool"])
			if mode.get("ok", false): ui.close_panels()
			else: ui.notify(str(mode.get("reason", "放置路由尚未提供")), true), "build:" + id, blocked, body)

static func _workbench(ui, body: VBoxContainer, station_id: String) -> void:
	if station_id.is_empty():
		ui.paragraph("需从真实工位 E 打开；不能从远处制作。", body)
		return
	ui.paragraph("点配方直接制作1批，受理后回场景劳动，无需再次确认。%s／Esc返回场景；下次打开时上次配方置顶。" % WorkModes.key(ui.snapshot.get("hand", {}), "interact", KEY_E), body)
	var pack := P.player_stock(ui.snapshot)
	var recipes := _catalog(ui, "recipes")
	var modern_targets:Dictionary={}
	var owning_module_id:=""
	for module:Dictionary in F.rows(ui.factory,"modules","instances"):
		if module.get("id")!=station_id and not P.records(module.get("members",[])).any(func(member:Dictionary):return member.get("id")==station_id):continue
		if module.get("mechanism",{}).get("version")==2 and module.get("recipe_management") is Dictionary:
			owning_module_id=str(module.id)
			var modern:Array=P.records(module.recipe_management.get("recipes",[]))
			for recipe:Dictionary in modern:modern_targets[str(recipe.get("id",recipe.get("recipe_id","")))]=str(module.id)
			# Current module recipes use the owning module. Legacy personal-tool
			# recipes remain on the actual station, never a fabricated module ID.
			for recipe:Dictionary in recipes:
				if not modern_targets.has(str(recipe.get("id",recipe.get("recipe_id","")))):modern.append(recipe)
			recipes=modern
			break
	var recent: Dictionary = ui._recent_crafts.get(station_id, ui._recent_crafts.get(owning_module_id,{}))
	for index in recipes.size():
		if str(recipes[index].get("id", recipes[index].get("recipe_id", ""))) == recent.get("recipe_id"):
			var previous: Dictionary = recipes.pop_at(index)
			recipes.push_front(previous)
			break
	if recipes.is_empty(): ui.paragraph("工位配方投影尚未接入，暂不能制作；未提供虚拟队列。", body)
	var recipe_parent := body
	for recipe: Dictionary in recipes:
		body = C.card(recipe_parent)
		var id := str(recipe.get("id", recipe.get("recipe_id", "")))
		if id.is_empty(): continue
		var craft_target:String=str(modern_targets.get(id,station_id))
		var is_recent: bool = id == recent.get("recipe_id")
		heading(ui, ("上次使用 · " if is_recent else "") + str(recipe.get("name", id)), body)
		ui.item_row(recipe.get("inputs", {}), "需要", body)
		ui.item_row(recipe.get("outputs", {}), "产出1批", body)
		ui.paragraph(_requirements(recipe, false), body)
		var invalid := P.definition_reason(recipe, true)
		if not invalid.is_empty():
			ui.paragraph(invalid, body)
			continue
		for key in ["createTool", "repairTool"]:
			if recipe.get(key) is Dictionary:
				var tool_kind := str(recipe[key].get("kind", ""))
				var tool_definition: Dictionary = ui.snapshot.get("catalog", {}).get("tool_definitions", {}).get(tool_kind, {})
				var target := HBoxContainer.new()
				target.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var texture := Icons.texture({"reference":{"kind":"tool"}, "definition_id":tool_kind})
				if texture != null: target.add_child(Icons.image(texture))
				target.add_child(ui.label(("产出工具 · " if key == "createTool" else "维修目标 · ") + str(tool_definition.get("name", tool_kind))))
				body.add_child(target)
		var payload := {"recipe_id":id, "source_id":str(pack.get("id", "")), "output_id":str(pack.get("id", "")), "tool_ids":_tool_ids(pack, ui.snapshot)}
		if recipe.has("repair_tool_id"):
			payload["repair_tool_id"] = recipe.repair_tool_id
			payload["tool_ids"] = _tool_ids(pack, ui.snapshot, str(recipe.repair_tool_id))
		if recipe.get("repairTool") is Dictionary:
			var repairable := false
			for tool: Dictionary in P.records(ui.snapshot.get("tools", [])):
				if tool.get("kind") == recipe.repairTool.get("kind") and str(tool.get("holder_id", tool.get("holderId", ""))) == str(pack.get("id", "")):
					var repair_payload := payload.duplicate(true)
					repair_payload["repair_tool_id"] = str(tool.get("id", ""))
					repair_payload["tool_ids"] = _tool_ids(pack, ui.snapshot, str(tool.get("id", "")))
					var entry := P.entry(pack, ui.snapshot, {"kind":"tool", "tool_id":str(tool.get("id", ""))})
					_action(ui, "维修 " + str(entry.get("name", tool.get("id", "工具"))) + " · 耐久 " + P.number(tool.get("durability")), "craft", craft_target, repair_payload, body, true)
					repairable = true
			if not repairable: ui.paragraph("随身没有此工序可维修的真实工具", body)
		else: _action(ui, "再制作1批" if is_recent else "制作1批", "craft", craft_target, payload, body, true)
	body = recipe_parent
	var extra := C.fold(ui, body, "workbench:" + station_id, "知识、研读与当前订单")
	if extra == null: return
	body = extra
	heading(ui, "知识与当前订单", body)
	var knowledge: Variant = ui.snapshot.get("knowledge", [])
	if knowledge is Dictionary and knowledge.get(P.player(ui.snapshot).get("id", "")) is Array:
		for id in knowledge[P.player(ui.snapshot).id]: ui.paragraph(P.item_name(str(id)), body)
	for record: Dictionary in P.records(knowledge):
		ui.paragraph(str(record.get("name", record.get("id", ""))) + " · " + str(record.get("status", "已记录")), body)
	for record: Dictionary in P.records(ui.snapshot.get("records", [])):
		var id := str(record.get("id", ""))
		if id.is_empty(): continue
		var holder := str(record.get("holder_id", record.get("holderId", "")))
		var source := P.stock(ui.snapshot, holder)
		ui.paragraph(("随身背包" if holder == str(pack.get("id", "")) else str(source.get("name", "附近容器"))) + " · 研读工时 " + P.number(record.get("seconds")) + "秒", body)
		# B derives the physical book source from record.holderId at preflight/commit.
		_action(ui, "研读 " + str(record.get("name", P.item_name(str(record.get("itemId", id))))), "study", id, {"record_id":id}, body, true)
	_orders(ui, body)

static func _tool_ids(pack: Dictionary, snapshot: Dictionary, excluding: String = "") -> Array:
	var result: Array = []
	for item: Dictionary in P.entries(pack, snapshot):
		if item.reference.kind == "tool" and float(item.available) >= 1 and str(item.reference.tool_id) != excluding: result.append(item.reference.tool_id)
	return result

static func _requirements(definition: Dictionary, include_materials: bool = true) -> String:
	var parts: PackedStringArray = []
	var materials: Variant = definition.get("cost", definition.get("inputs", {}))
	if include_materials and materials is Dictionary:
		for id in materials: parts.append(P.item_text(str(id), materials[id]))
	if definition.has("duration") or definition.has("seconds"): parts.append("工时 " + P.number(definition.get("duration", definition.get("seconds"))) + "秒")
	if definition.get("knowledge") is Array:
		var names: PackedStringArray = []
		for id in definition.knowledge: names.append(P.item_name(str(id)))
		if not names.is_empty(): parts.append("知识 " + " / ".join(names))
	var qualities: Variant = definition.get("qualities", definition.get("tools", {}))
	if qualities is Dictionary:
		var tools: PackedStringArray = []
		for quality in qualities: tools.append(str(QUALITIES.get(str(quality), str(quality))) + " " + P.number(qualities[quality]))
		if not tools.is_empty(): parts.append("工具能力 " + " / ".join(tools))
	elif definition.has("tools"): parts.append("工具 " + str(definition.tools))
	if float(definition.get("minCrafting", 0)) > 0: parts.append("制作技能 " + P.number(definition.minCrafting))
	if definition.has("reason") and definition.reason != null: parts.append(str(definition.reason))
	return " · ".join(parts) if not parts.is_empty() else "材料／知识／工位要求由实际预检确认"

static func companion(ui, body: VBoxContainer, id: String) -> void:
	var actor:=P.find(ui.snapshot.get("actors",[]),id)
	if actor.is_empty():
		C.caption(ui,"找不到这名同伴",body)
		return
	Identity.header(ui,body,actor)
	C.caption(ui,Identity.needs(actor),body)
	var factory=preload("res://scripts/ui/factory_projection.gd")
	var routine:Dictionary=actor.get("self_routine",{})
	var decision:Dictionary=routine.get("factory_decision",{})
	if not decision.is_empty() and decision.get("action")!="idle":C.caption(ui,Identity.decision_text(decision),body)
	var failure:Dictionary=routine.get("last_failure",{})
	if not failure.is_empty():C.reason(ui,body,P.feedback_text(failure))
	var relationship:Dictionary=actor.get("relationship",{})
	if relationship.get("member",false) and relationship.get("consent",false) and float(actor.get("hp",0))>0 and factory.enabled(ui.factory):
		var order:Dictionary=factory.find(factory.rows(ui.factory,"workforce","assignments"),id,"actor_id")
		if order.has("building_phase"):
			var ops=preload("res://scripts/ui/factory_operations.gd")
			C.caption(ui,"建筑工程 · "+ops.building_order_status(order),body)
			ui.add_button("查看工程",func():ui.open_panel("factory_module",str(order.module_id)),"npc:building:open:"+id,"",body)
		ui.add_button("搬运地面物资",func():ui.start_companion_area(id,"haul"),"npc:area:haul","",body)
		ui.add_button("划区采伐",func():ui.start_companion_area(id,"forestry"),"npc:area:forestry","",body)
		if ui.is_companion_building_pick():
			C.caption(ui,"选择目标建筑",body)
			ui.add_button("取消选择",ui.cancel_ui,"npc:building:pick:cancel","",body)
		else:
			ui.add_button("点建筑安排工作",func():ui.begin_companion_building_pick(id),"npc:building:pick","",body)
		ui.add_button("建造住宅",func():ui.open_companion_home_catalog(id),"npc:home:blueprint","",body)
		ui.add_button("生产与施工安排",func():ui.open_panel("factory_people",id),"npc:work","",body)
		if actor.get("pending_delivery",{}).get("phase")=="deliver":C.caption(ui,"携货中 · 等原货物交付",body)
	_action(ui,"交谈","talk",id,{},body,true)
	ui.add_button("人物与合作",func():ui.open_panel("npc",id),"npc:details","",body)

static func _people(ui, parent: VBoxContainer, subject: String) -> void:
	var player := P.player(ui.snapshot)
	var found := false
	for actor: Dictionary in P.records(ui.snapshot.get("actors", [])):
		var id := str(actor.get("id", ""))
		if id == player.get("id") or (not subject.is_empty() and id != subject): continue
		found = true
		var body := C.card(parent)
		var relationship: Dictionary = actor.get("relationship", {})
		var met := bool(relationship.get("met", false))
		if met: Identity.header(ui, body, actor, 64)
		else: heading(ui, "附近的幸存者", body)
		if met:
			C.caption(ui, Identity.needs(actor), body)
			Identity.cargo(ui, body, id)
			if not ui.factory.is_empty():
				ui.add_button("共同经历",func():
					ui.factory_view.handbook_section="stories";ui.factory_view.story_person=id;ui.factory_view.handbook_search="";ui.open_panel("factory_handbook"),"npc:stories:"+id,"",body)
		_action(ui, "交谈", "talk", id, {}, body, true)
		if met: Teaching.render(ui, body, id)
		var pack := P.player_stock(ui.snapshot)
		for item: Dictionary in P.entries(pack, ui.snapshot):
			if item.reference.kind == "item" and float(item.available) >= 1 and item.reference.item_id in ["food", "water", "medicine"]:
				_action(ui, "实际帮助：交给对方 " + str(item.name) + " × 1", "help", id, {"items":{str(item.reference.item_id):1}}, body, true)
		if not relationship.get("member", false):
			_action(ui, "邀请同行", "invite", id, {}, body, true)
		else:
			ui.paragraph("已同行 · " + ("同意工作" if relationship.get("consent", false) else "尚未同意工作"), body)
			var companion_pack := P.stock(ui.snapshot, "pack:" + id)
			if not companion_pack.is_empty():
				ui.add_button("交接随身物品", func(): ui.open_panel("container", str(companion_pack.id)), "handoff:" + id, "", body)
				ui.paragraph("走到同伴旁并获得同意后，可在两侧格子真实交接；预留材料与工具仍受同一库存校验。", body)
			_action(ui, "暂停工作授权" if relationship.get("consent", false) else "请求工作同意", "consent", id, {"enabled":not relationship.get("consent", false)}, body, true)
			if relationship.get("consent", false):
				_action(ui, "安排休息", "job", id, {"job":"rest", "work_target_id":""}, body, true)
				var targets := P.records(ui.snapshot.get("work_targets", []))
				for target: Dictionary in targets:
					var job := str(target.get("job", ""))
					if not JOBS.has(job) or job == "rest" or str(target.get("id", "")).is_empty(): continue
					var payload := {"job":job, "work_target_id":str(target.id)}
					if target.get("work_payload") is Dictionary: payload.work_payload = target.work_payload.duplicate(true)
					_action(ui, str(JOBS[job]) + " · " + str(target.get("name", target.id)), "job", id, payload, body, true)
				if targets.is_empty(): ui.paragraph("还没有发布可指派的真实工作目标；不生成虚拟产出。", body)
	if not found: ui.paragraph("当前没有可见的人物；继续在场景寻找线索。", parent)

static func _quests(ui, body: VBoxContainer) -> void:
	preload("res://scripts/ui/chapter_panel.gd").quests(ui,body,ui.snapshot.get("village",{}))
	var village:Dictionary=ui.snapshot.get("village",{})
	if village.get("available",false):
		heading(ui,"旧村复兴 · "+str(village.get("title","共同安顿")),body)
		ui.paragraph(str(village.get("next_step","")),body)
		ui.paragraph("前期：安顿与修仓 → 中期：稳定供给、升级生产 → 后期：接通电台、恢复外部联系与区域扩张",body)
	var quests := P.records(ui.snapshot.get("quests", []))
	if quests.is_empty(): ui.paragraph("当前没有已发布的任务事实。RH-Q01—08进度由世界行动推进。", body)
	for quest: Dictionary in quests:
		heading(ui, str(quest.get("name", quest.get("title", quest.get("id", "")))), body)
		ui.paragraph(str(quest.get("description", quest.get("hint", ""))), body)
		ui.paragraph("状态 " + str(quest.get("status", "—")) + (" · " + str(quest.progress) if quest.has("progress") else ""), body)
		for objective: Dictionary in P.records(quest.get("objectives", [])):
			ui.paragraph(str(objective.get("text", objective.get("name", ""))) + " · " + str(objective.get("status", objective.get("progress", "—"))), body)
	heading(ui, "当前作业", body)
	_orders(ui, body)
	for key in ["exploration", "defense"]:
		var state: Variant = ui.snapshot.get(key)
		if not state is Dictionary or state.is_empty(): continue
		heading(ui, "探索" if key == "exploration" else "据点预警", body)
		ui.paragraph(str(state.get("description", state.get("status", ""))), body)
		if key == "exploration":
			if state.has("stages"): ui.paragraph("本次已完成阶段 " + P.number(state.stages), body)
			if state.has("loot_collected"): ui.paragraph("本次实际收集记录 " + P.number(state.loot_collected), body)
			var settled := P.records(state.get("settled", []))
			if not settled.is_empty():
				var last: Dictionary = settled.back()
				ui.paragraph("最近一次返回结算 · " + str(last.get("run_id", "")), body)
				ui.paragraph("阶段 %s · 收集记录 %s · 技巧 %s · %s" % [P.number(last.get("stages")), P.number(last.get("loot_collected")), P.number(last.get("choices")), "整段目标已完成" if last.get("complete", false) else "尚未完成整段探索目标"], body)
			if state.get("upgrades") is Array:
				var names: PackedStringArray = []
				var published_names: Dictionary = state.get("upgrade_names", {})
				for id in state.upgrades:
					if published_names.has(str(id)): names.append(str(published_names[str(id)]))
				var summary := "尚未选择"
				if not state.upgrades.is_empty():
					summary = "、".join(names) if names.size() == state.upgrades.size() else "已选择 %s 项" % state.upgrades.size()
				ui.paragraph("本次临时技巧：" + summary, body)
		elif state.get("status") == "warning" and state.has("remaining"):
			ui.paragraph("来袭前剩余 " + P.number(state.remaining) + " 秒 · 在界面中暂停", body)
		for choice: Dictionary in P.records(state.get("choices", [])):
			# Actual candidate ID, command and payload are projected by A; never reroll/award here.
			if not choice.get("command") is Dictionary: continue
			var command: Dictionary = choice.command
			_action(ui, str(choice.get("name", choice.get("id", "选择"))), str(command.get("kind", "")), str(command.get("target_id", "")), command.get("payload", {}), body, true)
	var radio: Variant = ui.snapshot.get("radio")
	if radio is Dictionary and not radio.is_empty():
		heading(ui, "固定通信设备", body)
		var status := str(radio.get("status", ""))
		ui.paragraph(str({"unrepaired":"尚未维修", "repaired":"线路已修好，等待发送", "connected":"已取得联系"}.get(status, status)), body)
		if radio.has("unlocked") and not radio.unlocked:ui.paragraph(str(radio.get("unlock_hint","")),body)
		for choice:Dictionary in P.records(radio.get("choices",[])):
			var command:Dictionary=choice.get("command",{})
			if not command.is_empty():_action(ui,str(choice.get("name",choice.get("label","操作电台"))),str(command.get("kind","radio")),str(command.get("target_id","")),command.get("payload",{}),body,true)
		var intent: Variant = P.player(ui.snapshot).get("intent")
		if intent is Dictionary and intent.get("kind") == "radio":
			ui.paragraph("正在发送" if intent.get("operation") == "transmit" else "正在维修", body)
			var progress := P.progress(intent)
			if not progress.is_empty():
				var bar := ProgressBar.new()
				bar.step = 0.0; bar.max_value = progress.maximum; bar.value = progress.value
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				body.add_child(bar)

static func _orders(ui, body: VBoxContainer) -> void:
	var orders := P.records(ui.snapshot.get("orders", []))
	if orders.is_empty(): ui.paragraph("无当前制作订单", body)
	for order: Dictionary in orders:
		var text := str(order.get("name", order.get("recipe_id", order.get("recipeId", order.get("id", ""))))) + " · " + str(order.get("status", "—"))
		if order.has("reason") and order.reason != null: text += " · " + str(order.reason)
		ui.paragraph(text, body)
		var progress := P.progress(order)
		if not progress.is_empty():
			var bar := ProgressBar.new()
			bar.step = 0.0
			bar.max_value = progress.maximum
			bar.value = progress.value
			body.add_child(bar)

static func _settings(ui, body: VBoxContainer) -> void:
	heading(ui,"拾取与行动",body)
	var pickup := CheckBox.new()
	pickup.text = "自动拾取身边的原木和小件（" + WorkModes.key(ui.snapshot.get("hand",{}),"auto_pickup",KEY_G) + "切换）"
	pickup.button_pressed = bool(ui.snapshot.get("hand",{}).get("auto_pickup",false))
	pickup.set_meta("ui_focus_key","settings:auto-pickup")
	pickup.toggled.connect(func(value:bool): ui.set_auto_pickup(value))
	body.add_child(pickup)
	var combat := CheckBox.new()
	combat.text = "点按右键切换手动战备"
	combat.button_pressed = bool(ui.snapshot.get("hand", {}).get("combat_toggle", false))
	combat.set_meta("ui_focus_key", "settings:combat-toggle")
	combat.toggled.connect(func(value: bool):
		var receipt: Dictionary = ui.router_call("set_combat_toggle", [value])
		if not receipt.get("ok", false):
			combat.set_pressed_no_signal(not value)
			ui.notify(str(receipt.get("reason", "战备设置保存失败")), true))
	body.add_child(combat)
	ui.paragraph("右键建筑打开功能页，右键树木安排采运。遇到感染者时，木棒或弓进入射程会自动攻击。快捷栏选中食水或药品后可按使用键。", body)
	ui.paragraph("地面掉落物：E直接拾取；普通箱柜：E打开双栏。自动拾取仍受距离、权限与背包容量限制。",body)
	heading(ui,"按键设置",body)
	ui.paragraph("场景键按物理位置识别；中文输入只交给文本控件。系统快捷键与已占用按键由统一输入路由拒绝。", body)
	var bindings: Dictionary = ui._bindings()
	for action in bindings:
		var id := str(action)
		ui.add_button(str(ACTIONS.get(id, id)) + "   " + WorkModes.keys(ui.snapshot.get("hand",{}),id,0), func():
			ui.capture_action = id
			ui.queue_refresh(), "bind:" + id, "", body)
	ui.add_button("恢复默认按键", func():
		var receipt: Dictionary = ui.router_call("reset_bindings")
		ui.notify("已恢复默认按键" if receipt.get("ok", false) else str(receipt.get("reason", "恢复失败")), not receipt.get("ok", false))
		ui.queue_refresh(), "bind:reset", "", body)
	heading(ui, "界面文字（本次会话）", body)
	var row := HBoxContainer.new()
	body.add_child(row)
	for amount in [1.0, 1.25, 1.5]:
		var value := float(amount)
		ui.add_button(str(int(value * 100)) + "%", func(): ui.set_text_scale(value), "text:" + str(value), "", row)
	ui.paragraph("左键工具作业 · 右键使用／放置 · 数字1—9／滚轮快捷栏 · Ctrl滚轮缩放（由场景路由处理）", body)

static func _pause(ui, body: VBoxContainer) -> void:
	if ui.Factory.enabled(ui.factory):
		ui.add_button("村落设施与生产", func(): ui.open_panel("factory"), "pause:factory", "", body)
	var profile := P.playtest_profile(ui.snapshot)
	if not profile.is_empty():
		ui.paragraph(P.playtest_text(ui.snapshot), body)
		ui.paragraph(P.playtest_supplies(ui.snapshot), body)
	ui.add_button("继续游戏", ui.close_panels, "pause:resume", "世界切换进行中，请等待实际回执" if ui.world_change_busy() else "", body)
	var busy: bool = ui.file_request_busy()
	var save_reason := "正在处理当前文件请求" if busy else ""
	if save_reason.is_empty(): save_reason = ui.storage_reason("save_async")
	ui.add_button("正在保存…" if ui.saving or ui.storage_state().get("busy", false) else "保存世界 · Ctrl+S / ⌘S", ui.save_world, "pause:save", save_reason, body)
	var state: Dictionary = ui.storage_state()
	if not str(state.get("reason", "")).is_empty(): ui.paragraph(str(state.reason), body)
	var restore_reason := "正在处理当前文件或世界请求" if busy else ""
	if restore_reason.is_empty(): restore_reason = ui.storage_reason("restore_saved_world")
	ui.add_button("正在恢复…" if ui.world_restoring else "恢复上次手动保存", ui.restore_saved_world, "pause:restore-saved", restore_reason, body)
	ui.paragraph("恢复上次手动保存会替换当前世界；当前未保存的测试进度不保留。需要保留时请先保存。", body)
	var candidates_reason := "正在处理当前文件或世界请求" if busy else ""
	if candidates_reason.is_empty(): candidates_reason = ui.storage_reason("list_recovery_candidates")
	if candidates_reason.is_empty(): candidates_reason = ui.storage_reason("restore_recovery_candidate")
	ui.add_button("选择其他恢复候选…", ui.open_recovery_candidates, "pause:recovery-candidates", candidates_reason, body)
	var world_reason := "正在处理当前文件或世界请求" if busy else ""
	if world_reason.is_empty(): world_reason = ui.new_world_storage_reason()
	ui.add_button("新建生成村落…", ui.choose_new_world, "pause:new-world", world_reason, body)
	var export_reason := "正在处理当前文件请求" if busy else ""
	if export_reason.is_empty(): export_reason = ui.storage_reason("export_checkpoint_file")
	ui.add_button("导出检查点…", ui.export_world, "pause:export", export_reason, body)
	var import_reason := "正在处理当前文件请求" if busy else ""
	if import_reason.is_empty(): import_reason = ui.storage_reason("import_checkpoint_file")
	ui.add_button("恢复存档文件到新槽…", ui.choose_import, "pause:import", import_reason, body)
	ui.add_button("键位与界面", func(): ui.open_panel("settings"), "pause:settings", "", body)
	ui.add_button("任务与工作", func(): ui.open_panel("quests"), "pause:quests", "", body)
	ui.paragraph("默认启动为随机试玩新图，不自动读取旧地图。请用「保存世界」保留进度；新图首次手动保存写入独立目录。", body)
	ui.paragraph("「恢复上次手动保存」直接读取最近有效槽；恢复外部文件会验证后写入新槽。也可用启动参数 --continue 显式恢复。", body)
	ui.paragraph("默认试玩退出不自动保存；需保留时请先手动保存。通过恢复入口进入的世界沿引擎既有关闭保存流程。", body)

static func _new_world(ui, body: VBoxContainer) -> void:
	ui.paragraph("先保存当前世界，保存成功后再生成新村落。旧世界存档独立保留；保存或生成失败时留在当前世界。", body)
	ui.paragraph("默认种子713；也可输入其他整数。新村落生成后，请用「保存世界」保留新进度。", body)
	if is_instance_valid(ui.runtime) and ui.runtime.has_method("start_profiled_world"):
		var profiles := HFlowContainer.new(); body.add_child(profiles)
		for spec in [["normal", "正常开局 · 现场获取"], ["playtest", "测试开局 · 五工具补给"]]:
			var profile_id: String = spec[0]
			var selected: bool = ui._new_world_profile == profile_id
			ui.add_button(("已选 · " if selected else "") + str(spec[1]), func(): ui._new_world_profile = profile_id; ui.queue_refresh(), "new-world:profile:" + profile_id, "保存与生成进行中" if ui.world_change_busy() else "", profiles)
		ui.paragraph("正常开局不赠送测试工具；测试开局的补给不代表正常经济路线通过。当前选择：" + ("正常" if ui._new_world_profile == "normal" else "测试"), body)
	var seed := LineEdit.new()
	seed.placeholder_text = "村落种子 · 默认713"
	seed.text = ui._new_world_seed_text
	seed.max_length = 12
	seed.editable = not ui.world_change_busy()
	seed.set_meta("ui_focus_key", "new-world:seed")
	body.add_child(seed)
	var validation: Label = ui.paragraph(ui.new_world_seed_reason(), body)
	validation.visible = not validation.text.is_empty()
	validation.add_theme_color_override("font_color", Color("e8ae99"))
	var state: Dictionary = ui.storage_state()
	if ui.world_change_busy():
		heading(ui, "正在生成村落…" if state.get("status") == "generating" else "正在保存当前世界…", body)
		ui.paragraph(str(state.get("reason", "")), body)
		ui.paragraph("请等待实际回执；此时不能取消生成或返回游戏。", body)
	else:
		if not ui._new_world_receipt.is_empty() and not ui._new_world_receipt.get("ok", false):
			heading(ui, "新建村落未完成", body)
			ui.paragraph(str(ui._new_world_receipt.get("code", "")) + " · " + str(ui._new_world_receipt.get("reason", "")), body)
	var reason: String = "保存与生成进行中，请等待" if ui.file_request_busy() else ui.new_world_storage_reason()
	if reason.is_empty(): reason = ui.new_world_seed_reason()
	var confirm: Button = ui.add_button("保存当前世界并生成" if ui._new_world_receipt.is_empty() else "重新保存并重试生成", ui.confirm_new_world, "new-world:confirm", reason, body)
	seed.text_changed.connect(func(value: String):
		ui._new_world_seed_text = value
		validation.text = ui.new_world_seed_reason()
		validation.visible = not validation.text.is_empty()
		var blocked: String = "保存与生成进行中，请等待" if ui.file_request_busy() else ui.new_world_storage_reason()
		if blocked.is_empty(): blocked = validation.text
		confirm.disabled = not blocked.is_empty()
		confirm.tooltip_text = blocked)
	ui.add_button("取消 · 返回暂停菜单", ui.cancel_ui, "new-world:cancel", "生成已提交，请等待实际回执" if ui.world_change_busy() else "", body)

static func _action(ui, text: String, kind: String, target: String, payload: Dictionary, parent: Node, resume: bool = false) -> void:
	var command: Dictionary = ui.request(kind, target, payload)
	var check: Dictionary = ui.availability(command)
	var reason := "" if check.get("ok", false) else P.action_feedback(check, kind)
	ui.add_button(text, func(): ui.execute(kind, target, payload, resume), kind + ":" + target + ":" + str(payload.hash()), reason, parent)
