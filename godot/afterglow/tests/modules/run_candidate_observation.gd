extends SceneTree
## Original saved states plus explicitly isolated query-only counterexamples.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const CurrentActions=preload("res://scripts/actions/workforce_executor.gd")
const CurrentModules=preload("res://scripts/modules/module_workforce.gd")
const OldActions=preload("res://tests/modules/query_reference/workforce_executor.gd")
const OldModules=preload("res://tests/modules/query_reference/module_workforce.gd")
var checks:Array=[]
func check(label:String,ok:bool)->void:checks.append({"name":label,"ok":ok})
func _initialize()->void:call_deferred("run")
func compare(services:Dictionary,facts:Dictionary,overrides:Dictionary,label:String)->void:
	var f0:=facts.duplicate(true);var e0:=overrides.duplicate(true)
	for actor_id:String in ["*","player","village-resident","repair-resident","missing-person"]:
		var expected: Array=OldActions.candidates(services.actions,actor_id,facts,overrides)
		var actual:Array=CurrentActions.candidates(services.actions,actor_id,facts,overrides)
		check(label+" action exact "+actor_id,Data.json_equal(actual,expected))
		var em:Array=OldModules.candidates(services.modules,actor_id,facts,overrides)
		var am:Array=CurrentModules.candidates(services.modules,actor_id,facts,overrides)
		check(label+" module exact "+actor_id,Data.json_equal(am,em))
		# Returned candidate arrays/locations/items cannot alias input authority.
		for row:Dictionary in actual+am:
			if row.has("items"):row.items["query_poison"]=123
			if row.has("location"):row.location["x"]=10000
			row.reason="query_poison"
	check(label+" caller facts/overrides unchanged including actor port probes",Data.json_equal(facts,f0) and Data.json_equal(overrides,e0))
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0];var rows:Array=[]
	for path:String in args.slice(1):
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path));var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
		check("actual Native input "+path,built.get("ok",false))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var services:Dictionary=built.services;var capture:Dictionary=rt.capture_checkpoint()
		var facts:Dictionary=rt.facts();var extensions:Dictionary=built.world.snapshot().extensions
		compare(services,facts,extensions,"actual complete "+str(rows.size()))
		compare(services,facts,{},"lazy world extensions "+str(rows.size()))
		compare(services,{},extensions,"default facts "+str(rows.size()))
		var timings:Array=[]
		for mode:String in ["original","current","current","original"]:
			var t:int=Time.get_ticks_usec();var all_equal:bool=true;var first:Array=[]
			for i:int in 102:
				var c:Array=OldActions.candidates(services.actions,"*",facts,extensions) if mode=="original" else CurrentActions.candidates(services.actions,"*",facts,extensions)
				if i==0:first=c
				else:all_equal=all_equal and c==first
			timings.append({"mode":mode,"calls":102,"usec":Time.get_ticks_usec()-t});check("same query stable "+str(rows.size())+mode+str(timings.size()),all_equal)
		# Query-only project fixture, NOT a legal normal-world build or completion.
		var query_ext:=extensions.duplicate(true);var modules:Dictionary=query_ext["r34:modules"]
		var m:Dictionary=modules.instances.filter(func(v:Dictionary)->bool:return v.status in ["operational","damaged"] and v.region=="RH-HOME")[0]
		modules.projects.append({"id":"query-only-project","module_id":m.id,"operation":"repair","source_id":"pack:player","actor_id":"player","tool_id":"","cost":{},"status":"paused","created_at":rt.clock(),"duration_seconds":10.0,"progress_seconds":1.0,"effective_work":0.0,"paused_reason":"query_only"})
		compare(services,facts,query_ext,"isolated actual-port probe "+str(rows.size()))
		var denied:=facts.duplicate(true)
		for actor:Dictionary in denied.actors:actor.relationship.consent=false;actor.hp=0
		compare(services,denied,query_ext,"isolated disabled/revoked "+str(rows.size()))
		check("all authority unchanged "+str(rows.size()),Data.json_equal(capture,rt.capture_checkpoint()))
		rows.append({"input":path,"timings":timings});rt.retire()
	var report:Dictionary={"checks":checks,"rows":rows,"scope":"saved-state read-only query equality/caller isolation plus explicit uncommitted project/permission counterexamples; CPU only, no normal economic lifecycle or FPS claim"}
	FileAccess.open(output+"/detail.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
