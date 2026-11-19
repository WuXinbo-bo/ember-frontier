extends Node3D
## Tree/trunk/shrub/ground layers are derived from real live entities and cells.
const Data = preload("res://scripts/world/world_data.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
var world: RefCounted
var materials: RefCounted
var _roots: Dictionary = {}
var _signatures: Dictionary = {}
var rebuilt: int = 0
var _ground: Dictionary = {}

func configure(context: Dictionary) -> void:
	world = context.world
	materials = context.get("materials",Materials.new())
	sync()

func _box(parent: Node3D, position: Vector3, size: Vector3, material_id: String, cell: int = -1) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh: Mesh = box
	if cell >= 0 or material_id == "bark":
		var arrays := box.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if cell >= 0:
			for i in uv.size(): uv[i] = (Vector2(cell%4,cell/4)*256.0+Vector2(8,8)+uv[i]*240.0)/1024.0
		else:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in uv.size():
				var p := vertices[i]+position
				uv[i]=Vector2(p.x,p.z) if absf(normals[i].y)>0.5 else Vector2(p.z if absf(normals[i].x)>0.5 else p.x,p.y)
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var native := ArrayMesh.new()
		native.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh = native
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = materials.material(material_id)
	item.position = position
	parent.add_child(item)
	return item

func _clear(id: String) -> void:
	if not _roots.has(id): return
	var node: Node3D = _roots[id]
	remove_child(node)
	node.queue_free()
	_roots.erase(id)
	_signatures.erase(id)

func _grounded(p: Vector3, size: Vector2, required_material: int = -1) -> bool:
	# Check the entire footprint, not only its centre. These are disposable
	# decorations: they disappear over a hole/cold chunk instead of floating.
	var n := int(world.config().chunkCells)
	var s := float(world.config().cellSize)
	var y := floori((p.y-0.001)/s)
	if absf((y+1)*s-p.y)>0.001: return false
	for z in range(floori((p.z-size.y/2.0+0.00001)/s),floori((p.z+size.y/2.0-0.00001)/s)+1):
		for x in range(floori((p.x-size.x/2.0+0.00001)/s),floori((p.x+size.x/2.0-0.00001)/s)+1):
			if not world.is_cell_known(x,y,z) or not world.is_cell_known(x,y+1,z): return false
			if not world.is_cell_resident(x,y,z): return false
			var material: int = world.cell_at(x,y,z)
			if material==0 or (required_material>=0 and material!=required_material) or world.cell_at(x,y+1,z)!=0: return false
	return true

func sync() -> void:
	if world == null: return
	var seen := {}
	var n := int(world.config().chunkCells)
	var s := float(world.config().cellSize)
	for e in world.entities():
		if e.kind != "tree": continue
		var p := Vector3(e.position.x,e.position.y,e.position.z)
		var cell := Vector3i(floori(p.x/s),floori((p.y-0.01)/s),floori(p.z/s))
		var chunk: Dictionary = world.chunk(Data.key(Data.cell_chunk(cell,n)))
		var ground: Variant = world.surface_height(p.x,p.z)
		if not chunk.get("resident",false) or ground == null or absf(float(ground)-p.y) > 0.01: continue
		seen[e.id] = true
		var offsets := [Vector3(-1.3,0,-0.8),Vector3(1.35,0,0.9)]
		var leaf_ground := _grounded(p,Vector2(1.5,1.5))
		var shrub_ground: Array = []
		for offset in offsets: shrub_ground.append(_grounded(p+offset,Vector2(0.8,0.7),1))
		var root_offsets := [Vector3(-0.23,0,0),Vector3(0.23,0,0),Vector3(0,0,0.23)]
		var root_ground: Array = []
		for offset in root_offsets: root_ground.append(_grounded(p+offset,Vector2(0.28,0.24)))
		var signature := str([e,ground,leaf_ground,shrub_ground,root_ground])
		if _signatures.get(e.id) == signature: continue
		_clear(e.id)
		var root := Node3D.new()
		root.name = str(e.id).validate_node_name()
		root.set_meta("world_entity_id",e.id)
		root.position = p
		add_child(root)
		_roots[e.id] = root
		_signatures[e.id] = signature
		rebuilt += 1
		var standing: bool = e.data.get("harvest",{}).get("phase","standing") == "standing" and e.data.get("phase","") != "stump"
		_box(root,Vector3(0,0.16,0),Vector3(0.46,0.32,0.46),"bark")
		if standing:
			var variant := str(e.id).sha256_text().substr(0,8).hex_to_int()
			var spread := 0.9+float(variant%4)*0.08
			_box(root,Vector3(0,1.4,0),Vector3(0.34,2.8,0.34),"bark")
			var lower := _box(root,Vector3(-0.25,2.8,-0.08),Vector3(1.85*spread,1.1,1.65),"foliage_atlas",variant%4)
			lower.rotation.y = float(variant%4)*PI/2.0
			var middle := _box(root,Vector3(0.36,3.45,0.12),Vector3(1.45,1.0,1.35*spread),"foliage_atlas",(variant+1)%4)
			middle.rotation.y = float((variant/4)%4)*PI/2.0
			_box(root,Vector3(-0.15,3.95,-0.12),Vector3(1.0,0.65,1.0),"foliage_atlas",(variant+2)%4)
			var branch := _box(root,Vector3(-0.25,2.5,-0.08),Vector3(0.7,0.18,0.2),"bark")
			branch.rotation.z = -0.45
			if leaf_ground:
				var leaf := MeshInstance3D.new()
				leaf.name = "GroundLeaves"
				var plane := PlaneMesh.new()
				plane.size = Vector2(1.5,1.5)
				leaf.mesh = plane
				leaf.material_override = materials.material("leaves")
				leaf.position.y = 0.008
				root.add_child(leaf)
			for i in offsets.size():
				if shrub_ground[i]:
					# Two existing atlas cells and two real volume silhouettes: a
					# taller shrub and lower/sparser ground cover. Keep the original
					# conservative footprint check, node count and no resource yield.
					var size := Vector3(0.8,0.6,0.7) if i==0 else Vector3(0.58,0.24,0.46)
					var shrub := _box(root,offsets[i]+Vector3(0,size.y*0.5,0),size,"foliage_atlas",8+i)
					shrub.rotation.y = float(variant%2)*PI
					shrub.name = "GroundShrub_"+str(i)
			var body := StaticBody3D.new()
			body.set_meta("world_entity_id",e.id)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.7,4.0,0.7)
			shape.shape = box
			shape.position.y = 2.0
			body.add_child(shape)
			root.add_child(body)
		for i in root_offsets.size():
			if root_ground[i]: _box(root,root_offsets[i]+Vector3(0,0.08,0),Vector3(0.28,0.16,0.24),"bark")
	for id in _roots.keys():
		if not seen.has(id): _clear(id)

func on_world_changed(_changes: Dictionary) -> void: sync()

func rebuild_ground(key: String) -> void:
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
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in c.cells.size():
		if c.cells[index] != 1: continue
		var x: int = int(c.coord.x)*n+index%n
		var z: int = int(c.coord.z)*n+(int(index)/n)%n
		var y: int = int(c.coord.y)*n+int(index)/(n*n)
		if not world.is_cell_known(x,y+1,z) or world.cell_at(x,y+1,z)!=0: continue
		for d in [Vector3i(-1,0,0),Vector3i(1,0,0),Vector3i(0,0,-1),Vector3i(0,0,1)]:
			if world.cell_at(x+d.x,y,z+d.z) not in [2,4,6] or not world.is_cell_known(x+d.x,y+1,z+d.z) or world.cell_at(x+d.x,y+1,z+d.z)!=0: continue
			var center := Vector3((x+0.5)*s,(y+1)*s+0.006,(z+0.5)*s)
			var toward := Vector3(d.x,0,d.z)
			var along := Vector3(d.z,0,-d.x)
			center += toward*s*0.5
			var first := vertices.size()
			# The original strip covers 1.6 x .65 metres, resting over two
			# same-height exposed cells. Do not squeeze it into .13 metres.
			var corners := [center-along*s*0.5-toward*0.325,center+along*s*0.5-toward*0.325,center+along*s*0.5+toward*0.325,center-along*s*0.5+toward*0.325]
			for i in 4:
				vertices.append(corners[i])
				normals.append(Vector3.UP)
				# Continue the original strip along the whole road, rather than
				# restarting its leftmost half-metre on every individual cell.
				var along_m: float = corners[i].dot(along)
				uvs.append(Vector2(along_m/1.6,0.0 if i<2 else 1.0))
			for i in [0,1,2,0,2,3]: indices.append(first+i)
	if vertices.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = materials.material("grass_edge")
	visual.set_meta("terrain_chunk",key)
	add_child(visual)
	_ground[key] = visual

func statistics() -> Dictionary:
	return {"tree_roots":_roots.size(),"ground_transition_chunks":_ground.size(),"rebuilt":rebuilt,"missing_materials":materials.missing.duplicate()}
