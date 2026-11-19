extends RefCounted
## Disposable visual fringe from SAVED content3 plans, never generation facts.
## Two existing cutouts, native instancing; no resource/entity/collider/stock.
const Raster=preload("res://scripts/world/settlement_generator.gd")
const LIMIT=384

static func _hash(plan:Dictionary,key:String)->int:
	# JSON may represent the exact integer as a float after load. Canonicalize
	# its numeric identity, never hash "713" and "713.0" as different worlds.
	return (str(int(plan.seed))+":fringe-v1:"+str(plan.region_id)+":"+key).sha256_text().substr(0,8).hex_to_int()

static func clear(plan:Dictionary,roads:Dictionary,x:float,z:float,radius:float)->bool:
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	if x-radius<ox+0.5 or x+radius>ox+63.5 or z-radius<oz+0.5 or z+radius>oz+63.5:return false
	for space:Dictionary in plan.get("spaces",[]):
		if str(space.get("purpose","")).contains("buildable") and Raster._rect_distance(x,z,space.xz)<radius+0.5:return false
	for parcel:Dictionary in plan.parcels:
		if Raster._rect_distance(x,z,parcel.pad.xz)<radius+0.7:return false
	for segment:Dictionary in roads.get(Vector2i(floori(x/8),floori(z/8)),[]):
		if Raster._distance(x,z,segment.a,segment.b).x<float(segment.half)+radius+0.5:return false
	for site:Dictionary in plan.resource_sites:
		if Vector2(x-site.position.x,z-site.position.z).length()<radius+0.85:return false
	return true

static func _append(rows:Array,seen:Dictionary,plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,z:float,tag:String,width:float)->void:
	if rows.size()>=LIMIT:return
	x=snappedf(x,1.0/64.0);z=snappedf(z,1.0/64.0)
	var key:String="%d:%d"%[floori(x*2),floori(z*2)]
	if seen.has(key):return
	var h:int=_hash(plan,tag+":"+key);var scale:float=0.85+float(h%4)*0.05
	if not clear(plan,roads,x,z,width*scale*sqrt(2.0)*0.5):return
	# Original saved grade selects only a candidate. EnvironmentView checks
	# every CURRENT exposed grass/air cell of its full rotated footprint.
	# Changed/cold/covered ground hides it; this cannot resurrect edited soil.
	var surface:Dictionary=Raster._sample(plan,noise,(floori(x*2)+0.5)*0.5,(floori(z*2)+0.5)*0.5,false,roads)
	if surface.material!=1:return
	seen[key]=true
	rows.append({"id":"render:fringe-v1:"+str(plan.region_id)+":"+key,"model":"quality:v02_dry_grass" if h%5==0 else "quality:v01_fresh_grass","position":{"x":x,"y":surface.height,"z":z},"yaw":float((h/7)%16)*TAU/16.0,"scale":scale,"footprint":[width,width],"material":1,"use":"presentation-route-fringe","presentation_only":true,"blocking":false,"harvestable":false})

static func _skirts(rows:Array,seen:Dictionary,plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,limit:int,classify:bool=false)->void:
	var anchors:Array=[]
	if classify:
		# Interleave actual persisted land uses, so the first forest strip cannot
		# consume the whole reserved share before courtyard/contour shrubs.
		var groups:Dictionary={};var longest:int=0
		for patch:Dictionary in plan.get("ecology",{}).get("patches",[]):
			if patch.get("material")!=1 or patch.get("use") in ["abandoned-field","dry-ditch-edge"]:continue
			var use:String=str(patch.use)
			if not groups.has(use):groups[use]=[]
			groups[use].append(patch);longest=maxi(longest,groups[use].size())
		var uses:Array=groups.keys();uses.sort()
		for i:int in longest:
			for use:String in uses:
				if i<groups[use].size():anchors.append(groups[use][i])
	else:anchors=plan.get("ecology",{}).get("patches",[])
	for patch:Dictionary in anchors:
		if patch.get("material")!=1 or patch.get("use") in ["abandoned-field","dry-ditch-edge"]:continue
		for offset:Vector2 in [Vector2(-0.7,-0.4),Vector2(0.6,0.5),Vector2(-0.3,0.8)]:
			if rows.size()>=limit:return
			var before:int=rows.size()
			_append(rows,seen,plan,noise,roads,patch.position.x+offset.x,patch.position.z+offset.y,str(patch.id)+str(offset),0.46)
			if classify and rows.size()>before:
				rows[-1].presentation_group="vegetation-skirt"
				rows[-1].anchor_id=patch.id;rows[-1].anchor_use=patch.use

static func patches(plan:Dictionary)->Array:
	if plan.get("generator_version")!="factory-country-1" or int(plan.get("generation_content_version",1))<3:return []
	var rows:Array=[];var seen:Dictionary={}
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var grouped:bool=int(plan.get("generation_content_version",1))>=9
	if grouped:_skirts(rows,seen,plan,noise,roads,96,true)
	# Inner low-grass ribbon with a broken outer fringe, rather than identical
	# isolated shrubs at a path's first midpoint. Keep the actual road shoulder
	# and service/buildable land open; no tall occluder or extra resource tree.
	for path:Dictionary in plan.paths:
		for segment:int in path.points.size()-1:
			var a:Dictionary=path.points[segment];var b:Dictionary=path.points[segment+1]
			var start:=Vector2(a.x,a.z);var delta:=Vector2(b.x-a.x,b.z-a.z)
			var length:float=delta.length()
			if length<0.25:continue
			var side:=Vector2(-delta.y,delta.x).normalized()
			for step:int in ceili(length/1.5):
				var at:Vector2=start+delta*minf((float(step)+0.5)*1.5/length,1.0)
				for sign:float in [-1.0,1.0]:
					var key:String=str(path.id)+":%d:%d:%d"%[segment,step,int(sign)]
					var jitter:float=float(_hash(plan,key)%7-3)/32.0
					var p:Vector2=at+side*(float(path.width)*0.5+1.15+jitter)*sign
					_append(rows,seen,plan,noise,roads,p.x,p.y,key,0.52)
					if _hash(plan,key+":outer")%3!=0:
						p=at+side*(float(path.width)*0.5+2.15+jitter)*sign
						_append(rows,seen,plan,noise,roads,p.x,p.y,key+":outer",0.44)
	# A small skirt joins already-persisted medium shrubs to the ground layer.
	# No edits to parent IDs/positions or plans; actual support is checked live.
	if not grouped:_skirts(rows,seen,plan,noise,roads,LIMIT)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.id<b.id)
	return rows
