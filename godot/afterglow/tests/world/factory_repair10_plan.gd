extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const BeforeContract=preload("res://tests/world/fixtures/repair10_before_contract.gd")
const BeforeFactory=preload("res://tests/world/fixtures/repair10_before_generator.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Materials=preload("res://scripts/environment/environment_materials.gd")
var checks:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func as_nine(plan:Dictionary,old:Dictionary)->Dictionary:
	# Only the explicit contract identity and the repair's three geometry IDs
	# may differ. Every other persistent field is compared without tolerance.
	var out:Dictionary=plan.duplicate(true)
	out.erase("repair_geometry_policy");out.generation_content_version=9
	out.configuration_sha256=old.configuration_sha256
	for p:Dictionary in out.parcels:
		if p.site_id!="woodwork":continue
		p.profile_id="r34.module.repair_shed_v2";p.definition_id=p.profile_id;p.geometry_version=p.profile_id+".geometry-v1"
	for m:Dictionary in out.module_seeds:
		if m.purpose!="woodwork":continue
		m.definition_id="r34.module.repair_shed_v2";m.geometry_version=m.definition_id+".geometry-v1"
	return out
func run()->void:
	var expanded:Array=Catalog.profiles_for_content(10)
	check("B version API keeps12/18/19 ordered inputs",Catalog.profiles_for_content(8).size()==12 and Catalog.profiles_for_content(9).size()==18 and expanded.size()==19 and Catalog.profiles_for_content(11).is_empty() and Data.json_equal(Catalog.profiles_for_content(9),Catalog.profiles(true)))
	for version:int in range(1,10):
		var story:int=1 if version>=3 else 0
		var profiles:Array=Catalog.profiles_for_content(version)
		var before:Dictionary=BeforeContract.fresh(profiles,version,story)
		var current:Dictionary=Contract.fresh(expanded,version,story)
		check("historical%d entire lock identical under expanded19"%version,before.ok and current.ok and Data.json_equal(before.contract,current.contract) and Contract.resolve(before.contract,expanded).ok)
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
			var a:Dictionary=BeforeFactory.plan_region(713,coord,profiles,before.contract)
			var b:Dictionary=Factory.plan_region(713,coord,expanded,before.contract)
			check("historical%d %s whole plan preserved"%[version,coord],a.ok and b.ok and Data.json_equal(a.plan,b.plan),b.get("reason"))
	var lock:Dictionary=Contract.fresh(expanded,10,1)
	check("explicit10 pins repair policy and all nine policies",lock.ok and lock.contract.repair_geometry_policy=="repair-shed-quality-v1" and lock.contract.content_version==10 and lock.contract.story_entrance_policy=="yard-stone-v1" and lock.contract.family_policy=="three-families-quality-v1",lock.get("reason"))
	check("legacy18 cannot silently create10",Contract.fresh(Catalog.profiles(true),10,1).get("code")=="MISSING_QUALITY_REPAIR_PROFILE")
	for variant:String in ["missing","wrong"]:
		var altered:Dictionary=lock.contract.duplicate(true)
		if variant=="missing":altered.erase("repair_geometry_policy")
		else:altered.repair_geometry_policy="unrecognized"
		check("saved10 rejects "+variant+" repair policy",Contract.resolve(altered,expanded).get("code")=="FACTORY_GENERATION_POLICY_MISMATCH")
	var lost:Array=expanded.filter(func(p:Dictionary)->bool:return p.id!=Contract.REPAIR_ID)
	check("saved10 rejects missing current repair geometry",Contract.resolve(lock.contract,lost).get("code")=="MODULE_PROFILE_VERSION_MISMATCH")
	var wrong:Array=expanded.duplicate(true)
	for p:Dictionary in wrong:
		if p.id==Contract.REPAIR_ID:p.geometry_version="r34.module.repair_shed_v3.geometry-v99"
	check("fresh10 rejects unknown repair geometry",Contract.fresh(wrong,10,1).get("code")=="MISSING_QUALITY_REPAIR_PROFILE")
	var old_lock:Dictionary=BeforeContract.fresh(Catalog.profiles(true),9,1)
	for seed:int in [713,2026,17,999]:
		var batch:Array=[]
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(-1,0),Vector2i(0,1)]:
			var start:int=Time.get_ticks_usec()
			var made:Dictionary=Factory.plan_region(seed,coord,expanded,lock.contract)
			var old:Dictionary=BeforeFactory.plan_region(seed,coord,Catalog.profiles(true),old_lock.contract)
			check("seed%d %s new10 compiles"%[seed,coord],made.ok,made.get("reason"))
			if not made.ok or not old.ok:continue
			check("seed%d %s only explicit repair identity differs from9"%[seed,coord],Data.json_equal(as_nine(made.plan,old.plan),old.plan))
			batch.append({"coord":{"x":coord.x,"z":coord.y},"plan":made.plan,"prepare_usec":Time.get_ticks_usec()-start})
		batch.reverse()
		for item:Dictionary in batch:
			var repeat:Dictionary=Factory.plan_region(seed,Vector2i(item.coord.x,item.coord.z),expanded,lock.contract)
			check("seed%d %s reverse order whole plan deterministic"%[seed,item.coord],repeat.ok and Data.json_equal(item.plan,repeat.plan))
		rows.append({"seed":seed,"regions":batch})
	var mats:=Materials.new();mats.set_world_style("factory-country-1",9)
	var nine:Material=mats.terrain_material("soil_side","side",1)
	mats.set_world_style("factory-country-1",10)
	var ten:Material=mats.terrain_material("soil_side","side",1)
	check("repair-only10 retains9 actual natural soil image and metre scale",nine.albedo_texture.get_image().get_data()==ten.albedo_texture.get_image().get_data() and nine.uv1_scale==ten.uv1_scale and mats._terrain_source("soil_side","side",1)=="natural_soil_side")
	check("10 retains roads and tops; unknown11 remains compatible",mats._terrain_source("soil_side","side",4)=="soil_side" and mats._terrain_source("grass_top","top",1)=="grass_top")
	mats.set_world_style("factory-country-1",11)
	check("unreleased11 not silently assigned new material policy",mats._terrain_source("soil_side","side",1)=="soil_side")
	var failed:int=checks.filter(func(r:Dictionary)->bool:return not r.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"Repair-only10 contract/full historical plans and exact9 comparison. Four seeds/four coordinates/reverse order. Actual material consumer; no renderer, PCK or VA."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
