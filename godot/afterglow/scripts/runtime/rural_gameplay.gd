extends RefCounted
## Project rules only: same A actors/inventory/clock, same B movement and C world.
## Finite encounters, decisions and settlement are checkpoint facts, never UI RNG.
const Draft = preload("res://scripts/actions/domain_draft.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Initial = preload("res://scripts/runtime/initial_state.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Content = preload("res://scripts/runtime/content_definitions.gd")
const Village=preload("res://scripts/runtime/village_progression.gd")
const Expedition = preload("res://scripts/runtime/village_expedition.gd")
const Night = preload("res://scripts/runtime/village_night_defense.gd")
const KEY := "r33:gameplay"
const HOME := "rural:v1:RH-HOME:old-house"
const GATE := HOME+":yard-gate"
const MELEE_REACH := 2.05
const SWING_STAMINA := 14.0
const SWING_WEAR := 0.4
const SWING_WINDUP := 0.1 # One A simulation step.
const SWING_RECOVERY := 0.48
const CHOICES := {
	"shove":{"name":"重心打击","description":"命中后把敌人向后推0.8m；碰到墙和门会停下。"},
	"chain":{"name":"顺势连击","description":"同次挥击可命中面前两个目标。可与击退或控制组合。"},
	"stagger":{"name":"压制节奏","description":"命中后使敌人停顿0.6秒，争取移动和换位时间。"},
	"guard":{"name":"稳住架势","description":"本趟受到近战伤害减少25%。"}}
var context: Dictionary={}
var _actions: WeakRef
var _production: WeakRef
var _modules: WeakRef
var _next_quest_check := 0.0
var _walker_path_budget:int=1
var _experience14:bool=false
var _ambient_opening_walkers:bool=false
var _expedition_enabled := false
var night_screen_test: Callable
var night_next_check := 0.0

static func initial(layout:Dictionary={}) -> Dictionary:
	var state:Dictionary={"version":1,"last_event_revision":-1,"flags":{},"next_run":1,
		"encounters":[{"id":"village-road","position":{"x":32.0,"y":0.0,"z":-10.0,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null},"spawned":false,"cleared":false,"actors":[],"choice_issued":false},
			{"id":"repair-road","position":{"x":32.0,"y":0.0,"z":-33.0,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null},"spawned":false,"cleared":false,"actors":[],"choice_issued":false}],
		"exploration":{"status":"idle","run_id":"","upgrades":[],"candidates":[],"stages":0,"loot_collected":0,"started_at":0.0,"settled":[],"earned_choices":[]},
		"defense":{"status":"dormant","warning_at":0.0,"arrival_at":0.0,"actors":[]},
		"radio":{"status":"unrepaired","station_id":"","signal":0.0}}
	if not layout.is_empty():
		state.layout=layout.duplicate(true)
		for i:int in mini(state.encounters.size(),layout.get("encounter_positions",[]).size()):state.encounters[i].position=layout.encounter_positions[i].duplicate(true)
	return state

func configure(value:Dictionary) -> void:
	context=preload("res://scripts/actions/domain_context.gd").isolate(value)
	var version_fields:Array[String]=["content_version"]
	var generation:Dictionary=context.world.extension_fields("generation:factory-r34",version_fields) if context.world.has_method("extension_fields") else {}
	_expedition_enabled = int(generation.get("content_version", 0)) >= 21
	_experience14=int(generation.get("content_version",0)) in [14,15,16,17,18,19,20,21]
	_ambient_opening_walkers=_experience14 and int(generation.get("content_version",0))<20
	_actions=weakref(value.services.actions)
	_production=weakref(value.services.production)
	var modules:Variant=value.get("services",{}).get("modules")
	_modules=weakref(modules) if modules is RefCounted else null

func validate_intent(intent:Dictionary,actor_state:Dictionary={},_facts_state:Dictionary={})->Dictionary:
	var bad:Dictionary=_no("INVALID_GAMEPLAY_INTENT","通信行动描述无效")
	if _facts_state.get("scenario")=="factory-settlement-r34" and not _village_enabled():return _no("SCENARIO_UNAVAILABLE","当前场景没有村庄电台工作")
	var version:Variant=intent.get("schema_version",0)
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) not in [0.0,1.0]:return bad
	if intent.get("owner")!="gameplay" or intent.get("kind")!="radio" or not Data.valid_id(intent.get("id")) or intent.get("operation") not in ["repair","transmit"] or not Data.valid_id(intent.get("target_id")):return bad
	if intent.has("phase") and intent.phase not in ["active","paused"]:return bad
	if not actor_state.is_empty() and intent.get("source_id")!="pack:"+str(actor_state.get("id","")):return bad
	if not Data.valid_id(intent.get("source_id")) or not intent.get("cost") is Dictionary:return bad
	var repair:bool=intent.operation=="repair"
	# Native JSON restores integer quantities as floats. Validate the exact
	# finite quantities, rather than Dictionary's representation-sensitive ==.
	if repair:
		if intent.cost.size()!=2 or not intent.cost.has_all(["scrap","tool_handle"]):return bad
		for item:String in ["scrap","tool_handle"]:
			var quantity:Variant=intent.cost[item]
			if not Content.quantity_valid(item,quantity) or float(quantity)!=(8.0 if item=="scrap" else 1.0):return bad
	elif not intent.cost.is_empty():return bad
	if not intent.get("tool_id") is String or (repair and not Data.valid_id(intent.tool_id)):return bad
	for field:String in ["elapsed","duration"]:
		var value:Variant=intent.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0:return bad
	if float(intent.duration)!=(20.0 if repair else 30.0) or float(intent.elapsed)>float(intent.duration)+0.000001:return bad
	return _ok()

func hold_descriptors(facts:Dictionary,_extension_overrides:Dictionary={})->Array:
	var result:Array=[]
	for a:Dictionary in facts.get("actors",[]):
		var intent:Variant=a.get("intent")
		if float(a.get("hp",0))<=0 or not intent is Dictionary or intent.get("owner")!="gameplay" or not validate_intent(intent,a,facts).ok:continue
		var repair:bool=intent.operation=="repair"
		result.append({"schema_version":1,"owner":"gameplay","intent_id":intent.id,"actor_id":a.id,"phase":"paused" if float(a.get("stamina",0))<=0 else "active","source_id":intent.source_id if repair else "","cost":intent.cost.duplicate(true) if repair else {},"tool_ids":[intent.tool_id] if repair else [],"use_target_id":intent.target_id})
	return result

func _active() -> bool:
	if context.get("scenario") is Callable:return context.scenario.call()=="rural-home-r33"
	return context.facts.call().get("scenario")=="rural-home-r33"
func _village_layout()->Dictionary:
	if context.get("world")==null:return {}
	var value:Variant=context.world.extension("r34:gameplay")
	return value.get("layout",{}) if value is Dictionary else {}
func _village_enabled()->bool:
	if context.get("world")==null:return false
	if context.world.has_method("extension_fields"):
		var fields:Array[String]=["content_version"]
		var generation:Variant=context.world.extension_fields("generation:factory-r34",fields)
		if generation is Dictionary and generation.has("content_version"):return int(generation.content_version) in [13,14,15,16,17,18,19,20,21]
	return Village.enabled(_village_layout())
func _state() -> Dictionary:
	var value:Variant=context.world.extension(KEY)
	if not value is Dictionary:return initial(_village_layout())
	if not value.has("radio"):value.merge(initial(_village_layout()))
	return value
func _ok() -> Dictionary:return {"ok":true,"code":"OK","reason":null}
func _no(code:String,reason:String) -> Dictionary:return {"ok":false,"code":code,"reason":reason}
static func at_home(a:Dictionary) -> bool:
	return a.get("regionId")=="RH-HOME" and Vector2(float(a.get("x",0))-22,float(a.get("z",0))-39).length()<18
func _at_home(a:Dictionary) -> bool:
	if _village_enabled():return a.get("regionId")=="RH-HOME"
	var layout:Dictionary=_state().get("layout",{})
	if layout.is_empty():return at_home(a)
	var home:Dictionary=layout.home
	return a.get("regionId")==home.regionId and Vector2(float(a.x)-float(home.x),float(a.z)-float(home.z)).length()<float(layout.get("home_radius",18))
func _layout_id(key:String,fallback:String)->String:
	return str(_state().get("layout",{}).get(key,fallback))
func _near(a:Dictionary,b:Dictionary,r:float) -> bool:
	if a.is_empty() or b.is_empty() or Geometry.point(a).distance_to(Geometry.point(b))>r:return false
	if a.get("regionId")==b.get("regionId"):return true
	# Spatial coverage is distinct from both the rule's range and B's sight.
	# In particular 7m/12m awareness must not inherit the 2.5m hand limit.
	return context.world.continuous_outdoor_segment(Geometry.location(a),Geometry.location(b),r,true).ok
func _clear(a:Dictionary,b:Dictionary) -> bool:
	# B raises foot locations to eye height itself; raising them twice can
	# incorrectly see/strike over real cover.
	return context.spatial.current_space().line_clear(Geometry.location(a),Geometry.location(b),"")
func _tool(request:Dictionary) -> Dictionary:
	var id:String=str(request.get("payload",{}).get("tool_id",""))
	return context.tool.call(id) if not id.is_empty() else {}

func _radio_station(a:Dictionary,id:String,staged:Dictionary={},excluding:String="",tx:RefCounted=null)->Dictionary:
	if _village_enabled() and id!=Village.radio_station(context.world):return _no("NO_STATION","需要旧村手工棚的真实通信工位")
	var bench:Dictionary=context.spatial.instance(id)
	if bench.is_empty() or float(bench.get("hp",0))<=0 or context.spatial.geometry.definition(bench).get("kind")!="workbench":return _no("NO_STATION","需要真实建成的旧宅工作台")
	var permission:Variant=context.spatial.permission(str(a.id),id,"use",bench,staged)
	if permission!=null:return _no("FORBIDDEN",str(permission))
	if _production.get_ref().use_reserved(id,excluding,tx):return _no("RESERVED","通信工位正在被使用")
	var contact:Variant=context.spatial.can_use(str(a.id),bench,{},staged)
	return _ok() if contact==null else _no("OUT_OF_REACH",str(contact))

func availability(request:Dictionary) -> Dictionary:
	if str(request.get("kind", "")).begins_with("night."):
		return Night.check(self, request) if _expedition_enabled else _no("SCENARIO_UNAVAILABLE", "此存档没有守夜循环")
	if str(request.get("kind", "")) in ["expedition.depart", "expedition.open"] and _expedition_enabled and Night.busy(Night.snapshot(self)):
		return _no("NIGHT_ACTIVE", "守夜结束后再出征")
	if str(request.get("kind", "")).begins_with("expedition."):
		return Expedition.check(self, request) if _expedition_enabled else _no("SCENARIO_UNAVAILABLE", "此存档没有村口补给站")
	var factory:bool=context.facts.call().get("scenario")=="factory-settlement-r34"
	if not _active() and (not factory or (request.get("kind")!="attack" and not (request.get("kind")=="radio" and _village_enabled()))):return _no("SCENARIO_UNAVAILABLE","当前地区仅开放现场战斗与本村电台，旧探索保持独立")
	var a:Dictionary=context.actor.call(str(request.get("actor_id","player")))
	if a.is_empty() or float(a.hp)<=0:return _no("ACTOR_UNAVAILABLE","角色无法行动")
	var state:=_state()
	var kind:String=str(request.get("kind",""))
	var payload:Dictionary=request.get("payload",{})
	if kind=="explore_start":
		if not _at_home(a):return _no("RETURN_HOME","先回旧宅整备再开始探索")
		if state.exploration.status=="running":return _no("ACTIVE_EXPLORATION","本次探索尚未明确结算")
		if not state.encounters.any(func(e:Dictionary)->bool:return not e.cleared):return _no("NO_NEW_OBJECTIVE","本片新目标已清理；原战利品不会刷新")
		return _ok()
	if kind=="explore_choose":
		if state.exploration.status!="running" or not state.exploration.candidates.has(str(payload.get("choice_id",""))):return _no("INVALID_CHOICE","该候选不存在或已经选择，读档不能重抽")
		return _ok()
	if kind=="explore_end":
		if not _at_home(a):return _no("RETURN_HOME","实际返回旧宅后才能结算")
		if state.exploration.status!="running":return _no("NO_EXPLORATION","当前没有待结算探索")
		if not state.exploration.candidates.is_empty():return _no("CHOOSE_FIRST","先处理本次遭遇已经获得的选择，再明确结算")
		return _ok()
	if kind=="defend":
		if state.defense.status!="warning" or not _at_home(a):return _no("NO_WARNING","收到预警并回到旧宅后才能迎战")
		return _ok()
	if kind=="attack":
		return _attack_availability(request, a, factory)
	if kind=="radio":
		if factory:
			var village_state:Dictionary=context.world.extension("r34:gameplay")
			var missing:=Village.radio_missing(village_state)
			if not missing.is_empty():return _no("VILLAGE_SUPPLY_REQUIRED","电台整备还需要："+"、".join(missing))
		elif state.defense.status!="cleared":return _no("DEFENSE_REQUIRED","先处理已预警的有限来袭")
		if not _at_home(a):return _no("RETURN_HOME","通信设备在旧宅工作台整备")
		if a.get("intent")!=null:return _no("BUSY","先完成当前作业")
		var operation:String=str(payload.get("operation","repair"))
		if operation not in ["repair","transmit"]:return _no("INVALID_OPERATION","通信行动参数无效")
		if operation=="transmit":
			if state.radio.status!="repaired":return _no("RADIO_NOT_READY","先完成实际维修")
			if request.get("target_id")!=state.radio.station_id:return _no("NO_STATION","需要原通信工位")
			return _radio_station(a,str(state.radio.station_id))
		if state.radio.status!="unrepaired":return _no("RADIO_READY","通信设备已经维修，不重复扣料")
		var station:Dictionary=_radio_station(a,str(request.get("target_id","")))
		if not station.ok:return station
		var production:Dictionary=context.world.extension("r3:production")
		if not production.get("knowledge",{}).get(a.id,[]).has("basic_tool_repair"):return _no("KNOWLEDGE","先从真实手册学会基础维修")
		for item:String in ["scrap","tool_handle"]:
			var required:int=8 if item=="scrap" else 1
			if float(a.pack.get(item,0))-_production.get_ref().reserved("pack:"+str(a.id),item)<required:return _no("NO_MATERIAL","维修需要废料8、工具柄1，不能使用已预留物资")
		var tool:=_tool(request)
		if tool.is_empty() or tool.get("holderId")!="pack:"+str(a.id) or float(tool.durability)<=0 or float(_production.get_ref().tool_qualities(tool).get("hammering",0))<1 or _production.get_ref().tool_unavailable(str(tool.id)):return _no("MISSING_TOOL","需要随身可用手锤")
		return _ok()
	return _no("UNKNOWN_GAMEPLAY","未知游戏行动")

func prepare(request:Dictionary) -> Dictionary:
	var ready:=availability(request)
	if not ready.ok:return ready
	var tx:=Draft.new(context)
	if str(request.kind).begins_with("night."):
		return Night.execute(self, tx, request)
	if str(request.kind).begins_with("expedition."):
		return Expedition.execute(self, tx, request)
	var factory:bool=tx.staged.get("scenario")=="factory-settlement-r34"
	var state:Dictionary={"exploration":{"status":"idle","upgrades":[]}} if factory and request.get("kind")!="radio" else tx.extension(KEY,initial(_village_layout()))
	var a:Dictionary=tx.actor(str(request.get("actor_id","player")))
	var payload:Dictionary=request.get("payload",{})
	match str(request.kind):
		"explore_start":
			var settled:Array=state.exploration.settled.duplicate(true)
			state.exploration={"status":"running","run_id":"exploration:%s"%state.next_run,"upgrades":[],"candidates":[],"stages":0,"loot_collected":0,"started_at":context.clock.call(),"settled":settled}
			state.next_run=int(state.next_run)+1
			tx.events.append({"kind":"exploration-started","actor_id":a.id,"run_id":state.exploration.run_id})
		"explore_choose":
			state.exploration.upgrades.append(str(payload.choice_id));state.exploration.candidates=[]
			tx.events.append({"kind":"exploration-choice","actor_id":a.id,"choice_id":payload.choice_id})
		"explore_end":
			var prior_choices:int=0
			var prior_loot:int=0
			for previous:Dictionary in state.exploration.settled:
				prior_choices+=int(previous.get("choices",0));prior_loot+=int(previous.get("loot_collected",0))
			var complete:bool=state.encounters.all(func(e:Dictionary)->bool:return e.cleared) and prior_choices+state.exploration.upgrades.size()>=2 and prior_loot+int(state.exploration.loot_collected)>0
			state.exploration.settled.append({"run_id":state.exploration.run_id,"at":context.clock.call(),"upgrades":state.exploration.upgrades.duplicate(),"stages":state.exploration.stages,"loot_collected":state.exploration.loot_collected,"choices":state.exploration.upgrades.size(),"complete":complete})
			state.exploration.status="settled";state.exploration.upgrades=[];state.exploration.candidates=[]
			if complete:
				state.flags.exploration_completed=true
				if state.defense.status=="dormant":state.defense={"status":"warning","warning_at":context.clock.call(),"arrival_at":float(context.clock.call())+60,"actors":[]}
			tx.events.append({"kind":"exploration-settled","actor_id":a.id,"complete":complete})
		"defend":state.defense.arrival_at=context.clock.call()
		"attack":
			var target_id: String = request.get("target_id", "")
			var tool_id: String = payload.get("tool_id", "")
			if payload.get("manual_aim", false):
				_begin_swing(tx, a, target_id, tool_id, payload.get("aim", {}))
			else:
				_strike(tx, a, target_id, tool_id, state)
		"radio":
			var operation:String=str(payload.get("operation","repair"))
			if not state.has("radio"):state.merge(initial(_village_layout()))
			state.radio.station_id=request.get("target_id","")
			a.intent={"schema_version":1,"owner":"gameplay","kind":"radio","id":request.command_id,"source_id":"pack:"+str(a.id),"cost":{"scrap":8,"tool_handle":1} if operation=="repair" else {},"operation":operation,"target_id":request.get("target_id",""),"tool_id":payload.get("tool_id",""),"elapsed":0.0,"duration":30.0 if operation=="transmit" else 20.0}
			a.activity="发送求救信号" if operation=="transmit" else "接线并维修通信设备"
	return tx.result()

func _spawn(tx:RefCounted,encounter:Dictionary,defense:bool=false) -> Dictionary:
	var expedition: bool = encounter.get("expedition", false)
	var count: int = clampi(int(encounter.get("count", 3 if defense else 2)), 1, 6 if expedition else 3)
	var pending:Array=[]
	for index:int in count:
		var id:String="infected:"+str(encounter.id)+":"+str(index)
		if not tx.actor(id).is_empty():return _no("ENCOUNTER_ID_EXISTS","遭遇人物身份已存在，未重复生成")
		var place:Dictionary=encounter.position.duplicate(true)
		if encounter.get("positions",[]).size()>=count:place=encounter.positions[index].duplicate(true)
		else:place.x+=float(index-1)*0.7
		if tx.staged.get("scenario")=="factory-settlement-r34" or not _state().get("layout",{}).is_empty():
			# Resolve EACH body against the committed terrain and buildings, not
			# a planar offset or an out-of-date generator height function.
			place=context.spatial.current_space().standing_point(place)
			if place.is_empty():return _no("NO_ENCOUNTER_GROUND","遭遇站位缺少合法地面，未生成或判定清除："+id)
		var a:=Initial.actor(id,"感染者",place,place,{"scrap":1})
		a.merge({"faction":"infected","appearance_id":"infected_walker","body_profile_id":"human-default-v1","hp":48.0,"max_hp":48.0,"job":"hostile","activity":"游荡","cooldown":0.0,"stunned_until":0.0,"death_settled":false,"encounter_id":encounter.id},true)
		if expedition:
			var runner: bool = index >= count - int(encounter.get("runner_count", int(encounter.get("runner", false))))
			a.name = "奔跑感染者" if runner else "感染者"
			a.hp = 42.0 if runner else 34.0
			a.max_hp = a.hp
			a.expedition_enemy = true
			a.speed = 3.1 if runner else 1.9
			a.pack = {}
		if _experience14:
			a.walker_version=14
			a.walker_brain={"phase":"patrol","origin":Geometry.location(a),"next_sense":0.0,"memory_until":0.0,"patrol_index":0,"next_path":0.0,"route":[]}
		pending.append(a)
	# Stage the entire finite group only after every real body has a legal foot.
	# An empty/partial array is never a defeated encounter or a free choice.
	encounter.actors=[]
	for a:Dictionary in pending:
		tx.staged.actors.append(a);encounter.actors.append(a.id)
	encounter.spawned=true
	encounter.erase("spawn_error");encounter.erase("next_spawn_attempt")
	return _ok()

func _cleared(tx:RefCounted,encounter:Dictionary,count:int)->bool:
	var roster:Variant=encounter.get("actors",[])
	if not roster is Array or roster.size()!=count:return false
	var seen:Dictionary={}
	for value:Variant in roster:
		if not value is String or value.is_empty() or seen.has(value):return false
		var id:String=value;seen[id]=true
		var a:Dictionary=tx.actor(id)
		if a.is_empty() or a.get("faction")!="infected" or a.get("encounter_id")!=encounter.id or float(a.hp)>0:return false
	return true

func _attack_availability(request: Dictionary, actor: Dictionary, factory: bool) -> Dictionary:
	var payload: Dictionary = request.get("payload", {})
	var manual: Variant = payload.get("manual_aim", false)
	var target_id: Variant = request.get("target_id", "")
	var tool_id: Variant = payload.get("tool_id", "")
	if not manual is bool or not _optional_id(target_id) or not _optional_id(tool_id):
		return _no("INVALID_ATTACK", "挥击指令参数无效")
	if manual and payload.has("aim") and not Data.vec(payload.aim):
		return _no("INVALID_ATTACK", "挥击方向无效")
	if _expedition_enabled and (not manual or expedition_in_combat()):
		return _no("AUTO_ATTACK", "进入武器范围后会自动攻击")
	if actor.get("faction") == "infected" or (manual and actor.id != "player"):
		return _no("ACTOR_UNAVAILABLE", "角色无法执行这次挥击")
	if actor.get("intent") != null:
		return _no("BUSY", "先结束当前作业再战斗")
	if actor.has("combat_swing") or float(actor.get("cooldown", 0)) > 0:
		return _no("COOLDOWN", "武器尚未准备好")
	if float(actor.stamina) < SWING_STAMINA:
		return _no("EXHAUSTED", "体力不足以挥击")
	var tool: Dictionary = _tool(request)
	var tool_check := _swing_tool_check(actor, tool_id, tool)
	if not tool_check.ok:
		return tool_check
	if target_id != "":
		var target: Dictionary = context.actor.call(target_id)
		return _contact_check(actor, target, _swing_reach(tool, manual), factory)
	return _ok()

static func _optional_id(value: Variant) -> bool:
	return value is String and (value.is_empty() or Data.valid_id(value))

func _swing_tool_check(actor: Dictionary, tool_id: String, tool: Dictionary, tx: RefCounted = null) -> Dictionary:
	if tool_id.is_empty():
		return _ok()
	if tool.is_empty() or tool.get("holderId") != "pack:" + str(actor.id) or float(tool.get("durability", 0)) <= 0:
		return _no("MISSING_TOOL", "武器不在身上或已损坏")
	if _production.get_ref().tool_unavailable(tool_id, "", tx):
		return _no("TOOL_RESERVED", "工具正在实际作业中")
	return _ok()

static func _swing_reach(tool: Dictionary, manual: bool) -> float:
	if manual:
		if tool.get("kind") == "bow": return 7.2
		if tool.get("kind") == "club": return 2.15
	return MELEE_REACH

func _contact_check(actor: Dictionary, target: Dictionary, reach: float, factory: bool) -> Dictionary:
	if target.is_empty() or target.get("faction") != "infected" or float(target.hp) <= 0:
		return _no("TARGET_UNAVAILABLE", "目标已离开或倒下")
	if (factory and not context.region_is_detailed.call(str(target.regionId))) or not _near(actor, target, reach):
		return _no("OUT_OF_REACH", "目标超出武器范围")
	if not context.spatial.current_space().contact_clear(Geometry.location(actor), Geometry.location(target)):
		return _no("ATTACK_BLOCKED", "门墙或障碍挡住了攻击")
	return _ok()

static func _swing_direction(actor: Dictionary, target: Dictionary, aim: Dictionary) -> Vector3:
	var direction := Vector3.ZERO
	if not target.is_empty():
		direction = Geometry.point(target) - Geometry.point(actor)
	elif Data.vec(aim):
		# Input sends the cursor's world contact point, including on empty ground.
		direction = Geometry.point(aim) - Geometry.point(actor)
		direction.y = 0.0
	if direction.is_finite() and direction.length_squared() > 0.000001 and is_finite(direction.length_squared()):
		return direction.normalized()
	var previous: Variant = actor.get("combat_aim")
	if Data.vec(previous):
		var prior := Geometry.point(previous)
		if prior.is_finite() and prior.length_squared() > 0.000001 and is_finite(prior.length_squared()):
			return prior.normalized()
	return Vector3.FORWARD

func _begin_swing(tx: RefCounted, actor: Dictionary, target_id: String, tool_id: String, aim: Dictionary) -> void:
	var now: float = context.clock.call()
	var tool: Dictionary = {} if tool_id.is_empty() else context.tool.call(tool_id)
	actor.combat_aim = Geometry.json_point(_swing_direction(actor, tx.actor(target_id), aim))
	actor.combat_kind = str(tool.get("kind", "unarmed"))
	actor.attack_until = now + SWING_WINDUP + 0.25
	# The actor's combat phase survives logical movement and checkpoint restore.
	# Stamina and wear are spent by the contact transaction, never at windup.
	actor.combat_swing = {"target_id": target_id, "tool_id": tool_id, "contact_at": now + SWING_WINDUP}
	actor.cooldown = SWING_WINDUP + SWING_RECOVERY
	tx.events.append({"kind": "combat-windup", "actor_id": actor.id, "target_id": target_id, "weapon": actor.combat_kind,
		"from": Geometry.json_point(Geometry.point(actor)), "aim": actor.combat_aim.duplicate(true)})

func _advance_swing(tx: RefCounted, state: Dictionary, now: float) -> void:
	if not Draft.find(tx.observe_facts().actors, "player").has("combat_swing"):
		return
	var actor: Dictionary = tx.actor("player")
	var swing: Variant = actor.combat_swing
	if not swing is Dictionary or not _optional_id(swing.get("target_id")) or not _optional_id(swing.get("tool_id")):
		actor.erase("combat_swing")
		return
	var contact_at: Variant = swing.get("contact_at")
	if not (contact_at is float or contact_at is int) or not is_finite(float(contact_at)) or absf(float(contact_at) - now) > SWING_WINDUP + 0.000001:
		actor.erase("combat_swing")
		return
	if now + 0.000001 < float(contact_at):
		return
	actor.erase("combat_swing")
	if float(actor.hp) <= 0 or not context.region_is_detailed.call(str(actor.regionId)):
		return
	if expedition_in_combat():
		actor.cooldown = 0.0
		_swing_miss(tx, actor, swing.target_id, "AUTO_ATTACK", false)
		return
	if actor.get("intent") != null:
		_swing_miss(tx, actor, swing.target_id, "BUSY", false)
		return
	if float(actor.stamina) < SWING_STAMINA:
		_swing_miss(tx, actor, swing.target_id, "EXHAUSTED", false)
		return
	_strike(tx, actor, swing.target_id, swing.tool_id, state, true)

func _swing_miss(tx: RefCounted, actor: Dictionary, target_id: String, reason: String, contact: bool) -> void:
	tx.events.append({"kind": "combat-miss", "actor_id": actor.id, "target_id": target_id, "code": reason,
		"contact": contact, "weapon": actor.get("combat_kind", "unarmed"),
		"from": Geometry.json_point(Geometry.point(actor)), "aim": Geometry.json_point(_swing_direction(actor, {}, {}))})

func _strike(tx: RefCounted, actor: Dictionary, target_id: String, tool_id: String, state: Dictionary, manual: bool = false) -> void:
	var tool: Dictionary = {}
	if not tool_id.is_empty():
		tool = Draft.find(tx.extension("r3:production").get("tools", []), tool_id)
	var tool_check := _swing_tool_check(actor, tool_id, tool, tx)
	if not tool_check.ok:
		if manual: _swing_miss(tx, actor, target_id, tool_check.code, false)
		return
	var now: float = context.clock.call()
	var origin := Geometry.point(actor)
	var factory: bool = tx.staged.get("scenario") == "factory-settlement-r34"
	var reach := _swing_reach(tool, manual)
	var primary: Dictionary = tx.actor(target_id)
	if target_id.is_empty() and not manual:
		# Older callers can still ask for an untargeted attack. The player input
		# uses manual_aim, which always treats an empty target as an air swing.
		primary = _closest_contact(tx, actor, reach, factory)
	var check := _no("SWING_EMPTY", "挥空") if target_id.is_empty() and primary.is_empty() else _contact_check(actor, primary, reach, factory)
	var direction := _swing_direction(actor, primary if check.ok else {}, {})
	var weapon: String = str(tool.get("kind", "unarmed"))
	actor.stamina = maxf(0.0, float(actor.stamina) - SWING_STAMINA)
	actor.cooldown = SWING_RECOVERY if manual else SWING_WINDUP + SWING_RECOVERY
	actor.combat_aim = Geometry.json_point(direction)
	actor.combat_kind = weapon
	if not manual:
		actor.attack_until = now + 0.28
	if not tool.is_empty():
		tool.durability = maxf(0.0, float(tool.durability) - SWING_WEAR)
	if not check.ok:
		_swing_miss(tx, actor, target_id, check.code, true)
		return

	var upgrades: Array = state.exploration.upgrades if state.exploration.status == "running" and actor.id == "player" else []
	var targets: Array[Dictionary] = [primary]
	if upgrades.has("chain") and (not manual or weapon != "bow"):
		var secondary := _closest_contact(tx, actor, reach, factory, str(primary.id), direction)
		if not secondary.is_empty(): targets.append(secondary)
	var damage := 6.0 if tool.is_empty() else 18.0
	if manual:
		if weapon == "club": damage = 19.0
		if weapon == "bow": damage = 16.0
	for enemy: Dictionary in targets:
		var contact_point := Geometry.json_point(Geometry.point(enemy))
		enemy.hp = maxf(0.0, float(enemy.hp) - damage)
		enemy.hit_until = now + 0.18
		actor.skills.combat = float(actor.skills.get("combat", 0)) + 0.6
		if upgrades.has("stagger"): enemy.stunned_until = now + 0.6
		var pushed := false
		if upgrades.has("shove"):
			var location := Geometry.location(enemy)
			var away := origin.direction_to(Geometry.point(enemy))
			location.x += away.x * 0.8
			location.z += away.z * 0.8
			var moved: Dictionary = _actions.get_ref().move_step(str(enemy.id), Geometry.location(enemy), location)
			if moved.ok:
				enemy.merge(moved.location, true)
				pushed = Geometry.point(enemy).distance_squared_to(Geometry.point(contact_point)) > 0.000001
		tx.events.append({"kind": "combat-hit", "actor_id": actor.id, "target_id": enemy.id, "damage": damage,
			"weapon": weapon, "manual": manual, "primary_hit": enemy.id == primary.id,
			"position": contact_point, "from": Geometry.json_point(origin), "knockback": pushed, "stagger": upgrades.has("stagger")})
		if float(enemy.hp) <= 0: _drop(tx, enemy)

func _closest_contact(tx: RefCounted, actor: Dictionary, reach: float, factory: bool, exclude_id: String = "", forward: Vector3 = Vector3.ZERO) -> Dictionary:
	var best: Dictionary = {}
	var origin := Geometry.point(actor)
	var best_distance := INF
	for candidate: Dictionary in tx.staged.actors:
		if candidate.id == exclude_id or candidate.get("faction") != "infected" or float(candidate.hp) <= 0:
			continue
		var offset := Geometry.point(candidate) - origin
		var distance := offset.length_squared()
		if distance > best_distance or (forward != Vector3.ZERO and forward.dot(offset.normalized()) <= 0.2):
			continue
		if distance == best_distance and not best.is_empty() and str(candidate.id) >= str(best.id):
			continue
		if _contact_check(actor, candidate, reach, factory).ok:
			best = candidate
			best_distance = distance
	return best

func _drop(tx:RefCounted,enemy:Dictionary) -> void:
	if enemy.get("death_settled",false):return
	if enemy.get("expedition_enemy", false):
		enemy.death_settled = true
		enemy.activity = "倒下"
		tx.events.append({"kind": "infected-defeated", "actor_id": enemy.id})
		return
	var id:String=str(enemy.id)+":drops"
	var p:=Geometry.location(enemy)
	tx.staged.stocks.append({"id":id,"location":p.duplicate(true),"items":enemy.pack.duplicate(true),"owner":null,"searched":true})
	enemy.pack={};enemy.death_settled=true;enemy.activity="倒下"
	var e:Dictionary={"id":id,"kind":"container","regionId":p.regionId,"position":Geometry.json_point(Geometry.point(p)),"bounds":Geometry.json_box(AABB(Geometry.point(p),Vector3(0.3,0.2,0.3))),"revision":0,"blocksTerrain":false,"data":{"dropped":true,"inventoryOwner":"runtime","sourceId":enemy.id,"solid":false,"opaque":false}}
	if p.buildingId!=null:e.buildingId=p.buildingId;e.storeyId=p.storeyId
	tx.extra.append({"op":"entity.put","id":id,"before_exists":false,"before":null,"after":e})
	tx.events.append({"kind":"infected-defeated","actor_id":enemy.id,"target_id":id})

func prepare_defense_spawn(tx:RefCounted,encounter:Dictionary)->Dictionary:
	# Shared existing finite infected and standing/contact rules, no new combat
	# system or direct commit. The caller persists its own event/roster state.
	if tx.staged.get("scenario")!="factory-settlement-r34":return _no("SCENARIO_UNAVAILABLE","新防守生成只服务R3.4编排")
	if not _route_location(encounter.get("position")):return _no("INVALID_ENCOUNTER_ANCHOR","防守缺少真实空间锚点")
	if not context.region_is_detailed.call(str(encounter.position.regionId)):return _no("REGION_PAUSED","遭遇地区未详细模拟，保留预告和真实货物")
	return _spawn(tx,encounter,true)

static func _route_location(value:Variant)->bool:
	return value is Dictionary and Data.vec(value) and Data.valid_id(value.get("regionId"))

func advance(dt:float) -> Dictionary:
	if not is_finite(dt) or dt<=0 or dt>1:return _no("INVALID_STEP","玩法只由A同一时钟推进")
	var tx:=Draft.new(context)
	var scenario:String=str(tx.observe_facts().get("scenario",""))
	if scenario=="factory-settlement-r34":
		var combat_tx:=tx
		_walker_path_budget=1
		var player: Dictionary = context.actor.call("player")
		var regional_patrol: bool = _expedition_enabled and not player.is_empty() and player.regionId != "RH-HOME"
		if _ambient_opening_walkers or regional_patrol:
			_ensure_opening_walkers(combat_tx, player if regional_patrol else {})
		var now: float = context.clock.call()
		var combat_state := {"exploration": {"status": "idle", "upgrades": []}}
		_advance_swing(combat_tx, combat_state, now)
		if _expedition_enabled:
			var expedition := Expedition.snapshot(self)
			var night := Night.advance(self, combat_tx, Night.snapshot(self), combat_tx.actor("player"), now, expedition)
			Expedition.advance(self, combat_tx, dt, now, night)
			Night.after_combat(self, combat_tx, night, combat_tx.actor("player"), now)
		elif _ambient_opening_walkers or combat_tx.observe_facts().actors.any(func(a: Dictionary) -> bool: return a.get("faction") == "infected" and float(a.hp) > 0):
			_combat_step(combat_tx, combat_state, dt, now, false)
		if _village_enabled():
			for actor: Dictionary in combat_tx.observe_facts().actors:
				var intent: Variant = actor.get("intent")
				if not intent is Dictionary or intent.get("owner") != "gameplay" or intent.get("kind") != "radio": continue
				var staged_actor: Dictionary = combat_tx.actor(str(actor.id))
				if float(staged_actor.hp) > 0 and context.region_is_detailed.call(str(staged_actor.regionId)):
					_radio_step(combat_tx,staged_actor,combat_tx.extension(KEY),dt)
		return combat_tx.result()
	if scenario!="rural-home-r33":return {"ok":true,"world_changes":[],"fact_changes":[]}
	var state:Dictionary=tx.extension(KEY,initial())
	var player:Dictionary=tx.actor("player")
	var now:float=context.clock.call()
	var observed_revision:int=int(state.last_event_revision)
	var latest_revision:int=observed_revision
	for event:Variant in tx.staged.get("ledger",[]):
		if not event is Dictionary or int(event.get("revision",-1))<=observed_revision:continue
		# Only observer candidate kinds need durable consumption. Movement remains
		# in A/B's ledger; same-revision candidates all use the original cutoff.
		if event.get("kind") not in ["inventory-transfer","structure-completed","life-completed"]:continue
		_observe(state,event)
		latest_revision=maxi(latest_revision,int(event.get("revision",-1)))
	state.last_event_revision=latest_revision
	if state.exploration.status=="running":
		for encounter:Dictionary in state.encounters:
			if not encounter.spawned and now>=float(encounter.get("next_spawn_attempt",0)) and _near(player,encounter.position,7):
				var spawned:Dictionary=_spawn(tx,encounter)
				if not spawned.ok:encounter.spawn_error=spawned;encounter.next_spawn_attempt=now+3.0
			if encounter.spawned and not encounter.cleared and _cleared(tx,encounter,2):encounter.cleared=true
			if encounter.cleared and not encounter.choice_issued and state.exploration.candidates.is_empty():
				var candidates:Array=CHOICES.keys().filter(func(id:String)->bool:return not state.exploration.upgrades.has(id))
				candidates.sort_custom(func(a:String,b:String)->bool:return (str(context.world.identity().seed)+encounter.id+a).sha256_text()<(str(context.world.identity().seed)+encounter.id+b).sha256_text())
				state.exploration.candidates=candidates.slice(0,3);state.exploration.stages=int(state.exploration.stages)+1;encounter.choice_issued=true
	if state.defense.status=="warning" and now>=maxf(float(state.defense.arrival_at),float(state.defense.get("next_spawn_attempt",0))) and _at_home(player):
		var wave:Dictionary={"id":"first-night","position":{"x":32.0,"y":0.0,"z":47.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null},"actors":[]}
		wave.position=state.get("layout",{}).get("defense_position",wave.position).duplicate(true)
		var spawned:Dictionary=_spawn(tx,wave,true)
		if spawned.ok:
			state.defense.status="active";state.defense.actors=wave.actors
			state.defense.erase("spawn_error");state.defense.erase("next_spawn_attempt")
		else:state.defense.spawn_error=spawned;state.defense.next_spawn_attempt=now+3.0
	if state.defense.status=="active" and _cleared(tx,{"id":"first-night","actors":state.defense.actors},3):state.defense.status="cleared"
	_advance_swing(tx, state, now)
	_combat_step(tx,state,dt,now,true)
	if now>=_next_quest_check:
		_next_quest_check=now+0.5
		_quests(tx,state,player)
	return tx.result()

func _combat_step(tx:RefCounted,state:Dictionary,dt:float,now:float,legacy_radio:bool)->void:
	var actors: Array = tx.writable_collection("actors")
	for a: Dictionary in actors:
		if not legacy_radio and not context.region_is_detailed.call(str(a.regionId)):continue
		if float(a.hp)<=0:
			if a.get("intent") is Dictionary and a.intent.get("owner")=="gameplay":
				a.intent=null;a.activity="已失能"
			continue
		if a.get("faction")=="infected":_enemy_step(tx,a,state,dt,now)
		elif a.id!="player" and a.get("job")=="guard" and a.get("relationship",{}).get("consent",false) and float(a.get("cooldown",0))<=0 and float(a.stamina)>=14:
			if not legacy_radio and not a.get("relationship",{}).get("member",false):continue
			var target:Dictionary={}
			for enemy: Dictionary in actors:
				if not legacy_radio and not context.region_is_detailed.call(str(enemy.regionId)):continue
				if enemy.get("faction")=="infected" and float(enemy.hp)>0 and _contact_check(a, enemy, MELEE_REACH, not legacy_radio).ok:target=enemy;break
			if not target.is_empty():
				var tool_id:=""
				for tool:Dictionary in tx.extension("r3:production").get("tools",[]):
					if tool.get("holderId")=="pack:"+str(a.id) and float(tool.durability)>0 and not _production.get_ref().tool_unavailable(str(tool.id)):tool_id=tool.id;break
				_strike(tx,a,str(target.id),tool_id,state)
		if legacy_radio and a.get("intent") is Dictionary and a.intent.get("owner")=="gameplay":_radio_step(tx,a,state,dt)

func _enemy_step(tx:RefCounted,enemy:Dictionary,state:Dictionary,dt:float,now:float) -> void:
	if enemy.get("walker_version",0)==14:
		_walker_step(tx,enemy,state,dt,now);return
	if now<float(enemy.get("stunned_until",0)):enemy.activity="被压制";return
	var target:Dictionary={}
	var nearest:=INF
	for a:Dictionary in tx.staged.actors:
		if a.get("faction")=="infected" or float(a.hp)<=0 or not _near(enemy,a,12):continue
		if tx.staged.get("scenario")=="factory-settlement-r34" and not context.region_is_detailed.call(str(a.regionId)):continue
		var distance:float=Geometry.point(a).distance_to(Geometry.point(enemy))
		# Awareness may persist behind a real gate; the attack itself still needs
		# clear sight. Requiring sight here made enemies forget the player and
		# prevented them from ever reaching B's actual barrier damage path.
		if distance<nearest and distance<12:target=a;nearest=distance
	if target.is_empty():enemy.activity="失去目标";return
	if nearest<=1.05 and _clear(enemy,target):
		if float(enemy.get("cooldown",0))<=0:
			var reduced:bool=target.id=="player" and state.exploration.status=="running" and state.exploration.upgrades.has("guard")
			target.hp=maxf(0,float(target.hp)-8*(0.75 if reduced else 1.0));target.hit_until=now+0.2;enemy.cooldown=1.3
			target.wounds.append({"cause":"感染者抓伤","time":now,"severity":1})
			while target.wounds.size()>64:target.wounds.pop_front()
			enemy.attack_until=now+0.28
			tx.events.append({"kind":"combat-hit","actor_id":enemy.id,"target_id":target.id,"damage":6 if reduced else 8})
		return
	var direction:Vector3=(Geometry.point(target)-Geometry.point(enemy)).normalized()
	var destination:=Geometry.location(enemy);destination.x+=direction.x*dt*1.03;destination.z+=direction.z*dt*1.03
	var moved:Dictionary=_actions.get_ref().move_step(str(enemy.id),Geometry.location(enemy),destination)
	if moved.ok:enemy.merge(moved.location,true);enemy.activity="接近"
	else:
		enemy.activity="被真实门墙阻挡"
		if float(enemy.get("cooldown",0))<=0:
			# B selects only a physically contacted module in this same Draft and
			# owns damage, cooldown and ruin consequences. No remote target search.
			var modules:Variant=_modules.get_ref() if _modules!=null else null
			if tx.staged.get("scenario")=="factory-settlement-r34" and modules!=null and modules.has_method("strike_hostile"):
				var struck:Dictionary=modules.strike_hostile(tx,str(enemy.id))
				if struck.get("ok",false):return
			if context.spatial.has_method("strike_structure"):
				context.spatial.strike_structure(tx,str(enemy.id))

func _ensure_opening_walkers(tx:RefCounted, explorer:Dictionary={})->void:
	var state:Dictionary=tx.extension(KEY)
	if state.get("opening_walkers",{}).get("spawned",false):
		var encounter:Dictionary=state.opening_walkers
		if not encounter.get("cleared",false):
			var dead:bool=not encounter.get("actors",[]).is_empty()
			for id:String in encounter.get("actors",[]):
				var actor:Dictionary=tx.actor(id)
				if actor.is_empty() or float(actor.get("hp",0))>0:dead=false
			encounter.cleared=dead
		return
	var now:float=float(context.clock.call())
	if now<float(state.get("opening_walkers_next_attempt",0)):return
	state.opening_walkers_next_attempt=now+3.0
	# Only already registered physical exterior stock sources qualify. Never
	# place a threat beside the home or its mandatory starter resources.
	for stock:Dictionary in tx.read_facts().get("stocks",[]):
		var p:Dictionary=stock.get("location",{})
		if str(stock.get("module_id","")).is_empty() or p.get("regionId")=="RH-HOME" or not context.region_is_detailed.call(str(p.get("regionId",""))):continue
		if not explorer.is_empty() and (p.get("regionId") != explorer.regionId or Geometry.point(p).distance_to(Geometry.point(explorer)) > 32.0):
			continue
		var positions:Array=[]
		for index:int in 8:
			var at:Dictionary=p.duplicate(true)
			var angle:float=TAU*float(index)/8.0
			at.x=float(at.x)+cos(angle)*6.0;at.z=float(at.z)+sin(angle)*6.0
			at.buildingId=null;at.storeyId=null
			var feet:Dictionary=context.spatial.current_space().standing_point(at)
			if feet.is_empty() or feet.get("regionId")=="RH-HOME":continue
			if not explorer.is_empty() and feet.get("regionId") != explorer.regionId:continue
			positions.append(feet)
			if positions.size()==2:break
		if positions.is_empty():continue
		var encounter:Dictionary={"id":"v14:outskirts:"+str(stock.module_id),"position":positions[0],"positions":positions,"count":positions.size(),"actors":[]}
		var spawned:Dictionary=_spawn(tx,encounter,false)
		if not spawned.ok:continue
		for id:String in encounter.actors:
			var actor:Dictionary=tx.actor(id);actor.walker_version=14
			if not explorer.is_empty():actor.patrol_region=explorer.regionId
			actor.walker_brain={"phase":"patrol","origin":Geometry.location(actor),"next_sense":0.0,"memory_until":0.0,"patrol_index":0,"next_path":0.0,"route":[]}
		state.opening_walkers=encounter
		tx.events.append({"kind":"opening-walkers-spawned","actor_id":"player","encounter_id":encounter.id,"actors":encounter.actors.duplicate()})
		return

func _walker_step(tx:RefCounted,enemy:Dictionary,state:Dictionary,dt:float,now:float)->void:
	if now<float(enemy.get("stunned_until",0)):enemy.activity="被压制";return
	var brain:Dictionary=enemy.get("walker_brain",{})
	if brain.is_empty():brain={"phase":"patrol","origin":Geometry.location(enemy),"next_sense":0.0,"memory_until":0.0,"patrol_index":0,"next_path":0.0,"route":[]};enemy.walker_brain=brain
	if now>=float(brain.get("next_sense",0)):
		brain.next_sense=now+0.35
		var target:Dictionary={};var distance:float=12.0
		for actor:Dictionary in tx.staged.get("actors",[]):
			if actor.get("faction")=="infected" or float(actor.hp)<=0 or not context.region_is_detailed.call(str(actor.regionId)):continue
			if actor.regionId != enemy.get("patrol_region", actor.regionId):continue
			var d:float=Geometry.point(enemy).distance_to(Geometry.point(actor))
			if d<distance and _near(enemy,actor,12.0) and _clear(enemy,actor):target=actor;distance=d
		if not target.is_empty():
			brain.phase="chase";brain.target_id=target.id;brain.last_seen=Geometry.location(target);brain.memory_until=now+6.0
		elif brain.get("phase")=="chase":
			brain.phase="search";brain.search_until=now+6.0
		# Sound is a real, currently active production/action intent, never a
		# periodic free alarm or a fact fabricated by opening narration.
		if brain.get("phase") not in ["chase","search"]:
			for actor:Dictionary in tx.staged.get("actors",[]):
				var intent:Variant=actor.get("intent")
				if not intent is Dictionary or float(actor.get("hp",0))<=0 or not _near(enemy,actor,17.0):continue
				if actor.regionId != enemy.get("patrol_region", actor.regionId):continue
				var kind:String=str(intent.get("kind",""))
				if kind in ["craft","harvest","structure","terrain","module-work"] and intent.get("held",true) and float(actor.get("stamina",0))>0:
					brain.phase="investigate";brain.last_seen=Geometry.location(actor);brain.search_until=now+5.0;break
	var phase:String=str(brain.get("phase","patrol"))
	var target:Dictionary=tx.actor(str(brain.get("target_id",""))) if phase=="chase" else {}
	if not target.is_empty() and target.regionId == enemy.get("patrol_region", target.regionId) and float(target.hp)>0 and _near(enemy,target,1.05) and _clear(enemy,target):
		enemy.activity="近身抓击"
		if float(enemy.get("cooldown",0))<=0:
			target.hp=maxf(0,float(target.hp)-8.0);target.hit_until=now+.2;enemy.cooldown=1.3;enemy.attack_until=now+.28
			target.wounds.append({"cause":"感染者抓伤","time":now,"severity":1})
			while target.wounds.size()>64:target.wounds.pop_front()
			tx.events.append({"kind":"combat-hit","actor_id":enemy.id,"target_id":target.id,"damage":8})
		return
	var goal:Dictionary=brain.get("last_seen",brain.origin)
	if phase in ["search","investigate"] and now>=float(brain.get("search_until",0)):
		brain.phase="return";brain.erase("target_id");brain.route=[];goal=brain.origin;phase="return"
	if phase=="return" and Geometry.point(enemy).distance_to(Geometry.point(brain.origin))<.5:brain.phase="patrol";phase="patrol"
	if phase=="return":goal=brain.origin
	if phase=="patrol":
		var angle:float=TAU*float(int(brain.get("patrol_index",0))%4)/4.0
		goal=brain.origin.duplicate(true);goal.x=float(goal.x)+cos(angle)*2.5;goal.z=float(goal.z)+sin(angle)*2.5
		if Geometry.point(enemy).distance_to(Geometry.point(goal))<.35:brain.patrol_index=int(brain.get("patrol_index",0))+1
	if phase in ["search","investigate"] and Geometry.point(enemy).distance_to(Geometry.point(goal))<.4:enemy.activity="搜索动静";return
	enemy.activity={"patrol":"外围巡游","chase":"追击目标","search":"搜索最后位置","investigate":"调查作业噪声","return":"返回巡游"}.get(phase,"巡游")
	_walker_move(tx,enemy,goal,dt,now)

func _walker_move(tx:RefCounted,enemy:Dictionary,goal:Dictionary,dt:float,now:float,damage_structure:bool=true)->void:
	var brain:Dictionary=enemy.walker_brain
	var route:Array=brain.get("route",[])
	var waypoint:Dictionary=goal
	while not route.is_empty():
		var step:Dictionary=route[0]
		if step.get("kind")!="move":route.clear();break
		if Geometry.point(enemy).distance_to(Geometry.point(step.to))<.18:route.pop_front();continue
		waypoint=step.to;break
	var direction:Vector3=Geometry.point(waypoint)-Geometry.point(enemy)
	if direction.length()<.05:return
	var destination:Dictionary=Geometry.location(enemy)
	var next:Vector3=Geometry.point(enemy)+direction.normalized()*minf(direction.length(),dt*float(enemy.get("speed", 1.03)))
	destination.x=next.x;destination.z=next.z
	var actions:Variant=_actions.get_ref()
	var moved:Dictionary=actions.move_step(str(enemy.id),Geometry.location(enemy),destination)
	if moved.ok:
		if moved.location.regionId == enemy.get("patrol_region", moved.location.regionId):
			enemy.merge(moved.location, true)
		elif brain.get("phase") == "patrol":
			brain.patrol_index = int(brain.get("patrol_index", 0)) + 1
		return
	# A local actor gets at most one route search per two seconds. The whole
	# gameplay STEP shares one search admission; failed paths are not retried
	# per-frame, and every resulting movement still passes the real executor.
	if _walker_path_budget>0 and now>=float(brain.get("next_path",0)):
		_walker_path_budget-=1;brain.next_path=now+2.0
		if enemy.regionId==goal.get("regionId") and (enemy.get("night_enemy", false) or Geometry.point(enemy).distance_to(Geometry.point(goal))<20):
			var plan:Dictionary=actions.route(str(enemy.id),Geometry.location(enemy),goal)
			if plan.get("ok",false):brain.route=plan.get("steps",[]).duplicate(true)
			elif brain.get("phase")=="patrol":brain.patrol_index=int(brain.get("patrol_index",0))+1
	if not damage_structure or float(enemy.get("cooldown",0))>0:return
	var modules:Variant=_modules.get_ref() if _modules!=null else null
	if modules!=null and modules.has_method("strike_hostile"):
		var struck:Dictionary=modules.strike_hostile(tx,str(enemy.id))
		if struck.get("ok",false):return
	if context.spatial.has_method("strike_structure"):context.spatial.strike_structure(tx,str(enemy.id))

func _radio_step(tx:RefCounted,a:Dictionary,state:Dictionary,dt:float) -> void:
	var intent:Dictionary=a.intent
	# Recheck the same real station/materials/tool at completion; ignore own intent only.
	if not _at_home(a):a.intent=null;a.activity="离开通信工位，进度停止";return
	if intent.get("operation") not in ["repair","transmit"] or state.radio.status!=("unrepaired" if intent.operation=="repair" else "repaired") or state.radio.station_id!=intent.get("target_id"):
		a.intent=null;a.activity="通信阶段已变化，行动停止";return
	var station:Dictionary=_radio_station(a,str(intent.target_id),tx.staged,str(intent.id),tx)
	if not station.ok:a.intent=null;a.activity=str(station.reason);return
	if intent.operation=="repair":
		var tool:Dictionary=Draft.find(tx.extension("r3:production").get("tools",[]),str(intent.tool_id))
		if tool.is_empty() or tool.holderId!="pack:"+str(a.id) or float(tool.durability)<=0 or float(_production.get_ref().tool_qualities(tool).get("hammering",0))<1 or _production.get_ref().tool_unavailable(str(tool.id),str(intent.id),tx):a.intent=null;a.activity="维修工具不可用";return
		for item:String in ["scrap","tool_handle"]:
			if float(a.pack.get(item,0))-_production.get_ref().reserved("pack:"+str(a.id),item,str(intent.id),tx)<(8 if item=="scrap" else 1):a.intent=null;a.activity="维修材料不足";return
	if float(a.stamina)<=0:a.activity="体力不足，休息后再继续";return
	# Same staged actor and existing neutral effects as B's labor consumer.
	# Never grant a full tick for fractional stamina or charge past completion.
	var labor:float=float(Content.actor_effects(a).labor_multiplier)
	var worked:float=minf(dt*labor,minf(float(intent.duration)-float(intent.elapsed),float(a.stamina)/0.5))
	intent.elapsed=minf(float(intent.duration),float(intent.elapsed)+worked);a.stamina=maxf(0,float(a.stamina)-worked*0.5)
	if intent.operation=="transmit":state.radio.signal=intent.elapsed
	if float(intent.elapsed)+0.000001<float(intent.duration):return
	if intent.operation=="repair":
		if not tx.stock_delta("pack:"+str(a.id),{"scrap":8,"tool_handle":1},-1):return
		if not _expedition_enabled:
			var tool:Dictionary=Draft.find(tx.extension("r3:production").tools,str(intent.tool_id));tool.durability=maxf(0,float(tool.durability)-2)
		state.radio.status="repaired";state.radio.station_id=intent.target_id
	else:state.radio.status="connected";state.flags.radio_connected=true
	a.intent=null;a.activity="通信设备已接通" if state.radio.status=="connected" else "通信设备维修完成"
	a.skills.crafting=float(a.skills.get("crafting",0))+1
	tx.events.append({"kind":"radio-completed","actor_id":a.id,"operation":intent.operation})

func _observe(state:Dictionary,event:Dictionary) -> void:
	if event.get("kind")=="inventory-transfer" and event.get("actor_id")=="player":
		var source:String=str(event.get("source_id",""))
		if source.begins_with(_layout_id("store_prefix","rural:v1:RH-VILLAGE:store:")) and event.get("output_id")=="pack:player" and (float(event.get("items",{}).get("food",0))>0 or float(event.get("items",{}).get("water",0))>0):state.flags.village_supplies=true
		if source.begins_with("infected:") and state.exploration.status=="running" and event.get("output_id")=="pack:player":state.exploration.loot_collected=int(state.exploration.loot_collected)+1
	if event.get("kind")=="structure-completed" and event.get("target_id")==_layout_id("gate_id",GATE) and event.get("operation")=="repair":state.flags.gate_repaired=true
	if event.get("kind")=="life-completed" and event.get("operation")=="rest" and not str(event.get("target_id","")).is_empty():state.flags.slept=true

func _quests(tx:RefCounted,state:Dictionary,player:Dictionary) -> void:
	if player.get("buildingId")==_layout_id("home_building",HOME):state.flags.entered_home=true
	if float(player.pack.get("water",0))>0:state.flags.water_found=true
	var production:Dictionary=tx.extension("r3:production")
	var knowledge:Array=production.get("knowledge",{}).get("player",[])
	for actor:Dictionary in tx.staged.actors:
		if actor.id!="player" and actor.get("faction")!="infected" and float(actor.hp)>0 and actor.get("relationship",{}).get("member",false) and actor.get("relationship",{}).get("consent",false) and _at_home(actor):actor.relationship.home_arrived=true
	for stock:Dictionary in tx.staged.stocks:
		if str(stock.id).begins_with(_layout_id("store_prefix","rural:v1:RH-VILLAGE:store:")) and stock.get("searched",false):state.flags.repair_clue=true
	var villager:Dictionary=tx.actor("village-resident")
	var repair:Dictionary=tx.actor("repair-resident")
	var home_tools:bool=production.get("tools",[]).any(func(t:Dictionary)->bool:return t.get("holderId")=="pack:player" and t.get("kind")=="hammer" and float(t.get("durability",0))>0) and _at_home(player)
	var bench_built:=false
	var store_built:=false
	var equipped:=false
	for order:Dictionary in tx.extension("r3:structure-orders",{"orders":[]}).orders:
		if order.get("status")!="completed" or order.get("kind")!="place":continue
		var instance:Dictionary=order.get("instance",{})
		if instance.get("regionId")!="RH-HOME":continue
		if instance.get("definitionId")=="workbench" and not context.world.entity(str(instance.id)).is_empty():bench_built=true
		if instance.get("definitionId")=="cabinet" and not context.world.entity(str(instance.id)).is_empty():store_built=true
	for order:Dictionary in production.get("orders",[]):
		if order.get("status")=="completed" and order.get("kind")=="craft" and order.get("targetId") in ["repair_axe","assemble_field_axe"]:equipped=true
	var requirements:Dictionary={"RH-Q01":[bool(state.flags.get("entered_home",false)),bool(state.flags.get("water_found",false)),bool(state.flags.get("gate_repaired",false)),bool(state.flags.get("slept",false))],
		"RH-Q02":[villager.get("relationship",{}).get("helped",false),villager.get("relationship",{}).get("home_arrived",false)],
		"RH-Q03":[bool(state.flags.get("village_supplies",false)),bool(state.flags.get("repair_clue",false))],
		"RH-Q04":[home_tools,repair.get("relationship",{}).get("home_arrived",false) or knowledge.has("basic_tool_repair")],
		"RH-Q05":[bench_built,store_built,equipped],"RH-Q06":[bool(state.flags.get("exploration_completed",false))],"RH-Q07":[state.defense.status=="cleared"],"RH-Q08":[bool(state.flags.get("radio_connected",false))]}
	var labels:Dictionary={"RH-Q01":["亲自进入旧宅","找到真实饮水","完成院门修补","在铺好的睡位休息"],"RH-Q02":["实际帮助周婶","自愿同行并回到旧宅"],"RH-Q03":["从小卖部实际取回补给","发现修理铺线索"],"RH-Q04":["实际带工具回家","带回老许或学会替代维修路径"],"RH-Q05":["建成真实工作台","新建可用存放点","完成实际装备改善"],"RH-Q06":["两次临时选择并携物回家结算"],"RH-Q07":["收到预警并清除有限来袭"],"RH-Q08":["支付物资劳动维修并完成通信"]}
	var previous_completed:=true
	for quest:Dictionary in tx.staged.get("quests",[]):
		if not requirements.has(quest.id):continue
		var checks:Array=requirements[quest.id]
		quest.objectives=[]
		for index:int in checks.size():quest.objectives.append({"id":str(quest.id)+":"+str(index),"text":labels[quest.id][index],"status":"已完成" if checks[index] else "待完成"})
		quest.completed=bool(quest.get("completed",false)) or checks.all(func(value:Variant)->bool:return bool(value))
		quest.status="已完成" if quest.completed else "进行中" if previous_completed else "可提前准备"
		quest.progress="%s / %s"%[checks.filter(func(value:Variant)->bool:return bool(value)).size(),checks.size()]
		previous_completed=quest.completed

func expedition_in_combat() -> bool:
	if not _expedition_enabled: return false
	var fields: Array[String] = ["phase"]
	return context.world.extension_fields(Expedition.KEY, fields).get("phase") in ["warning", "fighting"] or context.world.extension_fields(Night.KEY, fields).get("phase") in ["warning", "fighting", "between"]

func pursue_night_enemy(tx: RefCounted, enemy: Dictionary, player: Dictionary, night: Dictionary, dt: float, now: float) -> void:
	Night.pursue(self, tx, enemy, player, night, dt, now)

func expedition_snapshot() -> Dictionary:
	return Expedition.display(self) if _expedition_enabled else {}

func display() -> Dictionary:
	if _expedition_enabled:
		return {"expedition": expedition_snapshot(), "night": Night.display(self)}
	if not _active():return {}
	var state:=_state()
	var exploration:Dictionary=state.exploration.duplicate(true)
	exploration.description="临时技巧只属于本次探索，跨区和读档保留；回到旧宅明确结算才清除。" if exploration.status=="running" else "从旧宅整备后出发。已清理目标和已取走物资不会刷新。"
	for encounter:Dictionary in state.encounters:
		if encounter.has("spawn_error"):exploration.description+=" "+str(encounter.spawn_error.reason)
	exploration.choices=[]
	if exploration.status=="running":
		for id:String in exploration.candidates:exploration.choices.append({"id":id,"name":CHOICES[id].name+" · "+CHOICES[id].description,"command":{"kind":"explore_choose","payload":{"choice_id":id}}})
		exploration.choices.append({"id":"settle","name":"明确结束本次探索并结算","command":{"kind":"explore_end"}})
	else:exploration.choices.append({"id":"start","name":"从旧宅开始一次探索","command":{"kind":"explore_start"}})
	var defense:Dictionary=state.defense.duplicate(true)
	defense.description={"dormant":"尚无据点来袭线索。","warning":"公路传来脚步声。先回旧宅整备，修补入口，准备迎战。","active":"有限来袭已抵达；利用真实门墙、击退与守备。","cleared":"这一晚守住了。用工作台维修通信设备，再发送求救信号。"}.get(defense.status,defense.status)
	if defense.has("spawn_error"):defense.description+=" "+str(defense.spawn_error.reason)
	defense.remaining=maxf(0,float(defense.arrival_at)-float(context.clock.call()))
	defense.choices=[]
	if defense.status=="warning":defense.choices.append({"id":"ready","name":"已准备好，提前迎战","command":{"kind":"defend"}})
	if defense.status=="cleared":
		var station:=""
		var nearest:=INF
		var player:Dictionary=context.actor.call("player")
		for e:Dictionary in context.world.entities("RH-HOME"):
			if e.get("definitionId")=="workbench" and Geometry.point(e.position).distance_to(Geometry.point(player))<nearest:station=e.id;nearest=Geometry.point(e.position).distance_to(Geometry.point(player))
		var hammer:=""
		for tool:Dictionary in context.world.extension("r3:production").get("tools",[]):
			if tool.get("holderId")=="pack:player" and tool.get("kind")=="hammer":hammer=tool.id;break
		if state.radio.status=="unrepaired":defense.choices.append({"id":"radio-repair","name":"在工作台维修电台 · 废料8 / 工具柄1 / 手锤","command":{"kind":"radio","target_id":station,"payload":{"operation":"repair","tool_id":hammer}}})
		elif state.radio.status=="repaired":defense.choices.append({"id":"radio-transmit","name":"发送求救信号 · 30秒真实供电整备","command":{"kind":"radio","target_id":state.radio.station_id,"payload":{"operation":"transmit"}}})
		else:defense.description="电台收到下一地区的回应。世界与库存保留，你可以继续生活。"
	return {"exploration":exploration,"defense":defense,"radio":state.radio.duplicate(true)}
