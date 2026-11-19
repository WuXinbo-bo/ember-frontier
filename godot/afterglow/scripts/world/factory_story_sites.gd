extends RefCounted
## Saved spatial facts for S01/S03 only. Registration and all composition/costs
## belong to B; no machine, source receipt or resource is spawned here.
const Data=preload("res://scripts/world/world_data.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const RegionalArt=preload("res://scripts/modules/village_regional_catalog.gd")

static func supply_approach(plan:Dictionary,profiles:Array)->Dictionary:
	if plan.region_id!="RH-VILLAGE":return {"ok":true,"approaches":[],"paths":[]}
	var lots:Array=plan.parcels.filter(func(p:Dictionary)->bool:return p.site_id=="store")
	var expected:=RegionalArt.id_for("r34.module.supply_rear_v3",int(plan.generation_content_version))
	var definitions:Array=profiles.filter(func(p:Dictionary)->bool:return p.id==expected)
	if lots.size()!=1 or definitions.size()!=1 or not definitions[0].has("story_front_point"):return Data.reject("S03_MISSING_PINNED_REAR_SUPPLY_PROFILE")
	var lot:Dictionary=lots[0];var profile:Dictionary=definitions[0]
	var local:Array=profile.story_front_point
	var rotated:Vector3=Geometry.rotate(Vector3(local[0],local[1],local[2]),lot.quarter_turn)
	var front:Dictionary={"x":lot.origin.x+rotated.x,"y":lot.origin.y,"z":lot.origin.z+rotated.z,"regionId":plan.region_id,"buildingId":null,"storeyId":null}
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var f:Dictionary=lot.footprint
	var r:Array=[lot.origin.x+f.min.x-1.25,lot.origin.z+f.min.z-1.25,lot.origin.x+f.max.x+1.25,lot.origin.z+f.max.z+1.25]
	var loop:Array=[]
	for p:Vector2 in [Vector2(r[0],r[1]),Vector2(r[2],r[1]),Vector2(r[2],r[3]),Vector2(r[0],r[3]),Vector2(r[0],r[1])]:loop.append(_point(plan,noise,roads,p.x,p.y))
	var paths:Array=[{"id":str(plan.region_id)+":store-front-rear-loop","purpose":"store-empty-front-to-original-rear-source","width":0.9,"shoulder":0.25,"material":4,"points":loop}]
	var rear:Dictionary={}
	var mouths:Array=[{"id":"empty-front","position":front}]
	for port:Dictionary in lot.entrance_ports:
		mouths.append(port)
		if port.id=="service":rear=port.position.duplicate(true)
	for port:Dictionary in mouths:
		var p:Dictionary=port.position;var nearest:Vector2=Vector2(clampf(p.x,r[0],r[2]),clampf(p.z,r[1],r[3]))
		var distances:Array=[absf(p.x-r[0]),absf(p.x-r[2]),absf(p.z-r[1]),absf(p.z-r[3])]
		var side:int=distances.find(distances.min())
		if side<2:nearest.x=r[0] if side==0 else r[2]
		else:nearest.y=r[1] if side==2 else r[3]
		paths.append({"id":str(plan.region_id)+":store-side:"+str(port.id),"purpose":"physical-store-side-approach","width":0.9,"shoulder":0.25,"material":4,"points":[p.duplicate(true),_point(plan,noise,roads,nearest.x,nearest.y)]})
	if rear.is_empty():return Data.reject("S03_MISSING_REAR_SERVICE")
	return {"ok":true,"approaches":[{"version":1,"kind":"supply-front-rear-s03-v1","id":str(lot.id)+":front-rear","module_id":"r34:generated:"+str(lot.id),"definition_id":profile.id,"geometry_version":profile.geometry_version,"front_point":front,"rear_point":rear,"stock_id":"r34:generated:"+str(lot.id)+":stock:supplies","front_has_stock":false,"side_route_ids":paths.map(func(p:Dictionary)->String:return p.id)}],"paths":paths}

static func _rect_surface(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,r:Array)->Variant:
	var lo:float=INF;var hi:float=-INF
	for z:int in range(floori(r[1]*2),ceili(r[3]*2)):
		for x:int in range(floori(r[0]*2),ceili(r[2]*2)):
			var h:float=float(Raster._sample(plan,noise,(x+0.5)*0.5,(z+0.5)*0.5,false,roads).height)
			lo=minf(lo,h);hi=maxf(hi,h)
	return hi if lo==hi else null

static func _clear(plan:Dictionary,r:Array)->bool:
	for parcel:Dictionary in plan.parcels:
		var p:Array=parcel.pad.xz
		if r[0]<p[2]+0.6 and r[2]>p[0]-0.6 and r[1]<p[3]+0.6 and r[3]>p[1]-0.6:return false
	for tree:Dictionary in plan.resource_sites:
		if tree.position.x>r[0]-1 and tree.position.x<r[2]+1 and tree.position.z>r[1]-1 and tree.position.z<r[3]+1:return false
	return true

static func _point(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,z:float)->Dictionary:
	return {"x":x,"y":float(Raster._sample(plan,noise,x,z,false,roads).height),"z":z}

static func prepare(plan:Dictionary,profiles:Array)->Dictionary:
	if int(plan.get("generation_content_version",1)) in [15,16,17,18,19,20,21]:return _village_frame15(plan,profiles)
	if int(plan.get("generation_content_version",1)) in [13,14]:return {"ok":true,"sites":[],"paths":[]}
	if plan.region_id!="RH-HOME":return {"ok":true,"sites":[],"paths":[]}
	var matching:Array=profiles.filter(func(p:Dictionary)->bool:return p.id=="r34.module.fuel_woodshop")
	if matching.size()!=1:return Data.reject("S01_MISSING_PINNED_MACHINE_PROFILE")
	var profile:Dictionary=matching[0];var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var manual:Array=plan.parcels.filter(func(p:Dictionary)->bool:return p.site_id=="woodwork")
	if manual.size()!=1:return Data.reject("S01_MISSING_MANUAL_SITE")
	var m:Dictionary=manual[0].origin
	# Stay beside the original hand workshop. Existing grade must already fit
	# the full foundation and all five mouths: never flatten land to hide a miss.
	for dz:float in [-2.0,-1.0,0.0,1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,11.0,12.0]:
		for dx:float in [10.5,11.5,12.5,13.5,14.5,15.5]:
			var x:float=m.x+dx;var z:float=m.z+dz
			var f:Dictionary=profile.footprint
			var rect:Array=[x+float(f.min.x),z+float(f.min.z),x+float(f.max.x),z+float(f.max.z)]
			for r:Array in profile.foundation.pad_rectangles:rect=[minf(rect[0],x+r[0]),minf(rect[1],z+r[1]),maxf(rect[2],x+r[2]),maxf(rect[3],z+r[3])]
			var reserve:Array=[rect[0]-1.5,rect[1]-1.5,rect[2]+1.5,rect[3]+1.5]
			if reserve[1]<1.5 or reserve[2]>30.0 or reserve[3]>22.0 or not _clear(plan,reserve):continue
			var y:Variant=_rect_surface(plan,noise,roads,rect)
			if y==null:continue
			var valid:bool=true;var ports:Array=[]
			for port:Dictionary in profile.ports:
				var p:Array=port.position;var radius:float=float(port.clearance.radius)
				var height:Variant=_rect_surface(plan,noise,roads,[x+p[0]-radius,z+p[2]-radius,x+p[0]+radius,z+p[2]+radius])
				if height==null or float(height)!=float(y):valid=false;break
				ports.append({"id":port.id,"purpose":port.purpose,"position":{"x":x+p[0],"y":float(y),"z":z+p[2],"regionId":plan.region_id,"buildingId":null,"storeyId":null},"clearance":port.clearance.duplicate(true)})
			if not valid:continue
			# Reject original roads under the machine; its surrounding lane may
			# meet a road. New paths change surface material only on the same grade.
			for path:Dictionary in plan.paths:
				for i:int in path.points.size()-1:
					if Raster._distance(x,z,path.points[i],path.points[i+1]).x<float(path.width)*0.5+3.2:valid=false
			if not valid:continue
			var loop:Array=[]
			for at:Vector2 in [Vector2(reserve[0],reserve[1]),Vector2(reserve[2],reserve[1]),Vector2(reserve[2],reserve[3]),Vector2(reserve[0],reserve[3]),Vector2(reserve[0],reserve[1])]:loop.append(_point(plan,noise,roads,at.x,at.y))
			var paths:Array=[{"id":str(plan.region_id)+":old-frame-side-loop","purpose":"old-frame-physical-side-route","width":1.0,"shoulder":0.35,"material":4,"points":loop}]
			# Join the loop to the real existing manual approach; not a portal.
			var mouth:Dictionary=manual[0].entrance_ports[0].position
			paths.append({"id":str(plan.region_id)+":old-frame-manual-link","purpose":"manual-to-old-frame-physical-route","width":1.0,"shoulder":0.35,"material":4,"points":[mouth.duplicate(true),_point(plan,noise,roads,reserve[0],mouth.z),loop[0].duplicate(true)]})
			return {"ok":true,"sites":[{"version":1,"kind":"woodshop-restoration-s01-v1","id":str(plan.region_id)+":woodshop-old-frame","source_key":"r34:%d:%s:woodshop-old-frame:s01-v1"%[int(plan.seed),str(plan.region_id)],"region":plan.region_id,"position":{"x":x,"y":float(y),"z":z},"quarter_turn":0,"definition_id":profile.id,"definition_version":profile.version,"geometry_version":profile.geometry_version,"restoration_policy":"s01-frame-v1","foundation_xz":rect,"service_points":ports,"side_route_ids":paths.map(func(p:Dictionary)->String:return p.id)}],"paths":paths}
	return Data.reject("NO_SAFE_S01_OLD_FRAME_SITE")

static func _village_frame15(plan:Dictionary,profiles:Array)->Dictionary:
	if plan.region_id!="RH-HOME":return {"ok":true,"sites":[],"paths":[]}
	var yards:Array=plan.parcels.filter(func(p:Dictionary)->bool:return p.get("site_id")=="workyard")
	var expected:=RegionalArt.id_for("r34.module.fuel_woodshop",int(plan.generation_content_version))
	var matches:Array=profiles.filter(func(p:Dictionary)->bool:return p.id==expected)
	if yards.size()!=1 or matches.size()!=1:return Data.reject("V15_MISSING_HERITAGE_WORKYARD")
	var yard:Dictionary=yards[0];var profile:Dictionary=matches[0]
	var origin:Dictionary=yard.origin;var turn:int=int(yard.quarter_turn)
	var f:Dictionary=profile.footprint
	var local:Array=[float(f.min.x),float(f.min.z),float(f.max.x),float(f.max.z)]
	for r:Array in profile.foundation.pad_rectangles:local=[minf(local[0],r[0]),minf(local[1],r[1]),maxf(local[2],r[2]),maxf(local[3],r[3])]
	var a:Vector3=Geometry.rotate(Vector3(local[0],0,local[1]),turn)
	var b:Vector3=Geometry.rotate(Vector3(local[2],0,local[3]),turn)
	var rect:Array=[float(origin.x)+minf(a.x,b.x),float(origin.z)+minf(a.z,b.z),float(origin.x)+maxf(a.x,b.x),float(origin.z)+maxf(a.z,b.z)]
	var pad:Array=yard.pad.xz
	if rect[0]<pad[0] or rect[1]<pad[1] or rect[2]>pad[2] or rect[3]>pad[3]:return Data.reject("V15_FRAME_EXCEEDS_EXISTING_WORKYARD")
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var y:Variant=_rect_surface(plan,noise,roads,rect)
	if y==null:return Data.reject("V15_FRAME_UNSUPPORTED_EXISTING_GRADE")
	var ports:Array=[];var paths:Array=[]
	for port:Dictionary in profile.ports:
		var p:Array=port.position;var offset:Vector3=Geometry.rotate(Vector3(p[0],p[1],p[2]),turn)
		var at:Dictionary={"x":float(origin.x)+offset.x,"y":float(y),"z":float(origin.z)+offset.z,"regionId":plan.region_id,"buildingId":null,"storeyId":null}
		ports.append({"id":port.id,"purpose":port.purpose,"position":at,"clearance":port.clearance.duplicate(true)})
		var entrances:Array=yard.entrance_ports.filter(func(e:Dictionary)->bool:return e.id==port.id)
		if entrances.size()!=1:return Data.reject("V15_FRAME_MISSING_REAL_APPROACH")
		paths.append({"id":str(plan.region_id)+":heritage-frame15:"+str(port.id),"purpose":"existing-workyard-to-heritage-service-surface","width":.9,"shoulder":.25,"material":4,"points":[entrances[0].position.duplicate(true),at.duplicate(true)]})
	var site:Dictionary={"version":1,"kind":"woodshop-restoration-s01-v1","id":str(plan.region_id)+":woodshop-old-frame","source_key":"r34:%d:%s:woodshop-old-frame:s01-v1"%[int(plan.seed),str(plan.region_id)],"region":plan.region_id,"position":{"x":float(origin.x),"y":float(y),"z":float(origin.z)},"quarter_turn":turn,"definition_id":profile.id,"definition_version":profile.version,"geometry_version":profile.geometry_version,"restoration_policy":"s01-frame-v1","foundation_xz":rect,"service_points":ports,"side_route_ids":paths.map(func(path:Dictionary)->String:return path.id)}
	return {"ok":true,"sites":[site],"paths":paths}
