extends "res://tests/buildings/domain_suite.gd"
## Explicit in-memory texture/wound fixtures. No finished art or native VA claim.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D
var original_materials:Dictionary={}
var geometry:Dictionary={}
func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("same finite C world loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("friend",at.merged({"x":31},true)),resident("other",at.merged({"x":32},true))])
	var facts:Dictionary=runtime.facts();facts.actors[0].hp=65.0;facts.actors[0].wounds=[];facts.actors[0].pack={"medicine":1}
	configure(facts)
	view=Actors.new()
	root.add_child(view);view.configure(runtime);view.set_process(false)
	# Missing-asset fixtures stay deterministic after normal skins arrive.
	# arrived_actor_skin_suite separately checks actual delivered images.
	for path:String in Actors.MODEL_PATHS:
		var model:String=path.get_file().get_basename()
		view._skin_textures[model+"_normal"]=null
		view._skin_textures[model+"_injured"]=null
	view._skin_states.clear();view.sync(0)
	expect("three original roles bind their six actual rigid mesh parts",view._skin_bindings.size()==3 and view._skin_bindings.values().all(func(entries:Array)->bool:return entries.size()==6))
	for id:String in view._skin_models:
		var role:String=str(view._skin_models[id]).trim_prefix("r1_resident_")
		var path:String=ProjectSettings.globalize_path("res://").path_join("../../outputs/r3-3-character-uv-v1/"+role+"/regions-and-uv.json").simplify_path()
		var extracted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var matches:=true;var details:Array=[]
		for binding:Dictionary in view._skin_bindings[id]:
			var records:Array=extracted.parts.filter(func(part:Dictionary)->bool:return part.part==str(binding.mesh.name))
			if records.size()!=1:matches=false;details.append(str(binding.mesh.name));continue
			var actual:PackedVector2Array=binding.mesh.mesh.surface_get_arrays(binding.surface)[Mesh.ARRAY_TEX_UV]
			var expected:Array=records[0].primitives[binding.surface].uv
			if actual.size()!=expected.size():matches=false;continue
			# This native import reorders vertices and stores UV as UNORM16.
			# Compare that exact packing rule, not an arbitrary tolerance.
			var actual_keys:Array=[];var expected_keys:Array=[]
			for uv:Vector2 in actual:actual_keys.append(var_to_bytes(uv).hex_encode())
			for uv:Array in expected:
				var packed:=Vector2(floorf(float(uv[0])*65535.0)/65535.0,floorf(float(uv[1])*65535.0)/65535.0)
				expected_keys.append(var_to_bytes(packed).hex_encode())
			actual_keys.sort();expected_keys.sort()
			if actual_keys!=expected_keys:
				var points:Array=[]
				for uv:Vector2 in actual:points.append([float(uv.x),float(uv.y)])
				details.append({"part":str(binding.mesh.name),"actual_uv":points,"expected_vertex_count":expected.size(),"actual_vertex_count":actual.size()})
			matches=matches and actual_keys==expected_keys
		expect("actual Godot UV matches exact UNORM16 import of artist template without flip "+role,matches,details)
	for id:String in view._skin_bindings:
		original_materials[id]=[];geometry[id]=[]
		for binding:Dictionary in view._skin_bindings[id]:
			original_materials[id].append(binding.mesh.get_active_material(binding.surface))
			geometry[id].append(var_to_bytes(binding.mesh.mesh.surface_get_arrays(binding.surface)))
	expect("missing candidate files preserve every original resident material",view.statistics().skin_states.values().all(func(state:String)->bool:return state=="original"))
	var invalid:=Image.create(512,512,false,Image.FORMAT_RGBA8);invalid.fill(Color(0.5,0.5,0.5,0.5))
	expect("transparent clothing cannot silently change opaque geometry",not Actors._valid_skin_image(invalid))
	var wrong:=Image.create(1024,512,false,Image.FORMAT_RGB8)
	expect("wrong atlas dimensions fail the original UV contract",not Actors._valid_skin_image(wrong))
	var before:Dictionary=runtime.capture_checkpoint()
	for id:String in view._skin_models:
		var model:String=view._skin_models[id]
		var source:Texture2D=load("res://data/gameplay/actors/"+model+"_model_albedo.png")
		var image:Image=source.get_image().duplicate();image.generate_mipmaps()
		expect("actual extracted original atlas validates "+id,Actors._valid_skin_image(image))
		# Diagnostic resources only, not copied to a production skin path.
		var normal:Texture2D=ImageTexture.create_from_image(image)
		view._skin_textures[model+"_normal"]=normal
		var wounded:Image=image.duplicate();wounded.clear_mipmaps();wounded.set_pixel(0,0,Color.RED);wounded.generate_mipmaps()
		view._skin_textures[model+"_injured"]=ImageTexture.create_from_image(wounded)
		view._skin_states.erase(id)
	view._skin_materials.clear();view.sync(0)
	var all_bound:=true;var render_properties:=true;var geometry_preserved:=true;var no_shared_writes:=true
	for id:String in view._skin_bindings:
		for i:int in view._skin_bindings[id].size():
			var binding:Dictionary=view._skin_bindings[id][i]
			var material:BaseMaterial3D=binding.mesh.get_active_material(binding.surface)
			var original:BaseMaterial3D=original_materials[id][i]
			all_bound=all_bound and material!=original and material.albedo_texture==view._skin_textures[view._skin_models[id]+"_normal"]
			render_properties=render_properties and material.roughness==original.roughness and material.metallic==original.metallic and material.cull_mode==original.cull_mode and material.albedo_color==Color.WHITE and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS and material.albedo_texture.get_image().has_mipmaps()
			geometry_preserved=geometry_preserved and geometry[id][i]==var_to_bytes(binding.mesh.mesh.surface_get_arrays(binding.surface))
			no_shared_writes=no_shared_writes and binding.mesh.mesh.surface_get_material(binding.surface)==original and original.albedo_texture!=material.albedo_texture
	expect("all actual surfaces receive their role-specific instance material",all_bound)
	expect("original roughness metal cull and real mip data survive binding",render_properties)
	expect("skin binding preserves exact vertices normals indices and original UV",geometry_preserved)
	expect("shared original mesh materials remain untouched",no_shared_writes)
	expect("low HP alone never fabricates an injury texture",view._skin_applied.player=="normal")
	expect("texture and pose binding cannot change world clock actor facts or inventory",Data.json_equal(before,runtime.capture_checkpoint()))
	facts=runtime.facts();facts.actors[0].wounds=[{"cause":"explicit isolated injury fixture","time":runtime.clock(),"severity":1}];configure(facts);view.sync(0)
	expect("real wound field selects only this actor injury skin",view._skin_applied.player=="injured" and view._skin_applied.friend=="normal" and view._skin_applied.other=="normal")
	var medicine:Dictionary=command("medicine")
	expect("same actual finite medicine command starts",medicine.ok,medicine)
	for i:int in 13:runtime.tick(0.1)
	view.sync(0)
	expect("actual medicine spends one item clears wounds and restores normal skin",runtime.actor("player").pack.medicine==0 and runtime.actor("player").wounds.is_empty() and view._skin_applied.player=="normal")
	var model:String=view._skin_models.player
	view._skin_textures[model+"_injured"]=null
	facts=runtime.facts();facts.actors[0].wounds=[{"cause":"second explicit fixture"}];configure(facts);view.sync(0)
	expect("missing wound variant falls back to same role normal skin",view._skin_applied.player=="normal")
	view._apply_skin_texture("player",null,"restore")
	var restored:=true
	for i:int in view._skin_bindings.player.size():
		var binding:Dictionary=view._skin_bindings.player[i]
		restored=restored and binding.mesh.get_active_material(binding.surface)==original_materials.player[i]
	expect("original instance overrides restore exactly",restored)
	facts=runtime.facts();facts.actors=facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player");configure(facts);view.sync(0)
	expect("retired actors release material binding and state references",view._skin_bindings.size()==1 and view._skin_states.size()==1 and view._skin_applied.size()==1 and view._skin_models.size()==1)
	finish(started)
func configure(facts:Dictionary)->void:
	expect("explicit fixture accepted by same runtime",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
func finish(started:int)->void:
	if is_instance_valid(view):view.free()
	print("DDD_SKIN "+JSON.stringify({"scope":"original mesh/material invariants plus isolated textures and wound fixture; actual medicine; NOT delivered new art or native VA","checks":checks,"failures":failures,"ok":failures.is_empty(),"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)
