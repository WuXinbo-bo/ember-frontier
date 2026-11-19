extends "res://tests/buildings/profile_domain.gd"
## Nested CPU diagnostics only. No gameplay counters or production timers.
class MeteredSpace extends "res://scripts/buildings/building_space.gd":
	var meters:Dictionary={}
	func record(label:String,t:int)->void:
		if not meters.has(label):meters[label]={"calls":0,"inclusive_us":0}
		meters[label].calls+=1;meters[label].inclusive_us+=Time.get_ticks_usec()-t
	func floor_sample(region:String,x:float,z:float,y:float)->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.floor_sample(region,x,z,y);record("floor_sample",t);return out
	func body_location(p:Dictionary,radius:float=0.26)->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.body_location(p,radius);record("body_location",t);return out
	func blockers(a:Dictionary,b:Dictionary,id:String,doors:bool=false,exclude:String="")->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.blockers(a,b,id,doors,exclude);record("blockers",t);return out
	func terrain_clear(region:String,volume:AABB,exclude:String="")->bool:
		var t:=Time.get_ticks_usec();var out:=super.terrain_clear(region,volume,exclude);record("terrain_clear",t);return out
	func walk_uncached(id:String,a:Dictionary,b:Dictionary,doors:bool)->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.walk_uncached(id,a,b,doors);record("walk_uncached",t);return out

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var b:=Building.new();var r:=Runtime.new();r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}})
	var rows:Array=[]
	for a:Dictionary in imported.facts.actors:
		var from:=Geometry.location(a)
		if from.buildingId==null:continue
		for slot:Dictionary in w.extension("generation:"+str(from.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=from.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=w.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var q:=MeteredSpace.new();q.configure(w,b.structures(),b.geometry,func(id:String,target:String,kind:String,p:Dictionary)->Variant:return b.permission(id,target,kind,p))
			var actual:Dictionary=q.route(a.id,from,to)
			var original:Dictionary=b.space().route(a.id,from,to)
			rows.append({"actor":a.id,"ok":actual==original and actual.ok,"meters":q.meters})
	print(JSON.stringify({"ok":rows.size()==4 and rows.all(func(v:Dictionary)->bool:return v.ok),"rows":rows,"scope":"nested same-result route CPU diagnosis; not full cold door, FPS or formal qualification"}))
	quit(0 if rows.size()==4 and rows.all(func(v:Dictionary)->bool:return v.ok) else 1)
