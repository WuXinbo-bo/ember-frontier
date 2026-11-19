extends "res://tests/world/village_contours.gd"
func run()->void:
	var args:=OS.get_cmdline_user_args();var profiles:Array=Building.generation_profiles()
	for seed:int in [12,713]:
		for model:String in ["village-contours-v4","broad-terraces-v5","local-hills-v6"]:
			var path:String=args[2]+"/seed%d-%s.var"%[seed,model]
			if model=="local-hills-v6":path=args[1]+"/seed%d-v6-source.var"%seed
			var original:Dictionary=FileAccess.open(path,FileAccess.READ).get_var()
			var current:Dictionary=model_world(seed,profiles,model)
			check("v7 opt-in wiring preserves exact complete older source "+str(seed)+model,var_to_bytes(original)==var_to_bytes(current))
	costs.scope="Six fixed full world snapshots (all cells/plans/IDs/content), not seed-only or old unrelated green test reruns. No changes to v4/v5/v6 algorithms or old captures."
	finish()
