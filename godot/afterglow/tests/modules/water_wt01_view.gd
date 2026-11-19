extends "res://tests/modules/factory_boundary_fixture.gd"
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const WaterView=preload("res://scripts/presentation/factory_water_view.gd")
func run()->void:
	var profiles:Array=Modules.generation_profiles();var prepared:=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("actual C6/B registered source",prepared.ok)
	if not prepared.ok:finish();return
	var assembled:=mount(prepared.capture,"actual source for B entity branch")
	if not assembled.ok:finish();return
	var rt:RefCounted=assembled.runtime;var ms:RefCounted=assembled.services.modules;var before:Dictionary=rt.capture_checkpoint()
	var src:Dictionary=ms.state().water.sources[0];var entity:Dictionary=rt.world.entity(src.id)
	var view:=View.new();view.service=assembled.services.buildings;root.add_child(view)
	view.sync_entity_object(src.id,entity)
	check("original B entity branch creates one actual fixture",view.objects.size()==1 and view.get_child_count()==1 and view.objects[src.id].has_node("Assembly/body"))
	var old:Node3D=view.objects[src.id];var forward:=G.point(src.use_point)-G.point(src.position);forward.y=0;forward=forward.normalized()
	check("one actual fixture bound to authoritative world/source",old.get_meta("world_instance")==rt.world.get_instance_id() and old.get_meta("water_source_id")==src.id and old.position==G.point(src.position))
	check("actual nozzle assembly faces C real use point",(old.get_node("Assembly").transform.basis*Vector3(0,0,1)).is_equal_approx(forward))
	view.sync_entity_object(src.id,entity)
	check("resync frees old projection and keeps one body",not is_instance_valid(old) and view.objects.size()==1 and view.get_child_count()==1)
	var actual:Node3D=view.objects[src.id]
	WaterView.apply_public(actual,ms.water_projection())
	check("unknown projection keeps actual apparatus opaque balance",actual.get_meta("water_state")=="unknown" and not actual.get_node("Assembly/stream").visible)
	view.sync_entity_object(src.id,{})
	check("missing/removed entity frees unique derived fixture",view.objects.is_empty() and view.get_child_count()==0)
	check("geometry/nozzle projection never changes authoritative source",Data.json_equal(before,rt.capture_checkpoint()))
	# Output capacity uses the real registered home buffer definition. Only
	# the candidate project's remote output is injected into a local Draft;
	# this verifies accounting, never claims remote water work was permitted.
	var prod:RefCounted=assembled.services.production;var tx:=Draft.new(ms.context);var home:Dictionary=ms.state().instances.filter(func(v:Dictionary)->bool:return Modules.definition(v.definition_id).shape=="home")[0]
	var sid:String=home.stock_refs.supplies;var spec:Dictionary=Factory.spec(prod,sid,tx);var limit:float=spec.limits.water
	tx.stock(sid).items["water"]=limit-1
	check("real module buffer has room for exact last water",prod.capacity_check(sid,{"water":1},"",tx).ok)
	tx.extension(Modules.KEY).water.projects.append({"id":"B:water:capacity-fixture","status":"active","operation":"draw","output_id":sid,"source_id":src.id,"actor_id":"player","material_source_id":"","cost":{},"tool_id":""})
	check("one real water project accounts for exact output promise",prod.capacity_reserved(sid,"water","",tx)==1)
	check("second water promise sees full buffer",prod.capacity_check(sid,{"water":1},"",tx).get("code")=="BUFFER_FULL")
	check("own promise exclusion permits only its reserved last unit",prod.capacity_check(sid,{"water":1},"B:water:capacity-fixture",tx).ok)
	check("capacity fixture is uncommitted and leaves authority unchanged",Data.json_equal(before,rt.capture_checkpoint()))
	view.free();finish()
