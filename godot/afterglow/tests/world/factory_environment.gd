extends "res://tests/world/factory_joint.gd"
## C derived-state check, not an A streaming-policy or normal-player journey.
## Real generated cells/module entities; explicit C storage/edit transactions.
const TerrainView=preload("res://scripts/terrain/terrain_view.gd")
var terrain:Node3D
var world:RefCounted

func apply(ops:Array)->Dictionary:
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision())
	if not tx.ok:return tx
	var result:Dictionary=world.commit_prepared(tx.capability)
	if result.ok:terrain.on_world_changed(result.changes)
	return result

func mesh_data(mesh:Mesh)->Array:
	var rows:Array=[]
	for i in mesh.get_surface_count():rows.append(mesh.surface_get_arrays(i))
	return rows

func node_data(node:Node)->Array:
	var row:Array=[node.get_class()]
	if node is Node3D:row.append(node.transform)
	if node is MeshInstance3D:row.append(mesh_data(node.mesh))
	if node is MultiMeshInstance3D:
		row.append(mesh_data(node.multimesh.mesh))
		for i in node.multimesh.instance_count:row.append(node.multimesh.get_instance_transform(i))
	if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:row.append(node.shape.get_faces())
	for child:Node in node.get_children():row.append(node_data(child))
	return row

func derived_signature()->String:
	var rows:Array=[]
	for collection:Dictionary in [terrain._chunks,terrain.environment._roots,terrain.environment._ecology,terrain.environment._ground,terrain.environment._contacts,terrain.environment._fields]:
		var keys:Array=collection.keys();keys.sort();var entries:Array=[]
		for key:String in keys:
			var node:Node=collection[key].node if collection[key] is Dictionary else collection[key]
			entries.append([key,node_data(node)])
		rows.append(entries)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(rows))
	return hash.finish().hex_encode()

func cached_bytes(keys:Array)->int:
	var total:int=0
	for key:String in keys:
		for values:PackedInt32Array in terrain._boundary_values.get(key,{}).get("faces",{}).values():total+=values.size()*4
	return total

func run()->void:
	var assembled:Dictionary=Assembly.prepare(Factory.generate(713,Modules.generation_profiles()))
	check("real factory cells and module geometry assemble for environment checks",assembled.ok,assembled.get("reason"))
	if not assembled.ok:return finish()
	world=State.new();var loaded:Dictionary=world.load_snapshot(assembled.capture.world)
	check("environment uses one actual authoritative world",loaded.ok)
	if not loaded.ok:return finish()
	terrain=TerrainView.new();root.add_child(terrain);terrain.set_process(false)
	terrain.configure({"world":world,"stream_updates":true,"budgeted_edits":true});terrain.cancel_pending()
	var region:String="RH-VILLAGE";var keys:Array=world.region_chunk_keys(region)
	var plan:Dictionary=world.extension("generation:"+region)
	var selected:Array=[]
	for key:String in plan.field_surfaces.chunks:
		selected.append(key)
		if selected.size()>=3:break
	for tree:Dictionary in world.entities(region):
		if tree.kind!="tree":continue
		var p:Dictionary=tree.position
		var key:String=Data.key(Data.cell_chunk(Vector3i(floori(p.x*2),floori((p.y-0.001)*2),floori(p.z*2)),16))
		if key not in selected:selected.append(key)
		if selected.size()>=6:break
	for key:String in keys:
		if not terrain.environment._ground_arrays(key).is_empty():
			if key not in selected:selected.append(key)
			break
	for key:String in selected:terrain._rebuild(key)
	await physics_frame
	var hot:String=derived_signature();var facts:String=raster_digest(world.snapshot())
	var initial:Dictionary=terrain.environment.statistics()
	check("actual trees cutout ecology fields and shoulders are mounted",initial.tree_roots>0 and initial.ecology_patches>0 and initial.field_surface_chunks>0 and initial.ground_transition_chunks>0,initial)
	var paved:bool=true
	for parcel:Dictionary in plan.parcels:
		paved=paved and world.cell_at(floori(parcel.origin.x*2),roundi(parcel.pad.height*2)-1,floori(parcel.origin.z*2)) in [4,6]
	check("actual paved module pads do not invent a grass foundation earth overlay",paved and initial.foundation_contact_quads==0)
	check("actual native meshes and physical shapes are ready before changes",terrain.readiness(selected).ready)
	var cache_before:int=cached_bytes(keys)
	check("real neighbour derivation populated exact boundary plane cache",cache_before>0,cache_before)
	var patch:Dictionary={}
	for candidate:Dictionary in plan.ecology.patches:
		var p:Dictionary=candidate.position
		var key:String=Data.key(Data.cell_chunk(Vector3i(floori(p.x*2),floori((p.y-0.001)*2),floori(p.z*2)),16))
		if terrain.environment._ecology.has(key) and candidate.id in terrain.environment._ecology[key].get_meta("persistent_patch_ids"):patch=candidate;break
	check("edit input is an actually visible persistent vegetation patch",not patch.is_empty())
	if patch.is_empty():terrain.free();return finish()
	var c:Dictionary={"x":floori(patch.position.x*2),"y":roundi(patch.position.y*2)-1,"z":floori(patch.position.z*2)}
	var mat:int=world.cell_at(c.x,c.y,c.z)
	var edit:Dictionary=apply([{"op":"voxel.set","cell":c,"before":mat,"after":0}])
	var visible:Array=[]
	for node:Node in terrain.environment._ecology.values():visible.append_array(node.get_meta("persistent_patch_ids"))
	check("real support removal immediately retires affected groundcover",edit.ok and patch.id not in visible)
	var restored:Dictionary=apply([{"op":"voxel.set","cell":c,"before":0,"after":mat}])
	visible.clear()
	for node:Node in terrain.environment._ecology.values():visible.append_array(node.get_meta("persistent_patch_ids"))
	check("matching factual fill restores same patch identity without reroll",restored.ok and patch.id in visible)
	# Test uses a bounded native subset; discard other pending allocations.
	terrain.cancel_pending()
	for key:String in selected:terrain._rebuild(key)
	check("edit-fill restores exact original native environment and terrain arrays",derived_signature()==hot)
	var old_nodes:Array=[]
	for key:String in selected:
		if terrain._chunks.has(key):old_nodes.append(terrain._chunks[key].node)
	var prep:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	var cold:Dictionary=apply(prep.world_changes) if prep.ok else prep
	var cold_count:int=0
	for collection:Dictionary in [terrain._chunks,terrain.environment._ecology,terrain.environment._ground,terrain.environment._contacts,terrain.environment._fields]:
		for key:String in keys:if collection.has(key):cold_count+=1
	var cold_trees:int=0
	for tree:Dictionary in world.entities(region):if terrain.environment._roots.has(tree.id):cold_trees+=1
	check("compressed cells retire every cold terrain body and environment layer immediately",cold.ok and cold_count==0 and cold_trees==0,{"layers":cold_count,"trees":cold_trees})
	check("cold data cannot satisfy physical or detailed readiness",not terrain.readiness(selected).ready and not world.region_is_resident(region))
	var retained:int=cached_bytes(keys)
	check("cold release also frees all cached factual boundary planes",retained==0,{"before_bytes":cache_before,"retained_bytes":retained})
	await process_frame
	check("retired native mesh body objects are actually freed",old_nodes.all(func(n:Variant)->bool:return not is_instance_valid(n)))
	var warm_prep:Dictionary=world.prepare_region_residency(region,true,world.get_revision())
	var warm:Dictionary=apply(warm_prep.world_changes) if warm_prep.ok else warm_prep
	terrain.cancel_pending()
	for key:String in selected:terrain._rebuild(key)
	await physics_frame
	check("reloaded exact cells restore physical readiness",warm.ok and terrain.readiness(selected).ready)
	check("cold warm round trip restores exact native meshes collision plants and contacts",derived_signature()==hot)
	check("all derived activity leaves persistent plans and real cells unchanged",raster_digest(world.snapshot())==facts and Data.json_equal(world.extension("generation:"+region),plan))
	var final:Dictionary=terrain.environment.statistics()
	check("all actual bound source images and plant models resolve",final.missing_materials.is_empty() and final.missing_models.is_empty() and final.missing_quality_images.is_empty(),final)
	costs={"boundary_cache_hot_bytes":cache_before,"boundary_cache_cold_bytes":retained,"selected_native_chunks":selected,"initial_environment":initial,"final_environment":final,"scope":"real C source-derived native arrays/objects only; storage/edit transactions explicit, not A scheduling, OS visual/Alpha/GPU/RSS or performance acceptance"}
	terrain.free();finish()
