extends RefCounted
## Ephemeral transaction builder. No clock, persistent cache, or authority of its own.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Content = preload("res://scripts/runtime/content_definitions.gd")
var context: Dictionary
var _initial: Dictionary
var _borrowed_initial: bool = false
var initial: Dictionary:
	get:
		# Public initial is writable. Preserve the original independent staged
		# snapshot before exposing it, including nested caller edits.
		_ensure_staged()
		_detach_initial()
		return _initial
	set(value):
		invalidate_observation()
		_ensure_staged()
		_initial = value
		_borrowed_initial = false
var _staged: Dictionary
var _has_staged: bool = false
var _partially_staged: bool = false
var _detached_fields: Dictionary = {}
var staged: Dictionary:
	get:
		_ensure_staged()
		return _staged
	set(value):
		invalidate_observation()
		_staged = value.duplicate(true) if _borrowed_initial and is_same(value,_initial) else value
		_has_staged = true
		_partially_staged = false
		_detached_fields.clear()
var _extensions: Dictionary = {}
var extensions: Dictionary:
	get: return _extensions
	set(value):
		invalidate_observation()
		_extensions = value
# Only Workforce.observation opts in, for one synchronous read call. Mutable
# prepare/advance/commit Drafts never reuse observations. Borrowed nested values
# remain writable, so exact input comparisons also guard writes via aliases.
var observation_only: bool = false
var _observation_cache: Dictionary = {}
var observation_cache: Dictionary:
	get: return _observation_cache.duplicate(true)
	set(_value): invalidate_observation()
var _observation_facts: Dictionary = {}
var _observation_extensions: Dictionary = {}
var _observation_world_revision: int = -1
var _observation_clock: float = -1.0
var extra: Array = []
var events: Array = []

func _init(value: Dictionary = {}) -> void:
	context = value
	if context.get("draft_snapshot") is Callable:
		_initial=context.draft_snapshot.call();_borrowed_initial=true
	else:
		_initial = context.facts.call() if context.has("facts") else {}

func _detach_initial()->void:
	if _borrowed_initial:
		_initial=_initial.duplicate(true);_borrowed_initial=false

func _ensure_staged() -> void:
	if not _has_staged:
		_staged = _initial.duplicate(true)
		_has_staged = true
	elif _partially_staged:
		# The legacy property exposes every nested collection for mutation.
		# Preserve existing actor/stock references and detach everything else.
		for field: Variant in _staged:
			var value: Variant = _staged[field]
			if not _detached_fields.has(field) and (value is Array or value is Dictionary):
				_staged[field] = value.duplicate(true)
		_partially_staged = false
		_detached_fields.clear()

func writable_collection(field: String) -> Variant:
	if not _has_staged:
		_staged = _initial.duplicate(false)
		_has_staged = true
		_partially_staged = true
	if _partially_staged and not _detached_fields.has(field) and (_staged.get(field) is Array or _staged.get(field) is Dictionary):
		_staged[field] = _staged[field].duplicate(true)
		_detached_fields[field] = true
	return _staged.get(field, [])

func read_facts() -> Dictionary:
	# Synchronous readers may observe the latest staged values in place.
	# Writers must use a detached collection or the legacy writable property.
	return _staged if _has_staged else _initial

func observe_facts() -> Dictionary:
	# Read-only, transaction-local view. Callers must not mutate this snapshot;
	# use public staged/actor/stock (or an explicit deep fork) before any write.
	return _initial

func invalidate_observation() -> void:
	_observation_cache.clear()
	_observation_facts = {}
	_observation_extensions = {}

func cached_observation(key: String) -> Variant:
	if not observation_only or not _observation_cache.has(key): return null
	# Equality is deliberate, not a hash or object-identity assumption: actor
	# HP/consent/intent and nested extension edits must invalidate complete holds.
	if _observation_world_revision != context.world.get_revision() or _observation_clock != float(context.clock.call()) or _observation_facts != _staged or _observation_extensions != _extensions:
		invalidate_observation()
		return null
	return _observation_cache[key].duplicate(true)

func cache_observation(key: String, value: Variant) -> void:
	if not observation_only: return
	_observation_facts = staged.duplicate(true)
	_observation_extensions = extensions.duplicate(true)
	_observation_world_revision = context.world.get_revision()
	_observation_clock = float(context.clock.call())
	_observation_cache[key] = value.duplicate(true)

static func find(values: Variant, id: String) -> Dictionary:
	for v in values.values() if values is Dictionary else values if values is Array else []:
		if str(v.get("id", "")) == id: return v
	return {}

func actor(id: String) -> Dictionary:
	return find(writable_collection("actors"), id)

func stock(id: String) -> Dictionary:
	if id.begins_with("pack:"):
		var a := actor(id.trim_prefix("pack:"))
		return {} if a.is_empty() else {"id": id, "items": a.pack, "location": Geometry.location(a), "searched": true, "owner": a.id}
	return find(writable_collection("stocks"), id)

## Observe stock during a synchronous check without enrolling it for writes.
func read_stock(id: String) -> Dictionary:
	var facts := read_facts()
	if id.begins_with("pack:"):
		var person := find(facts.get("actors", []), id.trim_prefix("pack:"))
		if person.is_empty(): return {}
		return {"id": id, "items": person.pack, "location": Geometry.location(person), "searched": true, "owner": person.id}
	return find(facts.get("stocks", []), id)

func stock_delta(id: String, values: Dictionary, sign: float = 1.0) -> bool:
	invalidate_observation()
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
		invalidate_observation()
		var v: Variant = context.world.extension(id)
		extensions[id] = v if v is Dictionary else fallback.duplicate(true)
	return extensions[id]

func read_extension_fields(id:String,fields:Array[String])->Dictionary:
	# Read-only consumers check staged overrides before borrowing live fields.
	# No full extension clone, mutable alias, or extra entry in the write set.
	if not _extensions.has(id) and context.world.has_method("extension_fields"):
		return context.world.extension_fields(id,fields)
	var source:Variant=_extensions[id] if _extensions.has(id) else context.world.extension(id)
	var result:Dictionary={}
	if source is Dictionary:
		for field:String in fields:
			if not source.has(field):continue
			var v:Variant=source[field]
			result[field]=v.duplicate(true) if v is Array or v is Dictionary else v
	return result

func result() -> Dictionary:
	invalidate_observation()
	if context.get("available") is Callable and not context.available.call():return {"ok":false,"code":"UNAVAILABLE","reason":"事务所属运行时已关闭","world_changes":[],"fact_changes":[],"events":[]}
	var facts: Array = []
	# No writable facts were requested, or the caller explicitly supplied its
	# isolated initial snapshot for read-only inspection. Both compare equal
	# under the existing diff; retain the complete plan and availability check.
	if _has_staged and not is_same(_initial,_staged) and context.get("facts_diff") is Callable:
		facts=context.facts_diff.call(_initial,_staged)
	elif _has_staged and not is_same(_initial,_staged):
		# Non-runtime isolated adapters retain the exact existing diff. The live
		# runtime always supplies its public, isolated, linear ID diff above.
		for collection in ["actors", "stocks", "actions", "quests"]:
			for v in _staged.get(collection, []):
				var before := find(_initial.get(collection, []), str(v.id))
				if before != v: facts.append({"collection": collection, "id": v.id, "before": null if before.is_empty() else before.duplicate(true), "after": v.duplicate(true)})
			for v in _initial.get(collection, []):
				if find(_staged.get(collection, []), str(v.id)).is_empty(): facts.append({"collection": collection, "id": v.id, "before": v.duplicate(true), "after": null})
	var changes: Array = extra.duplicate(true)
	var can_compare: bool = not extensions.is_empty() and context.world.has_method("extension_equals")
	for id in extensions:
		if can_compare and context.world.extension_equals(id, extensions[id]): continue
		var before: Variant = context.world.extension(id)
		if can_compare or before != extensions[id]: changes.append({"op": "extension.set", "id": id, "before_exists": context.world.has_extension(id), "before": before, "after": extensions[id].duplicate(true)})
	return {"ok": true, "code": "OK", "reason": null, "world_changes": changes, "fact_changes": facts, "duration": 0.0, "destination": {}, "events": events.duplicate(true)}

static func unique(values: Array) -> Array:
	var seen: Dictionary = {}
	for value in values: seen[value] = true
	return seen.keys()
