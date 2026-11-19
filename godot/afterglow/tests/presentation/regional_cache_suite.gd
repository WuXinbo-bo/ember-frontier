extends SceneTree
const Planning=preload("res://scripts/presentation/planning_visual.gd")
const Ecology=preload("res://scripts/presentation/ecology_visual.gd")
class EcologyProvider extends RefCounted:
	var queries:int=0
	var basis:Dictionary={"available":true,"ecology_revision":1,"world_revision":1,"resident_revision":1,"actor_location":[0,0,0]}
	func presentation_basis(_actor:String)->Dictionary:return basis.duplicate(true)
	func presentation_projection(_actor:String)->Dictionary:queries+=1;return {"available":true,"visuals":[]}
class Authority extends RefCounted:
	var world:RefCounted=RefCounted.new()
	var queries:int=0
	var ecology:RefCounted=EcologyProvider.new()
	var basis:Dictionary={"available":true,"zones_revision":1,"zones_generation":{"authority":1,"generation":1,"extension":1},"world_revision":1,"work_revision":1}
	func zone_view_basis(_actor:String)->Dictionary:
		var result:Dictionary=basis.duplicate();result.world_generation=world.get_instance_id();result.runtime_generation=get_instance_id();return result
	func zone_projection(_actor:String,_zone:String)->Dictionary:queries+=1;return {"available":basis.available,"schema":"afterglow-work-zones-v1","selection":{}}
	func domain_service(_name:String)->Variant:return ecology
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var rt:=Authority.new();var plan:=Planning.new();root.add_child(plan);plan.set_process(false);plan.configure(rt)
	for i:int in 100:plan.sync()
	expect("unchanged scalar basis causes just one full zone projection",rt.queries==1)
	rt.basis.world_revision=99;rt.basis.work_revision=200;plan.sync()
	expect("unrelated world and labor revision does not copy zone records",rt.queries==1)
	plan.set_selected("zone:2")
	expect("new selected identity queries exact selection",rt.queries==2)
	rt.basis.zones_revision=2;plan.sync()
	expect("real zone revision invalidates exact selection",rt.queries==3)
	rt.basis.zones_generation.extension=2;plan.sync()
	expect("same persisted revision successful extension set invalidates by authority token",rt.queries==4)
	rt.basis.available=false;plan.sync()
	expect("availability changes discard stale zone",rt.queries==5 and plan.statistics().chunks==0)
	var view:=Ecology.new();root.add_child(view);view.set_process(false);view.configure(rt)
	for i:int in 100:view.sync()
	expect("stable owner visibility basis pulls ecology once",rt.ecology.queries==1)
	rt.ecology.basis.actor_location=[1,0,0];view.sync()
	expect("actual player movement rechecks visible ecology",rt.ecology.queries==2)
	rt.ecology.basis.world_revision=2;view.sync()
	expect("wall spatial change rechecks visibility despite same growth",rt.ecology.queries==3)
	rt.ecology.basis.resident_revision=2;view.sync()
	expect("resident disclosure change cannot reuse stale ecology",rt.ecology.queries==4)
	rt.ecology.basis.available=false;view.sync()
	expect("unavailable ecology retires batches without full projection",not view.statistics().available and rt.ecology.queries==4)
	rt.ecology.basis.available=true;view.sync()
	expect("availability return fetches real provider again",rt.ecology.queries==5)
	rt.world=RefCounted.new();plan.sync();view.sync()
	expect("world generation invalidates both consumers",rt.queries==6 and rt.ecology.queries==6)
	plan.free();view.free();await process_frame
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"scope":"finite scalar-basis invalidation consumer; not actual C cache authority/OS/VA/FPS","checks":checks,"failures":failures},"\t"))
	print("DDD_REGIONAL_CACHE ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
