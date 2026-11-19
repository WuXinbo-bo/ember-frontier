extends RefCounted
## Pure value conversion only. No World/Runtime, scene, IO, clock or mutable
## authority references. Caller hands off exclusive input until worker joins.
const Data=preload("res://scripts/world/world_data.gd")
const Page=preload("res://scripts/world/chunk_page.gd")
const SCHEMA:String="afterglow-detached-region-residency-v1"
const MAX_CHUNKS:int=256
const MAX_GUARDS:int=8192
const MAX_INPUT_BYTES:int=8*1024*1024

static func region_keys(region:Dictionary,config:Dictionary)->Array:
	var b:Dictionary=region.bounds;var width:float=float(config.cellSize)*int(config.chunkCells)
	var lo:=Vector3i(floori(b.min.x/width),floori(maxf(b.min.y,int(config.minCellY)*float(config.cellSize))/width),floori(b.min.z/width))
	var hi:=Vector3i(ceili(b.max.x/width),ceili(minf(b.max.y,int(config.maxCellY)*float(config.cellSize))/width),ceili(b.max.z/width))
	if hi.x<=lo.x or hi.y<=lo.y or hi.z<=lo.z:return []
	if hi.x-lo.x>MAX_GUARDS or hi.y-lo.y>MAX_GUARDS or hi.z-lo.z>MAX_GUARDS or (hi.x-lo.x)*(hi.y-lo.y)*(hi.z-lo.z)>MAX_GUARDS:return []
	var keys:Array=[]
	for z in range(lo.z,hi.z):
		for y in range(lo.y,hi.y):
			for x in range(lo.x,hi.x):keys.append(Data.key(Vector3i(x,y,z)))
	return keys

static func prepare(input:Dictionary)->Dictionary:
	var began:int=Time.get_ticks_usec()
	if input.size()!=8 or input.get("schema")!=SCHEMA or not input.get("resident") is bool or not input.get("region_id") is String or not input.get("rows") is Array or not input.get("basis") is Dictionary or not input.get("state_before") is Dictionary or not Data.json_value(input.state_before):return Data.reject("INVALID_DETACHED_RESIDENCY")
	if not Data.integer(input.get("max_chunks")) or input.max_chunks<1 or input.max_chunks>MAX_CHUNKS:return Data.reject("INVALID_RESIDENCY_BUDGET")
	var basis:Dictionary=input.basis
	if basis.size()!=5 or not basis.get("identity") is Dictionary or not Data.json_value(basis.identity) or not basis.get("region") is Dictionary or not Data.json_value(basis.region) or not Data.config_error(basis.get("config")).is_empty() or not Data.json_value(basis.config) or not basis.get("chunks") is Dictionary or not Data.integer(basis.get("captured_world_revision")) or basis.captured_world_revision<0:return Data.reject("INVALID_DETACHED_RESIDENCY")
	if basis.region.get("id")!=input.region_id or not basis.region.get("generated",false) or not Data.bounds(basis.region.get("bounds")):return Data.reject("INVALID_DETACHED_RESIDENCY")
	var keys:Array=region_keys(basis.region,basis.config)
	if keys.is_empty() or basis.chunks.size()!=keys.size():return Data.reject("INVALID_DETACHED_RESIDENCY")
	var selected:Array=[];var needed:int=0
	for key:String in keys:
		var guard:Variant=basis.chunks.get(key)
		if not guard is Dictionary or guard.size()!=4 or not guard.has_all(["revision","resident","generated","has_page"]) or not Data.integer(guard.revision) or guard.revision<0 or guard.revision>basis.captured_world_revision or not guard.resident is bool or guard.generated!=true or not guard.has_page is bool or guard.has_page and guard.resident:return Data.reject("INVALID_DETACHED_RESIDENCY")
		if input.resident and guard.resident and not guard.has_page:continue
		if not input.resident and guard.has_page:continue
		needed+=1
		if selected.size()<int(input.max_chunks):selected.append(key)
	if input.get("needed_chunks")!=needed or input.rows.size()!=selected.size():return Data.reject("INVALID_DETACHED_RESIDENCY")
	# Check the byte envelope before any copy/decompression. A malicious request
	# cannot multiply a small compressed input into unbounded output buffers.
	var length:int=int(basis.config.chunkCells)**3;var input_bytes:int=0
	if selected.size()*length*4>MAX_INPUT_BYTES:return Data.reject("DETACHED_RESIDENCY_BUDGET")
	for i in input.rows.size():
		var row:Variant=input.rows[i]
		if not row is Dictionary or row.size()!=5 or not row.has_all(["id","revision","resident","cells","cell_page"]) or row.id!=selected[i] or not row.cells is PackedInt32Array:return Data.reject("INVALID_DETACHED_RESIDENCY")
		var guard:Dictionary=basis.chunks[row.id]
		if row.revision!=guard.revision or row.resident!=guard.resident or (row.cell_page!=null)!=guard.has_page:return Data.reject("INVALID_DETACHED_RESIDENCY")
		if row.cell_page!=null:
			if not row.cell_page is Dictionary or not row.cell_page.get("data") is String or not row.cells.is_empty():return Data.reject("INVALID_DETACHED_RESIDENCY")
			input_bytes+=row.cell_page.data.length()
		else:
			if row.cells.size()!=length:return Data.reject("INVALID_DETACHED_RESIDENCY")
			input_bytes+=row.cells.size()*4
		if input_bytes>MAX_INPUT_BYTES:return Data.reject("DETACHED_RESIDENCY_BUDGET")
	var changes:Array=[];var output_bytes:int=0
	for row:Dictionary in input.rows:
		var after:Dictionary={"resident":input.resident,"cells":PackedInt32Array(),"cell_page":null};var digest:String
		if row.cell_page!=null:
			var decoded:Dictionary=Page.unpack(row.cell_page,length,Data.MATERIALS)
			if not decoded.ok:return decoded.merged({"chunk_id":row.id})
			after.cells=decoded.cells;digest=row.cell_page.raw_sha256
		elif input.resident:
			if not Page.values_valid(row.cells,Data.MATERIALS):return Data.reject("UNKNOWN_MATERIAL",row.id)
			after.cells=row.cells.duplicate();digest=Page.fingerprint(row.cells)
		else:
			var encoded:Dictionary=Page.pack(row.cells,length,Data.MATERIALS)
			if not encoded.ok:return encoded.merged({"chunk_id":row.id})
			after.cell_page=encoded.page;digest=encoded.page.raw_sha256
		output_bytes+=after.cells.size()*4 if after.cell_page==null else after.cell_page.data.length()
		changes.append({"op":"chunk.storage","id":row.id,"before":{"revision":row.revision,"resident":row.resident,"sha256":digest},"after":after})
	return {"ok":true,"code":"OK","region_id":input.region_id,"resident":input.resident,"expected_world_revision":basis.captured_world_revision,"basis":basis.duplicate(true),"world_changes":changes,"remaining_chunks":needed-changes.size(),"complete":needed==changes.size(),"cost":{"prepare_usec":Time.get_ticks_usec()-began,"converted_chunks":changes.size(),"input_payload_bytes":input_bytes,"output_payload_bytes":output_bytes},"state_before":input.get("state_before",{}).duplicate(true)}
