extends SceneTree
## Read-only saved-scene diagnostic. Run against the frozen actual PCK.
## No Runtime, native scene, user:// storage, mounting or actor movement.
const Store = preload("res://scripts/storage/native_store.gd")
const State = preload("res://scripts/world/world_state.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Space = preload("res://scripts/buildings/building_space.gd")
var checks: Array = []
var details: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"label": label, "ok": ok, "detail": detail})
	if not ok: push_error("FAIL " + label + " " + str(detail))

func query(view: RefCounted) -> RefCounted:
	var geo := Geometry.new()
	geo.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
	var space := Space.new()
	space.configure(view, view.extension("r3:structures"), geo,
		func(_actor: String, _target: String, _action: String, _instance: Dictionary) -> Variant: return null)
	return space

func samples(view: RefCounted, space: RefCounted, p: Dictionary) -> Dictionary:
	var rows: Array = []
	for dx: float in [-0.26, 0.0, 0.26]:
		for dz: float in [-0.26, 0.0, 0.26]:
			var x: float = float(p.x) + dx
			var z: float = float(p.z) + dz
			rows.append({"dx": dx, "dz": dz, "x": x, "z": z,
				"cell_x": floori(x / 0.5), "cell_z": floori(z / 0.5),
				"c_surface": view.surface_height(x, z), "b_surface": space.ground_height(x, z),
				"floor_sample": space.floor_sample(str(p.regionId), x, z, float(p.y))})
	var position := Vector3(float(p.x), float(p.y), float(p.z))
	var foot := AABB(position + Vector3(-0.26, 0, -0.26), Vector3(0.52, 0.01, 0.52))
	return {"location": p, "samples": rows, "body_location": space.body_location(p),
		"standing_point": space.standing_point(p), "blockers": space.blockers(p, p, "player"),
		"terrain_supports_inset": space.terrain_supports(str(p.regionId), foot),
		"center_support_cell": view.cell_at(floori(float(p.x) / 0.5), floori((float(p.y) - 0.01) / 0.5), floori(float(p.z) / 0.5))}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3: push_error("expected output, saved-slot and original-rejection paths"); quit(2); return
	var raw: String = FileAccess.get_file_as_string(args[1])
	check("exact A read-only saved slot SHA", raw.sha256_text() == "52eba1792d1145a6f3de30cc3a8abfe6170f9e524e463191541772793d70690d")
	var decoded: Dictionary = Store.decode(raw)
	check("actual candidate PCK native decoder accepts saved scene", decoded.ok, decoded.get("code"))
	if not decoded.ok: finish(args[0]); return
	var capture: Dictionary = decoded.capture
	var saved: Dictionary = capture.world
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var player: Dictionary = capture.facts.actors.filter(func(a: Dictionary) -> bool: return a.id == "player")[0]
	var p: Dictionary = Geometry.location(player)
	var world := State.new()
	var loaded: Dictionary = world.load_snapshot(saved)
	check("saved scene remains rural3 seed12 world revision5", loaded.ok and saved.worldId == "rural:v3:12" and saved.seed == 12 and saved.revision == 5, world.identity())
	if not loaded.ok: finish(args[0]); return
	var logged: Dictionary = original.actors.filter(func(a: Dictionary) -> bool: return a.id == "player")[0].before
	check("saved player equals original rejection within JSON diagnostic rounding", absf(float(p.x) - float(logged.x)) < 0.000000001 and absf(float(p.y) - float(logged.y)) < 0.000000001 and absf(float(p.z) - float(logged.z)) < 0.000000001 and p.regionId == logged.regionId, {"saved": p, "logged": logged, "saved_time": capture.facts.time, "logged_time": original.get("time")})
	var before: Dictionary = samples(world, query(world), p)
	var cells: Array = []
	for x in range(79, 83):
		for z in range(111, 116):
			var column: Array = []
			for y in range(2, 9): column.append({"y": y, "material": world.cell_at(x, y, z), "known": world.is_cell_known(x, y, z)})
			cells.append({"x": x, "z": z, "surface": world.surface_height((x + 0.5) * 0.5, (z + 0.5) * 0.5), "column": column})
	check("C/B raw terrain height agrees at every actual foot probe", before.samples.all(func(s: Dictionary) -> bool: return s.c_surface == s.b_surface))
	check("all actual foot sample columns are generated known", before.samples.all(func(s: Dictionary) -> bool: return world.is_cell_known(s.cell_x, 5, s.cell_z)))
	check("logged terrain target still material4 in exact saved world", world.cell_at(80, 5, 112) == 4, world.cell_at(80, 5, 112))
	var draft: Dictionary = world.prepare_changes([{"op": "voxel.set", "cell": {"x": 80, "y": 5, "z": 112}, "before": 4, "after": 0}], world.get_revision())
	check("private exact voxel projection prepares without committing", draft.ok, draft.get("code"))
	var after: Dictionary = {}
	if draft.ok:
		after = samples(draft.view, query(draft.view), p)
		check("private voxel projection keeps all other neighboring cells exact", cells.all(func(row: Dictionary) -> bool: return row.column.all(func(c: Dictionary) -> bool: return (row.x == 80 and c.y == 5 and row.z == 112) or world.cell_at(row.x, c.y, row.z) == draft.view.cell_at(row.x, c.y, row.z))))
		world.discard_prepared(draft.capability)
	check("read-only probe and discarded projection preserve complete saved world", world.snapshot() == saved and world.get_revision() == 5)
	var edges: Array = []
	for dz: float in [-0.02, -0.01, 0.0, 0.01, 0.02]:
		var at := p.duplicate(true); at.z = float(p.z) + dz
		edges.append({"diagnostic_only_dz": dz, "result": samples(world, query(world), at)})
	details = {"scope": "Actual candidate10 PCK and exact read-only saved world rev5/player position. Save time is later than first rejection; no claim of identical runtime facts or replay of full production extension. Private voxel-only draft is not committed. Decoding intentionally marks chunks nonresident; no claim about live visual/physics readiness or OS/performance acceptance.",
		"world": world.identity(), "world_revision": world.get_revision(), "saved_command_revision": capture.command_revision,
		"saved_time": capture.facts.time, "logged_runtime_revision": original.get("runtime_revision"), "logged_time": original.get("time"),
		"before": before, "voxel_only_draft": after, "surrounding_cells": cells, "boundary_diagnostics": edges,
		"actors": capture.facts.actors.map(func(a: Dictionary) -> Dictionary: return {"id": a.id, "location": Geometry.location(a), "standing_point": query(world).standing_point(Geometry.location(a))})}
	finish(args[0])

func finish(path: String) -> void:
	var failed: int = checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failed": failed, "details": details}, "\t", true, true))
	print(JSON.stringify({"checks": checks.size(), "failed": failed})); quit(1 if failed else 0)
