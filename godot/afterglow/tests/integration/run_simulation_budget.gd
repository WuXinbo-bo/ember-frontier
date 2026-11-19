extends SceneTree
## Real fixed-step runtime; deliberately small finite fixtures, no live saves.
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
class Counter extends RefCounted:
	var calls:=0
	var delay_usec:=0
	func advance(_dt:float)->Dictionary:
		calls+=1
		if delay_usec>0:OS.delay_usec(delay_usec)
		return {"ok":true}
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func fixture(service:RefCounted=null,simulation:Dictionary={})->RefCounted:
	var world:=World.new();world.load_snapshot(Rural.generate(713))
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var a:Dictionary=Initial.actor("player","fixture",at,at,{"food":2,"water":2});a.stamina=50.0
	var runtime:=Runtime.new()
	var result:Dictionary=runtime.configure({"world":world,"facts":{"actors":[a],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"simulation":simulation,"services":{"gameplay":service} if service!=null else {}})
	check("isolated actual runtime configures",result.ok,result)
	return runtime
func drain(r:RefCounted)->void:
	for i:int in 100:
		if r.simulation_budget().pending_steps==0:return
		r.tick(0)
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var counter:=Counter.new();var r:RefCounted=fixture(counter)
	var before:Dictionary=r.actor("player")
	r.tick(1.05)
	check("long frame is bounded to at most four complete steps",counter.calls>0 and counter.calls<=4 and r.simulation_budget().last_steps<=4,r.simulation_budget())
	check("accepted wall time is conserved in clock plus debt",is_equal_approx(r.clock()+r.simulation_budget().backlog_seconds,1.05))
	var saved:Dictionary=r.capture_checkpoint()
	check("pending debt is explicit in checkpoint",saved.simulation.remainder>0.6)
	var clock:float=r.clock();var debt:float=r.simulation_budget().backlog_seconds
	r.set_paused(true);r.tick(500.0);r.tick(0)
	check("pause neither adds wall time nor consumes accepted debt",r.clock()==clock and r.simulation_budget().backlog_seconds==debt)
	r.set_paused(false);drain(r)
	check("zero-delta frames consume all accepted full steps exactly once",is_equal_approx(r.clock(),1.0) and counter.calls==10 and is_equal_approx(r.simulation_budget().backlog_seconds,0.05))
	check("needs advance with actual simulation time not presentation frames",is_equal_approx(before.hunger-r.actor("player").hunger,Runtime.LIFE.hunger) and is_equal_approx(before.thirst-r.actor("player").thirst,Runtime.LIFE.thirst))
	var encoded:Dictionary=Store.encode(saved);var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("debt survives complete native world codec",encoded.ok and decoded.ok and is_equal_approx(decoded.capture.simulation.remainder,debt))
	var restored:RefCounted=fixture(null,decoded.capture.simulation if decoded.ok else {})
	var context:Dictionary={"world":restored.world,"facts":decoded.capture.facts,"services":{},"simulation":decoded.capture.simulation}
	check("resume configures same saved needs clock and debt",restored.configure(context).ok)
	drain(restored)
	check("restored debt conserves exact resulting needs and clock",Data.json_equal(r.facts(),restored.facts()) and is_equal_approx(restored.simulation_budget().backlog_seconds,0.05))
	var frozen:Dictionary=r.capture_checkpoint();r.tick(NAN);r.tick(INF);r.tick(-1)
	check("nonfinite and negative frame input cannot change world or debt",Data.json_equal(frozen,r.capture_checkpoint()))
	r.retire();r.tick(10)
	check("retired runtime cannot consume or accrue time",Data.json_equal(frozen,r.capture_checkpoint()))
	var slow:=Counter.new();slow.delay_usec=8000
	var overloaded:RefCounted=fixture(slow);overloaded.tick(0.9)
	check("soft wall budget starts no second over-budget step",slow.calls==1 and overloaded.simulation_budget().last_steps==1 and overloaded.simulation_budget().over_budget==1,overloaded.simulation_budget())
	check("nonpreemptible step overrun is reported not hidden",overloaded.simulation_budget().max_step_usec>=8000 and is_equal_approx(overloaded.clock()+overloaded.simulation_budget().backlog_seconds,0.9))
	var old:Dictionary=overloaded.capture_checkpoint()
	var invalid:Dictionary={"world":overloaded.world,"facts":overloaded.facts(),"services":{},"simulation":{"remainder":-1.0}}
	check("bad debt rejects before corrupting configured authority",not overloaded.configure(invalid).ok and Data.json_equal(old,overloaded.capture_checkpoint()))
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("all current formal item references resolve",Content.validate_catalog(catalog).ok)
	var bad:Dictionary=catalog.duplicate(true);bad.production_recipes[0].inputs={"unknown_m3":1.0}
	check("formal unknown item cannot use legacy suffix adapter",not Content.validate_catalog(bad).ok and Content.quantity_valid("unknown_m3",0.125,true) and not Content.quantity_valid("unknown_m3",0.125))
	check("bad descriptor shapes fail without consumer crash",not Content.validate_catalog({"production_recipes":[{"inputs":1}]}).ok and not Content.validate_catalog({"structure_definitions":[]}).ok)
	check("count finite integer and fractional volume semantics preserved",not Content.quantity_valid("log",0.5) and Content.quantity_valid("soil_m3",0.000125) and not Content.quantity_valid("food",NAN))
	var definition:Dictionary=Content.item_definition("water");definition.name="changed"
	check("definitions return detached values",Content.item_definition("water").name=="饮水")
	check("optional legacy missing or null skills is safe",Content.actor_effects({"skills":null}).skills=={} and Content.actor_effects({}).skills=={})
	finish()
func finish()->void:
	var report:Dictionary={"scope":"source/headless production fixed-step and native codec; explicit slow-step fixture; not FPS/PCK/OS","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close();print(JSON.stringify(report));quit(1 if report.failed else 0)
