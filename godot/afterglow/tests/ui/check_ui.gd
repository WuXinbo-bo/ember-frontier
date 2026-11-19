extends SceneTree
const UiProjection = preload("res://scripts/ui/ui_projection.gd")
const Layout = preload("res://scripts/ui/inventory_layout.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const GameUi = preload("res://scripts/ui/game_ui.gd")

func _initialize() -> void:
	print("UI_PARSE_OK")
	quit()
