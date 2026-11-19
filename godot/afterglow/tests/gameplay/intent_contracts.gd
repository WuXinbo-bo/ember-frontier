extends "res://tests/gameplay/generated_cooperation.gd"
## Pure E schemas/derived holds on explicit shape fixtures. This is not an
## earned radio/material route or proof of A's not-yet-adopted owner dispatch.

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="E-pure-schema-and-derived-hold-counterexamples"
	host=Client.new()
	var built:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	if not built.ok or not mount(built.capture):check("contract fixture assembles",false);finish();return
	var residents:RefCounted=runtime._services.residents
	var gameplay:RefCounted=runtime._services.gameplay
	var facts:Dictionary=runtime.facts()
	var person:Dictionary=runtime.actor("village-resident")
	var walk:Dictionary={"schema_version":1,"owner":"residents","kind":"walk","id":"E:contract:walk","steps":[{"kind":"move","to":Geometry.location(person)}],"step":0,"held":true,"movement_mode":"walk","resident_goal":{"kind":"bed","target_id":"RH-VILLAGE:neighbor:sleeping-place"}}
	var radio:Dictionary={"schema_version":1,"owner":"gameplay","kind":"radio","id":"E:contract:radio","source_id":"pack:"+str(person.id),"cost":{"scrap":8,"tool_handle":1},"operation":"repair","target_id":"E:contract:bench","tool_id":"E:contract:hammer","elapsed":2.0,"duration":20.0}
	var checkpoint:Dictionary=runtime.capture_checkpoint()
	var original:Dictionary=facts.duplicate(true)
	for entry:Dictionary in [{"service":residents,"intent":walk},{"service":gameplay,"intent":radio}]:
		var service:RefCounted=entry.service
		var intent:Dictionary=entry.intent
		check(str(intent.owner)+" current v1 schema accepts shape without executing",service.validate_intent(intent,person,facts).ok)
		var legacy:Dictionary=intent.duplicate(true);legacy.erase("schema_version")
		check(str(intent.owner)+" known v0 shape stays compatible",service.validate_intent(legacy,person,facts).ok)
		for mutation:String in ["owner","kind","version","nan_version","phase","id"]:
			var bad:Dictionary=intent.duplicate(true)
			match mutation:
				"owner":bad.owner="unknown"
				"kind":bad.kind="unknown"
				"version":bad.schema_version=2
				"nan_version":bad.schema_version=NAN
				"phase":bad.phase="completed-but-still-working"
				"id":bad.id=""
			check(str(intent.owner)+" rejects "+mutation+" before consumer",not service.validate_intent(bad,person,facts).ok)
	for mutation:String in ["negative_step","fractional_step","out_of_steps","nan_point","unknown_step","bad_door","bad_goal"]:
		var bad:Dictionary=walk.duplicate(true)
		match mutation:
			"negative_step":bad.step=-1
			"fractional_step":bad.step=0.5
			"out_of_steps":bad.step=2
			"nan_point":bad.steps[0].to.x=NAN
			"unknown_step":bad.steps[0].kind="teleport"
			"bad_door":bad.steps=[{"kind":"open-door","targetId":"","at":Geometry.location(person)}]
			"bad_goal":bad.resident_goal.target_id=42
		check("resident rejects "+mutation,not residents.validate_intent(bad,person,facts).ok)
	var decoded:Dictionary=JSON.parse_string(JSON.stringify(radio))
	check("radio accepts native JSON exact numeric quantities after roundtrip",gameplay.validate_intent(decoded,person,facts).ok)
	for mutation:String in ["wrong_source","free_repair","bad_tool","bad_target","elapsed","duration","string_cost","extra_cost","missing_cost","wrong_cost","nan_cost","infinite_cost","boolean_cost"]:
		var bad:Dictionary=radio.duplicate(true)
		match mutation:
			"wrong_source":bad.source_id="pack:player"
			"free_repair":bad.cost={}
			"bad_tool":bad.tool_id=""
			"bad_target":bad.target_id=42
			"elapsed":bad.elapsed=21
			"duration":bad.duration=0
			"string_cost":bad.cost.scrap="8"
			"extra_cost":bad.cost.food=1
			"missing_cost":bad.cost.erase("tool_handle")
			"wrong_cost":bad.cost.scrap=7.999
			"nan_cost":bad.cost.scrap=NAN
			"infinite_cost":bad.cost.tool_handle=INF
			"boolean_cost":bad.cost.tool_handle=true
		check("radio rejects "+mutation,not gameplay.validate_intent(bad,person,facts).ok)
	var staged:Dictionary=facts.duplicate(true)
	var actor:Dictionary=preload("res://scripts/actions/domain_draft.gd").find(staged.actors,str(person.id))
	actor.intent=walk.duplicate(true)
	var holds:Array=residents.hold_descriptors(staged,{})
	check("bed route derives exactly one standard use hold",holds.size()==1 and holds[0].schema_version==1 and holds[0].owner=="residents" and holds[0].intent_id==walk.id and holds[0].actor_id==person.id and holds[0].use_target_id==walk.resident_goal.target_id and holds[0].cost.is_empty() and holds[0].tool_ids.is_empty(),holds)
	actor.intent=radio.duplicate(true)
	holds=gameplay.hold_descriptors(staged,{})
	check("radio repair derives original unpaid quantities tool and station",holds.size()==1 and holds[0].source_id==radio.source_id and holds[0].cost=={"scrap":8,"tool_handle":1} and holds[0].tool_ids==[radio.tool_id] and holds[0].use_target_id==radio.target_id and holds[0].phase=="active",holds)
	if not holds.is_empty():holds[0].cost.scrap=999
	check("returned descriptor mutation cannot alter authoritative intent",actor.intent.cost.scrap==8)
	actor.stamina=0.0
	holds=gameplay.hold_descriptors(staged,{})
	check("paused radio retains its real unpaid holds",holds.size()==1 and holds[0].phase=="paused" and holds[0].cost.scrap==8)
	actor.intent.operation="transmit";actor.intent.cost={};actor.intent.tool_id="";actor.intent.duration=30.0
	holds=gameplay.hold_descriptors(staged,{})
	check("transmission holds station without charging repair again",holds.size()==1 and holds[0].source_id.is_empty() and holds[0].cost.is_empty() and holds[0].tool_ids.is_empty() and holds[0].use_target_id==radio.target_id)
	for service:RefCounted in [residents,gameplay]:
		actor.intent=walk.duplicate(true) if service==residents else radio.duplicate(true)
		actor.hp=0.0
		check("incapacitated actor has no effective "+str(actor.intent.owner)+" hold",service.hold_descriptors(staged,{}).is_empty())
		actor.hp=100.0;actor.intent=null
		check("cancellation releases "+("resident" if service==residents else "radio")+" hold",service.hold_descriptors(staged,{}).is_empty())
	check("all pure schema/hold queries leave caller facts untouched",facts==original)
	check("all pure schema/hold queries leave world clock inventory events exact",Data.json_equal(checkpoint,runtime.capture_checkpoint()))
	# Exercise A's actual owner dispatch and rejection boundary, not merely
	# calling the providers. No accepted action or material fixture is created.
	for value:Dictionary in [walk,radio]:
		var malformed:Dictionary=value.duplicate(true);malformed.schema_version=77
		var after:Dictionary=person.duplicate(true);after.intent=malformed
		var before:Dictionary=runtime.capture_checkpoint()
		var refused:Dictionary=runtime._commit({"ok":true,"world_changes":[],"fact_changes":[{"collection":"actors","id":person.id,"before":runtime.actor(person.id),"after":after}]})
		check("A owner dispatch rejects malformed "+str(value.owner)+" transaction atomically",not refused.ok and Data.json_equal(before,runtime.capture_checkpoint()),refused)
		var saved:Dictionary=checkpoint.duplicate(true)
		for a:Dictionary in saved.facts.actors:
			if a.id==person.id:a.intent=malformed
		var rejected:Dictionary=host._assemble(saved)
		check("A rejects malformed restored "+str(value.owner)+" before consumers",not rejected.ok and Data.json_equal(before,runtime.capture_checkpoint()),rejected.get("code"))
	finish()
