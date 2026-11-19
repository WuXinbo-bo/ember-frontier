extends RefCounted
## Small derived tool geometry: no unique asset/quantity or authority here.
## No standalone tool GLB exists in the delivered library. Reuse its wood/zinc
## surfaces and Godot BoxMesh; all definitions share this bounded adapter.
static var _materials:Dictionary={}
# Local contact frames describe the actual derived geometry, not action reach.
# The action owner still decides whether a hit/work contact is valid.
const CONTACTS={
	"salvaged_axe":{"point":Vector3(0.21,0.25,0),"normal":Vector3.RIGHT},
	"hammer":{"point":Vector3(0.125,0.28,0),"normal":Vector3.RIGHT},
	# The sixth existing tooth is at x=.045+5*.055=.32, lower face y=.0225.
	# Use the actual forward cutting tooth, rather than an arbitrary middle
	# blade point. Mesh dimensions, palm grip and action reach stay unchanged.
	"hand_saw":{"point":Vector3(0.32,0.0225,0),"normal":Vector3.DOWN},
	"shovel":{"point":Vector3(0,0.5625,-0.025),"normal":Vector3.UP},
	"pickaxe":{"point":Vector3(-0.215,0.31,0),"normal":Vector3(-0.70710678,-0.70710678,0)}}

static func contact_frame(tool:Node3D)->Dictionary:
	if tool==null or not is_instance_valid(tool) or not tool.has_meta("contact_point"):return {}
	return {"kind":tool.get_meta("tool_kind",""),"grip_world":tool.global_position,
		"point_world":tool.global_transform*Vector3(tool.get_meta("contact_point")),
		"normal_world":(tool.global_basis*Vector3(tool.get_meta("contact_normal"))).normalized(),
		"scope":"derived tool geometry only; no hit or reach authority"}
static func material(kind:String)->Material:
	if _materials.has(kind):return _materials[kind]
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	var id:String="wood_floor" if kind=="wood" else "zinc"
	var result:=StandardMaterial3D.new()
	result.albedo_texture=load(manifest.textures[id].resource)
	# Match C's existing native fallback: a mip sampler cannot use levels that
	# PNG imports did not generate. Derive them once, preserving base pixels.
	var image:Image=result.albedo_texture.get_image()
	if image!=null and not image.has_mipmaps():
		if image.is_compressed():image.decompress()
		if image.generate_mipmaps()==OK:result.albedo_texture=ImageTexture.create_from_image(image)
	result.roughness=0.9 if kind=="wood" else 0.68
	result.metallic=0 if kind=="wood" else 0.65
	result.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	result.set_meta("tile_meters",float(manifest.textures[id].tile_meters))
	result.set_meta("source_resource",str(manifest.textures[id].resource))
	_materials[kind]=result
	return result
static func metric_box(size:Vector3,tile_meters:float)->ArrayMesh:
	# Reuse Godot's exact primitive vertices/normals/indices. Only its default
	# 3x2 box-atlas UVs change: every face samples physical local metres.
	var primitive:=BoxMesh.new();primitive.size=size
	var arrays:Array=primitive.get_mesh_arrays()
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv:=PackedVector2Array();uv.resize(vertices.size())
	for i:int in vertices.size():
		var point:Vector3=vertices[i];var normal:Vector3=normals[i]
		if absf(normal.x)>0.5:uv[i]=Vector2(point.z*signf(normal.x),-point.y)/tile_meters
		elif absf(normal.y)>0.5:uv[i]=Vector2(point.x,point.z*signf(normal.y))/tile_meters
		else:uv[i]=Vector2(point.x*signf(normal.z),-point.y)/tile_meters
	arrays[Mesh.ARRAY_TEX_UV]=uv
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
static func box(parent:Node3D,position:Vector3,size:Vector3,surface:String)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.material_override=material(surface)
	node.mesh=metric_box(size,float(node.material_override.get_meta("tile_meters",2.0)));node.position=position
	parent.add_child(node);return node
static func create(kind:String)->Node3D:
	if kind in ["club","bow"]:
		var weapon := Node3D.new()
		if kind == "club":
			box(weapon,Vector3(0,0.22,0),Vector3(.085,.63,.08),"wood")
			box(weapon,Vector3(0,.47,0),Vector3(.14,.32,.13),"wood")
		else:
			box(weapon,Vector3(0,0,0),Vector3(.065,.35,.065),"wood")
			for side: float in [-1.0,1.0]:
				var limb := box(weapon,Vector3(-.065,.27 * side,0),Vector3(.045,.29,.045),"wood")
				limb.rotation.z = side * .48
			box(weapon,Vector3(-.13,0,0),Vector3(.013,.76,.013),"metal")
		return weapon
	if kind not in ["salvaged_axe","hammer","hand_saw","shovel","pickaxe"]:return null
	var root:=Node3D.new();root.name="HeldTool"
	root.set_meta("tool_kind",kind);root.set_meta("grip_point",Vector3.ZERO)
	root.set_meta("contact_point",CONTACTS[kind].point);root.set_meta("contact_normal",CONTACTS[kind].normal)
	var length:float=0.56 if kind in ["shovel","pickaxe"] else 0.43
	box(root,Vector3(0,0.08,0),Vector3(0.045,length,0.05),"wood")
	match kind:
		"hammer":
			box(root,Vector3(0,0.28,0),Vector3(0.25,0.1,0.09),"metal")
			box(root,Vector3(-0.12,0.25,0),Vector3(0.045,0.1,0.07),"metal")
		"salvaged_axe":
			box(root,Vector3(0.08,0.25,0),Vector3(0.2,0.13,0.055),"metal")
			box(root,Vector3(0.19,0.25,0),Vector3(0.04,0.19,0.025),"metal")
		"hand_saw":
			box(root,Vector3(0.18,0.12,0),Vector3(0.35,0.13,0.025),"metal")
			for i:int in 6:box(root,Vector3(0.045+i*0.055,0.04,0),Vector3(0.025,0.035,0.025),"metal")
		"shovel":
			box(root,Vector3(0,0.43,0),Vector3(0.18,0.2,0.045),"metal")
			box(root,Vector3(0,0.54,-0.025),Vector3(0.16,0.045,0.06),"metal")
		"pickaxe":
			box(root,Vector3(0,0.39,0),Vector3(0.37,0.065,0.07),"metal")
			box(root,Vector3(-0.19,0.36,0),Vector3(0.05,0.1,0.045),"metal")
	return root
