extends "res://tests/gameplay/generated_cooperation.gd"
## Diagnostic only: log sample positions are NOT the unknown warning position.
## Fresh same-seed isolated world; no user saves, native app or OS input.
var probes:Array=[]
var accepted_but_invalid:Array=[]

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="same-seed-fresh-isolated-spatial-commit-diagnostic-not-native-warning-replay"
	host=Client.new()
	var generated:Dictionary=Assembly.prepare(Assembly.generate(973339546,Building.generation_profiles()))
	check("native-warning seed prepares through actual C/B/A assembly",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	var samples:Array=[
		{"label":"sample1-start","x":28.3513850090094,"y":2.0,"z":36.0986694269814,"regionId":"RH-HOME","buildingId":null,"storeyId":null},
		{"label":"sample1-end","x":9.19477134058252,"y":1.0,"z":12.0184513521381,"regionId":"RH-HOME","buildingId":"RH-HOME:shed","storeyId":"RH-HOME:shed:ground"},
		{"label":"sample2-start","x":23.0358393591305,"y":3.0,"z":-8.5933844668325,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null},
		{"label":"sample2-end","x":17.110546369935,"y":2.5,"z":-49.6824738486903,"regionId":"RH-VILLAGE","buildingId":"RH-VILLAGE:neighbor","storeyId":"RH-VILLAGE:neighbor:ground"}]
	for sample:Dictionary in samples:
		var fixture:Dictionary=baseline.duplicate(true)
		for a:Dictionary in fixture.facts.actors:
			if a.id=="player":a.merge(Geometry.location(sample),true);a.intent=null
		if not mount(fixture):continue
		probe(sample)
	finish()

func probe(sample:Dictionary)->void:
	var building:RefCounted=runtime._services.buildings
	var query:RefCounted=building.current_space()
	var at:Dictionary=Geometry.location(runtime.actor("player"))
	var feet:Dictionary=query.standing_point(at)
	var before:Variant=runtime.world.extension(Gameplay.KEY)
	var after:Dictionary=before.duplicate(true);after.last_event_revision=int(after.last_event_revision)+1
	var changes:Array=[{"op":"extension.set","id":Gameplay.KEY,"before_exists":true,"before":before,"after":after}]
	var draft:Dictionary=runtime.world.prepare_changes(changes,runtime.world.get_revision())
	var row:Dictionary={"label":sample.label,"log_sample_only":true,"position":at,"current_feet":feet,"current_exact":not feet.is_empty() and Geometry.point(feet).distance_to(Geometry.point(at))<=0.025,"metadata_prepared":draft.ok}
	if draft.ok:
		var proposed:RefCounted=building.space(draft.view,building.structures(draft.view),runtime.facts())
		row.prepared_feet=proposed.standing_point(at)
		row.metadata_safety=building.validate_world_draft(draft.view,runtime.facts(),changes)
		runtime.world.discard_prepared(draft.capability)
	var plan:Dictionary=runtime._services.gameplay.advance(0.1)
	row.gameplay_changes=[];row.gameplay_player_locations=[]
	for change:Dictionary in plan.get("world_changes",[]):row.gameplay_changes.append({"op":change.get("op"),"id":change.get("id")})
	for change:Dictionary in plan.get("fact_changes",[]):
		if change.get("collection")=="actors" and change.get("id")=="player":row.gameplay_player_locations.append({"before":Geometry.location(change.before),"after":Geometry.location(change.after)})
	row.actual_gameplay_commit=runtime._commit(plan)
	row.local_accepted_steps=0
	if not feet.is_empty():
		for distance:float in [0.073,0.28,0.46]:
			for direction:Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized()]:
				var target:Dictionary=feet.duplicate(true);target.x+=direction.x*distance;target.z+=direction.y*distance
				var accepted:Dictionary=runtime._services.actions.move_step("player",feet,target)
				if not accepted.ok:continue
				row.local_accepted_steps+=1
				var rechecked:Dictionary=query.standing_point(accepted.location)
				if rechecked.is_empty() or Geometry.point(rechecked).distance_to(Geometry.point(accepted.location))>0.025:accepted_but_invalid.append({"label":sample.label,"from":feet,"target":target,"accepted":accepted,"rechecked":rechecked})
	probes.append(row)

func finish()->void:
	write_json("probe.json",{"scope":"fresh same-seed sampled-position diagnosis; live door/terrain state and exact warning position unknown","seed":973339546,"probes":probes,"accepted_but_invalid":accepted_but_invalid})
	super.finish()
