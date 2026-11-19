extends SceneTree
## Original naturally acquired checkpoint, including infected loot inventories.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("original natural infected checkpoint decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(output)
	var host:=Client.new();var assembled:Dictionary=host._assemble(decoded.capture);host.free()
	check("same authoritative checkpoint assembles",assembled.get("ok",false),assembled.get("reason"))
	if not assembled.get("ok",false):return finish(output)
	var runtime:RefCounted=assembled.runtime
	var before:Dictionary=runtime.capture_checkpoint()
	var infected:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("appearance_id")=="infected_walker")
	check("natural input actually includes infected with loot",not infected.is_empty() and infected.any(func(a:Dictionary)->bool:return not a.pack.is_empty()))
	var view:=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	check("all original rigs mount without invented carry clips",view.assembly_report().ok,view.assembly_report())
	for index:int in 4:view.sync(.016)
	for actor:Dictionary in infected:
		check("infected loot selects actual infected motion "+str(actor.id),view._states.get(actor.id) in ["Idle","Walk","Run","Attack","Hit"] and not view._carried.has(actor.id),view._states.get(actor.id))
	check("repeated visual synchronization retains full original inventory and authority",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free();runtime.retire();finish(output)
func finish(output:String)->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Real saved infected inventories and original GLB animation assembly; no inventory edits or render-FPS qualification"},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
