extends SceneTree
## Real content15 public reads: scope, isolation, compatibility and CPU cost.
## This is not a renderer or FPS acceptance test.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Profile=preload("res://scripts/runtime/playtest_profile.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var checks:Array=[]
var samples:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles(15)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,15)) if profiles.ok else profiles
	check("real content15 capture prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var capture:Dictionary=Profile.prepare_opening(prepared.capture,"normal")
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free()
	check("real NativeClient validation assembles",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime
	var before:Dictionary=rt.capture_checkpoint()
	var full:Dictionary=rt.snapshot()
	var inventory:Dictionary=rt.ui_page_snapshot("factory_inventory","")
	for key:String in ["player","actors","stocks","tools","records","knowledge","quests","orders"]:
		check("inventory preserves original public "+key,inventory.get(key)==full.get(key))
	check("inventory avoids unrelated world and work directory",inventory.regions.is_empty() and inventory.work_targets.is_empty())
	var catalog:Dictionary=rt.factory_page_snapshot("player","factory_catalog","")
	check("catalog retains native schema and navigation capability",catalog.schema=="afterglow-factory-display-v1" and catalog.version==1 and catalog.available and catalog.modules.available and catalog.production.available)
	check("catalog does not enumerate modules/jobs/production",catalog.modules.instances.is_empty() and catalog.workforce.get("people",[]).is_empty() and catalog.production.orders.is_empty() and catalog.logistics.tasks.is_empty())
	check("catalog retains exact owner build selection",catalog.modules.build_definition_ids==preload("res://scripts/modules/module_catalog.gd").build_definition_ids())
	var ui_catalog:Dictionary=rt.ui_page_snapshot("factory_catalog","")
	check("catalog keeps the existing movable cabinet definition",ui_catalog.catalog.buildings.size()==1 and ui_catalog.catalog.buildings[0].id=="cabinet")
	var station:String="r34:generated:RH-HOME:woodwork:workbench"
	var workshop:Dictionary=rt.factory_page_snapshot("player","workbench",station)
	check("member workbench resolves exactly its owning module",workshop.modules.instances.size()==1 and workshop.modules.instances[0].id=="r34:generated:RH-HOME:woodwork")
	check("workbench retains live recipe controls and member identity",not workshop.modules.instances[0].get("recipe_management",{}).get("recipes",[]).is_empty() and workshop.modules.instances[0].get("members",[]).any(func(row:Dictionary)->bool:return row.id==station))
	var bench:Dictionary=rt.ui_page_snapshot("workbench",station)
	check("workbench keeps existing legacy recipes",not bench.catalog.get("recipes",bench.catalog.get("production_recipes",[])).is_empty())
	check("pause avoids detailed stocks and world catalog",rt.ui_page_snapshot("pause").stocks.size()==1 and not rt.ui_page_snapshot("pause").catalog.has("recipes"))
	var map:Dictionary=rt.factory_page_snapshot("player","factory_alerts","")
	check("map publishes detached explored cartography",map.get("map",{}).get("cartography",{}).get("schema")=="afterglow-known-cartography-v1")
	catalog.modules.definitions.clear();inventory.player.pack["test-only"]=1
	check("mutating returned dictionaries never changes another read",not rt.factory_page_snapshot("player","factory_catalog","").modules.definitions.is_empty() and not rt.actor("player").pack.has("test-only"))
	check("all public page reads preserve complete authority",before==rt.capture_checkpoint())
	for page:String in ["pause","factory_inventory","factory_catalog","factory_people","factory_alerts"]:
		for i:int in 3:
			var started:int=Time.get_ticks_usec();rt.ui_page_snapshot(page,"");var ui_usec:int=Time.get_ticks_usec()-started
			started=Time.get_ticks_usec();rt.factory_page_snapshot("player",page,"");var factory_usec:int=Time.get_ticks_usec()-started
			samples.append({"page":page,"sample":i,"ui_usec":ui_usec,"factory_usec":factory_usec})
	var encoded:Dictionary=Store.encode(capture)
	if encoded.ok:FileAccess.open(output+"/normal15.capture.json",FileAccess.WRITE).store_string(encoded.text)
	rt.retire();finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"samples":samples,"scope":"Source content15 pure page reads and CPU samples, not GPU or complete gameplay acceptance"},"\t",true,true))
	print("CONTROLS15_PAGES "+JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
