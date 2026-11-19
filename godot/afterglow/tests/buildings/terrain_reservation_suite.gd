extends "res://tests/buildings/domain_suite.gd"
const Draft = preload("res://scripts/actions/domain_draft.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
var terrain:=Terrain.new()

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("same C world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":29.2,"y":0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	expect("public terrain provider registered",runtime.configure({"world":world,"facts":runtime.facts(),"services":{"buildings":building,"actions":actions,"production":production,"terrain":terrain}}).ok)
	var tx:=Draft.new(production.context)
	var intent:Dictionary={"schema_version":1,"owner":"terrain","kind":"terrain","id":"bbb:staged-fill","source_id":"pack:player","cost":{"soil_m3":0.125},"held":false,"tool_id":"fixture:shovel","elapsed":0.0,"duration":2.0,"request":{"actor_id":"player","kind":"terrain","payload":{"tool_id":"fixture:shovel","edit":{"operation":"fill","material":2,"cells":[{"x":58,"y":0,"z":60}]}}}}
	tx.actor("player").intent=intent
	expect("new staged terrain hold is seen before commit",production.reserved("pack:player","soil_m3","",tx)==0.125 and production.reserved("pack:player","soil_m3")==0)
	expect("own staged terrain hold excluded by exact intent id",production.reserved("pack:player","soil_m3",intent.id,tx)==0 and production.reserved("pack:player","soil_m3","other",tx)==0.125)
	expect("paused intent holds only its source and actual cost",production.reserved("other-stock","soil_m3","",tx)==0 and production.reserved("pack:player","stone_m3","",tx)==0)
	intent.held=true
	expect("resume preserves same material reservation",production.reserved("pack:player","soil_m3","",tx)==0.125)
	var second:=resident("friend",Geometry.location(tx.actor("player")))
	second.relationship={"member":true,"consent":true}
	second.intent=intent.duplicate(true);second.intent.id="bbb:second-fill"
	second.intent.source_id="pack:friend";second.intent.request.actor_id="friend";second.intent.cost={"soil_m3":0.25}
	tx.staged.actors.append(second)
	expect("two provider intents retain their real sources",production.reserved("pack:player","soil_m3","",tx)==0.125 and production.reserved("pack:friend","soil_m3","",tx)==0.25)
	tx.actor("player").intent=null
	expect("staged completion removes only completed hold",production.reserved("pack:player","soil_m3","",tx)==0 and production.reserved("pack:friend","soil_m3","",tx)==0.25)
	second.intent.cost={};second.intent.yield={"soil_m3":0.125}
	expect("dig future output is never held material",production.reserved("pack:player","soil_m3","",tx)==0)
	second.intent.cost={"soil_m3":0.125};second.intent.owner="actions"
	expect("unrelated owner cannot create terrain material hold",production.reserved("pack:player","soil_m3","",tx)==0)
	second.intent.owner="terrain";second.intent.kind="walk"
	expect("unrelated terrain intent kind does not reserve material",production.reserved("pack:player","soil_m3","",tx)==0)
	second.intent.kind="terrain"
	expect("terrain tool_reserved self-completion contract unchanged",not production.tool_reserved("fixture:shovel","",tx) and production.tool_unavailable("fixture:shovel","",tx) and not production.tool_unavailable("fixture:shovel",second.intent.id,tx))
	expect("staged reads never mutate authoritative facts",runtime.actor("player").intent==null and runtime.facts().actors.size()==1)
	var committed:=runtime.facts();committed.actors[0].intent=intent.duplicate(true)
	expect("single authoritative paused intent can be restored",runtime.configure({"world":world,"facts":committed,"services":{"buildings":building,"actions":actions,"production":production,"terrain":terrain}}).ok)
	var cancelled:=Draft.new(production.context);cancelled.actor("player").intent=null
	expect("staged cancellation overrides existing live hold",production.reserved("pack:player","soil_m3")==0.125 and production.reserved("pack:player","soil_m3","",cancelled)==0)
	finish(started)
