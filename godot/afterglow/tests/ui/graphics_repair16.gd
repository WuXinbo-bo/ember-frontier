extends SceneTree
## Root-only packaged graphics acceptance. Original Native restore/mount/clock;
## no position, goods, work or camera injection. Does not qualify frame time.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const FactoryView=preload("res://scripts/presentation/factory_view.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
class LiveClient extends Native:
	func _ready()->void:pass
var output:String
var input_path:String
var input_bytes:String
var host:Node3D
var checks:Array=[]
var samples:Array=[]
var shots:Array=[]
var finishing:=false
var module_id:="r34:generated:RH-HOME:village-warehouse"
func _initialize()->void:
	create_timer(210).timeout.connect(func():check("bounded graphics workflow completes",false);finish())
	call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var path:String=output+"/"+name+".png"
	var saved:int=root.get_texture().get_image().save_png(path)
	shots.append({"name":name,"path":path,"error":saved,"clock":host.runtime.clock() if host!=null and host.runtime!=null else 0})
	check("normal camera screenshot "+name,saved==OK)
func row()->Dictionary:
	return F.instance(host.runtime.factory_page_snapshot("player","factory_module",module_id),module_id)
func condition()->Dictionary:
	for node:Node in host.scene_root.get_children():
		if node.get_script()==FactoryView:
			for item:Dictionary in node.statistics().conditions:
				if item.module_id==module_id:return item.condition
	return {}
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:print("Usage: <output-directory> <partial-native-checkpoint> [--graphics]");quit(2);return
	output=args[0];input_path=args[1];DirAccess.make_dir_recursive_absolute(output)
	check("explicit graphics mode with real renderer",args.has("--graphics") and DisplayServer.get_name()!="headless")
	if DisplayServer.get_name()=="headless":return finish()
	check("occupied-code minimal translation",P.reason_text("MODULE_LIVE_ACTOR_OCCUPIED")=="施工范围有人，请先让人离开")
	check("specific owner occupied explanation is preserved",P.feedback_text({"code":"MODULE_LIVE_ACTOR_OCCUPIED","reason":"有人站在建筑施工范围内，请先让开"})=="有人站在建筑施工范围内，请先让开")
	input_bytes=FileAccess.get_file_as_string(input_path)
	var decoded:Dictionary=Store.decode(input_bytes)
	check("original partial checkpoint decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=LiveClient.new();host.controls_path=output+"/controls.json";host.store=Store.new(output+"/isolated-saves");root.add_child(host)
	var started:Dictionary=host.store.begin_save(decoded.capture,true,input_bytes)
	check("original capture stages through native store",started.get("ok",false),started)
	if not started.get("ok",false):return finish()
	var saved:Dictionary={};var save_begin:int=Time.get_ticks_msec()
	while saved.is_empty() and Time.get_ticks_msec()-save_begin<20000:
		saved=host.store.poll()
		if saved.is_empty():await process_frame
	check("isolated native copy committed",saved.get("ok",false),saved)
	if not saved.get("ok",false):return finish()
	var restored:Dictionary=await host.restore_saved_world("graphics-repair16-restore")
	check("shipping restore mounts full validated scene",restored.get("ok",false) and host._ready_game and host.camera!=null,restored)
	if not restored.get("ok",false):return finish()
	check("normal shipping orthographic camera remains",host.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(host.camera.size,24.0))
	var first:Dictionary=row();var first_work:Dictionary=first.get("visuals",{}).get("construction",{})
	check("restored original project is partially worked",float(first_work.get("progress_seconds",0))>0 and float(first_work.get("progress_seconds",0))<float(first_work.get("duration_seconds",0)),first_work)
	await shot("construction-start-normal-camera")
	var middle:=false;var late:=false;var completed:=false;var last_poll:int=0;var began:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<90000:
		await process_frame
		if Time.get_ticks_msec()-last_poll<200:continue
		last_poll=Time.get_ticks_msec()
		var module:Dictionary=row();var work:Dictionary=module.get("visuals",{}).get("construction",{})
		var visual:Dictionary=condition()
		if samples.size()<500:samples.append({"clock":host.runtime.clock(),"status":module.get("status"),"work":work,"visual":visual,"player":host.runtime.actor("player")})
		var settled:bool=work.is_empty() or (work.get("phase")=="completed" and not work.get("active",true) and is_equal_approx(float(work.get("progress_seconds",0)),float(work.get("duration_seconds",0))))
		if module.get("status")=="operational" and settled:
			completed=true;await shot("construction-complete-normal-camera");break
		var duration:float=float(work.get("duration_seconds",0));var ratio:float=float(work.get("progress_seconds",0))/duration if duration>0 else 0
		if not middle and ratio>=0.34:
			middle=true;check("real middle progress mounts stage two",int(visual.get("construction_stage",0))>=2,visual);await shot("construction-middle-normal-camera")
		if not late and ratio>=0.68:
			late=true;check("real late progress mounts stage three",int(visual.get("construction_stage",0))==3,visual);await shot("construction-late-normal-camera")
	check("real Native frame clock completes original partial repair",completed,{"last_module":row(),"readiness":host.runtime.spatial_readiness(),"budget":host.runtime.simulation_budget()})
	if completed:
		await process_frame;await process_frame
		var done:Dictionary=condition()
		check("finished scene clears temporary staging and labor",not done.get("staging_visible",false) and not done.get("construction_active",false),done)
	else:await shot("construction-real-blocker-normal-camera")
	check("both intermediate stages were observed",middle and late)
	check("original partial input remains byte identical",FileAccess.get_file_as_string(input_path)==input_bytes)
	finish()
func finish()->void:
	if finishing:return
	finishing=true
	if is_instance_valid(host) and host.runtime!=null:
		host.runtime.set_paused(true);host.set_process(false)
		var drain_started:int=Time.get_ticks_usec()
		while host._streaming and Time.get_ticks_usec()-drain_started<65000000:await process_frame
		check("isolated repair client drains admitted residency before teardown",not host._streaming)
	var failed:int=checks.filter(func(item:Dictionary):return not item.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"screenshots":shots,"samples":samples,"scope":"root-run real Native full-scene restore and natural frame-clock construction; normal shipping camera unchanged; no injection, OS input, export or frame-time qualification; screenshot quality requires human review"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print("GRAPHICS_REPAIR16 "+JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
