extends Node3D
## Main-scene component. Native meshes/collision share one generated array batch.
const Mesher = preload("res://tests/world/fixtures/foundation_mesher_before.gd")
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
var _stats := {"rebuilds":0,"quads":0,"build_usec":0,"collision_usec":0,"max_rebuild_usec":0,"last_stream_enqueue_usec":0,"last_environment_sync_usec":0,"last_notification_usec":0}

func configure(context: Dictionary) -> void:
	world = context.world
	materials = context.get("materials",Materials.new())
	materials.set_world_style(str(world.identity().generatorVersion))
	_stream_updates = context.get("stream_updates",false)
	environment = EnvironmentView.new()
	add_child(environment)
	environment.configure({"world":world,"materials":materials})
	for key in world.chunk_keys(): _enqueue(key)
	if context.has("runtime") and context.runtime.has_signal("changed"):
		context.runtime.changed.connect(on_world_changed)

func _enqueue(key: String) -> void:
	if not _queued.has(key):
		_queued[key] = true
		_queue.append(key)

func _process(_delta: float) -> void:
	# Initial presentation is budgeted; a committed edit is synchronized below.
	var start := Time.get_ticks_usec()
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		_queued.erase(key)
		_rebuild(key)
		if Time.get_ticks_usec()-start >= 4000: break

func _remove(key: String) -> void:
	if not _chunks.has(key): return
	var old: Dictionary = _chunks[key]
	_stats.quads -= old.quads
	remove_child(old.node)
	old.node.queue_free()
	_chunks.erase(key)

func _rebuild(key: String) -> void:
	var start := Time.get_ticks_usec()
	var c: Dictionary = world.chunk(key)
	environment.rebuild_ground(key)
	# Empty generated chunks also finish derivation. Node presence alone cannot
	# prove a region ready: most upper chunks legitimately have no surface/body.
	if c.is_empty(): _derived.erase(key)
	else: _derived[key] = {"revision":c.revision,"physics_frame":Engine.get_physics_frames()}
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
			elif op.op in ["chunk.put","chunk.residency"]:
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
	# The owner must gate actors/interactions until readiness().ready. Opt-in
	# applies only to allocations/residency; voxel edits retain synchronous mesh
	# and collision invalidation, including mixed edit/stream transactions.
	var stream := _stream_updates and operations.any(func(op: Dictionary)->bool:return op.op in ["chunk.put","chunk.residency"])
	stream = stream and not operations.any(func(op: Dictionary)->bool:return op.op=="voxel.set")
	if changes.get("reload",false):
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
				else: _queued.erase(key); _queue.erase(key)
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

func readiness(keys: Array) -> Dictionary:
	var pending: Array=[]; var unknown: Array=[]; var cold: Array=[]; var physics: Array=[]
	for input in keys:
		var key := str(input)
		var chunk: Dictionary = world.chunk(key)
		if not chunk.get("generated",false): unknown.append(key); continue
		if not chunk.get("resident",false): cold.append(key); continue
		var derived: Dictionary = _derived.get(key,{})
		if _queued.has(key) or derived.get("revision",-1)!=chunk.revision:
			pending.append(key)
		elif int(derived.physics_frame)>=Engine.get_physics_frames(): physics.append(key)
	var geometry_ready := not keys.is_empty() and pending.is_empty() and unknown.is_empty() and cold.is_empty()
	return {"ready":geometry_ready and physics.is_empty(),"geometry_ready":geometry_ready,"world_id":world.identity().worldId,"world_revision":world.get_revision(),"pending":pending,"unknown":unknown,"cold":cold,"awaiting_physics":physics}

func flush_pending() -> void:
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		_queued.erase(key)
		_rebuild(key)

func pick(a: Vector3, b: Vector3) -> Dictionary: return Queries.pick(world,a,b)
func target_at(point: Vector3, normal: Vector3) -> Dictionary: return Queries.target_at(world,point,normal)
func statistics() -> Dictionary:
	var result := _stats.duplicate(true)
	result.merge({"derived_chunks":_chunks.size(),"pending":_queue.size(),"environment":environment.statistics()})
	return result
