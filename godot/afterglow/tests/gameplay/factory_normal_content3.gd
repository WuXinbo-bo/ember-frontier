extends "res://tests/gameplay/factory_normal_preparation.gd"
## Explicit content3 uses the same C finite-source opening and full E journey.
## The application's default content contract is unchanged by this test.
func normal_tools(generation_contract:Dictionary={})->Dictionary:
	var contract:Dictionary=Contract.fresh(Modules.generation_profiles(),3).contract if generation_contract.is_empty() else generation_contract
	var opening:Dictionary=super.normal_tools(contract)
	if opening.get("ok",false):
		costs.generation_contract=opening.world.extension(Factory.CONFIG_KEY)
		check("normal journey explicitly selects content3 without changing default",costs.generation_contract.get("content_version")==3)
	return opening
