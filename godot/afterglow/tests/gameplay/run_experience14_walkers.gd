extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Profiles=preload("res://scripts/runtime/actor_profiles.gd")
const ActorView=preload("res://scripts/presentation/actor_view.gd")
var checks:Array=[]
var host:Node
var runtime:RefCounted
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+": "+str(detail))
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0] if not args.is_empty() else "user://experience14-walkers"
	DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles(14)
	check("actual content14 generation profiles",profiles.get("ok",false),profiles.get("reason"))
	if not profiles.get("ok",false):finish();return
	var initial:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,14))
	check("actual content14 preparation",initial.get("ok",false),initial.get("reason"))
	if not initial.get("ok",false):finish();return
	host=Native.new();var built:Dictionary=host._assemble(initial.capture)
	check("actual content14 runtime assembly",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):finish();return
	runtime=built.runtime
	var legacy:Array=[{"id":"village-resident","name":"周婶","appearance_id":"r1_resident_neighbor"},{"id":"repair-resident","name":"老许","appearance_id":"r1_resident_shopkeeper"}]
	Profiles.apply_opening(legacy,{"content_version":13})
	check("content13 retains original names appearances and absent age metadata",legacy[0].name=="周婶" and legacy[1].name=="老许" and legacy[0].appearance_id=="r1_resident_neighbor" and not legacy[0].has("age_years") and not legacy[1].has("age_years"))
	check("young scout identity and biography",runtime.actor("village-resident").name=="林夏" and runtime.actor("village-resident").get("age_years")==27 and runtime.actor("village-resident").get("role_id")=="scout_hauler")
	check("middle-aged carpenter identity and biography",runtime.actor("repair-resident").name=="陈拓" and runtime.actor("repair-resident").get("age_years")==36)
	check("new appearance validation accepts configured characters",Profiles.valid(runtime.actor("village-resident")) and Profiles.valid(runtime.actor("repair-resident")))
	check("both new appearances resolve actual commuter rigs",Profiles.model_profile("village_linxia_v14")=="r1_resident_commuter" and Profiles.model_profile("village_chentuo_v14")=="r1_resident_commuter")
	for i:int in 5:runtime.tick(.1)
	var state:Dictionary=runtime.world.extension("r33:gameplay")
	var encounter:Dictionary=state.get("opening_walkers",{})
	check("finite exterior encounter registered through actual spawn path",encounter.get("spawned",false) and encounter.get("actors",[]).size() in [1,2],encounter)
	var before:Dictionary={}
	for id:String in encounter.get("actors",[]):
		var actor:Dictionary=runtime.actor(id);before[id]=[actor.x,actor.z]
		check("walker starts outside protected home with persisted brain",actor.regionId!="RH-HOME" and actor.get("walker_version")==14 and actor.get("walker_brain",{}).get("phase")=="patrol",actor.get("walker_brain"))
	for i:int in 20:runtime.tick(.1)
	var changed:bool=false
	for id:String in before:
		var actor:Dictionary=runtime.actor(id)
		if Vector2(actor.x,actor.z).distance_to(Vector2(before[id][0],before[id][1]))>.05:changed=true
	check("at least one actual exterior walker physically patrols",changed)
	var captured:Dictionary=runtime.capture_checkpoint();var roster:Array=encounter.get("actors",[]).duplicate()
	var cold:Dictionary=host._assemble(captured)
	check("cold checkpoint restores new biographies and finite encounter",cold.get("ok",false),cold.get("reason"))
	if cold.get("ok",false):
		runtime.retire();runtime=cold.runtime
		check("same stable walker roster after restore",runtime.world.extension("r33:gameplay").get("opening_walkers",{}).get("actors",[])==roster)
		check("cold resume retains young appearance without renaming legacy IDs",runtime.actor("village-resident").get("appearance_id")=="village_linxia_v14")
		for i:int in 5:runtime.tick(.1)
		var count:int=0
		for actor:Dictionary in runtime.facts().actors:
			if actor.get("faction")=="infected":count+=1
		check("restore does not duplicate finite enemies",count==roster.size())
	finish()
func finish()->void:
	var result:Dictionary={"scope":"Actual content14 generation/runtime finite patrol and cold checkpoint; no GPU or natural combat acceptance. No combat stats, materials or actor positions injected.","ok":checks.all(func(row:Dictionary)->bool:return row.ok),"checks":checks}
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	if runtime!=null:runtime.retire()
	if is_instance_valid(host):host.free()
	quit(0 if result.ok else 1)
