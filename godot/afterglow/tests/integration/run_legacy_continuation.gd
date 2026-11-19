extends SceneTree
const Store=preload("res://scripts/storage/native_store.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+name+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();var directory:String=args[0];var host:=Client.new()
	for kind:String in ["drink-approach","cross-approach"]:
		var decoded:=Store.decode(FileAccess.get_file_as_string(directory+"/"+kind+".v5.json"))
		check(kind+" actual JS request decodes",decoded.ok,decoded.get("reason"))
		if not decoded.ok:continue
		var old:Dictionary=decoded.capture.facts.actors[0].duplicate(true)
		var assembly:Dictionary=host._assemble(decoded.capture)
		check(kind+" formal assembly succeeds",assembly.ok,assembly.get("reason"))
		if not assembly.ok:continue
		var runtime:RefCounted=assembly.runtime
		check(kind+" no activation movement, inventory loss or clock advancement",Geometry.point(runtime.actor("player"))==Geometry.point(old) and runtime.actor("player").pack==old.pack and runtime.clock()==decoded.capture.facts.time)
		check(kind+" original source intent unchanged",Data.json_equal(decoded.capture.facts.actors[0],old))
		if kind=="drink-approach":
			check("approach has a one-time continuation",runtime.actor("player").get("migration_resume",{}).get("legacy",{}).get("kind")=="drink")
			for n in 5:runtime.tick(0.1)
			check("approach waits for remaining real work",runtime.actor("player").pack.water==old.pack.water)
			for n in 20:runtime.tick(0.1)
			check("approach consumes one water after real arrival and labor",runtime.actor("player").pack.water==old.pack.water-1 and not runtime.actor("player").has("migration_resume"))
			var another:Dictionary=host._assemble(decoded.capture)
			var result:Dictionary=another.runtime.command({"command_id":"test:cancel:legacy-approach","actor_id":"player","kind":"cancel"})
			for n in 30:another.runtime.tick(0.1)
			check("normal cancellation clears continuation without late consumption",result.ok and another.runtime.actor("player").intent==null and not another.runtime.actor("player").has("migration_resume") and another.runtime.actor("player").pack.water==old.pack.water,result)
		else:
			var intent:Dictionary=runtime.actor("player").intent
			check("restored travel keeps the far-side region destination",intent.request.destination.regionId==old.intent.payload.nextRegion,intent.request.destination)
			check("restored travel contains a real B cross-region step",intent.steps.any(func(s:Dictionary)->bool:return s.get("kind")=="cross-region"))
			var destination:Dictionary=intent.request.destination.duplicate(true)
			for n in 5000:
				runtime.tick(0.1)
				if runtime.actor("player").intent==null:break
			var actual:Dictionary=runtime.actor("player")
			check("travel arrives through real supported movement at the far side",actual.regionId==destination.regionId and Geometry.point(actual).distance_to(Geometry.point(destination))<0.15,{"region":actual.regionId,"destination":destination,"actual":Geometry.location(actual),"activity":actual.activity})
			var bad:Dictionary=decoded.capture.duplicate(true);bad.facts.actors[0].intent.payload.nextRegion="region:not-generated"
			var rejected:Dictionary=host._assemble(bad)
			check("missing return connection refuses rather than shortening travel",not rejected.ok and rejected.code=="UNSUPPORTED_LEGACY_ACTIVITY",rejected)
	var report:Dictionary={"scope":"real old JS command fixtures and formal native assembly; not physical app acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close();print(JSON.stringify(report));host.free();quit(1 if report.failed else 0)
