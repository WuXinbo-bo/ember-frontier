extends "res://tests/buildings/domain_suite.gd"
## Actual PNGs and imported actor meshes. Report each image's actual source mode;
## --source-images remains an explicit diagnostic fixture, never imported adoption.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")

func pixels(texture:Texture2D)->PackedByteArray:
	var image:Image=texture.get_image().duplicate()
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("same real rural fixture loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("neighbor",at.merged({"x":31},true)),resident("shopkeeper",at.merged({"x":32},true))])
	var before:Dictionary=runtime.capture_checkpoint()
	var source_only:bool=OS.get_cmdline_user_args().has("--source-images")
	var image_resources:Array=[]
	var view:=Actors.new()
	var source_textures:Dictionary={}
	if source_only:
		# D cannot import while A owns the running app. Use the exact delivered
		# PNGs with the existing instance binding, never call it imported adoption.
		for path:String in Actors.MODEL_PATHS:
			var model:String=path.get_file().get_basename()
			var image_path:String=Actors.SKIN_DIRECTORY+model+"_normal.png"
			var candidate:Image=Image.load_from_file(ProjectSettings.globalize_path(image_path))
			if not Actors._valid_skin_image(candidate):
				expect("source candidate obeys original UV contract "+model,false);continue
			candidate.generate_mipmaps()
			source_textures[model+"_normal"]=ImageTexture.create_from_image(candidate)
			var imported:Texture2D=load(image_path) if ResourceLoader.exists(image_path,"Texture2D") else null
			image_resources.append({"path":image_path,"source_matches_current_import":imported!=null and pixels(imported)==pixels(source_textures[model+"_normal"]),"source_only":true})
	root.add_child(view);view.configure(runtime);view.set_process(false)
	if source_only:
		# configure now retires all former-world caches. Install this explicitly
		# labelled source-only fixture AFTER binding, never call it an import.
		view._skin_textures.merge(source_textures,true);view._skin_materials.clear();view._skin_states.clear();view.sync(0)
	expect("three normal PNGs bind actual actor instances ("+("explicit source fixture" if source_only else "consumer-selected resources; see source modes")+")",view._skin_applied.size()==3 and view._skin_applied.values().all(func(state:String)->bool:return state=="normal"),view.statistics())
	for id:String in view._skin_models:
		var model:String=view._skin_models[id]
		var path:String=Actors.SKIN_DIRECTORY+model+"_normal.png"
		var image:Image=Image.load_from_file(ProjectSettings.globalize_path(path))
		expect("delivered atlas dimensions and opacity satisfy original UV "+id,Actors._valid_skin_image(image))
		var actual:Texture2D=view._skin_textures.get(model+"_normal")
		expect("actual candidate pixel data and mip chain bind "+id,actual!=null and actual.get_image().has_mipmaps() and pixels(actual)==pixels(ImageTexture.create_from_image(image)))
		var correct:=true;var preserved:=true
		for binding:Dictionary in view._skin_bindings[id]:
			var material:BaseMaterial3D=binding.mesh.get_active_material(binding.surface)
			correct=correct and material!=binding.base and material.albedo_texture==actual and material.albedo_color==Color.WHITE
			preserved=preserved and material.roughness==binding.base.roughness and material.metallic==binding.base.metallic and material.cull_mode==binding.base.cull_mode
		expect("all actual imported surfaces use isolated candidate material "+id,correct)
		expect("original material geometry and surface character are preserved "+id,preserved)
		if source_only:
			var role:String=model.trim_prefix("r1_resident_")
			var template_path:String=ProjectSettings.globalize_path("res://").path_join("../../outputs/r3-3-character-uv-v1/"+role+"/regions-and-uv.json").simplify_path()
			var template:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(template_path))
			var uv_ok:=true
			for binding:Dictionary in view._skin_bindings[id]:
				var parts:Array=template.parts.filter(func(part:Dictionary)->bool:return part.part==str(binding.mesh.name))
				if parts.size()!=1:uv_ok=false;continue
				var actual_uv:PackedVector2Array=binding.mesh.mesh.surface_get_arrays(binding.surface)[Mesh.ARRAY_TEX_UV]
				var source_uv:Array=parts[0].primitives[binding.surface].uv
				var actual_keys:Array=[];var expected_keys:Array=[]
				for uv:Vector2 in actual_uv:actual_keys.append(var_to_bytes(uv).hex_encode())
				for uv:Array in source_uv:expected_keys.append(var_to_bytes(Vector2(floorf(float(uv[0])*65535.0)/65535.0,floorf(float(uv[1])*65535.0)/65535.0)).hex_encode())
				actual_keys.sort();expected_keys.sort();uv_ok=uv_ok and actual_keys==expected_keys
			expect("all six actual mesh UVs match exact original UNORM16 contract "+id,uv_ok)
	expect("candidate binding cannot change any world or facts",Data.json_equal(before,runtime.capture_checkpoint()))
	var facts:Dictionary=runtime.facts();facts.actors[0].hp=60.0;facts.actors[0].wounds=[]
	expect("explicit low HP fixture accepted",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("low HP alone keeps delivered normal",view._skin_applied.player=="normal" and view._skin_states.player=="normal")
	facts=runtime.facts();facts.actors[0].wounds=[{"cause":"explicit candidate fallback fixture"}]
	expect("explicit wound fixture accepted",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("missing injury candidate retains correct role normal",view._skin_states.player=="injured" and view._skin_applied.player=="normal")
	var original_ok:=true
	view._apply_skin_texture("player",null,"original")
	for binding:Dictionary in view._skin_bindings.player:original_ok=original_ok and binding.mesh.get_active_material(binding.surface)==binding.base
	expect("original shared material is intact and still restorable",original_ok)
	var binding_sources:Dictionary=view.statistics().skin_sources
	view.free()
	var result:Dictionary={"scope":"explicit source PNG fixture; IMPORT ADOPTION PENDING" if source_only else "actual normal PNG consumer binding; per-image imported/source-png modes recorded","skin_sources":binding_sources,"normal_camera_VA":false,"image_resources":image_resources,"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_ARRIVED_SKIN "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
