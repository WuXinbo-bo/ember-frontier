extends SceneTree
## Actual untouched opening through shipping Native/FactoryServices composition.
## No injected resident/resource/job; one normal STEP (residents may walk).
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const PerformanceView=preload("res://scripts/presentation/native_performance.gd")
const EXPECTED=["actions","buildings","display","ecology","gameplay","modules","production","residents","terrain","workforce","zones","zonework"]
const ADVANCE=["ecology","residents","workforce","actions","zonework","modules","production","terrain","gameplay","display"]
var checks:Array=[]
var host:Node
var rt:RefCounted
var output:String
var owners:Array=[]
var details:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->bool:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
	return ok
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var bytes:String=FileAccess.get_file_as_string(args[1]);var input_hash:String=bytes.sha256_text()
	var decoded:Dictionary=Store.decode(bytes)
	if not check("untouched actual Native envelope decodes",decoded.get("ok",false),decoded.get("reason")):return finish()
	check("input is regional-production content12",decoded.capture.world.extensions.get("generation:factory-r34",{}).get("content_version")==12)
	host=Native.new();var built:Dictionary=host._assemble(decoded.capture)
	if not check("shipping Native assembly mounts real services and required residency",built.get("ok",false),built.get("reason")):return finish()
	rt=built.runtime;owners.assign(built.services.keys());owners.sort()
	if not check("exact twelve shipping owners are registered",owners==EXPECTED,owners):return finish()
	for owner:String in EXPECTED:check("public owner identity "+owner,rt.domain_service(owner)==built.services[owner])
	for owner:String in ADVANCE:check("actual STEP owner exists "+owner,built.services[owner].has_method("advance"))
	check("zones are passive plans not another simulation clock",not ADVANCE.has("zones"))
	var authority_before:Dictionary=rt.capture_checkpoint()
	var observer:=PerformanceView.new();root.add_child(observer);observer.set_process(false);observer.runtime=rt
	var observed:Dictionary=observer._scene();observer.free()
	check("performance scene records current exact factory generation lock",Data.json_equal(observed.factory_generation_configuration,rt.world.extension("generation:factory-r34")))
	check("performance scene retains original legacy generation field",observed.has("generation_configuration"))
	check("performance provenance query cannot change actual authority",Data.json_equal(authority_before,rt.capture_checkpoint()))
	var before:Dictionary=rt.capture_checkpoint();var time:float=rt.clock();rt.tick(.1)
	check("one real fixed STEP advances original clock once",is_equal_approx(rt.clock()-time,.1),rt.clock()-time)
	check("all original resident identities remain",rt.facts().actors.map(func(a:Dictionary)->String:return a.id)==before.facts.actors.map(func(a:Dictionary)->String:return a.id))
	check("actual regional crop seed and reusable bucket remain finite",rt.actor("player").pack.get("r34:potato_seed",0)==before.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player")[0].pack.get("r34:potato_seed",0) and rt.actor("player").pack.get("r34:water_bucket",0)==before.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player")[0].pack.get("r34:water_bucket",0))
	check("read-only input bytes remain identical",FileAccess.get_file_as_string(args[1]).sha256_text()==input_hash)
	details={"owner_names":owners,"advance_order":ADVANCE,"actor_count":rt.facts().actors.size(),"input_sha256":input_hash,"input_path":args[1],"content":rt.capture_checkpoint().content,"assembly_costs_usec":built.get("assembly_costs_usec",{}),"scope":"shipping twelve-owner full Native assembly plus single normal STEP (original residents may naturally walk); no normal production/NPC journey, observer, renderer, GPU, OS or performance acceptance"}
	finish()
func finish()->void:
	var ok:bool=checks.all(func(row:Dictionary)->bool:return row.ok)
	var f:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"ok":ok,"checks":checks,"details":details},"\t"));f.close()
	if rt!=null:rt.retire()
	if is_instance_valid(host):host.free()
	print("FULL_NATIVE "+str(checks.filter(func(row:Dictionary)->bool:return row.ok).size())+"/"+str(checks.size()))
	quit(0 if ok else 1)
