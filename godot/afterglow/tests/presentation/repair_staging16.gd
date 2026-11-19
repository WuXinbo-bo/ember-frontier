extends SceneTree
## Explicit project DTO contract; actual renderer/normal-camera quality belongs to root.
const Conditions=preload("res://scripts/presentation/factory_condition_view.gd")
const Feedback=preload("res://scripts/ui/ui_projection.gd")
var checks:Array=[]
func check(name:String,ok:bool)->void:
	checks.append({"name":name,"ok":ok})
	if not ok:print("FAIL "+name)
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var host:=Node3D.new();root.add_child(host)
	var view:=Conditions.new();host.add_child(view)
	var at:=Transform3D(Basis(Vector3.UP,PI/2),Vector3(12,0.65,8))
	var ground:=Transform3D(at.basis,Vector3(13,0,8))
	var work:Dictionary={"active":false,"project_id":"actual-dto-project","operation":"restore","phase":"approaching","progress_seconds":0.0,"duration_seconds":20.0,"paused_reason":"","paused_code":""}
	var original:Dictionary=work.duplicate(true)
	check("approach does not fake delivered materials or labor",view.update_construction(work,at,ground) and not view.statistics().staging_visible and not view.statistics().construction_active)
	check("read-only project DTO",work==original)
	work.phase="working";work.active=true;work.progress_seconds=2.0;view.update_construction(work,at,ground)
	check("real early progress creates visible stage one",view.statistics().staging_visible and view.statistics().construction_stage==1 and view.statistics().construction_active)
	check("staging uses validated ground transform",view._site.global_transform.is_equal_approx(ground))
	check("temporary wall patches use real facade contact",view._facade.global_transform.is_equal_approx(at))
	check("facade patches remain beside the central entrance",view._facade.get_children().all(func(part:Node3D):return part.position.x>0.8))
	check("rack has visible human-scale dimensions",view._stage_parts[0].mesh.get_aabb().size.y>1)
	check("staging adds no physics or capacity",view.find_children("*","CollisionObject3D",true,false).is_empty() and not view.statistics().owns_scaffold_or_ruin)
	var site_id:int=view._site.get_instance_id();var chip_id:int=view._chips[0].get_instance_id();var pose:Transform3D=view._chips[0].transform
	view.update_construction(work,at,ground)
	check("unchanged project reuses all geometry and pose",site_id==view._site.get_instance_id() and chip_id==view._chips[0].get_instance_id() and pose.is_equal_approx(view._chips[0].transform))
	work.progress_seconds=9.0;view.update_construction(work,at,ground)
	check("real middle progress changes construction stage",view.statistics().construction_stage==2 and view._site_label.text.contains("45%"))
	check("only real progress changes activity pose",not pose.is_equal_approx(view._chips[0].transform))
	work.progress_seconds=17.0;view.update_construction(work,at,ground)
	check("late project makes stage three before completion",view.statistics().construction_stage==3 and view._site.visible)
	for code:String in ["held","operator_not_at_port","no_stamina","tool_broken","region_paused"]:
		work.paused_code=code;work.phase="paused";view.update_construction(work,at,ground)
		check("paused retains actual stage but stops fake work "+code,view.statistics().staging_visible and not view.statistics().construction_active and not view._work.visible and view._site_label.text.contains("暂停"))
	work.paused_code="";work.phase="working";work.active=true;view.update_construction(work,at,ground)
	check("actual resumed DTO resumes activity",view.statistics().construction_active)
	work.progress_seconds=20.0;work.phase="completed";view.update_construction(work,at,ground)
	check("completion clears temporary equipment and movement",not view.statistics().staging_visible and not view.statistics().construction_active)
	work.progress_seconds=7.0;work.phase="cancelled";view.update_construction(work,at,ground)
	check("cancelled clears temporary equipment",not view.statistics().staging_visible)
	work.phase="working";work.progress_seconds=NAN
	check("invalid project hides all stale staging",not view.update_construction(work,at,ground) and not view._site.visible and not view._work.visible)
	view.update_construction({},at,ground)
	check("missing project clears prior issue and project identity",view.statistics().issues.is_empty() and view.statistics().project_id.is_empty())
	for code:String in ["operator_not_at_port","MODULE_TOOL_REQUIRED","MODULE_NOT_RESTORABLE","stamina_or_tool"]:
		var text:String=Feedback.reason_text(code)
		check("specific human reason "+code,text!=code and not text.contains("当前操作条件尚未满足"))
	host.free();await process_frame
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"explicit project DTO, geometry lifecycle and specific UI reasons; no actual owner route or GPU/visual/FPS qualification"},"\t"));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
