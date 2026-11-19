extends RefCounted
## S01-A: historical material is separate from player-paid material.
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const POLICY="s01-frame-v1"
const KIND="woodshop-restoration-s01-v1"
const DEFINITION="r34.module.fuel_woodshop"
const HISTORY={"timber":12,"scrap":4}
const COST={"timber":8,"scrap":4,"r34:salvaged_drive_unit":1}
const TOTAL={"timber":20,"scrap":8,"r34:salvaged_drive_unit":1}
const VILLAGE_POLICY="village-heritage-v1"
static func village(v:Dictionary)->bool:return v.get("restoration",{}).get("policy")==VILLAGE_POLICY
static func cost(v:Dictionary)->Dictionary:return v.restoration.cost.duplicate(true) if village(v) else COST.duplicate(true)
static func duration(v:Dictionary)->float:return float(v.restoration.seconds) if village(v) else 40.0
static func village_initial(d:Dictionary)->Dictionary:
	return {"version":1,"policy":VILLAGE_POLICY,"definition_id":d.id,"geometry_version":d.geometry_version,"historical_cost":d.village_restoration.historical_cost.duplicate(true),"cost":d.village_restoration.cost.duplicate(true),"seconds":d.village_restoration.seconds,"completed":false,"project_id":""}
static func pending(v:Dictionary)->bool:return v.get("restoration") is Dictionary and not v.restoration.get("completed",false)
static func basis(v:Dictionary)->Dictionary:
	if not v.get("restoration") is Dictionary:return v.get("paid_cost",{})
	if village(v):
		var result:Dictionary=v.restoration.historical_cost.duplicate(true)
		for item:String in v.get("paid_cost",{}):result[item]=float(result.get(item,0))+float(v.paid_cost[item])
		return result
	return HISTORY if pending(v) else TOTAL
static func initial()->Dictionary:return {"version":1,"policy":POLICY,"historical_cost":HISTORY.duplicate(true),"completed":false,"project_id":""}
static func origin(host:RefCounted,v:Dictionary)->bool:
	# Re-read the current origin on every validation. The existing detached
	# projection avoids copying unrelated roads/plots/terrain for two fields;
	# legacy/custom views keep their full-extension compatibility path.
	var view:RefCounted=host.context.world
	var key:="generation:"+str(v.region)
	var fields:Array[String]=["generation_content_version","story_sites"]
	var plan:Variant=view.extension_fields(key,fields) if view.has_method("extension_fields") else view.extension(key)
	if not plan is Dictionary or int(plan.get("generation_content_version",0))<7:return false
	for s:Dictionary in plan.get("story_sites",[]):
		if s.get("id")==v.id:return s.get("kind")==KIND and s.get("restoration_policy")==POLICY and s.get("source_key")==v.source_key and s.get("position")==v.position and s.get("region")==v.region and s.get("quarter_turn")==v.quarter_turn and s.get("definition_id")==v.definition_id and s.get("geometry_version")==v.geometry_version
	return false
static func register(host:RefCounted,world:RefCounted,plan:Dictionary,state:Dictionary,changes:Array,stocks:Array,structures:Dictionary)->Dictionary:
	if int(plan.get("generation_content_version",0))<7:return {"ok":true}
	for s:Dictionary in plan.get("story_sites",[]):
		if s.get("kind")!=KIND:continue
		if s.get("version")!=1 or s.get("restoration_policy")!=POLICY or s.get("definition_id")!=DEFINITION or not Data.valid_id(s.get("id")) or not Data.valid_id(s.get("source_key")) or s.get("region")!=plan.get("region_id") or not Data.vec(s.get("position")) or not Data.integer(s.get("quarter_turn")) or int(s.quarter_turn) not in [0,1,2,3]:return Data.reject("INVALID_RESTORATION_SOURCE")
		var d:Dictionary=host.definition(DEFINITION)
		if s.get("definition_version")!=d.version or s.get("geometry_version")!=d.geometry_version:return Data.reject("INVALID_RESTORATION_GEOMETRY")
		if state.source_receipts.has(s.source_key):
			if state.source_receipts[s.source_key].get("module_id")!=s.id:return Data.reject("RESTORATION_SOURCE_CONFLICT")
			continue
		if not world.entity(s.id).is_empty() or world.retired_entity_ids().has(s.id) or not Draft.find(state.instances,s.id).is_empty():return Data.reject("RESTORATION_ID_OCCUPIED")
		var v:Dictionary=host.record_for(s,"home-residents");v.player_built=false;v.status="damaged";v.hp=120.0;v.discovered=false;v.restoration=initial()
		host.append_instance(world,host.building_adapter(world,{}),v,d,changes,structures)
		stocks.append_array(host.stock_rows(v,d));state.instances.append(v)
		state.source_receipts[s.source_key]={"module_id":v.id,"source_key":s.source_key,"content_seed":0,"stock_ids":v.stock_refs.values()}
	return {"ok":true}
static func validate(host:RefCounted,state:Dictionary)->Dictionary:
	for v:Dictionary in state.instances:
		if village(v):
			var valid:=validate_village(host,state,v)
			if not valid.ok:return valid
			continue
		if not v.has("restoration"):continue
		var r:Variant=v.restoration
		if not r is Dictionary or r.get("version")!=1 or r.get("policy")!=POLICY or not Data.json_equal(r.get("historical_cost"),HISTORY) or not r.get("completed") is bool or not r.get("project_id") is String or v.player_built or v.definition_id!=DEFINITION or not v.get("paid_cost",{}).is_empty() or not origin(host,v):return Data.reject("INVALID_RESTORATION_ORIGIN")
		var done:Array=state.projects.filter(func(p:Dictionary)->bool:return p.module_id==v.id and p.operation=="restore" and p.status=="completed")
		if (not r.completed and (not done.is_empty() or r.project_id!="" or v.status not in ["damaged","ruined","dismantled"] or float(v.hp)>120)) or (r.completed and (done.size()!=1 or r.project_id!=done[0].id or not Data.json_equal(done[0].cost,COST) or done[0].duration_seconds!=40 or not is_equal_approx(done[0].progress_seconds,40))):return Data.reject("INVALID_RESTORATION_LEDGER")
	return {"ok":true}
static func complete(host:RefCounted,tx:RefCounted,v:Dictionary,p:Dictionary)->void:
	if village(v):
		v.restoration.completed=true;v.restoration.project_id=p.id;v.hp=float(host.definition(v.definition_id).hp);v.status="operational";v.recovery_version="rc01-v1";v.paid_cost=p.cost.duplicate(true)
		# Replace every changed structural member in the SAME paid transaction.
		var entities:Array=Shape.entities(v,host.definition(v.definition_id));var next:Dictionary={}
		for entity:Dictionary in entities:
			next[entity.id]=true;var before:Dictionary=host.context.world.entity(str(entity.id))
			entity.revision=host.context.world.get_revision();tx.extra.append({"op":"entity.put","id":entity.id,"before_exists":not before.is_empty(),"before":null if before.is_empty() else before,"after":entity})
			if Draft.find(v.members,entity.id).is_empty():v.members.append({"id":entity.id,"kind":"entity"})
		return
	v.restoration.completed=true;v.restoration.project_id=p.id;v.hp=float(host.definition(v.definition_id).hp);v.status="operational";v.recovery_version="rc01-v1"
	for entity:Dictionary in Shape.entities(v,host.definition(v.definition_id)):
		if not host.context.world.entity(entity.id).is_empty():continue
		entity.revision=host.context.world.get_revision();tx.extra.append({"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity})
		if Draft.find(v.members,entity.id).is_empty():v.members.append({"id":entity.id,"kind":"entity"})

static func validate_village(host:RefCounted,state:Dictionary,v:Dictionary)->Dictionary:
	var r:Dictionary=v.restoration;var d:Dictionary=Catalog.definition_view(str(r.get("definition_id","")))
	if not d.has("village_restoration") or r.get("version")!=1 or r.get("geometry_version")!=d.geometry_version or r.get("cost")!=d.village_restoration.cost or r.get("seconds")!=d.village_restoration.seconds or r.get("historical_cost")!=d.village_restoration.historical_cost or not r.get("completed") is bool or v.player_built:return Data.reject("INVALID_VILLAGE_RESTORATION")
	var view:RefCounted=host.context.world;var key:="generation:"+str(v.region)
	var fields:Array[String]=["generation_content_version","module_seeds"]
	var plan:Variant=view.extension_fields(key,fields) if view.has_method("extension_fields") else view.extension(key);var found:bool=false
	for seed:Dictionary in plan.get("module_seeds",[]) if plan is Dictionary else []:
		if seed.id==v.id and seed.source_key==v.source_key and seed.definition_id==d.id and seed.position==v.position and seed.quarter_turn==v.quarter_turn:found=true
	if not found or not plan is Dictionary or int(plan.get("generation_content_version",0)) not in [13,14,15,16]:return Data.reject("INVALID_VILLAGE_ORIGIN")
	var done:Array=state.projects.filter(func(p:Dictionary)->bool:return p.module_id==v.id and p.operation=="restore" and p.status=="completed")
	if not r.completed:
		if not done.is_empty() or r.get("project_id")!="" or v.status not in ["damaged","ruined","dismantled"] or not v.get("paid_cost",{}).is_empty():return Data.reject("INVALID_VILLAGE_RESTORATION_LEDGER")
	elif done.size()!=1 or r.project_id!=done[0].id or done[0].cost!=cost(v) or not is_equal_approx(float(done[0].progress_seconds),duration(v)):return Data.reject("INVALID_VILLAGE_RESTORATION_LEDGER")
	return {"ok":true,"code":"OK"}
