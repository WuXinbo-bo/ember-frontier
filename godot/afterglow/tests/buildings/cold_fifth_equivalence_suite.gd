extends "res://tests/buildings/cold_equivalence_suite.gd"
## Incremental CPU proof against the exact service/space shipped in fifth PCK.
## Uses the identical complete two-side, five-moving-actor cold comparison.
const FifthBuilding=preload("res://tests/buildings/fifth_reference/building_service.gd")
func reference_building()->RefCounted:return FifthBuilding.new()
