extends RefCounted
## An immutable query proxy over a COW candidate. The backing lives only in a
## static lambda capture, never in an addressable member of the exported object.
## Its Callable admits only read APIs that return detached DTOs or scalar values.
const View=preload("res://scripts/world/world_view.gd")
const READS=["snapshot", "get_revision", "config", "identity", "entity", "region", "regions", "region_ids", "chunk", "chunk_metadata", "chunk_boundary", "chunk_is_generated", "chunk_keys", "cell_storage_statistics", "retired_entity_ids", "has_extension", "extension", "extension_fields", "extension_entries", "entities", "entities_in_bounds", "entities_with_data_in_bounds", "entities_in_any_bounds", "region_at", "region_is_resident", "region_chunk_keys", "region_residency_state", "continuous_outdoor_step", "continuous_outdoor_contact", "continuous_outdoor_segment", "continuous_outdoor_neighbors", "is_cell_known", "cell_at", "is_cell_resident", "surface_height"]
var _reader:Callable
var _local:RefCounted
var _state:Dictionary:
	get:
		if _local==null:_local=View.new(_reader.call("snapshot",[]))
		return _local._state
	set(value):
		_local=View.new(value.duplicate(true))

func _init(state:Dictionary={},readiness:Dictionary={})->void:
	_reader=_capture_reader(state,readiness)

static func _capture_reader(state:Dictionary,readiness:Dictionary)->Callable:
	var source:RefCounted=View.new(state)
	source._region_readiness=readiness.duplicate(false)
	return func(method:String,arguments:Array)->Variant:
		if method not in ["spatial_entities", "segment_cell"] and method not in READS:return null
		return source.callv(method,arguments)

func _query(method:String,arguments:Array)->Variant:
	return _local.callv(method,arguments) if _local!=null else _reader.call(method,arguments)

func snapshot()->Dictionary:
	return _query("snapshot",[])

func get_revision()->int:
	return _query("get_revision",[])

func config()->Dictionary:
	return _query("config",[])

func identity()->Dictionary:
	return _query("identity",[])

func entity(id: String)->Dictionary:
	return _query("entity",[id])

func region(id: String)->Dictionary:
	return _query("region",[id])

func regions()->Array:
	return _query("regions",[])

func region_ids()->Array:
	return _query("region_ids",[])

func chunk(id: String)->Dictionary:
	return _query("chunk",[id])

func chunk_metadata(key:String)->Dictionary:
	return _query("chunk_metadata",[key])

func chunk_boundary(key:String,axis:int,sign:int)->PackedInt32Array:
	return _query("chunk_boundary",[key,axis,sign])

func chunk_is_generated(key:String)->bool:
	return _query("chunk_is_generated",[key])

func chunk_keys()->Array:
	return _query("chunk_keys",[])

func cell_storage_statistics()->Dictionary:
	return _query("cell_storage_statistics",[])

func retired_entity_ids()->Array:
	return _query("retired_entity_ids",[])

func has_extension(id: String)->bool:
	return _query("has_extension",[id])

func extension(id: String)->Variant:
	return _query("extension",[id])

func extension_fields(id:String,fields:Array[String])->Dictionary:
	return _query("extension_fields",[id,fields])

func extension_entries(id:String,field:String,ids:Array)->Dictionary:
	return _query("extension_entries",[id,field,ids])

func entities(region_id: String = "")->Array:
	return _query("entities",[region_id])

func spatial_entities()->Array:
	return _query("spatial_entities",[])

func segment_cell(cell: Vector3i, require_resident: bool) -> int:
	return _query("segment_cell", [cell, require_resident])

func entities_in_bounds(bounds: Dictionary)->Array:
	return _query("entities_in_bounds",[bounds])

func entities_with_data_in_bounds(bounds:Dictionary,field:String)->Array:
	return _query("entities_with_data_in_bounds",[bounds,field])

func entities_in_any_bounds(volumes:Array)->Array:
	return _query("entities_in_any_bounds",[volumes])

func region_at(position: Dictionary)->Dictionary:
	return _query("region_at",[position])

func region_is_resident(region_id:String)->bool:
	return _query("region_is_resident",[region_id])

func region_chunk_keys(region_id:String)->Array:
	return _query("region_chunk_keys",[region_id])

func region_residency_state(region_id:String)->Dictionary:
	return _query("region_residency_state",[region_id])

func continuous_outdoor_step(from_location:Dictionary,to_location:Dictionary)->Dictionary:
	return _query("continuous_outdoor_step",[from_location,to_location])

func continuous_outdoor_contact(from_location:Dictionary,to_location:Dictionary)->Dictionary:
	return _query("continuous_outdoor_contact",[from_location,to_location])

func continuous_outdoor_segment(from_location:Dictionary,to_location:Dictionary,max_distance:float,require_resident:bool=true)->Dictionary:
	return _query("continuous_outdoor_segment",[from_location,to_location,max_distance,require_resident])

func continuous_outdoor_neighbors(region_id:String)->Array:
	return _query("continuous_outdoor_neighbors",[region_id])

func is_cell_known(x: int, y: int, z: int)->bool:
	return _query("is_cell_known",[x,y,z])

func cell_at(x: int, y: int, z: int)->int:
	return _query("cell_at",[x,y,z])

func is_cell_resident(x: int,y: int,z: int)->bool:
	return _query("is_cell_resident",[x,y,z])

func surface_height(x: float, z: float)->Variant:
	return _query("surface_height",[x,z])

