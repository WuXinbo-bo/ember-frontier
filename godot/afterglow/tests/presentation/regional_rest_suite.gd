extends "res://tests/buildings/domain_suite.gd"
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Housing=preload("res://scripts/modules/module_housing.gd")
const Rest=preload("res://scripts/presentation/module_rest_visual.gd")
const Data=preload("res://scripts/world/world_data.gd")
const BedView=preload("res://scripts/buildings/building_view.gd")
var observations:Array=[]
func actual_bounds(node:Node3D)->AABB:
	var result:AABB;var first:bool=true
	for mesh:Node in node.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or mesh.mesh==null:continue
		var box:AABB=mesh.global_transform*mesh.mesh.get_aabb()
		result=box if first else result.merge(box);first=false
	return result
func run()->void:
	for q:int in 4:
		for level:int in 2:
			world=World.new();runtime=Runtime.new();building=Building.new();actions=Actions.new();production=Production.new()
			var home:Dictionary={"id":"D:finite:home","region":"RH-HOME","position":{"x":30,"y":0,"z":43},"quarter_turn":q,"geometry_version":"r34.module.home_small_porch_v1.geometry-v2","owner":"player"}
			var slot:Dictionary={"room_id":"D:finite:room","position":[0,0,0],"quarter_turn":0,"approach":[-.9,0,0],"level":level}
			var p:Vector3=Vector3(30,0,43)+Geometry.rotate(Vector3(-.9,0,0),q)
			var at:Dictionary=Geometry.json_point(p).merged({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
			var room:=AABB(Vector3(27,0,40),Vector3(6,2.4,6))
			var bed:Dictionary=Housing.bed_entity(home,level,slot,at,AABB(Vector3(29.59,0,42.09),Vector3(.82,.56,1.82)),room,true)
			# An explicitly finite B bed entity, not a paid-built/natural home.
			var snapshot:Dictionary=Generator.generate(713);snapshot.entities[bed.id]=bed
			expect("finite actual B bed entity loads "+str([q,level]),world.load_snapshot(snapshot).ok)
			initialize_at(at)
			var view:=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
			var started:Dictionary=command("rest",bed.id)
			expect("real Runtime accepts finite B bed contact "+str([q,level]),started.ok,started)
			if not started.ok:view.free();continue
			var before:Dictionary=runtime.capture_checkpoint();var actor_root:Transform3D=view.roots.player.global_transform
			view.sync(0)
			var report:Dictionary=view.statistics().module_rest.get("player",{})
			observations.append({"q":q,"level":level,"report":report})
			expect("accepted rest aligns original model to actual mattress "+str([q,level]),not report.is_empty() and absf(float(report.get("bottom_gap_m",999))-.005)<.0001 and float(report.get("head_alignment",0))>.999,report)
			expect("render attachment leaves actual root capsule and full authority unchanged "+str([q,level]),view.roots.player.global_transform.is_equal_approx(actor_root) and Data.json_equal(before,runtime.capture_checkpoint()))
			await process_frame;view.sync(.016)
			var actual:AABB=actual_bounds(view.roots.player)
			var surface:Vector3=Geometry.point(bed.data.module_bed.surface)
			var head_node:MeshInstance3D=view.roots.player.find_child("head",true,false) as MeshInstance3D
			var heading:Vector3=head_node.to_global(head_node.mesh.get_aabb().get_center())-actual.get_center();heading.y=0
			expect("independent actual mesh bounds stay on mattress after animation frame "+str([q,level]),absf(actual.position.y-surface.y-.005)<.0001 and Vector2(actual.get_center().x-surface.x,actual.get_center().z-surface.z).length()<.0001,Geometry.json_box(actual))
			expect("independent actual head points toward owner pillow "+str([q,level]),heading.normalized().dot(Geometry.rotate(Vector3.BACK,posmod(q,4)))>.999)
			var bed_view:=BedView.new();root.add_child(bed_view);bed_view.set_process(false);bed_view.configure({"service":building,"runtime":runtime})
			var bed_mesh:MeshInstance3D=bed_view.entity_object(bed) as MeshInstance3D;bed_view.add_child(bed_mesh)
			var mattress:AABB;var found:bool=false
			for s:int in bed_mesh.mesh.get_surface_count():
				var vertices:PackedVector3Array=bed_mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v:Vector3 in vertices:
					if absf(v.y-(.56+level*1.02))>.00001:continue
					mattress=mattress.expand(v) if found else AABB(v,Vector3.ZERO);found=true
			var local_actor:AABB;var first:bool=true
			for mesh:Node in view.roots.player.find_children("*","MeshInstance3D",true,false):
				if not mesh.is_visible_in_tree() or mesh.mesh==null:continue
				var box:AABB=(bed_mesh.global_transform.affine_inverse()*mesh.global_transform)*mesh.mesh.get_aabb()
				local_actor=box if first else local_actor.merge(box);first=false
			expect("original rig fits actual B mattress mesh without scale changes "+str([q,level]),found and not first and local_actor.position.x>=mattress.position.x-.0001 and local_actor.end.x<=mattress.end.x+.0001 and local_actor.position.z>=mattress.position.z-.0001 and local_actor.end.z<=mattress.end.z+.0001,{"actual_local_rig":Geometry.json_box(local_actor),"actual_mattress_plane":Geometry.json_box(mattress)})
			bed_view.free()
			var anchor:Node3D=view._module_rest.bindings.get("player",{}).get("anchor")
			if anchor!=null:
				var frozen:Transform3D=anchor.global_transform;runtime.set_paused(true);view.sync(.4);view.sync(1)
				expect("paused original rest attachment remains fixed "+str([q,level]),anchor.global_transform.is_equal_approx(frozen))
				runtime.set_paused(false)
			for field:String in ["sleeping","prepared","owner"]:
				var changed:Dictionary=bed.duplicate(true);changed.data[field]="another-owner" if field=="owner" else false
				var tx:Dictionary=world.prepare_changes([{"op":"entity.put","id":bed.id,"before_exists":true,"before":world.entity(bed.id),"after":changed}],world.get_revision())
				expect("explicit finite bed invalidation commits "+str([q,level,field]),tx.ok and world.commit_prepared(tx.capability).ok)
				var invalid_before:Dictionary=runtime.capture_checkpoint();view.sync(0)
				expect("unavailable bed removes attachment without authorizing rest "+str([q,level,field]),not view._module_rest.bindings.has("player") and not runtime.bed_availability(runtime.actor("player"),bed.id).ok and view._animations.player.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE and Data.json_equal(invalid_before,runtime.capture_checkpoint()))
				tx=world.prepare_changes([{"op":"entity.put","id":bed.id,"before_exists":true,"before":world.entity(bed.id),"after":bed}],world.get_revision())
				expect("finite original bed descriptor restored "+str([q,level,field]),tx.ok and world.commit_prepared(tx.capability).ok)
				view.sync(0)
				expect("only original accepted usable bed can rebind "+str([q,level,field]),view._module_rest.bindings.has("player"))
			command("cancel");view.sync(0)
			expect("cancel removes bed-only render attachment "+str([q,level]),not view._module_rest.bindings.has("player") and view._animations.player.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)
			var actor:Dictionary=runtime.actor("player");actor.intent={"owner":"residents","kind":"walk","resident_goal":{"kind":"bed","target_id":bed.id}}
			expect("resident approach does not lie down early "+str([q,level]),Rest.frame(actor,bed).is_empty())
			actor.intent={"owner":"runtime","kind":"rest","target_id":bed.id};var old:Dictionary=bed.duplicate(true);old.data.module_geometry_version="r34.module.home_small_porch_v1.geometry-v1"
			expect("legacy geometry1 never gets new bed offset "+str([q,level]),Rest.frame(actor,old).is_empty())
			view.free();runtime.retire();await process_frame
	var result:Dictionary={"scope":"Finite B bed_entity helper + real Runtime accepted rest + original rig geometry, four directions/two bunk levels. Not actual paid-built nine homes, bed routes/cold/renderer/PCK/VA/FPS.","checks":checks,"failures":failures,"observations":observations}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_REGIONAL_REST ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
