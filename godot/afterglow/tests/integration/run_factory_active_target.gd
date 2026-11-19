extends SceneTree
## Reproduce the actual candidate25 paused-tree save. No gifted tools,
## actor relocation, changed geometry or replacement world state.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Direct=preload("res://scripts/input/direct_interaction.gd")
const Router=preload("res://scripts/input/input_router.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const Data=preload("res://scripts/world/world_data.gd")
class ProbeRouter extends Router:
	func _persist_bindings()->bool:return true
class ProbeDirect extends Direct:
	var cursor:=Vector2.ZERO
	func _refresh()->void:_refresh_at(cursor)
class Ground extends Node3D:
	var world:RefCounted
	func pick(a:Vector3,b:Vector3)->Dictionary:return Queries.raycast(world,a,b)
class Feedback extends Control:
	var receipts:Array=[]
	func report_action(value:Dictionary)->void:receipts.append(value.duplicate(true))
	func notify(_text:String,_bad:bool=false)->void:pass
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1])
	var decoded:Dictionary=Store.decode(original)
	check("original actual25 manual save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):finish();return
	var host:=Client.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("shipping cold assembler accepts actual paused tree",built.get("ok",false),built.get("code"))
	if not built.get("ok",false):finish();return
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world
	var player:Dictionary=runtime.actor("player");var intent:Dictionary=player.get("intent",{})
	var request:Dictionary=intent.get("request",{});var target_id:String=str(request.get("target_id",""))
	var tool_id:String=str(request.get("payload",{}).get("tool_id",""))
	check("actual input owns a paused held harvest order",intent.get("kind")=="harvest" and intent.get("held")==false and request.get("payload",{}).get("requires_hold",false) and runtime.tool(tool_id).get("holderId")=="pack:player",intent)
	var scene:=Node3D.new();var camera:=Camera3D.new();var ground:=Ground.new();var router:=ProbeRouter.new();var direct:=ProbeDirect.new();var feedback:=Feedback.new()
	root.add_child(scene);scene.add_child(camera);scene.add_child(ground);root.add_child(router);root.add_child(feedback);root.add_child(direct)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true;ground.world=world
	var feet:=Geometry.point(player);camera.position=feet+Vector3(24,29,31);camera.look_at(feet+Vector3(0,0.7,0))
	router.configure(runtime);router.set_physics_process(false)
	router.assign_slot(0,{"kind":"tool","id":tool_id});router.select_slot(0)
	direct.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":built.services.buildings,"modules":built.services.modules,"terrain":ground,"ui":feedback});direct.set_process(false)
	await process_frame
	var before:Dictionary=runtime.capture_checkpoint()
	direct.cursor=camera.unproject_position(feet+Vector3(6,0,-6));direct._refresh()
	check("paused own tree remains nearby target when cursor leaves thin trunk",direct._target.get("id")==target_id and direct._target.get("primary")=="harvest" and direct._target.get("enabled",false),direct._target)
	check("paused work feedback identifies resumable action",direct._target.get("active_work",false) and direct._target.get("work_paused",false),direct._target)
	check("target projection does not change canonical world or gameplay",Data.json_equal(before,runtime.capture_checkpoint()))
	direct._primary(true)
	var resumed:Dictionary=runtime.actor("player").get("intent",{})
	check("actual pointer hold resumes the same order without a second harvest",resumed.get("id")==intent.get("id") and resumed.get("order_id")==intent.get("order_id") and resumed.get("held",false),resumed)
	var old_elapsed:=order_elapsed(runtime,str(intent.get("order_id","")))
	runtime.tick(0.1)
	check("resumed original order performs real paid work",order_elapsed(runtime,str(intent.get("order_id","")))>old_elapsed)
	direct._primary(false)
	var paused:Dictionary=runtime.actor("player").get("intent",{})
	check("release pauses same action",paused.get("id")==intent.get("id") and paused.get("held")==false)
	var elapsed:=order_elapsed(runtime,str(intent.get("order_id","")));var wear:float=runtime.tool(tool_id).durability
	for i in 10:runtime.tick(0.1)
	check("released action pays no more labor or durability",is_equal_approx(elapsed,order_elapsed(runtime,str(intent.get("order_id","")))) and is_equal_approx(wear,runtime.tool(tool_id).durability))
	var other_tool:String=""
	for item:Dictionary in runtime.snapshot().tools:
		if item.id!=tool_id and item.holderId=="pack:player":other_tool=str(item.id);break
	check("counterexample uses an existing different owned tool",not other_tool.is_empty())
	if not other_tool.is_empty():
		router.assign_slot(1,{"kind":"tool","id":other_tool});router.select_slot(1)
		var tree:Dictionary=world.entity(target_id);var target:Dictionary=direct._describe(tree)
		check("different selected tool cannot advertise original paused action as resumable",not target.get("active_work",false) and not target.get("enabled",false),target)
	check("original manual save bytes stay unchanged",original==FileAccess.get_file_as_string(args[1]))
	direct.free();router.free();feedback.free();scene.free();finish()
func order_elapsed(runtime:RefCounted,id:String)->float:
	for order:Dictionary in runtime.snapshot().get("orders",[]):
		if order.id==id:return float(order.elapsed)
	return -1.0
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Actual25 paused harvest save, production pointer target, hold/release and real order. Not OS or final package acceptance.","checks":checks,"failed":failed},"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
