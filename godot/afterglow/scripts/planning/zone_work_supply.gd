extends RefCounted
## Read-only prerequisites for B's original actions executor. These DTOs are
## offers, not reservations, completed paths, transfers or a second work clock.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")

static func candidates(host:RefCounted,tx:RefCounted,a:Dictionary,zone:Dictionary,job:Dictionary,requirements:Dictionary)->Array:
	if not _allowed(host,a,zone,job):return []
	if host.has_method("supply_candidates"):return host.supply_candidates(tx,a,zone,job,requirements)
	return compute_candidates(host,tx,a,zone,job,requirements)

static func compute_candidates(host:RefCounted,tx:RefCounted,a:Dictionary,zone:Dictionary,job:Dictionary,requirements:Dictionary)->Array:
	var rows:Array=[]
	if not _allowed(host,a,zone,job):return rows
	var production:Variant=host.domain("production")
	if production==null or host.domain("actions")==null:return rows
	var pack:String="pack:"+str(a.id)
	var excluding:String=str(job.get("work_id",""))
	var needed:Dictionary=_quantities(requirements)
	var qualities:Variant=requirements.get("tool_quality",{})
	if needed.has("!invalid") or not qualities is Dictionary:return rows
	for quality:Variant in qualities:
		if not quality is String or not _positive(qualities[quality]):return rows
	for item:String in needed.keys():
		needed[item]=maxf(0,float(needed[item])-production.available_for(pack,item,"work",excluding,tx))
		if float(needed[item])<=.000001:needed.erase(item)
	var p:Variant=tx.extensions["r3:production"] if tx.extensions.has("r3:production") else host.context.world.extension("r3:production")
	if not p is Dictionary or not p.get("tools") is Array:return rows
	var missing:Dictionary=qualities.duplicate(true)
	for tool:Dictionary in p.tools:
		if tool.get("holderId")==pack and _usable(production,tx,tool,excluding):_satisfy(production,missing,tool)
	if needed.is_empty() and missing.is_empty():return rows
	var modules:Variant=tx.extensions["r34:modules"] if tx.extensions.has("r34:modules") else host.context.world.extension("r34:modules")
	var module_stocks:Dictionary={}
	if modules is Dictionary:
		for module:Dictionary in modules.get("instances",[]):
			for stock_id:Variant in module.get("stock_refs",{}).values():module_stocks[str(stock_id)]=module
	var sources:Array=[]
	for stock:Dictionary in tx.staged.get("stocks",[]):
		var id:String=str(stock.get("id",""))
		if id.is_empty() or id.begins_with("pack:") or not stock.get("searched",true) or not Factory.permitted(a,stock.get("owner")):continue
		var at:Dictionary=G.location(stock)
		if not host.detailed(at) or (at.regionId!=zone.region_id and (not zone.has("region_ids") or at.regionId not in [G.location(a).regionId,G.location(job.location).regionId])):continue
		# Both explicit module IDs and the authoritative stock_refs are checked;
		# omitting module_id must not expose an undiscovered building's buffer.
		var module:Dictionary=module_stocks.get(id,{})
		if module.is_empty() and not str(stock.get("module_id","")).is_empty():continue
		if not module.is_empty() and (not module.get("discovered",false) or not Factory.permitted(a,module.get("owner")) or module.get("status") not in ["operational","damaged"]):continue
		var source_policy:String=str(zone.get("policy",{}).get("source_stock_id",""))
		var items:Dictionary={}
		if source_policy.is_empty() or source_policy==id:
			for item:String in needed:
				var amount:float=minf(float(needed[item]),production.available_for(id,item,"work",excluding,tx))
				var step:float=Content.quantity_step(item)
				if step<=0:continue
				amount=floorf((amount+.0000001)/step)*step
				if amount>0 and Content.quantity_valid(item,amount):items[item]=amount
		var selected:Array=[]
		var tool_summaries:Array=[]
		var source_missing:Dictionary=missing.duplicate(true)
		for tool:Dictionary in p.tools:
			if source_missing.is_empty():break
			if tool.get("holderId")!=id or not _usable(production,tx,tool,excluding):continue
			var count:int=source_missing.size()
			_satisfy(production,source_missing,tool)
			if source_missing.size()<count:
				selected.append(str(tool.id))
				var definition:Dictionary=production.tool_definition(tool)
				tool_summaries.append({"id":str(tool.id),"kind":str(tool.get("kind","")),"name":str(definition.get("name",tool.get("kind","作业工具"))),"durability":float(tool.durability),"max_durability":float(definition.get("maxDurability",tool.durability)),"qualities":production.tool_qualities(tool).duplicate(true)})
		if items.is_empty() and selected.is_empty():continue
		var capacity:Dictionary=production.capacity_check(pack,items,excluding,tx)
		var reason:String="" if capacity.get("ok",false) else str(capacity.get("reason",capacity.get("code","PACK_CAPACITY")))
		if a.get("intent")!=null:reason="角色已有行动，请先安全交接"
		var basis:Array=[str(a.id),str(zone.id),int(zone.revision),str(job.id),id]
		var candidate:String="zone-supply:"+JSON.stringify(basis).sha256_text().substr(0,32)
		var work_candidate:String="zonework:"+str(zone.id)+":"+str(job.id)
		# This source has already passed the exact searched/permission/residency
		# guards above. These detached labels do not authorize a remote transfer.
		var name:String=str(stock.get("name",stock.get("label",id)))
		if name.is_empty():name=id
		sources.append({"id":candidate,"actor_id":str(a.id),"owner":"actions","executor":"actions","kind":"supply","valid":reason.is_empty(),"reason":reason,"source_id":id,"destination_id":pack,"items":items,"tool_ids":selected,"zone_id":str(zone.id),"zone_revision":zone.revision,"work_candidate_id":work_candidate,"job_id":str(job.id),"player_priority":float(zone.get("policy",{}).get("priority",2)),"wait_seconds":0.0,"route_cost":G.point(G.location(a)).distance_to(G.point(at)),"critical_supply":true,"unblocks_output":false,"carrying":false})
		sources[-1].source_name=name
		sources[-1].source_location=at.duplicate(true)
		sources[-1].tools=tool_summaries
	sources.sort_custom(func(left:Dictionary,right:Dictionary)->bool:
		if left.route_cost==right.route_cost:return left.source_id<right.source_id
		return left.route_cost<right.route_cost)
	return sources

static func _positive(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>0

static func _quantities(requirements:Dictionary)->Dictionary:
	var result:Dictionary={}
	for kind:String in ["cost","reusable"]:
		var group:Variant=requirements.get(kind,{})
		if not group is Dictionary:return {"!invalid":true}
		for item:Variant in group:
			if not item is String or not _positive(group[item]) or not Content.quantity_valid(item,group[item]):return {"!invalid":true}
			# Reusable requirements describe possession, not an additional charge.
			result[item]=maxf(float(result.get(item,0)),float(group[item]))
	return result

static func _usable(production:RefCounted,tx:RefCounted,tool:Dictionary,excluding:String)->bool:
	return float(tool.get("durability",0))>0 and not production.tool_unavailable(str(tool.get("id","")),excluding,tx)

static func _satisfy(production:RefCounted,missing:Dictionary,tool:Dictionary)->void:
	var quality:Dictionary=production.tool_qualities(tool)
	for key:String in missing.keys():
		if float(quality.get(key,0))>=float(missing[key]):missing.erase(key)

static func _allowed(host:RefCounted,a:Dictionary,zone:Dictionary,job:Dictionary)->bool:
	if a.is_empty() or float(a.get("hp",0))<=0 or not zone.get("enabled",false) or not zone.has_all(["id","revision","region_id"]) or not job.has_all(["id","location"]):return false
	if a.id!="player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false)):return false
	var workers:Array=zone.get("policy",{}).get("worker_ids",[])
	if not workers.is_empty() and not workers.has(a.id):return false
	var at:Dictionary=G.location(a)
	if zone.has("region_ids") and zone.get("policy",{}).get("mode")=="harvest_only":
		var target:Dictionary=G.location(job.location)
		return zone.region_ids.has(target.regionId) and host.detailed(at) and host.detailed(target)
	return at.regionId==zone.region_id and G.location(job.location).regionId==zone.region_id and host.detailed(at)
