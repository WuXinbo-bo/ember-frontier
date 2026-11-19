extends SceneTree
## Same TerrainView except exact-face memo; isolated CPU comparison only.
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const View=preload("res://scripts/world/world_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
class Original extends "res://scripts/terrain/terrain_view.gd":
	func _dependencies_match(key:String,derived:Dictionary,read:Dictionary)->bool:
		return not derived.is_empty() and derived.get("dependencies",[])==_dependencies(key,read)
func _initialize()->void:call_deferred("run")
func measure(view:Node3D,keys:Array)->int:
	var began:int=Time.get_ticks_usec()
	for i:int in 200:view.readiness(keys)
	return Time.get_ticks_usec()-began
func run()->void:
	var state:Dictionary={"worldId":"same:face-proof","revision":1,"config":Data.DEFAULT_CONFIG.duplicate(true),"chunks":{}}
	var cells:=PackedInt32Array();cells.resize(4096)
	for z:int in range(-2,3):
		for y:int in range(-1,2):
			for x:int in range(-2,3):state.chunks[Data.key(Vector3i(x,y,z))]={"revision":1,"generated":true,"resident":true,"cells":cells}
	var world:=View.new(state);var a:=Original.new();var b:=Terrain.new();a.world=world;b.world=world
	var keys:Array=["-1,0,-1","0,0,0","1,0,1"]
	for view:Node3D in [a,b]:
		for key:String in keys:view._derived[key]={"revision":1,"dependencies":view._dependencies(key),"physics_frame":-1}
	var equal:bool=a.readiness(keys)==b.readiness(keys)
	var samples:Array=[]
	for view:Node3D in [a,b,b,a]:samples.append({"kind":"original" if view==a else "stamp","usec":measure(view,keys)})
	state.chunks["1,0,0"].cells[Data.local_index(Vector3i(0,5,5),16)]=1;state.chunks["1,0,0"].revision+=1
	equal=equal and a.readiness(keys)==b.readiness(keys) and b.readiness(keys).pending.has("0,0,0")
	a.free();b.free()
	var result:Dictionary={"equal":equal,"samples":samples,"iterations":200,"keys":3,"scope":"isolated CPU, synthetic ready markers, identical source except exact dependency memo; no real mesh/GPU/FPS claim"}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print("READINESS_STAMP "+JSON.stringify(result));quit(0 if equal else 1)
