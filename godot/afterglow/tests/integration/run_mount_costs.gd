extends SceneTree
## Actual Native assembly/staging CPU attribution; no readiness or FPS claim.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
class DiagnosticClient extends Native:
	func _ready()->void:pass
var checks:Array=[]
var monitoring:bool=false
var close_fixture:bool=false
var callbacks:int=0
var last_callback:int=0
var max_callback_gap:int=0
var host:Node3D
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:checks.append({"name":label,"ok":ok})
func pulse()->void:
	if not monitoring:return
	var now:int=Time.get_ticks_usec();max_callback_gap=maxi(max_callback_gap,now-last_callback);last_callback=now;callbacks+=1
	if close_fixture and callbacks==2:host._closing=true
func begin_monitor()->void:
	callbacks=0;max_callback_gap=0;last_callback=Time.get_ticks_usec();monitoring=true
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var output:String=args[0];var input:String=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var digest:String=FileAccess.get_sha256(input)
	var started:int=Time.get_ticks_usec()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	var decode_usec:int=Time.get_ticks_usec()-started
	check("exact explicit normal source decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):quit(1);return
	host=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	started=Time.get_ticks_usec()
	var built:Dictionary=host._assemble(decoded.capture)
	var assembly_usec:int=Time.get_ticks_usec()-started
	check("shipping Native services fully assemble",built.get("ok",false))
	if not built.get("ok",false):host.free();quit(1);return
	var before:Dictionary=built.runtime.capture_checkpoint()
	process_frame.connect(pulse)
	started=Time.get_ticks_usec();begin_monitor()
	var asynchronous:Dictionary=await host._assemble_async(decoded.capture)
	var async_usec:int=Time.get_ticks_usec()-started
	await process_frame;monitoring=false
	var async_callbacks:int=callbacks;var async_maxgap:int=max_callback_gap
	check("yielding assembly preserves exact sync candidate checkpoint and revisions",asynchronous.get("ok",false) and Data.json_equal(before,asynchronous.runtime.capture_checkpoint()))
	check("real dependency restore yields callbacks without publishing a second world",async_callbacks>2 and host.world==null and host.runtime==null)
	if asynchronous.get("ok",false):asynchronous.runtime.retire()
	close_fixture=true;begin_monitor()
	var cancelled:Dictionary=await host._assemble_async(decoded.capture)
	await process_frame;monitoring=false;close_fixture=false;host._closing=false
	check("explicit closing during candidate dependency batches cancels publication",not cancelled.get("ok",false) and cancelled.get("code")=="WORLD_SWITCH_CANCELLED" and host.world==null and host.runtime==null)
	check("cancelled candidate leaves previous complete assembly exact",Data.json_equal(before,built.runtime.capture_checkpoint()))
	started=Time.get_ticks_usec()
	var candidate:Dictionary=host._stage_scene(built)
	var stage_usec:int=Time.get_ticks_usec()-started
	check("actual unpromoted terrain building module actor and camera views stage",candidate.get("ok",false))
	check("staged candidate stays invisible and unpublished",not candidate.root.visible and host.runtime==null and host.world==null)
	check("staging never ticks or changes any complete checkpoint fact",Data.json_equal(before,built.runtime.capture_checkpoint()))
	var phases:Dictionary={"decode_usec":decode_usec,"assembly_usec":assembly_usec,"async_assembly_wall_usec":async_usec,"async_callbacks":async_callbacks,"async_max_callback_gap_usec":async_maxgap,"async_assembly_costs":asynchronous.get("assembly_costs_usec",{}),"stage_usec":stage_usec,"assembly":built.assembly_costs_usec,"scene":candidate.scene_costs_usec}
	check("assembly phases cover elapsed CPU scope without claiming hard budget",built.assembly_costs_usec.values().reduce(func(total:int,v:int)->int:return total+v,0)<=assembly_usec)
	check("scene phases cover elapsed CPU scope without claiming renderer work",candidate.scene_costs_usec.values().reduce(func(total:int,v:int)->int:return total+v,0)<=stage_usec)
	check("original external save remains byte-identical",FileAccess.get_sha256(input)==digest)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"scope":"Actual supplied source/Native service assembly and unpromoted views, headless CPU only. No process_frame terrain completion, physics readiness, activation, OS/GPU/FPS or final qualification.","input":{"path":input,"sha256":digest},"regions":built.world.regions().size(),"chunks":built.world.chunk_keys().size(),"checks":checks,"failed":failed,"phases":phases}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	candidate.terrain.cancel_pending();candidate.root.free();built.runtime.retire();host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"phases":phases}));quit(1 if failed else 0)
