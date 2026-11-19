extends SceneTree
## Exact saved-state return-home path. CPU attribution only; no renderer/edits/ticks.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Phase=preload("res://tests/buildings/route_phase_probe.gd")
class MeteredSpace extends "res://scripts/buildings/building_space.gd":
	var meters:Dictionary={}
	var columns:Dictionary={}
	var failed_bodies:Dictionary={}
	func record(label:String,t:int)->void:
		if not meters.has(label):meters[label]={"calls":0,"inclusive_us":0}
		meters[label].calls+=1;meters[label].inclusive_us+=Time.get_ticks_usec()-t
	func ground_height(x:float,z:float)->Variant:
		var t:=Time.get_ticks_usec();var v:Variant=super.ground_height(x,z);record("ground_height",t)
		var key:=Vector2i(floori(x/cell_size),floori(z/cell_size));columns[key]=true;return v
	func cell_material(cell:Vector3i)->int:
		var t:=Time.get_ticks_usec();var v:=super.cell_material(cell);record("cell_material",t);return v
	func floor_sample(r:String,x:float,z:float,y:float)->Dictionary:
		var t:=Time.get_ticks_usec();var v:=super.floor_sample(r,x,z,y);record("floor_sample",t);return v
	func body_location(p:Dictionary,radius:float=0.26)->Dictionary:
		var t:=Time.get_ticks_usec();var v:=super.body_location(p,radius);record("body_location",t)
		if v.is_empty():
			var key:Array=[p.regionId,p.x,p.y,p.z,radius]
			record("body_fail_repeat" if failed_bodies.has(key) else "body_fail_unique",t);failed_bodies[key]=true
		return v
	func blockers(a:Dictionary,b:Dictionary,id:String,doors:bool=false,exclude:String="")->Dictionary:
		var t:=Time.get_ticks_usec();var v:=super.blockers(a,b,id,doors,exclude);record("blockers",t);return v
	func walk(id:String,a:Dictionary,b:Dictionary,doors:bool=false)->Dictionary:
		var t:=Time.get_ticks_usec();var v:=super.walk(id,a,b,doors);record("walk",t);return v
var checks:Array=[]
func check(label:String,ok:bool)->void:checks.append({"name":label,"ok":ok})
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var source:Dictionary=evidence.rows[0].profile.actions.route.slow[0]
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("actual Native saved-state assembly",built.get("ok",false))
	if not built.get("ok",false):print(JSON.stringify({"checks":checks}));quit(1);return
	var rt:RefCounted=built.runtime;var building:RefCounted=rt._services.buildings
	var capture:Dictionary=rt.capture_checkpoint();var rows:Array=[]
	for i:int in 3:
		var q:RefCounted=building.space();var t:=Time.get_ticks_usec()
		var actual:Dictionary=q.route(source.actor_id,source.from,source.to)
		var cold:int=Time.get_ticks_usec()-t;t=Time.get_ticks_usec()
		var hot:Dictionary=q.route(source.actor_id,source.from,source.to)
		rows.append({"cold_us":cold,"hot_us":Time.get_ticks_usec()-t,"route":actual})
		check("cold exact original recorded route "+str(i),Data.json_equal(actual,source.result))
		check("hot exact original recorded route "+str(i),Data.json_equal(hot,source.result))
	var q:=MeteredSpace.new();q.configure(built.world,building.structures(),building.geometry,building.permission)
	var nav:=Phase.MeteredNavigation.new();var measured:Dictionary=nav.plan(q,source.actor_id,source.from,source.to)
	check("instrumented exact recorded route",Data.json_equal(measured,source.result))
	check("full authority unchanged",Data.json_equal(rt.capture_checkpoint(),capture))
	var result:Dictionary={"checks":checks,"rows":rows,"space_meters":q.meters,"distinct_columns":q.columns.size(),"nav_meters":nav.meters,"nodes":nav.nodes.size(),"scope":"same exact saved-state route, cold new projection/hot same projection; nested instrumentation inclusive, background contention disclosed; no FPS claim"}
	FileAccess.open(output+"/detail.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks,"rows":rows.map(func(r:Dictionary)->Dictionary:return {"cold_us":r.cold_us,"hot_us":r.hot_us}),"space_meters":q.meters,"nav_meters":nav.meters,"distinct_columns":q.columns.size()}))
	rt.retire();quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
