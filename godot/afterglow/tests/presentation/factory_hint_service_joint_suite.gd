extends "res://tests/modules/factory_boundary_fixture.gd"
## Final helper's public-radius service pads against actual B preview.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Hints=preload("res://scripts/presentation/factory_world_view_hints.gd")
func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("actual service-pad source prepares",opening.ok)
	if not opening.ok:finish();return
	var mounted:Dictionary=mount(opening.capture,"service-pad Native")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var modules:RefCounted=mounted.services.modules
	var target:Dictionary=modules.projection().instances[0]
	var payload:Dictionary={"definition_id":"r34.module.fuel_woodshop","position":target.location,"quarter_turn":1,"source_id":"pack:player","tool_id":""}
	var request:Dictionary={"actor_id":"player","kind":"module.plan","target_id":"D:pad:preview","payload":payload}
	var preview:Dictionary=modules.preview(request);var revision:int=rt.world.get_revision()
	var dto:Dictionary={"schema":Hints.SCHEMA,"world_id":rt.world.identity().worldId,"world_revision":revision,"selected":{},"placement":{"active":true,"world_revision":revision,"module_id":request.target_id,"quarter_turn":1,"request":request,"preview":preview}}
	var before:Dictionary=rt.capture_checkpoint();var hint:Node3D=Hints.new();root.add_child(hint)
	check("final helper consumes actual rotated B preview",hint.update(dto,rt.world.identity().worldId,revision) and hint.statistics().ports==preview.ports.size())
	var all_exact:=true;var examined:Array=[];var mesh:Mesh=hint._placement.mesh
	for port:Dictionary in preview.ports:
		var key:String=str(port.purpose) if port.purpose in ["input","output"] else "service"
		var at:Vector3=G.point(port.location);var r:float=float(port.clearance.radius);var found:=false
		# Exact lower-x ring rod outer vertex, including its 4.5cm thickness.
		for s:int in mesh.get_surface_count():
			if mesh.surface_get_material(s)!=hint._materials[key]:continue
			for v:Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				if absf(v.x-(at.x-r-.0225))<.0001 and absf(v.y-(at.y+.06-.0225))<.0001 and absf(v.z-at.z)<=r+.023:found=true
		all_exact=all_exact and found;examined.append({"port_id":port.id,"location":port.location,"radius":r,"exact_ring_vertex_found":found})
	check("all pads exactly follow current public port locations and radii",all_exact,examined)
	check("actual conflict intersection consumed without guessed IDs",preview.get("conflicts",[]).size()>0 and hint.statistics().conflicts==preview.conflicts.size(),preview.conflicts)
	check("preview and mesh refresh never mutate authority",Data.json_equal(before,rt.capture_checkpoint()))
	evidence.append({"preview":preview,"scope":"one actual rotated source preview, final D radius path; no placement commit/route/VA"})
	hint.free();finish()
