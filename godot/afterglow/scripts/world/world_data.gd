extends RefCounted
## Source schema/cell order retained. No scene, clock, inventory or file access.
const ChunkPage=preload("res://scripts/world/chunk_page.gd")
const GENERATORS = ["r3-town-1", "r3-town-2", "r3-town-3", "r3-town-4", "r3-town-5", "rural-1", "rural-2", "rural-3", "factory-country-1"]
const DEFAULT_CONFIG = {"cellSize":0.5,"chunkCells":16,"minCellY":-8,"maxCellY":40,"maxEditCells":256,"maxReach":2.5}
const MAX_SAFE_INTEGER: int = 9007199254740991
const MATERIALS = {
	0:{"key":"air","solid":false,"diggable":false},
	1:{"key":"grass","solid":true,"diggable":true,"item":"soil_m3","tool":"","top":"grass_top","side":"soil_side"},
	2:{"key":"soil","solid":true,"diggable":true,"item":"soil_m3","tool":"","top":"soil_side","side":"soil_side"},
	3:{"key":"stone","solid":true,"diggable":true,"item":"stone_m3","tool":"pickaxe","top":"stone","side":"stone"},
	4:{"key":"road","solid":true,"diggable":true,"item":"gravel_m3","tool":"pickaxe","top":"dirt_road","side":"soil_side"},
	5:{"key":"bedrock","solid":true,"diggable":false,"item":"","tool":"","top":"stone","side":"stone"},
	6:{"key":"gravel","solid":true,"diggable":true,"item":"gravel_m3","tool":"shovel","top":"gravel","side":"gravel"}}

static func is_continuous_outdoor_generator(version:String)->bool:
	# Authored old-city/rural-1 portals retain their original meaning. New
	# countryside partitions share real bodies/cells, never teleport gates.
	return version in ["rural-2","rural-3","factory-country-1"]

static func material_capabilities(material: int) -> Dictionary:
	# Existing 0..6 are air and opaque, load-bearing terrain. No fluid or
	# transparent-solid material is implied by adding query purposes. Keep the
	# tool QUALITY string in MATERIALS distinct from physical tool obstruction.
	var known := MATERIALS.has(material)
	var blocked := not known or bool(MATERIALS[material].solid)
	return {"known":known,"body":blocked,"sight":blocked,"contact":blocked,"support":blocked,"selection":blocked}

static func material_blocks(material: int, purpose: String) -> bool:
	# All physical purposes share the same solidity rule. A ray only needs
	# this scalar result, so avoid allocating the full capabilities DTO per cell.
	match purpose:
		"body", "sight", "contact", "support", "selection":
			return not MATERIALS.has(material) or bool(MATERIALS[material].solid)
		"known":
			return MATERIALS.has(material)
		_:
			return true

static func reject(code: String, reason: String = "") -> Dictionary:
	return {"ok":false,"code":code,"reason":reason if reason else code}

static func integer(v: Variant) -> bool:
	# Keep the interoperable JSON/legacy limit as an integer literal. The engine
	# decimal-float literal parser rounds 9007199254740991.0 down on our binary;
	# conversion from this exact integer preserves the intended boundary.
	if v is int: return v >= -MAX_SAFE_INTEGER and v <= MAX_SAFE_INTEGER
	return v is float and is_finite(v) and v == floor(v) and abs(v) <= float(MAX_SAFE_INTEGER)

# Process metadata for a pure immutable string predicate only. Full keys avoid
# hash-only identity claims. Never cache entity/stock/permission/transaction facts.
const _VALID_ID_LIMIT:int=2048
static var _valid_id_cache:Dictionary={}
static var _valid_id_mutex:Mutex=Mutex.new()

static func valid_id(v: Variant) -> bool:
	# Bound hashing work as well as retained memory, including hostile long input.
	if not v is String or v.is_empty() or v.length()>240:return false
	_valid_id_mutex.lock()
	var known:bool=_valid_id_cache.has(v)
	_valid_id_mutex.unlock()
	if known:return true
	if v in ["__proto__","constructor","prototype"]: return false
	for c in v:
		if c.unicode_at(0) < 32: return false
	_valid_id_mutex.lock()
	if _valid_id_cache.size()>=_VALID_ID_LIMIT:_valid_id_cache.clear()
	_valid_id_cache[v]=true
	_valid_id_mutex.unlock()
	return true

static func vec(v: Variant) -> bool:
	return v is Dictionary and v.has_all(["x","y","z"]) and [v.x,v.y,v.z].all(func(x: Variant) -> bool: return (x is int or x is float) and is_finite(float(x)))

static func bounds(b: Variant) -> bool:
	return b is Dictionary and vec(b.get("min")) and vec(b.get("max")) and b.min.x < b.max.x and b.min.y < b.max.y and b.min.z < b.max.z

static func contains(b: Dictionary, p: Dictionary) -> bool:
	return p.x >= b.min.x and p.x < b.max.x and p.y >= b.min.y and p.y < b.max.y and p.z >= b.min.z and p.z < b.max.z

static func intersects(a: Dictionary, b: Dictionary) -> bool:
	return a.min.x < b.max.x and a.max.x > b.min.x and a.min.y < b.max.y and a.max.y > b.min.y and a.min.z < b.max.z and a.max.z > b.min.z

static func json_value(v: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if v == null or v is String or v is StringName or v is bool or v is int: return true
	if v is float: return is_finite(v)
	if v is Array:
		for x in v:
			if not json_value(x,depth+1): return false
		return true
	if v is Dictionary:
		for k in v:
			if not (k is String or k is StringName) or not json_value(v[k],depth+1): return false
		return true
	return false

static func json_equal(a: Variant, b: Variant) -> bool:
	# JSON has numbers and strings, not GDScript int-vs-float or StringName keys.
	if (a is int or a is float) and (b is int or b is float): return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k) or not json_equal(a[k],b[k]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not json_equal(a[i],b[i]): return false
		return true
	return a == b

static func config_error(c: Variant) -> String:
	if not c is Dictionary or not c.has_all(DEFAULT_CONFIG.keys()): return "INVALID_CONFIG"
	if not c.cellSize in [0.5,1.0] or not integer(c.chunkCells): return "INVALID_CONFIG"
	var n := int(c.chunkCells)
	if n < 4 or n > 64 or (n & (n-1)) != 0: return "INVALID_CONFIG"
	if not integer(c.minCellY) or not integer(c.maxCellY) or c.minCellY >= c.maxCellY or c.maxCellY-c.minCellY > 256: return "INVALID_CONFIG"
	if not integer(c.maxEditCells) or c.maxEditCells < 1 or c.maxEditCells > 4096 or not (c.maxReach is float or c.maxReach is int) or not is_finite(c.maxReach) or c.maxReach <= 0: return "INVALID_CONFIG"
	return ""

static func coord(key: String) -> Variant:
	var parts := key.split(",")
	if parts.size() != 3: return null
	var c := Vector3i.ZERO
	for d in 3:
		if not parts[d].is_valid_int(): return null
		var v := int(parts[d])
		if str(v) != parts[d] or abs(v) > 2147483647: return null
		c[d] = v
	return c

static func key(c: Vector3i) -> String:
	return "%d,%d,%d" % [c.x,c.y,c.z]

static func cell_chunk(c: Vector3i, n: int) -> Vector3i:
	return Vector3i(floori(float(c.x)/n),floori(float(c.y)/n),floori(float(c.z)/n))

static func local_index(c: Vector3i, n: int) -> int:
	return posmod(c.x,n)+n*(posmod(c.z,n)+n*posmod(c.y,n))

static func affected(c: Vector3i, n: int) -> Array:
	var q := cell_chunk(c,n)
	var out := [key(q)]
	for d in 3:
		var a := q
		if posmod(c[d],n) == 0:
			a[d] -= 1
			out.append(key(a))
		if posmod(c[d],n) == n-1:
			a = q
			a[d] += 1
			out.append(key(a))
	return out

static func chunk_error(k: String, c: Variant, w: Dictionary, check_cells: bool = true) -> String:
	var p: Variant = coord(k)
	if p == null or not c is Dictionary or c.get("key") != k or not vec(c.get("coord")): return "INVALID_CHUNK"
	if c.coord.x != p.x or c.coord.y != p.y or c.coord.z != p.z or c.get("generatorVersion") != w.generatorVersion: return "INVALID_CHUNK"
	if not integer(c.get("revision")) or c.revision < 0 or c.revision > w.revision or not c.get("resident") is bool or not c.get("generated") is bool: return "INVALID_CHUNK"
	var cells: Variant = c.get("cells")
	if not (cells is PackedInt32Array or cells is Array):return "INVALID_CHUNK"
	if c.has("cell_page"):
		# Exactly ONE authority representation. A cold page is never considered
		# resident/air, and cannot coexist with a second full cell array.
		if c.resident or not c.generated or not cells.is_empty():return "INVALID_CHUNK_PAGE"
		var checked:Dictionary=ChunkPage.unpack(c.cell_page,int(w.config.chunkCells)**3,MATERIALS) if check_cells else ChunkPage.header(c.cell_page,int(w.config.chunkCells)**3)
		if not checked.ok:return str(checked.code)
		var page_metadata:Dictionary=c.duplicate(false);page_metadata.erase("cells")
		return "" if json_value(page_metadata) else "INVALID_JSON_FACT"
	if cells.size() != int(w.config.chunkCells)**3:return "INVALID_CHUNK"
	if check_cells:
		var metadata: Dictionary = c.duplicate(false)
		metadata.erase("cells")
		if not json_value(metadata): return "INVALID_JSON_FACT"
		if cells is PackedInt32Array:
			# Packed cells are already exactly typed integers. Use the engine's
			# native exact counts for EACH catalog ID, including future gaps.
			# No range assumption, unchecked cache, or skipped replacement proof.
			var allowed := 0
			for material in MATERIALS:
				allowed += cells.count(material)
				# Homogeneous and two-material chunks can prove completeness early.
				if allowed == cells.size():
					break
			if allowed!=cells.size():return "UNKNOWN_MATERIAL"
		else:
			# Legacy JSON arrays still need strict scalar/integer validation.
			for m in cells:
				if not integer(m) or not MATERIALS.has(int(m)): return "UNKNOWN_MATERIAL"
	return ""

static func entity_error(id: String, e: Variant, w: Dictionary) -> String:
	# The same complete record schema serves full-load and incremental replace
	# validation. Entity records have no graph edges other than their region;
	# replacing one cannot invalidate an unchanged entity/chunk/receipt.
	if not e is Dictionary or e.get("id") != id or not vec(e.get("position")) or not bounds(e.get("bounds")) or not w.regions.has(e.get("regionId")) or not integer(e.get("revision")) or e.revision < 0 or e.revision > w.revision: return "INVALID_ENTITY"
	return ""

static func region_error(id: String, region: Variant) -> String:
	if not region is Dictionary or region.get("id") != id or not bounds(region.get("bounds")) or not region.get("exits") is Array or not region.get("editAreas") is Array or not region.get("generated") is bool:
		return "INVALID_REGION"
	return ""

static func chunk_capacity_exceeded(world: Dictionary) -> bool:
	var count: int = world.chunks.size()
	return count > 8192 or count * int(world.config.chunkCells) ** 3 > 67108864

static func validate(w: Variant, check_cells: bool = true, check_json: bool = true) -> Dictionary:
	if not w is Dictionary or w.get("schemaVersion") != 1 or not valid_id(w.get("worldId")) or not integer(w.get("seed")) or not integer(w.get("revision")) or w.revision < 0: return reject("INVALID_WORLD")
	if not w.get("generatorVersion") in GENERATORS: return reject("UNSUPPORTED_GENERATOR")
	var err := config_error(w.get("config"))
	if err: return reject(err)
	for name in ["regions","chunks","entities","extensions","receipts"]:
		if not w.get(name) is Dictionary: return reject("INVALID_WORLD",name)
		for id in w[name]:
			if not valid_id(id): return reject("INVALID_ID",str(id))
	if chunk_capacity_exceeded(w): return reject("SAVE_TOO_LARGE")
	var retired: Variant = w.get("retiredEntityIds")
	if not retired is Array: return reject("INVALID_ID")
	var seen := {}
	for id in retired:
		if not valid_id(id) or seen.has(id) or w.entities.has(id): return reject("RETIRED_ENTITY_ID")
		seen[id] = true
	for id in w.regions:
		err = region_error(id, w.regions[id])
		if err: return reject(err, id)
	for id in w.entities:
		var e: Variant = w.entities[id]
		err = entity_error(id,e,w)
		if err: return reject(err,id)
	for k in w.chunks:
		err = chunk_error(k,w.chunks[k],w,check_cells)
		if err: return reject(err,k)
	for id in w.receipts:
		var r: Variant = w.receipts[id]
		if not r is Dictionary or not r.get("fingerprint") is String or not r.get("result") is Dictionary or not r.result.get("ok") is bool: return reject("INVALID_RECEIPT",id)
		if r.result.ok:
			if not r.result.get("changes") is Dictionary or r.result.changes.get("commandId") != id or not integer(r.result.get("revision")) or r.result.revision < 1 or r.result.revision > w.revision or r.result.changes.get("revision") != r.result.revision: return reject("INVALID_RECEIPT",id)
		elif not r.result.get("reasonCode") is String or not r.result.get("reason") is String or not r.result.get("retryable") is bool: return reject("INVALID_RECEIPT",id)
	if check_json:
		var headers: Dictionary = w.duplicate(false)
		headers.erase("chunks")
		if not json_value(headers): return reject("INVALID_JSON_FACT","world metadata")
	return {"ok":true,"code":"OK","reason":null}
