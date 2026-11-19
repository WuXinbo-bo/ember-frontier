extends Node3D
## Derived, editable-world presentation. No reward/inventory or authority in render nodes.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const MeshBuilder = preload("res://scripts/buildings/building_mesh.gd")
const Details = preload("res://scripts/buildings/building_details.gd")
const SurfaceState = preload("res://scripts/buildings/building_surface_state.gd")
const ModuleFacade=preload("res://scripts/buildings/module_facade_detail.gd")
const ModuleRoof=preload("res://scripts/buildings/module_roof_mesh.gd")
const QualityFacade=preload("res://scripts/buildings/module_quality_facade.gd")
const ArchitectureDetail=preload("res://scripts/buildings/architecture_detail_mesh.gd")
const ProductionMaterials=preload("res://scripts/presentation/factory_materials.gd")
const Costs=preload("res://scripts/runtime/frame_costs.gd")
var _residency:Dictionary={}
var service: RefCounted
var runtime_ref: WeakRef
var manifest: Dictionary
var materials: Dictionary = {}
var models: Dictionary = {}
var texture_cache: Dictionary = {}
# Native meshes retain this view's material resources. Only immutable,
# explicit architecture recipes share them; entity nodes stay independent.
const ARCHITECTURE_MESH_LIMIT:=128
var _architecture_meshes:Dictionary={}
var _architecture_manifest:Dictionary={}
var _architecture_bindings:Dictionary={}
var _architecture_mesh_stats:Dictionary={"hit":0,"miss":0,"evict":0,"invalidations":0,"build_usec":0}
var static_nodes: Dictionary = {}
var objects: Dictionary = {}
var content_nodes: Dictionary = {}
var content_signatures: Dictionary = {}
var doors: Dictionary = {}
var visibility_key := ""
var content_key := ""
var state_key := ""
var state_revision := 0
var batches: Dictionary = {}
var roof_wall_ids: Dictionary = {}
var roof_cutaway:=preload("res://scripts/buildings/building_roof_cutaway.gd").new()
var _roof_query:RefCounted
var _view_policy:RefCounted
var _policy_query:RefCounted
var _visibility_query:RefCounted
var _local_shell_basis: Array = []
var _local_shell_results: Dictionary = {}
var _outdoor_shell_groups: Dictionary = {}
var _outdoor_shell_nodes: Dictionary = {}
var _outdoor_shell_dirty: bool = true
var _refresh_delay := 0.0
var _visibility_queued:=false
var _last_visibility_scope: Array = []
const VISIBILITY_INTERVAL := 0.075
var _stage_generation := false
var _generation_rebuild_frame := -1
var _generated_regions: Dictionary = {}
const FLOOR_SKIN := 0.012

func configure(context: Dictionary) -> void:
	_architecture_meshes.clear();_architecture_manifest.clear();_architecture_bindings.clear()
	_architecture_mesh_stats={"hit":0,"miss":0,"evict":0,"invalidations":0,"build_usec":0}
	service = context.service
	var runtime: Variant = context.get("runtime")
	if runtime != null: runtime_ref = weakref(runtime); runtime.changed.connect(_changed)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	# Resolve surfaces when their actual mesh is assembled. A cold/absent
	# building must not decode every floor, roof, decal and inventory atlas.
	# finish_mesh still binds ALL used materials synchronously before return.
	var glass := StandardMaterial3D.new(); glass.albedo_color=Color(0.43,0.63,0.66,0.27); glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; glass.roughness=0.45; materials.glass=glass
	rebuild()

func finish_mesh(builder:RefCounted)->ArrayMesh:
	for id:String in builder.groups:material(id)
	return builder.mesh(materials)

func has_surface(id:Variant)->bool:
	# Preserve the old authored-finish eligibility of eager catalog entries
	# without forcing their textures into a view that never draws them.
	return materials.has(id) or (manifest.textures.has(id) and not manifest.textures[id].get("lazy",false))

func material(id:String)->StandardMaterial3D:
	if materials.has(id):return materials[id]
	if ProductionMaterials.is_architecture(id):
		var architectural:StandardMaterial3D=ProductionMaterials.architecture_material(id)
		if architectural!=null:materials[id]=architectural
		return architectural
	if not manifest.textures.has(id):return null
	var entry:Dictionary=manifest.textures[id]
	var m:=StandardMaterial3D.new()
	# Native per-view resources are shared only once actually used. Expanded
	# state families must not eagerly allocate every possible 1024px image.
	m.albedo_texture=texture(str(entry.resource),entry.uv.get("repeat",true));m.roughness=0.91
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode=BaseMaterial3D.CULL_DISABLED
	if not entry.uv.get("repeat",true):m.texture_repeat=false
	if id in ["plaster_crack","brick_wear","damp","threshold","wall_dust","dust_corner","rust_runoff","sawdust","repaired_plaster","board_patch","moved_trace"] or entry.get("alpha",false):
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;m.alpha_scissor_threshold=0.25
	if id=="damaged_wood":m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	materials[id]=m
	return m

func texture(path: String, with_mipmaps:bool=false) -> Texture2D:
	var key:=path+"|mip" if with_mipmaps else path+"|canvas"
	if texture_cache.has(key):return texture_cache[key]
	var result:Texture2D
	if ResourceLoader.exists(path):
		var imported: Variant = load(path)
		if imported is Texture2D:result=imported
	if result==null:
		var picture := Image.load_from_file(path)
		if picture!=null and not picture.is_empty():result=ImageTexture.create_from_image(picture)
	if result!=null and with_mipmaps:
		# Same native path as C EnvironmentMaterials; never edits PNG/imports or
		# a ResourceLoader-shared image. Build once per actual view resource.
		var image:=result.get_image()
		if image!=null and not image.has_mipmaps():
			image=image.duplicate()
			if image.is_compressed() and image.decompress()!=OK:return result
			if image.generate_mipmaps()==OK:result=ImageTexture.create_from_image(image)
	if result!=null:texture_cache[key]=result
	return result

func model(id: String) -> Node3D:
	if not manifest.models.has(id): return null
	if not models.has(id):
		var path: String = manifest.models[id].resource
		var imported: Variant = load(path) if ResourceLoader.exists(path) else null
		if imported is PackedScene: models[id]=imported
		else:
			var document := GLTFDocument.new(); var state := GLTFState.new()
			if document.append_from_buffer(FileAccess.get_file_as_bytes(path), path.get_base_dir(), state) != OK: return null
			var root := document.generate_scene(state)
			var scene := PackedScene.new(); scene.pack(root); root.free(); models[id]=scene
	var root: Node3D = models[id].instantiate()
	nearest(root)
	return root

func nearest(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(i)
			if original is StandardMaterial3D:
				var m: StandardMaterial3D = original.duplicate(); m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS; m.roughness=0.9
				node.set_surface_override_material(i,m)
	for child in node.get_children(): nearest(child)

static func contents_state_unchanged(changes:Dictionary)->bool:
	# These two projections read stocks/holders and world order extensions,
	# never the clock or actor motion. Accept only the known notification
	# shapes; edits, lifecycle, inventory and unknown messages stay immediate.
	if not changes.get("revision") is int or int(changes.revision)<0:return false
	if changes.has("clock"):
		for key:Variant in changes:
			if key not in ["clock","revision","simulation"]:return false
		var clock:Variant=changes.clock
		return (clock is int or clock is float) and is_finite(float(clock)) and float(clock)>=0 and (not changes.has("simulation") or changes.simulation is Dictionary)
	for key:Variant in changes:
		if key not in ["world","facts","events","revision","actor_transitions"]:return false
	if not changes.get("world") is Array or not changes.world.is_empty():return false
	if not changes.get("actor_transitions") is Array or not changes.actor_transitions.is_empty():return false
	if not changes.get("facts") is Array or changes.facts.is_empty() or not changes.get("events") is Array or changes.events.is_empty():return false
	var actors:Dictionary={};var moved:Dictionary={}
	for fact:Variant in changes.facts:
		if not fact is Dictionary or fact.get("collection")!="actors" or not fact.get("id") is String or str(fact.id).is_empty():return false
		for key:Variant in fact:
			if key not in ["collection","id","before","after"]:return false
		if not fact.get("before") is Dictionary or not fact.get("after") is Dictionary or fact.before.get("id")!=fact.id or fact.after.get("id")!=fact.id:return false
		actors[fact.id]=true
	for event:Variant in changes.events:
		if not event is Dictionary or event.get("kind")!="actor-moved" or not actors.has(event.get("actor_id")) or event.get("mode") not in ["walk","run"]:return false
		for key:Variant in event:
			if key not in ["kind","actor_id","mode","elapsed","id","revision","time"]:return false
		var elapsed:Variant=event.get("elapsed")
		if not (elapsed is int or elapsed is float) or not is_finite(float(elapsed)) or float(elapsed)<0:return false
		moved[event.actor_id]=true
	return moved.size()==actors.size()

func _changed(changes: Dictionary) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_changed(changes)
	preload("res://scripts/runtime/frame_costs.gd").end("buildings/change_projection.gd",measured)

func _profiled_changed(changes: Dictionary) -> void:
	# Other actors are drawn by ActorView and never participate in these
	# shell/content sight rays. A complete actor-only notification with no
	# player fact, transition or world mutation cannot change this view.
	# In particular, distant walkers must not repeatedly sample every room.
	if other_actor_facts_only(changes):return
	if contents_state_unchanged(changes):
		_queue_visibility()
		return
	var operations:Array=changes.get("world",[])
	var events: Array = changes.get("events", [])
	if _stage_generation and events.size() == 1 and events[0].get("kind") == "region_generated":
		var region_id := str(events[0].get("region_id", ""))
		if _is_additive_region_notification(region_id, operations):
			# No existing world object is edited by this publication. Rebuild
			# only the new region after the decorative ecology update.
			_generated_regions[region_id] = true
			_generation_rebuild_frame = Engine.get_process_frames() + 2
			return
	if not changes.get("reload",false) and changes.get("facts",[]).is_empty() and changes.get("actor_transitions",[]).is_empty() and not operations.is_empty() and operations.all(func(op:Dictionary)->bool:return op.get("op") in ["chunk.storage","chunk.residency"]):
		# Building eligibility depends on whole-region residency, not on which
		# batch was paged. Rebuild only at an actual eligibility transition;
		# the other batches cannot change any of these meshes or their data.
		var warming:Array=[]
		var cooling:Dictionary={}
		for id:String in _residency:
			var resident:bool=service.context.world.region_is_resident(id)
			if resident!=_residency[id]:
				if resident:warming.append(id)
				else:cooling[id]=true
			_residency[id]=resident
		_roof_query=null;_policy_query=null
		if not cooling.is_empty():_retire_paged_regions(cooling)
		if not warming.is_empty():rebuild(warming,true)
		else:_queue_visibility()
		return
	var geometry_changed := false
	var piece_updates: Array = []
	var object_updates:Dictionary={}
	for op in changes.get("world",[]):
		if op.get("op") in ["chunk.storage","chunk.residency"]:_residency.clear();geometry_changed=true;break
		var before:Dictionary=op.get("before",{}) if op.get("before") is Dictionary else {}
		if op.get("op")=="entity.remove":
			if doors.has(op.id) or before.get("kind")=="structure":geometry_changed=true;break
			if objects.has(op.id) or before.get("kind") in ["prop","container"]:object_updates[op.id]={}
		if op.get("op") == "entity.put":
			var after:Dictionary=op.get("after",{})
			var next: Dictionary=op.get("after",{}).get("data",{}).get("structure",{})
			var previous: Dictionary=op.get("before",{}).get("data",{}).get("structure",{}) if op.get("before") is Dictionary else {}
			if same_static_shape(previous,next):piece_updates.append({"before":previous,"after":next})
			elif not next.is_empty() or not previous.is_empty():geometry_changed=true;break
			elif after.get("kind") in ["prop","container"] or before.get("kind") in ["prop","container"] or objects.has(op.id):object_updates[op.id]=after
	if geometry_changed:
		var generated:Array=[]
		for event:Dictionary in changes.get("events",[]):
			if event.get("kind")=="region_generated":generated.append(str(event.region_id))
		rebuild(generated)
	else:
		# C canonicalizes entity revisions at commit. The change-set payload is
		# the requested proposal, so read the committed object once by ID rather
		# than retaining stale revision metadata in incremental render nodes.
		for id:String in object_updates:sync_entity_object(id,service.context.world.entity(id))
		if not object_updates.is_empty() or not piece_updates.is_empty():visibility_key=""
		for update:Dictionary in piece_updates:
			var v:Dictionary=update.after;var before:Dictionary=update.before
			if v.hp!=before.hp:state_revision+=1
			# Positive HP and door-state changes cannot alter the static frame or
			# other buildings. Recreate only this leaf's fact-driven overlays.
			if v.has("door") and doors.has(v.id):
				var entry:Dictionary=doors[v.id]
				if v.hp!=before.hp:
					entry.full.free();door_leaf(v,entry.node)
					entry=doors[v.id]
				entry.piece=v
				if v.door!=before.door:
					var yaw:float=-int(v.quarterTurn)*PI/2.0+(-int(v.door.swing)*PI/2.0 if v.door.open else 0.0)
					if is_inside_tree():entry.node.create_tween().tween_property(entry.node,"rotation:y",yaw,0.2)
					else:entry.node.rotation.y=yaw
			for node:MeshInstance3D in static_nodes.values():
				if node.get_meta("piece",{}).get("id")==v.id:node.set_meta("piece",v)
		# These projections consume stocks/holders and completed orders, not
		# every unrelated world extension. Unknown notification shapes retain
		# the original eager refresh; no authority or sight proof is cached.
		var refresh:Dictionary=projection_refresh(changes,piece_updates,object_updates)
		if refresh.contents:update_contents()
		if refresh.state:update_state_details()
	if _generation_rebuild_frame < 0:
		update_visibility()
	else:
		_queue_visibility()

static func _is_additive_region_notification(region_id: String, operations: Array) -> bool:
	if region_id.is_empty():
		return false
	var added_region := false
	for op: Dictionary in operations:
		match str(op.get("op", "")):
			"region.put":
				if added_region or op.get("id") != region_id or op.get("before_exists") != false:
					return false
				added_region = true
			"entity.put":
				if op.get("before_exists") != false or op.get("after", {}).get("regionId") != region_id:
					return false
			"chunk.put":
				if op.get("before_exists") != false:
					return false
			"extension.set":
				continue
			_:
				return false
	return added_region

func _queue_visibility()->void:
	# Godot can flush deferred calls between physics substeps. Consume this
	# flag in the view's process pass to sample the final pose just once.
	if not is_inside_tree():update_visibility();return
	_visibility_queued=true

static func other_actor_facts_only(changes:Dictionary)->bool:
	if not changes.get("revision") is int or int(changes.revision)<0:return false
	for key:Variant in changes:
		if key not in ["world","facts","events","revision","actor_transitions"]:return false
	if not changes.get("world") is Array or not changes.world.is_empty() or not changes.get("facts") is Array or changes.facts.is_empty() or not changes.get("events") is Array or not changes.get("actor_transitions") is Array:return false
	for fact:Variant in changes.facts:
		if not fact is Dictionary or fact.get("collection")!="actors" or not fact.get("id") is String or str(fact.id).is_empty() or fact.id=="player":return false
		for field:Variant in fact:
			if field not in ["collection","id","before","after"]:return false
		for field:String in ["before","after"]:
			var value:Variant=fact.get(field)
			if value!=null and (not value is Dictionary or value.get("id")!=fact.id):return false
		if fact.get("before")==null and fact.get("after")==null:return false
	for transition:Variant in changes.actor_transitions:
		if not transition is Dictionary or not transition.get("actor_id") is String or transition.actor_id in ["","player"]:return false
	return true

static func projection_refresh(changes:Dictionary,pieces:Array=[],object_updates:Dictionary={})->Dictionary:
	var all:Dictionary={"contents":true,"state":true}
	if changes.get("reload",false) or not changes.get("facts") is Array or not changes.get("world") is Array:return all
	var contents:bool=not object_updates.is_empty();var state:bool=not pieces.is_empty()
	for fact:Variant in changes.facts:
		if not fact is Dictionary or not fact.get("collection") is String:return all
		if fact.collection=="stocks":contents=true
		elif fact.collection not in ["actors","actions","quests"]:return all
	for op:Variant in changes.world:
		if not op is Dictionary:return all
		if op.get("op")=="extension.set":
			if op.get("id") in ["r3:structure-orders","r3:production"]:state=true
		elif op.get("op") not in ["entity.put","entity.remove","voxel.set","chunk.put","region.put"]:return all
	return {"contents":contents,"state":state}

func region_resident(id:String)->bool:
	if not _residency.has(id):_residency[id]=not service.context.world.has_method("region_is_resident") or service.context.world.region_is_resident(id)
	return _residency[id]

func _architecture_key(part:Dictionary)->String:
	var recipe:Variant=part.get("architecture_detail")
	if not recipe is Dictionary or recipe.get("version")!=ArchitectureDetail.VERSION:return ""
	if recipe.get("kind") not in ["wall","gable_roof","lean_roof","details"] or not recipe.get("local_size") is Dictionary:return ""
	# Quality/legacy facade skins can depend on external owner state. Leave
	# them on their original path rather than cache a partial dependency set.
	if part.has("quality_facade"):return ""
	return JSON.stringify(part,"",true,true)

func _architecture_refresh_config()->void:
	var bindings:Dictionary={}
	for id:String in materials:
		var value:Variant=materials[id]
		bindings[id]=value.get_instance_id() if value is Material else 0
	# Includes every UV tile size/resource entry, not just the main surface.
	# Replacement materials invalidate; edits to a shared Material already
	# affect cached and freshly built meshes through the same resource.
	if manifest==_architecture_manifest and bindings==_architecture_bindings:return
	_architecture_meshes.clear();_architecture_manifest=manifest.duplicate(true);_architecture_bindings=bindings
	_architecture_mesh_stats.invalidations+=1

func _architecture_remember(key:String,mesh:ArrayMesh)->void:
	_architecture_refresh_config()
	if _architecture_meshes.size()>=ARCHITECTURE_MESH_LIMIT:
		_architecture_meshes.erase(_architecture_meshes.keys()[0]);_architecture_mesh_stats.evict+=1
	_architecture_meshes[key]=mesh

func entity_object(e:Dictionary)->Node3D:
	if not region_resident(str(e.get("regionId",""))):return null
	if e.get("kind") not in ["prop","container"]:return null
	var n:Node3D
	if e.get("data",{}).get("module_bed",{}).get("version")==2:
		material("b_wood_aged");material("wood_floor");material("textile_atlas")
		n=preload("res://scripts/buildings/module_bed_mesh.gd").create(e,materials)
	elif not str(e.get("data",{}).get("water_source_id","")).is_empty():
		n=preload("res://scripts/presentation/factory_water_view.gd").create_fixture(e,service.context.world.get_instance_id())
	elif e.get("data",{}).get("module_construction_site") is Dictionary:
		var b:=Geometry.aabb(e.data.module_construction_site.footprint);var builder:=MeshBuilder.new();material("wood_floor")
		for x:float in [b.position.x,b.end.x]:
			for z:float in [b.position.z,b.end.z]:builder.box(AABB(Vector3(x-0.05,0,z-0.05),Vector3(0.1,0.65,0.1)),Transform3D.IDENTITY,"wood_floor",2.0)
		var mesh_node:=MeshInstance3D.new();mesh_node.mesh=finish_mesh(builder);n=mesh_node
	elif e.get("data",{}).get("module_part") is Dictionary:
		var part:Dictionary=e.data.module_part
		var cache_key:String=_architecture_key(part)
		var cached:ArrayMesh
		if not cache_key.is_empty():
			_architecture_refresh_config()
			# Retain the old owner-dependent skin decision even for a recipe
			# copied into an unexpected legacy member. Its full path is uncached.
			if _architecture_meshes.has(cache_key) and not ModuleFacade.add(self,MeshBuilder.new(),e):
				cached=_architecture_meshes[cache_key];_architecture_mesh_stats.hit+=1
			else:_architecture_mesh_stats.miss+=1
		if cached!=null:
			var cached_node:=MeshInstance3D.new();cached_node.mesh=cached;n=cached_node
		else:
			var began:int=Time.get_ticks_usec()
			var builder:=MeshBuilder.new();var surface:String=str(part.material)
			var meters:float=float(manifest.textures.get(surface,{}).get("tile_meters",2.0))
		# Select only the fixed power assembly's real surfaces. The pinned part
		# bounds/ID/collider stay unchanged; metre UVs are rebuilt for this 1m
		# albedo rather than applying it through the old 2m zinc/concrete UVs.
			var id:String=str(e.get("id",""));var power_surface:String=""
			if surface=="zinc" and (id.ends_with(":part:fixed-power") or id.ends_with(":part:fixed-power-housing")):power_surface="drive_paint"
			elif surface=="concrete" and id.ends_with(":part:power-base"):power_surface="drive_rust"
			if not power_surface.is_empty():
				surface="r34-fixed-"+power_surface;materials[surface]=ProductionMaterials.material(power_surface);meters=1.0
			else:material(surface)
			if not ArchitectureDetail.add(builder,part,manifest.textures) and not ModuleRoof.add(builder,part,manifest.textures):
				builder.box(AABB(Vector3.ZERO,Geometry.point(part.size)),Transform3D.IDENTITY,surface,meters,int(part.get("atlas_cell",-1)))
			QualityFacade.add(builder,part,manifest.textures)
			var detailed:bool=ModuleFacade.add(self,builder,e)
			var mesh_node:=MeshInstance3D.new();mesh_node.mesh=finish_mesh(builder);n=mesh_node
			if detailed:n.set_meta("facade_skin_version",ModuleFacade.VERSION)
			elif not cache_key.is_empty():
				_architecture_mesh_stats.build_usec+=Time.get_ticks_usec()-began
				_architecture_remember(cache_key,mesh_node.mesh)
	elif e.get("data",{}).get("dressing_profile") is Dictionary:
		n=preload("res://scripts/buildings/dressing_geometry.gd").create(e,self)
	else:
		n=model(str(e.get("data",{}).get("assetId","")))
		if n!=null and e.get("data",{}).get("sleeping",false):
			if e.data.get("prepared",false):material("textile_atlas")
			Details.bed_textiles(n,e,materials)
	if n!=null:
		n.position=Geometry.point(e.position);n.rotation.y=-int(e.get("data",{}).get("quarterTurn",0))*PI/2
		n.set_meta("piece",e.duplicate(true))
	return n

func sync_entity_object(id:String,e:Dictionary)->void:
	_outdoor_shell_dirty = true
	# Initial rebuild and commit projection use exactly the same consumer.
	# Never write world facts to repair a missing node; deletion/replacement
	# frees the prior derived object and rebuilds only this entity.
	var old:Node3D=objects.get(id)
	if old!=null:
		objects.erase(id)
		if old.get_parent()!=null:old.get_parent().remove_child(old)
		# Keep per-instance material resources alive until their geometry has
		# detached from RenderingServer. GLB overrides otherwise may lose their
		# last RID while MeshInstance3D still tears down shader parameters.
		var retained_materials:Array=[]
		retain_object_materials(old,retained_materials)
		release_object(old)
	var node:=entity_object(e)
	if node!=null:add_child(node);objects[id]=node
	visibility_key="";content_key="";state_key=""

static func retain_object_materials(node:Node,retained:Array)->void:
	if node is MeshInstance3D and node.mesh!=null:
		for i in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(i)
			if material!=null:retained.append(material)
	for child:Node in node.get_children():retain_object_materials(child,retained)

static func same_static_shape(before:Dictionary,after:Dictionary)->bool:
	if before.is_empty() or after.is_empty() or float(before.get("hp",0))<=0 or float(after.get("hp",0))<=0 or before.has("door")!=after.has("door"):return false
	var a:=before.duplicate(true);var b:=after.duplicate(true)
	for key in ["hp","version","door"]:a.erase(key);b.erase(key)
	return a==b

func _process(delta: float) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("buildings/building_view.gd",measured)

func set_staged_generation(enabled: bool) -> void:
	_stage_generation = enabled

func _profiled_process(delta: float) -> void:
	if _generation_rebuild_frame >= 0:
		if Engine.get_process_frames() >= _generation_rebuild_frame:
			var regions := _generated_regions.keys()
			_generated_regions.clear()
			_generation_rebuild_frame = -1
			rebuild(regions)
		return
	_refresh_delay -= delta
	if _refresh_delay > 0:
		if not _visibility_queued: return
		var player := current_player()
		if _visibility_scope(player) == _last_visibility_scope: return
	_visibility_queued = false
	_refresh_delay = VISIBILITY_INTERVAL
	update_visibility()

func _visibility_scope(player: Dictionary) -> Array:
	return [player.get("regionId"), player.get("buildingId"), player.get("storeyId")]

func _batch(v: Dictionary, role: String) -> RefCounted:
	var size:=2.0 if role in ["wall","cap","roof"] else 8.0
	var key := str(v.get("buildingId")) + "|" + str(v.get("storeyId")) + "|" + str(v.regionId) + "|" + role + "|" + str(floor(float(v.position.x)/size)) + "," + str(floor(float(v.position.z)/size))
	# Perpendicular walls can share one spatial cell but lie on opposite sides
	# of the room's cut plane. Never let a representative hide both together.
	if role in ["wall","cap"]:key+="|q"+str(int(v.get("quarterTurn",0)))
	if not batches.has(key): batches[key]={"builder":MeshBuilder.new(),"piece":v,"role":role,"pieces":{}}
	batches[key].pieces[v.id]=true
	return batches[key].builder

func xform(v: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,-int(v.get("quarterTurn",0))*PI/2.0),Geometry.point(v.position))

func box(builder: RefCounted, v: Dictionary, center: Vector3, size: Vector3, material: String, cell: int = -1) -> void:
	var meters: float = manifest.textures.get(material,{}).get("tile_meters",2.0)
	builder.box(AABB(center-size/2.0,size),xform(v),material,meters,cell)

func model_bounds(node:Node,at:Transform3D=Transform3D.IDENTITY)->AABB:
	var transform:Transform3D=at*node.transform if node is Node3D else at
	var result:=AABB()
	if node is MeshInstance3D and node.mesh!=null:result=transform*node.mesh.get_aabb()
	for child:Node in node.get_children():
		var child_bounds:=model_bounds(child,transform)
		if child_bounds.has_volume():result=child_bounds if not result.has_volume() else result.merge(child_bounds)
	return result

func furniture(v:Dictionary,d:Dictionary)->Node3D:
	var original:=model(str(d.assetId))
	if original==null:return null
	if d.id!="cabinet":
		original.name="Object";original.transform=xform(v)
		return original
	var root:=Node3D.new();root.name="Object";root.transform=xform(v)
	var mount:=Node3D.new();mount.name="SourceModel";root.add_child(mount);mount.add_child(original)
	if d.id=="cabinet":
		# The delivered storage GLB is a 0.785m chest, while this actual movable
		# cabinet has always occupied 1.5m. Fit the original mesh/UVs to its real
		# collider, so the player can see the full object that blocks their body.
		var bounds:=Geometry.aabb(d.solids[0]);var source:=model_bounds(original)
		if source.has_volume():
			var scale_factor:=bounds.size/source.size
			mount.scale=scale_factor
			mount.position=bounds.position-source.position*scale_factor
		var joinery:=MeshBuilder.new()
		Details.cabinet_joinery(joinery,bounds,manifest.textures)
		var detail:=MeshInstance3D.new();detail.name="CabinetJoinery";detail.mesh=finish_mesh(joinery);root.add_child(detail)
	return root

func original_surface(v:Dictionary,d:Dictionary)->String:
	var kind:String=d.kind
	var role := "roof" if kind=="roof" else "wall" if kind in ["wall","corner","door","window"] else "floor"
	var material := "roof_tile" if kind=="roof" else "cream_plaster" if role=="wall" else "concrete"
	if str(v.get("buildingId","")).contains(":shed") and kind=="roof":material="zinc"
	if str(v.get("buildingId","")).contains(":repair-shop") and role=="wall":material="old_brick"
	if str(v.get("buildingId","")).contains(":store") and role=="wall":material="mint_paint"
	var finish:Dictionary=v.get("presentation",{})
	if role=="wall" and has_surface(finish.get("wall")):material=finish.wall
	if kind=="roof" and has_surface(finish.get("roof")):material=finish.roof
	if v.definitionId=="porch_post":material="wood_floor"
	if kind in ["foundation","floor"] and v.get("buildingId")!=null:
		material="ceramic" if v.get("buildingId")=="rural:v1:RH-HOME:old-house" and float(v.position.x)<16 and float(v.position.z)>32 else "wood_floor"
		if str(v.get("buildingId","")).contains(":repair-shop"):material="concrete"
		if has_surface(finish.get("floor")):material=finish.floor
	return material

func _retire_paged_regions(regions:Dictionary)->void:
	_outdoor_shell_dirty = true
	# Lossless paging does not change stock/order/structure facts in still
	# resident regions. Remove the cold projections without regenerating theirs.
	for key:String in static_nodes.keys():
		if not regions.has(static_nodes[key].get_meta("piece",{}).get("regionId","")):continue
		static_nodes[key].free();static_nodes.erase(key);batches.erase(key)
	for id:String in objects.keys():
		if not regions.has(objects[id].get_meta("piece",{}).get("regionId","")):continue
		release_object(objects[id]);objects.erase(id)
	for id:String in doors.keys():
		if not regions.has(doors[id].piece.get("regionId","")):continue
		doors[id].node.free();doors.erase(id)
	for id:String in content_nodes.keys():
		var stock:Dictionary=content_nodes[id].get_meta("piece",{})
		if not regions.has(stock.get("location",{}).get("regionId","")):continue
		content_nodes[id].free();content_nodes.erase(id);content_signatures.erase(id)
	var details:=get_node_or_null("StateDetails")
	if details!=null:
		for detail:Node in details.get_children():
			if (detail.has_meta("state_batch") and not static_nodes.has(detail.get_meta("state_batch"))) or regions.has(detail.get_meta("piece",{}).get("regionId","")):
				detail.free()
	visibility_key=""

func rebuild(region_ids:Array=[],storage_warm:bool=false) -> void:
	_outdoor_shell_dirty = true
	var phase:int=Costs.begin()
	if not storage_warm:_residency.clear()
	_roof_query=null;_policy_query=null
	var surface_history:=SurfaceState.history(service)
	for key:String in static_nodes.keys():
		if region_ids.is_empty() or region_ids.has(str(static_nodes[key].get_meta("piece",{}).get("regionId",""))):
			static_nodes[key].free();static_nodes.erase(key);batches.erase(key)
	# A door, wall or distant scenery edit must not destroy every unchanged
	# domestic mesh/material. Reuse furniture shells and their real transform;
	# only changed prop payloads need a new instance (e.g. prepared bedding).
	var retained:Dictionary={}
	for id:String in objects.keys():
		if region_ids.is_empty() or region_ids.has(str(objects[id].get_meta("piece",{}).get("regionId",""))):retained[id]=objects[id];objects.erase(id)
	for id:String in doors.keys():
		if region_ids.is_empty() or region_ids.has(str(doors[id].piece.get("regionId",""))):doors[id].node.free();doors.erase(id)
	if region_ids.is_empty():static_nodes.clear();objects.clear();doors.clear();batches.clear()
	var pieces: Array = service.structures().instances.filter(func(v:Dictionary)->bool:return (region_ids.is_empty() or region_ids.has(str(v.regionId))) and region_resident(str(v.regionId)))
	var roofs: Dictionary = {}
	for piece in pieces:
		if float(piece.hp)>0 and service.geometry.definition(piece).kind=="roof":roofs[[piece.get("buildingId"),piece.get("storeyId"),Geometry.point(piece.position)]]=true
	for v in pieces:
		if float(v.hp)<=0: continue
		var d: Dictionary=service.geometry.definition(v)
		var kind: String=d.kind
		if kind in ["cabinet","workbench"]:
			var n:Node3D=retained.get(v.id)
			if n!=null and n.get_meta("piece",{}).get("definitionId")!=v.definitionId:n=null
			if n==null:n=furniture(v,d)
			if n != null:
				if storage_warm:n.visible=false
				if n.get_parent()==null:add_child(n)
				n.transform=xform(v);objects[v.id]=n;n.set_meta("piece",v)
				if retained.get(v.id)==n:retained.erase(v.id)
			continue
		var role := "roof" if kind=="roof" else "wall" if kind in ["wall","corner","door","window"] else "floor"
		var builder := _batch(v,role)
		var material := original_surface(v,d)
		if kind not in ["foundation","floor"]:material=SurfaceState.baseline_material(self,v,material,surface_history)
		for raw in d.solids:
			var part:=Geometry.aabb(raw)
			if kind in ["foundation","floor"]:
				# Visual skin separates the top from C terrain's coincident y=0 plane.
				# Authoritative floor/support heights remain exactly unchanged.
				part.size.y+=FLOOR_SKIN
				builder.box(part,xform(v),"concrete" if kind=="foundation" else "wood_floor",1.6,-1,material,float(manifest.textures[material].tile_meters))
			elif kind=="roof" and d.has("roof_profile"):
				# Exact same voxel-stepped solids as collision/sight, with a real
				# timber soffit and the existing metre-scaled tile/zinc top.
				builder.box(part,xform(v),"wood_floor",1.6,-1,material,float(manifest.textures[material].tile_meters))
			else:builder.box(part,xform(v),material,float(manifest.textures[material].tile_meters))
		if role=="wall":
			Details.aged_wall(builder,v,xform(v),kind)
			for z in [-0.115,0.115]:
				for raw in d.solids:
					var solid:=Geometry.aabb(raw)
					for band in [Vector2(0.02,0.14),Vector2(3.06,3.20)]:
						var low:=maxf(solid.position.y,band.x)
						var high:=minf(solid.end.y,band.y)
						if high<=low:continue
						# Trim follows real solids: no visual plank across a doorway.
						box(builder,v,Vector3(solid.get_center().x,(low+high)/2,z),Vector3(solid.size.x,high-low,0.035),"wood_floor")
			if kind=="window":
				for x in [-0.69,0.69,0.0]: box(builder,v,Vector3(x,1.5,0),Vector3(0.07,1.35,0.27),"wood_floor")
				for y in [0.84,2.18]: box(builder,v,Vector3(0,y,0),Vector3(1.45,0.08,0.3),"wood_floor")
				box(builder,v,Vector3(0,1.5,0),Vector3(1.32,1.25,0.012),"glass")
			# Entry trim is independent of the facade: the cutaway removes the
			# entire near wall/leaf, while retaining the real doorway outline.
			if kind=="door":
				door_view(v,_batch(v,"entry"))
				if storage_warm:doors[v.id].node.visible=false
		if kind=="roof":
			for direction in [Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2)]:
				if roofs.has([v.get("buildingId"),v.get("storeyId"),Geometry.point(v.position)+direction]):continue
				# Perimeter only; do not repeat fascia along every internal tile seam.
				var edge:=Geometry.rotate(direction.normalized(),-int(v.quarterTurn))
				box(builder,v,Vector3(edge.x*1.025,-0.06,edge.z*1.025),Vector3(0.07 if absf(edge.x)>0.5 else 2.07,0.09,0.07 if absf(edge.z)>0.5 else 2.07),"wood_floor")
		if kind=="stairs":
			var stair: Dictionary=d.stairs
			for i in 24:
				box(builder,v,Vector3(0,(i+0.5)*float(stair.rise)/24,(i+0.5)*float(stair.run)/24),Vector3(stair.width,float(stair.rise)/24,float(stair.run)/24),"wood_floor")
				box(builder,v,Vector3(0,(i+1)*float(stair.rise)/24,float(stair.run)*i/24+0.025),Vector3(stair.width,0.025,0.05),"painted_metal")
	for key in batches:
		var entry: Dictionary=batches[key]
		if static_nodes.has(key):continue # Unchanged regions retain their actual meshes.
		var n:=MeshInstance3D.new();n.mesh=finish_mesh(entry.builder);n.set_meta("piece",entry.piece);n.set_meta("piece_ids",entry.pieces.keys());n.set_meta("role",entry.role);n.visible=not storage_warm;add_child(n);static_nodes[key]=n
	var entities:Array=[]
	if region_ids.is_empty():entities=service.context.world.entities()
	else:
		for id:String in region_ids:entities.append_array(service.context.world.entities(id))
	for e in entities:
		if e.kind not in ["prop","container"] or (not region_ids.is_empty() and not region_ids.has(str(e.regionId))) or not region_resident(str(e.regionId)): continue
		var old:Node3D=retained.get(e.id)
		if old!=null and old.get_meta("piece",{})==e:
			if storage_warm:old.visible=false
			objects[e.id]=old;retained.erase(e.id);continue
		var n:=entity_object(e)
		if n==null: continue
		n.visible=not storage_warm
		add_child(n);objects[e.id]=n
	for node:Node3D in retained.values():release_object(node)
	Costs.end("buildings/rebuild_shells",phase)
	content_key="";visibility_key=""
	phase=Costs.begin()
	update_contents(region_ids if storage_warm else [])
	Costs.end("buildings/rebuild_contents",phase)
	phase=Costs.begin()
	if storage_warm:
		update_state_details(region_ids)
		_queue_visibility()
	else:
		state_key=""
		update_state_details()
		update_visibility()
	Costs.end("buildings/rebuild_details_and_visibility",phase)

func release_object(node:Node3D)->void:
	# Paging can release the final GLB override reference. Keep its resources
	# alive through the complete synchronous renderer/node teardown, just as
	# the single-entity update path already does.
	var retained_materials:Array=[]
	retain_object_materials(node,retained_materials)
	_release_object_tree(node)

func _release_object_tree(node:Node3D)->void:
	# MeshInstance keeps surface overrides separate from its mesh. Drop those
	# bindings while both resources still exist, before destroying the node.
	for child:Node in node.get_children():
		if child is Node3D:_release_object_tree(child)
	if node is MeshInstance3D and node.mesh!=null:
		for surface:int in node.mesh.get_surface_count():node.set_surface_override_material(surface,null)
	if node.get_parent()!=null:node.get_parent().remove_child(node)
	node.free()

func door_view(v: Dictionary,builder: RefCounted) -> void:
	for x in [-0.835,0.835]: box(builder,v,Vector3(x,1.1,0),Vector3(0.07,2.2,0.27),"wood_floor")
	box(builder,v,Vector3(0,2.235,0),Vector3(1.74,0.07,0.27),"wood_floor")
	var hinge:=Node3D.new();hinge.transform=xform(v);hinge.position+=hinge.basis*Vector3(-0.8,0,0);add_child(hinge)
	hinge.rotate_y(-int(v.door.swing)*PI/2 if v.door.open else 0)
	door_leaf(v,hinge)

func door_leaf(v:Dictionary,hinge:Node3D)->void:
	var history:=SurfaceState.history(service)
	var state:=SurfaceState.condition(v,float(service.geometry.definition(v).maxHp),history)
	var surface:=SurfaceState.id_for("wood_floor",state);material(surface)
	var mesh:=MeshBuilder.new();var leaf:=AABB(Vector3(0,0,-0.045),Vector3(1.6,2.2,0.09))
	mesh.box(leaf,Transform3D.IDENTITY,surface,2)
	mesh.box(AABB(Vector3(1.42,1.0,-0.09),Vector3(0.1,0.04,0.18)),Transform3D.IDENTITY,"painted_metal",1)
	if state in ["damaged","repaired"]:
		var decal:="b_wood_"+("damage_detail" if state=="damaged" else "repair_detail");material(decal)
		SurfaceState.detail_quad(mesh,leaf,Transform3D.IDENTITY,decal,Vector2(0.7,0.7),false)
	var n:=MeshInstance3D.new();n.mesh=finish_mesh(mesh);hinge.add_child(n)
	n.name="FullDoorLeaf"
	doors[v.id]={"node":hinge,"piece":v,"full":n}

func current_player() -> Dictionary:
	var runtime: Variant=runtime_ref.get_ref() if runtime_ref!=null else null
	return runtime.actor("player") if runtime!=null else {}

func visible_room(piece: Dictionary,player: Dictionary,observer:Dictionary={}) -> bool:
	var p:=Geometry.location(player) if observer.is_empty() else observer
	var at:=Geometry.location(piece)
	# Region labels partition finite data, not sight. Outdoor contents still
	# require the real opaque/terrain ray and resident continuity across a seam;
	# this grants neither hand reach nor knowledge of a different indoor room.
	var query:RefCounted=_visibility_query if _visibility_query!=null else service.current_space()
	if at.buildingId==null:return query.line_clear(p,at,str(piece.get("id","")))
	return at.regionId==p.regionId and at.buildingId==p.buildingId and at.storeyId==p.storeyId and query.line_clear(p,at,str(piece.get("id","")))

func visible_shell(piece:Dictionary,player:Dictionary,observer:Dictionary={})->bool:
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var phase:int=Costs.begin()
	var cut:bool=_view_policy!=null and _view_policy.has_method("module_part_visible") and not _view_policy.module_part_visible(piece,player)
	Costs.end("buildings/shell_room_policy",phase)
	if cut:return false
	if piece.get("data",{}).get("module_part") is Dictionary or piece.get("data",{}).get("module_construction_site") is Dictionary:
		# A fixed exterior is scenery, like a terrain surface. A ray to the
		# lower corner incorrectly deletes whole walls/roof bands behind another
		# face of the SAME shell. Render depth handles these surfaces; inventory,
		# actors, tool contact and authoritative LOS still use their own checks.
		if not region_resident(str(piece.get("regionId",""))):return false
		var from:=Geometry.location(player) if observer.is_empty() else observer
		var to:=Geometry.location(piece)
		if from.regionId==to.regionId:return true
		if _view_policy!=null and _view_policy.has_method("shell_coverage"):
			phase=Costs.begin()
			var covered:bool=_view_policy.shell_coverage(service.context.world,from,to)
			Costs.end("buildings/shell_region_coverage",phase)
			return covered
		return service.context.world.continuous_outdoor_segment(from,to,96.0,true).ok
	# Stable SAME structural-room furniture shell, never inventory contents or
	# another actor. Closed-room/other-floor/region boundaries remain D's true
	# structural scope; all other objects retain the exact original LOS path.
	var definition:Dictionary=service.geometry.definitions.get(piece.get("definitionId"),{})
	var fixed:bool=definition.get("kind") in ["cabinet","workbench"] or piece.get("data",{}).get("assetId")=="city_bed"
	phase=Costs.begin()
	var visible:bool
	if fixed and _view_policy!=null and _view_policy.has_method("can_observe_geometry"):
		visible=_view_policy.can_observe_geometry(piece,player)
	else:visible=visible_room(piece,player,observer)
	Costs.end("buildings/shell_object_los",phase)
	return visible

func cut_wall(piece:Dictionary,p:Dictionary)->bool:
	return piece.get("buildingId")!=null and piece.get("buildingId")==p.buildingId and not roof_wall_ids.has(piece.id) and (float(piece.position.x)>float(p.x)+0.5 or float(piece.position.z)>float(p.z)+0.5)

func set_view_policy(policy:RefCounted)->void:
	_view_policy=policy;_policy_query=null;visibility_key=""
	_local_shell_basis.clear()
	_local_shell_results.clear()
	update_visibility()

func _compile_outdoor_shells() -> void:
	_outdoor_shell_groups.clear()
	_outdoor_shell_nodes.clear()
	_outdoor_shell_dirty = false
	for node: Node3D in objects.values():
		var piece: Dictionary = node.get_meta("piece")
		var data: Dictionary = piece.get("data", {})
		if not (data.get("module_part") is Dictionary or data.get("module_construction_site") is Dictionary):
			continue
		var location: Dictionary = Geometry.location(piece)
		if piece.get("regionId") != location.regionId or piece.get("buildingId") != null or location.buildingId != null or location.storeyId != null:
			continue
		var region: String = str(location.regionId)
		var point: Vector3 = Geometry.point(location)
		var bounds: Dictionary = _outdoor_shell_groups.get(region, {"low": point, "high": point})
		bounds.low = bounds.low.min(point)
		bounds.high = bounds.high.max(point)
		_outdoor_shell_groups[region] = bounds
		_outdoor_shell_nodes[node.get_instance_id()] = region

func update_policy_visibility(player:Dictionary,query:RefCounted)->void:
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var phase:int=Costs.begin()
	if query!=_policy_query:
		_view_policy.configure(query);_policy_query=query
	var p:=Geometry.location(player)
	# Sample even at identical coordinates: a pending doorway transition must
	# settle after 140ms without requiring another movement or world edit.
	_view_policy.sample(p)
	# B's current_space identity changes for every geometric dependency, and
	# stays identical only after its complete metadata-preservation proof.
	# A clock/alert/bookkeeping revision cannot change these draw decisions.
	var signature: String = _view_policy.signature()
	var key:=str([p.x,p.y,p.z,p.regionId,p.buildingId,p.storeyId,query.get_instance_id(),signature])
	Costs.end("buildings/policy_sample",phase)
	if key==visibility_key:return
	visibility_key=key;roof_wall_ids.clear()
	phase=Costs.begin()
	for node:MeshInstance3D in static_nodes.values():
		var v:Dictionary=node.get_meta("piece");var role:String=node.get_meta("role")
		var cut:bool=_view_policy.cut_wall(v)
		node.visible=_view_policy.base_visible(v,role) and (not cut if role=="wall" else false if role=="cap" else true)
	Costs.end("buildings/static_visibility",phase)
	phase=Costs.begin()
	var region_candidates:Dictionary={}
	var region_gate:bool=_view_policy.has_method("shell_region_candidate")
	var module_gate:bool=_view_policy.has_method("module_shell_visible")
	var local_region: String = str(p.regionId)
	var local_resident: bool = region_resident(local_region)
	if _outdoor_shell_dirty: _compile_outdoor_shells()
	var proven_groups: Dictionary = {}
	if module_gate and player.get("regionId") == p.regionId and query.world.has_method("proves_outdoor_shell_group"):
		for region: String in _outdoor_shell_groups:
			if region == local_region or not region_resident(region): continue
			var bounds: Dictionary = _outdoor_shell_groups[region]
			if query.world.proves_outdoor_shell_group(p, region, bounds.low, bounds.high):
				proven_groups[region] = true
	# Within one region, fixed module shells depend on the settled room/floor
	# and camera side, not on the observer's exact coordinates. The policy has
	# already sampled every registered room above, including pending changes.
	var local_basis: Array = [query.get_instance_id(), local_region, local_resident, signature]
	if local_basis != _local_shell_basis or _local_shell_results.size() > objects.size() * 2:
		_local_shell_basis = local_basis
		_local_shell_results.clear()
	for node:Node3D in objects.values():
		var v:Dictionary=node.get_meta("piece")
		var region:String=str(v.get("regionId",""))
		if region_gate:
			if not region_candidates.has(region):region_candidates[region]=_view_policy.shell_region_candidate(region)
			if not region_candidates[region]:node.visible=false;continue
		var data:Dictionary=v.get("data",{})
		if module_gate and (data.get("module_part") is Dictionary or data.get("module_construction_site") is Dictionary):
			var node_id: int = node.get_instance_id()
			# Remote outdoor module parts have no local room cut or floor veto.
			# The group proof covers their exact original 96m segment checks.
			if proven_groups.has(region) and _outdoor_shell_nodes.get(node_id) == region:
				node.visible = true
				continue
			var measured:int=Costs.begin()
			var memo: Dictionary = _local_shell_results.get(node_id, {}) if region == local_region else {}
			if not memo.is_empty() and is_same(memo.piece, v):
				node.visible = memo.visible
			else:
				node.visible = _view_policy.module_shell_visible(v, player, p, local_resident if region == local_region else region_resident(region))
				if region == local_region and str(Geometry.location(v).regionId) == local_region:
					_local_shell_results[node_id] = {"piece": v, "visible": node.visible}
			Costs.end("buildings/module_shell_visibility",measured)
			continue
		node.visible=visible_shell(v,player,p) and _view_policy.base_visible(v,"object")
	# Discovering or settling a room during the pass can change its epoch.
	# Discard any decisions sampled before that transition.
	if signature != _view_policy.signature(): _local_shell_basis.clear()
	Costs.end("buildings/shell_visibility",phase)
	phase=Costs.begin()
	for entry:Dictionary in doors.values():
		var v:Dictionary=entry.piece
		entry.node.visible=_view_policy.base_visible(v,"door")
		var cut:bool=_view_policy.cut_wall(v)
		entry.full.visible=not cut
	if has_node("Contents"):
		for child:Node3D in get_node("Contents").get_children():
			var v:Dictionary=child.get_meta("piece")
			child.visible=_view_policy.base_visible(v,"object") and visible_room(v,player,p)
	if has_node("StateDetails"):
		for child:Node3D in get_node("StateDetails").get_children():
			if child.has_meta("state_batch"):
				child.visible=static_nodes.has(child.get_meta("state_batch")) and static_nodes[child.get_meta("state_batch")].visible
				continue
			var v:Dictionary=child.get_meta("piece")
			var cut:bool=child.get_meta("wall_attached",false) and _view_policy.cut_wall(v)
			child.visible=not cut and _view_policy.base_visible(v,"object") and visible_room(v,player,p)
	Costs.end("buildings/door_content_visibility",phase)

func update_visibility() -> void:
	var player:=current_player()
	if player.is_empty(): return
	_last_visibility_scope = _visibility_scope(player)
	# Only movement inside the same scope is coalesced. Direct updates from
	# geometry, doors, and residency still evaluate the authoritative scene.
	# A synchronous pass sees one immutable spatial projection. Reuse only
	# inside this call, so public visible_room callers always resolve current.
	_visibility_query=service.current_space()
	if _view_policy!=null:
		update_policy_visibility(player,_visibility_query)
		_visibility_query=null
		return
	var p:=Geometry.location(player)
	var key:=str([p.x,p.y,p.z,p.regionId,p.buildingId,p.storeyId,_visibility_query.get_instance_id()])
	if key==visibility_key:_visibility_query=null;return
	visibility_key=key
	roof_wall_ids.clear()
	var query:RefCounted=_visibility_query
	if query!=_roof_query:
		roof_cutaway.configure(query);_roof_query=query
	var active_ceiling:int=roof_cutaway.component_at(p)
	# Resolve opaque room covers first. Their actual supports must remain full
	# height; cutting every foreground wall independently left floating slabs.
	# Reuse the immutable support-neighbor projection, never a visual world.
	for node:MeshInstance3D in static_nodes.values():
		if node.get_meta("role")!="roof":continue
		var v:Dictionary=node.get_meta("piece")
		var same:bool=v.get("buildingId")!=null and v.get("buildingId")==p.buildingId
		node.visible=v.regionId==p.regionId and not (same and float(v.position.y)>float(p.y)+1.0)
		if same and v.get("storeyId")==p.storeyId:
			# A whole connected ceiling region changes together. Per-tile sight
			# rays produced isolated strips over furniture and ragged room edges.
			node.visible=false
			for id:String in node.get_meta("piece_ids",[v.id]):
				if active_ceiling<0 or int(roof_cutaway.components.get(id,-1))!=active_ceiling:node.visible=true;break
		if node.visible:
			for id:String in node.get_meta("piece_ids",[v.id]):
				for wall:Dictionary in query.support_walls(query.by_id[id]):roof_wall_ids[wall.id]=true
	for node in static_nodes.values():
		var v: Dictionary=node.get_meta("piece");var role: String=node.get_meta("role")
		if role=="roof":continue
		var same: bool=v.get("buildingId")!=null and v.get("buildingId")==p.buildingId
		var upper: bool=same and float(v.position.y)>float(p.y)+1.0
		var cut:bool=cut_wall(v,p)
		if cut and role in ["wall","cap"]:
			for id:String in node.get_meta("piece_ids",[v.id]):
				if roof_wall_ids.has(id):cut=false;break
		node.visible=v.regionId==p.regionId and not (upper and role in ["roof","floor","entry"]) and (not cut if role=="wall" else role!="cap")
	for node in objects.values(): node.visible=visible_shell(node.get_meta("piece"),player)
	for entry in doors.values():
		var v:Dictionary=entry.piece
		entry.node.visible=v.regionId==p.regionId and (v.get("buildingId")!=p.buildingId or float(v.position.y)<=float(p.y)+0.5)
		var cut:bool=cut_wall(v,p)
		entry.full.visible=not cut
	if has_node("Contents"):
		for child in get_node("Contents").get_children(): child.visible=visible_room(child.get_meta("piece"),player)
	if has_node("StateDetails"):
		for child in get_node("StateDetails").get_children():
			if child.has_meta("state_batch"):
				child.visible=static_nodes.has(child.get_meta("state_batch")) and static_nodes[child.get_meta("state_batch")].visible
				continue
			var v:Dictionary=child.get_meta("piece")
			var cut:bool=child.get_meta("wall_attached",false) and cut_wall(v,p)
			child.visible=visible_room(v,player) and not cut
	_visibility_query=null

func update_state_details(region_ids:Array=[])->void:
	var fields:Array[String]=["orders"]
	var world:RefCounted=service.context.world
	var structure_orders:Variant=world.extension_fields("r3:structure-orders",fields) if world.has_method("extension_fields") else world.extension("r3:structure-orders")
	var production:Variant=world.extension_fields("r3:production",fields) if world.has_method("extension_fields") else world.extension("r3:production")
	var completed:Array=[]
	for o in (structure_orders.get("orders",[]) if structure_orders is Dictionary else [])+(production.get("orders",[]) if production is Dictionary else []):
		if o.get("status")=="completed":completed.append(o.id)
	var key:=str([completed,state_revision])
	var scoped:bool=not region_ids.is_empty() and key==state_key and has_node("StateDetails")
	if key==state_key and not scoped:return
	state_key=key
	visibility_key=""
	var previous:=get_node_or_null("StateDetails")
	if previous!=null and not scoped:previous.free()
	var scope:Array=region_ids if scoped else []
	var details:=Details.state_details(service,materials,self,scope)
	SurfaceState.add_details(self,details,SurfaceState.history(service),scope)
	for child:Node in details.get_children():
		var piece:Dictionary=child.get_meta("piece",{})
		if (child.has_meta("state_batch") and not static_nodes.has(child.get_meta("state_batch"))) or (not piece.is_empty() and not region_resident(str(piece.get("regionId","")))):child.free()
		elif scoped:
			child.visible=false
			details.remove_child(child);previous.add_child(child)
	if scoped:details.free()
	else:add_child(details)

func update_contents(region_ids:Array=[]) -> void:
	var runtime: Variant=runtime_ref.get_ref() if runtime_ref!=null else null
	if runtime==null: return
	var stocks:Array=runtime.stock_states() if runtime.has_method("stock_states") else runtime.facts().get("stocks",[])
	var root:Node3D=get_node_or_null("Contents")
	if root==null:root=Node3D.new();root.name="Contents";add_child(root)
	var retained:Dictionary={}
	var holders:Dictionary={}
	var indexed_holders:=false
	for stock in stocks:
		if stock.has("module_id") or (not region_ids.is_empty() and not region_ids.has(str(stock.location.regionId))) or not region_resident(str(stock.location.regionId)):continue
		var id:String=stock.id
		retained[id]=true
		var p:=Geometry.location(stock)
		# This projection needs only the resident holder's transform. Constructing
		# BuildingSpace here would also build every collider and navigation index.
		if not indexed_holders:
			for piece:Dictionary in service.structures().instances:
				if region_resident(str(piece.regionId)):holders[piece.id]=piece
			indexed_holders=true
		var holder:Dictionary=holders.get(str(stock.get("structureId",stock.id)),{})
		if not holder.is_empty(): p=Geometry.location(holder)
		# Presentation keys exclude order/revision/other holders. Movement of a
		# different stock or clock tick no longer destroys every visible object.
		var signature:=JSON.stringify([stock.get("searched",false),stock.get("items",{}),p,holder.is_empty()],"",true)
		if content_signatures.get(id)==signature:
			if content_nodes.has(id):content_nodes[id].set_meta("piece",stock)
			continue
		content_signatures[id]=signature;visibility_key=""
		if content_nodes.has(id):content_nodes[id].free();content_nodes.erase(id)
		if not stock.get("searched",false):continue
		var builder:=MeshBuilder.new();var n:=0
		var ground: bool=holder.is_empty()
		# The signature and native codec use sorted dictionary keys. Match that
		# order before choosing the capped visible objects, so first save/load
		# or a semantically identical stock cannot substitute their geometry.
		var item_ids:Array=stock.get("items",{}).keys();item_ids.sort()
		for item in item_ids:
			var count:=mini(3,int(stock.items[item]))
			for i in count:
				if n>=8: break
				var visual:=item_visual(str(item),i)
				var center:=Vector3(p.x+(n%3)*0.24-0.24,p.y+(0.06 if ground else 0.8),p.z+float(n/3)*0.2)
				builder.box(AABB(center,visual.size),Transform3D.IDENTITY,visual.material,1,visual.cell);n+=1
		if n==0: continue
		var node:=MeshInstance3D.new();node.mesh=finish_mesh(builder);node.set_meta("piece",stock)
		# Hide until this same call's visibility pass, including stock-only
		# changes. Never flash default-visible contents behind a closed door.
		node.visible=false;root.add_child(node);content_nodes[id]=node
	# Cooling already retired this region's visuals; storage never moves stock.
	if not region_ids.is_empty():return
	for id:String in content_signatures.keys():
		if retained.has(id):continue
		content_signatures.erase(id);visibility_key=""
		if content_nodes.has(id):content_nodes[id].free();content_nodes.erase(id)

static func item_visual(item:String,index:int=0)->Dictionary:
	# Semantic cells from existing A01/A02/A04 contracts, never hash into a
	# random food label. Counts and visibility still come from the actual stock.
	if item.begins_with("book"):
		return {"material":"book_atlas","cell":1 if item=="book_tool_repair" else 0,"size":Vector3(0.18,0.045,0.24)}
	if item=="water":return {"material":"grocery_atlas","cell":3,"size":Vector3(0.14,0.22,0.14)}
	if item=="food":return {"material":"grocery_atlas","cell":4 if index%2==0 else 8,"size":Vector3(0.14,0.18,0.14)}
	if item in ["scrap","axe_head","brace"]:return {"material":"painted_metal","cell":-1,"size":Vector3(0.12,0.06,0.18)}
	if item=="cloth":return {"material":"textile_atlas","cell":2,"size":Vector3(0.18,0.06,0.24)}
	if item in ["timber","log","tool_handle"]:return {"material":"wood_floor","cell":-1,"size":Vector3(0.08,0.08,0.28) if item=="tool_handle" else Vector3(0.18,0.12,0.3)}
	return {"material":"plywood","cell":-1,"size":Vector3(0.14,0.12,0.18)}

func residency_statistics()->Dictionary:
	var regions:Dictionary={}
	for node:Node3D in objects.values():
		var piece:Dictionary=node.get_meta("piece",{});var id:String=str(piece.get("regionId",""));regions[id]=int(regions.get(id,0))+1
	return {"objects":objects.size(),"static_batches":static_nodes.size(),"doors":doors.size(),"contents":content_nodes.size(),"regions":regions}
