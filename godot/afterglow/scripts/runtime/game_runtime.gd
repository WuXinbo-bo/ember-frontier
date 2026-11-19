extends RefCounted
## Sole owner of runtime facts and the 0.1s simulation clock. Domains only prepare changes.
signal changed(changes: Dictionary)
signal close_failed(receipt: Dictionary)
const FrameCosts = preload("res://scripts/runtime/frame_costs.gd")
const Data = preload("res://scripts/world/world_data.gd")
const LegacyIntents = preload("res://scripts/storage/legacy_intents.gd")
const Movement = preload("res://scripts/runtime/movement_policy.gd")
const ActorProfiles=preload("res://scripts/runtime/actor_profiles.gd")
const FactoryContracts=preload("res://scripts/runtime/factory_contracts.gd")
const FactoryDefinitions=preload("res://scripts/runtime/factory_definitions.gd")
const FactoryHandbook=preload("res://scripts/runtime/factory_handbook.gd")
const ChapterStock=preload("res://scripts/runtime/chapter_stock.gd")
const EcologyRules=preload("res://scripts/ecology/ecology_rules.gd")
const VillageProgression=preload("res://scripts/runtime/village_progression.gd")
const STEP: float = 0.1
const LIFE := {"hunger":0.022,"thirst":0.035,"fatigue":0.012}
var world: RefCounted
var _context: Dictionary = {}
var _facts: Dictionary = {}
var _checked_stocks: Variant = null
var _services: Dictionary = {}
var _revision: int = 0
var _remainder: float = 0.0
const Content=preload("res://scripts/runtime/content_definitions.gd")
const MAX_STEPS_PER_FRAME:=4
const TICK_BUDGET_USEC:=6000
var _tick_stats:Dictionary={"frames":0,"steps":0,"last_steps":0,"last_usec":0,"max_step_usec":0,"max_backlog":0.0,"over_budget":0}
var _receipts: Dictionary = {}
var _source: Dictionary = {}
var _content_lock:Dictionary={}
var _paused: bool = false
var _storage_barrier:=false
var _retired:bool=false
var _target: Dictionary = {}
var _hand: Dictionary = {}
var _work_targets: Array=[]
var _work_revision: int=-1
var _render_visibility_key: Array = []
var _render_visible: Array=[]
var _movement_used:Dictionary={}
var _movement_recent:Dictionary={}
var _recovery_motion:Dictionary={}
var _readiness_provider:Callable
var _authority_costs:Dictionary={"count":0,"failed":0,"total_usec":0,"max_usec":0,"phases":{}}
var _simulation_costs:Dictionary={}
var _detailed_step_scope:=false
var _detailed_step_revision:int=-1
var _detailed_step_regions:Dictionary={}
var _detailed_read_basis:Array=[]
var _detailed_read_regions:Dictionary={}
var _draft_read_snapshot:Dictionary={}
var _actor_work_basis:Array=[]
var _actor_work_cache:Dictionary={}
var _ui_read_epoch:int=0
var _use_idle_direct_move:=true

func ui_read_basis()->Dictionary:
	# A detached observation fence for duplicate synchronous UI reads only.
	# Frame identity also fences geometry/readiness changes outside authority;
	# no cached query grants admission to a command or skips its validation.
	var scopes:Array=[]
	if world!=null:
		for id:String in world.region_ids():scopes.append([id,region_is_detailed(id)])
	return {"runtime":get_instance_id(),"epoch":_ui_read_epoch,"frame":Engine.get_process_frames(),"world":world.get_instance_id() if world!=null else 0,"world_token":world.extension_token("") if world!=null and world.has_method("extension_token") else {},"world_revision":world.get_revision() if world!=null else -1,"revision":_revision,"clock":clock(),"paused":_paused,"retired":_retired,"storage_barrier":_storage_barrier,"scopes":scopes,"target":_target.duplicate(true),"hand":_hand.duplicate(true),"save":_context.get("save_state",{}).duplicate(true),"stream":_context.get("stream_state",{}).duplicate(true)}

# Domain access is for same-authority preparation. Only command/_commit publish.
func domain_service(name:String)->Variant:
	return null if _retired else _services.get(name)

func zone_service()->Variant:
	return domain_service("zones")

func zone_records()->Array:
	var service:Variant=zone_service()
	return service.zone_records() if service!=null and service.has_method("zone_records") else []

func zone_preview(spec:Dictionary)->Dictionary:
	var service:Variant=zone_service()
	return service.preview(spec) if service!=null else _failure("ZONE_UNAVAILABLE","区域规划尚未装配")

func zone_projection(actor_id:String="player",zone_id:String="")->Dictionary:
	var service:Variant=zone_service()
	var result:Dictionary=service.projection(actor_id,zone_id) if service!=null else {"available":false,"zones":[],"selection":{},"definitions":{}}
	result.crops=EcologyRules.CROPS.duplicate(true);result.trees=EcologyRules.TREES.duplicate(true)
	return result

func zone_view_basis(actor_id:String="player")->Dictionary:
	var service:Variant=zone_service()
	var basis:Dictionary=service.view_basis(actor_id) if service!=null else {"available":false,"zones_revision":0,"world_revision":world.get_revision()}
	basis.world_generation=world.get_instance_id();basis.runtime_generation=get_instance_id()
	# Runtime revision is a safe work-query fence (includes actual actor/stock
	# changes). Consumers keep list/selection caching on zones_revision alone.
	basis.work_revision=_revision
	return basis

func zone_work_projection(actor_id:String="player",include_candidates:bool=false)->Dictionary:
	var service:Variant=domain_service("zonework")
	if service==null:return {"available":false,"jobs":[],"candidates":[]}
	var result:Dictionary=service.projection(actor_id)
	result.candidates=service.work_candidates(actor_id) if include_candidates and result.get("available",false) else []
	result.basis=zone_view_basis(actor_id)
	return result

func housing_projection(actor_id:String="player")->Dictionary:
	var fallback:Dictionary={"available":false,"homes":[]}
	if _retired or actor(actor_id).is_empty():return fallback
	var service:Variant=domain_service("modules")
	if service==null or not service.has_method("housing_projection"):return fallback
	var value:Variant=service.housing_projection(actor_id)
	return value.duplicate(true) if value is Dictionary and value.get("available") is bool and value.get("homes") is Array else fallback

func life_consumables(actor_id:String="player",kind:String="eat")->Array:
	var actor_state:Dictionary=actor(actor_id);var result:Array=[]
	if actor_state.is_empty() or kind not in ["eat","drink","medicine"]:return result
	var tx:=LifeReadView.new(_facts,world)
	for id:String in actor_state.get("pack",{}):
		var definition:Dictionary=Content.consumable_definition(id,kind)
		if definition.is_empty():continue
		var held:float=_services.production.reserved("pack:"+actor_id,id,"",tx) if _services.has("production") else 0.0
		var free:float=float(actor_state.pack[id])-held
		if free>=1:
			definition.free=free;definition.name=Content.item_definition(id).get("name",id);result.append(definition)
	return result

func _life_consumable(a:Dictionary,kind:String,request:Dictionary,observed:Dictionary)->Dictionary:
	if kind not in ["eat","drink","medicine"]:return {}
	var payload:Variant=request.get("payload",{})
	if not payload is Dictionary:return {}
	var requested:Variant=payload.get("item_id","")
	if not requested is String:return {}
	var ids:Array=[]
	if not requested.is_empty():ids.append(requested)
	else:
		ids.append({"eat":"food","drink":"water","medicine":"medicine"}[kind])
		for id:String in a.get("pack",{}):
			if not ids.has(id):ids.append(id)
	var tx:=LifeReadView.new(observed,world)
	for id:String in ids:
		var definition:Dictionary=Content.consumable_definition(id,kind)
		if definition.is_empty():continue
		var held:float=_services.production.reserved("pack:"+str(a.id),id,str(request.get("command_id","")),tx) if _services.has("production") else 0.0
		if float(a.get("pack",{}).get(id,0))-held>=1:return definition
	return {}

func authority_costs()->Dictionary:return _authority_costs.duplicate(true)
func simulation_costs()->Dictionary:return _simulation_costs.duplicate(true)
func _simulation_phase(name:String,started:int)->void:
	var elapsed:int=Time.get_ticks_usec()-started
	var phase:Dictionary=_simulation_costs.get(name,{"count":0,"total_usec":0,"max_usec":0})
	phase.count+=1;phase.total_usec+=elapsed;phase.max_usec=maxi(int(phase.max_usec),elapsed)
	_simulation_costs[name]=phase
	if FrameCosts.trace_enabled: FrameCosts.end("simulation/" + name, started)
func _cost_phase(name:String,started:int)->void:
	if FrameCosts.trace_enabled: FrameCosts.end("authority/" + name, started)
	var elapsed:int=Time.get_ticks_usec()-started
	var phase:Dictionary=_authority_costs.phases.get(name,{"count":0,"total_usec":0,"max_usec":0})
	phase.count+=1;phase.total_usec+=elapsed;phase.max_usec=maxi(int(phase.max_usec),elapsed)
	_authority_costs.phases[name]=phase

# A short-lived read adapter for the existing domain query protocol. It never
# commits or mutates either the supplied staged facts or the live authority.
class LifeReadView extends RefCounted:
	var staged:Dictionary
	var authority:RefCounted
	var extensions:Dictionary={}
	# Reservation queries share the Draft protocol; this adapter never caches
	# observations or owns mutable preparation state.
	var observation_only:bool=false
	func _init(value:Dictionary,source:RefCounted)->void:
		staged=value;authority=source
	func actor(id:String)->Dictionary:return fact_from(staged,"actors",id)
	func extension(id:String,fallback:Dictionary={})->Dictionary:
		var value:Variant=authority.extension(id)
		return value if value is Dictionary else fallback.duplicate(true)
	static func fact_from(value:Dictionary,collection:String,id:String)->Dictionary:
		for entry:Dictionary in value.get(collection,[]):
			if str(entry.get("id",""))==id:return entry.duplicate(true)
		return {}

static func fact_from(value:Dictionary,collection:String,id:String)->Dictionary:
	return LifeReadView.fact_from(value,collection,id)

static func facts_diff(before:Dictionary,after:Dictionary)->Array:
	var result:Array=[]
	for collection:String in ["actors","stocks","actions","quests"]:
		var prior:Array=before.get(collection,[])
		var staged:Array=after.get(collection,[])
		if prior==staged:continue
		var old:Dictionary={};var next:Dictionary={}
		for entry:Dictionary in prior:old[str(entry.id)]=entry
		for entry:Dictionary in staged:next[str(entry.id)]=entry
		for id:String in next:
			if old.get(id)!=next[id]:result.append({"collection":collection,"id":id,"before":old.get(id,null),"after":next[id]})
		for id:String in old:
			if not next.has(id):result.append({"collection":collection,"id":id,"before":old[id],"after":null})
	return result.duplicate(true)

func life_availability(request:Dictionary,actor_state:Dictionary={},facts_state:Dictionary={})->Dictionary:
	var schema:Dictionary=_request_schema(request)
	if not schema.ok:return schema
	var observed:Dictionary=_facts if facts_state.is_empty() else facts_state
	var a:Dictionary=fact_from(observed,"actors",str(request.get("actor_id",actor_state.get("id","player")))) if actor_state.is_empty() else actor_state.duplicate(true)
	if a.is_empty() or float(a.get("hp",0))<=0 or observed.get("status","playing")!="playing":return _failure("ACTOR_UNAVAILABLE","角色无法行动")
	if request.has("actor_id") and request.actor_id!=a.get("id"):return _failure("INVALID_ACTOR","生活请求与暂存角色身份不一致")
	if request.get("kind") not in ["eat","drink","medicine","rest","talk","help","invite","consent","job","cancel"]:return _failure("UNSUPPORTED_LIFE","生活动作类型无效")
	# This query reads through LifeReadView. Only the actor list needs a
	# private copy to substitute the caller's actor and latest staged pose.
	var view := observed.duplicate()
	var actors: Array = observed.get("actors", []).duplicate()
	view.actors = actors
	for i in actors.size():
		if actors[i].id == a.id:
			actors[i] = a
			break
	return _life_availability(request,a,view)

func prepare_life(request:Dictionary,actor_state:Dictionary={},facts_state:Dictionary={})->Dictionary:
	if not Data.valid_id(request.get("command_id")):return _failure("INVALID_COMMAND","生活请求缺少唯一标识")
	var ready:Dictionary=life_availability(request,actor_state,facts_state)
	if not ready.ok:return ready
	var observed:Dictionary=_facts if facts_state.is_empty() else facts_state
	var a:Dictionary=fact_from(observed,"actors",str(request.get("actor_id",actor_state.get("id","player")))) if actor_state.is_empty() else actor_state.duplicate(true)
	return _prepare_life(request,a,observed)

func hold_descriptors(observed:Dictionary, _extension_overrides:Dictionary={})->Array:
	var result:Array=[]
	for a:Dictionary in observed.get("actors",[]):
		var intent:Variant=a.get("intent")
		if float(a.get("hp",0))<=0 or not intent is Dictionary or intent.get("owner")!="runtime":continue
		var item:String=str(intent.get("item_id",{"eat":"food","drink":"water","medicine":"medicine"}.get(intent.get("kind"),"")))
		var target:String=str(intent.get("target_id","")) if intent.get("kind") in ["rest","sleep"] else ""
		if item.is_empty() and target.is_empty():continue
		result.append({"schema_version":1,"owner":"runtime","intent_id":str(intent.get("id","")),"actor_id":str(a.id),"phase":"active","source_id":"pack:"+str(a.id) if not item.is_empty() else "","cost":{item:1} if not item.is_empty() else {},"tool_ids":[],"use_target_id":target})
	return result

func validate_intent(intent:Dictionary,actor_state:Dictionary={},facts_state:Dictionary={})->Dictionary:
	var owner:Variant=intent.get("owner");var kind:Variant=intent.get("kind")
	var version:Variant=intent.get("schema_version",0)
	if not owner is String or not kind is String or kind.is_empty() or not _number(version) or float(version)!=floorf(float(version)) or int(version) not in [0,1]:return _failure("INVALID_INTENT_SCHEMA","活动归属、类型或版本无效")
	for key:String in ["elapsed","duration","blocked_seconds"]:
		if intent.has(key) and (not _number(intent[key]) or float(intent[key])<0):return _failure("INVALID_INTENT_SCHEMA","活动时间无效")
	if owner=="runtime":
		if kind not in ["eat","drink","medicine","rest","sleep","legacy_dispatch"]:return _failure("UNSUPPORTED_INTENT","未知生活活动；原存档保留")
		if intent.has("item_id") and (not intent.item_id is String or Content.consumable_definition(str(intent.item_id),kind).is_empty()):return _failure("INVALID_INTENT_ITEM","生活活动引用了不可食用或类型不符的物品")
		if not Data.valid_id(intent.get("id")) or not _number(intent.get("elapsed")) or not _number(intent.get("duration")) or float(intent.duration)<0 or float(intent.elapsed)<0 or float(intent.elapsed)>float(intent.duration)+STEP+0.00001:return _failure("INVALID_INTENT_SCHEMA","生活活动身份或进度无效")
		if kind=="legacy_dispatch" and (not intent.get("resume") is Dictionary or not LegacyIntents.valid(intent.resume.get("legacy",{}))):return _failure("INVALID_INTENT_SCHEMA","旧活动接续描述无效")
		if kind=="sleep" and (not intent.get("legacy_v5",false) or not Data.valid_id(intent.get("target_id"))):return _failure("INVALID_INTENT_SCHEMA","睡眠仅允许经过验证的旧档迁移活动")
		if intent.get("legacy_v5",false) and not Data.vec(intent.get("legacy_destination")):return _failure("INVALID_INTENT_SCHEMA","旧活动使用点无效")
		if intent.has("use_location") and not Data.vec(intent.use_location):return _failure("INVALID_INTENT_SCHEMA","生活活动使用点无效")
		return _success()
	var domain:Variant=_services.get(owner)
	if domain==null or not domain.has_method("validate_intent"):return _failure("MISSING_INTENT_VALIDATOR","活动所属领域尚未装配格式校验")
	return domain.validate_intent(intent.duplicate(true),actor_state.duplicate(true),facts_state)

func validate_intents(observed:Dictionary)->Dictionary:
	for a:Dictionary in observed.get("actors",[]):
		var intent:Variant=a.get("intent")
		if intent==null:continue
		if not intent is Dictionary:return _failure("INVALID_INTENT_SCHEMA","活动描述必须为对象")
		var result:Dictionary=validate_intent(intent,a,observed)
		if not result.ok:
			result=result.duplicate(true);result.actor_id=a.id;return result
	return _success()

func configure(context: Dictionary) -> Dictionary:
	var locked:Dictionary=Content.validate_lock(context.get("content",{}))
	if not locked.ok:return locked
	var simulation:Variant=context.get("simulation",{})
	if not simulation is Dictionary or not _number(simulation.get("remainder",0)) or float(simulation.get("remainder",0))<0:return _failure("INVALID_SIMULATION_STATE","模拟积压状态无效，原存档保留")
	var content_check:Dictionary=Content.validate_catalog(context.get("definitions",{}))
	if not content_check.ok:return content_check
	_context = context
	_ui_read_epoch+=1
	world = context.get("world")
	if world == null:
		return _failure("MISSING_WORLD", "世界模块尚未装配")
	_services = context.get("services", {})
	var incoming: Dictionary = context.get("facts", {})
	var validation: Dictionary = validate_facts(incoming)
	if not validation.ok:
		return validation
	for actor:Dictionary in incoming.actors:
		var intent:Variant=actor.get("intent")
		if intent is Dictionary and intent.get("owner") not in FactoryContracts.INTENT_OWNERS:
			return _failure("UNSUPPORTED_INTENT","活动没有已接入的运行时归属；请使用旧档转换，原存档保留")
	_facts = incoming.duplicate(true)
	_checked_stocks = _facts.stocks
	_facts.actors=ActorProfiles.normalize_legacy(_facts.actors)
	for a:Dictionary in _facts.actors:
		_normalize_actor_compat(a)
		if not ActorProfiles.valid(a):return _failure("INVALID_ACTOR_PROFILE","角色引用了尚未装配的外观或身体定义")
	_source = context.get("source", {}).duplicate(true)
	_content_lock=Content.content_lock()
	_revision = int(context.get("command_revision", 0))
	_receipts = context.get("receipts",{}).duplicate(true)
	_remainder=float(simulation.get("remainder",0))
	_render_visibility_key.clear();_render_visible.clear()
	_movement_used.clear();_movement_recent.clear();_recovery_motion.clear()
	var shared: Dictionary = context.duplicate()
	shared.merge({"world":world,"actor":actor,"stock":stock,"tool":tool,"facts":facts,"draft_snapshot":_draft_facts_snapshot,"clock":clock,"definitions":context.get("definitions",{}),"spatial":_services.get("buildings"),"runtime":self},true)
	for service: Variant in _services.values():
		if service != null and service.has_method("configure"):
			service.configure(shared)
	var intent_check:Dictionary=validate_intents(_facts)
	return validate_factory_extensions(_facts) if intent_check.ok else intent_check

func validate_factory_extensions(observed:Dictionary,world_changes:Array=[])->Dictionary:
	# JSON validity alone cannot authorize a batch/task/reference graph.
	# Ask each real domain owner; never reconstruct its private rules here.
	var overrides:Dictionary={}
	var owners:Dictionary={}
	var version_fields:Array[String]=["version"]
	var selective_read:bool=world.has_method("extension_fields")
	var validation_started:int=Time.get_ticks_usec()
	for change:Dictionary in world_changes:
		if change.get("op")!="extension.set" or not str(change.get("id","")).begins_with("r34:"):continue
		var id:String=str(change.id)
		if not FactoryContracts.EXTENSION_OWNERS.has(id):return _failure("UNSUPPORTED_FACTORY_EXTENSION","新生产状态没有已接入归属："+id)
		overrides[id]=change.get("after")
	for id:String in FactoryContracts.EXTENSION_OWNERS:
		if not overrides.has(id) and not world.has_extension(id):continue
		# Only the envelope version is needed here. The same domain owners
		# below still validate every complete current/proposed state and facts.
		var state:Variant=overrides[id] if overrides.has(id) else (world.extension_fields(id,version_fields) if selective_read else world.extension(id))
		if not state is Dictionary or not Data.integer(state.get("version")) or int(state.version)!=1:return _failure("INVALID_FACTORY_STATE","新生产状态版本无效："+id)
		owners[FactoryContracts.EXTENSION_OWNERS[id]]=true
	_cost_phase("factory_extension_views",validation_started)
	for owner:String in owners:
		var provider:Variant=_services.get(owner)
		if provider==null or not provider.has_method("validate_extensions"):return _failure("MISSING_FACTORY_VALIDATOR","新生产状态所属校验未装配："+owner)
		validation_started=Time.get_ticks_usec()
		var result:Variant=provider.validate_extensions(observed,overrides)
		_cost_phase("factory_validator."+owner,validation_started)
		if not result is Dictionary or not result.get("ok") is bool:return _failure("INVALID_FACTORY_VALIDATOR","新生产状态校验返回无效："+owner)
		if not result.ok:return result.duplicate(true)
	return _success()

func clock() -> float:
	return float(_facts.get("time", 0.0))
func region_is_detailed(region_id:String)->bool:
	if _retired or world==null:return false
	if _facts.get("scenario")!=FactoryContracts.SCENARIO:return not world.region(region_id).is_empty()
	if not world.has_method("region_is_resident"):return false
	# Native WorldState already maintains the exact residency memo at chunk and
	# region commits and invalidates it on reload. Avoid a second map and a
	# revision/token allocation on every actor, interest, and contact query.
	if world.get_script() == preload("res://scripts/world/world_state.gd"):
		return world.region_is_resident(region_id)
	# World mutations replace state and increment revision. Same-revision
	# snapshot loads increment generation. Validate BOTH before reusing this
	# metadata-only read; time, actors and renderers never establish residency.
	if world.has_method("extension_token"):
		var token:Dictionary=world.extension_token("")
		var basis:Array=[world.get_instance_id(),world.get_revision(),token.get("generation",-1)]
		if basis!=_detailed_read_basis:
			_detailed_read_basis=basis;_detailed_read_regions.clear()
		if not _detailed_read_regions.has(region_id):_detailed_read_regions[region_id]=world.region_is_resident(region_id)
		return _detailed_read_regions[region_id]
	# Foreign/offline views retain the original synchronous-step bound.
	if not _detailed_step_scope:return world.region_is_resident(region_id)
	var current:int=world.get_revision()
	if current!=_detailed_step_revision:
		_detailed_step_regions.clear();_detailed_step_revision=current
	if not _detailed_step_regions.has(region_id):_detailed_step_regions[region_id]=world.region_is_resident(region_id)
	return _detailed_step_regions[region_id]
func facts() -> Dictionary:
	return _facts.duplicate(true)

func _draft_facts_snapshot()->Dictionary:
	# Trusted synchronous domain preparation may share an immutable constructor
	# snapshot. It is detached from authority; Draft forks before writable API
	# access. Outside the fixed-step scope retain independent constructor copies.
	if not _detailed_step_scope:return facts()
	if _draft_read_snapshot.is_empty():_draft_read_snapshot=facts()
	return _draft_read_snapshot
func stock_states()->Array:
	# Independent stock read model: never clone actors, quests or ledgers.
	return _facts.get("stocks",[]).duplicate(true)

func expedition_in_combat() -> bool:
	var gameplay: Variant = _services.get("gameplay")
	return gameplay != null and gameplay.expedition_in_combat()

func night_phase() -> String:
	var fields: Array[String] = ["phase"]
	return str(world.extension_fields("village:night-defense", fields).get("phase", "")) if world != null else ""

func set_night_screen_test(test: Callable) -> void:
	var gameplay: Variant = _services.get("gameplay")
	if gameplay != null: gameplay.night_screen_test = test

func expedition_snapshot() -> Dictionary:
	var gameplay: Variant = _services.get("gameplay")
	return gameplay.expedition_snapshot() if gameplay != null else {}

func chapter_stock_snapshot()->Dictionary:
	if _retired or world==null:return {"available":false,"rows":[]}
	return ChapterStock.read(world,actor("player"),_facts.get("stocks",[]),_facts.get("actors",[]),_services.get("production"))
func scenario()->String:
	return str(_facts.get("scenario",""))
func actor_states()->Array:
	# Residency needs bodies/routes, never every stock, quest and ledger row.
	return _facts.get("actors",[]).duplicate(true)
func active_positions()->Array:
	var result:Array=[]
	for a:Dictionary in _facts.get("actors",[]):
		if float(a.hp)>0 and region_is_detailed(str(a.regionId)):result.append(Vector3(a.x,a.y,a.z))
	return result
func bind_readiness(provider:Callable)->void:
	_readiness_provider=provider
func spatial_readiness(request:Dictionary={})->Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	if not _readiness_provider.is_valid():return {"ok":true,"ready":true}
	return _readiness_provider.call(request)
func actor(id: String) -> Dictionary:
	return _find("actors", id).duplicate(true)
func movement_budget(actor_id:String,dt:float,requested_mode:String="walk")->Dictionary:
	var used:Dictionary=_movement_used.get(actor_id,{})
	var elapsed:float=float(used.get("elapsed",0)) if int(used.get("tick",-1))==_movement_tick() else 0.0
	var result:Dictionary=Movement.budget(_find("actors",actor_id),dt,requested_mode,elapsed)
	if _paused or _facts.get("status")!="playing":
		result.ok=false;result.code="PAUSED";result.reason="世界已暂停";result.max_distance=0.0
	return result
func _movement_tick()->int:
	return int(round(clock()/STEP))
func _movement_display()->Dictionary:
	var result:Dictionary={}
	for a:Dictionary in _facts.get("actors",[]):
		var budget:Dictionary=movement_budget(str(a.id),STEP,"run")
		var last:Dictionary=_movement_recent.get(str(a.id),{})
		var moving:bool=not _paused and not last.is_empty() and clock()-float(last.get("time",-1))<0.15
		result[a.id]={"moving":moving,"mode":last.get("mode","walk") if moving else "idle","speed":last.get("speed",0.0) if moving else 0.0,"stamina_max":budget.stamina_max,"can_run":budget.can_run,"reason":budget.reason}
	return result
func _update_render_visible(actors: Array) -> void:
	var player:Dictionary=_find("actors","player")
	var positions:Array=[]
	for a:Dictionary in actors:positions.append([a.id,a.regionId,a.x,a.y,a.z,a.get("buildingId"),a.get("storeyId")])
	var key: Array = [world.get_revision(), positions]
	if key!=_render_visibility_key:
		_render_visibility_key=key;_render_visible=["player"]
		var building:Variant=_services.get("buildings")
		if building!=null and not player.is_empty():
			var query:RefCounted=building.current_space()
			for a:Dictionary in actors:
				if a.id=="player":continue
				if a.regionId!=player.regionId and not _continuous_near(player,a,180.0):continue
				if a.get("buildingId")!=null and a.get("buildingId")==player.get("buildingId") and a.get("storeyId")!=player.get("storeyId"):continue
				# Cutaway geometry never grants actor information. Use B's real
				# sight geometry including the ACTUAL door leaf, not render caps.
				var expedition_outdoors: bool = (a.get("expedition_follow",false) or a.get("expedition_enemy",false)) and a.regionId == player.regionId and a.get("buildingId") == null and player.get("buildingId") == null
				var same_outdoor_region:bool=a.regionId==player.regionId and a.get("buildingId")==null and player.get("buildingId")==null
				var known_companion:bool=same_outdoor_region and a.get("relationship",{}).get("member",false) and a.get("relationship",{}).get("consent",false)
				# In the village the raised camera can see the worker while a low
				# player-to-worker ray clips a fence, log pile or doorway edge.
				if known_companion or expedition_outdoors or query.line_clear(_location(player),_location(a),str(a.id)):_render_visible.append(a.id)

func actor_pick_snapshot() -> Dictionary:
	# Target picking needs the same current LOS and detached actor records.
	# Animation, held-item formatting and work progress belong to the view.
	var actors: Array = _facts.get("actors", [])
	_update_render_visible(actors)
	return {"actors": actors.duplicate(true), "visible_actor_ids": _render_visible.duplicate()}

func actor_presentation() -> Dictionary:
	var actors: Array = _facts.get("actors", [])
	_update_render_visible(actors)
	var work:Dictionary={}
	for a:Dictionary in actors:
		if _render_visible.has(a.id):work[a.id]=_actor_work_projection(a)
	return {"actors":actors.duplicate(true),"hand":_hand.duplicate(true),"visible_actor_ids":_render_visible.duplicate(),"movement":_movement_display(),"work":work}

func _actor_work_projection(a:Dictionary)->Dictionary:
	var intent:Variant=a.get("intent")
	if not intent is Dictionary:return {}
	var owner:String=str(intent.get("owner",""))
	var service:Variant=_services.get(owner)
	if service==null or not service.has_method("actor_work_projection"):return {}
	var basis:Array=[Engine.get_process_frames(),world.get_instance_id(),world.get_revision(),_revision,clock(),_paused,world.extension_token("") if world.has_method("extension_token") else {}]
	if basis!=_actor_work_basis:_actor_work_basis=basis;_actor_work_cache.clear()
	var cached:Dictionary=_actor_work_cache.get(str(a.get("id","")),{})
	if cached.get("provider")==service.get_instance_id() and cached.get("actor")==a:return cached.value.duplicate(true)
	var value:Variant=service.actor_work_projection(str(a.id))
	if not value is Dictionary or value.is_empty():return {}
	if value.get("owner")!=owner or not value.get("kind") is String or not value.get("effective_work") is bool or not value.get("paused_reason","") is String:return {}
	for field:String in ["progress_seconds","duration_seconds"]:
		var amount:Variant=value.get(field)
		if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount)<0:return {}
	if float(value.duration_seconds)<=0 or float(value.progress_seconds)>float(value.duration_seconds)+0.000001:return {}
	var result:Dictionary=value.duplicate(true)
	if _paused or not region_is_detailed(str(a.regionId)):
		result.effective_work=false;result.paused_reason="paused" if _paused else "region_paused"
	_actor_work_cache[str(a.id)]={"provider":service.get_instance_id(),"actor":a.duplicate(true),"value":result.duplicate(true)}
	return result

func actor_work_snapshot(actor_id:String="player")->Dictionary:
	return {} if _retired else _actor_work_projection(actor(actor_id))
func stock(id: String) -> Dictionary:
	if id.begins_with("pack:"):
		var a: Dictionary = _find("actors", id.trim_prefix("pack:"))
		if a.is_empty(): return {}
		return {"id":id,"items":a.get("pack",{}).duplicate(true),"location":_location(a),"searched":true,"owner":a.id}
	return _find("stocks", id).duplicate(true)
func tool(id: String) -> Dictionary:
	var production: Variant = world.extension("r3:production") if world.has_method("extension") else null
	if production is Dictionary:
		for entry: Dictionary in production.get("tools", []):
			if str(entry.get("id")) == id: return entry.duplicate(true)
	return {}
func get_revision() -> int:
	return _revision
func set_paused(value: bool) -> void:
	_paused = value
	# Pause/focus never adds wall time and never destroys pre-pause debt.
	if value:_movement_recent.clear();_recovery_motion.clear()
func is_paused() -> bool:
	return _paused

func commit_storage_projection(change:Dictionary)->Dictionary:
	# One synchronous authority transaction, with no await/input dispatch.
	# Reject reentrant commands during publication, but do not turn paging
	# into an actual lifecycle pause: that clears motion/held-input state.
	if _storage_barrier or not change.get("world_changes") is Array or change.world_changes.is_empty() or not change.world_changes.all(func(op:Dictionary)->bool:return op.get("op") in ["chunk.storage","chunk.residency"]) or not change.get("fact_changes",[]).is_empty():
		return _failure("INVALID_STORAGE_BARRIER","地形存储事务无效")
	var was_paused:bool=_paused
	_storage_barrier=true
	_paused=true
	var result:Dictionary=_commit(change)
	_paused=was_paused
	_storage_barrier=false
	return result
func is_retired()->bool:
	return _retired
func retire()->void:
	_retired=true;set_paused(true)
func set_target(value: Dictionary) -> void:
	_target = value.duplicate(true)
func set_hand(value: Dictionary) -> void:
	_hand = value.duplicate(true)

func _request_gate(request:Dictionary)->Dictionary:
	if _storage_barrier:return _failure("STORAGE_BARRIER","地形数据正在原子提交")
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换，请重新获取当前操作")
	var schema:Dictionary=_request_schema(request)
	if not schema.ok:return schema
	var loading:Dictionary=_context.get("save_state",{})
	if loading.get("busy",false) and loading.get("status") in ["generating","loading"]:return _failure("NOT_READY","世界切换尚未就绪，请等待完成")
	if _context.get("stream_state",{}).get("busy",false):return _failure("NOT_READY","正在保存远区或恢复地形，请稍候")
	# Reading/acknowledging an existing risk is not a physical action and must
	# remain possible when the player is incapacitated or a modal is open.
	if str(request.kind).begins_with("alerts."):
		return _success() if str(request.get("actor_id","player"))=="player" and not _find("actors","player").is_empty() else _failure("FORBIDDEN","只有当前玩家可以确认告警")
	var a: Dictionary = _find("actors", str(request.get("actor_id","player")))
	if a.is_empty() or float(a.get("hp",0)) <= 0 or _facts.get("status") != "playing":
		return _failure("ACTOR_UNAVAILABLE", "角色无法行动")
	var kind: String = str(request.get("kind",""))
	if kind=="cancel":return _success()
	var spatial:Dictionary=spatial_readiness(request)
	if not spatial.get("ready",false):return spatial
	if kind=="terrain" and _facts.get("scenario")==FactoryContracts.SCENARIO:
		var workforce:Variant=_services.get("workforce")
		if workforce!=null and workforce.has_method("site_work_permission"):
			var site:Variant=workforce.site_work_permission(request.duplicate(true))
			if not site is Dictionary or not site.get("ok",false):return site if site is Dictionary else _failure("INVALID_SITE_PERMISSION","地区作业校验尚未就绪")
	return _success()

func availability(request: Dictionary) -> Dictionary:
	var gate:Dictionary=_request_gate(request)
	if not gate.ok:return gate
	var a:Dictionary=_find("actors",str(request.get("actor_id","player")))
	var kind:String=str(request.kind)
	if kind in ["held","cancel"] and a.get("intent") is Dictionary and a.intent.get("owner")=="zonework":
		var zonework:Variant=_services.get("zonework")
		if zonework==null or not zonework.has_method("prepare_actor_control"):return _failure("ZONE_WORK_UNAVAILABLE","区域作业控制尚未接通")
		var controlled:Dictionary=zonework.prepare_actor_control(request.duplicate(true))
		if controlled.get("ok",false):controlled.world_changes=[];controlled.fact_changes=[]
		return controlled
	if kind=="held" and a.get("intent") is Dictionary and a.intent.get("owner")=="modules":
		var modules:Variant=_services.get("modules")
		if modules==null or not modules.has_method("prepare_actor_control"):return _failure("UNAVAILABLE","模块作业控制尚未接入")
		var result:Dictionary=modules.prepare_actor_control(request.duplicate(true))
		if result.get("ok",false):result.world_changes=[];result.fact_changes=[]
		return result
	if kind=="cancel":return _success()
	if kind in ["eat","drink","medicine","rest","talk","help","invite","consent","job"]:
		return life_availability(request, a)
	var service: Variant = _service_for(kind,str(a.id))
	if service == null or not service.has_method("availability"):
		return _failure("UNAVAILABLE", "该动作尚未接入")
	return service.availability(request.duplicate(true))

func command(request: Dictionary) -> Dictionary:
	var schema:Dictionary=_request_schema(request)
	if not schema.ok:return schema
	if not Data.valid_id(request.get("command_id")):return _failure("INVALID_COMMAND", "命令缺少唯一标识")
	var id: String = request.command_id
	if _receipts.has(id): return _receipts[id].duplicate(true)
	if request.has("expected_revision") and int(request.expected_revision) != _revision:
		return _failure("STALE_REVISION", "现场已经变化，请重新确认")
	# Domain prepare is the complete, pure authority preflight. Calling its
	# availability wrapper first repeats the same preparation (and cold door
	# sweep/support/exit checks) without adding any authority or safety.
	var ready: Dictionary = _request_gate(request)
	if not ready.get("ok",false): return ready
	var a: Dictionary = _find("actors", str(request.get("actor_id","player")))
	var kind: String = str(request.kind)
	if kind=="direct_move" and _use_idle_direct_move and a.id=="player":
		var motion:=_try_idle_direct_move(request,a)
		if not motion.is_empty():return _remember_command(id,motion)
	var prepared: Dictionary
	if kind in ["cancel","held"] and a.get("intent") is Dictionary and a.intent.get("owner")=="zonework":
		var zonework:Variant=_services.get("zonework")
		if zonework==null or not zonework.has_method("prepare_actor_control"):return _failure("ZONE_WORK_UNAVAILABLE","区域作业控制尚未接通")
		prepared=zonework.prepare_actor_control(request.duplicate(true))
	elif kind in ["cancel","held"] and a.get("intent") is Dictionary and a.intent.get("owner")=="modules":
		var modules:Variant=_services.get("modules")
		if modules==null or not modules.has_method("prepare_actor_control"):return _failure("UNAVAILABLE","模块作业控制尚未接入")
		prepared=modules.prepare_actor_control(request.duplicate(true))
	elif kind=="cancel" and _services.has("actions"):
		var cancel_request:=request.duplicate(true);cancel_request.kind="cancel_work"
		prepared=_services.actions.prepare(cancel_request)
	elif kind in ["eat","drink","medicine","rest","talk","help","invite","consent","job"]:
		prepared = prepare_life(request,a)
	else:
		var service:Variant=_service_for(kind,str(a.id))
		if service==null or not service.has_method("prepare"):return _failure("UNAVAILABLE","该动作尚未接入")
		prepared = service.prepare(request.duplicate(true))
	if not prepared.get("ok",false): return prepared
	if kind in ["cancel","move","direct_move"]:
		for change:Dictionary in prepared.get("fact_changes",[]):
			if change.get("collection")=="actors" and change.get("id")==a.id and change.get("after") is Dictionary:change.after.erase("migration_resume")
	return _remember_command(id,_commit(prepared))

func _remember_command(id:String,receipt:Dictionary)->Dictionary:
	if receipt.ok:
		receipt.command_id = id
		_receipts[id] = receipt.duplicate(true)
		if _receipts.size() > 512: _receipts.erase(_receipts.keys()[0])
	return receipt

func _try_idle_direct_move(request:Dictionary,before:Dictionary)->Dictionary:
	var service:Variant=_services.get("actions")
	if service==null or not service.has_method("prepare_idle_direct_move"):return {}
	var started:int=Time.get_ticks_usec()
	var base_revision:int=_revision
	var world_revision:int=world.get_revision()
	var plan:Dictionary=service.prepare_idle_direct_move(request,before.duplicate(true))
	if plan.is_empty() or not plan.ok:return plan
	if _revision!=base_revision or world.get_revision()!=world_revision:return {}
	var to:Dictionary=plan.location
	# Transitions can affect intent, residency and dependent domains.
	for key:String in ["regionId","buildingId","storeyId"]:
		if to.get(key)!=before.get(key):return {}
	if not Data.vec(to) or before.has("position") or before.get("intent")!=null:return {}
	if not ActorProfiles.valid(before) or not before.get("skills") is Dictionary or not before.get("relationship") is Dictionary:return {}
	var distance:=Vector2(float(to.x)-float(before.x),float(to.z)-float(before.z)).length()
	if distance<=0.000001:return {}
	var after:=before.duplicate(true)
	for key:String in ["x","y","z"]:after[key]=to[key]
	for key:String in ["regionId","buildingId","storeyId"]:after[key]=to.get(key)
	after.intent=null;after.activity="自由行动"
	var event:Dictionary={"kind":"actor-moved","actor_id":before.id,"mode":plan.budget.mode,"elapsed":distance/float(plan.budget.speed)}
	var motion:=_prepare_movement({"actors":[after]},[event])
	if not motion.ok:return motion
	var standing:=_validate_changed_actor_standing({"actors":[after]},_services.get("buildings"))
	if not standing.ok:return standing
	var actors:Array=_facts.actors.duplicate()
	var slot:int=actors.find(before)
	if slot<0:return {}
	actors[slot]=after
	var next:=_facts.duplicate()
	next.actors=actors;next.ledger=_facts.get("ledger",[]).duplicate()
	_facts=next;_draft_read_snapshot={}
	_publish_movement_budget(motion)
	_revision+=1
	var changes:Dictionary={"world":[],"facts":[{"collection":"actors","id":before.id,"before":before.duplicate(true),"after":after.duplicate(true)}],"events":[event],"revision":_revision,"actor_transitions":[]}
	_record_events(changes.events)
	var publish_started:int=Time.get_ticks_usec()
	changed.emit(changes)
	_cost_phase("idle_direct_move_publish",publish_started)
	_cost_phase("idle_direct_move",started)
	return _success({"changes":changes})

func _service_for(kind: String,actor_id: String="player") -> Variant:
	var factory_domain:String=FactoryContracts.service_for(kind)
	if not factory_domain.is_empty():return _services.get(factory_domain)
	var active: Variant=_find("actors",actor_id).get("intent")
	if kind == "terrain" or (kind=="held" and active is Dictionary and active.get("owner")=="terrain"): return _services.get("terrain")
	if kind.begins_with("explore") or kind.begins_with("night.") or kind.begins_with("expedition.") or kind in ["attack","radio","defend"]: return _services.get("gameplay")
	# B action_service orchestrates arrival, labor and domain completion; it owns no clock.
	return _services.get("actions")

func _commit(prepared: Dictionary) -> Dictionary:
	var started:int=Time.get_ticks_usec()
	var result:Dictionary=_commit_impl(prepared)
	var elapsed:int=Time.get_ticks_usec()-started
	_authority_costs.count+=1;_authority_costs.total_usec+=elapsed
	_authority_costs.max_usec=maxi(int(_authority_costs.max_usec),elapsed)
	if not result.ok:_authority_costs.failed+=1
	return result

func _commit_impl(prepared: Dictionary) -> Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换，陈旧事务未提交")
	var phase_started:int=Time.get_ticks_usec()
	var fact_changes: Array = prepared.get("fact_changes", []).duplicate(true)
	# Runtime owns these stock records. Movement/needs never mutate them and
	# stock replacements go through the same collection name and CAS below.
	var unchanged_stocks:bool=is_same(_facts.get("stocks"),_checked_stocks) and not fact_changes.any(func(change:Dictionary)->bool:return str(change.get("collection",""))=="stocks")
	var staged: Dictionary = _facts.duplicate(false)
	for key:Variant in _facts:
		var value:Variant=_facts[key]
		if key=="stocks" and unchanged_stocks:
			# Stock records are replaced through CAS. Lifecycle release plans
			# detach this collection before applying any additional changes.
			continue
		if key=="ledger" and value is Array and not fact_changes.any(func(c:Dictionary)->bool:return c.get("collection")=="ledger"):
			# Existing events are read-only during authority validation. The
			# new list owns its appends/trimming; explicit ledger edits get a deep fork.
			staged[key]=value.duplicate(false)
		elif value is Array or value is Dictionary:
			staged[key]=value.duplicate(true)
	_cost_phase("facts_clone",phase_started);phase_started=Time.get_ticks_usec()
	var detail_started:int=Time.get_ticks_usec()
	var applied:Dictionary=_apply_fact_changes(staged,fact_changes)
	if not applied.ok:return applied
	var basic:Dictionary=_validate_fact_schema(staged,unchanged_stocks)
	if not basic.ok:return basic
	_cost_phase("facts_basic",detail_started);detail_started=Time.get_ticks_usec()
	var release:Dictionary=_prepare_actor_releases(staged,prepared.get("world_changes",[]))
	if not release.ok:return release
	staged=release.facts
	_cost_phase("actor_releases",detail_started);detail_started=Time.get_ticks_usec()
	if not release.transitions.is_empty():fact_changes=facts_diff(_facts,staged)
	var events:Array=prepared.get("events",[]).duplicate(true)
	events.append_array(release.events)
	var motion:Dictionary=_prepare_movement(staged,events)
	if not motion.ok:return motion
	_cost_phase("movement_preparation",detail_started);detail_started=Time.get_ticks_usec()
	if not release.transitions.is_empty():
		var valid: Dictionary = validate_facts(staged)
		if not valid.ok: return valid
	# Old captures are normalized during offscreen configure. A new ordinary
	# actor without an explicit profile gets a stable ID-based current default.
	for a:Dictionary in staged.actors:
		_normalize_actor_compat(a)
		if not a.has("appearance_id"):a.appearance_id=ActorProfiles.INFECTED if a.get("faction")=="infected" else ActorProfiles.for_new_actor(str(a.id))
		if not a.has("body_profile_id"):a.body_profile_id=ActorProfiles.BODY_ID
		if not ActorProfiles.valid(a):return _failure("INVALID_ACTOR_PROFILE","角色引用了尚未装配的外观或身体定义")
	_cost_phase("actor_profiles",detail_started);detail_started=Time.get_ticks_usec()
	var intent_validation:Dictionary=validate_intents(staged)
	if not intent_validation.ok:return intent_validation
	_cost_phase("intent_validation",detail_started)
	var factory_validation:Dictionary=validate_factory_extensions(staged,release.world_changes)
	if not factory_validation.ok:return factory_validation
	_cost_phase("facts_validate_release_movement",phase_started)
	var world_changes: Array = release.world_changes
	var draft: Dictionary = {"view":world,"capability":null}
	var building: Variant = _services.get("buildings")
	if world_changes.is_empty():
		# A provider's successful movement preparation is not permission to
		# publish an impossible final pose. Validate only newly living/moved
		# bodies here; world edits use the full draft safety below instead.
		phase_started=Time.get_ticks_usec()
		var standing:Dictionary=_validate_changed_actor_standing(staged,building)
		_cost_phase("final_actor_standing",phase_started)
		if not standing.ok:return standing
	if not world_changes.is_empty():
		phase_started=Time.get_ticks_usec()
		# Display read-state cannot change any input read by B's full validator.
		# Keep every factory owner/CAS/JSON check and the same capability commit;
		# only avoid exporting an otherwise unused detached copy of the whole world.
		var display_only:bool=fact_changes.is_empty() and events.is_empty() and release.transitions.is_empty() and release.events.is_empty() and world_changes.all(func(c:Dictionary)->bool:return c.get("op")=="extension.set" and c.get("id")=="r34:display")
		# Keep the public two-argument protocol for injected or instrumented
		# world implementations. The native owner uses the smaller receipt.
		var native_world: bool = world.get_script() != null and world.get_script().resource_path == "res://scripts/world/world_state.gd"
		if native_world:
			draft = world.prepare_runtime_changes(world_changes, world.get_revision(), not display_only)
		elif display_only:
			draft = world.prepare_changes_without_view(world_changes, world.get_revision())
		else:
			draft = world.prepare_changes(world_changes, world.get_revision())
		_cost_phase("world_prepare",phase_started)
		if not draft.get("ok",false): return draft
		var validation_world:RefCounted=world if display_only else draft.view
		if building == null or not building.has_method("validate_world_draft"):
			world.discard_prepared(draft.capability)
			return _failure("MISSING_SPATIAL_VALIDATOR", "空间安全验证尚未装配")
		phase_started=Time.get_ticks_usec()
		var safety: Dictionary = building.validate_world_draft(validation_world,staged,world_changes)
		_cost_phase("final_spatial_validation",phase_started)
		if not safety.get("ok",false):
			# Only spatial rejections have passed domain/schema validation. An
			# invalid definition/version must never be projected into a Space.
			# Preserve its original failure instead of failing in diagnostics.
			safety=safety.duplicate(true)
			if safety.get("code")=="SPATIAL_REJECTED":
				safety.spatial_diagnostic=_spatial_rejection_context(building,validation_world,staged)
			world.discard_prepared(draft.capability)
			return safety
		phase_started=Time.get_ticks_usec()
		var committed: Dictionary = world.commit_runtime_changes(draft.capability) if native_world else world.commit_prepared(draft.capability)
		_cost_phase("world_commit",phase_started)
		if not committed.get("ok",false): return committed
	# No callbacks or fallible operations between the two authoritative reference swaps.
	phase_started=Time.get_ticks_usec()
	_facts = staged
	_checked_stocks = staged.stocks
	_draft_read_snapshot={}
	for transition:Dictionary in release.transitions:
		_movement_used.erase(transition.actor_id);_movement_recent.erase(transition.actor_id);_recovery_motion.erase(transition.actor_id)
	_publish_movement_budget(motion)
	_revision += 1
	if world_changes.any(func(c:Dictionary)->bool:return str(c.get("op","")).begins_with("entity.") or c.get("id") in ["r3:structures","r3:production"]) or fact_changes.any(func(c:Dictionary)->bool:return c.get("collection")=="stocks"):_work_revision=-1
	var changes: Dictionary = {"world":world_changes.duplicate(true),"facts":fact_changes.duplicate(true),"events":events,"revision":_revision,"actor_transitions":release.transitions.duplicate(true)}
	for change:Dictionary in changes.facts:
		if change.get("collection")=="actors" and change.get("after") is Dictionary:change.after=_find("actors",str(change.id)).duplicate(true)
	_record_events(changes.events)
	changed.emit(changes)
	_cost_phase("publish_and_views",phase_started)
	return _success({"changes":changes})

func _publish_movement_budget(motion:Dictionary)->void:
	for entry:Dictionary in motion.get("movements",[]):
		var previous:Dictionary=_movement_used.get(entry.actor_id,{})
		var used:float=float(previous.get("elapsed",0)) if int(previous.get("tick",-1))==_movement_tick() else 0.0
		_movement_used[entry.actor_id]={"tick":_movement_tick(),"elapsed":used+float(entry.elapsed)}
		_movement_recent[entry.actor_id]={"time":clock(),"mode":entry.mode,"speed":entry.speed}
		if _recovery_motion.get(entry.actor_id)!="run":_recovery_motion[entry.actor_id]=entry.mode

func _validate_changed_actor_standing(staged:Dictionary,building:Variant)->Dictionary:
	var query:RefCounted
	for after:Dictionary in staged.get("actors",[]):
		if float(after.get("hp",0))<=0:continue
		var before:Dictionary=_find("actors",str(after.id))
		if not before.is_empty() and float(before.get("hp",0))>0 and _location(before)==_location(after) and before.get("body_profile_id")==after.get("body_profile_id"):continue
		if building==null or not building.has_method("current_space"):return _failure("MISSING_SPATIAL_VALIDATOR","人物站位校验尚未装配")
		if query==null:query=building.current_space()
		var p:Dictionary=_location(after)
		var feet:Dictionary=query.standing_point(p)
		if feet.is_empty() or Vector3(float(feet.x)-float(p.x),float(feet.y)-float(p.y),float(feet.z)-float(p.z)).length()>0.025:
			return _failure("SPATIAL_REJECTED","人物脚下支撑或身体净空失效："+str(after.id))
	return _success()

func _apply_fact_changes(staged:Dictionary,fact_changes:Array)->Dictionary:
	for change: Dictionary in fact_changes:
		var collection: String = str(change.get("collection",""))
		if not staged.get(collection) is Array: return _failure("INVALID_FACT_CHANGE", "事实集合无效")
		var entries: Array = staged[collection]
		var index: int = -1
		for i: int in range(entries.size()):
			if str(entries[i].get("id","")) == str(change.get("id","")): index=i;break
		var before: Variant = entries[index] if index >= 0 else null
		if before != change.get("before"): return _failure("CAS_MISMATCH", "事实已变化，未扣除材料")
		var after: Variant = change.get("after")
		if after == null:
			if index >= 0: entries.remove_at(index)
		elif not after is Dictionary or str(after.get("id","")) != str(change.get("id","")):
			return _failure("INVALID_FACT_CHANGE", "事实身份无效")
		elif index < 0: entries.append(after.duplicate(true))
		else: entries[index] = after.duplicate(true)
	return _success()

func _prepare_actor_releases(staged:Dictionary,pending:Array)->Dictionary:
	var next:Dictionary={}
	for a:Dictionary in staged.actors:next[str(a.id)]=a
	var transitions:Array=[]
	for before:Dictionary in _facts.actors:
		var after:Dictionary=next.get(str(before.id),{})
		var kind:String=""
		if after.is_empty():
			if before.pack.values().any(func(n:Variant)->bool:return float(n)>0):return _failure("ACTOR_INVENTORY_TRANSFER_REQUIRED","先将角色随身物资合法转移，再移除角色")
			kind="removed"
		elif float(before.hp)>0 and float(after.hp)<=0:kind="incapacitated"
		elif before.id!="player" and before.get("relationship",{}).get("member",false) and before.get("relationship",{}).get("consent",false) and (not after.get("relationship",{}).get("member",false) or not after.get("relationship",{}).get("consent",false)):kind="consent_revoked"
		if not kind.is_empty():transitions.append({"actor_id":str(before.id),"kind":kind})
	if transitions.is_empty():return {"ok":true,"facts":staged,"world_changes":pending,"events":[],"transitions":[]}
	if is_same(staged.stocks,_facts.stocks):
		staged.stocks=staged.stocks.duplicate(true)
	var world_changes:Array=pending.duplicate(true)
	var events:Array=[]
	if not transitions.is_empty():
		for domain:String in ["actions","residents","modules","production","workforce","zonework"]:
			var service:Variant=_services.get(domain)
			if service==null:continue
			if domain in ["modules","production","workforce","zonework"] and not _factory_owner_active(domain,world_changes):continue
			if not service.has_method("prepare_actor_release"):return _failure("MISSING_LIFECYCLE_RELEASER","角色生命周期所属领域尚未装配原子清理："+domain)
			var plan:Dictionary=service.prepare_actor_release(transitions.duplicate(true),staged.duplicate(true),world_changes.duplicate(true))
			if not plan.get("ok",false):return plan
			var applied:Dictionary=_apply_fact_changes(staged,plan.get("fact_changes",[]))
			if not applied.ok:return applied
			for change:Dictionary in plan.get("world_changes",[]):
				if change.get("op")!="extension.set":return _failure("INVALID_LIFECYCLE_PLAN","生命周期清理仅能修改所属扩展")
				var found:bool=false
				for index:int in world_changes.size():
					var prior:Dictionary=world_changes[index]
					if prior.get("op")=="extension.set" and prior.get("id")==change.get("id"):
						if prior.get("before_exists")!=change.get("before_exists") or prior.get("before")!=change.get("before"):return _failure("CAS_MISMATCH","角色清理扩展与请求的原事实不一致")
						world_changes[index]=change.duplicate(true);found=true;break
				if not found:world_changes.append(change.duplicate(true))
			events.append_array(plan.get("events",[]))
		for transition:Dictionary in transitions:
			var a:Dictionary=next.get(transition.actor_id,{})
			# Provider changes may replace dictionaries, so resolve the final one.
			for candidate:Dictionary in staged.actors:
				if candidate.id==transition.actor_id:a=candidate;break
			if a.is_empty():continue
			a.intent=null;a.erase("migration_resume")
			a.activity="已失能，行动中断" if transition.kind=="incapacitated" else "已撤回合作，行动中断"
	return {"ok":true,"facts":staged,"world_changes":world_changes,"events":events,"transitions":transitions}

func _factory_owner_active(owner:String,pending:Array=[])->bool:
	for id:String in FactoryContracts.EXTENSION_OWNERS:
		if FactoryContracts.EXTENSION_OWNERS[id]==owner and world.has_extension(id):return true
	for change:Dictionary in pending:
		if change.get("op")=="extension.set" and FactoryContracts.EXTENSION_OWNERS.get(change.get("id"))==owner:return true
	return false

func _prepare_movement(staged:Dictionary,events:Array)->Dictionary:
	var movements:Array=[]
	var seen:Dictionary={}
	for event:Dictionary in events:
		if event.get("kind")!="actor-moved":continue
		var id:String=str(event.get("actor_id",""))
		if seen.has(id):return _failure("INVALID_MOVEMENT","同一事务重复移动记录")
		seen[id]=true
		var before:Dictionary=_find("actors",id);var after:Dictionary={}
		for candidate:Dictionary in staged.actors:
			if candidate.id==id:after=candidate;break
		var elapsed:Variant=event.get("elapsed")
		if before.is_empty() or after.is_empty() or not _number(elapsed) or float(elapsed)<=0 or float(elapsed)>STEP+0.000001:return _failure("INVALID_MOVEMENT","移动事实或时长无效")
		var budget:Dictionary=movement_budget(id,minf(STEP,float(elapsed)),str(event.get("mode","")))
		if not budget.ok:return budget
		var distance:float=Vector2(float(after.x)-float(before.x),float(after.z)-float(before.z)).length()
		if budget.mode!=event.mode or distance>float(budget.max_distance)+0.00001 or distance<=0.000001:return _failure("MOVEMENT_BUDGET","实际位移超过本逻辑帧预算")
		var cost:float=distance*Movement.run_cost(before) if event.mode=="run" and before.get("faction")!="infected" else 0.0
		if cost>float(after.stamina)+0.000001:return _failure("MOVEMENT_BUDGET","实际跑动体力不足")
		after.stamina=maxf(0,float(after.stamina)-cost)
		if before.get("faction")!="infected" and float(after.stamina)<Movement.RUN_MIN_STAMINA:after.run_recovering=true
		movements.append({"actor_id":id,"mode":event.mode,"elapsed":distance/float(budget.speed),"speed":float(budget.speed)})
	return {"ok":true,"movements":movements}

func simulation_budget()->Dictionary:
	return _tick_stats.merged({"policy":"bounded-catch-up-preserve-debt","step_seconds":STEP,"max_steps_per_frame":MAX_STEPS_PER_FRAME,"budget_usec":TICK_BUDGET_USEC,"backlog_seconds":_remainder,"pending_steps":int(floorf((_remainder+0.000001)/STEP))})

var _display_work_frame := -1

func reserve_periodic_display_frame() -> bool:
	var frame := Engine.get_process_frames()
	if _display_work_frame == frame:
		return false
	_display_work_frame = frame
	return true

func tick(delta: float, defer_steps: bool = false) -> void:
	if _retired or _paused or not is_finite(delta) or delta < 0 or _facts.get("status") != "playing": return
	if not is_finite(_remainder+delta):return
	_remainder+=delta
	var started:int=Time.get_ticks_usec();var steps:=0
	# A costly atomic region publication can consume the current frame. Keep
	# its elapsed time on the same clock for the next frame to drain in order.
	while not defer_steps and _remainder+0.000001>=STEP and steps<MAX_STEPS_PER_FRAME:
		if steps>0 and Time.get_ticks_usec()-started>=TICK_BUDGET_USEC:break
		if _facts.get("status")!="playing":break
		var readiness_started:int=Time.get_ticks_usec()
		var readiness:Dictionary=spatial_readiness()
		_simulation_phase("spatial_readiness",readiness_started)
		_tick_stats.waiting_for_geometry=not readiness.get("ready",false)
		if not readiness.get("ready",false):break
		_remainder=maxf(0.0,_remainder-STEP)
		var step_start:int=Time.get_ticks_usec()
		_advance_fixed_step()
		_tick_stats.max_step_usec=maxi(int(_tick_stats.max_step_usec),Time.get_ticks_usec()-step_start)
		steps+=1
	_tick_stats.frames+=1;_tick_stats.steps+=steps;_tick_stats.last_steps=steps
	_tick_stats.last_usec=Time.get_ticks_usec()-started
	_tick_stats.max_backlog=maxf(float(_tick_stats.max_backlog),_remainder)
	if int(_tick_stats.last_usec)>TICK_BUDGET_USEC:_tick_stats.over_budget+=1
	if steps>0:
		var publish_started:int=Time.get_ticks_usec()
		changed.emit({"clock":clock(),"revision":_revision,"simulation":simulation_budget()})
		_simulation_phase("clock_publish_and_views",publish_started)
	if defer_steps or Time.get_ticks_usec() - started >= 4_000:
		_display_work_frame = Engine.get_process_frames()

func _advance_fixed_step()->void:
	var phase_started:int=Time.get_ticks_usec()
	_draft_read_snapshot={}
	_detailed_step_scope=true;_detailed_step_regions.clear();_detailed_step_revision=world.get_revision()
	_facts.time = clock() + STEP
	for a: Dictionary in _facts.actors:
		if not region_is_detailed(str(a.regionId)):continue
		if float(a.hp) <= 0:
			if a.get("intent") is Dictionary and a.intent.get("owner")=="runtime":a.intent=null;a.activity="已失能，生活行动中断"
			continue
		a.hunger=maxf(0,float(a.hunger)-STEP*LIFE.hunger)
		a.thirst=maxf(0,float(a.thirst)-STEP*LIFE.thirst)
		a.fatigue=minf(100,float(a.fatigue)+STEP*LIFE.fatigue)
		a.cooldown=maxf(0,float(a.get("cooldown",0))-STEP)
		if float(a.hunger)<=0 or float(a.thirst)<=0: a.hp=maxf(0,float(a.hp)-0.015)
		var intent: Variant = a.get("intent")
		if intent is Dictionary and intent.get("owner") == "runtime":
			_advance_life(a,STEP)
	_resume_migrations()
	_draft_read_snapshot={}
	_simulation_phase("needs_life_migrations",phase_started)
	# Exactly one call for each owner at the same logical STEP. Old manual
	# labor stays in actions; production.advance owns new autonomous machines.
	# Prepare/commit each domain before the next observes updated facts.
	for domain: String in ["ecology","residents","workforce","actions","zonework","zones","modules","production","terrain","gameplay","display"]:
		var service: Variant = _services.get(domain)
		if service != null and service.has_method("advance"):
			phase_started=Time.get_ticks_usec()
			var plan: Dictionary = service.advance(STEP)
			_simulation_phase(domain+".prepare",phase_started)
			if plan.get("ok",false) and (not plan.get("world_changes",[]).is_empty() or not plan.get("fact_changes",[]).is_empty()):
				phase_started=Time.get_ticks_usec()
				var result:=_commit(plan)
				_simulation_phase(domain+".commit",phase_started)
				if not result.ok:
					print("Afterglow native domain rejection "+JSON.stringify(_rejection_context(domain,plan,result)))
					push_warning("Domain commit rejected: "+domain+" "+str(result))
	phase_started=Time.get_ticks_usec()
	for a:Dictionary in _facts.actors:
		if a.get("faction")=="infected" or float(a.hp)<=0 or not region_is_detailed(str(a.regionId)):continue
		var motion_mode:String=str(_recovery_motion.get(str(a.id),"idle"))
		var recovery:float=Movement.WALK_RECOVERY if motion_mode=="walk" else Movement.IDLE_RECOVERY if motion_mode=="idle" and a.get("intent")==null else 0.0
		a.stamina=minf(Movement.stamina_max(a),float(a.stamina)+STEP*recovery)
		if a.get("run_recovering",false) and float(a.stamina)>=Movement.RUN_RECOVERY_STAMINA:a.run_recovering=false
	_recovery_motion.clear()
	var player: Dictionary = _find("actors","player")
	if not player.is_empty() and float(player.hp)<=0: _facts.status="dead"
	_simulation_phase("stamina_status",phase_started)
	_detailed_step_scope=false;_detailed_step_regions.clear();_detailed_step_revision=-1
	_draft_read_snapshot={}

func _spatial_rejection_context(building:RefCounted,view:RefCounted,staged:Dictionary)->Dictionary:
	var current:RefCounted=building.current_space()
	var draft:RefCounted=building.space(view,{},staged)
	var rows:Array=[]
	for a:Dictionary in staged.get("actors",[]):
		if rows.size()>=32:break
		var at:Dictionary=_location(a)
		var doors:Array=[]
		for piece:Dictionary in draft.nearby_pieces(str(a.regionId),AABB(Vector3(float(a.x)-2,float(a.y)-1,float(a.z)-2),Vector3(4,4,4))):
			if piece.get("door") is Dictionary:doors.append({"id":piece.id,"door":piece.door.duplicate(true),"hp":piece.get("hp")})
		rows.append({"id":a.id,"staged":at,"current_feet":current.standing_point(at),"draft_feet":draft.standing_point(at),"nearby_draft_doors":doors})
	return {"actors":rows,"limit":32}

func _rejection_context(domain:String,plan:Dictionary,result:Dictionary)->Dictionary:
	# Failure-only, read-only evidence. Never resolve a rejection by relocating
	# actors, retrying a plan or changing the authoritative draft.
	var actors:Array=[]
	for a:Dictionary in _facts.get("actors",[]):
		if actors.size()>=32:break
		var row:Dictionary={"id":a.id,"before":_location(a)}
		for change:Dictionary in plan.get("fact_changes",[]):
			if change.get("collection")=="actors" and change.get("id")==a.id:
				row.after=_location(change.after) if change.get("after") is Dictionary else null
		var size:float=float(world.config().cellSize)
		var cell:Vector3i=Vector3i(floori(float(a.x)/size),floori(float(a.y)/size)-1,floori(float(a.z)/size))
		row.support_cell={"x":cell.x,"y":cell.y,"z":cell.z,"material":world.cell_at(cell.x,cell.y,cell.z)}
		actors.append(row)
	var edits:Array=[]
	for change:Dictionary in plan.get("world_changes",[]):
		if edits.size()>=32:break
		var row:Dictionary={"op":change.get("op"),"id":change.get("id")}
		for key:String in ["x","y","z","chunk","key","cell"]:
			if change.has(key):row[key]=change[key]
		if change.get("op")=="voxel.set":
			row.before=change.get("before");row.after=change.get("after")
		var after:Variant=change.get("after")
		if after is Dictionary:
			for key:String in ["kind","regionId","buildingId","storeyId","position"]:
				if after.has(key):row[key]=after[key]
		edits.append(row)
	return {"schema":"afterglow-domain-rejection-v1","utc":Time.get_datetime_string_from_system(true),"domain":domain,"code":result.get("code"),"reason":result.get("reason"),"world":world.identity(),"world_revision":world.get_revision(),"runtime_revision":_revision,"time":clock(),"actors":actors,"actor_count":_facts.get("actors",[]).size(),"world_changes":edits,"world_change_count":plan.get("world_changes",[]).size(),"fact_change_count":plan.get("fact_changes",[]).size(),"spatial_diagnostic":result.get("spatial_diagnostic",{})}

func bed_availability(actor_state:Dictionary,target_id:String,facts_state:Dictionary={},require_contact:bool=true)->Dictionary:
	if actor_state.is_empty() or float(actor_state.get("hp",0))<=0:return _failure("ACTOR_UNAVAILABLE","角色无法行动")
	return _bed_availability(actor_state,target_id,_facts if facts_state.is_empty() else facts_state,{},false,require_contact)

func _bed_availability(a:Dictionary,target_id:String,observed:Dictionary,expected_location:Dictionary={},legacy:bool=false,require_contact:bool=true)->Dictionary:
	var bed:Dictionary=world.entity(target_id)
	var data:Dictionary=bed.get("data",{})
	if bed.is_empty() or (not data.get("sleeping",false) and not (legacy and bed.get("kind")=="bed")):return _failure("NO_BED","实际寝具已不存在")
	if not legacy and not data.get("prepared",false):return _failure("NO_BED","先用真实布料整理睡位")
	var owner:Variant=data.get("owner")
	if owner!=null and owner not in [a.id,a.get("householdId"),"home-residents"]:return _failure("FORBIDDEN","没有寝具物主许可")
	if owner=="home-residents" and a.id!="player" and (not a.get("relationship",{}).get("member",false) or not a.get("relationship",{}).get("consent",false)):return _failure("NO_CONSENT","尚未同意共同使用寝具")
	for other:Dictionary in observed.get("actors",[]):
		if other.get("id")==a.id or float(other.get("hp",0))<=0:continue
		var intent:Variant=other.get("intent")
		if not intent is Dictionary:continue
		if (intent.get("owner")=="runtime" and intent.get("kind") in ["rest","sleep"] and intent.get("target_id")==target_id) or (intent.get("owner")=="residents" and intent.get("resident_goal",{}).get("kind")=="bed" and intent.resident_goal.get("target_id")==target_id):return _failure("RESERVED","寝具已有人使用或正在前往")
	var at:Dictionary=_location(bed.position.merged({"regionId":bed.regionId,"buildingId":bed.get("buildingId"),"storeyId":bed.get("storeyId")}))
	if not expected_location.is_empty() and at!=expected_location:return _failure("TARGET_MOVED","寝具位置已变化，休息中断")
	if not require_contact:return _success()
	if not _services.has("production"):return _failure("NOT_READY","寝具接触检查尚未装配")
	var target:Dictionary=at.merged({"owner":owner})
	var access:Variant=_services.production.reach(str(a.id),target_id,target,"rest",LifeReadView.new(observed,world))
	return _success() if access==null else _failure("OUT_OF_REACH",str(access))

func _life_availability(request: Dictionary,a: Dictionary,facts_state:Dictionary={}) -> Dictionary:
	var observed:Dictionary=_facts if facts_state.is_empty() else facts_state
	var tx:=LifeReadView.new(observed,world)
	var kind: String = str(request.kind)
	if kind in ["eat","drink","medicine"] and _life_consumable(a,kind,request,observed).is_empty():return _failure("NO_ITEM","随身没有可用的安全食物、饮水或药品；种子与原水不可直接食用")
	if kind=="rest" and not str(request.get("target_id","")).is_empty():
		var usable:Dictionary=_bed_availability(a,str(request.target_id),observed,request.get("use_location",{}))
		if not usable.ok:return usable
	if kind in ["talk","help","invite","consent","job"]:
		var other: Dictionary = fact_from(observed,"actors",str(request.get("target_id","")))
		if other.is_empty() or other.get("faction")=="infected" or float(other.hp)<=0: return _failure("MISSING_RESIDENT","住户不在这里")
		if kind == "job":
			if not other.get("relationship",{}).get("member",false) or not other.get("relationship",{}).get("consent",false): return _failure("NO_CONSENT","对方尚未自愿加入")
			if observed.get("scenario")=="rural-home-r33" and not other.relationship.get("home_arrived",false):return _failure("RETURN_HOME_FIRST","先一起沿真实路线回到旧宅，再安排工作")
		elif not _social_reach(a,other,2.2): return _failure("OUT_OF_REACH","需要走到对方面前，且中间没有墙体遮挡")
		if kind == "invite" and not other.get("relationship",{}).get("helped",false): return _failure("HELP_REQUIRED","先实际帮助对方，再邀请同行")
		if kind == "help":
			var cost: Dictionary = request.get("payload",{}).get("items",{})
			if cost.is_empty(): return _failure("NO_ITEMS","请选择实际交给对方的物资")
			for key: String in cost:
				if not (cost[key] is int or cost[key] is float) or not is_finite(float(cost[key])) or float(cost[key])<=0 or float(a.pack.get(key,0))-(_services.production.reserved("pack:"+str(a.id),key,str(request.get("command_id","")),tx) if _services.has("production") else 0)<float(cost[key]) or not Content.quantity_valid(key,cost[key],true): return _failure("NO_ITEMS","随身物资不足或数量无效")
			if other.id=="repair-resident":
				var production:Variant=world.extension("r3:production")
				if not production is Dictionary or not production.get("tools",[]).any(func(t:Dictionary)->bool:return t.get("holderId")=="pack:"+str(a.id) and t.get("kind")=="hammer" and float(t.get("durability",0))>0):return _failure("RECOVER_TOOL_FIRST","老许需要确认修理工具还在；先实际带回一把手锤，再提供帮助")
	return _success()

func _prepare_life(request: Dictionary,a: Dictionary,facts_state:Dictionary={}) -> Dictionary:
	var observed:Dictionary=_facts if facts_state.is_empty() else facts_state
	var next: Dictionary = a.duplicate(true)
	var kind: String = str(request.kind)
	var changes: Array = []
	if kind in ["eat","drink","medicine","rest"]:
		if a.get("intent") != null: return _failure("BUSY","先结束或取消当前行动")
		next.intent={"schema_version":1,"owner":"runtime","kind":kind,"elapsed":0.0,"duration":12.0 if kind=="rest" else 1.3,"id":request.command_id,"target_id":request.get("target_id","")}
		if kind in ["eat","drink","medicine"]:
			var consumable:Dictionary=_life_consumable(a,kind,request,observed)
			if consumable.is_empty():return _failure("NO_ITEM","没有可用于这次生活动作的物品")
			next.intent.duration=float(consumable.duration)
			if consumable.item_id!={"eat":"food","drink":"water","medicine":"medicine"}[kind]:next.intent.item_id=consumable.item_id
		if kind=="rest" and not str(next.intent.target_id).is_empty():
			var bed:Dictionary=world.entity(str(next.intent.target_id))
			next.intent.use_location=_location(bed.position.merged({"regionId":bed.regionId,"buildingId":bed.get("buildingId"),"storeyId":bed.get("storeyId")}))
		next.activity={"eat":"进食","drink":"饮水","medicine":"处理伤势","rest":"休息"}[kind]
	elif kind == "cancel": next.intent=null;next.activity="自由行动"
	else:
		var other: Dictionary = fact_from(observed,"actors",str(request.target_id))
		var updated: Dictionary = other.duplicate(true)
		var relationship: Dictionary = updated.get("relationship",{}).duplicate(true)
		if kind == "talk": relationship.met=true
		elif kind == "help":
			for key: String in request.payload.items:
				next.pack[key]=float(next.pack.get(key,0))-float(request.payload.items[key])
				updated.pack[key]=float(updated.pack.get(key,0))+float(request.payload.items[key])
			relationship.helped=true;relationship.met=true
		elif kind == "invite":
			relationship.member=true;relationship.consent=true;relationship.met=true
			updated.job="follow";updated.householdId="home-residents"
		elif kind == "consent": relationship.consent=bool(request.get("payload",{}).get("enabled",false))
		elif kind == "job":
			var job: String = str(request.get("payload",{}).get("job","rest"))
			if not job in ["gather","craft","guard","rest"]: return _failure("INVALID_JOB","工作类型无效")
			var target_id:String=str(request.get("payload",{}).get("work_target_id",""))
			var selected:Dictionary={}
			for candidate:Dictionary in work_targets():
				if candidate.id==target_id and candidate.job==job:selected=candidate;break
			if job!="rest" and selected.is_empty():return _failure("MISSING_WORK_TARGET","需要选择实际工作目标")
			if selected.get("work_payload",{}).has("zone_id"):
				var zone:Dictionary={}
				for current_zone:Dictionary in zone_records():
					if current_zone.id==selected.work_payload.zone_id:zone=current_zone;break
				if zone.is_empty() or not zone.enabled or zone.kind!="patrol" or zone.region_id!=_location(other).regionId:return _failure("REGIONAL_JOB_UNAVAILABLE","巡逻区已停用或同伴尚未实际到达该地区")
				var workers:Array=zone.get("policy",{}).get("worker_ids",[])
				if not workers.is_empty() and not workers.has(other.id):return _failure("REGIONAL_JOB_PERMISSION","这个巡逻区未安排该同伴")
			updated.job=job;updated.work_target_id=selected.get("actual_target_id",target_id)
			updated.work_payload=selected.get("work_payload",{}).duplicate(true)
			for field:String in ["source_id","output_id"]:
				if updated.work_payload.get(field)=="$actor_pack":updated.work_payload[field]="pack:"+str(other.id)
		updated.relationship=relationship
		changes.append({"collection":"actors","id":other.id,"before":other,"after":updated})
	changes.append({"collection":"actors","id":a.id,"before":a,"after":next})
	return {"ok":true,"world_changes":[],"fact_changes":changes,"events":[{"kind":kind,"actor_id":a.id,"target_id":request.get("target_id","")}]}

func _advance_life(a: Dictionary,dt: float) -> void:
	# Metabolism may incapacitate someone earlier in this very fixed step.
	# A nearly finished medicine/rest action cannot revive or reward them.
	if float(a.get("hp",0))<=0:
		a.intent=null;a.activity="已失能，生活行动中断";return
	var intent: Dictionary = a.intent
	if intent.kind=="legacy_dispatch":
		intent.elapsed=float(intent.elapsed)+dt
		if float(intent.elapsed)+0.000001>=float(intent.duration):a.migration_resume=intent.resume.duplicate(true);a.intent=null
		return
	if intent.get("legacy_v5",false):
		if not _near(a,intent.legacy_destination,0.4):a.intent=null;a.activity="已离开旧档活动使用点，行动中断";return
		if intent.kind=="sleep":
			var bed_ready:Dictionary=_bed_availability(a,str(intent.target_id),_facts,intent.get("use_location",{}),true)
			if not bed_ready.ok:a.intent=null;a.activity=str(bed_ready.reason);return
	# Validate continuation BEFORE advancing time, recovering or consuming.
	# E's post-step decisions cannot undo a free recovery already applied here.
	if intent.kind!="sleep":
		var request:Dictionary={"kind":intent.kind,"actor_id":a.id,"command_id":intent.get("id",""),"target_id":intent.get("target_id",""),"use_location":intent.get("use_location",{})}
		if intent.kind in ["eat","drink","medicine"]:request.payload={"item_id":intent.get("item_id",{"eat":"food","drink":"water","medicine":"medicine"}[intent.kind])}
		var ready:Dictionary=_life_availability(request,a,_facts)
		if not ready.ok:a.intent=null;a.activity=str(ready.reason);return
	intent.elapsed=float(intent.elapsed)+dt
	if intent.get("legacy_v5",false) and intent.kind=="rest":a.fatigue=maxf(0,float(a.fatigue)-dt*0.12)
	if intent.kind=="sleep":a.stamina=minf(Movement.stamina_max(a),float(a.stamina)+dt*3);a.fatigue=maxf(0,float(a.fatigue)-dt*1.4)
	if intent.kind=="rest":
		a.stamina=minf(Movement.stamina_max(a),float(a.stamina)+5*dt)
		if not str(intent.get("target_id","")).is_empty():a.fatigue=maxf(0,float(a.fatigue)-dt*1.5)
	if float(intent.elapsed)+0.00001<float(intent.duration): return
	var item:String=str(intent.get("item_id",{"eat":"food","drink":"water","medicine":"medicine"}.get(intent.kind,"")))
	if not item.is_empty():
		if float(a.pack.get(item,0))-(_services.production.reserved("pack:"+str(a.id),item,str(intent.get("id",""))) if _services.has("production") else 0)<1: a.intent=null;a.activity="物品不足，行动中断";return
		var consumable:Dictionary=Content.consumable_definition(item,intent.kind)
		if consumable.is_empty():a.intent=null;a.activity="物品已经不适合这次生活动作";return
		a.pack[item]=float(a.pack[item])-1
		if intent.kind=="eat":a.hunger=minf(100,float(a.hunger)+float(consumable.restore))
		elif intent.kind=="drink":a.thirst=minf(100,float(a.thirst)+float(consumable.restore))
		else:a.hp=minf(100,float(a.hp)+float(consumable.restore));a.wounds=[]
	_facts.actions.append({"id":intent.id,"actorId":a.id,"kind":intent.kind,"status":"completed","time":clock(),"targetId":intent.get("target_id"),"reason":"已完成"})
	if _facts.actions.size()>80: _facts.actions.pop_front()
	a.intent=null;a.activity="自由行动"
	_revision+=1
	a.skills.survival=float(a.skills.get("survival",0))+0.25
	_record_events([{"kind":"life-completed","operation":intent.kind,"actor_id":a.id,"target_id":intent.get("target_id","")}])

func _resume_migrations()->void:
	# B completes the real walk first. The old operation then enters the normal
	# command preflight once; failed arrival/permission never becomes free work.
	var ids:Array=[]
	for actor:Dictionary in _facts.actors:
		if actor.get("intent")==null and actor.get("migration_resume") is Dictionary:ids.append(str(actor.id))
	for id:String in ids:
		var before:Dictionary=_find("actors",id)
		var after:Dictionary=before.duplicate(true)
		var resume:Dictionary=after.migration_resume
		after.erase("migration_resume")
		var old:Dictionary=resume.get("legacy",{})
		var request:Dictionary=resume.get("request",{})
		var result:Dictionary=_failure("INVALID_MIGRATION","旧档接续状态无效")
		var prepared:Dictionary={}
		if LegacyIntents.valid(old) and request.get("actor_id")==id and request.get("command_id")==old.id and _near(before,old.destination,0.4):
			if old.kind=="sleep":
				var bed:Dictionary=world.entity(str(request.get("target_id","")))
				var owner:Variant=bed.get("data",{}).get("owner")
				var occupied:bool=_facts.actors.any(func(a:Dictionary)->bool:return a.id!=id and a.get("intent") is Dictionary and a.intent.get("kind")=="sleep" and a.intent.get("target_id")==request.get("target_id"))
				result=_success() if not bed.is_empty() and (bed.get("kind")=="bed" or bed.get("data",{}).get("sleeping",false)) and owner in [null,id,"home-residents"] and not occupied else _failure("NO_BED","旧档实际床位不可使用")
				if result.ok:
					after.intent=LegacyIntents.life_intent(old)
					prepared={"ok":true,"fact_changes":[{"collection":"actors","id":id,"before":before,"after":after}]}
			else:
				result=availability(request)
				if result.ok:
					prepared=_prepare_life(request,before) if old.kind in ["eat","drink","medicine","rest","talk"] else _services.actions.prepare(request)
					result=prepared
					if prepared.ok:
						for change:Dictionary in prepared.get("fact_changes",[]):
							if change.get("collection")=="actors" and change.get("id")==id:
								change.after.erase("migration_resume")
								if old.kind in ["eat","drink","medicine","rest"]:change.after.intent=LegacyIntents.life_intent(old)
		if result.ok and not prepared.is_empty():
			result=_commit(prepared)
		if not result.ok:
			after.intent=null;after.activity="旧档活动接续受阻："+str(result.get("reason","无法到达原使用点"))
			_commit({"fact_changes":[{"collection":"actors","id":id,"before":before,"after":after}],"events":[{"kind":"legacy-activity-blocked","actor_id":id,"intent_id":old.get("id",""),"reason":after.activity}]})

func _record_events(events:Array) -> void:
	if not _facts.get("ledger") is Array:_facts.ledger=[]
	for index:int in events.size():
		var event:Dictionary=events[index].duplicate(true)
		event.id="event:%s:%s"%[_revision,index];event.revision=_revision;event.time=clock()
		_facts.ledger.append(event)
	while _facts.ledger.size()>256:_facts.ledger.pop_front()

func work_targets() -> Array:
	# Static tree/structure/record choices retain their existing cache. Regional
	# discoveries are owned by E and may change without any structure or stock
	# edit, so merge their permission-filtered public facts on every read.
	if _work_revision>=0:return _with_regional_work_targets(_work_targets)
	var targets:Array=[]
	var definitions:Dictionary=_context.get("definitions",{})
	var home_stock:="rural:v1:RH-HOME:old-house:storage"
	var gameplay:Variant=world.extension("r33:gameplay")
	if gameplay is Dictionary:
		# Factory village layouts do not contain the legacy building identifier.
		var home_building := str(gameplay.get("layout", {}).get("home_building", ""))
		if not home_building.is_empty():
			home_stock = home_building + ":storage"
	for e:Dictionary in world.entities():
		if e.get("kind")=="tree" and e.get("data",{}).get("harvest",{}).get("phase")=="standing":
			targets.append({"id":e.id,"actual_target_id":e.id,"name":"采伐 · "+("宅旁林缘" if e.regionId=="RH-HOME" else "村边树木"),"job":"gather","work_payload":{"action_kind":"harvest","delivery_id":home_stock}})
		elif e.get("kind")=="structure":
			var piece:Dictionary=_services.buildings.instance(str(e.id))
			var d:Dictionary=_services.buildings.geometry.definition(piece)
			if float(piece.get("hp",0))<float(d.get("maxHp",0)):
				targets.append({"id":"work:repair:"+str(e.id),"actual_target_id":e.id,"name":"维修 · "+str(d.get("name","构件")),"job":"craft","work_payload":{"action_kind":"structure","kind":"repair","source_id":"$actor_pack","output_id":"$actor_pack"}})
			if d.get("kind")=="door":targets.append({"id":e.id,"actual_target_id":e.id,"name":"守备 · "+str(d.name),"job":"guard","work_payload":{}})
			if d.get("kind")=="workbench":
				for recipe:Dictionary in definitions.get("production_recipes",[]):
					targets.append({"id":"work:craft:"+e.id+":"+str(recipe.id),"actual_target_id":e.id,"name":"制作 · "+str(recipe.name),"job":"craft","work_payload":{"action_kind":"craft","recipe_id":recipe.id,"source_id":"$actor_pack","output_id":"$actor_pack"}})
	var production:Variant=world.extension("r3:production")
	if production is Dictionary:
		for record:Dictionary in production.get("records",[]):
			var source:Dictionary=stock(str(record.get("holderId","")))
			if source.is_empty() or not source.get("searched",false):continue
			targets.append({"id":"work:study:"+str(record.id),"actual_target_id":record.id,"name":"学习 · "+str(record.get("itemId","手册")),"job":"craft","work_payload":{"action_kind":"study","source_id":record.holderId,"record_id":record.id}})
	# B owns construction reservations and their canonical placement. Reuse its
	# actual choices instead of recreating the rural workbench layout in A.
	if _services.get("actions")!=null and _services.actions.has_method("camp_work_targets"):
		for candidate:Dictionary in _services.actions.camp_work_targets():
			if not targets.any(func(t:Dictionary)->bool:return t.id==candidate.id):targets.append(candidate)
	_work_revision=world.get_revision();_work_targets=targets
	return _with_regional_work_targets(targets)

func _with_regional_work_targets(base:Array)->Array:
	var targets:Array=base.duplicate(true)
	# A designation is an actual role-selection anchor, never a free guard or
	# a completed route. B still owns every patrol point and movement admission.
	var player_state:Dictionary=actor("player")
	var actions:Variant=domain_service("actions")
	if not _retired and not player_state.is_empty() and actions!=null:
		var probe:Dictionary=player_state.duplicate(true);probe.job="guard"
		var tx:RefCounted=preload("res://scripts/actions/workforce_executor.gd").observation(actions,_facts,{})
		for point:Dictionary in preload("res://scripts/actions/regional_workforce.gd").patrol_points(actions,tx,probe):
			if point.get("operation")!="patrol":continue
			var zone:Dictionary={}
			for current_zone:Dictionary in zone_records():
				if current_zone.id==point.site_id:zone=current_zone;break
			if zone.is_empty():continue
			var id:String="work:guard:"+str(zone.id)
			if targets.any(func(row:Dictionary)->bool:return row.id==id):continue
			targets.append({"id":id,"actual_target_id":zone.id,"name":"巡逻 · "+str(zone.get("name","规划区域")),"job":"guard","work_payload":{"site_id":zone.id,"zone_id":zone.id,"zone_revision":zone.revision,"position":point.position.duplicate(true)}})
	var provider:Variant=_services.get("workforce")
	if provider==null or not provider.has_method("regional_projection"):return targets
	var regional:Variant=provider.regional_projection("player")
	if not regional is Dictionary or not regional.get("available",false) or not regional.get("sites") is Array:return targets
	for site:Variant in regional.sites:
		if not site is Dictionary or not site.get("surveyed",false) or not Data.valid_id(site.get("id")) or not Data.vec(site.get("defense_position")) or not Data.valid_id(site.defense_position.get("regionId")):continue
		var id:String="work:guard:"+str(site.id)
		if targets.any(func(row:Dictionary)->bool:return row.id==id):continue
		targets.append({"id":id,"actual_target_id":site.id,"name":"守备 · "+str(site.get("title","已勘察地区")),"job":"guard","work_payload":{"site_id":site.id,"position":site.defense_position.duplicate(true)}})
	return targets

func factory_alert_sources(actor_id:String="player",workforce_alerts:Variant=null)->Array:
	# A bounded read for display reconciliation: no content catalog, map,
	# residency traversal or second scan of private production state.
	if _retired or actor(actor_id).is_empty():return []
	var rows:Array=[];var keys:Dictionary={};var read_owners:Dictionary={}
	for spec:Array in [["modules","projection"],["production","factory_projection"],["production","logistics_projection"],["workforce","projection"]]:
		if spec[0]=="workforce" and workforce_alerts is Array:
			for row:Dictionary in workforce_alerts:
				if not keys.has(row.key):keys[row.key]=true;rows.append(row)
			continue
		var provider:Variant=_services.get(spec[0]);var method:String=spec[1]
		if provider!=null and provider.has_method("alert_projection"):
			if read_owners.has(spec[0]):continue
			read_owners[spec[0]]=true;method="alert_projection"
		var alerts:Array=_factory_alert_rows(provider,method,actor_id)
		for row:Dictionary in alerts:
			if not keys.has(row.key):keys[row.key]=true;rows.append(row)
	return rows

static func _factory_alert_rows(service:Variant,method:String,actor_id:String)->Array:
	# Reuse the exact permission-filtered public provider, but detach ONLY the
	# requested rows. The old generic merger copied its entire catalogue,
	# buffers, people and commands merely to discard everything except alerts.
	if service==null or not service.has_method(method):return []
	var value:Variant=service.call(method,actor_id)
	if not value is Dictionary or not value.get("available") is bool or not value.get("alerts",[]) is Array:return []
	var alerts:Array=value.get("alerts",[])
	if not alerts.all(func(row:Variant)->bool:return row is Dictionary and row.get("key") is String):return []
	return alerts.duplicate(true)

func module_service_approaches(module_id:String,actor_id:String="player")->Dictionary:
	# On-demand detail only: B proves real supported feet, permissions and the
	# existing walk command. This facade cannot search a cache or move items.
	var unavailable:Dictionary={"available":false,"module_id":module_id,"approaches":[],"code":"SERVICE_ACCESS_UNAVAILABLE","reason":"此模块尚未提供可用的现场服务面"}
	if _retired or actor(actor_id).is_empty() or not Data.valid_id(module_id):return unavailable
	var provider:Variant=_services.get("modules")
	if provider==null or not provider.has_method("service_approaches"):return unavailable
	var value:Variant=provider.call("service_approaches",actor_id,module_id)
	if not value is Dictionary or not value.get("available") is bool or value.get("module_id")!=module_id or not value.get("approaches") is Array:return unavailable
	return value.duplicate(true)

func handbook_snapshot(actor_id:String="player",entry_id:String="")->Dictionary:
	if _retired:return FactoryHandbook.empty()
	return FactoryHandbook.build(self,actor_id,entry_id,_services,_context.get("definitions",{}))

func water_snapshot(actor_id:String="player",source_id:String="",visual_only:bool=false)->Dictionary:
	var fallback:Dictionary={"available":false,"sources":[],"projects":[]}
	if _retired or actor_id!="player" or actor(actor_id).is_empty():return fallback
	var provider:Variant=_services.get("modules")
	if provider==null or not provider.has_method("water_projection"):return fallback
	var method: String = "water_visual_projection" if visual_only and provider.has_method("water_visual_projection") else "water_projection"
	var value:Variant=provider.call(method,actor_id,source_id)
	if not value is Dictionary or not value.get("available") is bool or not value.get("sources") is Array or not value.get("projects") is Array:return fallback
	return value.duplicate(true)

func teaching_snapshot(actor_id:String="player",teacher_id:String="")->Dictionary:
	var fallback:Dictionary={"available":false,"offers":[]}
	if _retired or actor_id!="player" or actor(actor_id).is_empty() or (not teacher_id.is_empty() and not Data.valid_id(teacher_id)):return fallback
	var provider:Variant=_services.get("production")
	if provider==null or not provider.has_method("teaching_projection"):return fallback
	var value:Variant=provider.call("teaching_projection",actor_id,teacher_id)
	if not value is Dictionary or not value.get("available") is bool or not value.get("offers") is Array:return fallback
	if not value.offers.all(func(offer:Variant)->bool:return offer is Dictionary and offer.get("teacher_id") is String and offer.get("knowledge_id") is String and offer.get("can_start") is bool):return fallback
	return value.duplicate(true)

var _visual_stocks_observed: Variant = null
var _visual_stocks_serial := 0

func factory_visual_basis() -> Array:
	if _retired or world == null or not world.has_method("extension_token"):
		return []
	var modules: Variant = _services.get("modules")
	if modules == null or not modules.has_method("visual_projection") or not modules.has_method("water_visual_projection"):
		return []
	# This fence is for the native scene's player view. An equal stock table
	# copied by an actor-only transaction represents the same visual state.
	if not is_same(_visual_stocks_observed, _facts.stocks):
		if _visual_stocks_observed != _facts.stocks:
			_visual_stocks_serial += 1
		_visual_stocks_observed = _facts.stocks
	var observers: Array = []
	for person: Dictionary in _facts.actors:
		var intent: Variant = person.get("intent")
		var construction: Array = []
		if intent is Dictionary:
			construction = [bool(intent.get("held", true)), intent.get("owner"), intent.get("kind"), intent.get("workforce_candidate_id")]
		observers.append([person.id, construction])
	var viewer := _find("actors", "player")
	var visual_revision: int = world.factory_visual_revision() if world.has_method("factory_visual_revision") else world.get_revision()
	return [get_instance_id(), _ui_read_epoch, world.get_instance_id(), visual_revision, world.extension_token(""), _paused, _visual_stocks_serial, viewer.get("householdId"), float(viewer.get("hp", 0)) > 0.0, observers]

func factory_visual_snapshot(actor_id:String="player")->Dictionary:
	# Scene consumers use only real modules and water. Do not enumerate jobs,
	# logistics, stories, catalogues or map history just to draw a building.
	# This is a detached permission-filtered read, not a cached simulation.
	var identity:Dictionary=world.identity() if world!=null else {}
	var result:Dictionary=FactoryContracts.empty_snapshot(str(identity.get("worldId","")),world.get_revision() if world!=null else 0,_revision)
	if _retired or actor(actor_id).is_empty():return result
	var modules:Variant=_services.get("modules")
	var visual_method:String="visual_projection" if modules!=null and modules.has_method("visual_projection") else "projection"
	result.modules=_factory_projection(modules,visual_method,actor_id,result.modules)
	result.water=water_snapshot(actor_id,"",true)
	for key:String in ["modules","water"]:
		result.capabilities[key]=result[key].get("available",false)
		if result[key].has("error"):result.errors.append({"domain":key,"error":result[key].error})
	result.available=bool(result.capabilities.modules)
	var scopes:Array=[]
	for id:String in world.region_ids():scopes.append({"id":id,"detailed":region_is_detailed(id)})
	result.scope={"policy":"generated-resident-regions-v1","regions":scopes,"offscreen_production":false,"label":"远区生产、运输与交战暂停"}
	return result

func factory_ui_snapshot(actor_id:String="player",include_read_state:bool=true)->Dictionary:
	# Real management facts, with expensive candidate enumeration requested only
	# by the workforce page. The original full public API retains its semantics.
	return _factory_snapshot(actor_id,include_read_state,false)

var _page_module_catalog:Dictionary={}

func factory_page_snapshot(actor_id:String="player",page:String="",subject:String="")->Dictionary:
	# Page reads are detached observations of the existing owners. An unrequested
	# section advertises capability for navigation, without evaluating its jobs,
	# production buffers, route proposals or full module catalogue.
	var identity:Dictionary=world.identity() if world!=null else {}
	var result:Dictionary=FactoryContracts.empty_snapshot(str(identity.get("worldId","")),world.get_revision() if world!=null else 0,_revision)
	if _retired or actor_id!="player" or actor(actor_id).is_empty():return result
	for spec:Array in [["modules","r34:modules"],["production","r34:production"],["logistics","r34:logistics"],["workforce","r34:workforce"]]:
		result[spec[0]].available=world.has_extension(spec[1])
		result[spec[0]].details_state="not_requested"
		result.capabilities[spec[0]]=result[spec[0]].available
	# Production/logistics use their owner's lazy empty initial state. Absence
	# of a persisted order/task extension is not absence of that capability.
	var producer:Variant=_services.get("production")
	result.production.available=producer!=null and producer.has_method("factory_projection")
	result.logistics.available=producer!=null and producer.has_method("logistics_projection") and preload("res://scripts/production/factory_kernel.gd").permitted(actor(actor_id),"home-residents")
	var workforce_owner:Variant=_services.get("workforce")
	var workforce_hud:Dictionary=workforce_owner.hud_projection(actor_id) if workforce_owner!=null and workforce_owner.has_method("hud_projection") else {}
	result.workforce.available=workforce_hud.get("available",false)
	if page in ["factory_module","npc_quick"]:
		result.workforce.members=workforce_hud.get("members",[])
		result.workforce.assignments=workforce_hud.get("assignments",[])
		result.workforce.building_queue=workforce_hud.get("building_queue",[])
	for key:String in ["production","logistics","workforce"]:result.capabilities[key]=result[key].available
	result.available=result.modules.available
	result.details_state="page:"+page
	var modules:Variant=_services.get("modules")
	if page=="factory_catalog" and modules!=null:
		# The owner pins its immutable content catalogue for this process. Cache
		# only those static definitions, never availability or an accepted plan.
		if _page_module_catalog.is_empty():_page_module_catalog={"definitions":modules.module_definitions(),"build_definition_ids":modules.build_choices()}
		result.modules.merge(_page_module_catalog.duplicate(true),true)
		if result.modules.build_definition_ids.has("r38.module.stockyard"):
			result.modules.village_stage=modules.village_building_stage()
		result.modules.details_state="requested"
	elif page in ["factory","factory_module","factory_inventory","factory_confirm","workbench","container","inventory","factory_alerts"] and modules!=null and not (page == "factory_inventory" and subject == "pack:player"):
		var module_id:String=""
		if page in ["factory_module","workbench","container","factory_inventory"] and not subject.is_empty():
			# Resolve an old member workbench/container ID inside its owning domain;
			# the projection below still enforces live discovery and permission.
			for row:Dictionary in modules.state().get("instances",[]):
				if row.id==subject or row.get("stock_refs",{}).values().has(subject) or row.get("members",[]).any(func(member:Dictionary)->bool:return member.get("id")==subject):
					module_id=str(row.id);break
		if page in ["factory","factory_module","factory_confirm","workbench"] or (not module_id.is_empty() and page in ["factory_inventory","container"]):
			result.modules=modules.projection(actor_id,module_id)
		else:
			result.modules=modules.visual_projection(actor_id,module_id)
		result.modules.details_state="requested"
	if page in ["factory_production","factory_module","factory_confirm"]:
		result.production=_factory_projection(_services.get("production"),"factory_projection",actor_id,result.production)
	if page in ["factory_logistics","factory_confirm"]:
		result.logistics=_factory_projection(_services.get("production"),"logistics_projection",actor_id,result.logistics)
	if page in ["factory_people","factory_alerts"]:
		result.workforce=workforce_snapshot(actor_id,false)
	if page in ["water","factory_module"]:result.water=water_snapshot(actor_id,subject if page=="water" else "")
	if page in ["factory_catalog","factory_module","factory_production","factory_inventory","factory_handbook","factory_confirm"]:
		result.definitions={"content":FactoryDefinitions.catalog(),"items":Content.item_definitions(),"modules":result.modules.get("definitions",[])}
	if page=="factory_alerts":
		result.alerts=factory_alert_sources(actor_id)
		result.water=water_snapshot(actor_id)
		var display:Variant=_services.get("display")
		if display!=null:
			var read_state:Dictionary=display.projection(result.alerts,clock())
			for key:String in ["alerts","alert_history","alert_summary"]:result[key]=read_state[key]
			result.map={"schema":"afterglow-known-map-v1","tile_metres":read_state.tile_metres,"explored_tiles":read_state.explored_tiles,"markers":result.workforce.get("map_markers",[]).duplicate(true)}
			for module:Dictionary in result.modules.get("instances",[]):result.map.markers.append({"id":module.id,"kind":"module","title":module.get("name",module.id),"location":module.get("location",{}).duplicate(true)})
			result.map.cartography=_page_cartography.build(world,result.map,result.modules,result.water)
	return result

var _page_cartography:=preload("res://scripts/runtime/known_cartography.gd").new()

func ui_page_snapshot(page:String="",subject:String="")->Dictionary:
	if page in ["inventory","container","workbench","factory_inventory","factory_module","factory_confirm","factory_logistics"]:
		return _display_snapshot(true,page,subject)
	if page in ["build","terrain","factory_catalog"]:
		var result:Dictionary=hud_snapshot()
		result.catalog=_page_catalog(page)
		return result
	if page.is_empty():return hud_snapshot(true)
	if page in ["pause","settings","new_world","close_failed","quests","neighbors","npc","factory","factory_catalog","factory_people","factory_alerts","factory_handbook","factory_production","water","zone_planning"]:return hud_snapshot()
	# Unknown/third-party routes retain the complete compatibility observation.
	return snapshot()

func _page_catalog(page:String)->Dictionary:
	var result:Dictionary=_hud_catalog()
	if page in ["build","factory_catalog"]:
		var buildings:Variant=_services.get("buildings")
		result.buildings=buildings.catalog() if buildings!=null else []
		if page=="factory_catalog":result.buildings=result.buildings.filter(func(row:Dictionary)->bool:return row.get("id")=="cabinet")
	elif page=="workbench":
		var source:Dictionary=_context.get("definitions",{})
		for key:String in ["recipes","production_recipes","items"]:
			if source.has(key):result[key]=source[key].duplicate(true)
	return result

var _hud_factory_basis:Array=[]
var _hud_factory_value:Dictionary={}
var _hud_factory_facts:Dictionary={}

func factory_hud_snapshot(actor_id:String="player")->Dictionary:
	# Demand boundary: no catalogs, route searches, job enumeration, inventory
	# layouts or historical map copies in the normal walking/hover refresh.
	var basis:Array=[world.get_instance_id() if world!=null else 0,world.get_revision() if world!=null else -1,_revision,clock(),_paused,_retired,actor_id]
	if basis==_hud_factory_basis and is_same(_facts,_hud_factory_facts):return _hud_factory_value.duplicate(true)
	var identity:Dictionary=world.identity() if world!=null else {}
	var result:Dictionary=FactoryContracts.empty_snapshot(str(identity.get("worldId","")),world.get_revision() if world!=null else 0,_revision)
	result.details_state="not_requested"
	if _retired or actor_id!="player" or actor(actor_id).is_empty():return result
	var modules:Variant=_services.get("modules")
	result.modules.available=modules!=null and world.has_extension("r34:modules")
	result.modules.details_state="not_requested"
	result.available=result.modules.available
	var workforce:Variant=_services.get("workforce")
	result.workforce=_factory_projection(workforce,"hud_projection",actor_id,result.workforce)
	var alerts:Variant=result.workforce.get("alerts") if workforce!=null and workforce.has_method("hud_projection") and not result.workforce.has("error") else null
	result.alerts=factory_alert_sources(actor_id,alerts)
	var display:Variant=_services.get("display")
	if display!=null:
		var read_state:Dictionary=display.projection(result.alerts,clock(),false)
		for key:String in ["alerts","alert_summary"]:result[key]=read_state[key]
	_hud_factory_basis=basis;_hud_factory_facts=_facts;_hud_factory_value=result.duplicate(true)
	return result

func workforce_snapshot(actor_id:String="player",include_candidates:bool=true)->Dictionary:
	var fallback:Dictionary={"available":false,"assignments":[],"members":[],"people":[],"alerts":[]}
	if _retired or actor_id=="*":return fallback
	var target:Dictionary=actor(actor_id)
	if target.is_empty():return fallback
	if actor_id!="player" and (target.get("faction")=="infected" or not target.get("relationship",{}).get("member",false)):return fallback
	var service:Variant=_services.get("workforce")
	var method:String="projection" if include_candidates or service==null or not service.has_method("summary_projection") else "summary_projection"
	return _factory_projection(service,method,actor_id,fallback)

func workforce_person_snapshot(actor_id:String)->Dictionary:
	if _retired or actor_id=="*":return {}
	var target:Dictionary=actor(actor_id)
	if target.is_empty() or target.get("faction")=="infected" or (actor_id!="player" and not target.get("relationship",{}).get("member",false)):return {}
	var service:Variant=_services.get("workforce")
	if service==null or not service.has_method("person_projection"):return {}
	var value:Variant=service.person_projection(actor_id)
	return value.duplicate(true) if value is Dictionary and value.get("actor_id")==actor_id else {}

func factory_snapshot(actor_id:String="player",include_read_state:bool=true)->Dictionary:
	return _factory_snapshot(actor_id,include_read_state,true)

func _factory_snapshot(actor_id:String,include_read_state:bool,include_candidates:bool)->Dictionary:
	var identity:Dictionary=world.identity() if world!=null else {}
	var result:Dictionary=FactoryContracts.empty_snapshot(str(identity.get("worldId","")),world.get_revision() if world!=null else 0,_revision)
	if _retired or actor(actor_id).is_empty():return result
	var modules:Variant=_services.get("modules")
	var production:Variant=_services.get("production")
	var workforce:Variant=_services.get("workforce")
	result.modules=_factory_projection(modules,"projection",actor_id,result.modules)
	result.production=_factory_projection(production,"factory_projection",actor_id,result.production)
	result.logistics=_factory_projection(production,"logistics_projection",actor_id,result.logistics)
	var workforce_method:String="projection" if include_candidates or workforce==null or not workforce.has_method("summary_projection") else "summary_projection"
	result.workforce=_factory_projection(workforce,workforce_method,actor_id,result.workforce)
	result.water=water_snapshot(actor_id)
	for key:String in ["modules","production","logistics","workforce","water"]:
		result.capabilities[key]=result[key].get("available",false)
		if result[key].has("error"):result.errors.append({"domain":key,"error":result[key].error})
		for alert:Dictionary in result[key].get("alerts",[]):
			# Providers already filter discovery/permissions. No second scan of
			# private extensions or inaccessible buffers from the facade.
			if not result.alerts.any(func(existing:Dictionary)->bool:return existing.get("key")==alert.get("key")):result.alerts.append(alert.duplicate(true))
	result.available=bool(result.capabilities.modules)
	var scopes:Array=[]
	for id:String in world.region_ids():scopes.append({"id":id,"detailed":region_is_detailed(id)})
	result.scope={"policy":"generated-resident-regions-v1","regions":scopes,"offscreen_production":false,"label":"远区生产、运输与交战暂停"}
	result.definitions={"content":FactoryDefinitions.catalog(),"items":Content.item_definitions(),"modules":result.modules.get("definitions",[]).duplicate(true)}
	var display:Variant=_services.get("display")
	if include_read_state and actor_id=="player" and display!=null:
		var read_state:Dictionary=display.projection(result.alerts,clock())
		for key:String in ["alerts","alert_history","alert_summary"]:result[key]=read_state[key]
		result.map={"schema":"afterglow-known-map-v1","tile_metres":read_state.tile_metres,"explored_tiles":read_state.explored_tiles,"markers":result.workforce.get("map_markers",[]).duplicate(true)}
		# Module owners already enforce discovery and permissions. Never scan
		# generated resource entities or future encounter positions for the map.
		for module:Dictionary in result.modules.get("instances",[]):
			result.map.markers.append({"id":module.id,"kind":"module","title":module.get("name",module.get("definition_id",module.id)),"location":module.get("location",module.get("position",{})).duplicate(true)})
	return result.duplicate(true)

func _factory_projection(service:Variant,method:String,actor_id:String,fallback:Dictionary)->Dictionary:
	if service==null or not service.has_method(method):return fallback.duplicate(true)
	var value:Variant=service.call(method,actor_id)
	var valid:bool=value is Dictionary and value.get("available") is bool
	if valid:
		for key:String in fallback:
			if fallback[key] is Array and not value.get(key,[]) is Array:valid=false;break
		if not value.get("alerts",[]) is Array:valid=false
		elif not value.get("alerts",[]).all(func(alert:Variant)->bool:return alert is Dictionary and alert.get("key") is String):valid=false
	if not valid:
		var rejected:Dictionary=fallback.duplicate(true)
		rejected.error={"code":"INVALID_FACTORY_PROJECTION","method":method}
		return rejected
	var result:Dictionary=fallback.duplicate(true)
	result.merge(value.duplicate(true),true)
	return result

func movable_facility(stock_id:String)->Dictionary:
	# An on-demand UI association for a currently public container. No ID/name
	# inference, general furniture catalogue, or cached movement permission.
	var unavailable:Dictionary={"available":false,"stock_id":stock_id,"can_move":false,"code":"UNAVAILABLE","reason":"当前没有可用的储物柜关联"}
	if _retired or not Data.valid_id(stock_id) or actor("player").is_empty():return unavailable
	var visible:Dictionary={}
	var display:Dictionary=snapshot()
	for candidate:Dictionary in display.stocks:
		if candidate.get("id")==stock_id and candidate.get("searched",false):visible=candidate;break
	var structure_id:String=str(visible.get("structureId",""))
	var buildings:Variant=_services.get("buildings")
	var production:Variant=_services.get("production")
	if structure_id.is_empty() or buildings==null or production==null:return unavailable
	var piece:Dictionary=buildings.instance(structure_id)
	if piece.get("definitionId")!="cabinet" or buildings.permission("player",structure_id,"move",piece)!=null:return unavailable
	var tool_id:String=""
	for tool_row:Dictionary in display.tools:
		if tool_row.get("holderId")=="pack:player" and float(tool_row.get("durability",0))>0 and float(production.tool_qualities(tool_row).get("hammering",0))>0:tool_id=str(tool_row.id);break
	var ready:Dictionary=availability({"actor_id":"player","kind":"structure","target_id":structure_id,"payload":{"kind":"move","destination":piece.duplicate(true),"source_id":"pack:player","output_id":"pack:player","tool_id":tool_id}})
	return {"available":true,"stock_id":stock_id,"structure_id":structure_id,"definition_id":"cabinet","can_move":ready.get("ok",false),"code":ready.get("code","UNAVAILABLE"),"reason":ready.get("reason")}

func snapshot() -> Dictionary:
	return _display_snapshot(true)

var _hud_snapshot_basis:Array=[]
var _hud_snapshot_value:Dictionary={}
var _hud_snapshot_facts:Dictionary={}
var _village_display_basis: Array = []
var _village_display_quests: Array = []
var _village_display: Dictionary = {}

func hud_snapshot(companions_only:bool=false)->Dictionary:
	# Hover, held-key and focus changes do not advance authority. Reuse only the
	# small HUD core for that exact authority/clock/world observation; target,
	# hand and save notifications remain fresh even without a revision change.
	var basis:Array=[world.get_instance_id() if world!=null else 0,world.get_revision() if world!=null else -1,_revision,clock(),_paused,_retired,_hand.get("slots",[]),companions_only]
	if basis!=_hud_snapshot_basis or not is_same(_facts,_hud_snapshot_facts):
		_hud_snapshot_value=_hud_minimal_snapshot(companions_only)
		_hud_snapshot_basis=basis.duplicate(true);_hud_snapshot_facts=_facts
	var result:Dictionary=_hud_snapshot_value.duplicate(true)
	result.target=_target.duplicate(true);result.hand=_hand.duplicate(true)
	result.save=_context.get("save_state",{}).duplicate(true)
	result.simulation=simulation_budget()
	return result

func _hud_minimal_snapshot(companions_only:bool=false)->Dictionary:
	var player:Dictionary=actor("player")
	var actors:Array=[]
	for entry:Dictionary in _facts.get("actors",[]):
		if entry.id=="player" or entry.get("relationship",{}).get("member",false) or (not companions_only and _social_reach(player,entry,6.0)):actors.append(entry.duplicate(true))
	var pack:Dictionary=stock("pack:player")
	var fields:Array[String]=["tools","orders","knowledge"]
	var production:Dictionary=world.extension_fields("r3:production",fields) if world!=null and world.has_method("extension_fields") else world.extension("r3:production") if world!=null else {}
	var tools:Array=[]
	for entry:Dictionary in production.get("tools",[]):
		if str(entry.get("holderId",""))=="pack:player":tools.append(entry)
	var reserved:Dictionary={"items":{},"tool_ids":[]}
	var held_tools:Dictionary={}
	var service:Variant=_services.get("production")
	if service!=null:
		var started:int=preload("res://scripts/runtime/frame_costs.gd").begin()
		var holds: Array = service.hud_holds(_facts.actors) if service.has_method("hud_holds") else service.all_holds()
		for hold:Dictionary in holds:
			if hold.intent_id=="":continue
			if hold.source_id=="pack:player":
				for item:String in hold.cost:reserved.items[item]=float(reserved.items.get(item,0))+float(hold.cost[item])
			for id:String in hold.tool_ids:held_tools[id]=true
		preload("res://scripts/runtime/frame_costs.gd").end("hud/hold_descriptors",started)
		for entry:Dictionary in tools:
			entry.reserved=held_tools.has(str(entry.id))
			if entry.reserved:reserved.tool_ids.append(entry.id)
		pack.reserved=reserved
	var orders:Array=[]
	for order:Dictionary in production.get("orders",[]):
		if order.get("actorId")=="player":orders.append(order)
	var work_fields:Array[String]=["orders"]
	var construction:Dictionary=world.extension_fields("r3:structure-orders",work_fields) if world!=null and world.has_method("extension_fields") else {}
	for order:Dictionary in construction.get("orders",[]):
		if order.get("actorId")=="player":orders.append(order)
	var result:Dictionary={"schema":"afterglow-display-v1","revision":_revision,"command_revision":_revision,"time":clock(),"status":_facts.get("status"),"actors":actors,"player":player,"stocks":[pack],"tools":tools,"knowledge":{"player":production.get("knowledge",{}).get("player",[]).duplicate()},"records":[],"quests":_facts.get("quests",[]).duplicate(true),"orders":orders,"work_targets":[],"regions":[],"catalog":_hud_catalog(),"movement":_movement_display(),"playtest":_source.get("playtest",{}).duplicate(true),"opening_profile":_source.get("opening_profile","playtest" if not _source.get("playtest",{}).is_empty() else "normal")}
	var gameplay:Variant=_services.get("gameplay")
	if gameplay!=null and gameplay.has_method("display"):result.merge(gameplay.display(),true)
	result.player_work=_actor_work_projection(player)
	var village:Dictionary=_village_display_snapshot()
	if village.get("available",false):result.village=village;result.radio=village.get("radio",{})
	return result

func _village_display_snapshot() -> Dictionary:
	if not world.has_method("extension_token"):
		return VillageProgression.snapshot(_facts, world)
	# The projection reads village flags and landmarks, radio state, workshop
	# instances, tool ownership, and quest progress. Clock and movement alone
	# leave those inputs unchanged. Tokens also fence world replacement/load.
	var basis: Array = []
	for id: String in [VillageProgression.KEY, "r33:gameplay", "r34:modules", "r3:production"]:
		basis.append(world.extension_token(id))
	var quests: Array = _facts.get("quests", [])
	if basis != _village_display_basis or quests != _village_display_quests:
		_village_display_basis = basis
		_village_display_quests = quests.duplicate(true)
		_village_display = VillageProgression.snapshot(_facts, world)
	return _village_display.duplicate(true)

func _display_snapshot(details:bool,page:String="",subject:String="")->Dictionary:
	var personal_pack := page == "factory_inventory" and subject in ["", "pack:player"]
	var player: Dictionary = actor("player")
	var actors: Array = []
	var stocks: Array = []
	for a: Dictionary in _facts.get("actors",[]):
		if a.id=="player" or a.get("relationship",{}).get("member",false) or _social_reach(player,a,6.0):actors.append(a.duplicate(true))
	stocks.append(stock("pack:player"))
	for member:Dictionary in _facts.get("actors",[]):
		if not details or personal_pack or member.id=="player" or not member.get("relationship",{}).get("member",false) or not member.get("relationship",{}).get("consent",false):continue
		var pack:Dictionary=stock("pack:"+str(member.id))
		if _services.get("production")!=null and _services.production.reach("player",str(pack.id),pack,"handoff")==null:stocks.append(pack)
	for s: Dictionary in _facts.get("stocks",[]):
		if not details or personal_pack or not s.get("searched",false):continue
		var at:Dictionary=s.get("location",{})
		if _near(player,at,3.0) and player.get("buildingId")==at.get("buildingId") and player.get("storeyId")==at.get("storeyId"):stocks.append(s.duplicate(true))
		# Module stock uses the same real building contact as take/deposit. A
		# nearby building's far-side buffer is not a remote-only summary.
		elif (s.has("module_id") or player.regionId!=at.get("regionId")) and _services.get("production")!=null and _services.production.reach("player",str(s.id),s,"inspect")==null:stocks.append(s.duplicate(true))
	var production_fields:Array[String]=["tools","records","orders","knowledge"]
	var production: Variant = world.extension_fields("r3:production",production_fields) if world.has_method("extension_fields") else world.extension("r3:production") if world.has_method("extension") else null
	var tools: Array=[]
	if production is Dictionary:
		for t: Dictionary in production.get("tools",[]):
			if str(t.get("holderId",""))=="pack:player" or stocks.any(func(s:Dictionary)->bool:return s.id==t.get("holderId")): tools.append(t.duplicate(true))
	var records:Array=[]
	var orders:Array=[]
	var knowledge:Dictionary={}
	if production is Dictionary:
		knowledge["player"]=production.get("knowledge",{}).get("player",[]).duplicate()
		for record:Dictionary in production.get("records",[]):
			if stocks.any(func(s:Dictionary)->bool:return s.id==record.get("holderId")):records.append(record.duplicate(true))
		orders=production.get("orders",[]).filter(func(o:Dictionary)->bool:return o.get("actorId")=="player").duplicate(true)
	var construction:Variant=world.extension("r3:structure-orders")
	if construction is Dictionary:orders.append_array(construction.get("orders",[]).filter(func(o:Dictionary)->bool:return o.get("actorId")=="player").duplicate(true))
	var production_service:Variant=_services.get("production")
	if production_service!=null:
		# One immutable synchronous observation for the entire display read.
		# All original holds participate; no command uses this derived index.
		var held_items:Dictionary={};var held_tools:Dictionary={}
		for hold:Dictionary in production_service.all_holds():
			if hold.intent_id=="":continue
			if not held_items.has(hold.source_id):held_items[hold.source_id]={}
			for item:String in hold.cost:held_items[hold.source_id][item]=float(held_items[hold.source_id].get(item,0))+float(hold.cost[item])
			for id:String in hold.tool_ids:held_tools[id]=true
		for s:Dictionary in stocks:
			var reserved:Dictionary={"items":{},"tool_ids":[]}
			for key:String in s.get("items",{}):reserved.items[key]=float(held_items.get(str(s.id),{}).get(key,0))
			for t:Dictionary in tools:
				if t.get("holderId")==s.id:
					t.reserved=held_tools.has(str(t.id))
					if t.reserved:reserved.tool_ids.append(t.id)
			s.reserved=reserved
	var result:Dictionary={"schema":"afterglow-display-v1","revision":_revision,"command_revision":_revision,"time":clock(),"status":_facts.get("status"),"actors":actors,"player":player,"stocks":stocks,"tools":tools,"knowledge":knowledge,"records":records,"quests":_facts.get("quests",[]).duplicate(true),"orders":orders,"work_targets":work_targets() if details and page.is_empty() else [],"regions":world.regions() if details and page.is_empty() else [],"target":_target.duplicate(true),"hand":_hand.duplicate(true),"catalog":(_catalog() if details else _hud_catalog()) if page.is_empty() else _page_catalog(page),"save":_context.get("save_state",{}).duplicate(true)}
	var gameplay:Variant=_services.get("gameplay")
	result.simulation=simulation_budget()
	result.movement=_movement_display()
	result.playtest=_source.get("playtest",{}).duplicate(true)
	result.opening_profile=_source.get("opening_profile","playtest" if not result.playtest.is_empty() else "normal")
	if gameplay!=null and gameplay.has_method("display"):result.merge(gameplay.display(),true)
	var village:Dictionary=_village_display_snapshot()
	if village.get("available",false):
		result.village=village
		result.radio=village.get("radio",{})
	return result

func capture_checkpoint() -> Dictionary:
	return {"schema":"afterglow-native-state-v1","command_revision":_revision,"world":world.snapshot(),"facts":facts(),"source":_source.duplicate(true),"content":_content_lock.duplicate(true),"receipts":_receipts.duplicate(true),"simulation":{"remainder":_remainder}}
func save_async(request_id: String="") -> Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	return await _context.save_async.call(request_id)
func start_new_world(seed:int=-1,request_id:String="") -> Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	if not _context.get("start_new_world") is Callable:return _failure("UNAVAILABLE","世界装配入口未接入")
	return await _context.start_new_world.call(seed,request_id)
func start_profiled_world(profile:String,seed:int=-1,request_id:String="")->Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	if not _context.get("start_profiled_world") is Callable:return _failure("UNAVAILABLE","新世界配置入口未接入")
	return await _context.start_profiled_world.call(profile,seed,request_id)
func restore_saved_world(request_id:String="")->Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	if not _context.get("restore_saved_world") is Callable:return _failure("UNAVAILABLE","明确恢复入口未接入")
	return await _context.restore_saved_world.call(request_id)
func list_recovery_candidates(expected_world_id:String="")->Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	if not _context.get("list_recovery_candidates") is Callable:return _failure("UNAVAILABLE","恢复候选入口未装配")
	return _context.list_recovery_candidates.call(expected_world_id)
func restore_recovery_candidate(candidate_id:String,sha256:String,request_id:String="")->Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	if not _context.get("restore_recovery_candidate") is Callable:return _failure("UNAVAILABLE","明确选档入口未装配")
	return await _context.restore_recovery_candidate.call(candidate_id,sha256,request_id)
func import_checkpoint(text: String,request_id: String="") -> Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	return await _context.import_checkpoint.call(text,request_id)
func import_checkpoint_file(path: String,request_id: String="") -> Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	return await _context.import_checkpoint_file.call(path,request_id)
func export_checkpoint_file(path: String,request_id: String="") -> Dictionary:
	if _retired:return _failure("WORLD_RETIRED","此世界已被替换")
	return await _context.export_checkpoint_file.call(path,request_id)
func retry_close() -> void:
	if _retired:return
	_context.retry_close.call()
func cancel_close() -> void:
	if _retired:return
	_context.cancel_close.call()
func _hud_catalog()->Dictionary:
	# Hotbar needs tool names/limits and only explicitly bound build recipes.
	var source:Dictionary=_context.get("definitions",{})
	var definitions:Dictionary={}
	var wanted:Dictionary={}
	for ref:Dictionary in _hand.get("slots",[]):
		if ref.get("kind")=="recipe":wanted[str(ref.get("definition_id",ref.get("id","")))]=true
	var building:Variant=_services.get("buildings")
	if not wanted.is_empty() and building!=null:
		for row:Dictionary in building.catalog():
			if wanted.has(str(row.id)):definitions[row.id]=row
	return {"tool_definitions":source.get("tool_definitions",{}).duplicate(true),"buildings":definitions}

func _catalog() -> Dictionary:
	var building: Variant = _services.get("buildings")
	var definitions:Dictionary=_context.get("definitions",{}).duplicate(true)
	definitions.items=Content.item_definitions()
	definitions.buildings=building.catalog() if building!=null and building.has_method("catalog") else []
	return definitions
func _find(collection: String,id: String) -> Dictionary:
	for entry: Dictionary in _facts.get(collection,[]):
		if str(entry.get("id",""))==id: return entry
	return {}
func _continuous_near(a:Dictionary,b:Dictionary,radius:float)->bool:
	if a.is_empty() or b.is_empty() or Vector3(a.x,a.y,a.z).distance_to(Vector3(b.x,b.y,b.z))>radius:return false
	if world.has_method("continuous_outdoor_segment"):return world.continuous_outdoor_segment(_location(a),_location(b),radius,true).ok
	return world.has_method("continuous_outdoor_contact") and world.continuous_outdoor_contact(_location(a),_location(b)).ok
func _social_reach(a:Dictionary,b:Dictionary,radius:float)->bool:
	if not _near(a,b,radius) and not _continuous_near(a,b,radius):return false
	var building:Variant=_services.get("buildings")
	return building!=null and building.current_space().line_clear(_location(a),_location(b),str(b.get("id","")))
static func _near(a: Dictionary,b: Dictionary,radius: float) -> bool:
	if a.is_empty() or b.is_empty() or a.get("regionId",a.get("region_id")) != b.get("regionId",b.get("region_id")): return false
	return Vector3(float(a.get("x",0)),float(a.get("y",0)),float(a.get("z",0))).distance_to(Vector3(float(b.get("x",0)),float(b.get("y",0)),float(b.get("z",0))))<=radius
static func _location(a: Dictionary) -> Dictionary:
	return {"x":a.get("x",0),"y":a.get("y",0),"z":a.get("z",0),"regionId":a.get("regionId"),"buildingId":a.get("buildingId"),"storeyId":a.get("storeyId")}
func _success(extra: Dictionary={}) -> Dictionary:
	var value: Dictionary={"ok":true,"code":"OK","reason":null,"revision":_revision}
	value.merge(extra,true);return value
func _failure(code: String,reason: String) -> Dictionary:
	return {"ok":false,"code":code,"reason":reason,"revision":_revision}
static func _number(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _normalize_actor_compat(a:Dictionary)->void:
	# Explicit old-save/ordinary-actor adapter. Never coerce a bad typed value.
	if a.get("skills")==null:a.skills={}
	if a.get("relationship")==null:a.relationship={}

func _request_schema(request:Dictionary)->Dictionary:
	if not request.get("kind") is String or str(request.kind).is_empty():return _failure("INVALID_COMMAND_SCHEMA","动作类型须为非空字符串")
	if not FactoryContracts.valid_command_kind(request.kind):return _failure("INVALID_COMMAND_SCHEMA","生产命令缺少具体操作")
	if request.has("actor_id") and not Data.valid_id(request.actor_id):return _failure("INVALID_COMMAND_SCHEMA","角色身份无效")
	if not request.get("payload",{}) is Dictionary:return _failure("INVALID_COMMAND_SCHEMA","动作参数须为对象")
	if request.has("expected_revision") and (not _number(request.expected_revision) or float(request.expected_revision)<0 or float(request.expected_revision)!=floorf(float(request.expected_revision))):return _failure("INVALID_COMMAND_SCHEMA","请求修订须为非负整数")
	return _success()
static func _items_valid(items:Variant) -> bool:
	if not items is Dictionary:return false
	for key:Variant in items:
		if not Data.valid_id(key) or not _number(items[key]) or float(items[key])<0:return false
		if not Content.quantity_valid(str(key),items[key],true):return false
	return true
static func validate_facts(data: Dictionary) -> Dictionary:
	return _validate_fact_schema(data,false)

static func _validate_fact_schema(data:Dictionary,unchanged_stocks:bool)->Dictionary:
	var bad:Dictionary={"ok":false,"code":"INVALID_FACTS","reason":"运行时事实、物资或身份无效"}
	if not data.get("actors") is Array or not data.get("stocks") is Array or not data.get("actions") is Array or not _number(data.get("time")) or float(data.time)<0:return bad
	if data.actors.size()>1024 or data.stocks.size()>8192 or data.actions.size()>8192:return bad
	if data.get("status","playing") not in ["playing","dead","won","lost"]:return bad
	var ids:Dictionary={}
	for a:Variant in data.actors:
		if not a is Dictionary or not Data.valid_id(a.get("id")) or ids.has(a.id) or not _items_valid(a.get("pack")) or not Data.vec(a) or not Data.valid_id(a.get("regionId")):return bad
		ids[a.id]=true
		if a.has("max_hp") and (not _number(a.max_hp) or float(a.max_hp)<=0):return bad
		for key:String in ["cooldown","nextDecision"]:
			if a.has(key) and (not _number(a[key]) or float(a[key])<0):return bad
		for key:String in ["hp","hunger","thirst","fatigue","stamina"]:
			if not _number(a.get(key)) or float(a[key])<0 or float(a[key])>float(a.get("max_hp",100) if key=="hp" else 100):return bad
		for key:String in ["buildingId","storeyId"]:
			if a.get(key)!=null and not Data.valid_id(a[key]):return bad
		if a.get("intent")!=null and not a.intent is Dictionary:return bad
		if a.get("relationship")!=null and not a.relationship is Dictionary:return bad
		if a.get("relationship") is Dictionary:
			for key:String in ["member","consent","met","helped","home_arrived"]:
				if a.relationship.has(key) and not a.relationship[key] is bool:return bad
		if a.has("work_payload") and not a.work_payload is Dictionary:return bad
		if a.get("skills")!=null:
			if not a.skills is Dictionary or not a.skills.values().all(func(n:Variant)->bool:return _number(n) and float(n)>=0):return bad
	if not ids.has("player"):return bad
	if not unchanged_stocks:
		var stock_ids:Dictionary={}
		for stock:Variant in data.stocks:
			if not stock is Dictionary or not Data.valid_id(stock.get("id")) or stock_ids.has(stock.id) or str(stock.id).begins_with("pack:") or not _items_valid(stock.get("items")) or not Data.vec(stock.get("location")) or not Data.valid_id(stock.location.get("regionId")):return bad
			stock_ids[stock.id]=true
	for collection:String in ["actions","quests"]:
		if not data.get(collection,[]) is Array:return bad
		var seen:Dictionary={}
		for entry:Variant in data.get(collection,[]):
			if not entry is Dictionary or not Data.valid_id(entry.get("id")) or seen.has(entry.id):return bad
			seen[entry.id]=true
	return {"ok":true}
