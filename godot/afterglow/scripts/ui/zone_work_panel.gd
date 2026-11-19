extends RefCounted
## Public Runtime projection only. No private provider read or local success.
const C=preload("res://scripts/ui/ui_composition.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
const Ops=preload("res://scripts/ui/factory_operations.gd")
const NAMES={"harvest_tree":"采伐成熟树","collect_seed":"采集树种","nursery":"育苗","plant_tree":"种植树苗","clear_stump":"清理树桩","till":"翻土","sow":"播种","water":"浇灌","compost":"施肥","harvest_crop":"收获","recover_seed":"收回种子","remove_crop":"清除作物","draw_raw_water":"取原水","terrain_dig":"逐格挖方","terrain_fill":"逐格填方"}
var work: Dictionary={}
var candidates: Array=[]
var chosen := ""
var _basis: Array=[]
var _candidate_basis: Array=[]
var _selection := ""
var _serial := 0
var projection_reads := 0
var candidate_reads := 0
var _shape: Dictionary={}
var _supply_view: Array=[]
var _live_rows: Dictionary={}

func reset() -> void:
	work.clear();candidates.clear();chosen="";_basis.clear();_candidate_basis.clear();_selection="";_shape.clear();_supply_view.clear();_live_rows.clear();_serial+=1

func sync(ui,selection: String,basis: Dictionary) -> void:
	var intent: Dictionary=P.player(ui.snapshot).get("intent",{}) if P.player(ui.snapshot).get("intent") is Dictionary else {}
	var supply: Dictionary=intent.get("supply",{}) if intent.get("kind")=="zone_supply" else {}
	var intent_view: Array=[intent.get("kind"),intent.get("held"),supply] if supply.get("zone_id")==selection else []
	if intent_view!=_supply_view:_supply_view=intent_view.duplicate(true);_serial+=1
	var key: Array=[selection,basis.get("runtime_generation"),basis.get("world_generation"),basis.get("zones_generation",{}),basis.get("work_revision"),basis.get("available")]
	if selection!=_selection:
		_selection=selection;candidates.clear();_candidate_basis.clear();chosen="";_serial+=1
	if selection.is_empty() or key==_basis:return
	_basis=key.duplicate(true)
	var raw: Variant=ui.runtime.call("zone_work_projection","player",false) if is_instance_valid(ui.runtime) and ui.runtime.has_method("zone_work_projection") else null
	projection_reads+=1
	work=raw if raw is Dictionary else {"available":false,"jobs":[]}
	var shape: Dictionary={"available":work.get("available"),"jobs":[]}
	for job: Dictionary in work.get("jobs",[]):
		if job.get("job",{}).get("zone_id")!=selection or job.get("status") in ["completed","cancelled"]:continue
		var row: Dictionary=job.duplicate(true)
		# These values update the native progress controls below. State, reason,
		# held/cancel actions and job membership still rebuild when they change.
		for field: String in ["progress_seconds","elapsed","effective_seconds"]:row.erase(field)
		shape.jobs.append(row)
	if shape!=_shape:_shape=shape;_serial+=1

func load_candidates(ui) -> void:
	var raw: Variant=ui.runtime.call("zone_work_projection","player",true) if is_instance_valid(ui.runtime) and ui.runtime.has_method("zone_work_projection") else null
	candidate_reads+=1
	if raw is Dictionary:
		work=raw
		candidates=F.dictionaries(raw.get("candidates",[])).filter(func(row:Dictionary):return row.get("zone_id")==_selection)
		_candidate_basis=_basis.duplicate(true)
	else:
		candidates.clear();_candidate_basis.clear()
	_serial+=1;ui.queue_refresh()

func signature() -> int:return [_serial,chosen,_basis!=_candidate_basis if not candidates.is_empty() else false].hash()

func update_live() -> void:
	for job: Dictionary in work.get("jobs",[]):
		var live: Dictionary=_live_rows.get(str(job.get("id","")),{})
		var progress: Variant=live.get("bar").get_ref() if live.get("bar") is WeakRef else null
		var label: Variant=live.get("label").get_ref() if live.get("label") is WeakRef else null
		if is_instance_valid(progress):progress.value=float(job.get("progress_seconds",0))
		if is_instance_valid(label):label.text=P.number(job.get("progress_seconds",0))+" / "+P.number(job.get("duration_seconds",0))+" 有效秒"

func render(ui,parent: Node,selection: String) -> void:
	_live_rows.clear()
	if selection.is_empty():return
	var card:=C.card(parent)
	C.heading(ui,"本人现场作业",card,"带上工具与物资，实际走到作业点")
	var intent: Variant=P.player(ui.snapshot).get("intent")
	if intent is Dictionary and intent.get("kind")=="zone_supply" and intent.get("supply",{}).get("zone_id")==selection:
		C.caption(ui,"前置取料 · "+("前往实际来源" if intent.get("held",true) else "已暂歇"),card)
		_supply_details(ui,card,intent.supply)
		C.caption(ui,"物资仍在实际来源，抵达并转移后才进入背包；当前显示不计为已取得。",card)
		Ops.action(ui,card,"暂歇取料" if intent.get("held",true) else "接续取料","held","",{"held":not intent.get("held",true)})
		Ops.action(ui,card,"取消本次取料…","cancel","",{},"","结束本次取料并释放未消费的预约；实际来源和已取得物资保持，不另发退款或材料。")
	for job: Dictionary in F.dictionaries(work.get("jobs",[])):
		if job.get("job",{}).get("zone_id")!=selection or job.get("status") in ["completed","cancelled"]:continue
		C.caption(ui,str(NAMES.get(job.get("operation"),"区域作业"))+" · "+str({"active":"执行中","paused":"手动暂停","blocked":"受阻","suspended":"已让出行动"}.get(job.get("status"),"等待实际状态")),card)
		if float(job.get("duration_seconds",0))>0:
			var progress:=ProgressBar.new();progress.max_value=float(job.duration_seconds);progress.value=float(job.get("progress_seconds",0));progress.show_percentage=false;card.add_child(progress)
			var label:=C.caption(ui,P.number(job.get("progress_seconds",0))+" / "+P.number(job.duration_seconds)+" 有效秒",card)
			_live_rows[str(job.id)]={"bar":weakref(progress),"label":weakref(label)}
		if not str(job.get("paused_reason","")).is_empty():C.reason(ui,card,P.reason_text(str(job.paused_reason)))
		var id:=str(job.id)
		if job.get("status")=="active":Ops.action(ui,card,"暂歇本次作业","zonework.pause",id,{"work_id":id})
		else:Ops.action(ui,card,"接续原作业","zonework.resume",id,{"work_id":id})
		Ops.action(ui,card,"取消本次作业…","zonework.cancel",id,{"work_id":id},"","只取消这一次人物作业；已完成的劳动、田间状态与真实物资保留，区域安排本身不删除。")
	ui.add_button("刷新可做的工作",func():load_candidates(ui),"zone:work:refresh","",card)
	if candidates.is_empty():
		C.caption(ui,"查看本区的真实作业与缺料原因；不自动派人，也不会生成材料",card);return
	var rows: Array=[]
	for candidate: Dictionary in candidates:
		var title: String="前置取料" if candidate.get("kind")=="supply" else str(NAMES.get(candidate.get("operation"),"现场劳动"))
		rows.append({"id":str(candidate.id),"name":title+" · "+("可安排" if candidate.get("valid",false) else "暂不可做"),"description":str(candidate.get("reason",""))})
	chosen=Ops._choice(ui,card,"zone_work_candidate:"+selection,"本区作业",rows,chosen)
	var candidate:=F.find(candidates,chosen)
	if candidate.is_empty():return
	var stale:=_basis!=_candidate_basis
	if stale:C.caption(ui,"现场条件已变化；开始时会复检，也可刷新作业",card)
	if not candidate.get("valid",false):C.reason(ui,card,P.reason_text(str(candidate.get("reason","当前条件不满足"))))
	var supply: bool=candidate.get("kind")=="supply"
	if supply:_supply_details(ui,card,candidate)
	var command: Dictionary=candidate.get("command",{})
	var reason: String=str(candidate.get("reason","当前条件不满足")) if not candidate.get("valid",false) else ""
	var expected: String="zonework.supply" if supply else "zonework.start"
	var payload: Variant=command.get("payload")
	var exact: bool=command.get("kind")==expected and command.get("target_id")==selection and candidate.get("zone_id")==selection and candidate.get("actor_id")=="player" and payload is Dictionary and payload=={"candidate_id":str(candidate.id)}
	var button: Button=ui.add_button("前往来源取料" if supply else "开始本人作业",func():ui.execute(expected,selection,{"candidate_id":str(candidate.id)});candidates.clear();_serial+=1;ui.queue_refresh(),"zone:work:start",reason,card)
	if not exact:
		button.disabled=true;button.tooltip_text="真实执行器未提供本区的准确取料命令" if supply else "真实执行器未提供本区开始命令"

func _supply_details(ui,parent:Node,candidate:Dictionary)->void:
	var source_id:=str(candidate.get("source_id",""))
	var name:=str(candidate.get("source_name",""))
	var endpoint:=Ops.endpoint_name(ui,source_id)
	if name.is_empty() or name==source_id:name="已搜索容器" if endpoint=="原任务库存暂不可见" else endpoint
	C.caption(ui,name+" → 随身背包",parent)
	if candidate.get("source_location") is Dictionary:C.caption(ui,F.location(candidate.source_location),parent)
	ui.item_row(candidate.get("items",{}),"本次实际缺口",parent)
	var source: Dictionary=F.visible_stock(ui.factory,ui.snapshot,source_id)
	for id:Variant in candidate.get("tool_ids",[]):
		var summary: Dictionary=F.find(F.dictionaries(candidate.get("tools",[])),str(id))
		var entry: Dictionary=P.entry(source,ui.snapshot,{"kind":"tool","tool_id":str(id)})
		if not summary.is_empty():C.caption(ui,"候选工具 · "+str(summary.get("name","作业工具"))+" · 耐久 "+P.number(summary.get("durability"))+(" / "+P.number(summary.max_durability) if summary.get("max_durability") is int or summary.get("max_durability") is float else ""),parent)
		elif entry.is_empty():C.caption(ui,"作业工具 · 1件 · 到实际来源查看身份与耐久",parent)
		else:C.caption(ui,"工具 · "+str(entry.get("name","作业工具"))+" · "+("可用" if float(entry.get("available",0))>0 and float(entry.get("durability",0))>0 else "当前不能确认可用"),parent)
	var known: bool=not source_id.is_empty() and F.stock_visible(ui.factory,ui.snapshot,source_id)
	ui.add_button("查看来源",func():ui.open_panel("factory_inventory",source_id),"zone:work:source","" if known else "来源当前不可见；请刷新或到现场重新确认",parent)
	C.caption(ui,"只前往这一处取实际缺少的物资；到达时复检数量、预留、权限与背包容量。取料后需再选择作业，可复用桶不会重复领取。",parent)
