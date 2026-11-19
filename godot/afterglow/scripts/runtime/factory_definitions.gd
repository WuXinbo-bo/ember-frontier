extends RefCounted
## Additive item registration. Core legacy IDs keep their original owner/meaning;
## module/recipe definitions remain with B and are queried, never copied here.
const Data = preload("res://scripts/world/world_data.gd")
const PATH := "res://data/factory/content.json"
const SCHEMA := "afterglow-factory-content-v1"
static var _loaded:bool = false
static var _catalog:Dictionary = {}
static var _validation:Dictionary = {}
static var _load_mutex:Mutex = Mutex.new()

static func validate_document(value:Variant,reserved_ids:Dictionary={})->Dictionary:
	if not value is Dictionary or value.get("schema")!=SCHEMA or value.get("version")!=1:
		return _failure("INVALID_FACTORY_CONTENT","生产内容注册版本无效")
	for field:String in ["categories","handbook_sections","items"]:
		if not value.get(field) is Array:return _failure("INVALID_FACTORY_CONTENT","生产内容列表无效："+field)
		var ids:Dictionary={}
		for record:Variant in value[field]:
			if not record is Dictionary or not Data.valid_id(record.get("id")) or ids.has(record.id) or not record.get("name") is String or record.name.is_empty():
				return _failure("INVALID_FACTORY_CONTENT","生产内容身份、名称或重复项无效："+field)
			ids[record.id]=true
			if field=="items":
				if not str(record.id).begins_with("r34:") or reserved_ids.has(record.id):return _failure("FACTORY_ITEM_CONFLICT","新内容不得重定义旧物品："+str(record.id))
				if record.get("unit") not in ["count","m3"] or not record.get("stackable") is bool:return _failure("INVALID_FACTORY_CONTENT","新物品单位或堆叠声明无效")
				var step:Variant=record.get("step")
				if not (step is float or step is int) or not is_finite(float(step)) or float(step)<=0 or (record.unit=="count" and float(step)!=1.0):return _failure("INVALID_FACTORY_CONTENT","新物品数量步长无效")
	return {"ok":true,"code":"OK"}

static func _ensure_loaded()->void:
	_load_mutex.lock()
	if _loaded:_load_mutex.unlock();return
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_validation=validate_document(value)
	if _validation.ok:_catalog=value.duplicate(true)
	_loaded=true
	_load_mutex.unlock()

static func validation(reserved_ids:Dictionary={})->Dictionary:
	_ensure_loaded()
	return validate_document(_catalog,reserved_ids) if _validation.get("ok",false) else _validation.duplicate(true)

static func catalog()->Dictionary:
	_ensure_loaded()
	return _catalog.duplicate(true)

static func item_definition(id:String)->Dictionary:
	_ensure_loaded()
	for record:Dictionary in _catalog.get("items",[]):
		if record.id==id:
			var result:Dictionary=record.duplicate(true);result.schema_version=1
			return result
	return {}

static func item_ids()->Array:
	_ensure_loaded()
	var result:Array=[]
	for record:Dictionary in _catalog.get("items",[]):result.append(record.id)
	return result

static func _failure(code:String,reason:String)->Dictionary:
	return {"ok":false,"code":code,"reason":reason}
