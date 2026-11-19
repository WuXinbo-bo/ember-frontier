extends "res://tests/world/factory_joint.gd"
## Exact historical contracts/plans/cells and old unexplored locks, not a migration.
const Before=preload("res://tests/world/fixtures/factory_generator_before_orientation.gd")
const OldContract=preload("res://tests/world/fixtures/factory_contract_before_orientation.gd")

func run()->void:
	var profiles:Array=Modules.generation_profiles()
	check("low default remains exact historical content2",Data.json_equal(Contract.fresh(profiles),OldContract.fresh(profiles)) and Contract.fresh(profiles).contract.content_version==2)
	var fresh:Dictionary=Contract.fresh(profiles,4,1)
	check("explicit content4 pins complete parcel policy",fresh.ok and fresh.contract.parcel_orientation=="road-court-v1" and Data.json_equal(Contract.resolve(fresh.contract,profiles).get("contract"),fresh.contract))
	for change:Variant in [null,"camera-facing","road-court-v2"]:
		var bad:Dictionary=fresh.contract.duplicate(true)
		if change==null:bad.erase("parcel_orientation")
		else:bad.parcel_orientation=change
		check("saved content4 missing or foreign policy rejected "+str(change),not Contract.resolve(bad,profiles).ok)
	for content:Variant in [0,5,4.5,"4",true]:
		var bad:Dictionary=fresh.contract.duplicate(true);bad.content_version=content
		check("unknown/noninteger content refused "+str(content),not Contract.resolve(bad,profiles).ok)
	for seed:int in [713,2026]:
		for pair:Array in [[1,0],[2,0],[3,0],[3,1]]:
			var version:int=pair[0];var story:int=pair[1];var suffix:String=" seed%d c%d s%d"%[seed,version,story]
			var old:Dictionary=OldContract.fresh(profiles,version,story)
			var policy:Dictionary=Contract.fresh(profiles,version,story)
			check("old lock shape/profile/configuration hash exact"+suffix,Data.json_equal(old,policy) and Data.json_equal(Contract.resolve(old.contract,profiles).get("contract"),old.contract))
			var exact:bool=true
			for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,-1)]:
				var before:Dictionary=Before.plan_region(seed,coord,profiles,old.contract)
				var after:Dictionary=Factory.plan_region(seed,coord,profiles,policy.contract)
				exact=exact and before.ok and after.ok and Data.json_equal(before.plan,after.plan)
			check("all initial/positive/negative old plans exact"+suffix,exact)
			var before:Dictionary=Before.generate(seed,profiles,old.contract)
			var after:Dictionary=Factory.generate(seed,profiles,policy.contract)
			check("historical raster entities and explored source untouched"+suffix,before.has("chunks") and after.has("chunks") and raster_digest(before)==raster_digest(after) and Data.json_equal(before.entities,after.entities) and Data.json_equal(before.extensions,after.extensions))
			if not after.has("chunks"):return finish()
			var made:Dictionary=Assembly.prepare(after)
			var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.ok else made;host.free()
			check("real Native loads each old opening"+suffix,built.ok,built.get("reason"))
			if not built.ok:return finish()
			var saved:Dictionary=Store.encode(built.runtime.capture_checkpoint())
			var decoded:Dictionary=Store.decode(saved.text) if saved.ok else saved
			var restored:Dictionary={}
			if decoded.ok:
				host=Native.new();restored=host._assemble(decoded.capture);host.free()
			check("old Native cold restore retains lock/source receipts"+suffix,restored.get("ok",false) and Data.json_equal(restored.world.extension(Factory.CONFIG_KEY),old.contract) and Data.json_equal(restored.world.extension("generation:RH-HOME"),after.extensions["generation:RH-HOME"]) and Data.json_equal(restored.world.extension("r34:modules"),built.world.extension("r34:modules")))
			if not restored.get("ok",false):return finish()
			var input:Dictionary=Factory.region_generation_input(restored.world,profiles)
			var new_draft:Dictionary=Factory.draft_region_request(input,Vector2i(-1,-1))
			var old_draft:Dictionary=Before.draft_region(seed,Vector2i(-1,-1),profiles,old.contract)
			check("unexplored recovered old lock never upgrades to4"+suffix,new_draft.ok and old_draft.ok and Data.json_equal(new_draft.plan,old_draft.plan) and raster_digest({"chunks":new_draft.chunks})==raster_digest({"chunks":old_draft.chunks}))
			var revisit:Dictionary=Factory.prepare_region_draft(restored.world,Factory.draft_region_request(input,Vector2i.ZERO),restored.world.get_revision())
			check("old explored sources/contents never replay"+suffix,revisit.ok and revisit.already_generated and revisit.world_changes.is_empty() and revisit.module_seeds.is_empty() and revisit.initial_stocks.is_empty())
			costs[suffix]={"raster_sha256":raster_digest(after),"configuration_sha256":Contract.digest(old.contract),"module_transforms":built.world.extension("r34:modules").instances.map(func(m:Dictionary)->Dictionary:return {"id":m.id,"q":m.quarter_turn,"at":m.position}),"native_bytes":saved.text.length()}
	costs.scope="Exact pre-content4 source fixtures, both seeds, historical1/2/3 story0/1, real Native cold saves and unexplored old locks. No formal entry switch/PCK/OS/VA/performance."
	finish()
