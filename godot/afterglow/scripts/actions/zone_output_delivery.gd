extends RefCounted
## C has already settled into the real pack. This records original logistics
## custody only; walking/deposit remain B actions, never remote output credit.
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
static func pending(host:RefCounted,tx:RefCounted,a:Dictionary)->bool:
	return Factory.state(host.domain("production"),Factory.LOGISTICS,tx).tasks.any(func(t:Dictionary)->bool:return t.actor_id==a.id and t.status not in ["completed","cancelled"])
static func queue(host:RefCounted,tx:RefCounted,a:Dictionary,zone:Dictionary,work:Dictionary,outputs:Dictionary)->void:
	var destination:String=str(zone.get("policy",{}).get("target_stock_id",""))
	if destination.is_empty() or outputs.is_empty():return
	var stock:Dictionary=tx.stock(destination)
	if destination.begins_with("pack:") or stock.is_empty() or not stock.get("searched",true) or not Factory.permitted(a,stock.get("owner")):
		tx.events.append({"kind":"zone-output-retained","actor_id":a.id,"zone_id":zone.id,"reason":"destination_unavailable"});return
	var production:RefCounted=host.domain("production");var l:=Factory.state(production,Factory.LOGISTICS,tx)
	if pending(host,tx,a):return
	var items:Dictionary={}
	for item:String in outputs:
		var amount:float=minf(float(outputs[item]),production.available_for("pack:"+str(a.id),item,"work","",tx))
		if amount>0:items[item]=amount
	if items.is_empty():return
	var cap:Dictionary=production.capacity_check(destination,items,"",tx)
	var id:String="logistics:"+str(l.next_id);l.next_id=int(l.next_id)+1
	l.tasks.append({"id":id,"source_id":"pack:"+str(a.id),"destination_id":destination,"items":items,"actor_id":a.id,"phase":"deliver","status":"delivering" if cap.ok else "cargo_held","repeat":false,"priority":float(zone.policy.get("priority",2)),"created_at":float(host.context.clock.call()),"trips":0,"reason":"" if cap.ok else str(cap.get("code","destination_full")),"zone_id":zone.id,"zone_revision":zone.revision,"zone_output_work_id":work.id})
	Factory.sync_logistics(l)
	tx.events.append({"kind":"zone-output-custody","actor_id":a.id,"work_id":work.id,"task_id":id,"destination_id":destination,"items":items.duplicate(true)})
static func candidates(host:RefCounted,tx:RefCounted,a:Dictionary)->Array:
	var rows:Array=[];var actions:Variant=host.domain("actions")
	var l:=Factory.state(host.domain("production"),Factory.LOGISTICS,tx)
	for task:Dictionary in l.tasks:
		if task.actor_id!=a.id or not task.has("zone_output_work_id") or task.status in ["completed","cancelled"]:continue
		var row:Dictionary=actions.Workforce.candidate(actions,tx,a,task)
		row.owner="actions";row.executor="actions"
		row.command={"kind":"zonework.deliver","target_id":task.zone_id,"payload":{"task_id":task.id}}
		rows.append(row)
	return rows
static func prepare(host:RefCounted,tx:RefCounted,a:Dictionary,request:Dictionary)->Dictionary:
	var l:=Factory.state(host.domain("production"),Factory.LOGISTICS,tx);var task:=Draft.find(l.tasks,str(request.get("payload",{}).get("task_id","")))
	if task.is_empty() or not task.has("zone_output_work_id") or task.actor_id!=a.id or task.get("zone_id")!=request.get("target_id"):return {"ok":false,"code":"CANDIDATE_UNAVAILABLE","reason":"真实区域携货任务已改变"}
	return host.domain("actions").prepare_workforce({"actor_id":a.id,"candidate_id":task.id,"command_id":request.get("command_id","")},tx.staged,tx.extensions)
