extends "res://tests/buildings/domain_suite.gd"
## Real B mesh builder and doorway dimensions. Derived geometry, never OS/VA.
const Occlusion=preload("res://scripts/presentation/player_occlusion.gd")
const Builder=preload("res://scripts/buildings/building_mesh.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var stage:Node3D
var camera:Camera3D
var blockers:Node3D
var occlusion:Node

func run()->void:
	var started:int=Time.get_ticks_msec()
	stage=Node3D.new();root.add_child(stage)
	camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	camera.position=Vector3(0,1.1,10);camera.look_at(Vector3(0,1.1,0))
	blockers=Node3D.new();stage.add_child(blockers)
	occlusion=Occlusion.new();stage.add_child(occlusion)
	# Configure against a plain node; only _covered is called in this matrix.
	occlusion.configure(camera,Node3D.new(),blockers);occlusion.set_process(false)
	var frame:=Builder.new()
	for x:float in [-0.835,0.835]:frame.box(AABB(Vector3(x-0.035,0,-0.135),Vector3(0.07,2.2,0.27)),Transform3D.IDENTITY,"wood")
	frame.box(AABB(Vector3(-0.87,2.2,-0.135),Vector3(1.74,0.07,0.27)),Transform3D.IDENTITY,"wood")
	var doorway:=MeshInstance3D.new();doorway.mesh=frame.mesh({});blockers.add_child(doorway);doorway.position.z=2
	refresh()
	expect("real B three-bar door opening does not erase player skin",not occlusion._covered(Vector3(0,1.1,0)) and not occlusion._covered(Vector3(0,1.65,0)))
	expect("real wooden side post still occludes",occlusion._covered(Vector3(0.835,1.1,0)))
	expect("real wooden header still occludes",occlusion._covered(Vector3(0,2.235,0)))
	doorway.visible=false
	expect("hidden doorway geometry never occludes",not occlusion._covered(Vector3(0.835,1.1,0)))
	doorway.visible=true
	doorway.rotation.y=PI/2;camera.position=Vector3(10,1.1,0);camera.look_at(Vector3(0,1.1,0));doorway.position=Vector3(2,0,0)
	expect("rotated actual frame retains its empty opening",not occlusion._covered(Vector3(0,1.1,0)))
	expect("rotated actual frame retains its solid post",occlusion._covered(Vector3(0,1.1,0.835)))
	doorway.rotation=Vector3.ZERO;doorway.position=Vector3(0,0,2);doorway.scale=Vector3(2,1.5,0.5)
	camera.position=Vector3(0,1.65,10);camera.look_at(Vector3(0,1.65,0))
	expect("nonuniformly scaled frame opening stays empty",not occlusion._covered(Vector3(0,1.65,0)))
	expect("nonuniformly scaled frame post stays solid",occlusion._covered(Vector3(1.67,1.65,0)))
	doorway.visible=false
	var batch:=Builder.new()
	batch.box(AABB(Vector3(-2,0,-2),Vector3(0.2,3,6)),Transform3D.IDENTITY,"wall")
	batch.box(AABB(Vector3(1.8,0,-2),Vector3(0.2,3,6)),Transform3D.IDENTITY,"wall")
	batch.box(AABB(Vector3(-2,0,3.8),Vector3(4,3,0.2)),Transform3D.IDENTITY,"wall")
	var enclosure:=MeshInstance3D.new();enclosure.mesh=batch.mesh({});blockers.add_child(enclosure);refresh()
	expect("real face occludes even when target is inside aggregate AABB",occlusion._covered(Vector3(0,1.65,0)))
	enclosure.visible=false
	var nested:=Node3D.new();blockers.add_child(nested);refresh()
	var solid:=MeshInstance3D.new();var cube:=BoxMesh.new();cube.size=Vector3(1,3,0.2);solid.mesh=cube;solid.position=Vector3(0,1.5,2);nested.add_child(solid)
	expect("nested actual mesh invalidates scoped collection",occlusion._dirty)
	refresh()
	expect("new nested actual mesh enters the occluder collection",occlusion._covered(Vector3(0,1.65,0)))
	solid.position.z=-2
	expect("geometry behind player never triggers silhouette",not occlusion._covered(Vector3(0,1.65,0)))
	solid.position=Vector3(0,1.65,0);cube.size=Vector3(0.1,0.1,0.1)
	expect("player contact surface keeps original twenty-centimetre grace",not occlusion._covered(Vector3(0,1.65,0)))
	solid.position.z=2;cube.size=Vector3(1,3,0.2)
	expect("same resource geometry edits are reflected",occlusion._covered(Vector3(0,1.65,0)))
	solid.position.x=4
	expect("dynamic node transform never uses stale world triangles",not occlusion._covered(Vector3(0,1.65,0)))
	for i:int in 12:
		var transient:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3.ONE;transient.mesh=shape;transient.position=Vector3(0,1.65,2);nested.add_child(transient)
		refresh();occlusion._covered(Vector3(0,1.65,0));nested.remove_child(transient);transient.free();refresh()
	expect("retired nested geometry leaves no triangle or node cache",occlusion._triangles.size()<=3 and occlusion._watched.size()<=6,occlusion.statistics())
	var spare:Node3D=occlusion.actors
	stage.free();spare.free()
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():capture_case(args[0])
	print("DDD_OCCLUSION "+JSON.stringify({"scope":"B actual dimensions/native geometry; not normal-camera VA","ok":failures.is_empty(),"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)

func refresh()->void:
	if occlusion.has_method("_refresh"):occlusion._refresh()
	else:occlusion._meshes.clear();occlusion._collect(blockers);occlusion._dirty=false

func capture_case(path:String)->void:
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
	expect("archived actual pre-build-seven native slot decodes read-only",decoded.ok)
	if not decoded.ok:return
	var capture:Dictionary=decoded.capture
	expect("archived world loads without generation",world.load_snapshot(capture.world).ok)
	var configured:Dictionary=runtime.configure({"world":world,"facts":capture.facts,"source":capture.get("source",{}),"command_revision":capture.get("command_revision",0),"receipts":capture.get("receipts",{}),"services":{"buildings":building,"actions":actions,"production":production}})
	expect("full actual archived facts install with original metadata",configured.ok)
	if not configured.ok:return
	var before:Dictionary=runtime.capture_checkpoint()
	stage=Node3D.new();root.add_child(stage)
	var actors:=Actors.new();stage.add_child(actors);actors.configure(runtime);actors.set_process(false)
	blockers=building.create_view({"runtime":runtime});stage.add_child(blockers);blockers.set_process(false)
	var policy:=Policy.new();policy.configure(building.current_space());policy.sample(Geometry.location(runtime.actor("player")),0);blockers.set_view_policy(policy)
	camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	# A's actual seventh package metadata for this retained store slot.
	camera.position=Vector3(39.5728225708008,32.7000007629395,12.6239490509033)
	camera.rotation=Vector3(-0.636882483959198,0.658806025981903,0)
	occlusion=Occlusion.new();stage.add_child(occlusion);occlusion.configure(camera,actors,blockers);occlusion.set_process(false);occlusion._process(0.2)
	var comparisons:Array=[]
	for height:float in [1.1,1.65]:
		var target:Vector3=actors.roots.player.global_position+Vector3(0,height,0)
		var origin:Vector3=camera.project_ray_origin(camera.unproject_position(target))
		var aabb_hits:Array=[];var triangle_hits:Array=[]
		for instance:MeshInstance3D in occlusion._meshes:
			if not instance.is_visible_in_tree() or instance.mesh==null:continue
			var box:AABB=instance.global_transform*instance.get_aabb()
			var hit:Variant=box.intersects_segment(origin,target)
			if not box.has_point(target) and hit is Vector3 and hit.distance_to(target)>0.2:aabb_hits.append({"node":str(instance.get_path()),"piece":instance.get_meta("piece",{}).get("id"),"role":instance.get_meta("role")})
			var inverse:Transform3D=instance.global_transform.affine_inverse()
			var shape:TriangleMesh=instance.mesh.generate_triangle_mesh()
			if shape==null:continue
			var exact:Dictionary=shape.intersect_segment(inverse*origin,inverse*target)
			if not exact.is_empty() and (instance.global_transform*exact.position).distance_to(target)>0.2:triangle_hits.append({"node":str(instance.get_path()),"piece":instance.get_meta("piece",{}).get("id"),"role":instance.get_meta("role")})
		comparisons.append({"height":height,"old_aabb_hits":aabb_hits,"actual_face_hits":triangle_hits,"candidate_covered":occlusion._covered(target)})
	expect("retained actual source camera preserves real doorway post occlusion",comparisons.all(func(item:Dictionary)->bool:return not item.actual_face_hits.is_empty() and item.candidate_covered),comparisons)
	var player_meshes:Array=actors.roots.player.find_children("*","MeshInstance3D",true,false)
	expect("actual native player overlay only draws depth-covered fragments",actors._player_occluded and player_meshes.all(func(m:Node)->bool:return m.material_overlay is BaseMaterial3D and not m.material_overlay.no_depth_test and m.material_overlay.depth_test==BaseMaterial3D.DEPTH_TEST_INVERTED and m.material_overlay.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED),occlusion.statistics())
	expect("actual native slot projection changes no world facts clock inventory metadata",Data.json_equal(before,runtime.capture_checkpoint()))
	stage.free()
