extends SceneTree
## Exact semantics against the frozen preimage; isolated invalidation fixtures.
const View=preload("res://scripts/world/world_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Terrain=preload("res://scripts/terrain/terrain_view.gd")
const Prior=preload("res://tests/world/fixtures/terrain_before_readiness_projection.gd")
class Probe extends View:
	var copies:int=0
	var planes:int=0
	func chunk(key:String)->Dictionary:
		copies+=1;return super.chunk(key)
	func chunk_boundary(key:String,axis:int,sign:int)->PackedInt32Array:
		planes+=1;return super.chunk_boundary(key,axis,sign)
class Legacy extends RefCounted:
	var source:RefCounted
	func chunk(key:String)->Dictionary:return source.chunk(key)
	func config()->Dictionary:return source.config()
	func identity()->Dictionary:return source.identity()
	func get_revision()->int:return source.get_revision()
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label)
func mark(view:Node3D,key:String)->void:
	view._derived[key]={"revision":view.world.chunk(key).revision,"dependencies":view._dependencies(key),"physics_frame":-1}
func same(a:Node3D,b:Node3D,keys:Array)->bool:return a.readiness(keys)==b.readiness(keys)
func run()->void:
	var state:Dictionary={"worldId":"isolated:readiness","revision":10,"config":Data.DEFAULT_CONFIG.duplicate(true),"chunks":{}}
	for z:int in range(-2,2):
		for y:int in range(-1,2):
			for x:int in range(-2,2):
				var cells:=PackedInt32Array();cells.resize(4096)
				for i:int in 4096:cells[i]=(i+x+y+z+12)%7
				state.chunks[Data.key(Vector3i(x,y,z))]={"revision":4,"generated":true,"resident":true,"cells":cells}
	var world:=Probe.new(state);var a:=Prior.new();var b:=Terrain.new();a.world=world;b.world=world
	var keys:Array=["-1,0,-1","0,0,0"]
	check("initial identical pending before derivation",same(a,b,keys) and not b.readiness(keys).ready)
	for key:String in keys:mark(a,key);mark(b,key)
	check("identical ready fixture after exact dependencies",same(a,b,keys) and b.readiness(keys).ready)
	world.copies=0;world.planes=0
	for i:int in 20:b.readiness(keys);b.prioritize(keys)
	check("warm readiness and priority do not clone cells or reread cached planes",world.copies==0 and world.planes==0,{"chunk_copies":world.copies,"plane_reads":world.planes})
	var metadata:Dictionary=world.chunk_metadata("0,0,0");metadata.resident=false;metadata.revision=-99
	check("metadata is detached and unknown stays empty",world.chunk_metadata("0,0,0").resident and world.chunk_metadata("0,0,0").revision==4 and world.chunk_metadata("unknown").is_empty())
	var exact:bool=true
	for axis:int in 3:
		for sign:int in [-1,1]:
			var c:Dictionary=world.chunk("-1,0,-1");var plane:PackedInt32Array=world.chunk_boundary("-1,0,-1",axis,sign)
			exact=exact and plane==a._boundary(c,"-1,0,-1",axis,sign) and plane.size()==256
			plane[0]=99
	check("all six negative-coordinate planes exact and detached",exact and not world.chunk("-1,0,-1").cells.has(99))
	check("invalid boundary arguments fail closed",world.chunk_boundary("0,0,0",-1,1).is_empty() and world.chunk_boundary("0,0,0",0,0).is_empty())
	var pending:String="0,0,0";b._queued[pending]=true;a._queued[pending]=true
	check("queued body remains pending",same(a,b,keys) and b.readiness(keys).pending==[pending])
	a._queued.clear();b._queued.clear()
	a._derived[pending].physics_frame=Engine.get_physics_frames();b._derived[pending].physics_frame=Engine.get_physics_frames()
	check("same actual physics frame is not ready",same(a,b,keys) and not b.readiness(keys).ready and b.readiness(keys).awaiting_physics==[pending])
	await physics_frame;await process_frame
	check("only subsequent physics frame releases fixture",same(a,b,keys) and b.readiness(keys).ready)
	state.revision+=1
	check("unrelated world revision observed but does not invalidate geometry",same(a,b,keys) and b.readiness(keys).ready and b.readiness(keys).world_revision==11)
	var neighbor:String="1,0,0";var c:Dictionary=state.chunks[neighbor]
	c.cells[Data.local_index(Vector3i(5,5,5),16)]=6;c.revision+=1
	check("neighbor interior edit preserves exact same seam and ready",same(a,b,keys) and b.readiness(keys).ready)
	var local:Vector3i=Vector3i(0,5,5);var index:int=Data.local_index(local,16);var prior:int=c.cells[index]
	c.cells[index]=(prior+1)%7;c.revision+=1
	check("neighbor face material edit invalidates old derivation",same(a,b,keys) and not b.readiness(keys).ready and b.readiness(keys).pending.has(pending))
	for key:String in keys:mark(a,key);mark(b,key)
	state.chunks[pending].revision+=1
	check("own revision invalidates even unchanged cell bytes",same(a,b,keys) and b.readiness(keys).pending.has(pending))
	for key:String in keys:mark(a,key);mark(b,key)
	state.chunks[pending].resident=false;state.chunks[pending].cell_page={"isolated_marker":true};state.chunks[pending].cells=PackedInt32Array()
	var cold_before:Dictionary=state.duplicate(true)
	check("cold body blocked and page never expanded",same(a,b,keys) and b.readiness(keys).cold==[pending] and world.chunk_boundary(pending,0,1).is_empty() and state==cold_before)
	state.chunks[pending].generated=false
	check("allocated ungenerated differs from missing",same(a,b,[pending,"99,0,99"]) and b.readiness([pending]).ungenerated==[pending] and b.readiness(["99,0,99"]).unallocated==["99,0,99"])
	check("empty keys never ready",same(a,b,[]) and not b.readiness([]).ready)
	var legacy:=Legacy.new();legacy.source=world;b.world=legacy
	check("legacy aggregate-only projection keeps exact dependencies",a._dependencies("-1,0,-1")==b._dependencies("-1,0,-1") and same(a,b,keys))
	b.world=world
	var points:Array=[Vector3(-8,0,-8),Vector3(-0.01,0,-0.01),Vector3.ZERO,Vector3(8,8,8)]
	for radius:float in [0,0.32,2.5,16]:
		var old:Dictionary=a.readiness_near(points,radius,0.5,2);var projected:Dictionary=b.readiness_keys_near(points,radius,0.5,2)
		check("near key-only projection exact inclusive lattice radius "+str(radius),projected.ok and projected.keys==old.keys and old==b.readiness_near(points,radius,0.5,2))
	check("key-only projection grants no readiness permission",not b.readiness_keys_near(points).has("ready"))
	for args:Array in [[[],1.0,0.5,2.0],[Array(range(65)),1.0,0.5,2.0],[points,16.01,0.5,2.0],[points,NAN,0.5,2.0],[points,1.0,-0.1,2.0],[[Vector3(INF,0,0)],1.0,0.5,2.0],[["bad"],1.0,0.5,2.0]]:
		check("old invalid bounds/points preserved "+str(checks.size()),a.readiness_near.callv(args)==b.readiness_near.callv(args) and not b.readiness_keys_near.callv(args).ok)
	a.free();b.free()
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"isolated exact invalidation fixtures; manual derived markers are not real mesh/physics or normal gameplay qualification"},"\t"));quit(1 if failed else 0)
