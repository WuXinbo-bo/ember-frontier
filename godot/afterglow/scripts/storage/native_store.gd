extends RefCounted
## A owns the native envelope and atomic slots; C alone encodes terrain/world.
const Codec = preload("res://scripts/world/world_codec.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const FORMAT := "afterglow-native-v1"
const SCHEMA := "afterglow-native-state-v1"
const LIMIT := 67108864
const ENVELOPE_LIMIT := LIMIT*2+4096
const RECOVERY_NAMESPACES := 32
var root: String = "user://saves"
var _thread: Thread
var _pending: Dictionary = {}

func _init(directory: String = "user://saves") -> void:
	root = directory

static func failure(code: String, reason: String) -> Dictionary:
	return {"ok":false,"code":code,"reason":reason}

static func encode(capture: Dictionary,payload_limit:int=LIMIT,envelope_limit:int=ENVELOPE_LIMIT) -> Dictionary:
	var locked:Dictionary=Content.validate_lock(capture.get("content",{}))
	if not locked.ok:return locked
	var validation := Runtime.validate_facts(capture.get("facts",{}))
	if not validation.ok: return validation
	var checkpoint_id := "native:%s:%s" % [int(capture.get("command_revision",0)),Time.get_unix_time_from_system()]
	var world := Codec.encode_checkpoint(capture.get("world",{}),{},checkpoint_id)
	if not world.ok: return world
	var payload := capture.duplicate(false)
	payload.schema = SCHEMA
	payload.world = world.envelope
	if not Data.json_value(payload): return failure("INVALID_CHECKPOINT","检查点含不可保存的值")
	var raw := JSON.stringify(payload,"",true,true)
	if raw.to_utf8_buffer().size() > mini(LIMIT,payload_limit): return failure("SAVE_TOO_LARGE","检查点内容超过字节预算")
	var envelope := {"format":FORMAT,"payload":raw,"sha256":raw.sha256_text(),"checkpoint_id":checkpoint_id}
	var text:String=JSON.stringify(envelope,"",true,true)
	if text.to_utf8_buffer().size()>mini(ENVELOPE_LIMIT,envelope_limit):return failure("SAVE_TOO_LARGE","检查点封装超过字节预算")
	return {"ok":true,"code":"OK","text":text,"checkpoint_id":checkpoint_id,"payload_bytes":raw.to_utf8_buffer().size(),"envelope_bytes":text.to_utf8_buffer().size()}

static func _parse_json(text:String) -> Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(text)==OK else null

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > ENVELOPE_LIMIT: return failure("SAVE_TOO_LARGE","检查点封装超过字节预算")
	var envelope: Variant = _parse_json(text)
	if not envelope is Dictionary: return failure("INVALID_CHECKPOINT","文件不是完整JSON")
	if envelope.get("format") != FORMAT:
		var legacy := Codec.decode_checkpoint(text)
		if not legacy.ok: return legacy
		var facts: Variant = legacy.extensions.get("r3:runtime")
		if not facts is Dictionary: return failure("UNSUPPORTED_SAVE","此旧档缺少统一世界运行时；原文件保留")
		var valid := Runtime.validate_facts(facts)
		if not valid.ok: return valid
		var converted:Dictionary=facts.duplicate(true)
		var production:Dictionary=legacy.state.extensions.get("r3:production",{}).duplicate(true)
		if not production.get("tools") is Array:return failure("INVALID_CHECKPOINT","旧档生产工具事实无效")
		# Old terrain tools become the same production tools, once. Retain original
		# bytes/extensions as source only; queries never read a second live table.
		for tool:Dictionary in converted.get("tools",[]):
			var found:Dictionary={}
			for existing:Dictionary in production.tools:
				if existing.id==tool.id:found=existing;break
			if not found.is_empty() and not Data.json_equal(found,tool):return failure("INVALID_CHECKPOINT","旧档重复工具事实不一致")
			if found.is_empty():production.tools.append(tool.duplicate(true))
		legacy.state.extensions["r3:production"]=production
		converted.erase("tools")
		return {"ok":true,"code":"OK","checkpoint_id":legacy.checkpoint_id,"capture":{"schema":SCHEMA,"command_revision":0,"world":legacy.state,"facts":converted,"source":{"legacy":legacy.source,"legacy_extensions":legacy.extensions.duplicate(true),"conversion":{"terrain_tools":"merged once into r3:production; original source retained","active_intents":"pending formal offscreen assembly"}},"receipts":{}},"legacy":true}
	if not envelope.get("payload") is String or not envelope.get("sha256") is String or envelope.payload.sha256_text()!=envelope.sha256:
		return failure("INVALID_CHECKPOINT","检查点校验失败，原档保留")
	if envelope.payload.to_utf8_buffer().size()>LIMIT:return failure("SAVE_TOO_LARGE","检查点内容超过64MB")
	var payload: Variant = _parse_json(envelope.payload)
	if not payload is Dictionary or payload.get("schema") != SCHEMA or not Data.integer(payload.get("command_revision")) or int(payload.command_revision)<0:
		return failure("INVALID_CHECKPOINT","检查点版本或修订无效")
	var valid := Runtime.validate_facts(payload.get("facts",{}))
	if not valid.ok: return valid
	var locked:Dictionary=Content.validate_lock(payload.get("content",{}))
	if not locked.ok:return locked
	var world := Codec.decode_checkpoint(payload.get("world"))
	if not world.ok: return world
	if not payload.get("source",{}) is Dictionary or not payload.get("receipts",{}) is Dictionary:
		return failure("INVALID_CHECKPOINT","检查点来源或回执无效")
	var simulation:Variant=payload.get("simulation",{})
	if not simulation is Dictionary or not (simulation.get("remainder",0) is int or simulation.get("remainder",0) is float) or not is_finite(float(simulation.get("remainder",0))) or float(simulation.get("remainder",0))<0:return failure("INVALID_SIMULATION_STATE","模拟积压状态无效")
	payload.world = world.state
	return {"ok":true,"code":"OK","capture":payload,"checkpoint_id":str(envelope.get("checkpoint_id","")),"legacy":false}

func _read(path: String,limit:int=ENVELOPE_LIMIT) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return failure("IO_ERROR","无法读取："+path)
	if file.get_length()>limit: file.close();return failure("SAVE_TOO_LARGE","文件超过封装字节预算")
	var text := file.get_as_text();file.close()
	return {"ok":true,"text":text}

func _write_atomic(path: String,text: String) -> Dictionary:
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	# A path component that is a regular file is an ordinary IO failure. Catch
	# it before Godot's mkdir emits an engine ERROR for a recoverable save.
	var ancestor:String=directory
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor):return failure("IO_ERROR","存档目录被同名文件占用，原存档保留")
		var parent:String=ancestor.get_base_dir()
		if parent==ancestor or parent.is_empty():break
		ancestor=parent
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return failure("IO_ERROR","无法创建存档目录")
	var temporary := path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return failure("IO_ERROR","无法写入临时存档")
	file.store_string(text);file.flush()
	var err := file.get_error();file.close()
	if err!=OK: return failure("IO_ERROR","写入存档失败")
	var reread := _read(temporary)
	if not reread.ok or reread.text.sha256_text()!=text.sha256_text(): return failure("IO_ERROR","存档落盘校验失败")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))!=OK:
		return failure("IO_ERROR","原子替换存档失败")
	return {"ok":true,"code":"OK"}

func load_current() -> Dictionary:
	if not FileAccess.file_exists(root+"/active.json"): return _recovery_required("NO_SAVE","活动索引缺失")
	var pointer := _read(root+"/active.json",4096)
	if not pointer.ok: return _recovery_required(str(pointer.code),str(pointer.reason))
	var meta: Variant = _parse_json(pointer.text)
	if not meta is Dictionary or not _safe_namespace(meta.get("namespace")) or meta.get("slot") not in ["a","b"] or not Data.valid_id(meta.get("checkpoint_id")):
		return _recovery_required("INVALID_CHECKPOINT","存档索引无效；现有文件保留")
	for slot: String in [str(meta.slot),"b" if meta.slot=="a" else "a"]:
		var path: String=root+"/"+str(meta.namespace)+"/"+slot+".json"
		if not FileAccess.file_exists(path):continue
		var source := _read(path)
		if not source.ok:continue
		var result := decode(source.text)
		if result.ok:
			if meta.has("world_id") and result.capture.world.worldId!=meta.world_id:continue
			if slot==meta.slot and (result.checkpoint_id!=meta.checkpoint_id or meta.has("sha256") and str(source.text).sha256_text()!=meta.sha256):continue
			result.path=path;result.recovered=slot!=meta.slot
			# Read-only resume basis. A rechecks these exact bytes before
			# publishing a candidate prepared across asynchronous boundaries.
			result.source_sha256=str(source.text).sha256_text()
			result.source_bytes=str(source.text).to_utf8_buffer().size()
			result.read_active_sha256=str(pointer.text).sha256_text()
			return result
	return _recovery_required("INVALID_CHECKPOINT","当前世界两个槽均未通过校验；原文件保留")

func _recovery_required(code:String,reason:String)->Dictionary:
	var scan:Dictionary=list_recovery_candidates()
	if not scan.candidates.is_empty():return {"ok":false,"code":"RECOVERY_CHOICE_REQUIRED","reason":reason+"；请选择经过校验的存档，不自动切换世界","candidates":scan.candidates,"scan":scan.scan}
	if scan.scan.get("truncated",false):code="RECOVERY_SCAN_LIMIT"
	elif code=="NO_SAVE" and scan.scan.get("slot_files",0)>0:code="INVALID_CHECKPOINT"
	return failure(code,reason+"；未找到通过校验的候选，原文件保留").merged({"scan":scan.scan})

func list_recovery_candidates(expected_world_id:String="")->Dictionary:
	# Bounded, read-only discovery. Neither mtime nor a higher clock authorizes
	# crossing worlds. Full domain/assets/readiness validation is A's next gate.
	var directory:=DirAccess.open(root)
	var candidates:Array=[];var names:Array=[];var slots:=0;var rejected:=0;var entries:=0;var entry_limit:=256
	if directory!=null:
		directory.list_dir_begin()
		var entry:String=directory.get_next()
		while not entry.is_empty() and entries<entry_limit:
			entries+=1
			if directory.current_is_dir() and _safe_namespace(entry):names.append(entry)
			entry=directory.get_next()
		directory.list_dir_end()
	names.sort()
	var truncated:bool=names.size()>RECOVERY_NAMESPACES or entries>=entry_limit
	for index:int in mini(names.size(),RECOVERY_NAMESPACES):
		var ns:String=names[index]
		for slot:String in ["a","b"]:
			var path:String=root+"/"+ns+"/"+slot+".json"
			if not FileAccess.file_exists(path):continue
			slots+=1
			var source:Dictionary=_read(path)
			if not source.ok:rejected+=1;continue
			var parsed:Dictionary=decode(source.text)
			if not parsed.ok or parsed.get("legacy",false):rejected+=1;continue
			var identity:Dictionary=parsed.capture.world
			if not expected_world_id.is_empty() and identity.worldId!=expected_world_id:continue
			candidates.append({"candidate_id":ns+"/"+slot,"namespace":ns,"slot":slot,"sha256":str(source.text).sha256_text(),"checkpoint_id":parsed.checkpoint_id,"world_id":identity.worldId,"seed":identity.seed,"command_revision":parsed.capture.command_revision,"time":parsed.capture.facts.time,"requires_assembly_validation":true})
	# Stable identity ordering, newest revision only inside the SAME world.
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.world_id!=b.world_id:return str(a.world_id)<str(b.world_id)
		if a.command_revision!=b.command_revision:return int(a.command_revision)>int(b.command_revision)
		if a.time!=b.time:return float(a.time)>float(b.time)
		return str(a.candidate_id)<str(b.candidate_id))
	return {"ok":true,"code":"OK","candidates":candidates,"scan":{"namespaces":mini(names.size(),RECOVERY_NAMESPACES),"slot_files":slots,"rejected":rejected,"truncated":truncated,"namespace_limit":RECOVERY_NAMESPACES}}

func load_recovery_candidate(candidate_id:String,expected_sha256:String)->Dictionary:
	var parts:PackedStringArray=candidate_id.split("/")
	if parts.size()!=2 or not _safe_namespace(parts[0]) or parts[1] not in ["a","b"] or expected_sha256.length()!=64:return failure("INVALID_CANDIDATE","恢复候选身份无效")
	var existed:bool=FileAccess.file_exists(root+"/active.json")
	var active:Dictionary=_read(root+"/active.json") if existed else {"ok":true,"text":""}
	if not active.ok:return active
	var source:Dictionary=_read(root+"/"+candidate_id+".json")
	if not source.ok:return source
	if str(source.text).sha256_text()!=expected_sha256:return failure("STALE_CANDIDATE","候选已变化，请重新列出；原活动索引保留")
	var result:Dictionary=decode(source.text)
	if not result.ok:return result
	if result.get("legacy",false):return failure("LEGACY_IMPORT_REQUIRED","旧档须通过明确导入完成转换，原档保留")
	result.activation={"ok":true,"activated":false,"namespace":parts[0],"slot":parts[1],"sha256":expected_sha256,"checkpoint_id":result.checkpoint_id,"active_before_exists":existed,"active_before_sha256":str(active.text).sha256_text()}
	return result

static func _safe_namespace(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>96:return false
	for c in value:
		if not c in "0123456789abcdef-":return false
	return true

func begin_save(capture: Dictionary,fresh_namespace: bool=false,original_text: String="",activate:bool=true) -> Dictionary:
	if _thread!=null:return failure("BUSY","存档正在处理")
	_thread=Thread.new()
	var err := _thread.start(_save_job.bind(capture,fresh_namespace,original_text,activate))
	if err!=OK:_thread=null;return failure("IO_ERROR","无法启动保存任务")
	return {"ok":true,"code":"PENDING"}

func save_pending() -> bool:
	return _thread!=null

func poll() -> Dictionary:
	if _thread==null:return {}
	if _thread.is_alive():return {}
	var result: Dictionary=_thread.wait_to_finish()
	_thread=null
	return result

func _save_job(capture: Dictionary,fresh: bool,original: String,activate:bool=true) -> Dictionary:
	var started := Time.get_ticks_usec()
	var active_before_exists:bool=FileAccess.file_exists(root+"/active.json")
	var active_before:Dictionary=_read(root+"/active.json") if active_before_exists else {"ok":true,"text":""}
	if not active_before.ok:return active_before
	var encoded := encode(capture)
	if not encoded.ok:return encoded
	var verified := decode(encoded.text)
	if not verified.ok:return verified
	var save_namespace := ""
	var previous_slot := "b"
	if not fresh and FileAccess.file_exists(root+"/active.json"):
		var current := _read(root+"/active.json")
		var index: Variant=_parse_json(current.get("text",""))
		if index is Dictionary and _safe_namespace(index.get("namespace")) and index.get("slot") in ["a","b"]:
			save_namespace=index["namespace"];previous_slot=index.slot
	if save_namespace.is_empty():save_namespace=(str(Time.get_ticks_usec())+str(crypto_bytes())).sha256_text().substr(0,32)
	var slot := "a" if previous_slot=="b" else "b"
	var path := root+"/"+save_namespace+"/"+slot+".json"
	if not original.is_empty():
		var archive := _write_atomic(root+"/"+save_namespace+"/source.original.json",original)
		if not archive.ok:return archive
	var write := _write_atomic(path,encoded.text)
	if not write.ok:return write
	var pointer := JSON.stringify({"namespace":save_namespace,"slot":slot,"checkpoint_id":encoded.checkpoint_id,"world_id":capture.world.worldId,"sha256":encoded.text.sha256_text()},"",true,true)
	if activate:
		var committed := _write_atomic(root+"/active.json",pointer)
		if not committed.ok:return committed
	return {"ok":true,"code":"OK","reason":"完整世界已保存" if activate else "候选完整世界已保存，尚未激活","checkpoint_id":encoded.checkpoint_id,"namespace":save_namespace,"slot":slot,"path":ProjectSettings.globalize_path(path),"sha256":encoded.text.sha256_text(),"active_before_exists":active_before_exists,"active_before_sha256":str(active_before.text).sha256_text(),"activated":activate,"worker_ms":(Time.get_ticks_usec()-started)/1000.0}

func activate_saved(candidate:Dictionary)->Dictionary:
	if save_pending():return failure("BUSY","保存任务尚未完成")
	if not candidate.get("ok",false) or candidate.get("activated",true) or not _safe_namespace(candidate.get("namespace")) or candidate.get("slot") not in ["a","b"]:return failure("INVALID_CANDIDATE","候选保存身份无效")
	var exists:bool=FileAccess.file_exists(root+"/active.json")
	var current:Dictionary=_read(root+"/active.json") if exists else {"ok":true,"text":""}
	if not current.ok:return current
	if exists!=candidate.get("active_before_exists") or str(current.text).sha256_text()!=candidate.get("active_before_sha256"):return failure("STALE_ACTIVE","活动存档已被其他操作改变，候选未激活")
	var path:String=root+"/"+str(candidate["namespace"])+"/"+str(candidate.slot)+".json"
	var read:Dictionary=_read(path)
	if not read.ok:return read
	if str(read.text).sha256_text()!=candidate.get("sha256"):return failure("INVALID_CANDIDATE","候选保存内容发生变化，原活动存档保留")
	var decoded:Dictionary=decode(read.text)
	if not decoded.ok:return decoded
	var envelope:Variant=_parse_json(read.text)
	if not envelope is Dictionary or envelope.get("checkpoint_id")!=candidate.get("checkpoint_id"):return failure("INVALID_CANDIDATE","候选保存标识不一致")
	var pointer:String=JSON.stringify({"namespace":candidate["namespace"],"slot":candidate.slot,"checkpoint_id":candidate.checkpoint_id,"world_id":decoded.capture.world.worldId,"sha256":str(read.text).sha256_text()},"",true,true)
	var committed:Dictionary=_write_atomic(root+"/active.json",pointer)
	if not committed.ok:return committed
	var result:Dictionary=candidate.duplicate(true);result.activated=true;result.reason="完整世界已保存并激活";return result

static func crypto_bytes() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func export_file(path: String,capture: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path):return failure("FILE_EXISTS","目标已存在，请选择新文件名以保留原文件")
	var encoded := encode(capture)
	if not encoded.ok:return encoded
	var written := _write_atomic(path,encoded.text)
	if not written.ok:return written
	return {"ok":true,"code":"OK","reason":"检查点已导出","path":path,"checkpoint_id":encoded.checkpoint_id}

func read_file(path: String) -> Dictionary:
	return _read(path)
