extends RefCounted
## Short display labels only. Identity, capability and permissions stay with
## the public module definition and original command authorities.
const FAMILIES := ["home", "warehouse", "sawmill", "workshop", "artisan", "repair", "water", "canteen", "guard", "supply", "machine"]
const LEGACY_FAMILIES := {
	"r34.module.fuel_woodshop":"sawmill",
	"r39.module.heritage_mill":"sawmill",
	"r34.module.woodshop_long_v2":"sawmill",
	"r34.module.woodshop_long_v3":"sawmill",
	"r34.module.woodshop_yard_v3":"sawmill",
	"r34.module.repair_shed_v2":"repair",
	"r34.module.repair_shed_v3":"repair"
}

static func family(definition: Dictionary) -> String:
	var id := str(definition.get("id", ""))
	# The opening shed intentionally combines basic woodwork and life recipes.
	if id in ["r35.module.village_workshop", "r35.module.village_workshop.opening-v15", "r37.module.workshop", "r38.module.workshop"] or definition.get("inherits") == "r35.module.village_workshop": return "workshop"
	var mechanism: Variant = definition.get("mechanism", {})
	if mechanism is Dictionary and FAMILIES.has(str(mechanism.get("family", ""))): return str(mechanism.family)
	var architecture: Variant = definition.get("architecture", {})
	if architecture is Dictionary and FAMILIES.has(str(architecture.get("family", ""))): return str(architecture.family)
	if LEGACY_FAMILIES.has(id): return str(LEGACY_FAMILIES[id])
	return str({"home":"home", "storage":"warehouse", "workshop":"workshop", "machine":"machine", "supply":"supply", "story_supply":"supply"}.get(str(definition.get("generation_role", "")), ""))

static func name(definition: Dictionary, fallback: String = "") -> String:
	if definition.has("compact_kind") or definition.has("village_tier") or definition.get("regional_art",false): return str(definition.name)
	var key := family(definition)
	if key == "water":
		# A well picture does not prove that water can actually be extracted.
		var mechanism: Variant = definition.get("mechanism", {})
		return "净水站" if mechanism is Dictionary and not mechanism.get("recipes", []).is_empty() else "取水站"
	if key == "canteen": return "厨房" if _tier(definition) == 1 else "食堂"
	var simple := str({"home":"住宅", "warehouse":"仓库", "workshop":"工作棚", "sawmill":"锯木厂", "artisan":"工匠坊", "repair":"修理铺", "guard":"岗亭", "supply":"补给点", "machine":"加工站"}.get(key, ""))
	if not simple.is_empty(): return simple
	return fallback if not fallback.is_empty() else str(definition.get("name", "建筑"))

static func purpose(definition: Dictionary) -> String:
	if definition.get("regional_art",false):return str(definition.village_role)
	return str({"home":"住宿、休息与生活补给", "warehouse":"存放物资、取放与搬运", "workshop":"基础制作、工具修理与应急加工", "sawmill":"把原木加工成木板", "artisan":"制作工具和建筑零件", "repair":"修理工具与设备", "water":"查看取水与净水操作", "canteen":"把食材加工成餐食", "guard":"安排值守、查看警戒", "supply":"查看补给物资", "machine":"把原料加工成成品"}.get(family(definition), "查看此处可用操作"))

static func instance_name(definition: Dictionary, row: Dictionary) -> String:
	var custom := str(row.get("custom_name", "")).strip_edges()
	if not custom.is_empty(): return custom
	if row.get("name_is_custom", false) and not str(row.get("name", "")).strip_edges().is_empty(): return str(row.name)
	return name(definition, str(row.get("name", "建筑")))

static func _tier(definition: Dictionary) -> int:
	var mechanism: Variant = definition.get("mechanism", {})
	if mechanism is Dictionary and (mechanism.get("tier") is int or mechanism.get("tier") is float): return int(mechanism.tier)
	var architecture: Variant = definition.get("architecture", {})
	return int({"low":1, "small":1, "mid":2, "medium":2, "high":3, "large":3}.get(str(architecture.get("tier", "")), 0)) if architecture is Dictionary else 0
