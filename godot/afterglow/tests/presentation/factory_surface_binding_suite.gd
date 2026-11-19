extends SceneTree
## Exact image/metric UV and actual disposable mesh consumers, not OS/VA.
const Materials=preload("res://scripts/presentation/factory_materials.gd")
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
const Cargo=preload("res://scripts/presentation/factory_cargo_view.gd")
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const Machine=preload("res://scripts/presentation/factory_machine_view.gd")
var checks:Array=[]
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label)
func pixels(image:Image)->PackedByteArray:
	image=image.duplicate()
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8);return image.get_data()
func same_geometry(mesh:Mesh,original:Array)->bool:
	var actual_indices:Array=[];var expected_indices:Array=[]
	for value:int in original[Mesh.ARRAY_INDEX]:expected_indices.append(value)
	for surface:int in mesh.get_surface_count():
		var arrays:Array=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		if vertices.size()!=original[Mesh.ARRAY_VERTEX].size():return false
		for i:int in vertices.size():
			if vertices[i].distance_to(original[Mesh.ARRAY_VERTEX][i])>.000001 or normals[i].dot(original[Mesh.ARRAY_NORMAL][i])<.9999:return false
		for value:int in arrays[Mesh.ARRAY_INDEX]:actual_indices.append(value)
	actual_indices.sort();expected_indices.sort();return actual_indices==expected_indices
func board(mesh:Mesh,size:Vector3,axis:int,label:String)->void:
	var primitive:=BoxMesh.new();primitive.size=size
	expect("board retains original primitive vertices normals and all triangles "+label,same_geometry(mesh,primitive.get_mesh_arrays()))
	expect("only long faces use new saw timber; cut ends retain former wood "+label,mesh.get_surface_count()==2 and mesh.surface_get_material(0)==Materials.material("timber") and mesh.surface_get_material(1)==Surfaces.material("wood"))
	var correct:=true
	for surface:int in mesh.get_surface_count():
		var arrays:Array=mesh.surface_get_arrays(surface)
		for index:int in arrays[Mesh.ARRAY_INDEX]:
			var normal:Vector3=arrays[Mesh.ARRAY_NORMAL][index]
			correct=correct and (absf(normal[axis])>.5)==(surface==1)
			if surface==0:correct=correct and absf(arrays[Mesh.ARRAY_TEX_UV][index].y-arrays[Mesh.ARRAY_VERTEX][index][axis]/2.0)<.00001
	expect("two meter grain V follows true long axis and avoids end faces "+label,correct)
func run()->void:
	var selection:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Materials.DIRECTORY+"selection.json"))
	var modes:Dictionary={}
	for key:String in Materials.SPECS:
		var material:StandardMaterial3D=Materials.material(key);var spec:Dictionary=Materials.SPECS[key]
		expect("delivered material exists "+key,material!=null)
		if material==null:continue
		var path:String=Materials.DIRECTORY+str(spec.file)
		var rows:Array=selection.assets.filter(func(row:Dictionary)->bool:return row.resource==path)
		expect("exact copied PNG hash "+key,rows.size()==1 and FileAccess.get_sha256(path)==str(rows[0].sha256))
		expect("true image pixels and derived mip chain "+key,material.albedo_texture.get_image().has_mipmaps() and pixels(material.albedo_texture.get_image())==pixels(Image.load_from_file(path)))
		expect("per-use physical meters and repeat "+key,float(material.get_meta("tile_meters"))==float(spec.meters) and material.texture_repeat==bool(spec.repeat))
		modes[key]=material.get_meta("source_mode","")
		expect("binding provenance is explicit "+key,modes[key] in ["source-png","imported"])
	var parent:=Node3D.new();root.add_child(parent)
	var stock:=Stock.new();parent.add_child(stock)
	var row:Dictionary={"stock_ref":"fixture:finite","item_id":"timber","unit":"count","representation":"plank","actual":1.0,"capacity":10.0,"reserved":0.0,"extent":Vector3(.4,.38,.48)}
	expect("actual stock consumer accepts finite plank row",stock.update(row))
	var part:MeshInstance3D=stock._parts[0];var identity:int=part.get_instance_id();var mesh_identity:int=part.mesh.get_instance_id()
	board(part.mesh,Vector3(.4*.29,.38*.10,.48*.96),2,"stock Z")
	for amount:float in [0.0,1.0,5.0,9.0,10.0]:
		row.actual=amount;stock.update(row)
		expect("material binding preserves stock bands identity and amount "+str(amount),stock._parts[0].get_instance_id()==identity and stock._parts[0].mesh.get_instance_id()==mesh_identity and stock.statistics().actual==amount and stock.statistics().visible_parts==Stock.BAND_COUNTS[Stock.band(amount,10.0)])
	row.visual_available=false;stock.update(row)
	expect("material replacement retains unavailable owner hiding",not stock.visible and stock.statistics().actual==10.0)
	var timber:Node3D=Cargo.create("timber");parent.add_child(timber)
	board(timber.get_child(0).mesh,Vector3(.88,.045,.16),0,"carried X")
	var log:Node3D=Cargo.create("log");parent.add_child(log)
	var log_mesh:Mesh=log.get_child(0).mesh
	expect("actual carried log selects new cap while preserving bark",log_mesh.surface_get_material(1)==Materials.material("end") and str(log_mesh.surface_get_material(0).get_meta("source_resource","")).ends_with("v09_broadleaf_bark.png"))
	var cap:Array=log_mesh.surface_get_arrays(1);var cap_ok:=true
	for index:int in cap[Mesh.ARRAY_INDEX]:
		var p:Vector3=cap[Mesh.ARRAY_VERTEX][index]
		cap_ok=cap_ok and cap[Mesh.ARRAY_TEX_UV][index].distance_to(Vector2(p.x,p.z)/.4+Vector2.ONE*.5)<.00001
	expect("actual cap preserves nonrepeating local 0.4m UV",cap_ok and not log_mesh.surface_get_material(1).texture_repeat)
	var drive:Node3D=Cargo.create("r34:salvaged_drive_unit");parent.add_child(drive)
	var cylinder:=CylinderMesh.new();cylinder.height=.26;cylinder.top_radius=.12;cylinder.bottom_radius=.12;cylinder.radial_segments=8
	var housing:MeshInstance3D=drive.get_child(0);var base:MeshInstance3D=drive.get_child(1);var shaft:MeshInstance3D=drive.get_child(2)
	expect("recovered drive retains exact former cylinder geometry",same_geometry(housing.mesh,cylinder.get_mesh_arrays()) and housing.rotation.is_equal_approx(Vector3(0,0,PI/2)))
	expect("painted shell rusty local base and bare shaft are separately selected",housing.get_active_material(0)==Materials.material("drive_paint") and base.get_active_material(0)==Materials.material("drive_rust") and shaft.material_override==Surfaces.material("metal"))
	var actual:Array=housing.mesh.surface_get_arrays(0);var source:Array=cylinder.get_mesh_arrays();var metric:=true
	for i:int in actual[Mesh.ARRAY_VERTEX].size():
		var p:Vector3=actual[Mesh.ARRAY_VERTEX][i];var n:Vector3=actual[Mesh.ARRAY_NORMAL][i]
		var uv:Vector2=Vector2(p.x,p.z) if absf(n.y)>.5 else Vector2(source[Mesh.ARRAY_TEX_UV][i].x*TAU*.12,p.y)
		metric=metric and actual[Mesh.ARRAY_TEX_UV][i].distance_to(uv)<.00001
	expect("cylinder side and cap use actual one meter sampling",metric)
	var base_uv:PackedVector2Array=Surfaces.metric_box(Vector3(.34,.04,.22),1.0).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	expect("rust base keeps original dimensions and uses one meter box UV",base.position.is_equal_approx(Vector3(0,-.13,0)) and base.mesh.get_aabb().size.is_equal_approx(Vector3(.34,.04,.22)) and var_to_bytes(base.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV])==var_to_bytes(base_uv))
	var machine:=Machine.new();parent.add_child(machine)
	expect("real moving subassembly creates from owner progress",machine.update({"kind":"reciprocating_saw","progress_seconds":.2,"duration_seconds":10.0,"effective_work":.1,"active":true}))
	expect("blade and crank retain working metal instead of painted housing",machine._blade.material_override==Surfaces.material("metal") and machine._crank.get_child(0).material_override==Surfaces.material("metal"))
	expect("global wood and tool metal are not replaced",Surfaces.material("wood").get_meta("source_resource","")!=Materials.DIRECTORY+"timber_sawn_face_2m.png" and Surfaces.material("metal").get_meta("source_resource","")!=Materials.DIRECTORY+"drive_painted_iron_1m.png")
	parent.free();await process_frame
	var result:Dictionary={"scope":"exact source PNG/metric UV/real stock cargo and moving-part consumer meshes with explicit finite DTO; not normal economy, PCK, OS, VA or performance","source_modes":modes,"checks":checks,"failures":failures}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_PRODUCTION_SURFACES "+JSON.stringify({"checks":checks.size(),"failed":failures.size()}));quit(0 if failures.is_empty() else 1)
