extends SceneTree
const State=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var snapshot:Dictionary=Rural.generate(713)
	var original:=State.new();var optimized:=State.new()
	check("real rural authority loads",original.load_snapshot(snapshot).ok and optimized.load_snapshot(snapshot).ok)
	var id:String=original.region_ids()[0];var keys:Array=original.region_chunk_keys(id)
	var changes:Array=[]
	for key:String in keys.slice(0,mini(40,keys.size())):changes.append({"op":"chunk.residency","id":key,"before":true,"after":false})
	for world:RefCounted in [original,optimized]:
		var plan:Dictionary=world.prepare_changes(changes,world.get_revision())
		check("identical real cold fixture commits",plan.ok and world.commit_prepared(plan.capability).ok)
	var node:=Native.new()
	var canonical_started:int=Time.get_ticks_usec()
	while not original.region_is_resident(id):
		var conversion:Dictionary=original.prepare_region_residency(id,true,original.get_revision(),32)
		var prepared:Dictionary=original.prepare_changes(conversion.world_changes,original.get_revision())
		check("canonical original restore commits",prepared.ok and original.commit_prepared(prepared.capability).ok)
	var canonical_usec:int=Time.get_ticks_usec()-canonical_started
	var optimized_started:int=Time.get_ticks_usec()
	while not optimized.region_is_resident(id):
		var result:Dictionary=node._assembly_restore_batch(optimized,id)
		check("optimized bounded restore commits",result.ok)
	var optimized_usec:int=Time.get_ticks_usec()-optimized_started
	check("no-view restoration preserves exact authoritative snapshot and revisions",original.snapshot()==optimized.snapshot())
	var basis:Dictionary=optimized.snapshot()
	var stale:Dictionary=optimized.prepare_changes_without_view(changes,optimized.get_revision()-1)
	check("no-view path keeps stale revision rejection and exact authority",not stale.ok and optimized.snapshot()==basis)
	var bad:Dictionary=optimized.prepare_changes_without_view([{"op":"chunk.residency","id":keys[0],"before":false,"after":true}],optimized.get_revision())
	check("no-view path keeps before-value CAS rejection",not bad.ok and optimized.snapshot()==basis)
	for world:RefCounted in [original,optimized]:
		var plan:Dictionary=world.prepare_changes(changes,world.get_revision());check("legacy fixture recools",plan.ok and world.commit_prepared(plan.capability).ok)
	var legacy:Array=[]
	for key:String in original.chunk_keys():
		if not original.chunk(key).resident:legacy.append({"op":"chunk.residency","id":key,"before":false,"after":true})
	var prepared:Dictionary=original.prepare_changes(legacy,original.get_revision());check("canonical legacy commit",prepared.ok and original.commit_prepared(prepared.capability).ok)
	check("optimized legacy restore commits",node._assembly_restore_legacy(optimized).ok)
	check("legacy no-view restore preserves exact snapshot",original.snapshot()==optimized.snapshot())
	node.free()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var out:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"restore-prepare15","checks":checks,"failed":failed,"canonical_usec":canonical_usec,"optimized_usec":optimized_usec,"scope":"Actual C region-residency conversion, same 32-chunk batches, exact state/revision equivalence and stale/before CAS. Timings are a bounded headless source probe, not gameplay FPS."},"\t",true,true))
	print(JSON.stringify({"suite":"restore-prepare15","checks":checks.size(),"failed":failed,"canonical_usec":canonical_usec,"optimized_usec":optimized_usec}));quit(1 if failed else 0)
