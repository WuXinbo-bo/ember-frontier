extends SceneTree
## Analytic CPU binding of actual T0 pixels to the frozen PCK terrain arrays.
## No viewport, rendering, scene mounting, physics or user storage writes.
const Store = preload("res://scripts/storage/native_store.gd")
const State = preload("res://scripts/world/world_state.gd")
const View = preload("res://scripts/world/world_view.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
var checks: Array = []
var details: Dictionary = {}
var camera_origin: Vector3
var camera_basis: Basis
var viewport := Vector2(1280, 800)
var camera_size := 24.0

func _initialize() -> void: call_deferred("run")
func point(a: Array) -> Vector3: return Vector3(float(a[0]), float(a[1]), float(a[2]))
func vec(p: Vector3) -> Array: return [p.x, p.y, p.z]
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"label": label, "ok": ok, "detail": detail})
	if not ok: push_error("FAIL " + label + " " + str(detail))
func project(p: Vector3) -> Array:
	var local: Vector3 = camera_basis.inverse() * (p - camera_origin)
	return [(local.x / (camera_size * viewport.x / viewport.y) + 0.5) * viewport.x, (0.5 - local.y / camera_size) * viewport.y, -local.z]
func ray(pixel: Array) -> Dictionary:
	var origin := camera_origin + camera_basis.x * ((float(pixel[0]) / viewport.x - 0.5) * camera_size * viewport.x / viewport.y) + camera_basis.y * ((0.5 - float(pixel[1]) / viewport.y) * camera_size)
	var direction := -camera_basis.z
	var a: Vector3 = origin + direction * ((19.999 - origin.y) / direction.y)
	var b: Vector3 = origin + direction * ((-3.999 - origin.y) / direction.y)
	return {"pixel": pixel, "origin": a, "end": b, "direction": direction}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3: push_error("expected output, exact slot and T0-frame JSON paths"); quit(2); return
	var raw := FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary = Store.decode(raw)
	check("same exact saved input decodes in actual PCK", decoded.ok and raw.sha256_text() == "52eba1792d1145a6f3de30cc3a8abfe6170f9e524e463191541772793d70690d")
	if not decoded.ok: finish(args[0]); return
	var frame: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var baseline: Dictionary = frame.state
	camera_origin = point(baseline.camera.position_xyz)
	camera_basis = Basis.from_euler(point(baseline.camera.rotation_xyz))
	viewport = Vector2(float(baseline.viewport[0]), float(baseline.viewport[1])); camera_size = float(baseline.camera.size)
	check("exact controlled T0 identity and orthographic camera", baseline.world.worldId == "rural:v3:12" and baseline.world_revision == 6 and baseline.clock == decoded.capture.facts.time and baseline.camera.projection == 1 and viewport == Vector2(1280, 800))
	var original: Dictionary = decoded.capture.world
	var loaded: Dictionary = original.duplicate(true)
	# Reproduce D's explicitly qualified derived residency view, never commit
	# these loading flags to the input save or a live WorldState.
	for key: String in loaded.chunks:
		loaded.chunks[key].resident = true; loaded.chunks[key].revision = 6
	loaded.revision = 6
	var world := View.new(loaded)
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	var keys: Array = loaded.chunks.keys(); keys.sort()
	for key: String in keys: hash.update(key.to_utf8_buffer()); hash.update(PackedInt32Array(loaded.chunks[key].cells).to_byte_array())
	var cells_sha: String = hash.finish().hex_encode()
	check("analytic view cells match D qualified assembled cells SHA", cells_sha == "ebddaacaf1c6ea18977a3c7f2ab4e8e92c6b0d43fb30a54b99ebfa9ca2cdb329")
	var rays: Array = []
	for pixel: Array in [[503,329],[520,299],[375,294],[740,18],[778,67],[826,376],[995,431],[270,521],[926,399],[700,340],[640,420]]: rays.append(ray(pixel))
	var batches: Dictionary = {}
	var triangles := 0; var degenerate := 0; var wrong_winding := 0; var nonplanar := 0
	for key: String in keys:
		var coord: Vector3i = Data.coord(key)
		var box := AABB(Vector3(coord) * 8.0 - Vector3.ONE * 0.001, Vector3.ONE * 8.002)
		if not rays.any(func(r: Dictionary) -> bool: return box.intersects_segment(r.origin, r.end) != null): continue
		var batch: Dictionary = Mesher.build(world, key)
		if batch.groups.is_empty(): continue
		batches[key] = batch
		for group: Dictionary in batch.groups.values():
			for i in range(0, group.indices.size(), 3):
				var a: Vector3 = group.vertices[group.indices[i]]; var b: Vector3 = group.vertices[group.indices[i + 1]]; var c: Vector3 = group.vertices[group.indices[i + 2]]
				var cross := (b - a).cross(c - a); var n: Vector3 = group.normals[group.indices[i]]
				triangles += 1
				if cross.length_squared() <= 0.00000001: degenerate += 1
				elif cross.dot(n) >= 0.0: wrong_winding += 1
				if absf((b - a).dot(n)) > 0.000001 or absf((c - a).dot(n)) > 0.000001: nonplanar += 1
	check("all localized PCK triangles are nondegenerate planar clockwise to outward normals", degenerate == 0 and wrong_winding == 0 and nonplanar == 0, {"triangles": triangles, "degenerate": degenerate, "wrong_winding": wrong_winding, "nonplanar": nonplanar})
	var rows: Array = []
	for r: Dictionary in rays:
		var nearest: Dictionary = {}; var distance := INF
		for key: String in batches:
			for group_key: String in batches[key].groups:
				var group: Dictionary = batches[key].groups[group_key]
				for i in range(0, group.indices.size(), 3):
					var a: Vector3 = group.vertices[group.indices[i]]; var b: Vector3 = group.vertices[group.indices[i + 1]]; var c: Vector3 = group.vertices[group.indices[i + 2]]
					var normal: Vector3 = group.normals[group.indices[i]]
					if normal.dot(r.direction) >= 0.0: continue
					var intersection: Variant = Geometry3D.ray_intersects_triangle(r.origin, r.direction, a, b, c)
					if intersection == null: continue
					var at: Vector3 = intersection
					var length: float = (at - (r.origin as Vector3)).length()
					if length >= distance: continue
					distance = length
					var first: int = (int(i / 6)) * 4; var vertices: Array = []; var projected: Array = []
					for j in 4: vertices.append(vec(group.vertices[first + j])); projected.append(project(group.vertices[first + j]))
					nearest = {"chunk": key, "group": group_key, "surface_index": batches[key].groups.keys().find(group_key), "texture": group.texture, "material": group.material, "triangle_index": int(i / 3), "quad_index": int(i / 6), "intersection": vec(at), "outward_normal": vec(normal), "quad_vertices": vertices, "quad_projected_pixels_depth": projected, "triangle_indices": [group.indices[i], group.indices[i + 1], group.indices[i + 2]], "triangle_cross_dot_normal": (b-a).cross(c-a).dot(normal)}
		var semantic: Dictionary = Queries.raycast(world, r.origin, r.end)
		if semantic.has("normal") and semantic.normal is Vector3: semantic.normal = vec(semantic.normal)
		var match_geometry := false
		if not nearest.is_empty() and not semantic.get("unknown", true):
			match_geometry = absf(distance - float(semantic.distance)) < 0.0001
			var cell: Dictionary = semantic.cell; var grid := Vector3i(cell.x, cell.y, cell.z)
			var normal := Vector3i(point(nearest.outward_normal))
			nearest.solid_cell = cell; nearest.solid_material = world.cell_at(grid.x, grid.y, grid.z)
			nearest.outside_cell = {"x": grid.x+normal.x, "y": grid.y+normal.y, "z": grid.z+normal.z}
			nearest.outside_material = world.cell_at(grid.x+normal.x, grid.y+normal.y, grid.z+normal.z)
			if nearest.outward_normal[1] == 0:
				var halves: Array = []
				for triple: Array in [[0, 2, 1], [0, 3, 2]]:
					var center := (point(nearest.quad_vertices[triple[0]]) + point(nearest.quad_vertices[triple[1]]) + point(nearest.quad_vertices[triple[2]])) / 3.0
					var projected: Array = project(center)
					var center_ray: Dictionary = ray(projected)
					var occluder: Dictionary = Queries.raycast(world, center_ray.origin, center_ray.end)
					if occluder.has("normal") and occluder.normal is Vector3: occluder.normal = vec(occluder.normal)
					var target_distance: float = center.distance_to(center_ray.origin)
					halves.append({"quad_local_triangle": triple, "world_centroid": vec(center), "projected_pixel": projected, "target_distance": target_distance, "semantic_first_hit": occluder, "occluded_by_actual_terrain_before_this_quad": not occluder.get("unknown", true) and float(occluder.distance) < target_distance - 0.0001})
				nearest.quad_halves = halves
		rows.append({"pixel": r.pixel, "ray_origin": vec(r.origin), "direction": vec(r.direction), "nearest_front_terrain_triangle": nearest, "semantic_voxel_face": semantic, "semantic_and_mesh_distance_match": match_geometry})
	check("all selected rays with known terrain match actual raw mesh face distance", rows.all(func(row: Dictionary) -> bool: return row.semantic_voxel_face.get("unknown", false) or row.semantic_and_mesh_distance_match), rows.filter(func(row: Dictionary) -> bool: return not row.semantic_voxel_face.get("unknown", false) and not row.semantic_and_mesh_distance_match))
	check("read-only derived view does not alter decoded source cells or residency", original.revision == 5 and original.chunks.values().all(func(c: Dictionary) -> bool: return not c.resident))
	details = {"scope": "Analytic pixel rays against actual PCK pure mesher arrays and exact T0 camera. Main terrain only: ignores ecology/buildings/actors/alpha/shadows and does not identify a final rendered pixel if another visual lies in front. No rendered image or complete visual qualification.", "frame_image_sha256": frame.sha256, "cells_sha256": cells_sha, "source_revision": original.revision, "derived_revision": loaded.revision, "camera": baseline.camera, "player_foot_projected": project(point(baseline.player.position_xyz)), "localized_mesh_chunks": batches.keys(), "triangles": triangles, "native_cull_enums": {"back": BaseMaterial3D.CULL_BACK, "front": BaseMaterial3D.CULL_FRONT, "disabled": BaseMaterial3D.CULL_DISABLED}, "pixels": rows}
	finish(args[0])

func finish(path: String) -> void:
	var failed: int = checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failed": failed, "details": details}, "\t", true, true))
	print(JSON.stringify({"checks": checks.size(), "failed": failed})); quit(1 if failed else 0)
