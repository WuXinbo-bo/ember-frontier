extends RefCounted
## Retain the original GLB body/legs/bands/UVs. Only the verified 24 side
## triangles receive the authored new metre skin on a derived mesh copy.

static func apply(root:Node,material:StandardMaterial3D)->void:
	if root is MeshInstance3D and root.mesh!=null:
		var source:Mesh=root.mesh;var replacement:=ArrayMesh.new();var selected:=0
		for surface:int in source.get_surface_count():
			var arrays:Array=source.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if indices==null or indices.is_empty():
				indices=PackedInt32Array()
				for i:int in vertices.size():indices.append(i)
			var retained:=PackedInt32Array();var v:=PackedVector3Array();var n:=PackedVector3Array();var uv:=PackedVector2Array();var ix:=PackedInt32Array()
			for offset:int in range(0,indices.size(),3):
				var triangle:Array=[vertices[indices[offset]],vertices[indices[offset+1]],vertices[indices[offset+2]]]
				var low:=INF;var high:=-INF;var radius:=0.0
				for p:Vector3 in triangle:low=minf(low,p.y);high=maxf(high,p.y);radius=maxf(radius,Vector2(p.x,p.z).length())
				if absf(low-0.45)>0.00001 or absf(high-1.55)>0.00001 or absf(radius-0.62)>0.00001:
					for k:int in 3:retained.append(indices[offset+k])
					continue
				selected+=1
				var us:Array=[]
				for p:Vector3 in triangle:us.append(atan2(p.z,p.x))
				if float(us.max())-float(us.min())>PI:
					for k:int in 3:
						if us[k]<0:us[k]+=TAU
				for k:int in 3:
					v.append(triangle[k]);n.append(normals[indices[offset+k]]);uv.append(Vector2(float(us[k])*0.62,triangle[k].y));ix.append(ix.size())
			var old:=arrays.duplicate();old[Mesh.ARRAY_INDEX]=retained
			replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,old)
			replacement.surface_set_material(replacement.get_surface_count()-1,root.get_active_material(surface))
			if not v.is_empty():
				var fresh:Array=[];fresh.resize(Mesh.ARRAY_MAX)
				fresh[Mesh.ARRAY_VERTEX]=v;fresh[Mesh.ARRAY_NORMAL]=n;fresh[Mesh.ARRAY_TEX_UV]=uv;fresh[Mesh.ARRAY_INDEX]=ix
				replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,fresh)
				replacement.surface_set_material(replacement.get_surface_count()-1,material)
		# This exact existing source has 24 side triangles. Future asset shape
		# changes must be explicitly re-adapted, not paint arbitrary components.
		if selected==24:
			root.mesh=replacement;root.set_meta("tank_retiled_triangles",selected)
			for i:int in replacement.get_surface_count():root.set_surface_override_material(i,null)
	for child:Node in root.get_children():apply(child,material)
