extends SceneTree
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Housing=preload("res://scripts/modules/module_housing.gd")
func _initialize()->void:
	for d:Dictionary in Catalog.definitions():
		if not Housing.applies(d):continue
		var original:=Shape.parts(Catalog.definition_view(str(d.geometry_source_id)))
		print(JSON.stringify({"id":d.id,"capacity":d.mechanism.beds,"rooms":Housing.rooms(original),"layout":Housing.layout(original,int(d.mechanism.beds))}))
	quit()
