extends RefCounted
## Derived space for one complete world/draft. No persistent actors, inventory or clock.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Navigation = preload("res://tests/buildings/pre_template_reference/building_navigation.gd")
var geometry: RefCounted
var world: RefCounted
var state: Dictionary
var permission: Callable
var pieces: Array = []
var by_id: Dictionary = {}
var solid_entities: Array = []
var surfaces: Array = []
var colliders: Array = []
var buckets: Dictionary = {}
var piece_buckets: Dictionary = {}
var surface_buckets: Dictionary = {}
var walk_surfaces: Dictionary = {}
var piece_bounds: Dictionary = {}
var sight_boxes: Dictionary = {}
var entity_buckets: Dictionary = {}
var cell_cache: Dictionary = {}
var terrain_cache: Dictionary = {}
var voxel_clear_cache: Dictionary = {}
var support_cache: Dictionary = {}
var support_roots: Dictionary = {}
var support_neighbors_cache: Dictionary = {}
var support_wall_index: Dictionary = {}
var support_slab_index: Dictionary = {}
var surface_support_neighbors: Dictionary = {}
var support_witnesses: Dictionary = {}
var support_points: Dictionary = {}
var cell_size := 0.5
var chunk_cells := 16
var min_cell_y := -8
var max_cell_y := 40
var chunk_cache: Dictionary = {}
var ground_cache: Dictionary = {}
var body_cache: Dictionary = {}
var stair_cache: Dictionary = {}
var blocker_cache: Dictionary = {}
var walk_cache: Dictionary = {}
var agent := {"radius": 0.26, "height": 1.8, "max_step": 0.55, "max_move_distance": 1.0}

func configure(view: RefCounted, structures: Dictionary, geo: RefCounted, can_open: Callable) -> void:
	world = view
	state = structures.duplicate(true)
	geometry = geo
	permission = can_open
	var config: Dictionary = world.config()
	cell_size = float(config.get("cellSize",0.5))
	chunk_cells=int(config.get("chunkCells",16));min_cell_y=int(config.get("minCellY",-8));max_cell_y=int(config.get("maxCellY",40))
	pieces = state.get("instances", [])
	var collider_tokens:Dictionary={}
	var ordinal:=0
	for v in pieces:
		ordinal+=1
		by_id[v.id] = v
		if float(v.get("hp", 0)) <= 0: continue
		for index:Dictionary in [piece_buckets,surface_buckets,buckets]:
			if not index.has(v.regionId):index[v.regionId]={}
		var footprint: AABB = geometry.bounds(v)
		var kind:String=geometry.definition(v).kind
		var support_index:Dictionary=support_wall_index if kind in ["wall","corner","door","window"] else support_slab_index
		var support_entry:Dictionary={}
		var support_y:=0
		if kind in ["wall","corner","door","window","floor","roof"]:
			if not support_index.has(v.regionId):support_index[v.regionId]={}
			support_y=floori((footprint.end.y if kind in ["wall","corner","door","window"] else float(v.position.y))/2.0)
			support_entry={"piece":v,"bounds":footprint,"ordinal":ordinal}
		var walk_surface:Dictionary={}
		if geometry.definition(v).get("surfaceY")!=null and geometry.definition(v).kind!="roof":
			walk_surface={"piece":v,"bounds":footprint,"elevation":float(v.position.y)}
			if not walk_surfaces.has(v.regionId):walk_surfaces[v.regionId]={}
		piece_bounds[v.id] = footprint
		sight_boxes[v.id] = geometry.boxes(v,"sight")
		for x in range(int(floor(footprint.position.x / 2.0)), int(floor(footprint.end.x / 2.0)) + 1):
			for z in range(int(floor(footprint.position.z / 2.0)), int(floor(footprint.end.z / 2.0)) + 1):
				var key := Vector2i(x,z)
				if not support_entry.is_empty():
					var support_key:=Vector3i(x,support_y,z)
					if not support_index[v.regionId].has(support_key):support_index[v.regionId][support_key]=[]
					support_index[v.regionId][support_key].append(support_entry)
				if not piece_buckets[v.regionId].has(key): piece_buckets[v.regionId][key] = []
				piece_buckets[v.regionId][key].append(v)
				if geometry.definition(v).get("surfaceY") != null:
					if not surface_buckets[v.regionId].has(key): surface_buckets[v.regionId][key] = []
					surface_buckets[v.regionId][key].append(v)
				if not walk_surface.is_empty():
					var cell:=Vector2i(x,z)
					if not walk_surfaces[v.regionId].has(cell):walk_surfaces[v.regionId][cell]=[]
					walk_surfaces[v.regionId][cell].append(walk_surface)
		for b in geometry.boxes(v):
			# Allocate one exact geometric identity when projecting the query.
			# Every body sample previously formatted id+AABB strings repeatedly.
			var shape_key:Array=[v.id,b]
			if not collider_tokens.has(shape_key):collider_tokens[shape_key]=collider_tokens.size()
			var entry: Dictionary = {"instance": v, "bounds": b,"token":collider_tokens[shape_key]}
			colliders.append(entry)
			for x in range(int(floor(b.position.x / 2.0)), int(floor(b.end.x / 2.0)) + 1):
				for z in range(int(floor(b.position.z / 2.0)), int(floor(b.end.z / 2.0)) + 1):
					var k := Vector2i(x,z)
					if not buckets[v.regionId].has(k): buckets[v.regionId][k] = []
					buckets[v.regionId][k].append(entry)
		if geometry.definition(v).get("surfaceY") != null: surfaces.append(v)
	if world.has_method("entities"):
		for e in world.entities():
			if e.get("kind") != "structure" and e.get("data", {}).get("solid", false):
				solid_entities.append(e)
				if not entity_buckets.has(e.regionId):entity_buckets[e.regionId]={}
				var b:=Geometry.aabb(e.bounds)
				for x in range(floori(b.position.x/2),floori(b.end.x/2)+1):
					for z in range(floori(b.position.z/2),floori(b.end.z/2)+1):
						var key:=Vector2i(x,z)
						if not entity_buckets[e.regionId].has(key):entity_buckets[e.regionId][key]=[]
						entity_buckets[e.regionId][key].append(e)

func candidates(region: String, a: Vector3, b: Vector3, radius: float) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var index:Dictionary=buckets.get(region,{})
	for x in range(int(floor((minf(a.x, b.x) - radius) / 2.0)), int(floor((maxf(a.x, b.x) + radius) / 2.0)) + 1):
		for z in range(int(floor((minf(a.z, b.z) - radius) / 2.0)), int(floor((maxf(a.z, b.z) + radius) / 2.0)) + 1):
			for entry in index.get(Vector2i(x,z), []):
				var k:int = entry.token
				if not seen.has(k):
					seen[k] = true
					result.append(entry)
	return result

func nearby_pieces(region: String, volume: AABB, only_surfaces: bool = false) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var index:Dictionary = (surface_buckets if only_surfaces else piece_buckets).get(region,{})
	for x in range(int(floor(volume.position.x / 2.0)), int(floor(volume.end.x / 2.0)) + 1):
		for z in range(int(floor(volume.position.z / 2.0)), int(floor(volume.end.z / 2.0)) + 1):
			for v in index.get(Vector2i(x,z), []):
				if not seen.has(v.id): seen[v.id] = true; result.append(v)
	return result

func bounds(v: Dictionary) -> AABB:
	return piece_bounds[v.id] if piece_bounds.has(v.id) else geometry.bounds(v)

func support_neighbors(v: Dictionary) -> Dictionary:
	# Immutable geometry projection only. Do not memoize recursive support truth:
	# its ancestry/cycle/three-slab limit remains a fresh safety predicate.
	if support_neighbors_cache.has(v.id):return support_neighbors_cache[v.id]
	var result: Dictionary={"wall":[],"slab":[]}
	var b: AABB=bounds(v)
	for entry:Dictionary in support_candidates(support_wall_index,str(v.regionId),b.grow(2.01),float(v.position.y)-0.2):
		var other:Dictionary=entry.piece;var ob:AABB=entry.bounds
		if other.id!=v.id and absf(ob.end.y-(float(v.position.y)-0.2))<Geometry.EPS and ob.position.x<=b.end.x and ob.end.x>=b.position.x and ob.position.z<=b.end.z and ob.end.z>=b.position.z:result.wall.append(other)
	for entry:Dictionary in support_candidates(support_slab_index,str(v.regionId),b.grow(2.01),float(v.position.y)):
		var other:Dictionary=entry.piece
		if other.id!=v.id and absf(float(other.position.y)-float(v.position.y))<Geometry.EPS and absf(float(other.position.x)-float(v.position.x))+absf(float(other.position.z)-float(v.position.z))<=2.01:result.slab.append(other)
	support_neighbors_cache[v.id]=result
	return result

func support_candidates(all_regions:Dictionary,region:String,volume:AABB,y:float)->Array:
	# Broad phase only: include both bins across every EPS boundary. Exact
	# height/overlap predicates still decide support, in the old bucket order.
	var index:Dictionary=all_regions.get(region,{})
	var result:Array=[];var seen:Dictionary={}
	var low:=floori((y-Geometry.EPS)/2.0);var high:=floori((y+Geometry.EPS)/2.0)
	for x in range(floori(volume.position.x/2),floori(volume.end.x/2)+1):
		for z in range(floori(volume.position.z/2),floori(volume.end.z/2)+1):
			var entries:Array=[]
			for level in range(low,high+1):entries.append_array(index.get(Vector3i(x,level,z),[]))
			if low!=high:entries.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.ordinal)<int(b.ordinal))
			for entry:Dictionary in entries:
				if not seen.has(entry.piece.id):seen[entry.piece.id]=true;result.append(entry)
	return result

func support_at(region:String,p:Vector3)->Array:
	# The same exact sample is shared by adjacent walls/floors. Store ordered
	# geometric candidates only, never recursive support or ancestor decisions.
	var key:Array=[region,p]
	if support_points.has(key):return support_points[key]
	var result:Array=[]
	for piece:Dictionary in nearby_pieces(region,AABB(p,Vector3.ZERO),true):
		if piece.regionId!=region or absf(float(piece.position.y)-p.y)>=Geometry.EPS:continue
		var b:AABB=bounds(piece)
		if p.x>=b.position.x-0.005 and p.x<=b.end.x+0.005 and p.z>=b.position.z-0.005 and p.z<=b.end.z+0.005:result.append(piece)
	support_points[key]=result
	return result

func cell_material(cell: Vector3i) -> int:
	if not cell_cache.has(cell):
		if cell_cache.size() >= 65536: cell_cache.clear()
		if cell.y<min_cell_y or cell.y>=max_cell_y:return -1
		var coord:=Vector3i(floori(float(cell.x)/chunk_cells),floori(float(cell.y)/chunk_cells),floori(float(cell.z)/chunk_cells))
		if not chunk_cache.has(coord):chunk_cache[coord]=world.chunk("%d,%d,%d"%[coord.x,coord.y,coord.z])
		var chunk:Dictionary=chunk_cache[coord]
		cell_cache[cell] = int(chunk.cells[posmod(cell.x,chunk_cells)+chunk_cells*(posmod(cell.z,chunk_cells)+chunk_cells*posmod(cell.y,chunk_cells))]) if chunk.get("generated",false) else -1
	return cell_cache[cell]

func ground_height(x:float,z:float)->Variant:
	var cx:=floori(x/cell_size);var cz:=floori(z/cell_size)
	for y in range(max_cell_y-1,min_cell_y-1,-1):
		var m:=cell_material(Vector3i(cx,y,cz))
		if m<0:return null
		if m>0:return (y+1)*cell_size
	return null

func terrain_clear(region: String, volume: AABB, exclude_id: String = "") -> bool:
	var key: Array = [region,volume,exclude_id]
	if terrain_cache.has(key): return terrain_cache[key]
	var result:=terrain_clear_uncached(region,volume,exclude_id)
	if terrain_cache.size()>=32768:terrain_cache.clear()
	terrain_cache[key]=result
	return result

func terrain_clear_uncached(region: String, volume: AABB, exclude_id: String) -> bool:
	var lo := Vector3i(floor((volume.position.x + 0.00001) / cell_size), floor((volume.position.y + 0.00001) / cell_size), floor((volume.position.z + 0.00001) / cell_size))
	var hi := Vector3i(ceil((volume.end.x - 0.00001) / cell_size), ceil((volume.end.y - 0.00001) / cell_size), ceil((volume.end.z - 0.00001) / cell_size))
	if (hi.x - lo.x) * (hi.y - lo.y) * (hi.z - lo.z) > 65536: return false
	# Continuous foot/body boxes often touch exactly the same voxel interval.
	# Only the voxel proof is shared: solid-entity overlap remains continuous,
	# per volume and per excluded entity. A new immutable query invalidates it.
	var voxel_key:Array=[lo,hi]
	if not voxel_clear_cache.has(voxel_key):
		if voxel_clear_cache.size()>=32768:voxel_clear_cache.clear()
		voxel_clear_cache[voxel_key]=voxel_span_clear(lo,hi)
	if not voxel_clear_cache[voxel_key]:return false
	var entities:Dictionary=entity_buckets.get(region,{})
	for x in range(floori(volume.position.x/2),floori(volume.end.x/2)+1):
		for z in range(floori(volume.position.z/2),floori(volume.end.z/2)+1):
			for e in entities.get(Vector2i(x,z),[]):
				if e.id != exclude_id and Geometry.overlap(Geometry.aabb(e.bounds), volume):return false
	return true

func voxel_span_clear(lo:Vector3i,hi:Vector3i)->bool:
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			for z in range(lo.z, hi.z):
				if cell_material(Vector3i(x,y,z)) != 0: return false
	return true

func terrain_supports(region: String, footprint: AABB) -> bool:
	var key: Array=[region,footprint]
	if support_cache.has(key):return support_cache[key]
	var result:=terrain_supports_uncached(footprint)
	support_cache[key]=result
	return result

func terrain_supports_uncached(footprint: AABB) -> bool:
	# Exact cell coverage of the same inset rectangle, no repeated sub-cell probes.
	var inset_x := minf(0.01,footprint.size.x/2.0)
	var inset_z := minf(0.01,footprint.size.z/2.0)
	var y := floori((footprint.position.y-0.01)/cell_size)
	for x in range(floori((footprint.position.x+inset_x)/cell_size),floori((footprint.end.x-inset_x)/cell_size)+1):
		for z in range(floori((footprint.position.z+inset_z)/cell_size),floori((footprint.end.z-inset_z)/cell_size)+1):
			if cell_material(Vector3i(x,y,z)) <= 0: return false
	return true

func point_location(region: String, x: float, z: float, reference_y: float) -> Dictionary:
	var support:=floor_sample(region,x,z,reference_y)
	if support.is_empty():return {}
	var v:Dictionary=support.piece
	return {"regionId":region,"x":x,"y":float(support.elevation),"z":z,"buildingId":v.get("buildingId"),"storeyId":v.get("storeyId")}

func floor_sample(region:String,x:float,z:float,reference_y:float)->Dictionary:
	# A point touches exactly one existing 2m bucket. Reuse its ordered floor
	# projection instead of allocating/deduplicating candidates and re-reading
	# definitions for each of the nine precise foot samples on every walk step.
	# Height, footprint, 1mm tolerance and exact terrain clearance stay identical.
	for surface:Dictionary in walk_surfaces.get(region,{}).get(Vector2i(floori(x/2),floori(z/2)),[]):
		if absf(float(surface.elevation) - reference_y) > agent.max_step: continue
		var v:Dictionary=surface.piece
		var b: AABB = surface.bounds
		if x >= b.position.x - 0.001 and x <= b.end.x + 0.001 and z >= b.position.z - 0.001 and z <= b.end.z + 0.001:
			if terrain_clear(region, AABB(Vector3(x - 0.01, v.position.y + 0.01, z - 0.01), Vector3(0.02, 0.01, 0.02))):
				return surface
	var k: Array = [region,floori(x/cell_size),floori(z/cell_size)]
	if not ground_cache.has(k): ground_cache[k] = ground_height(x, z)
	var ground: Variant = ground_cache[k]
	if ground == null or absf(float(ground) - reference_y) > agent.max_step: return {}
	return {"elevation":float(ground),"piece":{}}

func body_location(p: Dictionary, radius: float = 0.26) -> Dictionary:
	var k: Array = [p.regionId, p.x, p.y, p.z, radius]
	if body_cache.has(k): return body_cache[k].duplicate(true)
	var y := -INF
	for dx in [-radius, 0.0, radius]:
		for dz in [-radius, 0.0, radius]:
			# These nine probes only need elevation. Allocate a full location once
			# at the centre below, not a discarded seven-field record per probe.
			var feet := floor_sample(str(p.regionId), float(p.x) + dx, float(p.z) + dz, float(p.y))
			if feet.is_empty(): return {}
			y = maxf(y, float(feet.elevation))
	if absf(y - float(p.y)) > agent.max_step: return {}
	var result := point_location(str(p.regionId), p.x, p.z, y)
	if not result.is_empty(): result.y = y
	if body_cache.size() >= 16384: body_cache.clear()
	body_cache[k] = result.duplicate(true)
	return result

func blockers(a: Dictionary, b: Dictionary, actor_id: String, allow_doors: bool = false, exclude_id: String = "") -> Dictionary:
	var key: Array = [a.regionId,Geometry.point(a),Geometry.point(b),allow_doors,exclude_id]
	if not blocker_cache.has(key):
		if blocker_cache.size()>=16384:blocker_cache.clear()
		blocker_cache[key]=geometry_blockers(a,b,allow_doors,exclude_id)
	var result:Dictionary=blocker_cache[key]
	if not result.ok:return result
	for id in result.doors:
		var v:Dictionary=by_id[id]
		if permission.call(actor_id,id,"open",v)!=null:return {"ok":false,"doors":[],"permission_denied":true}
	return result

func geometry_blockers(a: Dictionary, b: Dictionary, allow_doors: bool, exclude_id: String) -> Dictionary:
	var av := Geometry.point(a)
	var bv := Geometry.point(b)
	var doors: Array = []
	for entry in candidates(str(a.regionId), av, bv, agent.radius):
		var v: Dictionary = entry.instance
		var bounds: AABB = entry.bounds
		if v.id == exclude_id or bounds.end.y <= minf(av.y, bv.y) + 0.04 or bounds.position.y >= maxf(av.y, bv.y) + agent.height: continue
		if geometry.definition(v).get("surfaceY") != null and bounds.end.y <= maxf(av.y, bv.y) + 0.04: continue
		var expanded := AABB(bounds.position - Vector3(agent.radius, agent.height - 0.05, agent.radius), bounds.size + Vector3(agent.radius * 2.0, agent.height - 0.05, agent.radius * 2.0))
		if expanded.intersects_segment(av + Vector3(0, 0.05, 0), bv + Vector3(0, 0.05, 0)) == null: continue
		var door: Dictionary = v.get("door", {})
		if allow_doors and not door.is_empty() and not door.get("open", false) and not door.get("locked", false) and not door.get("blocked", false) and bounds.is_equal_approx(geometry.leaf(v)):
			if not doors.has(v.id): doors.append(v.id)
			continue
		return {"ok": false, "doors": []}
	var samples := maxi(1, int(ceil(av.distance_to(bv) / 0.25)))
	for i in range(samples + 1):
		var p := av.lerp(bv, float(i) / samples)
		p.y = maxf(av.y, bv.y)
		if not terrain_clear(str(a.regionId), AABB(p + Vector3(-agent.radius, 0.04, -agent.radius), Vector3(agent.radius * 2.0, agent.height - 0.04, agent.radius * 2.0))): return {"ok": false, "doors": []}
	return {"ok": true, "doors": doors}

func stair_point(p: Dictionary) -> Dictionary:
	for v in nearby_pieces(str(p.regionId), AABB(Geometry.point(p) - Vector3.ONE, Vector3.ONE * 2.0)):
		if not v.has("stairs") or v.get("buildingId") != p.get("buildingId"): continue
		var d: Dictionary = geometry.definition(v).stairs
		if p.get("storeyId") not in [v.stairs.get("fromStoreyId"), v.stairs.get("toStoreyId")]: continue
		var local := Geometry.rotate(Geometry.point(p) - Geometry.point(v.position), -int(v.quarterTurn))
		if absf(local.x) > float(d.width) / 2.0 - agent.radius + 0.001 or local.z < -agent.radius or local.z > float(d.run) + agent.radius: continue
		var y := clampf(ceil((local.z + agent.radius) / (float(d.run) / 24.0)) * float(d.rise) / 24.0, 0, d.rise)
		if absf(local.y - y) > 0.025 or not stair_clear(v) or not blockers(p, p, "", false, v.id).ok: continue
		var result := p.duplicate(true)
		result.y = float(v.position.y) + y
		return result
	return {}

func standing_point(p: Dictionary) -> Dictionary:
	var stair := stair_point(p)
	if not stair.is_empty(): return stair
	var feet := body_location(p)
	return feet if not feet.is_empty() and blockers(feet, feet, "").ok else {}

func use_points(instance: Dictionary) -> Array:
	var result: Array = []
	for local in geometry.definition(instance).get("usePoints", []):
		var p := Geometry.json_point(Geometry.transform(Geometry.point(local), instance))
		p.merge({"regionId": instance.regionId, "buildingId": instance.get("buildingId"), "storeyId": instance.get("storeyId")})
		var resolved := point_location(str(p.regionId), p.x, p.z, p.y)
		if not resolved.is_empty(): p = resolved
		result.append(p)
	return result

func walk(actor_id: String, from: Dictionary, to: Dictionary, allow_doors: bool = false) -> Dictionary:
	var key: Array=[from.duplicate(true),to.duplicate(true),allow_doors]
	if walk_cache.has(key):
		var saved:Dictionary=walk_cache[key]
		for id in saved.get("doors",[]):
			if permission.call(actor_id,id,"open",by_id[id])!=null:return {"ok":false,"code":"FORBIDDEN","reason":"门权限已变化"}
		return saved.duplicate(true)
	var result:=walk_uncached(actor_id,from,to,allow_doors)
	# Permission failures never become geometry proofs.
	if not result.get("permission_denied",false):
		if walk_cache.size()>=8192:walk_cache.clear()
		walk_cache[key]=result.duplicate(true)
	return result

func walk_uncached(actor_id: String, from: Dictionary, to: Dictionary, allow_doors: bool) -> Dictionary:
	if from.regionId != to.regionId or Geometry.point(from).distance_to(Geometry.point(to)) > 16.0: return {"ok": false, "code": "UNREACHABLE", "reason": "通路过长或跨地区"}
	var current := from.duplicate(true)
	var crossed: Array=[]
	var count := maxi(1, int(ceil(Vector2(float(to.x) - float(from.x), float(to.z) - float(from.z)).length() / 0.2)))
	for i in range(1, count + 1):
		var p := current.duplicate(true)
		p.x = lerpf(from.x, to.x, float(i) / count)
		p.z = lerpf(from.z, to.z, float(i) / count)
		var feet := body_location(p)
		if feet.is_empty(): return {"ok": false, "code": "UNSUPPORTED", "reason": "脚下支撑或台阶高度不合法"}
		var obstruction:=blockers(current, feet, actor_id, allow_doors)
		if not obstruction.ok: return {"ok": false, "code": "BLOCKED", "reason": "身体通路被阻挡","permission_denied":obstruction.get("permission_denied",false)}
		for id in obstruction.doors:
			if not crossed.has(id):crossed.append(id)
		current = feet
	return {"ok": true, "location": current,"doors":crossed}

func line_clear(a: Dictionary, b: Dictionary, exclude: String = "") -> bool:
	var av := Geometry.point(a) + Vector3(0, 1.2, 0)
	var bv := Geometry.point(b) + Vector3(0, 1.2, 0)
	for v in nearby_pieces(str(a.regionId), AABB(av.min(bv), av.max(bv) - av.min(bv))):
		if v.id == exclude or v.regionId != a.regionId: continue
		for volume in sight_boxes.get(v.id, []):
			if volume.intersects_segment(av, bv) != null: return false
	var steps := maxi(1, int(ceil(av.distance_to(bv) / 0.15)))
	for i in range(steps + 1):
		var p := av.lerp(bv, float(i) / steps)
		if not terrain_clear(str(a.regionId), AABB(p - Vector3.ONE * 0.005, Vector3.ONE * 0.01), exclude): return false
	return true

func stair_clear(instance: Dictionary) -> bool:
	if stair_cache.has(instance.id): return stair_cache[instance.id]
	var d: Dictionary = geometry.definition(instance).get("stairs", {})
	if d.is_empty() or not instance.has("stairs"): return false
	var lower: Dictionary = {}; var upper: Dictionary = {}
	for s in state.get("storeys", []):
		if s.id == instance.stairs.get("fromStoreyId"): lower = s
		if s.id == instance.stairs.get("toStoreyId"): upper = s
	if upper.is_empty() or upper.buildingId != instance.buildingId or upper.regionId != instance.regionId or absf(float(upper.elevation) - float(instance.position.y) - float(d.rise)) > Geometry.EPS: return false
	if instance.stairs.get("fromStoreyId") != null and (lower.is_empty() or lower.buildingId != instance.buildingId or lower.regionId != instance.regionId or absf(float(lower.elevation) - float(instance.position.y)) > Geometry.EPS): return false
	for end in [Vector3(0,0,-0.6),Vector3(0,d.rise,float(d.run)+0.6)]:
		var at := Geometry.json_point(Geometry.transform(end,instance)); at.regionId = instance.regionId
		var feet := body_location(Geometry.location(at))
		if feet.is_empty() or absf(float(feet.y) - float(at.y)) > 0.025 or not blockers(feet,feet,"",false,instance.id).ok: return false
	for n in range(49):
		var p := Geometry.transform(Vector3(0, minf(float(d.rise), ceil((float(d.run) * n / 48.0 + agent.radius) / (float(d.run) / 24.0)) * float(d.rise) / 24.0), float(d.run) * n / 48.0), instance)
		var loc := Geometry.json_point(p)
		loc.regionId = instance.regionId
		if not blockers(loc, loc, "", false, instance.id).ok:
			stair_cache[instance.id] = false
			return false
	stair_cache[instance.id] = true
	return true

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

func route(actor_id: String, from: Dictionary, to: Dictionary) -> Dictionary:
	var navigator := Navigation.new()
	return navigator.plan(self, actor_id, from, to)
