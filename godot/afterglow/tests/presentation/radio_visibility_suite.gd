extends "res://tests/buildings/domain_suite.gd"
## D diagnostic only: original A/B/C modules, in-memory fixture; no saves/imports.
const GameplayState=preload("res://scripts/runtime/rural_gameplay.gd")
const RadioView=preload("res://scripts/presentation/gameplay_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("real existing rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	var outside:Dictionary={"x":33.3,"y":0,"z":40.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(outside)
	var seeded:Dictionary=building.seed_rural(world)
	expect("existing B buildings prepare",seeded.ok)
	if not seeded.ok:finish(started);return
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("same C world commits buildings",draft.ok and world.commit_prepared(draft.capability).ok)
	initialize_at(outside,[],seeded.initial_stocks)
	var facts:Dictionary=runtime.facts();facts.actors[0].pack={"timber":8,"scrap":14,"tool_handle":1}
	var tools:Dictionary=Production.empty_state();tools.tools=seeded.initial_tools;tools.records=seeded.initial_records;tools.knowledge={"player":["basic_woodwork","basic_tool_repair"]}
	for tool:Dictionary in tools.tools:tool.holderId="pack:player"
	var state:Dictionary=GameplayState.initial();state.defense.status="cleared"
	draft=world.prepare_changes([building.extension_change(Production.KEY,tools),building.extension_change(GameplayState.KEY,state)],world.get_revision())
	expect("isolated finite construction and post-defense fixture accepted",draft.ok and world.commit_prepared(draft.capability).ok)
	expect("same actual runtime configured",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var bench:Dictionary=building.make_instance("workbench","ddd:radio-probe-bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	var construction:Dictionary=command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"})
	expect("actual B workbench construction starts",construction.ok,construction)
	if not construction.ok:finish(started);return
	for i:int in 80:runtime.tick(0.1)
	expect("actual B workbench completes",not building.instance(bench.id).is_empty())
	var stage:=Node3D.new();root.add_child(stage)
	var view:=RadioView.new();stage.add_child(view);view.configure(runtime,building);view._process(0.2)
	expect("same-region unobstructed station initially visible",view.statistics().radio_visible,view.statistics())
	var query:RefCounted=building.current_space()
	var at:Dictionary=query.standing_point({"x":9,"y":0,"z":31,"regionId":"RH-HOME"})
	expect("actual enclosed home station has supported feet",not at.is_empty(),at)
	if at.is_empty():stage.free();finish(started);return
	facts=runtime.facts();facts.actors[0].merge(at,true);facts.actors[0].intent=null
	expect("explicit diagnostic observation configured only in memory",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	query=building.current_space()
	var from:Dictionary=Geometry.location(runtime.actor("player"))
	var target:Dictionary=Geometry.location(building.instance(bench.id))
	var clear:bool=query.line_clear(from,target,bench.id)
	expect("original B true sight rejects station behind closed structure",not clear,{"from":from,"target":target,"line_clear":clear})
	var capture:Dictionary=runtime.capture_checkpoint()
	view._process(0.2)
	expect("radio render follows original sight boundary",not view.statistics().radio_visible,{"original_sight_clear":clear,"view":view.statistics()})
	expect("render observation changes no world facts clock inventory",Data.json_equal(capture,runtime.capture_checkpoint()))
	# Same live view must recover visibility on return to an actually clear station.
	facts=runtime.facts();facts.actors[0].merge(outside,true)
	runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	view._process(0.2)
	expect("return to actual clear station restores radio",view.statistics().radio_visible,view.statistics())
	# Actual 1.5m cabinet distinguishes B's shared 1.2m eye ray from the old
	# double-raised 2.35m ray. Reuse real construction, not a fake sight service.
	facts=runtime.facts();facts.actors[0].merge({"x":34,"y":0,"z":38,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
	runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	var cabinet:Dictionary=building.make_instance("cabinet","ddd:radio-eye-blocker",{"x":34,"y":0,"z":40,"regionId":"RH-HOME"})
	var placed:Dictionary=command("structure",cabinet.id,{"kind":"place","instance":cabinet,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"})
	expect("actual cabinet construction starts with remaining finite material",placed.ok,placed)
	if not placed.ok:stage.free();finish(started);return
	for i:int in 100:runtime.tick(0.1)
	expect("actual 1.5m cabinet completes between observer and station",not building.instance(cabinet.id).is_empty())
	query=building.current_space();from=Geometry.location(runtime.actor("player"));target=Geometry.location(building.instance(bench.id))
	var high_from:Dictionary=from.duplicate(true);high_from.y+=1.15
	var high_target:Dictionary=target.duplicate(true);high_target.y+=1.15
	expect("B shared eye ray is blocked while duplicate offset wrongly clears",not query.line_clear(from,target,bench.id) and query.line_clear(high_from,high_target,bench.id),{"from":from,"target":target,"cabinet":cabinet.position})
	capture=runtime.capture_checkpoint();view._process(0.2)
	expect("radio uses B eye height once and stays behind actual cabinet",not view.statistics().radio_visible,view.statistics())
	expect("sight height correction changes no authority facts",Data.json_equal(capture,runtime.capture_checkpoint()))
	view.configure(runtime)
	view._process(0.2)
	expect("legacy configure signature stays valid and missing spatial fails closed",not view.statistics().radio_visible,view.statistics())
	stage.free();finish(started)
func finish(started:int)->void:
	var result:Dictionary={"scope":"DDD production-source sight-boundary regression on existing A runtime/B spatial/C world; in-memory fixtures, no formal app/pixel VA","ok":failures.is_empty(),"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	print("DDD_DIAGNOSTIC "+JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
