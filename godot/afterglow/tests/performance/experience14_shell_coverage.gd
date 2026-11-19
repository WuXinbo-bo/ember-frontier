extends SceneTree
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Data=preload("res://scripts/world/world_data.gd")
class CoverageWorld extends "res://scripts/world/world_view.gd":
	var queries:int=0
	func continuous_outdoor_segment(a:Dictionary,b:Dictionary,limit:float,resident:bool=true)->Dictionary:
		queries+=1;return super.continuous_outdoor_segment(a,b,limit,resident)
class Query extends RefCounted:
	var world:RefCounted
	var cell_size:float=0.5
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:checks.append({"label":label,"ok":ok})
func run()->void:
	var state:Dictionary={"worldId":"coverage:real","seed":713,"generatorVersion":"factory-country-1","revision":1,"config":Data.DEFAULT_CONFIG.duplicate(true),"chunks":{},"regions":{}}
	for x:int in 2:
		var id:String="region:"+str(x)
		state.regions[id]={"id":id,"kind":"rural","generated":true,"bounds":{"min":{"x":x*64,"y":-4,"z":0},"max":{"x":(x+1)*64,"y":20,"z":64}}}
	var cells:=PackedInt32Array();cells.resize(4096)
	for x:int in 16:state.chunks[Data.key(Vector3i(x,0,0))]={"revision":1,"generated":true,"resident":true,"cells":cells}
	var world:=CoverageWorld.new(state);var q:=Query.new();q.world=world;var p:=Policy.new();p._query=q
	var from:Dictionary={"x":1.0,"y":0.5,"z":1.0,"regionId":"region:0","buildingId":null,"storeyId":null}
	var to:Dictionary={"x":65.0,"y":0.5,"z":1.0,"regionId":"region:1","buildingId":null,"storeyId":null}
	check("real C shorter shell query succeeds",p.shell_coverage(world,from,to))
	var count:int=world.queries
	check("same-endpoint longer policy reuses exact positive proof",p._outdoor_coverage(from,to) and world.queries==count)
	var far:Dictionary=to.duplicate(true);far.x=110.0
	check("real C 96m failure does not poison valid 256m segment",not p.shell_coverage(world,from,far) and p._outdoor_coverage(from,far))
	var inside:Dictionary=from.duplicate(true);inside.buildingId="actual:room";inside.storeyId="actual:floor"
	check("indoor shell partition remains rejected",not p.shell_coverage(world,inside,to))
	state.chunks["4,0,0"].generated=false;state.revision+=1
	check("current world revision invalidates old positive seam proof",not p._outdoor_coverage(from,to))
	state.chunks["4,0,0"].generated=true;state.revision+=1
	check("current generated coverage can recover without poisoned failure",p.shell_coverage(world,from,to) and p._outdoor_coverage(from,to))
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"scope":"real C segment semantics on explicit adjacent/chunk/indoor fixtures; no body/LOS permission or FPS claim"}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print("SHELL_COVERAGE "+JSON.stringify(result));quit(1 if failed else 0)
