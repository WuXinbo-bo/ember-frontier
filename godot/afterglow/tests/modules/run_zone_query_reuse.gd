extends SceneTree
## Original new12 input + publicly paid-free planning only. Approximate 19x10
## replay, NOT the unsaved OS161-cell capture. No actor/material grants.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Workforce=preload("res://scripts/actions/workforce_executor.gd")
const Before=preload("res://tests/modules/query_reference/zone_work_before.gd")
var checks:Array=[]
var samples:Dictionary={}
var output:String
class Probe extends RefCounted:
	var calls:int=0
	func hold_descriptors(facts:Dictionary,overrides:Dictionary)->Array:
		calls+=1
		var a:Dictionary=Draft.find(facts.get("actors",[]),"player")
		if float(a.get("hp",0))<=0:return []
		return [{"schema_version":1,"owner":"B-test-probe","intent_id":"B:test:hold","actor_id":"player","phase":"active","source_id":"pack:player","cost":{"log":overrides.get("B:probe",{}).get("amount",1)},"tool_ids":["B:tool"],"use_target_id":"B:target"}]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail});print("B_QUERY ",checks.size()," ",ok," ",label)
func digest(value:Variant)->String:return JSON.stringify(value,"",true,true).sha256_text()
func measure(service:RefCounted)->Array:
	var rows:Array=[];var times:Array=[]
	for i:int in 4:
		var t:int=Time.get_ticks_usec();rows=service.work_candidates("player");times.append(Time.get_ticks_usec()-t)
	samples["before" if service is Before else "after"]={"usec":times,"ordered_sha256":digest(rows),"rows":rows.size()}
	return rows
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("original immutable new12 decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var live:Dictionary=host._assemble(decoded.capture);host.free()
	check("shipping Native and all owners mount",live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var service:RefCounted=live.services.zonework
	var reference:=Before.new();var context:Dictionary=service.context.duplicate();context.runtime=rt;context.services=live.services;reference.configure(context)
	var spec:Dictionary={"kind":"forestry","region_id":"RH-VILLAGE","bounds":{"x0":20,"x1":39,"z0":-96,"z1":-86},"policy":{"replant":true,"mature_only":true,"tree_id":"broadleaf"}}
	var created:Dictionary=rt.command({"kind":"zone.create","actor_id":"player","target_id":"B:query:forestry","command_id":"B:query:create","payload":{"spec":spec}})
	check("public 19x10 forestry admitted unchanged terrain",created.get("ok",false),created.get("code"))
	if not created.get("ok",false):rt.retire();return finish()
	var initial:String=digest(rt.capture_checkpoint())
	var old:Array=measure(reference);var current:Array=measure(service)
	check("complete ordered candidates equal original B loop",Data.json_equal(old,current),samples)
	check("nonempty real jobs and original three people remain",not current.is_empty() and rt.facts().actors.size()==3,{"cells":rt.zone_records()[0].cells.size(),"rows":current.size()})
	check("all candidate queries preserve complete authority",digest(rt.capture_checkpoint())==initial)
	var detached:Array=current.duplicate(true);detached.clear()
	check("fresh query cannot retain caller edited rows",Data.json_equal(service.work_candidates("player"),old))
	var facts:Dictionary=rt.facts();var overrides:Dictionary={};var z:Dictionary=rt.world.extension("r34:zones");z.zones[0].policy.worker_ids=["village-resident"];overrides["r34:zones"]=z
	check("worker policy change affects next query identically",Data.json_equal(service.work_candidates("player",facts,overrides),reference.work_candidates("player",facts,overrides)) and service.work_candidates("player",facts,overrides).is_empty())
	var dead:Dictionary=facts.duplicate(true);Draft.find(dead.actors,"player").hp=0
	check("HP removal next query rejects rather than cache",service.work_candidates("player",dead).is_empty() and reference.work_candidates("player",dead).is_empty())
	holds(live)
	check("isolated holds and alias counterexamples leave authority unchanged",digest(rt.capture_checkpoint())==initial)
	# Actual authority changes use the original public dispatcher; subsequent
	# candidates must see cancellation and no prior ordered result survives.
	var cancelled:Dictionary=rt.command({"kind":"zone.cancel","actor_id":"player","target_id":"B:query:forestry","command_id":"B:query:cancel","payload":{}})
	check("public zone cancel invalidates complete next query",cancelled.get("ok",false) and service.work_candidates("player").is_empty() and reference.work_candidates("player").is_empty())
	rt.retire();finish()
func holds(live:Dictionary)->void:
	var service:RefCounted=live.services.zonework;var prod:RefCounted=live.services.production
	var probe:=Probe.new();prod._hold_providers.append(weakref(probe))
	var tx:RefCounted=Workforce.observation(service,live.runtime.facts(),{})
	check("only explicit synchronous observer opts in",tx.observation_only and not Draft.new(service.context).observation_only and not Workforce.draft(service,{},{}).observation_only)
	var first:Array=prod.all_holds(tx);var n:int=probe.calls;var again:Array=prod.all_holds(tx)
	check("complete provider set computed once per unchanged observer",n==1 and probe.calls==n and Data.json_equal(first,again))
	first[-1].cost.log=999;again.clear();var exported:Dictionary=tx.observation_cache;exported.clear()
	check("public complete holds and cache are detached",prod.reserved("pack:player","log","",tx)==1 and probe.calls==n)
	Draft.find(tx.staged.actors,"player").hp=0;prod.all_holds(tx)
	check("nested borrowed actor edit invalidates full proof",probe.calls==n+1 and prod.reserved("pack:player","log","",tx)==0)
	tx.staged=live.runtime.facts();prod.all_holds(tx);n=probe.calls
	tx.extensions["B:probe"]={"amount":2};check("extension insert recomputes full holds",prod.reserved("pack:player","log","",tx)==2 and probe.calls==n+1)
	n=probe.calls;tx.extensions["B:probe"].amount=3
	check("nested extension edit is never stale",prod.reserved("pack:player","log","",tx)==3 and probe.calls==n+1)
	n=probe.calls;tx.extensions=tx.extensions.duplicate(true);prod.all_holds(tx)
	check("explicit extensions replacement invalidates even equal values",probe.calls==n+1)
	n=probe.calls;var another:RefCounted=Workforce.observation(service,live.runtime.facts(),tx.extensions);prod.all_holds(another)
	check("new synchronous query never inherits holds cache",probe.calls==n+1)
	var mutable:RefCounted=Workforce.draft(service,{},{});n=probe.calls
	prod.all_holds(mutable);prod.all_holds(mutable)
	check("mutable prepare Draft always consults every provider",probe.calls==n+2 and mutable.observation_cache.is_empty())
	mutable.extensions["B:probe"]={"amount":4};check("mutable nested changes read fresh",prod.reserved("pack:player","log","",mutable)==4)
	n=probe.calls;tx.result();prod.all_holds(tx);check("result boundary clears read proof",probe.calls==n+1)
	prod._hold_providers.pop_back()
func finish()->void:
	var report:Dictionary={"checks":checks,"samples":samples,"scope":"Same live Native new12 immutable input, public19x10 forestry approximate replay (not unsavedOS161), exact B before-loop reference with C same API/current dependencies, ordered DTO and authority equality; isolated explicit hold-provider counterexamples. CPU headless parallel, not FPS/OS/VA/package qualification."}
	FileAccess.open(output+"/query-evidence.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit(0 if not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
