extends "res://tests/world/factory_mt01_source.gd"
## Actual fresh Native/Runtime and B body navigation. No grants, relocation,
## fixture economics or writing capture/world facts. B owns restore economics.
const Shape=preload("res://scripts/modules/module_geometry.gd")
var story_rows:Array=[]
func rectangle_supported(live:RefCounted,r:Array,y:float)->bool:
	var lower:int=roundi(y*2)-1
	for z:int in range(floori(r[1]*2),ceili(r[3]*2)):
		for x:int in range(floori(r[0]*2),ceili(r[2]*2)):
			if not live.is_cell_known(x,lower,z) or not live.is_cell_resident(x,lower,z) or live.cell_at(x,lower,z)==0:return false
			if live.cell_at(x,lower+1,z)!=0:return false
	return true
func reach_point(built:Dictionary,at:Dictionary,label:String)->Dictionary:
	var rt:RefCounted=built.runtime;var from:Dictionary=Geometry.location(rt.actor("player"))
	var feet:Dictionary=built.services.buildings.current_space().standing_point(at)
	var route:Dictionary=built.services.actions.route("player",from,feet) if not feet.is_empty() else {"ok":false,"reason":"NO_BODY_SUPPORT"}
	var traveled:Dictionary=walk(rt,feet) if route.get("ok",false) else route
	check(label,traveled.get("ok",false) and Geometry.point(feet).distance_to(Geometry.point(at))<0.01 and toolfree(rt),{"from":from,"to":at,"feet":feet,"route":route,"walk":slim(traveled),"sim_seconds":traveled.get("sim_seconds")})
	return traveled
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();report_path=args[0];outdir=report_path.get_base_dir();wall_started=Time.get_ticks_msec()
	spec={"max_ticks_per_seed":6500,"max_wall_msec":100000}
	var profiles:Array=Modules.generation_profiles();var lock:Dictionary=Contract.fresh(profiles,7,1)
	for seed:int in [713,2026]:
		current_seed=seed;tick_count=0;current={"visits":[],"transfers":[]}
		var start_usec:int=Time.get_ticks_usec();var generated:Dictionary=Factory.generate(seed,profiles,lock.contract)
		var prepare_usec:int=Time.get_ticks_usec()-start_usec
		var made:Dictionary=Assembly.prepare(generated)
		var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.get("ok",false) else made;host.free()
		check("content7 actual normal Native composes without any capture edit",built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var live:RefCounted=built.world
		var plan:Dictionary=live.extension("generation:RH-HOME");var village:Dictionary=live.extension("generation:RH-VILLAGE")
		var site:Dictionary=plan.story_sites[0];var approach:Dictionary=village.story_approaches[0]
		var modules:RefCounted=built.services.modules;var frame:Dictionary=modules.instance(site.id)
		var raster:String=raster_digest(live.snapshot());var original:Dictionary=rt.capture_checkpoint()
		var spawn:Dictionary=Geometry.location(rt.actor("player"))
		check("actual source is one damaged old frame, manual remains, zero carried tool",frame.id==site.id and frame.status=="damaged" and frame.hp==120 and frame.stock_refs.values().all(func(id:String)->bool:return rt.stock(id).items.is_empty()) and not live.entity("r34:generated:RH-HOME:woodwork").is_empty() and toolfree(rt))
		check("complete actual foundation supports all half-metre cells",rectangle_supported(live,site.foundation_xz,site.position.y),site.foundation_xz)
		for port:Dictionary in Shape.ports(frame,modules.definition(frame.definition_id)):
			var point:Dictionary=port.use_points[0]
			var radius:float=float(port.clearance.radius)
			check("full service support "+str(port.id),rectangle_supported(live,[point.x-radius,point.z-radius,point.x+radius,point.z+radius],point.y),point)
			reach_point(built,point,"actual zero-tool walk to frame "+str(port.id))
		var loop:Dictionary=plan.paths.filter(func(p:Dictionary)->bool:return p.id==site.side_route_ids[0])[0]
		for i:int in loop.points.size():
			var at:Dictionary=loop.points[i].duplicate(true);at.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
			reach_point(built,at,"actual walk frame side-loop corner%d"%i)
		var manual:Dictionary=rt.stock("r34:generated:RH-HOME:woodwork:stock:tools").location
		reach_point(built,manual,"original manual source remains reachable after frame")
		reach_point(built,approach.front_point,"actual inter-region zero-tool route to empty storefront")
		var store_id:String=approach.stock_id;var initial_store:Dictionary=rt.stock(store_id)
		var before_front:Dictionary=rt.capture_checkpoint()
		var front_search:Dictionary=send(rt,"search",store_id,{"direct":true})
		check("empty front cannot search original rear through building and rejects atomically",not front_search.ok and Data.json_equal(before_front,rt.capture_checkpoint()),slim(front_search))
		var source_count:int=rt.facts().stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==approach.module_id).size()
		check("front hint and rear have one original stock, no front grant",source_count==1 and not initial_store.searched and Geometry.point(initial_store.location).distance_to(Geometry.point(approach.rear_point))<0.001 and live.entity(approach.module_id).data.has("story_front_point"))
		var supply_loop:Dictionary=village.paths.filter(func(p:Dictionary)->bool:return p.id==approach.side_route_ids[0])[0]
		for i:int in supply_loop.points.size():
			var at:Dictionary=supply_loop.points[i].duplicate(true);at.merge({"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null},true)
			reach_point(built,at,"actual walk store side-loop corner%d"%i)
		reach_point(built,initial_store.location,"actual walk reaches original supplies from rear")
		var searched:Dictionary=send(rt,"search",store_id);var completed:Dictionary=progress(rt,120) if searched.ok else {}
		check("rear actual search consumes real work with one stock, unchanged items",searched.ok and completed.get("finished",false) and rt.stock(store_id).searched and rt.stock(store_id).items==initial_store.items,slim(searched))
		var read:Dictionary=send(rt,"settlement.read_story","",{"story_id":"ST03","source_id":store_id})
		check("rear actual original ST03 route record remains readable",read.ok,slim(read))
		var taken:Dictionary=send(rt,"take",store_id,{"items":{"water":1}})
		check("rear take debits exactly one finite original water",taken.ok and rt.stock(store_id).items.get("water",0)==initial_store.items.get("water",0)-1 and rt.actor("player").pack.get("water",0)==2,slim(taken))
		reach_point(built,spawn,"actual loaded inter-region return to original spawn")
		check("all actual route commands preserve every original terrain cell and no tools granted",raster_digest(live.snapshot())==raster and toolfree(rt))
		var encoded:Dictionary=Store.encode(rt.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
		var host2:=Native.new();var restored:Dictionary=host2._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host2.free()
		var final_frame:Dictionary=modules.instance(site.id)
		var recovery:Dictionary={"mounted":restored.get("ok",false)}
		if recovery.mounted:
			recovery.sites=Data.json_equal(restored.world.extension("generation:RH-HOME").story_sites,JSON.parse_string(JSON.stringify(plan.story_sites,"",true,true)))
			recovery.frame=Data.json_equal(restored.services.modules.instance(site.id),JSON.parse_string(JSON.stringify(final_frame,"",true,true)))
			recovery.searched=restored.runtime.stock(store_id).searched
			recovery.stock=Data.json_equal(restored.runtime.stock(store_id).items,rt.stock(store_id).items)
		check("real Native save and cold mount retains exact site/module/source identity",recovery.values().all(func(v:Variant)->bool:return v==true),recovery)
		if restored.get("ok",false):
			var again:Dictionary=restored.services.modules.prepare_generation(restored.world,["RH-HOME","RH-VILLAGE"],restored.runtime.facts())
			check("cold revisit does not respawn original frame, source, or materials",again.get("ok",false) and again.world_changes.is_empty() and again.initial_stocks.is_empty())
			restored.runtime.retire()
		if encoded.get("ok",false):FileAccess.open(outdir+"/seed%d-story7-routes.native.json"%seed,FileAccess.WRITE).store_string(encoded.text)
		story_rows.append({"seed":seed,"prepare_generation_usec":prepare_usec,"source":site,"approach":approach,"initial_spawn":spawn,"original_world_revision":original.world.revision,"final_world_revision":live.get_revision(),"raster_sha256":raster,"final_time":rt.clock(),"ticks":tick_count,"scope":"C real original zero-tool normal paths, source search/read/take/loaded return and Native restore only; B fixture economics are separate"})
		rt.retire()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":story_rows,"scope":"source candidate headless C actual routes; no PCK/OS/VA/FPS/G5 or full restoration/migration economy qualification"},"\t",true,true));quit(1 if failed else 0)
