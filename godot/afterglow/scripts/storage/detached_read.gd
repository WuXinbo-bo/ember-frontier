extends RefCounted
## Read-only worker capability: a path string in, detached validated data out.
const Store=preload("res://scripts/storage/native_store.gd")

static func load_current(directory:String)->Dictionary:
	# A worker-local reader, with no live Store/thread state, world or Node.
	return Store.new(directory).load_current()
