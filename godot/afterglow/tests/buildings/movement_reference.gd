extends "res://scripts/buildings/building_space.gd"
## Frozen original direct_move before stair-only candidate projection.
func direct_move(actor_id: String, from: Dictionary, to: Dictionary) -> Dictionary:
	if Geometry.point(from).distance_to(Geometry.point(to)) > agent.max_move_distance: return {"ok": false, "code": "INVALID", "reason": "单次移动过长"}
	var current := from.duplicate(true)
	var count := maxi(1, int(ceil(Vector2(float(to.x) - float(from.x), float(to.z) - float(from.z)).length() / 0.08)))
	for n in range(1, count + 1):
		var next := current.duplicate(true)
		next.x = lerpf(from.x, to.x, float(n) / count)
		next.z = lerpf(from.z, to.z, float(n) / count)
		var on_stair := false
		for v in pieces:
			if not v.has("stairs") or float(v.hp) <= 0 or v.regionId != from.regionId or v.get("buildingId") != current.get("buildingId"): continue
			var d: Dictionary = geometry.definition(v).stairs
			var local := Geometry.rotate(Geometry.point(current) - Geometry.point(v.position), -int(v.quarterTurn))
			var desired := Geometry.rotate(Geometry.point(next) - Geometry.point(v.position), -int(v.quarterTurn))
			if absf(local.x) > float(d.width) / 2.0 - agent.radius + 0.001: continue
			if local.z < -agent.radius - 0.001 and desired.z < -agent.radius - 0.001: continue
			if local.z > float(d.run) + agent.radius + 0.001 and desired.z > float(d.run) + agent.radius + 0.001: continue
			var expected := minf(float(d.rise), maxf(0, ceil((local.z + agent.radius) / (float(d.run) / 24.0)) * float(d.rise) / 24.0))
			var entry: bool = local.z <= 0.0 and absf(local.y) <= 0.025 and current.get("storeyId") == v.stairs.fromStoreyId
			var exit: bool = local.z >= float(d.run) and absf(local.y - float(d.rise)) <= 0.025 and current.get("storeyId") == v.stairs.toStoreyId
			if absf(float(current.y) - float(v.position.y) - expected) > 0.025 and not entry and not exit: continue
			if absf(desired.x) > float(d.width) / 2.0 - agent.radius + 0.001 or not stair_clear(v): return {"ok": false, "code": "BLOCKED", "reason": "楼梯侧沿、净空或平台不可用"}
			next.storeyId = v.stairs.toStoreyId if desired.z >= float(d.run) else v.stairs.fromStoreyId
			next.y = float(v.position.y) + minf(float(d.rise), maxf(0, ceil((desired.z + agent.radius) / (float(d.run) / 24.0)) * float(d.rise) / 24.0))
			if not blockers(current, next, actor_id, false, v.id).ok: return {"ok": false, "code": "BLOCKED", "reason": "楼梯身体被阻挡"}
			if desired.z < -agent.radius or desired.z > float(d.run) + agent.radius:
				var landing := standing_point(next)
				if landing.is_empty(): return {"ok": false, "code": "UNSUPPORTED", "reason": "楼梯落地平台缺失"}
				next = landing
			current = next
			on_stair = true
			break
		if not on_stair:
			var result := walk(actor_id, current, next)
			if not result.ok: return result
			current = result.location
	return {"ok": true, "location": current}

