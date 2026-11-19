extends RefCounted
## Reuse ONLY the pure WorldData string predicate, never a world/actor/stock
## validation result. Full string keys avoid hash-collision proofs; bounded
## process metadata is absent from saves and drops on script/process restart.
const Data=preload("res://scripts/world/world_data.gd")
const LIMIT:=2048
static var _valid:Dictionary={}
static var _mutex:=Mutex.new()
static func valid_id(value:Variant)->bool:
	if not value is String:return false
	_mutex.lock();var known:bool=_valid.has(value);_mutex.unlock()
	if known:return true
	if not Data.valid_id(value):return false
	_mutex.lock()
	if _valid.size()>=LIMIT:_valid.clear()
	_valid[value]=true;_mutex.unlock()
	return true
