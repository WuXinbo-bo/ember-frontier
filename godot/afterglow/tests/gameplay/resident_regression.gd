extends "res://tests/integration/run_resident_life.gd"
## Reuse the retained-world checks, then real generated stocks and explicit
## needs/threat/blocked-route fixtures. Not an OS-input/RH player route.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
var output_dir:String

func finish()->void:
	output_dir=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output_dir)
	if runtime!=null and checks.all(func(c:Dictionary)->bool:return c.ok):regression()
	var report:Dictionary={"scope":"E real generated self-supply plus explicit needs/threat/blocked fixtures; not formal player/input/VA acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output_dir+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));host.free();quit(1 if report.failed else 0)

func regression()->void:
	var generated:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("real current generated assembly for new resident cases",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):return
	var baseline:Dictionary=runtime.capture_checkpoint()
	var owned:Array=runtime.facts().stocks.filter(func(s:Dictionary)->bool:return s.get("owner")=="village-resident" and float(s.items.get("water",0))>0)
	check("generated resident really owns finite searched water",not owned.is_empty() and owned[0].searched)
	if owned.is_empty():return
	var source:String=owned[0].id
	var thirsty:Dictionary=baseline.duplicate(true)
	for a:Dictionary in thirsty.facts.actors:
		if a.id=="village-resident":a.thirst=20.0
	if not mount(thirsty):return
	var old_position:Vector3=Geometry.point(runtime.actor("village-resident"))
	var consumed:=false
	for i:int in 1200:
		runtime.tick(0.1)
		if float(runtime.actor("village-resident").thirst)>60:consumed=true;break
	check("unjoined resident walks to OWN generated stock and drinks",consumed,{"actor":runtime.actor("village-resident"),"stock":runtime.stock(source)})
	check("own-stock use has real movement and exactly one water debit",old_position.distance_to(Geometry.point(runtime.actor("village-resident")))>1 and float(runtime.stock(source).items.water)==float(owned[0].items.water)-1)
	check("self supply does not touch player/team or consent",runtime.actor("player").pack==baseline.facts.actors[0].pack and not runtime.actor("village-resident").relationship.member and not runtime.actor("village-resident").relationship.consent)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("actual consumed stock and autonomous facts encode/decode",encoded.ok and decoded.ok)
	if decoded.ok and mount(decoded.capture):check("restore never refills consumed personal water",float(runtime.stock(source).items.water)==float(owned[0].items.water)-1)
	# Explicit finite need fixture: missing water must not prevent available food.
	var needs:Dictionary=baseline.duplicate(true)
	for a:Dictionary in needs.facts.actors:
		if a.id=="village-resident":a.hunger=20.0;a.thirst=20.0;a.pack={"food":1}
	if mount(needs):
		for i:int in 15:runtime.tick(0.1)
		check("thirst without carried water never starves available food",float(runtime.actor("village-resident").hunger)>54 and float(runtime.actor("village-resident").pack.get("food",0))==0)
	# An actual route failure must retain B's reason instead of idle text.
	var blocked:Dictionary=baseline.duplicate(true)
	for a:Dictionary in blocked.facts.actors:
		if a.id=="village-resident":
			a.self_routine={"version":1,"origin":Geometry.location(a),"phase":0,"next_decision":0.0}
			var to:Dictionary=Geometry.location(a);to.x+=10000
			a.intent={"owner":"residents","kind":"walk","id":"E:fixture:blocked-walk","steps":[{"kind":"move","to":to}],"step":0,"held":true}
	if mount(blocked):
		# B may move through initially clear ground before its blocked timer
		# starts. Wait for that real executor to finish, not a guessed 2.2s.
		for i:int in 400:
			runtime.tick(0.1)
			if runtime.actor("village-resident").intent==null:break
		var a:Dictionary=runtime.actor("village-resident")
		check("failed physical step retains exact real blocked fact",a.intent==null and a.self_routine.get("last_failure",{}).get("code")=="ROUTE_BLOCKED" and a.activity!="在住处附近守望",a)
	# Need during a valid existing walk enters the same A life service.
	var walking:Dictionary=baseline.duplicate(true)
	for a:Dictionary in walking.facts.actors:
		if a.id=="village-resident":a.thirst=20.0;a.pack={"water":1}
	if mount(walking):
		var a:Dictionary=runtime.actor("village-resident")
		var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.residents.context)
		var actor:Dictionary=tx.actor(a.id)
		var routine:Dictionary=runtime._services.residents._routine(actor)
		check("fixture has a genuine B-planned walking route",runtime._services.residents._walk(actor,routine,tx,runtime.clock()))
		check("fixture commits only the real planned intent",runtime._commit(tx.result()).ok)
		runtime.tick(0.1)
		check("low thirst interrupts walk into A runtime care",runtime.actor(a.id).get("intent",{}).get("owner")=="runtime")
		for i:int in 14:runtime.tick(0.1)
		check("walk interruption consumes exactly one owned water",runtime.actor(a.id).pack.water==0 and runtime.actor(a.id).thirst>64)
	# Threat is placed at a supported nearby indoor point, never an invisible
	# off-map threat; all movement is still B's ordinary executor.
	if mount(baseline):
		var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.residents.context)
		var a:Dictionary=tx.actor("village-resident")
		var routine:Dictionary=runtime._services.residents._routine(a)
		var points:Array=runtime._services.residents._destinations(a,routine,tx)
		points=points.filter(func(p:Dictionary)->bool:return Geometry.point(p).distance_to(Geometry.point(a))<6 and runtime._services.buildings.current_space().line_clear(Geometry.location(a),p,""))
		check("generated resident has supported threat fixture points",not points.is_empty())
		if not points.is_empty():
			var enemy:Dictionary=Initial.actor("infected:fixture-visible","visible threat",points[0],points[0],{})
			enemy.faction="infected";enemy.appearance_id="infected_walker";enemy.stunned_until=1000.0;tx.staged.actors.append(enemy)
			check("visible threat fixture commits valid shared facts",runtime._commit(tx.result()).ok)
			runtime.tick(0.1)
			var actor:Dictionary=runtime.actor(a.id)
			check("perceived threat chooses real avoid intent or exact safe failure",(actor.get("intent") is Dictionary and actor.intent.get("purpose")=="avoid") or str(actor.activity).begins_with("避险受阻："),actor)
			check("threat does not grant cooperation or supply",not actor.relationship.consent and actor.pack.is_empty())
	# Explicit supported bed fixtures distinguish stamina recovery on the
	# ground from fatigue recovery at a real, owned, prepared sleeping place.
	if not mount(baseline):return
	var bed:Dictionary=runtime.world.entity("RH-VILLAGE:neighbor:sleeping-place")
	var at:Dictionary=Geometry.location(bed);at.x+=1.1
	var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
	check("owned generated bed has a supported nearby rest point",not feet.is_empty())
	if feet.is_empty():return
	for prepared:bool in [false,true]:
		var rest:Dictionary=baseline.duplicate(true)
		rest.world.entities[bed.id].data.prepared=prepared
		for a:Dictionary in rest.facts.actors:
			if a.id=="village-resident":a.merge(feet,true);a.stamina=20.0;a.fatigue=70.0
		if mount(rest):
			runtime.tick(0.1)
			var intent:Dictionary=runtime.actor("village-resident").intent
			check("self rest selects only actually prepared owned bed "+str(prepared),intent.owner=="runtime" and intent.kind=="rest" and (intent.get("target_id","")==bed.id if prepared else str(intent.get("target_id","")).is_empty()),intent)
			for i:int in 10:runtime.tick(0.1)
			var resident:Dictionary=runtime.actor("village-resident")
			check("A alone restores stamina and only prepared bed restores fatigue "+str(prepared),resident.stamina>24 and (resident.fatigue<69 if prepared else resident.fatigue>=70),resident)
	# Incapacity cancels this service's real walk without a final free step.
	if mount(baseline):
		var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.residents.context)
		var a:Dictionary=tx.actor("village-resident")
		check("incapacity fixture starts with B-planned resident walk",runtime._services.residents._walk(a,runtime._services.residents._routine(a),tx,runtime.clock()))
		a.hp=0.0
		check("explicit incapacitated walking actor validates in shared facts",runtime._commit(tx.result()).ok)
		var before:Dictionary=runtime.actor(a.id)
		runtime.tick(0.1)
		var after:Dictionary=runtime.actor(a.id)
		check("incapacitated self walk stops without movement inventory or growth",after.intent==null and after.activity=="已失能" and Geometry.point(before)==Geometry.point(after) and before.pack==after.pack and before.skills==after.skills)
