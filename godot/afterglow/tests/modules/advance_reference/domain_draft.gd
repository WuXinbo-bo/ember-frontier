extends RefCounted
## Ephemeral transaction builder. No clock, persistent cache, or authority of its own.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Content = preload("res://scripts/runtime/content_definitions.gd")
var context: Dictionary
var initial: Dictionary
var staged: Dictionary
var extensions: Dictionary = {}
var extra: Array = []
var events: Array = []

func _init(value: Dictionary = {}) -> void:
	context = value
	initial = context.facts.call() if context.has("facts") else {}
	staged = initial.duplicate(true)

static func find(values: Variant, id: String) -> Dictionary:
	for v in values.values() if values is Dictionary else values if values is Array else []:
		if str(v.get("id", "")) == id: return v
	return {}

func actor(id: String) -> Dictionary:
	return find(staged.get("actors", []), id)

func stock(id: String) -> Dictionary:
	if id.begins_with("pack:"):
		var a := actor(id.trim_prefix("pack:"))
		return {} if a.is_empty() else {"id": id, "items": a.pack, "location": Geometry.location(a), "searched": true, "owner": a.id}
	return find(staged.get("stocks", []), id)

func stock_delta(id: String, values: Dictionary, sign: float = 1.0) -> bool:
	var s := stock(id)
	if s.is_empty(): return false
	for item in values:
		var n := float(s.items.get(item, 0)) + float(values[item]) * sign
		# Compatibility belongs to existing inventory, never formal recipe refs.
		# Volume quantities retain their exact finite value; do not round to step.
		if n < -0.000001 or not Content.quantity_valid(str(item),maxf(0,n),true): return false
	for item in values: s.items[item] = maxf(0, float(s.items.get(item, 0)) + float(values[item]) * sign)
	return true

func extension(id: String, fallback: Dictionary = {}) -> Dictionary:
	if not extensions.has(id):
		var v: Variant = context.world.extension(id)
		extensions[id] = v if v is Dictionary else fallback.duplicate(true)
	return extensions[id]

func result() -> Dictionary:
	if context.get("available") is Callable and not context.available.call():return {"ok":false,"code":"UNAVAILABLE","reason":"事务所属运行时已关闭","world_changes":[],"fact_changes":[],"events":[]}
	var facts: Array = []
	if context.get("facts_diff") is Callable:
		facts=context.facts_diff.call(initial,staged)
	else:
		# Non-runtime isolated adapters retain the exact existing diff. The live
		# runtime always supplies its public, isolated, linear ID diff above.
		for collection in ["actors", "stocks", "actions", "quests"]:
			for v in staged.get(collection, []):
				var before := find(initial.get(collection, []), str(v.id))
				if before != v: facts.append({"collection": collection, "id": v.id, "before": null if before.is_empty() else before.duplicate(true), "after": v.duplicate(true)})
			for v in initial.get(collection, []):
				if find(staged.get(collection, []), str(v.id)).is_empty(): facts.append({"collection": collection, "id": v.id, "before": v.duplicate(true), "after": null})
	var changes: Array = extra.duplicate(true)
	for id in extensions:
		var before: Variant = context.world.extension(id)
		if before != extensions[id]: changes.append({"op": "extension.set", "id": id, "before_exists": context.world.has_extension(id), "before": before, "after": extensions[id].duplicate(true)})
	return {"ok": true, "code": "OK", "reason": null, "world_changes": changes, "fact_changes": facts, "duration": 0.0, "destination": {}, "events": events.duplicate(true)}

static func unique(values: Array) -> Array:
	var seen: Dictionary = {}
	for value in values: seen[value] = true
	return seen.keys()
