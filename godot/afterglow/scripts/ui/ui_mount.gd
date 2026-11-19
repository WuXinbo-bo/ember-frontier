extends RefCounted
## A calls this once at its composition root; does not create a world or tick it.
const Scene = preload("res://scenes/ui/game_ui.tscn")
const Recovery = preload("res://scripts/ui/recovery_menu.gd")

static func mount(parent: Node, runtime: Object, input_router: Object) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "PlayerInterface"
	layer.layer = 20
	var ui: Control = Scene.instantiate()
	ui.configure(runtime, input_router)
	layer.add_child(ui)
	parent.add_child(layer)
	return ui

static func mount_recovery(host: Node, candidates: Array, choose: Callable, fresh: Callable, initial_failure: Dictionary = {}) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "RecoveryInterface"
	layer.layer = 20
	var ui := Recovery.new()
	ui.configure(candidates, choose, fresh)
	ui.show_failure(initial_failure)
	layer.add_child(ui); host.add_child(layer)
	return ui
