extends RefCounted
## Existing GLBs via native loader. Cached meshes/materials; no collision truth.
const MANIFEST="res://data/world/ecology/models.json"
const Quality=preload("res://scripts/environment/environment_quality.gd")
var _rows:Dictionary={}
var _parts:Dictionary={}
var _bounds:Dictionary={}
var failures:Array=[]
var quality:=Quality.new()
var _quality_parts:Dictionary={}
var quality_triangles:Dictionary={}

func _init()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for row:Dictionary in source.models:_rows[row.id]=row

func parts(id:String)->Array:
	if _parts.has(id):return _parts[id]
	if not _rows.has(id):failures.append(id);return []
	var path:String=_rows[id].resource
	var scene:Node3D
	# Imported resources in A's next native package; direct native GLTF parsing
	# covers pre-import domain checks without running a second editor/importer.
	if FileAccess.file_exists(path+".import") and ResourceLoader.exists(path):
		var packed:Variant=load(path)
		if packed is PackedScene:scene=packed.instantiate()
	if scene==null:
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		if document.append_from_buffer(FileAccess.get_file_as_bytes(path),path.get_base_dir(),state)!=OK:failures.append(id);return []
		scene=document.generate_scene(state)
	if scene==null:failures.append(id);return []
	var rows:Array=[];_collect(scene,Transform3D.IDENTITY,rows)
	var bounds:=AABB();var first:=true
	for row:Dictionary in rows:
		var box:AABB=row.transform*row.mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
	scene.free();_parts[id]=rows;_bounds[id]=bounds
	return rows

func bounds(id:String)->AABB:
	parts(id)
	return _bounds.get(id,AABB())

func _collect(node:Node,parent:Transform3D,rows:Array)->void:
	var transform:Transform3D=parent*(node.transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D and node.mesh!=null:
		var mesh:Mesh=node.mesh.duplicate()
		for i in mesh.get_surface_count():
			var original:Material=node.get_active_material(i)
			if original is StandardMaterial3D:
				var material:StandardMaterial3D=original.duplicate()
				material.roughness=0.95
				material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if material.albedo_texture!=null:
					var image:Image=material.albedo_texture.get_image()
					if image!=null and not image.has_mipmaps():image.generate_mipmaps();material.albedo_texture=ImageTexture.create_from_image(image)
				mesh.surface_set_material(i,material)
		rows.append({"mesh":mesh,"transform":transform})
	for child:Node in node.get_children():_collect(child,transform,rows)

func instance(id:String,target_height:float,yaw:float,surface_version:int=0,variant:int=0)->Node3D:
	var root:=Node3D.new();var items:Array=quality_parts(id,target_height,variant) if surface_version==1 else parts(id)
	var box:=bounds(id);var scale:float=target_height/maxf(box.size.y,0.001)
	root.rotation.y=yaw;root.scale=Vector3.ONE*scale
	root.set_meta("existing_model",id)
	root.set_meta("quality_surface_version",surface_version)
	for row:Dictionary in items:
		var mesh:=MeshInstance3D.new();mesh.mesh=row.mesh
		mesh.transform=Transform3D(Basis.IDENTITY,Vector3(0,-box.position.y,0))*row.transform
		root.add_child(mesh)
	return root

func quality_parts(id:String,height:float,variant:int=0)->Array:
	var key:=id+":"+str(height)+":"+str(variant%2)
	if _quality_parts.has(key):return _quality_parts[key]
	if id not in ["broadleaf_tree","conifer_tree","dead_tree","tree_stump"]:return parts(id)
	var result:Array=[];var counts:Dictionary={};var scale:float=height/maxf(bounds(id).size.y,0.001)
	# Exact existing local atlas contract, verified against finalize_living_pack.
	# All three vertices of each source triangle must occupy the SAME 128px tile.
	var columns:int=1 if id=="dead_tree" else 2
	var rows:int=2 if id in ["broadleaf_tree","conifer_tree"] else 1
	for part:Dictionary in parts(id):
		var groups:Dictionary={};var source:Mesh=part.mesh
		for surface in source.get_surface_count():
			var a:Array=source.surface_get_arrays(surface)
			var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=a[Mesh.ARRAY_NORMAL];var uv:PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
			var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			for start in range(0,indices.size(),3):
				var tile:=Vector2i(floori(uv[indices[start]].x*columns),floori(uv[indices[start]].y*rows))
				var valid:=true
				for j in 3:valid=valid and tile==Vector2i(floori(uv[indices[start+j]].x*columns),floori(uv[indices[start+j]].y*rows))
				if not valid:failures.append("mixed-atlas-triangle:"+id);return parts(id)
				var bark:String={"broadleaf_tree":"v09_broadleaf_bark","conifer_tree":"v10_conifer_bark","dead_tree":"v11_dead_bark","tree_stump":"v09_broadleaf_bark"}[id]
				var texture:String=bark
				if id=="tree_stump" and tile.x==1:texture="v12_cut_endgrain"
				elif tile!=Vector2i.ZERO:
					var canopy_variant:int=(variant+(1 if tile.y==1 else 0))%2
					texture=(["v15_conifer_canopy_a","v16_conifer_canopy_b"] if id=="conifer_tree" else ["v13_broadleaf_canopy_a","v14_broadleaf_canopy_b"])[canopy_variant]
				if not groups.has(texture):groups[texture]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"indices":PackedInt32Array()}
				var g:Dictionary=groups[texture]
				for j in 3:
					var index:int=indices[start+j];var p:Vector3=part.transform*vertices[index];var normal:Vector3=part.transform.basis*normals[index]
					var metre_uv:=Vector2(p.x,p.z) if absf(normal.y)>0.5 else Vector2(p.z if absf(normal.x)>0.5 else p.x,p.y)
					if texture=="v12_cut_endgrain":metre_uv=Vector2(uv[index].x*columns-tile.x,uv[index].y*rows-tile.y)
					else:metre_uv*=scale
					g.indices.append(g.vertices.size());g.vertices.append(vertices[index]);g.normals.append(normals[index]);g.uv.append(metre_uv)
				counts[texture]=int(counts.get(texture,0))+1
		var mesh:=ArrayMesh.new()
		for texture:String in groups:
			var g:Dictionary=groups[texture];var a:Array=[];a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX]=g.vertices;a[Mesh.ARRAY_NORMAL]=g.normals;a[Mesh.ARRAY_TEX_UV]=g.uv;a[Mesh.ARRAY_INDEX]=g.indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);mesh.surface_set_material(mesh.get_surface_count()-1,quality.material(texture))
		result.append({"mesh":mesh,"transform":part.transform})
	_quality_parts[key]=result;quality_triangles[key]=counts
	return result

func patch_parts(id:String,width:float)->Array:
	var items:Array=parts(id);var box:=bounds(id)
	var scale:float=width/maxf(maxf(box.size.x,box.size.z),0.001)
	var center:=box.get_center()
	var fit:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale),Vector3(-center.x*scale,-box.position.y*scale,-center.z*scale))
	var result:Array=[]
	for row:Dictionary in items:result.append({"mesh":row.mesh,"transform":fit*row.transform})
	return result
