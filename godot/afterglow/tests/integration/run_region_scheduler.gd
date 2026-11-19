extends SceneTree
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var output:String
var jobs:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Buildings.generation_profiles()))
	check("real C terrain/B settlement prepares",prepared.ok,prepared.get("code"))
	if not prepared.ok:finish();return
	var host:=Client.new();var built:Dictionary=host._assemble(prepared.capture);host.free()
	check("same formal assembly configures all existing domain services",built.ok,built.get("code"))
	if not built.ok:finish();return
	var r:RefCounted=built.runtime;var w:RefCounted=built.world
	var old:Dictionary=w.snapshot();var oldfacts:Dictionary=r.facts()
	jobs=Scheduler.new();jobs.attach(r,built.services.buildings,1)
	check("nonadjacent request cannot allocate a separate island",jobs.request(Vector2i(5,5)).code=="NONADJACENT_REGION")
	check("existing region is idempotent",jobs.request(Vector2i.ZERO).code=="ALREADY_GENERATED")
	var first:Dictionary=jobs.request(Vector2i(1,0));var second:Dictionary=jobs.request(Vector2i(1,0))
	check("duplicate requests share one worker and no queued duplicate",first.ok and second.code=="PENDING" and jobs.status().requested==1 and jobs.status().queued==0)
	var result:Dictionary={};var deadline:int=Time.get_ticks_msec()+60000
	while result.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;result=jobs.poll(0,false)
		if jobs._active.has("draft"):break
	check("finished value job cannot mutate world before owner allows commit",jobs._active.has("draft") and w.get_revision()==old.revision and Data.json_equal(r.facts(),oldfacts))
	# Publication prepares the world and family in successive process frames.
	deadline=Time.get_ticks_msec()+60000
	while result.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
		result=jobs.poll(0,true)
	check("real C draft/B buildings/stocks commit through same A authority",result.get("ok",false) and not w.region("R2:1:0").is_empty(),{"code":result.get("code"),"revision":result.get("revision"),"reason":result.get("reason")})
	if result.get("ok",false):
		check("new plan and region persist at true adjacent coordinates",w.region("R2:1:0").bounds.min.x==64 and not w.extension("generation:R2:1:0").is_empty())
		var unchanged:=true
		for key:String in old.chunks:
			if not Data.json_equal(old.chunks[key],w.chunk(key)):unchanged=false;break
		check("all existing authoritative cells remain exact",unchanged)
		check("existing actors and clock unchanged by map preparation",Data.json_equal(r.facts().actors,oldfacts.actors) and r.clock()==oldfacts.time)
		var stocks:int=r.facts().stocks.size();var revision:int=w.get_revision()
		check("revisit does not regenerate or duplicate rewards",jobs.request(Vector2i(1,0)).code=="ALREADY_GENERATED" and r.facts().stocks.size()==stocks and w.get_revision()==revision)
		var saved:Dictionary=Store.encode(r.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.get("text",""))
		var restoring:=Client.new();var restored:Dictionary=restoring._assemble(decoded.capture) if decoded.ok else decoded;restoring.free()
		check("expanded finite map survives native codec/full reassembly",saved.ok and restored.ok and not restored.world.region("R2:1:0").is_empty(),restored.get("reason"))
		if restored.ok:
			# Same native JSON representation: the existing codec documents ULP
			# rounding of generated decorative doubles, not changed cell bytes.
			var expected_plan:Dictionary=JSON.parse_string(JSON.stringify(w.extension("generation:R2:1:0"),"",true,true))
			var expected_stocks:Array=JSON.parse_string(JSON.stringify(r.facts().stocks,"",true,true))
			check("reassembly preserves native JSON plan and exact finite stocks",Data.json_equal(restored.world.extension("generation:R2:1:0"),expected_plan) and Data.json_equal(restored.runtime.facts().stocks,expected_stocks),{"plan":Data.json_equal(restored.world.extension("generation:R2:1:0"),expected_plan),"stocks":Data.json_equal(restored.runtime.facts().stocks,expected_stocks)})
	# Old worker is not killed, joined on a render frame, or allowed to commit.
	var before:Dictionary=w.snapshot()
	check("second adjacent task can start",jobs.request(Vector2i(-1,0)).ok)
	jobs.cancel();deadline=Time.get_ticks_msec()+60000
	while jobs.status().active and Time.get_ticks_msec()<deadline:await process_frame;jobs.poll(0,false)
	check("cancelled epoch is discarded without changing former authority",not jobs.status().active and jobs.status().discarded==1 and Data.json_equal(w.snapshot(),before))
	check("queue and worker remain bounded",jobs.status().peak_queue<=Scheduler.MAX_QUEUED and jobs.status().queued==0 and jobs.status().worker_limit==1)
	jobs.shutdown();finish()
func finish()->void:
	if jobs!=null:jobs.shutdown()
	var report:Dictionary={"scope":"source/headless real Thread/C draft/B assembly/A atomic commit and native reassembly; no OS/FPS claim","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close();print(JSON.stringify(report));quit(1 if report.failed else 0)
