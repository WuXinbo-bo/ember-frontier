extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Chapter=preload("res://scripts/modules/village_chapter_catalog.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Village=preload("res://scripts/world/village_opening_layout.gd")
const Geometry=preload("res://scripts/modules/village_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Contact=preload("res://scripts/modules/module_contact.gd")
const StockRoute=preload("res://scripts/actions/zone_supply_executor.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const Progression=preload("res://scripts/runtime/village_progression.gd")
const STARTER="r34:generated:RH-HOME:woodwork:stock:tools"
const SALVAGE="RH-HOME:stockyard-content:container"
const HOME="RH-HOME"
var checks:int=0
var failed:int=0

func _initialize()->void:call_deferred("run")

func check(label:String,ok:bool,detail:Variant=null)->bool:
	checks+=1
	if not ok:failed+=1;print("FAIL ",label," ",detail)
	return ok

func run()->void:
	var current:=Assembly.generation_profiles(20)
	if not check("content20 geometry is available",current.ok,current.get("code")):return finish()
	var old:=Assembly.generation_profiles(19)
	check("old generation retains old geometry inputs",old.ok and old.profiles.all(func(p:Dictionary)->bool:return not str(p.id).begins_with(Chapter.PREFIX)))
	for family:String in ["home","warehouse","workshop","sawmill"]:
		var d:=Catalog.definition(Chapter.PREFIX+family)
		check("opening family has a physical silhouette marker "+family,Geometry.parts(d).any(func(p:Dictionary)->bool:return p.id=="chapter-service-character"))
	var args:=OS.get_cmdline_user_args()
	for seed:int in [int(args[0].trim_prefix("--seed="))] if not args.is_empty() else [713,1597]:
		var generated:=Assembly.generate(seed,current.profiles,20)
		var opening:=Assembly.prepare(generated)
		if not check("normal generation and content registration "+str(seed),opening.ok,opening.get("code")):continue
		var capture:Dictionary=opening.capture
		var region:Dictionary=capture.world.extensions["generation:RH-HOME"]
		var starter:=Draft.find(capture.facts.stocks,STARTER)
		var items:Dictionary=starter.get("items",{})
		check("starter has only potato seed and one bucket for growing "+str(seed),starter.get("searched",false) and starter.get("owner")=="home-residents" and items.get("r34:potato_seed",0)==2 and items.get("r34:water_bucket",0)==1 and items.get("r34:bean_seed",0)==0 and items.get("r34:rice_seed",0)==0,starter)
		var salvage:=Draft.find(capture.facts.stocks,SALVAGE)
		var receipt_count:int=0
		for receipt:Dictionary in capture.world.extensions["r34:modules"].source_receipts.values():
			if receipt.stock_ids.has(SALVAGE):receipt_count+=1
		check("salvage is finite and registered once "+str(seed),receipt_count==1 and salvage.get("items",{}).get("scrap",0)==12 and salvage.get("items",{}).get("cloth",0)==6 and salvage.get("items",{}).get("tool_handle",0)==1 and salvage.get("items",{}).get("r34:salvaged_drive_unit",0)==1,salvage)
		var water:Dictionary=region.ecology_sources[0] if not region.ecology_sources.is_empty() else {}
		if not check("raw well has one supported source clear of expansion "+str(seed),region.ecology_sources.size()==1 and water.initial_units==8 and water.recharge_seconds==90 and water.water_quality=="raw-not-drinkable" and Village.clear_expansion(region,water.location.x,water.location.z,1.4),water):continue
		var state:Dictionary=capture.world.extensions["r34:modules"]
		var workshop:=Draft.find(state.instances,"r34:generated:RH-HOME:woodwork")
		var warehouse:=Draft.find(state.instances,"r34:generated:RH-HOME:village-warehouse")
		var mill:=Draft.find(state.instances,"RH-HOME:woodshop-old-frame")
		check("workshop and damaged buildings are known chapter targets "+str(seed),workshop.get("definition_id")==Chapter.WORKSHOP and warehouse.get("definition_id")==Chapter.WAREHOUSE and warehouse.get("status")=="damaged" and mill.get("status")=="damaged" and mill.get("discovered",false))
		check_home_routes(capture,seed,region,water,[workshop,warehouse,mill])
	finish()

func check_home_routes(capture:Dictionary,seed:int,region:Dictionary,water:Dictionary,modules:Array)->void:
	var host:=Native.new()
	var loaded:Dictionary=host._assemble(capture)
	if not check("mount unmodified opening for route proof "+str(seed),loaded.ok,loaded.get("code")):
		host.free();return
	var runtime:RefCounted=loaded.runtime
	var actions:RefCounted=loaded.services.actions
	var query:RefCounted=loaded.services.buildings.current_space()
	var player:Dictionary=runtime.actor("player")
	var origin:=G.location(player)
	var draft:=Draft.new(actions.context)
	for stock_id:String in [STARTER,SALVAGE]:
		var stock:Dictionary=runtime.stock(stock_id)
		var path:=StockRoute.stock_path(actions,draft,player,stock,"search" if stock_id==SALVAGE else "stock")
		check("local inventory access %d %s"%[seed,stock_id],local_path(path),{"path":path,"location":stock.get("location")})
	for module:Dictionary in modules:
		var points:=Contact.points(query,origin,module,Contact.DISTANCE,true)
		check("local building work access %d %s"%[seed,module.get("id","")],local_points(actions,origin,points),module.get("position"))
	var station:=Progression.radio_station(loaded.world)
	var bench:Dictionary=loaded.services.buildings.instance(station)
	check("local radio workbench access "+str(seed),not bench.is_empty() and local_points(actions,origin,query.use_points(bench)),station)
	check("local well approach "+str(seed),local_points(actions,origin,[water.use_point]),water.use_point)
	# Seed terrain may reject the authored courtyard sockets. The authority
	# harvests whichever real local tree has both a body and a drop approach.
	var near_trees:Array=region.resource_sites.filter(func(site:Dictionary)->bool:return site.get("kind")=="tree")
	near_trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(origin).distance_squared_to(G.point(a.position))<G.point(origin).distance_squared_to(G.point(b.position)))
	var reachable_tree:String=""
	for site:Dictionary in near_trees:
		if local_points(actions,origin,Interaction.tree_points(query,loaded.world.entity(str(site.id)))):reachable_tree=str(site.id);break
	check("local forest has an accessible trunk and drop surface "+str(seed),not reachable_tree.is_empty(),near_trees.size())
	var field_points:Array=[]
	for land:Dictionary in region.landforms:
		if land.use!="field":continue
		for fraction:Vector2 in [Vector2(.5,.5),Vector2(.25,.25),Vector2(.75,.25)]:
			var at:Dictionary={"regionId":HOME,"buildingId":null,"storeyId":null,"x":lerpf(land.xz[0],land.xz[2],fraction.x),"z":lerpf(land.xz[1],land.xz[3],fraction.y),"y":land.height}
			var feet:Dictionary=query.standing_point(at)
			if not feet.is_empty():field_points.append(feet)
	check("local field access "+str(seed),local_points(actions,origin,field_points),field_points)
	runtime.retire()
	host.free()

func local_points(actions:RefCounted,origin:Dictionary,points:Array)->bool:
	for at:Dictionary in points:
		if at.get("regionId")==HOME and local_path(actions.route("player",origin,at)):return true
	return false

func local_path(path:Dictionary)->bool:
	if not path.get("ok",false):return false
	for step:Dictionary in path.get("steps",[]):
		if step.kind=="cross-region" or step.get("to",{}).get("regionId",HOME)!=HOME:return false
	return true

func finish()->void:
	print("VILLAGE_CHAPTER_GENERATION ",checks-failed,"/",checks)
	quit(0 if failed==0 else 1)
