extends RefCounted
## C places B's read-only footprint contracts into the single persisted plan.
## No scene/stock/interaction or implicit upgrade of an explored plan.
const Generator=preload("res://scripts/world/settlement_generator.gd")
const PROFILES="res://data/buildings/dressing_profiles.json"
const HISTORY="res://data/world/dressing-history-v1.json"

static func profiles()->Array:
	var source:Variant=JSON.parse_string(FileAccess.get_file_as_string(PROFILES))
	return source.get("profiles",[]).duplicate(true) if source is Dictionary else []

static func contract_sha256(input:Variant=null)->String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(profiles() if input==null else input)),"",true,true).sha256_text()

static func resolve(expected:String,catalog:Variant=null)->Dictionary:
	if catalog!=null and not catalog is Array:return {"ok":false,"code":"DRESSING_PROFILE_VERSION_MISMATCH"}
	var current:Array=profiles() if catalog==null else catalog.duplicate(true)
	if contract_sha256(current)==expected:return {"ok":true,"profiles":current,"contract_sha256":expected}
	# Only an exact old input is accepted. New IDs do not alter old selection;
	# an existing ID with ANY changed value still requires explicit migration.
	# Never drop a hash or silently keep an old footprint with a new B body.
	var candidates:Array=[current]
	var history:Variant=JSON.parse_string(FileAccess.get_file_as_string(HISTORY))
	if history is Dictionary:
		for entry:Dictionary in history.get("catalogues",[]):candidates.append(entry.profiles)
	for candidate:Array in candidates:
		if contract_sha256(candidate)!=expected:continue
		var exact:bool=candidate.all(func(old:Dictionary)->bool:
			var matches:Array=current.filter(func(p:Variant)->bool:return p is Dictionary and p.get("id")==old.id)
			return matches.size()==1 and preload("res://scripts/world/world_data.gd").json_equal(old,matches[0]))
		if exact:return {"ok":true,"profiles":candidate.duplicate(true),"contract_sha256":expected}
	return {"ok":false,"code":"DRESSING_PROFILE_VERSION_MISMATCH","reason":"Preserve used definitions or migrate explicitly; added unused IDs alone are allowed"}

static func _rect(profile:Dictionary,x:float,z:float,turn:int)->Array:
	var f:Dictionary=profile.footprint
	var a:=Vector2(f.min.x,f.min.z);var b:=Vector2(f.max.x,f.max.z)
	for i in turn:a=Vector2(-a.y,a.x);b=Vector2(-b.y,b.x)
	return [x+minf(a.x,b.x),z+minf(a.y,b.y),x+maxf(a.x,b.x),z+maxf(a.y,b.y)]

static func _overlap(a:Array,b:Array,margin:float=0.0)->bool:
	return a[0]<b[2]+margin and a[2]>b[0]-margin and a[1]<b[3]+margin and a[3]>b[1]-margin

static func _supported(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,rect:Array,height:float,tolerance:float)->bool:
	var xs:Array=[rect[0]+0.001,rect[2]-0.001];var zs:Array=[rect[1]+0.001,rect[3]-0.001]
	for x in range(floori(rect[0]*2),ceili(rect[2]*2)):xs.append((x+0.5)*0.5)
	for z in range(floori(rect[1]*2),ceili(rect[3]*2)):zs.append((z+0.5)*0.5)
	for x:float in xs:
		for z:float in zs:
			if x<rect[0] or x>=rect[2] or z<rect[1] or z>=rect[3]:continue
			# Match the raster's column CENTRE, exactly as WorldView.surface_height.
			# A continuous corner sample can differ by one quantized half-metre.
			var cx:float=(floori(x*2)+0.5)*0.5;var cz:float=(floori(z*2)+0.5)*0.5
			if absf(float(Generator._sample(plan,noise,cx,cz,true,roads).height)-height)>tolerance:return false
	return true

static func plan_slots(plan:Dictionary,profile_input:Variant=null)->Dictionary:
	var indexed:Dictionary={}
	var input:Array=profiles() if profile_input==null else profile_input
	for profile:Dictionary in input:indexed[profile.id]=profile
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	var requests:Array=[
		["well_covered",31.25,45.25,"meeting-point"],
		["water_barrel",3.25,37.25,"homestead-wall"],
		["haystack",13.25,60.25,"field-edge"],
		["village_sign",36.25,5.25,"entry-wayfinding"],
		["stored_water_tank",16.25,13.25,"utility-edge"],
		["abandoned_bicycle",27.25,45.25,"home-approach"],
		["rural_fence",7.25,54.25,"field-boundary"],
		["abandoned_scooter",36.25,31.25,"lane-side"]]
	if plan.region_id=="RH-VILLAGE":
		requests=[["well_covered",34.25,34.25,"meeting-point"],["water_barrel",22.25,40.25,"shop-side"],["haystack",13.25,60.25,"field-edge"],["village_sign",36.25,60.25,"village-entry"],["stored_water_tank",39.25,21.25,"repair-utility"],["abandoned_bicycle",24.25,34.25,"shop-approach"],["rural_fence",7.25,54.25,"field-boundary"],["abandoned_scooter",38.25,28.25,"repair-lane"]]
	# Exact released B sedan contract. Append after original slots, new plans
	# only: prepare_region returns existing saved plans before reaching here.
	if indexed.has("abandoned_car"):
		requests.append(["abandoned_car",43.25 if plan.region_id=="RH-VILLAGE" else 40.25,31.25 if plan.region_id=="RH-VILLAGE" else 14.25,"abandoned-lane-edge"])
	var noise:=Generator._noise(int(plan.seed));var roads:=Generator._road_index(plan)
	var slots:Array=[];var occupied:Array=[];var skipped:Array=[]
	for request:Array in requests:
		if not indexed.has(request[0]):skipped.append({"profile_id":request[0],"reason":"profile-not-delivered"});continue
		var profile:Dictionary=indexed[request[0]];var chosen:Dictionary={}
		var phase:int=(str(plan.seed)+plan.region_id+str(request[0])).sha256_text().substr(0,8).hex_to_int()%4
		# Finite deterministic local search, closest usable footprint to its real
		# purpose. Never level terrain to squeeze in a scenery prop.
		for radius in 8:
			if not chosen.is_empty():break
			for dz in range(-radius,radius+1):
				if not chosen.is_empty():break
				for dx in range(-radius,radius+1):
					if maxi(absi(dx),absi(dz))!=radius:continue
					var x:float=ox+request[1]+dx;var z:float=oz+request[2]+dz
					for step in 2:
						var turn:int=(phase+step)%4;var rect:=_rect(profile,x,z,turn)
						if rect[0]<ox+1 or rect[2]>ox+63 or rect[1]<oz+1 or rect[3]>oz+63:continue
						var center:=Vector2((rect[0]+rect[2])/2,(rect[1]+rect[3])/2)
						var bound_radius:=Vector2(rect[2]-rect[0],rect[3]-rect[1]).length()/2
						var conflict:=false
						for path:Dictionary in plan.paths:
							for i in path.points.size()-1:
								if Generator._distance(center.x,center.y,path.points[i],path.points[i+1]).x<bound_radius+float(path.width)*0.5+float(profile.clearance.road):conflict=true;break
							if conflict:break
						if conflict:continue
						for parcel:Dictionary in plan.parcels:
							if _overlap(rect,parcel.pad.xz,0.25):conflict=true
							for port:Dictionary in parcel.entrance_ports:
								if center.distance_to(Vector2(port.position.x,port.position.z))<bound_radius+float(profile.clearance.entrance):conflict=true
						if conflict:continue
						for other:Array in occupied:
							if _overlap(rect,other,0.8):conflict=true
						for site:Dictionary in plan.resource_sites:
							if Generator._rect_distance(site.position.x,site.position.z,rect)<1.4:conflict=true
						if conflict:continue
						var height:float=Generator._sample(plan,noise,(floori(x*2)+0.5)*0.5,(floori(z*2)+0.5)*0.5,true,roads).height
						if not _supported(plan,noise,roads,rect,height,float(profile.terrain_tolerance)):continue
						chosen={"id":plan.region_id+":dressing1:"+str(request[0]),"profile_id":request[0],"position":{"x":x,"y":height,"z":z},"quarter_turn":turn,"state":"aged"}
						occupied.append(rect);break
					if not chosen.is_empty():break
		if chosen.is_empty():skipped.append({"profile_id":request[0],"reason":"no-safe-flat-purpose-neighborhood"})
		else:slots.append(chosen)
	return {"slots":slots,"footprints":occupied,"skipped":skipped,"contract_sha256":contract_sha256(input),"version":1}
