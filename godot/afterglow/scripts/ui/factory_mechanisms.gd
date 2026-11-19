extends RefCounted
## UI drafts only; B owns thresholds, batch admission, paid delta and settlement.
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
const C=preload("res://scripts/ui/ui_composition.gd")
const Ops=preload("res://scripts/ui/factory_operations.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const BUFFER_NAMES={"input":"原料","output":"成品","fuel":"燃料","tools":"工具","supplies":"生活物资","storage":"仓储"}

static func stocks(ui)->Array:
	var rows:Array=[];var seen:Dictionary={}
	var pack:=P.player_stock(ui.snapshot)
	if not pack.is_empty():rows.append({"id":str(pack.id),"name":"随身背包"});seen[str(pack.id)]=true
	for module:Dictionary in F.rows(ui.factory,"modules","instances"):
		for ref:Dictionary in F.known_stocks(ui.factory,ui.snapshot,module):
			var id:=str(ref.stock_id)
			if seen.has(id) or ref.stock.is_empty() or not ref.stock.get("searched",false):continue
			seen[id]=true;rows.append({"id":id,"name":str(module.name)+" · "+str(BUFFER_NAMES.get(ref.buffer_id,"缓存"))})
	return rows

static func stock_policies(ui,parent:Node,module:Dictionary)->void:
	var policies:=F.dictionaries(module.get("stock_policies",[]))
	if policies.is_empty():return
	var body=C.fold(ui,parent,"stock-policy:"+str(module.id),"库存分类、保留量与目标")
	if body==null:return
	C.caption(ui,"保留量是可消耗下限；已预约是实际作业占用，二者分列。目标不会生成或自动搬运物资。",body)
	for buffer:Dictionary in policies:
		var buffer_id:=str(buffer.get("buffer_id",""));var key:="stock-draft:"+str(module.id)+":"+buffer_id
		var items:=F.dictionaries(buffer.get("items",[]))
		if items.is_empty():continue
		var card:=C.card(body)
		C.heading(ui,str(BUFFER_NAMES.get(buffer_id,"设施缓存")),card)
		if not ui.factory_view.has(key):ui.factory_view[key]=buffer.get("policy",{"filter":[],"reserve":{},"target":{}}).duplicate(true)
		var draft:Dictionary=ui.factory_view[key]
		var basis_key:=key+":basis"
		if not ui.factory_view.has(basis_key):ui.factory_view[basis_key]=buffer.get("policy",{}).duplicate(true)
		if ui.factory_view[basis_key]!=buffer.get("policy",{}):C.reason(ui,card,"现场策略已变化；本地编辑仍保留，应用时复检，或放弃编辑重新载入。")
		var all_goods:=CheckBox.new();all_goods.text="接收此缓存允许的全部物资";all_goods.button_pressed=draft.filter.is_empty();all_goods.set_meta("ui_focus_key",key+":all");card.add_child(all_goods)
		all_goods.toggled.connect(func(value:bool):
			draft.filter=[] if value else items.map(func(row:Dictionary):return str(row.item_id));ui.queue_refresh())
		var choices:Array=[]
		for item:Dictionary in items:choices.append({"id":str(item.item_id),"name":P.item_name(str(item.item_id))})
		var selected:=Ops._choice(ui,card,key+":item","查看并编辑物资",choices)
		for item:Dictionary in items:
			var id:=str(item.item_id)
			if id!=selected:continue
			var section:=C.card(card)
			C.caption(ui,P.item_name(id),section)
			C.caption(ui,"现场实有 "+P.number(item.get("onsite",0))+P.item_unit(id)+" / 容量 "+P.number(item.get("capacity",0))+P.item_unit(id),section)
			C.caption(ui,"作业预约 "+P.number(item.get("reserved",0))+" · 保留 "+P.number(item.get("reserve_floor",0))+" · 可作业 "+P.number(item.get("available_for_work",0)),section)
			if not all_goods.button_pressed:
				var accept:=CheckBox.new();accept.text="允许接收";accept.button_pressed=draft.filter.has(id);accept.set_meta("ui_focus_key",key+":filter:"+id);section.add_child(accept)
				accept.toggled.connect(func(value:bool):
					if value and not draft.filter.has(id):draft.filter.append(id)
					elif not value:draft.filter.erase(id)
					ui.queue_refresh())
			for field:String in ["reserve","target"]:
				C.caption(ui,"保留量" if field=="reserve" else "库存目标",section)
				var input:=SpinBox.new();input.min_value=0;input.max_value=float(item.get("capacity",0));input.step=Content.quantity_step(id,true);input.value=float(draft.get(field,{}).get(id,0));input.set_meta("ui_focus_key",key+":"+field+":"+id);section.add_child(input)
				input.get_line_edit().set_meta("ui_focus_key",key+":"+field+":"+id+":value")
				input.value_changed.connect(func(value:float):draft[field][id]=value;ui.queue_refresh())
		C.caption(ui,"切换物资会保留未应用编辑；仅在下方应用后写入本缓存。",card)
		var payload:Dictionary={"buffer_id":buffer_id,"policy":draft.duplicate(true)}
		var ready:Dictionary=ui.availability(ui.request("module.stock_policy",str(module.id),payload))
		ui.add_button("应用本缓存策略",func():
			# Capture current spin/check values, not an earlier render's copy.
			if not all_goods.button_pressed and draft.filter.is_empty():ui.notify("至少选择一种接收物资，或启用接收全部",true);return
			var receipt:Dictionary=ui.execute("module.stock_policy",str(module.id),{"buffer_id":buffer_id,"policy":draft.duplicate(true)})
			if receipt.get("ok",false):ui.factory_view.erase(key);ui.factory_view.erase(basis_key);ui.queue_refresh(),"mechanism:policy:"+str(module.id)+":"+buffer_id,"" if ready.get("ok",false) else P.feedback_text(ready),card)
		ui.add_button("放弃本地编辑",func():ui.factory_view.erase(key);ui.factory_view.erase(basis_key);ui.queue_refresh(),"mechanism:policy:discard:"+str(module.id)+":"+buffer_id,"",card)

static func recipes(ui,parent:Node,module:Dictionary,expanded:bool=false)->void:
	var management:Dictionary=module.get("recipe_management",{})
	var recipes:=F.dictionaries(management.get("recipes",[]))
	if recipes.is_empty():return
	var body=C.fold(ui,parent,"recipe-program:"+str(module.id),"配方订单与生产目标",expanded)
	if body==null:return
	C.caption(ui,"只登记需求；每批仍由人物到真实工位备料、劳动并结算。暂停面板中不会推进工时。",body)
	for order:Dictionary in F.dictionaries(management.get("orders",[])):
		var card:=C.card(body);var recipe:=F.find(recipes,str(order.recipe_id))
		C.heading(ui,str(recipe.get("name","既有配方订单")),card)
		var mode:=str(order.get("mode","quantity"))
		C.caption(ui,("已暂停" if order.get("paused",false) else "按需执行")+" · 已完成 "+P.number(order.get("completed",0))+" 批",card)
		C.caption(ui,"总需求 "+P.number(order.get("quantity",0))+" 批" if mode=="quantity" else "保持 "+P.item_text(str(order.get("target_item","")),order.get("target_quantity",0)) if mode=="target" else "持续生产",card)
		C.caption(ui,"原料 · "+Ops.endpoint_name(ui,str(order.get("source_id","")))+" → 成品 · "+Ops.endpoint_name(ui,str(order.get("output_id",""))),card)
		Ops.recipe_workers(ui,card,module,order)
		Ops.action(ui,card,"恢复订单" if order.get("paused",false) else "暂停订单","module.recipe.resume" if order.get("paused",false) else "module.recipe.pause",str(module.id),{"order_id":str(order.id)})
		Ops.action(ui,card,"停止此需求…","module.recipe.cancel",str(module.id),{"order_id":str(order.id)},"","停止此项配方需求并保留记录。已在制批次、投入和进度按真实生产回执保留，不复制退款或产物。")
	var choices:Array=[]
	for recipe:Dictionary in recipes:choices.append({"id":str(recipe.id),"name":str(recipe.get("name",recipe.id))})
	var prefix:="program:"+str(module.id)+":"
	var recipe_id:=Ops._choice(ui,body,prefix+"recipe","生产配方",choices)
	var selected:=F.find(recipes,recipe_id)
	if selected.is_empty():return
	ui.item_row(selected.get("inputs",{}),"每批投入",body);ui.item_row(selected.get("outputs",{}),"每批产出",body)
	if selected.has("seconds"):C.caption(ui,"每批有效劳动 "+P.number(selected.seconds)+" 秒",body)
	var modes:Array=[]
	for id:String in management.get("modes",[]):
		if id=="target" and selected.get("outputs",{}).is_empty():continue
		if id in ["quantity","target","continuous"]:modes.append({"id":id,"name":str({"quantity":"按批数","target":"保持库存","continuous":"持续生产"}[id])})
	var mode:=Ops._choice(ui,body,prefix+"mode","执行方式",modes)
	var quantity:=1
	if mode=="quantity":quantity=int(Ops._number(ui,body,prefix+"quantity","批数（不是物品件数）",1,100000,1,1))
	var stock_choices:=stocks(ui)
	if stock_choices.is_empty():C.reason(ui,body,"尚无可见可用的真实库存");return
	var refs:Dictionary=module.get("stock_refs",{})
	var source:=Ops._choice(ui,body,prefix+"source","原料来源",stock_choices,str(refs.get("input",refs.get("tools",refs.get("supplies","")))))
	var destination:=Ops._choice(ui,body,prefix+"output","成品存入",stock_choices,str(refs.get("output",refs.get("supplies",""))))
	var payload:Dictionary={"recipe_id":recipe_id,"mode":mode,"quantity":quantity,"source_id":source,"output_id":destination}
	if mode=="target":
		var outputs:Array=[]
		for item:String in selected.get("outputs",{}):outputs.append({"id":item,"name":P.item_name(item)})
		if outputs.is_empty():C.reason(ui,body,"本配方没有可设库存目标的物品产出");return
		var item:=Ops._choice(ui,body,prefix+"target_item","保持哪项产出",outputs)
		payload.target_item=item;payload.target_quantity=int(Ops._number(ui,body,prefix+"target:"+item,"库存目标（下一整批产出不得超过此数）",1,100000,1,maxf(1,float(selected.outputs[item]))))
	var repair_tools:Array=[{"id":"","name":"不指定维修对象"}]
	for entry:Dictionary in P.entries(P.player_stock(ui.snapshot),ui.snapshot):
		if entry.get("reference",{}).get("kind")=="tool":repair_tools.append({"id":str(entry.reference.tool_id),"name":str(entry.name)+" · 耐久 "+P.number(entry.get("durability",0))})
	if selected.get("repairTool") is Dictionary:
		repair_tools=repair_tools.filter(func(row:Dictionary):return not row.id.is_empty() and P.entry(P.player_stock(ui.snapshot),ui.snapshot,{"kind":"tool","tool_id":str(row.id)}).get("definition_id")==selected.repairTool.get("kind"))
		if repair_tools.is_empty():C.reason(ui,body,"随身没有此配方可维修的真实工具；先把工具带到现场");return
		var tool:=Ops._choice(ui,body,prefix+"repair","要维修的真实工具",repair_tools)
		if not tool.is_empty():payload.repair_tool_id=tool
	var existing:=F.dictionaries(management.get("orders",[])).filter(func(row:Dictionary):return row.get("recipe_id")==recipe_id)
	if not existing.is_empty():
		payload.order_id=existing[0].id
		C.caption(ui,"应用会重设此配方原需求的完成计数；在制批次未处理时由真实执行器拒绝。",body)
	Ops.action(ui,body,"更新此配方需求" if not existing.is_empty() else "登记配方需求","module.recipe.configure",str(module.id),payload)

static func upgrades(ui,parent:Node,module:Dictionary)->void:
	var proposals:=F.dictionaries(module.get("upgrade_proposals",[]))
	var current:=F.definition(ui.factory,str(module.get("definition_id","")))
	var level:=int(current.get("village_tier",0))
	if proposals.is_empty():
		if level>0:
			var terminal:bool=current.get("mechanism",{}).get("upgrade_to",[]).is_empty()
			C.caption(ui,("建筑等级 %s" % level)+(" · 当前为最高级" if terminal and level>1 else ""),parent)
		return
	var heading:="建筑升级 · %s 级" % level if level>0 else "升级 · 扩大能力"
	var body:=C.fold(ui,parent,"upgrade:"+str(module.id),heading,module.get("state_code") != "needs_restoration")
	if body==null:return
	for proposal:Dictionary in proposals:
		var target:=F.definition(ui.factory,str(proposal.definition_id))
		var card:=C.card(body)
		var target_level:=int(proposal.get("level",target.get("village_tier",0)))
		var staged:=target_level>0
		var title:=str(target.get("source_name",target.get("name","建筑升级"))) if staged else str(target.get("name","建筑升级"))
		C.heading(ui,"%s 级 · %s" % [target_level,title] if staged else title,card)
		var mechanism:Dictionary=target.get("mechanism",{})
		if not staged and mechanism.has("tier"):C.caption(ui,"目标功能等级 · "+str({1:"初级",2:"中级",3:"高级"}.get(int(mechanism.tier),str(mechanism.tier))),card)
		var benefit:=str(proposal.get("benefit",target.get("village_role",target.get("description",""))))
		if not benefit.is_empty():C.caption(ui,benefit,card)
		var cost:Dictionary=proposal.get("cost",{})
		var duration:=float(proposal.get("duration_seconds",0))
		if not cost.is_empty():ui.item_row(cost,"实际需补材料（已付抵扣后）",card)
		elif staged and duration>0:C.caption(ui,"实际需补材料：无",card)
		if duration>0 or not staged:
			C.caption(ui,"有效劳动 "+P.number(duration)+(" 秒" if staged else " 秒；仍需实际占地、清空缓存及工具权限复检"),card)
		var details:Node=card
		if staged:details=C.fold(ui,card,"upgrade-details:"+str(module.id)+":"+str(proposal.definition_id),"查看升级后的容量")
		if details!=null:
			if target.has("hp"):C.caption(ui,"目标结构耐久 · "+P.number(target.hp),details)
			for buffer:Dictionary in F.dictionaries(target.get("buffer_specs",[])):ui.item_row(buffer.get("limits",{}),"目标"+str(BUFFER_NAMES.get(buffer.get("id"),"缓存"))+"容量"+("" if staged else "（不是已有库存）"),details)
		if not proposal.get("available",false):C.reason(ui,card,P.feedback_text(proposal));continue
		var sources:=stocks(ui)
		var proposal_key:=str(module.id)+":"+str(proposal.definition_id)
		var source:=Ops._choice(ui,card,"upgrade-source:"+proposal_key,"补料库存",sources)
		C.materials(ui,card,cost,P.stock(ui.snapshot,source),"所选库存 · 升级准备")
		var tools:Array=[]
		for entry:Dictionary in P.entries(P.player_stock(ui.snapshot),ui.snapshot):
			if entry.get("reference",{}).get("kind")!="tool" or float(entry.get("available",0))<=0 or float(entry.get("durability",0))<=0:continue
			var definition:Dictionary=ui.snapshot.get("catalog",{}).get("tool_definitions",{}).get(str(entry.get("definition_id","")),{})
			if float(definition.get("qualities",{}).get("hammering",0))>=1:tools.append({"id":str(entry.reference.tool_id),"name":str(entry.name)})
		if tools.is_empty():C.reason(ui,card,"随身缺少可用手锤，先取得工具再开始升级");continue
		var tool:=Ops._choice(ui,card,"upgrade-tool:"+proposal_key,"升级工具",tools)
		var confirm:="开始升级为%s，施工完成后生效。将复检工地、施工工具和库存。" % title
		Ops.action(ui,card,"开始这项升级…","module.upgrade",str(module.id),{"definition_id":str(proposal.definition_id),"source_id":source,"tool_id":tool},"",confirm)
