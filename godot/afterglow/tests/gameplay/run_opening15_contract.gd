extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Profile=preload("res://scripts/runtime/playtest_profile.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Generation=preload("res://scripts/world/factory_generation_contract.gd")
const Village=preload("res://scripts/runtime/village_progression.gd")
const Recipes=preload("res://scripts/production/module_recipes.gd")
const World=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
class Host extends RefCounted:
	var context:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label)
func pack_tools(capture:Dictionary)->Array:
	return capture.world.extensions["r3:production"].tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player")
func run()->void:
	check("authoritative module catalog validates additive15 definition",Catalog.validate().ok)
	var historical:Dictionary=Assembly.generation_profiles(14)
	check("historical14 profiles do not receive new workshop",historical.ok and historical.profiles.all(func(p:Dictionary)->bool:return p.id!=Catalog.OPENING15_WORKSHOP))
	var old_lock:Dictionary=Generation.fresh(historical.profiles,14,1)
	check("historical14 contract retains previous experience and no15 policy",old_lock.ok and old_lock.contract.experience_policy=="village-experience-v14" and not old_lock.contract.has("opening_configuration_policy"))
	var profiles:Dictionary=Assembly.generation_profiles(15)
	check("content15 generation profiles include only new opening workshop",profiles.ok and profiles.profiles.filter(func(p:Dictionary)->bool:return p.id==Catalog.OPENING15_WORKSHOP).size()==1 and profiles.profiles.all(func(p:Dictionary)->bool:return p.id!="r35.module.village_workshop"))
	if not profiles.ok:return finish()
	var generated:Dictionary=Assembly.generate(713,profiles.profiles,15)
	var prepared:Dictionary=Assembly.prepare(generated)
	check("actual seed713 content15 opening assembles",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var source:Dictionary=prepared.capture
	var total:int=source.world.extensions["r3:production"].tools.size()
	var normal:Dictionary=Profile.prepare_opening(source,"normal")
	check("normal15 contains one actual usable axe in player pack",pack_tools(normal).size()==1 and pack_tools(normal)[0].kind=="salvaged_axe" and float(pack_tools(normal)[0].durability)>0)
	check("normal axe transfer conserves every physical tool instance",normal.world.extensions["r3:production"].tools.size()==total and normal.source.opening_configuration.transfers.size()==1 and normal.source.opening_configuration.transfers[0].from=="r34:generated:RH-HOME:woodwork:stock:tools")
	check("normal15 grants no building materials or extra food",Data.json_equal(source.facts,normal.facts) and not normal.source.has("playtest"))
	check("normal opening configuration is idempotent",Data.json_equal(normal,Profile.prepare_opening(normal,"normal")))
	var tested:Dictionary=Profile.prepare_opening(source,"playtest")
	check("explicit test15 supplies exactly five real tool kinds",pack_tools(tested).size()==5 and Profile.TOOL_KINDS.all(func(kind:String)->bool:return pack_tools(tested).filter(func(t:Dictionary)->bool:return t.kind==kind).size()==1))
	check("test15 transfers tools without creating duplicate instances",tested.world.extensions["r3:production"].tools.size()==total)
	check("test15 records actual ids rather than ghost tool references",tested.source.playtest.tools.values().all(func(id:Variant)->bool:return pack_tools(tested).any(func(t:Dictionary)->bool:return t.id==id)))
	check("test15 has finite configured supplies",Profile.ITEMS.keys().all(func(item:String)->bool:return tested.facts.actors[0].pack.get(item,0)==Profile.ITEMS[item]))
	check("test15 composition is idempotent",Data.json_equal(tested,Profile.prepare_opening(tested,"playtest")))
	var spent:Dictionary=tested.duplicate(true);spent.facts.actors[0].pack.water=0;spent.world.extensions["r3:production"].tools[0].durability=1
	check("reapplying a recorded profile cannot refill spent resources",Data.json_equal(spent,Profile.prepare_opening(spent,"playtest")))
	var legacy:Dictionary=source.duplicate(true);legacy.world.extensions["generation:factory-r34"].content_version=14
	check("old14 playtest retains its historical finite-source semantics",Data.json_equal(legacy,Profile.apply(legacy)))
	var state:Dictionary={"layout":{"content_version":15},"flags":{}}
	Village.observe(state,{"kind":"crafted","targetId":"r34:filter_water_v2"})
	check("filtering alone never claims potable water",not state.flags.get("village_clean_water",false))
	Village.observe(state,{"kind":"crafted","targetId":"r34:raw_boil_water_v2"})
	check("cloth-free raw boil output advances real clean-water objective",state.flags.get("village_clean_water",false))
	Village.observe(state,{"kind":"crafted","targetId":"r34:hearty_stew_v2"})
	check("registered edible stew output advances food objective",state.flags.get("village_food_produced",false))
	var unknown:Dictionary={"layout":{"content_version":15},"flags":{}}
	Village.observe(unknown,{"kind":"crafted","targetId":"made-up-recipe"})
	check("unknown recipe names cannot forge supply milestones",unknown.flags.is_empty())
	var world:=World.new();var loaded:Dictionary=world.load_snapshot(normal.world)
	check("configured15 world snapshot loads with original validation",loaded.ok,loaded.get("reason"))
	if loaded.ok:
		var host:=Host.new();host.context={"world":world}
		check("physical original workbench resolves its real owning module",Recipes.canonical_station(host,"r34:generated:RH-HOME:woodwork:workbench")=="r34:generated:RH-HOME:woodwork")
		check("unknown workbench cannot alias a real module",Recipes.module(host,"made-up-workbench").is_empty())
	var workshop:Dictionary=Catalog.definition(Catalog.OPENING15_WORKSHOP)
	check("new15 bootstrap uses existing cooking water bucket and recovery recipes",["r34:raw_boil_water_v2","r34:cook_potato_v2","r34:make_water_bucket_v2","r34:repair_hammer_v2"].all(func(id:String)->bool:return workshop.mechanism.recipes.has(id)))
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"opening15-contract","checks":checks,"failed":failed},"\t"))
	print(JSON.stringify({"suite":"opening15-contract","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
