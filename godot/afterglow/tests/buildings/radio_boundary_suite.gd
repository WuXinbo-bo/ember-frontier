extends "res://tests/buildings/domain_suite.gd"
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
var gameplay:=Gameplay.new()
func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":33.3,"y":0,"z":40.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at)
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual buildings seed",draft.ok and world.commit_prepared(draft.capability).ok)
	var friend:=resident("friend",at.merged({"x":33.9},true));friend.relationship={"member":true,"consent":true};friend.job="rest"
	initialize_at(at,[friend],seeded.initial_stocks)
	var f:=runtime.facts();f.scenario="rural-home-r33";f.actors[0].pack={"timber":8,"scrap":14,"tool_handle":1}
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records;p.knowledge={"player":["basic_woodwork","basic_tool_repair"]}
	for tool in p.tools:tool.holderId="pack:player"
	var state:=Gameplay.initial();state.defense.status="cleared"
	draft=world.prepare_changes([building.extension_change(Production.KEY,p),building.extension_change(Gameplay.KEY,state)],world.get_revision())
	expect("finite tools and post-defense fixture registered",draft.ok and world.commit_prepared(draft.capability).ok)
	expect("same actual gameplay service configured",runtime.configure({"world":world,"facts":f,"services":{"buildings":building,"actions":actions,"production":production,"gameplay":gameplay}}).ok)
	var hammer:="rural:v1:RH-HOME:shed:hammer"
	var bench:Dictionary=building.make_instance("workbench","bbb:radio-bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	expect("real workbench construction begins",command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":hammer}).ok)
	for n in 80:runtime.tick(0.1)
	expect("actual workbench built before radio",not building.instance(bench.id).is_empty())
	var before:Dictionary=runtime.actor("player").pack.duplicate(true);var wear:float=runtime.tool(hammer).durability
	var start:=command("radio",bench.id,{"operation":"repair","tool_id":hammer})
	expect("actual A radio repair accepted",start.ok,start)
	if not start.ok:finish(started);return
	var intent:Dictionary=runtime.actor("player").intent
	var contract:bool=intent.get("id") is String and intent.get("source_id")=="pack:player" and intent.get("cost")=={"scrap":8,"tool_handle":1}
	expect("real radio intent has shared reservation contract",contract,intent)
	if not contract:finish(started);return
	expect("radio material reservation and excluding own intent",production.reserved("pack:player","scrap")==8 and production.reserved("pack:player","tool_handle")==1 and production.reserved("pack:player","scrap",intent.id)==0)
	expect("radio tool visible to all domains and excludes itself",production.tool_reserved(hammer) and production.tool_unavailable(hammer) and not production.tool_unavailable(hammer,intent.id))
	expect("radio blocks actual tool handoff",not command("deposit","pack:friend",{"tool_ids":[hammer]}).ok)
	expect("radio blocks reserved material handoff",not command("deposit","pack:friend",{"items":{"tool_handle":1}}).ok)
	for n in 100:runtime.tick(0.1)
	expect("radio labor keeps material and wear until completion",runtime.actor("player").pack==before and runtime.tool(hammer).durability==wear)
	var saved:=runtime.capture_checkpoint()
	expect("radio reservation survives same-world restore",world.load_snapshot(saved.world).ok and runtime.configure({"world":world,"facts":saved.facts,"services":{"buildings":building,"actions":actions,"production":production,"gameplay":gameplay}}).ok and production.tool_unavailable(hammer) and production.reserved("pack:player","scrap")==8)
	for n in 100:runtime.tick(0.1)
	var after:Dictionary=world.extension(Gameplay.KEY)
	expect("actual A radio completes once without self reservation deadlock",after.radio.status=="repaired" and runtime.actor("player").pack.scrap==before.scrap-8 and runtime.actor("player").pack.tool_handle==0 and runtime.tool(hammer).durability==wear-2,{"radio":after.radio,"actor":runtime.actor("player")})
	expect("completion releases all actual holds",not production.tool_unavailable(hammer) and production.reserved("pack:player","scrap")==0)
	expect("post-radio domain snapshot valid",building.validate_snapshot(world,runtime.facts()).ok)
	finish(started)
