extends SceneTree
## Actual C4 normal capture and production input. No source-world edits or grants.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Router=preload("res://scripts/input/input_router.gd")
const Direct=preload("res://scripts/input/direct_interaction.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
class Ground extends Node3D:
	var world:RefCounted
	func pick(a:Vector3,b:Vector3)->Dictionary:return Queries.raycast(world,a,b)
class Probe extends Direct:
	var cursor:=Vector2.ZERO
	func _refresh()->void:_refresh_at(cursor)
class Feedback extends Control:
	var receipts:Array=[]
	var panels:Array=[]
	func report_action(value:Dictionary)->void:receipts.append(value)
	func notify(_message:String,_bad:bool=false)->void:pass
	func open_panel(page:String,id:String="")->void:panels.append({"page":page,"id":id})
var checks:Array=[]
var output:String
var runtime:RefCounted
var host:Node3D
var camera:Camera3D
var router:Node
var direct:Node
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func aim(at:Vector3)->void:
	camera.position=at+Vector3(12,18,14);camera.look_at(at)
	direct.cursor=camera.unproject_position(at);direct._refresh()
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0]
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,800)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("explicit unchanged actual normal capture decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var native:=Native.new();var assembled:Dictionary=native._assemble(decoded.capture);native.free()
	check("original services assemble without fixture floor or material grants",assembled.get("ok",false),assembled.get("reason"))
	if not assembled.get("ok",false):return finish()
	runtime=assembled.runtime
	check("normal C4 scenario and physical story sources retained",runtime.snapshot().opening_profile=="normal" and runtime.world.extension("generation:factory-r34").content_version==4 and runtime.world.extension("generation:factory-r34").story_clue_version==1)
	host=Node3D.new();root.add_child(host)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true;host.add_child(camera)
	var ground:=Ground.new();ground.world=runtime.world;host.add_child(ground)
	var feedback:=Feedback.new();host.add_child(feedback)
	router=Router.new();router.controls_path=output+"/controls.json";host.add_child(router);router.configure(runtime);router.set_physics_process(false)
	direct=Probe.new();host.add_child(direct)
	direct.configure({"runtime":runtime,"world":runtime.world,"router":router,"camera":camera,"buildings":runtime._services.buildings,"modules":runtime._services.modules,"terrain":ground,"ui":feedback});direct.set_process(false)
	await process_frame
	var before:Dictionary=runtime.capture_checkpoint();var state:Dictionary=router.state()
	check("unknown stock cannot disclose a movable structure association",not runtime.movable_facility("unknown:stock").get("available",false))
	check("actual player pack cannot masquerade as a movable cabinet",not runtime.movable_facility("pack:player").get("available",false) and Data.json_equal(before,runtime.capture_checkpoint()))
	check("unknown facility is rejected without mode or hand changes",not router.begin_facility_placement("unknown").ok and Data.json_equal(state,router.state()))
	check("legacy walls and complete modules cannot enter movable facility placement",not router.begin_facility_placement("wall_wood").ok and not router.begin_facility_placement("r34.module.warehouse").ok and Data.json_equal(state,router.state()))
	check("cabinet selects only transient production input state",router.begin_facility_placement("cabinet").ok and router.state().mode=="facility_place" and router.state().facility_definition_id=="cabinet")
	check("preview entry preserves all nine hotbar references and selection",router.state().slots==state.slots and router.state().selected==state.selected and not FileAccess.file_exists(router.controls_path))
	var p:Dictionary=runtime.actor("player");var x:float=snappedf(float(p.x)+1.0,1);var z:float=snappedf(float(p.z)+1.0,1)
	var y:Variant=runtime.world.surface_height(x,z)
	check("actual C4 player-adjacent terrain has measured support",y!=null)
	if y==null:return finish()
	aim(Vector3(x,float(y),z))
	check("real terrain ray produces original structure payload and hammer identity",direct._preview.get("kind")=="place" and direct._preview.get("instance",{}).get("definitionId")=="cabinet" and runtime.tool(str(direct._preview.get("tool_id",""))).get("kind")=="hammer",direct._preview)
	check("facility follows ground hit and explicit outdoor identity",direct._preview.instance.position.x==x and direct._preview.instance.position.z==z and direct._preview.instance.position.y==y and direct._preview.instance.buildingId==null and direct._preview.instance.storeyId==null)
	var first:Dictionary=direct._preview.instance.duplicate(true)
	router.rotate_requested.emit()
	check("original rotate input changes cabinet quarter turn without paying",direct._preview.instance.quarterTurn==posmod(int(first.quarterTurn)+1,4) and Data.json_equal(before,runtime.capture_checkpoint()))
	router.primary_requested.emit(true);router.primary_requested.emit(false);router.interact_requested.emit()
	var fixed: Dictionary = direct._preview.instance.position.duplicate(true)
	aim(Vector3(x + 2.0, float(y), z))
	check("facility follows the fixed coordinate after moving the cursor", direct._placement_locked() and direct._preview.instance.position == fixed, direct._target)
	check("preview mouse primary and E cannot mine harvest or open a target",Data.json_equal(before,runtime.capture_checkpoint()) and feedback.receipts.is_empty())
	# Reproduce a stale sampled height without mutating the archived world.
	direct._fixed_structure_location.y = float(fixed.y) + 0.5
	router.confirm_placement()
	check("invalidated fixed height keeps the lock and cannot retarget on confirm", direct._placement_locked() and direct._preview.is_empty() and feedback.receipts.is_empty() and Data.json_equal(before, runtime.capture_checkpoint()), direct._target)
	router.secondary_requested.emit()
	check("right click retracts the fixed facility without a command", not direct._placement_locked() and feedback.receipts.is_empty() and Data.json_equal(before, runtime.capture_checkpoint()))
	aim(Vector3(x, float(y), z))
	router.primary_requested.emit(true);router.primary_requested.emit(false)
	router.cancel()
	check("first Escape retracts a fixed facility and preserves placement mode", not direct._placement_locked() and router.mode() == "facility_place" and Data.json_equal(before, runtime.capture_checkpoint()))
	router.cancel()
	check("second Escape clears transient preview and restores prior hand",router.state().mode=="tool" and router.state().facility_definition_id.is_empty() and router.state().slots==state.slots and router.state().selected==state.selected and not direct._ghost.visible)
	check("cancelled preview cannot persist recipe into controls or authority",not FileAccess.file_exists(router.controls_path) and Data.json_equal(before,runtime.capture_checkpoint()))
	router.begin_facility_placement("cabinet");router.select_slot(int(state.selected))
	check("explicit hotbar selection exits facility placement",router.state().mode=="tool" and router.state().facility_definition_id.is_empty() and router.state().slots==state.slots)
	router.begin_facility_placement("cabinet");router.set_mode("repair")
	check("another work mode clears transient facility without changing inventory",router.state().facility_definition_id.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	# Actual module planning used to leak through to the terrain primary target.
	# Keep the real ray/space preview, and prove both click and held-repeat are inert.
	router.set_mode("tool");feedback.receipts.clear();feedback.panels.clear()
	check("known complete module begins in original shared input router",router.begin_module_placement("r34.module.warehouse").ok and router.state().mode=="module_place")
	aim(Vector3(x,float(y),z))
	check("module planning produces actual current-space placement request",direct._preview.get("payload",{}).get("definition_id")=="r34.module.warehouse" and not direct._preview.get("module_id","").is_empty())
	var preview:Dictionary=direct._preview.duplicate(true);var module_before:Dictionary=runtime.capture_checkpoint()
	router.primary_requested.emit(true);direct._process(0.2);router.interact_requested.emit()
	check("module preview left click held repeat and E never invoke terrain or object actions",feedback.receipts.is_empty() and feedback.panels.is_empty() and Data.json_equal(module_before,runtime.capture_checkpoint()),feedback.receipts.duplicate(true))
	check("planning cannot retain a terrain harvest or attack hold",not direct._holding_primary and direct._held_kind.is_empty(),{"held":direct._holding_primary,"kind":direct._held_kind})
	router.primary_requested.emit(false);router.rotate_requested.emit()
	check("module rotation still uses original placement payload without payment",direct._preview.payload.quarter_turn==posmod(int(preview.payload.quarter_turn)+1,4) and Data.json_equal(module_before,runtime.capture_checkpoint()))
	var receipt_count: int = feedback.receipts.size()
	router.secondary_requested.emit()
	check("module right click retracts without attempting a command", feedback.receipts.size() == receipt_count and not direct._placement_locked() and Data.json_equal(module_before, runtime.capture_checkpoint()))
	router.primary_requested.emit(true);router.primary_requested.emit(false)
	router.confirm_placement()
	check("module confirm obtains one authoritative receipt for the fixed candidate", feedback.receipts.size() == receipt_count + 1, feedback.receipts)
	if router.mode() == "module_place":
		router.cancel()
		if router.mode() == "module_place": router.cancel()
	check("module exits to tool mode and removes world placement hint",router.state().mode=="tool" and direct.view_hints().placement.is_empty() and not direct._ghost.visible)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"C4 normal real source + facility/module input preview, primary/E isolation, rotate, retract and confirmation boundary; not actual paid build/move, OS, VA or performance"},"\t",true,true))
	if is_instance_valid(host):host.queue_free();await process_frame
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
