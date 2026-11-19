extends RefCounted
## Pure codec. A owns FileAccess/atomic slots. Legacy canonical bytes are checked,
## never recreated with Godot JSON.stringify and mislabeled as JS canonical.
const Data = preload("res://scripts/world/world_data.gd")
const FORMAT = "afterglow-native-v1"
const MAX_CHARS = 67108864

static func encode_runs(cells: Variant) -> Array:
	var runs: Array = []
	var at := 0
	while at < cells.size():
		var m := int(cells[at])
		var end := at+1
		while end < cells.size() and cells[end] == m: end += 1
		runs.append(m)
		runs.append(end-at)
		at = end
	return runs

static func decode_runs(runs: Variant, length: int) -> Dictionary:
	if length < 1 or length > 64**3 or not runs is Array or runs.size()%2 != 0 or runs.size() > length*2: return Data.reject("INVALID_RLE")
	var total := 0
	for n in range(0,runs.size(),2):
		if not Data.integer(runs[n]) or not Data.MATERIALS.has(int(runs[n])) or not Data.integer(runs[n+1]) or runs[n+1] < 1 or runs[n+1] > length-total: return Data.reject("INVALID_RLE")
		total += int(runs[n+1])
	if total != length: return Data.reject("INVALID_RLE")
	var cells := PackedInt32Array()
	cells.resize(length)
	var at := 0
	for n in range(0,runs.size(),2):
		for i in int(runs[n+1]): cells[at+i] = int(runs[n])
		at += int(runs[n+1])
	return {"ok":true,"cells":cells}

static func hash_legacy_utf16(value: String) -> String:
	var h: int = 2166136261
	for i in value.length():
		var cp := value.unicode_at(i)
		if cp > 65535:
			cp -= 65536
			h = ((h ^ (55296+(cp >> 10)))*16777619) & 0xffffffff
			cp = 56320+(cp & 1023)
		h = ((h ^ cp)*16777619) & 0xffffffff
	return "%08x" % h

static func _decode_world(encoded: Variant) -> Dictionary:
	if not encoded is Dictionary or Data.config_error(encoded.get("config")) != "" or not encoded.get("chunks") is Dictionary: return Data.reject("INVALID_WORLD")
	var count: int = encoded.chunks.size()
	var length := int(encoded.config.chunkCells)**3
	if count > 8192 or count*length > 67108864: return Data.reject("SAVE_TOO_LARGE")
	var state: Dictionary = encoded.duplicate(true)
	for key in state.chunks:
		if not state.chunks[key] is Dictionary: return Data.reject("INVALID_CHUNK")
		if state.chunks[key].has("cell_page"):
			if not state.chunks[key].get("cells") is Array or not state.chunks[key].cells.is_empty():return Data.reject("INVALID_CHUNK_PAGE")
			var checked:Dictionary=Data.ChunkPage.unpack(state.chunks[key].cell_page,length,Data.MATERIALS)
			if not checked.ok:return checked
			state.chunks[key].cells=PackedInt32Array()
		else:
			var decoded := decode_runs(state.chunks[key].get("cells"),length)
			if not decoded.ok: return decoded
			state.chunks[key].cells = decoded.cells
		# Residency is a derived loading choice, not permission to regenerate facts.
		state.chunks[key].resident = false
	var valid := Data.validate(state,false)
	if not valid.ok: return valid
	return {"ok":true,"state":state}

static func _unicode_representable(raw: String) -> bool:
	# Godot strings contain Unicode scalar values, whereas JS strings can contain
	# lone surrogates. Refuse those legacy strings rather than silently replace them.
	var i := 0
	while i < raw.length():
		if raw[i] != "\\":
			i += 1
			continue
		if i+1 < raw.length() and raw[i+1] == "u":
			if i+6 > raw.length(): return false
			var cp := raw.substr(i+2,4).hex_to_int()
			if cp >= 0xd800 and cp <= 0xdbff:
				if i+12 > raw.length() or raw.substr(i+6,2) != "\\u": return false
				var low := raw.substr(i+8,4).hex_to_int()
				if low < 0xdc00 or low > 0xdfff: return false
				i += 12
				continue
			if cp >= 0xdc00 and cp <= 0xdfff: return false
			i += 6
		else: i += 2
	return true

static func encode_checkpoint(state: Dictionary, extensions: Dictionary = {}, checkpoint_id: String = "native:checkpoint") -> Dictionary:
	var valid := Data.validate(state)
	if not valid.ok: return valid
	if not Data.valid_id(checkpoint_id) or not Data.json_value(extensions): return Data.reject("INVALID_CHECKPOINT")
	var encoded := state.duplicate(false)
	encoded.chunks = {}
	for key in state.chunks:
		var c: Dictionary = state.chunks[key].duplicate(false)
		c.cells = [] if c.has("cell_page") else encode_runs(c.cells)
		c.resident = false
		encoded.chunks[key] = c
	var content := {"world":encoded,"extensions":extensions,"checkpointId":checkpoint_id,"worldId":state.worldId,"revision":state.revision,"generatorVersion":state.generatorVersion,"seed":state.seed,"schemaVersion":1}
	var payload := JSON.stringify(content,"",true,true)
	if payload.length() > MAX_CHARS: return Data.reject("SAVE_TOO_LARGE")
	return {"ok":true,"envelope":{"format":FORMAT,"payload":payload,"sha256":payload.sha256_text(),"payloadBytes":payload.to_utf8_buffer().size(),"worldId":state.worldId,"revision":state.revision}}

static func decode_checkpoint(input: Variant, expected_sha256: String = "") -> Dictionary:
	var raw := ""
	var root: Variant
	if input is String:
		raw = input
		if raw.length() > MAX_CHARS: return Data.reject("SAVE_TOO_LARGE")
		if not expected_sha256.is_empty() and raw.sha256_text() != expected_sha256: return Data.reject("SOURCE_SHA_MISMATCH")
		if not _unicode_representable(raw): return Data.reject("UNREPRESENTABLE_UNICODE","Retain the original JS source; a lone UTF16 surrogate cannot be silently replaced")
		root = JSON.parse_string(raw)
	elif input is Dictionary: root = input.duplicate(true)
	else: return Data.reject("INVALID_JSON")
	if not root is Dictionary: return Data.reject("INVALID_JSON")
	var content: Dictionary
	var source: Dictionary
	if root.get("format") == FORMAT:
		if not root.get("payload") is String or root.payload.length() > MAX_CHARS or not root.get("sha256") is String or root.payload.sha256_text() != root.sha256: return Data.reject("CHECKSUM_MISMATCH")
		if not Data.integer(root.get("payloadBytes")) or root.payloadBytes != root.payload.to_utf8_buffer().size(): return Data.reject("CHECKSUM_MISMATCH")
		var parsed: Variant = JSON.parse_string(root.payload)
		if not parsed is Dictionary: return Data.reject("INVALID_JSON")
		content = parsed
		if root.get("worldId") != content.get("worldId") or root.get("revision") != content.get("revision"): return Data.reject("CHECKPOINT_MISMATCH")
		source = {"format":FORMAT,"payload_sha256":root.sha256}
	else:
		if raw.is_empty(): return Data.reject("LEGACY_BYTES_REQUIRED","Use the original canonical v5 file, not a reconstructed Dictionary")
		# The official legacy writer emits this exact canonical root order. Remove
		# ONLY its root checksum field, retaining numeric lexemes/UTF16 semantics.
		var re := RegEx.new()
		re.compile('^\\{"checkpointId":("(?:[^"\\\\]|\\\\.)*"),"checksum":"([0-9a-f]{8})",')
		var m := re.search(raw)
		if m == null: return Data.reject("LEGACY_CANONICAL_REQUIRED","Use the retained v5 canonical export / existing JS decoder")
		var unsigned := '{"checkpointId":'+m.get_string(1)+','+raw.substr(m.get_end())
		if hash_legacy_utf16(unsigned) != root.get("checksum"): return Data.reject("CHECKSUM_MISMATCH")
		content = root
		source = {"format":"legacy-v5","source_sha256":raw.sha256_text(),"legacy_checksum":root.checksum,"original_bytes_retained":true}
	if content.get("schemaVersion") != 1 or not Data.valid_id(content.get("checkpointId")) or not content.get("extensions") is Dictionary or not Data.json_value(content.extensions): return Data.reject("INVALID_CHECKPOINT")
	var decoded := _decode_world(content.get("world"))
	if not decoded.ok: return decoded
	for k in ["schemaVersion","worldId","seed","generatorVersion","revision"]:
		if content.get(k) != decoded.state.get(k): return Data.reject("CHECKPOINT_MISMATCH",k)
	return {"ok":true,"code":"OK","state":decoded.state,"extensions":content.extensions.duplicate(true),"checkpoint_id":content.checkpointId,"source":source}

static func encode(state: Dictionary, extensions: Dictionary = {}, checkpoint_id: String = "native:checkpoint") -> Dictionary:
	return encode_checkpoint(state,extensions,checkpoint_id)

static func decode(input: Variant, expected_sha256: String = "") -> Dictionary:
	return decode_checkpoint(input,expected_sha256)
