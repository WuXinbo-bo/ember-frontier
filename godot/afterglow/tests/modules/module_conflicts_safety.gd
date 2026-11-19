extends "res://tests/modules/factory_boundary_fixture.gd"
const Projects=preload("res://scripts/modules/module_projects.gd")
func compare(old:Script,svc:RefCounted,v:Dictionary,facts:Dictionary,rows:Array)->Dictionary:
	var result:Dictionary=Projects.footprint_check(svc,v,facts);var expected:Dictionary=old.footprint_check(svc,v,facts)
	var stripped:Dictionary=result.duplicate(true);stripped.erase("conflicts")
	check("precise original decision/first failure unchanged "+str(v.position),Data.json_equal(stripped,expected))
	if result.has("conflicts"):
		check("actual conflict has point/bounds and no unknown identities",result.conflicts.size()==1 and (result.conflicts[0].has("point") or result.conflicts[0].has("bounds")) and not result.conflicts[0].has("entity_id") and not result.conflicts[0].has("actor_id"))
	rows.append({"position":v.position,"result":result});return result
func run()->void:
	var args:=OS.get_cmdline_user_args();var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[3]));var old:Script=load(cfg.reference_projects)
	var base:=opening();var built:=mount(base,"original natural world for conflict differential");if not built.ok:finish();return
	var rt:RefCounted=built.runtime;var svc:RefCounted=built.services.modules;var space:RefCounted=built.services.buildings.current_space()
	var original:Dictionary=rt.capture_checkpoint();var facts:Dictionary=rt.facts();var rows:Array=[];var safe:Dictionary={}
	for x:int in range(3,58,6):
		for z:int in range(3,58,6):
			var ground:Variant=space.ground_height(x,z)
			var v:Dictionary=Modules.record_for({"id":"B:preview-only","definition_id":"r34.module.hand_workshop","region":"RH-HOME","position":{"x":float(x),"y":float(ground) if ground!=null else .5,"z":float(z)},"quarter_turn":0})
			var result:=compare(old,svc,v,facts,rows)
			if result.ok and safe.is_empty():safe=v
	check("natural supported unoccupied placement actually exists",not safe.is_empty())
	if not safe.is_empty():
		var elevated:Dictionary=safe.duplicate(true);elevated.position.y+=.5
		var result:=compare(old,svc,elevated,facts,rows)
		check("unsupported actual cell exposes exact support sample",result.code=="MODULE_FOUNDATION_UNSUPPORTED" and result.conflicts[0].kind=="support" and not Data.material_blocks(rt.world.cell_at(floori(result.conflicts[0].point.x*2),floori(result.conflicts[0].point.y*2),floori(result.conflicts[0].point.z*2)),"support"))
		var crowded:Dictionary=facts.duplicate(true);var actor:Dictionary=Draft.find(crowded.actors,"player");actor.merge(G.location(safe.position.merged({"regionId":"RH-HOME"})),true)
		result=compare(old,svc,safe,crowded,rows)
		check("real actor intersection reported without widening body",result.code=="MODULE_LIVE_ACTOR_OCCUPIED" and result.conflicts[0].kind=="actor")
		# Query-only fixture: add exactly one physical blocker to this isolated
		# Space projection, compare both old/new predicates, then remove it.
		var box:=AABB(G.point(safe.position),Vector3(.3,1,.3));var blocker:Dictionary={"id":"private-fixture","bounds":G.json_box(box),"data":{}}
		space.solid_entities.append(blocker);result=compare(old,svc,safe,facts,rows);space.solid_entities.erase(blocker)
		check("actual entity overlap exposes intersection only",result.code=="MODULE_ENTITY_OCCUPIED" and result.conflicts[0].kind=="entity" and G.aabb(result.conflicts[0].bounds)==Shape.transform_box(safe,G.aabb(Modules.definition(safe.definition_id).footprint)).intersection(box))
	check("conflict projection never changes authority or query blockers",Data.json_equal(original,rt.capture_checkpoint()) and not space.solid_entities.any(func(e:Dictionary)->bool:return e.id=="private-fixture"))
	evidence.append({"rows":rows,"scope":"Actual natural-world 100 placements, plus isolated actor/blocker query counterexamples; old first-failure and all decisions compared exactly, no authorisation or authority mutation."});finish()
