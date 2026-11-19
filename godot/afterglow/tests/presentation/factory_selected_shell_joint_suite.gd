extends "res://tests/modules/factory_boundary_fixture.gd"
## A's corrected shell selection only. Does not rerun prior placement probes.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Direct=preload("res://scripts/input/direct_interaction.gd")
const FactoryView=preload("res://scripts/presentation/factory_view.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
class Sidebar extends Control:
	var selected:Dictionary={}
	func world_view_selection()->Dictionary:return selected.duplicate(true)
func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("actual C6 selected shell prepares",opening.ok,opening.get("reason"))
	if not opening.ok:finish();return
	var mounted:Dictionary=mount(opening.capture,"selected shell Native")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var modules:RefCounted=mounted.services.modules
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	var policy:=Policy.new();policy.configure(mounted.services.buildings.current_space());policy.sample(G.location(rt.actor("player")))
	var ui:=Sidebar.new();root.add_child(ui)
	var interaction:Node=Direct.new();root.add_child(interaction);interaction.set_process(false)
	interaction.runtime=rt;interaction.world=rt.world;interaction.modules=modules;interaction.buildings=mounted.services.buildings;interaction.camera=camera;interaction.ui=ui;interaction.view_policy=policy
	var factory:Node3D=FactoryView.new();root.add_child(factory);factory.set_process(false);factory.configure(rt);factory.configure_view_hints(interaction)
	var original:Dictionary=rt.capture_checkpoint();var samples:Array=[]
	for target:Dictionary in modules.projection().instances:
		var entity:Dictionary=rt.world.entity(str(target.id));var focus:Vector3=G.aabb(entity.bounds).get_center()
		camera.position=focus+Vector3(18,23,26);camera.look_at(focus)
		ui.selected={"kind":"module","id":target.id};var dto:Dictionary=interaction.view_hints();factory.sync()
		check("known real shell now yields exact positive "+str(target.id),dto.selected.get("id")==target.id and dto.selected.visible and Data.json_equal(dto.selected.bounds,entity.bounds),dto.selected)
		check("D positive actual selected mesh retains world bounds "+str(target.id),factory._hints.statistics().selected and factory._hints.global_transform.is_equal_approx(Transform3D.IDENTITY) and factory._hints._selected.mesh.get_aabb().get_center().distance_to(focus)<.001)
		var mat:StandardMaterial3D=factory._hints._selected.mesh.surface_get_material(0)
		check("positive remains depth tested "+str(target.id),not mat.no_depth_test)
		camera.look_at(camera.position+(camera.position-focus));factory.sync()
		check("camera-hidden selected shell removes corners "+str(target.id),not factory._hints.statistics().selected)
		samples.append({"id":target.id,"dto":dto.selected,"actual_bounds":entity.bounds})
	ui.selected={"kind":"module","id":"never-discovered"};factory.sync()
	check("unknown module still has no rendered selection",not factory._hints.statistics().selected)
	check("all selected refreshes preserve actual authority",Data.json_equal(original,rt.capture_checkpoint()))
	evidence.append({"scope":"post22 A corrected owner+shell scope and D depth-tested corners; explicit camera/sidebar fixture only; no normal gameplay or VA","positive_samples":samples})
	factory.free();interaction.free();ui.free();camera.free();finish()
