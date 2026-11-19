extends RefCounted
## A render attachment for an already accepted rest on B's exact new bed.
## The actor root, capsule, permissions, occupancy and recovery never move here.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var bindings:Dictionary={}
var reports:Dictionary={}

static func frame(actor:Dictionary,bed:Dictionary)->Dictionary:
	var intent:Variant=actor.get("intent")
	if not intent is Dictionary or intent.get("owner")!="runtime" or intent.get("kind") not in ["rest","sleep"] or intent.get("target_id")!=bed.get("id") or float(actor.get("hp",0))<=0:return {}
	var data:Dictionary=bed.get("data",{})
	var version:String=str(data.get("module_geometry_version",""))
	if not version.begins_with("r34.module.home_") or not version.ends_with(".geometry-v2") or not data.get("sleeping",false) or not data.get("prepared",false) or bed.get("regionId")!=actor.get("regionId"):return {}
	var pose:Variant=data.get("module_bed")
	if not pose is Dictionary or pose.get("version")!=2 or not Data.vec(pose.get("surface")) or not Data.vec(pose.get("normal")) or not Data.bounds(pose.get("room_bounds")):return {}
	var normal:Vector3=G.point(pose.normal)
	if not normal.is_equal_approx(Vector3.UP):return {}
	var head:Vector3
	if pose.has("head_direction"):
		if not Data.vec(pose.head_direction):return {}
		head=G.point(pose.head_direction)
	else:
		if not pose.get("quarter_turn") is int or pose.quarter_turn<0 or pose.quarter_turn>3:return {}
		head=G.rotate(Vector3.BACK,int(pose.quarter_turn))
	if absf(head.y)>.0001 or head.length_squared()<.99 or head.length_squared()>1.01:return {}
	if not Data.contains(pose.room_bounds,pose.surface):return {}
	return {"bed_id":bed.id,"surface":G.point(pose.surface),"head":head.normalized(),"level":pose.get("level",0),"scope":"accepted exact geometry2 bed; render model only"}

func retire(id:String)->void:
	bindings.erase(id);reports.erase(id)

func restore(id:String)->void:
	var b:Dictionary=bindings.get(id,{})
	if not b.is_empty() and is_instance_valid(b.model) and is_instance_valid(b.root):
		if is_instance_valid(b.get("animator")):b.animator.callback_mode_process=b.callback
		# Reparent without retaining the bed offset. Original animation-local
		# transform and model subtree remain exactly as supplied by the rig.
		var original:Transform3D=b.model.transform
		b.model.reparent(b.root,false);b.model.transform=original
		b.root.move_child(b.model,mini(int(b.index),b.root.get_child_count()-1))
		b.anchor.get_parent().remove_child(b.anchor);b.anchor.queue_free()
	retire(id)

func sync(actor:Dictionary,root:Node3D,state:String,authority:RefCounted,paused:bool,animator:AnimationPlayer=null)->void:
	var id:String=str(actor.id);var f:Dictionary={}
	if state=="RestLying" and authority!=null and authority.world!=null:
		var intent:Variant=actor.get("intent")
		if intent is Dictionary and intent.get("owner")=="runtime" and intent.get("kind") in ["rest","sleep"] and not str(intent.get("target_id","")).is_empty():
			var bed:Dictionary=authority.world.entity(str(intent.target_id))
			f=frame(actor,bed)
			if not f.is_empty() and (not authority.has_method("bed_availability") or not authority.bed_availability(actor,str(bed.id)).get("ok",false)):f={}
	if f.is_empty():restore(id);return
	if not root.is_visible_in_tree():return
	if animator==null or animator.current_animation.is_empty():return
	var clip:String=animator.current_animation
	if not animator.has_animation(clip):return
	var original_callback:int=animator.callback_mode_process
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.play(clip,0)
	animator.seek(fposmod(float(actor.intent.get("elapsed",0)),maxf(.001,animator.get_animation(clip).length)),true)
	if not bindings.has(id):
		var model:Node3D=root.get_child(0) if root.get_child_count()>0 else null
		if model==null or model is CollisionObject3D:animator.callback_mode_process=original_callback;return
		var anchor:=Node3D.new();anchor.name="AcceptedBedVisual";root.add_child(anchor)
		var index:int=model.get_index();model.reparent(anchor,false);root.move_child(anchor,index)
		var first:bool=true;var bounds:AABB
		for mesh:Node in model.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or mesh.mesh==null:continue
			var box:AABB=(anchor.global_transform.affine_inverse()*mesh.global_transform)*mesh.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
		var head:MeshInstance3D=model.find_child("head",true,false) as MeshInstance3D
		if first or head==null:
			model.reparent(root,false);root.move_child(model,index);root.remove_child(anchor);anchor.queue_free();animator.callback_mode_process=original_callback;return
		var head_at:Vector3=anchor.to_local(head.to_global(head.mesh.get_aabb().get_center()))
		var heading:Vector3=head_at-bounds.get_center();heading.y=0
		if heading.length_squared()<.001:
			model.reparent(root,false);root.move_child(model,index);root.remove_child(anchor);anchor.queue_free();animator.callback_mode_process=original_callback;return
		bindings[id]={"root":root,"model":model,"anchor":anchor,"index":index,"pivot":Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z),"heading":heading.normalized(),"authored_bounds":bounds,"animator":animator,"callback":original_callback}
	var b:Dictionary=bindings[id]
	if paused and reports.has(id):return
	var yaw:float=atan2(f.head.x,f.head.z)-atan2(b.heading.x,b.heading.z)
	var basis:=Basis(Vector3.UP,yaw)
	var origin:Vector3=f.surface+Vector3(0,.005,0)-basis*Vector3(b.pivot)
	b.anchor.global_transform=Transform3D(basis,origin)
	var rendered:AABB=b.anchor.global_transform*AABB(b.authored_bounds)
	reports[id]={"bed_id":f.bed_id,"level":f.level,"surface":[f.surface.x,f.surface.y,f.surface.z],"head_alignment":(basis*Vector3(b.heading)).dot(f.head),"bottom_gap_m":rendered.position.y-f.surface.y,"render_bounds":G.json_box(rendered),"actor_root":[root.global_position.x,root.global_position.y,root.global_position.z],"authority_changes":false}
