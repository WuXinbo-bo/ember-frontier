extends SceneTree
const Store = preload("res://scripts/storage/native_store.gd")
const World = preload("res://scripts/world/world_state.gd")
const Rural = preload("res://scripts/world/rural_generator.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Initial = preload("res://scripts/runtime/initial_state.gd")
const Data = preload("res://scripts/world/world_data.gd")
var checks: Array=[]
func _initialize() -> void:call_deferred("run")
func test(name: String,value: bool,detail: Variant=null) -> void:
	checks.append({"name":name,"ok":value,"detail":detail})
	if not value:push_error("FAIL "+name+" "+str(detail))
func run() -> void:
	var output:String=OS.get_cmdline_user_args()[0]
	var world:=World.new();test("rural world load",world.load_snapshot(Rural.generate()).ok)
	var runtime:=Runtime.new();var b:=Building.new();b.configure({"world":world,"runtime":runtime})
	var seeded:Dictionary=b.seed_rural(world)
	test("actual B rural seed",seeded.ok)
	var facts:Dictionary=Initial.facts(seeded)
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append({"op":"extension.set","id":"r3:production","before":null,"before_exists":false,"after":Initial.production(seeded)})
	var prepared:Dictionary=world.prepare_changes(changes,world.get_revision())
	test("C accepts B buildings and A initial production atomically",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(output);return
	var safe:Dictionary=b.validate_world_draft(prepared.view,facts,changes)
	test("real initial three actors have support and safe exits",safe.ok,safe.get("reason"))
	test("initial commit",world.commit_prepared(prepared.capability).ok)
	test("runtime config",runtime.configure({"world":world,"facts":facts,"services":{"buildings":b}}).ok)
	var capture:Dictionary=runtime.capture_checkpoint()
	var encoded:Dictionary=Store.encode(capture)
	test("full C codec plus A facts encode",encoded.ok,encoded.get("reason"))
	if not encoded.ok:finish(output);return
	var decoded:Dictionary=Store.decode(encoded.text)
	test("full native envelope decode",decoded.ok,decoded.get("reason"))
	if decoded.ok:
		test("all actors stocks quests and clock survive",Data.json_equal(decoded.capture.facts,capture.facts))
		test("all cell bytes survive native roundtrip",same_cells(decoded.capture.world,capture.world))
	var invalid:Dictionary=JSON.parse_string(encoded.text);invalid.payload+=" "
	test("tampered payload refused",not Store.decode(JSON.stringify(invalid)).ok)
	var store:=Store.new(output+"/slots")
	test("first background save starts",store.begin_save(capture).ok)
	var first:Dictionary={}
	while first.is_empty():await process_frame;first=store.poll()
	test("background file save validated and committed",first.ok,first)
	var restored:Dictionary=store.load_current()
	test("restart path reads same world and facts",restored.ok and Data.json_equal(restored.capture.facts,capture.facts),restored.get("reason"))
	capture.facts.actors[0].pack.water=7
	store.begin_save(capture)
	var second:Dictionary={}
	while second.is_empty():await process_frame;second=store.poll()
	test("second save uses other physical slot",second.ok and second.path!=first.path,second)
	var f:=FileAccess.open(second.path,FileAccess.WRITE);f.store_string("{broken");f.close()
	var fallback:Dictionary=store.load_current()
	test("damaged latest slot recovers prior verified snapshot",fallback.ok and fallback.get("recovered",false) and fallback.capture.facts.actors[0].pack.water==1,fallback.get("reason"))
	var legacy_path:String=output.get_base_dir().get_base_dir().get_base_dir()+"/work/r3-2/ordinary-source-713/checkpoint.v5.json"
	# Optional explicit source path is supplied by the runner, never inferred as proof.
	if OS.get_cmdline_user_args().size()>1:legacy_path=OS.get_cmdline_user_args()[1]
	if FileAccess.file_exists(legacy_path):
		var legacy:Dictionary=Store.decode(FileAccess.get_file_as_string(legacy_path))
		test("actual canonical ordinary v5 imports",legacy.ok,legacy.get("reason"))
		if legacy.ok:
			var tools:Array=legacy.capture.world.extensions["r3:production"].tools
			test("old shovel/pickaxe retain exact IDs and one live table",tools.any(func(t:Dictionary)->bool:return t.id=="world-tool:shovel" and t.qualities.shovel==1) and tools.any(func(t:Dictionary)->bool:return t.id=="world-tool:pickaxe") and not legacy.capture.facts.has("tools"))
			var migrated:Dictionary=Store.encode(legacy.capture)
			test("ordinary legacy fully re-encodes to native",migrated.ok,migrated.get("reason"))
	finish(output)
func same_cells(a:Dictionary,b:Dictionary) -> bool:
	if a.chunks.size()!=b.chunks.size():return false
	for key in a.chunks:
		if not b.chunks.has(key) or a.chunks[key].cells!=b.chunks[key].cells:return false
	return true
func finish(output:String) -> void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"scope":"actual runtime/C codec/B safety/Thread/FileAccess in isolated evidence directory; not app UI acceptance","checks":checks,"failed":failed}
	DirAccess.make_dir_recursive_absolute(output)
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify(report));quit(1 if failed else 0)
