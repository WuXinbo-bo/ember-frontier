extends "res://tests/buildings/domain_suite.gd"
## Actual three imported rigid arms and five finite registered tool fixtures.
## Checks display geometry only, never tool reach or world-action authority.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const ToolView=preload("res://scripts/presentation/held_tool_view.gd")
var view:Node3D

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("original rural fixture loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("neighbor",at.merged({"x":31},true)),resident("shopkeeper",at.merged({"x":32},true))])
	var state:Dictionary=Production.empty_state()
	for id:String in ["player","neighbor","shopkeeper"]:
		for kind:String in ["hammer","salvaged_axe","hand_saw","shovel","pickaxe"]:
			state.tools.append({"id":"fixture:"+id+":"+kind,"kind":kind,"holderId":"pack:"+id,"durability":1.0,"qualities":{}})
	var draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,state)],world.get_revision())
	expect("same world accepts finite separately owned tool fixtures",draft.ok and world.commit_prepared(draft.capability).ok)
	var script:Script=Actors
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()>1:
		var old:=GDScript.new();old.source_code=FileAccess.get_file_as_string(args[1])
		expect("archived display source compiles for same geometry comparison",old.reload()==OK)
		script=old
	view=script.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	var before:Dictionary=runtime.capture_checkpoint()
	for id:String in ["player","neighbor","shopkeeper"]:
		var arm:MeshInstance3D=view._arms[id]
		var sleeve:AABB=arm.mesh.get_aabb()
		for kind:String in ["hammer","salvaged_axe","hand_saw","shovel","pickaxe"]:
			var a:Dictionary=runtime.actor(id).duplicate(true)
			a.intent={"tool_id":"fixture:"+id+":"+kind}
			view._update_props(a,{},false,"Use")
			var prop:Node3D=view._props[id]
			var head:MeshInstance3D=prop.get_child(1)
			var center:Vector3=prop.transform*(head.transform*head.mesh.get_aabb().get_center())
			var clearance:float=center.z-sleeve.end.z
			expect("working head clears original sleeve front "+id+" "+kind,clearance>0.025,{"head_center":str(center),"sleeve_front":sleeve.end.z,"clearance_metres":clearance})
			expect("grip remains within original lower palm volume "+id+" "+kind,sleeve.has_point(prop.position) and prop.position.y<sleeve.position.y+sleeve.size.y*0.3,{"grip":str(prop.position),"arm":str(sleeve)})
			var contact:Vector3=prop.get_meta("contact_point")
			var on_surface:bool=false
			for mesh:MeshInstance3D in prop.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh.get_aabb().grow(0.0001).has_point(mesh.transform.affine_inverse()*contact):on_surface=true
			expect("contact lies on actual tool mesh within human scale "+id+" "+kind,on_surface and contact.length()>0.2 and contact.length()<0.9,str(contact))
			var frame:Dictionary=ToolView.contact_frame(prop)
			var local_contact:Vector3=prop.global_transform.affine_inverse()*Vector3(frame.point_world)
			expect("public contact follows original moving arm in world metres "+id+" "+kind,local_contact.is_equal_approx(contact) and is_equal_approx(Vector3(frame.normal_world).length(),1.0) and Vector3(frame.grip_world).is_equal_approx(prop.global_position))
			var animator:AnimationPlayer=view._animations[id]
			animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var bounded:=true;var preserved:=true;var finite:=true
			for progress:float in [0.2,0.5,0.8]:
				animator.play("Use",0.0);animator.seek(progress,true)
				prop.rotation=Vector3(PI/2,0,0)
				var arm_origin:Vector3=arm.position;var palm:Vector3=prop.position
				var limb:float=arm.global_position.distance_to(prop.global_position)
				var body:Transform3D=view.roots[id].transform
				frame=ToolView.contact_frame(prop)
				var point:Vector3=Vector3(frame.point_world)+Vector3(0.1,-0.08,0.14)
				var work:Dictionary={"progress_seconds":progress,"contact":{"position":[point.x,point.y,point.z],"normal":[0.0,0.0,-1.0]}}
				view._aim_work_arm(id,prop,work,animator.get_animation("Use").length);view._aim_work_tool(prop,work)
				bounded=bounded and float(work.arm_contact.shoulder_degrees)<=65.001 and float(work.contact_result.wrist_degrees)<=35.001
				preserved=preserved and arm.position.is_equal_approx(arm_origin) and prop.position.is_equal_approx(palm) and is_equal_approx(arm.global_position.distance_to(prop.global_position),limb) and view.roots[id].transform.is_equal_approx(body)
				finite=finite and is_finite(float(work.contact_result.gap_meters)) and float(work.arm_contact.radial_shortfall_m)>=0
			expect("coupled contact keeps original pose angle bounds "+id+" "+kind,bounded)
			expect("coupled contact cannot move body shoulder palm or stretch limb "+id+" "+kind,preserved)
			expect("coupled contact reports actual finite gap and reach shortfall "+id+" "+kind,finite)
	expect("grip display never mutates facts tool ownership durability or time",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free()
	var result:Dictionary={"scope":"actual imported arm/derived tool geometry, explicit finite registered fixtures; not native VA or action reach","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_GRIP "+JSON.stringify({"checks":checks.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
