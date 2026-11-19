extends "res://tests/buildings/radio_boundary_suite.gd"
## Reuse B's actual built-workbench/20s repair route, not a second simulation.
const View=preload("res://scripts/presentation/gameplay_view.gd")
const ActorView=preload("res://scripts/presentation/actor_view.gd")
const Occlusion=preload("res://scripts/presentation/player_occlusion.gd")
func finish(started:int)->void:
	var stage:=Node3D.new();root.add_child(stage)
	var view:=View.new();stage.add_child(view);view.configure(runtime,building);view._process(0.2)
	expect("real repaired workbench displays imported panel cell one",view.statistics().radio_visible and view.statistics().panel_registered and view.statistics().panel_cell==1,view.statistics())
	# A failed upstream construction/schema route is evidence, not permission
	# to dereference a device that was never assembled and hang the suite.
	if view._radio==null or view._led==null:stage.free();super.finish(started);return
	var begin:=command("radio","bbb:radio-bench",{"operation":"transmit"})
	expect("actual transmission begins at the repaired same station",begin.ok,begin)
	view._process(0.2)
	expect("real transmission selects panel cell two",view.statistics().panel_cell==2,view.statistics())
	var energy:float=view._led.emission_energy_multiplier
	await create_timer(0.025).timeout
	view._process(0.2)
	expect("radio presentation does not advance without logical clock",is_equal_approx(view._led.emission_energy_multiplier,energy))
	for n in 300:runtime.tick(0.1)
	view._process(0.2)
	expect("completed transmission selects connected panel cell three",view.statistics().panel_cell==3 and world.extension(Gameplay.KEY).radio.status=="connected",view.statistics())
	var before:Dictionary=world.extension(Gameplay.KEY)
	var invalid:Dictionary=before.duplicate(true);invalid.radio.station_id="rural:v1:RH-HOME:old-house:yard-gate"
	var draft:Dictionary=world.prepare_changes([building.extension_change(Gameplay.KEY,invalid)],world.get_revision())
	expect("explicit invalid-station fixture commits only in isolated test",draft.ok and world.commit_prepared(draft.capability).ok)
	view._process(0.2)
	expect("a door reference never becomes a visible radio",not view.statistics().radio_visible)
	var actors:=ActorView.new();stage.add_child(actors);actors.configure(runtime)
	var player:Node3D=actors.roots.player
	var camera:=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	var target:=player.global_position+Vector3(0,1.1,0)
	camera.position=target+Vector3(24,29,31);camera.look_at(target)
	var blockers:=Node3D.new();stage.add_child(blockers)
	var obstacle:=MeshInstance3D.new();var cube:=BoxMesh.new();cube.size=Vector3(3,3,3);obstacle.mesh=cube
	blockers.add_child(obstacle);obstacle.position=target+Vector3(24,29,31)*0.1
	var occlusion:=Occlusion.new();stage.add_child(occlusion);occlusion.configure(camera,actors,blockers);occlusion._process(0.2)
	expect("rendered obstacle activates player-only silhouette",occlusion.statistics().player_occluded and actors._player_occluded,occlusion.statistics())
	var meshes:Array=player.find_children("*","MeshInstance3D",true,false)
	expect("animated original meshes reuse covered-pixels-only native overlay",not meshes.is_empty() and meshes.all(func(m:Node)->bool:return m.material_overlay is BaseMaterial3D and not m.material_overlay.no_depth_test and m.material_overlay.depth_test==BaseMaterial3D.DEPTH_TEST_INVERTED and m.material_overlay.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED))
	var friend:Node3D=actors.roots.friend
	expect("same overlay does not reveal other residents",friend.find_children("*","MeshInstance3D",true,false).all(func(m:Node)->bool:return m.material_overlay==null))
	obstacle.visible=false;occlusion._process(0.2)
	expect("hidden cutaway meshes stop occluding and restore original materials",not occlusion.statistics().player_occluded and meshes.all(func(m:Node)->bool:return m.material_overlay==null))
	var replacement:=Runtime.new()
	expect("replacement view authority accepts same explicit facts",replacement.configure({"world":world,"facts":runtime.facts(),"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.configure(replacement,building)
	expect("authority replacement immediately clears stale radio node and ID",view._radio==null and view.statistics().station_id.is_empty() and not view.statistics().radio_visible)
	obstacle.visible=true;occlusion._process(0.2)
	expect("actual obstacle is active before occlusion lifecycle replacement",actors._player_occluded)
	var next_actors:=ActorView.new();stage.add_child(next_actors);next_actors.configure(replacement);next_actors.set_process(false)
	var next_blockers:=Node3D.new();stage.add_child(next_blockers)
	occlusion.configure(camera,next_actors,next_blockers)
	expect("occlusion reconfigure immediately restores retired actor overlays",not actors._player_occluded and meshes.all(func(m:Node)->bool:return m.material_overlay==null))
	expect("occlusion reconfigure immediately clears old blocked statistics and caches",not occlusion.statistics().player_occluded and occlusion._triangles.is_empty() and occlusion._watched.is_empty())
	occlusion._process(0.2)
	expect("replacement actors do not inherit old building occlusion",not next_actors._player_occluded and not occlusion.statistics().player_occluded)
	stage.free()
	super.finish(started)
