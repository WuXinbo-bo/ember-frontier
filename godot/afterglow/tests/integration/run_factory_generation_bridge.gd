extends SceneTree
## Real saved8/9, explicit locked10 and new12 through the same scheduler.
## Explicit historical input is read-only; no graphical client or user saves.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var output:String
var jobs:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:quit(2);return
	output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:String=FileAccess.get_file_as_string(args[1])
	var original9:String=FileAccess.get_file_as_string(args[2])
	var old:Dictionary=Store.decode(original)
	check("explicit historical native input decodes",old.get("ok",false),old.get("code"))
	if not old.get("ok",false):return finish()
	check("historical input really pins content8",old.capture.world.extensions.get("generation:factory-r34",{}).get("content_version")==8)
	var old9:Dictionary=Store.decode(original9)
	check("explicit actual content9 native input decodes",old9.get("ok",false),old9.get("code"))
	if not old9.get("ok",false):return finish()
	check("actual previous input really pins content9",old9.capture.world.extensions.get("generation:factory-r34",{}).get("content_version")==9)
	var profiles:Dictionary=Assembly.generation_profiles()
	var fresh:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.ok else profiles
	check("formal new entry prepares content12",fresh.get("ok",false) and fresh.get("capture",{}).get("world",{}).get("extensions",{}).get("generation:factory-r34",{}).get("content_version")==12,fresh.get("code"))
	if not fresh.get("ok",false):return finish()
	var locked10:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,10))
	if not locked10.get("ok",false):check("explicit locked10 still prepares",false,locked10.get("code"));return finish()
	await expand(old.capture,8)
	await expand(old9.capture,9)
	await expand(locked10.capture,10)
	await expand(fresh.capture,12)
	check("original historical save bytes never changed",original==FileAccess.get_file_as_string(args[1]))
	check("original actual content9 save bytes never changed",original9==FileAccess.get_file_as_string(args[2]))
	finish()
func expand(capture:Dictionary,version:int)->void:
	var host:=Client.new()
	var built:Dictionary=host._assemble(capture);host.free()
	check("shipping cold assembly configures content"+str(version),built.get("ok",false),built.get("code"))
	if not built.get("ok",false):return
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world
	var before:Dictionary=runtime.capture_checkpoint()
	var configuration:Dictionary=world.extension("generation:factory-r34")
	jobs=Scheduler.new();jobs.attach(runtime,built.services.buildings,version,built.services.modules)
	var chosen:=Vector2i.ZERO;var found:=false
	for region:Dictionary in world.regions():
		var at:Dictionary=region.data.regionCoord
		for direction:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var candidate:=Vector2i(int(at.x),int(at.z))+direction
			if world.region(Factory.region_id(candidate)).is_empty():chosen=candidate;found=true;break
		if found:break
	check("real adjacent ungenerated frontier exists content"+str(version),found)
	if not found:jobs.shutdown();jobs=null;return
	var requested:Dictionary=jobs.request(chosen)
	check("same scheduler starts pinned profile job content"+str(version),requested.get("ok",false),requested)
	var expected_profiles:int=19 if version in [10,12] else 18 if version==9 else 12
	check("worker consumes saved-world profile set content"+str(version),jobs._active.get("input",{}).get("profiles",[]).size()==expected_profiles,jobs._active.get("input",{}).get("code"))
	var result:Dictionary={};var deadline:int=Time.get_ticks_msec()+60000
	while requested.get("ok",false) and result.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame;result=jobs.poll(0.0,true)
	var id:String=Factory.region_id(chosen)
	check("threaded draft and real module registration commit content"+str(version),result.get("ok",false) and not world.region(id).is_empty(),result)
	check("expansion preserves exact original generation lock content"+str(version),Data.json_equal(configuration,world.extension("generation:factory-r34")))
	var prior_plans_ok:=true
	for region:Dictionary in before.world.regions.values():
		var key:String="generation:"+str(region.id)
		if not Data.json_equal(before.world.extensions.get(key),world.extension(key)):prior_plans_ok=false
	check("all preexisting region plans stay exact content"+str(version),prior_plans_ok)
	check("real actors and simulation time stay exact content"+str(version),Data.json_equal(before.facts.actors,runtime.facts().actors) and before.facts.time==runtime.clock())
	var original_stocks_ok:=true
	for stock:Dictionary in before.facts.stocks:
		if not Data.json_equal(stock,runtime.stock(stock.id)):original_stocks_ok=false
	check("old stock identities and amounts are untouched content"+str(version),original_stocks_ok)
	if version==12:
		check("frontier generation never adds a second regional seed bag",runtime.facts().stocks.filter(func(s:Dictionary)->bool:return str(s.id).ends_with(":regional-seed-bag:v1")).size()==1)
	var checkpoint:Dictionary=runtime.capture_checkpoint()
	var repeated:Dictionary=jobs.request(chosen)
	check("revisit neither regenerates nor grants sources content"+str(version),repeated.get("code")=="ALREADY_GENERATED" and Data.json_equal(checkpoint,runtime.capture_checkpoint()))
	var saved:Dictionary=Store.encode(checkpoint)
	var restored:Dictionary=Store.decode(saved.text) if saved.ok else saved
	var cold_host:=Client.new()
	var cold:Dictionary=cold_host._assemble(restored.capture) if restored.ok else restored;cold_host.free()
	check("native codec and shipping cold restore preserve expanded world content"+str(version),cold.get("ok",false) and not cold.world.region(id).is_empty() and Data.json_equal(JSON.parse_string(JSON.stringify(configuration,"",true,true)),cold.world.extension("generation:factory-r34")),cold.get("code"))
	jobs.shutdown();jobs=null
func finish()->void:
	if jobs!=null:jobs.shutdown()
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Actual historical8/actual9/explicit locked10/new12 native cold assembly, shipping threaded frontier, exact old facts and native restore. No renderer/OS/VA/performance qualification.","checks":checks,"failed":failed},"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
