extends "res://tests/buildings/door_transaction_suite.gd"
## Same live A runtime, same local preview and full command, exact B baseline
## after support safety fix versus current production. No prototype proxies.
const BeforeTemplate=preload("res://tests/buildings/pre_template_reference/building_service.gd")
func reference_building()->RefCounted:return BeforeTemplate.new()
func hint(c:Dictionary,request:Dictionary,_reference:bool)->Dictionary:
	return c.building.door_preview(request)
