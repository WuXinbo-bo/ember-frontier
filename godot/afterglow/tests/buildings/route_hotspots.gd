extends "res://tests/buildings/profile_domain.gd"
## Inclusive timings identify repeated immutable geometry work. Not an FPS test.
class MeteredSpace extends "res://scripts/buildings/building_space.gd":
	var meters:Dictionary={}
	var failed_body_keys:Dictionary={}
	func record(label:String,started:int)->void:
		if not meters.has(label):meters[label]={"calls":0,"inclusive_usec":0}
		meters[label].calls+=1;meters[label].inclusive_usec+=Time.get_ticks_usec()-started
	func point_location(region:String,x:float,z:float,y:float)->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.point_location(region,x,z,y);record("point_location",t);return value
	func body_location(p:Dictionary,radius:float=0.26)->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.body_location(p,radius);record("body_location",t)
		if value.is_empty():
			var key:Array=[p.regionId,p.x,p.y,p.z,radius]
			record("body_failed_repeat" if failed_body_keys.has(key) else "body_failed_unique",t)
			failed_body_keys[key]=true
		return value
	func floor_sample(region:String,x:float,z:float,y:float)->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.floor_sample(region,x,z,y);record("floor_sample",t);return value
	func candidates(region:String,a:Vector3,b:Vector3,radius:float)->Array:
		var t:=Time.get_ticks_usec();var value:=super.candidates(region,a,b,radius);record("candidates",t);return value
	func terrain_clear(region:String,volume:AABB,exclude_id:String="")->bool:
		var t:=Time.get_ticks_usec();var value:=super.terrain_clear(region,volume,exclude_id);record("terrain_clear",t);return value
	func terrain_clear_uncached(region:String,volume:AABB,exclude_id:String)->bool:
		var t:=Time.get_ticks_usec();var value:=super.terrain_clear_uncached(region,volume,exclude_id);record("terrain_clear_uncached",t);return value
	func walk(actor_id:String,from:Dictionary,to:Dictionary,allow_doors:bool=false)->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.walk(actor_id,from,to,allow_doors);record("walk",t);return value
	func blockers(a:Dictionary,b:Dictionary,actor_id:String,allow_doors:bool=false,exclude_id:String="")->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.blockers(a,b,actor_id,allow_doors,exclude_id);record("blockers",t);return value
	func stair_point(p:Dictionary)->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.stair_point(p);record("stair_point",t);return value
	func use_points(piece:Dictionary)->Array:
		var t:=Time.get_ticks_usec();var value:=super.use_points(piece);record("use_points",t);return value

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();world.load_snapshot(imported.world)
	var runtime:=Runtime.new();var building:=Building.new()
	runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building}})
	var rows:Array=[]
	for actor:Dictionary in imported.facts.actors:
		var p:=Geometry.location(actor)
		if p.buildingId==null:continue
		var query:=MeteredSpace.new();query.configure(world,building.structures(),building.geometry,building.permission)
		for slot:Dictionary in world.extension("generation:"+str(p.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=p.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=world.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var navigator:=preload("res://scripts/buildings/building_navigation.gd").new()
			var t:=Time.get_ticks_usec();var route:Dictionary=navigator.plan(query,actor.id,p,to)
			rows.append({"actor":actor.id,"ms":float(Time.get_ticks_usec()-t)/1000,"ok":route.ok,"visited":route.get("visited"),"steps":route.get("steps",[]).size(),"native_search_passes":navigator.search_passes,"eager_fallback":navigator.graph.neighbor_filter_enabled if navigator.graph!=null else false,"inclusive_meters":query.meters.duplicate(true)})
	print(JSON.stringify({"scope":"B cold route inclusive CPU instrumentation; extra timer overhead; not FPS or budget evidence","ok":rows.size()==4 and rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}))
	quit(0 if rows.size()==4 and rows.all(func(r:Dictionary)->bool:return r.ok) else 1)
