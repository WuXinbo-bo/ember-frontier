extends SceneTree
## A-owned, real GPU review of the SAME module entity/BuildingView consumer.
## Presentation fixture only: never creates an economic world, NPC or save.
const Catalog = preload("res://scripts/modules/module_catalog.gd")
const Shape = preload("res://scripts/modules/module_geometry.gd")
const View = preload("res://scripts/buildings/building_view.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Modules = preload("res://scripts/modules/module_service.gd")
const Lighting = preload("res://scripts/presentation/scene_lighting.gd")

class ReviewWorld extends RefCounted:
	var instances: Array = []
	func extension(key: String) -> Variant:
		return {"instances": instances} if key == "r34:modules" else null
	func get_revision() -> int: return 0
	func entity(_id: String) -> Dictionary: return {}

class ReviewService extends RefCounted:
	var context: Dictionary = {}

var stage: Node3D
var model_root: Node3D
var consumer: Node3D
var camera: Camera3D
var heading: Label
var detail: Label
var definitions: Array = []
var selected := 0
var turn := 0
var output := ""
var batch := false
var fit := false
var transparent := false
var village := false
var requested: PackedStringArray = []
var captures: Array = []
var current_counts: Dictionary = {}
var saving := false
var advance_button: Button

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg.begins_with("--ids="): requested = arg.trim_prefix("--ids=").split(",", false)
		elif arg == "--batch": batch = true
		elif arg == "--fit": fit = true
		elif arg == "--transparent": transparent = true; fit = true
		elif arg == "--village": village = true
		else:
			push_error("Unknown architecture review option: " + arg); quit(2); return
	if batch and output.is_empty():
		push_error("Batch review requires explicit --out= directory"); quit(2); return
	for definition: Dictionary in Catalog.definitions():
		var default_match:bool=definition.has("village_family_art") or definition.get("regional_art",false) if village else definition.get("architecture", {}).get("set") == "r34-architecture-30-v1"
		if requested.has(str(definition.id)) or (requested.is_empty() and default_match):
			definitions.append(definition)
	if not requested.is_empty() and definitions.size() != requested.size():
		push_error("A requested architecture definition is absent or duplicated"); quit(3); return
	if definitions.is_empty():
		push_error("No registered architecture definitions; no placeholder fallback"); quit(3); return
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	root.title = "末日余晖 · 实际建筑几何审阅（不写存档）"
	# Match the G0 game viewport; larger exports must not pose as normal-camera detail.
	root.size = Vector2i(1280, 800)
	if transparent: root.size = Vector2i(768, 768); root.transparent_bg = true
	root.content_scale_size = root.size
	stage = Node3D.new(); root.add_child(stage)
	var lighting: Dictionary = Lighting.mount(stage)
	# Asset cutout only: preserve sun/ambient/tonemap, clear the backdrop.
	if transparent: lighting.environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0; camera.near = 0.1; camera.far = 180.0
	stage.add_child(camera); camera.make_current()
	var floor_mesh := PlaneMesh.new(); floor_mesh.size = Vector2(70, 70)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("8f967e"); floor_material.roughness = 1.0
	var floor_node := MeshInstance3D.new(); floor_node.mesh = floor_mesh
	floor_node.material_override = floor_material; floor_node.position.y = -0.025
	if transparent: floor_node.free()
	else: stage.add_child(floor_node)
	make_controls()
	if batch:
		for index: int in definitions.size():
			selected = index
			for quarter: int in 4:
				turn = quarter
				if not mount_definition(): quit(4); return
				await capture()
		if captures.size() != definitions.size() * 4:
			push_error("Incomplete GPU capture set"); quit(5); return
		write_manifest()
		print("ARCHITECTURE_GPU_REVIEW " + JSON.stringify({"definitions": definitions.size(), "captures": captures.size(), "output": output, "gameplay_acceptance": false}))
		quit(0)
	else:
		if not mount_definition(): quit(4)

func make_controls() -> void:
	var layer := CanvasLayer.new(); root.add_child(layer)
	if transparent: layer.visible = false
	var panel := PanelContainer.new(); panel.position = Vector2(20, 20)
	panel.size = Vector2(1240, 108); layer.add_child(panel)
	var box := VBoxContainer.new(); panel.add_child(box)
	heading = Label.new(); heading.add_theme_font_size_override("font_size", 22); box.add_child(heading)
	detail = Label.new(); detail.add_theme_font_size_override("font_size", 13); box.add_child(detail)
	var buttons := HBoxContainer.new(); box.add_child(buttons)
	for title: String in ["上一款", "下一款", "旋转90°", "正常镜头 / 适配", "保存当前图"]:
		var button := Button.new(); button.text = title; buttons.add_child(button)
		match title:
			"上一款": button.pressed.connect(func(): selected = posmod(selected - 1, definitions.size()); mount_definition())
			"下一款": button.pressed.connect(func(): selected = posmod(selected + 1, definitions.size()); mount_definition())
			"旋转90°": button.pressed.connect(func(): turn = posmod(turn + 1, 4); mount_definition())
			"正常镜头 / 适配": button.pressed.connect(func(): fit = not fit; mount_definition())
			"保存当前图": button.pressed.connect(func():
				if not output.is_empty() and not saving:
					await capture(); write_manifest())
		button.disabled = batch or (title == "保存当前图" and output.is_empty())

func mount_definition() -> bool:
	if is_instance_valid(model_root): model_root.free()
	if is_instance_valid(consumer): consumer.free()
	var definition: Dictionary = definitions[selected]
	if not family_is_implemented(definition):
		push_error("Architecture family is not implemented for " + str(definition.id)); return false
	var instance: Dictionary = {"id": "A:architecture-review:" + str(definition.id), "definition_id": definition.id, "geometry_version": definition.geometry_version, "region": "A:architecture-review", "position": {"x": 0, "y": 0, "z": 0}, "quarter_turn": turn, "owner": "home-residents", "status": "operational", "members": [], "config": {}}
	var world := ReviewWorld.new(); world.instances = [instance]
	# Derive the SAME static module plan as construction. Manual modules add a
	# real structure workbench outside Shape.entities; omitting it gives false
	# empty-shed thumbnails. This fixture never commits that plan or creates stock.
	var building: RefCounted = Modules.building_adapter(world, {"actors": [], "stocks": [], "time": 0.0})
	var changes: Array = []; var structures: Dictionary = {"instances": []}
	Modules.append_instance(world, building, instance, definition, changes, structures)
	var service := ReviewService.new(); service.context = {"world": world}
	consumer = View.new(); consumer.service = service
	consumer.manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	consumer._residency["A:architecture-review"] = true
	consumer.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(consumer)
	model_root = Node3D.new(); stage.add_child(model_root)
	current_counts = {"entities": 0, "structures": 0, "meshes": 0, "surfaces": 0, "triangles": 0, "materials": []}
	var materials: Dictionary = {}
	for change: Dictionary in changes:
		var entity: Dictionary = change.after
		# Workbench is drawn by the actual furniture/GLB path below, not twice
		# as its collider. The aggregate selectable target is not a render part.
		if entity.get("data", {}).get("module_target", false) or structures.instances.any(func(v: Dictionary) -> bool: return v.id == entity.id): continue
		var node: Node3D = consumer.entity_object(entity)
		if node == null:
			push_error("Actual BuildingView consumer rejected " + str(entity.id)); return false
		model_root.add_child(node); current_counts.entities += 1
		count_mesh(node, materials)
	for piece: Dictionary in structures.instances:
		var node: Node3D = consumer.furniture(piece, building.geometry.definition(piece))
		if node == null:
			push_error("Actual BuildingView furniture rejected " + str(piece.id)); return false
		model_root.add_child(node); current_counts.structures += 1
		count_mesh(node, materials)
	current_counts.materials = materials.keys()
	if current_counts.meshes == 0:
		push_error("Architecture has no actual renderable mesh"); return false
	var bounds: AABB = Shape.transform_box(instance, Geometry.aabb(definition.footprint))
	var focus := Vector3(bounds.get_center().x, bounds.size.y * 0.35, bounds.get_center().z)
	camera.position = focus + Vector3(24, 29, 31); camera.look_at(focus, Vector3.UP)
	camera.size = maxf(12, maxf(bounds.size.x, bounds.size.z) * 1.65) if fit else 24.0
	var architecture: Dictionary = definition.get("architecture", {})
	var capacity: String = " · 设计容纳%d人" % int(architecture.design_capacity) if architecture.has("design_capacity") else ""
	heading.text = "%02d/%02d  %s%s · 方向%d" % [selected + 1, definitions.size(), str(definition.name), capacity, turn]
	detail.text = "%s · 同游戏材质/光照/几何管线 · 几何审阅，非玩法验收" % str(definition.id)
	return true

func family_is_implemented(definition: Dictionary) -> bool:
	# Mechanism definitions are explicit derivatives. Resolve their declared
	# source using the SAME dispatcher, including the new housing-v2 portal/
	# bed geometry; never substitute a v1 source image or strip ID suffixes.
	if definition.has("geometry_source_id"):
		var original:Dictionary=Catalog.definition_view(str(definition.geometry_source_id))
		if original.is_empty() or original.has("geometry_source_id"):return false
		if definition.geometry_version!=original.geometry_version and not preload("res://scripts/modules/module_housing.gd").applies(definition):return false
		return family_is_implemented(original) and not Shape.parts(definition).is_empty()
	var architecture: Dictionary = definition.get("architecture", {})
	if architecture.get("set") != "r34-architecture-30-v1": return true
	var family: String = str(architecture.get("family", ""))
	var path: String = ""
	match family:
		"home": path = "res://scripts/modules/module_residential_geometry.gd"
		"sawmill", "warehouse", "canteen", "artisan": path = "res://scripts/modules/module_industrial_geometry.gd"
		"water", "repair", "guard": path = "res://scripts/modules/module_civic_geometry.gd"
	if path.is_empty() or not ResourceLoader.exists(path): return false
	var source: Script = load(path)
	return source != null and bool(source.call("supports", definition))

func count_mesh(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		current_counts.meshes += 1
		for surface: int in node.mesh.get_surface_count():
			current_counts.surfaces += 1
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			current_counts.triangles += indices.size() / 3
			var material: Material = node.get_active_material(surface)
			if material == null:
				push_error("Unbound architecture surface")
			else:
				materials[str(material.get_instance_id())] = true
	for child: Node in node.get_children(): count_mesh(child, materials)

func capture() -> void:
	saving = true
	# Wait for actual renderer completion. Headless/dummy images are rejected.
	for frame: int in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("No GPU image; headless cannot qualify visual review"); saving = false; return
	var definition: Dictionary = definitions[selected]
	var name: String = str(definition.id).replace(".", "_") + "-q%d-%s.png" % [turn, "cutout" if transparent else ("fit" if fit else "normal")]
	var path: String = output.path_join(name)
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Cannot save architecture review image: " + path); saving = false; return
	captures.append({"definition_id": definition.id, "geometry_version": definition.geometry_version, "quarter_turn": turn, "camera_size": camera.size, "camera_offset": [24, 29, 31], "viewport": [root.size.x, root.size.y], "cutout": transparent, "image": path, "counts": current_counts.duplicate(true), "renderer": RenderingServer.get_video_adapter_name(), "architecture": definition.get("architecture", {}).duplicate(true)})
	saving = false

func write_manifest() -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output.path_join("render-manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot save architecture render manifest"); return
	file.store_string(JSON.stringify({"schema": "afterglow-architecture-gpu-review-v2", "captures": captures, "actual_consumer": "module_service.append_instance -> building_view.entity_object + building_view.furniture (original workbench)", "lighting": "scene_lighting.mount; cutout only overrides background clear", "ground": "none/transparent cutout" if transparent else "neutral review ground only", "scope": "real GPU static geometry/material review; explicit presentation fixture, no fake inventory, economy/world generation/OS gameplay or FPS acceptance", "gameplay_accepted": false}, "\t", true, true))
	file.close()
