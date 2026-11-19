extends SceneTree
const State = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
const Materials = preload("res://scripts/environment/environment_materials.gd")
const TerrainView = preload("res://scripts/terrain/terrain_view.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
var checks: Array = []
func root_piece(node: Node3D,position: Vector3) -> bool:
	if node==null: return false
	for child in node.get_children():
		if child is MeshInstance3D and child.position.is_equal_approx(position): return true
	return false

func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := State.new();world.load_snapshot(Generator.generate())
	var building := Building.new()
	# Only B's pure seed constructor is used here, not a partial runtime host.
	building.geometry.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
	var seed: Dictionary = building.seed_rural(world)
	var installation: Dictionary = world.prepare_changes(seed.world_changes,world.get_revision()) if seed.ok else seed
	check("contact input is complete actual B rural seed on the same C world",installation.ok and world.commit_prepared(installation.capability).ok)
	var materials := Materials.new()
	var exact := true
	for row in materials.manifest().values():
		var bytes := FileAccess.get_file_as_bytes(row.resource)
		var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		exact=exact and hash.finish().hex_encode()==row.sha256
	check("12 original plus four adopted image sources retain their exact declared bytes",exact and materials.manifest().size()==16)
	var grass: Material = materials.terrain_material("grass_top")
	var soil: Material = materials.terrain_material("soil_side")
	check("ground phase blending reuses original image at manifest metre scale",grass is ShaderMaterial and grass.get_shader_parameter("sample_metres")==Vector2(1.6,1.6) and grass.get_shader_parameter("ground_texture")==materials.material("grass_top").albedo_texture)
	check("new grass and fine gravel are actually bound as compatible top variants",grass.get_shader_parameter("use_variant")==true and grass.get_shader_parameter("variant_texture")==materials.material("grass_top_detail").albedo_texture and materials.terrain_material("gravel").get_shader_parameter("variant_texture")==materials.material("gravel_fine").albedo_texture)
	var soil_top: Material = materials.terrain_material("soil_top")
	check("loose soil tops bind dedicated fine loose earth rather than compacted road",soil_top is ShaderMaterial and soil_top.get_shader_parameter("ground_texture")==soil.albedo_texture and soil_top.get_shader_parameter("variant_texture")==materials.material("soil_top_fine").albedo_texture)
	var mipmaps := true
	for id in ["grass_top","grass_top_detail","soil_side","soil_top_fine","gravel","gravel_fine","dirt_road"]:
		mipmaps=mipmaps and materials.material(id).albedo_texture.get_image().has_mipmaps()
	check("actual metre-sampled textures have native mip chains, not sampler flags alone",mipmaps)
	check("excavated gravel side keeps vertical native sampling without top variants",materials.terrain_material("gravel","side") is StandardMaterial3D)
	check("directional soil section retains native material and metre scale",soil is StandardMaterial3D and soil.uv1_scale==Vector3(0.625,0.625,1))
	var facts_before := world.snapshot()
	var ground := Mesher.build(world,"3,-1,0")
	var metres_ok := true
	for g in ground.groups.values():
		for i in g.vertices.size():
			var p: Vector3 = g.vertices[i]
			var normal: Vector3 = g.normals[i]
			var expected := Vector2(p.x,p.z) if absf(normal.y)>0.5 else Vector2(p.z if absf(normal.x)>0.5 else p.x,p.y)
			metres_ok=metres_ok and g.uvs[i].is_equal_approx(expected)
	check("greedy mesh emits exact continuous world-metre coordinates",metres_ok)
	var terrain := TerrainView.new();terrain.set_process(false);root.add_child(terrain)
	terrain.configure({"world":world,"materials":materials})
	terrain.set_process(false)
	terrain.on_world_changed({"chunks":["3,-1,0","4,-1,0"]})
	terrain.environment.rebuild_ground("3,-1,-1")
	var transition_ok := true
	var count := 0
	for key in terrain.environment._ground:
		var instance: MeshInstance3D = terrain.environment._ground[key]
		for surface in instance.mesh.get_surface_count():
			var a: Array = instance.mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var u: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var strip: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
			for start in range(0,v.size(),4):
				var along: Vector3 = (v[start+1]-v[start]).normalized()
				transition_ok=transition_ok and is_equal_approx(v[start].distance_to(v[start+3]),0.65)
				for i in range(start,start+4):
					transition_ok=transition_ok and u[i].is_equal_approx(Vector2(v[i].x,v[i].z)) and is_equal_approx(strip[i].x,v[i].dot(along)/1.6) and strip[i].y==(0.0 if i<start+2 else 1.0)
				count+=1
	check("road shoulders sample continuously instead of restarting each half-metre",transition_ok and count>0,{"quads":count})
	var shoulder_bindings := true
	for id in [2,4,6]:
		var treatment: ShaderMaterial = materials.shoulder_material(id)
		var earth_id: String = {2:"soil_top",4:"dirt_road",6:"gravel"}[id]
		var native: ShaderMaterial = materials.terrain_material(earth_id)
		shoulder_bindings=shoulder_bindings and treatment.get_shader_parameter("earth_texture")==native.get_shader_parameter("ground_texture") and treatment.get_shader_parameter("earth_metres")==native.get_shader_parameter("sample_metres") and treatment.get_shader_parameter("earth_use_variant")== (native.get_shader_parameter("use_variant")==true) and treatment.get_shader_parameter("grass_texture")==grass.get_shader_parameter("ground_texture") and treatment.get_shader_parameter("grass_variant")==grass.get_shader_parameter("variant_texture")
	check("shoulders reuse exact grass and actual soil-road-gravel sources and metre scales",shoulder_bindings)
	check("flat ground shoulders receive lighting without casting an elevated cutout shadow",terrain.environment._ground.values().all(func(node: MeshInstance3D)->bool:return node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
	check("terrain/environment derivation never changes authoritative facts",facts_before==world.snapshot())
	var passes: int=terrain.environment.sync_passes
	terrain.on_world_changed({"world":[{"op":"extension.set","id":"r3:production"}]})
	check("actual runtime extension-only notification skips unrelated environment scan",terrain.environment.sync_passes==passes and facts_before==world.snapshot())
	var tree_id := "rural:v1:RH-HOME:tree:02"
	var tree_root: Node3D = terrain.environment.get_node_or_null(NodePath(tree_id.validate_node_name()))
	check("real tree retains grounded leaf and shrub layers",tree_root!=null and tree_root.has_node("GroundLeaves") and tree_root.has_node("GroundShrub_0"))
	var low: MeshInstance3D = tree_root.get_node_or_null("GroundShrub_1") if tree_root!=null else null
	var tall: MeshInstance3D = tree_root.get_node_or_null("GroundShrub_0") if tree_root!=null else null
	var low_slot: int=int(low.get_meta("atlas_cell")) if low!=null else -1
	check("new low cover replaces only the existing low box, keeps taller A03 shrub",low!=null and tall!=null and low.mesh.get_aabb().size.y>=0.12 and low.mesh.get_aabb().size.y<=0.3 and is_equal_approx(tall.mesh.get_aabb().size.y,0.6) and low.material_override==materials.material("low_cover_atlas"))
	var cover: StandardMaterial3D = materials.material("low_cover_atlas")
	check("low cover uses two cropped cutout planes at true baseline without sorted transparency",low!=null and low.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==8 and low.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==12 and low.get_meta("atlas_baseline_px")==232 and low.mesh.get_aabb().position.y==0 and cover.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and not cover.texture_repeat)
	var alpha: Image = cover.albedo_texture.get_image()
	var atlas_ok := alpha.get_size()==Vector2i(512,512) and alpha.detect_alpha()!=Image.ALPHA_NONE
	for k in 4:
		var b: Array = materials.manifest().low_cover_atlas.alpha_bboxes[k]
		for y in 256:
			for x in 256:
				if x<16 or x>=240 or y<16 or y>=240: atlas_ok=atlas_ok and alpha.get_pixel((k%2)*256+x,(k/2)*256+y).a==0
		var probe: MeshInstance3D = terrain.environment._low_cover(tree_root,Vector3.ZERO,k,0)
		var uv: PackedVector2Array = probe.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		atlas_ok=atlas_ok and uv[0].is_equal_approx((Vector2(k%2,k/2)*256+Vector2(b[0],232))/512.0) and is_equal_approx(probe.mesh.get_aabb().size.x,0.49) and probe.mesh.get_aabb().size.y<=0.3
		tree_root.remove_child(probe);probe.free()
	check("all four delivered cells preserve transparent gutters, exact UV slot/aspect and shared baseline",atlas_ok)
	check("live foundation edge derives limited earth contact bands from real source IDs",terrain.environment.statistics().foundation_contact_quads>0 and terrain.environment._contacts.values().all(func(node: MeshInstance3D)->bool:return node.get_meta("foundation_ids").all(func(id: String)->bool:return world.entity(id).get("tags",[]).has("foundation"))),terrain.environment.statistics())
	var contact_key: String = terrain.environment._contacts.keys()[0] if not terrain.environment._contacts.is_empty() else ""
	var contact_arrays: Array = terrain.environment._contacts[contact_key].mesh.surface_get_arrays(0) if not contact_key.is_empty() else []
	var contact_grounded := not contact_arrays.is_empty()
	for visual in terrain.environment._contacts.values():
		var v: PackedVector3Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for first in range(0,v.size(),4):
			var lo: Vector3=v[first];var hi: Vector3=v[first]
			for k in range(first,first+4):lo=lo.min(v[k]);hi=hi.max(v[k])
			contact_grounded=contact_grounded and terrain.environment._grounded(Vector3((lo.x+hi.x)/2,lo.y-0.009,(lo.z+hi.z)/2),Vector2(hi.x-lo.x,hi.z-lo.z),1)
	check("every contact quad rests on full exposed resident grass footprint, excluding roads and holes",contact_grounded)
	# Exercise the new root footprint, not just the older shrub-centre vectors.
	# Keep the tree centre supported so the entire tree cannot disappear and
	# accidentally make this attachment-only assertion pass.
	var tree: Dictionary = world.entity(tree_id)
	var center := Vector3(tree.position.x,tree.position.y,tree.position.z)
	var root_case := {}
	for offset in [Vector3(-0.23,0,0),Vector3(0.23,0,0),Vector3(0,0,0.23)]:
		for z in range(floori((center.z+offset.z-0.12+0.00001)/0.5),floori((center.z+offset.z+0.12-0.00001)/0.5)+1):
			for x in range(floori((center.x+offset.x-0.14+0.00001)/0.5),floori((center.x+offset.x+0.14-0.00001)/0.5)+1):
				if x==floori(center.x/0.5) and z==floori(center.z/0.5): continue
				if root_case.is_empty() and root_piece(tree_root,offset+Vector3(0,0.08,0)):
					root_case={"cell":{"x":x,"y":-1,"z":z},"position":offset+Vector3(0,0.08,0)}
	var root_sync := false
	var root_restore := false
	if not root_case.is_empty():
		var c: Dictionary = root_case.cell
		var original: int = world.cell_at(c.x,c.y,c.z)
		var removed: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":c,"before":original,"after":0}],world.get_revision())
		if removed.ok:
			terrain.on_world_changed(world.commit_prepared(removed.capability).changes)
			tree_root=terrain.environment.get_node_or_null(NodePath(tree_id.validate_node_name()))
			root_sync=tree_root!=null and not root_piece(tree_root,root_case.position) and world.surface_height(center.x,center.z)==center.y
			var refill: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":c,"before":0,"after":original}],world.get_revision())
			if refill.ok:
				terrain.on_world_changed(world.commit_prepared(refill.capability).changes)
				tree_root=terrain.environment.get_node_or_null(NodePath(tree_id.validate_node_name()))
				root_restore=root_piece(tree_root,root_case.position) and world.entity(tree_id)==tree
	check("root footprint corner excavation removes only unsupported root",root_sync,root_case)
	check("root refill reconstructs attachment without new resource fact",root_restore)
	var low_offset := Vector3(1.35,0,0.9)
	var low_cell := {"x":floori((center.x+low_offset.x+0.32)/0.5),"y":-1,"z":floori((center.z+low_offset.z+0.26)/0.5)}
	var low_before: int=world.cell_at(low_cell.x,low_cell.y,low_cell.z)
	var low_cut: Dictionary=world.prepare_changes([{"op":"voxel.set","cell":low_cell,"before":low_before,"after":0}],world.get_revision())
	if low_cut.ok:terrain.on_world_changed(world.commit_prepared(low_cut.capability).changes)
	tree_root=terrain.environment.get_node_or_null(NodePath(tree_id.validate_node_name()))
	check("low cutout disappears when a corner of its checked footprint is excavated",low_cut.ok and tree_root!=null and not tree_root.has_node("GroundShrub_1"))
	var low_fill: Dictionary=world.prepare_changes([{"op":"voxel.set","cell":low_cell,"before":0,"after":low_before}],world.get_revision())
	if low_fill.ok:terrain.on_world_changed(world.commit_prepared(low_fill.capability).changes)
	tree_root=terrain.environment.get_node_or_null(NodePath(tree_id.validate_node_name()))
	check("low cover refill restores the same stable atlas cell without adding yield",low_fill.ok and tree_root!=null and tree_root.has_node("GroundShrub_1") and tree_root.get_node("GroundShrub_1").get_meta("atlas_cell")==low_slot and world.entity(tree_id)==tree)
	var before_count: int = terrain.environment.statistics().ground_transition_chunks
	var cell := {"x":63,"y":-1,"z":4}
	var before: int = world.cell_at(cell.x,cell.y,cell.z)
	var p: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":cell,"before":before,"after":0}],world.get_revision())
	if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
	var synchronized := true
	for record in terrain._chunks.values():
		var shape: CollisionShape3D = record.node.get_child(1).get_child(0)
		synchronized=synchronized and shape.shape!=null
	check("edited neighbour mesh and collision remain present from same geometry",p.ok and synchronized and world.cell_at(63,-1,4)==0,{"before_material":before,"transition_chunks_before":before_count,"after":terrain.environment.statistics()})
	var key := "3,-1,0"
	p=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
	if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
	check("cold projection removes shoulder and terrain while retaining hole",not terrain._chunks.has(key) and not terrain.environment._ground.has(key) and world.cell_at(63,-1,4)==0)
	p=world.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],world.get_revision())
	if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
	check("warm revisit reconstructs same edited facts and material bindings",terrain._chunks.has(key) and world.cell_at(63,-1,4)==0 and materials.missing.is_empty(),materials.missing)
	if not contact_key.is_empty():
		var saved: Dictionary = world.snapshot()
		var v: PackedVector3Array = terrain.environment._contacts[contact_key].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var midpoint := (v[0]+v[1]+v[2]+v[3])/4.0
		var cut_cell := {"x":floori(midpoint.x/0.5),"y":floori((midpoint.y-0.02)/0.5),"z":floori(midpoint.z/0.5)}
		var old_quads: int = terrain.environment.statistics().foundation_contact_quads
		p=world.prepare_changes([{"op":"voxel.set","cell":cut_cell,"before":1,"after":0}],world.get_revision())
		if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
		check("excavating an exterior contact footprint removes its unsupported band",p.ok and terrain.environment.statistics().foundation_contact_quads<old_quads,cut_cell)
		p=world.prepare_changes([{"op":"voxel.set","cell":cut_cell,"before":0,"after":1}],world.get_revision())
		if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
		check("refilling the same facts reconstructs exact prior contact geometry",p.ok and terrain.environment._contacts.has(contact_key) and terrain.environment._contacts[contact_key].mesh.surface_get_arrays(0)==contact_arrays)
		var original_entity: Dictionary = world.entity(str(terrain.environment._contacts[contact_key].get_meta("foundation_ids")[0]))
		p=world.prepare_changes([{"op":"entity.remove","id":original_entity.id,"before":original_entity}],world.get_revision())
		if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
		check("removing a real foundation removes its attachments, without phantom saved edges",p.ok and terrain.environment._contacts.values().all(func(node: MeshInstance3D)->bool:return not node.get_meta("foundation_ids").has(original_entity.id)))
		p=world.prepare_changes([{"op":"entity.put","id":original_entity.id,"before_exists":false,"before":null,"after":original_entity}],world.get_revision())
		# Retired IDs must not be resurrected: restore the preserved checkpoint
		# for this projection-only removal fixture, not a gameplay undo command.
		check("removed stable identity cannot be reused by decoration restoration",not p.ok)
		var encoded: Dictionary = Codec.encode_checkpoint(saved,{},"environment:contact-revisit")
		var decoded: Dictionary = Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var restored: bool = decoded.ok and world.load_snapshot(decoded.state).ok
		terrain.on_world_changed({"reload":true});terrain.set_process(false)
		check("reload to encoded cold facts immediately clears old overlays",restored and terrain.environment._contacts.is_empty() and terrain.environment._ground.is_empty())
		var warming: Array = []
		for chunk_key in saved.chunks:
			if saved.chunks[chunk_key].resident: warming.append({"op":"chunk.residency","id":chunk_key,"before":false,"after":true})
		p=world.prepare_changes(warming,world.get_revision())
		if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
		check("saved checkpoint recreates identical contact arrays with no saved visual authority",restored and terrain.environment._contacts.has(contact_key) and terrain.environment._contacts[contact_key].mesh.surface_get_arrays(0)==contact_arrays)
		p=world.prepare_changes([{"op":"chunk.residency","id":contact_key,"before":true,"after":false}],world.get_revision())
		if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
		check("cold chunk removes derived foundation contacts while retaining authoritative structures",p.ok and not terrain.environment._contacts.has(contact_key) and world.entity(original_entity.id)==JSON.parse_string(JSON.stringify(original_entity,"",true,true)))
		p=world.prepare_changes([{"op":"chunk.residency","id":contact_key,"before":false,"after":true}],world.get_revision())
		if p.ok: terrain.on_world_changed(world.commit_prepared(p.capability).changes)
		check("warm contact revisit rebuilds exact same world-metre mesh",p.ok and terrain.environment._contacts.has(contact_key) and terrain.environment._contacts[contact_key].mesh.surface_get_arrays(0)==contact_arrays)
	# Grass cell x15 borders the real gravel pad in the adjacent x16 chunk.
	# Resident grass must not project a strip over retained but cold road facts.
	var grass_key := "0,-1,5";var road_key := "1,-1,5"
	terrain.environment.rebuild_ground(grass_key)
	var original_shoulders: Array = []
	if terrain.environment._ground.has(grass_key):
		for surface in terrain.environment._ground[grass_key].mesh.get_surface_count(): original_shoulders.append(terrain.environment._ground[grass_key].mesh.surface_get_arrays(surface))
	var residency: Dictionary=world.prepare_changes([{"op":"chunk.residency","id":road_key,"before":true,"after":false}],world.get_revision())
	if residency.ok: terrain.on_world_changed(world.commit_prepared(residency.capability).changes)
	check("resident grass cannot project shoulders into a cold adjacent road chunk",not original_shoulders.is_empty() and residency.ok and not terrain.environment._ground.has(grass_key))
	residency=world.prepare_changes([{"op":"chunk.residency","id":road_key,"before":false,"after":true}],world.get_revision())
	if residency.ok: terrain.on_world_changed(world.commit_prepared(residency.capability).changes)
	var revisited_shoulders: Array = []
	if terrain.environment._ground.has(grass_key):
		for surface in terrain.environment._ground[grass_key].mesh.get_surface_count(): revisited_shoulders.append(terrain.environment._ground[grass_key].mesh.surface_get_arrays(surface))
	check("warming the same road restores exact shoulder UVs and geometry",residency.ok and original_shoulders==revisited_shoulders)
	var failed := checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"section8 actual terrain/environment generation; headless native, no GPU/VA/app pass","checks":checks,"failed":failed,"visual_cost_change":{"ground_sample_branches":3,"previous_fetches":1,"extra_variant_textures":3,"extra_branch_meshes_per_standing_tree":1,"additional_low_cover_meshes":0,"low_cover_quads_each":2,"contact":terrain.environment.statistics(),"actual_gpu_branch_cost":"unmeasured"},"adopted_variants":["grass_top_detail","gravel_fine","soil_top_fine","low_cover_atlas"],"unbound_registered_images":["concrete","grass_corner","moss_edge"]}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result));terrain.free();quit(1 if failed else 0)
