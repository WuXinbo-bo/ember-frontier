extends SceneTree
## E pure policy + actual A transaction/lifecycle, finite labeled fixtures.
## No claim of B's not-yet-adopted logistics execution, PCK, OS, VA or performance.
const Combat=preload("res://scripts/runtime/rural_gameplay.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Workforce=preload("res://scripts/runtime/settlement_workforce.gd")
const Policy=preload("res://scripts/runtime/workforce_arbitration.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var runtime:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func location(x:float=29.2)->Dictionary:return {"x":x,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
func registration()->Dictionary:
	return {"ok":true,"spawn_points":{"player":location(),"village-resident":location(32.0),"repair-resident":location(35.0)},"home":location(),"initial_stocks":[{"id":"fixture:woodwork","items":{"book_woodwork":1},"location":location(),"owner":"home-residents","searched":false}],"initial_tools":[{"id":"fixture:saw","kind":"hand_saw","holderId":"fixture:woodwork","durability":100.0}],"initial_records":[{"id":"fixture:book","itemId":"book_woodwork","holderId":"fixture:woodwork","grants":["basic_woodwork"],"seconds":12.0}],"world_changes":[]}
func row()->Dictionary:return {"id":"workforce:1","actor_id":"village-resident","candidate_id":"fixture:candidate","sequence":1,"priority":0.0,"status":"requested","created_at":0.0}
func run()->void:
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var layout:Dictionary={"home":location(),"home_radius":18.0}
	var source:Dictionary=registration();var saved:Dictionary=source.duplicate(true)
	var opened:Dictionary=Gameplay.initial(layout,source)
	check("normal initial DTO is pure and preserves finite source",opened.ok and Data.json_equal(source,saved),opened)
	if not opened.ok:finish(output);return
	check("three permanent identities and original ration only",opened.facts.actors.size()==3 and opened.facts.actors[0].pack=={"food":1,"water":1} and opened.facts.actors[1].pack.is_empty() and opened.facts.actors[2].pack.is_empty())
	check("new tutorial uses production transport rather than legacy furniture",opened.facts.scenario==Gameplay.SCENARIO and opened.facts.quests.size()==4 and str(opened.facts.quests[0].id).begins_with("R34-") and not opened.facts.quests.any(func(q:Dictionary)->bool:return str(q.id).begins_with("RH-")))
	check("new people require earned consent and retain original needs",not opened.facts.actors[1].relationship.member and not opened.facts.actors[1].relationship.consent and opened.facts.actors[1].hunger==68.0 and opened.facts.actors[1].thirst==58.0)
	var opened_story:Dictionary=opened.world_changes.filter(func(c:Dictionary)->bool:return c.id==Gameplay.KEY)[0].after
	check("four story cards bind finite real sources without claiming unknown sites",Gameplay.story_projection(opened_story).size()==4 and opened_story.stories.ST01.sources==["fixture:woodwork"] and opened_story.stories.ST03.sources.is_empty() and opened_story.stories.ST04.sources.is_empty())
	var nested:Dictionary=source.duplicate(true);nested.seed_result=source.duplicate(true)
	var alias:Dictionary=Gameplay.initial(layout,nested)
	check("identical flat aliases never issue a second stock tool or record",alias.ok and alias.facts.stocks.size()==1 and alias.production_state.tools.size()==1 and alias.production_state.records.size()==1)
	nested.initial_stocks[0].items.book_woodwork=2
	check("conflicting alias fails closed",Gameplay.initial(layout,nested).get("code")=="INITIAL_ALIAS_CONFLICT")
	var bad:Dictionary=source.duplicate(true);bad.initial_stocks.append(bad.initial_stocks[0].duplicate(true))
	check("duplicate ID inside unique stock source rejects",Gameplay.initial(layout,bad).get("code")=="INITIAL_DUPLICATE_CONTENT")
	bad=source.duplicate(true);bad.initial_stocks[0].items={}
	check("knowledge cannot exist without actual book",Gameplay.initial(layout,bad).get("code")=="INITIAL_RECORD_SOURCE_MISSING")
	bad=source.duplicate(true);bad.initial_tools[0].holderId="missing"
	check("tool cannot exist without a physical holder",Gameplay.initial(layout,bad).get("code")=="INITIAL_TOOL_HOLDER_MISSING")
	var s:Dictionary={"actor_id":"member","actor_exists":true,"alive":true,"requires_consent":true,"consent":false,"danger":true,"urgent_need":"drink"}
	check("N0 withdrawal wins over danger and work",Policy.decide(s).priority=="N0")
	s.consent=true
	check("N1 immediate danger wins over urgent need",Policy.decide(s).priority=="N1")
	s.danger=false;s.emergency={"authorized":true,"qualified":true,"kind":"defend"}
	check("N2 urgent need wins over emergency guard",Policy.decide(s).priority=="N2")
	s.urgent_need="";s.explicit_assignment={"valid":true,"handoff_safe":true}
	check("N3 eligible defense wins over explicit assignment",Policy.decide(s).priority=="N3")
	s.emergency.at_position=true
	check("N3 guard holds a proved real arrival without making a second route",Policy.decide(s).priority=="N3" and Policy.decide(s).action=="hold")
	s.emergency={};s.explicit_assignment.handoff_safe=false
	check("N4 cannot seize a slot before safe handoff",Policy.decide(s).action=="wait_handoff")
	s.explicit_assignment={};s.carried_delivery={"reachable":false,"capacity_valid":false}
	check("N5 blocked carried goods cannot disappear into a new job",Policy.decide(s).priority=="N5" and Policy.decide(s).action=="hold")
	s.carried_delivery={};s.candidates=[{"id":"invalid","valid":true,"route_cost":NAN},{"id":"z","valid":true,"player_priority":2,"wait_seconds":20,"route_cost":1},{"id":"a","valid":true,"player_priority":2,"wait_seconds":20,"route_cost":1}]
	check("N6 ignores malformed candidate and uses stable ID tie break",Policy.decide(s).candidate.id=="a")
	s.candidates.append({"id":"unload","valid":true,"unblocks_output":true,"player_priority":0,"wait_seconds":0,"route_cost":20})
	check("N6 real output unblocking outranks ordinary player priority",Policy.decide(s).candidate.id=="unload")
	s.explicit_assignment={"id":"building-order:warehouse","valid":false,"reason":"missing_material"}
	check("legacy unavailable assignment keeps its original arbitration",Policy.decide(s).action=="blocked")
	s.explicit_assignment.deferred=true
	check("pending building order yields to productive work without losing its slot",Policy.decide(s).candidate.id=="unload" and s.explicit_assignment.id=="building-order:warehouse")
	s.carried_delivery={"id":"logistics:1","reachable":true,"capacity_valid":true}
	check("pending order cannot jump ahead of physical cargo",Policy.decide(s).priority=="N5" and Policy.decide(s).candidate.id=="logistics:1")
	s.carried_delivery={}
	s.candidates=[]
	check("N7 no legal work gives no fake resource intent",Policy.decide(s).action=="idle")
	s.explicit_assignment.valid=true;s.explicit_assignment.handoff_safe=true
	check("ready durable order regains priority",Policy.decide(s).priority=="N4")
	var world:=World.new();check("actual world fixture loads",world.load_snapshot(Rural.generate(713)).ok)
	var snapshot:Dictionary=world.snapshot()
	for c:Dictionary in opened.world_changes:snapshot.extensions[c.id]=c.after
	check("E state DTO loads without second world",world.load_snapshot(snapshot).ok)
	var facts:Dictionary=opened.facts.duplicate(true);facts.actors[1].relationship={"member":true,"consent":true};facts.actors[1].pack={"log":2}
	facts.stocks.append({"id":"fixture:source","items":{},"location":location(),"owner":"home-residents","searched":true})
	facts.stocks.append({"id":"fixture:destination","items":{},"location":location(30.1),"owner":"home-residents","searched":true})
	var workforce_state:Dictionary=snapshot.extensions[Workforce.KEY];workforce_state.assignments=[row()];workforce_state.next_id=2
	snapshot.extensions[Workforce.KEY]=workforce_state
	snapshot.extensions["r3:production"]=opened.production_state.duplicate(true)
	world.load_snapshot(snapshot)
	runtime=Runtime.new()
	var service:=Workforce.new()
	check("actual A B E configure validates new states",runtime.configure({"world":world,"facts":facts,"services":{"buildings":Buildings.new(),"actions":Actions.new(),"production":Production.new(),"gameplay":Combat.new(),"workforce":service}}).ok)
	var capture:Dictionary=runtime.capture_checkpoint();var projected:Dictionary=service.projection()
	projected.assignments.clear();projected.members.clear()
	check("projection is detached and cannot change clock cargo or assignments",Data.json_equal(capture,runtime.capture_checkpoint()))
	check("E never creates a second stock reservation",service.hold_descriptors(runtime.facts()).is_empty())
	var transport:Dictionary=runtime.command({"kind":"logistics.create","actor_id":"player","command_id":"fixture:transport","payload":{"source_id":"fixture:source","destination_id":"fixture:destination","items":{"log":1},"repeat":true}})
	var request:Dictionary={"kind":"workforce.assign","actor_id":"village-resident","command_id":"fixture:transport-worker","payload":{"candidate_id":"logistics:1"}}
	var assigned:Dictionary=runtime.command(request) if transport.ok else transport
	var assigned_row:Dictionary=Draft.find(service.hud_projection().assignments,"workforce:2")
	check("real transport may be assigned before input material arrives",assigned.ok and assigned_row.get("work_phase")=="queued" and assigned_row.get("region_ids")==["RH-HOME"] and runtime.stock("fixture:source").items.is_empty(),assigned)
	request.actor_id="player"
	check("one transport cannot be assigned to two people",service.availability(request).get("code")=="WORK_ALREADY_ASSIGNED")
	check("pending transport pins its real stock region",service.event_dependency_regions().has("RH-HOME"))
	var before:Dictionary=runtime.actor("village-resident");var after:Dictionary=before.duplicate(true);after.relationship.consent=false
	var pending:Dictionary=world.extension(Workforce.KEY);pending.next_id=9
	var change:Dictionary={"op":"extension.set","id":Workforce.KEY,"before_exists":true,"before":world.extension(Workforce.KEY),"after":pending}
	var released:Dictionary=runtime._commit({"fact_changes":[{"collection":"actors","id":before.id,"before":before,"after":after}],"world_changes":[change]})
	check("withdrawal releases assignment atomically with pending overlay",released.ok and world.extension(Workforce.KEY).assignments.is_empty() and world.extension(Workforce.KEY).next_id==9,released)
	check("release keeps actual carried wood and records reason without time",runtime.actor(before.id).pack=={"log":2} and runtime.clock()==0 and world.extension(Workforce.KEY).interrupted[0].reason=="consent_revoked")
	check("restored post-release state validates without resurrecting assignment",service.validate_extensions(runtime.facts()).ok)
	var invalid:Dictionary=world.extension(Workforce.KEY);invalid.assignments=[row()]
	check("restore refuses an assignment after withdrawn consent",not service.validate_extensions(runtime.facts(),{Workforce.KEY:invalid}).ok)
	var old:Dictionary=runtime.capture_checkpoint();invalid.assignments[0].actor_id="missing"
	var refused:Dictionary=runtime._commit({"world_changes":[{"op":"extension.set","id":Workforce.KEY,"before_exists":true,"before":world.extension(Workforce.KEY),"after":invalid}]})
	check("A refuses bad actor reference atomically",not refused.ok and Data.json_equal(old,runtime.capture_checkpoint()),refused)
	var tx:=Draft.new(service.context)
	tx.staged.ledger=[{"id":"event:10:0","revision":10,"time":0.0,"kind":"help","actor_id":"player","target_id":"village-resident"},{"id":"event:10:1","revision":10,"time":0.0,"kind":"invite","actor_id":"player","target_id":"village-resident"}]
	check("two same-revision real ledger events both observed",Gameplay.advance_in(tx,0).ok and tx.extensions[Gameplay.KEY].event_ids.size()==2 and tx.extensions[Gameplay.KEY].flags.helped_someone and tx.extensions[Gameplay.KEY].flags.invited_member)
	check("re-observing same revision emits no duplicate",Gameplay.advance_in(tx,0).ok and tx.extensions[Gameplay.KEY].event_ids.size()==2)
	check("observed help and invite never fabricate relationship or recruit another person",not tx.extensions[Gameplay.KEY].stories.ST02.people["repair-resident"].member and not tx.extensions[Gameplay.KEY].stories.ST02.people["repair-resident"].helped and tx.staged.actors==runtime.facts().actors)
	tx.staged.ledger.append({"id":"event:11:0","revision":11,"time":0.0,"kind":"factory-batch-completed","actor_id":"player"})
	check("actual machine completion grants milestone without unannounced raid",Gameplay.advance_in(tx,0).ok and tx.extensions[Gameplay.KEY].defense.status=="dormant" and tx.extensions[Gameplay.KEY].flags.real_machine_output and tx.events.is_empty())
	check("machine milestone does not grant reward spawn or cargo",tx.staged.actors==runtime.facts().actors and tx.staged.stocks==runtime.facts().stocks)
	# Pure observer fixtures: B's real shell/construction tests prove execution;
	# here every catalog family must route the same paid completion fact.
	for definition:Dictionary in preload("res://scripts/modules/module_catalog.gd").definitions():
		if definition.get("shape") not in ["warehouse","woodshop"]:continue
		var family_tx:=Draft.new(service.context)
		family_tx.extension("r34:modules").instances=[{"id":"fixture:paid:"+str(definition.id),"definition_id":definition.id,"region":"RH-HOME","player_built":true,"paid_cost":{"timber":12,"scrap":4},"status":"operational"}]
		family_tx.staged.ledger=[{"id":"fixture:built:"+str(definition.id),"kind":"module-project-completed","operation":"build","actor_id":"player","module_id":"fixture:paid:"+str(definition.id),"revision":12,"time":0.0}]
		var family_result:Dictionary=Gameplay.advance_in(family_tx,0)
		check("paid catalog shape drives tutorial for "+str(definition.id),family_result.ok and family_tx.extensions[Gameplay.KEY].flags.get("real_warehouse_built" if definition.shape=="warehouse" else "real_machine_built",false),family_result)
	# Explicit timing fixture, not a claim that C's route-work site is available.
	tx.extensions[Gameplay.KEY].event_ids.append("fixture:route-commit")
	tx.extensions[Gameplay.KEY].regional_events.append({"id":"fixture:route-commit","kind":"fixture-route-commit","time":0.0})
	tx.extensions[Gameplay.KEY].defense={"status":"warning","warning_id":"fixture:warning","warning_at":0.0,"arrival_at":60.0,"warning_remaining":60.0,"cause_event_id":"fixture:route-commit","actors":[]}
	for i in 60:Gameplay.advance_in(tx,float(i+1),1.0)
	check("arrival waits for executor and never clears an empty encounter",tx.extensions[Gameplay.KEY].defense.status=="awaiting_execution")
	bad=tx.extensions[Gameplay.KEY].duplicate(true);bad.defense.status="cleared"
	check("bad spawn or empty actor list cannot be reported cleared",not Gameplay.validate_state(bad).ok)
	bad.defense.status="warning";bad.defense.cause_event_id="invented"
	check("warning without committed cause rejects",not Gameplay.validate_state(bad).ok)
	var combat:RefCounted=runtime._services.gameplay
	var prior_stamina:float=runtime.actor("player").stamina
	var attack:Dictionary=runtime.command({"kind":"attack","actor_id":"player","command_id":"factory:test:attack","payload":{}})
	check("R34 actual attack retains existing stamina and cooldown",attack.ok and runtime.actor("player").stamina==prior_stamina-14 and runtime.actor("player").cooldown==0.58,attack)
	check("R34 combat creates no legacy quest or gameplay extension",not world.has_extension("r33:gameplay") and runtime.facts().quests[0].id=="R34-Q01")
	check("R34 rejects old exploration and radio actions",combat.availability({"kind":"explore_start"}).code=="SCENARIO_UNAVAILABLE" and combat.availability({"kind":"radio"}).code=="SCENARIO_UNAVAILABLE")
	var spawn_tx:=Draft.new(service.context)
	var roster:Dictionary={"id":"r34:first-defense","position":location(100000),"actors":[]}
	var failed_spawn:Dictionary=combat.prepare_defense_spawn(spawn_tx,roster)
	check("actual B standing rejects broken R34 defense anchor",not failed_spawn.ok and failed_spawn.code=="NO_ENCOUNTER_GROUND" and roster.actors.is_empty() and spawn_tx.staged.actors.size()==runtime.facts().actors.size(),failed_spawn)
	roster={"id":"r34:first-defense","position":location(40),"actors":[]}
	var successful_spawn:Dictionary=combat.prepare_defense_spawn(spawn_tx,roster)
	check("actual B standing prepares all three existing infected once",successful_spawn.ok and roster.actors.size()==3 and spawn_tx.staged.actors.size()==runtime.facts().actors.size()+3,successful_spawn)
	if successful_spawn.ok:
		var duplicate_spawn:Dictionary=combat.prepare_defense_spawn(spawn_tx,roster)
		check("same encounter cannot duplicate its real actor identities",not duplicate_spawn.ok and spawn_tx.staged.actors.size()==runtime.facts().actors.size()+3)
		var active:Dictionary=tx.extensions[Gameplay.KEY].duplicate(true);active.defense.status="active";active.defense.actors=roster.actors.duplicate(true)
		check("defense valid references point to exact encounter actors",service.validate_extensions(spawn_tx.staged,{Gameplay.KEY:active}).ok)
		active.defense.status="cleared"
		check("restored live enemies cannot be labeled cleared",not service.validate_extensions(spawn_tx.staged,{Gameplay.KEY:active}).ok)
	finish(output)
func finish(output:String)->void:
	var report:Dictionary={"scope":"source/headless E policy, initial DTO, A atomic lifecycle, paid catalog family observer fixtures; real B execution validated separately, no PCK/OS/VA/performance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));runtime=null;quit(1 if report.failed else 0)
