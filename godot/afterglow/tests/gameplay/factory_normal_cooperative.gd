extends "res://tests/gameplay/factory_normal_preparation.gd"
## Continue an explicitly identified, real normal-economy save. Never edits a
## body, item holder, permission, job, enemy or clock outside normal commands.
var output_dir:String
var stage_rows:Array=[]
var guard_hits:Dictionary={}
var observed_events:Dictionary={}
var route_observations:Dictionary={}
var source_path:String
var source_sha:String
var guards:Array[String]=["village-resident","repair-resident"]
var stage_failure:String=""
const RouteInputs=preload("res://tests/gameplay/factory_route_inputs.gd")

func route_stock(runtime:RefCounted,role:String,buffer:String)->String:
	return RouteInputs.stock(runtime,role,buffer)

func prepare_defense_supplies(runtime:RefCounted)->bool:
	var home_stock:String=route_stock(runtime,"home","supplies")
	if RouteInputs.options().is_empty():
		if not take_real(runtime,home_stock,{"food":2,"water":3}):return false
	else:
		# Carry the same original provision target; fill only actual deficits.
		# Two water per companion plus one for the player, two food total.
		for spec:Array in [["food",2],["water",5]]:
			var missing:int=maxi(0,int(spec[1])-int(runtime.actor("player").pack.get(spec[0],0)))
			for role:String in ["home","store"]:
				if missing<=0:break
				var source:String=route_stock(runtime,role,"supplies")
				var quantity:int=mini(missing,int(runtime.stock(source).get("items",{}).get(spec[0],0)))
				if quantity>0:
					if not take_real(runtime,source,{spec[0]:quantity}):return false
					missing-=quantity
			if missing>0:check("finite original defense provision unavailable",false,{"item":spec[0],"missing":missing});return false
	for id:String in guards:
		var reached:bool=near_person(runtime,id)
		var handed:Dictionary=send(runtime,"deposit","pack:"+id,{"items":{"water":2}}) if reached else {"ok":false,"reason":"actual person handoff unreachable"}
		check("normal finite water physically handed to consenting companion "+id,handed.ok,handed)
		if not handed.ok:return false
	return true

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"r34:e:normal-cooperative:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})

func observe(runtime:RefCounted)->void:
	for event:Dictionary in runtime.facts().ledger:
		if observed_events.has(event.id):continue
		observed_events[event.id]=true
		if event.kind=="combat-hit" and str(event.get("actor_id","")) in guards:
			var id:String=event.actor_id;guard_hits[id]=int(guard_hits.get(id,0))+1
	for id:String in guards:
		var actor:Dictionary=runtime.actor(id);var intent:Variant=actor.get("intent")
		if intent is Dictionary and intent.get("kind")=="guard" and intent.has("guard_site_id"):
			var row:Dictionary=route_observations.get(id,{"first_clock":runtime.clock(),"from":Geometry.location(actor),"site_id":intent.guard_site_id,"destination":intent.guard_destination,"samples":0})
			row.samples+=1;row.last=Geometry.location(actor);route_observations[id]=row

func step(runtime:RefCounted,count:int=1)->void:
	for i in count:runtime.tick(0.1);observe(runtime)

func progress(runtime:RefCounted,limit:int=1200)->Dictionary:
	var start:float=runtime.clock();var i:int=0
	while runtime.actor("player").get("intent")!=null and i<limit:
		step(runtime);i+=1
	return {"finished":runtime.actor("player").get("intent")==null,"sim_seconds":runtime.clock()-start,"iterations":i,"actor":runtime.actor("player")}

func note(runtime:RefCounted,label:String)->void:
	observe(runtime)
	var row:Dictionary={"stage":label,"time":runtime.clock(),"defense":runtime.world.extension(Gameplay.KEY).defense,"actors":[]}
	for actor:Dictionary in runtime.facts().actors:
		row.actors.append({"id":actor.id,"location":Geometry.location(actor),"hp":actor.hp,"stamina":actor.stamina,"hunger":actor.get("hunger"),"thirst":actor.get("thirst"),"fatigue":actor.get("fatigue"),"pack":actor.pack,"job":actor.get("job"),"intent":actor.get("intent"),"relationship":actor.get("relationship"),"activity":actor.get("activity")})
	stage_rows.append(row)
	print("COOPERATIVE_STAGE "+label+" "+str(runtime.clock()))

func save(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	if encoded.ok:FileAccess.open(output_dir+"/"+label+".native.json",FileAccess.WRITE).store_string(encoded.text)
	return encoded

func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=save(runtime,label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	var differences:Array=[]
	if restored.get("ok",false):
		compare_fields(runtime.facts().actors,restored.runtime.facts().actors,"actors",differences)
		compare_fields(runtime.world.extension(Gameplay.KEY),restored.world.extension(Gameplay.KEY),"event",differences)
		compare_fields(runtime.facts().stocks,restored.runtime.facts().stocks,"stocks",differences)
	for difference:Dictionary in differences:
		var segments:PackedStringArray=str(difference.path).split("/")
		if segments.size()==3 and segments[0]=="actors" and segments[1].is_valid_int():
			var index:int=int(segments[1])
			difference.actor_id=runtime.facts().actors[index].id
			difference.restored_actor_id=restored.runtime.facts().actors[index].id
			if segments[2] in ["x","y","z"]:
				difference.vector_components_equal=exact_vector_components(Geometry.point(runtime.facts().actors[index]),Geometry.point(restored.runtime.facts().actors[index]))
		elif segments.size()==4 and segments[0]=="stocks" and segments[1].is_valid_int() and segments[2]=="location":
			var index:int=int(segments[1])
			difference.stock_id=runtime.facts().stocks[index].id
			difference.restored_stock_id=restored.runtime.facts().stocks[index].id
			difference.vector_components_equal=exact_vector_components(Geometry.point(runtime.facts().stocks[index].location),Geometry.point(restored.runtime.facts().stocks[index].location))
	# Require exact canonical payload facts and every persisted extension.
	# Live binary differences are accepted only at diagnosed identity-bound leaves,
	# with an absolute bound and <=1 ULP; all other paths remain exact.
	var same:bool=restored.get("ok",false) and persisted_restore_equal(decoded.capture,restored.runtime.facts(),restored.world) and differences.all(roundtrip_difference_allowed)
	check("normal cooperative cold restore retains all bodies cargo stock and event "+label,same,{"reason":restored.get("reason"),"differences":differences})
	return restored if same else {"ok":false}

func persisted_restore_equal(capture:Dictionary,facts:Dictionary,world:RefCounted)->bool:
	if not Data.json_equal(capture.facts,facts):return false
	var restored:Dictionary=world.snapshot()
	return Data.json_equal(capture.world.extensions,restored.get("extensions",{})) and Data.json_equal(capture.world.entities,restored.get("entities",{}))

func roundtrip_difference_allowed(difference:Dictionary)->bool:
	var path:String=str(difference.get("path",""))
	var allowed:bool=path=="event/regional_objectives/r34:regional:townward-roadfall:RH-VILLAGE/warning_basis/defense_route_distance_m"
	var fatigue_ids:Dictionary={"actors/3/fatigue":"infected:r34:first-defense:0","actors/4/fatigue":"infected:r34:first-defense:1","actors/5/fatigue":"infected:r34:first-defense:2"}
	if fatigue_ids.has(path):
		allowed=difference.get("actor_id")==fatigue_ids[path] and difference.get("restored_actor_id")==fatigue_ids[path]
	if path=="actors/3/z":
		allowed=difference.get("actor_id")=="infected:r34:first-defense:0" and difference.get("restored_actor_id")=="infected:r34:first-defense:0" and difference.get("vector_components_equal",false)
	elif path=="stocks/71/location/z":
		allowed=difference.get("stock_id")=="infected:r34:first-defense:0:drops" and difference.get("restored_stock_id")=="infected:r34:first-defense:0:drops" and difference.get("vector_components_equal",false)
	if not allowed or not difference.get("before") is float or not difference.get("after") is float:return false
	var before:float=difference.before;var after:float=difference.after
	var signed_coordinate:bool=path in ["actors/3/z","stocks/71/location/z"]
	if not signed_coordinate and (before<0 or after<0):return false
	if not is_finite(before) or not is_finite(after) or (before<0)!=(after<0) or absf(after-before)>=1e-12:return false
	var first:=PackedByteArray();first.resize(8);first.encode_double(0,before)
	var second:=PackedByteArray();second.resize(8);second.encode_double(0,after)
	return absi(first.decode_s64(0)-second.decode_s64(0))<=1

static func exact_vector_components(before:Vector3,after:Vector3)->bool:
	return before.x==after.x and before.y==after.y and before.z==after.z

func compare_fields(before:Variant,after:Variant,path:String,differences:Array)->void:
	if Data.json_equal(before,after):return
	if before is Dictionary and after is Dictionary:
		for key:Variant in before:
			if not after.has(key):differences.append({"path":path+"/"+str(key),"missing":true})
			else:compare_fields(before[key],after[key],path+"/"+str(key),differences)
		for key:Variant in after:
			if not before.has(key):differences.append({"path":path+"/"+str(key),"added":true})
	elif before is Array and after is Array and before.size()==after.size():
		for i:int in before.size():compare_fields(before[i],after[i],path+"/"+str(i),differences)
	else:differences.append({"path":path,"before":before,"after":after,"before_type":type_string(typeof(before)),"after_type":type_string(typeof(after)),"delta":after-before if (before is float or before is int) and (after is float or after is int) else null})

func near_person(runtime:RefCounted,id:String)->bool:
	for attempt in 18:
		if runtime._services.production.reach("player","pack:"+id,runtime.stock("pack:"+id),"handoff")==null:return true
		var at:Dictionary=Geometry.location(runtime.actor(id));at.x+=0.9
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if not feet.is_empty():walk(runtime,feet)
	return false

func take_real(runtime:RefCounted,source:String,items:Dictionary)->bool:
	var stock:Dictionary=runtime.stock(source)
	var reached:Dictionary=walk(runtime,stock.location)
	if not reached.get("ok",false):return false
	if not runtime.stock(source).get("searched",false):
		var searched:Dictionary=send(runtime,"search",source)
		if not searched.ok or not progress(runtime).finished:return false
	var taken:Dictionary=send(runtime,"take",source,{"items":items})
	check("preparation transfers actual finite source "+source,taken.ok,taken)
	return taken.ok

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("explicit A normal-economy prerequisite decodes without fact edits",decoded.ok,decoded.get("reason"))
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("normal economic success save reassembles actual services",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world;var query:RefCounted=built.services.buildings.current_space()
	for region_id:String in ["RH-HOME","RH-VILLAGE"]:
		var warming:Array=[]
		while not world.region_is_resident(region_id):
			var warm:Dictionary=world.prepare_region_residency(region_id,true,world.get_revision(),32)
			var committed:Dictionary=runtime._commit({"world_changes":warm.get("world_changes",[]),"fact_changes":[],"events":[]}) if warm.get("ok",false) else warm
			warming.append({"prepare":warm.get("cost"),"commit":committed.get("ok"),"remaining":warm.get("remaining_chunks")})
			if not committed.get("ok",false):check("actual persisted C pages warm target region "+region_id,false,committed);return finish()
		costs["page_warm:"+region_id]=warming
	var people:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")!="infected")
	check("prerequisite has only original three living people with real consent and returned home",people.size()==3 and people.all(func(a:Dictionary)->bool:return a.hp>0 and (a.id=="player" or (a.relationship.member and a.relationship.consent and a.relationship.home_arrived))))
	if people.size()!=3:return finish()
	note(runtime,"restored explicit normal economy prerequisite")
	for task:Dictionary in world.extension("r34:logistics").tasks:
		if task.status in ["cancelled","completed"]:continue
		var cancelled:Dictionary=send(runtime,"logistics.cancel",str(task.id))
		check("completed repeat logistics yields through original cancel command",cancelled.ok,cancelled)
		if not cancelled.ok:return finish()
	if not prepare_defense_supplies(runtime):return finish()
	var pickaxe:String="RH-HOME:stockyard-content:container:tool:pickaxe"
	var combat_tool:String=pickaxe
	for tool:Dictionary in world.extension("r3:production").tools:
		if tool.kind=="pickaxe" and tool.holderId=="pack:player":pickaxe=tool.id
		if tool.kind=="salvaged_axe" and tool.holderId=="pack:player":combat_tool=tool.id
	check("clearance uses the original paid normal pickaxe in player pack",runtime.tool(pickaxe).get("holderId")=="pack:player")
	var site:Dictionary=world.extension("generation:RH-VILLAGE").regional_sites[0]
	costs.route_context={"home_detailed":runtime.region_is_detailed("RH-HOME"),"village_detailed":runtime.region_is_detailed("RH-VILLAGE"),"home_resident":world.region_is_resident("RH-HOME"),"village_resident":world.region_is_resident("RH-VILLAGE"),"home_paths":world.extension("generation:RH-HOME").paths,"village_paths":world.extension("generation:RH-VILLAGE").paths}
	save(runtime,"actual-before-survey-route")
	note(runtime,"finite companion supplies delivered before survey route")
	var approached:Dictionary=walk(runtime,site.survey_point)
	check("normal cooperative player physically reaches original stone survey",approached.get("ok",false),{"route":approached,"from":stage_rows[-1].actors[0].location,"to":site.survey_point})
	if not approached.get("ok",false):return finish()
	var surveyed:Dictionary=send(runtime,"settlement.survey","",{"site_id":site.id})
	check("normal cooperative survey is an actual onsite committed command",surveyed.ok,surveyed)
	if not surveyed.ok:return finish()
	note(runtime,"onsite surveyed before accepting risk")
	var guard_targets:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.job=="guard")
	var guard_route_probe:Array=[]
	for id:String in guards:
		var actor:Dictionary=runtime.actor(id)
		var route:Dictionary=runtime._services.actions.route(id,Geometry.location(actor),site.warning_points.approach_after)
		guard_route_probe.append({"actor_id":id,"actor":actor,"destination":site.warning_points.approach_after,"route":route,"standing":query.standing_point(site.warning_points.approach_after),"region_detailed":runtime.region_is_detailed(str(actor.regionId))})
	var guard_page:Dictionary={"world_identity":world.identity(),"world_revision":world.get_revision(),"runtime_revision":runtime.get_revision(),"actors":runtime.facts().actors,"site":site,"home":world.extension(Gameplay.KEY).layout.home,"regional_event":runtime._services.workforce.projection("*").regional_event,"work_targets":runtime.work_targets(),"guard_route_probe":guard_route_probe,"region_home":world.region("RH-HOME"),"region_village":world.region("RH-VILLAGE"),"residency":{"home":world.region_residency_state("RH-HOME"),"village":world.region_residency_state("RH-VILLAGE")}}
	costs.guard_page=guard_page
	check("normal UI job selector exposes a real surveyed regional guard target",not guard_targets.is_empty(),{"guard_targets":guard_targets,"guard_route_probe":guard_route_probe})
	if guard_targets.is_empty():stage_failure="normal guard target unavailable after real survey; see guard_page";return finish()
	var target:Dictionary=guard_targets.filter(func(t:Dictionary)->bool:return t.get("actual_target_id")==site.id or t.id==site.id or t.get("work_payload",{}).get("site_id")==site.id)[0] if guard_targets.any(func(t:Dictionary)->bool:return t.get("actual_target_id")==site.id or t.id==site.id or t.get("work_payload",{}).get("site_id")==site.id) else guard_targets[0]
	for id:String in guards:
		var assigned:Dictionary=send(runtime,"job",id,{"job":"guard","work_target_id":target.id})
		check("real consenting original companion assigned guard by normal Runtime job "+id,assigned.ok,assigned)
		if not assigned.ok:return finish()
	var risk:Dictionary=send(runtime,"settlement.begin_route_work","",{"site_id":site.id,"accept_risk":true})
	check("onsite informed normal cooperative risk opens finite warning",risk.ok,risk)
	if not risk.ok:return finish()
	step(runtime);note(runtime,"risk accepted and dispatch requested")
	var home:Dictionary=world.extension(Gameplay.KEY).layout.home
	var returned:Dictionary=walk(runtime,home)
	check("normal cooperative player really returns for finite preparation",returned.get("ok",false),returned)
	if not returned.get("ok",false):return finish()
	for kind:String in ["drink","eat"]:
		var care:Dictionary=send(runtime,kind)
		check("normal cooperative player pays finite "+kind,care.ok and progress(runtime,20).finished,care)
	check("normal cooperative preparation uses original twelve second rest",rest_once(runtime))
	note(runtime,"home finite supplies and recovery complete")
	var restored:Dictionary=cold_restore(runtime,"prepared-guards-enroute")
	if not restored.ok:return finish()
	runtime=restored.runtime;world=restored.world;query=restored.services.buildings.current_space()
	var deployed:Dictionary=walk(runtime,site.warning_points.approach_after)
	check("normal prepared player reaches C real defense point through bypass",deployed.get("ok",false),deployed)
	if not deployed.get("ok",false):return finish()
	check("normal defender finishes one necessary recovery action",rest_once(runtime))
	note(runtime,"player at defense after necessary preparation")
	var remaining:float=world.extension(Gameplay.KEY).defense.get("warning_remaining",0)
	check("warning covers actual return supply recovery and field deployment",world.extension(Gameplay.KEY).defense.status=="warning" and remaining>=10,remaining)
	var field:Dictionary=site.warning_points.approach_after.duplicate(true);field.z-=8.0;field=query.standing_point(field)
	var field_walk:Dictionary=walk(runtime,field) if not field.is_empty() else {"ok":false}
	check("normal player takes supported open ground beyond the stone defense",field_walk.get("ok",false),field_walk)
	if not field_walk.get("ok",false):return finish()
	remaining=world.extension(Gameplay.KEY).defense.get("warning_remaining",0)
	for i in ceili(remaining*10)+5:
		step(runtime)
		if world.extension(Gameplay.KEY).defense.status=="active":break
	note(runtime,"finite original enemies arrive")
	var state:Dictionary=world.extension(Gameplay.KEY)
	check("actual finite warning spawns original three without waiting for home",state.defense.status=="active" and state.defense.actors.size()==3,state.defense)
	check("both normal guards traverse B actual route toward the real defense point",route_observations.size()==2,route_observations)
	if state.defense.status!="active":return finish()
	var partial_saved:bool=false
	for i in 1000:
		state=world.extension(Gameplay.KEY)
		var alive:Array=state.defense.actors.filter(func(id:String)->bool:return runtime.actor(id).hp>0)
		if alive.is_empty() or runtime.actor("player").hp<=0:break
		var player:Dictionary=runtime.actor("player")
		if not partial_saved and guard_hits.size()>0:
			partial_saved=true;note(runtime,"actual guard combat before cold restoration")
			restored=cold_restore(runtime,"actual-companion-partial-combat")
			if not restored.ok:return finish()
			runtime=restored.runtime;world=restored.world;query=restored.services.buildings.current_space()
		if player.get("intent")!=null:step(runtime);continue
		alive.sort_custom(func(a:String,b:String)->bool:return Geometry.point(runtime.actor(a)).distance_squared_to(Geometry.point(player))<Geometry.point(runtime.actor(b)).distance_squared_to(Geometry.point(player)))
		var enemy:Dictionary=runtime.actor(str(alive[0]));var distance:float=Geometry.point(enemy).distance_to(Geometry.point(player))
		if distance>3.0:
			var direction:Vector3=(Geometry.point(enemy)-Geometry.point(player)).normalized()
			var approach:Dictionary=Geometry.location(player);approach.x+=direction.x*minf(2.5,distance-2.6);approach.z+=direction.z*minf(2.5,distance-2.6)
			approach=query.standing_point(approach)
			var advanced:Dictionary=walk(runtime,approach) if not approach.is_empty() else {"ok":false}
			costs.get_or_add("combat_approaches",[]).append({"time":runtime.clock(),"ok":advanced.get("ok",false),"reason":advanced.get("reason"),"from":Geometry.location(player),"to":approach})
			if not advanced.get("ok",false):break
			continue
		if player.stamina<28:
			for retreat in 6:
				if not evade(runtime,query,alive):break
			var recovery:Dictionary=send(runtime,"rest")
			if recovery.ok:progress(runtime,120)
			continue
		if distance<=2.0 and float(player.get("cooldown",0))<=0:
			var struck:Dictionary=send(runtime,"attack",str(alive[0]),{"tool_id":combat_tool})
			costs.get_or_add("player_strikes",[]).append({"time":runtime.clock(),"request":struck,"stamina":runtime.actor("player").stamina})
			if not struck.ok:break
			var living:Array=alive.filter(func(id:String)->bool:return runtime.actor(id).hp>0)
			if not living.is_empty():evade(runtime,query,living)
		else:step(runtime)
	step(runtime);note(runtime,"cooperative defense outcome")
	state=world.extension(Gameplay.KEY)
	check("normal cooperation uses actual companion paid combat rather than assigned labor label",guard_hits.size()>0,guard_hits)
	check("normal cooperative finite defense ends only after all actual enemies die",state.defense.status=="cleared" and guards.all(func(id:String)->bool:return runtime.actor(id).hp>0) and runtime.actor("player").hp>0,state.defense)
	if state.defense.status!="cleared" or runtime.actor("player").hp<=0:return finish()
	var before:Dictionary=site.goal_corridor.approach_before;var after:Dictionary=site.goal_corridor.approach_after
	var toward:Vector3=(Geometry.point(after)-Geometry.point(before)).normalized()
	var work_at:Dictionary=before.duplicate(true);work_at.x+=toward.x*1.25;work_at.z+=toward.z*1.25;work_at=query.standing_point(work_at)
	var work_walk:Dictionary=walk(runtime,work_at)
	var cells:Array=site.obstacle_cells.duplicate(true);cells.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.y>b.y if a.y!=b.y else Vector2(a.x,a.z).distance_squared_to(Vector2(before.x*2,before.z*2))<Vector2(b.x,b.z).distance_squared_to(Vector2(before.x*2,before.z*2)))
	var removed:int=0
	if work_walk.get("ok",false):
		for cell:Dictionary in cells:
			if runtime.actor("player").stamina<20 and not rest_once(runtime):break
			var dig:Dictionary=send(runtime,"terrain","",brush(cell,"dig",pickaxe))
			if not dig.ok or not progress(runtime,45).finished:costs.clearance_failure=dig;break
			if world.cell_at(cell.x,cell.y,cell.z)==0:removed+=1
	step(runtime);note(runtime,"post-defense actual clearance outcome")
	check("original normal pickaxe clears every actual stone cell after real defense",removed==24,{"removed":removed,"failure":costs.get("clearance_failure")})
	check("normal cooperative region completes only after enemies and true corridor clear",world.extension(Gameplay.KEY).regional_objectives[site.id].get("completed",false))
	restored=cold_restore(runtime,"actual-cooperative-completed")
	check("final cooperative result survives actual cold native restore",restored.ok)
	finish()

func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"stages":stage_rows,"guard_hits":guard_hits,"guard_routes":route_observations,"stage_failure":stage_failure,"costs":costs,"prerequisite":{"path":source_path,"sha256":source_sha,"scope":"Explicit A 53-check actual normal-economy successful native save, including original finite tools, real voluntary recruitment and four physical deliveries; prior dependency drift remains disclosed."},"scope":"E actual follow-on cooperative survey/preparation/guard/combat/clearance/native restore from identified normal save. No actor, job, inventory or health injection; no new clock, rules, PCK OS VA performance qualification."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
