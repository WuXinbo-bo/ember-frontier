extends RefCounted
## Complete modules are extensions of the ONE world, stocks and transaction.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Context=preload("res://scripts/actions/domain_context.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Recovery=preload("res://scripts/modules/module_recovery.gd")
const Hostile=preload("res://scripts/modules/module_hostile.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Workforce=preload("res://scripts/modules/module_workforce.gd")
const Alerts=preload("res://scripts/modules/module_alerts.gd")
const StockLayout=preload("res://scripts/modules/module_stock_layout.gd")
const ServiceAccess=preload("res://scripts/modules/module_service_access.gd")
const Identity=preload("res://scripts/modules/module_identity.gd")
const Water=preload("res://scripts/modules/module_water.gd")
const Restoration=preload("res://tests/gameplay/fixtures/performance17/module_restoration_before17.gd")
const WorkOrders=preload("res://scripts/production/module_work_orders.gd")
const StockPolicy=preload("res://scripts/modules/module_stock_policy.gd")
const Upgrade=preload("res://scripts/modules/module_upgrade.gd")
const OpeningBed=preload("res://scripts/modules/module_opening_bed.gd")
const RestoreAction=preload("res://scripts/modules/module_restoration_action.gd")
const KEY:="r34:modules"
var context:Dictionary={}
var _production:WeakRef
var _actions:WeakRef
var _stock_query:WeakRef
var _stock_visibility:Dictionary={}

static func initial()->Dictionary:
	return {"version":1,"instances":[],"projects":[],"source_receipts":{},"next_id":1}

static func module_definitions()->Array:return Catalog.definitions()
static func generation_profiles(include_quality:bool=false)->Array:return Catalog.profiles(include_quality)
static func generation_profiles_for_content(content_version:int)->Array:return Catalog.profiles_for_content(content_version)
static func region_profiles()->Array:return Building.generation_profiles()
static func definition(id:String)->Dictionary:return Catalog.definition(id)

func configure(value:Dictionary)->void:
	context=Context.isolate(value)
	_stock_query=null;_stock_visibility.clear()
	var service:Variant=value.get("services",{}).get("production")
	_production=weakref(service) if service is RefCounted else null
	var actions:Variant=value.get("services",{}).get("actions")
	_actions=weakref(actions) if actions is RefCounted else null

func state(overrides:Dictionary={})->Dictionary:
	var v:Variant=overrides[KEY] if overrides.has(KEY) else context.world.extension(KEY)
	return v if v is Dictionary else initial()

func instance(id:String,overrides:Dictionary={})->Dictionary:
	return Draft.find(state(overrides).instances,id).duplicate(true)

static func permitted(actor:Dictionary,owner:Variant)->bool:
	return not actor.is_empty() and (owner==null or owner in [actor.get("id"),actor.get("householdId")] or (owner=="home-residents" and (actor.get("id")=="player" or (actor.get("relationship",{}).get("member",false) and actor.get("relationship",{}).get("consent",false)))))

static func record_for(seed:Dictionary,owner:Variant="home-residents")->Dictionary:
	var d:=definition(str(seed.definition_id))
	var v:Dictionary={"id":seed.id,"definition_id":d.id,"definition_version":d.version,"geometry_version":d.geometry_version,"region":seed.region,"position":seed.position.duplicate(true),"quarter_turn":int(seed.quarter_turn),"owner":owner,"status":"operational","hp":float(d.hp),"stock_refs":{},"config":{},"project_id":"","members":[],"source_key":seed.get("source_key",""),"player_built":seed.get("player_built",true),"discovered":true}
	for buffer:Dictionary in d.buffer_specs:v.stock_refs[buffer.id]=str(v.id)+":stock:"+str(buffer.id)
	return v

static func stock_rows(v:Dictionary,d:Dictionary)->Array:
	var rows:Array=[];var ports:Array=Shape.ports(v,d)
	for buffer:Dictionary in d.buffer_specs:
		var p:Dictionary=Draft.find(ports,str(buffer.port_id));var location:Dictionary=p.location.duplicate(true)
		# Containers occupy the actual service surface, not the sealed interior.
		rows.append({"id":v.stock_refs[buffer.id],"module_id":v.id,"buffer_id":buffer.id,"location":location,"items":{},"owner":v.owner,"searched":true})
	return rows

static func building_adapter(view:RefCounted,facts:Dictionary)->RefCounted:
	var building:=Building.new()
	building.configure({"world":view,"facts":func()->Dictionary:return facts.duplicate(true),"actor":func(id:String)->Dictionary:return Draft.find(facts.get("actors",[]),id).duplicate(true),"stock":func(id:String)->Dictionary:return Draft.find(facts.get("stocks",[]),id).duplicate(true),"tool":func(_id:String)->Dictionary:return {},"clock":func()->float:return float(facts.get("time",0))})
	return building

static func append_instance(view:RefCounted,building:RefCounted,v:Dictionary,d:Dictionary,changes:Array,structures:Dictionary)->void:
	if d.shape=="manual":
		var bench:Dictionary=building.make_instance("workbench",str(v.id)+":workbench",Shape.at(v,Shape.Families.bench_offset(d)),int(v.quarter_turn),v.owner)
		structures.instances.append(bench);v.members.append({"id":bench.id,"kind":"structure"})
		changes.append({"op":"entity.put","id":bench.id,"before_exists":false,"before":null,"after":building.geometry.entity(bench)})
		v.config.workbench_id=bench.id
	if d.shape!="manual" or d.has("design_id"):
		for entity:Dictionary in Shape.entities(v,d):
			entity.revision=view.get_revision()
			v.members.append({"id":entity.id,"kind":"entity"})
			changes.append({"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity})
	# Aggregate target is selectable but NEVER used as a single coarse collider.
	var bounds:=Shape.transform_box(v,G.aabb(d.footprint))
	var root:Dictionary={"id":v.id,"kind":"prop","regionId":v.region,"position":v.position.duplicate(true),"bounds":G.json_box(bounds),"revision":view.get_revision(),"blocksTerrain":true,"supportBounds":[G.json_box(AABB(bounds.position,Vector3(bounds.size.x,0.05,bounds.size.z)))],"data":{"module_id":v.id,"solid":false,"opaque":false,"owner":v.owner,"module_target":true}}
	var housing:Variant=preload("res://scripts/modules/module_housing.gd")
	if housing.applies(d):root.data.module_navigation=housing.navigation(v,d,Shape.parts(Catalog.definition_view(str(d.geometry_source_id))))
	if d.has("village_geometry") and d.shape=="home":
		root.data.module_navigation=[]
		for local:Vector3 in [Vector3(0,0,-1.2),Vector3(0,0,.05),Vector3(-1.7,0,.05),Vector3(1.7,0,.05)]:root.data.module_navigation.append(Shape.at(v,local))
	if d.get("story_front_point") is Array:
		var p:Array=d.story_front_point;root.data.story_front_point=Shape.at(v,Vector3(p[0],p[1],p[2]));root.data.story_front_hint="前场货架已空。侧边通向后侧收货处，那里保留原有物资和路线记录。"
	var previous:Dictionary=view.entity(str(v.id))
	changes.append({"op":"entity.put","id":v.id,"before_exists":not previous.is_empty(),"before":null if previous.is_empty() else previous,"after":root})
	if Draft.find(v.members,str(v.id)).is_empty():v.members.append({"id":v.id,"kind":"entity"})

func prepare_generation(view:RefCounted,region_ids:Array=[],staged_facts:Dictionary={})->Dictionary:
	# Pure view adapter: new().prepare_generation works before any Runtime/facts.
	var catalog_check:=Catalog.validate()
	if not catalog_check.ok:return catalog_check
	var old:Variant=view.extension(KEY);var after:Dictionary=old.duplicate(true) if old is Dictionary else initial()
	var building:=building_adapter(view,staged_facts)
	var original:Variant=view.extension(Building.EXTENSION)
	var structures:Dictionary=original.duplicate(true) if original is Dictionary else {"schemaVersion":1,"catalogVersion":1,"storeys":[],"instances":[]}
	var changes:Array=[];var stocks:Array=[];var tools:Array=[];var records:Array=[];var anchors:Dictionary={};var spawns:Dictionary={}
	for region:Dictionary in view.regions():
		if not region_ids.is_empty() and not region_ids.has(region.id):continue
		var plan:Variant=view.extension("generation:"+str(region.id))
		if not plan is Dictionary:continue
		for seed:Dictionary in plan.get("module_seeds",[]):
			if not Data.valid_id(seed.get("source_key")) or seed.get("initialization")!="generated-place-once" or seed.get("player_built")!=false:return Data.reject("INVALID_MODULE_SEED")
			if after.source_receipts.has(seed.source_key):
				if after.source_receipts[seed.source_key].module_id!=seed.id:return Data.reject("MODULE_SOURCE_CONFLICT")
				continue
			var d:=definition(str(seed.get("definition_id","")))
			if d.is_empty() or seed.get("definition_version")!=d.version or seed.get("geometry_version")!=d.geometry_version or not Data.vec(seed.get("position")) or seed.get("region")!=region.id or not Data.integer(seed.get("quarter_turn")) or int(seed.quarter_turn) not in [0,1,2,3]:return Data.reject("INVALID_MODULE_SEED")
			if not Draft.find(after.instances,str(seed.id)).is_empty() or not view.entity(str(seed.id)).is_empty() or view.retired_entity_ids().has(seed.id):return Data.reject("MODULE_ID_OCCUPIED")
			var owner:Variant=null if seed.get("purpose")=="store" else "home-residents"
			var v:=record_for(seed,owner);v.discovered=region.id=="RH-HOME";var rows:=stock_rows(v,d)
			if int(plan.get("generation_content_version",0)) in [13,14,15,16] and d.has("village_restoration"):
				v.restoration=Restoration.village_initial(d);v.status="damaged";v.hp=float(d.village_restoration.initial_hp)
			for row:Dictionary in rows:row.searched=false
			var supply:Dictionary=rows[0]
			if seed.get("purpose")=="home":
				var generation:Variant=view.extension("generation:factory-r34")
				if generation is Dictionary and generation.get("content_version")==12 and d.id in ["r34.module.home_roadside_v3","r34.module.home_court_v3"]:v.config.opening_bed_v1=1;after.source_receipts[OpeningBed.key(v)]=OpeningBed.receipt(v)
				supply.searched=true
				supply.items={"food":2,"water":3,"cloth":2,"timber":2,"scrap":1}
				if d.has("village_geometry"):supply.items={"food":8,"water":12,"cloth":4,"scrap":4}
				anchors.home=supply.location.duplicate(true);spawns.player=offset(supply.location,Vector3(0,0,-0.7))
			elif seed.get("purpose")=="woodwork":
				supply=Draft.find(rows,str(v.stock_refs.get("tools","")))
				if int(plan.get("generation_content_version",0)) in [15,16]:supply.searched=true
				supply.items={"timber":8,"scrap":6,"book_woodwork":1,"book_tool_repair":1}
				if d.has("village_geometry"):supply.items.erase("timber")
				for kind:String in ["salvaged_axe","hand_saw","hammer"]:tools.append({"id":str(v.id)+":tool:"+kind,"kind":kind,"holderId":supply.id,"durability":85.0 if kind=="salvaged_axe" else 100.0})
				for spec:Array in [["book_woodwork","basic_woodwork"],["book_tool_repair","basic_tool_repair"]]:records.append({"id":str(v.id)+":record:"+spec[0],"itemId":spec[0],"holderId":supply.id,"grants":[spec[1]],"seconds":12.0})
			elif seed.get("purpose")=="store":supply.items={"food":6,"water":6,"scrap":3}
			elif seed.get("purpose")=="neighbor":
				spawns["village-resident"]=offset(supply.location,Vector3(-0.8,0,-0.6));spawns["repair-resident"]=offset(supply.location,Vector3(0.8,0,-0.6))
			var addition:Variant=seed.get("zone_production_additions")
			if addition!=null:
				var config:Variant=view.extension("generation:factory-r34")
				var expected:Dictionary={"r34:potato_seed":4,"r34:bean_seed":4,"r34:rice_seed":4,"r34:water_bucket":1}
				var bag_id:String=str(seed.id)+":regional-seed-bag:v1";var receipt:String=str(seed.source_key)+":regional-production-v1"
				if not config is Dictionary or int(config.get("content_version",0)) not in [12,13,14,15,16] or seed.get("purpose")!="store" or region.id!="RH-VILLAGE" or not addition is Dictionary or addition.get("policy")!="regional-production-v1" or addition.get("version")!=1 or addition.get("source_key")!=seed.source_key or addition.get("module_id")!=seed.id or not Data.json_equal(addition.get("items"),expected) or addition.get("source_id")!=bag_id or addition.get("entity_id")!=bag_id or addition.get("region_id")!=region.id or not Data.vec(addition.get("position")):return Data.reject("INVALID_INITIAL_SEED_BAG")
				var entity:Dictionary=view.entity(bag_id)
				if entity.get("kind")!="container" or entity.get("regionId")!=region.id or not Data.json_equal(entity.get("position"),addition.position) or entity.get("data",{}).get("owner")!=null or after.source_receipts.has(receipt):return Data.reject("INITIAL_SEED_BAG_ENTITY_MISMATCH")
				var at:Dictionary=addition.position.duplicate(true);at.regionId=region.id;at.buildingId=null;at.storeyId=null
				stocks.append({"id":bag_id,"location":at,"owner":null,"searched":false,"items":expected.duplicate(true)})
				after.source_receipts[receipt]={"module_id":"","source_key":receipt,"content_seed":seed.get("content_seed",0),"stock_ids":[bag_id]}
			append_instance(view,building,v,d,changes,structures)
			stocks.append_array(rows);after.instances.append(v)
			after.source_receipts[seed.source_key]={"module_id":v.id,"source_key":seed.source_key,"content_seed":seed.get("content_seed",0),"stock_ids":v.stock_refs.values()}
			anchors[v.id]={"ports":Shape.ports(v,d),"stock_refs":v.stock_refs.duplicate(true)}
		for source:Dictionary in plan.get("content_anchors",[]):
			if region.id!="RH-HOME" or source.get("purpose")!="stockyard-and-recovery" or after.source_receipts.has(source.get("source_key")):continue
			var id:String=str(source.id)+":container";var p:Dictionary=source.position.duplicate(true);p.regionId=region.id;p.buildingId=null;p.storeyId=null
			var row:Dictionary={"id":id,"items":{"axe_head":1,"tool_handle":1,"scrap":4,"r34:salvaged_drive_unit":1},"owner":null,"searched":false,"location":p}
			stocks.append(row)
			for kind:String in ["shovel","pickaxe"]:tools.append({"id":id+":tool:"+kind,"kind":kind,"holderId":id,"durability":100.0})
			# MT01 only belongs to a freshly registered content5 source. The
			# source_receipts guard above also covers consumed/searched/removed
			# stock: revisiting or cold mounting can never refill it. Old plans,
			# even unexplored ones, retain their exact former finite supplies.
			if int(plan.get("generation_content_version",0))>=5:
				row.items["cloth"]=2;row.items["book_tool_repair"]=1
				for kind:String in ["salvaged_axe","hand_saw","hammer","shovel","pickaxe"]:
					tools.append({"id":id+":reserve-tool:"+kind,"kind":kind,"holderId":id,"durability":40.0})
				records.append({"id":id+":reserve-record:book_tool_repair","itemId":"book_tool_repair","holderId":id,"grants":["basic_tool_repair"],"seconds":12.0})
			var box:=AABB(G.point(p)-Vector3(0.35,0,0.3),Vector3(0.7,0.7,0.6))
			changes.append({"op":"entity.put","id":id,"before_exists":false,"before":null,"after":{"id":id,"kind":"container","regionId":region.id,"position":source.position.duplicate(true),"bounds":G.json_box(box),"revision":view.get_revision(),"blocksTerrain":true,"supportBounds":[G.json_box(box)],"data":{"assetId":"r1_storage_container","solid":true,"opaque":false,"dropped":false,"owner":null}}})
			after.source_receipts[source.source_key]={"module_id":"","source_key":source.source_key,"content_seed":source.get("content_seed",0),"stock_ids":[id]}
		var water_registration:=Water.register(view,plan,after,changes)
		if not water_registration.ok:return water_registration
		var restore_registration:=Restoration.register(self,view,plan,after,changes,stocks,structures)
		if not restore_registration.ok:return restore_registration
	if structures!=original and not structures.instances.is_empty():changes.append({"op":"extension.set","id":Building.EXTENSION,"before_exists":view.has_extension(Building.EXTENSION),"before":original,"after":structures})
	if after!=old:changes.append({"op":"extension.set","id":KEY,"before_exists":view.has_extension(KEY),"before":old,"after":after})
	var seed_result:Dictionary={"spawn_points":spawns,"initial_stocks":stocks,"initial_tools":tools,"initial_records":records,"home":anchors.get("home",{})}
	return {"ok":true,"code":"OK","world_changes":changes,"fact_changes":[],"initial_stocks":stocks,"initial_tools":tools,"initial_records":records,"spawn_points":spawns,"anchors":anchors,"seed_result":seed_result,"expected_world_revision":view.get_revision()}

static func offset(location:Dictionary,delta:Vector3)->Dictionary:
	var r:=location.duplicate(true);r.x+=delta.x;r.y+=delta.y;r.z+=delta.z;return r

func buffer_spec(stock_id:String,overrides:Dictionary={})->Dictionary:
	for v:Dictionary in state(overrides).instances:
		for b:Dictionary in definition(str(v.definition_id)).buffer_specs:
			if v.stock_refs.get(b.id)==stock_id:return b.duplicate(true)
	return {}

func validate_extensions(facts_state:Dictionary,extension_overrides:Dictionary={})->Dictionary:
	var source:Variant=extension_overrides[KEY] if extension_overrides.has(KEY) else context.world.extension(KEY)
	if source==null:return {"ok":true,"code":"OK"}
	if not source is Dictionary or source.get("version")!=1 or not source.get("instances") is Array or not source.get("projects") is Array or not source.get("source_receipts") is Dictionary or not Data.integer(source.get("next_id")) or source.next_id<1:return Data.reject("INVALID_MODULE_STATE")
	var ids:Dictionary={};var stock_ids:Dictionary={};var member_ids:Dictionary={}
	for v:Variant in source.instances:
		if not v is Dictionary or not Identity.valid_id(v.get("id")) or ids.has(v.id):return Data.reject("INVALID_MODULE_ID")
		ids[v.id]=true
		var d:=Catalog.definition_view(str(v.get("definition_id","")))
		if d.is_empty() or v.get("definition_version")!=d.version or v.get("geometry_version")!=d.geometry_version:return Data.reject("MODULE_GEOMETRY_VERSION_MISMATCH")
		if not Identity.valid_id(v.get("region")) or not Data.vec(v.get("position")) or not Data.integer(v.get("quarter_turn")) or not d.allowed_quarter_turns.any(func(turn:Variant)->bool:return float(turn)==float(v.quarter_turn)) or not number(v.get("hp")) or float(v.hp)<0 or float(v.hp)>float(d.hp) or v.get("status") not in ["planned","constructing","operational","damaged","ruined","dismantled"]:return Data.reject("INVALID_MODULE_INSTANCE")
		if not v.get("stock_refs") is Dictionary or v.stock_refs.size()!=d.buffer_specs.size() or not v.get("members") is Array:return Data.reject("INVALID_MODULE_REFERENCE")
		for b:Dictionary in d.buffer_specs:
			var id:Variant=v.stock_refs.get(b.id)
			if not Identity.valid_id(id) or stock_ids.has(id):return Data.reject("INVALID_MODULE_STOCK_REFERENCE")
			stock_ids[id]=true
			var stock:=Draft.find(facts_state.get("stocks",[]),str(id))
			if stock.is_empty() or stock.get("owner")!=v.owner or (v.status!="ruined" and v.status!="dismantled" and (stock.get("module_id")!=v.id or stock.get("buffer_id")!=b.id)):return Data.reject("MISSING_MODULE_STOCK")
			for item:String in stock.items:
				if not Content.quantity_valid(item,stock.items[item]) or (v.status not in ["ruined","dismantled"] and (not b.limits.has(item) or float(stock.items[item])>float(b.limits[item])+0.000001)):return Data.reject("MODULE_BUFFER_CAPACITY",str(id)+"/"+item)
		var attachment_check:=OpeningBed.validate(context.world,source,v,d)
		if not attachment_check.ok:return attachment_check
		var order_check:=WorkOrders.validate(v,d)
		if not order_check.ok:return order_check
		var policy_check:=StockPolicy.validate(v,d)
		if not policy_check.ok:return policy_check
		for member:Variant in v.members:
			if not member is Dictionary or not Identity.valid_id(member.get("id")) or member_ids.has(member.id) or member.get("kind") not in ["entity","structure"]:return Data.reject("INVALID_MODULE_MEMBERS")
			member_ids[member.id]=true
	var project_ids:Dictionary={};var workers:Dictionary={}
	for p:Variant in source.projects:
		if not p is Dictionary or not Identity.valid_id(p.get("id")) or project_ids.has(p.id) or not ids.has(p.get("module_id")) or not Identity.valid_id(p.get("actor_id")) or p.get("operation") not in ["build","repair","restore","dismantle","clear_ruin","upgrade"] or p.get("status") not in ["active","blocked","paused","completed","cancelled"] or not Identity.valid_id(p.get("source_id")) or not Identity.valid_id(p.get("tool_id")) or not p.get("cost") is Dictionary or not number(p.get("progress_seconds")) or not number(p.get("duration_seconds")) or float(p.duration_seconds)<=0 or float(p.progress_seconds)<0 or float(p.progress_seconds)>float(p.duration_seconds)+0.000001:return Data.reject("INVALID_MODULE_PROJECT")
		project_ids[p.id]=true
		var v:=Draft.find(source.instances,str(p.module_id));var d:=Catalog.definition_view(str(p.get("definition_id",v.definition_id)))
		if p.operation=="restore" and (not v.has("restoration") or not Data.json_equal(p.cost,Restoration.cost(v)) or p.duration_seconds!=Restoration.duration(v)):return Data.reject("INVALID_RESTORATION_PROJECT")
		if d.is_empty() or p.get("geometry_version")!=d.geometry_version or (p.operation=="build" and not Data.json_equal(p.cost,d.build_cost)) or (p.operation=="repair" and not Data.json_equal(p.cost,{"timber":2,"scrap":1})) or (p.operation in ["dismantle","clear_ruin"] and not p.cost.is_empty()):return Data.reject("INVALID_MODULE_PROJECT_COST")
		if p.operation=="upgrade":
			var target:=Catalog.definition_view(str(p.get("target_definition_id","")))
			if p.get("source_definition_id")!=d.id or target.is_empty() or p.duration_seconds!=ceilf(float(target.build_seconds)*.65):return Data.reject("INVALID_UPGRADE_PROJECT")
			if not p.get("paid_basis") is Dictionary or p.cost!=Upgrade.delta(p.paid_basis,target.build_cost):return Data.reject("INVALID_UPGRADE_PROJECT_COST")
			if Projects.active(p) and not Data.json_equal(p.paid_basis,v.get("paid_cost",{})):return Data.reject("INVALID_UPGRADE_CURRENT_BASIS")
		if Projects.active(p):
			var a:=Draft.find(facts_state.get("actors",[]),str(p.actor_id))
			if a.is_empty() or workers.has(a.id):return Data.reject("INVALID_MODULE_WORKER")
			workers[a.id]=true
	for v:Dictionary in source.instances:
		if not v.get("player_built") is bool or not v.get("discovered") is bool:return Data.reject("INVALID_MODULE_ORIGIN")
		var paid:Variant=v.get("paid_cost",{})
		if not paid is Dictionary:return Data.reject("INVALID_MODULE_PAID_COST")
		if v.player_built and v.status in ["operational","damaged","ruined","dismantled"]:
			var matching:Array=source.projects.filter(func(p:Dictionary)->bool:return p.module_id==v.id and p.operation=="build" and p.status=="completed")
			if matching.size()!=1 or v.get("recovery_version")!="rc01-v1":return Data.reject("INVALID_MODULE_PAID_COST")
			var basis:=Upgrade.paid_basis(source,v)
			if not basis.ok or not Data.json_equal(paid,basis.get("paid",{})):return Data.reject("INVALID_MODULE_PAID_COST")
		elif Restoration.village(v) and v.restoration.get("completed",false):
			var basis:=Upgrade.paid_basis(source,v)
			if not basis.ok or not Data.json_equal(paid,basis.get("paid",{})):return Data.reject("INVALID_VILLAGE_PAID_COST")
		elif not paid.is_empty():return Data.reject("INVALID_MODULE_PAID_COST")
		if v.status=="ruined" or v.has("recovery"):
			var r:Variant=v.get("recovery")
			if not r is Dictionary or r.get("version")!="rc01-v1" or r.get("id")!=str(v.get("ruin_id",""))+":recovery" or not r.get("claimed") is bool or not number(r.get("frozen_at")) or not Identity.valid_id(r.get("cause_id")) or not Data.json_equal(r.get("items"),Recovery.recovery_items(v,0.5)):return Data.reject("INVALID_MODULE_RECOVERY_LEDGER")
			if v.get("ruin_id")!=str(v.id)+":ruin:1" or v.status not in ["ruined","dismantled"] or float(v.hp)!=0 or float(r.frozen_at)<0 or r.claimed!=(v.status=="dismantled") or not v.get("damage_receipts",{}).has(r.cause_id):return Data.reject("INVALID_MODULE_RECOVERY_LEDGER")
			for buffer_id:String in v.stock_refs:
				var stock:=Draft.find(facts_state.get("stocks",[]),str(v.stock_refs[buffer_id]))
				if stock.id!=str(v.ruin_id)+":cache:"+buffer_id or stock.get("ruin_id")!=v.ruin_id or stock.has("module_id") or stock.has("buffer_id"):return Data.reject("INVALID_RUIN_CACHE")
		if v.status=="dismantled" or v.has("recovery_settlement"):
			var terminal:Array=source.projects.filter(func(p:Dictionary)->bool:return p.module_id==v.id and p.operation in ["dismantle","clear_ruin"] and p.status=="completed")
			var settlement:Variant=v.get("recovery_settlement")
			if v.status!="dismantled" or terminal.size()!=1 or not settlement is Dictionary:return Data.reject("INVALID_MODULE_RECOVERY_SETTLEMENT")
			var project:Dictionary=terminal[0];var expected:Dictionary=Recovery.recovery_items(v,0.5 if project.operation=="clear_ruin" else 0.75)
			if (project.operation=="clear_ruin")!=v.has("recovery") or settlement.get("version")!="rc01-v1" or settlement.get("id")!=str(project.id)+":recovery" or settlement.get("claimed")!=true or not Data.json_equal(settlement.get("items"),expected):return Data.reject("INVALID_MODULE_RECOVERY_SETTLEMENT")
		if v.has("damage_receipts"):
			if not v.damage_receipts is Dictionary:return Data.reject("INVALID_MODULE_DAMAGE_LEDGER")
			for cause:String in v.damage_receipts:
				if not Identity.valid_id(cause) or not number(v.damage_receipts[cause]) or float(v.damage_receipts[cause])<=0:return Data.reject("INVALID_MODULE_DAMAGE_LEDGER")
	for key:String in source.source_receipts:
		var receipt:Variant=source.source_receipts[key]
		if not Identity.valid_id(key) or not receipt is Dictionary or receipt.get("source_key")!=key or not receipt.get("stock_ids") is Array or (not str(receipt.get("module_id","")).is_empty() and not ids.has(receipt.module_id)):return Data.reject("INVALID_MODULE_SOURCE_RECEIPT")
	var restoration_valid:=Restoration.validate(self,source)
	return Water.validate(self,source,facts_state) if restoration_valid.ok else restoration_valid

func validate_extension(facts_state:Dictionary,extension_overrides:Dictionary={})->Dictionary:return validate_extensions(facts_state,extension_overrides)
static func number(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))

func projection(actor_id:String="player",id:String="")->Dictionary:
	return _projection(actor_id,id,false)

func visual_projection(actor_id:String="player",id:String="")->Dictionary:
	# Same live permission/stock/project/machine derivation as management;
	# never evaluate UI proposals, recipe controls or stock-policy commands.
	return _projection(actor_id,id,true)

func _projection(actor_id:String,id:String,visual_only:bool)->Dictionary:
	var facts:Dictionary=context.facts.call();var a:=Draft.find(facts.get("actors",[]),actor_id);var rows:Array=[];var projects:Array=[]
	var visual_definitions:Array=[];var visual_definition_ids:Dictionary={}
	if a.is_empty():return {"available":false,"instances":[],"projects":[],"definitions":[],"build_definition_ids":[],"alerts":[]}
	var observed:Dictionary=state()
	for v:Dictionary in observed.instances:
		if (not id.is_empty() and v.id!=id) or not v.get("discovered",false) or not permitted(a,v.owner):continue
		var d:Dictionary=Catalog.definition_view(str(v.definition_id)) if visual_only else definition(str(v.definition_id))
		if visual_only and not visual_definition_ids.has(d.id):
			# Renderer resolves only emitted instances. Copy each used definition
			# once rather than all historical/unused catalogues on every poll.
			visual_definition_ids[d.id]=true;visual_definitions.append(d.duplicate(true))
		var row:Dictionary={"id":v.id,"definition_id":v.definition_id,"quarter_turn":v.quarter_turn} if visual_only else v.duplicate(true)
		row.location=G.location(v.position.merged({"regionId":v.region}));row.name=d.name;row.detailed=context.region_is_detailed.call(str(v.region)) if context.get("region_is_detailed") is Callable else context.world.region_is_resident(str(v.region))
		if not visual_only and d.get("story_front_point") is Array:
			var fp:Array=d.story_front_point;row.story_front_point=Shape.at(v,Vector3(fp[0],fp[1],fp[2]));row.story_service_id="service"
		row.state_code="ruined" if v.status=="ruined" else "damaged" if float(v.hp)<float(d.hp) else "idle"
		if not visual_only:
			row.state_label={"ruined":"残骸","damaged":"受损","idle":"空闲"}.get(row.state_code,row.state_code);row.blockers=[];row.next_batch_blockers=[];row.allowed_actions=["view"]
			if OpeningBed.eligible(context.world,v,d) and not v.config.has("opening_bed_v1"):row.allowed_actions.append("module.bed.install")
			if v.status=="ruined":row.allowed_actions.append("module.clear_ruin")
			if v.status in ["constructing","planned"]:row.allowed_actions.append_array(["module.work","module.cancel","module.held"])
			elif v.status in ["operational","damaged"]:
				row.allowed_actions.append("module.dismantle")
				row.upgrade_options=Upgrade.options(d)
				if not d.has("mechanism") and d.has("architecture"):row.upgrade_options.append(str(d.id)+".mechanism-v2")
				if v.status=="operational" and not row.upgrade_options.is_empty():row.allowed_actions.append("module.upgrade")
				row.mechanism=d.get("mechanism",{}).duplicate(true)
				if Restoration.pending(v):
					row.state_code="needs_restoration";row.state_label="待修复旧宅" if d.shape=="home" else "破损仓棚" if d.shape=="warehouse" else "缺件旧机架";row.blockers=["restoration_required"];row.allowed_actions.append("module.restore")
				elif float(v.hp)<float(d.hp):row.allowed_actions.append("module.repair")
			if v.has("restoration"):
				row.restoration_requirements={"cost":Restoration.cost(v),"seconds":Restoration.duration(v),"qualities":{"hammering":1},"historical_cost":v.restoration.get("historical_cost",Restoration.HISTORY).duplicate(true),"restored":v.restoration.completed}
				if not str(v.project_id).is_empty() and observed.projects.any(func(p:Dictionary)->bool:return p.id==v.project_id and Projects.active(p)):row.allowed_actions=["view","module.work","module.held","module.cancel"]
			row.action_requirements={"module.work":{"target_id":v.id},"module.cancel":{"target_id":v.id},"module.held":{"payload":{"held":"bool"}},"module.repair":{"payload":{"source_id":"stock-id","tool_id":"hammer-id"}},"module.dismantle":{"payload":{"source_id":"stock-id","output_id":"stock-id","tool_id":"hammer-id"}}}
			if v.has("restoration"):
				row.action_requirements["module.restore"]={"payload":{},"auto_approach":true,"optional_payload":["source_id","tool_id","tool_ids"]}
				if Restoration.pending(v):
					# This projection only reads the same detached facts already
					# used above; do not make another mutable whole-world draft.
					var restore_tx:=Workforce.observation(self,facts,{})
					var restore_preview:=RestoreAction.resolve(self,restore_tx,restore_tx.actor(actor_id),v,{},str(v.project_id))
					row.restoration_action={"available":restore_preview.ok,"code":restore_preview.get("code","OK"),"reason":restore_preview.get("reason",""),"materials":restore_preview.get("materials",[]),"tool":restore_preview.get("tool",{}),"auto_approach":true,"command":{"kind":"module.restore","target_id":v.id,"payload":{}}}
			var recipe_host:Variant=_production.get_ref() if _production!=null else null
			row.recipe_management=WorkOrders.projection(v,recipe_host) if recipe_host!=null else {}
			row.upgrade_proposals=[]
			for target_id:String in row.get("upgrade_options",[]):
				var proposal:=Upgrade.proposal(self,v,target_id,facts)
				row.upgrade_proposals.append({"definition_id":target_id,"available":bool(proposal.ok),"code":proposal.get("code","OK"),"reason":proposal.get("reason",""),"cost":proposal.get("cost",{}),"duration_seconds":proposal.get("duration",0)})
			row.stock_policies=StockPolicy.projection(self,v,d,facts) if d.get("mechanism",{}).get("version")==2 else []
		elif v.status in ["operational","damaged"] and Restoration.pending(v):row.state_code="needs_restoration"
		var anchors:Dictionary={};var buffers:Array=[];row.stock_visibility={}
		var stock_layout:Dictionary={}
		for port:Dictionary in Shape.ports(v,d):
			var point:Vector3=G.point(port.location);var normal:Vector3=G.point(port.normal)
			anchors[port.id]={"position":[point.x,point.y,point.z],"forward":[normal.x,normal.z],"quarter_turn":int(v.quarter_turn)}
		for b:Dictionary in d.buffer_specs:
			var stock:=Draft.find(facts.get("stocks",[]),str(v.stock_refs[b.id]))
			row.stock_visibility[b.id]=stock.get("searched",true)
			if not stock.get("searched",true):continue
			if stock_layout.is_empty():stock_layout=StockLayout.projection(v,d)
			for item:String in b.limits:
				var actual:float=float(stock.get("items",{}).get(item,0));var visual:String=stock_representation(item)
				var anchor_id:String="cargo:"+str(b.id)+":"+item
				var bay:Dictionary=stock_layout.get(str(b.id)+":"+item,{})
				if bay.is_empty():continue
				anchors[anchor_id]=bay.anchor
				var reserved:float=0.0;var production:Variant=_production.get_ref() if _production!=null else null
				if production!=null and production.has_method("capacity_reserved"):reserved=production.capacity_reserved(str(stock.get("id","")),item)
				var status:=stock_visual_status(v,bay,bool(row.detailed))
				buffers.append({"id":str(b.id)+":"+item,"stock_ref":v.stock_refs[b.id],"item_id":item,"unit":Content.item_definition(item).get("unit","count"),"actual":actual,"capacity":b.limits[item],"reserved":reserved,"representation":visual,"anchor_id":anchor_id,"extent":bay.extent,"visual_available":status.visual_available,"visual_reason":status.visual_reason})
		var front:float=float(d.footprint.min.z)-0.101
		var center:Vector3=G.point(Shape.at(v,Vector3(0,0.9 if d.shape=="manual" else 0.65,front)));var machine:Vector3=G.point(Shape.at(v,Vector3(0,1.1,-2.25)))
		# Only the explicit additive set opts into a different machine layout.
		# Saved legacy modules retain their original tooth anchor.
		if (d.get("architecture",{}).get("set")=="r34-architecture-30-v1" or d.get("village_geometry",{}).get("kind")=="village_sawmill") and d.get("machine_work_point") is Array:
			var work:Array=d.machine_work_point
			if work.size()==3:machine=G.point(Shape.at(v,Vector3(work[0],work[1],work[2])))
		var outward:=G.rotate(Vector3(0,0,-1),int(v.quarter_turn))
		anchors["condition"]={"position":[center.x,center.y,center.z],"forward":[outward.x,outward.z],"quarter_turn":int(v.quarter_turn)}
		anchors["saw"]={"position":[machine.x,machine.y,machine.z],"forward":[outward.x,outward.z],"quarter_turn":int(v.quarter_turn)}
		var project:=Draft.find(observed.projects,str(v.project_id));var construction:Dictionary=RestoreAction.construction(project,v,d,facts)
		var mechanism:Dictionary={};var machine_owner:Variant=_production.get_ref() if _production!=null else null
		if machine_owner!=null and machine_owner.has_method("module_machine_projection"):
			var state_row:Dictionary=machine_owner.module_machine_projection(str(v.id))
			if not state_row.is_empty():
				row.state_code=state_row.state_code;row.blockers=state_row.blockers;row.next_batch_blockers=state_row.next_batch_blockers;mechanism=state_row.mechanism
		if Restoration.pending(v) and v.status=="damaged":row.state_code="needs_restoration";row.blockers=["restoration_required"]
		if not visual_only:row.ports=Shape.ports(v,d)
		row.visuals={"anchors":anchors,"buffers":buffers,"mechanism":mechanism,"construction":construction,"damage":{"hp":v.hp,"max_hp":d.hp,"state_code":row.state_code,"ruin_id":v.get("ruin_id",""),"anchor_id":"condition"}}

		if not visual_only:
			row.state_label={"needs_restoration":"待修复旧宅" if d.shape=="home" else "待修复仓棚" if d.shape=="warehouse" else "缺件旧机架","running":"运行","paused":"暂停","unconfigured":"待配置","missing_input":"缺料","missing_energy":"缺能","output_full":"输出已满","target_met":"目标完成","region_paused":"区域暂停","idle":"空闲"}.get(row.state_code,row.state_code)
		rows.append(row)
	if visual_only:return {"available":true,"instances":rows,"definitions":visual_definitions,"projects":[],"build_definition_ids":[],"alerts":[]}
	for project:Dictionary in observed.projects:
		var module:=Draft.find(observed.instances,str(project.module_id))
		if not module.is_empty() and module.get("discovered",false) and permitted(a,module.owner):projects.append(project.duplicate(true))
	return {"available":true,"instances":rows,"projects":projects,"definitions":module_definitions(),"build_definition_ids":Catalog.build_definition_ids(),"alerts":_alerts(rows,projects)}

func alert_projection(actor_id:String="player")->Dictionary:
	# Same visible facts and builder as projection(), without deriving cargo,
	# ports, machine visuals or a mutable copy of the complete catalog.
	var actor:Dictionary=context.actor.call(actor_id)
	if actor.is_empty():return {"available":false,"alerts":[]}
	var observed:Dictionary=state();var rows:Array=[];var visible:Dictionary={};var projects:Array=[]
	for v:Dictionary in observed.instances:
		if not v.get("discovered",false) or not permitted(actor,v.owner):continue
		rows.append({"id":v.id,"status":v.status,"location":G.location(v.position.merged({"regionId":v.region})),"ruin_id":v.get("ruin_id","")});visible[v.id]=true
	for project:Dictionary in observed.projects:
		if visible.has(project.module_id):projects.append(project)
	return {"available":true,"alerts":_alerts(rows,projects)}

func service_approaches(actor_id:String,module_id:String)->Dictionary:
	return ServiceAccess.describe(self,actor_id,module_id)

static func _alerts(rows:Array,projects:Array)->Array:
	var alerts:Array=[]
	for row:Dictionary in rows:
		# HP/status are already authoritative; never wait for a cached machine
		# blocker to notice the same committed hit or ruined building.
		if row.status=="dismantled":continue
		if row.status=="ruined":alerts.append(Alerts.row(row.id,"ruined",row.location,str(row.get("ruin_id",""))))
		elif row.status=="damaged":alerts.append(Alerts.row(row.id,"damaged",row.location))
	for project:Dictionary in projects:
		if project.status not in ["blocked","paused"] or str(project.get("paused_reason","")).is_empty():continue
		var module:=Draft.find(rows,str(project.module_id))
		if not module.is_empty() and module.status not in ["dismantled","ruined"]:alerts.append(Alerts.row(module.id,str(project.paused_reason),module.location,project.id))
	return alerts

func stock_visual_status(v:Dictionary,bay:Dictionary,detailed:bool)->Dictionary:
	if not detailed:return {"visual_available":false,"visual_reason":"not_detailed"}
	var query:RefCounted=context.spatial.current_space()
	if _stock_query==null or _stock_query.get_ref()!=query:
		_stock_query=weakref(query);_stock_visibility.clear()
	var key:Array=[v.id,bay.anchor.position,bay.anchor.quarter_turn,bay.extent,bay.support]
	if not _stock_visibility.has(key):_stock_visibility[key]=StockLayout.visibility(query,v,bay)
	return _stock_visibility[key].duplicate(true)

func availability(request:Dictionary)->Dictionary:
	var result:=prepare(request)
	if result.get("ok",false):result.world_changes=[];result.fact_changes=[]
	return result

func prepare(request:Dictionary)->Dictionary:
	if request.get("kind")=="module.bed.install":return OpeningBed.prepare(self,request)
	if str(request.get("kind","")).begins_with("module.recipe."):
		var prod:Variant=_production.get_ref() if _production!=null else null
		return WorkOrders.prepare(prod,request) if prod!=null else Data.reject("UNAVAILABLE")
	if request.get("kind")=="module.stock_policy":return StockPolicy.prepare(self,request)
	return Water.prepare(self,request) if str(request.get("kind","")).begins_with("module.water.") else Projects.prepare(self,request)
func water_projection(actor_id:String="player",id:String="")->Dictionary:return Water.projection(self,actor_id,id)

func housing_projection(actor_id:String="player",staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:
	var facts:Dictionary=staged_facts if not staged_facts.is_empty() else context.facts.call()
	var actor:Dictionary=Draft.find(facts.get("actors",[]),actor_id)
	var result:Dictionary={"available":false,"homes":[]}
	if actor.is_empty() or float(actor.get("hp",0))<=0:return result
	result.available=true
	var query:RefCounted=context.spatial.current_space()
	var actions:Variant=_actions.get_ref() if _actions!=null else null
	for home:Dictionary in state(extension_overrides).instances:
		var d:Dictionary=Catalog.definition_view(str(home.definition_id))
		if d.get("shape")!="home":continue
		if d.get("architecture",{}).get("set")!="r34-architecture-30-v1" and not home.config.has("opening_bed_v1") and not d.has("village_geometry"):continue
		if not home.get("discovered",false) or not permitted(actor,home.get("owner")):continue
		var detailed:bool=context.region_is_detailed.call(str(home.region)) if context.get("region_is_detailed") is Callable else context.world.region_is_resident(str(home.region))
		var usable:bool=(home.status=="operational" and float(home.hp)==float(d.hp) or (Restoration.village(home) and home.status=="damaged")) and detailed
		var service_points:Array=[];var beds:Array=[];var reachable_count:int=0;var available_count:int=0
		for port:Dictionary in Shape.ports(home,d):
			if port.purpose=="service":service_points.append_array(port.use_points)
		for member:Dictionary in home.members:
			var bed:Dictionary=context.world.entity(str(member.id));var data:Dictionary=bed.get("data",{})
			if not data.get("module_bed",{}).get("version")==2:continue
			var occupants:Array=[]
			for resident:Dictionary in facts.get("actors",[]):
				if float(resident.get("hp",0))<=0 or not resident.get("intent") is Dictionary:continue
				var intent:Dictionary=resident.intent
				if (intent.get("owner")=="runtime" and intent.get("kind") in ["rest","sleep"] and intent.get("target_id")==bed.id) or (intent.get("owner")=="residents" and intent.get("resident_goal",{}).get("target_id")==bed.id):occupants.append(resident.id)
			var allowed:bool=permitted(actor,data.get("owner"));var feet:Dictionary=query.standing_point(data.module_bed.approach) if detailed else {}
			var reachable:bool=not feet.is_empty() and preload("res://scripts/buildings/interaction_contact.gd").entity(query,feet,bed)
			if reachable and actions!=null:reachable=actions.route(actor_id,G.location(actor),feet).get("ok",false)
			else:reachable=false
			var available:bool=usable and allowed and reachable and data.get("prepared",false) and data.get("sleeping",false) and (occupants.is_empty() or occupants==[actor_id])
			if reachable:reachable_count+=1
			if available:available_count+=1
			beds.append({"module_id":home.id,"bed_id":bed.id,"available":available,"occupied":not occupants.is_empty(),"occupant_ids":occupants,"owner":data.get("owner"),"permitted":allowed,"reachable":reachable,"reason":"" if available else "building_unavailable" if not usable else "permission" if not allowed else "no_supported_route" if not reachable else "unprepared" if not data.get("prepared",false) else "occupied" if not occupants.is_empty() else "bed_unavailable","prepared":data.get("prepared",false),"approach":data.module_bed.approach.duplicate(true),"surface":data.module_bed.surface.duplicate(true),"level":data.module_bed.level})
		var capacity:int=int(d.get("architecture",{}).get("design_capacity",beds.size()))
		result.homes.append({"id":home.id,"module_id":home.id,"definition_id":d.id,"geometry_version":home.geometry_version,"name":d.name,"tier":d.get("architecture",{}).get("tier","legacy"),"variant":d.get("architecture",{}).get("variant","legacy"),"capacity":capacity,"design_capacity":capacity,"bed_count":beds.size(),"reachable_bed_count":reachable_count,"available_bed_count":available_count,"beds":beds,"status":home.status,"usable":usable,"detailed":detailed,"location":G.location(home.position.merged({"regionId":home.region})),"stock_refs":home.stock_refs.duplicate(true),"service_points":service_points.duplicate(true)})
	return result

func preview(request:Dictionary)->Dictionary:return Projects.preview(self,request)
func advance(dt:float)->Dictionary:return Projects.advance(self,dt)

func validate_intent(intent:Dictionary,actor_state:Dictionary={},_facts_state:Dictionary={})->Dictionary:
	if intent.get("owner")=="modules" and intent.get("kind")=="water":
		if intent.get("schema_version")!=1 or not Data.valid_id(intent.get("id")) or not Data.valid_id(intent.get("project_id")) or not intent.get("held",true) is bool or (not actor_state.is_empty() and actor_state.get("id")!="player"):return Data.reject("INVALID_WATER_INTENT")
		var p:=Draft.find(state().get("water",{}).get("projects",[]),str(intent.project_id))
		if not p.is_empty() and p.actor_id!="player":return Data.reject("INVALID_WATER_WORKER")
		return {"ok":true,"code":"OK"}
	if intent.get("owner")!="modules" or intent.get("schema_version")!=1 or intent.get("kind")!="construction" or not Data.valid_id(intent.get("id")) or not Data.valid_id(intent.get("project_id")) or not intent.get("held",true) is bool:return Data.reject("INVALID_MODULE_INTENT")
	if not actor_state.is_empty():
		var project:=Draft.find(state().projects,str(intent.project_id))
		if not project.is_empty() and project.actor_id!=actor_state.id:return Data.reject("MODULE_WORKER_MISMATCH")
	return {"ok":true,"code":"OK"}
func hold_descriptors(facts:Dictionary,overrides:Dictionary={})->Array:
	var holds:Array=[]
	for p:Dictionary in state(overrides).projects:
		if not Projects.active(p):continue
		var a:=Draft.find(facts.get("actors",[]),str(p.actor_id))
		if not Projects.actor_ready(a):continue
		holds.append({"schema_version":1,"owner":"modules","intent_id":p.id,"actor_id":p.actor_id,"phase":"paused" if p.status!="active" else "active","source_id":p.source_id,"cost":p.cost.duplicate(true),"tool_ids":[p.tool_id],"use_target_id":p.module_id})
	holds.append_array(Water.holds(self,facts,overrides))
	return holds
func prepare_actor_release(transitions:Array,staged:Dictionary,pending_changes:Array)->Dictionary:
	var tx:=Draft.new(context);tx.initial=staged.duplicate(true);tx.staged=staged.duplicate(true)
	for c:Dictionary in pending_changes:
		if c.get("op")=="extension.set" and c.get("id")==KEY:
			if c.get("before_exists")!=context.world.has_extension(KEY) or not Data.json_equal(c.get("before"),context.world.extension(KEY)) or not c.get("after") is Dictionary:return Data.reject("INVALID_LIFECYCLE_PLAN")
			tx.extensions[KEY]=c.after.duplicate(true)
	var value:Dictionary=tx.extension(KEY,initial())
	for transition:Variant in transitions:
		if not transition is Dictionary or not Data.valid_id(transition.get("actor_id")) or transition.get("kind") not in ["incapacitated","removed","consent_revoked"]:return Data.reject("INVALID_LIFECYCLE_PLAN")
		for p:Dictionary in value.projects:
			if p.actor_id==transition.actor_id and Projects.active(p):p.status="cancelled";p.effective_work=0.0;p.paused_reason=str(transition.kind)
		for p:Dictionary in value.get("water",{}).get("projects",[]):
			if p.actor_id==transition.actor_id and Water.active(p):
				p.status="cancelled";p.effective_work=0.0;p.paused_reason=str(transition.kind)
				var source:=Draft.find(value.water.sources,str(p.source_id));source.project_id=""
	return tx.result()
func actor_work_projection(actor_id:String)->Dictionary:
	var a:Dictionary=context.actor.call(actor_id);var intent:Variant=a.get("intent")
	if not intent is Dictionary or intent.get("owner")!="modules":return {}
	if intent.get("kind")=="water":
		var water:Dictionary=state().get("water",{});var project:=Draft.find(water.get("projects",[]),str(intent.get("project_id","")))
		if project.is_empty() or not Water.active(project):return {}
		var source:=Draft.find(water.sources,str(project.source_id));var normal:Vector3=G.point(source.use_point)-G.point(source.position)
		normal.y=0;normal=normal.normalized()
		var repair:bool=project.operation=="repair"
		var point:Vector3=G.point(source.position)+normal*(0.46 if repair else 0.535)+Vector3.UP*(0.73 if repair else 0.77)
		if not repair:
			var phase:float=fposmod(float(project.progress_seconds),1.0);var angle:float=-0.32-0.08*sin(phase*TAU)
			point=G.point(source.position)+normal*(0.46-0.24*sin(angle))+Vector3.UP*(0.86+0.24*cos(angle))
		var problem:=Water.problem(self,Draft.new(context),project,source)
		return {"owner":"modules","kind":"water","operation":project.operation,"tool_id":project.tool_id if repair else "","progress_seconds":project.progress_seconds,"duration_seconds":project.duration_seconds,"effective_work":problem.is_empty() and float(project.effective_work)>0,"effective_seconds":project.effective_work,"paused_reason":problem,"contact":{"position":[point.x,point.y,point.z],"normal":[normal.x,normal.y,normal.z]}}
	var p:=Draft.find(state().projects,str(intent.get("project_id","")))
	if p.is_empty() or not Projects.active(p):return {}
	var v:=instance(str(p.module_id));var d:=definition(str(v.definition_id));var local:=Vector3(0,0.9 if d.shape=="manual" else 0.65,float(d.footprint.min.z)-0.101)
	var point:Vector3=G.point(Shape.at(v,local));var normal:=G.rotate(Vector3(0,0,-1),int(v.quarter_turn));var problem:=Projects.labor_problem(self,Draft.new(context),p,v)
	var phase:String="paused" if not intent.get("held",true) or not problem.is_empty() else "working"
	return {"owner":"modules","kind":"construction","operation":p.operation,"phase":phase,"module_id":p.module_id,"project_id":p.id,"held":intent.get("held",true),"actor_id":actor_id,"progress_seconds":p.progress_seconds,"duration_seconds":p.duration_seconds,"effective_work":problem.is_empty() and float(p.get("effective_work",0))>0,"effective_seconds":p.get("effective_work",0),"paused_code":problem,"paused_reason":RestoreAction.reason(problem),"contact":{"position":[point.x,point.y,point.z],"normal":[normal.x,normal.y,normal.z]}}

func prepare_actor_control(request:Dictionary)->Dictionary:
	var a:Dictionary=context.actor.call(str(request.get("actor_id","")));var intent:Variant=a.get("intent")
	if not intent is Dictionary or intent.get("owner")!="modules":return Data.reject("MODULE_INTENT_MISSING")
	if intent.get("kind")=="water":
		var project:=Draft.find(state().get("water",{}).get("projects",[]),str(intent.get("project_id","")))
		if project.is_empty():return Data.reject("WATER_PROJECT_MISSING")
		var translated:Dictionary=request.duplicate(true);translated.target_id=project.source_id
		translated.kind="module.water.cancel" if request.get("kind")=="cancel" else "module.water.held" if request.get("kind")=="held" else ""
		return prepare(translated) if not translated.kind.is_empty() else Data.reject("INVALID_WATER_CONTROL")
	var project:=Draft.find(state().projects,str(intent.get("project_id","")))
	if project.is_empty():return Data.reject("MODULE_PROJECT_MISSING")
	var translated:Dictionary=request.duplicate(true);translated.target_id=project.module_id
	translated.kind="module.cancel" if request.get("kind")=="cancel" else "module.held" if request.get("kind")=="held" else ""
	return prepare(translated) if not translated.kind.is_empty() else Data.reject("INVALID_MODULE_CONTROL")

func workforce_candidates(actor_id:String,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Array:return Workforce.candidates(self,actor_id,staged_facts,extension_overrides)
func claim_workforce_in(tx:RefCounted,actor_id:String,candidate_id:String,command_id:String,arrived:bool=false)->Dictionary:return Workforce.claim_in(self,tx,actor_id,candidate_id,command_id,arrived)
func safe_handoff(actor_id:String,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:return Workforce.handoff(self,actor_id,staged_facts,extension_overrides)
func release_workforce_in(tx:RefCounted,actor_id:String,candidate_id:String)->void:Workforce.release_in(self,tx,actor_id,candidate_id)

func damage_in(tx:RefCounted,module_id:String,amount:float,cause_id:String)->Dictionary:return Recovery.damage_in(self,tx,module_id,amount,cause_id)
func strike_hostile(tx:RefCounted,actor_id:String,module_id:String="")->Dictionary:return Hostile.strike(self,tx,actor_id,module_id)
func prepare_damage(module_id:String,amount:float,cause_id:String,staged_facts:Dictionary={},extension_overrides:Dictionary={})->Dictionary:
	var tx:=Draft.new(context)
	if not staged_facts.is_empty():tx.initial=staged_facts.duplicate(true);tx.staged=staged_facts.duplicate(true)
	tx.extensions=extension_overrides.duplicate(true)
	var result:=damage_in(tx,module_id,amount,cause_id)
	return tx.result() if result.ok else result

static func stock_representation(item:String)->String:
	if item=="log":return "log"
	if item=="timber":return "plank"
	if item=="scrap":return "scrap"
	if item in ["r34:raw_water","r34:filtered_water"]:return "water_can"
	if item in ["r34:potato_seed","r34:bean_seed","r34:rice_seed","r34:broadleaf_seed","r34:conifer_seed"]:return "seed_sack"
	if item in ["r34:potato","r34:beans"]:return "produce"
	if item in ["r34:paddy","r34:rice"]:return "grain_sack"
	if item in ["r34:broadleaf_seedling","r34:conifer_seedling"]:return "seedling"
	if item in ["r34:compost","r34:crop_residue"]:return "compost_sack"
	if item in ["r34:meal_simple","r34:meal_hearty"]:return "meal"
	if item=="r34:dry_ration":return "ration"
	if item=="r34:structural_timber":return "joinery_beam"
	if item=="r34:metal_fitting":return "metal_bracket"
	if item=="r34:water_bucket":return "empty_bucket"
	return "crate"
