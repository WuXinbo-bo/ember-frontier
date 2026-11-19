extends "res://tests/buildings/domain_suite.gd"
## Post22 derived-shape comparison against the ORIGINAL fixed22 actor and GLBs.
## This is a geometry/rig/material check, not OS, normal-camera VA or reach proof.
const Candidate=preload("res://scripts/presentation/actor_view.gd")
const Original=preload("res://scripts/presentation/actor_view.gd") # EXTERNAL_ORIGINAL
const Shape=preload("res://scripts/presentation/resident_shape.gd")
const Tools=preload("res://scripts/presentation/held_tool_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const ROLES=["root","head","arm_l","arm_r","leg_l","leg_r"]
var geometry:Array=[]

func run()->void:
	for profile:String in ["r1_resident_commuter","r1_resident_neighbor","r1_resident_shopkeeper"]:probe_mesh(profile)
	probe_actual_actor()
	var result:Dictionary={"scope":"post22 D source overlay; immutable22 resources and original actor comparator; synthetic finite tool fixture; CPU mesh projection only; NOT unmodified22 qualification, normal route, OS, VA or FPS","checks":checks,"failures":failures}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(geometry))
	print("DDD_SHAPE "+JSON.stringify({"checks":checks.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func probe_mesh(profile:String)->void:
	var scene:PackedScene=load("res://data/gameplay/actors/"+profile+".glb")
	var source:Node3D=scene.instantiate();var target:Node3D=scene.instantiate()
	var before:Dictionary={}
	for role:String in ROLES:
		var node:MeshInstance3D=source.find_child(role,true,false)
		before[role]=mesh_hash(node.mesh)
	var rig:Dictionary=rig_state(target)
	var report:Dictionary=Shape.apply(target,profile)
	expect("all six original parts accept shape "+profile,report.ok,report)
	if not report.ok:source.free();target.free();return
	expect("no node transform or hierarchy changed "+profile,rig==rig_state(target))
	expect("same rig clips tracks and keys "+profile,animation_state(source)==animation_state(target))
	var cached:Node3D=scene.instantiate();Shape.apply(cached,profile)
	for role:String in ROLES:
		var old:MeshInstance3D=source.find_child(role,true,false);var node:MeshInstance3D=target.find_child(role,true,false)
		var again:MeshInstance3D=cached.find_child(role,true,false)
		var original:Array=old.mesh.surface_get_arrays(0)
		if role=="head":
			var identity_ok:=true
			for span:Dictionary in node.mesh.get_meta("source_spans"):
				var box:AABB=cube_bounds(original,span.part)
				if span.semantic==1:identity_ok=identity_ok and box.position.distance_to(Vector3(-.205,.03,-.18))<.00005 and box.size.distance_to(Vector3(.41,.36,.36))<.00005
				if span.semantic==2:identity_ok=identity_ok and box.position.distance_to(Vector3(-.22,.355,-.21))<.00005 and box.size.distance_to(Vector3(.44,.11,.39))<.00005
				if profile=="r1_resident_neighbor" and span.surface==1:identity_ok=identity_ok and absf(absf(box.get_center().x)-.105)<.00005 and box.get_center().distance_to(Vector3(box.get_center().x,.23,.217))<.00005 and box.size.distance_to(Vector3(.11,.07,.007))<.00005
			expect("semantic head and transparent lens match real imported anatomy "+profile,identity_ok)
		var bounded:=true;var uv_ok:=true;var unchanged:=true;var normals_ok:=true;var winding_ok:=true
		var min_dot:float=1.0;var uv_error:float=0.0;var triangle_count:int=0;var max_normal_delta:float=0.0
		for span:Dictionary in node.mesh.get_meta("source_spans"):
			var a:Array=node.mesh.surface_get_arrays(span.surface)
			var box:AABB=cube_bounds(original,span.part)
			var changed:bool=span.semantic>=0 and not (role=="head" and profile=="r1_resident_neighbor" and span.semantic in [11,13])
			for i:int in range(span.first,span.first+span.count):
				var point:Vector3=a[Mesh.ARRAY_VERTEX][i];var normal:Vector3=a[Mesh.ARRAY_NORMAL][i];var uv:Vector2=a[Mesh.ARRAY_TEX_UV][i]
				bounded=bounded and box.grow(.000002).has_point(point)
				normals_ok=normals_ok and is_finite(normal.x) and is_equal_approx(normal.length(),1.0)
				if not changed:
					var j:int=span.part*24+i-span.first
					# Godot repacks normals in ArrayMesh; positions/UV must stay exact.
					max_normal_delta=maxf(max_normal_delta,normal.distance_to(original[Mesh.ARRAY_NORMAL][j]))
					unchanged=unchanged and point==original[Mesh.ARRAY_VERTEX][j] and normal.distance_to(original[Mesh.ARRAY_NORMAL][j])<.0001 and uv==original[Mesh.ARRAY_TEX_UV][j]
				else:
					# At a 45-degree bevel, packed normals can swap equally good
					# original faces. Accept either face within 0.00015 dot only.
					var best:int=best_face(original,span.part,normal)
					var score:float=normal.dot(original[Mesh.ARRAY_NORMAL][best]);var err:float=INF
					for face:int in 6:
						var first:int=span.part*24+face*4
						if score-normal.dot(original[Mesh.ARRAY_NORMAL][first])>.00015:continue
						var lo:Vector2=original[Mesh.ARRAY_TEX_UV][first];var hi:Vector2=lo
						for j:int in range(first,first+4):lo=lo.min(original[Mesh.ARRAY_TEX_UV][j]);hi=hi.max(original[Mesh.ARRAY_TEX_UV][j])
						err=minf(err,maxf(maxf(lo.x-uv.x,uv.x-hi.x),maxf(lo.y-uv.y,uv.y-hi.y)))
					uv_error=maxf(uv_error,err)
					uv_ok=uv_ok and err<.000003 and is_finite(uv.x) and is_finite(uv.y)
		for surface:int in node.mesh.get_surface_count():
			var a:Array=node.mesh.surface_get_arrays(surface);var vs:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var ix:PackedInt32Array=a[Mesh.ARRAY_INDEX];var ns:PackedVector3Array=a[Mesh.ARRAY_NORMAL]
			for k:int in range(0,ix.size(),3):
				var cross:Vector3=(vs[ix[k+1]]-vs[ix[k]]).cross(vs[ix[k+2]]-vs[ix[k]])
				var sign_value:float=cross.normalized().dot(ns[ix[k]])
				min_dot=minf(min_dot,absf(sign_value));triangle_count+=1
				winding_ok=winding_ok and cross.length_squared()>1e-14 and sign_value*source_winding(original)>.99
		expect("derived vertices inside each original cuboid "+profile+" "+role,bounded)
		expect("all facets remain in original per-face UV islands "+profile+" "+role,uv_ok,{"max_error":uv_error})
		expect("non-target vertices UV exact and normals within packing bound "+profile+" "+role,unchanged,{"normal_delta":max_normal_delta,"normal_tolerance":.0001})
		expect("finite unit flat normals and original winding "+profile+" "+role,normals_ok and winding_ok,{"min_abs_dot":min_dot,"triangles":triangle_count})
		expect("same finite mesh cache reused "+profile+" "+role,node.mesh==again.mesh)
		expect("source shared mesh and material untouched "+profile+" "+role,before[role]==mesh_hash(old.mesh))
	probe_contours(target,profile)
	expect("reapplying shape is idempotent "+profile,Shape.apply(target,profile)==report)
	geometry.append({"profile":profile,"before":export_mesh(source),"after":export_mesh(target)})
	var malformed:Node3D=scene.instantiate();malformed.find_child("leg_l",true,false).free()
	var head:MeshInstance3D=malformed.find_child("head",true,false);var old_mesh:Mesh=head.mesh
	expect("missing original part rejected without partial assignment "+profile,not Shape.apply(malformed,profile).ok and head.mesh==old_mesh)
	malformed.free()
	var drifted:Node3D=scene.instantiate();head=drifted.find_child("head",true,false)
	var arrays:Array=head.mesh.surface_get_arrays(0);arrays[Mesh.ARRAY_VERTEX][0].x-=.001
	var changed:=ArrayMesh.new();changed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);changed.surface_set_material(0,head.mesh.surface_get_material(0));head.mesh=changed
	expect("changed source dimensions rejected without applying other meshes "+profile,not Shape.apply(drifted,profile).ok and not drifted.find_child("root",true,false).mesh.has_meta("resident_shape"))
	drifted.free();cached.free();source.free();target.free()

func probe_contours(model:Node3D,profile:String)->void:
	var head:MeshInstance3D=model.find_child("head",true,false)
	var hair:Dictionary=span_extent(head.mesh,2);var face:Dictionary=span_extent(head.mesh,1)
	var torso:Dictionary=span_extent(model.find_child("root",true,false).mesh,0)
	expect("crown tapers and sweeps within original height "+profile,hair.top_width<hair.bottom_width*.60 and absf(hair.top_center.x-hair.bottom_center.x)>.02,hair)
	expect("jaw narrower than temples "+profile,face.bottom_width<face.max_width*.85,face)
	expect("shoulder slopes toward neck "+profile,torso.top_width<torso.max_width*.70,torso)
	for role:String in ["leg_l","leg_r"]:
		var boot:Dictionary=span_extent(model.find_child(role,true,false).mesh,1)
		expect("boot full sole and tapered upper "+profile+" "+role,is_equal_approx(boot.bottom_y,-.78) and is_equal_approx(boot.bottom_width,.23) and boot.top_depth<boot.bottom_depth*.75,boot)
	for role:String in ["arm_l","arm_r"]:
		var arm:MeshInstance3D=model.find_child(role,true,false);var inside:float=-INF if role=="arm_l" else INF
		for span:Dictionary in arm.mesh.get_meta("source_spans"):
			if span.semantic!=0:continue
			var a:Array=arm.mesh.surface_get_arrays(span.surface)
			for i:int in range(span.first,span.first+span.count):
				var p:Vector3=a[Mesh.ARRAY_VERTEX][i]
				if absf(p.y)<.00005:inside=maxf(inside,p.x) if role=="arm_l" else minf(inside,p.x)
		expect("shoulder cap retains original inner seam "+profile+" "+role,absf(inside-(.095 if role=="arm_l" else -.095))<.00005,{"inner_shoulder_x":inside})
	if profile=="r1_resident_neighbor":
		var glass:Material=head.mesh.surface_get_material(1)
		expect("lenses alone have separate alpha surface",head.mesh.get_surface_count()==2 and glass.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and glass.albedo_color.a<.2 and glass.get_meta("resident_clear_lens",false))
		for part:int in [10,12]:
			expect("frame aperture contains no opaque triangle "+str(part),not frame_blocks_center(head.mesh,part))

func probe_actual_actor()->void:
	expect("actual22 rural fixture loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("neighbor",at.merged({"x":31},true)),resident("shopkeeper",at.merged({"x":32},true))])
	var state:Dictionary=Production.empty_state()
	for id:String in ["player","neighbor","shopkeeper"]:
		for kind:String in ["hammer","salvaged_axe","hand_saw","shovel","pickaxe"]:state.tools.append({"id":"shape-fixture:"+id+":"+kind,"kind":kind,"holderId":"pack:"+id,"durability":100.0,"qualities":{}})
	var draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,state)],world.get_revision())
	expect("finite geometry comparison fixture accepted",draft.ok and world.commit_prepared(draft.capability).ok)
	var before:Dictionary=runtime.capture_checkpoint()
	var old:Node3D=Original.new();var current:Node3D=Candidate.new()
	for view:Node3D in [old,current]:root.add_child(view);view.set_process(false);view.configure(runtime)
	for id:String in ["player","neighbor","shopkeeper"]:
		expect("comparator is actual original22 actor not candidate alias "+id,not old.roots[id].has_meta("resident_shape"))
		expect("candidate actor accepts original identity body and selection "+id,current.roots[id].get_meta("assembly_ok") and current.roots[id].get_meta("profile_id")==old.roots[id].get_meta("profile_id") and current.roots[id].get_meta("body_profile_id")==old.roots[id].get_meta("body_profile_id") and current.roots[id].get_child(1).get_child(0).shape.height==old.roots[id].get_child(1).get_child(0).shape.height)
		expect("actual actor selected new shape "+id,current.roots[id].get_meta("resident_shape").get("policy")==Shape.POLICY)
		var bindings_ok:=true
		for row:Dictionary in current._skin_bindings[id]:bindings_ok=bindings_ok and not row.base.get_meta("resident_clear_lens",false)
		expect("body skin application excludes clear lens "+id,bindings_ok)
		if id=="neighbor":
			var lens_head:MeshInstance3D=current.roots[id].find_child("head",true,false)
			var lens:Material=lens_head.get_active_material(1)
			var lens_ok:=true
			for wounds:Array in [[{"cause":"shape-only skin-transition fixture"}],[]]:
				var skin_actor:Dictionary=runtime.actor(id).duplicate(true);skin_actor.wounds=wounds;current._update_skin(skin_actor)
				lens_ok=lens_ok and lens_head.get_active_material(1)==lens and lens.albedo_color.a<.2 and lens.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and lens.albedo_texture==null
			current._apply_skin_texture(id,null,"original")
			lens_ok=lens_ok and lens_head.get_active_material(1)==lens and lens.albedo_color.a<.2
			current._skin_states.erase(id);current._update_skin(runtime.actor(id))
			expect("wound fallback normal restoration cannot repaint clear lenses",lens_ok)
		var pose_ok:=true;var maximum:float=0.0
		for clip:String in ["Idle","Walk","Run","Use","Carry","CarryWalk","RestLying","Hit"]:
			for view:Node3D in [old,current]:
				var player:AnimationPlayer=view._animations[id];player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;player.play(clip,0.0);player.seek(.23,true)
			pose_ok=pose_ok and rig_state(old.roots[id].get_child(0))==rig_state(current.roots[id].get_child(0))
		expect("all eight clips keep exact original rig transforms "+id,pose_ok)
		for kind:String in ["hammer","salvaged_axe","hand_saw","shovel","pickaxe"]:
			var a:Dictionary=runtime.actor(id).duplicate(true);a.intent={"tool_id":"shape-fixture:"+id+":"+kind}
			var contact_ok:=true
			for view:Node3D in [old,current]:view._update_props(a,{},false,"Use");view._play(id,"Use",1.0)
			for progress:float in [.1,.4,.7]:
				var work:Dictionary={"available":true,"active":true,"progress_seconds":progress,"contact":{"position":[float(a.x)+.15,float(a.y)+.5,float(a.z)+.55],"normal":[0.0,1.0,0.0]}}
				old._sync_work_pose(id,"Use",work.duplicate(true),false);current._sync_work_pose(id,"Use",work.duplicate(true),false)
				var x:Dictionary=Tools.contact_frame(old._props[id]);var y:Dictionary=Tools.contact_frame(current._props[id])
				var gap:float=Vector3(x.point_world).distance_to(Vector3(y.point_world));maximum=maxf(maximum,gap)
				contact_ok=contact_ok and gap<.00002 and Vector3(x.grip_world).distance_to(Vector3(y.grip_world))<.00002 and Vector3(x.normal_world).distance_to(Vector3(y.normal_world))<.00002 and old._arms[id].transform.is_equal_approx(current._arms[id].transform)
			expect("shape change preserves original moving palm tip normal "+id+" "+kind,contact_ok,{"max_tip_delta_m":maximum})
			for view:Node3D in [old,current]:view._sync_work_pose(id,"Idle",{"available":false,"active":false},false)
		current._retire_actor(id)
		expect("shape actor retires without retained rig work refs "+id,not current._arms.has(id) and not current._work_postures.has(id))
		var remounted:Node3D=current._spawn(runtime.actor(id),["player","neighbor","shopkeeper"].find(id))
		expect("same identity remounts derived shape "+id,remounted.get_meta("assembly_ok") and remounted.get_meta("resident_shape").get("policy")==Shape.POLICY)
	expect("geometry and animation consumer changes no world facts",Data.json_equal(before,runtime.capture_checkpoint()))
	expect("three source profiles retain at most eighteen derived mesh resources",Shape._derived.size()==18,{"cached_meshes":Shape._derived.size()})
	old.free();current.free()

func cube_bounds(a:Array,part:int)->AABB:
	var box:=AABB(a[Mesh.ARRAY_VERTEX][part*24],Vector3.ZERO)
	for i:int in range(part*24+1,part*24+24):box=box.expand(a[Mesh.ARRAY_VERTEX][i])
	return box

func best_face(a:Array,part:int,n:Vector3)->int:
	var best:int=part*24;var value:float=-2
	for face:int in 6:
		var i:int=part*24+face*4;var score:float=n.dot(a[Mesh.ARRAY_NORMAL][i])
		if score>value:best=i;value=score
	return best

func source_winding(a:Array)->float:
	var v:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var i:PackedInt32Array=a[Mesh.ARRAY_INDEX]
	return signf((v[i[1]]-v[i[0]]).cross(v[i[2]]-v[i[0]]).dot(a[Mesh.ARRAY_NORMAL][i[0]]))

func mesh_hash(mesh:Mesh)->String:
	return var_to_bytes([mesh.surface_get_arrays(0),mesh.surface_get_material(0).get_instance_id(),mesh.surface_get_material(0).get("albedo_color"),mesh.surface_get_material(0).get("transparency")]).hex_encode().sha256_text()

func rig_state(node:Node)->Dictionary:
	var result:Dictionary={}
	for child:Node in node.find_children("*","Node3D",true,false):
		if child is Node3D:result[str(node.get_path_to(child))]=var_to_str(child.transform)
	return result

func animation_state(node:Node)->Array:
	var result:Array=[];var player:AnimationPlayer=node.find_child("AnimationPlayer*",true,false)
	for name:String in player.get_animation_list():
		var clip:Animation=player.get_animation(name);var rows:Array=[name,clip.length,clip.loop_mode]
		for track:int in clip.get_track_count():
			var keys:Array=[]
			for k:int in clip.track_get_key_count(track):keys.append([clip.track_get_key_time(track,k),clip.track_get_key_value(track,k)])
			rows.append([clip.track_get_type(track),str(clip.track_get_path(track)),keys])
		result.append(rows)
	return result

func span_extent(mesh:Mesh,part:int)->Dictionary:
	var vs:Array=[]
	for span:Dictionary in mesh.get_meta("source_spans"):
		if span.semantic==part:
			var a:Array=mesh.surface_get_arrays(span.surface)
			for i:int in range(span.first,span.first+span.count):vs.append(a[Mesh.ARRAY_VERTEX][i])
	var box:=AABB(vs[0],Vector3.ZERO)
	for p:Vector3 in vs:box=box.expand(p)
	var top:=AABB(Vector3.ZERO,Vector3.ZERO);var bottom:=top;var ti:=false;var bi:=false
	for p:Vector3 in vs:
		if is_equal_approx(p.y,box.position.y):bottom=bottom.expand(p) if bi else AABB(p,Vector3.ZERO);bi=true
		if is_equal_approx(p.y,box.end.y):top=top.expand(p) if ti else AABB(p,Vector3.ZERO);ti=true
	return {"max_width":box.size.x,"top_width":top.size.x,"bottom_width":bottom.size.x,"top_depth":top.size.z,"bottom_depth":bottom.size.z,"bottom_y":box.position.y,"top_center":top.get_center(),"bottom_center":bottom.get_center()}

func frame_blocks_center(mesh:Mesh,part:int)->bool:
	var vertices:Array=[];var indices:PackedInt32Array
	for span:Dictionary in mesh.get_meta("source_spans"):
		if span.semantic!=part:continue
		var a:Array=mesh.surface_get_arrays(span.surface);var box:=AABB(a[Mesh.ARRAY_VERTEX][span.first],Vector3.ZERO)
		for i:int in range(span.first,span.first+span.count):box=box.expand(a[Mesh.ARRAY_VERTEX][i])
		var center:Vector3=box.get_center()
		indices=a[Mesh.ARRAY_INDEX]
		for k:int in range(0,indices.size(),3):
			if indices[k]<span.first or indices[k]>=span.first+span.count:continue
			var p:Vector3=a[Mesh.ARRAY_VERTEX][indices[k]];var q:Vector3=a[Mesh.ARRAY_VERTEX][indices[k+1]];var r:Vector3=a[Mesh.ARRAY_VERTEX][indices[k+2]]
			if Geometry3D.ray_intersects_triangle(center+Vector3(0,0,1),Vector3(0,0,-1),p,q,r)!=null:return true
	return false

func export_mesh(model:Node3D)->Array:
	var result:Array=[]
	for role:String in ROLES:
		var node:MeshInstance3D=model.find_child(role,true,false);var transform:Transform3D=node.transform;var parent:Node=node.get_parent()
		while parent!=model:transform=parent.transform*transform;parent=parent.get_parent()
		for surface:int in node.mesh.get_surface_count():
			var a:Array=node.mesh.surface_get_arrays(surface);var vertices:Array=[];var uv:Array=[];var normals:Array=[]
			for v:Vector3 in a[Mesh.ARRAY_VERTEX]:var p:Vector3=transform*v;vertices.append([p.x,p.y,p.z])
			for v:Vector2 in a[Mesh.ARRAY_TEX_UV]:uv.append([v.x,v.y])
			for n:Vector3 in a[Mesh.ARRAY_NORMAL]:var p:Vector3=transform.basis*n;normals.append([p.x,p.y,p.z])
			result.append({"role":role,"surface":surface,"vertices":vertices,"normals":normals,"uv":uv,"indices":Array(a[Mesh.ARRAY_INDEX]),"alpha":.14 if surface==1 else 1.0})
	return result
