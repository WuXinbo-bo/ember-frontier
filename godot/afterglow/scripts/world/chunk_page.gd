extends RefCounted
## One cold representation of the SAME authoritative cells. No IO, cache,
## simulation, region generation or fallback to a seed on decode failure.
const FORMAT="afterglow-i32le-zstd-v1"

static func bad(code:String)->Dictionary:return {"ok":false,"code":code,"reason":code}

static func sha256(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish().hex_encode()

static func little_endian()->bool:
	return PackedInt32Array([0x01020304]).to_byte_array()[0]==4

static func values_valid(cells:PackedInt32Array,materials:Dictionary)->bool:
	var allowed:int=0
	for material:Variant in materials:allowed+=cells.count(int(material))
	return allowed==cells.size()

static func fingerprint(cells:Variant)->String:
	return sha256(PackedInt32Array(cells).to_byte_array())

static func pack(cells:Variant,length:int,materials:Dictionary)->Dictionary:
	if not little_endian():return bad("UNSUPPORTED_CHUNK_BYTE_ORDER")
	if not cells is PackedInt32Array or cells.size()!=length or length<1 or length>64**3 or not values_valid(cells,materials):return bad("INVALID_CHUNK_PAGE_CELLS")
	var raw:PackedByteArray=cells.to_byte_array()
	var compressed:PackedByteArray=raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty():return bad("CHUNK_COMPRESSION_FAILED")
	return {"ok":true,"page":{"format":FORMAT,"cell_count":length,"raw_sha256":sha256(raw),"compressed_sha256":sha256(compressed),"data":Marshalls.raw_to_base64(compressed)}}

static func header(page:Variant,length:int)->Dictionary:
	if not page is Dictionary or page.size()!=5 or not page.has_all(["format","cell_count","raw_sha256","compressed_sha256","data"]) or page.format!=FORMAT:return bad("INVALID_CHUNK_PAGE")
	var count:Variant=page.cell_count
	if (not count is int and not count is float) or not is_finite(float(count)) or count!=length or length<1 or length>64**3:return bad("INVALID_CHUNK_PAGE")
	for field:String in ["raw_sha256","compressed_sha256"]:
		if not page[field] is String or page[field].length()!=64 or page[field]!=page[field].to_lower() or not page[field].is_valid_hex_number():return bad("INVALID_CHUNK_PAGE")
	if not page.data is String or page.data.is_empty() or page.data.length()%4!=0 or page.data.length()>(length*4+1024)*2:return bad("INVALID_CHUNK_PAGE")
	# Only accept the engine's exact canonical encoding, including padding.
	# This also rejects every non-alphabet character without a GDScript byte loop.
	var compressed:PackedByteArray=Marshalls.base64_to_raw(page.data)
	if Marshalls.raw_to_base64(compressed)!=page.data:return bad("INVALID_CHUNK_PAGE")
	if compressed.is_empty() or compressed.size()>length*4+1024 or sha256(compressed)!=page.compressed_sha256:return bad("CHUNK_PAGE_CHECKSUM")
	return {"ok":true,"compressed":compressed}

static func unpack(page:Variant,length:int,materials:Dictionary)->Dictionary:
	if not little_endian():return bad("UNSUPPORTED_CHUNK_BYTE_ORDER")
	var checked:Dictionary=header(page,length)
	if not checked.ok:return checked
	var raw:PackedByteArray=checked.compressed.decompress(length*4,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=length*4 or sha256(raw)!=page.raw_sha256:return bad("CHUNK_PAGE_CHECKSUM")
	var cells:PackedInt32Array=raw.to_int32_array()
	if cells.size()!=length or not values_valid(cells,materials):return bad("UNKNOWN_MATERIAL")
	return {"ok":true,"cells":cells}
