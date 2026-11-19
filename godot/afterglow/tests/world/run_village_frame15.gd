extends "res://tests/world/factory_joint.gd"
const Profile15=preload("res://scripts/runtime/playtest_profile.gd")
const Restoration15=preload("res://scripts/modules/module_restoration.gd")
const Recipes15=preload("res://scripts/production/module_recipes.gd")
var results_dir15:String=""
func run()->void:
	results_dir15=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(results_dir15)
	var profiles:Dictionary=Assembly.generation_profiles(15)
	for seed:int in [713,2026,42]:
		var prepared:Dictionary=Assembly.prepare(Assembly.generate(seed,profiles.get("profiles",[]),15))
		check("new15 heritage frame composes without injected materials "+str(seed),prepared.get("ok",false),prepared.get("reason"))
		if not prepared.get("ok",false):continue
		var capture:Dictionary=Profile15.prepare_opening(prepared.capture,"normal")
		var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free()
		check("new15 heritage frame survives complete Native validation "+str(seed),built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var runtime:RefCounted=built.runtime
		var machine:Dictionary=built.services.modules.instance("RH-HOME:woodshop-old-frame")
		check("one damaged finite S01 machine exists on original workyard "+str(seed),not machine.is_empty() and machine.definition_id==Restoration15.DEFINITION and machine.status=="damaged" and not machine.player_built and machine.restoration.policy==Restoration15.POLICY)
		if machine.is_empty():runtime.retire();continue
		check("frame recovery keeps original S01 materials and duration "+str(seed),Restoration15.cost(machine)==Restoration15.COST and Restoration15.duration(machine)==40 and machine.get("paid_cost",{}).is_empty())
		var d:Dictionary=Catalog.definition(machine.definition_id)
		var routes:Array=[]
		for port:Dictionary in preload("res://scripts/modules/module_geometry.gd").ports(machine,d):
			var feet:Dictionary=built.services.buildings.current_space().standing_point(port.use_points[0])
			var route:Dictionary=built.services.actions.route("player",Geometry.location(runtime.actor("player")),feet) if not feet.is_empty() else {"ok":false,"reason":"no supported service feet"}
			routes.append({"id":port.id,"supported":not feet.is_empty(),"reachable":route.get("ok",false),"reason":route.get("reason")})
		check("all five actual frame service mouths have supported reachable routes "+str(seed),routes.size()==5 and routes.all(func(r:Dictionary)->bool:return r.supported and r.reachable),routes)
		var old_home:Dictionary=built.services.modules.instance("r34:generated:RH-HOME:home")
		var warehouse:Dictionary=built.services.modules.instance("r34:generated:RH-HOME:village-warehouse")
		var initial_scrap:float=0
		for stock:Dictionary in runtime.facts().stocks:initial_scrap+=float(stock.get("items",{}).get("scrap",0))
		var axe_recipe:Dictionary=Recipes15.definitions().filter(func(r:Dictionary)->bool:return r.id=="r34:repair_axe_v2")[0]
		var required:float=float(Restoration15.cost(old_home).get("scrap",0))+float(Restoration15.cost(warehouse).get("scrap",0))+float(Restoration15.cost(machine).get("scrap",0))+8+float(axe_recipe.inputs.scrap)
		check("original finite scrap covers house warehouse machine radio and one axe recovery "+str(seed),initial_scrap==17 and required==16 and initial_scrap-required==1,{"original_scrap":initial_scrap,"required_scrap":required,"remaining_scrap":initial_scrap-required,"radio_scrap_from_rural_gameplay":8})
		var count:int=runtime.world.extension("r34:modules").instances.size()
		var again:Dictionary=built.services.modules.prepare_generation(runtime.world,[],runtime.facts())
		check("revisiting cannot duplicate the inherited frame or its source "+str(seed),again.ok and again.get("initial_stocks",[]).is_empty() and again.get("world_changes",[]).is_empty() and runtime.world.extension("r34:modules").instances.size()==count)
		runtime.retire()
	var historical:Dictionary=Assembly.generation_profiles(14)
	var old:Dictionary=Assembly.generate(713,historical.get("profiles",[]),14)
	check("historical14 keeps no15 old machine backfill",old.get("extensions",{}).get("generation:RH-HOME",{}).get("story_sites",[]).is_empty())
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(results_dir15+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"village-frame15","checks":checks,"failed":failed,"scope":"Three seeds: actual complete new-world Native assembly, supported real routes to inherited frame service mouths, original finite-resource arithmetic and once-only registration. No inventory/actor/terrain injection. Not a claim of completed full natural radio journey."},"\t",true,true))
	print(JSON.stringify({"suite":"village-frame15","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
