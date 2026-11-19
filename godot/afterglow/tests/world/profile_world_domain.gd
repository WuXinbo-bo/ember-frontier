extends SceneTree
const State = preload("res://scripts/world/world_state.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source := ProjectSettings.globalize_path("res://../../outputs/r3.3-ccc-evidence/ordinary-world-713/validated-source/checkpoint.v5.json")
	var result := {"scope":"CCC headless native domain cost, not game FPS/Metal/app acceptance","godot":Engine.get_version_info().string,"samples":{}}
	var t := Time.get_ticks_usec()
	var decoded: Dictionary = Codec.decode_checkpoint(FileAccess.get_file_as_string(source))
	if not decoded.ok: print(decoded); quit(1); return
	result.samples.legacy_decode_usec = Time.get_ticks_usec()-t
	var world := State.new()
	t = Time.get_ticks_usec()
	world.load_snapshot(decoded.state)
	result.samples.validated_load_usec = Time.get_ticks_usec()-t
	t = Time.get_ticks_usec()
	var copy: Dictionary = world.snapshot()
	result.samples.isolated_snapshot_usec = Time.get_ticks_usec()-t
	t = Time.get_ticks_usec()
	var encoded: Dictionary = Codec.encode_checkpoint(copy,decoded.extensions,decoded.checkpoint_id)
	result.samples.encode_usec = Time.get_ticks_usec()-t
	result.native_payload_bytes = encoded.envelope.payloadBytes
	result.authoritative_cells = 6291456
	result.packed_int32_cell_bytes = 6291456*4
	result.legacy_uint16_cell_bytes = 6291456*2
	var samples: Array = []
	for i in 12:
		t = Time.get_ticks_usec()
		var plan: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":{"x":-1,"y":-1,"z":-1},"before":1,"after":2}],world.get_revision())
		samples.append(Time.get_ticks_usec()-t)
		if not plan.ok: print(plan); quit(1); return
		world.discard_prepared(plan.capability)
	result.samples.prepare_same_real_world_usec = samples
	var c: Dictionary = world.chunk("-1,-1,-1")
	var warm: Dictionary = world.prepare_changes([{"op":"chunk.residency","id":c.key,"before":false,"after":true}],world.get_revision())
	world.commit_prepared(warm.capability)
	t = Time.get_ticks_usec()
	var greedy: Dictionary = Mesher.build(world,c.key)
	result.samples.greedy_build_usec = Time.get_ticks_usec()-t
	t = Time.get_ticks_usec()
	var naive: Dictionary = Mesher.build(world,c.key,false)
	result.samples.unit_face_build_usec = Time.get_ticks_usec()-t
	result.greedy_quads = greedy.quads
	result.unit_face_quads = naive.quads
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var f := FileAccess.open(args[0],FileAccess.WRITE)
		f.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result))
	quit()
