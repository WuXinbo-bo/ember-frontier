extends "res://tests/world/village_contours.gd"
const Layout=preload("res://scripts/world/bounded_layout.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const SEEDS=[713,2026,973339546,275196493,0,1,2147483646,2147483647,1034690049,553890622]
func run()->void:
	var profiles:Array=Building.generation_profiles()
	var rows:Array=[];var combinations:Dictionary={}
	var original:Dictionary=Contract.fresh(profiles).contract
	var bounded:Dictionary=original.duplicate(true);bounded.layout_policy=Layout.POLICY.duplicate()
	check("explicit persisted layout policy resolves",Contract.resolve(bounded,profiles).ok)
	for bad:Variant in [{"id":"rural-bounded-layout","version":2},{"id":"unknown","version":1},{"id":"rural-bounded-layout","version":1,"unreviewed":true}]:
		var input:Dictionary=bounded.duplicate(true);input.layout_policy=bad
		check("unknown layout policy cannot be silently reinterpreted "+str(bad),not Contract.resolve(input,profiles).ok)
	for seed:int in SEEDS:
		var choices:Array=[];var pad_valid:=true
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
			var a:Dictionary=Landscape.plan_region(seed,coord,profiles,bounded);var b:Dictionary=Landscape.plan_region(seed,coord,profiles,bounded)
			check("bounded full plan deterministic %d/%s"%[seed,coord],a.ok and b.ok and Data.json_equal(a,b))
			if not a.ok:continue
			pad_valid=pad_valid and Layout.constraint_error(a.plan.parcels,coord).is_empty()
			choices.append(a.plan.parcels[0].layout_choice.candidate)
		check("actual full B pad/reservations keep hub and body corridor "+str(seed),pad_valid)
		combinations[str(choices)]=true
		if seed not in [713,2026,973339546,275196493]:continue
		var source:Dictionary=Landscape.generate(seed,profiles,bounded)
		var assembled:Dictionary=Assembly.prepare(source)
		check("full sole A/B assembly accepts bounded source "+str(seed),assembled.ok,assembled.get("reason"))
		if not assembled.ok:continue
		var world:=State.new();world.load_snapshot(assembled.capture.world)
		var runtime:=Runtime.new();var building:=Building.new()
		check("actual runtime configures bounded source "+str(seed),runtime.configure({"world":world,"facts":assembled.capture.facts,"services":{"buildings":building,"actions":Actions.new(),"production":Production.new()}}).ok)
		walk_paths(world,building,"bounded critical seed "+str(seed))
		var row:Dictionary={"seed":seed,"choices":choices,"home_risers":risers(world),"village_risers":region_risers(world,"RH-VILLAGE"),"chunks":world.chunk_keys().size()}
		var reference_source:Dictionary=Landscape.generate(seed,profiles,original)
		var reference:=State.new();reference.load_snapshot(reference_source)
		row.comparable_regions={}
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var common:Dictionary=reference.extension("generation:"+region)
			row.comparable_regions[region]={"baseline":region_risers(reference,region,common),"bounded":region_risers(world,region,common),"mask":"same original pad/landform mask on both rasters"}
		rows.append(row)
		if seed==973339546:
			var captured:Dictionary=Rural.region_generation_input(world,profiles)
			var draft:Dictionary=Rural.draft_region_request(captured,Vector2i(1,0))
			var prepared:Dictionary=Rural.prepare_region_draft(world,draft,world.get_revision()) if draft.ok else draft
			var tx:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision()) if prepared.ok else prepared
			check("true coordinate peripheral draft keeps exact layout policy",tx.ok and draft.plan.layout_policy==Layout.POLICY)
			if tx.ok:world.commit_prepared(tx.capability)
			var saved:Dictionary=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:bounded:save")
			var decoded:Dictionary=Codec.decode_checkpoint(saved.envelope) if saved.ok else saved
			var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
			check("three-region native codec keeps exact authoritative raster and policy",loaded.ok and raster_digest(world.snapshot())==raster_digest(restored.snapshot()) and Data.json_equal(restored.extension("generation:rural2").get("layout_policy"),Layout.POLICY),{"load":loaded,"decode_ok":decoded.ok,"policy":restored.extension("generation:rural2").get("layout_policy") if loaded.ok else null,"raster_equal":raster_digest(world.snapshot())==raster_digest(restored.snapshot()) if loaded.ok else false})
			var no_policy:Dictionary=original.duplicate(true)
			var old:Dictionary=Landscape.plan_region(seed,Vector2i.ZERO,profiles,no_policy)
			check("old pinned layout does not acquire policy/choice",old.ok and not old.plan.has("layout_policy") and not old.plan.parcels[0].has("layout_choice"))
	check("fixed ten seeds produce multiple finite layout combinations",combinations.size()>=3,combinations.keys())
	costs.rows=rows;costs.layout_combinations=combinations.keys();costs.scope="Explicit bounded policy candidate; missing policy remains original v4 exactly. Actual full A/B assembly/body routes on four critical seeds, ten full-plan constraints. Long risers measured, no new height model or VA claim. Default unchanged until evaluated/adopted."
	finish()
