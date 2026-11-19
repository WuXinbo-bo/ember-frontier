extends Node3D
## Main-scene component. Native meshes/collision share one generated array batch.
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
const EnvironmentView = preload("res://scripts/environment/environment_view.gd")
const Data = preload("res://scripts/world/world_data.gd")
var world: RefCounted
var materials: RefCounted
var environment: Node3D
var _chunks: Dictionary = {}
var _queue: Array = []
var _queued: Dictionary = {}
var _derived: Dictionary = {}
var _stream_updates := false
var _budgeted_edits := false
var _active: Dictionary = {}
var _epoch := 0
var _stage_costs: Dictionary = {}
var _cancelled := 0
var _boundary_values: Dictionary = {}
var _stats := {"rebuilds":0,"quads":0,"build_usec":0,"collision_usec":0,"max_rebuild_usec":0,"last_stream_enqueue_usec":0,"last_environment_sync_usec":0,"last_notification_usec":0}

func configure(context: Dictionary) -> void:
	_epoch+=1;_boundary_values.clear()
	world = context.world
	materials = context.get("materials",Materials.new())
	materials.set_world_style(str(world.identity().generatorVersion))
	_stream_updates = context.get("stream_updates",false)
	_budgeted_edits = context.get("budgeted_edits",false)
	environment = EnvironmentView.new()
	add_child(environment)
	environment.configure({"world":world,"materials":materials})
	for key in world.chunk_keys(): _enqueue(key)
	if context.has("runtime") and context.runtime.has_signal("changed"):
		context.runtime.changed.connect(on_world_changed)

func _enqueue(key: String) -> void:
	if _active.get("key")==key:
		_discard_active()
		_queue.append(key)
		return
	if not _queued.has(key):
		_queued[key] = true
		_queue.append(key)

func _process(_delta: float) -> void:
	process_budget(4000)

func process_budget(budget_usec:int=4000)->void:
	# Cooperative pure-array layers, native upload, shape and registration are
	# distinct stages. Native engine calls remain non-preemptible soft-budget
	# units; expose their peaks instead of claiming a hard 4ms limit.
	var start := Time.get_ticks_usec()
	var units:=0;var limit:=clampi(budget_usec,1,16000)
	while not _queue.is_empty() or not _active.is_empty():
		if _active.is_empty():
			var key:String=_queue.pop_front()
			_active={"key":key,"epoch":_epoch,"dependencies":_dependencies(key),"stage":"capture"}
		var expected:int=maxi(25,int(_stage_costs.get(_active.stage,{}).get("max_usec",25)))
		if units>0 and Time.get_ticks_usec()-start+expected>=limit:break
		_advance_active()
		units+=1
		if Time.get_ticks_usec()-start >= limit: break

func _dependencies(key:String)->Array:
	var q:Variant=Data.coord(key)
	if q==null:return []
	var own:Dictionary=world.chunk(key)
	var result:Array=[[key,own.get("revision",-1),own.get("generated",false),own.get("resident",false)]]
	for axis in 3:
		for sign in [-1,1]:
			var neighbor:Vector3i=q;neighbor[axis]+=sign
			var id:String=Data.key(neighbor);var c:Dictionary=world.chunk(id)
			var values:=PackedInt32Array()
			if c.get("generated",false) and c.get("resident",false):values=_boundary(c,id,axis,sign)
			result.append([id,values,c.get("generated",false),c.get("resident",false)])
	return result

func _boundary(c:Dictionary,key:String,axis:int,sign:int)->PackedInt32Array:
	# Exact plane equality, not a lossy hash or all-neighbor revision. Interior
	# edits cannot change a seam; face edits still invalidate BOTH sides. Cache
	# only current revisions, bounded by the finite world's actual chunk keys.
	if _boundary_values.get(key,{}).get("revision",-1)!=c.revision:_boundary_values[key]={"revision":c.revision,"faces":{}}
	var face:String=str(axis)+":"+str(sign);var cached:Dictionary=_boundary_values[key].faces
	if not cached.has(face):
		var n:int=int(world.config().chunkCells);var strides:Array=[1,n*n,n]
		var layer:int=0 if sign>0 else n-1;var values:=PackedInt32Array();values.resize(n*n)
		var cells:PackedInt32Array=PackedInt32Array(c.cells)
		for v in n:
			for u in n:values[u+n*v]=cells[layer*strides[axis]+u*strides[(axis+1)%3]+v*strides[(axis+2)%3]]
		cached[face]=values
	return cached[face]

func _discard_active()->void:
	if _active.is_empty():return
	if _active.has("root"):_active.root.free()
	_active.clear();_cancelled+=1

func _advance_active()->void:
	var key:String=_active.key
	var stage:String=_active.stage;var started:=Time.get_ticks_usec()
	if _active.epoch!=_epoch or (_active.stage in ["mesh","ground_contacts","ground_fields","ground_shoulders","ground_materials","ground","publish"] and _active.dependencies!=_dependencies(key)) or (_active.has("ground_job") and not environment.ground_job_valid(_active.ground_job)):
		# At most one fresh pending attempt per actual notification. An obsolete
		# result never attaches, and unrelated metadata revisions never retry it.
		_discard_active();_queued.erase(key);_enqueue(key);return
	match stage:
		"capture":
			_active.job=Mesher.begin(world,key);_active.stage="arrays"
		"arrays":
			if Mesher.advance(_active.job):
				_active.material_inputs=materials.terrain_preparation(_active.job.output)
				_active.stage="materials"
		"materials":
			if _active.material_inputs.is_empty():_active.stage="mesh"
			else:materials.prepare_terrain_input(_active.material_inputs.pop_front())
		"mesh":
			var data:Dictionary=_active.job.output
			if data.groups.is_empty():_active.stage="ground_contacts"
			else:
				_active.mesh=Mesher.mesh(data,materials);_active.stage="shape"
		"shape":
			_active.shape=_active.mesh.create_trimesh_shape();_active.stage="ground_contacts"
		"ground_contacts":
			_active.ground_job=environment.begin_ground(key)
			environment.capture_ground_contact(_active.ground_job);_active.stage="ground_fields"
		"ground_fields":
			environment.capture_ground_fields(_active.ground_job);_active.stage="ground_shoulders"
		"ground_shoulders":
			environment.capture_ground_shoulders(_active.ground_job)
			_active.material_inputs=environment.ground_preparation(_active.ground_job);_active.stage="ground_materials"
		"ground_materials":
			if _active.material_inputs.is_empty():_active.stage="ground"
			else:materials.prepare_terrain_input(_active.material_inputs.pop_front())
		"ground":
			environment.publish_ground(_active.ground_job);_active.stage="publish"
		"publish":
			_remove(key)
			var data:Dictionary=_active.job.output
			if _active.has("mesh"):
				var root:=Node3D.new();root.name="Terrain_"+key.validate_node_name();root.set_meta("terrain_chunk",key)
				var visual:=MeshInstance3D.new();visual.mesh=_active.mesh;visual.set_meta("terrain_chunk",key);root.add_child(visual)
				var body:=StaticBody3D.new();body.set_meta("terrain_chunk",key)
				var shape:=CollisionShape3D.new();shape.shape=_active.shape;body.add_child(shape);root.add_child(body);add_child(root)
				_chunks[key]={"node":root,"quads":data.quads,"revision":world.get_revision()}
				_stats.rebuilds+=1;_stats.quads+=data.quads
			var c:Dictionary=world.chunk(key)
			if c.get("generated",false) and c.get("resident",false):_derived[key]={"revision":c.revision,"dependencies":_active.dependencies,"physics_frame":Engine.get_physics_frames()}
			else:_derived.erase(key)
			_queued.erase(key);_active.clear()
	var elapsed:=Time.get_ticks_usec()-started
	var cost:Dictionary=_stage_costs.get(stage,{"calls":0,"total_usec":0,"max_usec":0,"over_4ms":0})
	cost.calls+=1;cost.total_usec+=elapsed;cost.max_usec=maxi(cost.max_usec,elapsed)
	if elapsed>4000:cost.over_4ms+=1
	_stage_costs[stage]=cost

func _remove(key: String) -> void:
	if not _chunks.has(key): return
	var old: Dictionary = _chunks[key]
	_stats.quads -= old.quads
	remove_child(old.node)
	old.node.queue_free()
	_chunks.erase(key)

func _rebuild(key: String) -> void:
	if _active.get("key")==key:_discard_active()
	var start := Time.get_ticks_usec()
	var c: Dictionary = world.chunk(key)
	environment.rebuild_ground(key)
	# Empty generated chunks also finish derivation. Node presence alone cannot
	# prove a region ready: most upper chunks legitimately have no surface/body.
	if c.is_empty(): _derived.erase(key)
	else: _derived[key] = {"revision":c.revision,"dependencies":_dependencies(key),"physics_frame":Engine.get_physics_frames()}
	if c.is_empty() or not c.resident:
		_remove(key)
		return
	var data: Dictionary = Mesher.build(world,key)
	if data.groups.is_empty():
		_remove(key)
		return
	var root := Node3D.new()
	root.name = "Terrain_"+key.validate_node_name()
	root.set_meta("terrain_chunk",key)
	if not data.groups.is_empty():
		var mesh: ArrayMesh = Mesher.mesh(data,materials)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.set_meta("terrain_chunk",key)
		root.add_child(visual)
		var body := StaticBody3D.new()
		body.set_meta("terrain_chunk",key)
		var shape := CollisionShape3D.new()
		var t := Time.get_ticks_usec()
		shape.shape = mesh.create_trimesh_shape()
		_stats.collision_usec += Time.get_ticks_usec()-t
		body.add_child(shape)
		root.add_child(body)
	_remove(key)
	add_child(root)
	_chunks[key] = {"node":root,"quads":data.quads,"revision":world.get_revision()}
	_stats.rebuilds += 1
	_stats.quads += data.quads
	var elapsed := Time.get_ticks_usec()-start
	_stats.build_usec += elapsed
	_stats.max_rebuild_usec = maxi(_stats.max_rebuild_usec,elapsed)

func on_world_changed(notification: Dictionary) -> void:
	if notification.has("clock") and not notification.has("world"): return
	var started := Time.get_ticks_usec()
	var raw: Variant = notification.get("world",notification.get("changes",notification))
	var changes: Dictionary
	var operations: Array = raw if raw is Array else []
	if raw is Array:
		var dirty := {}
		var entity_ids := {}
		for op in raw:
			if op.op == "voxel.set":
				for key in Data.affected(Vector3i(op.cell.x,op.cell.y,op.cell.z),int(world.config().chunkCells)): dirty[key] = true
			elif op.op in ["chunk.put","chunk.residency","chunk.storage"]:
				var q: Variant = Data.coord(str(op.id))
				if q == null: continue
				dirty[op.id] = true
				for axis in 3:
					for sign in [-1,1]:
						var neighbor: Vector3i = q
						neighbor[axis] += sign
						dirty[Data.key(neighbor)] = true
			elif op.op in ["entity.put","entity.remove"]: entity_ids[str(op.id)]=true
		changes = {"operations":raw,"chunks":dirty.keys(),"entities":entity_ids.keys()}
		if raw.is_empty(): return
	elif raw is Dictionary: changes = raw
	else: return
	if changes.has("changes") and changes.changes is Dictionary: changes = changes.changes
	if changes.get("operations") is Array: operations = changes.operations
	# Boundary planes are disposable copies of factual cells too. Retiring a
	# cold body must not retain its old planes until an eventual warm rebuild.
	for key:String in changes.get("chunks",[]):
		if _boundary_values.has(key) and not world.chunk(key).get("resident",false):_boundary_values.erase(key)
	# The owner must gate actors/interactions until readiness().ready. Opt-in
	# applies only to allocations/residency; voxel edits retain synchronous mesh
	# and collision invalidation, including mixed edit/stream transactions.
	var edited:bool=operations.any(func(op:Dictionary)->bool:return op.op=="voxel.set")
	var stream := (_stream_updates and operations.any(func(op: Dictionary)->bool:return op.op in ["chunk.put","chunk.residency","chunk.storage"])) or (_budgeted_edits and edited)
	stream = stream and (_budgeted_edits or not edited)
	if changes.get("reload",false):
		_epoch+=1;_discard_active();_boundary_values.clear()
		for key in _chunks.keys(): _remove(key)
		environment.clear_ground()
		_queue.clear()
		_queued.clear()
		_derived.clear()
		for key in world.chunk_keys(): _enqueue(key)
	else:
		for key in changes.get("chunks",[]):
			if stream:
				# Retire stale bodies/overlays now, before budgeted warm rebuilding.
				_remove(str(key)); _derived.erase(key)
				environment.invalidate_ground(str(key))
				var chunk: Dictionary = world.chunk(str(key))
				if chunk.get("generated",false) and chunk.get("resident",false): _enqueue(str(key))
				else:
					if _active.get("key")==str(key):_discard_active()
					_queued.erase(key); _queue.erase(key)
				continue
			# No stale mesh/body remains after a committed terrain notification.
			_rebuild(str(key))
			_queued.erase(key)
			_queue.erase(key)
	var environment_start := Time.get_ticks_usec()
	_stats.last_stream_enqueue_usec = environment_start-started if stream else 0
	environment.on_world_changed(changes)
	_stats.last_environment_sync_usec = Time.get_ticks_usec()-environment_start
	_stats.last_notification_usec = Time.get_ticks_usec()-started

func set_streaming_updates(enabled: bool) -> void:
	# A owns the transaction/loading gate. Existing callers keep sync behaviour.
	_stream_updates = enabled

func set_budgeted_edits(enabled:bool)->void:
	# A enables only together with the input/body/NPC readiness gate. Logical
	# edits commit immediately; stale bodies retire before returning notification.
	_budgeted_edits=enabled

func cancel_pending()->void:
	_epoch+=1;_discard_active();_queue.clear();_queued.clear()

func prioritize(keys:Array)->void:
	# Only known resident chunks; this never allocates/generates authority.
	# The owner supplies its finite spawn/camera/tool neighborhood first.
	for i in range(keys.size()-1,-1,-1):
		var key:String=str(keys[i]);var c:Dictionary=world.chunk(key)
		if not c.get("generated",false) or not c.get("resident",false) or _active.get("key")==key:continue
		if not _queued.has(key) and _derived.get(key,{}).get("dependencies",[])==_dependencies(key):continue
		_enqueue(key);_queue.erase(key);_queue.push_front(key)

func readiness(keys: Array) -> Dictionary:
	var pending: Array=[]; var unknown: Array=[]; var cold: Array=[]; var physics: Array=[];var unallocated:Array=[];var ungenerated:Array=[]
	for input in keys:
		var key := str(input)
		var chunk: Dictionary = world.chunk(key)
		if not chunk.get("generated",false):
			unknown.append(key)
			if chunk.is_empty():unallocated.append(key)
			else:ungenerated.append(key)
			continue
		if not chunk.get("resident",false): cold.append(key); continue
		var derived: Dictionary = _derived.get(key,{})
		if _queued.has(key) or derived.get("revision",-1)!=chunk.revision or derived.get("dependencies",[])!=_dependencies(key):
			pending.append(key)
		elif int(derived.physics_frame)>=Engine.get_physics_frames(): physics.append(key)
	var geometry_ready := not keys.is_empty() and pending.is_empty() and unknown.is_empty() and cold.is_empty()
	return {"ready":geometry_ready and physics.is_empty(),"known":not keys.is_empty() and unallocated.is_empty(),"generated":not keys.is_empty() and unknown.is_empty(),"resident":not keys.is_empty() and unknown.is_empty() and cold.is_empty(),"geometry_ready":geometry_ready,"physics_ready":geometry_ready and physics.is_empty(),"world_id":world.identity().worldId,"world_revision":world.get_revision(),"view_epoch":_epoch,"pending":pending,"unknown":unknown,"unallocated":unallocated,"ungenerated":ungenerated,"cold":cold,"awaiting_physics":physics}

func readiness_near(points:Array,horizontal_radius:float=1.0,below:float=0.5,above:float=2.0)->Dictionary:
	# Finite spawn/body/tool/camera neighborhoods, never all remote chunks.
	if points.is_empty() or points.size()>64 or not is_finite(horizontal_radius) or horizontal_radius<0 or horizontal_radius>16 or not is_finite(below) or below<0 or below>16 or not is_finite(above) or above<0 or above>16:return {"ready":false,"code":"INVALID_READY_BOUNDS"}
	var width:float=float(world.config().cellSize)*int(world.config().chunkCells);var keys:Dictionary={}
	for point:Variant in points:
		if not point is Vector3 or not point.is_finite():return {"ready":false,"code":"INVALID_READY_POINT"}
		var lo:Vector3=point-Vector3(horizontal_radius,below,horizontal_radius);var hi:Vector3=point+Vector3(horizontal_radius,above,horizontal_radius)
		for z in range(floori(lo.z/width),floori(hi.z/width)+1):
			for y in range(floori(lo.y/width),floori(hi.y/width)+1):
					for x in range(floori(lo.x/width),floori(hi.x/width)+1):keys[Data.key(Vector3i(x,y,z))]=true
	var result:=readiness(keys.keys());result.keys=keys.keys();return result

func flush_pending() -> void:
	if not _active.is_empty():
		var key:String=_active.key;_discard_active();_queue.push_front(key)
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		_queued.erase(key)
		_rebuild(key)

func pick(a: Vector3, b: Vector3) -> Dictionary: return Queries.pick(world,a,b)
func target_at(point: Vector3, normal: Vector3) -> Dictionary: return Queries.target_at(world,point,normal)
func statistics() -> Dictionary:
	var result := _stats.duplicate(true)
	result.merge({"derived_chunks":_chunks.size(),"pending":_queued.size(),"environment":environment.statistics(),"stages":_stage_costs.duplicate(true),"cancelled_jobs":_cancelled,"view_epoch":_epoch,"budgeted_edits":_budgeted_edits})
	return result
