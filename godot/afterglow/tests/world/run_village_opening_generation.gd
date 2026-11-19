extends SceneTree
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Village=preload("res://scripts/world/village_opening_layout.gd")
const Landscape=preload("res://scripts/world/factory_landscape.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+": "+str(detail))
func run()->void:
	var profiles:Array=Catalog.profiles_for_content(13)
	var input:Dictionary=Contract.fresh(profiles,13,1)
	check("new opening pins explicit layout and source definitions",input.ok and input.get("contract",{}).get("village_layout_policy")==Village.POLICY,input.get("code"))
	if not input.ok:return finish()
	check("saved new opening resolves without new selection",Contract.resolve(input.contract,profiles).ok)
	var hashes:Dictionary={};var characters:Dictionary={}
	for seed:int in [713,2026,17]:
		var made:Dictionary=Generator.plan_region(seed,Vector2i.ZERO,profiles,input.contract)
		check("opening plans complete seed "+str(seed),made.ok,made if not made.ok else null)
		if not made.ok:continue
		var plan:Dictionary=made.plan
		hashes[Contract.digest(plan.parcels)]=true
		check("three real opening buildings are co-located "+str(seed),["home","woodwork","village-warehouse"].all(func(id:String)->bool:return plan.module_seeds.any(func(v:Dictionary)->bool:return v.purpose==id and v.region=="RH-HOME")))
		check("every building entrance has physical road "+str(seed),plan.parcels.all(func(p:Dictionary)->bool:return p.entrance_ports.all(func(port:Dictionary)->bool:return plan.paths.any(func(path:Dictionary)->bool:return path.id=="access:"+str(p.id)+":"+str(port.id)))))
		check("finite food water does not replace renewable raw-water source "+str(seed),plan.water_sources.size()==1 and plan.ecology_sources.size()==1 and plan.ecology_sources[0].water_quality=="raw-not-drinkable")
		check("starting forest has actual finite tree sources "+str(seed),plan.resource_sites.size()>=8,plan.resource_sites.size())
		check("future construction land remains free of generated trees "+str(seed),plan.resource_sites.all(func(v:Dictionary)->bool:return Village.clear_expansion(plan,v.position.x,v.position.z,1.0)))
		check("no gifted machine in restoration opening "+str(seed),plan.story_sites.is_empty() and plan.buildable_workyards.size()==1)
		var repeated:Dictionary=Generator.plan_region(seed,Vector2i.ZERO,profiles,input.contract)
		check("same seed and saved lock reproduce complete plan "+str(seed),repeated.ok and Data.json_equal(plan,repeated.plan))
		var nearby:Dictionary=Generator.plan_region(seed,Vector2i(1,0),profiles,input.contract)
		check("periphery plans complete "+str(seed),nearby.ok,nearby.get("code"))
		if nearby.ok:
			characters[nearby.plan.rural_character]=true
			var east:Array=plan.road_ports.filter(func(p:Dictionary)->bool:return p.direction=="east")
			var west:Array=nearby.plan.road_ports.filter(func(p:Dictionary)->bool:return p.direction=="west")
			check("adjacent owners share exact road mouth "+str(seed),east.size()==1 and west.size()==1 and east[0].position==west[0].position)
		var village:Dictionary=Generator.plan_region(seed,Vector2i(0,-1),profiles,input.contract)
		check("optional supply excursion retains one finite seed bag "+str(seed),village.ok and village.get("plan",{}).get("module_seeds",[]).any(func(v:Dictionary)->bool:return v.purpose=="store" and v.has("zone_production_additions")),village.get("code"))
	check("different seeds vary compact village geometry placement",hashes.size()>1,hashes.size())
	check("different seeds produce distinct peripheral choices",characters.size()>1,characters.keys())
	var sampled_variants:Dictionary={};var sampled_water:Dictionary={}
	for seed:int in range(1,17):
		var sampled:Dictionary=Generator.plan_region(seed,Vector2i.ZERO,profiles,input.contract)
		check("constrained opening remains viable across seed sweep "+str(seed),sampled.ok,sampled if not sampled.ok else null)
		if sampled.ok:
			sampled_variants[Village.variant(seed,Vector2i.ZERO)]=true
			sampled_water[roundi(sampled.plan.ecology_sources[0].location.x)]=true
	check("seed sweep covers all four village choices",sampled_variants.size()==4,sampled_variants.keys())
	check("seed changes raw-water approach and hauling distance",sampled_water.size()>1,sampled_water.keys())
	# Rasterize one complete starting region: geometry recipes alone cannot
	# prove that the actual authoritative half-metre terrain can be committed.
	var raster:Dictionary=Generator.draft_region(713,Vector2i.ZERO,profiles,input.contract)
	check("opening raster produces authoritative full chunk lattice",raster.ok and raster.get("chunks",{}).size()==256,raster.get("code"))
	if raster.ok:
		check("renewable raw source is an actual world entity",raster.entities.has("r34:ecology:raw-source:RH-HOME"))
		check("opening resource nodes have actual tree and drop entities",raster.plan.resource_sites.all(func(v:Dictionary)->bool:return raster.entities.has(v.id) and raster.entities.has(v.output_id)))
	var old_profiles:Array=Catalog.profiles_for_content(12)
	var old:Dictionary=Contract.fresh(old_profiles,12,1)
	check("historical content12 does not acquire village policy or definitions",old.ok and not old.contract.has("village_layout_policy") and old.profiles.all(func(v:Dictionary)->bool:return not str(v.id).begins_with("r35.")))
	if old.ok:
		var before:Dictionary=Generator.plan_region(713,Vector2i.ZERO,old_profiles,old.contract)
		check("historical opening retains its original parcels and old frame",before.ok and not before.plan.has("opening_version") and before.plan.story_sites.size()==1 and not before.plan.module_seeds.any(func(v:Dictionary)->bool:return v.purpose=="village-warehouse"),before.get("code"))
	finish()
func finish()->void:
	var failed:Array=checks.filter(func(v:Dictionary)->bool:return not v.ok)
	print(JSON.stringify({"suite":"village-opening-generation","checks":checks,"passed":checks.size()-failed.size(),"failed":failed.size()},"\t"))
	quit(0 if failed.is_empty() else 1)
