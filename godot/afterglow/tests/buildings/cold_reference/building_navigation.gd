## Frozen 2026-11-14 pre-optimization test oracle; never a production service.
extends RefCounted
## Native AStar3D chooses candidates; every edge still proves project body/door/stair rules.
const Geometry = preload("res://tests/buildings/cold_reference/building_geometry.gd")
class FilteredGraph extends AStar3D:
	var owner_query: WeakRef
	func _filter_neighbor(from_id: int, to_id: int) -> bool:
		var query: RefCounted = owner_query.get_ref()
		return query == null or not query.edge(from_id, to_id).get("ok", false)

var space: RefCounted
var actor_id: String
var nodes: Array = []
var flights: Dictionary = {}
var edges: Dictionary = {}
var graph: AStar3D

func add(p: Dictionary) -> int:
	for i in nodes.size():
		if same(nodes[i], p): return i
	nodes.append(p.duplicate(true))
	return nodes.size() - 1

static func same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("regionId") == b.get("regionId") and a.get("buildingId") == b.get("buildingId") and a.get("storeyId") == b.get("storeyId") and Geometry.point(a).distance_to(Geometry.point(b)) < 0.025

func plan(model: RefCounted, actor: String, from: Dictionary, to: Dictionary) -> Dictionary:
	space = model
	actor_id = actor
	var start: Dictionary = space.standing_point(from)
	var finish: Dictionary = space.standing_point(to)
	if start.is_empty() or finish.is_empty() or not same(start, from) or from.regionId != to.regionId: return rejected("起点、终点或地区不合法")
	add(start)
	if add(finish) == 0: return {"ok": true, "steps": [], "visited": 0}
	var direct := straight(start,finish)
	if direct.ok: return {"ok":true,"steps":direct.steps,"visited":1}
	for v in space.pieces:
		if float(v.hp) <= 0 or v.regionId != from.regionId or v.get("buildingId") == null or v.get("buildingId") not in [from.get("buildingId"), to.get("buildingId")]: continue
		if v.has("door"):
			var points: Array = space.use_points(v)
			for sign in [-1, 1]:
				var p := Geometry.json_point(Geometry.transform(Vector3(0, 0, sign * (space.agent.radius + 0.3)), v))
				p.merge({"regionId": v.regionId, "buildingId": v.get("buildingId"), "storeyId": v.get("storeyId")})
				points.append(p)
			for p in points:
				var feet: Dictionary = space.standing_point(p)
				if not feet.is_empty(): add(feet)
		if v.has("stairs"):
			var d: Dictionary = space.geometry.definition(v).stairs
			var low := Geometry.json_point(Geometry.transform(Vector3(0, 0, -0.6), v))
			var high := Geometry.json_point(Geometry.transform(Vector3(0, d.rise, float(d.run) + 0.6), v))
			low.merge({"regionId": v.regionId, "buildingId": v.buildingId, "storeyId": v.stairs.fromStoreyId})
			high.merge({"regionId": v.regionId, "buildingId": v.buildingId, "storeyId": v.stairs.toStoreyId})
			var a: Dictionary = space.standing_point(low)
			var b: Dictionary = space.standing_point(high)
			if not a.is_empty() and not b.is_empty() and a.get("storeyId") == low.get("storeyId") and b.get("storeyId") == high.get("storeyId"):
				var ai := add(a)
				var bi := add(b)
				flights[str(ai) + ":" + str(bi)] = v
				flights[str(bi) + ":" + str(ai)] = v
			for sign in [-1, 1]:
				for side in [Vector2(0, -0.6), Vector2(d.rise, float(d.run) + 0.6)]:
					var p := Geometry.json_point(Geometry.transform(Vector3(sign * (float(d.width) / 2.0 + space.agent.radius + 0.1), side.x, side.y), v))
					p.merge({"regionId": v.regionId, "buildingId": v.buildingId, "storeyId": v.stairs.fromStoreyId if side.x == 0 else v.stairs.toStoreyId})
					var feet: Dictionary = space.standing_point(p)
					if not feet.is_empty(): add(feet)
		if nodes.size() > 128: return grid_plan(start, finish)
	graph = FilteredGraph.new()
	graph.owner_query = weakref(self)
	graph.neighbor_filter_enabled = true
	for i in nodes.size(): graph.add_point(i, Geometry.point(nodes[i]))
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if absf(float(nodes[i].y) - float(nodes[j].y)) <= space.agent.max_step or flights.has(str(i) + ":" + str(j)): graph.connect_points(i, j)
	var path := collect(graph.get_id_path(0, 1))
	return path if path.ok else grid_plan(start, finish)

func edge(a: int, b: int) -> Dictionary:
	var key := str(a) + ":" + str(b)
	if edges.has(key): return edges[key]
	var result: Dictionary
	if flights.has(key):
		var v: Dictionary = flights[key]
		result = {"ok": space.stair_clear(v), "steps": [{"kind": "stairs", "targetId": v.id, "from": nodes[a], "to": nodes[b]}]}
	else:
		result = straight(nodes[a], nodes[b])
	edges[key] = result
	return result

func straight(a: Dictionary, b: Dictionary) -> Dictionary:
	var length := Geometry.point(a).distance_to(Geometry.point(b))
	if absf(float(a.y) - float(b.y)) > space.agent.max_step or length > 64.0: return {"ok": false}
	var count := maxi(1, int(ceil(length / 8.0)))
	var current := a
	var steps: Array = []
	for n in range(1, count + 1):
		var p := a.duplicate(true)
		p.x = lerpf(a.x, b.x, float(n) / count)
		p.z = lerpf(a.z, b.z, float(n) / count)
		var target: Dictionary = b if n == count else space.standing_point(p)
		if target.is_empty(): return {"ok": false}
		var hit: Dictionary = space.blockers(current, target, actor_id, true)
		if not hit.ok: return {"ok": false}
		for id in hit.doors:
			var uses: Array = space.use_points(space.by_id[id])
			uses.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return Geometry.point(current).distance_to(Geometry.point(x)) < Geometry.point(current).distance_to(Geometry.point(y)))
			var approach: Dictionary = {}
			for u in uses:
				var feet: Dictionary = space.standing_point(u)
				if feet.is_empty(): continue
				var walk: Dictionary = space.walk(actor_id, current, feet)
				if walk.ok and same(walk.location, feet):
					approach = feet
					break
			if approach.is_empty(): return {"ok": false}
			steps.append({"kind": "move", "to": approach})
			steps.append({"kind": "open-door", "targetId": id, "at": approach})
		var walk: Dictionary = space.walk(actor_id, current, target, true)
		if not walk.ok or not same(walk.location, target): return {"ok": false}
		steps.append({"kind": "move", "to": target})
		current = target
	return {"ok": true, "steps": steps}

func collect(ids: PackedInt64Array) -> Dictionary:
	if ids.is_empty(): return rejected("墙、门锁、地形或楼梯使目标不可达")
	var steps: Array = []
	for i in range(1, ids.size()):
		var segment := edge(ids[i - 1], ids[i])
		if not segment.ok: return rejected("通路安全检查失败")
		steps.append_array(segment.steps)
	return {"ok": true, "steps": steps, "visited": edges.size(), "agent": space.agent.duplicate(true)}

func grid_plan(start: Dictionary, finish: Dictionary) -> Dictionary:
	# Bounded .5m fallback uses the same exact space and builtin AStar; no second solver.
	var old_nodes := nodes.duplicate(true)
	var old_flights := flights.duplicate(true)
	nodes = [start, finish]
	flights = {}
	edges = {}
	graph = FilteredGraph.new()
	graph.owner_query = weakref(self)
	graph.neighbor_filter_enabled = true
	graph.add_point(0, Geometry.point(start))
	graph.add_point(1, Geometry.point(finish))
	var low := Geometry.point(start).min(Geometry.point(finish)) - Vector3(8, 0, 8)
	var high := Geometry.point(start).max(Geometry.point(finish)) + Vector3(8, 0, 8)
	for v in space.pieces:
		if v.get("buildingId") in [start.get("buildingId"), finish.get("buildingId")] and v.get("buildingId") != null:
			var b: AABB = space.geometry.bounds(v)
			low = low.min(b.position - Vector3(2, 0, 2))
			high = high.max(b.end + Vector3(2, 0, 2))
	var levels: Array = [float(start.y), float(finish.y)]
	for storey in space.state.get("storeys", []):
		if storey.get("buildingId") in [start.get("buildingId"), finish.get("buildingId")] and not levels.has(float(storey.elevation)): levels.append(float(storey.elevation))
	if (high.x - low.x) * (high.z - low.z) * 4.0 * levels.size() > 20000: return rejected("通路搜索达到预算，请分区重规划")
	var grid: Dictionary = {}
	for y in levels:
		for x in range(int(floor(low.x * 2)), int(ceil(high.x * 2)) + 1):
			for z in range(int(floor(low.z * 2)), int(ceil(high.z * 2)) + 1):
				var p: Dictionary = space.body_location({"regionId": start.regionId, "x": x / 2.0, "y": y, "z": z / 2.0})
				if p.is_empty() or absf(float(p.y) - y) > 0.025 or not space.blockers(p,p,actor_id).ok: continue
				var id := nodes.size()
				nodes.append(p)
				graph.add_point(id, Geometry.point(p))
				grid[str([x, z, y])] = id
	for k in grid:
		var id: int = grid[k]
		var p: Dictionary = nodes[id]
		for delta in [Vector2i(1, 0), Vector2i(0, 1)]:
			var key := str([int(round(float(p.x) * 2)) + delta.x, int(round(float(p.z) * 2)) + delta.y, float(p.y)])
			if grid.has(key): graph.connect_points(id, grid[key])
		for endpoint in [0, 1]:
			if Geometry.point(p).distance_to(Geometry.point(nodes[endpoint])) <= 0.8: graph.connect_points(id, endpoint)
	# Keep the sparse door/use/stair links when local obstacles require a grid
	# detour. A half-metre cell centred in a closed leaf is not a valid standing
	# node, and discarding the portal links made that grid permanently disconnected.
	var remap:Dictionary={}
	for index in old_nodes.size():
		var at:Dictionary=old_nodes[index]
		var id:=add(at);remap[index]=id
		if not graph.has_point(id):graph.add_point(id,Geometry.point(at))
		for dx in range(-2,3):
			for dz in range(-2,3):
				var key:=str([roundi(float(at.x)*2)+dx,roundi(float(at.z)*2)+dz,float(at.y)])
				if not grid.has(key):continue
				var neighbor:int=grid[key]
				if neighbor!=id and Geometry.point(nodes[neighbor]).distance_to(Geometry.point(at))<=0.8:graph.connect_points(id,neighbor)
	for key in old_flights:
		var endpoints:PackedStringArray=key.split(":")
		flights[str(remap[int(endpoints[0])])+":"+str(remap[int(endpoints[1])])]=old_flights[key]
	for i in old_nodes.size():
		for j in range(i+1,old_nodes.size()):
			var a:int=remap[i];var b:int=remap[j]
			if a!=b and (absf(float(old_nodes[i].y)-float(old_nodes[j].y))<=space.agent.max_step or flights.has(str(a)+":"+str(b))):graph.connect_points(a,b)
	return collect(graph.get_id_path(0, 1))

static func rejected(reason: String) -> Dictionary:
	return {"ok": false, "code": "UNREACHABLE", "reason": reason, "steps": []}
