extends "res://../../outputs/r3.3-ccc-evidence/section8-before/world_view.gd"
## Sole authoritative terrain/entity store. Copy-on-write drafts, never scene callbacks.
const View = preload("res://../../outputs/r3.3-ccc-evidence/section8-before/world_view.gd")
var _prepared: Dictionary = {}
var _epoch: int = 0

func load_snapshot(data: Dictionary) -> Dictionary:
	var result := Data.validate(data)
	if not result.ok: return result
	var next := data.duplicate(true)
	for k in next.chunks:
		next.chunks[k].cells = PackedInt32Array(next.chunks[k].cells)
	_state = next
	_epoch += 1
	_prepared.clear()
	return {"ok":true,"code":"OK","revision":get_revision()}

func prepare_changes(changes: Array, expected_world_revision: int) -> Dictionary:
	if _state.is_empty(): return Data.reject("NO_WORLD")
	if get_revision() != expected_world_revision: return Data.reject("STALE_WORLD_REVISION")
	if changes.size() > 16384: return Data.reject("TOO_MANY_CHANGES")
	# Only touched records/cells are copied; the committed graph remains immutable.
	var draft := _state.duplicate(false)
	for name in ["chunks","entities","regions","extensions"]: draft[name] = _state[name].duplicate(false)
	draft.retiredEntityIds = _state.retiredEntityIds.duplicate()
	var seen := {}
	var dirty := {}
	var entity_ids := {}
	var copied_chunks := {}
	var effective: Array = []
	var next_revision := get_revision()+1
	for input in changes:
		if not input is Dictionary or not input.get("op") is String: return Data.reject("INVALID_CHANGE")
		var c: Dictionary = input.duplicate(true)
		var op: String = c.op
		var id := str(c.get("id",""))
		var target := ""
		if op == "voxel.set":
			var p: Variant = c.get("cell")
			if not Data.vec(p) or not [p.x,p.y,p.z].all(Data.integer): return Data.reject("INVALID_CHANGE")
			var cell := Vector3i(int(p.x),int(p.y),int(p.z))
			target = "voxel:"+Data.key(cell)
			if not is_cell_known(cell.x,cell.y,cell.z): return Data.reject("UNKNOWN_CELL")
			if not Data.integer(c.get("before")) or cell_at(cell.x,cell.y,cell.z) != c.before: return Data.reject("CAS_MISMATCH")
			if not Data.integer(c.get("after")) or not Data.MATERIALS.has(int(c.after)): return Data.reject("UNKNOWN_MATERIAL")
			if seen.has(target): return Data.reject("DUPLICATE_TARGET")
			seen[target] = true
			if c.before == c.after: continue
			var n := int(_state.config.chunkCells)
			var k := Data.key(Data.cell_chunk(cell,n))
			if seen.has("chunk:"+k): return Data.reject("DUPLICATE_TARGET")
			seen["voxel_chunk:"+k] = true
			if not copied_chunks.has(k):
				draft.chunks[k] = _state.chunks[k].duplicate(true)
				copied_chunks[k] = true
			draft.chunks[k].cells[Data.local_index(cell,n)] = int(c.after)
			draft.chunks[k].revision = next_revision
			for key in Data.affected(cell,n): dirty[key] = true
		else:
			if not Data.valid_id(id): return Data.reject("INVALID_ID")
			var collection := ""
			match op:
				"chunk.put", "chunk.residency": collection = "chunks"
				"region.put": collection = "regions"
				"entity.put", "entity.remove": collection = "entities"
				"extension.set": collection = "extensions"
				_: return Data.reject("UNKNOWN_OPERATION",op)
			target = collection+":"+id
			if seen.has(target) or (collection == "chunks" and seen.has("voxel_chunk:"+id)): return Data.reject("DUPLICATE_TARGET")
			seen[target] = true
			var exists: bool = _state[collection].has(id)
			var old: Variant = _state[collection].get(id)
			if not c.has("before"): return Data.reject("INVALID_CHANGE","missing before")
			if op == "chunk.residency":
				if not exists or not c.before is bool or not c.get("after") is bool or old.resident != c.before: return Data.reject("CAS_MISMATCH")
				if c.before == c.after: continue
				draft.chunks[id] = old.duplicate(true)
				draft.chunks[id].resident = c.after
				draft.chunks[id].revision = next_revision
			elif op == "entity.remove":
				if not exists or old != c.before: return Data.reject("CAS_MISMATCH")
				draft.entities.erase(id)
				draft.retiredEntityIds.append(id)
			else:
				if not c.get("before_exists") is bool or exists != c.before_exists or old != c.before or not c.has("after"): return Data.reject("CAS_MISMATCH")
				if op == "entity.put" and id in draft.retiredEntityIds: return Data.reject("RETIRED_ENTITY_ID")
				if op == "extension.set" and not Data.json_value(c.after): return Data.reject("INVALID_JSON_FACT")
				if old == c.after and exists: continue
				if collection != "extensions" and not c.after is Dictionary: return Data.reject("INVALID_CHANGE")
				draft[collection][id] = c.after.duplicate(true) if c.after is Dictionary or c.after is Array else c.after
				if collection in ["chunks","entities"]: draft[collection][id].revision = next_revision
			if collection == "chunks":
				var q: Variant = Data.coord(id)
				if q == null: return Data.reject("INVALID_CHUNK")
				dirty[id] = true
				for axis in 3:
					for sign in [-1,1]:
						var neighbor: Vector3i = q
						neighbor[axis] += sign
						dirty[Data.key(neighbor)] = true
			elif collection == "entities": entity_ids[id] = true
		effective.append(c)
	draft.revision = next_revision if not effective.is_empty() else get_revision()
	# Existing untampered cell buffers were already checked on load; recheck only replacements.
	for c in effective:
		if c.op == "chunk.put":
			var error := Data.chunk_error(c.id,draft.chunks[c.id],draft)
			if error: return Data.reject(error,c.id)
		elif c.op == "entity.put":
			var e: Dictionary = draft.entities[c.id]
			if not Data.json_value(e) or not draft.regions.has(e.get("regionId")) or not Data.vec(e.get("position")) or not Data.contains(draft.regions[e.regionId].bounds,e.position): return Data.reject("INVALID_ENTITY",c.id)
		elif c.op == "region.put" and not Data.json_value(c.after): return Data.reject("INVALID_REGION",c.id)
	# Unchanged JSON subgraphs/receipts are already validated and immutable; do not
	# recurse through every historical receipt on each cell edit.
	var valid := Data.validate(draft,false,false)
	if not valid.ok: return valid
	# New region allocations must not overlap. Historical regions are preserved verbatim.
	for c in effective:
		if c.op == "region.put":
			for r in draft.regions.values():
				if r.id != c.id and Data.intersects(r.bounds,c.after.bounds): return Data.reject("INVALID_REGION","overlap")
	var token := RefCounted.new()
	for k in _prepared.keys():
		if _prepared[k].weak.get_ref() == null: _prepared.erase(k)
	if _prepared.size() >= 32: return Data.reject("TOO_MANY_PREPARED")
	var result_changes := {"operations":effective.duplicate(true),"chunks":dirty.keys(),"entities":entity_ids.keys(),"world_revision":draft.revision,"previous_revision":get_revision(),"invalidations":["render","collision","navigation","picking","environment","support","save"]}
	_prepared[token.get_instance_id()] = {"weak":weakref(token),"epoch":_epoch,"base":get_revision(),"draft":draft,"changes":result_changes}
	# Even reflective access to a view's conventional _state cannot modify the
	# prevalidated capability payload. Packed arrays retain COW storage semantics.
	return {"ok":true,"code":"OK","reason":null,"capability":token,"view":View.new(draft.duplicate(true)),"changes":result_changes.duplicate(true)}

func discard_prepared(capability: Variant) -> void:
	if capability is RefCounted: _prepared.erase(capability.get_instance_id())

func create_view(context: Dictionary) -> Node3D:
	var view := preload("res://scripts/terrain/terrain_view.gd").new()
	var domain_context := context.duplicate(false)
	domain_context.world = self
	view.configure(domain_context)
	return view

func commit_prepared(capability: Variant) -> Dictionary:
	if not capability is RefCounted: return Data.reject("FOREIGN_PREPARED")
	var id: int = capability.get_instance_id()
	if not _prepared.has(id) or _prepared[id].weak.get_ref() != capability: return Data.reject("PREPARED_CLOSED")
	var pending: Dictionary = _prepared[id]
	_prepared.erase(id)
	if pending.epoch != _epoch or pending.base != get_revision(): return Data.reject("STALE_WORLD_REVISION")
	_state = pending.draft
	return {"ok":true,"code":"OK","reason":null,"revision":get_revision(),"changes":pending.changes.duplicate(true)}
