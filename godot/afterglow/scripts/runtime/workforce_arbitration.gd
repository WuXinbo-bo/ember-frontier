extends RefCounted
## Pure policy ordering. Candidate ownership and execution stay with B.

static func decide(signals:Dictionary)->Dictionary:
	var actor_id:String=str(signals.get("actor_id",""))
	if actor_id.is_empty() or not signals.get("actor_exists",false):return _decision("N0","stop","actor_missing")
	if not signals.get("alive",false):return _decision("N0","stop","incapacitated")
	if signals.get("requires_consent",false) and not signals.get("consent",false):return _decision("N0","release","consent_revoked")
	if not signals.get("facts_valid",true) or not signals.get("target_valid",true):return _decision("N0","release","stale_or_invalid_target")
	if signals.get("danger",false):
		return _decision("N1","defend" if signals.get("guard_qualified",false) else "evade","immediate_threat")
	var need:String=str(signals.get("urgent_need",""))
	if not need.is_empty():return _decision("N2","care",need)
	var emergency:Dictionary=signals.get("emergency",{})
	if not emergency.is_empty():
		if not emergency.get("authorized",false) or not emergency.get("qualified",false):return _decision("N3","blocked",str(emergency.get("reason","emergency_not_qualified")),emergency)
		return _decision("N3","hold" if emergency.get("at_position",false) else "request",str(emergency.get("kind","defend")),emergency)
	var explicit:Dictionary=signals.get("explicit_assignment",{})
	if not explicit.is_empty() and (explicit.get("valid",false) or not explicit.get("deferred",false)):
		if not explicit.get("valid",false):return _decision("N4","blocked",str(explicit.get("reason","assignment_invalid")),explicit)
		if not explicit.get("handoff_safe",false):return _decision("N4","wait_handoff","safe_handoff_required",explicit)
		return _decision("N4","request","player_assignment",explicit)
	var carried:Dictionary=signals.get("carried_delivery",{})
	if not carried.is_empty():
		if carried.get("reachable",false) and carried.get("capacity_valid",false):return _decision("N5","deliver","finish_carried_delivery",carried)
		return _decision("N5","hold","carried_goods_need_valid_receiver",carried)
	var candidates:Array=[]
	for value:Variant in signals.get("candidates",[]):
		if value is Dictionary and value.get("valid",false) and valid_candidate(value):candidates.append(value.duplicate(true))
	if not candidates.is_empty():
		candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return _before(a,b))
		return _decision("N6","request","best_eligible_work",candidates[0])
	return _decision("N7","idle","no_eligible_work")

static func rank(values:Array)->Array:
	var result:Array=[]
	for value:Variant in values:
		if value is Dictionary and valid_candidate(value):result.append(value.duplicate(true))
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return _before(a,b))
	return result

static func valid_candidate(value:Dictionary)->bool:
	if not _valid_id(value.get("id")):return false
	for key:String in ["player_priority","wait_seconds","route_cost"]:
		var n:Variant=value.get(key,0)
		if not (n is int or n is float) or not is_finite(float(n)):return false
	if float(value.get("wait_seconds",0))<0 or float(value.get("route_cost",0))<0:return false
	for key:String in ["unblocks_output","critical_supply"]:
		if value.has(key) and not value[key] is bool:return false
	return true

static func _before(a:Dictionary,b:Dictionary)->bool:
	var a_unblock:=bool(a.get("unblocks_output",false) or a.get("critical_supply",false))
	var b_unblock:=bool(b.get("unblocks_output",false) or b.get("critical_supply",false))
	if a_unblock!=b_unblock:return a_unblock
	var ap:=float(a.get("player_priority",0));var bp:=float(b.get("player_priority",0))
	if ap!=bp:return ap>bp
	var aw:=float(a.get("wait_seconds",0));var bw:=float(b.get("wait_seconds",0))
	if aw!=bw:return aw>bw
	var ar:=float(a.get("route_cost",0));var br:=float(b.get("route_cost",0))
	if ar!=br:return ar<br
	return str(a.id)<str(b.id)

static func _decision(priority:String,action:String,reason:String,candidate:Dictionary={})->Dictionary:
	return {"priority":priority,"action":action,"reason":reason,"candidate":candidate.duplicate(true)}

static func _valid_id(value:Variant)->bool:
	return value is String and not str(value).is_empty() and str(value).length()<=192 and not str(value).contains("..")
