extends RefCounted
## Dispatch keeps an intent until B can start or resume the single paid project.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Recovery=preload("res://scripts/modules/module_recovery.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const Supply=preload("res://scripts/modules/module_construction_supply.gd")
const Opening=preload("res://scripts/runtime/playtest_profile.gd")
const PREFIX:="building-order:"

static func target(id:String)->String:
	return id.trim_prefix(PREFIX)

static func queue_is_finished(modules:RefCounted,building:Dictionary,overrides:Dictionary)->bool:
	if building.is_empty() or building.status=="dismantled":return true
	var definition:Dictionary=modules.definition(str(building.definition_id))
	if building.status=="ruined":return not Recovery.rebuildable(building,definition)
	var project:=Draft.find(modules.state(overrides).projects,str(building.get("project_id","")))
	if Projects.active(project) or Projects.queued(project):return false
	if building.status in ["damaged","planned","constructing"]:return false
	return float(building.hp)>=float(definition.get("hp",0))

static func inspect(modules:RefCounted,actor:Dictionary,id:String,bound_id:String="",overrides:Dictionary={})->Dictionary:
	var v:Dictionary=modules.instance(target(id),overrides)
	if v.is_empty() or not v.get("discovered",false) or not modules.permitted(actor,v.owner):return {}
	var state:Dictionary=modules.state(overrides)
	var p:=Draft.find(state.projects,bound_id if not bound_id.is_empty() else str(v.project_id))
	var result:Dictionary={"id":id,"kind":"building_order","valid":true,"module_id":v.id,"region_id":v.region,"project_id":"","command":"","phase":"queued","reason":""}
	if not bound_id.is_empty() and p.is_empty():
		result.valid=false;result.phase="ended";result.reason="原工程已不存在";return result
	if v.status=="ruined" and Projects.active(p) and p.get("rebuild_ruin_id", "")!=v.get("ruin_id"):
		result.valid=false
		result.reason="残骸正在清理，等待清理结束或取消"
		return result
	if v.status=="planned" and p.get("operation")=="build" and p.id==v.project_id and (bound_id.is_empty() or Projects.queued(p)):
		result.project_id=p.id;result.command="module.work";return result
	if not p.is_empty() and (Projects.active(p) or not bound_id.is_empty()):
		result.project_id=p.id
		if not Projects.active(p):
			result.valid=false;result.phase="completed" if p.status=="completed" else "ended";return result
		result.command="module.work";result.phase=p.status;return result
	var definition:Dictionary=modules.definition(str(v.definition_id))
	if v.status=="ruined" and Recovery.rebuildable(v,definition):result.command="module.repair"
	elif v.status=="damaged" and Restoration.pending(v):result.command="module.restore"
	elif v.status not in ["planned","constructing","ruined","dismantled"] and float(v.hp)<float(definition.get("hp",0)):result.command="module.repair"
	else:return {}
	return result

static func prepare(modules:RefCounted,order:Dictionary,actor_id:String,command_id:String,facts:Dictionary,overrides:Dictionary)->Dictionary:
	if order.command=="module.work" and order.get("phase")!="queued":
		var actions:Variant=modules._actions.get_ref() if modules._actions!=null else null
		if actions!=null:
			return actions.prepare_workforce({"actor_id":actor_id,"candidate_id":"module-project:"+str(order.project_id),"command_id":command_id},facts,overrides)
	var module:Dictionary=modules.instance(str(order.module_id),overrides)
	var project:=Draft.find(modules.state(overrides).projects,str(order.project_id))
	var cost:Dictionary={}
	if order.command=="module.restore":cost=Restoration.cost(module)
	elif order.command=="module.repair":
		cost=Recovery.rebuild_cost(module,modules.definition(str(module.definition_id))) if module.status=="ruined" else Projects.REPAIR_COST
	elif order.command=="module.work" and Projects.queued(project):cost=project.cost
	if not cost.is_empty() or Projects.queued(project):
		var tx:=Draft.new(modules.context)
		if not facts.is_empty():tx.initial=facts.duplicate(true);tx.staged=facts.duplicate(true)
		tx.extensions=overrides.duplicate(true)
		var worker:Dictionary=tx.actor(actor_id)
		if not Projects.actor_ready(worker) or not modules.permitted(worker,module.get("owner")):return {"ok":false,"code":"MODULE_WORKER_PERMISSION","reason":"同伴目前不能接手这项工程"}
		var supply:=Supply.prepare(modules,tx,worker,module,cost,command_id,str(order.project_id))
		if not supply.get("ok",false):
			var initial_restoration:bool=order.command=="module.restore" or (order.command=="module.repair" and module.status=="ruined" and Restoration.pending(module))
			if initial_restoration and supply.get("code")=="MODULE_MATERIALS" and supply.get("tool",{}).get("available",false):
				var missing_boards:bool=supply.get("materials",[]).any(func(row:Dictionary)->bool:return row.item_id=="timber" and float(row.missing)>0)
				var workshop:Dictionary=modules.instance(Opening.WORKSHOP,overrides)
				if missing_boards and not workshop.is_empty() and workshop.status=="operational":
					var actions:Variant=modules._actions.get_ref() if modules._actions!=null else null
					if actions!=null:
						var craft:Dictionary=actions.prepare_workforce({"actor_id":actor_id,"candidate_id":"module-recipe:"+Opening.BOARD_PROGRAM,"command_id":command_id},facts,overrides)
						if craft.get("ok",false):craft.preparing=true;return craft
			return supply
		if supply.get("preparing",false):return supply
	return Projects.prepare(modules,{"kind":order.command,"actor_id":actor_id,"command_id":command_id,"target_id":order.module_id,"payload":{}},facts,overrides)

static func project_id(plan:Dictionary,module_id:String)->String:
	for change:Dictionary in plan.get("world_changes",[]):
		if change.get("id")==Projects.KEY:
			return str(Draft.find(change.get("after",{}).get("instances",[]),module_id).get("project_id",""))
	return ""
