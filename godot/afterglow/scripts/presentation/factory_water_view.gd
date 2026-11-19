extends RefCounted
## B mounts/frees ONE physical fixture; this adapter only projects public water.
## No collider, authority query, timer, balance cache or second water inventory.
const Builder=preload("res://scripts/buildings/building_mesh.gd")
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const GROUP="factory_water_fixtures_v1"
const PAINT="res://data/buildings/textures/p03_water_tank_paint.png"
const RUST="res://data/buildings/textures/p06_car_rust.png"
static var _materials:Dictionary={}
static var _meshes:Dictionary={}

static func _number(v:Variant)->bool:
	return (v is int or v is float) and is_finite(float(v))

static func _point(v:Variant)->Variant:
	if not v is Dictionary:return null
	for key:String in ["x","y","z"]:
		if not _number(v.get(key)):return null
	return Vector3(v.x,v.y,v.z)

static func materials()->Dictionary:
	if not _materials.is_empty():return _materials
	var paint:StandardMaterial3D=_surface(PAINT,.87,.2)
	var rust:StandardMaterial3D=_surface(RUST,.95,.15)
	if paint==null or rust==null:return {}
	var water:=StandardMaterial3D.new()
	water.albedo_color=Color(.30,.62,.64,.65);water.roughness=.2
	water.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials={"paint":paint,"rust":rust,"metal":Surfaces.material("metal"),"wood":Surfaces.material("wood"),"water":water}
	return _materials

static func _surface(path:String,roughness:float,metallic:float)->StandardMaterial3D:
	var image:Image
	if ResourceLoader.exists(path,"Texture2D"):
		var texture:Texture2D=load(path)
		if texture!=null:image=texture.get_image()
	elif FileAccess.file_exists(path):image=Image.load_from_file(path)
	if image==null:
		push_error("WT01 surface missing: "+path);return null
	if image.is_compressed():image.decompress()
	if not image.has_mipmaps():image.generate_mipmaps()
	var paint:=StandardMaterial3D.new()
	paint.albedo_texture=ImageTexture.create_from_image(image)
	paint.roughness=roughness;paint.metallic=metallic;paint.texture_repeat=true
	paint.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	paint.set_meta("source_resource",path);paint.set_meta("tile_meters",1.0)
	return paint

static func _box(b:RefCounted,at:Vector3,size:Vector3,key:String)->void:
	b.box(AABB(at-size/2,size),Transform3D.IDENTITY,key,1.0 if key!="wood" else 2.0)

static func _triangle(b:RefCounted,a:Vector3,c:Vector3,d:Vector3,n:Vector3,key:String)->void:
	if not b.groups.has(key):b.groups[key]={"v":PackedVector3Array(),"n":PackedVector3Array(),"uv":PackedVector2Array(),"i":PackedInt32Array()}
	var g:Dictionary=b.groups[key];var start:int=g.v.size()
	for v:Vector3 in [a,c,d]:
		g.v.append(v);g.n.append(n);g.uv.append(Vector2(v.x,v.z))
	g.i.append_array(PackedInt32Array([start,start+1,start+2]))

static func _drum(b:RefCounted,radius:float,low:float,high:float,key:String)->void:
	# Flat octagonal sides, clockwise triangles and metre-scale side UVs.
	for i:int in 8:
		var angle:float=TAU*float(i)/8.0;var next:float=TAU*float(i+1)/8.0
		var a:=Vector3(sin(angle)*radius,low,cos(angle)*radius)
		var c:=Vector3(sin(next)*radius,low,cos(next)*radius)
		var normal:=Vector3(sin((angle+next)/2),0,cos((angle+next)/2))
		b.quad([c,a,Vector3(a.x,high,a.z),Vector3(c.x,high,c.z)],normal,Transform3D.IDENTITY,key,-1,Rect2(Vector2(float(i)*a.distance_to(c),0),Vector2(a.distance_to(c),high-low)))
		_triangle(b,Vector3(0,high,0),Vector3(c.x,high,c.z),Vector3(a.x,high,a.z),Vector3.UP,key)
		_triangle(b,Vector3(0,low,0),a,c,Vector3.DOWN,key)

static func _lid(b:RefCounted)->void:
	for i:int in 8:
		var angle:float=TAU*float(i)/8.0;var next:float=TAU*float(i+1)/8.0
		var a:=Vector3(sin(angle)*.445,1.25,cos(angle)*.445)
		var c:=Vector3(sin(next)*.445,1.25,cos(next)*.445)
		var d:=Vector3(sin(angle)*.18,1.35,cos(angle)*.18)
		var e:=Vector3(sin(next)*.18,1.35,cos(next)*.18)
		var normal:Vector3=-(a-c).cross(d-c).normalized()
		b.quad([c,a,d,e],normal,Transform3D.IDENTITY,"paint",-1,Rect2(0,0,a.distance_to(c),a.distance_to(d)))
	_drum(b,.18,1.35,1.375,"paint")

static func _mesh(key:String)->ArrayMesh:
	if _meshes.has(key):return _meshes[key]
	var b:=Builder.new()
	match key:
		"body":
			_drum(b,.425,.17,1.24,"paint")
			for y:float in [.22,.52,1.15]:_drum(b,.44,y,y+.045,"rust")
			_lid(b)
			for x:float in [-.29,.29]:
				_box(b,Vector3(x,.075,0),Vector3(.17,.15,.78),"rust")
			_box(b,Vector3(0,.82,.425),Vector3(.18,.34,.035),"rust")
			# Outlet and a dry catch tray stay inside B's 1.2 x 1.4 x 1.2m box.
			_box(b,Vector3(0,.77,.475),Vector3(.085,.085,.16),"metal")
			_box(b,Vector3(0,.735,.535),Vector3(.085,.12,.055),"rust")
			_box(b,Vector3(0,.315,.49),Vector3(.30,.035,.18),"rust")
			for x:float in [-.14,.14]:_box(b,Vector3(x,.345,.49),Vector3(.02,.045,.18),"rust")
			_box(b,Vector3(0,.345,.405),Vector3(.30,.045,.02),"rust")
		"loose":
			_box(b,Vector3(0,.06,0),Vector3(.045,.12,.045),"wood")
			_box(b,Vector3(0,0,0),Vector3(.085,.04,.06),"metal")
		"repaired":
			# Small replacement collar on the original manual mechanism.
			_box(b,Vector3(0,.87,.465),Vector3(.095,.05,.06),"metal")
			for x:float in [-.06,.06]:
				for y:float in [.72,.93]:_box(b,Vector3(x,y,.451),Vector3(.025,.025,.015),"rust")
		"lever":
			_box(b,Vector3(0,.14,0),Vector3(.055,.28,.055),"wood")
			_box(b,Vector3(0,.04,0),Vector3(.08,.055,.075),"metal")
			_box(b,Vector3(0,.24,0),Vector3(.075,.025,.075),"rust")
		"stream":_box(b,Vector3(0,.50,.535),Vector3(.014,.35,.014),"water")
		"cap":_box(b,Vector3.ZERO,Vector3(.095,.015,.075),"metal")
	var mesh:ArrayMesh=b.mesh(materials());_meshes[key]=mesh;return mesh

static func create_fixture(e:Dictionary,world_instance:int)->Node3D:
	var data:Variant=e.get("data");var at:Variant=_point(e.get("position"))
	if not data is Dictionary or at==null or world_instance==0 or str(e.get("id","")).is_empty() or data.get("water_source_id")!=e.id:return null
	var use_point:Variant=_point(data.get("water_use_point"))
	if use_point==null:return null
	var forward:Vector3=use_point-at;forward.y=0
	if forward.length_squared()<.0001:return null
	var root:=Node3D.new();root.name="WaterFixture"
	root.set_meta("water_source_id",str(e.id));root.set_meta("world_instance",world_instance)
	root.set_meta("source_position",at);root.set_meta("water_state","unknown")
	root.set_meta("public_known",false);root.set_meta("projection_issue","")
	root.add_to_group(GROUP)
	var assembly:=Node3D.new();assembly.name="Assembly";root.add_child(assembly)
	assembly.rotation.y=atan2(forward.x,forward.z)
	for key:String in ["body","loose","repaired","lever","stream","cap"]:
		var part:=MeshInstance3D.new();part.name=key;part.mesh=_mesh(key);assembly.add_child(part)
	assembly.get_node("loose").position=Vector3(0,.86,.46)
	assembly.get_node("loose").rotation.z=.28
	assembly.get_node("lever").position=Vector3(0,.86,.46)
	assembly.get_node("cap").position=Vector3(0,.6675,.535)
	for key:String in ["repaired","lever","stream","cap"]:assembly.get_node(key).visible=false
	return root

static func _reset(fixture:Node3D,issue:String="")->void:
	fixture.set_meta("public_known",false);fixture.set_meta("projection_issue",issue)
	fixture.set_meta("water_state","unknown");fixture.set_meta("work_phase",0.0)
	fixture.get_node("Assembly/stream").visible=false
	fixture.get_node("Assembly/cap").visible=false
	fixture.get_node("Assembly/lever").rotation.x=0.0
	fixture.get_node("Assembly/loose").rotation.z=.28
	# Keep observed physical repairs; disappearing permission is not new damage.

static func apply_public(fixture:Node3D,projection:Dictionary,paused:bool=false)->void:
	_reset(fixture)
	if not projection.get("available",false):return
	var sources:Variant=projection.get("sources");var projects:Variant=projection.get("projects")
	if not sources is Array or not projects is Array:_reset(fixture,"WATER_ARRAYS_REQUIRED");return
	var matches:Array=[];var id:String=fixture.get_meta("water_source_id","")
	for value:Variant in sources:
		if value is Dictionary and value.get("id")==id:matches.append(value)
	if matches.is_empty():return
	if matches.size()!=1:_reset(fixture,"WATER_DUPLICATE_SOURCE");return
	var source:Dictionary=matches[0];var remaining:Variant=source.get("remaining")
	if source.get("discovered")!=true or source.get("status") not in ["needs_repair","ready"] or not _number(remaining) or float(remaining)!=floorf(float(remaining)) or remaining<0 or remaining>48 or _point(source.get("location"))!=fixture.get_meta("source_position") or not source.get("project_id") is String:
		_reset(fixture,"WATER_SOURCE_INVALID");return
	var ready:bool=source.status=="ready"
	fixture.set_meta("public_known",true)
	fixture.set_meta("water_state","empty" if ready and remaining==0 else "ready" if ready else "needs_repair")
	fixture.get_node("Assembly/loose").visible=not ready
	fixture.get_node("Assembly/repaired").visible=ready
	fixture.get_node("Assembly/lever").visible=ready
	fixture.get_node("Assembly/lever").rotation.x=.2 if ready and remaining>0 else 0.0
	fixture.get_node("Assembly/cap").visible=ready and remaining==0
	if str(source.project_id).is_empty():return
	var jobs:Array=[]
	for value:Variant in projects:
		if value is Dictionary and value.get("id")==source.project_id:jobs.append(value)
	if jobs.size()!=1:_reset(fixture,"WATER_PROJECT_ID_INVALID");return
	var p:Dictionary=jobs[0]
	if p.get("source_id")!=id or p.get("actor_id")!="player" or p.get("operation") not in ["repair","draw"] or p.get("status") not in ["active","paused","blocked"] or not _number(p.get("progress_seconds")) or not _number(p.get("effective_work")) or p.effective_work<0 or p.effective_work>1 or not p.get("paused_reason") is String:
		_reset(fixture,"WATER_PROJECT_INVALID");return
	var repair:bool=p.operation=="repair";var duration:float=16.0 if repair else 12.0
	if p.get("duration_seconds")!=duration or p.progress_seconds<0 or p.progress_seconds>duration or repair==ready or (not repair and remaining<=0):
		_reset(fixture,"WATER_PROJECT_STATE_INVALID");return
	var phase:float=fposmod(float(p.progress_seconds),1.0)
	fixture.set_meta("work_phase",phase)
	if paused or p.status!="active" or not p.paused_reason.is_empty() or float(p.effective_work)<=0:return
	if repair:fixture.get_node("Assembly/loose").rotation.z=.20+.08*cos(phase*TAU)
	else:
		# Godot's positive X rotation moves the +Y grip toward local +Z.
		# B's contact uses offset=.46-.24*sin(-angle), the same real point.
		fixture.get_node("Assembly/lever").rotation.x=.32+.08*sin(phase*TAU)
		fixture.get_node("Assembly/stream").visible=true

static func sync_tree(tree:SceneTree,world_instance:int,projection:Dictionary,paused:bool=false)->void:
	if tree==null or world_instance==0:return
	for value:Node in tree.get_nodes_in_group(GROUP):
		if value is Node3D and not value.is_queued_for_deletion() and value.get_meta("world_instance",0)==world_instance:apply_public(value,projection,paused)
