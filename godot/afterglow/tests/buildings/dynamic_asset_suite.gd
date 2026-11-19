extends "res://tests/buildings/family_generation_suite.gd"
## Real C operations -> Runtime signal -> B actual GLBs. No preview/import.
func put_entity(value:Dictionary)->Dictionary:
	var before:Dictionary=world.entity(value.id)
	return runtime._commit({"ok":true,"world_changes":[{"op":"entity.put","id":value.id,"before_exists":not before.is_empty(),"before":before if not before.is_empty() else null,"after":value}],"fact_changes":[]})

func mesh_count(node:Node)->int:
	var count:=1 if node is MeshInstance3D and node.mesh!=null else 0
	for child:Node in node.get_children():count+=mesh_count(child)
	return count

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("retained C generated world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seed:Dictionary=building.seed_rural(world)
	var prepared:Dictionary=world.prepare_changes(seed.world_changes,world.get_revision())
	expect("existing structures seed through sole C capability",prepared.ok and world.commit_prepared(prepared.capability).ok)
	initialize_at(Geometry.location(runtime.actor("player")),[],seed.initial_stocks)
	expect("normalize optional ledger through actual runtime",runtime._commit({"ok":true,"world_changes":[],"fact_changes":[]}).ok)
	var view:Node3D=building.create_view({"runtime":runtime})
	view.set_view_policy(preload("res://scripts/presentation/interior_view_policy.gd").new())
	var before_facts:=runtime.facts();var static_ids:Dictionary={}
	for key:String in view.static_nodes:static_ids[key]=view.static_nodes[key].get_instance_id()
	var entity:Dictionary={"id":"fixture:dynamic-chair","kind":"prop","regionId":"RH-HOME","position":{"x":32.0,"y":0.0,"z":43.0},"bounds":{"min":{"x":31.7,"y":0.0,"z":42.7},"max":{"x":32.3,"y":0.9,"z":43.3}},"revision":0,"data":{"assetId":"city_chair","solid":false,"opaque":false,"quarterTurn":0}}
	expect("ordinary new asset entity commits",put_entity(entity).ok)
	var first:Node3D=view.objects.get(entity.id)
	expect("new ordinary entity instantiates real approved GLB",first!=null and mesh_count(first)>0 and view.models.has("city_chair"))
	entity=entity.duplicate(true);entity.data.assetId="city_table";entity.data.quarterTurn=1;entity.position.x=33.0;entity.bounds.min.x+=1;entity.bounds.max.x+=1;entity.revision+=1
	expect("asset transform and quarter turn update commits",put_entity(entity).ok)
	var second:Node3D=view.objects.get(entity.id)
	expect("old derived node freed and new real GLB replaces exactly one entity",not is_instance_valid(first) and second!=null and mesh_count(second)>0 and view.models.has("city_table") and second.position==Vector3(33,0,43) and is_equal_approx(second.rotation.y,-PI/2))
	var rebuilt:Node3D=building.create_view({"runtime":runtime})
	var canonical:Node3D=rebuilt.objects.get(entity.id)
	expect("initial rebuild and incremental projection agree",canonical!=null and canonical.position==second.position and canonical.rotation==second.rotation and canonical.get_meta("piece")==second.get_meta("piece") and mesh_count(canonical)==mesh_count(second),{"initial":canonical.get_meta("piece") if canonical!=null else {},"dynamic":second.get_meta("piece"),"rotations":[str(canonical.rotation) if canonical!=null else "",str(second.rotation)],"meshes":[mesh_count(canonical) if canonical!=null else 0,mesh_count(second)]})
	rebuilt.free()
	var capture:=runtime.capture_checkpoint();var encoded:=Store.encode(capture);var decoded:=Store.decode(encoded.get("text",""))
	var host:=Client.new();var assembly:Dictionary=host._assemble(decoded.capture) if encoded.ok and decoded.ok else {"ok":false}
	expect("actual native codec preserves dynamic ordinary asset",assembly.ok,assembly.get("reason"))
	if assembly.ok:
		var restored:Node3D=assembly.services.buildings.create_view({"runtime":assembly.runtime})
		var actual:Node3D=restored.objects.get(entity.id)
		expect("restored asset geometry transform and resource agree",actual!=null and actual.position==second.position and actual.rotation==second.rotation and mesh_count(actual)==mesh_count(second))
		restored.free()
	host.free()
	var removed:=runtime._commit({"ok":true,"world_changes":[{"op":"entity.remove","id":entity.id,"before_exists":true,"before":world.entity(entity.id)}],"fact_changes":[]})
	expect("ordinary removal commits and frees derived node",removed.ok and not view.objects.has(entity.id) and not is_instance_valid(second),removed)
	var unchanged:bool=static_ids.size()==view.static_nodes.size()
	for key:String in static_ids:unchanged=unchanged and view.static_nodes.has(key) and view.static_nodes[key].get_instance_id()==static_ids[key]
	expect("unrelated static building batches retained",unchanged)
	expect("projection creates no inventory time learning or actor changes",runtime.facts()==before_facts)
	view.free();finish(started)
