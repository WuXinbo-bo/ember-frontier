extends RefCounted
## Finite authored grammar on the SAME C world. Initial ruins use normal editable pieces.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
var service: RefCounted
var world: RefCounted
var instances: Array = []
var storeys: Array = []
var stocks: Array = []
var records: Array = []
var tools: Array = []
var changes: Array = []
var entrances: Dictionary = {}
var sequence := 0

func generate(building: RefCounted, view: RefCounted) -> Dictionary:
	service = building; world = view
	if view.identity().generatorVersion != "rural-1" or view.has_extension("r3:structures"): return service.failure("ALREADY_SEEDED", "只允许为未注册建筑的新农村世界装配一次")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/rural_layout.json"))
	var home: Dictionary = layout.home
	house(home.id, "RH-HOME", home.footprint_xz, home.doors, home.windows, true)
	for other in layout.other_buildings:
		var door := {"id_suffix": "front-door", "wall_center": other.entry, "quarter_turn": other.door_quarter_turn}
		house(other.id, "RH-HOME" if other.id.contains("RH-HOME") else "RH-VILLAGE", other.footprint_xz, [door], [], false)
	var home_id: String = home.id
	for object in home.objects:
		if object.id_suffix == "workbench-reservation": continue
		var p := at(object.position, "RH-HOME", home_id)
		if object.has("definition_id"):
			piece(object.definition_id, home_id + ":" + object.id_suffix, p)
		else:
			var size := Vector3(1.35, 1.01, 2.1) if object.asset_id == "city_bed" else Vector3(0.4, 0.6, 0.4)
			prop(home_id + ":" + object.id_suffix, object.asset_id, p, size, {"sleeping": object.asset_id == "city_bed", "prepared": false})
	stock(home_id + ":storage", at([22.5, 0, 27.5], "RH-HOME", home_id), {"food": 2, "water": 3, "cloth": 2, "timber": 2, "scrap": 1}, "home-residents", true, home_id + ":storage")
	var shed := "rural:v1:RH-HOME:shed"
	piece("cabinet", shed + ":storage", at([8, 0, 17], "RH-HOME", shed))
	stock(shed + ":storage", at([8, 0, 16], "RH-HOME", shed), {"timber": 8, "scrap": 6, "book_woodwork": 1, "book_tool_repair": 1}, "home-residents", false, shed + ":storage")
	for kind in ["salvaged_axe", "hand_saw", "hammer"]: tools.append({"id": shed + ":" + kind, "kind": kind, "holderId": shed + ":storage", "durability": 85.0 if kind == "salvaged_axe" else 100.0})
	records.append({"id": shed + ":record:woodwork", "holderId": shed + ":storage", "itemId": "book_woodwork", "grants": ["basic_woodwork"], "seconds": 12.0})
	records.append({"id": shed + ":record:repair", "holderId": shed + ":storage", "itemId": "book_tool_repair", "grants": ["basic_tool_repair"], "seconds": 12.0})
	var shop := "rural:v1:RH-VILLAGE:store"
	for n in range(3):
		var id := shop + ":shelf:" + str(n)
		piece("cabinet", id, at([14 + n * 2, 0, -21], "RH-VILLAGE", shop), 2)
		stock(id, at([14 + n * 2, 0, -20], "RH-VILLAGE", shop), {"food": 2, "water": 2, "scrap": 1}, null, false, id)
	piece("domestic_table", shop + ":counter", at([14, 0, -16], "RH-VILLAGE", shop))
	var repair := "rural:v1:RH-VILLAGE:repair-shop"
	piece("workbench", repair + ":bench", at([49, 0, -40], "RH-VILLAGE", repair), 2, "repair-resident")
	piece("cabinet", repair + ":tools", at([52, 0, -34], "RH-VILLAGE", repair), 1, "repair-resident")
	stock(repair + ":tools", at([51, 0, -34], "RH-VILLAGE", repair), {"axe_head": 1, "tool_handle": 1, "scrap": 4}, "repair-resident", false, repair + ":tools")
	var neighbor := "rural:v1:RH-VILLAGE:neighbor-home"
	prop(neighbor + ":bed", "city_bed", at([12, 0, -50], "RH-VILLAGE", neighbor), Vector3(1.35, 1.01, 2.1), {"sleeping": true, "prepared": false})
	piece("domestic_table", neighbor + ":table", at([12, 0, -44], "RH-VILLAGE", neighbor), 0, "village-resident")
	# The gate is a real damaged door. No free workbench/farm/radio at home.
	var gate := piece("door", home_id + ":yard-gate", at([28, 0, 40], "RH-HOME"), 1)
	gate.hp = 60
	# Every standing tree gets a real empty ground-drop stock; no direct-to-pack yield.
	for e in view.entities():
		if e.kind != "tree" or not e.get("data", {}).has("harvest"): continue
		var p := Geometry.location(e); p.z += 0.8
		var id := str(e.data.outputId)
		var existing: Dictionary = view.entity(id)
		if existing.is_empty(): prop(id, "ground_drop", p, Vector3(0.5, 0.15, 0.5), {"dropped": true}, "container", false)
		else: p = Geometry.location(existing)
		stock(id, p, {}, null, true)
	var data := {"schemaVersion": 1, "catalogVersion": 1, "instances": instances, "storeys": storeys}
	changes.append(service.extension_change("r3:structures", data, view))
	for instance in instances: put(service.geometry.entity(instance))
	for region_id in entrances:
		var prior: Variant = view.extension("generation:" + region_id)
		var generation: Dictionary = prior if prior is Dictionary else {}
		generation.slots = generation.get("slots", []) + entrances[region_id]
		changes.append(service.extension_change("generation:" + region_id, generation, view))
	return {"ok": true, "code": "OK", "reason": null, "world_changes": changes, "fact_changes": [], "initial_stocks": stocks,
		"initial_records": records, "initial_tools": tools, "spawn_points": {"player": at([30, 0, 43], "RH-HOME"), "village-resident": at([16, 0, -46], "RH-VILLAGE", neighbor), "repair-resident": at([46, 0, -36], "RH-VILLAGE", repair)},
		"initial_quantities": "R3.3 finite test parameters; sole runtime owns stock/register, never reseed existing save"}

func at(values: Array, region: String, building_id: Variant = null) -> Dictionary:
	return {"x": values[0], "y": values[1], "z": values[2], "regionId": region, "buildingId": building_id, "storeyId": null if building_id == null else str(building_id) + ":ground"}

func piece(definition: String, id: String, p: Dictionary, rotation: int = 0, owner: Variant = "home-residents") -> Dictionary:
	var v: Dictionary = service.make_instance(definition, id, p, rotation, owner)
	instances.append(v)
	return v

func stock(id: String, p: Dictionary, items: Dictionary, owner: Variant, searched: bool, parent: String = "") -> void:
	stocks.append({"id": id, "location": p.duplicate(true), "items": items, "owner": owner, "searched": searched, "structureId": parent})

func put(entity: Dictionary) -> void:
	changes.append({"op": "entity.put", "id": entity.id, "before_exists": false, "before": null, "after": entity})

func prop(id: String, asset: String, p: Dictionary, size: Vector3, data: Dictionary, kind: String = "prop", solid: bool = true) -> void:
	var details := data.duplicate(true)
	details.merge({"assetId": asset, "solid": solid, "opaque": solid}, true)
	var e := {"id": id, "kind": kind, "regionId": p.regionId, "position": Geometry.json_point(Geometry.point(p)), "bounds": Geometry.json_box(AABB(Geometry.point(p) - Vector3(size.x / 2, 0, size.z / 2), size)), "revision": 0, "blocksTerrain": solid, "supportBounds": [], "data": details}
	if p.buildingId != null: e.buildingId = p.buildingId; e.storeyId = p.storeyId
	put(e)

func house(id: String, region: String, rect: Array, doors: Array, windows: Array, interior: bool) -> void:
	storeys.append({"id": id + ":ground", "buildingId": id, "regionId": region, "index": 0, "elevation": 0.0})
	for x in range(int(rect[0]) + 1, int(rect[2]), 2):
		for z in range(int(rect[1]) + 1, int(rect[3]), 2):
			piece("foundation", id + ":base:" + str(x) + ":" + str(z), at([x, 0, z], region, id))
			piece("roof", id + ":roof:" + str(x) + ":" + str(z), at([x, 3.4, z], region, id))
	# 20cm real foundation rim supports the full wall thickness, not imaginary terrain.
	for z in range(int(rect[1]) + 1, int(rect[3]), 2):
		for x in [float(rect[0]) - 0.1, float(rect[2]) + 0.1]: piece("foundation_rim", id + ":rim:" + str(x) + ":" + str(z), at([x, 0, z], region))
	for x in range(int(rect[0]) + 1, int(rect[2]), 2):
		for z in [float(rect[1]) - 0.1, float(rect[3]) + 0.1]: piece("foundation_rim", id + ":rim:" + str(x) + ":" + str(z), at([x, 0, z], region), 1)
	var sockets: Array = []
	for x in range(int(rect[0]) + 1, int(rect[2]), 2):
		for z in [rect[1], rect[3]]: sockets.append({"center": [x, 0, z], "rotation": 0})
	for z in range(int(rect[1]) + 1, int(rect[3]), 2):
		for x in [rect[0], rect[2]]: sockets.append({"center": [x, 0, z], "rotation": 1})
	if interior:
		for z in range(27, 38, 2): sockets.append({"center": [16, 0, z], "rotation": 1})
		for x in range(9, 16, 2): sockets.append({"center": [x, 0, 32], "rotation": 0})
	for socket in sockets:
		var definition := "wall"
		var suffix := "wall:" + str(sequence); sequence += 1
		for door in doors:
			if Geometry.point(Geometry.json_point(Vector3(door.wall_center[0], door.wall_center[1], door.wall_center[2]))).distance_to(Vector3(socket.center[0], 0, socket.center[2])) < 0.05:
				definition = "door"; suffix = door.id_suffix
		for window in windows:
			if Vector3(window.center[0], 0, window.center[2]).distance_to(Vector3(socket.center[0], 0, socket.center[2])) < 0.05: definition = "window"
		piece(definition, id + ":" + suffix, at(socket.center, region, id), socket.rotation, "home-residents" if region == "RH-HOME" else null)
	for door in doors:
		var p: Dictionary = at(door.wall_center, region)
		if absf(float(p.x) - float(rect[0])) < 0.05: p.x -= 1.2
		elif absf(float(p.x) - float(rect[2])) < 0.05: p.x += 1.2
		elif absf(float(p.z) - float(rect[1])) < 0.05: p.z -= 1.2
		elif absf(float(p.z) - float(rect[3])) < 0.05: p.z += 1.2
		else: continue
		if not entrances.has(region): entrances[region] = []
		entrances[region].append({"id": id + ":entrance:" + door.id_suffix, "kind": "entrance", "buildingId": id, "position": Geometry.json_point(Geometry.point(p)), "x": p.x, "y": p.y, "z": p.z, "regionId": region})
