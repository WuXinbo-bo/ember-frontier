extends RefCounted
## One-time composition of C terrain, B modules/content and E opening facts.
## Works off-screen; only NativeClient may publish this capture/save pointer.
const Generator=preload("res://scripts/world/factory_generator.gd")
const GenerationContract=preload("res://scripts/world/factory_generation_contract.gd")
const Data=preload("res://scripts/world/world_data.gd")
const World=preload("res://scripts/world/world_state.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const ModuleShape=preload("res://scripts/modules/module_geometry.gd")
const ModuleCatalog=preload("res://scripts/modules/module_catalog.gd")
const ZoneProduction=preload("res://scripts/world/factory_zone_production.gd")
const MODULE_PATH="res://scripts/modules/module_service.gd"
const GENERATION_CONTENT_VERSION:=21

static func module_service()->Dictionary:
	if not ResourceLoader.exists(MODULE_PATH):return _failure("MISSING_FACTORY_SERVICE","完整模块领域尚未交付，保留原世界")
	var script:Variant=load(MODULE_PATH)
	if not script is GDScript or not script.can_instantiate():return _failure("INVALID_FACTORY_SERVICE","完整模块领域尚未可运行")
	var service:Variant=script.new()
	for method:String in ["generation_profiles_for_content","prepare_generation"]:
		if not service.has_method(method):return _failure("MISSING_FACTORY_INTERFACE","完整模块领域缺少生成接口："+method)
	return {"ok":true,"service":service}

static func generation_profiles(content_version:int=GENERATION_CONTENT_VERSION)->Dictionary:
	var loaded:Dictionary=module_service()
	if not loaded.ok:return loaded
	var profiles:Variant=loaded.service.generation_profiles_for_content(content_version)
	if not profiles is Array or profiles.is_empty():return _failure("MISSING_MODULE_GENERATION_PROFILES","新世界缺少完整模块地块与服务面定义")
	return {"ok":true,"profiles":profiles.duplicate(true)}

static func generate(seed:int,profiles:Array,content_version:int=GENERATION_CONTENT_VERSION)->Dictionary:
	# New worlds opt into the three-companion old-village layout and heritage
	# repair chain. Existing saves retain their recorded generation contract.
	var configured:Dictionary=GenerationContract.fresh(profiles,content_version,1)
	return Generator.generate(seed,profiles,configured.contract) if configured.ok else configured

static func prepare(snapshot:Dictionary)->Dictionary:
	if snapshot.get("ok")==false:return snapshot.duplicate(true)
	var world:=World.new()
	var loaded:Dictionary=world.load_snapshot(snapshot)
	if not loaded.ok:return loaded
	var module_load:Dictionary=module_service()
	if not module_load.ok:return module_load
	# B explicitly supports an unconfigured pure-view generation call. No
	# provisional live actors, second tick or temporary production is needed.
	var registration:Dictionary=module_load.service.prepare_generation(world)
	if not registration.get("ok",false):return registration
	var seed:Dictionary=registration.get("seed_result",registration).duplicate(true)
	var stocks:Array=seed.get("initial_stocks",[]).duplicate(true)
	var stock_ids:Dictionary={}
	for stock:Dictionary in stocks:
		if stock_ids.has(stock.get("id")):return _failure("INITIAL_DUPLICATE_CONTENT","模块起步库存身份重复")
		stock_ids[stock.id]=true
	for stock:Dictionary in Generator.initial_resource_stocks(world):
		if stock_ids.has(stock.id):return _failure("INITIAL_DUPLICATE_CONTENT","资源掉落库存被两次登记："+str(stock.id))
		stocks.append(stock);stock_ids[stock.id]=true
	# The C descriptor names the sole finite opening source. B registers the
	# actual independent container/stock in its existing one-time receipt path.
	# Composition verifies that result; it never grants a second copy here.
	var regional:Dictionary=ZoneProduction.opening_additions(world)
	if not regional.get("ok",false):return regional
	for addition:Dictionary in regional.get("additions",[]):
		var matches:Array=stocks.filter(func(row:Dictionary)->bool:return row.get("id")==addition.get("source_id"))
		if matches.size()!=1 or not Data.json_equal(matches[0].get("items"),addition.get("items")):return _failure("INITIAL_REGIONAL_SOURCE_MISSING","新开场种袋尚未由原登记入口准确接入")
		if matches[0].get("module_id")!=null:return _failure("INITIAL_REGIONAL_BUFFER_CONFLICT","种袋不能绕过原模块容量规则")
	seed.initial_stocks=stocks
	for field:String in ["initial_tools","initial_records"]:
		if not seed.get(field,[]) is Array:return _failure("INITIAL_CONTENT_INVALID","起步工具或书册列表无效")
		seed[field]=seed.get(field,[]).duplicate(true)
	var changes:Array=registration.get("world_changes",[]).duplicate(true)
	var projected:Dictionary=world.prepare_changes(changes,world.get_revision())
	if not projected.ok:return projected
	# Check the same B registration draft, including the once-only receipt.
	# A never manufactures a receipt, source entity or replacement supply row.
	var regional_state:Variant=projected.view.extension("r34:modules")
	for addition:Dictionary in regional.get("additions",[]):
		var receipt:Variant=regional_state.get("source_receipts",{}).get(addition.get("receipt_id")) if regional_state is Dictionary else null
		var entity:Dictionary=projected.view.entity(str(addition.get("entity_id","")))
		if not receipt is Dictionary or receipt.get("source_key")!=addition.get("receipt_id") or receipt.get("module_id")!="" or receipt.get("stock_ids")!=[addition.get("source_id")] or entity.get("kind")!="container" or entity.get("regionId")!="RH-VILLAGE" or not Data.json_equal(entity.get("position"),addition.get("position")):
			world.discard_prepared(projected.capability)
			return _failure("INITIAL_REGIONAL_RECEIPT_MISSING","新开场种袋缺少准确的一次性来源登记，未创建世界")
	var building:=Buildings.new()
	# Existing Space supports pure value callbacks and explicit observed facts.
	building.configure({"world":world,"actor":func(_id:String)->Dictionary:return {},"stock":func(_id:String)->Dictionary:return {},"tool":func(_id:String)->Dictionary:return {},"facts":func()->Dictionary:return {},"clock":func()->float:return 0.0})
	var query:RefCounted=building.space(projected.view,{}, {"actors":[]})
	var layout:Dictionary=_layout(world,query,seed.get("spawn_points",{}),regional_state)
	world.discard_prepared(projected.capability)
	if not layout.ok:return layout
	seed.spawn_points=layout.spawn_points;seed.home=layout.home
	# Compatibility aliases are replaced by the same detached canonical seed,
	# never appended as additional stock grants.
	registration.seed_result=seed
	for field:String in ["initial_stocks","initial_tools","initial_records"]:registration[field]=seed[field].duplicate(true)
	var initial:Dictionary=Gameplay.initial(layout,registration)
	if not initial.ok:return initial
	var facts:Dictionary=initial.facts
	var checked:Dictionary=Runtime.validate_facts(facts)
	if not checked.ok:return checked
	changes=initial.world_changes.duplicate(true)
	changes.append({"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":initial.production_state})
	changes.append({"op":"extension.set","id":"r3:structure-orders","before_exists":false,"before":null,"after":{"version":1,"orders":[]}})
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	if not draft.ok:return draft
	var safety:Dictionary=building.validate_world_draft(draft.view,facts,changes)
	if not safety.ok:world.discard_prepared(draft.capability);return safety
	var committed:Dictionary=world.commit_prepared(draft.capability)
	if not committed.ok:return committed
	return {"ok":true,"code":"OK","capture":{"world":world.snapshot(),"facts":facts,"source":{"scenario":Generator.SCENARIO,"generator":Generator.VERSION,"opening":"normal finite sources; registered once; test supplies only through explicit playtest profile"},"command_revision":0,"content":Content.content_lock()},"layout":layout,"content_card":initial.content_card}

static func _at(value:Dictionary,region:String)->Dictionary:
	var result:Dictionary=value.duplicate(true)
	result.merge({"regionId":region,"buildingId":null,"storeyId":null},true)
	return result

static func _spawn(world:RefCounted,query:RefCounted,plan:Dictionary,preferred:Dictionary,occupied:Array,worksites:Array=[])->Dictionary:
	var points:Array=[preferred]
	for offset:Vector2 in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2),Vector2(4,0),Vector2(-4,0)]:
		var point:Dictionary=preferred.duplicate(true);point.x+=offset.x;point.z+=offset.y;points.append(point)
	if not worksites.is_empty():
		# Try the nearby village yard before falling back to distant road points.
		for offset:Vector2 in [Vector2(2,2),Vector2(-2,2),Vector2(2,-2),Vector2(-2,-2),Vector2(0,4),Vector2(0,-4),Vector2(4,2),Vector2(-4,2)]:
			var point:Dictionary=preferred.duplicate(true);point.x+=offset.x;point.z+=offset.y;points.append(point)
	for path:Dictionary in plan.get("paths",[]):
		for point:Dictionary in path.get("points",[]):points.append(point)
	for point:Dictionary in points:
		if world.region_at(point).get("id")!=plan.region_id:continue
		var at:Dictionary=_at(point,str(plan.region_id))
		var feet:Dictionary=query.standing_point(at)
		if feet.is_empty() or feet.get("buildingId")!=null or world.region_at(feet).get("id")!=feet.regionId:continue
		# Spawn-time site planning uses the same real human body as completion
		# safety. It does not weaken collision or relocate any existing actor.
		var body:=AABB(Geometry.point(feet)-Vector3(0.26,0,0.26),Vector3(0.52,1.8,0.52))
		if worksites.any(func(box:AABB)->bool:return box.intersects(body)):continue
		if occupied.any(func(other:Dictionary)->bool:return Geometry.point(other).distance_squared_to(Geometry.point(feet))<4.0):continue
		return feet
	return {}

static func _layout(world:RefCounted,query:RefCounted,proposed:Dictionary,modules:Dictionary={})->Dictionary:
	var generation:Variant=world.extension("generation:factory-r34")
	var content_version:int=int(generation.get("content_version",0)) if generation is Dictionary else 0
	var old_village:bool=content_version>=13
	var home:Variant=world.extension("generation:RH-HOME")
	var village:Variant=world.extension("generation:RH-VILLAGE")
	if not home is Dictionary or not village is Dictionary or not home.get("anchors",{}).get("arrival") is Dictionary or not village.get("anchors",{}).get("arrival") is Dictionary:return _failure("MISSING_FACTORY_LAYOUT","新世界缺少真实起步与村路锚点")
	var spawns:Dictionary={};var occupied:Array=[];var worksites:Array=[]
	# Only new16 companions start clear of pending restoration footprints.
	# The projected original module registration supplies these exact bounds.
	if content_version>=16:
		for module:Dictionary in modules.get("instances",[]):
			if not module.get("restoration") is Dictionary or module.restoration.get("completed",false):continue
			worksites.append(ModuleShape.transform_box(module,Geometry.aabb(ModuleCatalog.definition_view(str(module.definition_id)).footprint)))
	for id:String in ["player","village-resident","repair-resident"]:
		var plan:Dictionary=village if id=="repair-resident" and not old_village else home
		var preferred:Dictionary=proposed.get(id,plan.anchors.arrival)
		if old_village and id!="player":
			preferred=proposed.get("player",home.anchors.arrival).duplicate(true)
			preferred.x+=2.0 if id=="village-resident" else -2.0
		if proposed.has(id):
			var actual:Dictionary=world.region_at(preferred)
			if actual.is_empty() or actual.id!=preferred.get("regionId"):return _failure("INITIAL_SPAWN_REGION_MISMATCH","出生点与实际地形地区不一致："+id)
			var preferred_plan:Variant=world.extension("generation:"+str(actual.id))
			if not preferred_plan is Dictionary:return _failure("MISSING_FACTORY_LAYOUT","出生点缺少真实地区规划："+id)
			plan=preferred_plan
		var at:Dictionary=_spawn(world,query,plan,preferred,occupied,worksites if content_version>=16 and id!="player" else [])
		if at.is_empty():return _failure("NO_FACTORY_SPAWN","真实地形与模块未提供合法人物站位："+id)
		spawns[id]=at;occupied.append(at)
	var defense:Dictionary=_spawn(world,query,home,home.anchors.get("defence_north",home.anchors.arrival),[])
	if defense.is_empty():return _failure("NO_FACTORY_DEFENSE_ANCHOR","真实村路未提供防守接近位置")
	var sites:Array=[]
	for region:Dictionary in world.regions():
		var plan:Variant=world.extension("generation:"+str(region.id))
		if plan is Dictionary:sites.append_array(plan.get("regional_sites",[]).duplicate(true))
	return {"ok":true,"version":1,"content_version":content_version,"opening_version":3 if old_village else 1,"scenario":Generator.SCENARIO,"generator":Generator.VERSION,"start_region":"RH-HOME","home_region":"RH-HOME","home":spawns.player.duplicate(true),"home_radius":18.0,"spawn_points":spawns,"defense_position":defense,"region_goal":"townward-transport-route","regional_sites":sites,"opening_landmarks":home.get("opening_landmarks",{}).duplicate(true),"opening_route":home.get("opening_route",[]).duplicate(true),"expansion_spaces":home.get("expansion_spaces",[]).duplicate(true)}

static func _failure(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
