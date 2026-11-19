extends SceneTree
func _initialize() -> void:
	var paths: Array = ["building_geometry", "building_navigation", "building_space", "building_service", "rural_buildings", "building_view", "building_mesh", "../actions/domain_context", "../actions/domain_draft", "../actions/action_service", "../production/production_service"]
	var failed := false
	for name in paths:
		var script: Script = load("res://scripts/buildings/" + str(name) + ".gd")
		if script == null or not script.can_instantiate(): failed = true
	print(JSON.stringify({"scope": "BBB domain script parse only, no preview or export", "ok": not failed, "scripts": paths}))
	quit(1 if failed else 0)
