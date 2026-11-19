extends "res://tests/world/factory_normal_path.gd"
## Isolated occupancy counterexample; explicitly not a normal-player action.
func run()->void:
	var profiles:Array=Modules.generation_profiles(true);var lock:Dictionary=Contract.fresh(profiles,9,1)
	var made:Dictionary=Assembly.prepare(Factory.generate(713,profiles,lock.contract));var native:=Native.new()
	var built:Dictionary=native._assemble(made.capture) if made.get("ok",false) else made;native.free()
	check("fixture starts from actual unedited9 normal Assembly",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var world:RefCounted=built.world;var rt:RefCounted=built.runtime;var plan:Dictionary=world.extension("generation:RH-HOME")
	var yard:Dictionary=plan.buildable_workyards[0];var c:Dictionary=yard.candidate_definitions[0];var position:Dictionary=c.position.duplicate(true)
	position.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
	var payload:Dictionary={"definition_id":c.definition_id,"position":position,"quarter_turn":c.quarter_turn,"source_id":"pack:player","tool_id":"absent-real-tool"}
	var request:Dictionary={"actor_id":"player","target_id":"r34:c:quality9:site-test","payload":payload}
	check("empty-yard advice passes original live spatial preview",built.services.modules.preview(request).ok)
	var id:String="fixture:quality9:occupier";var e:Dictionary={"id":id,"kind":"prop","regionId":"RH-HOME","position":c.position.duplicate(true),"bounds":{"min":{"x":position.x-.5,"y":position.y,"z":position.z-.5},"max":{"x":position.x+.5,"y":position.y+1,"z":position.z+.5}},"revision":world.get_revision(),"blocksTerrain":true,"data":{"solid":true,"opaque":true}}
	var before:Dictionary=rt.facts();var tx:Dictionary=world.prepare_changes([{"op":"entity.put","id":id,"before_exists":false,"before":null,"after":e}],world.get_revision())
	var commit:Dictionary=world.commit_prepared(tx.capability) if tx.get("ok",false) else tx
	check("explicit fixture uses original authority entity transaction only",commit.get("ok",false) and Data.json_equal(before,rt.facts()),commit)
	var frozen:Dictionary=rt.capture_checkpoint();var preview:Dictionary=built.services.modules.preview(request)
	var denied:Dictionary=send(rt,"module.plan",request.target_id,payload)
	check("occupied advice refuses original preview with real solid entity",preview.get("code")=="MODULE_ENTITY_OCCUPIED",preview)
	check("occupied advice refuses original command atomically before missing tool/source",denied.get("code")=="MODULE_ENTITY_OCCUPIED" and Data.json_equal(frozen,rt.capture_checkpoint()),denied)
	check("advisory persistent workyard never changes into permit or instance",Data.json_equal(plan,world.extension("generation:RH-HOME")) and not world.extension("r34:modules").instances.any(func(m:Dictionary)->bool:return m.id==request.target_id))
	rt.retire();costs.scope="Explicit isolated solid occupancy fixture on real9 Assembly. Not normal gathering/building, no renderer/VA/performance qualification.";finish()
