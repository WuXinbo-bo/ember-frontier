extends "res://tests/presentation/actor_motion_suite.gd"
## Extends real structure lifecycle with a completed real station + craft owner.
## Finite materials/owned tools are inherited fixtures, not normal economy proof.
func finish(started:int)->void:
	if is_instance_valid(view) and failures.is_empty():
		view.set_process(false)
		var bench:Dictionary=building.make_instance("workbench","ddd:craft-contact-bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
		var facts:Dictionary=runtime.facts();facts.actors[0].pack["log"]=1
		expect("finite log fixture uses actual actor pack",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
		var placed:Dictionary=command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"})
		expect("same owner starts station construction",placed.ok,placed)
		if placed.ok:
			for i:int in 90:runtime.tick(0.1)
			expect("actual work completes usable station",not building.instance(bench.id).is_empty())
			var work:Dictionary=command("craft",bench.id,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":["rural:v1:RH-HOME:shed:hand_saw"]})
			expect("actual craft starts with finite log and owned saw",work.ok,work)
			if work.ok:
				var samples:Array=[]
				for i:int in 12:
					runtime.tick(0.1);view.sync(0)
					var measured:Dictionary=view.statistics().work.player
					if measured.get("contact_result") is Dictionary:
						samples.append({"progress":measured.progress_seconds,"contact":measured.contact,"arm":measured.arm_contact,"result":measured.contact_result,"actor_position":view.roots.player.position,"grip_local":view._props.player.position})
				expect("real craft uses owner actual 0.9m table surface",samples.size()==12 and samples.all(func(row:Dictionary)->bool:return absf(float(row.contact.position[1])-0.9)<0.00001),samples)
				expect("coupled solve preserves actual shoulder palm and bounded rotations",samples.all(func(row:Dictionary)->bool:return row.grip_local.is_equal_approx(Vector3(0,-0.51,0.06)) and float(row.arm.shoulder_degrees)<=65.001 and float(row.result.wrist_degrees)<=35.001 and row.actor_position.is_equal_approx(Vector3(33.3,0,40.5))),samples)
				var before:Dictionary=runtime.capture_checkpoint();var pose:Transform3D=view._arms.player.transform;var tool:Transform3D=view._props.player.transform
				view.sync(1.0);view.sync(0.016)
				expect("same effective craft time gives deterministic exact pose and no world mutation",pose.is_equal_approx(view._arms.player.transform) and tool.is_equal_approx(view._props.player.transform) and Data.json_equal(before,runtime.capture_checkpoint()))
				expect("real craft cancellation releases same order",command("cancel").ok)
				var walk:Dictionary=command("move","",{}, {"x":33.3,"y":0,"z":40.7,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
				expect("same body accepts actual nearer approach route",walk.ok,walk)
				if walk.ok:
					for i:int in 15:runtime.tick(0.1)
					var at:Dictionary=runtime.actor("player")
					expect("actual move settles nearer without fixture teleport",absf(float(at.x)-33.3)<0.02 and absf(float(at.z)-40.7)<0.02,{"x":at.x,"y":at.y,"z":at.z})
					var resumed:Dictionary=command("craft",bench.id,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":["rural:v1:RH-HOME:shed:hand_saw"]})
					expect("actual craft accepts nearer reached body",resumed.ok,resumed)
					if resumed.ok:
						var near_samples:Array=[]
						for i:int in 12:
							runtime.tick(0.1);view.sync(0)
							var measured:Dictionary=view.statistics().work.player
							if measured.get("contact_result") is Dictionary:near_samples.append({"progress":measured.progress_seconds,"contact":measured.contact,"arm":measured.arm_contact,"result":measured.contact_result,"actor_position":view.roots.player.position})
						expect("nearer actual craft yields finite measured reach rather than forced contact",near_samples.size()==12 and near_samples.all(func(row:Dictionary)->bool:return is_finite(float(row.result.gap_meters))),near_samples)
						expect("nearer actual craft cancellation releases same order",command("cancel").ok)
	super.finish(started)
