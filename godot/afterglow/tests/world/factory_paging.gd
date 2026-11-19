extends "res://tests/world/factory_modules.gd"
const Page=preload("res://scripts/world/chunk_page.gd")

func apply(world:RefCounted,changes:Array)->Dictionary:
	var tx:Dictionary=world.prepare_changes(changes,world.get_revision())
	return world.commit_prepared(tx.capability) if tx.ok else tx

func run()->void:
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(Factory.generate(713,Catalog.profiles()))
	check("actual factory voxel authority loads for storage conversion",loaded.ok)
	if not loaded.ok:return finish()
	var region:String="RH-VILLAGE";var x:int=50;var z:int=-50
	var y:int=roundi(world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)*2)-1
	var edited:Dictionary=apply(world,[{"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":world.cell_at(x,y,z),"after":0}])
	check("real pre-release edit commits",edited.ok)
	var before_digest:String=raster_digest(world.snapshot())
	var original:Dictionary=world.region_residency_state(region)
	check("metadata measures complete actual one-region cell lattice",original.resident and original.required_chunks==256 and original.unpacked_bytes==4194304 and world.region_chunk_keys(region).size()==256,original)
	check("storage prepare uses exact revision and real region",world.prepare_region_residency(region,false,-1).get("code")=="STALE_WORLD_REVISION" and world.prepare_region_residency("absent",false,world.get_revision()).get("code")=="UNKNOWN_REGION")
	var cold:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	check("cold prepare returns only same-authority representation changes",cold.ok and cold.world_changes.size()==256 and cold.world_changes.all(func(c:Dictionary)->bool:return c.op=="chunk.storage" and c.after.cells.is_empty() and c.before.size()==3 and not c.before.has("cells")),cold.get("reason"))
	if not cold.ok:return finish()
	check("preparing compression cannot release live authority",world.region_is_resident(region) and world.cell_storage_statistics().cold_page_count==0)
	var prepared:Dictionary=world.prepare_changes(cold.world_changes,world.get_revision())
	check("prepared cold view is isolated and has released actual cell buffers",prepared.ok and not prepared.view.region_is_resident(region) and prepared.view.region_residency_state(region).unpacked_bytes==0 and world.region_is_resident(region),prepared.get("reason"))
	if not prepared.ok:return finish()
	var corrupt:Array=cold.world_changes.duplicate(true);corrupt[0].after.cell_page.raw_sha256="0".repeat(64)
	check("bad page is rejected before authority swap",not world.prepare_changes(corrupt,world.get_revision()).ok and world.region_is_resident(region))
	var wrong:Array=cold.world_changes.duplicate(true);var changed:PackedInt32Array=world.chunk(str(wrong[0].id)).cells;changed[0]=3 if changed[0]!=3 else 2
	wrong[0].after.cell_page=Page.pack(changed,4096,Data.MATERIALS).page
	check("valid compressed page cannot change factual cell content",world.prepare_changes(wrong,world.get_revision()).get("code")=="CHUNK_STORAGE_CONTENT_MISMATCH")
	var one:Dictionary=cold.world_changes[0]
	var same_cell:Dictionary={"x":int(world.chunk(one.id).coord.x)*16,"y":maxi(int(world.config().minCellY),int(world.chunk(one.id).coord.y)*16),"z":int(world.chunk(one.id).coord.z)*16}
	var edit:Dictionary={"op":"voxel.set","cell":same_cell,"before":world.cell_at(same_cell.x,same_cell.y,same_cell.z),"after":3}
	if edit.before==3:edit.after=2
	var forward:Dictionary=world.prepare_changes([one,edit],world.get_revision())
	var reverse:Dictionary=world.prepare_changes([edit,one],world.get_revision())
	check("chunk conversion and cell editing cannot alias in either transaction order",forward.get("code")=="DUPLICATE_TARGET" and reverse.get("code")=="DUPLICATE_TARGET",{"forward":forward.get("code"),"reverse":reverse.get("code"),"cell":same_cell,"chunk":one.id})
	var committed:Dictionary=world.commit_prepared(prepared.capability)
	var state:Dictionary=world.region_residency_state(region)
	check("actual cold commit frees all region full cell arrays",committed.ok and not state.resident and state.paged and not state.mixed and state.unpacked_bytes==0 and state.page_chunks==256 and state.page_bytes<original.unpacked_bytes/10,state)
	check("released cells cannot act as empty editable or traversable air",not world.is_cell_known(x,y,z) and not world.is_cell_resident(x,y,z) and world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)==null and not world.prepare_changes([{"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":0,"after":2}],world.get_revision()).ok)
	var key:String=world.region_chunk_keys(region)[0]
	check("legacy resident toggle cannot pretend a page is warm",world.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],world.get_revision()).get("code")=="CHUNK_PAGE_REQUIRES_RESTORE")
	var duplicate:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	check("repeat cold request is idempotent and never re-encodes source facts",duplicate.ok and duplicate.world_changes.is_empty())
	var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"r34:actual:pages")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();loaded=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("native codec saves exact cold content without re-expanding its cells",loaded.ok and restored.region_residency_state(region).paged and restored.region_residency_state(region).unpacked_bytes==0 and Data.json_equal(restored.chunk(key).cell_page,world.chunk(key).cell_page),loaded)
	var raw:Dictionary=world.snapshot();raw.chunks[key].cell_page.compressed_sha256="0".repeat(64)
	var preserved:Dictionary=restored.region_residency_state(region)
	var rejected:Dictionary=restored.load_snapshot(raw)
	check("corrupt restore preserves original loaded authority",not rejected.ok and restored.region_residency_state(region)==preserved,rejected)
	var warm:Dictionary=restored.prepare_region_residency(region,true,restored.get_revision())
	check("warm prepare decodes all actual pages to complete same-cell arrays",warm.ok and warm.world_changes.size()==256 and warm.world_changes.all(func(c:Dictionary)->bool:return c.after.cell_page==null and c.after.cells.size()==4096),warm.get("reason"))
	if not warm.ok:return finish()
	var first:Dictionary=apply(restored,[warm.world_changes[0]])
	check("partial loading remains explicitly mixed and never detailed",first.ok and restored.region_residency_state(region).mixed and not restored.region_is_resident(region),restored.region_residency_state(region))
	warm=restored.prepare_region_residency(region,true,restored.get_revision())
	var warmed:Dictionary=apply(restored,warm.world_changes)
	check("full reload restores every original edited voxel exactly",warmed.ok and restored.region_is_resident(region) and raster_digest(restored.snapshot())==before_digest and restored.cell_at(x,y,z)==0,restored.region_residency_state(region))
	check("full reload frees cold pages rather than retaining a second authority",restored.region_residency_state(region).page_chunks==0 and restored.region_residency_state(region).page_bytes==0)
	var replay:Dictionary=Factory.prepare_region_draft(restored,Factory.draft_region_request(Factory.region_generation_input(restored,Catalog.profiles()),Vector2i(0,-1)),restored.get_revision())
	check("revisit of paged edited world never generates or restocks",replay.ok and replay.already_generated and replay.world_changes.is_empty() and replay.initial_stocks.is_empty())
	var invalid:PackedInt32Array=PackedInt32Array([99]);invalid.resize(4096)
	check("unknown material cannot enter compression",Page.pack(invalid,4096,Data.MATERIALS).get("code")=="INVALID_CHUNK_PAGE_CELLS")
	var bad_page:Dictionary=world.chunk(key).cell_page.duplicate(true);bad_page.cell_count=64**3+1
	check("page count bound prevents oversized decompression",not Page.unpack(bad_page,4096,Data.MATERIALS).ok)
	var batches:Dictionary={"cold":[],"warm":[]};var bounded:bool=true
	for desired:bool in [false,true]:
		var complete:bool=false;var batch_count:int=0
		while not complete and batch_count<10:
			var part:Dictionary=restored.prepare_region_residency(region,desired,restored.get_revision(),32)
			if not part.ok:bounded=false;break
			batches["warm" if desired else "cold"].append(part.cost.prepare_usec)
			bounded=bounded and part.world_changes.size()<=32
			complete=part.complete;batch_count+=1
			var accepted:Dictionary=apply(restored,part.world_changes)
			if not accepted.ok:bounded=false;break
			if not complete:bounded=bounded and restored.region_residency_state(region).mixed and not restored.region_is_resident(region)
		check("bounded 32-chunk representation batches finish with exact detailed state "+str(desired),bounded and complete and restored.region_is_resident(region)==desired,batches)
	check("bounded release reload retains exact original edits",raster_digest(restored.snapshot())==before_digest and restored.cell_at(x,y,z)==0)
	check("invalid batch budget cannot change authority",restored.prepare_region_residency(region,false,restored.get_revision(),0).get("code")=="INVALID_RESIDENCY_BUDGET")
	costs={"release_prepare":cold.cost,"warm_prepare":warm.cost,"bounded_32_prepare_usec":batches,"hot_before":original,"cold_after":state,"warm_after":restored.region_residency_state(region),"raster_sha256":before_digest,"scope":"actual authority cell buffers and codec; no process RSS, renderer, A checkpoint schedule or performance qualification"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and encoded.ok:FileAccess.open(args[0].get_base_dir()+"/actual-paged-world.envelope.json",FileAccess.WRITE).store_string(JSON.stringify(encoded.envelope))
	finish()
