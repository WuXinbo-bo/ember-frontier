extends RefCounted
## UI intentions only. Preflight and settlement remain with Runtime/B/E.
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const Content = preload("res://scripts/runtime/content_definitions.gd")

static func action(ui, parent: Node, title: String, kind: String, target: String, payload: Dictionary = {}, worker: String = "", caution: String = "") -> Button:
	var command: Dictionary = ui.request(kind, target, payload)
	if not worker.is_empty(): command.actor_id = worker
	var ready: Dictionary = ui.availability(command)
	var reason := "" if ready.get("ok", false) else P.feedback_text(ready)
	var action_id := "factory:command:" + kind + ":" + target + (":"+worker if not worker.is_empty() else "")
	if kind.begins_with("module.recipe.") or kind=="module.upgrade":action_id+=":"+str(payload.get("order_id",payload.get("recipe_id",payload.get("definition_id",""))))
	return ui.add_button(title, func():
		if caution.is_empty(): ui.execute(kind, target, payload, resumes_world(kind,payload), worker)
		else:
			ui.factory_view.confirm = {"kind":kind,"target_id":target,"payload":payload.duplicate(true),"worker":worker,"world_id":ui.factory.get("world_id"),"consequence":caution}
			ui.open_panel("factory_confirm", target), action_id, reason, parent)

static func resumes_world(kind:String,payload:Dictionary)->bool:
	return kind in ["module.work","module.repair","module.restore","module.dismantle","module.clear_ruin","module.upgrade"] or (kind=="module.held" and payload.get("held",false))

static func confirmation(ui, body: VBoxContainer) -> void:
	var pending: Dictionary = ui.factory_view.get("confirm", {})
	if pending.is_empty() or pending.get("world_id") != ui.factory.get("world_id"):
		ui.paragraph("原操作已失效，请返回重新选择。",body);return
	Panels.heading(ui,"确认操作后果",body)
	ui.paragraph(str(pending.consequence),body)
	ui.add_button("返回 · 保持原状",ui.cancel_ui,"factory:confirm:cancel","",body)
	var command: Dictionary = ui.request(pending.kind,pending.target_id,pending.payload)
	if not str(pending.worker).is_empty():command.actor_id=pending.worker
	var ready: Dictionary=ui.availability(command)
	ui.add_button("确认执行",func():
		var result:Dictionary=ui.execute(pending.kind,pending.target_id,pending.payload,false,pending.worker)
		if result.get("ok",false):
			ui.factory_view.erase("confirm")
			if resumes_world(pending.kind,pending.payload):ui.close_panels()
			else:ui.cancel_ui(),"factory:confirm:submit","" if ready.get("ok",false) else P.feedback_text(ready),body)
	ui._restore_focus.call_deferred("factory:confirm:cancel")

static func machine(ui, parent: Node, module_id: String) -> void:
	var module := F.instance(ui.factory,module_id)
	var definition := F.definition(ui.factory,str(module.get("definition_id","")))
	if not definition.get("recipe_modes",[]).has("machine"):return
	if module.get("status") in ["ruined","dismantled"] or module.get("state_code") == "needs_restoration":return
	C.heading(ui,"生产目标",parent)
	var orders := F.rows(ui.factory,"production","orders")
	var order := F.find(orders,module_id,"module_id")
	if not order.is_empty():
		ui.paragraph(F.state_text(order)+" · 已完成 "+P.number(order.get("completed"))+" 批 · 剩余 "+("连续" if int(order.get("remaining",0))<0 else P.number(order.get("remaining"))+" 批"),parent)
		ui.paragraph("本地剩余能量 · "+P.number(order.get("energy_seconds"))+" 有效工作秒",parent)
		
	for recipe:Dictionary in F.rows(ui.factory,"production","recipes"):
		if recipe.get("mode")!="machine":continue
		C.production_flow(ui,parent,recipe.get("inputs",{}),recipe.get("outputs",{}),recipe.get("seconds"))
		ui.paragraph("有效加工 "+P.number(recipe.get("seconds"))+" 秒 · "+P.item_name(str(recipe.get("fuel_item","")))+" 每件提供 "+P.number(recipe.get("fuel_seconds_per_unit"))+" 有效秒",parent)
		var key := "batches:"+module_id
		var amount := _number(ui,parent,key,"批数（含当前未完成批）",1,9999,1,1)
		var repeat := CheckBox.new();repeat.text="持续生产";repeat.button_pressed=bool(ui.factory_view.get("continuous:"+module_id,false));parent.add_child(repeat)
		repeat.set_meta("ui_focus_key","factory:continuous:"+module_id)
		repeat.toggled.connect(func(value:bool):ui.factory_view["continuous:"+module_id]=value;ui.queue_refresh())
		C.caption(ui,"配置成功只更新目标。世界暂停时加工尚未推进；关页后按真实条件继续。",parent)
		C.primary(action(ui,parent,"配置并启用","factory.configure",module_id,{"recipe_id":recipe.id,"batches":-1 if repeat.button_pressed else int(amount)}))
	if order.is_empty():return
	action(ui,parent,"恢复生产" if order.get("paused",false) else "暂停生产","factory.resume" if order.get("paused",false) else "factory.pause",module_id)
	var progressed:=false
	for row:Dictionary in F.rows(ui.factory,"production","batches"):
		if row.get("module_id")==module_id and row.get("status") in ["active","blocked","refund_pending"] and float(row.get("elapsed",0))>0:progressed=true
	if order.get("allowed_actions",[]).has("factory.discard"):
		action(ui,parent,"停止后续生产…","factory.cancel",module_id,{},"","停止后续订单；已开工批次停工并保留在制，不还原整根木材。尚未开工的投入退合法本地缓存，无容量则等待。已耗能源不退。")
		if progressed:action(ui,parent,"废弃在制…","factory.discard",module_id,{"confirm_discard":true},"","永久废弃此批已开工在制原料；板件回收为0，已耗能源不退。仅释放其输出容量预约，不会发放产物或整木退款。")
	elif progressed:
		ui.paragraph("本批已开工；暂停保留在制，已耗能源不退。停止后续／废弃在制须由真实执行器提供相应动作与后果，当前不可用。",parent)
	else:
		action(ui,parent,"取消未开工生产…","factory.cancel",module_id,{},"","停止后续订单；尚未产生有效工时的本批原料退本地输入缓存，无容量则保持待处理在制。已耗能源不退。")

static func batch(ui,parent:Node,row:Dictionary)->void:
	ui.paragraph(F.state_text(row),parent)
	ui.item_row(row.get("wip",{}),"本批在制原料（已从输入扣除）",parent)
	ui.item_row(row.get("outputs",{}),"本批输出承诺（尚非实物）",parent)
	if float(row.get("duration",0))>0:
		ui.paragraph("有效进度 "+P.number(row.get("elapsed"))+" / "+P.number(row.duration)+" 秒",parent)
		var bar:=ProgressBar.new();bar.max_value=float(row.duration);bar.value=float(row.get("elapsed",0));bar.show_percentage=false;parent.add_child(bar)
	if not str(row.get("paused_reason","")).is_empty():ui.paragraph(str(F.STATE_NAMES.get(row.paused_reason,row.paused_reason)),parent)

static func _number(ui,parent:Node,key:String,title:String,minimum:float,maximum:float,step:float,default:float)->float:
	ui.paragraph(title,parent)
	var input:=SpinBox.new();input.min_value=minimum;input.max_value=maxf(minimum,maximum);input.step=step;input.value=float(ui.factory_view.get(key,default));input.allow_greater=false
	input.get_line_edit().set_meta("ui_focus_key","factory:number:"+key)
	parent.add_child(input)
	input.value_changed.connect(func(value:float):ui.factory_view[key]=value;ui.queue_refresh())
	return input.value

static func _choice(ui,parent:Node,key:String,title:String,rows:Array,default:String="")->String:
	ui.paragraph(title,parent)
	var chosen:=str(ui.factory_view.get(key,default))
	if F.find(rows,chosen).is_empty():chosen=str(rows[0].id) if not rows.is_empty() else ""
	ui.factory_view[key]=chosen
	var input:=OptionButton.new();input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;input.clip_text=true;input.set_meta("ui_focus_key","factory:choice:"+key)
	for index in rows.size():
		input.add_item(str(rows[index].get("name",rows[index].id)));input.set_item_metadata(index,str(rows[index].id));input.set_item_tooltip(index,str(rows[index].get("description",rows[index].id)))
		if rows[index].id==chosen:input.select(index)
	input.disabled=rows.is_empty();parent.add_child(input)
	input.item_selected.connect(func(index:int):ui.factory_view[key]=str(rows[index].id);ui.queue_refresh())
	return chosen

static func logistics_form(ui,parent:Node)->void:
	var stocks:Array=[]
	for module:Dictionary in F.rows(ui.factory,"modules","instances"):
		for ref:Dictionary in F.known_stocks(ui.factory,ui.snapshot,module):
			if ref.stock.is_empty() or not ref.stock.get("searched",false):continue
			var entries:Array=[]
			if ref.stock.get("display_only",false):
				for buffer:Dictionary in F.stock_buffers(ui.factory,str(ref.stock_id)):
					if float(buffer.actual)>0:entries.append({"reference":{"kind":"item","item_id":buffer.item_id},"name":P.item_name(str(buffer.item_id)),"amount":buffer.actual,"step":Content.quantity_step(str(buffer.item_id),true),"label":"现有"})
			else:
				for entry:Dictionary in P.entries(ref.stock,ui.snapshot):
					if entry.get("reference",{}).get("kind")=="item" and float(entry.get("available",0))>0:entries.append(entry.merged({"amount":entry.available,"label":"可用"}))
			stocks.append({"id":ref.stock_id,"name":str(module.name)+" · "+str({"input":"原料箱","output":"成品箱","fuel":"燃料箱","tools":"工具架","storage":"仓储","supplies":"生活物资"}.get(str(ref.buffer_id),"设施缓存")),"description":F.location(ref.stock.get("location")),"stock":ref.stock,"entries":entries})
	var sources:Array=stocks.filter(func(row:Dictionary):return not row.entries.is_empty())
	if sources.is_empty():ui.paragraph("尚无已搜索且有可用物料的授权来源，请先到现场发现与搜索。",parent);return
	C.heading(ui,"安排取送",parent)
	var context: Dictionary = ui.factory_view.get("logistics_context", {})
	var context_module := F.instance(ui.factory, str(context.get("module_id", "")))
	if not context_module.is_empty(): C.caption(ui,("清运 · " if context.get("direction") == "out" else "供料 · ") + str(context_module.get("name", "设施")),parent)
	var source:=_choice(ui,parent,"logistics_source","来源库存",sources)
	var destinations:Array=stocks.filter(func(row:Dictionary):return row.id!=source)
	if destinations.is_empty():
		C.heading(ui,"尚无接收库存",parent)
		C.caption(ui,"目前没有另一处已搜索且有权使用的设施缓存。先到现场搜索接收设施；新建仓储也需实际完工与搜索。",parent)
		var routes := HFlowContainer.new(); parent.add_child(routes)
		ui.add_button("查看已发现设施",func():ui.open_panel("factory"),"factory:logistics:find-receiver","",routes)
		ui.add_button("查看仓储建造",func():ui.factory_view.catalog_category="storage";ui.open_panel("factory_catalog"),"factory:logistics:build-receiver","",routes)
		return
	var destination:=_choice(ui,parent,"logistics_destination","目的库存",destinations)
	var items:Array=[]
	for entry:Dictionary in F.find(sources,source).get("entries",[]):
		items.append({"id":entry.reference.item_id,"name":str(entry.name)+" · "+str(entry.label)+" "+P.number(entry.amount),"entry":entry})
	var item:=_choice(ui,parent,"logistics_item","物料",items)
	var entry:Dictionary=F.find(items,item).get("entry",{})
	var step:=float(entry.get("step",1))
	var amount:=_number(ui,parent,"logistics_amount:"+item,"每次取送量",step,float(entry.get("amount",step)),step,step)
	var repeat:=CheckBox.new();repeat.text="重复取送（仍需实际取货与容量）";repeat.button_pressed=bool(ui.factory_view.get("logistics_repeat",false));parent.add_child(repeat)
	repeat.toggled.connect(func(value:bool):ui.factory_view.logistics_repeat=value;ui.queue_refresh())
	var priority:=_number(ui,parent,"logistics_priority","任务优先级",-100,100,1,0)
	if not destination.is_empty() and not item.is_empty():action(ui,parent,"创建运输任务","logistics.create","",{"source_id":source,"destination_id":destination,"items":{item:amount},"repeat":repeat.button_pressed,"priority":priority})
	ui.paragraph("只登记任务；远程现有量不承诺全部可取，预约、权限与容量在提交和实际取送时复检。不会瞬移货物或承诺到达时间。",parent)

static func endpoint_name(ui, id: String) -> String:
	for module: Dictionary in F.rows(ui.factory,"modules","instances"):
		for key: String in module.get("stock_refs",{}):
			if module.stock_refs[key] == id:
				return str(module.get("name","已知设施")) + " · " + str({"input":"原料箱","output":"成品箱","fuel":"燃料箱","tools":"工具架","storage":"仓储","supplies":"生活物资"}.get(key,"设施缓存"))
	return str(F.visible_stock(ui.factory,ui.snapshot,id).get("name","原任务库存暂不可见"))

static func logistics_retarget(ui,parent:Node,task:Dictionary)->void:
	if task.get("status")!="cargo_held" or task.get("phase")!="deliver":return
	var known:Dictionary={}
	for module:Dictionary in F.rows(ui.factory,"modules","instances"):
		for ref:Dictionary in F.known_stocks(ui.factory,ui.snapshot,module):
			if ref.stock.get("searched",false):known[str(ref.stock_id)]=str(module.name)+" · "+str({"input":"原料箱","output":"成品箱","fuel":"燃料箱","tools":"工具架","storage":"仓储","supplies":"生活物资"}.get(str(ref.buffer_id),"设施缓存"))
	for stock:Dictionary in P.records(ui.snapshot.get("stocks",[])):
		var id:=str(stock.get("id",""))
		if not id.begins_with("pack:") and F.stock_visible(ui.factory,ui.snapshot,id) and not known.has(id):known[id]=str(stock.get("name","现场库存"))+" · "+F.location(stock.get("location"))
	var destinations:Array=[]
	for id:String in known:
		if id==task.get("source_id"):continue
		var ready:Dictionary=ui.availability(ui.request("logistics.retarget",str(task.id),{"destination_id":id}))
		if ready.get("ok",false):destinations.append({"id":id,"name":known[id]})
	ui.paragraph("货仍在原承运者背包；改目的只调整同一任务，实际送达后才入库。",parent)
	if destinations.is_empty():
		ui.paragraph("暂无已搜索且通过权限／容量校验的接收库存。先到现场发现容器、清出空间或处理不安全交接，再回来改目的。",parent);return
	var destination:=_choice(ui,parent,"retarget:"+str(task.id),"改送至",destinations)
	action(ui,parent,"确认更改原任务目的地…","logistics.retarget",str(task.id),{"destination_id":destination},"","只修改原携货任务的目的库存，保留原任务ID、来源和承运者背包。停止重复取送，货物仍需原人物实际送达；确认不会新建运输任务、复制货物或立即入库。")

static func regional_event(ui,parent:Node,site_id:String="")->void:
	var event:Dictionary=F.section(ui.factory,"workforce").get("regional_event",{})
	if event.is_empty():return
	Panels.heading(ui,"镇向运输路",parent)
	if not event.get("available",false):
		ui.paragraph(str(event.get("reason","真实勘察地点尚不可用；不会代为确认或触发威胁。")),parent);return
	var sites:=F.dictionaries(event.get("sites",[]))
	if not site_id.is_empty():
		sites=sites.filter(func(site:Dictionary):return site.get("id")==site_id)
		if sites.is_empty():ui.paragraph("此地点当前尚未公开或已失效；请回到现场确认。",parent)
	for site:Dictionary in sites:
		var id:=str(site.get("id",""))
		if id.is_empty():continue
		Panels.heading(ui,str(site.get("title","道路勘察点")),parent)
		ui.paragraph(str(site.get("description","先实地勘察，再决定是否承担清障的动静风险。")),parent)
		ui.paragraph(F.location(site.get("location")),parent)
		ui.paragraph("勘察 · "+("已完成" if site.get("surveyed",false) else "未完成")+" / 风险承诺 · "+("已确认" if site.get("risk_accepted",false) else "未确认")+" / 实际通路 · "+("已打通" if site.get("corridor_clear",false) else "待清障")+" / 地区目标 · "+("已完成" if site.get("completed",false) else "进行中"),parent)
		for command:Dictionary in F.dictionaries(site.get("commands",[])):
			var kind:=str(command.get("kind",""))
			if kind not in ["settlement.survey","settlement.begin_route_work"]:continue
			var payload:Dictionary=command.get("payload",{}).duplicate(true)
			if payload.get("site_id")!=id:continue
			var caution:=""
			var title:="实地勘察"
			if kind=="settlement.survey":payload.erase("accept_risk")
			else:
				payload.accept_risk=true;title="开始清障 · 先确认风险…"
				caution="同意开始会产生动静的清障／恢复作业并承担有预告的当地威胁。真实现场、工具、补给和防线仍需准备；此确认不清除障碍、不直接获胜或发放材料。"
			var button:=action(ui,parent,title,kind,"",payload,"",caution)
			if not command.get("available",false) and not button.disabled:
				button.disabled=true;button.tooltip_text=P.feedback_text(command);ui.paragraph(button.tooltip_text,parent)
	var defense:Dictionary=event.get("defense",{})
	var status:=str(defense.get("status","dormant"))
	if status=="dormant":return
	ui.paragraph("地区威胁 · "+str({"warning":"预告中 · 请准备返程与防线","awaiting_execution":"等待真实遭遇就绪","active":"遭遇进行中","cleared":"本次遭遇已结束"}.get(status,status)),parent)
	if status=="warning" and defense.has("warning_remaining"):ui.paragraph("有效预告余时 · "+P.number(defense.warning_remaining)+" 秒 · 随同一世界暂停规则推进",parent)

static func building_order_label(row:Dictionary)->String:
	return {"queued":"等待同伴接单","blocked":"等待施工条件","supplying":"正在备料","preparing":"正在备料","accepted":"已接单","completed":"已完工","ended":"工程已结束"}.get(row.get("building_phase","queued"),"已安排")

static func building_order_status(row:Dictionary, work:Dictionary={})->String:
	var label:=building_order_label(row)
	var reason:=str(row.get("building_reason",""))
	if row.get("building_phase")=="accepted" and not work.is_empty():
		label={"approaching":"正在前往施工点","working":"现场施工中","paused":"施工暂停","completed":"已完工","cancelled":"工程已取消"}.get(work.get("phase"),label)
		if work.get("phase")=="paused" and reason.is_empty():reason=str(work.get("paused_reason",""))
	return label if reason.is_empty() else label+" · "+reason

static func workers(ui, preferred:String="")->Array:
	return F.rows(ui.factory,"workforce","members").filter(func(member:Dictionary)->bool:
		var id:String=str(member.get("actor_id",""))
		return id not in ["","player"] and (preferred.is_empty() or preferred==id) and member.get("alive",false) and member.get("consent",false))

static func worker_choices(ui, preferred:String="")->Array:
	var rows:=workers(ui,preferred)
	# A logistics page does not request workforce details. The actor summary
	# still carries the membership needed to show eligible controls.
	if rows.is_empty() and F.section(ui.factory,"workforce").get("details_state")=="not_requested":
		for actor:Dictionary in P.records(ui.snapshot.get("actors",[])):
			var id:String=str(actor.get("id",""));var relation:Dictionary=actor.get("relationship",{})
			if id not in ["","player"] and (preferred.is_empty() or preferred==id) and relation.get("member",false) and relation.get("consent",false) and float(actor.get("hp",0))>0:rows.append({"actor_id":id})
	return rows.map(func(row:Dictionary)->Dictionary:
		var id:String=str(row.actor_id);var actor:=P.find(ui.snapshot.get("actors",[]),id)
		return {"id":id,"name":str(actor.get("name","同伴"))})

static func companion_project(ui,parent:Node,module:Dictionary)->void:
	var id:String=str(module.id)
	var orders:=F.rows(ui.factory,"workforce","assignments").filter(func(entry:Dictionary)->bool:return entry.has("building_phase") and entry.get("module_id")==id)
	var active_orders:=orders.filter(func(entry:Dictionary)->bool:return entry.get("building_phase") not in ["completed","ended"])
	var order:Dictionary=active_orders[0] if not active_orders.is_empty() else orders.back() if not orders.is_empty() else {}
	var work:Dictionary=module.get("visuals",{}).get("construction",{})
	var live:bool=not work.is_empty() and work.get("phase") not in ["completed","cancelled"] and (module.get("status")!="ruined" or work.get("rebuild",false))
	var allowed:Array=module.get("allowed_actions",[])
	var can_assign:bool=live or module.get("status")=="planned" or allowed.has("module.restore") or allowed.has("module.repair")
	if order.is_empty() and not can_assign:return
	var verb:String="原地重建" if module.get("repair_action",{}).get("rebuild",false) or (live and work.get("rebuild",false)) else "修复" if allowed.has("module.restore") or work.get("operation")=="restore" else "建造" if module.get("status") in ["planned","constructing"] else "维修" if allowed.has("module.repair") or work.get("operation")=="repair" else "接续工程"
	C.heading(ui,verb,parent)
	if not order.is_empty():
		var actor:=P.find(ui.snapshot.get("actors",[]),str(order.actor_id))
		var assigned_work:Dictionary=work if not str(order.get("project_id","")).is_empty() and work.get("project_id")==order.project_id else {}
		var status:=C.caption(ui,str(actor.get("name","同伴"))+" · "+building_order_status(order,assigned_work),parent)
		status.set_meta("ui_building_order",str(order.id))
		var progress:=F.progress(assigned_work)
		if not progress.is_empty():
			var bar:=ProgressBar.new();bar.value=progress.value*100.0;bar.show_percentage=false;parent.add_child(bar)
			C.caption(ui,"施工工时 · "+str(progress.text),parent)
		if order.get("building_phase") not in ["completed","ended"]:
			ui.add_button("撤下负责人",func():ui.execute("workforce.clear","",{},false,str(order.actor_id)),"building:worker:clear:"+id,"保留原工程进度和现场材料",parent)
			return
	if not can_assign:return
	var selected:String=ui.building_dispatch_actor() if ui.has_method("building_dispatch_actor") else ""
	var buttons:=HFlowContainer.new();parent.add_child(buttons)
	if F.section(ui.factory,"workforce").get("building_queue",[]).has(id):
		C.caption(ui,"待办 · 同伴有空时接手",parent)
		ui.add_button("取消待办",func():ui.execute("workforce.cancel_building",id),"building:worker:cancel:"+id,"",buttons)
	elif selected.is_empty():
		C.primary(ui.add_button("安排"+verb,func():
			var result:Dictionary=ui.execute("workforce.queue_building",id,{},true)
			if result.get("ok",false):ui.notify("已加入村务待办 · 同伴有空时接手"),"building:worker:auto:"+id,"",buttons))
	for choice:Dictionary in worker_choices(ui,selected):
		var worker_id:String=choice.id
		ui.add_button("交给"+str(choice.name)+verb,func():
			var result:Dictionary=ui.execute("workforce.assign","",{"candidate_id":"building-order:"+id},true,worker_id)
			if result.get("ok",false):ui.notify("已交给"+str(choice.name)+verb),"building:worker:"+worker_id+":"+id,"",buttons)

static func recipe_workers(ui,parent:Node,module:Dictionary,order:Dictionary)->void:
	var candidate_id:String="module-recipe:"+str(order.id)
	var current:=F.find(F.rows(ui.factory,"workforce","assignments"),candidate_id,"candidate_id")
	if not current.is_empty():
		var actor:=P.find(ui.snapshot.get("actors",[]),str(current.actor_id))
		C.caption(ui,"负责人 · "+str(actor.get("name","同伴")),parent)
		return
	var preferred:String=ui.building_dispatch_actor() if ui.has_method("building_dispatch_actor") else ""
	var choices:=worker_choices(ui,preferred)
	if choices.is_empty() or order.get("paused",false) or (order.get("mode")=="quantity" and int(order.get("completed",0))>=int(order.get("quantity",0))):return
	var worker_id:String=choices[0].id if choices.size()==1 else _choice(ui,parent,"recipe-worker:"+str(order.id),"加工同伴",choices)
	var command:Dictionary=ui.request("workforce.assign","",{"candidate_id":candidate_id});command.actor_id=worker_id
	var ready:Dictionary=ui.availability(command)
	var button:Button=ui.add_button("安排加工",func():ui.execute("workforce.assign","",{"candidate_id":candidate_id},true,worker_id),"building:recipe-worker:"+str(module.id)+":"+str(order.id),"" if ready.get("ok",false) else P.feedback_text(ready),parent)
	if button.disabled:button.tooltip_text=P.feedback_text(ready)

static func logistics_workers(ui,parent:Node,task:Dictionary)->void:
	if task.get("status") not in ["queued","blocked"] or task.get("phase")!="collect" or not str(task.get("actor_id","")).is_empty():return
	var id:String=str(task.id)
	var preferred:String=ui.building_dispatch_actor() if ui.has_method("building_dispatch_actor") else ""
	var choices:=worker_choices(ui,preferred)
	if choices.is_empty():return
	var worker_id:String=choices[0].id if choices.size()==1 else _choice(ui,parent,"logistics-worker:"+id,"搬运同伴",choices)
	var command:Dictionary=ui.request("workforce.assign","",{"candidate_id":id});command.actor_id=worker_id
	var ready:Dictionary=ui.availability(command)
	ui.add_button("安排搬运",func():ui.execute("workforce.assign","",{"candidate_id":id},true,worker_id),"building:logistics-worker:"+id,"" if ready.get("ok",false) else P.feedback_text(ready),parent)

static func workforce(ui,parent:Node,member:Dictionary,assignment:Dictionary,person:Dictionary={})->void:
	var actor_id:=str(member.actor_id)
	if person.is_empty():person=F.find(F.rows(ui.factory,"workforce","people"),actor_id,"actor_id")
	var candidate:Dictionary=person.get("decision",{}).get("candidate",{})
	# E publishes B's actual candidates. Keep one explicit priority request;
	# automatic work switches remain N0—N7, never a second UI assignment list.
	var candidates: Array = F.dictionaries(person.get("candidates",[])) if person.has("candidates") else [candidate] if not candidate.is_empty() else []
	var choices: Array = []
	for current: Dictionary in candidates:
		if not current.get("valid",false) or str(current.get("id","")).is_empty(): continue
		var operation := str(current.get("operation",current.get("kind","")))
		var title := str({"haul":"运输", "supply":"作业前取料", "module":"施工与维护", "zonework":"区域作业", "harvest":"采伐", "harvest_tree":"采伐", "collect_seed":"采树种", "nursery":"育苗", "plant_tree":"补种树苗", "till":"翻土", "sow":"播种", "water":"浇灌", "compost":"施肥", "harvest_crop":"收获", "fetch_water":"取水"}.get(operation,"现场工作"))
		if current.get("kind") in ["haul","supply"]: title += " · "+endpoint_name(ui,str(current.get("source_id","")))+" → "+("随身背包" if current.get("kind")=="supply" else endpoint_name(ui,str(current.get("destination_id",""))))
		elif not str(current.get("zone_id","")).is_empty(): title += " · 区域 "+str(current.zone_id)
		choices.append({"id":str(current.id),"name":title,"description":"真实执行仍复检工具、通路、同意与携货交接"})
	if not choices.is_empty():
		var id := _choice(ui,parent,"workforce_candidate:"+actor_id,"可接受的现场安排",choices)
		var priority := _number(ui,parent,"workforce_request_priority:"+actor_id,"本次安排优先级",-100,100,1,float(candidate.get("player_priority",0)))
		action(ui,parent,"安排这项工作","workforce.assign","",{"candidate_id":id,"priority":priority},actor_id)
		C.caption(ui,"一项优先安排；空闲时的兼岗由真实需求与当前任务统一仲裁",parent)
	elif person.has("candidates"): C.caption(ui,"当前没有可接受的新岗位；正在执行的工作与货物保持",parent)
	var owner := str(person.get("current_owner",""))
	if not owner.is_empty(): C.caption(ui,"执行中 · "+str({"actions":"身体劳动","zonework":"区域作业","modules":"建筑施工","production":"生产与运输","residents":"生活照料","workforce":"岗位调度","runtime":"直接行动"}.get(owner,"现场行动")),parent)
	if person.get("pending_delivery") is Dictionary and not person.pending_delivery.is_empty(): C.caption(ui,"携货交接尚未完成；新安排须等待原货物安全交付",parent)
	if person.get("suspended_work") is Dictionary and not person.suspended_work.is_empty():C.caption(ui,"原工作已暂让给生活或更紧急的需求；进度保留，按真实仲裁决定接续",parent)
	for job:Dictionary in F.dictionaries(person.get("zonework",{}).get("jobs",[])):
		if job.get("status") in ["completed","cancelled"]:continue
		C.caption(ui,"区域劳动 · "+str({"active":"执行中","paused":"手动暂停","blocked":"受阻","suspended":"暂让行动"}.get(job.get("status"),"等待")),parent)
		if float(job.get("duration_seconds",0))>0:
			var progress:=ProgressBar.new();progress.max_value=float(job.duration_seconds);progress.value=float(job.get("progress_seconds",0));progress.show_percentage=false;parent.add_child(progress)
			C.caption(ui,P.number(job.get("progress_seconds",0))+" / "+P.number(job.duration_seconds)+" 有效秒",parent)
		if not str(job.get("paused_reason","")).is_empty():C.reason(ui,parent,P.reason_text(str(job.paused_reason)))
	var failure:Dictionary=person.get("last_failure",{})
	if not failure.is_empty():C.reason(ui,parent,"上次行动未完成 · "+P.feedback_text(failure))
	if not person.get("last_decision",{}).is_empty():C.caption(ui,"已有实际仲裁记录；当前候选仅是可选安排，不代表已经执行或产出",parent)
	if assignment.is_empty():return
	if assignment.has("building_phase"):
		C.caption(ui,"建筑工程 · "+building_order_status(assignment),parent)
		ui.add_button("查看工程",func():ui.open_panel("factory_module",str(assignment.module_id)),"village:building:"+str(assignment.module_id),"",parent)
		if assignment.get("building_phase") not in ["completed","ended"]:
			ui.add_button("撤下负责人",func():ui.execute("workforce.clear","",{},false,actor_id),"village:building:clear:"+actor_id,"",parent)
		return
	var priority:=_number(ui,parent,"workforce_priority:"+actor_id,"岗位优先级",-100,100,1,float(assignment.get("priority",0)))
	action(ui,parent,"更新优先级","workforce.priority","",{"priority":priority},actor_id)
	action(ui,parent,"解除岗位…","workforce.clear","",{},actor_id,"解除该成员的岗位选择。若正在携货，真实执行器会拒绝不安全交接；界面不会清空背包、退还或复制货物。")

static func restoration(ui,parent:Node,module:Dictionary,compact:bool=false)->void:
	var id:String=str(module.id)
	var requirements:Dictionary=module.get("restoration_requirements",{})
	var ready:Dictionary=module.get("restoration_action",{})
	var work:Dictionary=module.get("visuals",{}).get("construction",{})
	var allowed:Array=module.get("allowed_actions",[])
	if not work.is_empty():
		var phase:String=str(work.get("phase",""))
		var state:String={"approaching":"正在走近建筑","working":"正在修复","paused":"修复已暂停","completed":"修复完成","cancelled":"修复已取消"}.get(phase,"正在修复" if work.get("active",false) else "施工已暂停")
		C.caption(ui,state,parent)
		var progress:Dictionary=F.progress(work)
		if not progress.is_empty():
			C.caption(ui,"已完成 "+str(roundi(float(progress.value)*100))+"%",parent)
			var bar:=ProgressBar.new();bar.value=float(progress.value)*100;bar.show_percentage=false;parent.add_child(bar)
		var pause:String=str(work.get("paused_reason",""))
		if not pause.is_empty():C.reason(ui,parent,P.reason_text(pause))
		elif not str(work.get("paused_code","")).is_empty():C.reason(ui,parent,P.reason_text(work.paused_code))
		var intent:Variant=P.player(ui.snapshot).get("intent")
		var owns:bool=intent is Dictionary and intent.get("project_id")==work.get("project_id") and (intent.get("owner")=="modules" or (intent.get("owner")=="actions" and intent.get("kind")=="module_approach"))
		if allowed.has("module.held") and owns:
			var held:bool=bool(intent.get("held",true))
			C.primary(action(ui,parent,"暂停修复" if held else "继续修复","module.held",id,{"held":not held}))
		elif allowed.has("module.work") and phase!="approaching":C.primary(action(ui,parent,"继续修复","module.work",id))
		if allowed.has("module.cancel"):
			var more:Variant=C.fold(ui,parent,"restore-cancel:"+id,"取消本次修复")
			if more!=null:action(ui,more,"取消修复…","module.cancel",id,{},"","结束本项目并释放尚未消费的材料与工具预约；原料留在原库存，不另发退款。已付劳动不退。")
		return
	if ready.get("materials") is Array:
		if compact:
			var costs: Dictionary = {}
			for material: Dictionary in ready.materials: costs[str(material.get("item_id", ""))] = material.get("required", 0)
			C.materials(ui, parent, costs, P.player_stock(ui.snapshot), "修复材料 · 从背包取用", false)
		else:
			C.caption(ui,"需要补齐",parent)
			for material:Dictionary in ready.materials:
				var line:String=P.item_name(str(material.get("item_id","")))+" · 需要 "+P.number(material.get("required"))+" / 随身可用 "+P.number(material.get("available"))
				if float(material.get("missing",0))>0:line+=" · 还缺 "+P.number(material.missing)
				C.caption(ui,line,parent)
	elif not requirements.is_empty():C.materials(ui,parent,requirements.get("cost",{}),P.player_stock(ui.snapshot),"需要补齐")
	var tool:Dictionary=ready.get("tool",{})
	if not tool.is_empty():C.caption(ui,str(tool.get("name","锤子"))+" · "+("随身可用" if tool.get("available",false) else "随身缺少可用工具"),parent)
	if requirements.is_empty():
		C.reason(ui,parent,"该建筑的修复条件尚未公开，请稍后重新查看。")
		return
	var command:Dictionary=ui.request("module.restore",id,{})
	var preflight:Dictionary=ui.availability(command)
	var why:String="" if preflight.get("ok",false) else P.feedback_text(preflight)
	if not compact:
		if not why.is_empty():C.reason(ui,parent,why)
		else:C.caption(ui,"靠近建筑即可操作；点击后自动走近，用随身锤子与材料修复。",parent)
	var start:Button=ui.add_button("修复",func():ui.execute("module.restore",id,{},true),"factory:command:module.restore:"+id,why,parent)
	C.primary(start)

static func module_work(ui,parent:Node,module:Dictionary)->void:
	var allowed:Array=module.get("allowed_actions",[])
	var id:=str(module.id)
	var project:Dictionary=module.get("visuals",{}).get("construction",{})
	if allowed.has("module.restore") or str(project.get("operation",project.get("phase","")))=="restore":
		restoration(ui,parent,module)
		return
	var has_work:=false
	for operation in ["module.work","module.cancel","module.held","module.repair","module.restore","module.dismantle","module.clear_ruin"]:
		if allowed.has(operation):has_work=true
	if not has_work:return
	Panels.heading(ui,"现场施工与维护",parent)
	ui.paragraph("靠近建筑即可操作；请带齐材料与工具，实际劳动进度由世界确认。",parent)
	if allowed.has("module.work"):action(ui,parent,"接续原项目","module.work",id)
	if allowed.has("module.held"):
		var intent:Dictionary=P.player(ui.snapshot).get("intent",{}) if P.player(ui.snapshot).get("intent") is Dictionary else {}
		if intent.get("owner")=="modules" and intent.get("project_id")==module.get("project_id"):
			action(ui,parent,"暂歇施工" if intent.get("held",true) else "恢复施工","module.held",id,{"held":not intent.get("held",true)})
	if allowed.has("module.cancel"):action(ui,parent,"取消项目…","module.cancel",id,{},"","结束本项目并释放尚未消费的材料与工具预约；原料留在原库存，不另发退款。已付劳动不退；当前模块状态由真实回执确认。")
	if allowed.has("module.clear_ruin"):
		var recovery:Dictionary=module.get("recovery",{})
		ui.item_row(recovery.get("items",{}),"本残骸冻结回收账本（清理完工后入包）",parent)
		ui.paragraph("先取走残骸现场缓存与独立工具，再进行真实清理。结构回收只结算一次，能源余额与已开工在制不恢复。",parent)
	if not allowed.has("module.repair") and not allowed.has("module.restore") and not allowed.has("module.dismantle") and not allowed.has("module.clear_ruin"):return
	var pack:=P.player_stock(ui.snapshot)
	var tools:Array=[]
	for entry:Dictionary in P.entries(pack,ui.snapshot):
		if entry.get("reference",{}).get("kind")!="tool" or float(entry.get("available",0))<=0 or float(entry.get("durability",0))<=0:continue
		var definition:Dictionary=ui.snapshot.get("catalog",{}).get("tool_definitions",{}).get(str(entry.get("definition_id","")),{})
		if float(definition.get("qualities",{}).get("hammering",0))>=1:tools.append({"id":entry.reference.tool_id,"name":entry.name})
	if tools.is_empty():ui.paragraph("随身缺少可用手锤；请先取到工具再安排维护。",parent);return
	var tool:=_choice(ui,parent,"module_tool:"+id,"随身作业工具",tools)
	var payload:Dictionary={"source_id":pack.id,"output_id":pack.id,"tool_id":tool}
	if allowed.has("module.repair"):action(ui,parent,"开始现场维修","module.repair",id,payload)
	if allowed.has("module.dismantle"):
		ui.paragraph("受控拆迁按实际已支付普通材料75%向下取合法单位；动力总成单独回收原计入件数。缓存与独立工具须先清空，活动在制须先处理。战损残骸另按50%规则，不是此操作。",parent)
		action(ui,parent,"受控拆迁…","module.dismantle",id,payload,"","开始实际拆解劳动。普通已付材料按75%合法单位回收；动力总成按原计入件数保全。能源余额作废，未处理缓存、工具与在制不能销毁。回收进入随身背包且仍须容量与现场校验；不会立即拆除或发料。")
	if allowed.has("module.clear_ruin"):
		action(ui,parent,"清理残骸并回收…","module.clear_ruin",id,payload,"","开始实际残骸清理劳动，按本残骸已冻结账本一次回收；不会重算新品造价。需先清空现场缓存与工具，回收进入随身背包且需容量、工具与现场校验。确认不会立即发料或复原机器。")
