extends Node3D
## Derived, editable-world presentation. No reward/inventory or authority in render nodes.
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const MeshBuilder = preload("res://scripts/buildings/building_mesh.gd")
const Details = preload("res://tests/buildings/view_mount_reference/building_details.gd")
const SurfaceState = preload("res://scripts/buildings/building_surface_state.gd")
const ModuleFacade=preload("res://scripts/buildings/module_facade_detail.gd")
const ProductionMaterials=preload("res://scripts/presentation/factory_materials.gd")
var _residency:Dictionary={}
var service: RefCounted
var runtime_ref: WeakRef
var manifest: Dictionary
var materials: Dictionary = {}
var models: Dictionary = {}
var texture_cache: Dictionary = {}
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
var _refresh_delay := 0.0
const FLOOR_SKIN := 0.012

func configure(context: Dictionary) -> void:
	service = context.service
	var runtime: Variant = context.get("runtime")
	if runtime != null: runtime_ref = weakref(runtime); runtime.changed.connect(_changed)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	for id in manifest.textures:
		if not manifest.textures[id].get("lazy",false):material(id)
	var glass := StandardMaterial3D.new(); glass.albedo_color=Color(0.43,0.63,0.66,0.27); glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; glass.roughness=0.45; materials.glass=glass
	rebuild()

func material(id:String)->StandardMaterial3D:
	if materials.has(id):return materials[id]
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

func _changed(changes: Dictionary) -> void:
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
	if geometry_changed: rebuild()
	else:
		# C canonicalizes entity revisions at commit. The change-set payload is
		# the requested proposal, so read the committed object once by ID rather
		# than retaining stale revision metadata in incremental render nodes.
		for id:String in object_updates:sync_entity_object(id,service.context.world.entity(id))
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
		update_contents();update_state_details()
	update_visibility()

func region_resident(id:String)->bool:
	if not _residency.has(id):_residency[id]=not service.context.world.has_method("region_is_resident") or service.context.world.region_is_resident(id)
	return _residency[id]

func entity_object(e:Dictionary)->Node3D:
	if not region_resident(str(e.get("regionId",""))):return null
	if e.get("kind") not in ["prop","container"]:return null
	var n:Node3D
	if e.get("data",{}).get("module_construction_site") is Dictionary:
		var b:=Geometry.aabb(e.data.module_construction_site.footprint);var builder:=MeshBuilder.new();material("wood_floor")
		for x:float in [b.position.x,b.end.x]:
			for z:float in [b.position.z,b.end.z]:builder.box(AABB(Vector3(x-0.05,0,z-0.05),Vector3(0.1,0.65,0.1)),Transform3D.IDENTITY,"wood_floor",2.0)
		var mesh_node:=MeshInstance3D.new();mesh_node.mesh=builder.mesh(materials);n=mesh_node
	elif e.get("data",{}).get("module_part") is Dictionary:
		var part:Dictionary=e.data.module_part
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
		builder.box(AABB(Vector3.ZERO,Geometry.point(part.size)),Transform3D.IDENTITY,surface,meters,int(part.get("atlas_cell",-1)))
		var detailed:bool=ModuleFacade.add(self,builder,e)
		var mesh_node:=MeshInstance3D.new();mesh_node.mesh=builder.mesh(materials);n=mesh_node
		if detailed:n.set_meta("facade_skin_version",ModuleFacade.VERSION)
	elif e.get("data",{}).get("dressing_profile") is Dictionary:
		n=preload("res://tests/buildings/view_mount_reference/dressing_geometry.gd").create(e,self)
	else:
		n=model(str(e.get("data",{}).get("assetId","")))
		if n!=null and e.get("data",{}).get("sleeping",false):Details.bed_textiles(n,e,materials)
	if n!=null:
		n.position=Geometry.point(e.position);n.rotation.y=-int(e.get("data",{}).get("quarterTurn",0))*PI/2
		n.set_meta("piece",e.duplicate(true))
	return n

func sync_entity_object(id:String,e:Dictionary)->void:
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
	_refresh_delay -= delta
	if _refresh_delay > 0: return
	_refresh_delay=0.1
	update_visibility()

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
		var detail:=MeshInstance3D.new();detail.name="CabinetJoinery";detail.mesh=joinery.mesh(materials);root.add_child(detail)
	return root

func original_surface(v:Dictionary,d:Dictionary)->String:
	var kind:String=d.kind
	var role := "roof" if kind=="roof" else "wall" if kind in ["wall","corner","door","window"] else "floor"
	var material := "roof_tile" if kind=="roof" else "cream_plaster" if role=="wall" else "concrete"
	if str(v.get("buildingId","")).contains(":shed") and kind=="roof":material="zinc"
	if str(v.get("buildingId","")).contains(":repair-shop") and role=="wall":material="old_brick"
	if str(v.get("buildingId","")).contains(":store") and role=="wall":material="mint_paint"
	var finish:Dictionary=v.get("presentation",{})
	if role=="wall" and materials.has(finish.get("wall")):material=finish.wall
	if kind=="roof" and materials.has(finish.get("roof")):material=finish.roof
	if v.definitionId=="porch_post":material="wood_floor"
	if kind in ["foundation","floor"] and v.get("buildingId")!=null:
		material="ceramic" if v.get("buildingId")=="rural:v1:RH-HOME:old-house" and float(v.position.x)<16 and float(v.position.z)>32 else "wood_floor"
		if str(v.get("buildingId","")).contains(":repair-shop"):material="concrete"
		if materials.has(finish.get("floor")):material=finish.floor
	return material

func rebuild() -> void:
	_residency.clear();_roof_query=null;_policy_query=null
	var surface_history:=SurfaceState.history(service)
	for node in static_nodes.values(): node.free()
	# A door, wall or distant scenery edit must not destroy every unchanged
	# domestic mesh/material. Reuse furniture shells and their real transform;
	# only changed prop payloads need a new instance (e.g. prepared bedding).
	var retained:=objects.duplicate()
	for entry in doors.values(): entry.node.free()
	static_nodes.clear();objects.clear();doors.clear();batches.clear()
	var pieces: Array = service.structures().instances.filter(func(v:Dictionary)->bool:return region_resident(str(v.regionId)))
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
			if kind=="door": door_view(v,_batch(v,"entry"))
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
		var n:=MeshInstance3D.new();n.mesh=entry.builder.mesh(materials);n.set_meta("piece",entry.piece);n.set_meta("piece_ids",entry.pieces.keys());n.set_meta("role",entry.role);add_child(n);static_nodes[key]=n
	for e in service.context.world.entities():
		if e.kind not in ["prop","container"] or not region_resident(str(e.regionId)): continue
		var old:Node3D=retained.get(e.id)
		if old!=null and old.get_meta("piece",{})==e:
			objects[e.id]=old;retained.erase(e.id);continue
		var n:=entity_object(e)
		if n==null: continue
		add_child(n);objects[e.id]=n
	for node:Node3D in retained.values():release_object(node)
	content_key="";visibility_key="";state_key=""
	update_contents();update_state_details();update_visibility()

func release_object(node:Node3D)->void:
	# MeshInstance keeps surface overrides separate from its mesh. Drop those
	# bindings while both resources still exist, before destroying the node.
	for child:Node in node.get_children():
		if child is Node3D:release_object(child)
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
	var n:=MeshInstance3D.new();n.mesh=mesh.mesh(materials);hinge.add_child(n)
	n.name="FullDoorLeaf"
	doors[v.id]={"node":hinge,"piece":v,"full":n}

func current_player() -> Dictionary:
	var runtime: Variant=runtime_ref.get_ref() if runtime_ref!=null else null
	return runtime.actor("player") if runtime!=null else {}

func visible_room(piece: Dictionary,player: Dictionary) -> bool:
	var p:=Geometry.location(player);var at:=Geometry.location(piece)
	# Region labels partition finite data, not sight. Outdoor contents still
	# require the real opaque/terrain ray and resident continuity across a seam;
	# this grants neither hand reach nor knowledge of a different indoor room.
	if at.buildingId==null:return service.current_space().line_clear(p,at,str(piece.get("id","")))
	return at.regionId==p.regionId and at.buildingId==p.buildingId and at.storeyId==p.storeyId and service.current_space().line_clear(p,at,str(piece.get("id","")))

func visible_shell(piece:Dictionary,player:Dictionary)->bool:
	if piece.get("data",{}).get("module_part") is Dictionary or piece.get("data",{}).get("module_construction_site") is Dictionary:
		# A fixed exterior is scenery, like a terrain surface. A ray to the
		# lower corner incorrectly deletes whole walls/roof bands behind another
		# face of the SAME shell. Render depth handles these surfaces; inventory,
		# actors, tool contact and authoritative LOS still use their own checks.
		if not region_resident(str(piece.get("regionId",""))):return false
		var from:=Geometry.location(player);var to:=Geometry.location(piece)
		if from.regionId==to.regionId:return true
		return service.context.world.continuous_outdoor_segment(from,to,96.0,true).ok
	# Stable SAME structural-room furniture shell, never inventory contents or
	# another actor. Closed-room/other-floor/region boundaries remain D's true
	# structural scope; all other objects retain the exact original LOS path.
	var definition:Dictionary=service.geometry.definitions.get(piece.get("definitionId"),{})
	var fixed:bool=definition.get("kind") in ["cabinet","workbench"] or piece.get("data",{}).get("assetId")=="city_bed"
	if fixed and _view_policy!=null and _view_policy.has_method("can_observe_geometry"):
		return _view_policy.can_observe_geometry(piece,player)
	return visible_room(piece,player)

func cut_wall(piece:Dictionary,p:Dictionary)->bool:
	return piece.get("buildingId")!=null and piece.get("buildingId")==p.buildingId and not roof_wall_ids.has(piece.id) and (float(piece.position.x)>float(p.x)+0.5 or float(piece.position.z)>float(p.z)+0.5)

func set_view_policy(policy:RefCounted)->void:
	_view_policy=policy;_policy_query=null;visibility_key=""
	update_visibility()

func update_policy_visibility(player:Dictionary,query:RefCounted)->void:
	if query!=_policy_query:
		_view_policy.configure(query);_policy_query=query
	var p:=Geometry.location(player)
	# Sample even at identical coordinates: a pending doorway transition must
	# settle after 140ms without requiring another movement or world edit.
	_view_policy.sample(p)
	var key:=str([p.x,p.y,p.z,p.buildingId,p.storeyId,service.context.world.get_revision(),_view_policy.signature()])
	if key==visibility_key:return
	visibility_key=key;roof_wall_ids.clear()
	for node:MeshInstance3D in static_nodes.values():
		var v:Dictionary=node.get_meta("piece");var role:String=node.get_meta("role")
		var cut:bool=_view_policy.cut_wall(v)
		node.visible=_view_policy.base_visible(v,role) and (not cut if role=="wall" else false if role=="cap" else true)
	for node:Node3D in objects.values():
		var v:Dictionary=node.get_meta("piece")
		node.visible=visible_shell(v,player) and _view_policy.base_visible(v,"object")
	for entry:Dictionary in doors.values():
		var v:Dictionary=entry.piece
		entry.node.visible=_view_policy.base_visible(v,"door")
		var cut:bool=_view_policy.cut_wall(v)
		entry.full.visible=not cut
	if has_node("Contents"):
		for child:Node3D in get_node("Contents").get_children():
			var v:Dictionary=child.get_meta("piece")
			child.visible=visible_room(v,player) and _view_policy.base_visible(v,"object")
	if has_node("StateDetails"):
		for child:Node3D in get_node("StateDetails").get_children():
			if child.has_meta("state_batch"):
				child.visible=static_nodes.has(child.get_meta("state_batch")) and static_nodes[child.get_meta("state_batch")].visible
				continue
			var v:Dictionary=child.get_meta("piece")
			var cut:bool=child.get_meta("wall_attached",false) and _view_policy.cut_wall(v)
			child.visible=visible_room(v,player) and _view_policy.base_visible(v,"object") and not cut

func update_visibility() -> void:
	var player:=current_player()
	if player.is_empty(): return
	if _view_policy!=null:
		update_policy_visibility(player,service.current_space())
		return
	var p:=Geometry.location(player)
	var key:=str([p.x,p.y,p.z,p.buildingId,p.storeyId,service.context.world.get_revision()])
	if key==visibility_key: return
	visibility_key=key
	roof_wall_ids.clear()
	var query:RefCounted=service.current_space()
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

func update_state_details()->void:
	var structure_orders:Variant=service.context.world.extension("r3:structure-orders")
	var production:Variant=service.context.world.extension("r3:production")
	var completed:Array=[]
	for o in (structure_orders.get("orders",[]) if structure_orders is Dictionary else [])+(production.get("orders",[]) if production is Dictionary else []):
		if o.get("status")=="completed":completed.append(o.id)
	var key:=str([completed,state_revision])
	if key==state_key:return
	state_key=key
	visibility_key=""
	if has_node("StateDetails"):get_node("StateDetails").free()
	var details:=Details.state_details(service,materials,self)
	SurfaceState.add_details(self,details,SurfaceState.history(service))
	for child:Node in details.get_children():
		var piece:Dictionary=child.get_meta("piece",{})
		if (child.has_meta("state_batch") and not static_nodes.has(child.get_meta("state_batch"))) or (not piece.is_empty() and not region_resident(str(piece.get("regionId","")))):child.free()
	add_child(details)

func update_contents() -> void:
	var runtime: Variant=runtime_ref.get_ref() if runtime_ref!=null else null
	if runtime==null: return
	var facts: Dictionary=runtime.facts()
	var root:Node3D=get_node_or_null("Contents")
	if root==null:root=Node3D.new();root.name="Contents";add_child(root)
	var retained:Dictionary={}
	for stock in facts.get("stocks",[]):
		if stock.has("module_id") or not region_resident(str(stock.location.regionId)):continue
		var id:String=stock.id
		retained[id]=true
		var p:=Geometry.location(stock)
		var holder: Dictionary=service.instance(str(stock.get("structureId",stock.id)))
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
		for item in stock.get("items",{}):
			var count:=mini(3,int(stock.items[item]))
			for i in count:
				if n>=8: break
				var visual:=item_visual(str(item),i)
				var center:=Vector3(p.x+(n%3)*0.24-0.24,p.y+(0.06 if ground else 0.8),p.z+float(n/3)*0.2)
				builder.box(AABB(center,visual.size),Transform3D.IDENTITY,visual.material,1,visual.cell);n+=1
		if n==0: continue
		var node:=MeshInstance3D.new();node.mesh=builder.mesh(materials);node.set_meta("piece",stock)
		# Hide until this same call's visibility pass, including stock-only
		# changes. Never flash default-visible contents behind a closed door.
		node.visible=false;root.add_child(node);content_nodes[id]=node
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
