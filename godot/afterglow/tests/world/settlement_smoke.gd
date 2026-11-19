extends SceneTree
const Generator = preload("res://scripts/world/settlement_generator.gd")
func _initialize() -> void:
	var profiles: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var result := Generator.draft_region(713,Vector2i.ZERO,profiles)
	print(JSON.stringify({"ok":result.ok,"cost":result.get("cost"),"reason":result.get("reason"),"plan":result.get("plan")}))
	quit(0 if result.ok else 1)
