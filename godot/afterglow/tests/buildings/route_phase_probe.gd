extends "res://tests/buildings/profile_domain.gd"
## No new cache. Instrument the unchanged original navigation to decide the
## next cold-door change. Timer overhead and nested inclusive costs are explicit.
class MeteredNavigation extends "res://scripts/buildings/building_navigation.gd":
	var meters:Dictionary={}
	func record(label:String,start:int)->void:
		if not meters.has(label):meters[label]={"calls":0,"inclusive_us":0}
		meters[label].calls+=1;meters[label].inclusive_us+=Time.get_ticks_usec()-start
	func add(p:Dictionary)->int:
		var t:=Time.get_ticks_usec();var result:=super.add(p);record("add_candidate",t);return result
	func straight(a:Dictionary,b:Dictionary)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.straight(a,b);record("straight",t);return result
	func edge(a:int,b:int)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.edge(a,b);record("edge",t);return result
	func verified_path()->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.verified_path();record("native_and_edge_verification",t);return result
	func grid_plan(a:Dictionary,b:Dictionary)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.grid_plan(a,b);record("grid_fallback",t);return result
	func surface_network(a:Dictionary,b:Dictionary,c:Array,d:Dictionary)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.surface_network(a,b,c,d);record("road_fallback",t);return result
	func plan(q:RefCounted,id:String,a:Dictionary,b:Dictionary)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.plan(q,id,a,b);record("complete_route",t);return result

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var r:=Runtime.new();var b:=Building.new()
	r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}})
	var rows:Array=[]
	for a:Dictionary in imported.facts.actors:
		var from:=Geometry.location(a)
		if from.buildingId==null:continue
		for slot:Dictionary in w.extension("generation:"+str(from.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=from.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=w.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var q:RefCounted=b.space();var instrument:=MeteredNavigation.new()
			var actual:=instrument.plan(q,a.id,from,to)
			var original:Dictionary=preload("res://scripts/buildings/building_navigation.gd").new().plan(b.space(),a.id,from,to)
			rows.append({"actor":a.id,"ok":actual.ok and actual==original,"meters":instrument.meters,"nodes":instrument.nodes.size(),"edges":instrument.edges.size(),"native_search_passes":instrument.search_passes})
	print(JSON.stringify({"ok":rows.size()==4 and rows.all(func(row:Dictionary)->bool:return row.ok),"rows":rows,"scope":"original native navigation phase CPU diagnostic only; full returned route equals uninstrumented source; nested inclusive timers cannot be added; not complete prepare_door, native app or FPS"}))
	quit(0 if rows.size()==4 and rows.all(func(row:Dictionary)->bool:return row.ok) else 1)
