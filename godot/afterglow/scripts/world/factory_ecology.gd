extends RefCounted
## Content3: bounded, persisted middle-scale vegetation around actual land uses.
## Existing species/images only. No second terrain, crop yield or prop stocks.
const Terrain=preload("res://scripts/world/factory_landscape.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const Ecology=preload("res://scripts/world/ecology_layout.gd")

static func add_groves(plan:Dictionary)->void:
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var sites:Array=plan.resource_sites
	var added:int=0
	for parcel:Dictionary in plan.parcels:
		if parcel.site_id not in ["home","neighbor"]:continue
		var r:Array=parcel.pad.xz
		var candidates:Array=[Vector2(r[2]+3,r[3]+3),Vector2(r[0]-3,r[3]+3),Vector2(r[2]+5,r[3]+5),Vector2(r[0]-5,r[1]-3),Vector2(r[2]+3,r[1]-4),Vector2(r[2]+6,(r[1]+r[3])*0.5)]
		for i in candidates.size():
			if added>=3:break
			var at:Vector2=candidates[i]
			var point:Dictionary=Ecology._hills_tree_point(plan,noise,roads,sites,at.x,at.y)
			if point.is_empty():continue
			# B's new pads can contain decimal service offsets. Persist new grove
			# positions on the same binary-exact lattice as content3 groundcover,
			# then validate the final position, not the pre-quantized candidate.
			point.x=snappedf(float(point.x),1.0/64.0);point.z=snappedf(float(point.z),1.0/64.0)
			if not Ecology.clear_of_routes(plan,point.x,point.z,2.2):continue
			if int(plan.get("generation_content_version",1)) in [13,14,15,16,17,18,19,20,21] and not preload("res://scripts/world/village_opening_layout.gd").clear_expansion(plan,point.x,point.z,2.2):continue
			if sites.any(func(s:Dictionary)->bool:return Vector2(point.x-s.position.x,point.z-s.position.z).length()<2.6):continue
			var supported:bool=true
			for dx:float in [-0.35,0.0,0.35]:
				for dz:float in [-0.35,0.0,0.35]:
					var wx:float=(floori((point.x+dx)*2)+0.5)*0.5;var wz:float=(floori((point.z+dz)*2)+0.5)*0.5
					var sample:Dictionary=Raster._sample(plan,noise,wx,wz,false,roads)
					if sample.height!=point.y or sample.material!=1:supported=false
			if not supported:continue
			var id:String=str(parcel.id)+":grove3:"+str(i)
			var h:int=Terrain.hash_key(plan.seed,"resources",id)
			var drop:Dictionary=Ecology._drop(plan,noise,roads,point.x,point.y,point.z)
			drop.x=snappedf(float(drop.x),1.0/64.0);drop.z=snappedf(float(drop.z),1.0/64.0)
			drop.y=Raster._sample(plan,noise,drop.x,drop.z,false,roads).height
			sites.append({"id":id,"kind":"tree","position":point,"output_id":id+":drops","drops_position":drop,"use":"courtyard-grove","source_stream":"resources","appearance":{"version":1,"surface_version":1,"surface_variant":h%2,"model":["broadleaf_tree","conifer_tree"][h%2],"height":3.8+float((h/7)%3)*0.2,"yaw":float((h/13)%16)*TAU/16.0}})
			added+=1

static func _supported_append(points:Array,plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,z:float,model:String,use:String,width:float)->bool:
	if not Ecology._append(points,plan,noise,roads,x,z,model,1,use,width):return false
	var p:Dictionary=points[-1];var r:float=width*float(p.scale)*sqrt(2.0)*0.5
	# Same full square support as EnvironmentView, including rotated corners.
	for cz in range(floori((p.position.z-r+0.00001)*2),floori((p.position.z+r-0.00001)*2)+1):
		for cx in range(floori((p.position.x-r+0.00001)*2),floori((p.position.x+r-0.00001)*2)+1):
			var sample:Dictionary=Raster._sample(plan,noise,(cx+0.5)*0.5,(cz+0.5)*0.5,false,roads)
			if sample.height!=p.position.y or sample.material!=1:points.pop_back();return false
	return true

static func patches(plan:Dictionary)->Dictionary:
	# Existing abandoned field rows, real forest understory and dry ditch edge
	# remain land-use based. Replace the old scene-wide dot grid, not all cover.
	var result:Dictionary=Ecology.patches(plan)
	var points:Array=result.patches;var rejected:int=result.candidate_rejections
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var centers:Array=[]
	for parcel:Dictionary in plan.parcels:
		var r:Array=parcel.pad.xz
		for at:Vector2 in [Vector2(r[0]-2.5,r[1]-2.5),Vector2(r[2]+2.5,r[1]-2.5),Vector2(r[0]-2.5,r[3]+2.5),Vector2(r[2]+2.5,r[3]+2.5)]:centers.append({"at":at,"use":"activity-margin"})
	for land:Dictionary in plan.landforms:
		if land.use!="field-bank":continue
		var r:Array=land.xz
		for z in range(ceili(r[1]+1),floori(r[3]),4):centers.append({"at":Vector2((r[0]+r[2])*0.5,z),"use":"bund-cover"})
	for path:Dictionary in plan.paths:
		if path.purpose not in ["module-service","forest-access","field-shortcut","quarry-loop"] or path.points.size()<2:continue
		var a:Dictionary=path.points[0];var b:Dictionary=path.points[1]
		var along:=Vector2(float(b.x)-a.x,float(b.z)-a.z).normalized()
		var side:=Vector2(-along.y,along.x)
		var middle:=Vector2((a.x+b.x)*0.5,(a.z+b.z)*0.5)
		var sign:float=1.0 if Terrain.hash_key(plan.seed,"decor",path.id)%2==0 else -1.0
		centers.append({"at":middle+side*(float(path.width)*0.5+2.0)*sign,"use":"lane-shoulder-group"})
	# Small grass/shrub groups along stable contour shoulders form visible
	# middle-scale silhouettes while leaving actual roads and service pads clear.
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	for z in range(10,60,8):
		for x in range(10,60,8):
			var h:int=Terrain.hash_key(plan.seed,"decor",plan.region_id+":slope:%d:%d"%[x,z])
			if h%3!=0:continue
			var a:float=Raster._sample(plan,noise,ox+x,oz+z,false,roads).height
			var b:float=Raster._sample(plan,noise,ox+x+1,oz+z+1,false,roads).height
			if a!=b:centers.append({"at":Vector2(ox+x,oz+z),"use":"contour-shoulder"})
			elif h%6==0:centers.append({"at":Vector2(ox+x+1.0,oz+z-1.0),"use":"rough-grass-island"})
	for center:Dictionary in centers:
		var at:Vector2=center.at
		for i in 7:
			var angle:float=float(i)*TAU/7.0
			var radius:float=0.0 if i==0 else 0.9+float(i%2)*0.55
			var x:float=at.x+cos(angle)*radius;var z:float=at.y+sin(angle)*radius
			if x<ox+1 or x>ox+63 or z<oz+1 or z>oz+63:continue
			var model:String="quality:"+(["v06_flowering_shrub_dense","v05_flowering_shrub_sparse","v07_fern"][i%3] if i<3 else ["v01_fresh_grass","v02_dry_grass"][i%2])
			if not _supported_append(points,plan,noise,roads,x,z,model,str(center.use),0.85 if i<3 else 0.65):rejected+=1
	# Persist binary-exact 1/64m positions. Arbitrary trig/float32 intermediates
	# otherwise change their last bits through JSON even with full_precision.
	# This is a new content3 layout rule only, never an old-plan migration.
	var unique:Dictionary={};var canonical:Array=[]
	for patch:Dictionary in points:
		patch.position.x=snappedf(float(patch.position.x),1.0/64.0)
		patch.position.z=snappedf(float(patch.position.z),1.0/64.0)
		patch.id=plan.region_id+":eco3:"+str(patch.use)+":%d:%d"%[roundi(patch.position.x*64),roundi(patch.position.z*64)]
		if unique.has(patch.id):continue
		unique[patch.id]=true;canonical.append(patch)
	result.version=2;result.patches=canonical;result.candidate_rejections=rejected
	result.layout_policy="land-use-clusters-v3"
	result.semantics="persisted finite existing-image clusters; true support/route clearance; no stock, crop growth, collision or simulated yield"
	return result
