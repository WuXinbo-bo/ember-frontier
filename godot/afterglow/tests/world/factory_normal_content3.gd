extends "res://tests/world/factory_modification.gd"
## Same real finite-source route, new B7 geometry/content3 only. Fresh default
## remains2; no duplicate test implementation or privileged input fixtures.
func generation_contract()->Dictionary:
	return Contract.fresh(Modules.generation_profiles(),3).contract
