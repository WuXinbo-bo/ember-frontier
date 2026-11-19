extends "res://tests/modules/factory_boundary_fixture.gd"
## Headless geometry/material-call coverage only; not rendered visual acceptance.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Facade=preload("res://scripts/buildings/module_facade_detail.gd")
class ProbeView extends Node3D:
	var service:RefCounted
	var materials:Array=[]
	func material(id:String)->void:materials.append(id)
class ProbeBuilder extends RefCounted:
	var boxes:Array=[]
	func box(bounds:AABB,pose:Transform3D,material:String,density:float)->void:
		boxes.append({"bounds":bounds,"pose":pose,"material":material,"density":density})
func run()->void:
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[4]))
	for d:Dictionary in old.definitions:
		var current:Dictionary=Modules.definition(d.id)
		check("old pinned definition remains identical "+str(d.id),Data.json_equal(d,current))
		check("old physical parts remain identical "+str(d.id),Data.json_equal(Shape.parts(d),Shape.parts(current)))
	var profiles:Array=Modules.generation_profiles();var contract:Dictionary=Contract.fresh(profiles,7,1)
	var prepared:Dictionary=Assembly.prepare(Generator.generate(713,profiles,contract.contract))
	check("actual content7 for additive rear-store skin",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish();return
	var mounted:=mount(prepared.capture,"real store geometry skin");if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var ms:RefCounted=mounted.services.modules
	var store:Dictionary=ms.state().instances.filter(func(v:Dictionary)->bool:return v.definition_id=="r34.module.supply_rear_v3")[0]
	var before:Dictionary=rt.capture_checkpoint();var view:=ProbeView.new();view.service=mounted.services.buildings
	var walls:int=0
	for member:Dictionary in store.members:
		if not member.id.ends_with(":rear") and not member.id.ends_with(":side:1.0") and not member.id.ends_with(":side:-1.0"):continue
		var entity:Dictionary=rt.world.entity(member.id);var builder:=ProbeBuilder.new()
		var added:bool=Facade.add(view,builder,entity)
		check("new profile retains closed facade detail "+str(member.id),added and not builder.boxes.is_empty())
		check("facade only emits finite opaque material geometry "+str(member.id),builder.boxes.all(func(b:Dictionary)->bool:return b.bounds.has_volume() and b.pose.is_finite() and b.material in ["old_brick","painted_metal","b_wood_aged"] and b.density==1.2))
		walls+=1
	check("all three true rear and side planes receive facade",walls==3,walls)
	check("new real rear hatch is an owned physical part",store.members.any(func(m:Dictionary)->bool:return m.id.ends_with(":rear-receiving-hatch")))
	check("derived skin leaves physical geometry inventory and source untouched",Data.json_equal(before,rt.capture_checkpoint()))
	view.free();finish()
