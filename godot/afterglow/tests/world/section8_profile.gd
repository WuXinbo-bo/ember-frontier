extends SceneTree
## Paired same-process domain timing, never a formal game FPS/Metal benchmark.
const BeforeState = preload("res://tests/world/section8_baseline_state.gd")
const AfterState = preload("res://scripts/world/world_state.gd")
const BeforeEnvironment = preload("res://../../outputs/r3.3-ccc-evidence/section8-before/environment_view.gd")
const AfterEnvironment = preload("res://scripts/environment/environment_view.gd")
const BeforeMesher = preload("res://../../outputs/r3.3-ccc-evidence/section8-before/terrain_mesher.gd")
const AfterMesher = preload("res://scripts/terrain/terrain_mesher.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const TerrainView = preload("res://scripts/terrain/terrain_view.gd")
const BeforeTerrainView = preload("res://tests/world/section8_baseline_terrain_view.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
var checks: Array = []
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))
func times(callable: Callable,count: int=12) -> Array:
	callable.call() # excluded warm-up, for each side
	var out: Array = []
	for i in count:
		var t := Time.get_ticks_usec();callable.call();out.append(Time.get_ticks_usec()-t)
	return out
func summary(samples: Array) -> Dictionary:
	var sorted := samples.duplicate();sorted.sort()
	return {"samples_usec":samples,"median_usec":(float(sorted[5])+float(sorted[6]))/2.0,"max_usec":sorted[-1]}
func prepare_one(world: RefCounted) -> void:
	var p: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":{"x":-1,"y":-1,"z":-1},"before":1,"after":2}],world.get_revision())
	if not p.ok: push_error(str(p));return
	world.discard_prepared(p.capability)
func projection(world: RefCounted,env_script: GDScript) -> Node3D:
	var view: Node3D = BeforeTerrainView.new() if env_script==BeforeEnvironment else TerrainView.new()
	view.set_process(false)
	view.world=world;view.materials=Materials.new();root.add_child(view)
	view.environment=env_script.new();view.add_child(view.environment)
	view.environment.configure({"world":world,"materials":view.materials})
	return view
func queries(world: RefCounted) -> float:
	var value := 0.0
	for x in range(-16,16):
		for z in range(-16,16):
			var h: Variant = world.surface_height(x*0.5,z*0.5)
			value += float(h) if h!=null else -999.0
			value += world.cell_at(x,-1,z)
	return value

func query_values(world: RefCounted) -> Array:
	var out: Array = []
	for x in range(-16,16):
		for z in range(-16,16): out.append([world.surface_height(x*0.5,z*0.5),world.cell_at(x,-1,z)])
	return out

func same_geometry(a: Dictionary,b: Dictionary) -> bool:
	if a.quads!=b.quads or a.groups.keys()!=b.groups.keys() or a.solid_cells!=b.solid_cells: return false
	for id in a.groups:
		for field in ["vertices","normals","indices"]:
			if a.groups[id][field]!=b.groups[id][field]: return false
	return true

func small_mesh_cases() -> bool:
	# Deliberately different occupied shapes exercise the slab proof and its
	# fallback. Neighbours include holes and cold chunks; this protects exact
	# face geometry/collision input rather than comparing only quad totals.
	var random := RandomNumberGenerator.new();random.seed=713
	for pattern in 12:
		var fixture := {"schemaVersion":1,"worldId":"fixture:mesh-cases","seed":713,"generatorVersion":"rural-1","revision":0,"config":{"cellSize":0.5,"chunkCells":4,"minCellY":-8,"maxCellY":40,"maxEditCells":256,"maxReach":2.5},"regions":{},"entities":{},"extensions":{},"receipts":{},"retiredEntityIds":[],"chunks":{}}
		for cx in range(-1,2):
			for cy in range(-1,2):
				for cz in range(-1,2):
					var key := "%d,%d,%d" % [cx,cy,cz]
					var cells := PackedInt32Array();cells.resize(64)
					for i in 64:
						var y := i/16
						if pattern==0: cells[i]=0
						elif pattern==1: cells[i]=2
						elif pattern==2: cells[i]=random.randi_range(1,6) if y in [1,2] else 0
						elif pattern==3: cells[i]=2 if y==0 or y==3 else 0
						elif pattern==4: cells[i]=0 if i==21 else 2
						elif pattern==5: cells[i]=2 if y<=i%4 else 0
						else: cells[i]=random.randi_range(0,6)
					fixture.chunks[key]={"key":key,"coord":{"x":cx,"y":cy,"z":cz},"cells":cells,"revision":0,"resident":not (pattern==8 and cx==1),"generated":true,"generatorVersion":"rural-1"}
		var old := BeforeState.new();var current := AfterState.new()
		if not old.load_snapshot(fixture).ok or not current.load_snapshot(fixture).ok: return false
		for greedy in [true,false]:
			if not same_geometry(BeforeMesher.build(old,"0,0,0",greedy),AfterMesher.build(current,"0,0,0",greedy)): return false
	return true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var raw := FileAccess.get_file_as_string("res://../../outputs/r3.3-ccc-evidence/ordinary-world-713/validated-source/checkpoint.v5.json")
	var decoded: Dictionary = Codec.decode_checkpoint(raw)
	if not decoded.ok: print(decoded);quit(1);return
	var old := BeforeState.new();var current := AfterState.new()
	check("same complete ordinary source loads",old.load_snapshot(decoded.state).ok and current.load_snapshot(decoded.state).ok)
	check("all ordinary facts identical before measurement",old.snapshot()==current.snapshot())
	var before_prepare := times(func():prepare_one(old))
	var after_prepare := times(func():prepare_one(current))
	var query_equal := query_values(old)==query_values(current)
	check("query outputs identical on 1024 negative/positive columns",query_equal)
	var before_queries := times(func():queries(old))
	var after_queries := times(func():queries(current))
	var cases := [
		[{"op":"voxel.set","cell":{"x":-1,"y":-1,"z":-1},"before":0,"after":2}],
		[{"op":"voxel.set","cell":{"x":-1,"y":-1,"z":-1},"before":1,"after":99}],
		[{"op":"voxel.set","cell":{"x":-100000,"y":0,"z":0},"before":0,"after":2}],
		[{"op":"chunk.residency","id":"-1,-1,-1","before":false,"after":"true"}],
		[{"op":"extension.set","id":"fixture:bad","before_exists":false,"before":null,"after":{"n":NAN}}],
		[{"op":"entity.put","id":"fixture:bad","before_exists":false,"before":null,"after":{"id":"fixture:bad"}}]
	]
	var rejection_equal := true
	for ops in cases:
		var a: Dictionary = old.prepare_changes(ops,old.get_revision())
		var b: Dictionary = current.prepare_changes(ops,current.get_revision())
		rejection_equal=rejection_equal and not a.ok and not b.ok and a.code==b.code
	check("CAS/material/unknown/residency/JSON/structural rejections preserved",rejection_equal)
	var candidate: Dictionary = current.prepare_changes([{"op":"voxel.set","cell":{"x":-1,"y":-1,"z":-1},"before":1,"after":2}],current.get_revision())
	candidate.view._state.chunks["-1,-1,-1"].cells.fill(0)
	check("public draft reflection cannot mutate private capability commit",current.commit_prepared(candidate.capability).ok and current.cell_at(-1,-1,-1)==2 and current.cell_at(-2,-1,-1)==old.cell_at(-2,-1,-1))
	check("single-use capability still rejected",not current.commit_prepared(candidate.capability).ok)
	var max_cells := PackedInt32Array();max_cells.resize(64);max_cells.fill(1)
	var exhausted := {"schemaVersion":1,"worldId":"fixture:max-revision","seed":713,"generatorVersion":"rural-1","revision":9007199254740991,"config":{"cellSize":0.5,"chunkCells":4,"minCellY":-8,"maxCellY":40,"maxEditCells":256,"maxReach":2.5},"regions":{},"entities":{},"extensions":{},"receipts":{},"retiredEntityIds":[],"chunks":{"0,-1,0":{"key":"0,-1,0","coord":{"x":0,"y":-1,"z":0},"cells":max_cells,"revision":0,"resident":true,"generated":true,"generatorVersion":"rural-1"}}}
	var max_world := AfterState.new()
	var max_loaded: Dictionary = max_world.load_snapshot(exhausted)
	var max_noop: Dictionary = max_world.prepare_changes([],max_world.get_revision()) if max_loaded.ok else max_loaded
	check("exhausted revision still permits identity-preserving no-op",max_noop.ok and max_world.commit_prepared(max_noop.capability).ok,{"load":max_loaded,"prepare_ok":max_noop.ok,"prepare_code":max_noop.get("code"),"prepare_reason":max_noop.get("reason"),"revision":max_world.get_revision()})
	var overflow: Dictionary = max_world.prepare_changes([{"op":"voxel.set","cell":{"x":0,"y":-1,"z":0},"before":1,"after":2}],max_world.get_revision())
	check("revision overflow refuses mutation and preserves original cell",not overflow.ok and max_world.cell_at(0,-1,0)==1,{"prepare_ok":overflow.ok,"code":overflow.get("code"),"cell":max_world.cell_at(0,-1,0)})
	check("12 slab/hole/cave/step/negative-neighbour cases preserve exact geometry both greedy modes",small_mesh_cases())
	var generated: Dictionary = Generator.generate(713)
	var rural_before := BeforeState.new();rural_before.load_snapshot(generated)
	var rural_after := AfterState.new();rural_after.load_snapshot(generated)
	var old_view := projection(rural_before,BeforeEnvironment)
	var new_view := projection(rural_after,AfterEnvironment)
	var key := "3,-1,0"
	var before_rebuild: Array = [];var after_rebuild: Array = []
	# Alternate measurement order. Drain retired scene objects outside timings.
	old_view._rebuild(key);new_view._rebuild(key);await process_frame
	for i in 12:
		for side in ([0,1] if i%2==0 else [1,0]):
			var t := Time.get_ticks_usec()
			(old_view if side==0 else new_view)._rebuild(key)
			(before_rebuild if side==0 else after_rebuild).append(Time.get_ticks_usec()-t)
		await process_frame
	var mesh_before: Dictionary = BeforeMesher.build(rural_before,key)
	var mesh_after: Dictionary = AfterMesher.build(rural_after,key)
	var geometry_equal: bool = mesh_before.quads==mesh_after.quads and mesh_before.groups.keys()==mesh_after.groups.keys()
	for id in mesh_before.groups:
		for field in ["vertices","normals","indices"]: geometry_equal=geometry_equal and mesh_before.groups[id][field]==mesh_after.groups[id][field]
	check("same greedy geometry and collision input retained; UV change intentional",geometry_equal)
	check("rural authority remains byte-equivalent after repeated derivation",rural_before.snapshot()==rural_after.snapshot())
	# Replay the actual router-verified 2x2, two-layer level removal on each
	# source, so the generic mesher path is measured too (slab proof must fail).
	var edit: Array = []
	for z in range(60,62):
		for x in range(59,61):
			for y in [-2,-1]: edit.append({"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":rural_before.cell_at(x,y,z),"after":0})
	for w in [rural_before,rural_after]:
		var p: Dictionary = w.prepare_changes(edit,w.get_revision())
		check("identical real-command edit replay committed",p.ok and w.commit_prepared(p.capability).ok)
	var edited_key := "3,-1,3"
	var before_complex: Array = [];var after_complex: Array = []
	old_view._rebuild(edited_key);new_view._rebuild(edited_key);await process_frame
	for i in 12:
		for side in ([0,1] if i%2==0 else [1,0]):
			var t := Time.get_ticks_usec()
			(old_view if side==0 else new_view)._rebuild(edited_key)
			(before_complex if side==0 else after_complex).append(Time.get_ticks_usec()-t)
		await process_frame
	var edited_old: Dictionary = BeforeMesher.build(rural_before,edited_key)
	var edited_new: Dictionary = AfterMesher.build(rural_after,edited_key)
	var edited_equal: bool = edited_old.quads==edited_new.quads and edited_old.groups.keys()==edited_new.groups.keys()
	for id in edited_old.groups:
		for field in ["vertices","normals","indices"]: edited_equal=edited_equal and edited_old.groups[id][field]==edited_new.groups[id][field]
	check("post-edit complex fallback geometry unchanged",edited_equal)
	var failed := checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"CCC same-input headless native CPU comparison; excludes Metal/GPU/formal app FPS","godot":Engine.get_version_info().string,"fixture":{"ordinary_world":"world:713","regions":6,"chunks":1536,"cells":6291456,"rural_chunk":key,"rural_quads":mesh_after.quads,"post_edit_chunk":edited_key,"post_edit_quads":edited_new.quads},"before":{"prepare":summary(before_prepare),"query_1024_columns":summary(before_queries),"chunk_rebuild":summary(before_rebuild),"post_edit_rebuild":summary(before_complex)},"after":{"prepare":summary(after_prepare),"query_1024_columns":summary(after_queries),"chunk_rebuild":summary(after_rebuild),"post_edit_rebuild":summary(after_complex)},"checks":checks,"failed":failed,"soft_budget_usec":4000,"budget_is_hard_guarantee":false}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var f := FileAccess.open(args[0],FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result));old_view.free();new_view.free();quit(1 if failed else 0)
