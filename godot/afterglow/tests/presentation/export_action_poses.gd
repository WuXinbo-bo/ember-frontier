extends "res://tests/buildings/domain_suite.gd"
## Actual native clip/held-tool samples for offline visual diagnosis only.
## No rendered application, import, real save or visual-acceptance claim.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D
var output:String
var textures:Dictionary={}

func run()->void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	assert(world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":33.3,"y":0,"z":40.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at)
	var seeded:Dictionary=building.seed_rural(world)
	assert(seeded.ok)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	assert(draft.ok and world.commit_prepared(draft.capability).ok)
	initialize_at(at,[],seeded.initial_stocks)
	var facts:Dictionary=runtime.facts();facts.actors[0].pack={"timber":8,"scrap":8}
	var tools:Dictionary=Production.empty_state();tools.tools=seeded.initial_tools;tools.records=seeded.initial_records;tools.knowledge={"player":["basic_woodwork"]}
	for tool:Dictionary in tools.tools:tool.holderId="pack:player"
	draft=world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	assert(draft.ok and world.commit_prepared(draft.capability).ok)
	assert(runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	var bench:Dictionary=building.make_instance("workbench","ddd:pose-bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	var accepted:Dictionary=command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"})
	assert(accepted.ok)
	view.sync(0.1)
	assert(view._states.player=="Use" and view._props.has("player"))
	var before:Dictionary=runtime.capture_checkpoint()
	var animator:AnimationPlayer=view._animations.player
	var frames:Array=[]
	for fraction:float in [0.0,0.25,0.5,0.75]:
		animator.play("Use",0);animator.seek(animator.get_animation("Use").length*fraction,true)
		animator.advance(0)
		frames.append({"fraction":fraction,"surfaces":surfaces(view.roots.player),"hand_origin":point(view.roots.player.global_transform.affine_inverse()*view._props.player.global_position)})
	assert(Data.json_equal(before,runtime.capture_checkpoint()))
	var result:Dictionary={"scope":"native AnimationPlayer samples of real accepted finite construction fixture; software previews are NOT Godot screenshots, normal-camera VA or proof of world action reach","state":view._states.player,"tool_id":view._held_ids.player,"clip_length":animator.get_animation("Use").length,"frames":frames,"facts_unchanged":true,"textures":textures}
	var file:=FileAccess.open(output.path_join("action-poses.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	view.free()
	print(JSON.stringify({"output":output,"frames":frames.size(),"surfaces_per_frame":frames[0].surfaces.size(),"facts_unchanged":true}))
	quit()

func point(v:Vector3)->Array:
	return [v.x,v.y,v.z]

func surfaces(actor:Node3D)->Array:
	var result:Array=[]
	for mesh:MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		var transform:Transform3D=actor.global_transform.affine_inverse()*mesh.global_transform
		for surface:int in mesh.mesh.get_surface_count():
			var material:BaseMaterial3D=mesh.get_active_material(surface)
			var texture:Texture2D=material.albedo_texture
			var key:String=str(texture.get_instance_id())
			if not textures.has(key):
				var image:Image=texture.get_image().duplicate()
				if image.is_compressed():assert(image.decompress()==OK)
				if image.has_mipmaps():image.clear_mipmaps()
				var path:String=output.path_join("texture-"+key+".png")
				assert(image.save_png(path)==OK);textures[key]={"path":path,"resource":texture.resource_path}
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			var vertices:Array=[];var uvs:Array=[]
			for v:Vector3 in arrays[Mesh.ARRAY_VERTEX]:vertices.append(point(transform*v))
			for uv:Vector2 in arrays[Mesh.ARRAY_TEX_UV]:uvs.append([uv.x,uv.y])
			result.append({"mesh":str(mesh.name),"texture":key,"vertices":vertices,"uv":uvs,"indices":Array(arrays[Mesh.ARRAY_INDEX]),"albedo":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b]})
	return result
