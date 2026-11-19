extends RefCounted
const C=preload("res://scripts/ui/ui_composition.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
const Icons=preload("res://scripts/ui/ui_icons.gd")

static func stock(ui,body:VBoxContainer,display:Dictionary)->void:
	if not display.get("available",false):
		C.caption(ui,"当前没有可读取的村庄库存",body)
		return
	var search:=LineEdit.new()
	search.placeholder_text="搜索物资"
	search.clear_button_enabled=true
	search.text=str(ui.factory_view.get("chapter_stock_query",""))
	search.set_meta("ui_focus_key","chapter:stock:search")
	search.text_changed.connect(func(value:String):
		ui.factory_view.chapter_stock_query=value;ui.factory_view.chapter_stock_page=0;ui.queue_refresh())
	body.add_child(search)
	var query:=search.text.strip_edges().to_lower()
	var rows:=P.records(display.get("rows",[])).filter(func(row:Dictionary)->bool:
		return query.is_empty() or str(row.get("name",P.item_name(str(row.get("item_id",""))))).to_lower().contains(query) or str(row.get("item_id","")).to_lower().contains(query))
	if rows.is_empty():C.caption(ui,"村庄库存为空" if query.is_empty() else "没有匹配的物资",body)
	const LIMIT:=10
	var last:=maxi(0,ceili(float(rows.size())/LIMIT)-1)
	var page:=clampi(int(ui.factory_view.get("chapter_stock_page",0)),0,last)
	for index:int in range(page*LIMIT,mini(rows.size(),(page+1)*LIMIT)):
		var row:Dictionary=rows[index]
		var id:String=str(row.get("item_id",""))
		var card:=C.card(body)
		card.set_meta("ui_chapter_stock_item",id)
		var facts:=C.image_row(ui,card,Icons.texture({"kind":"item","id":id}),str(row.get("name",P.item_name(id))),"可用 "+P.number(row.get("available"))+" / 总计 "+P.number(row.get("total")),32)
		C.caption(ui,"已预留 %s · 在途 %s" % [P.number(row.get("reserved")),P.number(row.get("in_transit"))]+(" · 保留 %s" % P.number(row.protected) if float(row.get("protected",0))>0 else ""),facts)
		var sources:=P.records(row.get("sources",[]))
		if sources.is_empty():continue
		var details:=C.fold(ui,card,"chapter:stock:"+id,"来源（%s）" % sources.size())
		if details==null:continue
		for source:Dictionary in sources:
			C.caption(ui,"%s · %s 可用 / %s" % [str(source.get("name","储物点")),P.number(source.get("available")),P.number(source.get("quantity"))],details)
	if last>0:
		var paging:=HFlowContainer.new();body.add_child(paging)
		ui.add_button("上一页",func():ui.factory_view.chapter_stock_page=page-1;ui.queue_refresh(),"chapter:stock:prev","已是第一页" if page==0 else "",paging)
		paging.add_child(ui.label("%s / %s" % [page+1,last+1]))
		ui.add_button("下一页",func():ui.factory_view.chapter_stock_page=page+1;ui.queue_refresh(),"chapter:stock:next","已是最后一页" if page==last else "",paging)

static func quests(ui,body:VBoxContainer,village:Dictionary)->void:
	var chapter:Dictionary=village.get("chapter_one",{})
	if not chapter.get("active",false) and not chapter.get("completed",false):return
	C.heading(ui,str(chapter.get("heading","第一章 · 旧村复兴")),body)
	var goals:=P.records(chapter.get("goals",village.get("objectives",[])))
	for goal:Dictionary in goals:
		C.caption(ui,str(goal.get("text",goal.get("label","")))+" · "+str(goal.get("status",goal.get("value",""))),body)
	if chapter.get("completed",false):
		C.primary(ui.add_button("查看第一章成果",func():ui.open_panel("chapter_complete"),"chapter:complete:open","",body))

static func ending(ui,body:VBoxContainer,chapter:Dictionary)->void:
	if not chapter.get("completed",false):
		C.caption(ui,"第一章尚未完成",body)
		return
	C.heading(ui,str(chapter.get("heading","第一章完成")),body,str(chapter.get("caption","")))
	for row:Dictionary in P.records(chapter.get("summary",[])):
		C.caption(ui,"%s · %s" % [str(row.get("label","")),str(row.get("value",""))],body)
	C.primary(ui.add_button("继续经营",ui.close_panels,"chapter:complete:continue","",body))
