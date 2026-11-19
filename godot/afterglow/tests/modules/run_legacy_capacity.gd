extends "res://tests/buildings/domain_suite.gd"
## Original three-domain world, no module seed/fallback injected by fixture.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real legacy rural source loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":33.3,"y":0,"z":40.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at)
	var seeded:=building.seed_rural(world);var change:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("original legacy structures commit",change.ok and world.commit_prepared(change.capability).ok)
	if not change.ok:finish(started);return
	initialize_at(at,[],seeded.initial_stocks)
	var p:=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records;p.knowledge={"player":["basic_woodwork"]}
	for t:Dictionary in p.tools:t.holderId="pack:player"
	change=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("finite legacy tools register once",change.ok and world.commit_prepared(change.capability).ok)
	var facts:=runtime.facts();facts.actors[0].pack={"log":2,"timber":8,"scrap":8}
	expect("same runtime accepts original facts",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var tx:=Draft.new(production.context);var before:Dictionary=world.snapshot()
	expect("capacity query for old pack succeeds",production.capacity_check("pack:player",{"timber":4},"",tx).ok)
	expect("capacity and hold queries do not enlist new module domain",not tx.extensions.has(Factory.MODULES) and not tx.extensions.has(Factory.KEY) and not tx.extensions.has(Factory.LOGISTICS) and before==world.snapshot())
	var bench:=building.make_instance("workbench","B:legacy:bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	expect("real legacy held construction starts",command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"}).ok)
	for i:int in 90:runtime.tick(0.1)
	expect("real original station completes",not building.instance(bench.id).is_empty())
	var use_points:Array=actions.work_points({"kind":"craft","target_id":bench.id})
	expect("closer station hint preserves physical body and original hint",use_points.size()==2 and absf(float(use_points[0].z)-40.8)<0.001 and absf(float(use_points[1].z)-40.5)<0.001 and not building.current_space().standing_point(use_points[0]).is_empty(),use_points)
	var craft:=command("craft",bench.id,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":["rural:v1:RH-HOME:shed:hand_saw"]})
	expect("real craft accepts no-module legacy world",craft.ok,craft)
	runtime.tick(0.1)
	var projection:Dictionary=production.actor_work_projection("player")
	expect("actual craft publishes physical tabletop normal not a chest vector",projection.get("contact",{}).get("normal")==[0.0,1.0,0.0])
	for i:int in 110:runtime.tick(0.1)
	expect("manual production settles one real log once",runtime.actor("player").pack.log==1 and runtime.actor("player").pack.timber==8)
	expect("legacy craft never persists new factory domains",not world.has_extension(Factory.MODULES) and not world.has_extension(Factory.KEY) and not world.has_extension(Factory.LOGISTICS))
	var saved:=world.snapshot();var cold:=World.new()
	expect("legacy output cold world remains valid without synthesized module schema",cold.load_snapshot(saved).ok and not cold.has_extension(Factory.MODULES))
	finish(started)
func finish(started:int)->void:
	print(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"real legacy Runtime craft; no package/OS/VA qualification"}));quit(0 if failures.is_empty() else 1)
