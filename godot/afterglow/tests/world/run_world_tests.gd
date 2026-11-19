extends SceneTree
const State = preload("res://scripts/world/world_state.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
const TerrainView = preload("res://scripts/terrain/terrain_view.gd")
var checks: Array = []
var failed: bool = false

func check(label: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"label":label,"ok":condition,"detail":detail})
	if not condition:
		failed = true
		push_error("FAIL "+label+" "+str(detail))

func _initialize() -> void:
	create_timer(45).timeout.connect(func()->void: quit(2))
	call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_usec()
	var state := State.new()
	var generated: Dictionary = Generator.generate(713)
	check("two finite districts, 9 real resources with empty drop containers",generated.regions.size()==2 and generated.chunks.size()==512 and generated.entities.size()==18 and not generated.has("runtime"))
	var loaded: Dictionary = state.load_snapshot(generated)
	check("load generated",loaded.ok,loaded)
	if not loaded.ok:
		quit(1)
		return
	check("negative floor and X/Z/Y index",Data.cell_chunk(Vector3i(-1,-1,-17),16)==Vector3i(-1,-1,-2) and Data.local_index(Vector3i(-1,-1,-17),16)==4095)
	check("road crosses physical boundary",state.cell_at(64,-1,-1)==4 and state.cell_at(64,-1,0)==4 and state.surface_height(32,-0.1)==0.0 and state.surface_height(32,0.1)==0.0)
	check("unknown is not zero ground",state.surface_height(-1000,0)==null and not state.is_cell_known(-2000,0,0))
	var b: Dictionary = Generator.layout().buildings
	var pads: Array = []
	for door in b.home.doors:
		for pad in door.get("use_centers",[]): pads.append(pad)
	for building in b.other_buildings:
		for pad in building.use_centers: pads.append(pad)
	var flat := true
	for pad in pads:
		flat = flat and state.surface_height(pad[0],pad[2])==0.0
	check("all B actual exterior/interior pads have known ground y0",flat,pads.size())
	var p: Dictionary = state.prepare_changes([{"op":"voxel.set","cell":{"x":63,"y":-1,"z":0},"before":4,"after":0}],state.get_revision())
	check("prepare isolates original",p.ok and state.cell_at(63,-1,0)==4 and p.view.cell_at(63,-1,0)==0,p.get("reason"))
	if not p.ok:
		quit(1)
		return
	var copied: Dictionary = p.view.chunk("3,-1,0")
	copied.cells.fill(0)
	check("read APIs do not leak mutable buffers",p.view.cell_at(62,-1,0)==4)
	check("boundary invalidation adjacent + negative z",p.changes.chunks.has("4,-1,0") and p.changes.chunks.has("3,-1,-1"),p.changes.chunks)
	check("forged dictionary rejected",not state.commit_prepared({"draft":generated}).ok)
	var stranger := State.new()
	stranger.load_snapshot(generated)
	check("foreign capability rejected",not stranger.commit_prepared(p.capability).ok)
	var commit: Dictionary = state.commit_prepared(p.capability)
	check("commit swaps exactly once",commit.ok and state.get_revision()==1 and state.cell_at(63,-1,0)==0 and not state.commit_prepared(p.capability).ok)
	var stale_a: Dictionary = state.prepare_changes([],1)
	var next: Dictionary = state.prepare_changes([{"op":"voxel.set","cell":{"x":63,"y":-1,"z":0},"before":0,"after":2}],1)
	state.commit_prepared(next.capability)
	check("stale token refused before swap",not state.commit_prepared(stale_a.capability).ok and state.get_revision()==2)
	check("CAS failure leaves complete state",not state.prepare_changes([{"op":"voxel.set","cell":{"x":63,"y":-1,"z":0},"before":0,"after":3}],2).ok and state.cell_at(63,-1,0)==2)
	var e: Dictionary = state.entity("rural:v1:RH-HOME:tree:01")
	var remove: Dictionary = state.prepare_changes([{"op":"entity.remove","id":e.id,"before":e}],2)
	check("entity remove prepared",remove.ok)
	if remove.ok: state.commit_prepared(remove.capability)
	check("tombstone blocks reuse",not state.prepare_changes([{"op":"entity.put","id":e.id,"before_exists":false,"before":null,"after":e}],state.get_revision()).ok)
	var base: int = state.get_revision()
	var noop: Dictionary = state.prepare_changes([],base)
	state.commit_prepared(noop.capability)
	check("fact-only batch does not increment world revision",state.get_revision()==base)
	var ray: Dictionary = Queries.raycast(state,Vector3(31.75,2,0.25),Vector3(31.75,-2,0.25))
	check("DDA sees actual refilled cell",not ray.get("unknown",true) and ray.cell=={"x":63,"y":-1,"z":0} and ray.material==2,ray)
	var camera_origin := Vector3(43,29.7,69)
	var camera_target := Vector3(19,0,38)
	var camera_direction := (camera_target-camera_origin).normalized()
	var camera_hit: Dictionary = Queries.pick(state,camera_origin,camera_origin+camera_direction*160)
	check("formal orthographic camera outside world slab can pick real terrain",not camera_hit.get("unknown",true) and camera_hit.get("material",0)!=0 and camera_hit.get("distance",0)>29,camera_hit)
	check("safety DDA still blocks unknown exterior",Queries.raycast(state,camera_origin,camera_target).get("unknown",false))
	var mesh_data: Dictionary = Mesher.build(state,"3,-1,0")
	var mesh: ArrayMesh = Mesher.mesh(mesh_data)
	check("actual ArrayMesh and native static shape",mesh.get_surface_count()>0 and mesh.create_trimesh_shape()!=null,mesh_data.quads)
	var winding := true
	for group in mesh_data.groups.values():
		var v: PackedVector3Array = group.vertices
		var ix: PackedInt32Array = group.indices
		for i in range(0,ix.size(),3):
			var cross := (v[ix[i+1]]-v[ix[i]]).cross(v[ix[i+2]]-v[ix[i]])
			if cross.dot(group.normals[ix[i]]) >= 0: winding = false
	check("Godot clockwise face winding",winding)
	var encoded: Dictionary = Codec.encode_checkpoint(state.snapshot(),{"unknown":{"keep":"✅𠮷"},"r3:runtime":{"time":123.4}},"test:1")
	var restored: Dictionary = Codec.decode_checkpoint(encoded.envelope)
	check("native SHA envelope full fact roundtrip",restored.ok and Data.json_equal(restored.state.entities,state.snapshot().entities) and restored.state.retiredEntityIds==[e.id] and restored.extensions.unknown.keep=="✅𠮷",{"decoded":restored.ok,"entity_equal":Data.json_equal(restored.get("state",{}).get("entities",{}),state.snapshot().entities),"unicode":restored.get("extensions",{})})
	var equal_cells := true
	if restored.ok:
		for k in restored.state.chunks:
			if restored.state.chunks[k].cells != state.chunk(k).cells: equal_cells = false
	check("all 512 decoded cell buffers roundtrip",equal_cells)
	var corrupt: Dictionary = encoded.envelope.duplicate(true)
	corrupt.payload += " "
	check("corruption rejected",not Codec.decode_checkpoint(corrupt).ok)
	check("RLE rejects overflow/unknown/short before allocation",not Codec.decode_runs([1,4097],4096).ok and not Codec.decode_runs([99,4096],4096).ok and not Codec.decode_runs([1,1],4096).ok)
	check("legacy JS UTF16 supplementary checksum",Codec.hash_legacy_utf16("树🌳")=="7b4db7c9")
	check("unrepresentable lone surrogate rejected, original retained",Codec.decode_checkpoint('{"value":"\\ud800"}').get("code")=="UNREPRESENTABLE_UNICODE")
	var source := ProjectSettings.globalize_path("res://../../outputs/r3.3-ccc-evidence/ordinary-world-713/validated-source/checkpoint.v5.json")
	var ordinary_start := Time.get_ticks_usec()
	var raw := FileAccess.get_file_as_string(source)
	var ordinary: Dictionary = Codec.decode_checkpoint(raw,"64aee01d22714c0f12c0a19f5a7415d158b548181ec48a885a15332e6d82788e")
	check("REAL ordinary713 v5 original bytes validated natively",ordinary.ok,ordinary.get("reason"))
	var cells_sha := ""
	if ordinary.ok:
		check("ordinary original IDs/revision/6 regions/1536 chunks/417 receipts",ordinary.state.worldId=="world:713" and ordinary.state.revision==417 and ordinary.state.regions.size()==6 and ordinary.state.chunks.size()==1536 and ordinary.state.receipts.size()==417)
		check("ordinary authoritative time unchanged",ordinary.extensions["r3:runtime"].time==1377.3999999998427)
		var source_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.get_base_dir()+"/facts-index.json"))
		var cross_language_equal := true
		for row in source_index.chunks:
			var buffer := PackedByteArray()
			buffer.resize(row.cellCount*2)
			var cells: PackedInt32Array = ordinary.state.chunks[row.key].cells
			for i in cells.size(): buffer.encode_u16(i*2,cells[i])
			var hash_context := HashingContext.new()
			hash_context.start(HashingContext.HASH_SHA256)
			hash_context.update(buffer)
			if hash_context.finish().hex_encode() != row.cellsUint16LESha256: cross_language_equal = false
		check("1536 Godot uint16 LE chunk SHAs equal existing JS decoder",cross_language_equal)
		var native: Dictionary = Codec.encode_checkpoint(ordinary.state,ordinary.extensions,ordinary.checkpoint_id)
		var again: Dictionary = Codec.decode_checkpoint(native.envelope)
		var all_equal: bool = again.ok
		if again.ok:
			for k in ordinary.state.chunks:
				if ordinary.state.chunks[k].cells != again.state.chunks[k].cells: all_equal = false
		check("ordinary native codec preserves every cell/entity/extension/receipt",all_equal and again.state.entities==ordinary.state.entities and again.extensions==ordinary.extensions and again.state.receipts==ordinary.state.receipts)
	var ordinary_us := Time.get_ticks_usec()-ordinary_start
	var tree := Node3D.new()
	root.add_child(tree)
	var terrain := TerrainView.new()
	tree.add_child(terrain)
	terrain.configure({"world":state})
	# Only build affected chunk in this domain check, not a second game preview.
	terrain.on_world_changed({"chunks":["3,-1,0"]})
	await physics_frame
	await physics_frame
	var physics_query := PhysicsRayQueryParameters3D.create(Vector3(31.75,2,0.25),Vector3(31.75,-2,0.25))
	var physical: Dictionary = tree.get_world_3d().direct_space_state.intersect_ray(physics_query)
	check("native physics ray contacts same edited ground",not physical.is_empty() and absf(physical.position.y)<0.001,physical.get("position"))
	var cold: Dictionary = state.prepare_changes([{"op":"chunk.residency","id":"3,-1,0","before":true,"after":false}],state.get_revision())
	var cold_result: Dictionary = state.commit_prepared(cold.capability)
	terrain.on_world_changed(cold_result.changes)
	check("cold retains real cell, removes native projection",state.cell_at(63,-1,0)==2 and not state.chunk("3,-1,0").resident)
	var warm: Dictionary = state.prepare_changes([{"op":"chunk.residency","id":"3,-1,0","before":false,"after":true}],state.get_revision())
	var warm_result: Dictionary = state.commit_prepared(warm.capability)
	terrain.on_world_changed(warm_result.changes)
	check("warm returns unchanged edited material",state.cell_at(63,-1,0)==2 and state.chunk("3,-1,0").resident)
	var tree_name := "rural:v1:RH-HOME:tree:02".validate_node_name()
	var tree_root: Node = terrain.environment.get_node_or_null(NodePath(tree_name))
	check("tree ground attachments initially rest on full footprint",tree_root!=null and tree_root.has_node("GroundShrub_0") and tree_root.has_node("GroundLeaves"))
	# The shrub centre remains solid; only a footprint corner is excavated.
	var corner: Dictionary = state.prepare_changes([{"op":"voxel.set","cell":{"x":100,"y":-1,"z":21},"before":1,"after":0}],state.get_revision())
	if corner.ok:
		terrain.on_world_changed(state.commit_prepared(corner.capability).changes)
		tree_root=terrain.environment.get_node_or_null(NodePath(tree_name))
		check("digging shrub footprint corner removes floating decoration",tree_root!=null and not tree_root.has_node("GroundShrub_0"))
		var refill: Dictionary = state.prepare_changes([{"op":"voxel.set","cell":{"x":100,"y":-1,"z":21},"before":0,"after":1}],state.get_revision())
		terrain.on_world_changed(state.commit_prepared(refill.capability).changes)
		tree_root=terrain.environment.get_node_or_null(NodePath(tree_name))
		check("restoring ground restores derived shrub without new entity",tree_root!=null and tree_root.has_node("GroundShrub_0") and state.entity("rural:v1:RH-HOME:tree:02").id=="rural:v1:RH-HOME:tree:02")
	var leaf_corner: Dictionary = state.prepare_changes([{"op":"voxel.set","cell":{"x":102,"y":-1,"z":22},"before":1,"after":0}],state.get_revision())
	if leaf_corner.ok:
		terrain.on_world_changed(state.commit_prepared(leaf_corner.capability).changes)
		tree_root=terrain.environment.get_node_or_null(NodePath(tree_name))
		check("leaf plane disappears over actual partial ground hole",tree_root!=null and not tree_root.has_node("GroundLeaves"))
	var tree_cold: Dictionary = state.prepare_changes([{"op":"chunk.residency","id":"6,-1,1","before":true,"after":false}],state.get_revision())
	terrain.on_world_changed(state.commit_prepared(tree_cold.capability).changes)
	check("cold resource removes native tree and attachments without deleting identity",terrain.environment.get_node_or_null(NodePath(tree_name))==null and not state.entity("rural:v1:RH-HOME:tree:02").is_empty())
	var tree_warm: Dictionary = state.prepare_changes([{"op":"chunk.residency","id":"6,-1,1","before":false,"after":true}],state.get_revision())
	terrain.on_world_changed(state.commit_prepared(tree_warm.capability).changes)
	tree_root=terrain.environment.get_node_or_null(NodePath(tree_name))
	check("warm revisit preserves hole and grounded attachment decisions",tree_root!=null and not tree_root.has_node("GroundLeaves") and state.cell_at(102,-1,22)==0)
	var stats: Dictionary = terrain.statistics()
	tree.free()
	var result := {"scope":"CCC native domain checks, not formal game acceptance or exported app","godot":Engine.get_version_info().string,"checks":checks,"passed":checks.filter(func(c: Dictionary)->bool:return c.ok).size(),"failed":checks.filter(func(c: Dictionary)->bool:return not c.ok).size(),"elapsed_usec":Time.get_ticks_usec()-started,"ordinary_codec_roundtrip_usec":ordinary_us,"terrain_stats":stats}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result))
	quit(1 if failed else 0)
