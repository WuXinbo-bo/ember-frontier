extends SceneTree
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var world:=World.new();world.load_snapshot(Rural.generate(713))
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var a:Dictionary=Initial.actor("player","fixture",at,at,{"food":2,"water":2});a.erase("skills");a.relationship=null
	var facts:Dictionary={"actors":[a],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"}
	var runtime:=Runtime.new();check("legacy optional dictionaries normalize at assembly",runtime.configure({"world":world,"facts":facts,"services":{}}).ok and runtime.actor("player").skills=={} and runtime.actor("player").relationship=={})
	check("compat adapter never mutates caller source",not facts.actors[0].has("skills") and facts.actors[0].relationship==null)
	var original:Dictionary=runtime.capture_checkpoint()
	var bad_requests:Array=[{"kind":[]},{"kind":"eat","payload":[]},{"kind":"eat","actor_id":[]},{"kind":"eat","expected_revision":"zero"},{"kind":"eat","expected_revision":-1},{"kind":"eat","expected_revision":0.1}]
	for i:int in bad_requests.size():
		var request:Dictionary=bad_requests[i];request.command_id="bad:"+str(i)
		check("common bad request rejects before consumer "+str(i),runtime.command(request).code=="INVALID_COMMAND_SCHEMA" and Data.json_equal(original,runtime.capture_checkpoint()))
	check("nonstring command identity is not coerced",runtime.command({"kind":"eat","command_id":[]}).code=="INVALID_COMMAND")
	for pair:Array in [["max_hp",{}],["cooldown",[]],["nextDecision",INF],["work_payload",0],["skills",[]],["relationship",{"member":[]}]]:
		var broken:Dictionary=runtime.facts();broken.actors[0][pair[0]]=pair[1]
		check("common bad actor field rejects safely "+str(pair[0]),not Runtime.validate_facts(broken).ok)
	check("new captures carry explicit stable core content identity",original.content==Content.content_lock())
	var legacy:Dictionary=original.duplicate(true);legacy.erase("content")
	check("old captures without core stamp remain importable",Store.encode(legacy).ok)
	var changed:Dictionary=original.duplicate(true);changed.content.items.water="changed-definition"
	check("changed used item cannot silently reinterpret a save",Store.encode(changed).get("code")=="CONTENT_MIGRATION_REQUIRED")
	var lock:Dictionary=Content.content_lock();lock.items.erase("water")
	check("additive current definitions preserve older subset identity",Content.validate_lock(lock).ok)
	lock.schema="unknown-content-v9"
	check("unknown content version requires migration",not Content.validate_lock(lock).ok)
	var blocked:Array=[true]
	runtime.bind_readiness(func(_request:Dictionary)->Dictionary:return {"ok":not blocked[0],"ready":not blocked[0],"code":"NOT_READY" if blocked[0] else "OK"})
	runtime.tick(1.0)
	check("derived wait keeps debt and simulation frozen",runtime.clock()==0 and runtime.simulation_budget().pending_steps==10 and runtime.simulation_budget().waiting_for_geometry)
	blocked[0]=false
	for i:int in 10:runtime.tick(0)
	check("released derived wait executes accepted time once",is_equal_approx(runtime.clock(),1.0) and runtime.simulation_budget().pending_steps==0)
	var merged:Dictionary=preload("res://scripts/runtime/region_scheduler.gd").merge_world_changes([{"op":"extension.set","id":"generation:test","before_exists":false,"before":null,"after":{"v":1}}],[{"op":"extension.set","id":"generation:test","before_exists":true,"before":{"v":1},"after":{"v":2}}])
	check("world delta chain preserves original CAS and final after",merged.ok and merged.changes.size()==1 and not merged.changes[0].before_exists and merged.changes[0].after.v==2)
	var stale:Dictionary=preload("res://scripts/runtime/region_scheduler.gd").merge_world_changes([{"op":"extension.set","id":"generation:test","before_exists":false,"before":null,"after":{"v":1}}],[{"op":"extension.set","id":"generation:test","before_exists":true,"before":{"v":3},"after":{"v":2}}])
	check("foreign intermediate CAS cannot be flattened",stale.code=="GENERATION_CAS_CHAIN")
	finish()
func finish()->void:
	var report:Dictionary={"scope":"source/headless common schemas/content locks/readiness debt and delta-CAS counterexamples","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close();print(JSON.stringify(report));quit(1 if report.failed else 0)
