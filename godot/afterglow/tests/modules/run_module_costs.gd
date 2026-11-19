extends "res://tests/integration/run_factory_costs.gd"
func finish(costs:Dictionary)->void:
	print(JSON.stringify({"checks":checks,"costs":costs,"scope":"same normal three-person source, actual 600 ticks and full original validators; CPU attribution only, not renderer/FPS"}))
	quit(1 if checks.any(func(c:Dictionary)->bool:return not c.ok) else 0)
