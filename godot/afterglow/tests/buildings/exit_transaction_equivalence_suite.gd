extends "res://tests/buildings/door_transaction_suite.gd"
const ExitReference=preload("res://tests/buildings/exit_reference_service.gd")
func reference_building()->RefCounted:return ExitReference.new()
