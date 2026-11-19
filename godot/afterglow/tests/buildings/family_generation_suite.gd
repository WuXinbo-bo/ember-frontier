extends "res://tests/buildings/domain_suite.gd"
## Real C rural-2 persistent plans + B recipes, sole A runtime, actual geometry.
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Client=preload("res://scripts/runtime/native_client.gd")

func run()->void:
	var started:=Time.get_ticks_msec()
	var profiles:Array=preload("res://scripts/world/generation_contract.gd").baseline(Building.generation_profiles())
	expect("explicit retained rural-2 uses six original authored families",profiles.size()==6 and profiles.map(func(p:Dictionary)->String:return p.family_id).has("homestead"))
	var altered:=Building.generation_profiles();altered[0].id="test-copy"
	expect("static generation profile DTOs cannot mutate canonical recipes",Building.generation_profiles()[0].id!="test-copy")
	var source:Dictionary=Generator.generate_settlement(713,profiles,"rural-2")
	expect("C actual nonflat rural-2 source exists",source.get("generatorVersion")=="rural-2")
	var loaded:=world.load_snapshot(source)
	expect("same C authoritative world accepts persistent settlement",loaded.ok,loaded.get("reason"))
	if not loaded.ok:finish(started);return
	building.configure({"world":world,"runtime":runtime})
	var original:=world.snapshot()
	var seeded:Dictionary=building.seed_rural(world)
	expect("formal building entry consumes actual persistent parcels",seeded.ok,seeded.get("reason"))
	if not seeded.ok:finish(started);return
	expect("recipe preparation never commits terrain or entities",world.snapshot()==original)
	expect("plan produces actual home shed store repair neighbor buildings",seeded.assembled_parcels.size()==5,seeded.assembled_parcels)
	expect("all three real resident spawns follow generated elevations",seeded.spawn_points.has_all(["player","village-resident","repair-resident"]),seeded.spawn_points)
	if not seeded.spawn_points.has_all(["player","village-resident","repair-resident"]):finish(started);return
	var facts:=Initial.facts(seeded)
	facts.stocks.append_array(Generator.empty_resource_stocks(world))
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([building.extension_change(Production.KEY,Initial.production(seeded)),building.extension_change(Gameplay.KEY,Gameplay.initial()),building.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	expect("actual planned building proposal passes C capability preparation",draft.ok,draft.get("reason"))
	if not draft.ok:finish(started);return
	var safety:Dictionary=building.validate_world_draft(draft.view,facts,changes)
	if not safety.ok:
		var query:RefCounted=building.space(draft.view);var conflicts:Array=[]
		for op:Dictionary in changes:
			if op.get("op")!="entity.put" or op.after.kind!="structure":continue
			var v:Dictionary=op.after.data.structure
			for volume:AABB in building.geometry.boxes(v):
				if building.geometry.definition(v).kind!="foundation" and not query.terrain_clear(v.regionId,volume) and conflicts.size()<12:conflicts.append({"terrain":v.id,"bounds":str(volume)})
				for entry:Dictionary in query.candidates(v.regionId,volume.position,volume.end,0):
					if entry.instance.id!=v.id and Geometry.overlap(volume,entry.bounds) and (building.geometry.definition(v).kind=="foundation" or building.geometry.definition(entry.instance).kind=="foundation") and conflicts.size()<12:conflicts.append({"added":v.id,"other":entry.instance.id,"overlap":str(volume.intersection(entry.bounds))})
		print("FAMILY_COLLISION_DIAGNOSTIC "+JSON.stringify(conflicts))
	expect("every actual stepped roof wall foundation resident and exit stays safe",safety.ok,safety)
	if not safety.ok:finish(started);return
	expect("all generated buildings commit atomically",world.commit_prepared(draft.capability).ok)
	var host:=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":facts,"source":{"test":"B consumes actual C persistent rural-2 plan"}})
	expect("formal assembler restores full generated settlement services",assembled.ok,assembled.get("reason"))
	if assembled.ok:
		world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
		var before:=world.snapshot();var again:Dictionary=building.prepare_generation(world)
		expect("repeat generation cannot restock or restore demolished pieces",not again.ok and again.code=="ALREADY_SEEDED" and world.snapshot()==before,again.get("reason"))
		var view:Node3D=building.create_view({"runtime":runtime})
		var pitch:=0;var posts:=0;var geometry_mismatch:Array=[]
		for v:Dictionary in building.structures().instances:
			if v.definitionId.begins_with("roof_pitch_"):pitch+=1
			if v.definitionId=="porch_post":posts+=1
			if v.get("buildingId")!=null and v.get("presentation",{}).has("profile_id"):
				var level:Dictionary=building.current_space().state.storeys.filter(func(s:Dictionary)->bool:return s.id==v.storeyId)[0]
				if v.definitionId in ["foundation","wall","window","door"] and absf(float(v.position.y)-float(level.elevation))>0.00001:geometry_mismatch.append(v.id)
		expect("actual pitched covers and supported porch columns replace flat boxes",pitch>100 and posts>=6,{"roof_pieces":pitch,"porch_posts":posts})
		expect("all structures use real persisted storey elevations",geometry_mismatch.is_empty(),geometry_mismatch)
		expect("all existing dedicated GLBs and semantic materials are loaded",view.objects.size()>10 and view.models.has("city_bed") and view.models.has("city_kitchen"),{"objects":view.objects.size(),"models":view.models.keys()})
		var capture:=runtime.capture_checkpoint();var encoded:=Store.encode(capture);var decoded:=Store.decode(encoded.get("text",""))
		var restored:Dictionary=host._assemble(decoded.capture) if encoded.ok and decoded.ok else {"ok":false,"reason":encoded.get("reason",decoded.get("reason"))}
		expect("real native checkpoint restores nonzero-level family world",restored.ok,restored.get("reason"))
		if restored.ok:
			var after:Dictionary=restored.services.buildings.prepare_generation(restored.world)
			expect("JSON restore cannot change plan stamp or regenerate stock",not after.ok and after.code=="ALREADY_SEEDED",after.get("reason"))
		view.free()
	host.free();finish(started)
