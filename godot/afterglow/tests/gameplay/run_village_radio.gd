extends SceneTree
## Integration: only late-game prerequisites and starting material/position are
## explicit fixtures. All radio work, holds, cancel, CAS and cold resume are real.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Village=preload("res://scripts/runtime/village_progression.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
var host:Node
var runtime:RefCounted
var sequence:int=0
var output:String=""

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+": "+str(detail))
func send(kind:String,target:String="",payload:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"village-radio:test:"+str(sequence),"actor_id":"player","kind":kind,"target_id":target,"payload":payload})
func step(count:int)->void:
	for i:int in count:runtime.tick(.1)
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0] if not args.is_empty() else "user://village-radio-test"
	DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles(13)
	check("actual content13 profiles",profiles.get("ok",false),profiles.get("reason"))
	if not profiles.get("ok",false):finish();return
	var initial:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,13))
	check("actual generated village opening",initial.get("ok",false),initial.get("reason"))
	if not initial.get("ok",false):finish();return
	host=Native.new();var built:Dictionary=host._assemble(initial.capture)
	check("actual runtime assembly",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):finish();return
	runtime=built.runtime
	var station:String=Village.radio_station(runtime.world)
	check("radio binds generated real manual workbench",not station.is_empty(),station)
	if station.is_empty():finish();return
	var bench:Dictionary=runtime._services.buildings.instance(station)
	var positions:Array=runtime._services.buildings.current_space().use_points(bench)
	check("real workbench has standing approach",not positions.is_empty())
	if positions.is_empty():finish();return
	var tx:=Draft.new(runtime._services.production.context)
	var actor:Dictionary=tx.actor("player");actor.merge(positions[0],true);actor.intent=null
	actor.pack["scrap"]=8;actor.pack["tool_handle"]=1
	var production:Dictionary=tx.extension("r3:production");production.knowledge.player=["basic_tool_repair"]
	var hammer:String=""
	for tool:Dictionary in production.tools:
		if tool.get("kind")=="hammer":hammer=str(tool.id);tool.holderId="pack:player";break
	var village:Dictionary=tx.extension("r34:gameplay");village.flags.village_warehouse_restored=true;village.flags.real_machine_output=true
	var fixture:Dictionary=runtime._commit(tx.result())
	check("explicit isolated late-game prerequisites commit through real authority",fixture.get("ok",false),fixture.get("reason"))
	if not fixture.get("ok",false) or hammer.is_empty():finish();return
	var before_hammer:float=float(runtime.tool(hammer).durability)
	var repair:Dictionary=send("radio",station,{"operation":"repair","tool_id":hammer})
	check("real repair begins at workbench",repair.get("ok",false),repair)
	if not repair.get("ok",false):finish();return
	step(10)
	check("partial repair retains material and progress",runtime.actor("player").pack.get("scrap")==8 and runtime.actor("player").intent!=null and float(runtime.actor("player").intent.get("elapsed",0))>0)
	var cancelled:Dictionary=send("cancel")
	check("real cancellation releases work without material charge",cancelled.get("ok",false) and runtime.actor("player").intent==null and runtime.actor("player").pack.get("scrap")==8,cancelled)
	repair=send("radio",station,{"operation":"repair","tool_id":hammer});step(10)
	var captured:Dictionary=runtime.capture_checkpoint();var elapsed:float=float(runtime.actor("player").intent.get("elapsed",0))
	var cold:Dictionary=host._assemble(captured)
	check("cold checkpoint restores actual radio work",cold.get("ok",false),cold.get("reason"))
	if not cold.get("ok",false):finish();return
	runtime.retire();runtime=cold.runtime
	check("cold resume preserves fractional labor and reserves original materials",runtime.actor("player").intent!=null and is_equal_approx(float(runtime.actor("player").intent.elapsed),elapsed) and runtime.actor("player").pack.scrap==8)
	for i:int in 260:
		if runtime.actor("player").intent==null:break
		runtime.tick(.1)
	var radio_state:Dictionary=runtime.world.extension("r33:gameplay").radio
	check("twenty effective repair seconds finish actual radio",radio_state.status=="repaired" and runtime.actor("player").intent==null,radio_state)
	check("repair consumes exact eight scrap one handle once and two hammer wear",runtime.actor("player").pack.get("scrap",0)==0 and runtime.actor("player").pack.get("tool_handle",0)==0 and is_equal_approx(float(runtime.tool(hammer).durability),before_hammer-2))
	var duplicate:Dictionary=send("radio",station,{"operation":"repair","tool_id":hammer})
	check("completed repair cannot be charged twice",not duplicate.get("ok",false) and duplicate.get("code")=="RADIO_READY",duplicate)
	var transmitted:Dictionary=send("radio",station,{"operation":"transmit"})
	check("real transmission starts",transmitted.get("ok",false),transmitted)
	if not transmitted.get("ok",false):finish();return
	for i:int in 360:
		if runtime.actor("player").intent==null:break
		runtime.tick(.1)
	radio_state=runtime.world.extension("r33:gameplay").radio
	check("thirty effective labor seconds connect radio",radio_state.status=="connected" and is_equal_approx(float(radio_state.signal),30.0),radio_state)
	step(2)
	check("connected radio advances real village quest",runtime.world.extension("r34:gameplay").flags.get("village_radio_connected",false))
	finish()

func finish()->void:
	var result:Dictionary={"scope":"actual generated content13 world/runtime/commands and cold checkpoint; explicit late-game prerequisite fixture, not natural full journey or visual acceptance","ok":checks.all(func(row:Dictionary)->bool:return row.ok),"checks":checks}
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	if runtime!=null:runtime.retire()
	if is_instance_valid(host):host.free()
	quit(0 if result.ok else 1)
