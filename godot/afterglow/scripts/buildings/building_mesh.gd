extends RefCounted
## Small native ArrayMesh assembler, metre-scaled UVs and original atlas cells.
var groups: Dictionary = {}

func quad(vertices: Array, normal: Vector3, transform: Transform3D, material: String, cell: int = -1, uv_rect:Rect2=Rect2(0,0,1,1)) -> void:
	if not groups.has(material):groups[material]={"v":PackedVector3Array(),"n":PackedVector3Array(),"uv":PackedVector2Array(),"i":PackedInt32Array()}
	var g:Dictionary=groups[material];var offset:int=g.v.size()
	for n in range(4):
		g.v.append(transform*vertices[n]);g.n.append((transform.basis*normal).normalized())
		var uv:Vector2=[Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][n]
		uv=uv_rect.position+uv*uv_rect.size
		if cell>=0:uv=(Vector2(posmod(cell,4),floori(float(cell)/4))+Vector2.ONE*(8.0/256.0)+uv*(240.0/256.0))/4.0
		g.uv.append(uv)
	for n in [0,1,2,0,2,3]:g.i.append(offset+n)

func box(bounds: AABB, transform: Transform3D, material: String, meters: float = 2.0, cell: int = -1, top_material: String = "", top_meters: float = 2.0, uv_meters:Vector2=Vector2.ZERO) -> void:
	var lo := bounds.position; var hi := bounds.end
	var faces: Array = [
		[Vector3.UP, [Vector3(lo.x,hi.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,hi.y,hi.z),Vector3(lo.x,hi.y,hi.z)], Vector2(bounds.size.x,bounds.size.z)],
		[Vector3.DOWN, [Vector3(lo.x,lo.y,hi.z),Vector3(hi.x,lo.y,hi.z),Vector3(hi.x,lo.y,lo.z),Vector3(lo.x,lo.y,lo.z)], Vector2(bounds.size.x,bounds.size.z)],
		[Vector3.RIGHT, [Vector3(hi.x,lo.y,lo.z),Vector3(hi.x,lo.y,hi.z),Vector3(hi.x,hi.y,hi.z),Vector3(hi.x,hi.y,lo.z)], Vector2(bounds.size.z,bounds.size.y)],
		[Vector3.LEFT, [Vector3(lo.x,lo.y,hi.z),Vector3(lo.x,lo.y,lo.z),Vector3(lo.x,hi.y,lo.z),Vector3(lo.x,hi.y,hi.z)], Vector2(bounds.size.z,bounds.size.y)],
		[Vector3.BACK, [Vector3(hi.x,lo.y,hi.z),Vector3(lo.x,lo.y,hi.z),Vector3(lo.x,hi.y,hi.z),Vector3(hi.x,hi.y,hi.z)], Vector2(bounds.size.x,bounds.size.y)],
		[Vector3.FORWARD, [Vector3(lo.x,lo.y,lo.z),Vector3(hi.x,lo.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(lo.x,hi.y,lo.z)], Vector2(bounds.size.x,bounds.size.y)]]
	for face in faces:
		var use_top: bool = face[0].y > 0.5 and not top_material.is_empty()
		var selected: String = top_material if use_top else material
		var scale: float = top_meters if use_top else meters
		if not groups.has(selected): groups[selected] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
		var g: Dictionary = groups[selected]
		var offset: int = g.v.size()
		for n in range(4):
			g.v.append(transform * face[1][n]); g.n.append((transform.basis * face[0]).normalized())
			var uv: Vector2 = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)][n]
			if cell >= 0: uv = (Vector2(posmod(cell,4),floori(float(cell)/4)) + Vector2.ONE*(8.0/256.0) + uv*(240.0/256.0)) / 4.0
			else: uv *= face[2] / (uv_meters if not use_top and uv_meters.x>0 and uv_meters.y>0 else Vector2(scale,scale))
			g.uv.append(uv)
		for n in [0,1,2,0,2,3]: g.i.append(offset+n)

func mesh(materials: Dictionary) -> ArrayMesh:
	var result := ArrayMesh.new()
	for key in groups:
		var g: Dictionary = groups[key]
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=g.v; arrays[Mesh.ARRAY_NORMAL]=g.n; arrays[Mesh.ARRAY_TEX_UV]=g.uv; arrays[Mesh.ARRAY_INDEX]=g.i
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,materials.get(key))
	return result
