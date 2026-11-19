extends "res://tests/world/factory_normal_path.gd"
## The new seed parameter must support the real finite-tool walk, not just
## change a seed field in a generated snapshot. Full recovery remains E-owned.
func run()->void:
	var policy:Dictionary=Contract.fresh(Modules.generation_profiles(),3)
	var opening:Dictionary=normal_tools(policy.contract,2026)
	if not opening.ok:return finish()
	check("requested alternate seed reaches actual normal runtime",opening.world.identity().seed==2026 and Data.json_equal(opening.world.extension(Factory.CONFIG_KEY),policy.contract))
	check("alternate seed gets only the same real finite source tools",[opening.axe,opening.shovel,opening.pickaxe].all(func(id:String)->bool:return opening.runtime.tool(id).holderId=="pack:player"))
	costs={"seed":2026,"logical_seconds":opening.runtime.clock(),"scope":"new optional seed real normal source walk/search/take only; no duplicated E recovery, combat, OS, VA or performance qualification"};finish()
