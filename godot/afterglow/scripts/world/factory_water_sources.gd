extends RefCounted
## WT01 saved site descriptor only. B owns the one facility/remaining balance.
## No water stock, entity, runtime, clock or implicit refill is created here.
const Data=preload("res://scripts/world/world_data.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const Landscape=preload("res://scripts/world/factory_landscape.gd")

static func _surface(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,z:float,width:float)->Variant:
	var low:float=INF;var high:float=-INF
	for cz:int in range(floori((z-width/2+0.00001)*2),floori((z+width/2-0.00001)*2)+1):
		for cx:int in range(floori((x-width/2+0.00001)*2),floori((x+width/2-0.00001)*2)+1):
			var sample:Dictionary=Raster._sample(plan,noise,(cx+0.5)*0.5,(cz+0.5)*0.5,false,roads)
			low=minf(low,float(sample.height));high=maxf(high,float(sample.height))
	return high if high==low else null

static func _clear(plan:Dictionary,b:Dictionary)->bool:
	for parcel:Dictionary in plan.parcels:
		var pad:Array=parcel.pad.xz
		if b.min.x<pad[2]+1.0 and b.max.x>pad[0]-1.0 and b.min.z<pad[3]+1.0 and b.max.z>pad[1]-1.0:return false
	for tree:Dictionary in plan.resource_sites:
		# Covers existing maximum root/body radius and the independent use mouth.
		if tree.position.x>b.min.x-1.0 and tree.position.x<b.max.x+1.0 and tree.position.z>b.min.z-1.0 and tree.position.z<b.max.z+1.0:return false
	return true

static func descriptors(plan:Dictionary)->Dictionary:
	if int(plan.get("generation_content_version",1))<6:return {"ok":true,"sources":[]}
	# One finite source in the established starting field. Peripheral regions
	# do not turn exploration into an unlimited chain of identical free tanks.
	if plan.region_id!="RH-HOME":return {"ok":true,"sources":[]}
	var fields:Array=plan.landforms.filter(func(v:Dictionary)->bool:return v.use=="field")
	if fields.size()!=1:return Data.reject("WT01_FIELD_MISSING")
	var r:Array=fields[0].xz
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	# Finite deterministic choices relative to the saved field, not hard-coded
	# world/seed coordinates. Keep crops/ground facts; actual B blocker hides
	# decorative plants covered by the real tank, never a fake resource removal.
	var candidates:Array=[]
	for side:int in [0,1]:
		for step:int in 8:
			var x:float=r[0]+2.0 if side==0 else r[2]-2.0
			var z:float=r[1]+2.0+float(step)
			if z>r[3]-1.5:continue
			candidates.append({"x":x,"z":z,"direction":-1.0 if side==0 else 1.0})
	for at:Dictionary in candidates:
		var x:float=at.x;var z:float=at.z
		var height:Variant=_surface(plan,noise,roads,x,z,1.2)
		var ux:float=x+float(at.direction)*1.2
		var use_height:Variant=_surface(plan,noise,roads,ux,z,0.52)
		if height==null or use_height==null or absf(float(height)-float(use_height))>0.5:continue
		var b:Dictionary={"min":{"x":x-0.6,"y":float(height),"z":z-0.6},"max":{"x":x+0.6,"y":float(height)+1.4,"z":z+0.6}}
		var use_bounds:Dictionary={"min":{"x":ux-0.26,"y":float(use_height),"z":z-0.26},"max":{"x":ux+0.26,"y":float(use_height)+1.8,"z":z+0.26}}
		if not _clear(plan,b) or not _clear(plan,use_bounds):continue
		var on_road:bool=false
		for segment:Dictionary in roads.get(Vector2i(floori(x/8),floori(z/8)),[]):
			if Raster._distance(x,z,segment.a,segment.b).x<float(segment.half)+0.85:on_road=true;break
		if on_road:continue
		return {"ok":true,"sources":[{"id":str(plan.region_id)+":emergency-water","source_key":"r34:%d:%s:emergency-water:wt01-v1"%[int(plan.seed),str(plan.region_id)],"region":plan.region_id,"position":{"x":x,"y":float(height),"z":z},"use_point":{"x":ux,"y":float(use_height),"z":z,"regionId":plan.region_id,"buildingId":null,"storeyId":null},"bounds":b,"kind":"emergency-water-wt01-v1","initial_remaining":48}]}
	return Data.reject("NO_SAFE_WT01_SOURCE_SITE")
