extends RefCounted
## Exact local production surfaces. No shared floor or damage-state overrides.
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const DIRECTORY="res://data/factory/surfaces/production-v1/"
const SPECS={
	"end":{"file":"log_endgrain_04m.png","meters":0.4,"repeat":false,"roughness":0.92,"metallic":0.0},
	"timber":{"file":"timber_sawn_face_2m.png","meters":2.0,"repeat":true,"roughness":0.9,"metallic":0.0},
	"drive_paint":{"file":"drive_painted_iron_1m.png","meters":1.0,"repeat":true,"roughness":0.8,"metallic":0.25},
	"drive_rust":{"file":"drive_rust_iron_1m.png","meters":1.0,"repeat":true,"roughness":0.95,"metallic":0.2}}
static var _materials:Dictionary={}
static var _meshes:Dictionary={}
static func is_architecture(key:String)->bool:
	return key=="architecture_window"

static func architecture_material(key:String)->StandardMaterial3D:
	if not is_architecture(key):return null
	if _materials.has(key):return _materials[key]
	# Closed opaque glass keeps the original sealed service-wall authority.
	var result:=StandardMaterial3D.new()
	result.cull_mode=BaseMaterial3D.CULL_DISABLED
	result.albedo_color=Color(0.10,0.145,0.14);result.roughness=0.37;result.metallic=0.08
	result.set_meta("source_mode","native-closed-glazing")
	result.set_meta("tile_meters",2.0);result.set_meta("architecture_surface",key)
	_materials[key]=result
	return result

static func material(key:String)->StandardMaterial3D:
	if _materials.has(key):return _materials[key]
	var spec:Dictionary=SPECS[key];var path:String=DIRECTORY+str(spec.file)
	var image:Image;var mode:String="imported"
	if ResourceLoader.exists(path,"Texture2D"):
		var source:Texture2D=load(path)
		if source!=null:image=source.get_image()
	elif FileAccess.file_exists(path):image=Image.load_from_file(path);mode="source-png"
	if image==null or image.get_width()!=512 or image.get_height()!=512:
		push_error("Production surface missing or invalid: "+path);return null
	if image.is_compressed():image.decompress()
	if image.detect_alpha()!=Image.ALPHA_NONE:
		push_error("Production surface must be opaque: "+path);return null
	if not image.has_mipmaps():image.generate_mipmaps()
	var result:=StandardMaterial3D.new()
	result.albedo_texture=ImageTexture.create_from_image(image)
	result.roughness=float(spec.roughness);result.metallic=float(spec.metallic)
	result.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	result.texture_repeat=spec.repeat
	result.set_meta("source_resource",path);result.set_meta("source_mode",mode)
	result.set_meta("tile_meters",spec.meters);result.set_meta("production_surface",key)
	_materials[key]=result
	return result

static func timber_mesh(size:Vector3,long_axis:int)->ArrayMesh:
	var key:String=str(["timber",size,long_axis])
	if _meshes.has(key):return _meshes[key]
	var source:Array=Surfaces.metric_box(size,2.0).surface_get_arrays(0)
	var vertices:PackedVector3Array=source[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=source[Mesh.ARRAY_NORMAL]
	var indices:PackedInt32Array=source[Mesh.ARRAY_INDEX]
	var uv:PackedVector2Array=source[Mesh.ARRAY_TEX_UV].duplicate()
	# The new image's grain runs along V. Stock boards are long in Z;
	# carried boards are long in X. Their cut ends keep the former wood.
	for i:int in vertices.size():
		if absf(normals[i][long_axis])>.5:continue
		var transverse:float=vertices[i].x if long_axis==2 and absf(normals[i].y)>.5 else vertices[i].z if long_axis==0 and absf(normals[i].y)>.5 else vertices[i].y
		uv[i]=Vector2(transverse,vertices[i][long_axis])/2.0
	source[Mesh.ARRAY_TEX_UV]=uv
	var result:=ArrayMesh.new()
	for ends:bool in [false,true]:
		var selected:=PackedInt32Array()
		for i:int in range(0,indices.size(),3):
			if (absf(normals[indices[i]][long_axis])>.5)==ends:selected.append_array(indices.slice(i,i+3))
		var arrays:Array=source.duplicate();arrays[Mesh.ARRAY_INDEX]=selected
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,Surfaces.material("wood") if ends else material("timber"))
	_meshes[key]=result
	return result

static func timber(parent:Node3D,position:Vector3,size:Vector3,long_axis:int)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.position=position;node.mesh=timber_mesh(size,long_axis)
	parent.add_child(node);return node

static func drive_housing_mesh(height:float,radius:float)->ArrayMesh:
	var key:String=str(["drive",height,radius])
	if _meshes.has(key):return _meshes[key]
	var primitive:=CylinderMesh.new();primitive.height=height;primitive.top_radius=radius;primitive.bottom_radius=radius;primitive.radial_segments=8
	var arrays:Array=primitive.get_mesh_arrays()
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var old_uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var uv:=PackedVector2Array();uv.resize(vertices.size())
	for i:int in vertices.size():
		var p:Vector3=vertices[i]
		uv[i]=Vector2(p.x,p.z) if absf(normals[i].y)>.5 else Vector2(old_uv[i].x*TAU*radius,p.y)
	arrays[Mesh.ARRAY_TEX_UV]=uv
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.surface_set_material(0,material("drive_paint"));_meshes[key]=result
	return result
