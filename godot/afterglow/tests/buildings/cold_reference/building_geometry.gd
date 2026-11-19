## Frozen 2026-11-14 exact geometry oracle, never a runtime service.
extends RefCounted
## Metre/Y-up adapter. Builtin AABB/Vector3 supply geometry; JSON facts retain legacy IDs.
const EPS := 0.015
var definitions: Dictionary = {}

func configure(catalog: Dictionary) -> void:
	definitions = catalog.get("structure_definitions", {}).duplicate(true)

static func point(p: Dictionary) -> Vector3:
	return Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))

static func json_point(p: Vector3) -> Dictionary:
	return {"x": p.x, "y": p.y, "z": p.z}

static func location(value: Dictionary) -> Dictionary:
	var p: Dictionary = value.get("position", value.get("location", value))
	return {"x": float(p.get("x", 0)), "y": float(p.get("y", 0)), "z": float(p.get("z", 0)),
		"regionId": p.get("regionId", p.get("region_id", value.get("regionId", value.get("region_id", "")))),
		"buildingId": p.get("buildingId", p.get("building_id", value.get("buildingId", value.get("building_id", null)))),
		"storeyId": p.get("storeyId", p.get("storey_id", value.get("storeyId", value.get("storey_id", null))))}

static func display_location(p: Dictionary) -> Dictionary:
	return {"x": p.x, "y": p.y, "z": p.z, "region_id": p.get("regionId", ""),
		"building_id": p.get("buildingId"), "storey_id": p.get("storeyId")}

static func actor_at(actor: Dictionary, p: Dictionary) -> Dictionary:
	var result := actor.duplicate(true)
	if actor.has("position"):
		result.position = display_location(p)
	else:
		result.merge(p, true)
	return result

static func rotate(v: Vector3, turn: int) -> Vector3:
	match posmod(turn, 4):
		1: return Vector3(-v.z, v.y, v.x)
		2: return Vector3(-v.x, v.y, -v.z)
		3: return Vector3(v.z, v.y, -v.x)
	return v

static func transform(v: Vector3, instance: Dictionary) -> Vector3:
	return point(instance.position) + rotate(v, int(instance.get("quarterTurn", 0)))

static func aabb(value: Dictionary) -> AABB:
	var lo := point(value.min)
	return AABB(lo, point(value.max) - lo)

static func json_box(b: AABB) -> Dictionary:
	return {"min": json_point(b.position), "max": json_point(b.end)}

static func overlap(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - 0.000001 and a.end.x > b.position.x + 0.000001 and a.position.y < b.end.y - 0.000001 and a.end.y > b.position.y + 0.000001 and a.position.z < b.end.z - 0.000001 and a.end.z > b.position.z + 0.000001

static func transformed_box(b: AABB, instance: Dictionary) -> AABB:
	var a := transform(b.position, instance)
	var c := transform(b.end, instance)
	return AABB(a.min(c), a.max(c) - a.min(c))

func definition(instance: Dictionary) -> Dictionary:
	return definitions.get(instance.get("definitionId", ""), {})

func leaf(instance: Dictionary, angle: Variant = null) -> AABB:
	var d := definition(instance)
	var door: Dictionary = instance.get("door", {})
	var radians: float = float(angle) if angle != null else (float(door.get("swing", 1)) * PI / 2.0 if door.get("open", false) else 0.0)
	var hinge: float = d.door.hingeX
	var width: float = d.door.width
	var result := AABB()
	var first := true
	for z in [-0.045, 0.045]:
		for x in [0.0, width]:
			var p := transform(Vector3(hinge + x * cos(radians) - z * sin(radians), 0, x * sin(radians) + z * cos(radians)), instance)
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	result.size.y = float(d.door.height)
	return result

func boxes(instance: Dictionary, mode: String = "collision") -> Array:
	if float(instance.get("hp", 0)) <= 0: return []
	var d := definition(instance)
	var result: Array = []
	for part in d.get("sight" if mode == "sight" else "solids", []):
		result.append(transformed_box(aabb(part), instance))
	if instance.has("door"):
		result.append(leaf(instance, 0.0 if mode == "room" else null))
	if d.has("stairs") and mode != "room":
		var stairs: Dictionary = d.stairs
		for n in 24:
			var lo := Vector3(-float(stairs.width) / 2.0, n * float(stairs.rise) / 24.0, n * float(stairs.run) / 24.0)
			result.append(transformed_box(AABB(lo, Vector3(float(stairs.width), float(stairs.rise) / 24.0, float(stairs.run) / 24.0)), instance))
	return result

func bounds(instance: Dictionary) -> AABB:
	var d := definition(instance)
	if d.has("stairs"):
		return transformed_box(AABB(Vector3(-float(d.size.x) / 2.0, 0, 0), Vector3(float(d.size.x), float(d.size.y), float(d.size.z))), instance)
	var parts: Array = d.get("solids", [])
	if parts.is_empty(): return AABB(point(instance.position), Vector3.ZERO)
	var result: AABB = aabb(parts[0])
	for b in parts.slice(1): result = result.merge(aabb(b))
	return transformed_box(result, instance)

func entity(instance: Dictionary) -> Dictionary:
	var d := definition(instance)
	var b := bounds(instance)
	for part in boxes(instance): b = b.merge(part)
	var result: Dictionary = {"id": instance.id, "kind": "structure", "regionId": instance.regionId,
		"position": instance.position.duplicate(true), "bounds": json_box(b), "revision": instance.get("version", 0),
		"definitionId": instance.definitionId, "blocksTerrain": float(instance.hp) > 0,
		"supportBounds": [json_box(b)] if float(instance.hp) > 0 and d.kind == "foundation" else [],
		"tags": [d.kind] + d.get("stationTags", []), "data": {"structure": instance.duplicate(true), "assetId": d.assetId, "materialSemantics": d.materials.duplicate(true)}}
	if instance.get("buildingId") != null: result.buildingId = instance.buildingId
	if instance.get("storeyId") != null: result.storeyId = instance.storeyId
	return result
