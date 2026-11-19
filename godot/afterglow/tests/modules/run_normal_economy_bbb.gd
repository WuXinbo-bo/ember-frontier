extends "res://tests/integration/run_factory_economy.gd"
## Same full A normal journey, emit full checks to B source-stability runner.
func check(label:String,ok:bool,detail:Variant=null)->void:
	super.check(label,ok,detail)
	print("NORMAL_STAGE "+str(checks.size())+" "+str(ok)+" "+label)
func note(runtime:RefCounted,stage:String,detail:Variant=null)->void:
	super.note(runtime,stage,detail)
	print("NORMAL_JOURNEY "+str(runtime.clock())+" "+stage)
func finish()->void:
	print(JSON.stringify({"checks":checks,"journey":journey,"scope":"entire original normal content3 finite economy; no relocation/items/permissions injected; current source, not candidate16/OS/VA"}))
	quit(1 if checks.any(func(row:Dictionary)->bool:return not row.ok) else 0)
