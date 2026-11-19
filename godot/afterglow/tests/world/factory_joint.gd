extends "res://tests/world/factory_modules.gd"
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const View=preload("res://scripts/world/world_view.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")

func peripheral(jobs:RefCounted,coord:Vector2i)->Dictionary:
	var request:Dictionary=jobs.request(coord);var result:Dictionary={}
	var deadline:int=Time.get_ticks_msec()+10000
	while request.ok and result.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;result=jobs.poll(0,true)
		if result.is_empty():
			for entry:Dictionary in jobs.status().recent:
				if entry.region_id==Factory.region_id(coord) and not entry.ok:result=entry
	return result if request.ok else request

func continuous_checks(built:Dictionary)->void:
	var world:RefCounted=built.world;var actions:RefCounted=built.services.actions
	var terrain:RefCounted=built.services.terrain
	var home:Dictionary=world.extension("generation:RH-HOME");var pair:Array=[]
	for direction:String in ["north","east","west"]:
		var port:Dictionary=home.road_ports.filter(func(p:Dictionary)->bool:return p.direction==direction)[0]
		var p:Dictionary=port.position
		var axis:=Vector2(0,-1) if direction=="north" else Vector2(1,0) if direction=="east" else Vector2(-1,0)
		var a:Dictionary=_location(world,p.x-axis.x*0.35,p.z-axis.y*0.35)
		var b:Dictionary=_location(world,p.x+axis.x*0.35,p.z+axis.y*0.35)
		var forward:Dictionary=actions.move_step("player",a,b.duplicate(true))
		var backward:Dictionary=actions.move_step("player",b,a.duplicate(true))
		check("actual B swept body crosses both ways "+direction,forward.ok and backward.ok,{"forward":forward,"backward":backward})
		var near:Dictionary=_location(world,p.x-axis.x*2,p.z-axis.y*2)
		var far:Dictionary=_location(world,p.x+axis.x*2,p.z+axis.y*2)
		# Terrain centre height can be half a step below the body's highest
		# support probe. A route starts from actual feet, never a raw cell top.
		var near_feet:Dictionary=built.services.buildings.current_space().standing_point(near)
		var far_feet:Dictionary=built.services.buildings.current_space().standing_point(far)
		var route:Dictionary=actions.route("player",near_feet,far_feet) if not near_feet.is_empty() and not far_feet.is_empty() else {"ok":false,"reason":"no actual body feet"}
		var support:Dictionary={"near":near,"far":far,"near_standing":built.services.buildings.current_space().standing_point(near),"far_standing":built.services.buildings.current_space().standing_point(far),"reason":route.get("reason")}
		for label:String in ["near","far"]:
			var at:Dictionary=support[label];var values:Array=[]
			for dx:float in [-0.26,0.0,0.26]:
				for dz:float in [-0.26,0.0,0.26]:values.append(world.surface_height(at.x+dx,at.z+dz))
			support[label+"_probes"]=values
		check("actual B navigation uses shared factory face "+direction,route.ok and not route.steps.is_empty(),support if not route.ok else null)
		var cell:=Vector3i(floori(b.x*2),roundi(b.y*2)-1,floori(b.z*2))
		var contact:Dictionary=terrain._cell_contact(world,Geometry.point(a)+Vector3(0,1.2,0),cell,true,a,str(b.regionId))
		check("actual terrain face contact keeps LOS and cell identity "+direction,contact.ok and contact.target_id=="terrain:%d:%d:%d"%[cell.x,cell.y,cell.z] and contact.world_revision==world.get_revision(),contact)
		if direction=="north":pair=[a,b]
	# A different physical edge point is deliberately outside every authored
	# exit. This would have hit B's old factory portal fallback.
	var a:Dictionary=_location(world,8.25,0.35);var b:Dictionary=_location(world,8.25,-0.35)
	var outside:Dictionary=actions.move_step("player",a,b.duplicate(true))
	check("real body crosses ordinary supported factory edge away from exits",outside.ok,outside)
	check("only new and existing continuous generators share outdoor semantics",Data.is_continuous_outdoor_generator(Factory.VERSION) and not Data.is_continuous_outdoor_generator("rural-1") and not Data.is_continuous_outdoor_generator("r3-town-5"))
	if pair.is_empty():return
	a=pair[0];b=pair[1]
	var key:String=Data.key(Data.cell_chunk(Vector3i(floori(b.x*2),floori((b.y+1.2)*2),floori(b.z*2)),16))
	var cold:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
	check("prepared factory view rejects nonresident swept body before commit",cold.ok and cold.view.continuous_outdoor_step(a,b).get("code")=="UNLOADED_CELL" and world.continuous_outdoor_step(a,b).ok)
	if cold.ok:world.commit_prepared(cold.capability)
	var ha:Dictionary=a.duplicate(true);ha.y+=1.2
	var hb:Dictionary=b.duplicate(true);hb.y+=1.2
	check("actual B movement and contact reject unloaded factory body space",actions.move_step("player",a,b.duplicate(true)).get("code")=="UNLOADED_CELL" and world.continuous_outdoor_contact(ha,hb).get("code")=="UNLOADED_CELL")
	var warm:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],world.get_revision())
	if warm.ok:world.commit_prepared(warm.capability)
	check("warm current facts immediately restore actual body route",warm.ok and actions.move_step("player",a,b.duplicate(true)).ok)
	var source:Dictionary=world.snapshot();var missing:Dictionary=source.duplicate(true);missing.chunks.erase(key)
	var incomplete:=State.new();var loaded:Dictionary=incomplete.load_snapshot(missing)
	check("factory identity cannot hide a missing actual chunk",loaded.ok and incomplete.continuous_outdoor_step(a,b).get("code")=="UNKNOWN_CELL")
	check("complete-region predicate rejects missing lattice and unknown identity",not incomplete.region_is_resident(str(b.regionId)) and not world.region_is_resident("missing") and world.region_is_resident("RH-HOME"))
	var ungenerated:Dictionary=source.duplicate(true);ungenerated.regions["RH-HOME"].generated=false
	check("region metadata cannot mark ungenerated region detailed",not View.new(ungenerated).region_is_resident("RH-HOME"))
	var partial:Dictionary=source.duplicate(true);partial.chunks[key].generated=false
	check("complete-region predicate rejects ungenerated lattice metadata",not View.new(partial).region_is_resident(str(b.regionId)))
	partial=source.duplicate(true);partial.chunks[key].resident=false
	check("complete-region predicate rejects any cold chunk without copying cells",not View.new(partial).region_is_resident(str(b.regionId)))
	var gap:Dictionary=source.duplicate(true);gap.regions["RH-VILLAGE"].bounds.max.z=-0.0001
	var separated:=State.new();loaded=separated.load_snapshot(gap)
	check("factory submillimetre gap remains closed",loaded.ok and separated.continuous_outdoor_step(a,b).get("code")=="NOT_ADJACENT")
	var wrong:Dictionary=b.duplicate(true);wrong.regionId="RH-HOME"
	check("factory location cannot forge neighboring partition",world.continuous_outdoor_step(a,wrong).get("code")=="REGION_MISMATCH")
	wrong=a.duplicate(true);wrong.buildingId="indoor-fixture"
	check("factory identity does not open indoor bypass",not world.continuous_outdoor_step(wrong,b).ok)
	var legacy:=State.new();loaded=legacy.load_snapshot(Rural.generate())
	check("actual old rural world keeps authored portal contract",loaded.ok and legacy.continuous_outdoor_neighbors("RH-HOME").is_empty() and not legacy.continuous_outdoor_step(a,b).ok)
	check("same metadata predicate supports complete old rural region without opening its portals",legacy.region_is_resident("RH-HOME"))
	var old_city:Dictionary=source.duplicate(true);old_city.generatorVersion="r3-town-5"
	var city_view:=View.new(old_city)
	check("old city version gate remains closed even with adjacent rural geometry fixture",city_view.continuous_outdoor_neighbors("RH-HOME").is_empty() and not city_view.continuous_outdoor_step(a,b).ok)

func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var source:Dictionary=Factory.generate(713,profiles)
	check("real R34 generator uses B production profiles",source.has("chunks"),source.get("reason"))
	if not source.has("chunks"):return finish()
	var start:int=Time.get_ticks_usec();var assembled:Dictionary=Assembly.prepare(source)
	check("actual A B E opening assembly accepts C terrain",assembled.ok,assembled.get("reason"))
	if not assembled.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(assembled.capture);native.free()
	check("real Native offscreen reassembly configures all official services",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var world:RefCounted=built.world;var runtime:RefCounted=built.runtime
	var actors:Array=runtime.facts().actors;var inside:bool=true;var separated:bool=true
	for a:Dictionary in actors:
		inside=inside and world.region_at(a).get("id")==a.regionId
		for b:Dictionary in actors:
			if a.id!=b.id:separated=separated and Geometry.point(a).distance_to(Geometry.point(b))>=2.0
	check("all actual starting actors belong to containing region and are two metres apart",inside and separated,actors)
	var building:RefCounted=built.services.buildings;var query:RefCounted=building.current_space()
	var modules:Dictionary=world.extension("r34:modules");var blocked:Array=[]
	for module:Dictionary in modules.instances:
		var definition:Dictionary=Modules.definition(module.definition_id)
		var ports:Array=preload("res://scripts/modules/module_geometry.gd").ports(module,definition)
		for port:Dictionary in ports:
			for at:Dictionary in port.use_points:
				if query.standing_point(at).is_empty():blocked.append({"module":module.id,"port":port.id,"at":at})
	check("actual module geometry leaves every real service point standing",blocked.is_empty(),blocked)
	var stock_ids:Dictionary={};var duplicate:bool=false
	for stock:Dictionary in runtime.facts().stocks:
		if stock_ids.has(stock.id):duplicate=true
		stock_ids[stock.id]=true
	check("single registration keeps all real stock IDs unique",not duplicate)
	var replay:Dictionary=Modules.new().prepare_generation(world)
	check("actual B registration receipt never reapplies initial content",replay.ok and replay.initial_stocks.is_empty() and replay.initial_tools.is_empty() and replay.initial_records.is_empty(),replay.get("reason"))
	var jobs:=Scheduler.new();jobs.attach(runtime,building,34,built.services.modules)
	var original:Dictionary=world.snapshot()
	for coord:Vector2i in [Vector2i(1,0),Vector2i(-1,0)]:
		var result:Dictionary=await peripheral(jobs,coord)
		check("real A threaded C B registration commits peripheral region "+str(coord),result.get("ok",false),result)
		if not result.get("ok",false):jobs.shutdown();return finish()
	var repeat:Dictionary=jobs.request(Vector2i(1,0))
	check("official scheduler revisits do not replay generated contents",repeat.get("code")=="ALREADY_GENERATED" and Modules.new().prepare_generation(world).initial_stocks.is_empty())
	jobs.shutdown()
	var unchanged:bool=true
	for key:String in original.chunks:unchanged=unchanged and Data.json_equal(original.chunks[key],world.chunk(key))
	check("official peripheral integration preserves all explored initial cells",unchanged)
	continuous_checks(built)
	var save:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(save.text) if save.ok else save
	check("whole runtime native checkpoint decodes complete C B E world",decoded.ok,decoded.get("reason"))
	if decoded.ok:
		native=Native.new();var cold:Dictionary=native._assemble(decoded.capture);native.free()
		check("actual cold Native reassembly preserves module sources and edited world authority",cold.ok,cold.get("reason"))
		if cold.ok:check("cold restore retains actual cell raster and module source receipts",raster_digest(cold.world.snapshot())==raster_digest(world.snapshot()) and Data.json_equal(cold.world.extension("r34:modules").source_receipts,world.extension("r34:modules").source_receipts))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and save.ok:FileAccess.open(args[0].get_base_dir()+"/actual-r34-opening.native.json",FileAccess.WRITE).store_string(save.text)
	costs={"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"scheduler":jobs.status(),"source_profiles_sha256":world.extension(Factory.CONFIG_KEY).profile_sha256,"raster_sha256":raster_digest(world.snapshot())}
	finish()
