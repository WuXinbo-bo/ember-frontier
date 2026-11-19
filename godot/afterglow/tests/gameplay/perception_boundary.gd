extends "res://tests/gameplay/social_boundary.gd"
## Explicit supported actor/obstacle fixtures; genuine C continuous segment,
## B sight/motion and E's distinct perception/melee/awareness ranges.

func wide_pair(distance:float)->Dictionary:
	var home:Dictionary=runtime.world.region("RH-HOME")
	var edge:float=float(home.bounds.min.z)
	var query:RefCounted=runtime._services.buildings.current_space()
	for x:int in range(3,61):
		var points:Array=[]
		for side:float in [1.0,-1.0]:
			var z:float=edge+side*distance*0.5
			var y:Variant=runtime.world.surface_height(float(x),z)
			if y==null:continue
			var feet:Dictionary=query.standing_point({"x":float(x),"y":float(y),"z":z,"regionId":"RH-HOME" if side>0 else "RH-VILLAGE","buildingId":null,"storeyId":null})
			if not feet.is_empty() and feet.get("buildingId")==null:points.append(feet)
		if points.size()!=2:continue
		if runtime.world.continuous_outdoor_segment(points[0],points[1],12.0,true).ok and query.line_clear(points[0],points[1],""):
			var step:Dictionary=points[0].duplicate(true);step.z-=0.1
			if runtime._services.actions.move_step("player",points[0],step).ok:return {"from":points[0],"to":points[1]}
	return {}

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="real-generated-range-specific-perception-with-explicit-supported-actors"
	host=Client.new()
	var built:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("current generated perception world prepares",built.ok,built.get("reason"))
	if not built.ok or not mount(built.capture):finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	for distance:float in [6.0,10.5]:
		if not mount(baseline):finish();return
		var pair:Dictionary=wide_pair(distance)
		check(str(distance)+"m shared edge has supported clear actual endpoints",not pair.is_empty(),pair)
		if pair.is_empty():continue
		check(str(distance)+"m is outside hand-contact continuity",not runtime.world.continuous_outdoor_contact(pair.from,pair.to).ok)
		var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
		for a:Dictionary in tx.staged.actors:
			if a.id=="player":a.merge(pair.to,true);a.intent=null
			else:a.hp=0.0;a.intent=null
		var enemy:Dictionary=Initial.actor("infected:E-range","显式感知目标",pair.from,pair.from,{})
		enemy.faction="infected";enemy.appearance_id="infected_walker";tx.staged.actors.append(enemy)
		check("range fixture commits all real supported bodies "+str(distance),runtime._commit(tx.result()).ok)
		var observed:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
		var threat:Dictionary=runtime._services.residents._threat(observed.actor("player"),observed)
		check("resident 7m sight uses its own range "+str(distance),not threat.is_empty() if distance<7 else threat.is_empty(),threat)
		var enemy_before:Dictionary=observed.actor(enemy.id).duplicate(true)
		runtime._services.gameplay._enemy_step(observed,observed.actor(enemy.id),observed.extension(Gameplay.KEY),0.1,runtime.clock())
		check("12m hostile awareness crosses label and uses B real movement "+str(distance),Geometry.point(observed.actor(enemy.id))!=Geometry.point(enemy_before),observed.actor(enemy.id))
		check("awareness advance never grants ranged melee damage "+str(distance),observed.actor("player").hp==100)
		check("range motion commits through A budget and facts",runtime._commit(observed.result()).ok)
		if distance<7:
			# A real wall blocks perception but awareness retains its existing
			# pursuit/structure behavior. This is not a global same-region wall.
			var middle:Vector3=(Geometry.point(pair.from)+Geometry.point(pair.to))*0.5
			var wall:Dictionary={"id":"E:range-opaque","kind":"prop","regionId":pair.from.regionId,"position":Geometry.json_point(middle),"bounds":Geometry.json_box(AABB(middle+Vector3(-0.5,-1,-0.03),Vector3(1,4,0.06))),"revision":0,"data":{"solid":true,"opaque":true}}
			var committed:Dictionary=runtime._commit({"ok":true,"world_changes":[{"op":"entity.put","id":wall.id,"before_exists":false,"before":null,"after":wall}],"fact_changes":[]})
			check("real thin boundary wall commits",committed.ok,committed)
			if committed.ok:
				observed=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
				check("7m perception does not see through true opaque wall",runtime._services.residents._threat(observed.actor("player"),observed).is_empty())
	melee_case(baseline,false)
	melee_case(baseline,true)
	finish()

func melee_case(baseline:Dictionary,blocked:bool)->void:
	if not mount(baseline):return
	var pair:Dictionary=edge_pair()
	if pair.is_empty():check("melee pair exists",false);return
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
	var guard:Dictionary=tx.actor("village-resident")
	guard.merge(pair.from,true);guard.intent=null;guard.job="guard";guard.relationship={"member":true,"consent":true};guard.cooldown=0.0
	var enemy:Dictionary=Initial.actor("infected:E-melee","显式近身目标",pair.to,pair.to,{})
	enemy.faction="infected";enemy.appearance_id="infected_walker";enemy.stunned_until=1000.0;tx.staged.actors.append(enemy)
	check("melee fixture commits real close actors "+str(blocked),runtime._commit(tx.result()).ok)
	if blocked:
		var middle:Vector3=(Geometry.point(pair.from)+Geometry.point(pair.to))*0.5
		var wall:Dictionary={"id":"E:melee-opaque","kind":"prop","regionId":pair.from.regionId,"position":Geometry.json_point(middle),"bounds":Geometry.json_box(AABB(middle+Vector3(-0.15,0,-0.04),Vector3(0.3,1.8,0.08))),"revision":0,"data":{"solid":true,"opaque":true}}
		check("melee opaque wall commits",runtime._commit({"ok":true,"world_changes":[{"op":"entity.put","id":wall.id,"before_exists":false,"before":null,"after":wall}],"fact_changes":[]}).ok)
	var before:Dictionary=runtime.actor(enemy.id)
	var plan:Dictionary=runtime._services.gameplay.advance(0.1)
	check("actual guard step uses single A commit "+str(blocked),plan.ok and runtime._commit(plan).ok)
	check("guard cross-edge melee follows real 2.05m and sight "+str(blocked),runtime.actor(enemy.id).hp==float(before.hp)-(0.0 if blocked else 6.0),runtime.actor(enemy.id))
