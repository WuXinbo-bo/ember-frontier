extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const BeforeContract=preload("res://tests/world/fixtures/generation_before_story7.gd")
const BeforeFactory=preload("res://tests/world/fixtures/generator_before_story7.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _init()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"label":label,"ok":ok,"detail":detail})
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var path:String=args[0]
	var profiles:Array=Catalog.profiles();var historical:Array=profiles.filter(func(p:Dictionary)->bool:return p.get("generation_role")!="story_supply")
	for version:int in range(1,7):
		var old:Dictionary=BeforeContract.fresh(historical,version,1 if version>=3 else 0)
		var now:Dictionary=Contract.fresh(profiles,version,1 if version>=3 else 0)
		check("historical%d exact lock/digest and additive catalogue resolves"%version,old.ok and now.ok and JSON.stringify(old.contract,"",true,true)==JSON.stringify(now.contract,"",true,true) and Contract.resolve(old.contract,profiles).ok)
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
			var before:Dictionary=BeforeFactory.plan_region(713,coord,historical,old.contract)
			var after:Dictionary=Factory.plan_region(713,coord,profiles,old.contract)
			check("historical%d %s whole plan exact"%[version,coord],before.ok and after.ok and Data.json_equal(before.plan,after.plan) and not after.plan.has("story_sites"),after.get("reason"))
	var lock:Dictionary=Contract.fresh(profiles,7,1)
	check("content7 explicitly pins all three policies",lock.ok and lock.contract.story_site_policy=="s01-s03-v1" and lock.contract.tool_recovery_policy=="mt01-v1" and lock.contract.water_recovery_policy=="wt01-v1")
	check("invalid additive catalogue still rejected before historical filtering",not Contract.fresh(profiles+[null],6,1).get("ok",false))
	var rearless:Array=profiles.filter(func(p:Dictionary)->bool:return p.id!="r34.module.supply_rear_v3")
	var rearless_lock:Dictionary=Contract.fresh(rearless,7,1)
	check("missing exact story-only rear profile cannot silently choose legacy store",Factory.plan_region(713,Vector2i(0,-1),rearless,rearless_lock.contract).get("code")=="S03_MISSING_PINNED_REAR_SUPPLY_PROFILE")
	var altered:Array=profiles.duplicate(true)
	for p:Dictionary in altered:
		if p.id=="r34.module.supply_rear_v3":p.story_front_point[2]=-3.0
	check("saved front point participates in exact immutable geometry lock",Contract.resolve(lock.contract,altered).get("code")=="MODULE_PROFILE_VERSION_MISMATCH")
	for mode:String in ["missing","changed"]:
		var bad:Dictionary=lock.contract.duplicate(true)
		if mode=="missing":bad.erase("story_site_policy")
		else:bad.story_site_policy="other"
		check("story policy rejects "+mode,Contract.resolve(bad,profiles).get("code")=="FACTORY_GENERATION_POLICY_MISMATCH")
	var rows:Array=[]
	for seed:int in [713,2026,17,999]:
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(-1,0)]:
			var started:int=Time.get_ticks_usec();var one:Dictionary=Factory.plan_region(seed,coord,profiles,lock.contract)
			var elapsed:int=Time.get_ticks_usec()-started
			var two:Dictionary=Factory.plan_region(seed,coord,profiles,lock.contract)
			check("seed%d %s valid deterministic content7 plan"%[seed,coord],one.ok and two.ok and Data.json_equal(one.plan,two.plan),one if not one.ok else {"region":one.plan.region_id,"elapsed_usec":elapsed})
			if one.ok:rows.append({"seed":seed,"coord":{"x":coord.x,"z":coord.y},"sites":one.plan.story_sites,"approaches":one.plan.story_approaches,"parcels":one.plan.parcels,"elapsed_usec":elapsed})
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"static plan only, no physical route/economy/package qualification"},"\t",true,true));quit(1 if failed else 0)
