extends "res://tests/buildings/visual_surface_suite.gd"
## Real native meshes/GLBs/materials, not a screenshot or official package test.
const Dressing=preload("res://scripts/buildings/building_dressing.gd")
const DressingGeometry=preload("res://scripts/buildings/dressing_geometry.gd")

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(713,Building.generation_profiles(),"rural-2"))
	expect("existing real village prepares without implicit dressing",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	var host:=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
	expect("formal assembler provides real building material consumer",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings
	var original_capture:=runtime.capture_checkpoint()
	var view:Node3D=building.create_view({"runtime":runtime})
	var rows:Array=[]
	for profile:Dictionary in Dressing.profiles():
		var material_ids:Dictionary={};var triangles:=0
		for turn:int in 4:
			var slot:Dictionary={"id":"RH-HOME:geometry:"+profile.id+str(turn),"profile_id":profile.id,"position":{"x":32,"y":3.5,"z":50},"quarter_turn":turn,"state":"aged"}
			var entity:=Dressing.entity_for(profile,slot,"RH-HOME")
			var root:Node3D=DressingGeometry.create(entity,view);view.add_child(root)
			var actual:AABB=view.model_bounds(root);var collider:=Geometry.aabb(entity.bounds)
			var envelope:=collider.grow(0.0002)
			expect(profile.id+" actual rendered geometry is inside sole collider at turn "+str(turn),envelope.encloses(actual),{"actual":str(actual),"collider":str(collider)})
			if turn!=0:continue
			expect(profile.id+" is grounded at actual placed elevation",absf(actual.position.y-3.5)<0.0002,{"actual":str(actual)})
			if not str(profile.source_model).is_empty():
				var entry:Dictionary=view.manifest.models[profile.source_model]
				expect(profile.id+" uses unmodified original model bytes and UV",FileAccess.get_sha256(entry.resource)==entry.sha256 and root.get_child_count()>=1)
			var pending:Array=[root]
			while not pending.is_empty():
				var node:Node=pending.pop_back();pending.append_array(node.get_children())
				if not node is MeshInstance3D:continue
				for surface:int in node.mesh.get_surface_count():
					var arrays:Array=node.mesh.surface_get_arrays(surface)
					triangles+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
					var material:Material=node.get_active_material(surface)
					expect(profile.id+" actual mesh surface has authored textured material "+str(material_ids.size()),material is StandardMaterial3D and material.albedo_texture!=null)
					for id:String in view.materials:
						if material==view.materials[id]:material_ids[id]=true
					if profile.id=="haystack" and material==view.materials.get("straw_fibres"):
						var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
						var metric:=true
						for i:int in range(0,indices.size(),3):
							for edge:int in 3:
								var a:int=indices[i+edge];var b:int=indices[i+(edge+1)%3]
								if absf(vertices[a].distance_to(vertices[b])-uv[a].distance_to(uv[b])*0.6)>0.00001:metric=false
						expect("actual nine-bale straw mesh obeys approved 0.6m physical UV",metric and vertices.size()==9*24,{"vertices":vertices.size(),"metric":metric})
					if material==view.materials.living_palette:
						var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
						var texture_size:Vector2=material.albedo_texture.get_size()
						var crop:=Rect2(Vector2(642.5,770.5)/texture_size,Vector2(123,123)/texture_size)
						var contained:=true
						for p:Vector2 in uv:
							if not crop.grow(0.000001).has_point(p):contained=false
						expect("hay uses only real straw crop with half-pixel guards",contained)
			if profile.id=="haystack":
				var entry:Dictionary=view.manifest.textures.straw_fibres
				expect("actual haystack consumes approved c08 straw and original rope",material_ids.has("straw_fibres") and material_ids.has("hemp_rope") and not material_ids.has("living_palette") and entry.resource=="res://data/world/ecology/quality-v1/c08_straw_fibres.png" and FileAccess.get_sha256(entry.resource)==entry.sha256)
		rows.append({"id":profile.id,"triangles":triangles,"native_materials":material_ids.keys()})
	texture_chains(view)
	expect("new straw binding preserves all world facts stock clock and placement",preload("res://scripts/world/world_data.gd").json_equal(original_capture,runtime.capture_checkpoint()))
	print("ACTUAL_DRESSING_GEOMETRY "+JSON.stringify(rows))
	# Free mesh consumers while the view's PackedScene/material owners remain
	# alive, then release the cache on the following native frame.
	for child:Node in view.get_children():child.queue_free()
	await process_frame
	view.queue_free();host.queue_free()
	await process_frame
	finish(started)
