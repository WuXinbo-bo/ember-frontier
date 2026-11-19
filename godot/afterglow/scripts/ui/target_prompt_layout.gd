extends RefCounted
## Screen-space layout only. No selection, reach, world or input authority.

static func point(value: Variant) -> Variant:
	if not value is Dictionary: return null
	for key: String in ["x", "y"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])): return null
	return Vector2(float(value.x), float(value.y)) if value.get("visible", true) else null

static func target_clearance(anchor: Vector2, scale_factor: float) -> Rect2:
	return Rect2(anchor - Vector2(88, 80) * scale_factor, Vector2(176, 144) * scale_factor)

static func place(view: Vector2, extent: Vector2, anchor: Variant, player: Vector2, obstacles: Array, scale_factor: float, bottom_edge: float = -1.0) -> Vector2:
	var gap := 12.0
	var reserved_bottom := view.y - 24 - 96 * scale_factor
	var bottom := maxf(gap, minf(view.y, bottom_edge if bottom_edge > 0.0 else reserved_bottom) - gap - extent.y)
	var last_x := maxf(gap, view.x - extent.x - gap)
	var preferred := Vector2((view.x - extent.x) * 0.5, bottom)
	var candidates: Array[Vector2] = []
	var blocked: Array = obstacles.duplicate()
	blocked.append(Rect2(player - Vector2(48, 80) * scale_factor, Vector2(96, 120) * scale_factor))
	if anchor is Vector2:
		var clear := target_clearance(anchor, scale_factor)
		blocked.append(clear)
		candidates.append(Vector2(clear.end.x + gap, anchor.y - extent.y * 0.5))
		candidates.append(Vector2(clear.position.x - gap - extent.x, anchor.y - extent.y * 0.5))
		candidates.append(Vector2(anchor.x - extent.x * 0.5, clear.end.y + gap))
		candidates.append(Vector2(anchor.x - extent.x * 0.5, clear.position.y - gap - extent.y))
	for x: float in [preferred.x, last_x, gap]:
		candidates.append(Vector2(x, bottom))
		candidates.append(Vector2(x, gap))
	# Candidate lanes next to occupied panels preserve a visible gap even when
	# both corners are occupied or a zoomed sidebar crosses a preferred lane.
	for obstacle: Rect2 in blocked:
		for x: float in [obstacle.position.x - extent.x - gap, obstacle.end.x + gap]:
			candidates.append(Vector2(x, preferred.y))
			if anchor is Vector2: candidates.append(Vector2(x, anchor.y - extent.y * 0.5))
		for y: float in [obstacle.position.y - extent.y - gap, obstacle.end.y + gap]:
			candidates.append(Vector2(preferred.x, y))
			if anchor is Vector2: candidates.append(Vector2(anchor.x - extent.x * 0.5, y))
	var best := preferred
	var best_score := INF
	for candidate: Vector2 in candidates:
		var at := Vector2(clampf(candidate.x, gap, last_x), clampf(candidate.y, gap, bottom))
		var rect := Rect2(at, extent)
		var overlap := 0.0
		for avoid: Rect2 in blocked: overlap += rect.intersection(avoid).get_area()
		# Keep a short spatial association only after protecting the playfield.
		var score: float = overlap * 100000.0 + at.distance_squared_to(candidates[0])
		if score < best_score: best = at; best_score = score
	return best.round()
