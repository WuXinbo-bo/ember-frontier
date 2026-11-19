extends Node3D
## Tree/trunk/shrub/ground layers are derived from real live entities and cells.
const Data = preload("res://scripts/world/world_data.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
const Contacts = preload("res://scripts/environment/ground_contacts.gd")
const EcologyModels = preload("res://scripts/environment/ecology_models.gd")
const Fields=preload("res://scripts/environment/field_surfaces.gd")
var world: RefCounted
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
var _ecology_layout_dirty:=true
var _ecology_region_count:=-1
var _derived_entities:Array=[]
var _last_ecology_candidates:=0
var _fields:Dictionary={}

func configure(context: Dictionary) -> void:
	world = context.world
	_ecology_layout_dirty=true
	_derived_entities.clear()
	materials = context.get("materials",Materials.new())
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
	var seen := {}
	var n := int(world.config().chunkCells)
	var s := float(world.config().cellSize)
	# Disposable entity projection. Only explicit entity/reload notifications can
	# change it; voxel notifications still query every actual support cell live.
	if update_foundations or _derived_entities.is_empty():_derived_entities=world.entities()
	var entities:Array=_derived_entities
	if update_foundations:
		for key in contacts.update(entities): _rebuild_contact(str(key))
	for e in entities:
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
		# Each patch follows the SAME authoritative surface, rather than assuming
		# the whole forest is at its tree's Y. Full footprint checks still reject
		# steps, holes, unknown/cold ground and changed material.
		for i in offsets.size():
			var q: Vector3=p+offsets[i]
			var height: Variant=world.surface_height(q.x,q.z)
			if height!=null: offsets[i].y=float(height)-p.y
			shrub_ground.append(height!=null and _grounded(p+offsets[i],Vector2(0.8,0.7),1))
		var root_offsets := [Vector3(-0.23,0,0),Vector3(0.23,0,0),Vector3(0,0,0.23)]
		var root_ground: Array = []
		for offset in root_offsets: root_ground.append(_grounded(p+offset,Vector2(0.28,0.24)))
		var signature := str([e,ground,leaf_ground,offsets,shrub_ground,root_ground])
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
			shape.shape = box
			shape.position.y = tree_height*0.5
			body.add_child(shape)
			root.add_child(body)
		for i in root_offsets.size():
			if root_ground[i]: _box(root,root_offsets[i]+Vector3(0,0.08,0),Vector3(0.28,0.16,0.24),"bark")
	for id in _roots.keys():
		if not seen.has(id): _clear(id)
	_sync_ecology(entities,ecology_chunks,force_ecology)

func _cover_parts(cell:int)->Array:
	if not _cover_meshes.has(cell):
		var temporary:=Node3D.new()
		var native:=_low_cover(temporary,Vector3.ZERO,cell,0.0)
		native.mesh.surface_set_material(0,native.material_override)
		_cover_meshes[cell]=native.mesh
		temporary.free()
	return [{"mesh":_cover_meshes[cell],"transform":Transform3D.IDENTITY}]

func _sync_ecology(entities:Array,dirty_chunks:Array,force:bool)->void:
	var regions:Array=world.regions()
	if _ecology_layout_dirty or regions.size()!=_ecology_region_count:
		_ecology_patch_index.clear();_ecology_support_index.clear();force=true
		for region:Dictionary in regions:
			var plan:Variant=world.extension("generation:"+str(region.id))
			if not plan is Dictionary:continue
			for patch:Dictionary in plan.get("ecology",{}).get("patches",[]):
				var p:Dictionary=patch.position
				var key:=Data.key(Data.cell_chunk(Vector3i(floori(p.x/0.5),floori((p.y-0.001)/0.5),floori(p.z/0.5)),16))
				if not _ecology_patch_index.has(key):_ecology_patch_index[key]=[]
				_ecology_patch_index[key].append(patch)
				# Rotated footprints can cross TWO boundaries simultaneously. The
				# anchor chunk alone (or six face neighbours) misses diagonal digs.
				var width:float=float(patch.footprint[0])*float(patch.scale)*sqrt(2.0)
				var pitch:float=float(world.config().cellSize)*int(world.config().chunkCells)
				for z in range(floori((p.z-width/2)/pitch),floori((p.z+width/2)/pitch)+1):
					for x in range(floori((p.x-width/2)/pitch),floori((p.x+width/2)/pitch)+1):
						for y in range(floori((p.y-0.001)/pitch),floori((p.y+0.001)/pitch)+1):
							var support:=Data.key(Vector3i(x,y,z))
							if not _ecology_support_index.has(support):_ecology_support_index[support]={}
							_ecology_support_index[support][key]=true
		_ecology_layout_dirty=false;_ecology_region_count=regions.size()
	var affected:Dictionary={}
	for key:String in dirty_chunks:
		for anchor:String in _ecology_support_index.get(key,{}):affected[anchor]=true
	var selected:Array=_ecology_patch_index.keys() if force else affected.keys()
	_last_ecology_candidates=0
	if force:
		for key:String in _ecology.keys():
			if not _ecology_patch_index.has(key):_clear_ecology(key)
	var solids:Array=entities.filter(func(e:Dictionary)->bool:return e.get("data",{}).get("solid",false))
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
			if solids.any(func(e:Dictionary)->bool:return Data.intersects(e.bounds,bounds)):continue
			batches[key].append(patch)
	for key:String in batches:
		if batches[key].is_empty():_clear_ecology(key);continue
		var signature:=str([world.identity().worldId,batches[key]])
		if _ecology_signatures.get(key)==signature:continue
		_clear_ecology(key)
		var node:=Node3D.new();node.name="Ecology_"+key.validate_node_name()
		node.set_meta("terrain_chunk",key)
		node.set_meta("persistent_patch_ids",batches[key].map(func(p:Dictionary)->String:return p.id))
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

func on_world_changed(changes: Dictionary) -> void:
	# Full runtime operation notifications and C commit summaries both expose
	# explicit entity/chunk invalidations. Production/order extension-only work
	# cannot move a root or foundation; avoid deep-copying every entity for it.
	for op:Dictionary in changes.get("operations",changes.get("world",[])):
		if op.get("op")=="extension.set" and str(op.get("id","")).begins_with("generation:"):_ecology_layout_dirty=true
	if not _ecology_layout_dirty and not changes.get("reload",false) and changes.has("chunks") and changes.has("entities") and changes.chunks.is_empty() and changes.entities.is_empty(): return
	# A voxel/residency change rechecks real ground on already cached edges.
	# Only entity changes or an unknown/reload notification rescan footprints.
	var all:bool=changes.get("reload",false) or not changes.has("chunks") or not changes.has("entities") or not changes.entities.is_empty()
	if changes.get("reload",false):_ecology_layout_dirty=true
	sync(all,changes.get("chunks",[]),all)

func clear_ground() -> void:
	# Reload can change every residency/material without changing entity IDs.
	# Remove obsolete overlays immediately, before the budgeted mesh queue runs.
	for collection in [_ground,_contacts,_fields]:
		for node in collection.values(): remove_child(node);node.queue_free()
		collection.clear()
	for key:String in _ecology.keys():_clear_ecology(key)
	_ecology_layout_dirty=true

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
	var patches:=0;var instances:=0
	for node:Node3D in _ecology.values():
		patches+=node.get_meta("persistent_patch_ids").size()
		instances+=node.get_child_count()
	return {"tree_roots":_roots.size(),"ground_transition_chunks":_ground.size(),"field_surface_chunks":_fields.size(),"foundation_contact_chunks":_contacts.size(),"foundation_contact_quads":contact_quads,"rebuilt":rebuilt,"missing_materials":materials.missing.duplicate(),"ecology_chunks":_ecology.size(),"ecology_patches":patches,"ecology_multimeshes":instances,"last_ecology_candidates":_last_ecology_candidates,"missing_models":ecology_models.failures.duplicate(),"missing_quality_images":ecology_models.quality.failures.duplicate()}
