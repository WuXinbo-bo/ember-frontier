extends RefCounted
## Complete expected capture through original C residency changes, no Runtime.
const World=preload("res://scripts/world/world_state.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
const Data=preload("res://scripts/world/world_data.gd")
static func compare(capture:Dictionary,runtime:RefCounted,batch:int)->Dictionary:
	if batch<=0:return {"ok":false,"reason":"missing_exact_native_batch"}
	var oracle:=World.new();var loaded:Dictionary=oracle.load_snapshot(capture.world)
	if not loaded.get("ok",false):return loaded
	var batches:Array=[]
	for region:String in Residency.required_regions(runtime):
		while not oracle.region_is_resident(region):
			var conversion:Dictionary=oracle.prepare_region_residency(region,true,oracle.get_revision(),batch)
			if not conversion.get("ok",false) or conversion.world_changes.is_empty():return {"ok":false,"reason":"expected_residency_stalled"}
			batches.append({"region":region,"revision":oracle.get_revision(),"changes_sha256":JSON.stringify(conversion.world_changes,"",true,true).sha256_text()})
			var prepared:Dictionary=oracle.prepare_changes(conversion.world_changes,oracle.get_revision())
			if not prepared.get("ok",false):return prepared
			var committed:Dictionary=oracle.commit_prepared(prepared.capability)
			if not committed.get("ok",false):return committed
	var expected:Dictionary=capture.duplicate(true);expected.world=oracle.snapshot()
	var actual:Dictionary=runtime.capture_checkpoint();var fields:Dictionary={};var same:bool=true
	for field:String in expected:
		fields[field]=actual.has(field) and Data.json_equal(expected[field],actual[field]);same=same and fields[field]
	for field:String in actual:same=same and expected.has(field)
	return {"ok":same,"fields":fields,"residency_batches":batches}
