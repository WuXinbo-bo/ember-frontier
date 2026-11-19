extends SceneTree
## Actual Viewport -> Router -> DirectInteraction -> Camera/Terrain ray -> UI.
## Source-level native event support, not physical OS/GPU or normal economy QA.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const InputRouter=preload("res://scripts/input/input_router.gd")
const Interaction=preload("res://scripts/input/direct_interaction.gd")
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const Mount=preload("res://scripts/ui/ui_mount.gd")
const Data=preload("res://scripts/world/world_data.gd")
class TestHost extends Native:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class TestRouter extends InputRouter:
	func _persist_bindings()->bool:return true
var output:String
var checks:Array=[]
var host:Node3D
var ui:Control
var router:Node
var primary_count:int=0
func _initialize()->void:
	create_timer(40).timeout.connect(func():check("bounded pointer workflow completes",false);finish())
	call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func idle()->void:
	await process_frame;await process_frame
func send(position:Vector2,down:bool)->void:
	var event:=InputEventMouseButton.new();event.position=position;event.global_position=position
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event,true);await idle()
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	check("actual current new-world opening prepares",opening.get("ok",false),opening.get("reason"))
	if not opening.get("ok",false):return finish()
	host=TestHost.new();root.add_child(host)
	var built:Dictionary=host._assemble(opening.capture)
	check("actual Native assembly attaches real domains",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime;var world:RefCounted=built.world;var actor:Dictionary=rt.actor("player")
	var patch:Dictionary={};var size:float=world.config().cellSize
	for dz:int in [-16,-8,0,8,16,24]:
		for dx:int in [-16,-8,0,8,16,24]:
			var x:int=floori(actor.x/size)+dx;var z:int=floori(actor.z/size)+dz
			var spec:Dictionary={"kind":"farm","region_id":actor.regionId,"bounds":{"x0":x,"z0":z,"x1":x+3,"z1":z+3},"policy":{"crop_id":"potato"}}
			var result:Dictionary=rt.zone_preview(spec)
			if result.get("ok",false) and result.cells.size()==9:patch={"spec":spec,"cells":result.cells};break
		if not patch.is_empty():break
	check("real known supported terrain supplies a complete patch",not patch.is_empty())
	if patch.is_empty():return finish()
	router=TestRouter.new();router.controls_path=output.path_join("isolated-controls.json");host.add_child(router);router.configure(rt)
	router.set_process(false);router.primary_requested.connect(func(_down:bool):primary_count+=1)
	ui=Mount.mount(host,rt,router);await idle();await idle()
	var terrain:=Terrain.new();terrain.world=world;host.add_child(terrain);terrain.set_process(false)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;host.add_child(camera)
	var first:Dictionary=patch.cells[0];var last:Dictionary=patch.cells[-1]
	var p:=Vector3((first.x+.5)*size,first.y*size,(first.z+.5)*size)
	var q:=Vector3((last.x+.5)*size,last.y*size,(last.z+.5)*size)
	var focus:Vector3=(p+q)*.5
	camera.position=focus+Vector3(16,22,20);camera.look_at(focus);camera.make_current()
	var interaction:=Interaction.new();host.add_child(interaction);interaction.set_process(false)
	interaction.configure({"runtime":rt,"world":world,"router":router,"camera":camera,"buildings":built.services.buildings,"modules":built.services.modules,"terrain":terrain,"ui":ui})
	ui.open_panel("zone_planning");ui.zone_planning.kind="farm";ui.zone_planning.policy={"crop_id":"potato"};ui.queue_refresh();await idle();await idle()
	var before:Dictionary=rt.capture_checkpoint()
	var start:Vector2=camera.unproject_position(p);var end:Vector2=camera.unproject_position(q)
	# A projected ground point can be hidden by a nearer half-metre terrace.
	# The expected selection is the actual first visible terrain, never a
	# request to select through a hill merely because its centre was projected.
	var ray_a:Vector3=camera.project_ray_origin(start);var ray_b:Vector3=camera.project_ray_origin(end)
	var visible_a:Dictionary=terrain.pick(ray_a,ray_a+camera.project_ray_normal(start)*160.0)
	var visible_b:Dictionary=terrain.pick(ray_b,ray_b+camera.project_ray_normal(end)*160.0)
	check("normal orthographic camera resolves known visible ground",visible_a.has("cell") and visible_b.has("cell") and not visible_a.get("unknown",false) and not visible_b.get("unknown",false))
	if not visible_a.has("cell") or not visible_b.has("cell"):return finish()
	var bounds:Dictionary={"x0":mini(visible_a.cell.x,visible_b.cell.x),"z0":mini(visible_a.cell.z,visible_b.cell.z),"x1":maxi(visible_a.cell.x,visible_b.cell.x)+1,"z1":maxi(visible_a.cell.z,visible_b.cell.z)+1}
	var motion:=InputEventMouseMotion.new();motion.position=start;motion.global_position=start;root.push_input(motion,true);await idle()
	await send(start,true)
	check("real Viewport press reaches camera and terrain planner",ui.zone_planning.drawing,{"screen":str(start),"receipt":ui.zone_planning.receipt})
	motion=InputEventMouseMotion.new();motion.position=end;motion.global_position=end;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true);await idle()
	await send(end,false);await create_timer(.12).timeout;await idle()
	check("real ray drag resolves exact authoritative cell bounds",ui.zone_planning.bounds==bounds,{"expected_visible_bounds":bounds,"projected_patch":patch.spec.bounds,"actual":ui.zone_planning.bounds,"preview":ui.zone_planning.preview})
	await send(start,true)
	root.push_input(motion,true);await idle()
	ui.zone_planning.finish_pointer(ui,{})
	await create_timer(.12).timeout;await idle()
	check("release without terrain keeps the last known endpoint and gets a fresh preview",not ui.zone_planning.drawing and ui.zone_planning.bounds==bounds and ui.zone_planning._spec.bounds==bounds,ui.zone_planning.preview)
	check("planning click/release never leaks ordinary tool activation",primary_count==0 and Data.json_equal(before,rt.capture_checkpoint()),primary_count)
	check("planning remains scene-side and does not pause simulation policy",ui.is_zone_planning() and not router.state().pause_reasons.modal)
	router.set_window_focus(false)
	await send(start,true)
	check("unfocused native router cannot start a new draft",not ui.zone_planning.drawing)
	check("pointer support never commits plans or resource changes",Data.json_equal(before,rt.capture_checkpoint()))
	finish()
func finish()->void:
	var failures:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failures,"scope":"Real Viewport/Router/Camera/Terrain/UI source seam; no physical OS/GPU, package, natural economy or FPS qualification"},"\t"));file.close()
	if is_instance_valid(host):host.free()
	print("ZONE_POINTER "+str(checks.size()-failures)+"/"+str(checks.size()))
	quit(0 if failures==0 else 1)
