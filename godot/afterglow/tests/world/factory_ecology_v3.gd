extends "res://tests/world/factory_country.gd"
## New content3 ecological policy with actual latest B7 production geometry;
## archived old content2 remains its own immutable profile lock.
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")
const Ecology=preload("res://scripts/world/ecology_layout.gd")
const ModuleCatalog=preload("res://scripts/modules/module_catalog.gd")

func difference(a:Variant,b:Variant,path:String="")->Dictionary:
	if Data.json_equal(a,b):return {}
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):return {"path":path+"/"+str(key),"missing":true}
			var found:Dictionary=difference(a[key],b[key],path+"/"+str(key))
			if not found.is_empty():return found
	if a is Array and b is Array and a.size()==b.size():
		for i in a.size():
			var found:Dictionary=difference(a[i],b[i],path+"/"+str(i))
			if not found.is_empty():return found
	return {"path":path,"before":a,"after":b}

func run()->void:
	var args:Array=OS.get_cmdline_user_args()
	if args.size()<2:check("explicit archived profile input is required",false);return finish()
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(args[1])))
	var native:Dictionary=JSON.parse_string(raw.payload)
	var original:Dictionary=Codec.decode_checkpoint(native.world)
	check("actual original production profile lock decodes",original.ok)
	if not original.ok:return finish()
	var old_policy:Dictionary=original.state.extensions[Factory.CONFIG_KEY]
	var profiles:Array=ModuleCatalog.profiles()
	var next:Dictionary=Contract.fresh(profiles,3)
	check("new ecological policy is explicitly content3 while default stays2",next.ok and next.contract.content_version==3 and Contract.fresh(profiles).contract.content_version==2)
	for region:String in ["RH-HOME","RH-VILLAGE"]:
		var coord:Vector2i=Vector2i.ZERO if region=="RH-HOME" else Vector2i(0,-1)
		var old:Dictionary=Factory.draft_region(713,coord,profiles,old_policy)
		check("content2 exact saved plan does not acquire groves or new cover "+region,old.ok and Data.json_equal(old.plan,original.state.extensions["generation:"+region]))
	var total_groves:int=0;var total_clusters:int=0
	for seed:int in [713,2026,17,999]:
		var source:Dictionary=Factory.generate(seed,profiles,next.contract)
		check("new actual ecological world generates "+str(seed),source.has("chunks"),source.get("reason"))
		if not source.has("chunks"):return finish()
		var world:=State.new();var loaded:Dictionary=world.load_snapshot(source)
		check("same authority accepts ecological cells and finite tree entities "+str(seed),loaded.ok)
		if not loaded.ok:return finish()
		var environment:=EnvironmentView.new();root.add_child(environment);environment.configure({"world":world})
		var row:Dictionary={"regions":{},"native_environment":environment.statistics()}
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+region)
			var groups:Dictionary={};var duplicates:bool=false;var ids:Dictionary={};var supported:bool=true;var clear:bool=true;var clusters:int=0
			for patch:Dictionary in plan.ecology.patches:
				if ids.has(patch.id):duplicates=true
				ids[patch.id]=true;groups[patch.use]=int(groups.get(patch.use,0))+1
				if patch.use not in ["activity-margin","bund-cover","contour-shoulder","lane-shoulder-group","rough-grass-island"]:continue
				clusters+=1
				var p:=Vector3(patch.position.x,patch.position.y,patch.position.z)
				var width:float=float(patch.footprint[0])*float(patch.scale)*sqrt(2.0)
				supported=supported and environment._grounded(p,Vector2.ONE*width,1)
				clear=clear and Ecology.clear_of_routes(plan,p.x,p.z,float(patch.footprint[0])*0.5)
			var groves:Array=plan.resource_sites.filter(func(s:Dictionary)->bool:return s.use=="courtyard-grove")
			for tree:Dictionary in groves:
				var p:Dictionary=tree.position
				clear=clear and Ecology.clear_of_routes(plan,p.x,p.z,2.2)
				for dx:float in [-0.35,0.0,0.35]:
					for dz:float in [-0.35,0.0,0.35]:supported=supported and world.surface_height(p.x+dx,p.z+dz)==p.y
			check("new persistent land-use groups and grove exist "+str(seed)+region,clusters>5 and groves.size()>0 and plan.ecology.layout_policy=="land-use-clusters-v3",{"groups":groups,"groves":groves.size()})
			check("new cover retains exact full support route clearance and unique IDs "+str(seed)+region,supported and clear and not duplicates,{"support":supported,"clear":clear,"duplicate":duplicates})
			total_groves+=groves.size();total_clusters+=clusters
			row.regions[region]={"uses":groups,"trees":plan.resource_sites.size(),"groves":groves.size(),"clusters":clusters,"patches":plan.ecology.patches.size()}
		var stats:Dictionary=environment.statistics()
		check("all new actual plant and image bindings resolve "+str(seed),stats.missing_materials.is_empty() and stats.missing_models.is_empty() and stats.missing_quality_images.is_empty(),stats)
		var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"r34:ecology3:"+str(seed))
		var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		check("saved content3 retains exact persistent ecology without reroll "+str(seed),decoded.ok and Data.json_equal(world.extension("generation:RH-HOME"),decoded.state.extensions["generation:RH-HOME"]) and raster_digest(decoded.state)==raster_digest(world.snapshot()),{"encoded_ok":encoded.ok,"decoded_ok":decoded.ok,"code":decoded.get("code"),"plan_difference":difference(world.extension("generation:RH-HOME"),decoded.state.extensions["generation:RH-HOME"]) if decoded.ok else {},"raster_same":decoded.ok and raster_digest(decoded.state)==raster_digest(world.snapshot())})
		costs[str(seed)]=row;environment.free()
	costs.total_new_grove_trees=total_groves;costs.total_new_cluster_patches=total_clusters
	costs.scope="actual new content3 facts and native ecological binding only; bounded visual/content workload increase disclosed, no final package/OS/normal-camera Alpha/VA/GPU/performance qualification"
	finish()
