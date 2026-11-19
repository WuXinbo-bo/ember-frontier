extends SceneTree
const Ecology=preload("res://scripts/ecology/ecology_service.gd")
func _init()->void:
 var service=Ecology.new()
 print("ECOLOGY_IMPORT_OK ", service.KEY)
 quit(0)
