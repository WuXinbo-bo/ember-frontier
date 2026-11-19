extends SceneTree
## Native geometry/material/cell checks, never package/Metal/normal-camera VA.
const Quality=preload("res://scripts/environment/environment_quality.gd")
const Models=preload("res://scripts/environment/ecology_models.gd")
const Generator=preload("res://scripts/world/landscape_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Materials=preload("res://scripts/environment/environment_materials.gd")
const TerrainView=preload("res://scripts/terrain/terrain_view.gd")
var checks:Array=[]
var details:Dictionary={}
var max_repacked_normal_error:=0.0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func sha(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func triangles(items:Array)->Dictionary:
	var rows:Dictionary={}
	for item:Dictionary in items:
		for s in item.mesh.get_surface_count():
			var a:Array=item.mesh.surface_get_arrays(s);var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var row:Array=[];var normals:Array=[]
				for j in 3:row.append(a[Mesh.ARRAY_VERTEX][indices[i+j]]);normals.append(a[Mesh.ARRAY_NORMAL][indices[i+j]])
				rows[var_to_bytes(row).hex_encode()]=normals
	return rows
func geometry_equal(a:Array,b:Array)->bool:
	var left:Dictionary=triangles(a);var right:Dictionary=triangles(b)
	if left.size()!=right.size():return false
	for key:String in left:
		if not right.has(key):return false
		for i in 3:max_repacked_normal_error=maxf(max_repacked_normal_error,left[key][i].distance_to(right[key][i]))
	return max_repacked_normal_error<0.0002
func run()->void:
	var quality:=Quality.new();var exact:=true;var cutouts:=0;var tiling:=0;var cutout_ids:Array=[]
	for row:Dictionary in quality.rows.values():
		exact=exact and sha(FileAccess.get_file_as_bytes(row.resource))==row.sha256
		var mat:StandardMaterial3D=quality.material(row.id)
		exact=exact and mat.albedo_texture!=null and mat.albedo_texture.get_image().has_mipmaps()
		if row.alpha:
			cutouts+=1;cutout_ids.append(row.id)
			var parts:Array=quality.cutout_parts(row.id,float(row.visible_size_m[0]))
			var a:Array=parts[0].mesh.surface_get_arrays(0);var v:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var h:float=row.full_canvas_m[1]
			var ground_y:float=float(row.pivot[1])*h-float(row.alpha_bbox[3])/512.0*h
			check("cutout baseline aspect native alpha depth "+row.id,is_zero_approx(ground_y) and is_equal_approx(v[2].y-v[1].y,h) and is_equal_approx(v[1].x-v[0].x,float(row.full_canvas_m[0])) and not mat.texture_repeat and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and mat.cull_mode==BaseMaterial3D.CULL_DISABLED and a[Mesh.ARRAY_INDEX].size()==12)
		elif mat.texture_repeat:
			tiling+=1
			exact=exact and mat.uv1_scale.is_equal_approx(Vector3(1.0/row.physical_m[0],1.0/row.physical_m[1],1))
	check("28 exact staged images load native mips without replacing artist bytes",exact and quality.rows.size()==28 and cutouts==12 and tiling==15 and quality.failures.is_empty(),quality.failures)
	var models:=Models.new();models.quality=quality
	for id:String in ["broadleaf_tree","conifer_tree","dead_tree","tree_stump"]:
		var original:Array=models.parts(id);var remapped:Array=models.quality_parts(id,3.84 if id!="tree_stump" else 0.32,1)
		check("semantic local-atlas rebind preserves all oriented geometry "+id,geometry_equal(original,remapped) and models.failures.is_empty(),{"triangles":models.quality_triangles,"max_native_normal_repack_error":max_repacked_normal_error})
	var assembled:Dictionary=Assembly.prepare(Generator.generate(713,Buildings.generation_profiles()))
	check("new picture style uses actual formal A/B complete assembled world",assembled.ok,assembled.get("reason"))
	if not assembled.ok:return finish()
	var world:=State.new();world.load_snapshot(assembled.capture.world);var original:Dictionary=world.snapshot()
	var cars:Array=world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("dressing_profile_id")=="abandoned_car")
	check("safe persistent plan installs real B sedan with no stock or interaction",cars.size()>0 and cars.all(func(e:Dictionary)->bool:return e.data.no_stock and e.data.no_interaction and e.data.solid and e.data.opaque),cars)
	var terrain:=TerrainView.new();root.add_child(terrain);terrain.configure({"world":world});terrain.set_process(false)
	var env:Node3D=terrain.environment
	var keys:Dictionary={}
	for region:Dictionary in world.regions():
		var plan:Dictionary=world.extension("generation:"+region.id)
		for key:String in plan.field_surfaces.chunks:keys[key]=true
	for key:String in keys:env.rebuild_ground(key)
	var count:=0;var aligned:=true;var styles:Dictionary={}
	for node:MeshInstance3D in env._fields.values():
		count+=node.get_meta("actual_support_cells").size()
		for s in node.mesh.get_surface_count():
			styles[node.mesh.surface_get_material(s).resource_name]=true
			var a:Array=node.mesh.surface_get_arrays(s)
			for i in a[Mesh.ARRAY_VERTEX].size():
				var p:Vector3=a[Mesh.ARRAY_VERTEX][i];aligned=aligned and a[Mesh.ARRAY_TEX_UV][i].is_equal_approx(Vector2(p.x,p.z))
	check("actual field and raised bank have continuous metre rows on real supports",count>300 and aligned and styles.has("C:quality:c05_dry_tilled_soil") and styles.has("C:quality:c07_earthen_bund"),{"cells":count,"styles":styles.keys(),"chunks":env._fields.size()})
	var materials:RefCounted=terrain.materials
	check("rural3 real stone binds weathered top and fractured side metres",materials.terrain_material("stone").resource_name=="C:quality:r01_weathered_stone" and materials.terrain_material("stone","side").resource_name=="C:quality:r02_fractured_stone")
	var legacy_materials:=Materials.new();legacy_materials.set_world_style("rural-2")
	check("old rural2 keeps original stone bindings",legacy_materials.terrain_material("stone").resource_name!="C:quality:r01_weathered_stone")
	var actually_used:Dictionary={}
	for node:Node3D in env._ecology.values():
		for id:String in node.get_meta("persistent_patch_ids"):actually_used[id]=true
	var rice:=0;var understorey:Dictionary={}
	for region:Dictionary in world.regions():
		for patch:Dictionary in world.extension("generation:"+region.id).ecology.patches:
			if not actually_used.has(patch.id):continue
			if str(patch.model).begins_with("quality:c0"):rice+=1
			else:understorey[patch.model]=true
	check("actual native MultiMeshes mount rice stages and distinct low plant shapes",rice>0 and understorey.size()>=4,{"static_field_patches":rice,"understorey":understorey.keys()})
	var key:String=env._fields.keys()[0];var supported:Array=env._fields[key].get_meta("actual_support_cells")[0]
	var cell:Dictionary={"x":supported[0],"y":supported[1],"z":supported[2]};var mat:int=supported[3]
	var draft:Dictionary=world.prepare_changes([{"op":"voxel.set","cell":cell,"before":mat,"after":0}],world.get_revision())
	var committed:Dictionary=world.commit_prepared(draft.capability) if draft.ok else draft
	if committed.ok:terrain.on_world_changed(committed.changes)
	var gone:=true
	if env._fields.has(key):gone=not env._fields[key].get_meta("actual_support_cells").has(supported)
	check("real dig removes only the original field surface cell",committed.ok and gone)
	draft=world.prepare_changes([{"op":"voxel.set","cell":cell,"before":0,"after":mat}],world.get_revision())
	committed=world.commit_prepared(draft.capability) if draft.ok else draft
	if committed.ok:terrain.on_world_changed(committed.changes)
	check("matching real fill restores original directional field appearance",committed.ok and env._fields.has(key) and env._fields[key].get_meta("actual_support_cells").has(supported))
	draft=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
	committed=world.commit_prepared(draft.capability) if draft.ok else draft
	if committed.ok:terrain.on_world_changed(committed.changes)
	check("cold field removes all original surface geometry immediately",committed.ok and not env._fields.has(key))
	check("native picture loader reports all missing sources",quality.failures.is_empty() and env.statistics().missing_quality_images.is_empty())
	details={"field_cells":count,"field_native_chunks":keys.size(),"tree_triangle_groups":models.quality_triangles,"environment":env.statistics(),"source_world_id":world.identity(),"initial_world_revision":original.revision,"final_world_revision":world.get_revision(),"scope":"native sources meshes materials and actual changed cells; not Metal/app screenshots or VA"}
	terrain.free();finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"details":details}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
