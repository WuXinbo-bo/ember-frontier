extends RefCounted
## Finite countryside planning inputs. These are never sampled on a revisit.
## Reuses native FNL/AStar and the existing finite half-metre grade solver.
const Data=preload("res://scripts/world/world_data.gd")
const Site=preload("res://scripts/world/site_relief.gd")
const Relief=preload("res://scripts/world/local_relief.gd")
const Broad=preload("res://scripts/world/broad_terraces.gd")
const VERSION="factory-country-1"
const SCENARIO="factory-settlement-r34"
const SIZE=64
const COORD_LIMIT=8
const MAX_REGIONS=24
const STREAMS=["terrain","layout","resources","content","decor"]

static func hash_key(seed:int,stream:String,key:String)->int:
	assert(stream in STREAMS,"Unknown generation random stream")
	return (str(seed)+":"+VERSION+":"+stream+":"+key).sha256_text().substr(0,8).hex_to_int()

static func vec(x:float,y:float,z:float)->Dictionary:
	return {"x":x,"y":y,"z":z}

static func region_id(coord:Vector2i)->String:
	if coord==Vector2i.ZERO:return "RH-HOME"
	if coord==Vector2i(0,-1):return "RH-VILLAGE"
	return "R34:%d:%d"%[coord.x,coord.y]

static func noise(seed:int)->FastNoiseLite:
	var n:=FastNoiseLite.new()
	n.seed=hash_key(seed,"terrain","fnl")&0x7fffffff
	n.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;n.frequency=0.018
	n.fractal_type=FastNoiseLite.FRACTAL_FBM;n.fractal_octaves=2;n.fractal_gain=0.38
	return n

static func landforms(seed:int,coord:Vector2i)->Array:
	var ox:float=coord.x*SIZE;var oz:float=coord.y*SIZE
	var h:int=hash_key(seed,"layout","land:%d:%d"%[coord.x,coord.y])
	var shift:float=float(h%3)*2.0
	var n:=noise(seed);var id:String=region_id(coord)
	var field:float=Relief._half(clampf(Relief._base(n,ox+18,oz+52)-0.5,-0.5,3.0))
	return [
		{"id":id+":field","use":"field","xz":[ox+8+shift,oz+46,ox+28+shift,oz+58],"height":field,"blend":3.0,"material":2},
		{"id":id+":bund","use":"field-bank","xz":[ox+6+shift,oz+45,ox+8+shift,oz+59],"height":minf(field+0.5,3.0),"blend":2.0,"material":1},
		{"id":id+":ditch","use":"dry-ditch","xz":[ox+39,oz+43,ox+42,oz+59],"height":field,"blend":3.0,"material":3,"surface_shape":{"kind":"closed-local-channel-v1","depth_m":0.5,"half_width_m":3.0,"end_taper_m":4.0,"meander_m":1.25}},
		{"id":id+":quarry","use":"old-stockyard","xz":[ox+46,oz+6,ox+58,oz+18],"height":Relief._half(Relief._base(n,ox+52,oz+12)),"blend":3.0,"material":3}]

static func spaces(coord:Vector2i)->Array:
	var ox:float=coord.x*SIZE;var oz:float=coord.y*SIZE;var id:String=region_id(coord)
	var specs:Array=[
		["home-terrace",[4,22,28,44],"starting-service-and-buildable-land"],
		["contour-lanes",[28,0,44,64],"physical-transport-loading-retreat"],
		["fields-bunds-ditch",[6,43,44,60],"land-and-route-tradeoff-no-crop-yield"],
		["forest-edge",[44,22,62,60],"finite-normal-axe-timber"],
		["old-stockyard",[44,4,60,20],"normal-pickaxe-stone-and-content-anchor"],
		["townward-road",[22,0,44,22],"fork-landmark-and-expansion"]]
	var result:Array=[]
	for spec:Array in specs:
		var r:Array=spec[1]
		result.append({"id":id+":"+str(spec[0]),"type":spec[0],"xz":[ox+r[0],oz+r[1],ox+r[2],oz+r[3]],"purpose":spec[2],"owner_region":id})
	return result

static func port(seed:int,coord:Vector2i,direction:String)->Dictionary:
	var horizontal:bool=direction in ["north","south"]
	var edge:Vector2i=coord+Vector2i(0,1) if direction=="south" else coord+Vector2i(1,0) if direction=="east" else coord
	var key:String=("z:" if horizontal else "x:")+"%d:%d"%[edge.x,edge.y]
	var offset:float=26.0+float(hash_key(seed,"layout","edge:"+key)%6)*2.0
	var adjacent:Vector2i=coord+{"north":Vector2i(0,-1),"south":Vector2i(0,1),"west":Vector2i(-1,0),"east":Vector2i(1,0)}[direction]
	return {"id":"r34:edge:"+key,"direction":direction,"position":vec(coord.x*SIZE+offset if horizontal else edge.x*SIZE,0,edge.y*SIZE if horizontal else coord.y*SIZE+offset),"width":2.5,"to_region_id":region_id(adjacent),"to_coord":{"x":adjacent.x,"z":adjacent.y},"owner_coord":{"x":edge.x,"z":edge.y}}

static func prepare_height(plan:Dictionary,parcels:Array)->void:
	var n:=noise(int(plan.seed));var coord:=Vector2i(plan.region_coord.x,plan.region_coord.z)
	# Nine owners supply an identical absolute collar. Never normalize a region
	# separately, and never depend on which neighbour has already been explored.
	var lands:Array=[]
	for z in range(coord.y-1,coord.y+2):
		for x in range(coord.x-1,coord.x+2):lands.append_array(landforms(int(plan.seed),Vector2i(x,z)))
	plan.grade_controls=[]
	for parcel:Dictionary in parcels:plan.grade_controls.append(parcel.pad.duplicate(true))
	plan.landforms=landforms(int(plan.seed),coord)
	plan.height={"source":"authoritative voxels after first commit","cell_size":0.5,"noise":"Godot FastNoiseLite OpenSimplex2S FBM2","frequency":0.018,"noise_seed":n.seed,"grade_model":Site.MODEL,"terrain_revision":1,"reused_grade_algorithm":Site.MODEL,"generation_namespace":VERSION}
	Site.prepare(plan,n,lands)
	for p:Dictionary in plan.road_ports:p.position.y=Site.height(plan,p.position.x,p.position.z)

static func _inside(x:float,z:float,r:Array,margin:float)->bool:
	return x>r[0]-margin and x<r[2]+margin and z>r[1]-margin and z<r[3]+margin

static func _path(plan:Dictionary,grid:AStarGrid2D,start:Vector2i,end:Vector2i,id:String,width:float,purpose:String)->Dictionary:
	var route:PackedVector2Array=PackedVector2Array()
	if not grid.is_in_boundsv(start) or not grid.is_in_boundsv(end):return Data.reject("ROAD_ENDPOINT_OUTSIDE",id)
	if grid.is_point_solid(start) or grid.is_point_solid(end):return Data.reject("ROAD_ENDPOINT_BLOCKED",id)
	var points:Array[Vector2i]=grid.get_id_path(start,end)
	if points.is_empty():return Data.reject("NO_COUNTRY_ROAD",id)
	# Store corners, not every metre. Raster uses the same grade field across
	# the entire width, so dropping a collinear point cannot change any cells.
	for i in points.size():
		if i>0 and i<points.size()-1 and points[i]-points[i-1]==points[i+1]-points[i]:continue
		route.append(Vector2(points[i]))
	var absolute:Array=[];var ox:float=plan.region_coord.x*SIZE;var oz:float=plan.region_coord.z*SIZE
	for point:Vector2 in route:absolute.append(vec(ox+point.x,Site.height(plan,ox+point.x,oz+point.y),oz+point.y))
	return {"ok":true,"path":{"id":id,"width":width,"shoulder":0.75,"material":4,"purpose":purpose,"points":absolute}}

static func roads(plan:Dictionary)->Dictionary:
	var grid:=AStarGrid2D.new();grid.region=Rect2i(0,0,65,65)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER;grid.update()
	var ox:float=plan.region_coord.x*SIZE;var oz:float=plan.region_coord.z*SIZE
	for z in 65:
		for x in 65:
			var wx:float=ox+x;var wz:float=oz+z;var h:float=Site.height(plan,wx,wz)
			var slope:float=absf(Site.height(plan,minf(wx+1,ox+64),wz)-h)+absf(Site.height(plan,wx,minf(wz+1,oz+64))-h)
			grid.set_point_weight_scale(Vector2i(x,z),1.0+slope*7.0)
			# Leave a constant clear boundary collar shared by both owners.
			for p:Dictionary in plan.parcels:
				if _inside(wx,wz,p.pad.xz,1.5):grid.set_point_solid(Vector2i(x,z),true)
	var hub:=Vector2i(34,30);var paths:Array=[]
	for p:Dictionary in plan.road_ports:
		var target:=Vector2i(roundi(p.position.x-ox),roundi(p.position.z-oz))
		var made:Dictionary=_path(plan,grid,hub,target,plan.region_id+":"+p.direction,2.5,"transport-and-defence-access")
		if not made.ok:return made
		paths.append(made.path)
	# This bounded loop provides a second physical approach to the stockyard;
	# the field spur is shorter but narrower than the loaded transport route.
	var links:Array=[
		[Vector2i(34,30),Vector2i(50,30),"forest-access",1.5],
		[Vector2i(50,30),Vector2i(52,12),"quarry-access",2.5],
		[Vector2i(52,12),Vector2i(34,12),"quarry-loop",2.5],
		[Vector2i(34,12),Vector2i(34,30),"retreat-link",2.5],
		[Vector2i(34,30),Vector2i(24,48),"field-shortcut",1.5]]
	for link:Array in links:
		var made:Dictionary=_path(plan,grid,link[0],link[1],plan.region_id+":"+link[2],link[3],link[2])
		if not made.ok:return made
		paths.append(made.path)
	for p:Dictionary in plan.parcels:
		for entrance:Dictionary in p.entrance_ports:
			var pos:Dictionary=entrance.position;var start:=Vector2i(roundi(pos.x-ox),roundi(pos.z-oz))
			# A service mouth is deliberately on its pad. Open only its straight
			# reserved approach, never unblock the whole building for a road.
			var direction:Vector2i={"north":Vector2i(0,-1),"south":Vector2i(0,1),"west":Vector2i(-1,0),"east":Vector2i(1,0)}[entrance.direction]
			var outside:Vector2i=start
			for i in 28:
				if not grid.is_in_boundsv(outside):return Data.reject("MODULE_PORT_NO_APPROACH",p.id)
				grid.set_point_solid(outside,false)
				if not _inside(ox+outside.x,oz+outside.y,p.pad.xz,2.0):break
				outside+=direction
			var access:Dictionary=_path(plan,grid,outside,hub,"access:"+p.id+":"+entrance.id,2.0,"module-service")
			if not access.ok:return access
			var first:Dictionary=entrance.position.duplicate(true)
			access.path.points.push_front(first);paths.append(access.path)
	return {"ok":true,"paths":paths}
