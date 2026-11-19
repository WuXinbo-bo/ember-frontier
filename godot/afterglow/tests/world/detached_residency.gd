extends SceneTree
## Existing actual normal24 input. No generation, renderer, save-slot or A runner.
const State=preload("res://scripts/world/world_state.gd")
const Before=preload("res://tests/world/fixtures/residency_20261116_before.gd")
const Detached=preload("res://scripts/world/detached_residency.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Page=preload("res://scripts/world/chunk_page.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
var checks:Array=[]
var costs:Dictionary={}
var report:String
var target:String="R34:1:1"
var input_sha:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func apply(world:RefCounted,changes:Array)->Dictionary:
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	return world.commit_prepared(draft.capability) if draft.ok else draft
func digest(world:RefCounted)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	for key:String in world.region_chunk_keys(target):
		var c:Dictionary=world.chunk(key);var cells:PackedInt32Array=c.cells
		if c.has("cell_page"):
			var decoded:Dictionary=Page.unpack(c.cell_page,int(world.config().chunkCells)**3,Data.MATERIALS)
			if not decoded.ok:return "invalid page"
			cells=decoded.cells
		hash.update(key.to_utf8_buffer());hash.update(cells.to_byte_array())
	return hash.finish().hex_encode()
func values_only(value:Variant)->bool:
	if value is Object or value is Callable or value is Signal:return false
	if value is Dictionary:
		for key:Variant in value:
			if not key is String or not values_only(value[key]):return false
	if value is Array:
		for item:Variant in value:
			if not values_only(item):return false
	return true
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"input_sha256":input_sha,"target":target,"costs":costs,"scope":"post18 C source API/worker/CAS and real Native normal facts; deterministic authority-race fixtures disclosed; no generation/app/renderer/import/export/OS/RSS/fixed-performance qualification"},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
func worker(input:Dictionary)->Dictionary:
	var thread:=Thread.new();var began:int=Time.get_ticks_usec()
	var started:int=thread.start(State.prepare_detached_region_residency.bind(input))
	if started!=OK:return {"ok":false,"code":"TEST_THREAD_START"}
	var pumps:int=0
	while thread.is_alive():pumps+=1;await process_frame
	var result:Dictionary=thread.wait_to_finish()
	result.test_worker_wall_usec=Time.get_ticks_usec()-began;result.test_pumps=pumps
	return result
func run()->void:
	var args:=OS.get_cmdline_user_args();report=args[0];input_sha=FileAccess.get_sha256(args[1])
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("existing actual18 joint24 normal input decodes, no new world generation",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var source:Dictionary=decoded.capture.world
	check("input is original24/content4/story1 and original three identities",source.regions.size()==24 and source.extensions["generation:factory-r34"].content_version==4 and source.extensions["generation:factory-r34"].story_clue_version==1 and decoded.capture.facts.actors.size()==3)
	var world:=State.new();var old:=Before.new()
	check("both C implementations validate identical canonical input",world.load_snapshot(source).ok and old.load_snapshot(source).ok)
	if checks.any(func(c:Dictionary)->bool:return not c.ok):return finish()
	var original:Dictionary=world.snapshot();var raster:String=digest(world)
	var capture:Dictionary=world.capture_region_residency(target,false,world.get_revision())
	check("capture detaches exactly256 target buffers and all guards within4MiB",capture.ok and capture.input.rows.size()==256 and capture.input.basis.chunks.size()==256 and capture.cost.detached_payload_bytes==4194304,capture.get("cost"))
	if not capture.ok:return finish()
	check("DTO contains no World/Runtime/Node/capability/callable",values_only(capture.input))
	check("capture contains no irrelevant world graph and is not a commit",capture.input.basis.size()==5 and not capture.input.has("world") and Data.json_equal(original,world.snapshot()))
	var isolated:Dictionary=capture.input.duplicate(true)
	isolated.rows[0].cells[0]=99;isolated.basis.region.bounds.min.x-=1;isolated.basis.chunks.values()[0].revision+=1
	check("cell/region/nested guard mutation cannot alias live or original DTO",Data.json_equal(original,world.snapshot()) and capture.input.rows[0].cells[0]!=99 and capture.input.basis.region.bounds.min.x==world.region(target).bounds.min.x)
	var cold:Dictionary=await worker(capture.input)
	var legacy:Dictionary=old.prepare_region_residency(target,false,old.get_revision())
	check("real Thread pure conversion equals old before/resident/hash/page bytes",cold.ok and legacy.ok and Data.json_equal(cold.world_changes,legacy.world_changes) and cold.remaining_chunks==legacy.remaining_chunks and cold.complete==legacy.complete and Data.json_equal(cold.state_before,legacy.state_before),cold.get("reason"))
	check("worker conversion cannot mutate live authority or DTO buffers",Data.json_equal(original,world.snapshot()) and capture.input.rows[0].cells.size()==4096)
	check("every before keeps exact original revision/resident/SHA",cold.world_changes.all(func(c:Dictionary)->bool:return c.before.size()==3 and c.before.revision==world.chunk(c.id).revision and c.before.resident==world.chunk(c.id).resident and c.before.sha256==Page.fingerprint(world.chunk(c.id).cells)))
	var forged_input:Dictionary=capture.input.duplicate(true);forged_input.rows[-1].cells[0]=3 if forged_input.rows[-1].cells[0]!=3 else 2
	var forged:Dictionary=State.prepare_detached_region_residency(forged_input)
	check("detached cell tampering cannot forge original hash CAS",forged.ok and world.prepare_changes(forged.world_changes,world.get_revision()).get("code")=="CAS_MISMATCH" and Data.json_equal(original,world.snapshot()))
	var altered:Array=cold.world_changes.duplicate(true);var fake:PackedInt32Array=world.chunk(altered[-1].id).cells;fake[0]=3 if fake[0]!=3 else 2
	altered[-1].after.cell_page=Page.pack(fake,4096,Data.MATERIALS).page
	check("valid but different output page cannot change source facts",world.prepare_changes(altered,world.get_revision()).get("code")=="CHUNK_STORAGE_CONTENT_MISMATCH" and Data.json_equal(original,world.snapshot()))
	costs.initial_capture=capture.cost;costs.worker_cold=cold.cost;costs.worker_cold.wall_usec=cold.test_worker_wall_usec;costs.worker_cold.main_pumps=cold.test_pumps
	# Deterministic race fixture in this isolated authority: last chunk changes
	# after capture. This is NOT a player terrain command or normal play claim.
	var last:String=cold.world_changes[-1].id;var q:Vector3i=Data.coord(last)
	var cell:Dictionary={"x":q.x*16,"y":q.y*16,"z":q.z*16};var value:int=world.cell_at(cell.x,cell.y,cell.z)
	var edited:Dictionary=apply(world,[{"op":"voxel.set","cell":cell,"before":value,"after":3 if value!=3 else 2}])
	var raced:Dictionary=world.snapshot();var denied:Dictionary=world.prepare_changes(cold.world_changes,world.get_revision())
	check("one LAST target chunk conflict rejects whole256 before any mutation",edited.ok and denied.get("code")=="CAS_MISMATCH" and Data.json_equal(raced,world.snapshot()),denied)
	var fresh:Dictionary=world.capture_region_residency(target,false,world.get_revision())
	cold=await worker(fresh.input)
	var changed_raster:String=digest(world);var accepted:Dictionary=apply(world,cold.world_changes)
	check("fresh capture retains real intervening cell change and cools losslessly",accepted.ok and world.region_residency_state(target).paged and world.region_residency_state(target).unpacked_bytes==0 and digest(world)==changed_raster)
	var warm_capture:Dictionary=world.capture_region_residency(target,true,world.get_revision());var warm:Dictionary=await worker(warm_capture.input)
	var old_cold:=Before.new();old_cold.load_snapshot(world.snapshot());var old_warm:Dictionary=old_cold.prepare_region_residency(target,true,old_cold.get_revision())
	check("warm worker equals old lossless restoration including exact before",warm.ok and old_warm.ok and Data.json_equal(warm.world_changes,old_warm.world_changes))
	var warm_copy:Array=warm.world_changes.duplicate(true);warm_copy[0].after.cells[0]=99
	check("warm result arrays cannot alias input pages or authority",not world.region_is_resident(target) and warm.world_changes[0].after.cells[0]!=99 and warm_capture.input.rows[0].cells.is_empty())
	var bad:Dictionary=warm_capture.input.duplicate(true);bad.rows[0].cell_page.compressed_sha256="0".repeat(64)
	var corrupt:Dictionary=State.prepare_detached_region_residency(bad)
	check("corrupt worker page rejected without changing cold source",not corrupt.ok and digest(world)==changed_raster,corrupt)
	var warmed:Dictionary=apply(world,warm.world_changes)
	check("full256 warm restores every edited cell and frees every page",warmed.ok and world.region_is_resident(target) and world.region_residency_state(target).page_chunks==0 and digest(world)==changed_raster)
	costs.worker_warm=warm.cost;costs.worker_warm.wall_usec=warm.test_worker_wall_usec;costs.worker_warm.main_pumps=warm.test_pumps
	var no_work:Dictionary=world.capture_region_residency(target,true,world.get_revision());var no_result:Dictionary=State.prepare_detached_region_residency(no_work.input)
	check("already warm request is idempotent and does not reissue cells",no_result.ok and no_result.complete and no_result.world_changes.is_empty())
	check("new capture rejects stale/unknown/over-budget without authority changes",world.capture_region_residency(target,false,-1).get("code")=="STALE_WORLD_REVISION" and world.capture_region_residency("absent",false,world.get_revision()).get("code")=="UNKNOWN_REGION" and world.capture_region_residency(target,false,world.get_revision(),0).get("code")=="INVALID_RESIDENCY_BUDGET" and world.capture_region_residency(target,false,world.get_revision(),257).get("code")=="INVALID_RESIDENCY_BUDGET")
	var bad_requests:Array=[{},capture.input.duplicate(true),capture.input.duplicate(true),capture.input.duplicate(true),capture.input.duplicate(true)]
	bad_requests[1].max_chunks=257;bad_requests[2].rows[0].id="absent";bad_requests[3].basis.chunks.erase(capture.input.rows[0].id);bad_requests[4].rows[0].cells[0]=99
	check("malformed count/key/guard/unknown-material DTOs are all rejected",bad_requests.all(func(v:Dictionary)->bool:return not State.prepare_detached_region_residency(v).ok))
	var oversized:Dictionary=warm_capture.input.duplicate(true);oversized.rows[0].cell_page.data="A".repeat(Detached.MAX_INPUT_BYTES+4)
	check("8MiB byte envelope rejects oversized data before page decode",State.prepare_detached_region_residency(oversized).get("code")=="DETACHED_RESIDENCY_BUDGET")
	var with_object:Dictionary=capture.input.duplicate(true);with_object.state_before={"not_a_value":world}
	var extra:Dictionary=capture.input.duplicate(true);extra.forbidden_world=world
	check("worker rejects embedded authority objects and unknown DTO channels",not State.prepare_detached_region_residency(with_object).ok and not State.prepare_detached_region_residency(extra).ok)
	var changed:Dictionary=world.snapshot();var backwards:Dictionary=world.prepare_region_residency(target,false,world.get_revision(),8192)
	var frozen_old:=Before.new();frozen_old.load_snapshot(changed);var original_api:Dictionary=frozen_old.prepare_region_residency(target,false,frozen_old.get_revision(),8192)
	check("unchanged legacy API retains8192 range and exact original outputs",Data.json_equal(backwards.world_changes,original_api.world_changes) and backwards.complete==original_api.complete and backwards.expected_world_revision==original_api.expected_world_revision and Data.json_equal(backwards.state_before,original_api.state_before))
	check("legacy chunk.residency cannot falsely warm a page",old_cold.prepare_changes([{"op":"chunk.residency","id":last,"before":false,"after":true}],old_cold.get_revision()).get("code")=="CHUNK_PAGE_REQUIRES_RESTORE")
	var bounded:Array=[]
	for desired:bool in [false,true]:
		var batches:int=0;var complete:bool=false
		while batches<9 and not complete:
			var part:Dictionary=world.capture_region_residency(target,desired,world.get_revision(),32);var prepared:Dictionary=State.prepare_detached_region_residency(part.input) if part.ok else part
			if not prepared.ok:break
			var done:Dictionary=apply(world,prepared.world_changes)
			if not done.ok:break
			batches+=1;complete=prepared.complete
		bounded.append({"resident":desired,"batches":batches,"complete":complete})
		check("explicit32 chunk detached batches finish without losing edited raster "+str(desired),complete and batches==8 and digest(world)==changed_raster and world.region_is_resident(target)==desired,bounded[-1])
	# Same-input C-only costs: identical actual source, legacy32 versus one
	# detached256 conversion. This does not compare renderer frames or change A.
	var old_costs:Array=[];var candidate_costs:Array=[]
	for sample:int in 3:
		var w:=State.new();w.load_snapshot(source)
		var legacy_row:Dictionary={"prepare_usec":0,"cas_usec":0,"total_usec":0};var begin:int=Time.get_ticks_usec()
		for batch:int in 8:
			var start:int=Time.get_ticks_usec();var part:Dictionary=w.prepare_region_residency(target,false,w.get_revision(),32);legacy_row.prepare_usec+=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec();var done:Dictionary=apply(w,part.world_changes);legacy_row.cas_usec+=Time.get_ticks_usec()-start
			if not done.ok:check("legacy cost sample commits",false,done);break
		legacy_row.total_usec=Time.get_ticks_usec()-begin;old_costs.append(legacy_row)
		w=State.new();w.load_snapshot(source);var start:int=Time.get_ticks_usec();var cap:Dictionary=w.capture_region_residency(target,false,w.get_revision())
		var measured:Dictionary={"capture_usec":Time.get_ticks_usec()-start};var ready:Dictionary=await worker(cap.input)
		measured.worker_usec=ready.cost.prepare_usec;measured.worker_wall_usec=ready.test_worker_wall_usec;start=Time.get_ticks_usec();var done:Dictionary=apply(w,ready.world_changes)
		measured.cas256_usec=Time.get_ticks_usec()-start;measured.main_capture_plus_cas_usec=measured.capture_usec+measured.cas256_usec;candidate_costs.append(measured)
		check("same-input cost sample preserves exact semantic raster "+str(sample),done.ok and digest(w)==raster)
	costs.C_only_same_input={"legacy32":old_costs,"detached256":candidate_costs,"note":"legacy prepare+8 C CAS versus detached capture+1 C CAS; no Native owner or OS cost; no automatic A batch-size change"}
	await actual_native(decoded.capture)
	finish()

func actual_native(source:Dictionary)->void:
	var native:=Native.new();var built:Dictionary=native._assemble(source);native.free()
	check("real current Native assembles same canonical normal24 input",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world;var original_digest:String=digest(world)
	var begin:int=Time.get_ticks_usec();var cap:Dictionary=world.capture_region_residency(target,false,world.get_revision());var capture_usec:int=Time.get_ticks_usec()-begin
	check("actual Native target remains unpinned by existing bodies/routes",not preload("res://scripts/runtime/region_residency.gd").required_regions(runtime).has(target))
	if not cap.ok:check("actual Native target captures",false,cap);runtime.retire();return
	var old_revision:int=world.get_revision();var old_time:float=runtime.clock();var thread:=Thread.new()
	var started:int=thread.start(State.prepare_detached_region_residency.bind(cap.input));var ticks:int=0
	if started!=OK:check("actual Native worker starts",false);runtime.retire();return
	# The real Runtime alone continues normal actors/needs/production while
	# conversion owns detached values. A current-pins/epoch test is not bypassed.
	while thread.is_alive() and ticks<12:
		runtime.tick(0.1);ticks+=1;await process_frame
	while thread.is_alive():await process_frame
	var ready:Dictionary=thread.wait_to_finish()
	if ticks==0:runtime.tick(0.1);ticks=1
	var facts_before:Dictionary=runtime.facts();var time_before:float=runtime.clock();var extensions_before:Dictionary=world.snapshot().extensions
	check("background real facts/time can advance without staling unchanged target",ready.ok and runtime.clock()>old_time and digest(world)==original_digest,{"ticks":ticks,"old_world_revision":old_revision,"current_world_revision":world.get_revision(),"old_time":old_time,"time":runtime.clock()})
	var event:Dictionary={"kind":"region-storage-changed","region_id":target,"resident":false}
	var expected_event:Dictionary=event.duplicate(true);expected_event.id="event:%s:0"%(runtime.get_revision()+1);expected_event.revision=runtime.get_revision()+1;expected_event.time=runtime.clock();begin=Time.get_ticks_usec()
	var committed:Dictionary=runtime._commit({"world_changes":ready.world_changes,"events":[event]}) if ready.ok else ready
	var commit_usec:int=Time.get_ticks_usec()-begin
	var facts_after:Dictionary=runtime.facts();var expected_ledger:Array=facts_before.get("ledger",[]).duplicate(true)
	# Construct the exact event independently before commit; never adopt the
	# actual output as its own oracle. Keep all previous bounded rows exactly.
	var tail:Dictionary=facts_after.ledger[-1] if not facts_after.ledger.is_empty() else {}
	var ledger_ok:bool=Data.json_equal(expected_event,tail)
	expected_ledger.append(expected_event)
	if expected_ledger.size()>256:expected_ledger=expected_ledger.slice(expected_ledger.size()-256)
	ledger_ok=ledger_ok and Data.json_equal(expected_ledger,facts_after.ledger)
	facts_before.erase("ledger");facts_after.erase("ledger")
	check("real Runtime accepts unchanged per-chunk before at CURRENT revision",committed.get("ok",false) and world.region_residency_state(target).paged,committed.get("reason"))
	check("storage commit preserves every background fact except exact bounded event",Data.json_equal(facts_before,facts_after) and ledger_ok and runtime.clock()==time_before and Data.json_equal(extensions_before,world.snapshot().extensions),tail)
	check("Native cold conversion preserves every original target voxel",digest(world)==original_digest)
	var warm_capture:Dictionary=world.capture_region_residency(target,true,world.get_revision());var warm:Dictionary=await worker(warm_capture.input)
	begin=Time.get_ticks_usec();var restored:Dictionary=runtime._commit({"world_changes":warm.world_changes,"events":[{"kind":"region-storage-changed","region_id":target,"resident":true}]}) if warm.ok else warm
	var warm_commit_usec:int=Time.get_ticks_usec()-begin
	check("real Native Runtime warm restores complete edited normal content",restored.get("ok",false) and world.region_is_resident(target) and world.region_residency_state(target).page_chunks==0 and digest(world)==original_digest,restored.get("reason"))
	costs.actual_Native={"capture_usec":capture_usec,"worker_cold_usec":ready.get("cost",{}).get("prepare_usec"),"background_real_ticks":ticks,"cold_runtime_commit256_usec":commit_usec,"warm_worker_usec":warm.get("cost",{}).get("prepare_usec"),"warm_runtime_commit256_usec":warm_commit_usec,"scope":"one256 transaction cost explicitly exposed; no override of A32 contract/pins/epoch/checkpoint policy or frame qualification"}
	# Deterministic far-cell race fixture, not a player mining/OS claim. Check
	# the complete real Runtime capture, not only the first rejected chunk.
	var racing_capture:Dictionary=world.capture_region_residency(target,false,world.get_revision());var pending:Dictionary=await worker(racing_capture.input)
	var last:String=pending.world_changes[-1].id;var q:Vector3i=Data.coord(last);var cell:Dictionary={"x":q.x*16,"y":q.y*16,"z":q.z*16}
	var material:int=world.cell_at(cell.x,cell.y,cell.z)
	var raced:Dictionary=runtime._commit({"world_changes":[{"op":"voxel.set","cell":cell,"before":material,"after":3 if material!=3 else 2}]})
	var unchanged:Dictionary=runtime.capture_checkpoint();var rejected:Dictionary=runtime._commit({"world_changes":pending.world_changes,"events":[event]})
	check("real Runtime single-chunk conflict preserves complete world/facts/ledger",raced.get("ok",false) and rejected.get("code")=="CAS_MISMATCH" and Data.json_equal(unchanged,runtime.capture_checkpoint()),rejected.get("reason"))
	runtime.retire()
