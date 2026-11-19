extends RefCounted
## Explicit new-world-only finite grade model. Saved cells remain authoritative.
## Uses existing FastNoiseLite, half-metre voxels and pad constraints; no plugin,
## runtime cache, second terrain state or edits to already generated chunks.
const MODEL := "broad-terraces-v5"
const PITCH := 2.0
const BASE_PITCH := 32.0
const GRADE := 0.25
const GRID_SIDE := 35

static func rect(pad: Dictionary) -> Array:
	var r: Array = pad.xz
	return [floorf(float(r[0]) / PITCH) * PITCH, floorf(float(r[1]) / PITCH) * PITCH,
		ceilf(float(r[2]) / PITCH) * PITCH, ceilf(float(r[3]) / PITCH) * PITCH]

static func distance(x: float, z: float, r: Array) -> float:
	return maxf(maxf(float(r[0]) - x, x - float(r[2])), maxf(maxf(float(r[1]) - z, z - float(r[3])), 0.0))

static func fit_pads(parcels: Array) -> void:
	# Same finite relaxation used by v3/v4, now on the actual broad tile collars
	# and Chebyshev metric. Every pad retains its family/ports/footprint and half
	# metre elevation; only a NEW plan chooses compatible broad-tread heights.
	var heights: Array = parcels.map(func(p: Dictionary) -> float: return float(p.pad.height))
	for iteration in parcels.size():
		var next := heights.duplicate()
		for i in parcels.size():
			var a: Array = rect(parcels[i].pad)
			for j in parcels.size():
				var b: Array = rect(parcels[j].pad)
				var gap := maxf(maxf(maxf(float(a[0]) - float(b[2]), float(b[0]) - float(a[2])), 0.0), maxf(maxf(float(a[1]) - float(b[3]), float(b[1]) - float(a[3])), 0.0))
				next[i] = minf(float(next[i]), float(heights[j]) + floorf(gap * GRADE * 2.0) * 0.5)
		if next == heights: break
		heights = next
	for i in parcels.size():
		var p: Dictionary = parcels[i]
		var delta := float(heights[i]) - float(p.pad.height)
		p.origin.y += delta; p.pad.height = heights[i]
		for port: Dictionary in p.entrance_ports: port.position.y += delta
		for reserve: Dictionary in p.use_reservations: reserve.bounds.min.y += delta; reserve.bounds.max.y += delta
		for anchor: Dictionary in p.npc_anchors: anchor.position.y += delta

static func _base(noise: FastNoiseLite, x: float, z: float) -> float:
	# Coherent native noise at shared absolute 32m controls. Bounded knot range
	# gives each partial slope <= 0.125m/m; no hashed single-cell perturbation.
	var gx := floorf(x / BASE_PITCH) * BASE_PITCH
	var gz := floorf(z / BASE_PITCH) * BASE_PITCH
	var fx := (x - gx) / BASE_PITCH; var fz := (z - gz) / BASE_PITCH
	var a := clampf(1.5 + noise.get_noise_2d(gx, gz) * 3.5, -0.5, 3.5)
	var b := clampf(1.5 + noise.get_noise_2d(gx + BASE_PITCH, gz) * 3.5, -0.5, 3.5)
	var c := clampf(1.5 + noise.get_noise_2d(gx, gz + BASE_PITCH) * 3.5, -0.5, 3.5)
	var d := clampf(1.5 + noise.get_noise_2d(gx + BASE_PITCH, gz + BASE_PITCH) * 3.5, -0.5, 3.5)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

static func prepare(plan: Dictionary, noise: FastNoiseLite, landforms: Array) -> void:
	var controls: Array = []
	for pad: Dictionary in plan.grade_controls: controls.append({"xz": rect(pad), "height": float(pad.height)})
	var ox := int(plan.region_coord.x) * 64; var oz := int(plan.region_coord.z) * 64
	var cells: Array = []
	for z in GRID_SIDE:
		for x in GRID_SIDE:
			var wx := ox + (x - 1 + 0.5) * PITCH; var wz := oz + (z - 1 + 0.5) * PITCH
			var h := _base(noise, wx, wz)
			# Existing fields/bunds/ditch become broad landform planes, not new
			# content. Stable absolute neighbour order makes either border owner
			# see the same nearby controls. Far cones contain the entire grade.
			for land: Dictionary in landforms:
				var reach := distance(wx, wz, land.xz) * GRADE
				h = clampf(h, float(land.height) - reach, float(land.height) + reach)
			var lower := -INF; var upper := INF
			for pad: Dictionary in controls:
				var reach := distance(wx, wz, pad.xz) * GRADE
				lower = maxf(lower, float(pad.height) - reach); upper = minf(upper, float(pad.height) + reach)
			if not controls.is_empty(): h = clampf(h, lower, upper)
			# Use one translation-invariant tie direction across sea level. Godot's
			# round(-0.5)=-1 / round(+0.5)=+1 would turn a legal -0.25→+0.25
			# pair into a full-metre step at two adjacent broad controls.
			cells.append(floori(h * 2.0 + 0.5))
	plan.height.broad_surface = {"version": 1, "pitch": PITCH, "side": GRID_SIDE,
		"origin_cell": [ox / 2 - 1, oz / 2 - 1], "height_half_metres": cells,
		"semantics": "immutable new-plan grade samples only; after first commit gameplay reads authoritative voxel cells"}

static func height(plan: Dictionary, x: float, z: float) -> float:
	var grid: Dictionary = plan.height.broad_surface
	var ix := floori(x / PITCH) - int(grid.origin_cell[0]); var iz := floori(z / PITCH) - int(grid.origin_cell[1])
	assert(ix >= 0 and iz >= 0 and ix < GRID_SIDE and iz < GRID_SIDE, "v5 planning sample outside finite prepared collar")
	return float(grid.height_half_metres[ix + GRID_SIDE * iz]) * 0.5
