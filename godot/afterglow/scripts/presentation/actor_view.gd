extends Node3D
## Reuses delivered GLB rigs/animations. Render interpolation owns no actor facts.
const MODEL_PATHS := ["res://data/gameplay/actors/r1_resident_commuter.glb","res://data/gameplay/actors/r1_resident_neighbor.glb","res://data/gameplay/actors/r1_resident_shopkeeper.glb"]
const APPEARANCE_IDS := ["r1_resident_commuter","r1_resident_neighbor","r1_resident_shopkeeper","infected_walker"]
const BODY_PROFILE_ID := "human-default-v1"
const Profiles=preload("res://scripts/runtime/actor_profiles.gd")
const HeldTool=preload("res://scripts/presentation/held_tool_view.gd")
const WorkPose=preload("res://scripts/presentation/factory_work_pose.gd")
const WaterPose=preload("res://scripts/presentation/factory_water_work_pose.gd")
const RegionalPose=preload("res://scripts/presentation/regional_work_pose.gd")
const RegionalWorkItem=preload("res://scripts/presentation/regional_work_item.gd")
const ModuleRestVisual=preload("res://scripts/presentation/module_rest_visual.gd")
const Cargo=preload("res://scripts/presentation/factory_cargo_view.gd")
const ResidentShape=preload("res://scripts/presentation/resident_shape.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Definitions=preload("res://scripts/runtime/content_definitions.gd")
const LOOP_STATES=["Idle","Walk","Run","Use","Carry","CarryWalk","RestLying"]
const SKIN_DIRECTORY="res://data/gameplay/actors/skins/ar18-v5/"
const LEGACY_SKIN_DIRECTORY="res://data/gameplay/actors/skins/"
# Clip calibration only, never movement authority. Carry has no separate Run.
const CLIP_WALK_SPEED:float=2.8
const CLIP_RUN_SPEED:float=4.6
const INFECTED_CLIP_WALK_SPEED:float=2.2
var runtime: RefCounted
var roots: Dictionary = {}
var previous: Dictionary = {}
var _animations: Dictionary = {}
var _states: Dictionary = {}
var _clip_events:Dictionary={}
var _moved_until:Dictionary={}
var _props:Dictionary={}
var _arms:Dictionary={}
var _carry_anchors:Dictionary={}
var _carried:Dictionary={}
var _held_ids:Dictionary={}
var _held_kinds:Dictionary={}
var _skin_models:Dictionary={}
var _skin_bindings:Dictionary={}
var _skin_states:Dictionary={}
var _skin_applied:Dictionary={}
var _skin_textures:Dictionary={}
var _skin_materials:Dictionary={}
var _player_occluded:=false
var _overlay_dirty:=true
var _silhouette:StandardMaterial3D
var _old_overlays:Dictionary={}
var _model_paths:Dictionary={}
var _binding_keys:Dictionary={}
var _legacy_models:Dictionary={}
var _required_errors:Dictionary={}
var _prop_errors:Dictionary={}
var _optional_fallbacks:Dictionary={}
var _bound_world:int=0
var _work_frames:Dictionary={}
var _manual_work:Dictionary={}
var _work_postures:Dictionary={}
var _work_pose_keys:Dictionary={}
var _work_pose_results:Dictionary={}
var _work_items:Dictionary={}
var _module_rest:RefCounted=ModuleRestVisual.new()

func configure(authority: RefCounted) -> void:
	var world_id:int=authority.world.get_instance_id() if authority!=null and authority.world!=null else 0
	if runtime!=authority or _bound_world!=world_id:
		for id:String in roots.keys():_retire_actor(id)
		_legacy_models.clear();_skin_textures.clear();_skin_materials.clear()
		_required_errors.clear();_optional_fallbacks.clear();_old_overlays.clear()
		_player_occluded=false;_overlay_dirty=true
	runtime=authority
	_bound_world=world_id
	sync(0)

func _process(delta: float) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("presentation/actor_view.gd",measured)

func _profiled_process(delta: float) -> void:
	sync(delta)

func _spawn(a: Dictionary,index: int) -> Node3D:
	var root:=Node3D.new()
	root.name=str(a.id).validate_node_name()
	root.set_meta("actor_id",a.id)
	var path:String=_model_path(a,index)
	var errors:Array=[]
	var shape_report:Dictionary={"ok":true,"policy":"original"}
	var profile:String=_appearance_id(a,index)
	var body_profile:String=_body_profile_id(a)
	var body_spec:Dictionary=_body_definition(body_profile)
	if profile not in APPEARANCE_IDS+Profiles.NEW_HUMAN:errors.append(_assembly_issue(str(a.id),profile,path,"appearance_id","PROFILE_UNKNOWN"))
	if body_spec.is_empty():errors.append(_assembly_issue(str(a.id),profile,body_profile,"body_profile_id","BODY_PROFILE_UNKNOWN"))
	elif not _valid_body_definition(body_spec,body_profile):errors.append(_assembly_issue(str(a.id),profile,body_profile,"body_profile_id","BODY_DEFINITION_INVALID"))
	var resource:Variant=load(path) if errors.is_empty() and ResourceLoader.exists(path,"PackedScene") else null
	if errors.is_empty() and resource is PackedScene:
		var model:Node3D=resource.instantiate()
		errors=_inspect_model(model,profile,str(a.id),profile=="infected_walker")
		if errors.is_empty() and path in MODEL_PATHS:
			shape_report=ResidentShape.apply(model,Profiles.model_profile(profile))
			if not shape_report.ok:errors.append(_assembly_issue(str(a.id),profile,path,"resident_shape","SHAPE_SOURCE_MISMATCH"))
		if errors.is_empty():
			if profile in Profiles.NEW_HUMAN:_young_silhouette(model,profile)
			root.add_child(model)
			if path in MODEL_PATHS:
				_skin_models[a.id]=profile
				_skin_bindings[a.id]=_collect_skin_bindings(model)
			_arms[a.id]=model.find_child("arm_r",true,false)
			_carry_anchors[a.id]=model.find_child("anchor_carry",true,false)
			var player:AnimationPlayer=_find_animation(model)
			_bind_loops(player)
			_animations[a.id]=player
		else:model.free()
	elif errors.is_empty():errors.append(_assembly_issue(str(a.id),profile,path,"model","MODEL_MISSING"))
	_required_errors[a.id]=errors
	root.set_meta("assembly_ok",errors.is_empty());root.set_meta("model_resource",path)
	root.set_meta("profile_id",profile);root.set_meta("body_profile_id",body_profile)
	root.set_meta("resident_shape",shape_report)
	_model_paths[a.id]=path
	_binding_keys[a.id]=_binding_key(a,index)
	# This is selection geometry, never a substitute for B's body authority.
	# Failed assets must not leave an invisible selectable capsule behind.
	if errors.is_empty():
		var body:=StaticBody3D.new();body.set_meta("actor_id",a.id);body.collision_layer=2
		var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new()
		capsule.radius=float(body_spec.radius);capsule.height=float(body_spec.height);shape.shape=capsule;shape.position.y=float(body_spec.height)*0.5
		body.add_child(shape);root.add_child(body)
	add_child(root)
	root.position=Vector3(a.x,a.y,a.z)
	if float(a.hp)<=0 and profile=="infected_walker":root.rotation.z=PI*0.5
	roots[a.id]=root
	if a.id=="player":_overlay_dirty=true
	return root

func _appearance_id(a:Dictionary,index:int)->String:
	var explicit:Variant=a.get("appearance_id")
	if explicit!=null and not str(explicit).is_empty():return str(explicit)
	# Transitional read-only compatibility. A persists the original actor-array
	# mapping on load; this cache only protects an un-migrated mounted view.
	if not _legacy_models.has(a.id):_legacy_models[a.id]=MODEL_PATHS[index%MODEL_PATHS.size()]
	return "infected_walker" if a.get("faction")=="infected" else str(_legacy_models[a.id]).get_file().get_basename()

func _body_profile_id(a:Dictionary)->String:
	var value:Variant=a.get("body_profile_id")
	return BODY_PROFILE_ID if value==null or str(value).is_empty() else str(value)

func _body_definition(id:String)->Dictionary:
	return Definitions.body_definition(id)

static func _valid_body_definition(body:Dictionary,id:String)->bool:
	var radius:Variant=body.get("radius");var height:Variant=body.get("height")
	if body.get("id")!=id or not (radius is int or radius is float) or not (height is int or height is float):return false
	return is_finite(float(radius)) and is_finite(float(height)) and float(radius)>0 and float(height)>=2.0*float(radius)

func _binding_key(a:Dictionary,index:int)->Array:
	return [_appearance_id(a,index),_body_profile_id(a)]

func _model_path(a:Dictionary,index:int)->String:
	var profile:String=_appearance_id(a,index)
	return "res://data/gameplay/actors/"+Profiles.model_profile(profile)+".glb" if profile in APPEARANCE_IDS+Profiles.NEW_HUMAN else ""

func _young_silhouette(model:Node3D,profile:String)->void:
	# A detached mesh derivation keeps rig/socket transforms and physical body
	# authority intact. Neither profile reuses the elderly neighbour mesh.
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:MeshInstance3D=node
		if mesh.mesh==null:continue
		var derived:=ArrayMesh.new()
		for surface:int in mesh.mesh.get_surface_count():
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			for i:int in vertices.size():
				if str(mesh.name)=="root":vertices[i].x*=.94 if profile=="village_linxia_v14" else 1.07
				if str(mesh.name)=="head":vertices[i].x*=.95 if profile=="village_linxia_v14" else 1.02
			arrays[Mesh.ARRAY_VERTEX]=vertices
			derived.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			derived.surface_set_material(surface,mesh.mesh.surface_get_material(surface))
		mesh.mesh=derived
	model.set_meta("opening_character_geometry",profile)

func _assembly_issue(id:String,profile:String,resource:String,requirement:String,code:String)->Dictionary:
	return {"actor_id":id,"profile_id":profile,"resource":resource,"requirement":requirement,"code":code}

func _inspect_model(model:Node3D,profile:String,id:String,infected:bool)->Array:
	var errors:Array=[]
	var resource:String="res://data/gameplay/actors/"+profile+".glb"
	var player:AnimationPlayer=_find_animation(model)
	var required:Array=["Idle","Walk","Run","Attack","Hit"] if infected else ["Idle","Walk","Run","Use","Carry","CarryWalk","RestLying","Hit"]
	for clip:String in required:
		if player==null or not Array(player.get_animation_list()).any(func(name:String)->bool:return name==clip or name.ends_with("/"+clip)):
			errors.append(_assembly_issue(id,profile,resource,"clip:"+clip,"CLIP_MISSING"))
	for socket:String in (["arm_r"] if infected else ["arm_r","anchor_carry"]):
		if not model.find_child(socket,true,false) is Node3D:errors.append(_assembly_issue(id,profile,resource,"socket:"+socket,"SOCKET_MISSING"))
	var bindings:Array=_collect_skin_bindings(model)
	if bindings.is_empty():errors.append(_assembly_issue(id,profile,resource,"material:body","MATERIAL_MISSING"))
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:errors.append(_assembly_issue(id,profile,resource,"mesh:"+str(mesh.name),"MESH_MISSING"));continue
		for surface:int in mesh.mesh.get_surface_count():
			if not mesh.get_active_material(surface) is BaseMaterial3D:errors.append(_assembly_issue(id,profile,resource,"material:"+str(mesh.name)+":"+str(surface),"MATERIAL_MISSING"))
	if not infected:
		var normal_path:String=SKIN_DIRECTORY+profile+"_normal.png"
		var texture:Texture2D=_skin_texture(profile,"normal")
		var image:Image=texture.get_image() if texture!=null else null
		if image!=null and image.is_compressed():image.decompress()
		if not _valid_skin_image(image):errors.append(_assembly_issue(id,profile,normal_path,"skin:normal","SKIN_MISSING_OR_INVALID"))
	return errors

func assembly_report()->Dictionary:
	var required:Array=[];var optional:Array=[];var actors:Array=[]
	for issues:Array in _required_errors.values():required.append_array(issues)
	for issues:Dictionary in _prop_errors.values():required.append_array(issues.values())
	for issues:Array in _optional_fallbacks.values():optional.append_array(issues)
	var ids:Array=roots.keys();ids.sort()
	for id:String in ids:
		var node:Node3D=roots[id]
		actors.append({"actor_id":id,"profile_id":node.get_meta("profile_id",""),"resource":_model_paths.get(id,""),"ok":_required_errors.get(id,[]).is_empty() and _prop_errors.get(id,{}).is_empty()})
	return {"ok":runtime!=null and required.is_empty(),"required_errors":required.duplicate(true),"optional_fallbacks":optional.duplicate(true),"actors":actors}

func _record_fallback(id:String,requirement:String,resource:String,fallback:String)->void:
	if not _optional_fallbacks.has(id):_optional_fallbacks[id]=[]
	for entry:Dictionary in _optional_fallbacks[id]:
		if entry.requirement==requirement:return
	var issue:Dictionary=_assembly_issue(id,str(_model_paths.get(id,"")).get_file().get_basename(),resource,requirement,"OPTIONAL_FALLBACK")
	issue.fallback=fallback;_optional_fallbacks[id].append(issue)

func _retire_actor(id:String)->void:
	_module_rest.retire(id)
	if roots.has(id):
		var node:Node3D=roots[id];_forget_overlays(node)
		remove_child(node);node.queue_free();roots.erase(id)
	for cache:Dictionary in [previous,_animations,_states,_clip_events,_props,_arms,_carry_anchors,_carried,_held_ids,_held_kinds,_moved_until,_skin_models,_skin_bindings,_skin_states,_skin_applied,_model_paths,_binding_keys,_required_errors,_prop_errors,_optional_fallbacks,_work_frames,_manual_work,_work_postures,_work_pose_keys,_work_pose_results,_work_items]:cache.erase(id)
	var live_bases:Dictionary={}
	for bindings:Array in _skin_bindings.values():
		for binding:Dictionary in bindings:live_bases[str(binding.base.get_instance_id())]=true
	for key:String in _skin_materials.keys():
		if not live_bases.has(key.get_slice(":",1)):_skin_materials.erase(key)
	if id=="player":_overlay_dirty=true

func _find_animation(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:return node
	for child in node.get_children():
		var found:=_find_animation(child)
		if found!=null:return found
	return null

func _bind_loops(player:AnimationPlayer)->void:
	# GLB clips arrive as one-shots. Derive runtime libraries; never mutate the
	# delivered/imported resources, and retain transient Hit/Attack semantics.
	for id:String in player.get_animation_library_list():
		var source:AnimationLibrary=player.get_animation_library(id)
		var library:=AnimationLibrary.new()
		for name:String in source.get_animation_list():
			var clip:Animation=source.get_animation(name)
			if name.get_file() in LOOP_STATES:
				clip=clip.duplicate();clip.loop_mode=Animation.LOOP_LINEAR
			library.add_animation(name,clip)
		player.remove_animation_library(id);player.add_animation_library(id,library)

func _collect_skin_bindings(model:Node3D)->Array:
	var bindings:Array=[]
	var meshes:Array=model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:meshes.push_front(model)
	for mesh:MeshInstance3D in meshes:
		if mesh.mesh==null:continue
		for surface:int in mesh.mesh.get_surface_count():
			var base:Material=mesh.get_active_material(surface)
			if base is BaseMaterial3D and not base.get_meta("resident_clear_lens",false):
				bindings.append({"mesh":mesh,"surface":surface,"base":base,"original_override":mesh.get_surface_override_material(surface)})
	return bindings

static func _valid_skin_image(image:Image)->bool:
	return image!=null and image.get_width()==512 and image.get_height()==512 and image.detect_alpha()==Image.ALPHA_NONE

func _skin_texture(model:String,state:String)->Texture2D:
	var key:String=model+"_"+state
	if _skin_textures.has(key):return _skin_textures[key]
	var texture:Texture2D
	for directory:String in [SKIN_DIRECTORY,LEGACY_SKIN_DIRECTORY]:
		var path:String=directory+key+".png"
		var image:Image
		var mode:String="imported"
		if ResourceLoader.exists(path,"Texture2D"):
			var source:Texture2D=load(path)
			if source!=null:image=source.get_image()
		elif FileAccess.file_exists(path):
			# Before A's sole import, bind exact delivered pixels in source builds.
			# Exported builds use the imported resource above, never a guessed atlas.
			image=Image.load_from_file(path);mode="source-png"
		else:continue
		if image!=null and image.is_compressed():image.decompress()
		if _valid_skin_image(image):
			if image.has_mipmaps() or image.generate_mipmaps()==OK:
				texture=ImageTexture.create_from_image(image)
				texture.set_meta("source_resource",path)
				texture.set_meta("source_mode",mode)
				break
		else:push_warning("Resident skin rejected: expected opaque 512x512 original-UV PNG: "+path)
	# Missing/invalid assets are checked once per mounted view, never each frame.
	_skin_textures[key]=texture
	return texture

func _update_skin(a:Dictionary)->void:
	if not _skin_models.has(a.id):return
	var wounds:Variant=a.get("wounds",[])
	var wanted:String="injured" if wounds is Array and not wounds.is_empty() else "normal"
	if _skin_states.get(a.id)==wanted:return
	var model:String=_skin_models[a.id]
	var texture:Texture2D=_skin_texture(model,wanted)
	var applied:String=wanted
	if texture==null and wanted!="normal":
		texture=_skin_texture(model,"normal");applied="normal"
		_record_fallback(str(a.id),"skin:"+wanted,SKIN_DIRECTORY+model+"_"+wanted+".png","same-role normal skin")
	_apply_skin_texture(str(a.id),texture,model+"_"+applied)
	if texture!=null and not str(texture.get_meta("source_resource","")).begins_with(SKIN_DIRECTORY):
		_record_fallback(str(a.id),"skin:"+applied,SKIN_DIRECTORY+model+"_"+applied+".png","legacy same-role skin")
	_skin_states[a.id]=wanted
	_skin_applied[a.id]=applied if texture!=null else "original"

func _apply_skin_texture(id:String,texture:Texture2D,key:String)->void:
	for binding:Dictionary in _skin_bindings.get(id,[]):
		var mesh:MeshInstance3D=binding.mesh
		if not is_instance_valid(mesh):continue
		if texture==null:
			mesh.set_surface_override_material(binding.surface,binding.original_override)
			continue
		var material_key:String=key+":"+str(binding.base.get_instance_id())
		if not _skin_materials.has(material_key):
			var material:BaseMaterial3D=binding.base.duplicate()
			material.albedo_texture=texture;material.albedo_color=Color.WHITE
			material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			_skin_materials[material_key]=material
		mesh.set_surface_override_material(binding.surface,_skin_materials[material_key])

func sync(delta: float) -> void:
	if runtime==null:return
	if runtime.world.get_instance_id()!=_bound_world:
		configure(runtime);return
	var visible:Dictionary={}
	var projection:Dictionary=runtime.actor_presentation()
	var paused:bool=runtime.has_method("is_paused") and runtime.is_paused()
	var actors:Array=projection.actors
	for index in actors.size():
		var a:Dictionary=actors[index]
		visible[a.id]=true
		var root:Node3D=roots.get(a.id)
		if root!=null and _binding_keys.get(a.id)!=_binding_key(a,index):_retire_actor(str(a.id));root=null
		if root==null:root=_spawn(a,index)
		# Faction controls authority budgets, never which delivered rig/clip was
		# bound from the saved appearance. These can legally differ after load.
		var infected_rig:bool=str(_model_paths.get(a.id,"")).ends_with("/infected_walker.glb")
		_update_skin(a)
		root.visible=root.get_meta("assembly_ok",false) and a.id in projection.get("visible_actor_ids",[a.id])
		var destination:=Vector3(a.x,a.y,a.z)
		var from:Vector3=previous.get(a.id,destination)
		var travel:=destination-from
		var motion:Dictionary=projection.get("movement",{}).get(a.id,{})
		var walking:bool=bool(motion.get("moving",false)) and float(motion.get("speed",0))>0.000001
		if motion.is_empty() or a.get("expedition_follow",false) or a.get("expedition_enemy",false):
			# Legacy projection compatibility only. New movement never infers a
			# run, a pause or an accepted wall sweep from input/position deltas.
			walking=Vector2(travel.x,travel.z).length_squared()>0.000001
			if walking:_moved_until[a.id]=Time.get_ticks_msec()+180
			walking=walking or Time.get_ticks_msec()<int(_moved_until.get(a.id,0))
		if not paused:
			if delta<=0 or root.position.distance_to(destination)>3:root.position=destination
			else:root.position=root.position.lerp(destination,minf(1,delta*18))
			if Vector2(travel.x,travel.z).length_squared()>0.000001:root.rotation.y=lerp_angle(root.rotation.y,atan2(travel.x,travel.z),minf(1,delta*18) if delta>0 else 1.0)
		var intent:Variant=a.get("intent")
		var work:Dictionary=_work_frame(a,projection.get("work",{}).get(a.id,{}))
		_work_frames[a.id]=work
		# A STEP can finish the last route segment and do effective labor with
		# its remainder. Historical movement in that STEP must not keep walking
		# over the owner's already-completed path and actual work at its end.
		if work.active and intent is Dictionary and intent.get("owner")=="zonework" and intent.get("steps") is Array and (intent.get("step") is int or intent.get("step") is float) and float(intent.step)==float(intent.steps.size()):walking=false
		var state:String=("Run" if motion.get("mode")=="run" else "Walk") if walking else "Idle"
		# Loot in an infected actor's inventory is not a hauling instruction.
		# The infected rig retains its actual locomotion/attack clips and has
		# no resident carry socket. Never request a human carry clip on load.
		var carrying:bool=not infected_rig and is_carrying(a)
		if carrying:state="CarryWalk" if walking else "Carry"
		if intent is Dictionary and intent.get("held",true):
			if intent.get("kind") in ["rest","sleep"]:state="RestLying"
			elif intent.get("kind") in ["eat","drink","medicine"]:state="Use"
			elif intent.get("kind")=="water":
				if not walking and work.available and work.active:state="Use"
			elif intent.get("owner")=="zonework" and intent.get("kind")=="zonework":
				if not walking and work.available and work.active:state="Use"
			elif intent.get("kind") in ["structure","construction","craft","harvest","terrain","door","care","study","search","radio"]:
				if not walking or (work.available and work.active):state="Use"
		if float(a.get("attack_until",0))>runtime.clock():state="Attack" if infected_rig else "Use"
		if state=="Use" and work.available and not work.active and not paused and float(a.get("attack_until",0)) <= runtime.clock():
			state="Carry" if carrying else "Idle"
		if float(a.get("hit_until",0))>runtime.clock():state="Hit"
		if float(a.hp)<=0:
			state="RestLying"
			if infected_rig and not paused:root.rotation.z=PI*0.5 if delta<=0 else lerpf(root.rotation.z,PI*0.5,minf(1,delta*8))
		else:root.rotation.z=0.0
		if not paused and float(a.get("attack_until",0)) > runtime.clock() and a.get("combat_aim") is Dictionary:
			var aim: Dictionary = a.combat_aim
			root.rotation.y = atan2(float(aim.x),float(aim.z))
		elif state=="Use" and not walking and not paused:_face_action(root,a,delta,work)
		root.scale=Vector3.ONE*(1.0+0.04*sin(runtime.clock()*40.0)) if state=="Hit" else Vector3.ONE
		_update_props(a,projection.hand,carrying and float(a.hp)>0,state)
		var rate:float=1.0
		if walking and state in ["Walk","Run","CarryWalk"] and not motion.is_empty():
			var reference:float=CLIP_RUN_SPEED if state=="Run" else INFECTED_CLIP_WALK_SPEED if infected_rig else CLIP_WALK_SPEED
			rate=maxf(0.01,float(motion.speed)/reference)
		var event:float=float(a.get("hit_until",0)) if state=="Hit" else float(a.get("attack_until",0)) if state=="Attack" or (state=="Use" and float(a.get("attack_until",0))>runtime.clock()) else 0.0
		_play(str(a.id),state,0.0 if paused else rate,event)
		_sync_work_pose(str(a.id),state,work,paused)
		_sync_work_item(a,state,work,paused)
		_module_rest.sync(a,root,state,runtime,paused,_animations.get(a.id))
		previous[a.id]=destination
	for id in roots.keys():
		if not visible.has(id):
			_retire_actor(str(id));_legacy_models.erase(id)

func _sync_work_item(actor:Dictionary,state:String,work:Dictionary,paused:bool)->void:
	var id:String=str(actor.id)
	var existing:Node3D=_work_items.get(id)
	# Pause preserves an already active physical attachment. A cancelled intent
	# or removed real pack item still retires it, even while paused.
	var observed:Dictionary=work.duplicate()
	if paused and is_instance_valid(existing) and work.get("available",false):observed.active=true
	var retained:bool=paused and is_instance_valid(existing) and work.get("available",false) and float(actor.get("hp",0))>0
	var item:String=RegionalWorkItem.item_for(actor,observed) if (state=="Use" or retained) and not _props.has(id) else ""
	if is_instance_valid(existing) and existing.get_meta("item_id")!=item:
		_forget_overlays(existing);existing.get_parent().remove_child(existing);existing.queue_free();_work_items.erase(id);existing=null
		if id=="player":_overlay_dirty=true
	if item.is_empty() or not is_instance_valid(_arms.get(id)):return
	if not is_instance_valid(existing):
		existing=RegionalWorkItem.create(item);_arms[id].add_child(existing);_work_items[id]=existing
		if id=="player":_overlay_dirty=true
	if paused:return
	existing.position=Vector3(0,-.51,.06)
	# Gravity keeps the empty bucket upright while its handle follows the
	# actual animated palm. This does not move the hand or actor authority.
	existing.global_basis=Basis.IDENTITY
	existing.set_meta("actual_pack_quantity",actor.pack[item])

static func _work_frame(actor:Dictionary,value:Variant)->Dictionary:
	var intent:Variant=actor.get("intent")
	var fallback:Dictionary={"available":false,"active":false,"scope":"ordinary clip fallback; no effective contact progress"}
	if not intent is Dictionary or not value is Dictionary or value.is_empty():return fallback
	if value.get("owner")!=intent.get("owner") or value.get("kind")!=intent.get("kind") or not value.get("effective_work") is bool:return fallback
	for key:String in ["progress_seconds","duration_seconds"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])):return fallback
	if float(value.duration_seconds)<=0 or float(value.progress_seconds)<0 or float(value.progress_seconds)>float(value.duration_seconds)+0.000001:return fallback
	var result:Dictionary=value.duplicate(true)
	result.available=true
	result.active=bool(value.effective_work) and str(value.get("paused_reason","")).is_empty() and bool(intent.get("held",true))
	result.scope="owner effective progress; animation only, no hit or work settlement"
	return result

func _sync_work_pose(id:String,state:String,work:Dictionary,paused:bool)->void:
	if not _animations.has(id):return
	var player:AnimationPlayer=_animations[id]
	var prop:Node3D=_props.get(id)
	var pose_key:String=""
	var contact_pose:bool=(prop!=null and prop.get_meta("tool_kind","") in WorkPose.KINDS) or (prop==null and work.get("operation") in RegionalPose.OPERATIONS)
	if state=="Use" and work.get("available",false) and work.get("active",false) and not paused and contact_pose:
		pose_key=var_to_str([roots[id].global_transform,prop.get_instance_id() if prop!=null else 0,player.current_animation,work.get("owner"),work.get("kind"),work.get("operation"),work.get("progress_seconds"),work.get("duration_seconds"),work.get("contact")])
		if _work_pose_keys.get(id)==pose_key and _work_postures.has(id):
			work.merge(_work_pose_results[id].duplicate(true),true)
			player.speed_scale=1.0
			return
	if not paused and _work_postures.has(id):
		WorkPose.restore(_work_postures[id]);_work_postures.erase(id)
	if not paused:_work_pose_keys.erase(id);_work_pose_results.erase(id)
	if prop!=null and not paused:prop.rotation=Vector3(PI/2,0,0)
	if state!="Use" or not work.available:
		if _manual_work.erase(id):player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		return
	if paused and _manual_work.has(id):
		player.speed_scale=0.0
		return
	# Exactly the accepted owner's effective seconds. Frame dt, open panels and
	# wall time cannot keep a blocked saw or axe swinging.
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_manual_work[id]=true
	var clip:String=player.current_animation
	if clip.is_empty() or not player.has_animation(clip):return
	var length:float=player.get_animation(clip).length
	if length<=0:return
	player.play(clip,0.0)
	player.seek(fposmod(float(work.progress_seconds),length),true)
	player.speed_scale=0.0 if paused else 1.0
	if prop!=null and work.active and not paused:
		var posture:Dictionary=WorkPose.apply(_arms[id],prop,work,length,roots[id].global_position.y)
		if not posture.is_empty():_work_postures[id]=posture
		_aim_work_arm(id,prop,work,length)
		_aim_work_tool(prop,work)
	elif prop==null and work.active and not paused and work.get("operation") in RegionalPose.OPERATIONS and is_instance_valid(_arms.get(id)):
		var posture:Dictionary=RegionalPose.apply(_arms[id],work,length)
		if not posture.is_empty():_work_postures[id]=posture
	elif prop==null and work.active and not paused and work.get("kind")=="water" and work.get("operation")=="draw" and is_instance_valid(_arms.get(id)):
		# Turn the delivered rigid arm toward the owner's actual tap. The hand
		# stays at its original palm anchor; no bucket or inventory is invented.
		var contact:Variant=work.get("contact")
		var point:Variant=_contact_vector(contact.get("position")) if contact is Dictionary else null
		if point!=null:
			var arm:Node3D=_arms[id];var palm:=Vector3(0,-.51,.06)
			var posture:Dictionary=WaterPose.apply(arm,point)
			if not posture.is_empty():
				_work_postures[id]=posture;work.posture=posture.water_posture
			# Empty-hand valve operation differs from the original high tool
			# swing. Its own bounded shoulder arc retains the rigid palm radius.
			var reference:Basis=arm.basis
			_bounded_contact_rotation(arm,arm.to_global(palm),point,reference,110.0)
			work.hand_contact={"palm_world":arm.to_global(palm),"surface_world":point,"gap_meters":arm.to_global(palm).distance_to(point),"shoulder_degrees":rad_to_deg(reference.get_rotation_quaternion().angle_to(arm.basis.get_rotation_quaternion())),"shoulder_limit_degrees":110.0,"scope":"original rigid arm diagnostic; no reach or work permission"}
	if not pose_key.is_empty() and _work_postures.has(id):
		_work_pose_keys[id]=pose_key
		var result:Dictionary={}
		for key:String in ["posture","arm_contact","contact_wrist_degrees","contact_result","hand_contact"]:
			if work.has(key):result[key]=work[key]
		_work_pose_results[id]=result.duplicate(true)

static func _contact_vector(value:Variant)->Variant:
	if not value is Array or value.size()!=3:return null
	for n:Variant in value:
		if not (n is float or n is int) or not is_finite(float(n)):return null
	return Vector3(value[0],value[1],value[2])

func _aim_work_arm(id:String,prop:Node3D,work:Dictionary,clip_length:float)->void:
	var contact:Variant=work.get("contact")
	if not contact is Dictionary or not is_instance_valid(_arms.get(id)):return
	var point:Variant=_contact_vector(contact.get("position"));var normal:Variant=_contact_vector(contact.get("normal"))
	if point==null or normal==null or normal.length_squared()<0.000001:return
	var arm:Node3D=_arms[id]
	var frame:Dictionary=HeldTool.contact_frame(prop)
	if frame.is_empty():return
	# Keep the delivered shoulder pivot and rigid limb length. The real owner
	# progress drives retraction, so blocked/paused work cannot continue a swing.
	var phase:float=fposmod(float(work.progress_seconds),clip_length)/clip_length
	var retract:float=(1.0+cos(phase*TAU))*0.09
	var goal:Vector3=Vector3(point)+Vector3(normal).normalized()*retract
	var arm_reference:Basis=arm.basis;var tool_reference:Basis=prop.basis
	var limb:float=arm.global_position.distance_to(prop.global_position)
	var tool_length:float=Vector3(frame.grip_world).distance_to(frame.point_world)
	# Solve both rigid joints together. A one-pass shoulder aim followed by a
	# wrist turn moves the tip away again. Bounds stay relative to the original
	# effective-progress pose, not each iteration (which would accumulate reach).
	if prop.get_meta("tool_kind","") in WorkPose.KINDS:
		WorkPose.solve(arm,prop,point,Vector3(normal).normalized(),goal,arm_reference,tool_reference)
	else:
		for step:int in 6:
			frame=HeldTool.contact_frame(prop)
			_bounded_contact_rotation(prop,Vector3(frame.point_world),goal,tool_reference,35.0)
			frame=HeldTool.contact_frame(prop)
			_bounded_contact_rotation(arm,Vector3(frame.point_world),goal,arm_reference,65.0)
	var angle:float=arm_reference.get_rotation_quaternion().angle_to(arm.basis.get_rotation_quaternion())
	work.arm_contact={"shoulder_world":arm.global_position,"shoulder_degrees":rad_to_deg(angle),"retraction_meters":retract,"limb_length_preserved":true,"shoulder_to_surface_m":arm.global_position.distance_to(point),"rigid_limb_m":limb,"tool_grip_to_tip_m":tool_length,"radial_reach_limit_m":limb+tool_length,"radial_shortfall_m":maxf(0,arm.global_position.distance_to(point)-limb-tool_length),"pose_goal_world":goal}
	if _work_postures.has(id):
		work.arm_contact.reference_pose="tool-authored shoulder amplitude and rigid hip hinge"
		work.arm_contact.clip_shoulder_degrees=rad_to_deg(_work_postures[id].arm_basis.get_rotation_quaternion().angle_to(arm.basis.get_rotation_quaternion()))
	work.contact_wrist_degrees=rad_to_deg(tool_reference.get_rotation_quaternion().angle_to(prop.basis.get_rotation_quaternion()))

static func _bounded_contact_rotation(node:Node3D,tip:Vector3,goal:Vector3,reference:Basis,limit_degrees:float)->void:
	WorkPose.rotate_joint(node,tip,goal,reference,limit_degrees)

func _aim_work_tool(prop:Node3D,work:Dictionary)->void:
	var contact:Variant=work.get("contact")
	if not contact is Dictionary:return
	var point:Variant=_contact_vector(contact.get("position"))
	var normal:Variant=_contact_vector(contact.get("normal"))
	if point==null or normal==null or normal.length_squared()<0.000001:return
	var frame:Dictionary=HeldTool.contact_frame(prop)
	if frame.is_empty():return
	var gap:float=Vector3(frame.point_world).distance_to(point)
	work.contact_result={"tip_world":frame.point_world,"surface_world":point,"gap_meters":gap,"signed_plane_gap":(Vector3(frame.point_world)-Vector3(point)).dot(Vector3(normal).normalized()),"normal_alignment":Vector3(frame.normal_world).dot(Vector3(normal).normalized()),"wrist_degrees":work.get("contact_wrist_degrees",0.0),"visual_contact":gap<=0.04,"scope":"geometry diagnostic only; no hit/work settlement or actor movement"}

func _face_action(root:Node3D,a:Dictionary,delta:float,work:Dictionary={})->void:
	var intent:Variant=a.get("intent")
	if not intent is Dictionary or not intent.get("held",true):return
	# Face the accepted owner's actual working surface, not the centre of an
	# entire table/tree/building. This changes visual yaw only, never body facts.
	var contact:Variant=work.get("contact")
	if work.get("active",false) and contact is Dictionary:
		var point:Variant=_contact_vector(contact.get("position"))
		if point!=null:
			var toward:Vector2=Vector2(point.x-root.position.x,point.z-root.position.z)
			if toward.length_squared()>0.0001:
				root.rotation.y=lerp_angle(root.rotation.y,atan2(toward.x,toward.y),minf(1.0,delta*18.0) if delta>0 else 1.0)
				return
	var request:Dictionary=intent.get("request",{})
	var payload:Dictionary=request.get("payload",{})
	var target:Dictionary={}
	for id:String in [str(intent.get("target_id","")),str(request.get("target_id","")),str(payload.get("station_id",""))]:
		if id.is_empty():continue
		target=runtime.world.entity(id)
		if target.is_empty():target=runtime.actor(id)
		if not target.is_empty():break
	# Placement has a real accepted planned instance before its entity exists.
	if target.is_empty() and payload.get("instance") is Dictionary:target=payload.instance
	var at:Dictionary={}
	if not target.is_empty():at=Geometry.location(target)
	elif intent.get("kind")=="terrain":
		var edit:Dictionary=payload.get("edit",payload)
		var cells:Array=edit.get("cells",[])
		if not cells.is_empty() and cells[0] is Dictionary:
			var size:float=float(runtime.world.config().cellSize)
			at={"x":(float(cells[0].x)+0.5)*size,"y":(float(cells[0].y)+0.5)*size,"z":(float(cells[0].z)+0.5)*size,"regionId":a.regionId}
	if at.is_empty():return
	if at.get("regionId")!=a.regionId:
		# This is the existing accepted action's target, never a new target or
		# a visibility grant. Cross-partition facing still needs known/resident
		# outdoor coverage; action execution/range/LOS remain with B and A.
		if not runtime.world.has_method("continuous_outdoor_segment") or not runtime.world.continuous_outdoor_segment(Geometry.location(a),at,256.0,true).ok:return
	var direction:=Vector2(float(at.x)-root.position.x,float(at.z)-root.position.z)
	if direction.length_squared()>0.0001:root.rotation.y=lerp_angle(root.rotation.y,atan2(direction.x,direction.y),minf(1.0,delta*18.0) if delta>0 else 1.0)

static func is_carrying(a:Dictionary)->bool:
	return not Cargo.hand_items(a).is_empty()

func _update_props(a:Dictionary,hand:Dictionary,carrying:bool,state:String)->void:
	if not _prop_errors.has(a.id):_prop_errors[a.id]={}
	var issues:Dictionary=_prop_errors[a.id]
	if not carrying:issues.erase("carry")
	var items:Dictionary=Cargo.hand_items(a)
	var item:String=Cargo.representative(items)
	var old_cargo:Node3D=_carried.get(a.id)
	if carrying and is_instance_valid(old_cargo) and old_cargo.get_meta("item_id","")!=item:
		_forget_overlays(old_cargo);old_cargo.get_parent().remove_child(old_cargo);old_cargo.queue_free();_carried.erase(a.id)
		issues.erase("carry")
	if carrying and not item.is_empty() and not _carried.has(a.id) and is_instance_valid(_carry_anchors.get(a.id)):
		var bundle:Node3D=Cargo.create(item)
		if bundle!=null:
			_carry_anchors[a.id].add_child(bundle)
			bundle.position=Vector3(0,-0.17,-0.05);_carried[a.id]=bundle
			issues.erase("carry")
			if bundle.has_meta("fallback_resource"):_record_fallback(str(a.id),"prop:carry:"+item,str(bundle.get_meta("fallback_resource")),"existing sack for actual pack contents")
			if a.id=="player":_overlay_dirty=true
		else:issues.carry=_assembly_issue(str(a.id),str(roots[a.id].get_meta("profile_id","")),item,"prop:carry","MODEL_MISSING")
	if is_instance_valid(_carried.get(a.id)):
		_carried[a.id].visible=carrying and state in ["Carry","CarryWalk"]
		_carried[a.id].set_meta("actual_items",items.duplicate(true))
	var id:=""
	var intent:Variant=a.get("intent")
	if intent is Dictionary:
		id=str(intent.get("tool_id",intent.get("request",{}).get("payload",{}).get("tool_id","")))
		if id.is_empty() and not intent.get("request",{}).get("payload",{}).get("tool_ids",[]).is_empty():id=str(intent.request.payload.tool_ids[0])
	var water_work:bool=intent is Dictionary and intent.get("owner")=="modules" and intent.get("kind")=="water"
	var regional_frame:Dictionary=_work_frames.get(str(a.id),{})
	var regional_work:bool=(intent is Dictionary and intent.get("owner")=="zonework" and intent.get("kind")=="zonework") or (regional_frame.get("available",false) and regional_frame.get("operation")=="cook")
	if regional_work:
		var work:Dictionary=_work_frames.get(str(a.id),{})
		id=str(work.get("tool_id","")) if work.get("available",false) else ""
	if water_work:
		var work:Dictionary=_work_frames.get(str(a.id),{})
		id=str(work.get("tool_id","")) if work.get("available",false) and work.get("operation")=="repair" else ""
	if a.id=="player" and id.is_empty() and not water_work and not regional_work:
		var slots:Array=hand.get("slots",[])
		var index:int=int(hand.get("selected",0))
		if index>=0 and index<slots.size() and slots[index].get("kind")=="tool":id=str(slots[index].get("id",""))
	var tool:Dictionary=runtime.tool(id) if not id.is_empty() else {}
	if (carrying and state in ["Carry","CarryWalk"]) or state=="RestLying" or float(a.hp)<=0 or tool.get("holderId")!="pack:"+str(a.id) or float(tool.get("durability",0))<=0:id=""
	var kind:String=str(tool.get("kind","")) if not id.is_empty() else ""
	if float(a.get("attack_until",0)) > runtime.clock() and a.get("combat_kind") in ["club","bow"]:
		kind = a.combat_kind
		id = "weapon:" + kind
	if _held_ids.get(a.id,"")==id and _held_kinds.get(a.id,"")==kind:return
	issues.erase("held")
	if is_instance_valid(_props.get(a.id)):
		var old:Node3D=_props[a.id]
		_forget_overlays(old)
		old.get_parent().remove_child(old);old.queue_free();_props.erase(a.id)
	_held_ids[a.id]=id
	_held_kinds[a.id]=kind
	if a.id=="player":_overlay_dirty=true
	if not id.is_empty() and is_instance_valid(_arms.get(a.id)):
		var prop:Node3D=HeldTool.create(kind)
		if prop!=null:
			_arms[a.id].add_child(prop);prop.position=Vector3(0,-0.51,0.06)
			# Tool +Y runs from grip to head; the rigid arm's +Y runs back
			# toward the shoulder. Turn the tool forward out of the real palm,
			# otherwise its head and most of the shaft sit inside the sleeve.
			prop.rotation.x=PI/2.0
			prop.set_meta("tool_id",id);_props[a.id]=prop
		else:issues.held=_assembly_issue(str(a.id),str(roots[a.id].get_meta("profile_id","")),str(tool.get("kind","")),"prop:held_tool","TOOL_VIEW_UNSUPPORTED")

func player_occlusion_samples()->Array:
	var player:Node3D=roots.get("player")
	if not is_instance_valid(player) or not player.is_visible_in_tree() or not player.get_meta("assembly_ok",false):return []
	var torso:Node3D=_arms.player.get_parent() if is_instance_valid(_arms.get("player")) else player
	var head:Node3D=torso.get_node_or_null("head")
	var points:Array=[{"part":"chest","position":torso.to_global(Vector3(0,1.1,0)),"grace":0.2},
		{"part":"head","position":head.to_global(head.get_aabb().get_center()) if head is MeshInstance3D else player.to_global(Vector3(0,1.65,0)),"grace":0.2}]
	var tool:Node3D=_props.get("player")
	if is_instance_valid(_arms.get("player")) and _arms.player.is_visible_in_tree():points.append({"part":"palm","position":_arms.player.to_global(Vector3(0,-0.51,0.06)),"grace":0.02})
	if is_instance_valid(tool) and tool.is_visible_in_tree():
		var frame:Dictionary=HeldTool.contact_frame(tool)
		if not frame.is_empty():
			var grip:Vector3=frame.grip_world;var tip:Vector3=frame.point_world
			if points.size()==2:points.append({"part":"palm","position":grip,"grace":0.02})
			points.append({"part":"tool_middle","position":grip.lerp(tip,0.5),"grace":0.02})
			points.append({"part":"tool_tip","position":tip,"grace":0.02})
	return points

func set_player_occluded(value:bool)->void:
	if value==_player_occluded and not _overlay_dirty:return
	_player_occluded=value;_overlay_dirty=false
	if _silhouette==null:
		_silhouette=StandardMaterial3D.new()
		_silhouette.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		_silhouette.albedo_color=Color(0.45,0.75,0.71,0.62)
		_silhouette.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		# A narrow doorway post must not recolor the entire exposed character.
		# Reuse Godot's native inverted depth test: only covered fragments draw.
		_silhouette.depth_test=BaseMaterial3D.DEPTH_TEST_INVERTED
		_silhouette.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
		_silhouette.render_priority=110
	if roots.has("player"):_overlay_player(roots.player)
func _overlay_player(node:Node)->void:
	if node is MeshInstance3D:
		var key:int=node.get_instance_id()
		if not _old_overlays.has(key):_old_overlays[key]=node.material_overlay
		node.material_overlay=_silhouette if _player_occluded else _old_overlays[key]
	for child:Node in node.get_children():_overlay_player(child)

func _forget_overlays(node:Node)->void:
	# Retired equipment must leave the tree before the next silhouette traversal.
	if node is MeshInstance3D:_old_overlays.erase(node.get_instance_id())
	for child:Node in node.get_children():_forget_overlays(child)

func _play(id:String,state:String,rate:float=1.0,event:float=0.0)->void:
	if not _animations.has(id):return
	var player:AnimationPlayer=_animations[id]
	if state=="RestLying" and str(_model_paths.get(id,"")).ends_with("/infected_walker.glb"):
		# This delivered rig has no lying clip or carry socket. Retain the real
		# incapacitated tilt, freeze Idle, and explicitly report this optional case.
		_record_fallback(id,"clip:RestLying",str(_model_paths[id]),"frozen Idle with incapacitated root tilt")
		state="Idle";rate=0.0
	# A mode/rate change need not restart the same CarryWalk cycle. Conversely,
	# an actual new hit/attack must retrigger even when its semantic state stays.
	player.speed_scale=rate
	var same:bool=_states.get(id)==state
	if same and float(_clip_events.get(id,0))==event:return
	for animation: String in player.get_animation_list():
		if animation==state or animation.ends_with("/"+state):
			player.play(animation,0.12)
			if same:player.seek(0,true)
			_states[id]=state
			_clip_events[id]=event
			return
	# A requested semantic state may never silently keep a previous action alive.
	player.stop()
	var issue:Dictionary=_assembly_issue(id,str(_model_paths.get(id,"")).get_file().get_basename(),str(_model_paths.get(id,"")),"clip:"+state,"CLIP_MISSING")
	if not _required_errors.has(id):_required_errors[id]=[]
	if not _required_errors[id].has(issue):_required_errors[id].append(issue)

func statistics() -> Dictionary:
	var rates:Dictionary={}
	for id:String in _animations:rates[id]=_animations[id].speed_scale
	var skins:Dictionary={}
	for id:String in _skin_models:
		var texture:Texture2D=_skin_textures.get(str(_skin_models[id])+"_"+str(_skin_applied.get(id,"original")))
		if texture!=null:skins[id]={"resource":texture.get_meta("source_resource",""),"mode":texture.get_meta("source_mode","")}
	var contacts:Dictionary={}
	for id:String in _props:
		if is_instance_valid(_props[id]):
			var frame:Dictionary=HeldTool.contact_frame(_props[id])
			frame.tool_id=_held_ids.get(id,"");frame.work_pose=_states.get(id)=="Use"
			contacts[id]=frame
	return {"actors":roots.size(),"animation_players":_animations.size(),"animation_states":_states.duplicate(),"animation_rates":rates,"skin_states":_skin_applied.duplicate(),"skin_sources":skins,"tool_contacts":contacts,"work":_work_frames.duplicate(true),"module_rest":_module_rest.reports.duplicate(true)}
