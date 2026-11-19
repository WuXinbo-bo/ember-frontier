extends RefCounted
## Explicit paid replacement in the existing module project ledger. Old build
## definitions/costs remain immutable history; only reusable paid material is
## credited. No generated building or old ID is silently reinterpreted.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Stage=preload("res://scripts/modules/village_building_stage.gd")
const StockPolicy=preload("res://scripts/modules/module_stock_policy.gd")
static func delta(paid:Dictionary,target:Dictionary)->Dictionary:
	var result:Dictionary={}
	for item:String in target:
		var n:float=maxf(0,float(target[item])-float(paid.get(item,0)))
		if n>0:result[item]=n
	return result
static func options(d:Dictionary)->Array:
	return d.get("mechanism",{}).get("upgrade_to",[]).duplicate()
static func proposal(host:RefCounted,v:Dictionary,target_id:String,facts:Dictionary)->Dictionary:
	var old:=Catalog.definition_view(str(v.definition_id));var target:=Catalog.definition_view(target_id)
	if target.is_empty() or target.get("mechanism",{}).get("version")!=2:return Data.reject("INVALID_UPGRADE_TARGET")
	var allowed:Array=options(old)
	# A deliberate same-geometry adoption is allowed for player-paid v1 homes
	# and factories. It charges the positive delta, never rewrites the old ID.
	if not old.has("mechanism") and target.get("geometry_source_id")==old.id:allowed.append(target_id)
	var heritage:bool=v.get("restoration",{}).get("policy")=="village-heritage-v1" and v.restoration.get("completed",false)
	if not allowed.has(target_id) or (not v.get("player_built",false) and not heritage) or (v.has("restoration") and not heritage):return Data.reject("UPGRADE_NOT_AVAILABLE")
	var reason:=Stage.reason(host.context.world,target)
	if not reason.is_empty():return Data.reject("MODULE_VILLAGE_STAGE",reason)
	var candidate:Dictionary=v.duplicate(true);candidate.definition_id=target.id;candidate.definition_version=target.version;candidate.geometry_version=target.geometry_version
	var projects:Variant=load("res://scripts/modules/module_projects.gd")
	var safe:Dictionary=projects.footprint_check(host,candidate,facts,str(v.id))
	if not safe.ok:return safe
	return {"ok":true,"code":"OK","target":target.duplicate(true),"candidate":candidate,"cost":delta(v.get("paid_cost",{}),target.build_cost),"duration":ceilf(float(target.build_seconds)*.65)}
static func complete(host:RefCounted,tx:RefCounted,v:Dictionary,p:Dictionary)->Dictionary:
	var proposed:=proposal(host,v,str(p.target_definition_id),tx.staged)
	if not proposed.ok:return proposed
	if p.cost!=proposed.cost:return Data.reject("UPGRADE_MATERIAL_BASIS_CHANGED")
	var structures:Dictionary=tx.extension("r3:structures",{"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]})
	var old_members:Array=v.members.duplicate(true)
	var prior_stocks:Dictionary={};var prior_policies:Dictionary={}
	if proposed.target.has("village_family_art"):
		var ready:Dictionary=load("res://scripts/modules/module_projects.gd").upgrade_ready(host,tx,v,str(proposed.target.id))
		if not ready.ok:return ready
	if proposed.target.has("village_family_art") or int(v.get("rebuild_count",0))>0:
		for old_buffer:String in v.stock_refs:prior_stocks[old_buffer]=tx.stock(str(v.stock_refs[old_buffer])).duplicate(true)
		prior_policies=v.config.get("stock_policies",{}).duplicate(true)
	for member:Dictionary in old_members:
		if member.kind=="structure":structures.instances=structures.instances.filter(func(s:Dictionary)->bool:return s.id!=member.id)
	# Stamp the original project definitions before changing the current module.
	for project:Dictionary in tx.extension("r34:modules",host.initial()).projects:
		if project.module_id==v.id and not project.has("definition_id"):project.definition_id=v.definition_id
	v.definition_id=p.target_definition_id;v.definition_version=proposed.target.version;v.geometry_version=proposed.target.geometry_version
	var village_style:int=int(v.config.get("village_style_v1",0))
	v.members=[];v.config={};v.stock_refs={}
	if village_style==1 and preload("res://scripts/modules/village_style.gd").eligible(proposed.target):v.config.village_style_v1=1
	for b:Dictionary in proposed.target.buffer_specs:
		v.stock_refs[b.id]=prior_stocks.get(b.id,{}).get("id",str(v.id)+":stock:"+str(b.id))
	var new_stocks:Array=host.stock_rows(v,proposed.target)
	for stock:Dictionary in new_stocks:
		var buffer:String=stock.buffer_id
		if prior_stocks.has(buffer):
			stock.items=prior_stocks[buffer].get("items",{}).duplicate(true)
			stock.searched=prior_stocks[buffer].get("searched",true)
		var policy:Dictionary=prior_policies.get(buffer,{})
		if not policy.is_empty() and StockPolicy.validate_policy(policy,Draft.find(proposed.target.buffer_specs,buffer)).ok:
			if not v.config.has("stock_policies"):v.config.stock_policies={}
			v.config.stock_policies[buffer]=policy
	for stock:Dictionary in tx.staged.stocks.duplicate():
		if stock.get("module_id")==v.id:tx.staged.stocks.erase(stock)
	tx.staged.stocks.append_array(new_stocks)
	var generated:Array=[];host.append_instance(host.context.world,host.context.spatial,v,proposed.target,generated,structures)
	var new_ids:Dictionary={}
	for c:Dictionary in generated:
		new_ids[c.id]=true
		var before:Dictionary=host.context.world.entity(str(c.id))
		c.before_exists=not before.is_empty();c.before=null if before.is_empty() else before
		tx.extra.append(c)
	for member:Dictionary in old_members:
		if new_ids.has(member.id):continue
		var before:Dictionary=host.context.world.entity(str(member.id))
		if not before.is_empty():tx.extra.append({"op":"entity.remove","id":member.id,"before_exists":true,"before":before,"after":null})
	for item:String in p.cost:v.paid_cost[item]=float(v.paid_cost.get(item,0))+float(p.cost[item])
	if not v.has("upgrades"):v.upgrades=[]
	v.upgrades.append({"project_id":p.id,"from_definition_id":p.source_definition_id,"to_definition_id":p.target_definition_id,"cost":p.cost.duplicate(true)})
	v.hp=float(proposed.target.hp);v.status="operational"
	return {"ok":true,"code":"OK"}

static func paid_basis(state:Dictionary,v:Dictionary)->Dictionary:
	var builds:Array=state.projects.filter(func(p:Dictionary)->bool:return p.module_id==v.id and p.operation=="build" and p.status=="completed")
	var heritage:bool=v.get("restoration",{}).get("policy")=="village-heritage-v1" and v.restoration.get("completed",false)
	var origin:Dictionary={}
	if heritage:
		var restored:Array=state.projects.filter(func(p:Dictionary)->bool:return p.module_id==v.id and p.operation=="restore" and p.status=="completed")
		if restored.size()!=1:return Data.reject("INVALID_VILLAGE_UPGRADE_BASIS")
		origin=restored[0]
	elif builds.size()==1:origin=builds[0]
	else:return Data.reject("INVALID_MODULE_PAID_COST")
	var paid:Dictionary=origin.cost.duplicate(true)
	var definition_id:String=str(origin.get("definition_id",v.get("restoration",{}).get("definition_id",v.definition_id)));var seen:Dictionary={}
	for step:Variant in v.get("upgrades",[]):
		if not step is Dictionary or seen.has(step.get("project_id")) or step.get("from_definition_id")!=definition_id:return Data.reject("INVALID_UPGRADE_LEDGER")
		var project:=Draft.find(state.projects,str(step.get("project_id","")));var old:=Catalog.definition_view(definition_id);var target:=Catalog.definition_view(str(step.get("to_definition_id","")))
		if project.is_empty() or project.operation!="upgrade" or project.status!="completed" or project.source_definition_id!=definition_id or project.target_definition_id!=target.get("id") or target.is_empty():return Data.reject("INVALID_UPGRADE_LEDGER")
		if not options(old).has(target.id) and not (not old.has("mechanism") and target.get("geometry_source_id")==old.id):return Data.reject("INVALID_UPGRADE_LEDGER")
		if step.get("cost")!=delta(paid,target.build_cost) or project.cost!=step.cost:return Data.reject("INVALID_UPGRADE_PAID_COST")
		for item:String in step.cost:paid[item]=float(paid.get(item,0))+float(step.cost[item])
		seen[project.id]=true;definition_id=target.id
	if definition_id!=v.definition_id:return Data.reject("INVALID_UPGRADE_CURRENT_DEFINITION")
	for project:Dictionary in state.projects:
		if project.module_id==v.id and project.operation=="upgrade" and project.status=="completed" and not seen.has(project.id):return Data.reject("MISSING_UPGRADE_LEDGER")
	return {"ok":true,"code":"OK","paid":paid}
