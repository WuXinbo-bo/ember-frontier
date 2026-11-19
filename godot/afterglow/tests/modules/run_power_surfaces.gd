extends "res://tests/modules/run_factory_lifecycle.gd"
const BuildingView=preload("res://scripts/buildings/building_view.gd")
var checked_power:=false
func advance(rt:RefCounted,services:Dictionary,steps:int,domain:String)->void:
	super.advance(rt,services,steps,domain)
	if checked_power:return
	var module:Dictionary=services.modules.instance("r34:test-built-woodshop")
	if module.get("status")!="operational":return
	checked_power=true
	var original:Dictionary=rt.capture_checkpoint();var host:=Native.new();var built:Dictionary=host._assemble(original)
	check("paid physical machine cold restores for actual surface consumer",built.ok)
	if not built.ok:host.free();return
	var view:=BuildingView.new();root.add_child(view);view.configure({"service":built.services.buildings,"runtime":built.runtime})
	var count:int=0
	for member:Dictionary in module.members:
		var housing:bool=member.id.ends_with(":part:fixed-power") or member.id.ends_with(":part:fixed-power-housing")
		var base:bool=member.id.ends_with(":part:power-base")
		if not housing and not base:continue
		count+=1
		var entity:Dictionary=built.world.entity(member.id);var node:MeshInstance3D=view.objects.get(member.id)
		check("original fixed part ID is truly consumed "+member.id,node!=null and node.mesh!=null)
		if node==null or node.mesh==null:continue
		var selected:StandardMaterial3D=node.mesh.surface_get_material(0)
		var surface:String="drive_paint" if housing else "drive_rust"
		var file:String="drive_painted_iron_1m.png" if housing else "drive_rust_iron_1m.png"
		var expected_sha:String="1227519bb71ff73c0adac6a71d725922a3935541338e7e493ab8bac98855d102" if housing else "a2e695cc1225b24bdc535ae994695c95eec161d29896b703e7b326f5f878b4ea"
		var path:String="res://data/factory/surfaces/production-v1/"+file
		check("exact existing image bound at 1m "+member.id,selected!=null and selected.get_meta("production_surface","")==surface and selected.get_meta("source_resource","")==path and selected.get_meta("tile_meters",0)==1.0 and selected.texture_repeat and FileAccess.get_sha256(path)==expected_sha)
		var arrays:Array=node.mesh.surface_get_arrays(0);var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var size:Vector3=G.point(entity.data.module_part.size);var metric:bool=true
		for face:int in 6:
			var normal:Vector3=normals[face*4]
			var extent:Vector2=Vector2(size.x,size.z) if absf(normal.y)>0.5 else Vector2(size.z,size.y) if absf(normal.x)>0.5 else Vector2(size.x,size.y)
			metric=metric and (uv[face*4+2]-uv[face*4]).abs().is_equal_approx(extent)
		check("all six actual mesh faces use metres not old 2m UV "+member.id,metric)
		check("surface keeps exact pinned physical box "+member.id,node.mesh.get_aabb().is_equal_approx(AABB(Vector3.ZERO,size)) and node.get_meta("piece").data.module_geometry_version==module.geometry_version)
	check("only existing fixed assembly housing and base retargeted",count==2)
	var leg:MeshInstance3D=view.objects.get(module.id+":part:saw-leg:-0.57")
	check("moving saw and structural metal are not globally painted",leg!=null and leg.mesh.surface_get_material(0)==view.material("painted_metal"))
	check("source authority remains exact after loading surfaces",Data.json_equal(original,rt.capture_checkpoint()))
	var damage:Dictionary=built.runtime._commit(built.services.modules.prepare_damage(module.id,1000,"B:power-surface:destroy"))
	check("actual destruction removes painted machine parts too",damage.ok and not view.objects.has(module.id+":part:fixed-power") and not view.objects.has(module.id+":part:fixed-power-housing") and not view.objects.has(module.id+":part:power-base"))
	view.free();host.free()
func finish()->void:
	check("surface inspected on actual paid operational machine",checked_power)
	super.finish()
