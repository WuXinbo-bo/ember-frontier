extends RefCounted
## Exact display identities only. Missing art stays explicit; never infer from a name.
const Images = preload("res://scripts/ui/ui_images.gd")
const ROOT := "res://themes/icons/"
const ITEM_ICONS := {
	"food":"food_tin", "water":"water_bottle", "medicine":"bandage",
	"timber":"timber", "scrap":"metal_scrap", "knowledge":"knowledge_book",
	"manual_woodwork":"knowledge_book", "manual_tool_repair":"knowledge_book",
	"book_woodwork":"knowledge_book", "book_tool_repair":"knowledge_book",
	"log":"log", "cloth":"cloth", "tool_handle":"tool_handle",
	"r34:salvaged_drive_unit":"salvaged_drive_unit",
	"axe_head":"axe_head", "brace":"brace", "soil_m3":"soil_m3", "stone_m3":"stone_m3", "gravel_m3":"gravel_m3"
}
const REGION_ITEM_ICONS := {
 "r34:potato_seed": "region-production-v1/potato_seed",
 "r34:bean_seed": "region-production-v1/bean_seed",
 "r34:rice_seed": "region-production-v1/rice_seed",
 "r34:potato": "region-production-v1/potato",
 "r34:beans": "region-production-v1/beans",
 "r34:paddy": "region-production-v1/paddy",
 "r34:rice": "region-production-v1/rice",
 "r34:compost": "region-production-v1/compost",
 "r34:raw_water": "region-production-v3/raw_water",
 "r34:filtered_water": "region-production-v3/filtered_water",
 "r34:broadleaf_seed": "region-production-v1/broadleaf_seed",
 "r34:conifer_seed": "region-production-v1/conifer_seed",
 "r34:broadleaf_seedling": "region-production-v1/broadleaf_seedling",
 "r34:conifer_seedling": "region-production-v1/conifer_seedling",
 "r34:crop_residue": "region-production-v1/crop_residue",
 "r34:meal_simple": "region-production-v1/meal_simple",
 "r34:meal_hearty": "region-production-v1/meal_hearty",
 "r34:dry_ration": "region-production-v1/dry_ration",
 "water": "region-production-v1/water",
 "r34:structural_timber": "region-production-v3/structural_timber",
 "r34:metal_fitting": "region-production-v3/metal_fitting",
 "r34:water_bucket": "region-production-v3/water_bucket"
}
const TOOL_ICONS := {"salvaged_axe":"axe", "hammer":"hammer", "shovel":"shovel", "hand_saw":"hand_saw", "pickaxe":"pickaxe"}
const STATUS_ICONS := {"hunger":"status_hunger", "thirst":"water_bottle", "fatigue":"status_fatigue", "wounds":"status_injury", "inventory":"backpack"}

static func descriptor(entry: Dictionary) -> Dictionary:
	var reference: Dictionary = entry.get("reference", {})
	var kind := str(reference.get("kind", ""))
	var id := str(reference.get("item_id", "")) if kind == "item" else str(entry.get("definition_id", ""))
	var stem := ""
	if kind == "item": stem = str(REGION_ITEM_ICONS.get(id, ITEM_ICONS.get(id, "")))
	elif kind == "tool": stem = str(TOOL_ICONS.get(id, ""))
	var path := ROOT + stem + ".png" if not stem.is_empty() else ""
	var available := not path.is_empty() and (FileAccess.file_exists(path) or ResourceLoader.exists(path))
	return {"kind":kind, "id":id, "path":path, "available":available, "fallback":{"item":"材料", "tool":"工具", "recipe":"构件"}.get(kind, "—"), "reason":"" if available or entry.is_empty() else "图标待补"}

static func texture(entry: Dictionary) -> Texture2D:
	var info := descriptor(entry)
	return Images.texture(info.path) if info.available else null

static func use_hint(id: String) -> String:
	match id:
		"r34:raw_water": return "原水 · 不可直接饮用，须按工艺处理"
		"r34:filtered_water": return "过滤原水 · 尚不可饮用，需继续煮沸处理"
		"water": return "安全饮水 · 饮用仍需真实可用数量"
		"r34:water_bucket": return "取水桶 · 可重复使用的按件物品，桶本身不代表液体数量"
		"r34:structural_timber": return "结构木料 · 建筑梁材，不等同于普通木板"
		"r34:metal_fitting": return "金属连接件 · 已加工配件，不等同于废铁"
	return ""

static func status_texture(id: String) -> Texture2D:
	var stem := str(STATUS_ICONS.get(id, ""))
	var path := ROOT + stem + ".png"
	return Images.texture(path) if not stem.is_empty() else null

static func apply_button(button: Button, entry: Dictionary) -> void:
	# Clear reused controls as well as applying known images: no stale/misleading axe.
	button.icon = texture(entry)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	button.set_meta("ui_icon", descriptor(entry))

static func image(texture_value: Texture2D, width: int = 24) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture_value
	node.custom_minimum_size = Vector2(width, width)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
