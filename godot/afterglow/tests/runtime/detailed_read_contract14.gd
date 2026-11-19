extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles(14)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,14))
	var node:=Native.new();var made:Dictionary=node._assemble(prepared.capture);node.free()
	check("actual14 runtime assembles",made.get("ok",false))
	if not made.get("ok",false):return finish()
	var rt:RefCounted=made.runtime;var world:RefCounted=rt.world
	check("detached scalar IDs preserve actual region order",world.region_ids()==world.regions().map(func(r:Dictionary)->String:return r.id))
	var ids:Array=world.region_ids();ids.clear()
	check("caller cannot mutate world through region IDs",not world.region_ids().is_empty())
	check("warm region reads true outside fixed step",rt.region_is_detailed("RH-HOME") and rt.region_is_detailed("RH-HOME"))
	check("unknown region remains false",not rt.region_is_detailed("missing"))
	var key:String=world.region_chunk_keys("RH-HOME")[0]
	var snap:Dictionary=world.snapshot();var revision:int=world.get_revision()
	var plan:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
	var committed:Dictionary=world.commit_prepared(plan.capability) if plan.ok else plan
	check("real storage commit immediately revokes cached detailed predicate",committed.ok and not rt.region_is_detailed("RH-HOME") and not rt.region_is_detailed("RH-HOME"))
	var cold:Dictionary=world.snapshot();snap.revision=world.get_revision()
	check("warm snapshot with same revision reloads",world.load_snapshot(snap).ok and world.get_revision()==cold.revision)
	check("fresh generation prevents stale cold proof",rt.region_is_detailed("RH-HOME"))
	check("same-revision cold reload succeeds",world.load_snapshot(cold).ok)
	check("same-revision reload generation prevents stale warm proof",not rt.region_is_detailed("RH-HOME"))
	rt.retire();finish()
func finish()->void:
	var args:Array=OS.get_cmdline_user_args();var path:String=args[0] if not args.is_empty() else "user://detailed-read14"
	DirAccess.make_dir_recursive_absolute(path)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(path+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Actual native metadata/residency commits and same-revision snapshot-generation invalidation; no graphics/FPS claim."},"\t",true,true))
	print(JSON.stringify({"suite":"detailed-read14","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
