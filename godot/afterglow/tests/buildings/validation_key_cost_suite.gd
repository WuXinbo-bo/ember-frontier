extends "res://tests/buildings/cold_equivalence_suite.gd"
const BeforeKey=preload("res://tests/buildings/validation_key_reference.gd")
func reference_building()->RefCounted:return BeforeKey.new()
