extends "res://tests/buildings/cold_equivalence_suite.gd"
const BeforeCrop=preload("res://tests/buildings/support_crop_reference/building_service.gd")
func reference_building()->RefCounted:return BeforeCrop.new()
