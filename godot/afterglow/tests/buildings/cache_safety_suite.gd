extends "res://tests/buildings/domain_suite.gd"
var allow := true
func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real C world loads",world.load_snapshot(Generator.generate(713)).ok)
	var outside:Dictionary={"x":29.2,"y":0,"z":40.2,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(outside)
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("real structures seed",draft.ok and world.commit_prepared(draft.capability).ok)
	var friend:=resident("friend",{"x":25,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	initialize_at(outside,[friend],seeded.initial_stocks)
	# Warm real metadata certificates before the existing permission and exact
	# door-sweep adversaries. Every assertion below must still use staged facts.
	for n:int in 2:
		var metadata:Dictionary=runtime._commit({"world_changes":[building.extension_change("fixture:sweep-metadata",n)],"fact_changes":[]})
		expect("actual metadata safety commits before dynamic sweep "+str(n),metadata.ok,metadata.get("reason"))
	var query:RefCounted=building.current_space()
	query.permission=func(id:String,_target:String,_kind:String,_piece:Dictionary)->Variant:return null if allow and id=="player" else "fixture permission denied"
	var a:Dictionary={"x":29.2,"y":0,"z":40,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var b:=a.duplicate(true);b.x=26.8
	var initial:Dictionary=query.walk("player",a,b,true)
	expect("actual closed door walk records crossed permission",initial.ok and initial.get("doors",[]).has("rural:v1:RH-HOME:old-house:yard-gate"),initial)
	allow=false
	var revoked:Dictionary=query.walk("player",a,b,true)
	expect("cached geometry rechecks revoked authorization",not revoked.ok and revoked.get("code")=="FORBIDDEN",revoked)
	allow=true
	expect("authorization can recover without poisoned failure cache",query.walk("player",a,b,true).ok)
	expect("geometry proof never transfers authorization to another resident",not query.walk("friend",a,b,true).ok)
	if initial.ok:initial.location.x=500
	var intact:Dictionary=query.walk("player",a,b,true)
	expect("returned walk result cannot mutate cached proof",intact.ok and absf(float(intact.location.x)-26.8)<0.001)
	# Door preflight must read all current staged positions/HP on every call.
	var request:Dictionary={"actor_id":"player","kind":"door","target_id":"rural:v1:RH-HOME:old-house:yard-gate","payload":{"operation":"open"}}
	var before:=world.snapshot();var facts:=runtime.facts()
	var first:Dictionary=building.prepare_door(request,{},facts)
	expect("first exact door prepare succeeds",first.ok,first.get("reason"))
	facts.actors[1].merge({"x":27.6,"y":0,"z":40,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
	var obstructed:Dictionary=building.prepare_door(request,{},facts)
	expect("moving living resident invalidates door sweep immediately",not obstructed.ok and obstructed.code=="OCCUPIED",obstructed.get("reason"))
	facts.actors[1].hp=0
	var dead:Dictionary=building.prepare_door(request,{},facts)
	expect("HP change checked against current semantics",dead.ok,dead.get("reason"))
	facts.actors[1].hp=100;facts.actors[1].z=43
	expect("moving resident back restores prepare without world revision change",building.prepare_door(request,{},facts).ok)
	facts.actors[0].hp=0
	expect("acting resident HP also read from final staged facts",not building.prepare_door(request,{},facts).ok)
	facts.actors[0].hp=100;facts.actors[0].x=35
	expect("acting resident current use position cannot come from live cache",not building.prepare_door(request,{},facts).ok)
	expect("all preflight and proof work leaves authoritative world untouched",world.snapshot()==before)
	finish(started)
