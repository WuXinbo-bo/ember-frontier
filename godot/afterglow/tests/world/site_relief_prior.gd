extends "res://tests/world/village_contours.gd"
func run()->void:
	var args:=OS.get_cmdline_user_args();var profiles:Array=Building.generation_profiles()
	for seed:int in [12,713]:
		for model:String in ["village-contours-v4","broad-terraces-v5","local-hills-v6","local-relief-v7"]:
			var path:String=args[1]+"/seed%d-%s.var"%[seed,model]
			if model=="local-hills-v6":path=args[2]+"/seed%d-v6-source.var"%seed
			if model=="local-relief-v7":path=args[3]+"/seed%d-v7-source.var"%seed
			var original:Dictionary=FileAccess.open(path,FileAccess.READ).get_var()
			check("v8 wiring preserves exact full old source "+str(seed)+model,var_to_bytes(original)==var_to_bytes(model_world(seed,profiles,model)))
	costs.scope="Eight fixed full old-model worlds, all cells/plans/IDs/content. No migration or reinterpretation of older cells."
	finish()
