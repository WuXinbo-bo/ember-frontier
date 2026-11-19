extends "res://tests/buildings/cold_equivalence_suite.gd"
## Incremental full prepare_door comparison against the exact current source
## immediately before floor clearance certificates; only preload remaps differ.
const FloorReferenceBuilding=preload("res://tests/buildings/floor_reference/building_service.gd")
func reference_building()->RefCounted:return FloorReferenceBuilding.new()
