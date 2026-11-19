extends "res://tests/buildings/candidate_tokens_suite.gd"
## Frozen pre-change point predicate vs ordered immutable bucket projection.
class ReferenceSpace extends "res://scripts/buildings/building_space.gd":
	func body_location(p:Dictionary,radius:float=0.26)->Dictionary:
		var k:Array=[p.regionId,p.x,p.y,p.z,radius]
		if body_cache.has(k):return body_cache[k].duplicate(true)
		var y:float=-INF
		for dx in [-radius,0.0,radius]:
			for dz in [-radius,0.0,radius]:
				var feet:=point_location(str(p.regionId),float(p.x)+dx,float(p.z)+dz,float(p.y))
				if feet.is_empty():return {}
				y=maxf(y,float(feet.y))
		if absf(y-float(p.y))>agent.max_step:return {}
		var result:=point_location(str(p.regionId),p.x,p.z,y)
		if not result.is_empty():result.y=y
		if body_cache.size()>=16384:body_cache.clear()
		body_cache[k]=result.duplicate(true)
		return result
	func point_location(region:String,x:float,z:float,reference_y:float)->Dictionary:
		for v in nearby_pieces(region,AABB(Vector3(x,reference_y,z),Vector3.ZERO),true):
			if v.regionId!=region or geometry.definition(v).kind=="roof" or absf(float(v.position.y)-reference_y)>agent.max_step:continue
			var b:AABB=bounds(v)
			if x>=b.position.x-0.001 and x<=b.end.x+0.001 and z>=b.position.z-0.001 and z<=b.end.z+0.001:
				if terrain_clear(region,AABB(Vector3(x-0.01,v.position.y+0.01,z-0.01),Vector3(0.02,0.01,0.02))):
					return {"regionId":region,"x":x,"y":float(v.position.y),"z":z,"buildingId":v.get("buildingId"),"storeyId":v.get("storeyId")}
		var k:Array=[region,floori(x/cell_size),floori(z/cell_size)]
		if not ground_cache.has(k):ground_cache[k]=ground_height(x,z)
		var ground:Variant=ground_cache[k]
		if ground==null or absf(float(ground)-reference_y)>agent.max_step:return {}
		return {"regionId":region,"x":x,"y":float(ground),"z":z,"buildingId":null,"storeyId":null}

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();world.load_snapshot(imported.world)
	var runtime:=Runtime.new();var building:=Building.new()
	expect("same actual source facts and complete world load",runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building}}).ok)
	var before:=world.snapshot();var rows:Array=[]
	for n in 3:
		var variants:Dictionary={}
		for name in (["original","projection"] if n%2==0 else ["projection","original"]):
			var query:RefCounted=ReferenceSpace.new() if name=="original" else Space.new()
			var started:=Time.get_ticks_usec();query.configure(world,building.structures(),building.geometry,building.permission)
			var projection_ms:float=(Time.get_ticks_usec()-started)/1000.0
			variants[name]=measured(query,building,world,imported.facts)
			variants[name].projection_ms=projection_ms
		expect("cold complete route proof unchanged pass "+str(n),variants.original.routes==variants.projection.routes)
		expect("all four source residents retain actual exits pass "+str(n),variants.projection.rows.size()==4 and variants.projection.rows.all(func(r:Dictionary)->bool:return r.ok))
		rows.append({"pass":n,"order":"original-first" if n%2==0 else "projection-first","original":variants.original.rows,"candidate":variants.projection.rows,"original_projection_ms":variants.original.projection_ms,"candidate_projection_ms":variants.projection.projection_ms})
	var old_query:=ReferenceSpace.new();old_query.configure(world,building.structures(),building.geometry,building.permission)
	var new_query:=Space.new();new_query.configure(world,building.structures(),building.geometry,building.permission)
	var mismatches:Array=[];var samples:=0
	for piece:Dictionary in new_query.surfaces:
		var b:AABB=new_query.bounds(piece)
		for offset in [Vector2.ZERO,Vector2(-b.size.x/2-0.001,-b.size.z/2-0.001),Vector2(b.size.x/2+0.001,b.size.z/2+0.001),Vector2(-b.size.x/2,-b.size.z/2),Vector2(b.size.x/2,b.size.z/2)]:
			var at:Vector3=b.get_center()+Vector3(offset.x,0,offset.y)
			for dy in [-0.551,-0.55,0.0,0.55,0.551]:
				var y:float=float(piece.position.y)+dy;samples+=1
				var original:Dictionary=old_query.point_location(piece.regionId,at.x,at.z,y)
				var candidate:Dictionary=new_query.point_location(piece.regionId,at.x,at.z,y)
				if original!=candidate and mismatches.size()<20:mismatches.append({"piece":piece.id,"x":at.x,"y":y,"z":at.z,"before":original,"after":candidate})
	expect("exact floor edge/roof/step-height candidates preserve original order",samples>10000 and mismatches.is_empty(),{"samples":samples,"mismatches":mismatches})
	expect("projection never changes original world or actors",world.snapshot()==before and runtime.facts()==imported.facts)
	print(JSON.stringify({"scope":"B same-process alternating native cold CPU comparison; exact source/rules, no FPS claim","ok":not failed,"checks":checks,"measurements":rows}))
	quit(1 if failed else 0)
