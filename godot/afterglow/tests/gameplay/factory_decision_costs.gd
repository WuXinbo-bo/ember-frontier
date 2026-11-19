extends "res://tests/gameplay/factory_survival.gd"
## Source CPU diagnostics with actual normal actors; no simulation throttling.
func paths(before:Variant,after:Variant,prefix:String="")->Array:
	if before==after:return []
	var rows:Array=[]
	if before is Dictionary and after is Dictionary:
		for key:Variant in after:
			if not before.has(key):rows.append(prefix+str(key));continue
			rows.append_array(paths(before[key],after[key],prefix+str(key)+"."))
		return rows
	return [prefix.trim_suffix(".")]
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output);host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles();var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	if not mount(opening.capture):return finish()
	var samples:Array=[];var changed:int=0;var empty:int=0
	for i in 100:
		var plan:Dictionary=runtime._services.workforce.advance(0.1)
		var rows:Array=[]
		for change:Dictionary in plan.get("fact_changes",[]):rows.append({"collection":change.collection,"id":change.id,"fields":paths(change.before,change.after)})
		for change:Dictionary in plan.get("world_changes",[]):rows.append({"extension":change.id,"fields":paths(change.before,change.after)})
		if rows.is_empty():empty+=1
		else:changed+=1
		if samples.size()<20 and not rows.is_empty():samples.append({"time":runtime.clock(),"changes":rows})
		runtime.tick(0.1)
	var f:=FileAccess.open(output+"/changes.json",FileAccess.WRITE);f.store_string(JSON.stringify({"samples":samples,"changed":changed,"empty":empty},"\t"));f.close()
	check("all ten diagnostic seconds retain original clock and identities",absf(runtime.clock()-10)<0.001 and runtime.facts().actors.size()==3)
	finish()
