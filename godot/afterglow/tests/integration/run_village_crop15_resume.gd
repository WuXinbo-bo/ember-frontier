extends "res://tests/integration/run_village_supply15.gd"
## Continues the saved, unfunded resource journey. Never replays pickup/setup.
func run()->void:
	wall_start15=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args()
	outdir=args[0];DirAccess.make_dir_recursive_absolute(outdir)
	if args.size()<2:check("resume requires actual prior native capture",false);return finish()
	var path:String=args[1]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
	check("original saved natural journey passes native checksum codec",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("actual15 resource journey cold mounts all original domains",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;live15=runtime
	check("content15 inherits actual14 walker behavior",runtime._services.gameplay._experience14)
	check("content15 keeps scenario-three radio and village gates",runtime._services.gameplay._village_enabled())
	workshop15=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	axe15=workshop15.id+":tool:salvaged_axe";saw15=workshop15.id+":tool:hand_saw";hammer15=workshop15.id+":tool:hammer"
	var radio:Dictionary=runtime.availability({"command_id":"supply15:radio-gate","actor_id":"player","kind":"radio","target_id":workshop15.config.workbench_id,"payload":{"operation":"repair","tool_id":hammer15}})
	check("unrestored village cannot bypass real machine and warehouse radio gate",not radio.ok and radio.get("code")=="VILLAGE_SUPPLY_REQUIRED",radio.get("reason"))
	var zones:Array=runtime._services.zones.zone_records().filter(func(z:Dictionary)->bool:return z.id==field15)
	check("actual previous player-created potato bed persists",zones.size()==1)
	if zones.size()!=1:return finish()
	plant15=Rules15.plant_id("RH-HOME",zones[0].cells[0])
	check("real raw-water production survives observer and cold reload",runtime.world.extension("r34:gameplay").flags.get("village_clean_water",false))
	var seeds:float=float(runtime.actor("player").pack.get("r34:potato_seed",0))
	note(runtime,"resume original planted field without replaying resources",{"source":path,"plant":runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15]})
	for cycle:int in 2:
		if not wait_crop15(runtime) or not labor15(runtime,field15,"harvest_crop"):return finish()
		check("actual harvest retains next-cycle seed "+str(cycle+1),runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].seed_reserved==1)
		note(runtime,"real potato crop harvested",{"cycle":cycle+1,"plant":plant15})
		if not craft15(runtime,"r34:cook_potato_v2"):return finish()
		check("completed real meal sets semantic food objective",runtime.world.extension("r34:gameplay").flags.get("village_food_produced",false))
		check("cooked output is physically present and edible",runtime.actor("player").pack.get("r34:meal_simple",0)>=2)
		if not complete15(runtime,"eat","",{"item_id":"r34:meal_simple"}):return finish()
		save_scene(runtime,"actual-crop-cycle15-"+str(cycle+1))
		if cycle==0:
			if not labor15(runtime,field15,"sow"):return finish()
			check("same retained seed starts next crop without spending another finite seed",runtime.actor("player").pack.get("r34:potato_seed",0)==seeds)
	if float(runtime.actor("player").pack.get("r34:raw_water",0))<1:
		if not labor15(runtime,water15,"draw_raw_water"):return finish()
	if not craft15(runtime,"r34:compost_v2") or not labor15(runtime,field15,"sow") or not labor15(runtime,field15,"compost"):return finish()
	check("own two harvest residues restore depleted fertility",runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].fertility>=2)
	for draw:int in 2:
		if not labor15(runtime,water15,"draw_raw_water"):return finish()
	check("original raw source replenishes after actual normal game time",runtime.actor("player").pack.get("r34:raw_water",0)>=2)
	if not craft15(runtime,"r34:raw_boil_water_v2"):return finish()
	check("closed fertility seed water loop admits a third planted cycle",runtime.world.extension_entries("r34:ecology","plants",[plant15])[plant15].stage=="seedling" and runtime.actor("player").pack.get("r34:potato_seed",0)==seeds)
	finished15=true
	note(runtime,"two real harvests cooked consumed composted and replanted")
	save_scene(runtime,"actual-sustainable-supply15")
	finish()
