extends SceneTree
## Explicit DTO/lifecycle fixtures. No gameplay authority, renderer or VA.
const Hints=preload("res://scripts/presentation/factory_world_view_hints.gd")
const Factory=preload("res://scripts/presentation/factory_view.gd")
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
var checks:Array=[]
class TestWorld extends RefCounted:
	var revision:=7
	var id:="hint-world"
	func identity()->Dictionary:return {"worldId":id}
	func get_revision()->int:return revision
class Authority extends RefCounted:
	var world:RefCounted=TestWorld.new()
	func factory_snapshot()->Dictionary:return {"available":true,"schema":Contracts.SCHEMA,"version":Contracts.VERSION,"world_id":world.id,"modules":{"available":false}}
class Provider extends Node:
	var dto:Dictionary={}
	var enabled:=false
	var calls:Array=[]
	func view_hints()->Dictionary:return dto.duplicate(true)
	func set_view_hint_renderer(value:bool)->void:enabled=value;calls.append(value)
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func point(x:float,y:float,z:float)->Dictionary:return {"x":x,"y":y,"z":z}
func bounds()->Dictionary:return {"min":point(10,2,20),"max":point(16,5,24)}
func dto()->Dictionary:return {"schema":Hints.SCHEMA,"world_id":"hint-world","world_revision":7,"selected":{},"placement":{}}
func selected()->Dictionary:
	var value:=dto();value.selected={"id":"real-module","kind":"module","visible":true,"bounds":bounds()};return value
func placement(turn:int=0)->Dictionary:
	var value:=selected()
	value.placement={"active":true,"world_revision":7,"module_id":"planned-module","quarter_turn":turn,"request":{"kind":"module.plan","target_id":"planned-module","payload":{"definition_id":"actual-definition","quarter_turn":turn}},"preview":{"definition_id":"actual-definition","ok":true,"footprint":bounds(),"ports":[{"id":"input","purpose":"input","location":point(9,2,22),"normal":point(-1,0,0),"use_points":[point(8.4,2,22)]}],"conflicts":[]}}
	return value
func physical_count(node:Node)->int:
	var count:int=1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child:Node in node.get_children():count+=physical_count(child)
	return count
func mesh_ok(mesh:Mesh)->bool:
	for s:int in mesh.get_surface_count():
		var a:Array=mesh.surface_get_arrays(s);var v:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var n:PackedVector3Array=a[Mesh.ARRAY_NORMAL];var ix:PackedInt32Array=a[Mesh.ARRAY_INDEX]
		for j:int in range(0,ix.size(),3):
			var cross_value:Vector3=(v[ix[j+1]]-v[ix[j]]).cross(v[ix[j+2]]-v[ix[j]])
			if not v[ix[j]].is_finite() or cross_value.dot(n[ix[j]])>=0:return false
		var material:StandardMaterial3D=mesh.surface_get_material(s)
		if material.no_depth_test or material.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED:return false
	return true
func run()->void:
	var detached:Node3D=Hints.new()
	check("detached consumer fails closed without global transform errors",not detached.update(dto(),"hint-world",7));detached.free()
	var host:=Node3D.new();root.add_child(host);host.position=Vector3(500,40,-900);host.rotation.y=1.2
	var hints:Node3D=Hints.new();host.add_child(hints)
	check("valid empty DTO activates without geometry",hints.update(dto(),"hint-world",7) and not hints._selected.visible and not hints._placement.visible)
	var input:=selected();var saved:Dictionary=input.duplicate(true)
	check("visible actual selected bounds create corner brackets",hints.update(input,"hint-world",7) and hints.statistics().selected and hints._selected.mesh.get_surface_count()==1)
	check("transformed host does not retransform world anchors",hints.global_transform.is_equal_approx(Transform3D.IDENTITY) and hints._selected.mesh.get_aabb().position.distance_to(Vector3(9.9825,1.9825,19.9825))<.001)
	check("native triangle winding finite and depth tested",mesh_ok(hints._selected.mesh))
	check("hint geometry casts no fake scene shadows",hints._selected.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and hints._placement.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var mesh:Mesh=hints._selected.mesh;var updates:int=hints.statistics().updates
	hints.update(input,"hint-world",7)
	check("identical DTO keeps mesh identity",hints._selected.mesh==mesh and hints.statistics().updates==updates)
	input.world_revision=8;hints.update(input,"hint-world",8)
	check("revision advance alone does not rebuild unchanged geometry",hints._selected.mesh==mesh and hints.statistics().updates==updates)
	input=selected();input.selected.visible=false;input.selected.erase("bounds");hints.update(input,"hint-world",7)
	check("hidden selection removes all corners without demanding hidden bounds",not hints._selected.visible and hints._selected.mesh==null)
	for kind:String in ["module","water","npc","container"]:
		input=selected();input.selected.kind=kind;check("supported selected identity "+kind,hints.update(input,"hint-world",7))
	for turn:int in 4:
		input=placement(turn);check("rotated request uses exact public geometry "+str(turn),hints.update(input,"hint-world",7) and hints.statistics().ports==1 and mesh_ok(hints._placement.mesh))
	check("DTO caller bytes remain unmodified",saved==selected())
	input=placement();input.placement.preview.ok=false;input.placement.preview.reason="opaque unknown conflict";hints.update(input,"hint-world",7)
	check("reason only conflict does not invent a marker",hints.statistics().conflicts==0 and hints.statistics().placement)
	input.placement.preview.conflicts=[{"entity_id":"unknown"},{"point":point(8,2,22)},{"bounds":bounds()}];hints.update(input,"hint-world",7)
	check("only exact supplied conflict point or bounds draws",hints.statistics().conflicts==2)
	input=placement();input.placement.preview.ports[0].clearance={"radius":1.1,"height":1.8}
	hints.update(input,"hint-world",7)
	check("service pad follows public clearance radius instead of fixed extent",absf(hints._placement.mesh.get_aabb().position.x-7.8775)<.001,hints._placement.mesh.get_aabb())
	var invalid:Dictionary={}
	input=placement();input.world_id="other";invalid.world=input
	input=placement();input.world_revision=6;invalid.stale=input
	input=placement();input.placement.world_revision=6;invalid.stale_placement=input
	input=placement();input.placement.request.payload.quarter_turn=3;invalid.request_turn=input
	input=placement();input.placement.preview.ports[0].location.x=NAN;invalid.nan_port=input
	input=placement();input.placement.preview.ports.append(input.placement.preview.ports[0]);invalid.duplicate_port=input
	input=selected();input.selected.bounds.max.x=input.selected.bounds.min.x;invalid.zero_box=input
	input=selected();input.selected.kind="hidden-unowned-kind";invalid.kind=input
	for key:String in invalid:
		hints.update(placement(),"hint-world",7)
		check("invalid clears all old geometry "+key,not hints.update(invalid[key],"hint-world",7) and not hints._selected.visible and not hints._placement.visible)
	hints.update(placement(),"hint-world",7);hints.update(dto(),"hint-world",7)
	check("cancel clears preview and selection",hints._placement.mesh==null and hints._selected.mesh==null)
	check("hint nodes never add colliders",physical_count(hints)==0)
	var authority:=Authority.new();var factory:Node3D=Factory.new();root.add_child(factory);factory.set_process(false);factory.configure(authority)
	var provider:=Provider.new();root.add_child(provider);provider.dto=placement();factory.configure_view_hints(provider)
	check("real factory entry disables ghost only after helper succeeds",provider.enabled and factory._hints.statistics().placement)
	var other:=Provider.new();root.add_child(other);other.dto=selected();factory.configure_view_hints(other)
	check("provider replacement releases previous fallback",not provider.enabled and other.enabled)
	other.dto.world_id="wrong";factory.sync()
	check("invalid provider restores fallback and clears mesh",not other.enabled and not factory._hints.statistics().placement and not factory._hints.statistics().selected)
	other.dto=selected();factory.sync();other.free();factory.sync()
	check("freed weak provider clears without dangling object",not factory._hint_renderer and not factory._hints.statistics().selected)
	factory.configure_view_hints(provider);factory.configure(null)
	check("runtime detach restores original provider fallback",not provider.enabled and not factory._hints.statistics().placement)
	factory.configure(authority);factory.configure_view_hints(provider);authority.world=TestWorld.new();authority.world.id="replacement";factory.sync()
	check("new authority world rejects old world hints",not provider.enabled and not factory._hints.statistics().selected)
	authority.world.id="hint-world";factory.sync();factory.free()
	check("consumer exit releases replacement rendering",not provider.enabled)
	provider.free();host.free()
	var failed:Array=checks.filter(func(c:Dictionary)->bool:return not c.ok)
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failed},"\t"))
	print("WORLD_HINTS "+str(checks.size())+" / failures "+str(failed.size()));quit(0 if failed.is_empty() else 1)
