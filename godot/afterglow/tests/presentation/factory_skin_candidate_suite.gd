extends "res://tests/buildings/domain_suite.gd"
## Real imported GLBs + exact delivered v5 PNGs. No renderer or VA qualification.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")

func pixels(image:Image)->PackedByteArray:
	image=image.duplicate()
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("actual rural source world loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("neighbor",at.merged({"x":31},true)),resident("shopkeeper",at.merged({"x":32},true))])
	var before:Dictionary=runtime.capture_checkpoint()
	var view:=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	expect("all three actual rigs assemble with selected daily skins",view.assembly_report().ok and view._skin_models.size()==3,view.assembly_report())
	var selection:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Actors.SKIN_DIRECTORY+"selection.json"))
	var source_modes:Dictionary={}
	for id:String in view._skin_models:
		var model:String=view._skin_models[id]
		var expected_path:String=Actors.SKIN_DIRECTORY+model+"_normal.png"
		var texture:Texture2D=view._skin_textures.get(model+"_normal")
		expect("actual instance selects independent v5 path "+id,texture!=null and texture.get_meta("source_resource","")==expected_path)
		if texture==null:continue
		var mode:String=texture.get_meta("source_mode","");source_modes[id]=mode
		expect("binding declares actual import or source-png provenance "+id,mode in ["imported","source-png"])
		var source:Image=Image.load_from_file(expected_path)
		expect("exact opaque candidate pixels and derived mip chain "+id,Actors._valid_skin_image(source) and texture.get_image().has_mipmaps() and pixels(source)==pixels(texture.get_image()))
		var rows:Array=selection.assets.filter(func(row:Dictionary)->bool:return row.resource==expected_path)
		expect("copied PNG matches art manifest SHA "+id,rows.size()==1 and FileAccess.get_sha256(expected_path)==str(rows[0].sha256))
		var original:Node3D=load(view._model_paths[id]).instantiate()
		var same_geometry:=true;var same_material:=true;var isolated:=true
		for binding:Dictionary in view._skin_bindings[id]:
			var original_mesh:MeshInstance3D=original.find_child(str(binding.mesh.name),true,false)
			var surface:int=binding.surface
			same_geometry=same_geometry and original_mesh!=null and var_to_bytes(original_mesh.mesh.surface_get_arrays(surface))==var_to_bytes(binding.mesh.mesh.surface_get_arrays(surface))
			var applied:BaseMaterial3D=binding.mesh.get_active_material(surface)
			var base:BaseMaterial3D=binding.base
			same_material=same_material and applied.roughness==base.roughness and applied.metallic==base.metallic and applied.cull_mode==base.cull_mode and applied.transparency==base.transparency and applied.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			isolated=isolated and applied!=base and applied.albedo_texture==texture and applied.albedo_color==Color.WHITE and binding.mesh.mesh.surface_get_material(surface)==original_mesh.mesh.surface_get_material(surface)
		expect("all original mesh arrays including UV unchanged "+id,same_geometry)
		expect("original material character and opaque geometry preserved "+id,same_material)
		expect("v5 applies via isolated instance material only "+id,isolated)
		original.free()
	expect("selection never changes clock inventory world or actor facts",Data.json_equal(before,runtime.capture_checkpoint()))
	var facts:Dictionary=runtime.facts();facts.actors[0].wounds=[{"cause":"explicit fallback fixture"}]
	expect("explicit wound fact configures",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("missing injury falls back to this role v5 normal",view._skin_applied.player=="normal" and view.statistics().skin_sources.player.resource==Actors.SKIN_DIRECTORY+str(view._skin_models.player)+"_normal.png",view.statistics().skin_sources)
	var old_root:int=view.roots.player.get_instance_id()
	facts=runtime.facts();facts.actors[0].appearance_id="r1_resident_shopkeeper"
	expect("actual appearance change configures",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("rig replacement binds new role candidate with no stale skin",view.roots.player.get_instance_id()!=old_root and view._skin_models.player=="r1_resident_shopkeeper" and view.statistics().skin_sources.player.resource==Actors.SKIN_DIRECTORY+"r1_resident_shopkeeper_normal.png")
	var sources:Dictionary=view.statistics().skin_sources
	view.free()
	var result:Dictionary={"scope":"actual imported GLBs and selected AR18-v5 PNG pixel/material binding; source/import modes explicit; NOT normal-camera VA or exported package proof","skin_sources":sources,"initial_source_modes":source_modes,"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_V5_SKIN "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
