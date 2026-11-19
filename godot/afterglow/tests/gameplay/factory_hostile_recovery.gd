extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## Post19 B/E sources with immutable19 baseline; real original event, no fixtures.
const AXE=SHED+":tool:salvaged_axe"
const MACHINE="r34:normal-built-woodshop"
const Shape=preload("res://scripts/modules/module_geometry.gd")
var current:RefCounted
var commands:Array=[]
var hits:Array=[]
var event_ids:Dictionary={}
var samples:Array=[]
var checkpoints:Array=[]
var stop_reason:String=""
var natural_roster:Array=[]
var original_people:Array=[]
var initial_timber:float=0
var pre_attack:Dictionary={}
var last_sample:float=-1
func send(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var r:Dictionary=rt.command({"command_id":"E:R34-63:"+source_sha.substr(0,16)+":%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
	commands.append({"time":rt.clock(),"kind":kind,"target":target,"payload":payload.duplicate(true),"destination":destination.duplicate(true),"ok":r.get("ok"),"code":r.get("code"),"reason":r.get("reason")})
	observe(rt);return r
func observe(rt:RefCounted)->void:
	current=rt
	for e:Dictionary in rt.facts().ledger:
		if event_ids.has(e.id):continue
		event_ids[e.id]=true
		if e.kind in ["module-hostile-hit","module-ruined","module-damaged","combat-hit","factory-batch-completed","module-repaired"]:hits.append(e.duplicate(true))
	if rt.clock()-last_sample>=1:
		last_sample=rt.clock()
		samples.append({"time":rt.clock(),"machine":rt._services.modules.instance(MACHINE),"actors":rt.facts().actors.map(func(a:Dictionary)->Dictionary:return {"id":a.id,"hp":a.hp,"location":Geometry.location(a),"intent":a.intent,"activity":a.get("activity"),"cooldown":a.get("cooldown"),"stamina":a.stamina}),"defense":rt.world.extension(Gameplay.KEY).defense,"production":rt._services.production.factory_projection()})
func step(rt:RefCounted,count:int=1)->void:
	for i:int in count:
		if Time.get_ticks_msec()-started>240000 or ticks>=15000:stop_reason="bounded driver wall/tick budget";finish();return
		rt.tick(0.1);ticks+=1;observe(rt)
func point(rt:RefCounted,x:float,z:float)->Dictionary:
	var p:Dictionary={"x":x,"y":rt.world.surface_height(x,z),"z":z,"regionId":"RH-HOME" if z>=0 else "RH-VILLAGE","buildingId":null,"storeyId":null}
	return rt._services.buildings.current_space().standing_point(p)
func travel(rt:RefCounted,x:float,z:float,label:String)->bool:
	var at:Dictionary=point(rt,x,z)
	var r:Dictionary=walk(rt,at) if not at.is_empty() else {"ok":false,"reason":"unsupported actual feet"}
	if not r.get("ok",false):stop_reason=label+": "+str(r.get("reason","actual travel incomplete"));save(rt,"failed-route");return false
	return true
func capture_at(rt:RefCounted,label:String)->void:
	var e:Dictionary=save(rt,label);checkpoints.append({"label":label,"ok":e.get("ok"),"time":rt.clock()});print("HOSTILE_STAGE "+label+" "+str(rt.clock()))
func enemy_distance(rt:RefCounted,furthest:bool=false)->float:
	var d:float=0.0 if furthest else INF
	for id:String in natural_roster:
		if rt.actor(id).hp<=0:continue
		var distance:float=Geometry.point(rt.actor(id)).distance_to(Geometry.point(rt.actor("player")))
		d=maxf(d,distance) if furthest else minf(d,distance)
	return d
func lure(rt:RefCounted,x:float,z:float)->bool:
	# Wait only while real infected have awareness, never reset a target or clock.
	for i:int in 180:
		if enemy_distance(rt,true)<=6.0:break
		step(rt)
	if enemy_distance(rt,true)>11.5:stop_reason="real infected lost 12m awareness before lure waypoint";capture_at(rt,"failed-lost-awareness");return false
	return travel(rt,x,z,"lure waypoint "+str(Vector2(x,z)))
func self_care(rt:RefCounted)->bool:
	for s:Array in [["thirst","water","drink"],["hunger","food","eat"]]:
		if float(rt.actor("player")[s[0]])<40 and float(rt.actor("player").pack.get(s[1],0))>=1:
			var c:Dictionary=send(rt,s[2]);if not c.ok or not progress(rt,50).finished:return false
	if rt.actor("player").stamina<65:
		var rest:Dictionary=send(rt,"rest");if not rest.ok or not progress(rt,150).finished:return false
	return true
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1];DirAccess.make_dir_recursive_absolute(output_dir)
	var txt:String=FileAccess.get_file_as_string(source_path);source_sha=txt.sha256_text();sources.append({"path":source_path,"sha256":source_sha})
	var d:Dictionary=Store.decode(txt);check("original19 normal53 unedited source decodes",d.ok)
	if not d.ok:return finish()
	var n:=Native.new();var built:Dictionary=n._assemble(d.capture);n.free()
	check("19 baseline plus explicit post19 B E sources mounts real Runtime",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime;current=rt
	# Same original C page residency preparation as the normal G3 driver.
	for region_id:String in ["RH-HOME","RH-VILLAGE"]:
		while not rt.world.region_is_resident(region_id):
			var warm:Dictionary=rt.world.prepare_region_residency(region_id,true,rt.world.get_revision(),32)
			var committed:Dictionary=rt._commit({"world_changes":warm.get("world_changes",[]),"fact_changes":[],"events":[]}) if warm.get("ok",false) else warm
			if not committed.get("ok",false):check("original C residency pages warm through Runtime",false,committed);return finish()
	check("new B hostile API is actual modules service",rt._services.modules.has_method("strike_hostile"))
	if not rt._services.modules.has_method("strike_hostile"):stop_reason="new B implementation unavailable";return finish()
	if args.size()>3 and args[3]=="recover":
		original_people=rt.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")!="infected").map(func(a:Dictionary)->String:return a.id)
		natural_roster=rt.world.extension(Gameplay.KEY).defense.actors.duplicate()
		initial_timber=total_timber(rt)
		check("explicit actual natural-damage checkpoint has original three attackers and paid prefed damaged machine",natural_roster.size()==3 and rt._services.modules.instance(MACHINE).status=="damaged" and rt.stock(MACHINE+":stock:input").items.get("log",0)==2)
		recover_production(rt);return
	original_people=rt.facts().actors.map(func(a:Dictionary)->String:return a.id)
	initial_timber=total_timber(rt)
	for t:Dictionary in rt.world.extension("r34:logistics").tasks:
		if t.status not in ["completed","cancelled"]:
			send(rt,"logistics.cancel",t.id)
			if t.phase=="deliver":send(rt,"logistics.retarget",t.id,{"destination_id":t.destination_id})
	step(rt,100)
	for id:String in guards:
		if not social_contact(rt,id,false):stop_reason="original consent contact unreachable";return finish()
		var withdrawn:Dictionary=send(rt,"consent",id,{"enabled":false})
		check("original person explicitly withdraws guard cooperation "+id,withdrawn.ok,withdrawn)
		if not withdrawn.ok:return finish()
	if not self_care(rt):stop_reason="finite self-care failed";return finish()
	# One actual tree feeds two original batches; no materials are constructed.
	var trees:Array=rt.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(rt.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(rt.actor("player"))))
	var cut_id:String=""
	for tree:Dictionary in trees.slice(0,8):
		var c:Dictionary=send(rt,"harvest",tree.id,{"direct":false,"tool_ids":[AXE]})
		if not c.ok:continue
		if progress(rt,1200).finished and rt.world.entity(tree.id).data.harvest.phase=="stump":cut_id=tree.id;break
		stop_reason="real finite harvest incomplete";return finish()
	check("real standing source tree felled for three finite logs",not cut_id.is_empty(),cut_id)
	if cut_id.is_empty():return finish()
	if not transfer(rt,"take",rt.world.entity(cut_id).data.outputId,{"log":3}):return finish()
	var configured:Dictionary=send(rt,"factory.configure",MACHINE,{"recipe_id":"saw_timber","batches":2})
	var paused:Dictionary=send(rt,"factory.pause",MACHINE)
	check("original machine configures and pauses before physical feed",configured.ok and paused.ok)
	for spec:Array in [["input",2],["fuel",1]]:
		if not transfer(rt,"deposit",MACHINE+":stock:"+str(spec[0]),{"log":spec[1]}):return finish()
	capture_at(rt,"actual-fed-machine-before-risk")
	var site:Dictionary=rt.world.extension("generation:RH-VILLAGE").regional_sites[0]
	for waypoint:Vector2 in [Vector2(34,4),Vector2(34,0.5),Vector2(34,-0.5),Vector2(34,-12),Vector2(34,-28),Vector2(34,-40)]:
		if not travel(rt,waypoint.x,waypoint.y,"segmented original survey approach"):return finish()
	if not walk(rt,site.survey_point).get("ok",false):stop_reason="original survey route failed";return finish()
	var survey:Dictionary=send(rt,"settlement.survey","",{"site_id":site.id})
	var risk:Dictionary=send(rt,"settlement.begin_route_work","",{"site_id":site.id,"accept_risk":true})
	check("real on-site survey and informed risk start unchanged event",survey.ok and risk.ok,{"survey":survey,"risk":risk})
	if not risk.ok:return finish()
	# Actual C bypass reaches the north open side before original warning ends.
	if not travel(rt,38,-43,"approach C bypass south"):return finish()
	if not travel(rt,38,-54,"approach open original spawn flank"):return finish()
	if not self_care(rt):stop_reason="paid pre-combat care failed";return finish()
	for i:int in 1500:
		step(rt)
		if rt.world.extension(Gameplay.KEY).defense.status=="active":break
	natural_roster=rt.world.extension(Gameplay.KEY).defense.actors.duplicate()
	check("unchanged regional event creates exactly original three live infected",natural_roster.size()==3 and rt.facts().actors.size()==original_people.size()+3 and natural_roster.all(func(id:String)->bool:return rt.actor(id).hp==48),natural_roster)
	if natural_roster.size()!=3:return finish()
	capture_at(rt,"actual-original-enemies-before-lure")
	# Pull them east of original stone before moving south along its real bypass.
	for waypoint:Vector2 in [Vector2(39,-54),Vector2(39,-51),Vector2(39,-48),Vector2(39,-45),Vector2(39,-42),Vector2(37,-39),Vector2(35,-36)]:
		if not lure(rt,waypoint.x,waypoint.y):return finish()
	for z:int in range(-33,4,3):
		if not lure(rt,34,z):return finish()
	for waypoint:Vector2 in [Vector2(32,4),Vector2(29,4),Vector2(26,4),Vector2(30.5,4),Vector2(30.5,7),Vector2(30.5,10),Vector2(30.5,13.8),Vector2(27,13.8)]:
		if not lure(rt,waypoint.x,waypoint.y):return finish()
		if hits.any(func(e:Dictionary)->bool:return e.kind=="module-hostile-hit" and e.module_id==MACHINE):break
	capture_at(rt,"actual-enemies-at-machine")
	var module_before:Dictionary=rt._services.modules.instance(MACHINE)
	for i:int in 200:
		step(rt)
		if rt._services.modules.instance(MACHINE).hp<300:break
	var damaged:Dictionary=rt._services.modules.instance(MACHINE)
	var machine_hits:Array=hits.filter(func(e:Dictionary)->bool:return e.kind=="module-hostile-hit" and e.module_id==MACHINE)
	check("real pursuit collision naturally damages actual paid machine through B only",damaged.hp<300 and damaged.hp>0 and not machine_hits.is_empty() and machine_hits.all(func(e:Dictionary)->bool:return natural_roster.has(e.actor_id) and e.damage<=12 and e.hostile),{"machine":damaged,"hits":machine_hits})
	if machine_hits.is_empty():stop_reason="natural pursuit did not contact original machine";capture_at(rt,"actual-machine-no-natural-hit");return finish()
	# A damaged machine must stop even after ordinary resume; preserve input/fuel.
	var resumed:Dictionary=send(rt,"factory.resume",MACHINE)
	step(rt,2)
	var projection:Array=rt._services.production.factory_projection().orders.filter(func(o:Dictionary)->bool:return o.module_id==MACHINE)
	check("natural machine injury blocks real production before repairs",resumed.ok and projection.size()==1 and projection[0].blockers.has("damaged"),projection)
	capture_at(rt,"actual-natural-machine-damage")
	var restored:Dictionary=cold_restore(rt,"actual-natural-machine-damage-cold")
	if not restored.ok:return finish()
	rt=restored.runtime
	recover_production(rt)
func recover_production(rt:RefCounted)->void:
	# Draw original attackers away from shell and kill only through normal combat.
	if not travel(rt,34,16,"draw enemy to open work apron"):return finish()
	for i:int in 1800:
		var living:Array=natural_roster.filter(func(id:String)->bool:return rt.actor(id).hp>0)
		if living.is_empty() or rt.actor("player").hp<=0:break
		if rt.actor("player").intent!=null:step(rt);continue
		living.sort_custom(func(a:String,b:String)->bool:return Geometry.point(rt.actor(a)).distance_squared_to(Geometry.point(rt.actor("player")))<Geometry.point(rt.actor(b)).distance_squared_to(Geometry.point(rt.actor("player"))))
		var enemy:Dictionary=rt.actor(str(living[0]));var distance:float=Geometry.point(enemy).distance_to(Geometry.point(rt.actor("player")))
		if distance<=2.0 and rt.actor("player").stamina>=14 and rt.actor("player").get("cooldown",0)<=0:send(rt,"attack",enemy.id,{"tool_id":AXE})
		if rt.actor("player").stamina<28:
			# Real retreat beyond awareness, then original 12s rest; no reset.
			for retreat:int in 10:
				if enemy_distance(rt)>13:break
				if not evade(rt,rt._services.buildings.current_space(),living):stop_reason="real stamina retreat obstructed";return finish()
			if enemy_distance(rt)>12:
				var rested:Dictionary=send(rt,"rest")
				if rested.ok:progress(rt,150)
				var approach:Dictionary=Geometry.location(rt.actor(str(living[0])));approach.x+=2.0
				var supported:Dictionary=rt._services.buildings.current_space().standing_point(approach)
				if not supported.is_empty():walk(rt,supported)

		step(rt)
	check("original enemies truly defeated before paid repair no false event clearance",rt.world.extension(Gameplay.KEY).defense.status=="cleared" and natural_roster.all(func(id:String)->bool:return rt.actor(id).hp<=0) and rt.actor("player").hp>0,rt.facts().actors)
	if rt.world.extension(Gameplay.KEY).defense.status!="cleared":stop_reason="original combat failed before repair";return finish()
	if not self_care(rt):return finish()
	var module:Dictionary=rt._services.modules.instance(MACHINE)
	if module.status=="ruined":stop_reason="natural attackers ruined machine; real budget insufficient new drive/rebuild requires separate exact path";return finish()
	var repair_port:Dictionary={}
	for p:Dictionary in Shape.ports(module,Modules.definition(module.definition_id)):
		if p.purpose=="repair":repair_port=p
	var reached:Dictionary=walk(rt,repair_port.location)
	check("survivor physically reaches original attacked module repair surface",reached.get("ok",false),reached)
	if not reached.get("ok",false):return finish()
	var pack_before:Dictionary=rt.actor("player").pack.duplicate(true);var hammer_before:float=rt.tool(HAMMER).durability;var paid:Dictionary=module.paid_cost.duplicate(true)
	var repair:Dictionary=send(rt,"module.repair",MACHINE,{"source_id":"pack:player","tool_id":HAMMER})
	var done:Dictionary=progress(rt,200) if repair.ok else {}
	var fixed:Dictionary=rt._services.modules.instance(MACHINE)
	check("same naturally damaged machine repaired by real eight-second original cost",repair.ok and done.get("finished",false) and fixed.hp==300 and fixed.status=="operational" and rt.actor("player").pack.timber==pack_before.timber-2 and rt.actor("player").pack.scrap==pack_before.scrap-1 and rt.tool(HAMMER).durability<hammer_before and Data.json_equal(paid,fixed.paid_cost),{"repair":repair,"module":fixed,"pack":rt.actor("player").pack})
	if not repair.ok:return finish()
	capture_at(rt,"actual-paid-machine-repair")
	var before:Dictionary=rt.world.extension("r34:production");var output:float=rt.stock(BOARDS).items.get("timber",0)
	for i:int in 300:
		step(rt)
		if rt.stock(BOARDS).items.get("timber",0)>=output+8:break
	var after:Dictionary=rt.world.extension("r34:production")
	check("same repaired machine completes two genuine batches from original prefed logs",rt.stock(BOARDS).items.get("timber",0)==output+8 and after.settlements.size()==before.settlements.size()+2 and total_timber(rt)==initial_timber-2+8,{"before":before,"after":after,"timber":total_timber(rt)})
	check("cache tools cargo and withdrawal retained without free replacement",rt.tool(HAMMER).holderId=="pack:player" and guards.all(func(id:String)->bool:return not rt.actor(id).relationship.consent) and rt.stock(MACHINE+":stock:input").items.get("log",0)==0 and rt.stock(MACHINE+":stock:fuel").items.get("log",0)==0)
	var restored:Dictionary=cold_restore(rt,"actual-natural-attack-paid-repair-production")
	check("final canonical restore retains actual repaired production and real dead roster",restored.ok and restored.runtime._services.modules.instance(MACHINE).hp==300 and restored.world.extension(Gameplay.KEY).defense.status=="cleared")
	capture_at(rt,"actual-natural-attack-paid-repair-production-completed");finish()
func finish()->void:
	if not stop_reason.is_empty():check("complete natural machine attack repair production journey",false,stop_reason)
	if current!=null:save(current,"actual-final-failure" if checks.any(func(c:Dictionary)->bool:return not c.ok) else "actual-final-success")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"source":sources,"commands":commands,"samples":samples,"events":hits,"checkpoints":checkpoints,"ticks":ticks,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"stop_reason":stop_reason,"original_people":original_people,"natural_roster":natural_roster,"fixture_injections":[],"scope":"Post19 explicit B/E source overlay on immutable19 PCK; original19 actual normal53, actual study/risk/original3infected/movement/contact attacks, finite tools/material/repair/production/cold. No fixture enemy/HP/damage/material/position/capture, no renderer/import/export/OS/VA/FPS or whole63 qualification. Not claim new production in19."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed,"stop":stop_reason}));quit(1 if failed else 0)
