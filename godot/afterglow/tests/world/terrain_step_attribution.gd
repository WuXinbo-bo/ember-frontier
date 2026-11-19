extends SceneTree
## Read-only costs on the actual two saved Runtime inputs; no STEP, gifts or scene.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Before=preload("res://tests/world/fixtures/terrain_before_step.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error(label)
func run()->void:
	var args:=OS.get_cmdline_user_args()
	for path:String in [args[1],args[2]]:
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
		var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
		check("actual saved input assembles "+path,built.get("ok",false))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var old:=Before.new();old.context=built.services.terrain.context
		var initial:PackedByteArray=var_to_bytes(rt.capture_checkpoint())
		var costs:Dictionary={};var sample:Array=[];var expected:Dictionary=old.advance(0.1)
		for i:int in 128:
			var t:int=Time.get_ticks_usec();var result:Dictionary=old.advance(0.1)
			var old_cost:int=Time.get_ticks_usec()-t
			t=Time.get_ticks_usec();var tx:=Draft.new(old.context);var draft_cost:int=Time.get_ticks_usec()-t
			t=Time.get_ticks_usec();tx.result();var result_cost:int=Time.get_ticks_usec()-t
			t=Time.get_ticks_usec();rt.facts();var facts_cost:int=Time.get_ticks_usec()-t
			t=Time.get_ticks_usec();var actors:Array=rt.actor_states();var actors_cost:int=Time.get_ticks_usec()-t
			sample.append({"old_advance":old_cost,"draft_init":draft_cost,"draft_result":result_cost,"facts":facts_cost,"actor_states":actors_cost})
			check("read only same preparation "+str(rows.size())+":"+str(i),result==expected)
		for key:String in sample[0]:
			var values:Array=sample.map(func(x:Dictionary)->int:return x[key]);values.sort()
			var total:int=0
			for v:int in values:total+=v
			costs[key]={"count":values.size(),"total_usec":total,"median_usec":(values[63]+values[64])/2.0,"max_usec":values[-1]}
		rows.append({"input":path,"input_sha256":FileAccess.get_sha256(path),"actors":rt.actor_states().size(),"stocks":rt.facts().stocks.size(),"costs":costs,"samples":sample,"plan":expected})
		check("cost probes never change authoritative checkpoint",var_to_bytes(rt.capture_checkpoint())==initial)
		rt.retire()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"same saved state repeated read-only C attribution, background CPU only"},"\t",true,true))
	print("terrain attribution ",checks.size(),"/",failed);quit(1 if failed else 0)
