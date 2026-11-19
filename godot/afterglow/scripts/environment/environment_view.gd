extends Node3D
## Tree/trunk/shrub/ground layers are derived from real live entities and cells.
const Data = preload("res://scripts/world/world_data.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
const Contacts = preload("res://scripts/environment/ground_contacts.gd")
const EcologyModels = preload("res://scripts/environment/ecology_models.gd")
const Fields=preload("res://scripts/environment/field_surfaces.gd")
const LandUseCover=preload("res://scripts/environment/land_use_cover.gd")
const SupportSampler=preload("res://scripts/environment/support_sampler.gd")
var _support_sampler:RefCounted
var world: RefCounted
var region_fringe_hint:Callable
var materials: RefCounted
var _roots: Dictionary = {}
var _signatures: Dictionary = {}
var rebuilt: int = 0
var _ground: Dictionary = {}
var _contacts: Dictionary = {}
var contacts := Contacts.new()
var sync_passes := 0
var ecology_models:=EcologyModels.new()
var _ecology:Dictionary={}
var _ecology_signatures:Dictionary={}
var _cover_meshes:Dictionary={}
var _ecology_patch_index:Dictionary={}
var _ecology_support_index:Dictionary={}
var _ecology_patch_order:Dictionary={}
var _ecology_layout_dirty:=true
var _generation_ecology_dirty: Dictionary = {}
var _generation_ecology_frame := -1
var _generation_ecology_batches: Dictionary = {}
var _generation_ecology_batch_frame := -1
var _generation_tree_frame := -1
var _generation_trees: Dictionary = {}
var _ecology_region_count:=-1
var _indexed_regions:Dictionary={}
var _new_regions:Dictionary={}
var _full_ecology_reindex:=false
var _derived_entities:Array=[]
var _entities_by_id:Dictionary={}
var _projection_ready:=false
var _projection_revision:=-1
var _ecology_blocker_index:Dictionary={}
var _presentation_layouts:Dictionary={}
var _deferred_cover_regions:Dictionary={}
var _deferred_cover_chunks:Dictionary={}
var presentation_layout_builds:=0
var _last_ecology_candidates:=0
var _fields:Dictionary={}
var _tree_columns:Dictionary={}

func configure(context: Dictionary) -> void:
	world = context.world
	_ecology_layout_dirty=true;_indexed_regions.clear();_new_regions.clear();_full_ecology_reindex=false
	_derived_entities.clear();_entities_by_id.clear();_projection_ready=false
	_ecology_blocker_index.clear()
	_presentation_layouts.clear();presentation_layout_builds=0
	materials = context.materials if context.has("materials") else Materials.new()
	ecology_models.quality=materials.quality
	contacts.pitch = float(world.config().cellSize)*int(world.config().chunkCells)
	sync()

func _low_cover(parent: Node3D,position: Vector3,cell: int,yaw: float) -> MeshInstance3D:
	# Actual alpha bounds from A06. Crop inside the protected atlas cell, use
	# the common row232 baseline, and retain source aspect (no stretched blades).
	var row: Dictionary = materials.manifest()["low_cover_atlas"]
	var b: Array = row.alpha_bboxes[cell]
	var width := 0.49
	var height := width*float(b[3]-b[1])/float(b[2]-b[0])
	var vertices := PackedVector3Array([
		Vector3(-width/2,0,0),Vector3(width/2,0,0),Vector3(width/2,height,0),Vector3(-width/2,height,0),
		Vector3(0,0,-width/2),Vector3(0,0,width/2),Vector3(0,height,width/2),Vector3(0,height,-width/2)])
	var offset := Vector2(cell%2,cell/2)*256.0
	var low := (offset+Vector2(b[0],b[3]))/512.0
	var high := (offset+Vector2(b[2],b[1]))/512.0
	var uv := PackedVector2Array([Vector2(low.x,low.y),Vector2(high.x,low.y),Vector2(high.x,high.y),Vector2(low.x,high.y)])
	uv.append_array(uv.duplicate())
	var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.LEFT,Vector3.LEFT,Vector3.LEFT,Vector3.LEFT])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3,4,5,6,4,6,7])
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var item := MeshInstance3D.new();item.mesh=mesh;item.material_override=materials.material("low_cover_atlas")
	item.position=position;item.rotation.y=yaw
	item.set_meta("atlas_cell",cell);item.set_meta("atlas_baseline_px",232)
	parent.add_child(item)
	return item

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
	if _support_sampler!=null:return _support_sampler.grounded(p,size,required_material)
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

func sync(update_foundations: bool=true,ecology_chunks:Array=[],force_ecology:bool=true) -> void:
	if world == null: return
	sync_passes+=1
	var all_trees:bool=update_foundations or not _projection_ready
	if all_trees or ecology_chunks.is_empty():
		_generation_trees.clear()
		_generation_tree_frame = -1
	# This entire refresh is synchronous (no await/worker). Reuse detached
	# public chunks only for this call; discard before the next authority edit.
	_support_sampler=SupportSampler.new(world)
	# Full/unknown callers preserve the original synchronous refresh. This
	# detached projection is never a source for gameplay or world mutation.
	if update_foundations or not _projection_ready:
		_derived_entities=world.entities();_entities_by_id.clear()
		for e:Dictionary in _derived_entities:_entities_by_id[e.id]=e
		_projection_ready=true
		_index_ecology_blockers(_derived_entities)
		_index_tree_columns()
	if update_foundations:
		for key in contacts.update(_derived_entities):_rebuild_contact(str(key))
	if not all_trees and not ecology_chunks.is_empty():
		# Exact support still runs for every affected tree. A tree's leaves,
		# roots and shrubs fit within two metres of its anchor. The vertical
		# column is deliberately unbounded: an edit above/below may change the
		# surface-height query even when it misses the old support Y.
		var affected:Dictionary={}
		for key:String in ecology_chunks:
			var coord:Variant=Data.coord(key)
			if coord==null:
				for e:Dictionary in _derived_entities:
					if e.kind=="tree":affected[str(e.id)]=true
				break
			affected.merge(_tree_columns.get(Vector2i(coord.x,coord.z),{}))
		for id:String in affected:_sync_tree(_entities_by_id[id])
	else:
		var seen:Dictionary={}
		for e:Dictionary in _derived_entities:
			if e.kind!="tree":continue
			seen[e.id]=true;_sync_tree(e)
		for id in _roots.keys():
			if not seen.has(id):_clear(id)
	_sync_ecology(_derived_entities, _with_pending_ecology(ecology_chunks), force_ecology)
	_projection_revision=world.get_revision()
	_support_sampler=null

func _index_tree_columns()->void:
	_tree_columns.clear()
	var pitch:float=float(world.config().cellSize)*int(world.config().chunkCells)
	for e:Dictionary in _derived_entities:
		if e.kind!="tree":continue
		for z:int in range(floori((float(e.position.z)-2.0)/pitch),floori((float(e.position.z)+2.0)/pitch)+1):
			for x:int in range(floori((float(e.position.x)-2.0)/pitch),floori((float(e.position.x)+2.0)/pitch)+1):
				var key:=Vector2i(x,z)
				if not _tree_columns.has(key):_tree_columns[key]={}
				_tree_columns[key][str(e.id)]=true

func _sync_tree(e:Dictionary)->void:
	var config:Dictionary=_support_sampler.config if _support_sampler!=null else world.config()
	var n:int=int(config.chunkCells);var s:float=float(config.cellSize)
	var p := Vector3(e.position.x,e.position.y,e.position.z)
	var cell := Vector3i(floori(p.x/s),floori((p.y-0.01)/s),floori(p.z/s))
	# A cold tree cannot be mounted. Do not scan a cold, still-unpacked
	# column before rejecting it; warm trees keep every live support check.
	var resident:bool=_support_sampler.resident_cell(cell) if _support_sampler!=null else world.is_cell_resident(cell.x,cell.y,cell.z)
	if not resident:_clear(str(e.id));return
	var ground: Variant = _support_sampler.surface_height(p.x,p.z) if _support_sampler!=null else world.surface_height(p.x,p.z)
	if ground == null or absf(float(ground)-p.y) > 0.01:_clear(str(e.id));return
	var offsets := [Vector3(-1.3,0,-0.8),Vector3(1.35,0,0.9)]
	var leaf_ground := _grounded(p,Vector2(1.5,1.5))
	var shrub_ground: Array = []
	# Each patch follows the SAME authoritative surface, rather than assuming
	# the whole forest is at its tree's Y. Full footprint checks still reject
	# steps, holes, unknown/cold ground and changed material.
	for i in offsets.size():
		var q: Vector3=p+offsets[i]
		var height: Variant=_support_sampler.surface_height(q.x,q.z) if _support_sampler!=null else world.surface_height(q.x,q.z)
		if height!=null: offsets[i].y=float(height)-p.y
		shrub_ground.append(height!=null and _grounded(p+offsets[i],Vector2(0.8,0.7),1))
	var root_offsets := [Vector3(-0.23,0,0),Vector3(0.23,0,0),Vector3(0,0,0.23)]
	var root_ground: Array = []
	for offset in root_offsets: root_ground.append(_grounded(p+offset,Vector2(0.28,0.24)))
	# Entity rows here come from the detached presentation index. Compare the
	# complete row and every support result without formatting them as text.
	var signature := [e, ground, leaf_ground, offsets, shrub_ground, root_ground]
	if _signatures.get(e.id) == signature:return
	_clear(e.id)
	var root := Node3D.new()
	root.name = str(e.id).validate_node_name()
	root.set_meta("world_entity_id",e.id)
	root.position = p
	add_child(root)
	_roots[e.id] = root
	_signatures[e.id] = signature
	rebuilt += 1
	var standing: bool = e.data.get("harvest",{}).get("phase","standing") in ["standing","growing"] and e.data.get("phase","") != "stump"
	var appearance:Dictionary=e.data.get("appearance",{})
	if appearance.has("model"):
		var model_id:String=str(appearance.model) if standing else "tree_stump"
		root.add_child(ecology_models.instance(model_id,float(appearance.height) if standing else 0.32,float(appearance.yaw),int(appearance.get("surface_version",0)),int(appearance.get("surface_variant",0))))
	else:_box(root,Vector3(0,0.16,0),Vector3(0.46,0.32,0.46),"bark")
	if standing:
		var variant := str(e.id).sha256_text().substr(0,8).hex_to_int()
		var spread := 0.9+float(variant%4)*0.08
		if appearance.is_empty():
			# Preserve legacy rural-1/2 appearance and all existing evidence.
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
				# Keep the existing two patches and conservative footprint; A06
				# replaces only the low opaque box with two cutout planes.
				var shrub: MeshInstance3D
				if i==0:
					shrub=_box(root,offsets[i]+Vector3(0,0.3,0),Vector3(0.8,0.6,0.7),"foliage_atlas",8)
					shrub.rotation.y=float(variant%2)*PI
				else: shrub=_low_cover(root,offsets[i],variant%4,float((variant/4)%4)*PI/4.0)
				shrub.name = "GroundShrub_"+str(i)
		var body := StaticBody3D.new()
		body.set_meta("world_entity_id",e.id)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var tree_height:float=float(appearance.get("height",4.0))
		box.size = Vector3(0.7,tree_height,0.7)
		if e.data.has("ecology_id"):box.size=Vector3(float(e.bounds.max.x)-float(e.bounds.min.x),tree_height,float(e.bounds.max.z)-float(e.bounds.min.z))
		shape.shape = box
		shape.position.y = tree_height*0.5
		body.add_child(shape)
		root.add_child(body)
	for i in root_offsets.size():
		if root_ground[i]: _box(root,root_offsets[i]+Vector3(0,0.08,0),Vector3(0.28,0.16,0.24),"bark")

func _cover_parts(cell:int)->Array:
	if not _cover_meshes.has(cell):
		var temporary:=Node3D.new()
		var native:=_low_cover(temporary,Vector3.ZERO,cell,0.0)
		native.mesh.surface_set_material(0,native.material_override)
		_cover_meshes[cell]=native.mesh
		temporary.free()
	return [{"mesh":_cover_meshes[cell],"transform":Transform3D.IDENTITY}]

func _is_ecology_blocker(e:Dictionary)->bool:
	return e.get("data",{}).get("solid",false) or (e.get("blocksTerrain",false) and e.get("data",{}).get("module_target",false))

func _blocker_bins(e:Dictionary)->Array:
	var bins:Array=[]
	if not _is_ecology_blocker(e):return bins
	for z:int in range(floori(e.bounds.min.z/8),floori(e.bounds.max.z/8)+1):
		for x:int in range(floori(e.bounds.min.x/8),floori(e.bounds.max.x/8)+1):bins.append(Vector2i(x,z))
	return bins

func _index_ecology_blockers(entities:Array)->void:
	_ecology_blocker_index.clear()
	for e:Dictionary in entities:
		for key:Vector2i in _blocker_bins(e):
			if not _ecology_blocker_index.has(key):_ecology_blocker_index[key]=[]
			_ecology_blocker_index[key].append(e)

func _blocker_support_chunks(e:Dictionary,dirty:Dictionary)->void:
	if not _is_ecology_blocker(e):return
	var pitch:float=float(world.config().cellSize)*int(world.config().chunkCells)
	# Match the exact ecology AABB below (ground+0.01 to ground+1.6).
	# The conservative reverse range includes diagonal and vertical borders.
	for z:int in range(floori(e.bounds.min.z/pitch),floori(e.bounds.max.z/pitch)+1):
		for x:int in range(floori(e.bounds.min.x/pitch),floori(e.bounds.max.x/pitch)+1):
			for y:int in range(floori((e.bounds.min.y-1.6-0.001)/pitch),floori((e.bounds.max.y+0.001)/pitch)+1):dirty[Data.key(Vector3i(x,y,z))]=true

func _entity_summary_known(changes:Dictionary)->bool:
	if not _projection_ready or not changes.get("entities") is Array or not changes.get("chunks") is Array:return false
	if world.get_revision()!=_projection_revision+1:return false
	var ids:Dictionary={}
	for id:Variant in changes.entities:
		if not id is String or ids.has(id):return false
		ids[id]=true
		if not _entities_by_id.has(id) and world.entity(id).is_empty():return false
	if changes.has("operations"):
		if not changes.operations is Array:return false
		var observed:Dictionary={}
		for value:Variant in changes.operations:
			if not value is Dictionary:return false
			var op:Dictionary=value
			if op.get("op") in ["entity.put","entity.remove"]:
				var id:String=str(op.id)
				if not ids.has(id) or observed.has(id):return false
				observed[id]=true
				# Real Runtime operations expose exact preimages. A missed or
				# out-of-order event cannot silently reuse stale entity geometry.
				if op.get("before")!=_entities_by_id.get(id):return false
			elif op.get("op") not in ["voxel.set","chunk.put","chunk.residency","chunk.storage","extension.set","region.put"]:return false
		if observed.size()!=ids.size():return false
	return true

func _sync_entity_changes(ids:Array,changed_chunks:Array=[],defer_generation_ecology:bool=false)->void:
	sync_passes+=1
	_support_sampler=SupportSampler.new(world)
	var dirty:Dictionary={};var foundations:bool=not changed_chunks.is_empty()
	for key:String in changed_chunks:dirty[key]=true
	var changed_trees:Dictionary={}
	for id:String in ids:
		var before:Dictionary=_entities_by_id.get(id,{})
		var after:Dictionary=world.entity(id)
		for e:Dictionary in [before,after]:
			_blocker_support_chunks(e,dirty)
			foundations=foundations or (e.get("kind")=="structure" and "foundation" in e.get("tags",[]))
		for key:Vector2i in _blocker_bins(before):
			_ecology_blocker_index[key]=_ecology_blocker_index[key].filter(func(e:Dictionary)->bool:return e.id!=id)
			if _ecology_blocker_index[key].is_empty():_ecology_blocker_index.erase(key)
		if after.is_empty():_entities_by_id.erase(id)
		else:_entities_by_id[id]=after
		for key:Vector2i in _blocker_bins(after):
			if not _ecology_blocker_index.has(key):_ecology_blocker_index[key]=[]
			_ecology_blocker_index[key].append(after)
		if after.get("kind") == "tree":
			changed_trees[id] = true
			if defer_generation_ecology and before.is_empty() and not _roots.has(id):
				_generation_trees[id] = true
				if _generation_tree_frame < 0:
					_generation_tree_frame = Engine.get_process_frames() + 4
			else:
				_generation_trees.erase(id)
				_sync_tree(after)
		else:
			_generation_trees.erase(id)
			_clear(id)
	_derived_entities=_entities_by_id.values()
	_index_tree_columns()
	# Mixed generation/terrain notifications can change supports of old trees
	# along the seam. Recheck those exact unbounded XZ columns as well as all
	# changed entities; distant unchanged tree/crown footprints cannot change.
	var affected:Dictionary={}
	for key:String in changed_chunks:
		var coord:Variant=Data.coord(key)
		if coord==null:
			for e:Dictionary in _derived_entities:
				if e.kind=="tree":affected[str(e.id)]=true
			break
		affected.merge(_tree_columns.get(Vector2i(coord.x,coord.z),{}))
	for id:String in affected:
		if not changed_trees.has(id) and not _generation_trees.has(id):_sync_tree(_entities_by_id[id])
	# Contacts' original full footprint/edge algorithm remains authoritative
	# for a changed foundation; ordinary trees do not change these footprints.
	if foundations:
		for key:String in contacts.update(_derived_entities):_rebuild_contact(key)
	if defer_generation_ecology:
		if _generation_ecology_frame < 0:
			_generation_ecology_frame = Engine.get_process_frames() + 1
		_generation_ecology_dirty.merge(dirty)
	else:
		_sync_ecology(_derived_entities, _with_pending_ecology(dirty.keys()), false)
	_projection_revision=world.get_revision()
	_support_sampler=null

func _with_pending_ecology(dirty: Array) -> Array:
	if _generation_ecology_frame < 0:
		return dirty
	for key: String in dirty:
		_generation_ecology_dirty[key] = true
	var keys := _generation_ecology_dirty.keys()
	_generation_ecology_dirty.clear()
	_generation_ecology_frame = -1
	return keys

func accept_generation_fringe(region_id: String, patches: Array) -> void:
	# Native hands off an accepted worker result after its synchronous world
	# notification. A reload or another edit invalidates this derived memo.
	if not _new_regions.has(region_id) or _generation_ecology_frame < 0:
		return
	_presentation_layouts[region_id] = patches
	presentation_layout_builds += 1

func process_generation_ecology() -> bool:
	if _generation_ecology_frame < 0:
		return false
	if Engine.get_process_frames() >= _generation_ecology_frame:
		const Costs = preload("res://scripts/runtime/frame_costs.gd")
		var started: int = Costs.begin()
		_support_sampler = SupportSampler.new(world)
		# Static blockers and foundations already reflect the commit. Read live
		# support again before publishing decorative patches.
		_sync_ecology(_derived_entities, _with_pending_ecology([]), false, true)
		_support_sampler = null
		Costs.end("environment/generation_ecology", started)
	return true

func process_generation_ecology_batches() -> void:
	if _generation_ecology_batches.is_empty() or Engine.get_process_frames() < _generation_ecology_batch_frame:
		return
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var started: int = Costs.begin()
	var deadline := Time.get_ticks_usec() + 2000
	_support_sampler = SupportSampler.new(world)
	for key: String in _generation_ecology_batches.keys():
		_generation_ecology_batches.erase(key)
		_sync_ecology_batches([key])
		if Time.get_ticks_usec() >= deadline:
			break
	_support_sampler = null
	Costs.end("environment/generation_ecology_batches", started)

func process_generation_trees() -> void:
	if _generation_trees.is_empty():
		_generation_tree_frame = -1
		return
	if Engine.get_process_frames() < _generation_tree_frame:
		return
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var measured: int = Costs.begin()
	var deadline := Time.get_ticks_usec() + 2000
	_support_sampler = SupportSampler.new(world)
	for id: String in _generation_trees.keys():
		_generation_trees.erase(id)
		var entity: Dictionary = _entities_by_id.get(id, {})
		if entity.get("kind") == "tree":
			_sync_tree(entity)
		if Time.get_ticks_usec() >= deadline:
			break
	_support_sampler = null
	Costs.end("environment/generation_trees", measured)

func _ecology_blocked(bounds:Dictionary)->bool:
	# Include all touched XZ bins, including diagonal/negative boundaries;
	# the original exact three-dimensional AABB predicate remains decisive.
	for z:int in range(floori(bounds.min.z/8),floori(bounds.max.z/8)+1):
		for x:int in range(floori(bounds.min.x/8),floori(bounds.max.x/8)+1):
			for e:Dictionary in _ecology_blocker_index.get(Vector2i(x,z),[]):
				if Data.intersects(e.bounds,bounds):return true
	return false

func _index_ecology_patches(patches:Array,pitch:float,region_order:int,offset:int=0)->Dictionary:
	var anchors:Dictionary={}
	for i:int in patches.size():
		var patch:Dictionary=patches[i];var p:Dictionary=patch.position
		var key:=Data.key(Data.cell_chunk(Vector3i(floori(p.x/0.5),floori((p.y-0.001)/0.5),floori(p.z/0.5)),16))
		if not _ecology_patch_index.has(key):_ecology_patch_index[key]=[]
		_ecology_patch_index[key].append(patch);anchors[key]=true
		_ecology_patch_order[patch.id]=Vector2i(region_order,offset+i)
		# Rotated footprints may cross two boundaries, including diagonals.
		var width:float=float(patch.footprint[0])*float(patch.scale)*sqrt(2.0)
		for z in range(floori((p.z-width/2)/pitch),floori((p.z+width/2)/pitch)+1):
			for x in range(floori((p.x-width/2)/pitch),floori((p.x+width/2)/pitch)+1):
				for y in range(floori((p.y-0.001)/pitch),floori((p.y+0.001)/pitch)+1):
					var support:=Data.key(Vector3i(x,y,z))
					if not _ecology_support_index.has(support):_ecology_support_index[support]={}
					_ecology_support_index[support][key]=true
	return anchors

func _sync_ecology(entities:Array,dirty_chunks:Array,force:bool,defer_batches:bool=false)->void:
	var region_count: int = world.region_ids().size() if world.has_method("region_ids") else world.regions().size()
	var config: Dictionary = _support_sampler.config if _support_sampler != null else world.config()
	var pitch: float = float(config.cellSize) * int(config.chunkCells)
	var activated:Dictionary={}
	# Only the disposable within-region fringe is deferred. Persisted ecology
	# always gets indexed, including legacy/boundary layouts. A partial warm
	# is sufficient: never gate visible patches on a fully resident region.
	if _ecology_layout_dirty or region_count != _ecology_region_count:
		var regions: Array = world.regions()
		var addition_only:bool=not _full_ecology_reindex and not _indexed_regions.is_empty() and region_count==_indexed_regions.size()+_new_regions.size() and not _new_regions.is_empty()
		for id:String in _new_regions:
			if _indexed_regions.has(id):addition_only=false
		if not addition_only:
			_ecology_patch_index.clear();_ecology_support_index.clear();_ecology_patch_order.clear();_indexed_regions.clear()
			_deferred_cover_regions.clear();_deferred_cover_chunks.clear()
		force=not addition_only
		var fields:Array[String]=["ecology","generator_version","generation_content_version"]
		for region_order:int in regions.size():
			var region:Dictionary=regions[region_order];var id:String=str(region.id)
			if addition_only and _indexed_regions.has(id):continue
			_indexed_regions[id]=true
			var plan:Dictionary=world.extension_fields("generation:"+id,fields)
			if plan.is_empty():continue
			var patches:Array=plan.get("ecology",{}).get("patches",[]).duplicate()
			# Immutable saved plans let a newly streamed neighbour reuse existing
			# disposable layouts. Explicit plan/reload notifications invalidate it.
			if not _presentation_layouts.has(id):
				var has_fringe:bool=plan.get("generator_version")=="factory-country-1" and int(plan.get("generation_content_version",1))>=3
				if has_fringe and int(world.region_residency_state(id).resident_chunks)==0:
					_deferred_cover_regions[id]={"order":region_order,"offset":patches.size()}
					for key:String in world.region_chunk_keys(id):
						if not _deferred_cover_chunks.has(key):_deferred_cover_chunks[key]={}
						_deferred_cover_chunks[key][id]=true
				else:
					var fringe:Variant=null
					# Only a first-plan notification at the next revision may use the
					# worker rows. They still go through the same live support checks.
					if (has_fringe and _new_regions.has(id) and _projection_ready
							and world.get_revision()==_projection_revision+1 and region_fringe_hint.is_valid()):
						fringe=region_fringe_hint.call(world,id)
					_presentation_layouts[id]=fringe if fringe is Array else (LandUseCover.patches(world.extension("generation:"+id)) if has_fringe else [])
					presentation_layout_builds+=1
			patches.append_array(_presentation_layouts.get(id,[]))
			activated.merge(_index_ecology_patches(patches,pitch,region_order))
		_new_regions.clear()
		_full_ecology_reindex=false
		_ecology_layout_dirty=false;_ecology_region_count=regions.size()
	else:
		var warming:Dictionary={}
		if force:
			for id:String in _deferred_cover_regions:
				if int(world.region_residency_state(id).resident_chunks)>0:warming[id]=true
		else:
			for key:String in dirty_chunks:
				if not _deferred_cover_chunks.has(key):
					continue
				var chunk: Dictionary = world.chunk_metadata(key) if world.has_method("chunk_metadata") else world.chunk(key)
				if chunk.get("resident", false):
					warming.merge(_deferred_cover_chunks[key])
		# Residency-only activation appends the one saved layout to the existing
		# indexes. Do not rebuild/recheck every earlier resident region here.
		for id:String in warming:
			var order:Dictionary=_deferred_cover_regions[id]
			var patches:Array=LandUseCover.patches(world.extension("generation:"+id))
			_presentation_layouts[id]=patches;presentation_layout_builds+=1
			activated.merge(_index_ecology_patches(patches,pitch,int(order.order),int(order.offset)))
			_deferred_cover_regions.erase(id)
			for key:String in world.region_chunk_keys(id):
				_deferred_cover_chunks[key].erase(id)
				if _deferred_cover_chunks[key].is_empty():_deferred_cover_chunks.erase(key)
		for key:String in activated:
			# Preserve exact original per-region/per-plan instance order even for
			# saved persistent patches whose anchors cross a region boundary.
			_ecology_patch_index[key].sort_custom(func(a:Dictionary,b:Dictionary)->bool:
				var x:Vector2i=_ecology_patch_order[a.id];var y:Vector2i=_ecology_patch_order[b.id]
				return x.x<y.x or (x.x==y.x and x.y<y.y))
	var affected:Dictionary=activated.duplicate()
	for key:String in dirty_chunks:
		for anchor:String in _ecology_support_index.get(key,{}):affected[anchor]=true
	var selected:Array=_ecology_patch_index.keys() if force else affected.keys()
	_last_ecology_candidates=0
	if force:
		_generation_ecology_batches.clear()
		for key:String in _ecology.keys():
			if not _ecology_patch_index.has(key):_clear_ecology(key)
	if defer_batches and not force and not selected.is_empty():
		if _generation_ecology_batches.is_empty():
			# Let terrain, shells and factory visuals take their existing slots.
			_generation_ecology_batch_frame = Engine.get_process_frames() + 3
		for key: String in selected:
			_generation_ecology_batches[key] = true
		return
	# Real edits and cold paging refresh affected batches immediately. Avoid a
	# later duplicate refresh from an earlier generation notification.
	for key: String in selected:
		_generation_ecology_batches.erase(key)
	_sync_ecology_batches(selected)

func _sync_ecology_batches(selected: Array) -> void:
	var batches:Dictionary={}
	for key:String in selected:
		if not _ecology_patch_index.has(key):continue
		batches[key]=[]
		for patch:Dictionary in _ecology_patch_index[key]:
			_last_ecology_candidates+=1
			var p:=Vector3(patch.position.x,patch.position.y,patch.position.z)
			var width:float=float(patch.footprint[0])*float(patch.scale)*sqrt(2.0)
			if not _grounded(p,Vector2.ONE*width,int(patch.material)):continue
			var bounds:Dictionary={"min":{"x":p.x-width/2,"y":p.y+0.01,"z":p.z-width/2},"max":{"x":p.x+width/2,"y":p.y+1.6,"z":p.z+width/2}}
			if _ecology_blocked(bounds):continue
			batches[key].append(patch)
	for key:String in batches:
		if batches[key].is_empty():_clear_ecology(key);continue
		# A batch contains only this consumer's detached immutable plan rows.
		# Compare their exact values after every live support/blocker check;
		# avoid serializing all row dictionaries to text on an unchanged pass.
		# A layout invalidation creates new rows; equality still includes every
		# field (model, UV choice ID, transform, scale and world identity).
		var signature:Array=[world.identity().worldId,batches[key]]
		if _ecology_signatures.get(key)==signature:continue
		_clear_ecology(key)
		var node:=Node3D.new();node.name="Ecology_"+key.validate_node_name()
		node.set_meta("terrain_chunk",key)
		node.set_meta("persistent_patch_ids",batches[key].filter(func(p:Dictionary)->bool:return not p.get("presentation_only",false)).map(func(p:Dictionary)->String:return p.id))
		node.set_meta("presentation_patch_ids",batches[key].filter(func(p:Dictionary)->bool:return p.get("presentation_only",false)).map(func(p:Dictionary)->String:return p.id))
		var groups:Dictionary={}
		for patch:Dictionary in batches[key]:
			var width:float=float(patch.footprint[0])*float(patch.scale)
			var atlas_cell:int=str(patch.id).sha256_text().substr(0,8).hex_to_int()%4
			# Native per-instance scale keeps identical world geometry/UV while
			# sharing one metre mesh across sizes of the same image/model.
			var id:String=patch.model+(":"+str(atlas_cell) if patch.model=="low_cover" else "")
			if not groups.has(id):groups[id]={"patch":patch,"transforms":[]}
			var p:=Vector3(patch.position.x,patch.position.y,patch.position.z)
			groups[id].transforms.append(Transform3D(Basis(Vector3.UP,float(patch.yaw)).scaled(Vector3.ONE*width),p))
		for group:Dictionary in groups.values():
			var patch:Dictionary=group.patch
			var parts:Array
			if str(patch.model).begins_with("quality:"):parts=ecology_models.quality.cutout_parts(str(patch.model).trim_prefix("quality:"),1.0)
			elif patch.model=="low_cover":parts=_cover_parts(int(str(patch.id).sha256_text().substr(0,8).hex_to_int()%4))
			else:parts=ecology_models.patch_parts(patch.model,1.0)
			for part:Dictionary in parts:
				var multimesh:=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D
				multimesh.mesh=part.mesh;multimesh.instance_count=group.transforms.size()
				for i in group.transforms.size():
					var transform:Transform3D=part.transform
					if patch.model=="low_cover":transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE/0.49),Vector3.ZERO)
					multimesh.set_instance_transform(i,group.transforms[i]*transform)
				var item:=MultiMeshInstance3D.new();item.multimesh=multimesh
				if str(patch.model).begins_with("quality:") or patch.model in ["low_cover","grain_crop_stage_3","leafy_crop_stage_3"]:item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(item)
		add_child(node);_ecology[key]=node;_ecology_signatures[key]=signature

func _clear_ecology(key:String)->void:
	if _ecology.has(key):
		var old:Node3D=_ecology[key];remove_child(old);old.queue_free();_ecology.erase(key)
	_ecology_signatures.erase(key)

func on_world_changed(changes: Dictionary, defer_generation_ecology: bool = false) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_world_changed(changes, defer_generation_ecology)
	preload("res://scripts/runtime/frame_costs.gd").end("environment/change_projection.gd",measured)

func _profiled_world_changed(changes: Dictionary, defer_generation_ecology: bool = false) -> void:
	# Full runtime operation notifications and C commit summaries both expose
	# explicit entity/chunk invalidations. Production/order extension-only work
	# cannot move a root or foundation; avoid deep-copying every entity for it.
	var operations:Variant=changes.get("operations",changes.get("world",[]))
	var unknown_operations:bool=not operations is Array
	if operations is Array:
		for value:Variant in operations:
			if not value is Dictionary:unknown_operations=true;continue
			var op:Dictionary=value
			if op.get("op")=="extension.set" and str(op.get("id","")).begins_with("generation:"):
				_ecology_layout_dirty=true
				var region_id:String=str(op.id).trim_prefix("generation:")
				if op.get("before_exists")==false and not _indexed_regions.has(region_id):_new_regions[region_id]=true
				else:_full_ecology_reindex=true
				_presentation_layouts.erase(region_id)
	var complete:bool=not unknown_operations and changes.has("chunks") and changes.has("entities") and changes.chunks is Array and changes.entities is Array
	var known:bool=complete and _entity_summary_known(changes)
	var reload:bool=changes.get("reload",false)
	var queued_generation: bool = false
	if complete and _generation_ecology_frame >= 0:
		queued_generation = not operations.any(func(op: Dictionary) -> bool:
			return op.get("op") == "extension.set" and str(op.get("id", "")).begins_with("generation:")
		)
	if complete and not reload and (not _ecology_layout_dirty or queued_generation) and changes.chunks.is_empty() and changes.entities.is_empty():
		# Known extension-only commits advance no geometry. Keep the revision
		# guard current; unknown/missed summaries fall through to the full path.
		if known or world.get_revision()==_projection_revision:
			_projection_revision=world.get_revision();return
	if not reload and known and not changes.entities.is_empty():
		# Exact complete preimages permit an incremental entity index even when
		# a newly generated region also adds chunks/its saved ecology plan. The
		# existing ecology index still handles plan invalidation and seam support.
		_sync_entity_changes(changes.entities, changes.chunks, defer_generation_ecology);return
	# Mixed voxel/residency/entity commits, unknown summaries and reload retain
	# the full original path, including every tree support and foundation edge.
	var all:bool=reload or not complete or not changes.get("entities",[]).is_empty() or (world.get_revision()!=_projection_revision and not known)
	if reload:_ecology_layout_dirty=true;_presentation_layouts.clear();_indexed_regions.clear();_new_regions.clear()
	sync(all,changes.get("chunks",[]),all)

func clear_ground() -> void:
	_generation_ecology_batches.clear()
	_generation_ecology_batch_frame = -1
	_generation_trees.clear()
	_generation_tree_frame = -1
	_with_pending_ecology([])
	# Reload can change every residency/material without changing entity IDs.
	# Remove obsolete overlays immediately, before the budgeted mesh queue runs.
	for collection in [_ground,_contacts,_fields]:
		for node in collection.values(): remove_child(node);node.queue_free()
		collection.clear()
	for key:String in _ecology.keys():_clear_ecology(key)
	_ecology_layout_dirty=true
	_presentation_layouts.clear()

func invalidate_ground(key: String) -> void:
	# Streaming removes derived overlays immediately; no full-world clear and
	# no resampling of stale or cold terrain while the warm mesh queue drains.
	for collection in [_ground,_contacts,_fields]:
		if not collection.has(key): continue
		var node: Node3D = collection[key]
		remove_child(node);node.queue_free();collection.erase(key)
	_clear_ecology(key)
	for anchor:String in _ecology_support_index.get(key,{}):_clear_ecology(anchor)

func _rebuild_contact(key: String) -> void:
	var c:Dictionary=world.chunk(key)
	var data:Dictionary=contacts.build(key,_grounded) if c.get("resident",false) else {"quads":0}
	_install_contact(key,data)

func _install_contact(key:String,data:Dictionary)->void:
	if _contacts.has(key):
		var old:Node3D=_contacts[key];remove_child(old);old.queue_free();_contacts.erase(key)
	if data.quads==0: return
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data.arrays)
	var visual := MeshInstance3D.new();visual.mesh=mesh;visual.material_override=materials.contact_material()
	visual.set_meta("terrain_chunk",key);visual.set_meta("foundation_ids",data.source_ids)
	visual.set_meta("contact_quads",data.quads)
	add_child(visual);_contacts[key]=visual

func begin_ground(key:String)->Dictionary:
	# Disposable arrays only. The terrain owner retains revision/epoch checks.
	return {"key":key,"contact_signature":contacts._signature,"contact":{"quads":0},"field":{"groups":{},"supports":[]},"shoulders":{}}

func ground_job_valid(job:Dictionary)->bool:
	# Entity-only foundation changes do not necessarily touch voxel revisions.
	return job.contact_signature==contacts._signature

func capture_ground_contact(job:Dictionary)->void:
	var c:Dictionary=world.chunk(job.key)
	if c.get("resident",false):job.contact=contacts.build(job.key,_grounded)

func capture_ground_fields(job:Dictionary)->void:
	job.field=Fields.capture(world,job.key)

func capture_ground_shoulders(job:Dictionary)->void:
	job.shoulders=_ground_arrays(job.key)

func ground_preparation(job:Dictionary)->Array:
	return materials.ground_preparation(int(job.contact.quads),job.field.groups,job.shoulders)

func publish_ground(job:Dictionary)->void:
	_install_contact(job.key,job.contact)
	if _fields.has(job.key):
		var old:Node3D=_fields[job.key];remove_child(old);old.queue_free();_fields.erase(job.key)
	var field:MeshInstance3D=Fields.upload(job.field,job.key,ecology_models.quality)
	if field!=null:add_child(field);_fields[job.key]=field
	_install_shoulders(job.key,job.shoulders)

func rebuild_ground(key: String) -> void:
	# Existing synchronous callers retain synchronous semantics. The budgeted
	# terrain path instead yields between array layers and real image requests.
	var job:Dictionary=begin_ground(key)
	capture_ground_contact(job);capture_ground_fields(job);capture_ground_shoulders(job)
	for request:Dictionary in ground_preparation(job):materials.prepare_terrain_input(request)
	publish_ground(job)

func _ground_arrays(key:String)->Dictionary:
	var c: Dictionary = world.chunk(key)
	if c.is_empty() or not c.resident: return {}
	if not c.cells.has(1): return {}
	var n := int(world.config().chunkCells)
	var s := float(world.config().cellSize)
	var groups := {}
	# Native PackedInt32Array search skips air/stone/soil slabs without a
	# GDScript visit to every cell. Exact grass index order and all support /
	# neighbor / residency tests remain unchanged, including caves and edits.
	var next_grass:int=c.cells.find(1)
	while next_grass>=0:
		var index:int=next_grass
		next_grass=c.cells.find(1,index+1)
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
	return groups

func _install_shoulders(key:String,groups:Dictionary)->void:
	if _ground.has(key):
		var old:Node3D=_ground[key];remove_child(old);old.queue_free();_ground.erase(key)
	if groups.is_empty():return
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

func statistics() -> Dictionary:
	var contact_quads := 0
	for node in _contacts.values(): contact_quads+=int(node.get_meta("contact_quads"))
	var patches:=0;var instances:=0;var presentation_patches:=0
	for node:Node3D in _ecology.values():
		patches+=node.get_meta("persistent_patch_ids").size()
		presentation_patches+=node.get_meta("presentation_patch_ids",[]).size()
		instances+=node.get_child_count()
	return {"tree_roots":_roots.size(),"ground_transition_chunks":_ground.size(),"field_surface_chunks":_fields.size(),"foundation_contact_chunks":_contacts.size(),"foundation_contact_quads":contact_quads,"rebuilt":rebuilt,"missing_materials":materials.missing.duplicate(),"ecology_chunks":_ecology.size(),"ecology_patches":patches,"presentation_cover_patches":presentation_patches,"ecology_multimeshes":instances,"last_ecology_candidates":_last_ecology_candidates,"missing_models":ecology_models.failures.duplicate(),"missing_quality_images":ecology_models.quality.failures.duplicate()}
