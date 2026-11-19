extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Family=preload("res://scripts/world/factory_quality_family.gd")
const BeforeContract=preload("res://tests/world/fixtures/quality9_before_contract.gd")
const BeforeFactory=preload("res://tests/world/fixtures/quality9_before_generator.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	var old_profiles:Array=Catalog.profiles();var profiles:Array=Catalog.profiles(true)
	check("one B catalog exposes exact12 default and18 opt-in",old_profiles.size()==12 and profiles.size()==18)
	for version:int in range(1,9):
		var story:int=1 if version>=3 else 0
		var before:Dictionary=BeforeContract.fresh(old_profiles,version,story)
		var current:Dictionary=Contract.fresh(profiles,version,story)
		check("historical%d whole lock identical even with expanded catalog"%version,before.ok and current.ok and Data.json_equal(before.contract,current.contract) and Contract.resolve(before.contract,profiles).ok)
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
			var a:Dictionary=BeforeFactory.plan_region(713,coord,old_profiles,before.contract)
			var b:Dictionary=Factory.plan_region(713,coord,profiles,before.contract)
			check("historical%d %s entire persistent plan unchanged"%[version,coord],a.ok and b.ok and Data.json_equal(a.plan,b.plan),b.get("reason"))
	var lock:Dictionary=Contract.fresh(profiles,9,1)
	check("explicit9 locks six new shapes and existing source policies",lock.ok and lock.contract.family_policy==Family.POLICY and lock.contract.family_summary.size()==3 and lock.contract.workyard_policy==Family.WORKYARD_POLICY and lock.contract.parcel_orientation=="road-court-camera-v2" and lock.contract.story_site_policy=="s01-s03-v1" and lock.contract.story_entrance_policy=="yard-stone-v1")
	check("legacy12 cannot silently create9",Contract.fresh(old_profiles,9,1).get("code")=="MISSING_QUALITY_FAMILY_PROFILE")
	check("generation default remains historical2",Contract.fresh(profiles).contract.content_version==2)
	for key:String in ["family_policy","family_summary","workyard_policy","parcel_orientation"]:
		var tampered:Dictionary=lock.contract.duplicate(true);tampered.erase(key)
		check("saved9 strict missing policy "+key,Contract.resolve(tampered,profiles).get("code")=="FACTORY_GENERATION_POLICY_MISMATCH")
	var lost:Array=profiles.filter(func(p:Dictionary)->bool:return p.id!="r34.module.woodshop_yard_v3")
	check("saved9 cannot resolve missing machine family in current catalog",not Contract.resolve(lock.contract,lost).ok)
	var seen:Dictionary={};var visible:bool=true;var roadward:bool=true;var turns:Dictionary={}
	for seed:int in [713,2026,17,999]:
		var per_seed:Array=[]
		for z:int in range(-2,3):
			for x:int in range(-2,3):
				for parcel:Dictionary in Factory._lots(seed,Vector2i(x,z),lock.profiles,9):
					if Family.is_quality(parcel.definition_id):seen[parcel.definition_id]=true
					var primary:Dictionary=parcel.entrance_ports.filter(func(p:Dictionary)->bool:return p.id==parcel.orientation.primary_port_id)[0]
					var n:=Vector2(primary.normal.x,primary.normal.z)
					var to_road:Vector2=Vector2(parcel.orientation.target.x-parcel.origin.x,parcel.orientation.target.z-parcel.origin.z).normalized()
					visible=visible and n.dot(Vector2(24,31).normalized())>0
					roadward=roadward and n.dot(to_road)>0
					turns[parcel.quarter_turn]=true
		var coords:Array=[Vector2i.ZERO,Vector2i(0,-1)]
		for x:int in range(-2,3):
			var c:=Vector2i(x,1)
			if not Factory._lots(seed,c,lock.profiles,9).is_empty():coords.append(c);break
		for coord:Vector2i in coords:
			var started:int=Time.get_ticks_usec();var made:Dictionary=Factory.plan_region(seed,coord,profiles,lock.contract)
			check("seed%d %s complete9 plan compiles"%[seed,coord],made.ok,made.get("reason"))
			if not made.ok:continue
			var plan:Dictionary=made.plan
			per_seed.append({"coord":{"x":coord.x,"z":coord.y},"plan":plan,"prepare_usec":Time.get_ticks_usec()-started})
			check("seed%d %s never grants a machine seed or workyard stock"%[seed,coord],not plan.module_seeds.any(func(m:Dictionary)->bool:return m.purpose=="workyard" or m.definition_id in Family.IDS.machine) and plan.buildable_workyards.size()==(1 if coord==Vector2i.ZERO else 0))
			if coord==Vector2i.ZERO:
				var yard:Dictionary=plan.buildable_workyards[0]
				check("seed%d empty workyard carries two exact geometry candidates and five real approaches"%seed,yard.status=="unbuilt-space-suggestion" and yard.candidate_definitions.size()==2 and yard.service_points.size()==5 and yard.access_path_ids.size()==5 and yard.access_path_ids.all(func(id:String)->bool:return plan.paths.any(func(p:Dictionary)->bool:return p.id==id)))
				var old:Dictionary=BeforeFactory.plan_region(seed,coord,old_profiles,BeforeContract.fresh(old_profiles,8,1).contract)
				check("seed%d S01 original damaged-frame definition and source identity preserved"%seed,plan.story_sites[0].definition_id=="r34.module.fuel_woodshop" and plan.story_sites[0].source_key==old.plan.story_sites[0].source_key and plan.story_sites[0].restoration_policy==old.plan.story_sites[0].restoration_policy and plan.story_sites[0].geometry_version==old.plan.story_sites[0].geometry_version)
		per_seed.reverse()
		for row:Dictionary in per_seed:
			var c:=Vector2i(row.coord.x,row.coord.z);var repeat:Dictionary=Factory.plan_region(seed,c,profiles,lock.contract)
			check("seed%d %s reverse-order deterministic whole plan"%[seed,c],repeat.ok and Data.json_equal(row.plan,repeat.plan))
		rows.append({"seed":seed,"regions":per_seed})
	check("four bounded seeds exercise all six actual family candidates",seen.size()==6,seen.keys())
	check("all primary services face real roadward court and positive normal-camera half-space",visible and roadward)
	check("layout includes different physical orientations",turns.size()>1,turns.keys())
	check("different seeds retain different saved terrain/layout identity",Contract.digest(rows[0].regions)!=Contract.digest(rows[1].regions))
	var failed:int=checks.filter(func(r:Dictionary)->bool:return not r.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"New9 plan/contract/historical lock and source tests, not actual navigation/building/Native or camera visibility/VA proof. Facing dot is only a planned service-direction check, not occlusion/render evidence."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
