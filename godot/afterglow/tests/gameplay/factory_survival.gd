extends SceneTree
## Actual C/B/A assembly and E single-step survival; altered needs are fixtures.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Movement=preload("res://scripts/runtime/movement_policy.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Workforce=preload("res://scripts/runtime/settlement_workforce.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
var host:Node
var runtime:RefCounted
var base:Dictionary
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func mount(capture:Dictionary)->bool:
	var result:Dictionary=host._assemble(capture)
	check("actual native assembler accepts survival checkpoint",result.ok,result.get("reason"))
	if result.ok:runtime=result.runtime
	return result.ok
func npc_fixtures(capture:Dictionary,thirst:float=20.0,water:float=1.0)->void:
	for a:Dictionary in capture.facts.actors:
		if a.id=="player":continue
		a.intent=null;a.erase("self_routine");a.pack={"water":water} if water>0 else {};a.thirst=thirst;a.hunger=80.0;a.fatigue=0.0;a.stamina=100.0
func advance_decision()->Dictionary:
	var plan:Dictionary=runtime._services.workforce.advance(0.1)
	if not plan.ok:return plan
	return runtime._commit(plan)
func set_region_detail(region_id:String,detailed:bool)->bool:
	# Change one real lattice metadata flag; never replace the Runtime predicate.
	var world:RefCounted=runtime.world;var r:Dictionary=world.region(region_id);var cfg:Dictionary=world.config()
	var width:float=float(cfg.cellSize)*int(cfg.chunkCells)
	var key:String=Data.key(Vector3i(floori(r.bounds.min.x/width),floori(maxf(r.bounds.min.y,int(cfg.minCellY)*float(cfg.cellSize))/width),floori(r.bounds.min.z/width)))
	var plan:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":not detailed,"after":detailed}],world.get_revision())
	return plan.ok and world.commit_prepared(plan.capability).ok
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles()
	check("real B generation profiles available",profiles.ok)
	if not profiles.ok:finish();return
	var generated:Dictionary=Assembly.generate(713,profiles.profiles)
	var initial:Dictionary=Assembly.prepare(generated)
	check("normal C B E finite opening assembled",initial.ok,initial.get("reason"))
	if not initial.ok:finish();return
	base=initial.capture.duplicate(true)
	if not mount(base):finish();return
	var before:Dictionary=runtime.capture_checkpoint()
	var legacy:Dictionary=runtime._services.residents.advance(0.1)
	check("legacy resident advance never schedules R34",legacy.ok and legacy.fact_changes.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	var needs:Dictionary=base.duplicate(true);npc_fixtures(needs)
	if not mount(needs):finish();return
	var player_pack:Dictionary=runtime.actor("player").pack.duplicate(true)
	runtime.tick(0.1)
	var caring:int=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.id!="player" and a.get("intent") is Dictionary and a.intent.owner=="runtime").size()
	check("two first-time thirsty NPCs admit one new care intent per fixed step",caring==1,runtime.facts().actors)
	runtime.tick(0.1)
	caring=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.id!="player" and a.get("intent") is Dictionary and a.intent.owner=="runtime").size()
	check("other thirsty NPC is served on the next step",caring==2)
	for i in 16:runtime.tick(0.1)
	for id:String in ["village-resident","repair-resident"]:
		var a:Dictionary=runtime.actor(id)
		check(id+" consumes exactly one real water through A life",float(a.pack.get("water",0))==0 and float(a.thirst)>64 and not a.relationship.consent,{"pack":a.pack,"thirst":a.thirst})
	check("care leaves player inventory intact and uses A clock",runtime.actor("player").pack==player_pack and absf(runtime.clock()-1.8)<0.000001)
	var failure:Dictionary=base.duplicate(true);npc_fixtures(failure,20,0)
	if not mount(failure):finish();return
	check("failed need prepares valid A transaction",advance_decision().ok and advance_decision().ok)
	for id:String in ["village-resident","repair-resident"]:
		var a:Dictionary=runtime.actor(id)
		check(id+" empty unauthorized supplies give no imaginary recovery",a.pack.is_empty() and a.thirst==20 and a.intent==null and a.self_routine.last_failure.code=="NO_ITEM" and a.self_routine.next_decision>=runtime.clock()+1)
	before=runtime.capture_checkpoint();var no_retry:Dictionary=runtime._services.workforce.advance(0.1)
	check("unchanged failure is not retried before one simulated second",no_retry.ok and no_retry.fact_changes.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	var wake:Dictionary=runtime._commit({"events":[{"kind":"inventory-transfer","actor_id":"player"}],"fact_changes":[],"world_changes":[]})
	check("one committed relevant revision wakes waiting people",wake.ok and advance_decision().ok and advance_decision().ok)
	no_retry=runtime._services.workforce.advance(0.1)
	check("same revision cannot repeatedly wake failed decisions",no_retry.ok and no_retry.fact_changes.is_empty())
	# Unknown shared supplies are never searched by autonomous people.
	var private:Dictionary=base.duplicate(true);npc_fixtures(private,20,0)
	for s:Dictionary in private.facts.stocks:s.searched=false
	if not mount(private):finish();return
	var stocks_before:Array=runtime.facts().stocks.duplicate(true)
	advance_decision();advance_decision()
	check("unjoined people do not search or take unknown team stocks",Data.json_equal(stocks_before,runtime.facts().stocks) and runtime.actor("repair-resident").pack.is_empty())
	# A known local stock is an explicit finite source fixture at real B feet.
	var shared:Dictionary=base.duplicate(true);npc_fixtures(shared,20,0)
	for a:Dictionary in shared.facts.actors:
		if a.id=="repair-resident":a.relationship.member=true;a.relationship.consent=true;a.householdId="home-residents";a.job="rest"
	var receiver:Dictionary=shared.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="repair-resident")[0]
	shared.facts.stocks.append({"id":"fixture:finite-shared-water","items":{"water":1},"location":Geometry.location(receiver),"owner":"home-residents","searched":true})
	if not mount(shared):finish();return
	check("member takes one real authorized local water using B transfer",advance_decision().ok and runtime.stock("fixture:finite-shared-water").items.water==0 and runtime.actor("repair-resident").pack.get("water")==1)
	for i in 18:runtime.tick(0.1)
	check("shared water is consumed once by A without another inventory",runtime.actor("repair-resident").pack.get("water")==0 and runtime.actor("repair-resident").thirst>64 and runtime.stock("fixture:finite-shared-water").items.water==0)
	# Existing B handoff/cargo cannot be seized by a new E idle decision.
	var cargo:Dictionary=base.duplicate(true);npc_fixtures(cargo,20,0)
	for a:Dictionary in cargo.facts.actors:
		if a.id!="repair-resident":continue
		a.pack={"log":2};a.pending_delivery={"source_id":"fixture:source","destination_id":"fixture:destination","items":{"log":2},"phase":"deliver"}
	if not mount(cargo):finish();return
	before=runtime.actor("repair-resident")
	advance_decision()
	var after_cargo:Dictionary=runtime.actor("repair-resident")
	check("E preserves actual carried cargo and B pending delivery",Data.json_equal(before.pack,after_cargo.pack) and Data.json_equal(before.pending_delivery,after_cargo.pending_delivery) and after_cargo.intent==null)
	var homecoming:Dictionary=base.duplicate(true);npc_fixtures(homecoming,80,0)
	for a:Dictionary in homecoming.facts.actors:
		if a.id=="repair-resident":a.relationship.member=true;a.relationship.consent=true;a.householdId="home-residents";a.job="rest"
	if not mount(homecoming):finish();return
	var origin:Dictionary=runtime.actor("repair-resident")
	runtime.tick(0.1)
	var returning:Dictionary=runtime.actor("repair-resident")
	check("cooperator requests B route home without teleportation",returning.get("intent") is Dictionary and returning.intent.get("purpose")=="return-home" and Geometry.point(origin)==Geometry.point(returning),returning.get("self_routine"))
	if returning.get("intent") is Dictionary and returning.intent.get("purpose")=="return-home":
		var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
		check("real return route survives native checkpoint encoding",encoded.ok,encoded.get("reason"))
		if encoded.ok:
			var decoded:Dictionary=Store.decode(encoded.text)
			check("native return route decodes",decoded.ok,decoded.get("reason"))
			if decoded.ok:mount(decoded.capture)
		var feet_bad:int=0;var leaps:int=0;var moved:float=0.0
		var last:Vector3=Geometry.point(runtime.actor("repair-resident"))
		var home:Dictionary=initial.layout.home
		for i in 600:
			runtime.tick(0.1)
			var a:Dictionary=runtime.actor("repair-resident");var at:=Geometry.point(a);var delta:Vector3=at-last
			moved+=delta.length()
			if Vector2(delta.x,delta.z).length()>Movement.WALK_SPEED*0.1+0.001 or absf(delta.y)>0.501:leaps+=1
			if runtime._services.buildings.current_space().standing_point(Geometry.location(a)).is_empty():feet_bad+=1
			last=at
			if a.regionId==home.regionId and at.distance_to(Geometry.point(home))<=float(initial.layout.home_radius):break
		var arrived:Dictionary=runtime.actor("repair-resident")
		check("existing B executor advances a saved return path with real supported steps",moved>1 and feet_bad==0 and leaps==0,{"distance":moved,"unsupported":feet_bad,"leaps":leaps})
		check("cooperator physically reaches the home region and radius",arrived.regionId==home.regionId and Geometry.point(arrived).distance_to(Geometry.point(home))<=float(initial.layout.home_radius),{"location":Geometry.location(arrived),"activity":arrived.activity,"routine":arrived.get("self_routine")})
	# Both A life and E movement obey actual C metadata, with no elapsed catchup.
	if not mount(needs):finish();return
	runtime.tick(0.1);runtime.tick(0.1)
	var frozen_actor:Dictionary=runtime.actor("repair-resident")
	var home_player:Dictionary=runtime.actor("player")
	check("C actual cold lattice disables detailed region",set_region_detail("RH-VILLAGE",false) and not runtime.region_is_detailed("RH-VILLAGE") and runtime.region_is_detailed("RH-HOME"))
	for i in 20:runtime.tick(0.1)
	check("remote metabolism life and E decisions preserve exact actor and cargo",Data.json_equal(frozen_actor,runtime.actor("repair-resident")))
	check("detailed home player continues while remote village is paused",runtime.actor("player").hunger<home_player.hunger and runtime.clock()>2,{"clock":runtime.clock(),"hunger":runtime.actor("player").hunger})
	check("restoring real residency resumes same predicate",set_region_detail("RH-VILLAGE",true) and runtime.region_is_detailed("RH-VILLAGE"))
	runtime.tick(0.1)
	var resumed_actor:Dictionary=runtime.actor("repair-resident")
	check("returning region advances life by one fixed step without remote catchup",resumed_actor.pack.get("water")==1 and absf(float(resumed_actor.intent.elapsed)-float(frozen_actor.intent.elapsed)-0.1)<0.000001)
	# A committed event fixture exercises warning time; no machine reward claimed.
	if not mount(base):finish();return
	var cause:Dictionary=runtime._commit({"world_changes":[],"fact_changes":[],"events":[{"kind":"factory-batch-completed","actor_id":"","batch_id":"fixture:batch","settlement_id":"fixture:settlement"}]})
	check("committed machine event only marks capability and never starts a raid",cause.ok and advance_decision().ok and runtime.world.extension("r34:gameplay").defense.status=="dormant")
	var old_event:Dictionary=runtime.world.extension("r34:gameplay");var timing:Dictionary=old_event.duplicate(true)
	timing.event_ids.append("fixture:route-commit");timing.regional_events.append({"id":"fixture:route-commit","kind":"fixture-route-commit","time":runtime.clock()})
	timing.defense={"status":"warning","warning_id":"fixture:warning","warning_at":runtime.clock(),"arrival_at":runtime.clock()+60.0,"warning_remaining":60.0,"cause_event_id":"fixture:route-commit","actors":[]}
	check("explicit regional warning timing fixture validates without granting items",runtime._commit({"world_changes":[{"op":"extension.set","id":"r34:gameplay","before_exists":true,"before":old_event,"after":timing}],"fact_changes":[],"events":[]}).ok)
	check("cold home metadata pauses regional defense",set_region_detail("RH-HOME",false) and not runtime.region_is_detailed("RH-HOME"))
	var cold_spawn:=Draft.new(runtime._services.workforce.context)
	var cold_result:Dictionary=runtime._services.gameplay.prepare_defense_spawn(cold_spawn,{"id":"r34:first-defense","position":initial.layout.defense_position,"actors":[]})
	check("cold encounter cannot generate enemies or report victory",not cold_result.ok and cold_result.code=="REGION_PAUSED" and cold_spawn.staged.actors.size()==runtime.facts().actors.size())
	var defense_before:Dictionary=runtime.world.extension("r34:gameplay").defense
	for i in 20:runtime.tick(0.1)
	check("regional warning never counts down in a paused home",Data.json_equal(defense_before,runtime.world.extension("r34:gameplay").defense))
	check("restored home resumes regional countdown",set_region_detail("RH-HOME",true))
	runtime.tick(0.1)
	var defense_after:Dictionary=runtime.world.extension("r34:gameplay").defense
	check("warning resumes one fixed step without spawning from elapsed remote time",defense_after.status=="warning" and absf(float(defense_after.warning_remaining)-59.9)<0.000001 and defense_after.actors.is_empty())
	finish()
func finish()->void:
	var report:Dictionary={"scope":"actual C713 B modules A native offscreen assembly, E arbitration, A life and B movement; explicit need/cargo/local-water fixtures; no PCK OS VA performance acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));runtime=null;host.free();quit(1 if report.failed else 0)
