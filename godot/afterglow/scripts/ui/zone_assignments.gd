extends RefCounted
## Plan policy drafts only. Existing owners recheck people and stocks at work.
const C=preload("res://scripts/ui/ui_composition.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
const Ops=preload("res://scripts/ui/factory_operations.gd")

static func render(ui,parent:Node,plan:RefCounted)->void:
	var body:=C.fold(ui,parent,"zone:assignments","人员与取送范围")
	if body==null:return
	var workers: Array=plan.policy.get("worker_ids",[])
	C.caption(ui,"不限人" if workers.is_empty() else "仅所选人员可接本区工作",body)
	ui.add_button("恢复不限人",func():plan.policy["worker_ids"]=[];plan._view_serial+=1;ui.queue_refresh(),"zone:workers:all","" if not workers.is_empty() else "当前已不限人",body)
	var known: Array=[]
	var members: Array=F.rows(ui.factory,"workforce","members").duplicate(true)
	if not members.any(func(member:Dictionary):return member.get("actor_id")=="player"):
		var actor:=P.player(ui.snapshot)
		if not actor.is_empty():members.push_front({"actor_id":"player","alive":float(actor.get("hp",0))>0,"consent":true})
	for member:Dictionary in members:
		var id:=str(member.get("actor_id",""))
		if id.is_empty():continue
		known.append(id)
		var actor:=P.find(ui.snapshot.get("actors",[]),id)
		var permitted: bool=member.get("alive",false) and (id=="player" or member.get("consent",false))
		var button:=CheckBox.new();button.text=("我" if id=="player" else str(actor.get("name","已知同行者")))+("" if permitted else " · 当前不能接新工作")
		button.button_pressed=workers.has(id);button.disabled=not permitted and not button.button_pressed
		button.set_meta("ui_focus_key","zone:worker:"+id);body.add_child(button)
		button.toggled.connect(func(value:bool):
			var next: Array=plan.policy.get("worker_ids",[]).duplicate()
			if value and not next.has(id):next.append(id)
			elif not value:next.erase(id)
			plan.policy["worker_ids"]=next;plan._view_serial+=1;ui.queue_refresh())
	if workers.any(func(id:Variant):return not known.has(str(id))):C.caption(ui,"保留原有未在当前同行名单中的人员标识；可恢复不限人后重选。",body)
	C.caption(ui,"人员筛选只限制接单范围，不会代替同意、生活需求、工具、通路和岗位仲裁；未选任何人代表不限人。",body)
	var stocks: Array=[{"id":"","name":"不限单一来源 · 仅从实际有权库存取缺口"}]
	var region:=str(plan.selected().get("region_id",P.player(ui.snapshot).get("regionId","")))
	for stock:Dictionary in P.records(ui.snapshot.get("stocks",[])):
		var id:=str(stock.get("id",""))
		if id.begins_with("pack:") or not F.stock_visible(ui.factory,ui.snapshot,id):continue
		if str(stock.get("location",{}).get("regionId",stock.get("regionId","")))!=region:continue
		stocks.append({"id":id,"name":Ops.endpoint_name(ui,id)})
	_stock_choice(ui,body,plan,"source_stock_id","物资来源",stocks)
	C.caption(ui,"来源筛选约束材料，不会把工具、远程汇总或被预留物资变成可用物。",body)
	if plan.kind=="stockpile":
		var targets: Array=[{"id":"","name":"未指定接收容器"}]+stocks.slice(1)
		_stock_choice(ui,body,plan,"target_stock_id","堆场接收库存",targets)
		C.caption(ui,"接收容器还须在本区有效格内；按其真实库存目标补货，不会自动生成散落堆或瞬移货物。",body)

static func _stock_choice(ui,parent:Node,plan:RefCounted,field:String,title:String,rows:Array)->void:
	var selected:=str(plan.policy.get(field,""))
	if not selected.is_empty() and not rows.any(func(row:Dictionary):return row.id==selected):
		rows=rows.duplicate(true);rows.append({"id":selected,"name":"原选择当前不可见 · 保留原标识"})
	C.caption(ui,title,parent)
	var control:=OptionButton.new();control.size_flags_horizontal=Control.SIZE_EXPAND_FILL;control.fit_to_longest_item=false;control.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	control.set_meta("ui_focus_key","zone:stock:"+field);parent.add_child(control)
	for row:Dictionary in rows:
		control.add_item(str(row.name));control.set_item_metadata(control.item_count-1,str(row.id))
		if row.id==selected:control.select(control.item_count-1)
	control.item_selected.connect(func(index:int):plan.policy[field]=str(control.get_item_metadata(index));plan._view_serial+=1;plan.queue_preview(ui);ui.queue_refresh())
