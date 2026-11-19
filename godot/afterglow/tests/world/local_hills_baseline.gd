extends "res://tests/world/village_contours.gd"
func run()->void:
	var folder:String=OS.get_cmdline_user_args()[0].get_base_dir()
	var rows:Array=[];var profiles:Array=Building.generation_profiles()
	for seed:int in [12,713]:
		for model:String in ["village-contours-v4","broad-terraces-v5"]:
			var source:Dictionary=model_world(seed,profiles,model)
			check("pre-v6 full existing model snapshot "+str(seed)+model,source.has("chunks"))
			FileAccess.open(folder+"/seed%d-%s.var"%[seed,model],FileAccess.WRITE).store_var(source)
			rows.append({"seed":seed,"model":model,"raw_source_sha256":var_to_bytes(source).hex_encode().sha256_text(),"raster_sha256":raster_digest(source)})
	costs.rows=rows;finish()
