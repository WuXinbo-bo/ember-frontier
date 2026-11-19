extends SceneTree
## Explicit condition DTO source tests; no formal owner or visual qualification.
const Conditions=preload("res://scripts/presentation/factory_condition_view.gd")
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label);print("FAIL ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Node3D.new();root.add_child(host);host.position=Vector3(20,3,-10);host.rotation.y=0.7
	var view:=Conditions.new();host.add_child(view)
	var anchor:=Transform3D(Basis(Vector3.UP,PI/2),Vector3(12,0.9,8))
	var row:Dictionary={"active":true,"project_id":"actual-project","phase":"building","progress_seconds":1.2,"duration_seconds":12.0,"paused_reason":""}
	var before:String=JSON.stringify(row)
	expect("real construction projection makes only local activity",view.update_construction(row,anchor) and view.statistics().construction_active and not view.statistics().owns_scaffold_or_ruin)
	expect("consumer preserves supplied construction DTO",JSON.stringify(row)==before)
	expect("activity uses world anchor exactly once",view._work.global_transform.is_equal_approx(anchor))
	var chip:Node3D=view._chips[0];var chip_id:int=chip.get_instance_id();var frozen:Transform3D=chip.transform
	view.update_construction(row,anchor)
	expect("same effective progress retains node and frozen pose",chip.get_instance_id()==chip_id and chip.transform.is_equal_approx(frozen))
	row.progress_seconds=2.0;view.update_construction(row,anchor)
	expect("only owner progress moves chips",not chip.transform.is_equal_approx(frozen))
	for reason:String in ["missing_input","missing_operator","paused","region_paused"]:
		row.paused_reason=reason;view.update_construction(row,anchor)
		expect("blocked project cannot pretend work "+reason,not view.statistics().construction_active and not view._work.visible)
	row.paused_reason="";row.progress_seconds=12.0;view.update_construction(row,anchor)
	expect("completed project stops local work",not view._work.visible)
	row.active=false;row.progress_seconds=3.0;view.update_construction(row,anchor)
	expect("inactive project stops chips despite nonzero progress",not view._work.visible)
	row.progress_seconds=NAN
	expect("malformed project hides stale effects",not view.update_construction(row,anchor) and not view._work.visible)
	var damage:Dictionary={"hp":75.0,"max_hp":100.0,"state_code":"damaged","ruin_id":"","anchor_id":"surface"}
	expect("real partial HP binds an existing alpha detail",view.update_damage(damage,anchor,"b_wood_damage_detail") and view.statistics().damage_visible)
	var material:StandardMaterial3D=view._damage.material_override
	expect("detail uses original alpha and physical 0.7m coverage",material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and not material.texture_repeat and view._damage.mesh.size.is_equal_approx(Vector2.ONE*0.7))
	expect("detail is offset along real world surface normal",view._damage.global_position.is_equal_approx(anchor.origin+anchor.basis.z*0.006))
	var detail_id:int=view._damage.get_instance_id();var material_id:int=material.get_instance_id()
	damage.hp=50.0;view.update_damage(damage,anchor,"b_wood_damage_detail")
	expect("damage updates reuse detail and material",view._damage.get_instance_id()==detail_id and view._damage.material_override.get_instance_id()==material_id and is_equal_approx(view.statistics().damage_ratio,0.5))
	damage.hp=100.0;view.update_damage(damage,anchor,"b_wood_damage_detail")
	expect("real repair removes old damage",not view.statistics().damage_visible)
	damage.hp=0.0;damage.state_code="ruined";view.update_damage(damage,anchor,"b_wood_damage_detail")
	expect("ruin never gets a duplicate shell or damage plate",not view.statistics().damage_visible and view.get_child_count()==3 and view.find_children("*","CollisionObject3D",true,false).is_empty())
	damage.hp=50.0;damage.state_code="damaged"
	expect("unbound surface hides old marks instead of guessing material",not view.update_damage(damage,anchor,"b_wood_damaged") and not view.statistics().damage_visible and view.statistics().issues.damage=="DAMAGE_SURFACE_NOT_BOUND")
	damage.hp=101.0
	expect("invalid HP fails closed",not view.update_damage(damage,anchor,"b_wood_damage_detail"))
	view.update_construction({},anchor);view.update_damage({},anchor,"");view.hide_projection();view.hide_projection()
	expect("missing projections and repeated hide clear all activity",not view.statistics().construction_active and not view.statistics().damage_visible and view.statistics().issues.is_empty())
	host.free();await process_frame
	var result:Dictionary={"scope":"explicit condition DTO and original alpha-texture source tests; not actual owner integration or OS/VA","checks":checks,"failures":failures}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_FACTORY_CONDITION ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
