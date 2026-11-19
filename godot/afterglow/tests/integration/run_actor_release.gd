extends SceneTree
## Actual A CAS + B orders/provider + E schedule, with explicit finite fixtures.
## No user save, formal app, new death rule, OS/VA/performance qualification.
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Residents=preload("res://scripts/runtime/resident_life.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Store=preload("res://scripts/storage/native_store.gd")
class RejectRelease extends RefCounted:
	func prepare_actor_release(_transitions:Array,_observed:Dictionary,_pending:Array)->Dictionary:
		return {"ok":false,"code":"FIXTURE_RELEASE_REJECTED","reason":"explicit rejecting provider"}
var checks:Array=[]
var runtime:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func setup()->void:
	var w:=World.new();check("actual finite world loads",w.load_snapshot(Rural.generate(713)).ok)
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var player:Dictionary=Initial.actor("player","fixture",at,at,{"food":1,"water":1})
	var other:Dictionary=Initial.actor("ordinary:test","fixture",at.merged({"x":32.0},true),at,{})
	other.relationship={"member":true,"consent":true}
	other.self_routine={"version":1,"origin":at.duplicate(true),"phase":2,"next_decision":900.0,"last_failure":"fixture"}
	other.pending_delivery={"source_id":"original","destination_id":"destination","phase":"collect","items":{"log":1}}
	runtime=Runtime.new()
	check("real A B E services configure",runtime.configure({"world":w,"facts":{"actors":[player,other],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"buildings":Buildings.new(),"actions":Actions.new(),"production":Production.new(),"residents":Residents.new()}}).ok)
func edit(id:String,fields:Dictionary,extra:Array=[])->Dictionary:
	var before:Dictionary=runtime.actor(id);var after:Dictionary=before.duplicate(true);after.merge(fields,true)
	return runtime._commit({"fact_changes":[{"collection":"actors","id":id,"before":before,"after":after}],"world_changes":extra})
func remove(id:String)->Dictionary:
	return runtime._commit({"fact_changes":[{"collection":"actors","id":id,"before":runtime.actor(id),"after":null}]})
func run()->void:
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	setup()
	check("real life intent starts",runtime.command({"kind":"eat","command_id":"release:eat","actor_id":"player"}).ok)
	var result:Dictionary=edit("player",{"hp":0.0})
	check("incapacity clears life intent in SAME transaction without tick",result.ok and runtime.clock()==0 and runtime.actor("player").intent==null,result)
	check("incapacity preserves exact carried rations and costs",runtime.actor("player").pack=={"food":1,"water":1} and runtime._services.production.all_holds().is_empty())
	check("receipt identifies committed transition",result.ok and result.changes.actor_transitions==[{"actor_id":"player","kind":"incapacitated"}])
	check("immediate recovery cannot resurrect old intent",edit("player",{"hp":50.0}).ok and runtime.actor("player").intent==null and runtime.clock()==0)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("native restored facts cannot resurrect released life hold",decoded.ok and decoded.capture.facts.actors[0].intent==null and decoded.capture.facts.actors[0].pack.food==1)
	var p:Dictionary=runtime._services.production.state();var next:Dictionary=p.duplicate(true);next.nextId=7
	var op:Dictionary={"op":"extension.set","id":Production.KEY,"before_exists":runtime.world.has_extension(Production.KEY),"before":runtime.world.extension(Production.KEY),"after":next}
	result=edit("ordinary:test",{"hp":0.0},[op])
	check("pending production overlay merges with release and keeps nextId",result.ok and runtime.world.extension(Production.KEY).nextId==7,result)
	check("same extension emitted once after release composition",result.ok and result.changes.world.filter(func(c:Dictionary)->bool:return c.get("id")==Production.KEY).size()==1)
	var released:Dictionary=runtime.actor("ordinary:test")
	check("E schedule resets without a tick",released.self_routine.next_decision==0 and not released.self_routine.has("last_failure"))
	check("E release preserves origin phase and delivery descriptor",released.self_routine.phase==2 and released.pending_delivery=={"source_id":"original","destination_id":"destination","phase":"collect","items":{"log":1}})
	check("ordinary recovery preserves released schedule and no stale intent",edit("ordinary:test",{"hp":70.0}).ok and runtime.actor("ordinary:test").intent==null)
	check("ordinary active finite life fixture commits",edit("ordinary:test",{"intent":{"schema_version":1,"owner":"runtime","kind":"eat","id":"fixture:ordinary-eat","elapsed":0.0,"duration":1.3,"target_id":""}}).ok)
	result=edit("ordinary:test",{"relationship":{"member":true,"consent":false}})
	check("consent withdrawal atomically interrupts previous intent",result.ok and runtime.actor("ordinary:test").intent==null and result.changes.actor_transitions[0].kind=="consent_revoked")
	check("explicit finite carried inventory fixture commits",edit("ordinary:test",{"pack":{"water":1}}).ok)
	var before:Dictionary=runtime.capture_checkpoint();result=remove("ordinary:test")
	check("deletion refuses to silently lose inventory",not result.ok and result.code=="ACTOR_INVENTORY_TRANSFER_REQUIRED" and runtime.capture_checkpoint()==before,result)
	check("explicit fixture clears pack before empty actor deletion",edit("ordinary:test",{"pack":{}}).ok)
	result=remove("ordinary:test")
	check("empty ordinary actor deletion commits without reinsertion",result.ok and runtime.actor("ordinary:test").is_empty() and runtime._services.production.all_holds().is_empty())
	check("player identity cannot be removed",not remove("player").ok)
	setup()
	check("fresh real life starts for rollback counterexample",runtime.command({"kind":"drink","command_id":"release:rollback","actor_id":"player"}).ok)
	before=runtime.capture_checkpoint()
	var invalid_op:Dictionary={"op":"extension.set","id":"fixture:bad-cas","before_exists":true,"before":{"forged":true},"after":{}}
	result=edit("player",{"hp":0.0},[invalid_op])
	check("late world CAS rejection rolls back hp intent and all B release writes",not result.ok and runtime.capture_checkpoint()==before,result)
	var real_actions:RefCounted=runtime._services.actions
	runtime._services.actions=RejectRelease.new();result=edit("player",{"hp":0.0})
	check("provider failure preserves complete original authority",not result.ok and result.code=="FIXTURE_RELEASE_REJECTED" and runtime.capture_checkpoint()==before)
	runtime._services.actions=RefCounted.new();result=edit("player",{"hp":0.0})
	check("missing required release provider fails closed",not result.ok and result.code=="MISSING_LIFECYCLE_RELEASER" and runtime.capture_checkpoint()==before)
	runtime._services.actions=real_actions
	check("metabolic boundary fixture commits",edit("player",{"hp":0.01,"hunger":0.0,"pack":{"medicine":1},"intent":{"owner":"runtime","kind":"medicine","schema_version":1,"id":"fixture:near-completion","elapsed":1.2,"duration":1.3,"target_id":""}}).ok)
	runtime.tick(0.1)
	check("same-step incapacity cannot complete medicine and revive actor",runtime.actor("player").hp==0 and runtime.actor("player").intent==null and runtime.actor("player").pack.medicine==1)
	var report:Dictionary={"scope":"source/headless A atomic composition with actual B/E services and finite rollback fixtures; not PCK/OS/VA/performance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));runtime=null;quit(1 if report.failed else 0)
