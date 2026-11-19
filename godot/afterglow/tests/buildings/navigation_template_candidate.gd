extends "res://scripts/buildings/building_navigation.gd"
## Test-only candidate, inherited edge/walk/permission rules are unchanged.
func plan(model: RefCounted, actor: String, from: Dictionary, to: Dictionary) -> Dictionary:
	space = model
	actor_id = actor
	var start: Dictionary = space.standing_point(from)
	var finish: Dictionary = space.standing_point(to)
	if start.is_empty() or finish.is_empty() or not same(start, from): return rejected("起点或终点不合法")
	if from.regionId!=to.regionId:
		if not space.world.has_method("continuous_outdoor_segment"):return rejected("连续空间证明尚未就绪")
		var connected:Dictionary=space.world.continuous_outdoor_segment(start,finish,256.0,true)
		if not connected.ok:return connected
	add(start)
	if add(finish) == 0: return {"ok": true, "steps": [], "visited": 0}
	var direct := straight(start,finish)
	if direct.ok: return {"ok":true,"steps":direct.steps,"visited":1}
	var template_key:Array=[from.regionId,to.regionId,from.get("buildingId"),to.get("buildingId"),space.agent.duplicate(true)]
	var saved:Dictionary=space.route_templates.get(template_key,{})
	if not saved.is_empty():
		space.template_hits+=1
		for p:Dictionary in saved.points:add(p)
		for flight:Dictionary in saved.flights:
			var ai:=add(flight.from);var bi:=add(flight.to)
			flights[str(ai)+":"+str(bi)]=space.by_id[flight.id]
			flights[str(bi)+":"+str(ai)]=space.by_id[flight.id]
	else:
		var static_points:Array=[];var static_flights:Array=[]
		for v in space.pieces:
			if float(v.hp) <= 0 or v.regionId not in [from.regionId,to.regionId]:continue
			# Courtyard gates intentionally have no indoor building/storey ID. They
			# are still physical portals: without their real two-sided candidates a
			# valid outside road could never connect to its supported inside handle.
			# Candidate inclusion grants no access; straight()/edge() retain the same
			# body, leaf, terrain, stair and actual actor-permission proofs.
			var outdoor_door:bool=v.has("door") and v.get("buildingId")==null
			if not outdoor_door and (v.get("buildingId")==null or v.get("buildingId") not in [from.get("buildingId"),to.get("buildingId")]):continue
			if v.has("door"):
				var points: Array = space.use_points(v)
				for sign in [-1, 1]:
					var p := Geometry.json_point(Geometry.transform(Vector3(0, 0, sign * (space.agent.radius + 0.3)), v))
					p.merge({"regionId": v.regionId, "buildingId": v.get("buildingId"), "storeyId": v.get("storeyId")})
					points.append(p)
				for p in points:
					var feet: Dictionary = space.standing_point(p)
					if not feet.is_empty(): static_points.append(feet.duplicate(true));add(feet)
			if v.has("stairs"):
				var d: Dictionary = space.geometry.definition(v).stairs
				var low := Geometry.json_point(Geometry.transform(Vector3(0, 0, -0.6), v))
				var high := Geometry.json_point(Geometry.transform(Vector3(0, d.rise, float(d.run) + 0.6), v))
				low.merge({"regionId": v.regionId, "buildingId": v.buildingId, "storeyId": v.stairs.fromStoreyId})
				high.merge({"regionId": v.regionId, "buildingId": v.buildingId, "storeyId": v.stairs.toStoreyId})
				var a: Dictionary = space.standing_point(low)
				var b: Dictionary = space.standing_point(high)
				if not a.is_empty() and not b.is_empty() and a.get("storeyId") == low.get("storeyId") and b.get("storeyId") == high.get("storeyId"):
					static_points.append(a.duplicate(true));static_points.append(b.duplicate(true))
					static_flights.append({"id":v.id,"from":a.duplicate(true),"to":b.duplicate(true)})
					var ai := add(a)
					var bi := add(b)
					flights[str(ai) + ":" + str(bi)] = v
					flights[str(bi) + ":" + str(ai)] = v
				for sign in [-1, 1]:
					for side in [Vector2(0, -0.6), Vector2(d.rise, float(d.run) + 0.6)]:
						var p := Geometry.json_point(Geometry.transform(Vector3(sign * (float(d.width) / 2.0 + space.agent.radius + 0.1), side.x, side.y), v))
						p.merge({"regionId": v.regionId, "buildingId": v.buildingId, "storeyId": v.stairs.fromStoreyId if side.x == 0 else v.stairs.toStoreyId})
						var feet: Dictionary = space.standing_point(p)
						if not feet.is_empty(): static_points.append(feet.duplicate(true));add(feet)
			if nodes.size() > 128: return fallback_plan(start, finish)
		if static_points.size()+2<=128:
			if space.route_templates.size()>=32:space.route_templates.clear()
			space.route_templates[template_key]={"points":static_points,"flights":static_flights}

	graph = FilteredGraph.new()
	graph.owner_query=weakref(self)
	for i in nodes.size(): graph.add_point(i, Geometry.point(nodes[i]))
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if absf(float(nodes[i].y) - float(nodes[j].y)) <= space.agent.max_step or flights.has(str(i) + ":" + str(j)): graph.connect_points(i, j)
	var path := verified_path()
	return path if path.ok else fallback_plan(start, finish)

