extends "res://tests/buildings/domain_suite.gd"
## Projection identity fixtures, not accepted gameplay edits. Normal full
## prepare_door/snapshot tests separately prove final-world safety semantics.
func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real source for cache identity loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seed:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seed.world_changes,world.get_revision())
	expect("identity fixture uses actual full seeded structure facts",draft.ok and world.commit_prepared(draft.capability).ok)
	var original:Dictionary=building.structures();var facts:=runtime.facts()
	var base:RefCounted=building.validation_space(world,original,facts)
	expect("native identity reuses an equal deep-copied full projection",building.validation_space(world,original.duplicate(true),facts)==base)
	var variants:Array=[]
	for field:String in ["hp","version","owner","position","quarterTurn","definitionId"]:
		var data:=original.duplicate(true)
		match field:
			"hp":data.instances[0].hp-=1
			"version":data.instances[0].version+=1
			"owner":data.instances[0].owner="identity-fixture"
			"position":data.instances[0].position.x+=0.125
			"quarterTurn":data.instances[0].quarterTurn=1
			"definitionId":data.instances[0].definitionId="floor"
		variants.append({"name":field,"data":data})
	var elevation:=original.duplicate(true);elevation.storeys[0].elevation+=0.5;variants.append({"name":"storey height","data":elevation})
	var removed:=original.duplicate(true);removed.instances.pop_back();variants.append({"name":"removed instance","data":removed})
	var metadata:=original.duplicate(true);metadata.cache_test={"exact":0.000000001};variants.append({"name":"non-geometric metadata retained exactly","data":metadata})
	var reordered:=original.duplicate(true);reordered.instances.reverse();variants.append({"name":"ordered structure list","data":reordered})
	for variant:Dictionary in variants:
		var before:RefCounted=building.validation_space(world,original,facts)
		var after:RefCounted=building.validation_space(world,variant.data,facts)
		expect("native identity detects complete state change: "+variant.name,after!=before and after.state==variant.data)
	var changed:=facts.duplicate(true);changed.actors[0].householdId="identity-fixture"
	var same:RefCounted=building.validation_space(world,original,changed)
	var owned:Dictionary={"id":"identity-owned","owner":"identity-fixture"}
	expect("current staged permission binding grants only actual household",same.permission.call("player",owned.id,"move",owned)==null)
	changed=facts.duplicate(true);changed.actors[0].householdId="different"
	var rebound:RefCounted=building.validation_space(world,original,changed)
	expect("equal geometry never retains another staged household permission",rebound==same and rebound.permission.call("player",owned.id,"move",owned)!=null)
	changed.actors[0].hp=0
	var disabled:RefCounted=building.validation_space(world,original,changed)
	expect("equal geometry permission reads latest actor HP",disabled.permission.call("player",owned.id,"move",owned)!=null)
	var other:=World.new();other.load_snapshot(world.snapshot())
	var separate:RefCounted=building.validation_space(other,original,facts)
	expect("separate authority at same identity/revision cannot share cached projection",separate!=same and separate.world==other)
	var before:RefCounted=building.validation_space(world,original,facts)
	var revision_change:Dictionary=world.prepare_changes([building.extension_change("bbb:identity-fixture",{"value":1})],world.get_revision())
	expect("explicit isolated revision fixture commits through C capability",revision_change.ok and world.commit_prepared(revision_change.capability).ok)
	var after:RefCounted=building.validation_space(world,original,facts)
	expect("new world revision invalidates even identical full structure state",after!=before)
	expect("derived identity probes never mutate authoritative structures or actors",building.structures()==original and runtime.facts()==facts)
	finish(started)
