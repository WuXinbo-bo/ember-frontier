extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Opening=preload("res://scripts/runtime/playtest_profile.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Router=preload("res://scripts/input/input_router.gd")
const Direct=preload("res://scripts/input/direct_interaction.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
class TestRouter extends Router:
	func _persist_bindings()->bool:return true
class Ground extends Node3D:
	var world:RefCounted
	func pick(a:Vector3,b:Vector3)->Dictionary:return Queries.raycast(world,a,b)
class Feedback extends Control:
	var error:Dictionary={}
	func report_action(value:Dictionary)->void:error=value if not value.ok else {}
	func notify(_message:String,_bad:bool=false)->void:pass
	func is_zone_planning()->bool:return false

var failed:=0
var count:=0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	count+=1
	if not ok:
		failed+=1
		printerr("FAIL "+label)

func run()->void:
	root.size=Vector2i(1280,800)
	var prepared:=Assembly.prepare(Assembly.generate(713,Assembly.generation_profiles(21).profiles,21))
	var host:=Client.new()
	var built:Dictionary=host._assemble(Opening.prepare_opening(prepared.capture,"normal"))
	host.free()
	check("normal opening assembles",built.get("ok",false))
	if not built.get("ok",false):quit(1);return
	var rt:RefCounted=built.runtime
	var world:RefCounted=built.world
	var input:=TestRouter.new()
	root.add_child(input);input.configure(rt,true);input.set_physics_process(false);input.set_auto_pickup(true)
	var axe:String=""
	for tool:Dictionary in rt.snapshot().tools:
		if tool.kind=="salvaged_axe" and tool.holderId=="pack:player":axe=str(tool.id);break
	var origin:=Geometry.point(rt.actor("player"))
	var all:Array=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	all.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return origin.distance_squared_to(Geometry.point(a.position))<origin.distance_squared_to(Geometry.point(b.position)))
	var tree:Dictionary={}
	for candidate:Dictionary in all.slice(0,15):
		if not input.request("harvest",str(candidate.id),{"tool_id":axe,"direct":false,"held":true}).ok:continue
		for i:int in 400:
			var intent:Variant=rt.actor("player").get("intent")
			if intent==null:break
			if intent.get("kind")=="harvest":tree=candidate;break
			rt.tick(0.1)
		if not tree.is_empty():break
	check("ordinary player reaches a valid nearby tree",not tree.is_empty())
	if tree.is_empty():rt.retire();quit(1);return
	input.request("cancel")
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=44
	var feet:=Geometry.point(rt.actor("player"))
	camera.position=feet+Vector3(24,29,31);camera.look_at(feet)
	var ground:=Ground.new();ground.world=world;scene.add_child(ground)
	var feedback:=Feedback.new();feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(feedback)
	var interaction:=Direct.new();root.add_child(interaction)
	interaction.configure({"runtime":rt,"world":world,"router":input,"camera":camera,"terrain":ground,"buildings":built.services.buildings,"modules":built.services.modules,"ui":feedback})
	interaction.set_process(false)
	await process_frame
	var mouse:=camera.unproject_position(Geometry.point(tree.position)+Vector3.UP*1.3)
	interaction._press_screen=mouse
	interaction._primary(true);interaction._primary(false)
	var started:Variant=rt.actor("player").intent
	if started==null:print({"point":mouse,"exact":interaction._exact_target,"target":interaction._target,"tree":tree.id,"receipt":feedback.error,"feet":feet,"tree_at":tree.position})
	check("left click and release keeps the exact tree order working",started is Dictionary and started.get("held",false) and started.request.target_id==tree.id)
	var before:float=rt.actor("player").stamina
	rt.tick(0.1)
	check("0.1s of actual player harvest spends 0.08 stamina",absf(before-float(rt.actor("player").stamina)-0.08)<0.00001)
	var toward:=Geometry.point(tree.position)-feet;toward.y=0
	var local:=Geometry.location(rt.actor("player"));local.x-=toward.normalized().x*0.04;local.z-=toward.normalized().z*0.04
	var moved:=input.request("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},local)
	check("small real step inside range keeps the same order",moved.ok and rt.actor("player").get("intent") is Dictionary and rt.actor("player").intent.id==started.get("id"))
	var original_logs:float=rt.actor("player").pack.get("log",0)
	for i:int in 100:
		if rt.actor("player").get("intent")==null:break
		rt.tick(0.1)
	check("real fell event deposits all three logs once",world.entity(str(tree.id)).data.harvest.phase=="stump" and float(rt.actor("player").pack.get("log",0))==original_logs+3 and rt.stock(str(tree.data.outputId)).items.get("log",0)==0)
	camera.size=100
	await process_frame
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_RIGHT;press.pressed=true;press.position=Vector2(10,10)
	var drag:=InputEventMouseMotion.new();drag.position=root.get_visible_rect().end-Vector2(10,10)
	var captured:=interaction._tree_pointer(press)
	var dragged:=interaction._tree_pointer(drag)
	var selected:int=interaction._marked_trees.size()
	if selected<2:print({"captured":captured,"dragged":dragged,"selected":selected,"candidates":interaction._tree_candidates.size(),"viewport":root.get_visible_rect(),"router":input.interaction_state(),"combat":rt.expedition_in_combat()})
	check("right drag marks multiple real standing trees",selected>=2)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_RIGHT;release.position=drag.position
	interaction._input(release)
	check("releasing a dragged rectangle exposes the confirmation button",interaction._tree_confirm.visible)
	# Keep the two closest marked trees for the normal opening carry limit.
	interaction._marked_trees.sort_custom(func(a:String,b:String)->bool:return interaction._tree_distance(a,feet)<interaction._tree_distance(b,feet))
	interaction._marked_trees.resize(mini(2,selected))
	var batch_start:float=rt.actor("player").pack.get("log",0)
	interaction._confirm_tree_batch()
	var reached:int=0
	for i:int in 850:
		rt.tick(0.1);interaction._advance_tree_batch()
		reached=maxi(reached,interaction._tree_batch_done)
		if interaction._tree_queue.is_empty() and interaction._tree_batch_target.is_empty():break
	check("one confirmation chains more than one actual harvest",float(rt.actor("player").pack.get("log",0))>=batch_start+6 or reached>=2)
	interaction.free();rt.retire()
	print(JSON.stringify({"suite":"player-harvest","checks":count,"failed":failed}))
	quit(1 if failed else 0)
