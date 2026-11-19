extends RefCounted
## Exact staged source images, metre UV and native alpha/depth. No world facts.
const MANIFEST="res://data/world/ecology/quality-v1/manifest.json"
var rows:Dictionary={}
var _materials:Dictionary={}
var _cutouts:Dictionary={}
var failures:Array=[]
func _init()->void:
	var doc:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for row:Dictionary in doc.assets:rows[row.id]=row
func material(id:String)->StandardMaterial3D:
	if _materials.has(id):return _materials[id]
	var mat:=StandardMaterial3D.new();mat.resource_name="C:quality:"+id
	mat.roughness=0.96;mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var row:Dictionary=rows.get(id,{})
	if row.is_empty():failures.append(id);return mat
	var texture:Texture2D
	if ResourceLoader.exists(row.resource):texture=load(row.resource)
	var source:Image=texture.get_image() if texture!=null else Image.load_from_file(row.resource)
	if source!=null:
		if not source.has_mipmaps():source.generate_mipmaps()
		mat.albedo_texture=ImageTexture.create_from_image(source)
	else:failures.append(id)
	mat.texture_repeat=false
	if row.tiling is Array:mat.texture_repeat="X" in row.tiling and "Y" in row.tiling
	elif row.tiling is bool:mat.texture_repeat=row.tiling
	if row.alpha:
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold=0.4;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	elif mat.texture_repeat:
		mat.uv1_scale=Vector3(1.0/float(row.physical_m[0]),1.0/float(row.physical_m[1]),1)
	_materials[id]=mat;return mat
func cutout_parts(id:String,width:float)->Array:
	var key:=id+":"+str(width)
	if _cutouts.has(key):return _cutouts[key]
	var row:Dictionary=rows.get(id,{})
	if not row.get("alpha",false):failures.append(id);return []
	# Art's visible bbox and bottom baseline are different from full canvas.
	# Retain the source aspect and the transparent margin below the true feet.
	var scale:float=width/float(row.visible_size_m[0])
	var w:float=float(row.full_canvas_m[0])*scale;var h:float=float(row.full_canvas_m[1])*scale
	var bottom:float=(float(row.pivot[1])-1.0)*h;var top:float=float(row.pivot[1])*h
	var vertices:=PackedVector3Array([Vector3(-w/2,bottom,0),Vector3(w/2,bottom,0),Vector3(w/2,top,0),Vector3(-w/2,top,0),Vector3(0,bottom,-w/2),Vector3(0,bottom,w/2),Vector3(0,top,w/2),Vector3(0,top,-w/2)])
	var uv:=PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]);uv.append_array(uv.duplicate())
	var a:Array=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=vertices;a[Mesh.ARRAY_TEX_UV]=uv
	a[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.LEFT,Vector3.LEFT,Vector3.LEFT,Vector3.LEFT])
	a[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3,4,5,6,4,6,7])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);mesh.surface_set_material(0,material(id))
	_cutouts[key]=[{"mesh":mesh,"transform":Transform3D.IDENTITY}]
	return _cutouts[key]
