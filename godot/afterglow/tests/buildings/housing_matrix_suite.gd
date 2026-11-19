extends "res://tests/buildings/family_matrix_suite.gd"
## The same exact safety matrix, focused on the two new authored residences.
func profiles_to_check()->Array:
	return Building.generation_profiles().filter(func(p:Dictionary)->bool:return p.id in ["homestead_compact","homestead_courtyard"])
