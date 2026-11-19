extends "res://tests/world/factory_joint.gd"
## Explicit new-world annotation only. E owns reading/knowledge, not this test.
const BeforeStory=preload("res://tests/world/fixtures/factory_generator_before_story.gd")

func without_clues(plan:Dictionary)->Dictionary:
	var copy:Dictionary=plan.duplicate(true)
	copy.erase("configuration_sha256")
	for seed:Dictionary in copy.module_seeds:seed.erase("story_clues")
	return copy

func store_seed(plan:Dictionary)->Dictionary:
	for seed:Dictionary in plan.module_seeds:
		if seed.purpose=="store":return seed
	return {}

func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var policy:Dictionary=Contract.fresh(profiles,3,1)
	check("new explicit story lock resolves exactly",policy.ok and Data.json_equal(Contract.resolve(policy.contract,profiles).get("contract"),policy.contract))
	if not policy.ok:return finish()
	check("low-level default still omits all story annotation policy",not Contract.fresh(profiles).contract.has("story_clue_version") and Contract.fresh(profiles).contract.content_version==2)
	for content:int in [1,2]:check("old content cannot silently acquire a clue policy "+str(content),Contract.fresh(profiles,content,1).get("code")=="UNSUPPORTED_FACTORY_STORY_CLUE_VERSION")
	for value:Variant in [2,-1,"1",true]:
		var invalid:Dictionary=policy.contract.duplicate(true);invalid.story_clue_version=value
		check("unknown or noninteger clue lock refused "+str(value),not Contract.resolve(invalid,profiles).get("ok",false))
	for seed:int in [713,2026]:
		for content:int in [1,2,3]:
			var old:Dictionary=Contract.fresh(profiles,content);var unchanged:bool=true
			for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(-1,0)]:
				var before:Dictionary=BeforeStory.plan_region(seed,coord,profiles,old.contract)
				var current:Dictionary=Factory.plan_region(seed,coord,profiles,old.contract)
				unchanged=unchanged and before.ok and current.ok and Data.json_equal(before.plan,current.plan) and current.plan.module_seeds.all(func(s:Dictionary)->bool:return not s.has("story_clues"))
			check("frozen16 old exact plans no rewrite v%d seed%d"%[content,seed],unchanged)
		var generated:Dictionary=Factory.generate(seed,profiles,policy.contract)
		check("new annotated actual voxel world generates "+str(seed),generated.has("chunks"),generated.get("reason"))
		if not generated.has("chunks"):return finish()
		var village:Dictionary=generated.extensions["generation:RH-VILLAGE"]
		var source:Dictionary=store_seed(village);var clues:Array=source.get("story_clues",[])
		check("only actual store carries one persistent clue "+str(seed),clues.size()==1 and generated.extensions["generation:RH-HOME"].module_seeds.all(func(s:Dictionary)->bool:return not s.has("story_clues")) and village.module_seeds.all(func(s:Dictionary)->bool:return s.purpose=="store" or not s.has("story_clues")))
		if clues.size()!=1:return finish()
		var clue:Dictionary=clues[0];var sites:Array=village.regional_sites.filter(func(s:Dictionary)->bool:return s.id==clue.site_id)
		check("descriptor resolves stable real source module and stone site "+str(seed),Data.valid_id(clue.id) and clue.id==source.source_key+":route-record:"+clue.site_id and clue.source_key==source.source_key and clue.module_id==source.id and clue.story_id=="ST03" and clue.kind=="route-record" and sites.size()==1 and sites[0].kind=="stone-roadfall-v1" and sites[0].region_id==source.region)
		check("description names actual bypass not bridge or inventory "+str(seed),clue.text.contains("塌石") and clue.text.contains("侧肩") and not clue.text.contains("桥") and not clue.has("items") and not clue.has("reward") and sites[0].obstacle_cells.size()==24 and sites[0].goal_corridor.bypass_points.size()==2)
		# Compare like-for-like rasterized persisted plans: draft_plan adds
		# field_surfaces; a pre-raster pure plan is intentionally not equal.
		var repeated:Dictionary=Factory.draft_region(seed,Vector2i(0,-1),profiles,policy.contract)
		var historical:Dictionary=BeforeStory.draft_region(seed,Vector2i(0,-1),profiles,Contract.fresh(profiles,3).contract)
		check("annotation repeat exact and geometric plan unchanged "+str(seed),repeated.ok and Data.json_equal(village,repeated.plan) and historical.ok and Data.json_equal(without_clues(village),without_clues(historical.plan)))
		var opening:Dictionary=Assembly.prepare(generated)
		check("same formal assembly consumes annotated source "+str(seed),opening.ok,opening.get("reason"))
		if not opening.ok:return finish()
		var module_state:Dictionary=opening.capture.world.extensions["r34:modules"]
		var receipt:Dictionary=module_state.source_receipts.get(source.source_key,{})
		var stocks:Array=opening.capture.facts.stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==source.id)
		check("actual B receipt and finite stocks resolve same descriptor source "+str(seed),receipt.get("module_id")==source.id and not stocks.is_empty() and stocks.all(func(s:Dictionary)->bool:return s.id in receipt.get("stock_ids",[])))
		var legacy_world:Dictionary=BeforeStory.generate(seed,profiles,Contract.fresh(profiles,3).contract)
		var legacy_opening:Dictionary=Assembly.prepare(legacy_world)
		check("annotation adds no actor inventory tool record module or raster "+str(seed),legacy_opening.ok and Data.json_equal(opening.capture.facts,legacy_opening.capture.facts) and Data.json_equal(module_state,legacy_opening.capture.world.extensions["r34:modules"]) and raster_digest(generated)==raster_digest(legacy_world) and Data.json_equal(generated.entities,legacy_world.entities))
		var host:=Native.new();var built:Dictionary=host._assemble(opening.capture);host.free()
		check("same Native runtime accepts annotated actual world "+str(seed),built.ok,built.get("reason"))
		if not built.ok:return finish()
		var cold:Dictionary=built.world.prepare_region_residency("RH-VILLAGE",false,built.world.get_revision())
		var tx:Dictionary=built.world.prepare_changes(cold.world_changes,built.world.get_revision()) if cold.ok else cold
		var cooled:Dictionary=built.world.commit_prepared(tx.capability) if tx.ok else tx
		check("actual cold pages retain source descriptor without new facts "+str(seed),cooled.ok and not built.world.region_is_resident("RH-VILLAGE") and Data.json_equal(built.world.extension("generation:RH-VILLAGE"),village))
		var saved:Dictionary=Store.encode(built.runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.text) if saved.ok else saved
		var restored:Dictionary={}
		if decoded.ok:
			host=Native.new();restored=host._assemble(decoded.capture);host.free()
		check("Native cold save exact descriptor contract and module receipts "+str(seed),restored.get("ok",false) and Data.json_equal(restored.world.extension("generation:RH-VILLAGE"),village) and Data.json_equal(restored.world.extension(Factory.CONFIG_KEY),policy.contract) and Data.json_equal(restored.world.extension("r34:modules"),module_state),restored.get("reason"))
		if not restored.get("ok",false):return finish()
		var draft:Dictionary=Factory.draft_region_request(Factory.region_generation_input(restored.world,profiles),Vector2i(0,-1))
		var revisit:Dictionary=Factory.prepare_region_draft(restored.world,draft,restored.world.get_revision())
		check("cold revisit returns original clue no respawn or replenishment "+str(seed),revisit.ok and revisit.already_generated and revisit.world_changes.is_empty() and revisit.initial_stocks.is_empty() and revisit.module_seeds.is_empty() and Data.json_equal(revisit.plan,village))
		costs[str(seed)]={"descriptor":clue,"stock_ids":receipt.stock_ids,"raster_sha256":raster_digest(generated),"native_bytes":saved.text.length()}
	costs.scope="C explicit new-world annotation, exact frozen16 plan compatibility and actual A/B/Native cold save source path only. E onsite reading/map consumer, PCK, OS, VA and performance remain separate."
	finish()
