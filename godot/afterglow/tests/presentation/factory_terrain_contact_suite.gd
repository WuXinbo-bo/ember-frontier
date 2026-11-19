extends "res://tests/world/factory_normal_path.gd"
## Actual normal tool sources, movement, terrain owner and original actor mesh.
## Assert true strike/contact phases, planted original feet and pose restoration.
const ActorView=preload("res://scripts/presentation/actor_view.gd")
var contact_observations:Array=[]
func run()->void:
	var opening:Dictionary=normal_tools(Contract.fresh(Modules.generation_profiles(),3).contract)
	if not opening.ok:return finish()
	var runtime:RefCounted=opening.runtime;var world:RefCounted=opening.world
	var view:=ActorView.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	for mode:String in ["pickaxe","shovel"]:
		var at:Dictionary=_location(world,55.0,15.0) if mode=="pickaxe" else _location(world,41.5,20.25)
		at=opening.built.services.buildings.current_space().standing_point(at)
		var walked:Dictionary=walk(runtime,at) if not at.is_empty() else {"ok":false}
		check("normal actor physically reaches actual terrain work site "+mode,walked.get("ok",false),walked)
		if not walked.get("ok",false):break
		var cell:Dictionary={"x":111,"y":roundi(world.surface_height(55.75,15.75)*2)-1,"z":31} if mode=="pickaxe" else {"x":84,"y":roundi(world.surface_height(42.25,20.25)*2)-1,"z":40}
		var operation:String="dig" if mode=="pickaxe" else "level"
		var payload:Dictionary=brush(cell,operation,opening[mode],1 if mode=="pickaxe" else 2,float(cell.y)*0.5,3 if mode=="pickaxe" else 2)
		var started:Dictionary=send(runtime,"terrain","",payload)
		check("normal tool starts real terrain action "+mode,started.ok,started)
		if not started.ok:break
		var samples:Array=[];var unchanged:=true;var preserved:=true;var planted:=true;var above_ground:=true
		var shoulder_origin:Vector3=view._arms.player.position
		var original_legs:Array=[]
		for name:String in ["leg_l","leg_r"]:original_legs.append(view._arms.player.get_parent().get_node(name).position)
		for i:int in 12:
			runtime.tick(.1)
			var before:Dictionary=runtime.capture_checkpoint();view.sync(0)
			unchanged=unchanged and Data.json_equal(before,runtime.capture_checkpoint())
			var row:Dictionary=view.statistics().work.get("player",{})
			if not row.get("active",false) or not row.has("contact_result"):continue
			var arm:Node3D=view._arms.player;var prop:Node3D=view._props.player
			preserved=preserved and arm.position.is_equal_approx(shoulder_origin) and prop.position.is_equal_approx(Vector3(0,-.51,.06)) and arm.scale.is_equal_approx(Vector3.ONE) and prop.scale.is_equal_approx(Vector3.ONE) and view.roots.player.position.is_equal_approx(Geometry.point(runtime.actor("player"))) and is_equal_approx(arm.global_position.distance_to(prop.global_position),float(row.arm_contact.rigid_limb_m))
			var foot_drift:Array=[]
			for leg:Dictionary in view._work_postures.player.legs:
				var drift:float=leg.node.global_position.distance_to(leg.world.origin);foot_drift.append(drift)
				planted=planted and drift<.00002 and leg.node.global_basis.is_equal_approx(leg.world.basis)
			for name:String in ["head","arm_l","leg_l","leg_r"]:
				var mesh:MeshInstance3D=arm.get_parent().get_node(name)
				above_ground=above_ground and (mesh.global_transform*mesh.mesh.get_aabb()).position.y>=float(runtime.actor("player").y)-.00002
			samples.append({"progress":row.progress_seconds,"owner_progress":runtime.actor("player").intent.elapsed,"contact":row.contact,"arm":row.arm_contact,"result":row.contact_result,"posture":row.get("posture",{}),"foot_drift_m":foot_drift,"tool_kind":prop.get_meta("tool_kind"),"state":view._states.player})
		check("actual owner effective progress drives original tool and Use "+mode,samples.size()==12 and samples.all(func(s:Dictionary)->bool:return s.progress==s.owner_progress and s.tool_kind==mode and s.state=="Use"),{"samples":samples.size()})
		check("terrain contact solve preserves original body shoulder palm and limb "+mode,preserved and samples.all(func(s:Dictionary)->bool:return float(s.arm.shoulder_degrees)<=65.001 and float(s.result.wrist_degrees)<=35.001))
		check("public consumer never changes true terrain inventory wear or time "+mode,unchanged)
		var strikes:Array=samples.filter(func(s:Dictionary)->bool:return float(s.arm.retraction_meters)<=.005)
		check("actual terrain strike phases reach original tool surface "+mode,strikes.size()>=2 and strikes.all(func(s:Dictionary)->bool:return float(s.result.gap_meters)<=.04),strikes)
		check("actual tool stays outside terrain within two millimeter tolerance "+mode,samples.all(func(s:Dictionary)->bool:return float(s.result.signed_plane_gap)>=-.002))
		check("actual cutting surface has a definite inward slope at contact "+mode,strikes.size()>=2 and strikes.all(func(s:Dictionary)->bool:return float(s.result.normal_alignment)<=-.4))
		check("rigid hip pose plants original feet with head above ground "+mode,planted and above_ground)
		if not samples.is_empty():
			var gaps:Array=samples.map(func(s:Dictionary)->float:return float(s.result.gap_meters));gaps.sort()
			contact_observations.append({"tool":mode,"actual_foot":Geometry.location(runtime.actor("player")),"minimum_gap_m":gaps[0],"maximum_gap_m":gaps[-1],"contact_samples":samples.filter(func(s:Dictionary)->bool:return float(s.result.gap_meters)<=.04).size(),"samples":samples,"scope":"actual owner contact measurement; a miss remains an open presentation defect"})
		var arm_pose:Transform3D=view._arms.player.transform;var tool_pose:Transform3D=view._props.player.transform;var torso_pose:Transform3D=view._arms.player.get_parent().transform
		runtime.set_paused(true);view.sync(.5)
		check("actual terrain pause freezes corrected original pose "+mode,view._arms.player.transform.is_equal_approx(arm_pose) and view._props.player.transform.is_equal_approx(tool_pose) and view._arms.player.get_parent().transform.is_equal_approx(torso_pose))
		runtime.set_paused(false);send(runtime,"held","",{"held":false});view.sync(0)
		check("actual held release stops terrain Use "+mode,view._states.player!="Use" and not view.statistics().work.player.active)
		check("held release restores original hip and legs immediately "+mode,not view._work_postures.has("player") and view._arms.player.get_parent().transform.is_equal_approx(Transform3D.IDENTITY) and view._arms.player.get_parent().get_node("leg_l").position.is_equal_approx(original_legs[0]) and view._arms.player.get_parent().get_node("leg_r").position.is_equal_approx(original_legs[1]))
		send(runtime,"held","",{"held":true});runtime.tick(.1);view.sync(0)
		check("actual held resume restores effective terrain Use "+mode,view._states.player=="Use" and view.statistics().work.player.active)
		var cancelled:Dictionary=send(runtime,"cancel");view.sync(0)
		check("actual terrain cancel removes manual correction "+mode,cancelled.ok and not view._manual_work.has("player") and not view._work_postures.has("player"))
	view.free();finish()
func finish()->void:
	var failed:Array=checks.filter(func(c:Dictionary)->bool:return not c.ok)
	var result:Dictionary={"scope":"normal content3 tool acquisition and actual A/B/C owner-to-D mesh; no physical-input OS, formal package, normal-camera contact VA or new reach authority","checks":checks,"failures":failed,"observations":contact_observations}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_TERRAIN_CONTACT "+JSON.stringify({"checks":checks.size(),"failed":failed.size()}));quit(0 if failed.is_empty() else 1)
