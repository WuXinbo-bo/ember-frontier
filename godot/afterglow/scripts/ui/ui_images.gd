extends RefCounted
## Native resource cache. Source PNG fallback permits UI source development
## without taking over A's importer; packaged imports still use ResourceLoader.
static var _cache: Dictionary = {}
const MODULES := {
	"r34.module.warehouse":"warehouse",
	"r34.module.hand_workshop":"hand_workshop",
	"r34.module.home_service":"home_service",
	"r34.module.supply_rear_v3":"supply_rear_v3",
	"r34.module.fuel_woodshop":"fuel_woodshop",
	"r34.module.woodshop_long_v2":"woodshop_long_v2",
	"r34.module.warehouse_long_v2":"warehouse_long_v2",
	"r34.module.warehouse_court_v2":"warehouse_court_v2",
	"r34.module.repair_shed_v2":"repair_shed_v2",
	"r34.module.home_court_v2":"home_court_v2",
	"r34.module.home_roadside_v2":"home_roadside_v2",
	"r34.module.supply_roadside_v2":"supply_roadside_v2",
	"r34.module.woodshop_long_v3":"woodshop_long_v3",
	"r34.module.woodshop_yard_v3":"woodshop_yard_v3",
	"r34.module.home_court_v3":"home_court_v3",
	"r34.module.home_roadside_v3":"home_roadside_v3",
	"r34.module.warehouse_long_v3":"warehouse_long_v3",
	"r34.module.warehouse_court_v3":"warehouse_court_v3"
}
# Only these six source03 definitions have adopted geometry-v2 images.
# Existing definitions keep their original geometry-v1 identity and picture.
const MODULE_VERSIONS := {
	"r34.module.woodshop_long_v3":"r34.module.woodshop_long_v3.geometry-v2",
	"r34.module.woodshop_yard_v3":"r34.module.woodshop_yard_v3.geometry-v2",
	"r34.module.home_court_v3":"r34.module.home_court_v3.geometry-v2",
	"r34.module.home_roadside_v3":"r34.module.home_roadside_v3.geometry-v2",
	"r34.module.warehouse_long_v3":"r34.module.warehouse_long_v3.geometry-v2",
	"r34.module.warehouse_court_v3":"r34.module.warehouse_court_v3.geometry-v2"
}

# Exact final30 complete GPU03/04 adoption; prior source02 images remain untouched.
# Provenance: themes/modules/architecture-final-v1/adoption.json.
# Exact new9 A/GPU02 housing images; the original30 mapping stays below.
const HOUSING_MECHANISM_V2 := {
	"r34.module.home_small_porch_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_small_porch_v1", "geometry_version": "r34.module.home_small_porch_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_small_porch_v1-mechanism-v2.png"},
	"r34.module.home_small_annex_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_small_annex_v1", "geometry_version": "r34.module.home_small_annex_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_small_annex_v1-mechanism-v2.png"},
	"r34.module.home_small_court_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_small_court_v1", "geometry_version": "r34.module.home_small_court_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_small_court_v1-mechanism-v2.png"},
	"r34.module.home_medium_long_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_medium_long_v1", "geometry_version": "r34.module.home_medium_long_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_medium_long_v1-mechanism-v2.png"},
	"r34.module.home_medium_corner_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_medium_corner_v1", "geometry_version": "r34.module.home_medium_corner_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_medium_corner_v1-mechanism-v2.png"},
	"r34.module.home_medium_twin_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_medium_twin_v1", "geometry_version": "r34.module.home_medium_twin_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_medium_twin_v1-mechanism-v2.png"},
	"r34.module.home_large_u_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_large_u_v1", "geometry_version": "r34.module.home_large_u_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_large_u_v1-mechanism-v2.png"},
	"r34.module.home_large_double_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_large_double_v1", "geometry_version": "r34.module.home_large_double_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_large_double_v1-mechanism-v2.png"},
	"r34.module.home_large_lodge_v1.mechanism-v2": {"geometry_source_id": "r34.module.home_large_lodge_v1", "geometry_version": "r34.module.home_large_lodge_v1.geometry-v2", "path": "res://themes/modules/housing-mechanism-v2-v1/home_large_lodge_v1-mechanism-v2.png"}
}

const ARCHITECTURE_MODULES := {
	"r34.module.home_small_porch_v1": {"geometry_version":"r34.module.home_small_porch_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_small_porch_v1.png"},
	"r34.module.home_small_annex_v1": {"geometry_version":"r34.module.home_small_annex_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_small_annex_v1.png"},
	"r34.module.home_small_court_v1": {"geometry_version":"r34.module.home_small_court_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_small_court_v1.png"},
	"r34.module.home_medium_long_v1": {"geometry_version":"r34.module.home_medium_long_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_medium_long_v1.png"},
	"r34.module.home_medium_corner_v1": {"geometry_version":"r34.module.home_medium_corner_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_medium_corner_v1.png"},
	"r34.module.home_medium_twin_v1": {"geometry_version":"r34.module.home_medium_twin_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_medium_twin_v1.png"},
	"r34.module.home_large_u_v1": {"geometry_version":"r34.module.home_large_u_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_large_u_v1.png"},
	"r34.module.home_large_double_v1": {"geometry_version":"r34.module.home_large_double_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_large_double_v1.png"},
	"r34.module.home_large_lodge_v1": {"geometry_version":"r34.module.home_large_lodge_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/home_large_lodge_v1.png"},
	"r34.module.water_low_v1": {"geometry_version":"r34.module.water_low_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/water_low_v1.png"},
	"r34.module.water_mid_v1": {"geometry_version":"r34.module.water_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/water_mid_v1.png"},
	"r34.module.water_high_v1": {"geometry_version":"r34.module.water_high_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/water_high_v1.png"},
	"r34.module.repair_low_v1": {"geometry_version":"r34.module.repair_low_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/repair_low_v1.png"},
	"r34.module.repair_mid_v1": {"geometry_version":"r34.module.repair_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/repair_mid_v1.png"},
	"r34.module.repair_high_v1": {"geometry_version":"r34.module.repair_high_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/repair_high_v1.png"},
	"r34.module.guard_low_v1": {"geometry_version":"r34.module.guard_low_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/guard_low_v1.png"},
	"r34.module.guard_mid_v1": {"geometry_version":"r34.module.guard_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/guard_mid_v1.png"},
	"r34.module.guard_high_v1": {"geometry_version":"r34.module.guard_high_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/guard_high_v1.png"},
	"r34.module.sawmill_low_v1": {"geometry_version":"r34.module.sawmill_low_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/sawmill_low_v1.png"},
	"r34.module.sawmill_mid_v1": {"geometry_version":"r34.module.sawmill_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/sawmill_mid_v1.png"},
	"r34.module.sawmill_high_v1": {"geometry_version":"r34.module.sawmill_high_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/sawmill_high_v1.png"},
	"r34.module.warehouse_low_v1": {"geometry_version":"r34.module.warehouse_low_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/warehouse_low_v1.png"},
	"r34.module.warehouse_mid_v1": {"geometry_version":"r34.module.warehouse_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/warehouse_mid_v1.png"},
	"r34.module.warehouse_high_v1": {"geometry_version":"r34.module.warehouse_high_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/warehouse_high_v1.png"},
	"r34.module.canteen_low_v1": {"geometry_version":"r34.module.canteen_low_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/canteen_low_v1.png"},
	"r34.module.canteen_mid_v1": {"geometry_version":"r34.module.canteen_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/canteen_mid_v1.png"},
	"r34.module.canteen_high_v1": {"geometry_version":"r34.module.canteen_high_v1.geometry-v1", "path":"res://themes/modules/architecture-gpu02/canteen_high_v1.png"},
	"r34.module.artisan_low_v1": {"geometry_version":"r34.module.artisan_low_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/artisan_low_v1.png"},
	"r34.module.artisan_mid_v1": {"geometry_version":"r34.module.artisan_mid_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/artisan_mid_v1.png"},
	"r34.module.artisan_high_v1": {"geometry_version":"r34.module.artisan_high_v1.geometry-v1", "path":"res://themes/modules/architecture-final-v1/artisan_high_v1.png"},
}

static func texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if _cache.has(path): return _cache[path]
	var value: Texture2D
	if ResourceLoader.has_cached(path) or (ResourceLoader.exists(path) and (FileAccess.file_exists(path + ".import") or not FileAccess.file_exists(path))):
		value = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var pixels := Image.load_from_file(path)
		if pixels != null and not pixels.is_empty(): value = ImageTexture.create_from_image(pixels)
	if value != null: _cache[path] = value
	return value

static func module_texture(definition: Dictionary) -> Texture2D:
	var id := str(definition.get("id", ""))
	if HOUSING_MECHANISM_V2.has(id):
		var housing: Dictionary = HOUSING_MECHANISM_V2[id]
		if definition.get("mechanism", {}).get("version") != 2 or definition.get("geometry_source_id") != housing.geometry_source_id or definition.get("geometry_version") != housing.geometry_version: return null
		return texture(str(housing.path))
	# Reuse only an explicit public source and full geometry identity.
	if definition.get("mechanism", {}).get("version") == 2:
		id = str(definition.get("geometry_source_id", ""))
	if ARCHITECTURE_MODULES.has(id):
		var image: Dictionary = ARCHITECTURE_MODULES[id]
		return texture(str(image.path)) if definition.get("geometry_version") == image.geometry_version else null
	var stem := str(MODULES.get(id, ""))
	# Do not silently display an obsolete shape after a geometry version change.
	if stem.is_empty() or definition.get("geometry_version") != MODULE_VERSIONS.get(id, id + ".geometry-v1"): return null
	return texture("res://themes/modules/" + stem + "-front.png")

static func water_texture(source: Dictionary) -> Texture2D:
	# The broken physical pose is an image, never an unknown-source reveal.
	if source.get("discovered") != true: return null
	var remaining: Variant = source.get("remaining")
	if not (remaining is int or remaining is float) or not is_finite(float(remaining)) or float(remaining) < 0: return null
	var state := str(source.get("status", ""))
	if state not in ["needs_repair", "ready"]: return null
	var stem := "unknown" if state == "needs_repair" else "empty" if float(remaining) == 0 else "repaired"
	return texture("res://themes/water/WT01-" + stem + "-front.png")
