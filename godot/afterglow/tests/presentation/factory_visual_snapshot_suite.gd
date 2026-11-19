extends SceneTree
## D hook-only consumer. Runtime projection equality/purity and costs belong to A.
const View=preload("res://scripts/presentation/factory_view.gd")
const Fixture=preload("res://tests/presentation/factory_consumer_suite.gd")
const Water=preload("res://scripts/presentation/factory_water_view.gd")

class BaseAuthority extends RefCounted:
	var world:=RefCounted.new()
	var dto:Dictionary={}
	var full_calls:=0
	var visual_calls:=0
	var paused:=false
	func is_paused()->bool:return paused

class LegacyAuthority extends BaseAuthority:
	func factory_snapshot()->Dictionary:
		full_calls+=1
		return dto.duplicate(true)

class PreferredAuthority extends LegacyAuthority:
	func factory_visual_snapshot()->Dictionary:
		visual_calls+=1
		return dto.duplicate(true)

class VisualOnlyAuthority extends BaseAuthority:
	func factory_visual_snapshot()->Dictionary:
		visual_calls+=1
		return dto.duplicate(true)

class InvalidAuthority extends LegacyAuthority:
	func factory_visual_snapshot()->Variant:
		visual_calls+=1
		return 42

var checks:Array=[]
func _initialize()->void:call_deferred("run")
func expect(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL ",label," ",detail)

func make_view(authority:RefCounted)->Node3D:
	var view:=View.new();root.add_child(view);view.set_process(false);view.configure(authority)
	return view

func run()->void:
	var preferred:=PreferredAuthority.new();preferred.dto=Fixture.snapshot()
	preferred.dto.water={"available":true,"sources":[{"id":"fixture-water","discovered":true,"status":"ready","remaining":32,"project_id":"draw1","location":{"x":12.0,"y":1.0,"z":8.0}}],"projects":[{"id":"draw1","source_id":"fixture-water","actor_id":"player","operation":"draw","progress_seconds":.25,"duration_seconds":12.0,"effective_work":.1,"status":"active","paused_reason":""}]}
	var entity:Dictionary={"id":"fixture-water","kind":"prop","position":{"x":12.0,"y":1.0,"z":8.0},"data":{"water_source_id":"fixture-water","water_use_point":{"x":13.2,"y":1.5,"z":8.0}}}
	var water:Node3D=Water.create_fixture(entity,preferred.world.get_instance_id());root.add_child(water)
	var source:Dictionary=preferred.dto.duplicate(true)
	var view:Node3D=make_view(preferred)
	expect("both APIs choose visual exactly once and never full",preferred.visual_calls==1 and preferred.full_calls==0)
	expect("original module stock and machinery still mount",view._roots.size()==2 and view._buffers.a.wood.statistics().actual==5.0 and view._machines.a.statistics().active and view.statistics().required_errors.is_empty(),view.statistics())
	expect("original water DTO still drives actual fixture",water.get_meta("water_state")=="ready" and water.get_node("Assembly/stream").visible)
	var legacy:=LegacyAuthority.new();legacy.dto=source.duplicate(true)
	var old_view:Node3D=make_view(legacy)
	expect("old Runtime retains original no-argument fallback",legacy.full_calls==1 and legacy.visual_calls==0)
	expect("identical DTO retains identical full display statistics",view.statistics()==old_view.statistics(),{"visual":view.statistics(),"legacy":old_view.statistics()})
	var module_id:int=view._roots.a.get_instance_id();var stock:Node3D=view._buffers.a.wood
	var part_id:int=stock.get_child(0).get_instance_id();var mesh_id:int=stock.get_child(0).mesh.get_instance_id()
	view.sync()
	expect("unchanged sync keeps geometry and skips reapplication",view._roots.a.get_instance_id()==module_id and stock.get_child(0).get_instance_id()==part_id and stock.get_child(0).mesh.get_instance_id()==mesh_id and view.statistics().updates==2)
	var calls:int=preferred.visual_calls
	view._delay=0;view._process(0);view._process(.04)
	expect("original 100ms poll does not query before due",preferred.visual_calls==calls+1 and is_equal_approx(view._delay,.06))
	view._process(.061)
	expect("original 100ms poll queries on due",preferred.visual_calls==calls+2 and is_equal_approx(view._delay,.1) and preferred.full_calls==0)
	preferred.paused=true;view.sync()
	expect("pause still suppresses water motion",not water.get_node("Assembly/stream").visible)
	preferred.paused=false;view.sync()
	expect("resume still follows true effective water job",water.get_node("Assembly/stream").visible)
	expect("all sync and poll reads leave supplied DTO unchanged",preferred.dto==source)
	preferred.dto.modules.instances[0].detailed=false;view.sync()
	expect("non-detailed modules remain hidden",not view._roots.has("a") and view._roots.has("b"))
	preferred.dto=source.duplicate(true);view.sync();module_id=view._roots.a.get_instance_id()
	preferred.world=RefCounted.new();view.sync()
	expect("same Runtime new world object still invalidates same-ID roots",view._roots.a.get_instance_id()!=module_id)
	preferred.dto.available=false;view.sync()
	expect("unavailable light DTO clears without invoking full",view._roots.is_empty() and not view.statistics().available and preferred.full_calls==0)
	var light_only:=VisualOnlyAuthority.new();light_only.dto=source.duplicate(true);view.configure(light_only)
	expect("visual-only Runtime is accepted",view.statistics().available and light_only.visual_calls==1 and view._roots.size()==2)
	var invalid:=InvalidAuthority.new();invalid.dto=source.duplicate(true);view.configure(invalid)
	expect("malformed light DTO fails closed without full fallback",invalid.visual_calls==1 and invalid.full_calls==0 and not view.statistics().available and view.statistics().required_errors==[{"code":"FACTORY_DTO_REQUIRED"}])
	view.configure(RefCounted.new())
	expect("missing APIs clear existing display",not view.statistics().available and view._roots.is_empty())
	view.configure(null)
	expect("null Runtime stays safely unavailable",not view.statistics().available and view._roots.is_empty())
	view.free();old_view.free();water.free()
	await process_frame
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify({"scope":"D bounded hook-only source consumer with explicit public DTO fixtures; not Runtime equivalence/purity, native gameplay, PCK, OS, VA, performance or FPS","checks":checks,"failed":failed},"\t"));file.close()
	print("FACTORY_VISUAL_HOOK checks=",checks.size()," failed=",failed)
	quit(1 if failed else 0)
