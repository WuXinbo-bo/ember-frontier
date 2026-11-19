extends "res://scripts/environment/environment_view.gd"
## Frozen only the measured ground loop; other environment behavior stays shared.
func rebuild_ground(key: String) -> void:
	_rebuild_contact(key)
	if _fields.has(key):
		var old_field:Node3D=_fields[key];remove_child(old_field);old_field.queue_free();_fields.erase(key)
	var field:MeshInstance3D=Fields.build(world,key,ecology_models.quality)
	if field!=null:add_child(field);_fields[key]=field
	if _ground.has(key):
		var old: Node3D = _ground[key]
		remove_child(old)
		old.queue_free()
		_ground.erase(key)
	var c: Dictionary = world.chunk(key)
	if c.is_empty() or not c.resident: return
	if not c.cells.has(1): return
	var n := int(world.config().chunkCells)
	var s := float(world.config().cellSize)
	var groups := {}
	for index in c.cells.size():
		if c.cells[index] != 1: continue
		var x: int = int(c.coord.x)*n+index%n
		var z: int = int(c.coord.z)*n+(int(index)/n)%n
		var y: int = int(c.coord.y)*n+int(index)/(n*n)
		if not world.is_cell_known(x,y+1,z) or world.cell_at(x,y+1,z)!=0: continue
		for d in [Vector3i(-1,0,0),Vector3i(1,0,0),Vector3i(0,0,-1),Vector3i(0,0,1)]:
			var neighbor_material: int = world.cell_at(x+d.x,y,z+d.z)
			if neighbor_material not in [2,4,6] or not world.is_cell_resident(x+d.x,y,z+d.z) or not world.is_cell_known(x+d.x,y+1,z+d.z) or world.cell_at(x+d.x,y+1,z+d.z)!=0: continue
			if not groups.has(neighbor_material):
				groups[neighbor_material]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uvs":PackedVector2Array(),"strip_uvs":PackedVector2Array(),"indices":PackedInt32Array()}
			var g: Dictionary = groups[neighbor_material]
			var center := Vector3((x+0.5)*s,(y+1)*s+0.006,(z+0.5)*s)
			var toward := Vector3(d.x,0,d.z)
			var along := Vector3(d.z,0,-d.x)
			center += toward*s*0.5
			var first: int = g.vertices.size()
			# The original strip covers 1.6 x .65 metres, resting over two
			# same-height exposed cells. Do not squeeze it into .13 metres.
			var corners := [center-along*s*0.5-toward*0.325,center+along*s*0.5-toward*0.325,center+along*s*0.5+toward*0.325,center-along*s*0.5+toward*0.325]
			for i in 4:
				g.vertices.append(corners[i])
				g.normals.append(Vector3.UP)
				g.uvs.append(Vector2(corners[i].x,corners[i].z))
				# Continue the original strip along the whole road, rather than
				# restarting its leftmost half-metre on every individual cell.
				var along_m: float = corners[i].dot(along)
				g.strip_uvs.append(Vector2(along_m/1.6,0.0 if i<2 else 1.0))
			for i in [0,1,2,0,2,3]: g.indices.append(first+i)
	if groups.is_empty(): return
	var mesh := ArrayMesh.new()
	# Keep one instance per chunk; surfaces distinguish actual earth materials,
	# not a single brown decal painted over every kind of terrain.
	var material_ids: Array = groups.keys();material_ids.sort()
	for material_id in material_ids:
		var g: Dictionary = groups[material_id]
		var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=g.vertices;arrays[Mesh.ARRAY_NORMAL]=g.normals
		arrays[Mesh.ARRAY_TEX_UV]=g.uvs;arrays[Mesh.ARRAY_TEX_UV2]=g.strip_uvs;arrays[Mesh.ARRAY_INDEX]=g.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,materials.shoulder_material(material_id))
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta("terrain_chunk",key)
	visual.set_meta("shoulder_materials",material_ids)
	add_child(visual)
	_ground[key] = visual

