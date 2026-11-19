extends "res://tests/world/factory_coordinate_roundtrip.gd"
## Exact persisted facts and an actual pre-save future worker, no float tolerance.

func run()->void:
	var profiles:Array=Catalog.profiles();var configured:Dictionary=Contract.fresh(profiles,4,1)
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(Factory.generate(713,profiles,configured.contract))
	check("actual4/1 authority loads",loaded.ok)
	if not loaded.ok:return finish()
	var south:Dictionary=Factory.draft_region_request(Factory.region_generation_input(world,profiles),Vector2i(0,1))
	var ready:Dictionary=Factory.prepare_region_draft(world,south,world.get_revision()) if south.ok else south
	var prepared:Dictionary=world.prepare_changes(ready.world_changes,world.get_revision()) if ready.ok else ready
	var accepted:Dictionary=world.commit_prepared(prepared.capability) if prepared.ok else prepared
	check("actual fractional-mouth south region commits",accepted.ok,accepted.get("reason"))
	if not accepted.ok:return finish()
	var pending:Dictionary=Factory.draft_region_request(Factory.region_generation_input(world,profiles),Vector2i(1,1))
	check("real still-unexplored adjacent worker prepares before save",pending.ok and world.region(Factory.region_id(Vector2i(1,1))).is_empty())
	var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"r34:coordinate:identity")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();loaded=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("codec and strict authority load succeed",loaded.ok,loaded.get("reason"))
	if not loaded.ok:return finish()
	check("decoded full persistent state equals actual restored snapshot exactly",Data.json_equal(decoded.state,restored.snapshot()))
	var original_records:Dictionary={"identity":world.identity(),"regions":world.snapshot().regions,"entities":world.snapshot().entities,"config":world.config(),"retired":world.retired_entity_ids()}
	var restored_records:Dictionary={"identity":restored.identity(),"regions":decoded.state.regions,"entities":decoded.state.entities,"config":restored.config(),"retired":restored.retired_entity_ids()}
	var boundary:Dictionary=Roundtrip.compare(713,"@world",original_records,restored_records,"world")
	check("live identity regions and entity facts match except exact82 approved geometric leaves",boundary.ok,boundary)
	check("live authoritative generation contract and identity digest stay strict",Data.json_equal(world.extension(Factory.CONFIG_KEY),restored.extension(Factory.CONFIG_KEY)) and Contract.digest(world.extension(Factory.CONFIG_KEY))==Contract.digest(restored.extension(Factory.CONFIG_KEY)))
	check("all factual voxel buffers survive codec exactly",raster_digest(world.snapshot())==raster_digest(restored.snapshot()))
	var admitted:Dictionary=Factory.prepare_region_draft(restored,pending,restored.get_revision())
	check("real pre-save future worker is admitted by restored exact configuration lock",admitted.ok and not admitted.get("already_generated",false),admitted.get("code"))
	var tx:Dictionary=restored.prepare_changes(admitted.world_changes,restored.get_revision()) if admitted.ok else admitted
	accepted=restored.commit_prepared(tx.capability) if tx.ok else tx
	check("same old worker commits real future region after restore without migration",accepted.ok and Data.json_equal(restored.extension("generation:"+pending.region.id),pending.plan),accepted.get("reason"))
	var known:Dictionary=Factory.prepare_region_draft(restored,south,restored.get_revision())
	check("known decoded source remains persisted rather than replaying stale live plan",known.ok and known.already_generated and known.world_changes.is_empty() and Data.json_equal(known.plan,decoded.state.extensions["generation:RH-HOME"])==false and Data.json_equal(known.plan,decoded.state.extensions["generation:"+south.region.id]))
	costs={"payload_bytes":encoded.envelope.payloadBytes,"original_plan_summary":Contract.digest(world.extension("generation:"+south.region.id)),"decoded_plan_summary":Contract.digest(decoded.state.extensions["generation:"+south.region.id]),"configuration_sha256":Contract.digest(restored.extension(Factory.CONFIG_KEY)),"restored_regions":restored.regions().size(),"bounded_live_records":boundary,"scope":"actual C world/codec identity, exact decoded persistence and pre-save future-worker admission; only A exact82 indexed live coordinate observations, no global float tolerance/B module registration/package/OS acceptance"}
	finish()
