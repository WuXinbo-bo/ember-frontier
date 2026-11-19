extends SceneTree
## Geometry/derivation cost only, warmed shared materials and same actual B seed.
## No rendering/GPU/FPS claims. Original environment bytes preserved separately.
const State = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
const Before = preload("res://tests/world/fourth_baseline_environment.gd")
const After = preload("res://scripts/environment/environment_view.gd")
var checks: Array = []
var world := State.new()
var materials := Materials.new()

func _initialize() -> void: call_deferred("run")
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label)

func sample(script: GDScript) -> Dictionary:
	var view: Node3D=script.new();root.add_child(view)
	var t := Time.get_ticks_usec();view.configure({"world":world,"materials":materials})
	var configure_ms := float(Time.get_ticks_usec()-t)/1000.0
	t=Time.get_ticks_usec();view.sync()
	var sync_ms := float(Time.get_ticks_usec()-t)/1000.0
	t=Time.get_ticks_usec();view.on_world_changed({"chunks":[],"entities":[]})
	var extension_notification_ms := float(Time.get_ticks_usec()-t)/1000.0
	t=Time.get_ticks_usec();view.on_world_changed({"chunks":["3,-1,3"],"entities":[]})
	var terrain_notification_ms := float(Time.get_ticks_usec()-t)/1000.0
	var keys := ["0,-1,3","1,-1,3","2,-1,3","3,-1,3","0,-1,5","1,-1,5","3,-1,5","4,-1,5"]
	var rows: Array = []
	for key in keys:
		t=Time.get_ticks_usec();view.rebuild_ground(key)
		rows.append({"chunk":key,"ms":float(Time.get_ticks_usec()-t)/1000.0})
	var stats: Dictionary = view.statistics()
	var mesh_count := 0;var vertices := 0;var triangles := 0;var surfaces := 0
	for node in view.find_children("*","MeshInstance3D",true,false):
		mesh_count+=1;surfaces+=node.mesh.get_surface_count()
		for surface in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			vertices+=arrays[Mesh.ARRAY_VERTEX].size();triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
	view.free()
	return {"configure_ms":configure_ms,"unchanged_sync_ms":sync_ms,"extension_notification_ms":extension_notification_ms,"terrain_notification_ms":terrain_notification_ms,"rebuild":rows,"geometry":{"mesh_instances":mesh_count,"vertices":vertices,"triangles":triangles,"surfaces":surfaces},"statistics":stats}

func run() -> void:
	world.load_snapshot(Generator.generate())
	var building := Building.new();building.geometry.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
	var seed: Dictionary=building.seed_rural(world)
	var p: Dictionary=world.prepare_changes(seed.world_changes,world.get_revision())
	check("same real B seed installed",p.ok and world.commit_prepared(p.capability).ok)
	var saved: Dictionary=world.snapshot()
	var t := Time.get_ticks_usec()
	for id in materials.manifest(): materials.material(id)
	materials.contact_material()
	for id in [2,4,6]: materials.shoulder_material(id)
	var texture_prepare_ms := float(Time.get_ticks_usec()-t)/1000.0
	var before: Array=[];var after: Array=[]
	for i in 10:
		var left: Dictionary;var right: Dictionary
		if i%2==0: left=sample(Before);right=sample(After)
		else: right=sample(After);left=sample(Before)
		if i>=2: before.append(left);after.append(right)
		await process_frame
	check("both projections preserve all authoritative world facts",world.snapshot()==saved)
	check("both sides retain the same standing tree count and shoulder chunk workload",before.all(func(s:Dictionary)->bool:return s.statistics.tree_roots==after[0].statistics.tree_roots and s.statistics.ground_transition_chunks==after[0].statistics.ground_transition_chunks))
	check("shoulder material correction retains identical nodes/vertices/triangles/contact facts",after.all(func(s: Dictionary)->bool:return s.geometry.mesh_instances==before[0].geometry.mesh_instances and s.geometry.vertices==before[0].geometry.vertices and s.geometry.triangles==before[0].geometry.triangles and s.statistics.foundation_contact_quads==before[0].statistics.foundation_contact_quads))
	var failed := checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"fourth-package shoulder-fix warmed same-world CPU/geometry; no native app/GPU/FPS qualification","engine":Engine.get_version_info(),"samples_per_side":8,"excluded_warmups_per_side":2,"shared_current_material_loader":true,"material_prepare_ms":texture_prepare_ms,"before":before,"after":after,"checks":checks,"failed":failed}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var f := FileAccess.open(args[0],FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify({"failed":failed,"samples":8,"before_geometry":before[0].geometry,"after_geometry":after[0].geometry}));quit(1 if failed else 0)
