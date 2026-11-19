extends "res://tests/world/factory_normal_path.gd"
## Tests only. Formal C4/story1 normal Assembly and actual command/clock/B paths.
## No capture edits, grants, teleport, permission changes or second simulator.
var report_path:String
var outdir:String
var input_path:String
var spec:Dictionary={}
var seed_rows:Array=[]
var current:Dictionary={}
var current_seed:int=-1
var tick_count:int=0
var wall_started:int

func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":("seed%d: "%current_seed if current_seed>=0 else "")+label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+str(checks[-1]))

func progress(runtime:RefCounted,limit:int=1200)->Dictionary:
	var start:float=runtime.clock();var steps:int=0
	while runtime.actor("player").get("intent")!=null and steps<limit and tick_count<int(spec.max_ticks_per_seed) and Time.get_ticks_msec()-wall_started<int(spec.max_wall_msec):
		runtime.tick(0.1);steps+=1;tick_count+=1
	return {"finished":runtime.actor("player").get("intent")==null,"iterations":steps,"sim_seconds":runtime.clock()-start,"actor":runtime.actor("player")}

func care(runtime:RefCounted)->bool:
	for item:Array in [["hunger","food","eat"],["thirst","water","drink"]]:
		var actor:Dictionary=runtime.actor("player")
		if float(actor[item[0]])<40.0 and float(actor.pack.get(item[1],0))>=1:
			var used:Dictionary=send(runtime,item[2]);var done:Dictionary=progress(runtime,40) if used.ok else {}
			if not used.ok or not done.get("finished",false):return false
	if float(runtime.actor("player").stamina)<50.0:
		var rested:Dictionary=send(runtime,"rest");var done:Dictionary=progress(runtime,180) if rested.ok else {}
		if not rested.ok or not done.get("finished",false):return false
	return true

static func slim(receipt:Dictionary)->Dictionary:
	var row:Dictionary={}
	for key:String in ["ok","code","reason"]:
		if receipt.has(key):row[key]=receipt[key]
	return row

func visit(runtime:RefCounted,id:String,label:String)->bool:
	var stock:Dictionary=runtime.stock(id);var tries:Array=[]
	if stock.is_empty():check(label+" exists for actual visit",false,id);return false
	var candidates:Array=[]
	for offset:Vector2 in [Vector2.ZERO,Vector2(0,-1.2),Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,1.2)]:
		var at:Dictionary=stock.location.duplicate(true);at.x+=offset.x;at.z+=offset.y;candidates.append(at)
	for at:Dictionary in candidates:
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if feet.is_empty():tries.append({"point":at,"reason":"no B standing body"});continue
		var from:Dictionary=Geometry.location(runtime.actor("player"))
		var route:Dictionary=runtime._services.actions.route("player",from,feet)
		if not route.ok:tries.append({"point":feet,"route":slim(route)});continue
		var walked:Dictionary=walk(runtime,feet)
		var reach:Variant=runtime._services.production.reach("player",id,runtime.stock(id),"search")
		tries.append({"point":feet,"from":from,"route":route,"walk":slim(walked),"sim_seconds":walked.get("sim_seconds"),"contact_permission_reason":reach})
		if walked.get("ok",false) and reach==null:
			current.visits.append({"label":label,"stock_id":id,"stock_owner":stock.get("owner"),"initial_searched":stock.get("searched"),"attempts":tries,"pack_on_arrival":runtime.actor("player").pack,"actual_feet":Geometry.location(runtime.actor("player"))})
			check(label+" real B route, body travel and live contact/owner permission",true)
			return true
	current.visits.append({"label":label,"stock_id":id,"attempts":tries})
	check(label+" real B route, body travel and live contact/owner permission",false,tries)
	return false

func take_actual(runtime:RefCounted,id:String,items:Dictionary,tools:Array,label:String)->bool:
	if not care(runtime) or not visit(runtime,id,label):return false
	var search:Dictionary={"ok":true,"code":"ORIGINALLY_SEARCHED"}
	if not runtime.stock(id).get("searched",false):
		search=send(runtime,"search",id)
		if search.ok:
			var done:Dictionary=progress(runtime,100)
			if not done.finished:search={"ok":false,"code":"SEARCH_NOT_FINISHED","progress":done}
	check(label+" actual search state and authorization",search.ok and runtime.stock(id).get("searched",false),slim(search))
	if not search.ok:return false
	var before:Dictionary=runtime.stock(id);var pack:Dictionary=runtime.actor("player").pack
	var availability:Dictionary=runtime.availability({"actor_id":"player","kind":"take","target_id":id,"payload":{"items":items,"tool_ids":tools}})
	var taken:Dictionary=send(runtime,"take",id,{"items":items,"tool_ids":tools}) if availability.ok else availability
	var exact:bool=taken.ok
	for item:String in items:
		exact=exact and float(runtime.stock(id).items.get(item,0))==float(before.items.get(item,0))-float(items[item]) and float(runtime.actor("player").pack.get(item,0))==float(pack.get(item,0))+float(items[item])
	for tool:String in tools:exact=exact and runtime.tool(tool).get("holderId")=="pack:player"
	current.transfers.append({"label":label,"stock_id":id,"items":items,"tools":tools,"before_items":before.items,"after_items":runtime.stock(id).items,"availability":slim(availability),"receipt":slim(taken),"exact":exact})
	check(label+" actual finite item/tool transfer exactly once",exact,slim(taken))
	return exact

func source_row(runtime:RefCounted,id:String,minimum:Dictionary,label:String)->void:
	var stock:Dictionary=runtime.stock(id);var enough:bool=not stock.is_empty()
	for item:String in minimum:enough=enough and float(stock.get("items",{}).get(item,0))>=float(minimum[item])
	current.sources.append({"label":label,"stock":stock,"minimum":minimum,"generated_and_sufficient":enough,"classification":"finite historical stock registered once; not a recurring grant"})
	check(label+" generated stock and quantitative bridge",enough,id)

func work(runtime:RefCounted,station:String,recipe:String,tools:Array,repair:String="")->bool:
	if not care(runtime):return false
	var payload:Dictionary={"direct":false,"recipe_id":recipe,"source_id":"pack:player","output_id":"pack:player","tool_ids":tools}
	if not repair.is_empty():payload.repair_tool_id=repair
	var started:Dictionary=send(runtime,"craft",station,payload)
	var done:Dictionary=progress(runtime,1000) if started.ok else {}
	current.operations.append({"recipe":recipe,"start":slim(started),"finished":done.get("finished",false),"sim_seconds":done.get("sim_seconds"),"actor":runtime.actor("player")})
	check("normal actual work "+recipe,started.ok and done.get("finished",false),slim(started))
	return started.ok and done.get("finished",false)

func forest(runtime:RefCounted,axe:String)->bool:
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	# Distance orders a finite search only; no reachability claim uses it.
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var felled:int=0;var attempts:Array=[];var base_logs:float=float(runtime.actor("player").pack.get("log",0))
	for tree:Dictionary in trees.slice(0,12):
		if felled==3:break
		if not care(runtime):break
		var request:Dictionary={"actor_id":"player","kind":"harvest","target_id":tree.id,"payload":{"direct":false,"tool_ids":[axe]}}
		var available:Dictionary=runtime.availability(request)
		if not available.ok:attempts.append({"tree_id":tree.id,"availability":slim(available)});continue
		var output:String=tree.data.outputId;var empty_before:bool=runtime.stock(output).items.is_empty()
		var command:Dictionary=send(runtime,"harvest",tree.id,request.payload)
		var initial_intent:Variant=runtime.actor("player").get("intent")
		var done:Dictionary=progress(runtime,1200) if command.ok else {}
		var actual:bool=command.ok and done.get("finished",false) and runtime.world.entity(tree.id).data.harvest.phase=="stump" and runtime.stock(output).items.get("log",0)==3 and empty_before
		attempts.append({"tree_id":tree.id,"position":tree.position,"output_id":output,"availability":slim(available),"command":slim(command),"actual_approach_intent":initial_intent,"finished":done.get("finished",false),"sim_seconds":done.get("sim_seconds"),"actual_finite_yield":actual})
		check("real B approach and old axe fell actual tree "+str(felled+1),actual,slim(command))
		if not actual:break
		if not take_actual(runtime,output,{"log":3},[],"real finite tree drops"):break
		felled+=1
	current.forest={"standing_initially":trees.size(),"attempts":attempts,"felled":felled,"logs_carried":float(runtime.actor("player").pack.get("log",0))-base_logs,"classification":"finite persistent trees; stumps/drops do not regrow on revisit"}
	check("three actually reached and harvested trees provide nine carried logs",felled==3 and float(runtime.actor("player").pack.get("log",0))-base_logs==9,current.forest.get("logs_carried"))
	return felled==3

func terrain_sample(runtime:RefCounted,tool:String,stone:bool)->bool:
	var candidates:Array=[]
	var plan:Dictionary=runtime.world.extension("generation:RH-HOME")
	if stone:
		var bounds:Array=plan.source_nodes[0].xz
		for z:float in [float(bounds[1])+1.75,float(bounds[3])-2.25]:
			for x:float in [float(bounds[0])+1.75,float(bounds[2])-2.25]:candidates.append(Vector2(x,z))
	else:
		for z:float in [20.25,24.25,28.25]:
			for x:float in [36.25,40.25,44.25]:candidates.append(Vector2(x,z))
	var failures:Array=[]
	for point:Vector2 in candidates:
		var top:float=runtime.world.surface_height(point.x,point.y)
		var cell:Dictionary={"x":floori(point.x*2),"y":roundi(top*2)-1,"z":floori(point.y*2)}
		var material:int=runtime.world.cell_at(cell.x,cell.y,cell.z)
		if (stone and material!=3) or (not stone and material not in [1,2]):continue
		for offset:Vector2 in [Vector2(0,-1.25),Vector2(1.25,0),Vector2(-1.25,0),Vector2(0,1.25)]:
			var raw:Dictionary=_location(runtime.world,point.x+offset.x,point.y+offset.y)
			var feet:Dictionary=runtime._services.buildings.current_space().standing_point(raw)
			if feet.is_empty():continue
			var contact:Dictionary=runtime._services.terrain._cell_contact(runtime.world,Geometry.point(feet)+Vector3(0,1.2,0),Vector3i(cell.x,cell.y,cell.z),true,feet,str(feet.regionId))
			if not contact.ok:continue
			var route:Dictionary=runtime._services.actions.route("player",Geometry.location(runtime.actor("player")),feet)
			if not route.ok:failures.append({"cell":cell,"feet":feet,"route":slim(route)});continue
			if not care(runtime):return false
			var walked:Dictionary=walk(runtime,feet)
			if not walked.get("ok",false):failures.append({"cell":cell,"walk":slim(walked)});continue
			var item:String="stone_m3" if stone else "soil_m3";var initial:float=float(runtime.actor("player").pack.get(item,0))
			var payload:Dictionary=brush(cell,"dig",tool)
			var dug:Dictionary=send(runtime,"terrain",str(contact.target_id),payload)
			if not dug.ok:failures.append({"cell":cell,"command":slim(dug)});continue
			var done:Dictionary=progress(runtime,100)
			var ok:bool=done.finished and runtime.world.cell_at(cell.x,cell.y,cell.z)==0 and float(runtime.actor("player").pack.get(item,0))==initial+0.125
			check("real "+item+" tool extraction equals one physical cell",ok,slim(dug))
			if not ok:return false
			if not stone:
				var below:Dictionary=cell.duplicate(true);below.y-=1
				var fill:Dictionary=send(runtime,"terrain","",brush(below,"fill",tool,1,0.0,2));var filled:Dictionary=progress(runtime,100) if fill.ok else {}
				ok=fill.ok and filled.get("finished",false) and runtime.world.cell_at(cell.x,cell.y,cell.z)==2 and float(runtime.actor("player").pack.get(item,0))==initial
				check("soil fill consumes same volume, never an infinite material source",ok,slim(fill))
			current.terrain.append({"kind":item,"cell":cell,"original_material":material,"actual_feet":feet,"actual_B_route":route,"tool_id":tool,"extracted_m3":0.125,"filled_back":not stone,"ok":ok,"earlier_candidate_failures":failures})
			return ok
	check("actual bounded exposed "+("stone" if stone else "soil")+" approach exists",false,failures)
	return false

func seed_run(seed:int)->bool:
	current_seed=seed;tick_count=0
	print("NORMAL SOURCE SEED START "+str(seed))
	current={"seed":seed,"sources":[],"visits":[],"transfers":[],"operations":[],"terrain":[]};seed_rows.append(current)
	var start:int=Time.get_ticks_usec();var profiles:Dictionary=Assembly.generation_profiles()
	var generated:Dictionary=Assembly.generate(seed,profiles.profiles) if profiles.ok else profiles
	var made:Dictionary=Assembly.prepare(generated) if generated.has("chunks") else generated
	check("formal Native normal generation/prepare accepts unmodified C4 terrain",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return false
	var host:=Native.new();var built:Dictionary=host._assemble(made.capture);host.free()
	check("actual Native composes all real owners and spatial safety",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return false
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world
	var contract:Dictionary=world.extension(Factory.CONFIG_KEY)
	check("exact content4/story1 normal seed and original three people",contract.content_version==4 and contract.story_clue_version==1 and world.identity().seed==seed and runtime.actor_states().size()==3 and runtime.capture_checkpoint().source.get("playtest",{}).is_empty() and runtime.actor("player").pack=={"food":1,"water":1})
	current.contract=contract;current.initial_raster_sha256=raster_digest(world.snapshot());current.initial_actors=runtime.actor_states();current.designs=runtime._services.modules.state().instances.map(func(v:Dictionary)->Dictionary:return {"id":v.id,"definition_id":v.definition_id,"position":v.position,"quarter_turn":v.quarter_turn})
	save_actual(runtime,"initial")
	var home:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:home")
	var workshop:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	var store:Dictionary=runtime._services.modules.instance("r34:generated:RH-VILLAGE:store")
	var hs:String=home.stock_refs.values()[0];var ws:String=workshop.stock_refs.tools;var vs:String=store.stock_refs.values()[0]
	var anchor:Dictionary=world.extension("generation:RH-HOME").content_anchors[0];var ys:String=str(anchor.id)+":container"
	var axe:String=workshop.id+":tool:salvaged_axe";var saw:String=workshop.id+":tool:hand_saw";var hammer:String=workshop.id+":tool:hammer";var shovel:String=ys+":tool:shovel";var pickaxe:String=ys+":tool:pickaxe"
	source_row(runtime,hs,{"food":2,"water":3,"timber":2,"scrap":1},"home supply")
	source_row(runtime,ws,{"timber":8,"scrap":6,"book_woodwork":1,"book_tool_repair":1},"hand workshop")
	source_row(runtime,ys,{"scrap":4,"r34:salvaged_drive_unit":1,"axe_head":1,"tool_handle":1},"recovery stockyard")
	source_row(runtime,vs,{"scrap":3,"food":6,"water":6},"village supply")
	var result:bool=take_actual(runtime,hs,{"food":1,"water":1,"timber":2,"scrap":1},[],"home supply")
	if result:result=take_actual(runtime,ws,{"timber":8,"scrap":6,"book_woodwork":1,"book_tool_repair":1},[axe,saw,hammer],"hand workshop")
	if result:
		for book:String in ["book_woodwork","book_tool_repair"]:
			var studied:Dictionary=send(runtime,"study",workshop.id+":record:"+book,{"direct":false});var done:Dictionary=progress(runtime,250) if studied.ok else {}
			result=studied.ok and done.get("finished",false);check("real independent physical knowledge "+book,result,slim(studied))
			if not result:break
	if result:result=take_actual(runtime,ys,{"scrap":4,"r34:salvaged_drive_unit":1,"axe_head":1,"tool_handle":1},[shovel,pickaxe],"recovery stockyard")
	if result:result=take_actual(runtime,vs,{"scrap":3,"food":2,"water":2},[],"village supply")
	if result:
		var tool_rows:Array=[]
		for pair:Array in [[axe,"chopping"],[saw,"sawing"],[hammer,"hammering"],[shovel,"shovel"],[pickaxe,"pickaxe"]]:
			var t:Dictionary=runtime.tool(pair[0]);var qualities:Dictionary=runtime._services.production.tool_qualities(t)
			tool_rows.append({"id":t.id,"holder":t.holderId,"durability":t.durability,"qualities":qualities})
			check("real carried tool capability "+str(pair[1]),t.holderId=="pack:player" and float(t.durability)>0 and float(qualities.get(pair[1],0))>=1)
		current.tools=tool_rows;current.quantitative_bridge=runtime.actor("player").pack.duplicate(true)
		check("all finite bridge sources actually carried: ten boards fourteen scrap one drive",runtime.actor("player").pack.get("timber")==10 and runtime.actor("player").pack.get("scrap")==14 and runtime.actor("player").pack.get("r34:salvaged_drive_unit")==1)
		result=visit(runtime,hs,"actual loaded return from village")
	if result:
		var deposited:Dictionary=send(runtime,"deposit",hs,{"items":{"timber":2,"scrap":12,"food":1,"water":1}})
		check("actual carried goods enter compatible finite home buffer",deposited.ok,slim(deposited));result=deposited.ok
		current.home_buffer_limits=Modules.definition(home.definition_id).buffer_specs;current.incompatible_home_goods="drive and stone are carried in player pack; existing home supply buffer does not accept them, paid warehouse is a separate prerequisite"
	if result:result=forest(runtime,axe)
	if result:
		var before:Dictionary=runtime.actor("player").pack;result=work(runtime,workshop.config.workbench_id,"saw_timber",[saw])
		check("actual hand processing consumes one finite log into four boards",result and runtime.actor("player").pack.log==before.log-1 and runtime.actor("player").pack.timber==before.timber+4)
	if result:result=work(runtime,workshop.config.workbench_id,"make_handle",[saw])
	if result:
		var wear:float=runtime.tool(axe).durability;result=work(runtime,workshop.config.workbench_id,"repair_axe",[hammer],axe)
		check("real alternative hammer repairs old axe without requiring itself",result and float(runtime.tool(axe).durability)>wear,{"before":wear,"after":runtime.tool(axe).durability})
	if result:result=terrain_sample(runtime,pickaxe,true)
	if result:result=terrain_sample(runtime,shovel,false)
	if result:result=visit(runtime,hs,"actual return with finite logs processed boards stone and original tools")
	if result:
		check("harvested and mined goods genuinely return to supported home contact",runtime.actor("player").pack.get("log")==8 and runtime.actor("player").pack.get("stone_m3")==0.125 and float(runtime.actor("player").hp)>0)
		var before:Dictionary=runtime.actor("player").pack
		var stored:Dictionary=send(runtime,"deposit",hs,{"items":{"timber":4}})
		check("actual processed finite output is storable without phantom delivery",stored.ok and runtime.actor("player").pack.timber==before.timber-4,slim(stored));result=stored.ok
	current.finished=result;current.tick_count=tick_count;current.sim_seconds=runtime.clock();current.wall_usec=Time.get_ticks_usec()-start;current.final_actor=runtime.actor("player");current.final_stock_quantities=runtime.facts().stocks.map(func(s:Dictionary)->Dictionary:return {"id":s.id,"items":s.items,"searched":s.get("searched"),"owner":s.get("owner")})
	save_actual(runtime,"final" if result else "failure")
	if result:
		var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
		host=Native.new();var restored:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
		check("full canonical normal facts restore strictly after actual source journey",restored.get("ok",false) and Data.json_equal(decoded.capture.facts,restored.runtime.facts()),restored.get("reason"))
		if restored.get("ok",false):
			check("cold revisit preserves depleted stocks and finite stumps without grants",Data.json_equal(decoded.capture.world.extensions["r3:production"],restored.world.extension("r3:production")) and Data.json_equal(decoded.capture.world.extensions["r34:modules"],restored.world.extension("r34:modules")))
			restored.runtime.retire()
	runtime.retire();write_report(true);print("NORMAL SOURCE SEED END "+JSON.stringify({"seed":seed,"finished":result,"ticks":tick_count,"sim_seconds":current.sim_seconds,"wall_usec":current.wall_usec}));return result

func save_actual(runtime:RefCounted,label:String)->void:
	var saved:Dictionary=Store.encode(runtime.capture_checkpoint())
	if saved.ok:
		var path:String=outdir+"/seed%d-%s.native.json"%[current_seed,label]
		FileAccess.open(path,FileAccess.WRITE).store_string(saved.text)
		current[label+"_checkpoint"]={"path":path,"sha256":FileAccess.get_sha256(path)}

func run()->void:
	var args:=OS.get_cmdline_user_args();report_path=args[0];outdir=report_path.get_base_dir();input_path=args[1];wall_started=Time.get_ticks_msec()
	spec=JSON.parse_string(FileAccess.get_file_as_string(input_path))
	check("bounded exact C4/story1 normal seed input",spec.get("seeds") is Array and spec.seeds.size() in [1,4] and spec.content_version==4 and spec.story_clue_version==1 and spec.profile=="normal" and spec.max_ticks_per_seed<=12000 and spec.max_wall_msec<=240000)
	if checks.any(func(c:Dictionary)->bool:return not c.ok):return finish()
	for seed:Variant in spec.seeds:
		if Time.get_ticks_msec()-wall_started>int(spec.max_wall_msec):check("bounded wall budget retains unexecuted seeds as untested",false,seed);break
		seed_run(int(seed))
	current_seed=-1
	check("all explicitly requested seeds actually attempted",seed_rows.size()==spec.seeds.size())
	var hashes:Array=seed_rows.map(func(row:Dictionary)->String:return row.get("initial_raster_sha256",""))
	if hashes.size()>1:check("normal terrain variations are real, not just different seed labels",hashes.all(func(h:String)->bool:return not h.is_empty()) and hashes.any(func(h:String)->bool:return h!=hashes[0]))
	finish()

func write_report(partial:bool)->void:
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"partial":partial,"seed_rows":seed_rows,"input":spec,"input_sha256":FileAccess.get_sha256(input_path),"elapsed_msec":Time.get_ticks_msec()-wall_started,"supply_boundaries":{"historical_finite":"initial food/water/boards/scrap/tools/manuals/drive/axe-head are once-only finite sources; search does not refill","environment_finite":"actual tree stumps persist; stone/soil come from changed finite cells; filling consumes material","implemented_processing":"actual hand saw/handle/axe repair verified here; A prior normal53 machine path is separate, not repeated per seed","not_implemented_as_supply":"agriculture/seed reproduction, renewable clean well, periodic trade/external supply and natural tree regrowth are not claimed","storage":"home buffer accepts only its actual SKU limits; drive/stone can return carried but need compatible paid storage before deposit"},"scope":"actual immutable18 normal content4/story1 multi-seed key-source commands, B body/navigation, physical carry and canonical facts; no grants/teleport/capture edits; no renderer/OS/VA/RSS/performance/long-time or full economy/indefinite self-sufficiency qualification"}
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))

func finish()->void:
	write_report(false);var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"seeds":seed_rows.size()}));quit(1 if failed else 0)
