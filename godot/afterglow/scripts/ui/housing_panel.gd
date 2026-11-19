extends RefCounted
## On-demand public view only. Beds, permission, occupancy and routes belong to
## Runtime/B. Never derive a real bed count from architecture capacity.
const C=preload("res://scripts/ui/ui_composition.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
var projection:Dictionary={}
var dirty:=true
var projection_reads:=0
var serial:=0

func reset()->void:
	projection.clear();dirty=true;projection_reads=0;serial=0

func invalidate()->void:dirty=true;serial+=1

func read(ui)->void:
	if not dirty:return
	dirty=false;projection={"available":false,"homes":[]}
	if not is_instance_valid(ui.runtime) or not ui.runtime.has_method("housing_projection"):return
	var raw:Variant=ui.runtime.call("housing_projection","player")
	projection_reads+=1
	if raw is Dictionary and raw.get("available") is bool and raw.get("homes") is Array:projection=raw

func render(ui,parent:Node,module_id:String="")->void:
	var body=C.fold(ui,parent,"housing:"+module_id,"实际寝位与休息",not module_id.is_empty())
	if body==null:return
	read(ui)
	ui.add_button("刷新寝位情况",func():invalidate();ui.queue_refresh(),"housing:refresh:"+module_id,"",body)
	if not projection.get("available",false):
		C.caption(ui,"寝位资料当前不可用；设计人数不会替代实际睡位。",body);return
	var homes:=F.dictionaries(projection.homes)
	if not module_id.is_empty():homes=homes.filter(func(home:Dictionary):return home.get("id")==module_id)
	if homes.is_empty():
		C.caption(ui,"尚无已知且获准查看的住宅寝位。",body);return
	for home:Dictionary in homes:
		var card:=C.card(body)
		C.heading(ui,str(home.get("name","已知住宅")),card)
		var capacity:Variant=home.get("design_capacity",home.get("capacity"))
		if _count(capacity):C.caption(ui,"设计人数 "+str(int(capacity))+" · 不等于实际床位或入住人数",card)
		if not home.get("beds") is Array or not _count(home.get("bed_count")):
			C.caption(ui,"本住宅尚未发布实际床位资料；不按设计人数生成睡位。",card);continue
		var summary:="实际床位 "+str(int(home.bed_count))
		if _count(home.get("reachable_bed_count")):summary+=" · 当前可达 "+str(int(home.reachable_bed_count))
		if _count(home.get("available_bed_count")):summary+=" · 可用 "+str(int(home.available_bed_count))
		C.caption(ui,summary,card)
		if home.get("usable") is bool and not home.usable:C.reason(ui,card,"住宅服务当前不可用，请检查施工、损坏和地区状态。")
		var beds:=F.dictionaries(home.beds)
		if beds.is_empty():C.caption(ui,"此处当前没有已发布的实际床位。",card)
		for index in beds.size():
			var bed:Dictionary=beds[index];var id:=str(bed.get("bed_id",""))
			if id.is_empty() or bed.get("module_id")!=home.get("id"):continue
			var row:=C.card(card)
			row.set_meta("ui_bed_id",id)
			C.heading(ui,"寝位 "+str(index+1)+(" · 上铺" if bed.get("level")==1 else " · 下铺" if bed.get("level")==0 else ""),row)
			var states:Array=[]
			for field:Array in [["occupied","已有人占用／前往","未被占用"],["permitted","获准使用","当前无使用许可"],["reachable","有实际通路","当前不可达"]]:
				if bed.get(field[0]) is bool:states.append(field[1] if bed[field[0]] else field[2])
			C.caption(ui," · ".join(states) if not states.is_empty() else "使用条件未发布",row)
			if bed.get("prepared") is bool and not bed.prepared:C.caption(ui,"尚未实际铺好寝具",row)
			if not str(bed.get("reason","")).is_empty():C.reason(ui,row,P.reason_text(str(bed.reason)))
			var destination:=_approach(bed)
			var walk_reason:=""
			if bed.get("permitted")!=true:walk_reason="当前无此寝位的使用许可"
			elif bed.get("reachable")!=true or destination.is_empty():walk_reason="尚无已确认的真实通路"
			else:
				var walk_ready:Dictionary=ui.availability(ui.request("walk","",{},destination))
				if not walk_ready.get("ok",false):walk_reason=P.feedback_text(walk_ready)
			ui.add_button("前往此寝位",func():walk_to(ui,str(home.id),id,destination),"housing:walk:"+id,walk_reason,row)
			var reason:=""
			if bed.get("available")!=true:reason="此睡位当前不可用，请查看占用、通路和寝具准备状态"
			var ready:Dictionary=ui.availability(ui.request("rest",id))
			if not ready.get("ok",false):reason=P.action_feedback(ready,"rest")
			ui.add_button("在此寝位休息",func():ui.execute("rest",id,{},true),"housing:rest:"+id,reason,row)
	C.caption(ui,"寝具仍需实际接近并由原动作复检；不会隔空入睡或自动分配住户。",body)

func walk_to(ui,module_id:String,bed_id:String,expected:Dictionary)->Dictionary:
	# Re-read the same public proof at click time. Never infer a bed position
	# from its surface or silently switch to another place after rebuilding.
	invalidate();read(ui)
	var home:=F.find(F.dictionaries(projection.get("homes",[])),module_id)
	var bed:=F.find(F.dictionaries(home.get("beds",[])),bed_id,"bed_id")
	var destination:=_approach(bed)
	if projection.get("available")!=true or bed.get("module_id")!=module_id or bed.get("permitted")!=true or bed.get("reachable")!=true or destination.is_empty() or destination!=expected:
		var refusal:={"ok":false,"code":"HOUSING_ACCESS_CHANGED","reason":"寝位或通路已变化，请刷新后重新选择"}
		ui.notify(refusal.reason,true);ui.queue_refresh();return refusal
	return ui.execute("walk","",{},true,"",destination)

static func _approach(bed:Dictionary)->Dictionary:
	var at:Variant=bed.get("approach")
	if not at is Dictionary or not at.get("regionId") is String or str(at.regionId).is_empty():return {}
	for key:String in ["x","y","z"]:
		if not (at.get(key) is int or at.get(key) is float) or not is_finite(float(at[key])):return {}
	return at.duplicate(true)

static func _count(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and floorf(float(value))==float(value)
