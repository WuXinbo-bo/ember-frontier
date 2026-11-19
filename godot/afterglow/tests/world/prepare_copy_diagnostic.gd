extends SceneTree
## Read-only production-source diagnosis. Never substitutes a weaker draft/view.
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var costs:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:push_error("FAIL "+label)
func measure(world:RefCounted,label:String)->void:
	var original:Dictionary=world.snapshot()
	var times:Dictionary={"public_deep_snapshot":[],"empty_prepare_and_isolated_view":[],"small_metadata_prepare_and_isolated_view":[]}
	var valid:bool=true
	for iteration in 7:
		var order:Array=times.keys()
		if iteration%2==1:order.reverse()
		for kind:String in order:
			var started:int=Time.get_ticks_usec()
			if kind=="public_deep_snapshot":
				var detached:Dictionary=world.snapshot()
				var ms:float=(Time.get_ticks_usec()-started)/1000.0
				valid=valid and detached.revision==original.revision
				if iteration>=2:times[kind].append(ms)
			else:
				var changes:Array=[] if kind=="empty_prepare_and_isolated_view" else [{"op":"extension.set","id":"test:copy-cost","before_exists":false,"before":null,"after":{"cursor":iteration}}]
				var result:Dictionary=world.prepare_changes(changes,world.get_revision())
				var ms:float=(Time.get_ticks_usec()-started)/1000.0
				valid=valid and result.ok
				if result.ok:world.discard_prepared(result.capability)
				if iteration>=2:times[kind].append(ms)
	var summaries:Dictionary={}
	for kind:String in times:
		var sorted:Array=times[kind].duplicate();sorted.sort()
		summaries[kind]={"samples_ms":times[kind],"median_ms":sorted[2],"max_ms":sorted[-1]}
	check(label+" all native prepares succeed and discard leaves exact facts/revision",valid and Data.json_equal(original,world.snapshot()))
	costs.append({"case":label,"chunks":world.chunk_keys().size(),"entities":world.entities().size(),"regions":world.regions().size(),"timings":summaries})
func run()->void:
	var profiles:Array=Buildings.generation_profiles()
	var source:Dictionary=Landscape.generate(973339546,profiles)
	var assembled:Dictionary=Assembly.prepare(source)
	check("diagnostic consumes real complete A/B assembled source",assembled.ok)
	if assembled.ok:
		var world:=State.new();check("assembled world loads for native prepare diagnosis",world.load_snapshot(assembled.capture.world).ok)
		measure(world,"actual two-region assembled v4")
		var prepared:Dictionary=Rural.prepare_region(world,Vector2i(1,0),profiles,world.get_revision())
		var tx:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision()) if prepared.ok else prepared
		var committed:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
		check("same isolated authority expands real third coordinate",committed.ok and world.chunk_keys().size()==768)
		if committed.ok:measure(world,"same world with true third generated region")
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs,"scope":"Two warmups then five alternating native CPU samples; real complete A/B source and same-authority peripheral expansion, no production source modifications or live user world access. Public deep snapshot is a separate reference operation, not internal-stage attribution; empty prepare still returns isolated view. No safety removed, Metal/GPU/FPS claim or new optimization adopted."}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
