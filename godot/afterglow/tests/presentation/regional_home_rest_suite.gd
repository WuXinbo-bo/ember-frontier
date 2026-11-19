extends "res://tests/presentation/regional_rest_suite.gd"
## Actual nine-house generated bed descriptors, not hand-authored bed poses.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
var homes:int=0
var cases:int=0
func run()->void:
	for d:Dictionary in Catalog.definitions():
		if not Housing.applies(d):continue
		homes+=1
		for q:int in 4:
			var home:Dictionary={"id":"D:actual-shape:"+str(d.id),"region":"RH-HOME","position":{"x":30,"y":0,"z":43},"quarter_turn":q,"geometry_version":d.geometry_version,"owner":"player"}
			var beds:Array=Shape.entities(home,d).filter(func(e:Dictionary)->bool:return e.data.get("module_bed") is Dictionary)
			expect("actual current house emits beds "+str([d.id,q]),not beds.is_empty())
			if beds.is_empty():continue
			var selected:Array=[beds.front()]
			if beds.back().id!=beds.front().id:selected.append(beds.back())
			for bed:Dictionary in selected:
				cases+=1
				world=World.new();runtime=Runtime.new();building=Building.new();actions=Actions.new();production=Production.new()
				var capture:Dictionary=Generator.generate(713);capture.entities[bed.id]=bed
				expect("finite exact generated bed World load "+str(bed.id),world.load_snapshot(capture).ok)
				initialize_at(bed.data.module_bed.approach)
				var view:=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
				var at:Transform3D=view.roots.player.global_transform
				var started:Dictionary=command("rest",bed.id)
				expect("real Runtime accepts exact generated bed "+str([d.id,q,bed.id]),started.ok,started)
				if not started.ok:view.free();runtime.retire();continue
				var before:Dictionary=runtime.capture_checkpoint();view.sync(0);await process_frame;view.sync(.016)
				var model:Node3D=view._module_rest.bindings.get("player",{}).get("model")
				var report:Dictionary=view.statistics().module_rest.get("player",{})
				expect("generated bed uses actual accepted rest attachment "+str([d.id,q,bed.id]),not report.is_empty() and model!=null and model.scale.is_equal_approx(Vector3.ONE) and report.bed_id==bed.id,report)
				var bv:=BedView.new();root.add_child(bv);bv.set_process(false);bv.configure({"service":building,"runtime":runtime})
				var bm:MeshInstance3D=bv.entity_object(bed) as MeshInstance3D;bv.add_child(bm)
				var mattress:AABB;var found:bool=false
				for s:int in bm.mesh.get_surface_count():
					for v:Vector3 in bm.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
						if absf(v.y-(.56+int(bed.data.module_bed.level)*1.02))>.00001:continue
						mattress=mattress.expand(v) if found else AABB(v,Vector3.ZERO);found=true
				var local:AABB;var first:bool=true
				for mesh:Node in view.roots.player.find_children("*","MeshInstance3D",true,false):
					if not mesh.is_visible_in_tree() or mesh.mesh==null:continue
					var box:AABB=(bm.global_transform.affine_inverse()*mesh.global_transform)*mesh.mesh.get_aabb()
					local=box if first else local.merge(box);first=false
				expect("unscaled original mesh fits actual generated bed mattress "+str([d.id,q,bed.id]),found and not first and local.position.x>=mattress.position.x-.0001 and local.end.x<=mattress.end.x+.0001 and local.position.z>=mattress.position.z-.0001 and local.end.z<=mattress.end.z+.0001 and absf(local.position.y-mattress.position.y-.005)<.0001,{"rig_local":Geometry.json_box(local),"actual_mattress":Geometry.json_box(mattress),"bed":bed.data.module_bed})
				var bounds:AABB=actual_bounds(view.roots.player);var head:MeshInstance3D=view.roots.player.find_child("head",true,false) as MeshInstance3D
				var direction:Vector3=head.to_global(head.mesh.get_aabb().get_center())-bounds.get_center();direction.y=0
				expect("actual head follows generated rotated pillow "+str([d.id,q,bed.id]),direction.normalized().dot(Geometry.point(bed.data.module_bed.head_direction))>.999)
				expect("all exact home bed poses preserve authority and root "+str([d.id,q,bed.id]),Data.json_equal(before,runtime.capture_checkpoint()) and view.roots.player.global_transform.is_equal_approx(at))
				observations.append({"home":d.id,"q":q,"bed":bed.id,"level":bed.data.module_bed.level,"report":report,"actual_mattress":Geometry.json_box(mattress),"rig_local":Geometry.json_box(local)})
				bv.free();view.free();runtime.retire();await process_frame
	expect("nine exact house definitions covered",homes==9,homes)
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"scope":"Nine current Catalog homes x four orientations, first/last actual Shape-generated bed, real Runtime accepted rest and original actor mesh fits actual B mattress. Finite source fixture inserts only the exact bed; no wall/door/bed route, paid construction, natural economy, GPU/PCK/OS/VA/FPS claim.","checks":checks,"failures":failures,"homes":homes,"cases":cases,"observations":observations},"\t"))
	print("DDD_REGIONAL_HOME_REST ",JSON.stringify({"checks":checks.size(),"cases":cases,"failures":failures}));quit(0 if failures.is_empty() else 1)
