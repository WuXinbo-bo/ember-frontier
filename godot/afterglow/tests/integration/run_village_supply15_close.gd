extends "res://tests/integration/run_village_supply15.gd"
## Finish only the genuine retained-seed/fertility/water work left in prior save.
func run()->void:
	wall_start15=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args();outdir=args[0];DirAccess.make_dir_recursive_absolute(outdir)
	if args.size()<2:check("real prior natural journey capture is required",false);return finish()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("two-crop source passes original native checksum decoder",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("actual two-crop world cold-restores without backfilling a new frame",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;live15=runtime
	workshop15=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	axe15=workshop15.id+":tool:salvaged_axe";saw15=workshop15.id+":tool:hand_saw";hammer15=workshop15.id+":tool:hammer"
	var zones:Array=runtime._services.zones.zone_records().filter(func(z:Dictionary)->bool:return z.id==field15)
	check("original actual farm remains in its source position",zones.size()==1)
	if zones.size()!=1:return finish()
	plant15=Rules15.plant_id("RH-HOME",zones[0].cells[0])
	var ecology:Dictionary=runtime.world.extension("r34:ecology")
	var harvests:Array=ecology.completed.values().filter(func(v:Dictionary)->bool:return v.kind=="harvest_crop" and v.target_id==plant15)
	check("durable ecology facts prove two previously completed real harvests",harvests.size()==2)
	var facts:Array=runtime.world.extension("r3:production").facts
	check("durable production proves two original cooked-food batches",facts.filter(func(v:Dictionary)->bool:return v.kind=="crafted" and v.targetId=="r34:cook_potato_v2").size()==2)
	check("two original harvest residues persist as physical residue or real crafted compost",runtime.actor("player").pack.get("r34:crop_residue",0)==2 or (runtime.actor("player").pack.get("r34:compost",0)==1 and facts.any(func(v:Dictionary)->bool:return v.kind=="crafted" and v.targetId=="r34:compost_v2")))
	check("same original player owns recovered axe at restored durability",runtime.tool(axe15).holderId=="pack:player" and runtime.tool(axe15).durability>85)
	check("true food and safe-water objectives survive saved observer",runtime.world.extension("r34:gameplay").flags.get("village_clean_water",false) and runtime.world.extension("r34:gameplay").flags.get("village_food_produced",false))
	check("current old15 capture is not silently given the later new-world frame",runtime._services.modules.instance("RH-HOME:woodshop-old-frame").is_empty())
	note(runtime,"resume only remaining fertility and reusable water work",{"source":args[1],"completed_harvests":harvests.size()})
	var seeds:float=float(runtime.actor("player").pack.get("r34:potato_seed",0))
	if runtime.actor("player").pack.get("r34:compost",0)<1:
		if not craft15(runtime,"r34:compost_v2"):return finish()
	if runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].stage=="harvested":
		if not labor15(runtime,field15,"sow"):return finish()
	if not labor15(runtime,field15,"compost"):return finish()
	check("third planting uses retained seed and restores genuine depleted fertility",runtime.actor("player").pack.get("r34:potato_seed",0)==seeds and runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].fertility>=2 and runtime.actor("player").pack.get("r34:compost",0)==0)
	for draw:int in 2:
		if not labor15(runtime,water15,"draw_raw_water"):return finish()
	check("original real water source replenishes while original bucket remains reusable",runtime.actor("player").pack.get("r34:raw_water",0)>=2 and runtime.actor("player").pack.get("r34:water_bucket",0)==1)
	var before:float=float(runtime.actor("player").pack.get("water",0))
	if not craft15(runtime,"r34:raw_boil_water_v2"):return finish()
	check("second true raw-water batch creates exactly two more potable units",runtime.actor("player").pack.get("water",0)==before+2)
	check("original registration still cannot duplicate old source items",runtime._services.modules.prepare_generation(runtime.world,[],runtime.facts()).get("initial_stocks",[]).is_empty())
	finished15=true
	note(runtime,"natural two-cycle food water tool and fertility loop verified")
	save_scene(runtime,"actual-sustainable-supply15")
	finish()
