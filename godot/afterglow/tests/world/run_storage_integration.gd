extends SceneTree
## Waits for A's actual storage code, exercising C pure codec in its real worker.
## Writes only a new C evidence directory, never the formal user save directory.
const State = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Data = preload("res://scripts/world/world_data.gd")
var checks: Array = []

func test(label: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"label":label,"ok":condition,"detail":detail})
	if not condition: push_error(label+str(detail))

func _initialize() -> void: call_deferred("run")

func saved(store: RefCounted, capture: Dictionary, fresh: bool) -> Dictionary:
	var queued: Dictionary = store.begin_save(capture,fresh)
	if not queued.ok: return queued
	var deadline := Time.get_ticks_msec()+20000
	while store.save_pending() and Time.get_ticks_msec()<deadline:
		var result: Dictionary = store.poll()
		if not result.is_empty(): return result
		await create_timer(0.01).timeout
	return {"ok":false,"code":"TEST_TIMEOUT"}

func run() -> void:
	var world := State.new()
	world.load_snapshot(Generator.generate())
	var actor := {"id":"player","x":32.0,"y":0.0,"z":44.0,"regionId":"RH-HOME","hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{},"intent":null}
	var capture := {"schema":"afterglow-native-state-v1","world":world.snapshot(),"facts":{"actors":[actor],"stocks":Generator.empty_resource_stocks(world),"actions":[],"quests":[],"time":0.0,"status":"playing"},"source":{},"receipts":{},"command_revision":0}
	var directory := ProjectSettings.globalize_path("res://../../outputs/r3.3-ccc-evidence/native-storage-domain-"+str(Time.get_ticks_usec()))
	var store: RefCounted = Store.new(directory)
	var first: Dictionary = await saved(store,capture,true)
	test("A Thread encodes C world and atomically writes real file",first.get("ok",false),first)
	if first.get("ok",false):
		var loaded: Dictionary = store.load_current()
		test("disk load restores 512 C chunks and same runtime facts",loaded.get("ok",false) and loaded.capture.world.chunks.size()==512 and Data.json_equal(loaded.capture.facts,capture.facts),loaded.get("checkpoint_id"))
		var second: Dictionary = await saved(store,capture,false)
		test("second save advances double-slot pointer",second.get("ok",false) and second.path!=first.path,second)
		if second.get("ok",false):
			var bad := FileAccess.open(second.path,FileAccess.WRITE)
			# Valid JSON with a corrupted payload SHA: checks the real fallback
			# without parse_string's intentional malformed-JSON engine error log.
			bad.store_string('{"format":"afterglow-native-v1","payload":"{}","sha256":"damaged"}')
			bad.close()
			var fallback: Dictionary = store.load_current()
			test("real damaged active slot recovers earlier world",fallback.get("ok",false) and fallback.get("recovered",false) and Data.json_equal(fallback.capture.facts,capture.facts),{"path":fallback.get("path"),"recovered":fallback.get("recovered")})
	var source := FileAccess.get_file_as_string("res://../../outputs/r3.3-ccc-evidence/ordinary-world-713/validated-source/checkpoint.v5.json")
	var ordinary: Dictionary = Store.decode(source)
	test("A storage imports real ordinary1536 chunks using C legacy codec",ordinary.get("ok",false) and ordinary.capture.world.chunks.size()==1536,ordinary.get("reason"))
	if ordinary.get("ok",false):
		var old_tools: Array = ordinary.capture.source.legacy_extensions["r3:runtime"].get("tools",[])
		var live_tools: Array = ordinary.capture.world.extensions["r3:production"].get("tools",[])
		var preserved: bool = not ordinary.capture.facts.has("tools") and not old_tools.is_empty()
		for tool in old_tools:
			var found := false
			for live in live_tools:
				if live.id==tool.id and live.holderId==tool.holderId and live.durability==tool.durability and Data.json_equal(live.get("qualities",{}),tool.qualities): found=true
			preserved=preserved and found
		test("legacy terrain tools retain exact ID holder wear qualities in one live table",preserved,{"source_tools":old_tools.size(),"live_tools":live_tools.size()})
	var failures := checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"C codec + A Thread/FileAccess isolated domain check; no exported application/restart acceptance","directory":directory,"checks":checks,"failed":failures}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result))
	quit(1 if failures else 0)
