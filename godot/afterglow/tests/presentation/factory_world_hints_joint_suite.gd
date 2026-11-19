extends "res://tests/modules/factory_boundary_fixture.gd"
## Actual C6/Native/B preview/A interaction DTO consumed by D. Explicit camera
## and sidebar/router fixture only; no gameplay traversal or VA claim.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Direct=preload("res://scripts/input/direct_interaction.gd")
const FactoryView=preload("res://scripts/presentation/factory_view.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
class Sidebar extends Control:
	var selected:Dictionary={}
	func world_view_selection()->Dictionary:return selected.duplicate(true)
class HintRouter extends Node:
	var mode:="module_place"
	func state()->Dictionary:return {"mode":mode,"module_definition_id":"r34.module.fuel_woodshop"}
	func held_reference()->Dictionary:return {}
func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var opened:Dictionary=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("actual C6 generation prepares",opened.ok,opened.get("reason"))
	if not opened.ok:finish();return
	var mounted:Dictionary=mount(opened.capture,"actual hint authority")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var modules:RefCounted=mounted.services.modules
	var rows:Array=modules.projection().instances
	var target:Dictionary=rows[0];var entity:Dictionary=rt.world.entity(str(target.id))
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	var focus:Vector3=G.aabb(entity.bounds).get_center();camera.position=focus+Vector3(18,23,26);camera.look_at(focus)
	var ui:=Sidebar.new();root.add_child(ui);ui.selected={"kind":"module","id":target.id}
	var router:=HintRouter.new();root.add_child(router)
	var policy:=Policy.new();policy.configure(mounted.services.buildings.current_space());policy.sample(G.location(rt.actor("player")))
	var interaction:Node=Direct.new();root.add_child(interaction);interaction.set_process(false)
	interaction.runtime=rt;interaction.world=rt.world;interaction.modules=modules;interaction.buildings=mounted.services.buildings;interaction.camera=camera;interaction.ui=ui;interaction.router=router;interaction.view_policy=policy
	var ghost:=MeshInstance3D.new();root.add_child(ghost);interaction._ghost=ghost
	var factory:Node3D=FactoryView.new();root.add_child(factory);factory.set_process(false);factory.configure(rt)
	var raw:Dictionary=interaction.view_hints()
	check("A selection uses actual owner and room-policy result",raw.selected.is_empty() or (raw.selected.id==target.id and Data.json_equal(raw.selected.bounds,entity.bounds)),raw.selected)
	factory.configure_view_hints(interaction)
	check("A provider real entry enables D replacement",interaction._view_hint_renderer and factory._hints.statistics().available)
	var point:Vector3=G.point(target.location);var snapshots:Array=[]
	for turn:int in 4:
		interaction._quarter=turn;interaction._point={"distance":10.0}
		interaction._update_module_preview(point+Vector3.UP*10,Vector3.DOWN)
		raw=interaction.view_hints();factory.sync()
		var preview:Dictionary=modules.preview(raw.placement.request)
		check("actual B preview passed unchanged through A turn "+str(turn),Data.json_equal(raw.placement.preview,preview) and raw.placement.quarter_turn==turn and factory._hints.statistics().placement)
		check("actual B services and conflicts consumed exactly turn "+str(turn),factory._hints.statistics().ports==preview.ports.size() and factory._hints.statistics().conflicts==preview.get("conflicts",[]).size(),preview)
		check("real ghost suppressed only by working replacement turn "+str(turn),not ghost.visible and interaction._view_hint_renderer)
		snapshots.append(raw)
	var original:Dictionary=rt.capture_checkpoint();factory.sync();factory.sync()
	check("D sync never changes actual world or facts",Data.json_equal(original,rt.capture_checkpoint()))
	for id:String in ["unavailable-object",str(modules.state().instances[-1].id)]:
		ui.selected={"kind":"module","id":id};factory.sync()
		check("actual unknown sidebar module has no corner "+id,not factory._hints.statistics().selected)
	var water_id:String=str(modules.state().water.sources[0].id)
	ui.selected={"kind":"water","id":water_id};factory.sync()
	check("actual undiscovered finite water has no selected bounds",not factory._hints.statistics().selected)
	router.mode="tool";factory.sync()
	check("actual router cancellation clears placement",not factory._hints.statistics().placement)
	interaction._placement_view_hint.world_revision=-1;router.mode="module_place";factory.sync()
	check("actual A stale preview withheld",not factory._hints.statistics().placement)
	factory.configure_view_hints(null)
	interaction._update_module_preview(point+Vector3.UP*10,Vector3.DOWN)
	check("detached renderer restores actual legacy ghost",not interaction._view_hint_renderer and ghost.visible)
	evidence.append({"scope":"actual C6 B preview and A view_hints with real policy; fixture camera/sidebar/router, no simulated route or VA","raw_turns":snapshots})
	factory.free();interaction.free();ui.free();router.free();camera.free();finish()
