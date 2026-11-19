extends SceneTree
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const SEEDS=[713,2026,973339546,275196493,0,1,2147483646,2147483647,1034690049,553890622]
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var rows:Array=[]
	for seed:int in SEEDS:
		var source:Dictionary=Landscape.generate(seed,profiles)
		check("full two region source deterministic "+str(seed),Data.json_equal(source,Landscape.generate(seed,profiles)))
		var world:=State.new();var loaded:Dictionary=world.load_snapshot(source)
		check("actual authority 512 chunks loads "+str(seed),loaded.ok and world.chunk_keys().size()==512)
		if not loaded.ok:continue
		var low:=INF;var high:=-INF;var ports:=true;var identities:Dictionary={};var resources:=true
		for z:float in [-60.25,-40.25,-20.25,4.25,24.25,44.25,60.25]:
			for x:float in [4.25,24.25,44.25,60.25]:
				var y:float=world.surface_height(x,z);low=minf(low,y);high=maxf(high,y)
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+region)
			for parcel:Dictionary in plan.parcels:
				for port:Dictionary in parcel.entrance_ports:ports=ports and is_equal_approx(float(world.surface_height(port.position.x,port.position.z)),float(port.position.y))
			for site:Dictionary in plan.resource_sites:
				resources=resources and not identities.has(site.id);identities[site.id]=true
				resources=resources and Data.contains(world.region(region).bounds,site.position)
		check("real nonflat field and exact pad door port height "+str(seed),high-low>=1.0 and ports,{"sample_min":low,"sample_max":high,"port_height_exact":ports})
		check("persistent resource identities in actual region bounds "+str(seed),resources)
		rows.append({"seed":seed,"model":world.extension("generation:rural2").landscape_model,"sample_height_range":[low,high],"resource_ids":identities.size()})
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"seeds":SEEDS,"checks":checks,"rows":rows,"failed":failed,"scope":"C full raster/plan deterministic properties only; B complete body/use-point/NPC and OS visual gates remain separate, not new generation/layout quality acceptance"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"failed":failed,"checks":checks.size()}));quit(1 if failed else 0)
