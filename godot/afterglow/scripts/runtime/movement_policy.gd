extends RefCounted
## Shared human movement tuning. Authority and the sole clock stay in Runtime.
const Content=preload("res://scripts/runtime/content_definitions.gd")
const WALK_SPEED:float=2.8
const RUN_SPEED:float=4.6
const RUN_COST_PER_METRE:float=2.0
const RUN_MIN_STAMINA:float=10.0
const RUN_RECOVERY_STAMINA:float=20.0
const WALK_RECOVERY:float=0.5
const IDLE_RECOVERY:float=2.0
const PLAYER_EXERTION_SCALE:float=0.4
static func run_cost(actor:Dictionary)->float:
	return RUN_COST_PER_METRE * (PLAYER_EXERTION_SCALE if actor.get("id")=="player" else 1.0)
static func stamina_max(actor:Dictionary)->float:
	return float(Content.actor_effects(actor).stamina_max)
static func budget(actor:Dictionary,dt:float,requested:String,used:float)->Dictionary:
	var cap:=stamina_max(actor)
	var result:Dictionary={"ok":false,"mode":"walk","speed":0.0,"max_distance":0.0,"available_dt":0.0,"stamina_max":cap,"can_run":false,"reason":"角色无法行动","code":"ACTOR_UNAVAILABLE"}
	if actor.is_empty() or float(actor.get("hp",0))<=0:return result
	if not is_finite(dt) or dt<=0 or dt>0.1 or requested not in ["walk","run"]:
		result.code="INVALID_MOVEMENT";result.reason="移动时长或模式无效";return result
	var infected:bool=actor.get("faction")=="infected"
	var stamina:float=minf(cap,float(actor.get("stamina",0)))
	var minimum:float=RUN_RECOVERY_STAMINA if actor.get("run_recovering",false) else RUN_MIN_STAMINA
	var can_run:bool=not infected and stamina>=minimum
	var mode:String="run" if requested=="run" and can_run else "walk"
	var speed:float=2.2 if infected else RUN_SPEED if mode=="run" else WALK_SPEED
	var available:float=minf(dt,maxf(0.0,0.1-used))
	var distance:float=speed*available
	if mode=="run":distance=minf(distance,stamina/run_cost(actor))
	result.merge({"ok":true,"code":"OK","mode":mode,"speed":speed,"available_dt":available,"max_distance":distance,"can_run":can_run,"reason":"体力不足，改为步行" if requested=="run" and not can_run else null},true)
	return result
