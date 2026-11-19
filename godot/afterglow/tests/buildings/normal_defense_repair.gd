extends "res://tests/integration/run_factory_economy.gd"
## Actual immutable19 G3 preparation -> paid existing wall -> original infected
## AI/contact/structure damage -> paid repair -> same preexisting production.
## No fixture actors, HP, terrain, materials, clock, event or capture edits.
var source_path:String
var source_sha:String
var hits:Array=[]
var events_seen:Dictionary={}
var samples:Array=[]
var commands:Array=[]
var combat:Array=[]
var barrier_positions:Array=[]
var stop_reason:String=""
const WALL="B:R34-63:paid-road-barrier"
const HAMMER="r34:generated:RH-HOME:woodwork:tool:hammer"
const AXE="r34:generated:RH-HOME:woodwork:tool:salvaged_axe"

func send(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"B:R34-63:normal:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=rt.command(request)
	commands.append({"clock":rt.clock(),"request":request.duplicate(true),"ok":result.get("ok",false),"code":result.get("code"),"reason":result.get("reason"),"revision":result.get("revision")})
	observe(rt)
	return result
func observe(rt:RefCounted)->void:
	for event:Dictionary in rt.facts().ledger:
		if events_seen.has(event.id):continue
		events_seen[event.id]=true
		if event.kind=="structure-damaged" and event.get("target_id")==WALL:hits.append(event.duplicate(true))
		if event.kind in ["combat-hit","infected-defeated"]:combat.append(event.duplicate(true))
func step(rt:RefCounted,count:int=1)->void:
	for i:int in count:
		rt.tick(0.1)
		observe(rt)
func progress(rt:RefCounted,limit:int=1200)->Dictionary:
	var began:float=rt.clock();var i:int=0
	while rt.actor("player").get("intent")!=null and i<limit:
		step(rt);i+=1
	return {"finished":rt.actor("player").get("intent")==null,"sim_seconds":rt.clock()-began,"iterations":i,"actor":rt.actor("player")}
func near_stock(rt:RefCounted,id:String)->bool:
	var stock:Dictionary=rt.stock(id)
	if not stock.has("module_id"):return super.near_stock(rt,id)
	for row:Dictionary in rt.module_service_approaches(stock.module_id).get("approaches",[]):
		if row.get("stock_ref")==id and row.get("available",false):return walk(rt,row.location).get("ok",false) and rt._services.production.reach("player",id,rt.stock(id),"search")==null
	return false
func save_actual(rt:RefCounted,label:String)->void:
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint())
	check("actual checkpoint encodes "+label,encoded.get("ok",false),encoded.get("reason"))
	if encoded.get("ok",false):FileAccess.open(outdir+"/"+label+".native.json",FileAccess.WRITE).store_string(encoded.text)
func note_state(rt:RefCounted,label:String)->void:
	note(rt,label,{"wall":rt._services.buildings.instance(WALL),"defense":rt.world.extension("r34:gameplay").defense})
	samples.append({"stage":label,"clock":rt.clock(),"wall":rt._services.buildings.instance(WALL),"actors":rt.facts().actors.map(func(a:Dictionary)->Dictionary:return {"id":a.id,"hp":a.hp,"location":Geometry.location(a),"activity":a.get("activity"),"job":a.get("job"),"cooldown":a.get("cooldown")}),"hits":hits.duplicate(true)})
	print("DEFENSE_REPAIR "+label+" t="+str(rt.clock()))
func structure(rt:RefCounted,piece:Dictionary,kind:String)->Dictionary:
	var payload:Dictionary={"kind":kind,"source_id":"pack:player","output_id":"pack:player","tool_id":HAMMER,"direct":true,"held":true,"requires_hold":false}
	if kind=="place":payload.instance=piece
	return send(rt,"structure",str(piece.id),payload)

func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];source_path=args[1];DirAccess.make_dir_recursive_absolute(outdir)
	source_sha=FileAccess.get_sha256(source_path)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path))
	check("explicit19 actual G3 preparation envelope decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("original Native restores untouched real G3 facts",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime;var world:RefCounted=built.world;var building:RefCounted=built.services.buildings
	check("source is unspawned real finite warning with original three people",world.extension("r34:gameplay").defense.status=="warning" and world.extension("r34:gameplay").defense.actors.is_empty() and rt.facts().actors.size()==3 and rt.actor("player").pack.timber==2 and rt.actor("player").pack.scrap==2)
	if checks.any(func(c:Dictionary)->bool:return not c.ok):return finish()
	note_state(rt,"original19 G3 preparation")
	# Reuse the real already produced/transported boards, not a new grant.
	var stock_id:String="r34:normal-built-warehouse:stock:storage"
	var prior_stock:float=rt.stock(stock_id).items.timber
	if not take_source(rt,stock_id,{"timber":2}):stop_reason="actual warehouse service route/source unavailable";return finish()
	check("two real warehouse boards leave exact finite build-plus-repair budget",rt.stock(stock_id).items.timber==prior_stock-2 and rt.actor("player").pack.timber==4 and rt.actor("player").pack.scrap==2)
	# This is a real spatial choice on the original road, not edited terrain.
	# Keep the original spawn 1.5m north and guard positions 2m south.
	var at:Dictionary={"x":34.0,"y":world.surface_height(34.0,-51.0),"z":-51.0,"regionId":"RH-VILLAGE"}
	var piece:Dictionary=building.make_instance("wall",WALL,at,0,"home-residents")
	var preview:Dictionary=building.prepare_edit([],[piece])
	check("real generated defensive road admits original full-cost wall",preview.get("ok",false),preview)
	if not preview.get("ok",false):stop_reason="original terrain/structure safety refuses real barrier site";save_actual(rt,"actual-barrier-site-refused");return finish()
	var feet:Dictionary=building.current_space().standing_point({"x":34.0,"y":at.y,"z":-50.2,"regionId":"RH-VILLAGE"})
	var traveled:Dictionary=walk(rt,feet) if not feet.is_empty() else {"ok":false}
	check("player physically travels from home through original road to work side",traveled.get("ok",false),traveled)
	if not traveled.get("ok",false):return finish()
	var budget:Dictionary=rt.actor("player").pack.duplicate(true);var hammer_before:float=rt.tool(HAMMER).durability
	var started:Dictionary=structure(rt,piece,"place");var done:Dictionary=progress(rt,120) if started.ok else {}
	check("original eight-second labour actually constructs paid barrier",started.ok and done.get("finished",false) and not building.instance(WALL).is_empty(),{"start":started,"completed":done})
	if not started.ok or building.instance(WALL).is_empty():save_actual(rt,"actual-barrier-build-failed");return finish()
	var expected_pack:Dictionary=budget.duplicate(true);expected_pack.timber-=3;expected_pack.scrap-=1
	check("only original three boards one scrap charged and hammer paid labour",Data.json_equal(rt.actor("player").pack,expected_pack) and is_equal_approx(hammer_before-rt.tool(HAMMER).durability,1.2) and building.instance(WALL).hp==120)
	var south:Dictionary={"x":34.0,"y":at.y,"z":-49.0,"regionId":"RH-VILLAGE"};var north:Dictionary={"x":34.0,"y":at.y,"z":-52.0,"regionId":"RH-VILLAGE"}
	check("paid wall blocks original body crossing and melee sight",not building.current_space().walk("player",north,south).ok and not building.current_space().line_clear(north,south))
	var retreat:Dictionary=walk(rt,south)
	check("player remains alive on legal original defender side",retreat.get("ok",false),retreat)
	if not retreat.get("ok",false):return finish()
	note_state(rt,"paid barrier before original event");save_actual(rt,"actual-paid-barrier-before-attack")
	var defense:Dictionary=world.extension("r34:gameplay").defense
	for i:int in 1100:
		step(rt)
		defense=world.extension("r34:gameplay").defense
		if defense.status=="active":break
	check("unchanged natural warning spawns only original three infected",defense.status=="active" and defense.actors.size()==3 and defense.actors.all(func(id:String)->bool:return rt.actor(id).faction=="infected" and rt.actor(id).max_hp==48),defense)
	if defense.status!="active":stop_reason="original warning did not produce legal real enemies";save_actual(rt,"actual-defense-not-spawned");return finish()
	# Wait for real AI to attack. No direct strike_structure/damage_in calls,
	# no cooldown reset. If blocking were invulnerable this bounded stage fails.
	var before_people:Dictionary={}
	for actor:Dictionary in rt.facts().actors:
		if actor.get("faction")!="infected":before_people[actor.id]=actor.hp
	var illegal_crossings:Array=[];var first_hit_saved:bool=false
	for i:int in 250:
		step(rt)
		var wall:Dictionary=building.instance(WALL)
		for id:String in defense.actors:
			var enemy:Dictionary=rt.actor(id)
			barrier_positions.append({"clock":rt.clock(),"actor_id":id,"hp":enemy.hp,"location":Geometry.location(enemy),"wall_hp":wall.hp})
			if float(wall.hp)>0 and float(enemy.hp)>0 and float(enemy.x)>33.0 and float(enemy.x)<35.0 and float(enemy.z)>-50.64:illegal_crossings.append({"enemy":id,"location":Geometry.location(enemy),"wall_hp":wall.hp})
		if not hits.is_empty() and not first_hit_saved:
			first_hit_saved=true;note_state(rt,"real original infected hit paid wall");save_actual(rt,"actual-enemy-wall-damage")
		if float(wall.hp)<=0:break
	check("real hostile AI produces contact-valid structure damage in original transactions",not hits.is_empty() and hits.all(func(e:Dictionary)->bool:return defense.actors.has(e.actor_id) and e.get("hostile",false) and float(e.damage)>0 and float(e.damage)<=12),hits)
	check("living wall never permits original enemy through its solid interval",illegal_crossings.is_empty(),illegal_crossings)
	check("opaque unbroken barrier prevents original melee damage to all defenders",before_people.keys().all(func(id:String)->bool:return rt.actor(id).hp==before_people[id]))
	check("road blockade is breakable by original infected without extra damage",building.instance(WALL).hp==0 and hits.reduce(func(n:float,e:Dictionary)->float:return n+float(e.damage),0.0)==120,{"wall":building.instance(WALL),"hits":hits})
	if building.instance(WALL).hp>0:stop_reason="original enemy attack did not break legal barrier within25s";save_actual(rt,"actual-attack-bounded-red");return finish()
	check("destroyed wall releases its real collider and direct crossing",building.geometry.boxes(building.instance(WALL)).is_empty() and building.current_space().walk("player",north,south).ok)
	note_state(rt,"original enemies broke paid wall");save_actual(rt,"actual-broken-paid-barrier")
	# Original guards and the player's already acquired axe finish this encounter.
	for i:int in 1200:
		var alive:Array=defense.actors.filter(func(id:String)->bool:return rt.actor(id).hp>0)
		if alive.is_empty() or rt.actor("player").hp<=0:break
		if rt.actor("player").get("intent")!=null:step(rt);continue
		alive.sort_custom(func(a:String,b:String)->bool:return Geometry.point(rt.actor(a)).distance_squared_to(Geometry.point(rt.actor("player")))<Geometry.point(rt.actor(b)).distance_squared_to(Geometry.point(rt.actor("player"))))
		var enemy:Dictionary=rt.actor(str(alive[0]));var distance:float=Geometry.point(enemy).distance_to(Geometry.point(rt.actor("player")))
		if distance<=2.05 and float(rt.actor("player").stamina)>=14 and float(rt.actor("player").get("cooldown",0))<=0:
			send(rt,"attack",enemy.id,{"tool_id":AXE})
		elif rt.actor("player").stamina<14 and distance>2.2:send(rt,"rest")
		step(rt)
	step(rt)
	check("actual original combat clears roster while original people survive",world.extension("r34:gameplay").defense.status=="cleared" and rt.actor("player").hp>0 and ["village-resident","repair-resident"].all(func(id:String)->bool:return rt.actor(id).hp>0),rt.facts().actors)
	if world.extension("r34:gameplay").defense.status!="cleared":stop_reason="combat not cleared";save_actual(rt,"actual-combat-not-cleared");return finish()
	if not care(rt,35):return finish()
	# Same broken identity; no new fabricated HP or replacement object.
	var service:Dictionary=building.current_space().standing_point({"x":34.0,"y":at.y,"z":-50.2,"regionId":"RH-VILLAGE"})
	var reached:Dictionary=walk(rt,service)
	check("real survivor walks back to original broken barrier service",reached.get("ok",false),reached)
	if not reached.get("ok",false):return finish()
	var damaged:Dictionary=building.instance(WALL);var repair_pack:Dictionary=rt.actor("player").pack.duplicate(true);hammer_before=rt.tool(HAMMER).durability
	var repair:Dictionary=structure(rt,damaged,"repair");done=progress(rt,100) if repair.ok else {}
	check("original six-second repair labour restores same attacked wall",repair.ok and done.get("finished",false) and building.instance(WALL).hp==120 and building.instance(WALL).version==int(damaged.version)+1,{"request":repair,"labour":done,"wall":building.instance(WALL)})
	var after_repair:Dictionary=repair_pack.duplicate(true);after_repair.timber-=1;after_repair.scrap-=1
	check("repair pays exact one board one scrap original hammer and no refund",Data.json_equal(after_repair,rt.actor("player").pack) and is_equal_approx(hammer_before-rt.tool(HAMMER).durability,0.9))
	check("paid repair reestablishes original body and sight barrier",not building.current_space().walk("player",north,south).ok and not building.current_space().line_clear(north,south))
	if not repair.ok or building.instance(WALL).hp!=120:save_actual(rt,"actual-repair-failed");return finish()
	note_state(rt,"actual enemy-destroyed barrier repaired with finite material");save_actual(rt,"actual-paid-barrier-repaired")
	if not resume_production(rt):stop_reason="actual existing line failed to resume";save_actual(rt,"actual-reproduction-failed");return finish()
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint());var cold:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var cold_host:=Native.new();var restored:Dictionary=cold_host._assemble(cold.capture) if cold.ok else cold;cold_host.free()
	check("final native canonical restore retains repaired wall goods and event",restored.get("ok",false) and Data.json_equal(cold.capture.facts,restored.runtime.facts()) and Data.json_equal(cold.capture.world.extensions,restored.world.snapshot().extensions),restored.get("reason"))
	save_actual(rt,"actual-defense-repair-production-completed")
	check("original19 G3 source bytes remain untouched",FileAccess.get_sha256(source_path)==source_sha)
	finish()

func resume_production(rt:RefCounted)->bool:
	# This is only the minimum 1-log input +1-log energy return to the SAME
	# paid machine. Tool reconstruction/withdrawal adversity belongs E.
	if not care(rt,45):return false
	var home:Dictionary=rt.world.extension("r34:gameplay").layout.home
	if not walk(rt,home).get("ok",false):return false
	var trees:Array=rt.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(rt.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(rt.actor("player"))))
	if trees.is_empty():check("normal finite standing tree still exists",false);return false
	var tree:Dictionary=trees[0];var logs_before:float=rt.actor("player").pack.get("log",0)
	var harvest:Dictionary=send(rt,"harvest",tree.id,{"tool_id":AXE,"direct":false})
	var done:Dictionary=progress(rt,600) if harvest.ok else {}
	var stump:bool=rt.world.entity(tree.id).data.harvest.phase=="stump"
	check("real remaining finite tree yields actual logs by original axe and travel",harvest.ok and done.get("finished",false) and stump,{"tree":tree.id,"ok":harvest.ok,"phase":rt.world.entity(tree.id).data.harvest.phase,"sim_seconds":done.get("sim_seconds"),"axe":rt.tool(AXE)})
	if not harvest.ok or not done.get("finished",false) or not stump:return false
	var drop:String=str(tree.data.outputId)
	if not take_source(rt,drop,{"log":2}):return false
	check("two real cut logs physically taken once",rt.actor("player").pack.get("log",0)==logs_before+2)
	var machine:Dictionary=rt._services.modules.instance("r34:normal-built-woodshop")
	var before:Dictionary=rt.world.extension("r34:production");var output_before:float=rt.stock(machine.stock_refs.output).items.get("timber",0)
	for spec:Array in [["input",1],["fuel",1]]:
		var id:String=machine.stock_refs[spec[0]]
		if not near_stock(rt,id):check("original machine service body route "+str(spec[0]),false);return false
		var supplied:Dictionary=send(rt,"deposit",id,{"items":{"log":spec[1]}})
		check("same original paid machine receives actual return log "+str(spec[0]),supplied.ok,supplied)
		if not supplied.ok:return false
	var configured:Dictionary=send(rt,"factory.configure",machine.id,{"recipe_id":"saw_timber","batches":1})
	check("same original machine admits one genuine post-repair batch",configured.ok,configured)
	if not configured.ok:return false
	for i:int in 150:
		step(rt)
		if rt.stock(machine.stock_refs.output).items.get("timber",0)==output_before+4:break
	var after:Dictionary=rt.world.extension("r34:production")
	check("real existing line returns four boards with one new unique settlement",rt.stock(machine.stock_refs.output).items.get("timber",0)==output_before+4 and after.settlements.size()==before.settlements.size()+1 and after.batches.size()==before.batches.size()+1 and after.settlements[-1].module_id==machine.id and rt.actor("player").pack.get("log",0)==logs_before and rt.stock(machine.stock_refs.input).items.get("log",0)==0 and rt.stock(machine.stock_refs.fuel).items.get("log",0)==0,{"before":before,"after":after,"machine":machine.id})
	step(rt,30)
	check("postcompletion ticks never duplicate production or refund defense costs",rt.stock(machine.stock_refs.output).items.get("timber",0)==output_before+4 and rt.world.extension("r34:production").settlements.size()==after.settlements.size() and rt.actor("player").pack.timber==0 and rt.actor("player").pack.scrap==0)
	note_state(rt,"same finite paid production line actually restarted")
	return rt.stock(machine.stock_refs.output).items.get("timber",0)==output_before+4

func finish()->void:
	if not stop_reason.is_empty():check("complete bounded original defense-repair-production route",false,stop_reason)
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"source_path":source_path,"source_sha256":source_sha,"stop_reason":stop_reason,"journey":journey,"samples":samples,"commands":commands,"combat":combat,"barrier_positions":barrier_positions,"hostile_wall_hits":hits,"fixture_injections":[],"scope":"Unmodified actual19 G3 warning checkpoint, finite paid original wall barrier (not new fence asset), original infected AI, break/repair and same machine resupply. No direct HP/damage/capture/terrain/material/actor edits, no renderer/OS/VA/performance/G5 qualification. Immutable PCK identity belongs external runner."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report,"",false,true));quit(1 if report.failed else 0)
