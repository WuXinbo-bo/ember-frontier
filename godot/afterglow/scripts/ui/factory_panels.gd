extends RefCounted
const Mechanisms=preload("res://scripts/ui/factory_mechanisms.gd")
## Native factory surfaces. Every quantity and operation has one public owner.
const C = preload("res://scripts/ui/ui_composition.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const Identity = preload("res://scripts/ui/ui_identity.gd")
const ObjectPanel = preload("res://scripts/ui/factory_object.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const Catalog = preload("res://scripts/ui/factory_catalog.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")
const Alerts = preload("res://scripts/ui/factory_alerts.gd")
const Stories = preload("res://scripts/ui/factory_stories.gd")
const Access = preload("res://scripts/ui/factory_service_access.gd")
const Movable = preload("res://scripts/ui/factory_movable.gd")
const Handbook = preload("res://scripts/ui/factory_handbook.gd")
const LifeCare = preload("res://scripts/ui/life_care.gd")
const PORTS := {"input":"供料", "output":"出料", "fuel":"燃料", "work":"作业", "repair":"维修", "service":"补给服务"}
const BUFFERS := {"input":"原料缓存", "output":"成品缓存", "tools":"工具与书册", "supplies":"生活物资", "storage":"仓储", "fuel":"燃料缓存"}

static func render(ui, body: VBoxContainer, route: Dictionary) -> void:
	if not F.enabled(ui.factory):
		ui.paragraph("村落设施尚不可用；未创建替代库存或生产。", body)
		return
	match str(route.page):
		"factory": _modules(ui, body)
		"factory_catalog": _catalog(ui, body)
		"factory_module": _module(ui, body, str(route.get("subject", "")))
		"factory_inventory": _inventory(ui, body, str(route.get("subject", "")))
		"factory_production": _production(ui, body)
		"factory_logistics": _logistics(ui, body)
		"factory_people": _people(ui, body, str(route.get("subject", "")))
		"factory_alerts": _alerts(ui, body, str(route.get("subject", "")))
		"factory_handbook": _handbook(ui, body)
		"factory_confirm": Ops.confirmation(ui, body)

static func navigation(ui, row: Container, active: String) -> void:
	row.set_meta("ui_navigation", true)
	if active=="factory_catalog":
		for spec in [["设施总览", "factory"], ["物料手册", "factory_handbook"]]:
			var link: Button = ui.add_button(spec[0],func():ui.open_panel(spec[1]),"factory:nav:"+spec[1],"",row)
			link.theme_type_variation = "QuietButton"
		return
	for spec in [["设施","factory","modules"],["建造","factory_catalog","modules"],["库存","factory_stock","modules"],["区域","zone_planning","modules"],["生产","factory_production","production"],["物流","factory_logistics","logistics"],["人物","factory_people","workforce"],["地图与告警","factory_alerts","modules"],["手册","factory_handbook","modules"]]:
		if not F.section(ui.factory, spec[2]).get("available", false): continue
		var button: Button = ui.add_button(str(spec[0]), func(): ui.open_panel(spec[1]), "factory:nav:" + spec[1], "", row)
		if row is VBoxContainer: button.custom_minimum_size.x = roundi(112 * ui.text_scale)
		else: button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = "NavigationButton"
		button.toggle_mode = true
		button.set_pressed_no_signal(active == spec[1])
		button.tooltip_text = "当前页面" if active == spec[1] else ""

static func _search(ui, parent: Node, key: String, hint: String = "搜索名称或物料") -> void:
	var entry := LineEdit.new()
	entry.placeholder_text = hint
	entry.text = str(ui.factory_view.get(key, ""))
	entry.clear_button_enabled = true
	entry.theme_type_variation = "SearchField"
	entry.set_meta("ui_focus_key", "factory:search:" + key)
	entry.text_changed.connect(func(value: String): ui.factory_view[key] = value; ui.queue_refresh())
	parent.add_child(entry)

static func _matches(ui, key: String, values: Array) -> bool:
	var query := str(ui.factory_view.get(key, "")).strip_edges().to_lower()
	return query.is_empty() or " ".join(values.map(func(v): return str(v))).to_lower().contains(query)

static func _modules(ui, body: VBoxContainer) -> void:
	_search(ui, body, "modules_search", "查找已发现的设施")
	var count := 0
	var cards := GridContainer.new()
	cards.columns = 2 if ui.get_viewport_rect().size.x >= 1200 and ui.text_scale <= 1.0 else 1
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(cards)
	for row: Dictionary in F.rows(ui.factory, "modules", "instances"):
		if not _matches(ui, "modules_search", [row.get("name", ""), row.get("source_name", ""), row.get("use_hint", ""), row.get("id", ""), F.state_text(row)]): continue
		count += 1
		var card := _card(cards)
		card.set_meta("ui_module_id", str(row.id))
		C.image_row(ui, card, Images.module_texture(F.definition(ui.factory, str(row.get("definition_id", "")))), str(row.get("name", row.id)), F.state_text(row), roundi(64 * ui.text_scale))
		C.caption(ui,str(row.get("use_hint", "查看可用操作")),card)
		card.tooltip_text = str(row.get("source_name", "")) + "\n" + F.location(row.get("location"))
		_blockers(ui, row, card)
		var action: Button = ui.add_button("打开" + str(row.get("name", "建筑")), func(): ui.open_panel("factory_module", str(row.id)), "factory:module:" + str(row.id), "", card)
		# Shrink-to-content needs native text width. A wrapping vertical action
		# otherwise reports only its empty style padding and collapses to a bar.
		action.autowrap_mode = TextServer.AUTOWRAP_OFF
		action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if count == 0: ui.paragraph("此范围内没有匹配的已发现设施。", body)

static func _catalog(ui, body: VBoxContainer) -> void:
	Catalog.render(ui, body)

static func _module(ui, body: VBoxContainer, id: String) -> void:
	ObjectPanel.render(ui, body, id)

static func _inventory(ui, body: VBoxContainer, id: String) -> void:
	var pack:Dictionary=P.player_stock(ui.snapshot)
	# A subject equal to the current pack is one inventory, never a transfer pair.
	var paired:bool=not id.is_empty() and id!=str(pack.get("id",""))
	var stock := F.visible_stock(ui.factory, ui.snapshot, id)
	if paired:
		for module:Dictionary in F.rows(ui.factory,"modules","instances"):
			if module.get("stock_refs",{}).values().has(id):
				Access.nearby(ui,body,module,ui.read_service_approaches(str(module.id)))
				break
	C.caption(ui,"拖到另一侧取放 · Shift点击快速转移 · 右键拆分 · Esc归位" if paired else "拖动整理 · 右键拆分 · 拖到快捷栏绑定 · Esc归位", body)
	if paired and not stock.is_empty() and stock.get("searched",false) and not stock.get("display_only",false):
		var payload: Dictionary = ui.take_all_payload(stock,ui.snapshot)
		var ready: Dictionary = ui.availability(ui.request("take",id,payload)) if not payload.items.is_empty() or not payload.tool_ids.is_empty() else {"ok":false,"reason":"没有未预留的可取物品"}
		var actions := HBoxContainer.new(); body.add_child(actions)
		C.primary(ui.add_button("拿取全部可用物品 → 背包",ui.take_all_current,"factory:inventory:take-all","" if ready.get("ok",false) else P.feedback_text(ready),actions))
		C.caption(ui,"一次提交；容量不足时保留原物品，可按件取走。",body)
	if paired: Stories.source_actions(ui, body, id)
	if not ui.carry.is_empty() and paired:
		var taking:bool=ui.carry.source.get("stock_id")==id
		var reason: String = ui.factory_transfer_reason(stock)
		ui.add_button(("取出到背包 · " if taking else "存入当前容器 · ")+str(ui.carry.get("name","物品"))+" × "+P.number(ui.carry.get("amount")),ui.transfer_carried,"factory:inventory:transfer",reason,body)
	var geometry:Dictionary=inventory_geometry(ui,paired)
	var pair: Container = HBoxContainer.new() if geometry.horizontal else VBoxContainer.new()
	pair.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	pair.set_meta("ui_inventory_pair",paired)
	pair.set_meta("ui_inventory_orientation","horizontal" if geometry.horizontal else "vertical")
	pair.add_theme_constant_override("separation",8)
	body.add_child(pair)
	for spec in [["随身背包",pack],["当前容器",stock]]:
		if not paired and spec[0]=="当前容器":continue
		var column := C.card(pair); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not paired: column.set_meta("ui_inventory_single", true)
		column.set_meta("ui_inventory_stock",str(spec[1].get("id","")))
		column.set_meta("ui_inventory_width",geometry.grid_width)
		Panels.heading(ui, str(spec[0]), column)
		var current: Dictionary = spec[1]
		if current.is_empty(): ui.paragraph("容器已不可见或不存在。",column); continue
		if not current.get("searched",false): ui.paragraph("尚未搜索，内容不可见。",column); continue
		if current.get("display_only",false):
			for buffer:Dictionary in F.stock_buffers(ui.factory,str(current.id)):ui.paragraph(F.buffer_text(buffer),column)
			ui.paragraph("远程汇总 · 靠近建筑即可查看工具、书册与取放",column)
		else:
			if spec[0] == "当前容器": Movable.container_actions(ui, column, current)
			ui.inventory_grid(current,column)
			var buffers:=F.stock_buffers(ui.factory,str(current.id))
			if not buffers.is_empty():
				var key:="stock_details:"+str(current.id)
				ui.add_button("收起容量与预留" if ui.factory_view.get(key,false) else "容量与预留",func():ui.factory_view[key]=not ui.factory_view.get(key,false);ui.queue_refresh(),"factory:inventory:details:"+str(current.id),"",column)
				if ui.factory_view.get(key,false):
					for buffer:Dictionary in buffers:ui.paragraph(F.buffer_text(buffer),column)
	if not paired:ui.paragraph("在现场按E打开容器，即可与背包取放；快捷栏引用真实背包物品。",body)
	if paired and not stock.is_empty() and stock.get("searched",false):
		var reason: String = ui.factory_transfer_reason(stock)
		ui.paragraph("现场可取放，提交时仍复检容量、权限和预留。" if reason.is_empty() else "当前仅查看 · " + reason,body)
		if F.section(ui.factory,"logistics").get("available",false): ui.add_button("查看运输任务",func(): ui.open_panel("factory_logistics",id),"factory:stock:logistics","",body)

static func inventory_geometry(ui,paired:bool)->Dictionary:
	# Render may run before native containers finish sorting after a resize.
	# Budget from the actual viewport and window chrome, not the stale full
	# dialog width; subtract the visible navigation rail and scroll-bar gutter.
	var viewport_width:float=ui.get_viewport_rect().size.x
	var dialog_width:float=minf(float(ui._dialog.size.x),maxf(160,viewport_width-32))
	var panel_margin:float=ui._dialog.get_theme_stylebox("panel").get_minimum_size().x
	var navigation_width:float=0
	if ui._panel_navigation.visible:
		navigation_width=maxf(ui._panel_navigation.get_combined_minimum_size().x,112*float(ui.text_scale))+float(ui._workspace.get_theme_constant("separation"))
	var scrollbar:float=maxf(12,ui._scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var available:float=maxf(96,dialog_width-panel_margin-navigation_width-scrollbar-8)
	var card_margin:float=maxf(24,ui._dialog.get_theme_stylebox("panel","WorkshopCard").get_minimum_size().x)
	var four_slots:float=4*(64*float(ui.text_scale)+8)
	var horizontal:bool=paired and available>=2*(four_slots+card_margin)+8
	var grid_width:float=maxf(64*float(ui.text_scale),((available-8)*0.5 if horizontal else available)-card_margin)
	return {"horizontal":horizontal,"grid_width":grid_width,"available_width":available}

static func _production(ui, body: VBoxContainer) -> void:
	if not F.section(ui.factory,"production").get("available",false): ui.paragraph("生产能力尚不可用。",body); return
	_search(ui,body,"production_search","筛选设施、订单或批次")
	var count := 0
	for module:Dictionary in F.rows(ui.factory,"modules","instances"):
		var machine:bool=F.definition(ui.factory,str(module.definition_id)).get("recipe_modes",[]).has("machine")
		if not machine and module.get("recipe_management",{}).get("recipes",[]).is_empty():continue
		if not _matches(ui,"production_search",[module.get("name",""),module.id]):continue
		count+=1
		var card:=_card(body);Panels.heading(ui,str(module.name),card)
		if machine:Ops.machine(ui,card,str(module.id))
		Mechanisms.recipes(ui,card,module,true)
		for row:Dictionary in F.rows(ui.factory,"production","batches"):
			if row.get("module_id")!=module.id:continue
			Panels.heading(ui,"批次 · "+str(row.id),card);Ops.batch(ui,card,row)
		ui.add_button("打开现场缓存",func():ui.open_panel("factory_module",str(module.id)),"factory:order:"+str(module.id),"",card)
	if count == 0: ui.paragraph("尚无匹配的真实订单或批次。",body)

static func _logistics(ui, body: VBoxContainer) -> void:
	if not F.section(ui.factory,"logistics").get("available",false): ui.paragraph("运输能力尚不可用。",body);return
	_search(ui,body,"logistics_search","筛选物料、设施或运输任务")
	var tasks := F.rows(ui.factory,"logistics","tasks")
	var form := C.fold(ui, body, "logistics:create", "安排新的取送", tasks.is_empty() or not ui.factory_view.get("logistics_context", {}).is_empty())
	if form != null: Ops.logistics_form(ui,form)
	for task: Dictionary in tasks:
		if not _matches(ui,"logistics_search",[task.get("id",""),task.get("item_id",""),task.get("source_id",""),task.get("destination_id","")]):continue
		var card := _card(body);Panels.heading(ui,str(task.get("name",task.get("id","运输"))),card)
		ui.paragraph(F.state_text(task),card);_blockers(ui,task,card)
		# Only published fields; no invented route, ETA, cargo or automatic fill.
		for field in [["source_id","来源"],["actor_id","承运者"],["destination_id","目的地"]]:
			if task.has(field[0]):
				var target := str(task[field[0]])
				var name: String = str(P.find(ui.snapshot.get("actors", []), target).get("name", "待分配")) if field[0] == "actor_id" else Ops.endpoint_name(ui, target)
				ui.paragraph(field[1]+" · "+name,card)
		ui.item_row(task.get("items",{}),"承运中（尚未入库）" if task.get("phase")=="deliver" and task.get("status") not in ["completed","cancelled"] else "本次需求清单（不代表已取货）",card)
		ui.paragraph(("重复取送" if task.get("repeat",false) else "单次取送")+" · 已完成 "+P.number(task.get("trips",0))+" 趟 · 优先级 "+P.number(task.get("priority",0)),card)
		if not str(task.get("reason","")).is_empty():ui.paragraph(P.reason_text(task.reason),card)
		Ops.logistics_workers(ui,card,task)
		Ops.logistics_retarget(ui,card,task)
		if task.get("status") not in ["cancelled","completed","cargo_held"]:
			Ops.action(ui,card,"取消运输…","logistics.cancel",str(task.id),{},"","停止此任务及重复取送。已取出的货物仍由实际人物持有，不瞬移回源库存；未取货的任务直接取消。")
	if tasks.is_empty():ui.paragraph("尚未安排运输；没有把远方物资计入现场可用量。",body)

static func _people(ui, body: VBoxContainer, focus_id: String = "") -> void:
	if not focus_id.is_empty():
		ui.add_button("查看全部人物", func(): ui.open_panel("factory_people"), "factory:people:all", "", body)
		_people_members(ui, body, focus_id)
		return
	var player:=P.player(ui.snapshot)
	var self_card := C.card(body)
	Identity.header(ui,self_card,player,64)
	var stats := HFlowContainer.new(); self_card.add_child(stats)
	for field in [["hp","生命"],["hunger","饱食"],["thirst","饮水"],["stamina","体力"],["fatigue","疲劳"]]:
		if player.has(field[0]): C.caption(ui,field[1]+" "+P.stat_number(player[field[0]]),stats)
	LifeCare.render(ui,self_card)
	if player.get("intent") is Dictionary:
		Panels._action(ui,"取消当前行动","cancel_work" if player.intent.get("owner")=="actions" else "cancel","",{},self_card,true)
	_people_members(ui, body)
	ui.housing_view.render(ui,body)

static func _people_members(ui, body: VBoxContainer, focus_id: String = "") -> void:
	if not F.section(ui.factory,"workforce").get("available",false):ui.paragraph("岗位分工尚不可用。",body);return
	var people := GridContainer.new(); people.columns = 2 if ui.get_viewport_rect().size.x >= 1200 and ui.text_scale <= 1.0 else 1
	people.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(people)
	var count := 0
	for member: Dictionary in F.rows(ui.factory,"workforce","members"):
		var id := str(member.get("actor_id",""));var actor := P.find(ui.snapshot.get("actors",[]),id)
		if id == str(P.player(ui.snapshot).get("id", "player")) or not focus_id.is_empty() and id != focus_id: continue
		count += 1
		var card := _card(people);Identity.header(ui,card,actor)
		card.set_meta("ui_person_id", id)
		Identity.cargo(ui,card,id)
		ui.paragraph("同意工作" if member.get("consent",false) else "尚未同意工作",card)
		if member.get("activity", "") != actor.get("activity", "") and not str(member.get("activity", "")).is_empty():
			C.caption(ui,"岗位 · "+P.activity_text(member),card)
		ui.paragraph(F.location(actor),card)
		C.caption(ui,Identity.needs(actor),card)
		var assignment:=F.find(F.rows(ui.factory,"workforce","assignments"),id,"actor_id")
		if not assignment.is_empty() and not assignment.has("building_phase"):ui.paragraph("当前岗位 · 已接受你的安排",card)
		var person:=F.find(F.rows(ui.factory,"workforce","people"),id,"actor_id")
		# The public facade accepts an actor ID. Query only members already
		# disclosed to the player; no wildcard or private E/B reads.
		# Summary people exist too: they are not proof of an empty job list.
		# Every displayed member card requests its complete same-owner details.
		person=ui.workforce_person(id)
		ui.add_button("刷新可安排工作",func():ui.refresh_workforce_person(id),"factory:workforce:refresh:"+id,"",card)
		Ops.workforce(ui,card,member,assignment,person)
		if not person.is_empty() and person.has("decision"):
			var decision:Dictionary=person.get("decision",{})
			ui.paragraph("当前决策 · "+Identity.decision_text(decision),card)
		elif not person.has("candidates"):
			C.caption(ui,"尚未获得完整岗位查询；请刷新后查看可安排工作",card)
		if id!="player":
			ui.add_button("人物与合作",func():ui.open_panel("npc",id),"factory:person:"+id,"",card)
			ui.add_button("共同经历",func():Stories.open_person(ui,id),"factory:person:stories:"+id,"",card)
	if count == 0:
		ui.paragraph("这位幸存者目前不在可分工的同行名单中。已有经历保留，合作须由本人同意。" if not focus_id.is_empty() else "目前没有可分工的同行者。", body)
		if not focus_id.is_empty() and not P.find(ui.snapshot.get("actors", []), focus_id).is_empty():
			ui.add_button("查看人物与合作", func(): ui.open_panel("npc", focus_id), "factory:person:" + focus_id, "", body)

static func _alerts(ui, body: VBoxContainer, site_id:String="") -> void:
	Alerts.render(ui, body, site_id)

static func _handbook(ui, body: VBoxContainer) -> void:
	Handbook.render(ui, body)

static func _blockers(ui, row: Dictionary, parent: Node) -> void:
	var blockers: Variant = row.get("blockers",[])
	if not blockers is Array:return
	for blocker in blockers:
		var receipt: Dictionary = blocker if blocker is Dictionary else {"reason":str(blocker)}
		var text: String = str(receipt.get("label", ""))
		if not str(receipt.get("reason", "")).is_empty() or not str(receipt.get("code", "")).is_empty(): text = P.feedback_text(receipt)
		var note: Label = ui.paragraph(text, parent)
		note.tooltip_text = P.feedback_diagnostic(receipt)

static func _card(parent: Node) -> VBoxContainer:
	return C.card(parent)
