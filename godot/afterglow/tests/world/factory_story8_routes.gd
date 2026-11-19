extends "res://tests/world/factory_mt01_source.gd"
## Real explicit fresh8 opening, original command clock and B body navigation.
## No fixture grants, capture writes, voxel shortcuts, teleport or EV accept.
var rows:Array=[]
func walk_point(built:Dictionary,at:Dictionary,label:String,zero_tool:bool=false)->bool:
	var rt:RefCounted=built.runtime;var q:RefCounted=built.services.buildings.current_space()
	var feet:Dictionary=q.standing_point(at);var from:Dictionary=Geometry.location(rt.actor("player"))
	var route:Dictionary=built.services.actions.route("player",from,feet) if not feet.is_empty() else {"ok":false,"code":"NO_BODY_SUPPORT"}
	var result:Dictionary=walk(rt,feet) if route.get("ok",false) else route
	var ok:bool=result.get("ok",false) and Geometry.point(feet).distance_to(Geometry.point(at))<0.01 and (not zero_tool or toolfree(rt))
	check(label,ok,{"from":from,"to":at,"route":route,"walk":slim(result),"sim_seconds":result.get("sim_seconds")});return ok
func bypass(built:Dictionary,site:Dictionary,label:String,zero_tool:bool=false)->bool:
	var ok:bool=true
	for i:int in site.bypass_points.size():ok=walk_point(built,site.bypass_points[i],label+" side%d"%i,zero_tool) and ok
	return walk_point(built,site.approach_after,label+" far end",zero_tool) and ok
func cells_match(live:RefCounted,cells:Array,material:int)->bool:
	return cells.all(func(c:Dictionary)->bool:return live.cell_at(c.x,c.y,c.z)==material)
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();report_path=args[0];outdir=report_path.get_base_dir();wall_started=Time.get_ticks_msec()
	spec={"max_ticks_per_seed":6000,"max_wall_msec":100000}
	var profiles:Array=Modules.generation_profiles();var lock:Dictionary=Contract.fresh(profiles,8,1)
	for seed:int in [713,2026]:
		current_seed=seed;tick_count=0;current={"visits":[],"transfers":[]}
		var started:int=Time.get_ticks_usec();var generated:Dictionary=Factory.generate(seed,profiles,lock.contract);var generation_usec:int=Time.get_ticks_usec()-started
		var made:Dictionary=Assembly.prepare(generated);var host:=Native.new()
		var built:Dictionary=host._assemble(made.capture) if made.get("ok",false) else made;host.free()
		check("explicit8 actual normal Native composes with unedited opening",built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var live:RefCounted=built.world;var plan:Dictionary=live.extension("generation:RH-HOME")
		var site:Dictionary=plan.story_entrances[0];var before:Dictionary=site.approach_before;var after:Dictionary=site.approach_after
		var spawn:Dictionary=Geometry.location(rt.actor("player"));var raster:String=raster_digest(live.snapshot())
		var q:RefCounted=built.services.buildings.current_space()
		check("one finite24-cell entrance has no EV objective or extra source",site.obstacle_cells.size()==24 and plan.regional_sites.is_empty() and not live.extension("r34:gameplay").get("regional_objectives",{}).has(site.id) and rt.stock(site.id).is_empty() and cells_match(live,site.obstacle_cells,3))
		if not walk_point(built,before,"normal zero-tool walk reaches original short entrance",true):rt.retire();continue
		check("original B swept body refuses stone short segment",not q.walk("player",before,after).ok)
		var no_tool:Dictionary=rt.capture_checkpoint();var first:Dictionary=site.obstacle_cells.filter(func(c:Dictionary)->bool:return c.y==2)[0]
		var missing:Dictionary=send(rt,"terrain","",brush(first,"dig",""))
		check("normal zero-tool digging refuses atomically without a reward",not missing.ok and Data.json_equal(no_tool,rt.capture_checkpoint()),slim(missing))
		if not bypass(built,site,"actual zero-tool full bypass",true):rt.retire();continue
		check("zero-tool bypass preserved every original stone and terrain cell",cells_match(live,site.obstacle_cells,3) and raster_digest(live.snapshot())==raster and toolfree(rt))
		var manual:String="r34:generated:RH-HOME:woodwork:stock:tools"
		if not visit(rt,manual,"original manual source remains reachable without clearing"):rt.retire();continue
		var anchor:Dictionary=plan.content_anchors[0];var source:String=str(anchor.id)+":container";var pickaxe:String=source+":tool:pickaxe"
		if not take_actual(rt,source,{},[pickaxe],"original finite normal stockyard pickaxe"):rt.retire();continue
		if not walk_point(built,before,"actual pickaxe carrier returns by B route"):rt.retire();continue
		var carried:Dictionary=rt.actor("player").pack;var original_tool:Dictionary=rt.tool(pickaxe);var initial_raster:String=raster_digest(live.snapshot())
		var digging:Dictionary=send(rt,"terrain","",brush(first,"dig",pickaxe))
		if digging.ok:rt.tick(0.1);tick_count+=1
		var cancel:Dictionary=send(rt,"cancel")
		check("real early cancellation preserves all stones, pack and tool durability",digging.ok and cancel.ok and rt.actor("player").intent==null and cells_match(live,site.obstacle_cells,3) and Data.json_equal(carried,rt.actor("player").pack) and Data.json_equal(original_tool,rt.tool(pickaxe)) and raster_digest(live.snapshot())==initial_raster,{"start":slim(digging),"cancel":slim(cancel)})
		# Highest exposed layer first, then the front-to-back x faces; all
		# actual reach/LOS and original per-cell work are checked by Runtime.
		var ordered:Array=site.obstacle_cells.duplicate(true)
		ordered.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.y>b.y if a.y!=b.y else a.x<b.x if a.x!=b.x else a.z<b.z)
		var base_stone:float=float(rt.actor("player").pack.get("stone_m3",0));var removed:int=0;var blocked:Dictionary={};var receipts:Array=[]
		for c:Dictionary in ordered:
			var command:Dictionary=send(rt,"terrain","terrain:%d:%d:%d"%[c.x,c.y,c.z],brush(c,"dig",pickaxe))
			var done:Dictionary=progress(rt,40) if command.ok else {}
			receipts.append({"cell":c,"receipt":slim(command),"finished":done.get("finished",false),"sim_seconds":done.get("sim_seconds")})
			if not command.ok or not done.get("finished",false) or live.cell_at(c.x,c.y,c.z)!=0:blocked={"cell":c,"receipt":command,"progress":done,"actor":rt.actor("player")};break
			removed+=1
		check("original pickaxe actual24 commands clear all24 physical cells",removed==24,blocked)
		check("finite real volume yields only3 cubic metres and original base stays",removed==24 and float(rt.actor("player").pack.get("stone_m3",0))-base_stone==3.0 and site.base_cells.all(func(c:Dictionary)->bool:return live.cell_at(c.x,c.y,c.z)==c.material))
		q=built.services.buildings.current_space()
		check("after actual terrain commit both direct body segment and full bypass survive",q.walk("player",before,after).ok and q.walk("player",before,site.bypass_points[0]).ok and q.walk("player",site.bypass_points[0],site.bypass_points[1]).ok and q.walk("player",site.bypass_points[1],after).ok)
		walk_point(built,after,"actual loaded carrier walks restored direct shortcut")
		walk_point(built,before,"actual loaded carrier returns across restored shortcut")
		bypass(built,site,"actual loaded bypass still usable after clearing")
		walk_point(built,spawn,"actual3m3 load returns to original spawn")
		var encoded:Dictionary=Store.encode(rt.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
		var cold_host:=Native.new();var cold:Dictionary=cold_host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;cold_host.free()
		check("whole Native canonical cold restore retains exact cells, pack and pickaxe holder",cold.get("ok",false) and raster_digest(cold.world.snapshot())==raster_digest(live.snapshot()) and Data.json_equal(cold.runtime.actor("player").pack,rt.actor("player").pack) and Data.json_equal(cold.runtime.tool(pickaxe),rt.tool(pickaxe)))
		if cold.get("ok",false):
			var cq:RefCounted=cold.services.buildings.current_space()
			check("cold restore retains original spatial identity and both body routes",Data.json_equal(cold.world.extension("generation:RH-HOME").story_entrances,JSON.parse_string(JSON.stringify(plan.story_entrances))) and cells_match(cold.world,site.obstacle_cells,0) and cq.walk("player",before,after).ok and cq.walk("player",site.bypass_points[0],site.bypass_points[1]).ok)
			var input:Dictionary=Factory.region_generation_input(cold.world,profiles);var replay:Dictionary=Factory.prepare_region_draft(cold.world,Factory.draft_region_request(input,Vector2i.ZERO),cold.world.get_revision())
			var registration:Dictionary=cold.services.modules.prepare_generation(cold.world,["RH-HOME","RH-VILLAGE"],cold.runtime.facts())
			var reread:Dictionary={"replay":slim(replay),"already_generated":replay.get("already_generated"),"world_changes":replay.get("world_changes",[]).size(),"initial_stocks":replay.get("initial_stocks",[]).size(),"registration":slim(registration),"registered_changes":registration.get("world_changes",[]).size(),"registered_stocks":registration.get("initial_stocks",[]).size(),"registered_tools":registration.get("initial_tools",[]).size(),"old_stock":rt.stock(source).items,"cold_stock":cold.runtime.stock(source).items,"raw_variant_equal":cold.runtime.stock(source).items==rt.stock(source).items,"exact_json_equal":Data.json_equal(cold.runtime.stock(source).items,rt.stock(source).items)}
			check("actual generation revisit does not regrow obstruction, refill sources or duplicate frame",replay.get("ok",false) and replay.already_generated and replay.world_changes.is_empty() and replay.initial_stocks.is_empty() and registration.get("ok",false) and registration.world_changes.is_empty() and registration.initial_stocks.is_empty() and registration.initial_tools.is_empty() and reread.exact_json_equal,reread)
			cold.runtime.retire()
		if encoded.get("ok",false):FileAccess.open(outdir+"/seed%d-story8-cleared.native.json"%seed,FileAccess.WRITE).store_string(encoded.text)
		rows.append({"seed":seed,"generation_usec":generation_usec,"site":site,"clearing":receipts,"removed":removed,"actual_stone_delta":float(rt.actor("player").pack.get("stone_m3",0))-base_stone,"ticks":tick_count,"logical_seconds":rt.clock(),"final_revision":live.get_revision(),"raster_sha256":raster_digest(live.snapshot()),"visits":current.visits,"transfers":current.transfers});rt.retire()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"post23 explicit8 real zero-tool bypass, finite normal pickaxe, cancellation,24 actual dig commands, loaded both routes and Native canonical cold/revisit only; no PCK/OS/VA/FPS/G5"},"\t",true,true));quit(1 if failed else 0)
