extends SceneTree
## A counting pure provider proves one preparation per submitted command;
## real B/C/E safety and gameplay suites separately verify their providers.
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
class Domain extends RefCounted:
	var context:Dictionary={}
	var preparations:=0
	var previews:=0
	var denied:=false
	var stale:=false
	func configure(value:Dictionary)->void:context=value
	func availability(request:Dictionary)->Dictionary:
		previews+=1
		return prepare(request)
	func prepare(_request:Dictionary)->Dictionary:
		preparations+=1
		if denied:return {"ok":false,"code":"DOMAIN_REVOKED","reason":"fixture live permission revoked"}
		var before:Dictionary=context.actor.call("player")
		var after:Dictionary=before.duplicate(true);after.activity="single domain preparation"
		if stale:before.hp-=1
		return {"ok":true,"code":"OK","fact_changes":[{"collection":"actors","id":"player","before":before,"after":after}],"world_changes":[],"events":[]}
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
	var facts:Dictionary={"actors":[Initial.actor("player","fixture",at,at,{"food":2,"water":2})],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"}
	var domain:=Domain.new();var runtime:=Runtime.new();var save_state:Dictionary={"busy":false}
	check("counting provider uses same Runtime public entry",runtime.configure({"world":world,"facts":facts,"services":{"actions":domain},"save_state":save_state}).ok)
	var request:Dictionary={"kind":"probe","actor_id":"player","command_id":"once:1"}
	var original:Dictionary=runtime.capture_checkpoint()
	check("availability remains complete but purely advisory",runtime.availability(request).ok and domain.preparations==1 and domain.previews==1 and original==runtime.capture_checkpoint())
	check("submission prepares exactly once then commits",runtime.command(request).ok and domain.preparations==2 and domain.previews==1 and runtime.actor("player").activity=="single domain preparation")
	var committed:Dictionary=runtime.capture_checkpoint()
	check("duplicate receipt never prepares or commits again",runtime.command(request).ok and domain.preparations==2 and committed==runtime.capture_checkpoint())
	request.command_id="once:revoked";domain.denied=true
	check("old successful preview does not authorize later revoked request",runtime.command(request).code=="DOMAIN_REVOKED" and domain.preparations==3 and committed==runtime.capture_checkpoint())
	domain.denied=false;domain.stale=true;request.command_id="once:cas"
	check("single prepared draft still undergoes final fact CAS",not runtime.command(request).ok and domain.preparations==4 and committed==runtime.capture_checkpoint())
	domain.stale=false;request.command_id="once:loading";save_state.merge({"busy":true,"status":"loading"},true)
	check("world loading stops before touching provider",runtime.command(request).code=="NOT_READY" and domain.preparations==4)
	save_state.busy=false;request.command_id="once:geometry"
	runtime.bind_readiness(func(_r:Dictionary)->Dictionary:return {"ok":false,"ready":false,"code":"NOT_READY"})
	check("stale physics stops before touching provider",runtime.command(request).code=="NOT_READY" and domain.preparations==4)
	request.command_id="once:revision";request.expected_revision=runtime.get_revision()+1
	check("expected revision rejects before prepare",runtime.command(request).code=="STALE_REVISION" and domain.preparations==4)
	request.erase("expected_revision");request.command_id="once:retired";runtime.retire()
	check("retired world cannot prepare new input",runtime.command(request).code=="WORLD_RETIRED" and domain.preparations==4 and committed==runtime.capture_checkpoint())
	var report:Dictionary={"scope":"source/headless counting pure provider, common gates, stale preview and final fact CAS; not real door timing or OS acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	# This counting test owns a strong Callable; production providers use weak
	# references. Release the fixture's cycle before checking engine shutdown.
	domain.context.clear()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close();print(JSON.stringify(report));quit(1 if report.failed else 0)
