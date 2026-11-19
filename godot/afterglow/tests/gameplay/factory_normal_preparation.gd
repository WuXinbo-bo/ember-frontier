extends "res://tests/world/factory_normal_path.gd"
## Extend C's real normal-source opening with stop/retreat/recover and combat.
const Movement=preload("res://scripts/runtime/movement_policy.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
var journey:Array=[]
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs,"scope":"Actual normal C source tools, B supported routes and terrain, A finite self-care/native restore, E informed warning and original combat; no actor/item/health injection; seed713 source/headless, not OS/VA/package/economy qualification."}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
func body_state(actor:Dictionary)->Dictionary:
	return {"id":actor.id,"hp":actor.hp,"stamina":actor.stamina,"location":Geometry.location(actor),"pack":actor.pack.duplicate(true),"wounds":actor.get("wounds",[]).duplicate(true),"encounter_id":actor.get("encounter_id")}
func record(runtime:RefCounted,stage:String)->void:
	var a:Dictionary=runtime.actor("player");var state:Dictionary=runtime.world.extension(Gameplay.KEY)
	journey.append({"stage":stage,"time":runtime.clock(),"location":Geometry.location(a),"hp":a.hp,"stamina":a.stamina,"stamina_cap":Movement.stamina_max(a),"hunger":a.hunger,"thirst":a.thirst,"pack":a.pack.duplicate(true),"defense":state.defense.duplicate(true)})
func rest_once(runtime:RefCounted)->bool:
	var result:Dictionary=send(runtime,"rest")
	var recovered:Dictionary=progress(runtime,130) if result.ok else {}
	costs.get_or_add("rests",[]).append({"request":result,"finished":recovered.get("finished",false),"time":runtime.clock(),"actor":runtime.actor("player")})
	return result.ok and recovered.get("finished",false)
func evade(runtime:RefCounted,query:RefCounted,alive:Array)->bool:
	var player:Dictionary=runtime.actor("player")
	alive.sort_custom(func(a:String,b:String)->bool:return Geometry.point(runtime.actor(a)).distance_squared_to(Geometry.point(player))<Geometry.point(runtime.actor(b)).distance_squared_to(Geometry.point(player)))
	var away:Vector3=(Geometry.point(player)-Geometry.point(runtime.actor(str(alive[0])))).normalized()
	var best:Dictionary={};var score:float=0.0
	for angle:float in [0.0,PI/4,-PI/4,PI/2,-PI/2]:
		var direction:Vector3=away.rotated(Vector3.UP,angle)
		var raw:Dictionary=Geometry.location(player);raw.x+=direction.x*2.5;raw.z+=direction.z*2.5
		var point:Dictionary=query.standing_point(raw)
		if point.is_empty():continue
		var route:Dictionary=runtime._services.actions.route("player",Geometry.location(player),point)
		if not route.ok:continue
		var length:float=0;var last:Vector3=Geometry.point(player)
		for step:Dictionary in route.steps:
			if step.has("to"):length+=last.distance_to(Geometry.point(step.to));last=Geometry.point(step.to)
		if length>3.0:continue
		var nearest:float=INF
		for id:String in alive:nearest=minf(nearest,Geometry.point(point).distance_to(Geometry.point(runtime.actor(id))))
		if nearest>score:score=nearest;best=point
	var result:Dictionary=walk(runtime,best) if not best.is_empty() else {"ok":false,"reason":"no supported short retreat"}
	costs.get_or_add("combat_steps",[]).append({"stage":"backstep","time":runtime.clock(),"ok":result.get("ok",false),"reason":result.get("reason"),"location":Geometry.location(runtime.actor("player")),"hp":runtime.actor("player").hp})
	return result.get("ok",false)
func run()->void:
	var opening:Dictionary=normal_tools()
	if not opening.ok:return finish()
	var runtime:RefCounted=opening.runtime;var world:RefCounted=opening.world;var query:RefCounted=opening.query
	var sites:Array=world.extension("generation:RH-VILLAGE").get("regional_sites",[])
	check("normal journey consumes actual C v2 site",sites.size()==1)
	if sites.size()!=1:return finish()
	var site:Dictionary=sites[0];var pickaxe:String=opening.pickaxe;var axe:String=opening.axe
	var reached:Dictionary=walk(runtime,site.survey_point)
	check("normal finite tools reach actual survey by B route",reached.get("ok",false),reached)
	if not reached.get("ok",false):return finish()
	var survey:Dictionary=send(runtime,"settlement.survey","",{"site_id":site.id})
	var risk:Dictionary=send(runtime,"settlement.begin_route_work","",{"site_id":site.id,"accept_risk":true})
	check("normal on-site informed risk starts actual event",survey.ok and risk.ok,{"survey":survey,"risk":risk})
	if not risk.ok:return finish()
	record(runtime,"accepted")
	var before:Dictionary=site.goal_corridor.approach_before;var after:Dictionary=site.goal_corridor.approach_after
	var toward:Vector3=(Geometry.point(after)-Geometry.point(before)).normalized()
	var work_at:Dictionary=before.duplicate(true);work_at.x+=toward.x*1.25;work_at.z+=toward.z*1.25
	work_at=query.standing_point(work_at)
	check("normal actor approaches real stone face",not work_at.is_empty() and walk(runtime,work_at).get("ok",false))
	var remaining:Array=site.obstacle_cells.duplicate(true)
	remaining.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.y>b.y if a.y!=b.y else Vector2(a.x,a.z).distance_squared_to(Vector2(before.x*2,before.z*2))<Vector2(b.x,b.z).distance_squared_to(Vector2(before.x*2,before.z*2)))
	var first:Dictionary=remaining[0];var started:Dictionary=send(runtime,"terrain","",brush(first,"dig",pickaxe))
	for i in 3:runtime.tick(0.1)
	var active:Variant=runtime.actor("player").get("intent")
	check("normal stone work starts paid terrain intent",started.ok and active is Dictionary,started)
	if not started.ok or not active is Dictionary:return finish()
	var elapsed:float=float(active.elapsed);var held:Dictionary=send(runtime,"held","",{"held":false})
	for i in 5:runtime.tick(0.1)
	check("releasing work hold pauses labor while regional warning continues",held.ok and runtime.actor("player").intent.elapsed==elapsed and runtime.world.extension(Gameplay.KEY).defense.warning_remaining<runtime.world.extension(Gameplay.KEY).regional_objectives[site.id].warning_seconds)
	var cancelled:Dictionary=send(runtime,"cancel")
	check("normal worker may stop clearance without clearing cell or losing tool",cancelled.ok and world.cell_at(first.x,first.y,first.z)==3 and runtime.tool(pickaxe).holderId=="pack:player")
	var home:Dictionary=runtime.world.extension(Gameplay.KEY).layout.home
	var returned:Dictionary=walk(runtime,home)
	check("normal retreat follows full real home route",returned.get("ok",false),returned)
	if not returned.get("ok",false):return finish()
	var pack_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	var water:Dictionary=send(runtime,"drink");if water.ok:progress(runtime,20)
	var food:Dictionary=send(runtime,"eat");if food.ok:progress(runtime,20)
	check("retreat consumes original finite food and water without free refill",water.ok and food.ok and runtime.actor("player").pack.get("water")==float(pack_before.get("water",0))-1 and runtime.actor("player").pack.get("food")==float(pack_before.get("food",0))-1)
	var rest_start:float=runtime.clock()
	check("normal paid recovery follows original A rest duration and current body cap",rest_once(runtime) and absf(runtime.clock()-rest_start-12.0)<0.001 and absf(runtime.actor("player").stamina-Movement.stamina_max(runtime.actor("player")))<0.001)
	record(runtime,"home_prepared")
	var prepared:Dictionary=runtime.capture_checkpoint();var encoded:Dictionary=Store.encode(prepared)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("normal prepared checkpoint restores original event cells and inventory",restored.ok and Data.json_equal(restored.runtime.actor("player").pack,runtime.actor("player").pack) and restored.world.cell_at(first.x,first.y,first.z)==3)
	if not restored.ok:return finish()
	runtime=restored.runtime;world=restored.world;query=restored.services.buildings.current_space()
	var reapproach:Dictionary=walk(runtime,site.warning_points.approach_after)
	check("normal prepared actor returns to actual defense point through real bypass",reapproach.get("ok",false),reapproach)
	if not reapproach.get("ok",false):return finish()
	var final_action:bool=rest_once(runtime)
	record(runtime,"defense_prepared")
	check("warning covers real defense arrival and necessary preparation with operating margin",final_action and world.extension(Gameplay.KEY).defense.status=="warning" and world.extension(Gameplay.KEY).defense.warning_remaining>=10.0,world.extension(Gameplay.KEY).defense)
	var field:Dictionary=after.duplicate(true);field.z-=8.0;field=query.standing_point(field)
	var deployed:Dictionary=walk(runtime,field) if not field.is_empty() else {"ok":false}
	check("normal actor deploys via actual bypass to open defense ground",deployed.get("ok",false),deployed.get("reason"))
	var state:Dictionary=world.extension(Gameplay.KEY)
	for i in ceili(float(state.defense.get("warning_remaining",0))*10)+4:
		runtime.tick(0.1)
		if world.extension(Gameplay.KEY).defense.status=="active":break
	state=world.extension(Gameplay.KEY)
	check("normal preparation never freezes threat until player returns home",state.defense.status=="active" and state.defense.actors.size()==3,state.defense)
	if state.defense.status!="active":return finish()
	record(runtime,"before_combat")
	var attacks:int=0;var retreats:int=0
	# Approach the open far side with B's route, rather than chase a stale
	# enemy footpoint through the stone pile and stop inside all three bodies.
	for round_index in 450:
		state=world.extension(Gameplay.KEY)
		var alive:Array=state.defense.actors.filter(func(id:String)->bool:return float(runtime.actor(id).hp)>0)
		if alive.is_empty() or runtime.actor("player").hp<=0 or not deployed.get("ok",false):break
		var player:Dictionary=runtime.actor("player")
		alive.sort_custom(func(a:String,b:String)->bool:return Geometry.point(runtime.actor(a)).distance_squared_to(Geometry.point(player))<Geometry.point(runtime.actor(b)).distance_squared_to(Geometry.point(player)))
		var enemy:Dictionary=runtime.actor(str(alive[0]))
		var distance:float=Geometry.point(player).distance_to(Geometry.point(enemy))
		if distance>2.0:
			if distance>3.0:
				var toward_enemy:Vector3=(Geometry.point(enemy)-Geometry.point(player)).normalized()
				var approach:Dictionary=Geometry.location(player);approach.x+=toward_enemy.x*minf(2.5,distance-2.6);approach.z+=toward_enemy.z*minf(2.5,distance-2.6)
				approach=query.standing_point(approach)
				if approach.is_empty() or not walk(runtime,approach).get("ok",false):break
			runtime.tick(0.1);continue
		if float(player.stamina)<28:
			var opened:bool=true
			for step_index in 7:
				if not evade(runtime,query,alive):opened=false;break
			if not opened:break
			retreats+=1
			var recovery:Dictionary=send(runtime,"rest")
			if not recovery.ok:break
			for tick_index in 120:
				runtime.tick(0.1)
				var p:Dictionary=runtime.actor("player")
				var close:bool=alive.any(func(id:String)->bool:return Geometry.point(runtime.actor(id)).distance_to(Geometry.point(p))<2.2)
				if close or float(p.stamina)>=75 or p.get("intent")==null:break
			if runtime.actor("player").get("intent")!=null:send(runtime,"cancel")
			record(runtime,"combat_recovered")
			var residual:Dictionary=runtime.capture_checkpoint()
			var residual_encoded:Dictionary=Store.encode(residual)
			var residual_decoded:Dictionary=Store.decode(residual_encoded.text) if residual_encoded.ok else residual_encoded
			var residual_native:=Native.new();var residual_built:Dictionary=residual_native._assemble(residual_decoded.capture) if residual_decoded.ok else residual_decoded;residual_native.free()
			check("normal partial defense and paid recovery restore same remaining enemies without healing",residual_built.ok and Data.json_equal(body_state(residual_built.runtime.actor("player")),body_state(runtime.actor("player"))) and alive.all(func(id:String)->bool:return Data.json_equal(body_state(residual_built.runtime.actor(id)),body_state(runtime.actor(id)))) and Data.json_equal(residual_built.world.extension(Gameplay.KEY).defense,world.extension(Gameplay.KEY).defense),{"before":body_state(runtime.actor("player")),"after":body_state(residual_built.runtime.actor("player")) if residual_built.ok else residual_built})
			if not residual_built.ok:break
			runtime=residual_built.runtime;world=residual_built.world;query=residual_built.services.buildings.current_space()
			continue
		var strike:Dictionary=send(runtime,"attack",str(alive[0]),{"tool_id":axe})
		costs.get_or_add("combat_steps",[]).append({"stage":"attack","ok":strike.ok,"code":strike.get("code"),"time":runtime.clock(),"hp":runtime.actor("player").hp,"stamina":runtime.actor("player").stamina,"distance":distance,"location":Geometry.location(runtime.actor("player")),"enemy_hp":alive.map(func(id:String)->float:return runtime.actor(id).hp)})
		if not strike.ok:break
		attacks+=1
		# Attack recovery remains real time. A short supported B walk creates
		# space while the original enemies pursue at their original speed.
		var living:Array=alive.filter(func(id:String)->bool:return runtime.actor(id).hp>0)
		if not living.is_empty() and not evade(runtime,query,living):break
	runtime.tick(0.1)
	record(runtime,"combat_outcome")
	state=world.extension(Gameplay.KEY)
	check("normal supply recovery and real retreat permit finite defense outcome",state.defense.status=="cleared" and runtime.actor("player").hp>0,{"attacks":attacks,"retreats":retreats,"journey":journey})
	if state.defense.status=="cleared" and runtime.actor("player").hp>0:
		reached=walk(runtime,work_at)
		var removed:int=0
		if reached.get("ok",false):
			for cell:Dictionary in remaining:
				if runtime.actor("player").stamina<20 and not rest_once(runtime):break
				var result:Dictionary=send(runtime,"terrain","",brush(cell,"dig",pickaxe))
				if not result.ok or not progress(runtime,45).finished:break
				if world.cell_at(cell.x,cell.y,cell.z)==0:removed+=1
		check("after defense normal worker resumes all real clearance",removed==24,{"removed":removed,"actor":runtime.actor("player")})
		runtime.tick(0.1)
		check("normal regional objective completes only after actual final clearance",world.extension(Gameplay.KEY).regional_objectives[site.id].get("completed",false))
		record(runtime,"normal_route_completed")
	costs.normal_journey=journey
	finish()
