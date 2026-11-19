extends RefCounted
## New-world-only, finite coordinate mapgen. Persist the plan once; cells are
## authoritative thereafter. No runtime, inventory, clock, save slot or commit.
const Data = preload("res://scripts/world/world_data.gd")
const Contract = preload("res://scripts/world/generation_contract.gd")
const BoundedLayout = preload("res://scripts/world/bounded_layout.gd")
const Broad = preload("res://scripts/world/broad_terraces.gd")
const Hills = preload("res://scripts/world/local_hills.gd")
const Relief=preload("res://scripts/world/local_relief.gd")
const Site=preload("res://scripts/world/site_relief.gd")
const VERSION = "rural-2"
const SCHEMA = "afterglow-settlement-plan-v1"
const SIZE = 64
const MAX_REGIONS = 24
const COORD_LIMIT = 8

static func _v(x: float,y: float,z: float) -> Dictionary:
	return {"x":x,"y":y,"z":z}

static func _hash(seed: int,tag: String) -> int:
	# Explicit coordinate substreams. Never consume a shared/request-order RNG.
	return (str(seed)+":"+VERSION+":"+tag).sha256_text().substr(0,8).hex_to_int()

static func region_id(coord: Vector2i) -> String:
	if coord==Vector2i(0,0): return "RH-HOME"
	if coord==Vector2i(0,-1): return "RH-VILLAGE"
	return "R2:%d:%d" % [coord.x,coord.y]

static func _noise(seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed & 0x7fffffff
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.38
	return noise

static func _base(noise: FastNoiseLite,x: float,z: float) -> float:
	return clampf(1.5+noise.get_noise_2d(x,z)*3.5,-1.0,6.0)

static func _snap(height: float) -> float:
	return roundf(height*2.0)*0.5

static func _distance(x: float,z: float,a: Dictionary,b: Dictionary) -> Vector2:
	var delta := Vector2(b.x-a.x,b.z-a.z)
	var t := clampf(Vector2(x-a.x,z-a.z).dot(delta)/maxf(delta.length_squared(),0.000001),0,1)
	return Vector2(Vector2(x-a.x,z-a.z).distance_to(delta*t),t)

static func _rect_distance(x: float,z: float,rect: Array) -> float:
	return Vector2(maxf(maxf(rect[0]-x,0),x-rect[2]),maxf(maxf(rect[1]-z,0),z-rect[3])).length()

static func _port(seed: int,coord: Vector2i,direction: String,noise: FastNoiseLite) -> Dictionary:
	var horizontal := direction in ["north","south"]
	# Both sides hash the SAME boundary, including at negative coordinates.
	var edge := coord+Vector2i(0,1) if direction=="south" else coord+Vector2i(1,0) if direction=="east" else coord
	var tag := ("z:" if horizontal else "x:")+str(edge.x)+":"+str(edge.y)
	var offset := 28+int(_hash(seed,tag)%5)*2
	var x := float(coord.x*SIZE+offset) if horizontal else float(edge.x*SIZE)
	var z := float(edge.y*SIZE) if horizontal else float(coord.y*SIZE+offset)
	var adjacent: Vector2i = coord+{"north":Vector2i(0,-1),"south":Vector2i(0,1),"west":Vector2i(-1,0),"east":Vector2i(1,0)}[direction]
	return {"id":"edge:"+tag,"direction":direction,"position":_v(x,_snap(_base(noise,x,z)),z),"width":4.0,"to_region_id":region_id(adjacent),"to_coord":{"x":adjacent.x,"z":adjacent.y}}

static func _profile(profiles: Array,id: String) -> Dictionary:
	for profile in profiles:
		if profile is Dictionary and str(profile.get("id",profile.get("profile_id","")))==id: return profile
	return {}

static func _parcels(seed: int,coord: Vector2i,noise: FastNoiseLite,profiles: Array,selection: Dictionary={}) -> Array:
	var specs: Array = []
	if coord==Vector2i.ZERO:
		specs=[{"id":"home","profile_id":"homestead_l" if _hash(seed,"home-family")%2==0 else "homestead_wing","x":8,"z":26,"w":16,"d":14,"raise":1.5},
			{"id":"shed","profile_id":"shed_lean" if _hash(seed,"shed-family")%2==0 else "shed_through","x":4,"z":8,"w":8,"d":8,"raise":0.5}]
	elif coord==Vector2i(0,-1):
		specs=[{"id":"store","profile_id":"shop_front","x":8,"z":38,"w":10,"d":10,"raise":0.5},
			{"id":"repair","profile_id":"repair_court","x":44,"z":20,"w":12,"d":12,"raise":1.0},
			{"id":"neighbor","profile_id":"homestead_wing","x":8,"z":8,"w":16,"d":12,"raise":0.5}]
	if selection.get("version")==2:
		var families:Array=selection.ids
		for spec:Dictionary in specs:
			if spec.id in ["home","neighbor"]:spec.profile_id=families[_hash(seed,str(spec.id)+"-family")%families.size()]
	var result: Array = []
	for spec in specs:
		var profile := _profile(profiles,spec.profile_id)
		var footprint: Dictionary = profile.get("footprint",{"min":{"x":-0.2,"z":-0.2},"max":{"x":spec.w+0.2,"z":spec.d+0.2}})
		var w := ceilf(float(footprint.max.x)-0.2)
		var d := ceilf(float(footprint.max.z)-0.2)
		# Reject larger/unrecognized contracts at the caller, don't silently crop.
		var x := float(coord.x*SIZE+spec.x)
		var z := float(coord.y*SIZE+spec.z)
		var y := _snap(_base(noise,x+w/2,z+d/2)+spec.raise+float(_hash(seed,"pad:"+spec.id)%2)*0.5)
		var local_ports: Array = profile.get("entrance_ports",[{"id":"front","position":[w/2,0,d+1.2]}])
		var ports: Array = []
		for port in local_ports:
			var p: Array = port.position
			var direction := "north" if p[2]<0 else "west" if p[0]<0 else "east" if p[0]>w else "south"
			ports.append({"id":str(port.id),"position":_v(x+p[0],y+p[1],z+p[2]),"width":port.get("width",1.6),"direction":direction})
		var reserve: Array = []
		for item in profile.get("use_reservations",[]):
			var b: Array = item.rect
			reserve.append({"id":item.id,"bounds":{"min":_v(x+b[0],y+item.min_y,z+b[1]),"max":_v(x+b[2],y+item.max_y,z+b[3])}})
		# Consume B's complete physical contract, including the real yard and
		# exterior gate sweeps. Do not guess courtyard depth from family names.
		var rect := [x+float(footprint.min.x)-1.8,z+float(footprint.min.z)-1.8,x+float(footprint.max.x)+1.8,z+float(footprint.max.z)+1.8]
		for foundation in profile.get("foundation",{}).get("pad_rectangles",[]):
			rect=[minf(rect[0],x+foundation[0]-0.5),minf(rect[1],z+foundation[1]-0.5),maxf(rect[2],x+foundation[2]+0.5),maxf(rect[3],z+foundation[3]+0.5)]
		for reservation in reserve:
			var b: Dictionary=reservation.bounds
			rect=[minf(rect[0],b.min.x-0.5),minf(rect[1],b.min.z-0.5),maxf(rect[2],b.max.x+0.5),maxf(rect[3],b.max.z+0.5)]
		for port in ports:
			var p: Dictionary=port.position
			rect=[minf(rect[0],p.x-0.5),minf(rect[1],p.z-0.5),maxf(rect[2],p.x+0.5),maxf(rect[3],p.z+0.5)]
		for i in rect.size():rect[i]=_snap(rect[i])
		var npc: Array=[]
		for anchor in profile.get("npc_anchors",[]):
			var p: Array=anchor.position
			npc.append({"id":anchor.id,"purpose":anchor.purpose,"position":_v(x+p[0],y+p[1],z+p[2])})
		result.append({"id":region_id(coord)+":"+spec.id,"site_id":spec.id,"profile_id":spec.profile_id,"profile_resolved":not profile.is_empty(),"recipe_id":spec.profile_id,"origin":_v(x,y,z),"quarter_turn":0,"footprint":footprint.duplicate(true),"pad":{"xz":rect,"height":y,"blend":4.0},"entrance_ports":ports,"use_reservations":reserve,"npc_anchors":npc})
	if coord==Vector2i.ZERO and result.size()==2:
		# Back-yard shed is one metre below the house, leaving broad treads
		# compatible with a 0.52m-wide body rather than only a point probe.
		var shed: Dictionary=result[1]
		var target := float(result[0].origin.y)-1.0
		var delta := target-float(shed.origin.y)
		shed.origin.y=target;shed.pad.height=target
		for port in shed.entrance_ports: port.position.y+=delta
		for reservation in shed.use_reservations: reservation.bounds.min.y+=delta;reservation.bounds.max.y+=delta
		for anchor in shed.npc_anchors: anchor.position.y+=delta
	return BoundedLayout.apply(seed,coord,result) if selection.has("layout_policy") else result

static func _terrain_height(plan: Dictionary,noise: FastNoiseLite,x: float,z: float) -> float:
	if plan.height.get("grade_model","")==Broad.MODEL:return Broad.height(plan,x,z)
	if plan.height.get("grade_model","")==Hills.MODEL:return Hills.height(plan,x,z)
	if plan.height.get("grade_model","")==Relief.MODEL:return Relief.height(plan,x,z)
	if plan.height.get("grade_model","")==Site.MODEL:return Site.height(plan,x,z)
	var height := _village_base(noise,x,z) if plan.height.get("grade_model","")=="village-contours-v4" else _base(noise,x,z)
	for land in plan.landforms:
		var distance := _rect_distance(x,z,land.xz)
		var weight := 1.0-smoothstep(0.0,float(land.blend),distance)
		height=lerpf(height,float(land.height),weight)
	if plan.height.get("grade_model","")=="village-contours-v4":return _contoured_apron(plan,noise,height,x,z)
	return _bounded_grade(plan,height,x,z)

static func _village_base(noise:FastNoiseLite,x:float,z:float)->float:
	# Metre-scale slope folds, shared in absolute coordinates. The same native
	# coherent noise feeds terrain and road grade; never hash/rattle single cells.
	return _base(noise,x,z)+noise.get_noise_2d(x*3.0+417.0,z*3.0-193.0)*0.7

static func _contoured_apron(plan:Dictionary,noise:FastNoiseLite,height:float,x:float,z:float)->float:
	# Reuse the native low-frequency base as a displacement field. Blending
	# toward a constant rectangle erases its tangential variation and produces
	# ruler-straight half-metre contours. Match the nearest actual pad edge,
	# then fade its height correction over the same finite 12m support area.
	var sum:float=0.0;var correction:float=0.0;var influence:float=0.0
	for pad:Dictionary in plan.grade_controls:
		var distance:float=_rect_distance(x,z,pad.xz)
		if distance<=0:return float(pad.height)
		if distance>=12.0:continue
		var weight:float=1.0-smoothstep(0.0,12.0,distance)
		var normalized:float=pow(weight/maxf(distance,0.01),2)
		var edge_x:float=clampf(x,pad.xz[0],pad.xz[2]);var edge_z:float=clampf(z,pad.xz[1],pad.xz[3])
		correction+=(float(pad.height)-_village_base(noise,edge_x,edge_z))*normalized
		sum+=normalized;influence=maxf(influence,weight)
	return height+correction/sum*influence if sum>0 else height

static func _bounded_grade(plan: Dictionary,height: float,x: float,z: float) -> float:
	if plan.height.get("grade_model","") in ["local-apron-v2","local-apron-v3","village-contours-v4"]:return _local_apron(plan,height,x,z)
	# A shared grade field resolves intersections before rasterization. Nearest
	# path selection previously made two crossing roads disagree by metres.
	# Distance envelopes are 0.25m/m Lipschitz; broad treads also accommodate
	# the nine support probes of B's real 0.52m-wide body. Pads retain exact Y.
	var lower := -INF;var upper := INF
	for pad in plan.grade_controls:
		var distance := _rect_distance(x,z,pad.xz)
		if plan.height.get("grade_model","")=="organic-local-v1" and distance>0:
			# rural-3 only: soften the long rectangular apron contours while
			# keeping every actual pad exact. The coordinate field is shared by
			# both sides of a border; it is never recomputed on an explored cell.
			var bend:float=(sin(x*0.17+z*0.11+float(plan.seed%97))+sin(z*0.19-x*0.09))*0.32
			distance=maxf(0.0,distance+bend*smoothstep(0.0,2.0,distance))
		lower=maxf(lower,float(pad.height)-distance*0.25)
		upper=minf(upper,float(pad.height)+distance*0.25)
	return clampf(height,lower,upper)

static func _local_apron(plan:Dictionary,height:float,x:float,z:float,curved:bool=true)->float:
	# Finite world-coordinate support field, shared by every region. A smooth
	# local displacement preserves the natural base instead of clipping it to
	# long constant-slope rectangular cones. The saved v1 algorithm stays above.
	# 12m is part of model v2; changing it requires another persisted model ID.
	var sum:=0.0;var target:=0.0;var influence:=0.0
	var bend:float=0.0
	if curved:bend=sin(x*0.14+z*0.11+float(plan.seed%97))*1.2+sin(z*0.13-x*0.08)*0.6
	for pad:Dictionary in plan.grade_controls:
		var distance:=_rect_distance(x,z,pad.xz)
		if distance<=0:return float(pad.height)
		if distance>=12.0:continue
		# Broad, metre-scale edge curvature, not per-cell height noise. Fade to
		# zero at both ends so pad contact and the finite 12m boundary stay exact.
		if curved:
			distance+=bend*pow(sin(PI*distance/12.0),2)
		var weight:float=1.0-smoothstep(0.0,12.0,distance)
		var normalized:float=pow(weight/maxf(distance,0.01),2)
		sum+=normalized;target+=float(pad.height)*normalized
		influence=maxf(influence,weight)
	return lerpf(height,target/sum,influence) if sum>0 else height

static func _road_grade(plan: Dictionary,noise: FastNoiseLite,x: float,z: float) -> float:
	if plan.height.get("grade_model","")==Broad.MODEL:return Broad.height(plan,x,z)
	if plan.height.get("grade_model","")==Hills.MODEL:return Hills.height(plan,x,z)
	if plan.height.get("grade_model","")==Relief.MODEL:return Relief.height(plan,x,z)
	if plan.height.get("grade_model","")==Site.MODEL:return Site.height(plan,x,z)
	# The whole real road width uses one gentler grade field. Curved surrounding
	# shoulders must not compress a 0.5m tread beneath B's 0.52m body footprint.
	if plan.height.get("grade_model","")=="local-apron-v2":return _local_apron(plan,_base(noise,x,z),x,z,false)
	if plan.height.get("grade_model","")=="village-contours-v4":return _contoured_apron(plan,noise,_village_base(noise,x,z),x,z)
	if plan.height.get("grade_model","")=="local-apron-v3":
		# One compatible 0.25m/m cone envelope at every road/access point and
		# shared boundary. Unlike normalized inverse weights it cannot amplify
		# the slope at the meeting point of a high and low pad. Off-road land
		# still uses its finite curved 12m apron and actual FastNoiseLite base.
		var lower:float=-INF;var upper:float=INF
		for pad:Dictionary in plan.grade_controls:
			var distance:float=_rect_distance(x,z,pad.xz)
			lower=maxf(lower,float(pad.height)-distance*0.25)
			upper=minf(upper,float(pad.height)+distance*0.25)
		return clampf(_base(noise,x,z),lower,upper)
	return _bounded_grade(plan,_base(noise,x,z),x,z)

static func _roads(plan: Dictionary,noise: FastNoiseLite) -> Array:
	# Godot's own A*, used only for mapgen. B retains actor/door navigation.
	var grid := AStarGrid2D.new()
	# One-metre search cells preserve the real five-metre rear lane between
	# shed and house aprons. A two-metre grid could miss that corridor entirely.
	grid.region=Rect2i(0,0,65,65);grid.cell_size=Vector2.ONE
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	var village_contours:bool=plan.height.get("grade_model","") in ["village-contours-v4",Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]
	var ox := float(plan.region_coord.x*SIZE)
	var oz := float(plan.region_coord.z*SIZE)
	for z in 65:
		for x in 65:
			var wx := ox+x;var wz := oz+z
			var h := _terrain_height(plan,noise,wx,wz)
			var grade := absf(h-_terrain_height(plan,noise,wx+2,wz))+absf(h-_terrain_height(plan,noise,wx,wz+2))
			grid.set_point_weight_scale(Vector2i(x,z),1.0+grade*4.0)
			for parcel in plan.parcels:
				if _rect_distance(wx,wz,parcel.pad.xz)<2.0: grid.set_point_solid(Vector2i(x,z))
	var hub := Vector2i(34,30)
	grid.set_point_solid(hub,false)
	var hub_height := _snap(_terrain_height(plan,noise,ox+hub.x,oz+hub.y))
	var result: Array = []
	for port in plan.road_ports:
		var p: Dictionary = port.position
		var start := Vector2i(roundi(p.x-ox),roundi(p.z-oz))
		grid.set_point_solid(start,false)
		var route: Array[Vector2i] = grid.get_id_path(start,hub)
		if route.is_empty():
			plan["road_error"]={"port":port.id,"from":str(start),"to":str(hub)}
			return []
		var points: Array = []
		for i in route.size():
			# Constant endpoint collar across both sides; gentle linear grade
			# between port and common hub prevents contradictory junction levels.
			var t := clampf(float(i-1)/maxf(route.size()-3,1),0,1)
			points.append(_v(ox+route[i].x,lerpf(float(p.y),hub_height,t),oz+route[i].y))
		var main_path:Dictionary={"id":plan.region_id+":"+port.direction,"points":points,"width":(2.5 if port.direction in ["north","south"] else 1.5) if village_contours else 4.0,"material":4}
		if village_contours:main_path.shoulder=0.75
		result.append(main_path)
	# Link each real doorway to the closest existing road. The pad/yard itself
	# is level; road grade then interpolates toward that actual road point.
	for parcel in plan.parcels:
		for entrance in parcel.entrance_ports:
			var from: Dictionary = entrance.position
			var nearest := {};var best := INF
			for path in result:
				if not path.id.begins_with(plan.region_id+":"): continue
				for point in path.points:
					var distance := Vector2(from.x-point.x,from.z-point.z).length()
					if distance<best: best=distance;nearest=point
			var gate := from.duplicate()
			match entrance.direction:
				"north": gate.z=parcel.pad.xz[1]-2.5
				"south": gate.z=parcel.pad.xz[3]+2.5
				"west": gate.x=parcel.pad.xz[0]-2.5
				"east": gate.x=parcel.pad.xz[2]+2.5
			var start := Vector2i(clampi(roundi(gate.x-ox),1,63),clampi(roundi(gate.z-oz),1,63))
			var target := Vector2i(roundi(nearest.x-ox),roundi(nearest.z-oz))
			grid.set_point_solid(start,false);grid.set_point_solid(target,false)
			var route := grid.get_id_path(start,target)
			if route.is_empty():
				plan["road_error"]={"entrance":parcel.id+":"+entrance.id,"from":str(start),"to":str(target),"pad":parcel.pad.xz}
				return []
			var points: Array=[from.duplicate()]
			for i in route.size():
				var t := clampf(float(i-1)/maxf(route.size()-2,1),0,1)
				points.append(_v(ox+route[i].x,lerpf(float(from.y),float(nearest.y),t),oz+route[i].y))
			var access_path:Dictionary={"id":"access:"+parcel.id+":"+entrance.id,"points":points,"width":1.5 if village_contours else 2.0,"material":4}
			if village_contours:access_path.shoulder=0.75
			result.append(access_path)
	# Every centreline uses the ONE grade field, including at crossings/access
	# joins. The sampler uses this same continuous field across the whole width.
	for path in result:
		for point in path.points: point.y=_snap(_road_grade(plan,noise,point.x,point.z))
	return result

static func _road_index(plan: Dictionary) -> Dictionary:
	var index := {}
	for path in plan.paths:
		for i in path.points.size()-1:
			var a: Dictionary=path.points[i];var b: Dictionary=path.points[i+1]
			var half := float(path.width)*0.5
			var segment := {"a":a,"b":b,"half":half,"shoulder":float(path.get("shoulder",1.5))}
			for z in range(floori((minf(a.z,b.z)-half-1.5)/8),floori((maxf(a.z,b.z)+half+1.5)/8)+1):
				for x in range(floori((minf(a.x,b.x)-half-1.5)/8),floori((maxf(a.x,b.x)+half+1.5)/8)+1):
					var key := Vector2i(x,z)
					if not index.has(key): index[key]=[]
					index[key].append(segment)
	return index

static func _sample(plan: Dictionary,noise: FastNoiseLite,x: float,z: float,resources: bool=true,road_index: Dictionary={}) -> Dictionary:
	var height := _terrain_height(plan,noise,x,z)
	var material := 1
	for land in plan.landforms:
		if (Site.material_contains(noise,land,x,z) if plan.height.get("grade_model","")==Site.MODEL else _rect_distance(x,z,land.xz)==0):material=int(land.material)
	for parcel in plan.parcels:
		if _rect_distance(x,z,parcel.pad.xz)==0: material=6
	var best := INF;var strength := 0.0
	var index := _road_index(plan) if road_index.is_empty() else road_index
	for segment in index.get(Vector2i(floori(x/8),floori(z/8)),[]):
		var a: Dictionary=segment.a;var b: Dictionary=segment.b
		var distance := _distance(x,z,a,b)
		var half := float(segment.half)
		var shoulder:float=float(segment.get("shoulder",1.5))
		if distance.x<half+shoulder:
			var relative := distance.x/maxf(half,0.1)
			if relative<best:
				best=relative
				strength=1.0-smoothstep(half,half+shoulder,distance.x)
	if strength>0:
		# Stateless noise/grade is needed only where a real road contributes.
		# Preserve ordered distance selection and every sampled output exactly.
		var road_height:float=_road_grade(plan,noise,x,z)
		height=lerpf(height,road_height,strength)
		if best<=1.0: material=4
	# Pads take precedence over an access/path fringe, never sag a foundation.
	for parcel in plan.parcels:
		if _rect_distance(x,z,parcel.pad.xz)==0: height=float(parcel.pad.height)
	if resources and plan.height.get("grade_model","") not in [Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]:
		for site in plan.resource_sites:
			var d := Vector2(x-site.position.x,z-site.position.z).length()
			if d<2.1:
				height=lerpf(height,float(site.position.y),1.0-smoothstep(1.5,2.1,d))
	# Rock outcrops are actual stone cells, not a decorative fake resource.
	if material==1 and height>3.0 and noise.get_noise_2d(x+811,z-307)>0.18: material=3
	return {"height":_snap(height),"material":material}

static func _numbers(value: Variant,size: int) -> bool:
	return value is Array and value.size()==size and value.all(func(v: Variant)->bool:return (v is int or v is float) and is_finite(float(v)))

static func _local_rect(value: Variant) -> bool:
	return _numbers(value,4) and value[0]<value[2] and value[1]<value[3] and value[0]>=-4 and value[1]>=-4 and value[2]<=24 and value[3]<=24

static func _profiles_error(profiles: Array) -> String:
	var seen := {}
	for p in profiles:
		if not p is Dictionary or not Data.json_value(p): return "INVALID_GENERATION_PROFILE"
		if not Data.valid_id(p.get("id")) or seen.has(p.id): return "INVALID_PROFILE_ID"
		seen[p.id]=true
		var f: Variant = p.get("footprint")
		if not f is Dictionary or not f.get("min") is Dictionary or not f.get("max") is Dictionary: return "INVALID_PROFILE_FOOTPRINT"
		if not f.min.has_all(["x","z"]) or not f.max.has_all(["x","z"]): return "INVALID_PROFILE_FOOTPRINT"
		if not [f.min.x,f.min.z,f.max.x,f.max.z].all(func(v: Variant)->bool:return (v is int or v is float) and is_finite(float(v))): return "INVALID_PROFILE_FOOTPRINT"
		if f.max.x<=f.min.x or f.max.z<=f.min.z or f.max.x-f.min.x>20 or f.max.z-f.min.z>20: return "PROFILE_EXCEEDS_SITE"
		if not p.get("allowed_quarter_turns",[0]) is Array or not p.get("foundation",{}) is Dictionary: return "INVALID_PROFILE_FOUNDATION"
		if not p.get("allowed_quarter_turns",[0]).any(func(turn: Variant)->bool:return Data.integer(turn) and turn==0) or p.get("foundation",{}).get("top_offset",0)!=0: return "UNSUPPORTED_PROFILE_FOUNDATION"
		for name in ["entrance_ports","use_reservations","npc_anchors"]:
			if not p.get(name,[]) is Array:return "INVALID_PROFILE_"+name.to_upper()
		if not p.get("foundation",{}).get("pad_rectangles",[]) is Array:return "INVALID_PROFILE_FOUNDATION"
		for rect in p.get("foundation",{}).get("pad_rectangles",[]):
			if not _local_rect(rect):return "INVALID_PROFILE_FOUNDATION"
		for port in p.get("entrance_ports",[]):
			if not port is Dictionary or not _numbers(port.get("position"),3) or not Data.valid_id(port.get("id")): return "INVALID_PROFILE_PORT"
			if port.position[1]!=0 or port.position[0]<-4 or port.position[2]<-4 or port.position[0]>24 or port.position[2]>24:return "UNSUPPORTED_PROFILE_PORT"
		for reservation in p.get("use_reservations",[]):
			if not reservation is Dictionary or not _local_rect(reservation.get("rect")) or not Data.valid_id(reservation.get("id")): return "INVALID_PROFILE_RESERVATION"
			if not _numbers([reservation.get("min_y"),reservation.get("max_y")],2) or reservation.min_y<0 or reservation.max_y<=reservation.min_y:return "INVALID_PROFILE_RESERVATION"
		for anchor in p.get("npc_anchors",[]):
			if not anchor is Dictionary or not _numbers(anchor.get("position"),3) or not Data.valid_id(anchor.get("id")) or not anchor.get("purpose") is String:return "INVALID_PROFILE_ANCHOR"
	return ""

static func _profile_stamp(profiles: Array) -> String:
	# Only mapgen geometry affects this contract, not B's texture/recipe edits.
	return Contract.stamp(profiles)

static func _landforms(coord:Vector2i,noise:FastNoiseLite)->Array:
	# Same original three authored purposes/values/order. The v5 planner also
	# reads neighbouring controls without generating those regions or entities.
	var ox:float=coord.x*SIZE;var oz:float=coord.y*SIZE;var id:String=region_id(coord)
	var field_y:float=_snap(_base(noise,ox+19,oz+53)-0.5)
	return [
		{"id":id+":field","use":"field","xz":[ox+10,oz+48,ox+27,oz+58],"height":field_y,"blend":3.0,"material":2},
		{"id":id+":bank","use":"field-bank","xz":[ox+8,oz+47,ox+10,oz+59],"height":field_y+0.5,"blend":2.0,"material":1},
		{"id":id+":ditch","use":"dry-ditch","xz":[ox+39,oz+42,ox+42,oz+58],"height":_snap(_base(noise,ox+40,oz+50)-1.0),"blend":3.0,"material":3}]

static func plan_region(seed: int,coord: Vector2i,profiles: Array=[],selection: Dictionary={}) -> Dictionary:
	if selection.is_empty():profiles=Contract.baseline(profiles)
	if absi(coord.x)>COORD_LIMIT or absi(coord.y)>COORD_LIMIT: return Data.reject("GENERATION_COORD_LIMIT")
	var error := _profiles_error(profiles)
	if error: return Data.reject(error)
	var noise := _noise(seed)
	var id := region_id(coord)
	var ox := float(coord.x*SIZE);var oz := float(coord.y*SIZE)
	var plan := {"schema":SCHEMA,"generator_version":VERSION,"seed":seed,"region_id":id,"region_coord":{"x":coord.x,"z":coord.y},"height":{"source":"authoritative voxels after first commit","cell_size":0.5,"noise":"Godot FastNoiseLite OpenSimplex2S FBM2","frequency":0.018},"road_ports":[],"paths":[],"parcels":_parcels(seed,coord,noise,profiles,selection),"grade_controls":[],"landforms":[],"resource_sites":[],"npc_anchors":[],"anchors":{}}
	plan.profile_contract_sha256=_profile_stamp(profiles)
	if not profiles.is_empty() and plan.parcels.any(func(p: Dictionary)->bool:return not p.profile_resolved): return Data.reject("MISSING_GENERATION_PROFILE")
	for parcel in plan.parcels:
		var rect: Array=parcel.pad.xz
		if rect[0]<ox+1 or rect[1]<oz+1 or rect[2]>ox+SIZE-1 or rect[3]>oz+SIZE-1:return Data.reject("PROFILE_EXCEEDS_SITE",parcel.id)
		for other in plan.parcels:
			if other.id==parcel.id:continue
			var b: Array=other.pad.xz
			if rect[0]<b[2] and rect[2]>b[0] and rect[1]<b[3] and rect[3]>b[1]:return Data.reject("OVERLAPPING_PADS",parcel.id+" / "+other.id)
	# The finite settlement's grading constraints are world-coordinate controls,
	# also used in the adjacent region. They create no building/entity authority.
	for settlement_coord in [Vector2i.ZERO,Vector2i(0,-1)]:
		for parcel in _parcels(seed,settlement_coord,noise,profiles,selection): plan.grade_controls.append(parcel.pad.duplicate(true))
	for direction in ["north","south","west","east"]:
		var port := _port(seed,coord,direction,noise)
		port.position.y=_snap(_road_grade(plan,noise,port.position.x,port.position.z))
		plan.road_ports.append(port)
	plan.landforms.append_array(_landforms(coord,noise))
	plan.paths=_roads(plan,noise)
	if plan.paths.is_empty(): return Data.reject("NO_SETTLEMENT_ROAD",JSON.stringify(plan.get("road_error",{})))
	for parcel in plan.parcels:
		plan.anchors[parcel.site_id]=parcel.entrance_ports[0].position.duplicate()
		plan.npc_anchors.append({"id":id+":"+parcel.site_id+":activity","purpose":parcel.site_id,"position":parcel.entrance_ports[0].position.duplicate(),"parcel_id":parcel.id})
		for anchor in parcel.npc_anchors:
			var a: Dictionary=anchor.duplicate(true);a.id=parcel.id+":"+a.id;a.parcel_id=parcel.id
			plan.npc_anchors.append(a)
	var arrival: Dictionary=plan.paths[1].points[-4].duplicate()
	arrival.y=_sample(plan,noise,arrival.x,arrival.z,false).height
	plan.anchors.arrival=arrival
	# Clustered real trees on forest/field edges. Hash only this coordinate;
	# successful harvesting is saved on these IDs, never derived on revisit.
	for z in range(8,59,8):
		for x in [46,52,58]:
			var hash := _hash(seed,"tree:%d:%d:%d:%d"%[coord.x,coord.y,x,z])
			if hash%5==0: continue
			var wx: float = ox+x+float(hash%3)*0.5;var wz: float = oz+z+float((hash/3)%3)*0.5
			var near := false
			for parcel in plan.parcels:
				if _rect_distance(wx,wz,parcel.pad.xz)<3: near=true
			for path in plan.paths:
				for i in path.points.size()-1:
					if _distance(wx,wz,path.points[i],path.points[i+1]).x<float(path.width)*0.5+3: near=true
			if near: continue
			var sample := _sample(plan,noise,wx,wz,false)
			if sample.material!=1: continue
			var tree_id := "rural:v2:%d:%d:%d:tree:%d:%d"%[seed,coord.x,coord.y,x,z]
			plan.resource_sites.append({"id":tree_id,"kind":"tree","position":_v(wx,sample.height,wz),"output_id":tree_id+":drops","use":"forest-edge","drops_position":_v(wx+1,sample.height,wz)})
	return {"ok":true,"plan":plan}

static func planned_surface(plan: Dictionary,x: float,z: float) -> Dictionary:
	# Planning only. Gameplay must read world.surface_height/cell_at, including edits.
	return _sample(plan,_noise(int(plan.seed)),x,z)

static func _tree_entities(site: Dictionary,region: String) -> Array:
	var p: Dictionary=site.position
	var tree := {"id":site.id,"kind":"tree","regionId":region,"position":p.duplicate(),"bounds":{"min":_v(p.x-0.35,p.y,p.z-0.35),"max":_v(p.x+0.35,p.y+4,p.z+0.35)},"revision":0,"blocksTerrain":true,"supportBounds":[{"min":_v(p.x-0.35,p.y-0.5,p.z-0.35),"max":_v(p.x+0.35,p.y,p.z+0.35)}],"data":{"solid":true,"opaque":true,"outputId":site.output_id,"harvest":{"phase":"standing","work":0,"seconds":24,"toolWear":6,"yield":{"log":3}}}}
	if site.has("appearance"):
		tree.data.appearance=site.appearance.duplicate(true)
		tree.bounds.max.y=p.y+float(site.appearance.height)
	var d: Dictionary=site.drops_position
	var drops := {"id":site.output_id,"kind":"container","regionId":region,"position":d.duplicate(),"bounds":{"min":_v(d.x-0.15,d.y,d.z-0.15),"max":_v(d.x+0.15,d.y+0.2,d.z+0.15)},"revision":0,"blocksTerrain":false,"data":{"dropped":true,"inventoryOwner":"runtime","owner":null,"searched":true,"sourceId":site.id}}
	return [tree,drops]

static func draft_region(seed: int,coord: Vector2i,profiles: Array=[],selection: Dictionary={}) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := plan_region(seed,coord,profiles,selection)
	if not result.ok: return result
	return draft_plan(result.plan,started)

static func draft_plan(plan: Dictionary,started: int=0) -> Dictionary:
	# Shared raster/codec contract for explicit versions. Legacy plan_region()
	# retains its exact rural-2 output; new mapgen never rewrites old cells.
	if started==0:started=Time.get_ticks_usec()
	var coord:=Vector2i(plan.region_coord.x,plan.region_coord.z)
	var version:String=plan.generator_version
	var noise := _noise(int(plan.seed))
	var road_index := _road_index(plan)
	# Sample once per XZ column, not per voxel. This temporary raster is discarded.
	var heights := PackedInt32Array();heights.resize(128*128)
	var tops := PackedInt32Array();tops.resize(128*128)
	var min_h := INF;var max_h := -INF
	for z in 128:
		for x in 128:
			var sample := _sample(plan,noise,coord.x*SIZE+(x+0.5)*0.5,coord.y*SIZE+(z+0.5)*0.5,true,road_index)
			heights[x+128*z]=roundi(sample.height*2)
			tops[x+128*z]=sample.material
			min_h=minf(min_h,sample.height);max_h=maxf(max_h,sample.height)
	if plan.height.get("grade_model","") in ["local-apron-v2","local-apron-v3","village-contours-v4",Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL] and plan.get("anchors",{}).has("arrival"):
		# Planning coordinates lie on cell edges. Resolve the new-world spawn
		# against the FINAL authoritative raster, including all nine 0.26m body
		# probes, rather than the continuous centre sample. Old saves/models keep
		# their original anchors byte-for-byte; loading never re-runs this path.
		var arrival:Dictionary=plan.anchors.arrival
		var support:float=-INF;var minimum:float=INF
		for dx:float in [-0.26,0.0,0.26]:
			for dz:float in [-0.26,0.0,0.26]:
				var x:int=floori((float(arrival.x)+dx-coord.x*SIZE)*2)
				var z:int=floori((float(arrival.z)+dz-coord.y*SIZE)*2)
				if x<0 or x>=128 or z<0 or z>=128:return Data.reject("INVALID_ARRIVAL_SUPPORT")
				var y:float=heights[x+128*z]*0.5
				support=maxf(support,y);minimum=minf(minimum,y)
		if support-minimum>0.5:return Data.reject("INVALID_ARRIVAL_SUPPORT","Body spans more than one real half-metre step")
		arrival.y=support
	if plan.get("surface_style","")=="rural-quality-v1":
		plan.field_surfaces=preload("res://scripts/environment/field_surfaces.gd").layout(plan,heights,tops)
	var raster_us := Time.get_ticks_usec()-started
	var chunks := {}
	for cz in 8:
		for cx in 8:
			for cy in range(-1,3):
				var cells := PackedInt32Array();cells.resize(4096)
				for z in 16:
					for x in 16:
						var index := cx*16+x+128*(cz*16+z)
						var top := heights[index]-1
						for y in range(maxi(-8,cy*16),mini(top+1,cy*16+16)):
							cells[x+16*(z+16*posmod(y,16))]=5 if y==-8 else int(tops[index]) if y==top else 3 if y<top-3 else 2
				var c := Vector3i(coord.x*8+cx,cy,coord.y*8+cz)
				var key := Data.key(c)
				chunks[key]={"key":key,"coord":{"x":c.x,"y":c.y,"z":c.z},"cells":cells,"revision":0,"resident":true,"generated":true,"generatorVersion":version}
	var lo := _v(coord.x*SIZE,-4,coord.y*SIZE)
	var hi := _v((coord.x+1)*SIZE,20,(coord.y+1)*SIZE)
	var exits: Array=[]
	for port in plan.road_ports:
		var p: Dictionary=port.position.duplicate()
		var delta: Vector2={"north":Vector2(0,0.5),"south":Vector2(0,-0.5),"west":Vector2(0.5,0),"east":Vector2(-0.5,0)}[port.direction]
		p.x+=delta.x;p.z+=delta.y
		exits.append({"id":port.id,"toRegionId":port.to_region_id,"position":p,"width":port.width,"direction":port.direction})
	var region := {"id":plan.region_id,"kind":"rural","bounds":{"min":lo,"max":hi},"generated":true,"exits":exits,"editAreas":[{"id":plan.region_id+":land","bounds":{"min":lo.duplicate(),"max":hi.duplicate()},"minY":-4,"maxY":20,"operations":["dig","fill","level"]}],"data":{"generationVersion":version,"regionCoord":plan.region_coord.duplicate(),"heightMin":min_h,"heightMax":max_h}}
	var entities := {}
	for site in plan.resource_sites:
		for entity in _tree_entities(site,plan.region_id): entities[entity.id]=entity
	return {"ok":true,"plan":plan,"region":region,"chunks":chunks,"entities":entities,"cost":{"plan_and_raster_ms":raster_us/1000.0,"total_ms":(Time.get_ticks_usec()-started)/1000.0,"chunks":chunks.size(),"cells":chunks.size()*4096,"temporary_column_bytes":heights.size()*8,"height_min":min_h,"height_max":max_h}}

static func generate(seed: int=713,profiles: Array=[]) -> Dictionary:
	profiles=Contract.baseline(profiles)
	var world := {"schemaVersion":1,"worldId":"rural:v2:"+str(seed),"seed":seed,"generatorVersion":VERSION,"revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{},"receipts":{}}
	for coord in [Vector2i.ZERO,Vector2i(0,-1)]:
		var draft := draft_region(seed,coord,profiles)
		if not draft.ok: return draft
		world.regions[draft.region.id]=draft.region
		world.chunks.merge(draft.chunks);world.entities.merge(draft.entities)
		world.extensions["generation:"+draft.region.id]=draft.plan
	world.extensions["generation:rural2"]={"schema":"afterglow-rural2-configuration-v1","generator_version":VERSION,"profile_contract_sha256":_profile_stamp(profiles),"max_regions":MAX_REGIONS,"coord_limit":COORD_LIMIT}
	return world

static func prepare_region(world: RefCounted,coord: Vector2i,profiles: Array=[],expected_revision: int=-1) -> Dictionary:
	var identity: Dictionary=world.identity()
	if identity.generatorVersion!=VERSION: return Data.reject("GENERATOR_MISMATCH","Old/explored worlds are never regenerated")
	if expected_revision>=0 and expected_revision!=world.get_revision(): return Data.reject("STALE_REVISION")
	var id := region_id(coord)
	var existing: Dictionary=world.region(id)
	if not existing.is_empty():
		return {"ok":true,"already_generated":true,"plan":world.extension("generation:"+id),"world_changes":[],"initial_stocks":[]}
	var configuration: Variant=world.extension("generation:rural2")
	var input:=Contract.resolve(configuration,profiles)
	if not input.ok:return input
	profiles=input.profiles
	var profile_error := _profiles_error(profiles)
	if profile_error: return Data.reject(profile_error)
	if world.regions().size()>=MAX_REGIONS or world.chunk_keys().size()+256>8192: return Data.reject("GENERATION_CAPACITY")
	var draft := draft_region(int(identity.seed),coord,profiles,{"version":1})
	if not draft.ok: return draft
	return prepare_draft(world,draft,world.get_revision())

static func prepare_draft(world: RefCounted,draft: Dictionary,expected_revision: int,version: String=VERSION) -> Dictionary:
	# Main-thread handoff after A runs draft_region(seed,coord,profiles) on a
	# worker. The worker never touches a mutable live WorldState or scene node.
	if expected_revision!=world.get_revision(): return Data.reject("STALE_REVISION")
	var identity: Dictionary=world.identity()
	if identity.generatorVersion!=version or version not in [VERSION,"rural-3"]: return Data.reject("GENERATOR_MISMATCH")
	if not draft.get("ok",false) or not draft.get("plan") is Dictionary or not draft.get("region") is Dictionary or not draft.get("chunks") is Dictionary or not draft.get("entities") is Dictionary: return Data.reject("INVALID_REGION_DRAFT")
	var plan: Dictionary=draft.plan
	if plan.get("schema")!=SCHEMA or plan.get("generator_version")!=version or plan.get("seed")!=identity.seed or not plan.get("region_coord") is Dictionary: return Data.reject("INVALID_REGION_DRAFT")
	var point: Dictionary=plan.region_coord
	if not Data.integer(point.get("x")) or not Data.integer(point.get("z")): return Data.reject("INVALID_REGION_DRAFT")
	var coord := Vector2i(point.x,point.z)
	var id := region_id(coord)
	if absi(coord.x)>COORD_LIMIT or absi(coord.y)>COORD_LIMIT or plan.get("region_id")!=id or draft.region.get("id")!=id or draft.chunks.size()!=256: return Data.reject("INVALID_REGION_DRAFT")
	if not world.region(id).is_empty(): return {"ok":true,"already_generated":true,"plan":world.extension("generation:"+id),"world_changes":[],"initial_stocks":[]}
	# This generator's persisted lattice is explicitly 64m / 128 columns /
	# 16-cell chunks and four Y layers. Do not interpret a valid foreign config
	# or worker's displaced/missing chunk as a different region allocation.
	if not Data.json_equal(world.config(),Data.DEFAULT_CONFIG):return Data.reject("GENERATION_CONFIG_MISMATCH")
	var expected_bounds:Dictionary={"min":_v(coord.x*SIZE,-4,coord.y*SIZE),"max":_v((coord.x+1)*SIZE,20,(coord.y+1)*SIZE)}
	if not Data.json_equal(draft.region.get("bounds"),expected_bounds):return Data.reject("INVALID_REGION_DRAFT","coordinate bounds")
	for z in 8:
		for x in 8:
			for y in range(-1,3):
				if not draft.chunks.has(Data.key(Vector3i(coord.x*8+x,y,coord.y*8+z))):return Data.reject("INVALID_REGION_DRAFT","chunk lattice")
	if world.regions().size()>=MAX_REGIONS or world.chunk_keys().size()+256>8192: return Data.reject("GENERATION_CAPACITY")
	var configuration: Variant=world.extension("generation:rural2")
	if not configuration is Dictionary or configuration.get("profile_contract_sha256")!=plan.get("profile_contract_sha256"): return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
	if not Contract.plan_matches(configuration,plan):return Data.reject("GENERATION_POLICY_MISMATCH")
	if version=="rural-3" and (configuration.get("generator_version")!=version or configuration.get("dressing_contract_sha256")!=plan.get("dressing_contract_sha256")):return Data.reject("DRESSING_PROFILE_VERSION_MISMATCH")
	var changes: Array=[{"op":"region.put","id":id,"before_exists":false,"before":null,"after":draft.region}]
	for key in draft.chunks:
		if not world.chunk(key).is_empty(): return Data.reject("GENERATION_CHUNK_OCCUPIED",key)
		changes.append({"op":"chunk.put","id":key,"before_exists":false,"before":null,"after":draft.chunks[key]})
	for key in draft.entities:
		changes.append({"op":"entity.put","id":key,"before_exists":false,"before":null,"after":draft.entities[key]})
	changes.append({"op":"extension.set","id":"generation:"+id,"before_exists":false,"before":null,"after":draft.plan})
	var stocks: Array=[]
	for site in draft.plan.resource_sites:
		var p: Dictionary=site.drops_position
		stocks.append({"id":site.output_id,"items":{},"owner":null,"searched":true,"location":{"x":p.x,"y":p.y,"z":p.z,"regionId":id,"buildingId":null,"storeyId":null}})
	return {"ok":true,"already_generated":false,"expected_world_revision":world.get_revision(),"plan":draft.plan,"world_changes":changes,"initial_stocks":stocks,"cost":draft.cost}
