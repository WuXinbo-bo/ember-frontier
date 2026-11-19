extends "res://tests/modules/factory_boundary_fixture.gd"
## Real source-world selection; no renderer, traversal or package claim.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Interaction=preload("res://scripts/input/direct_interaction.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")

class Sidebar extends Control:
	var selection:Dictionary={}
	func world_view_selection()->Dictionary:return selection.duplicate(true)

class Router extends Node:
	func state()->Dictionary:return {"mode":"tool"}

func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var created:Dictionary=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("current content6 actual world prepares",created.ok,created.get("reason"))
	if not created.ok:finish();return
	var mounted:Dictionary=mount(created.capture,"source selection world")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var service:RefCounted=mounted.services.modules
	var rows:Array=service.projection().instances
	check("real owner exposes home module identities",not rows.is_empty())
	if rows.is_empty():finish();return
	var camera:=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	var sidebar:=Sidebar.new();root.add_child(sidebar)
	var router:=Router.new();root.add_child(router)
	var policy:=Policy.new();policy.configure(mounted.services.buildings.current_space());policy.sample(G.location(rt.actor("player")))
	var interaction:=Interaction.new();root.add_child(interaction);interaction.set_process(false)
	interaction.runtime=rt;interaction.world=rt.world;interaction.modules=service;interaction.buildings=mounted.services.buildings;interaction.camera=camera;interaction.ui=sidebar;interaction.router=router;interaction.view_policy=policy
	var before:Dictionary=rt.capture_checkpoint()
	for row:Dictionary in rows:
		var entity:Dictionary=rt.world.entity(str(row.id));var focus:Vector3=G.aabb(entity.bounds).get_center()
		camera.position=focus+Vector3(18,23,26);camera.look_at(focus)
		sidebar.selection={"kind":"module","id":row.id}
		var hint:Dictionary=interaction.view_hints().selected
		check("known outdoor aggregate survives its own shell "+str(row.id),hint.get("id")==row.id and hint.get("bounds")==entity.bounds and hint.get("visible",false),hint)
		if hint.has("bounds"):
			hint.bounds.min.x=99999
			check("real selection remains a detached projection "+str(row.id),interaction.view_hints().selected.get("bounds")==entity.bounds)
		camera.rotate_y(PI)
		check("off-camera selection does not request a visible outline "+str(row.id),interaction.view_hints().selected.get("visible")==false)
	for instance:Dictionary in service.state().instances:
		if rows.any(func(row:Dictionary)->bool:return row.id==instance.id):continue
		sidebar.selection={"kind":"module","id":instance.id}
		check("actual undiscovered module has no selected geometry "+str(instance.id),interaction.view_hints().selected.is_empty())
	var unknown_stocks:Array=rt.facts().stocks.filter(func(stock:Dictionary)->bool:return not stock.get("searched",false))
	check("real source has unsearched inventory counterexample",not unknown_stocks.is_empty())
	if not unknown_stocks.is_empty():
		sidebar.selection={"kind":"container","id":unknown_stocks[0].id}
		check("shell exception cannot reveal unsearched container",interaction.view_hints().selected.is_empty())
	sidebar.selection={"kind":"module","id":"missing:module"}
	check("unknown entity stays absent",interaction.view_hints().selected.is_empty())
	check("selection never changes authority or discovery",Data.json_equal(before,rt.capture_checkpoint()))
	rt.retire()
	check("world retirement removes the selected hint",interaction.view_hints().selected.is_empty())
	interaction.free();sidebar.free();router.free();camera.free();finish()
