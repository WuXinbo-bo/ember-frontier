extends "res://scripts/world/world_view.gd"
## Sole authoritative terrain/entity store. Copy-on-write drafts, never scene callbacks.
const View = preload("res://scripts/world/candidate_world_view.gd")
const DetachedResidency = preload("res://scripts/world/detached_residency.gd")
var _prepared: Dictionary = {}
var _epoch: int = 0
var _extension_epochs:Dictionary={}
var _factory_visual_revision := 0
var _generation_plan_revision := 0

# Consumers also track the snapshot generation; this counter tracks only
# committed replacements of authored generation plans on this world.
func generation_plan_revision() -> int:
	return _generation_plan_revision

func factory_visual_revision() -> int:
	return _factory_visual_revision

func extension_token(id:String)->Dictionary:
	# Ephemeral authority identity, never a stored payload revision or reference.
	return {"authority":get_instance_id(),"generation":_epoch,"extension":int(_extension_epochs.get(id,0))}

func matches_validated_extension_field(id:String,field:String,expected:Variant)->bool:
	# Loaded extensions and committed replacements have already passed JSON
	# validation. Keep the authoritative object private and compare at the same
	# top-level field depth. A detached/unloaded view cannot supply this proof.
	if _epoch==0:return false
	var value:Variant=_state.get("extensions",{}).get(id)
	return value is Dictionary and value.has(field) and typeof(value[field])==typeof(expected) and value[field]==expected

func capture_region_residency(region_id:String,resident:bool,expected_world_revision:int,max_chunks:int=256)->Dictionary:
	# MAIN THREAD only, serialized with the Runtime. Copy only target payloads;
	# no compression, decoding, hashing, pins, files or authority mutation here.
	if expected_world_revision!=get_revision():return Data.reject("STALE_WORLD_REVISION")
	if max_chunks<1 or max_chunks>DetachedResidency.MAX_CHUNKS:return Data.reject("INVALID_RESIDENCY_BUDGET")
	var r:Dictionary=_state.get("regions",{}).get(region_id,{})
	if not r.get("generated",false):return Data.reject("UNKNOWN_REGION")
	var started:int=Time.get_ticks_usec();var keys:Array=region_chunk_keys(region_id)
	if keys.is_empty():return Data.reject("UNKNOWN_REGION")
	if keys.size()>DetachedResidency.MAX_GUARDS:return Data.reject("DETACHED_RESIDENCY_BUDGET")
	var width:float=float(_state.config.cellSize)*int(_state.config.chunkCells)
	var guards:Dictionary={};var rows:Array=[];var needed:int=0;var payload_bytes:int=0
	for key:String in keys:
		var old:Dictionary=_state.chunks.get(key,{})
		if not old.get("generated",false):return Data.reject("UNKNOWN_CELL",key)
		var p:Vector3i=Data.coord(key)
		var box:Dictionary={"min":{"x":p.x*width,"y":p.y*width,"z":p.z*width},"max":{"x":(p.x+1)*width,"y":(p.y+1)*width,"z":(p.z+1)*width}}
		for other:Dictionary in _state.regions.values():
			if other.id!=region_id and Data.intersects(box,other.bounds):return Data.reject("SHARED_CHUNK_RESIDENCY",key)
		guards[key]={"revision":old.revision,"resident":old.resident,"generated":old.generated,"has_page":old.has("cell_page")}
		if resident and old.resident and not old.has("cell_page"):continue
		if not resident and old.has("cell_page"):continue
		needed+=1
		if rows.size()>=max_chunks:continue
		payload_bytes+=old.cell_page.data.length() if old.has("cell_page") else old.cells.size()*4
		if payload_bytes>DetachedResidency.MAX_INPUT_BYTES:return Data.reject("DETACHED_RESIDENCY_BUDGET")
		# Explicit packed-array duplication gives the worker its own buffer.
		# Dictionary/Array metadata is also detached, never an _state reference.
		rows.append({"id":key,"revision":old.revision,"resident":old.resident,"cells":old.cells.duplicate(),"cell_page":old.cell_page.duplicate(true) if old.has("cell_page") else null})
	var basis:Dictionary={"identity":identity(),"config":config(),"region":r.duplicate(true),"captured_world_revision":expected_world_revision,"chunks":guards}
	var input:Dictionary={"schema":DetachedResidency.SCHEMA,"region_id":region_id,"resident":resident,"max_chunks":max_chunks,"needed_chunks":needed,"basis":basis,"rows":rows,"state_before":region_residency_state(region_id)}
	return {"ok":true,"code":"OK","input":input,"cost":{"capture_usec":Time.get_ticks_usec()-started,"detached_payload_bytes":payload_bytes,"captured_chunks":rows.size(),"guard_chunks":keys.size()}}

static func prepare_detached_region_residency(input:Dictionary)->Dictionary:
	# Thread.start(State.prepare_detached_region_residency.bind(captured.input)).
	# The worker receives no world instance/capability and cannot commit or rebase.
	return DetachedResidency.prepare(input)

func prepare_region_residency(region_id:String,resident:bool,expected_world_revision:int,max_chunks:int=256)->Dictionary:
	# Pure conversion draft only. A pins actors/routes/combat, persists an
	# identical checkpoint and owns the one runtime safety check/commit.
	if expected_world_revision!=get_revision():return Data.reject("STALE_WORLD_REVISION")
	if max_chunks<1 or max_chunks>8192:return Data.reject("INVALID_RESIDENCY_BUDGET")
	var r:Dictionary=_state.get("regions",{}).get(region_id,{})
	if not r.get("generated",false):return Data.reject("UNKNOWN_REGION")
	var keys:Array=region_chunk_keys(region_id)
	if keys.is_empty():return Data.reject("UNKNOWN_REGION")
	var started:int=Time.get_ticks_usec();var changes:Array=[];var needed:int=0
	var length:int=int(_state.config.chunkCells)**3
	var width:float=float(_state.config.cellSize)*int(_state.config.chunkCells)
	for key:String in keys:
		var old:Dictionary=_state.chunks.get(key,{})
		if not old.get("generated",false):return Data.reject("UNKNOWN_CELL",key)
		# Partial/stacked legacy partitions may share a chunk. Do not cool a
		# neighbour by changing the storage of that shared factual buffer.
		var p:Vector3i=Data.coord(key)
		var box:Dictionary={"min":{"x":p.x*width,"y":p.y*width,"z":p.z*width},"max":{"x":(p.x+1)*width,"y":(p.y+1)*width,"z":(p.z+1)*width}}
		for other:Dictionary in _state.regions.values():
			if other.id!=region_id and Data.intersects(box,other.bounds):return Data.reject("SHARED_CHUNK_RESIDENCY",key)
		if resident and old.resident and not old.has("cell_page"):continue
		if not resident and old.has("cell_page"):continue
		needed+=1
		if changes.size()>=max_chunks:continue
		var after:Dictionary={"resident":resident,"cells":PackedInt32Array(),"cell_page":null}
		var digest:String=""
		if old.has("cell_page"):
			var decoded:Dictionary=Data.ChunkPage.unpack(old.cell_page,length,Data.MATERIALS)
			if not decoded.ok:return decoded.merged({"chunk_id":key})
			after.cells=decoded.cells;digest=old.cell_page.raw_sha256
		else:
			digest=Data.ChunkPage.fingerprint(old.cells)
			if resident:after.cells=old.cells.duplicate()
			else:
				var encoded:Dictionary=Data.ChunkPage.pack(old.cells,length,Data.MATERIALS)
				if not encoded.ok:return encoded.merged({"chunk_id":key})
				after.cell_page=encoded.page
		changes.append({"op":"chunk.storage","id":key,"before":{"revision":old.revision,"resident":old.resident,"sha256":digest},"after":after})
	return {"ok":true,"code":"OK","region_id":region_id,"resident":resident,"expected_world_revision":expected_world_revision,"world_changes":changes,"remaining_chunks":needed-changes.size(),"complete":needed==changes.size(),"cost":{"prepare_usec":Time.get_ticks_usec()-started,"converted_chunks":changes.size()},"state_before":region_residency_state(region_id)}

func load_snapshot(data: Dictionary) -> Dictionary:
	var result := Data.validate(data)
	if not result.ok: return result
	var next := data.duplicate(true)
	for k in next.chunks:
		next.chunks[k].cells = PackedInt32Array(next.chunks[k].cells)
	_state = next
	_clear_entity_spatial_index()
	_region_readiness.clear()
	_resident_prisms.clear()
	_region_points.clear()
	_epoch += 1
	_extension_epochs.clear()
	_prepared.clear()
	return {"ok":true,"code":"OK","revision":get_revision()}

func prepare_changes(changes: Array, expected_world_revision: int) -> Dictionary:
	return _prepare_changes(changes, expected_world_revision, true, true)

func prepare_changes_without_view(changes: Array, expected_world_revision: int) -> Dictionary:
	# Internal validation callers may prove that all of their reads are unchanged.
	# Export no draft at all; never expose the private capability through a view.
	return _prepare_changes(changes, expected_world_revision, false, true)

func prepare_runtime_changes(changes: Array, expected_world_revision: int, export_view: bool = true) -> Dictionary:
	return _prepare_changes(changes, expected_world_revision, export_view, false)

func _prepare_changes(changes: Array, expected_world_revision: int, export_view: bool, include_summary: bool) -> Dictionary:
	if _state.is_empty(): return Data.reject("NO_WORLD")
	if get_revision() != expected_world_revision: return Data.reject("STALE_WORLD_REVISION")
	if changes.size() > 16384: return Data.reject("TOO_MANY_CHANGES")
	# Only touched records/cells are copied; the committed graph remains immutable.
	var draft := _state.duplicate(false)
	var detached_collections: Dictionary = {}
	var seen := {}
	var dirty := {}
	var entity_ids := {}
	var copied_chunks := {}
	var effective: Array = []
	var next_revision := get_revision()+1
	var validate_graph := false
	var append_only := true
	for input in changes:
		if not input is Dictionary or not input.get("op") is String: return Data.reject("INVALID_CHANGE")
		var c: Dictionary = input.duplicate(true)
		var op: String = c.op
		var id := str(c.get("id",""))
		var target := ""
		if op == "voxel.set":
			append_only = false
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
			if seen.has("chunks:"+k): return Data.reject("DUPLICATE_TARGET")
			seen["voxel_chunk:"+k] = true
			if not copied_chunks.has(k):
				_detach_collection(draft, detached_collections, "chunks")
				draft.chunks[k] = _state.chunks[k].duplicate(true)
				copied_chunks[k] = true
			draft.chunks[k].cells[Data.local_index(cell,n)] = int(c.after)
			draft.chunks[k].revision = next_revision
			for key in Data.affected(cell,n): dirty[key] = true
		else:
			if not Data.valid_id(id): return Data.reject("INVALID_ID")
			var collection := ""
			match op:
				"chunk.put", "chunk.residency", "chunk.storage": collection = "chunks"
				"region.put": collection = "regions"
				"entity.put", "entity.remove": collection = "entities"
				"extension.set": collection = "extensions"
				_: return Data.reject("UNKNOWN_OPERATION",op)
			target = collection+":"+id
			if seen.has(target) or (collection == "chunks" and seen.has("voxel_chunk:"+id)): return Data.reject("DUPLICATE_TARGET")
			seen[target] = true
			var exists: bool = _state[collection].has(id)
			var old: Variant = _state[collection].get(id)
			if op != "extension.set" and (exists or op not in ["chunk.put", "entity.put", "region.put"]):
				append_only = false
			# Existing records use the exact full-load entity schema below. They
			# cannot change graph cardinality/IDs, retired IDs or other records.
			if op in ["chunk.put","entity.remove","region.put"] or (op=="entity.put" and not exists): validate_graph = true
			if not c.has("before"): return Data.reject("INVALID_CHANGE","missing before")
			if op == "chunk.residency":
				if not exists or not c.before is bool or not c.get("after") is bool or old.resident != c.before: return Data.reject("CAS_MISMATCH")
				if c.after and old.has("cell_page"):return Data.reject("CHUNK_PAGE_REQUIRES_RESTORE")
				if c.before == c.after: continue
				_detach_collection(draft, detached_collections, "chunks")
				draft.chunks[id] = old.duplicate(true)
				draft.chunks[id].resident = c.after
				draft.chunks[id].revision = next_revision
			elif op == "chunk.storage":
				if not exists or not old.generated or not c.before is Dictionary or not c.get("after") is Dictionary:return Data.reject("INVALID_CHANGE")
				if c.before.get("revision")!=old.revision or c.before.get("resident")!=old.resident:return Data.reject("CAS_MISMATCH")
				var digest:String=old.cell_page.raw_sha256 if old.has("cell_page") else Data.ChunkPage.fingerprint(old.cells)
				if c.before.get("sha256")!=digest:return Data.reject("CAS_MISMATCH")
				if c.after.size()!=3 or not c.after.has_all(["resident","cells","cell_page"]) or not c.after.resident is bool:return Data.reject("INVALID_CHANGE")
				var replacement:Dictionary=old.duplicate(false)
				replacement.resident=c.after.resident;replacement.cells=c.after.cells;replacement.revision=next_revision
				if c.after.cell_page==null:replacement.erase("cell_page")
				else:replacement.cell_page=c.after.cell_page
				var storage_world:Dictionary=draft.duplicate(false);storage_world.revision=next_revision
				var storage_error:String=Data.chunk_error(id,replacement,storage_world)
				if not storage_error.is_empty():return Data.reject(storage_error,id)
				var after_digest:String=replacement.cell_page.raw_sha256 if replacement.has("cell_page") else Data.ChunkPage.fingerprint(replacement.cells)
				if after_digest!=digest:return Data.reject("CHUNK_STORAGE_CONTENT_MISMATCH",id)
				_detach_collection(draft, detached_collections, "chunks")
				draft.chunks[id]=replacement
			elif op == "entity.remove":
				if not exists or old != c.before: return Data.reject("CAS_MISMATCH")
				_detach_collection(draft, detached_collections, "entities")
				if is_same(draft.retiredEntityIds, _state.retiredEntityIds):
					draft.retiredEntityIds = _state.retiredEntityIds.duplicate()
				draft.entities.erase(id)
				draft.retiredEntityIds.append(id)
			else:
				if not c.get("before_exists") is bool or exists != c.before_exists or old != c.before or not c.has("after"): return Data.reject("CAS_MISMATCH")
				if op == "entity.put" and id in draft.retiredEntityIds: return Data.reject("RETIRED_ENTITY_ID")
				if op == "extension.set" and not Data.json_value(c.after): return Data.reject("INVALID_JSON_FACT")
				if old == c.after and exists: continue
				if collection != "extensions" and not c.after is Dictionary: return Data.reject("INVALID_CHANGE")
				# c is already a private deep copy. Extensions are not subsequently
				# modified; sharing that private value with its private receipt is
				# safe. Both public outputs below are still independently detached.
				_detach_collection(draft, detached_collections, collection)
				draft[collection][id] = c.after if collection=="extensions" else c.after.duplicate(true) if c.after is Dictionary or c.after is Array else c.after
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
	if not Data.integer(draft.revision): return Data.reject("INVALID_WORLD","revision exhausted")
	# Existing untampered cell buffers were already checked on load; recheck only replacements.
	for c in effective:
		if c.op == "chunk.put":
			var error := Data.chunk_error(c.id,draft.chunks[c.id],draft)
			if error: return Data.reject(error,c.id)
		elif c.op == "entity.put":
			var e: Dictionary = draft.entities[c.id]
			if not Data.json_value(e) or Data.entity_error(c.id,e,draft) or not Data.contains(draft.regions[e.regionId].bounds,e.position): return Data.reject("INVALID_ENTITY",c.id)
		elif c.op == "region.put" and not Data.json_value(c.after): return Data.reject("INVALID_REGION",c.id)
	# Unchanged JSON subgraphs/receipts are already validated and immutable; do not
	# recurse through every historical receipt on each cell edit.
	# Cell CAS/material checks, bool residency and JSON-only extension changes
	# cannot alter region/entity/receipt identities, sizes or relationships.
	# The committed graph was fully validated at load or on an earlier commit.
	# Pure insertions cannot invalidate existing members or receipt revisions.
	# The loop above validates every inserted chunk/entity; check the new region
	# schema and total chunk capacity here. The overlap pass below is unchanged.
	if validate_graph:
		if append_only:
			if Data.chunk_capacity_exceeded(draft): return Data.reject("SAVE_TOO_LARGE")
			for change: Dictionary in effective:
				if change.op != "region.put": continue
				var error := Data.region_error(change.id, change.after)
				if error: return Data.reject(error, change.id)
		else:
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
	var result_changes := {"operations":effective,"chunks":dirty.keys(),"entities":entity_ids.keys(),"world_revision":draft.revision,"previous_revision":get_revision(),"invalidations":["render","collision","navigation","picking","environment","support","save"]}
	var extension_ids:Dictionary={}
	for input:Dictionary in changes:
		if input.get("op")=="extension.set":extension_ids[str(input.id)]=true
	var readiness:Variant=_storage_readiness_basis(effective)
	_prepared[token.get_instance_id()] = {"weak":weakref(token),"epoch":_epoch,"base":get_revision(),"draft":draft,"changes":result_changes,"extension_ids":extension_ids,"readiness":readiness}
	# The query proxy closes over this immutable COW graph. Only detached DTOs
	# can cross its read whitelist, including through reflective Callable access.
	var result: Dictionary = {"ok": true, "code": "OK", "reason": null, "capability": token}
	# The transaction owner may need only the query view and capability. Its
	# own later notification must still use a detached, fully ordered copy.
	if include_summary: result.changes = result_changes.duplicate(true)
	if export_view:result.view=View.new(draft,readiness if readiness is Dictionary else {})
	return result

static func _detach_collection(draft: Dictionary, detached: Dictionary, collection: String) -> void:
	if detached.has(collection): return
	draft[collection] = draft[collection].duplicate(false)
	detached[collection] = true

func _storage_readiness_basis(operations:Array)->Variant:
	if operations.is_empty() or _region_readiness.is_empty():return null
	var low:=Vector3i.ZERO;var high:=Vector3i.ZERO;var first:=true
	for op:Dictionary in operations:
		if op.op not in ["chunk.storage","chunk.residency"]:return null
		var coord:Vector3i=Data.coord(op.id)
		low=coord if first else low.min(coord)
		high=coord if first else high.max(coord)
		first=false
	var result:Dictionary={}
	for id:String in _region_readiness:
		var extent:=_residency_extent(_state.regions[id])
		var a:Vector3i=extent[0];var b:Vector3i=extent[1]
		# Conservative for scattered edits, including chunks shared by two
		# regions. Only keep proof for regions wholly outside the edited box.
		if b.x<low.x or b.y<low.y or b.z<low.z or a.x>high.x or a.y>high.y or a.z>high.z:
			result[id]=_region_readiness[id]
	return result

func discard_prepared(capability: Variant) -> void:
	if capability is RefCounted: _prepared.erase(capability.get_instance_id())

func create_view(context: Dictionary) -> Node3D:
	var view := preload("res://scripts/terrain/terrain_view.gd").new()
	var domain_context := context.duplicate(false)
	domain_context.world = self
	view.configure(domain_context)
	return view

func commit_prepared(capability: Variant) -> Dictionary:
	return _commit_prepared(capability, true)

func commit_runtime_changes(capability: Variant) -> Dictionary:
	return _commit_prepared(capability, false)

func _commit_prepared(capability: Variant, include_summary: bool) -> Dictionary:
	if not capability is RefCounted: return Data.reject("FOREIGN_PREPARED")
	var id: int = capability.get_instance_id()
	if not _prepared.has(id) or _prepared[id].weak.get_ref() != capability: return Data.reject("PREPARED_CLOSED")
	var pending: Dictionary = _prepared[id]
	_prepared.erase(id)
	if pending.epoch != _epoch or pending.base != get_revision(): return Data.reject("STALE_WORLD_REVISION")
	_state = pending.draft
	# Dialog and quest read-state never changes factory scenery. Treat every
	# other committed edit as relevant, including unfamiliar extensions.
	for change: Dictionary in pending.changes.operations:
		if change.op != "extension.set" or change.id != "r34:display":
			_factory_visual_revision += 1
			break
	for change: Dictionary in pending.changes.operations:
		if change.op == "extension.set" and str(change.id).begins_with("generation:"):
			_generation_plan_revision += 1
			break
	if not pending.changes.entities.is_empty():_clear_entity_spatial_index()
	var regions_changed:bool=pending.changes.operations.any(func(c:Dictionary)->bool:return c.op=="region.put")
	if regions_changed:_region_points.clear()
	if not pending.changes.chunks.is_empty() or regions_changed:
		_region_readiness=pending.readiness if pending.readiness is Dictionary else {}
		_resident_prisms.clear()
	for extension_id:String in pending.get("extension_ids",{}):_extension_epochs[extension_id]=int(_extension_epochs.get(extension_id,0))+1
	var result: Dictionary = {"ok": true, "code": "OK", "reason": null, "revision": get_revision()}
	if include_summary: result.changes = pending.changes.duplicate(true)
	return result
