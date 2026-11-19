extends "res://tests/buildings/domain_suite.gd"
## Actual versioned station and B mesh; explicit in-memory placement/state.
## These are transform assertions, not player construction or pixel VA.
const Device=preload("res://scripts/presentation/gameplay_view.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Data=preload("res://scripts/world/world_data.gd")

func commit(changes:Array,label:String)->bool:
	var prepared:Dictionary=world.prepare_changes(changes,world.get_revision())
	var accepted:bool=prepared.ok and world.commit_prepared(prepared.capability).ok
	expect(label,accepted,prepared.get("reason"))
	return accepted

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("same finite source loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	if not commit(seeded.world_changes,"actual B source seed installs"):finish(started);return
	var bench:Dictionary=building.make_instance("workbench","ddd:transform-station",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	var structures:Dictionary=building.structures();structures.instances.append(bench)
	if not commit(building.changes_for(structures,[bench],[]),"explicit versioned station installs"):finish(started);return
	var state:Dictionary=Gameplay.initial();state.defense.status="cleared";state.radio.status="repaired";state.radio.station_id=bench.id
	if not commit([building.extension_change(Gameplay.KEY,state)],"explicit repaired fixture refers to actual station"):finish(started);return
	var mesh_view:Node3D=building.create_view({"runtime":runtime});root.add_child(mesh_view);mesh_view.set_process(false)
	var device:=Device.new();root.add_child(device);device.configure(runtime,building);device.set_process(false);device._process(0.2)
	expect("actual renderer and radio share same live station",mesh_view.objects.has(bench.id) and device._radio!=null and device.statistics().station_id==bench.id)
	if device._radio==null:device.free();mesh_view.free();finish(started);return
	var radio_id:int=device._radio.get_instance_id()
	# The delivered workbench tabletop spans y=.9..1.02. Its rear rack reaches
	# 1.845, so a whole-model AABB is not a tabletop attachment point.
	var tabletop:float=source_tabletop(mesh_view.objects[bench.id])
	expect("actual imported mesh resolves centre tabletop separately from rack",is_equal_approx(tabletop,1.02),tabletop)
	expect("device base clears actual delivered tabletop instead of sinking",is_equal_approx(device._radio.position.y,float(bench.position.y)+tabletop),device._radio.position.y)
	for turn:int in [0,1,2,3,0]:
		var next:Dictionary=bench.duplicate(true);next.quarterTurn=turn;next.position.x+=0.1;next.version=int(next.version)+1
		structures=building.structures()
		for i:int in structures.instances.size():
			if structures.instances[i].id==bench.id:structures.instances[i]=next
		if not commit(building.changes_for(structures,[next],[]),"explicit station move/turn "+str(turn)+" commits"):break
		bench=next;mesh_view.rebuild()
		var before:Dictionary=runtime.capture_checkpoint();device._process(0.2)
		var definition:Dictionary=building.geometry.definition(bench)
		var approach:Vector3=Geometry.rotate(Geometry.point(definition.usePoints[0]),turn);approach.y=0;approach=approach.normalized()
		var front:Vector3=device._radio.transform.basis*Vector3.BACK
		expect("radio panel faces real station use point at turn "+str(turn),front.is_equal_approx(approach),{"actual":str(front),"expected":str(approach),"bench_basis":str(mesh_view.objects[bench.id].basis)})
		expect("radio follows station position without remount at turn "+str(turn),device._radio.get_instance_id()==radio_id and is_equal_approx(device._radio.position.x,float(bench.position.x)) and is_equal_approx(device._radio.position.z,float(bench.position.z)))
		var local_base:Vector3=mesh_view.objects[bench.id].global_transform.affine_inverse()*device._radio.global_position
		expect("actual radio remains seated on imported tabletop at turn "+str(turn),is_equal_approx(local_base.y,tabletop),str(local_base))
		expect("device projection preserves complete authority at turn "+str(turn),Data.json_equal(before,runtime.capture_checkpoint()))
	device.free();mesh_view.free();finish(started)

func source_tabletop(node:Node3D)->float:
	var top:float=-INF
	var meshes:Array=node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:meshes.push_front(node)
	for mesh:MeshInstance3D in meshes:
		var to_local:Transform3D=node.global_transform.affine_inverse()*mesh.global_transform
		var faces:PackedVector3Array=mesh.mesh.get_faces()
		for i:int in range(0,faces.size(),3):
			var a:Vector3=to_local*faces[i];var b:Vector3=to_local*faces[i+1];var c:Vector3=to_local*faces[i+2]
			if absf(a.y-b.y)>0.00001 or absf(a.y-c.y)>0.00001:continue
			if Geometry2D.is_point_in_polygon(Vector2.ZERO,PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])):top=maxf(top,a.y)
	return top

func finish(started:int)->void:
	var result:Dictionary={"scope":"actual B station/mesh and A/C authority; explicit state/placement, not OS or VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_DEVICE_TRANSFORM "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
