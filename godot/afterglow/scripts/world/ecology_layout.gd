extends RefCounted
## Pure seed/coordinate layout, persisted ONCE with its generation plan.
## Patches have no yield/stock/growth promise. Trees retain actual B harvesting.
const Generator=preload("res://scripts/world/settlement_generator.gd")
const Broad=preload("res://scripts/world/broad_terraces.gd")
const Hills=preload("res://scripts/world/local_hills.gd")
const Relief=preload("res://scripts/world/local_relief.gd")
const Site=preload("res://scripts/world/site_relief.gd")
const VERSION=1

static func _tree_center(plan:Dictionary,p:float)->float:
	return floorf(p/Broad.PITCH)*Broad.PITCH+Broad.PITCH*0.5 if plan.height.get("grade_model","") in [Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL] else p

static func _drop(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,y:float,z:float)->Dictionary:
	# v5 stays inside the same broad tread with clearance from the actual trunk.
	# Original saved models retain their exact output position and height.
	if plan.height.get("grade_model","") in [Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]:
		return {"x":x+0.7,"y":Generator._sample(plan,noise,x+0.7,z,false,roads).height,"z":z}
	return {"x":x+1,"y":y,"z":z}

static func _hash(seed:int,tag:String)->int:
	return (str(seed)+":ecology-v1:"+tag).sha256_text().substr(0,8).hex_to_int()

static func clear_of_routes(plan:Dictionary,x:float,z:float,radius:float)->bool:
	for parcel:Dictionary in plan.parcels:
		if Generator._rect_distance(x,z,parcel.pad.xz)<radius+0.7:return false
	for path:Dictionary in plan.paths:
		for i in path.points.size()-1:
			if Generator._distance(x,z,path.points[i],path.points[i+1]).x<float(path.width)*0.5+radius+0.5:return false
	return true

static func _hills_tree_point(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,sites:Array,x:float,z:float)->Dictionary:
	# Reuse the same finite tree candidates/IDs. Try nearby true broad-tread
	# centres instead of dropping the candidate when its first rounded position
	# meets a path; never block the broad activity surface with extra fake props.
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	for offset:Vector2 in [Vector2.ZERO,Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2),Vector2(-2,-2),Vector2(2,-2),Vector2(-2,2),Vector2(2,2)]:
		var wx:float=x+offset.x;var wz:float=z+offset.y
		if wx<ox+1 or wx>ox+63 or wz<oz+1 or wz>oz+63 or not clear_of_routes(plan,wx,wz,2.2):continue
		if sites.any(func(s:Dictionary)->bool:return Vector2(wx-s.position.x,wz-s.position.z).length()<2.6):continue
		var sample:Dictionary=Generator._sample(plan,noise,wx,wz,false,roads)
		if sample.material==1:return {"x":wx,"y":sample.height,"z":wz}
	return {}

static func tree_sites(plan:Dictionary)->Array:
	var sites:Array=[];var noise:=Generator._noise(int(plan.seed))
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	var road_index:=Generator._road_index(plan)
	for z in range(6,61,9):
		for x in [3,17,30,45,54,60]:
			var hash:=_hash(int(plan.seed),plan.region_id+":tree:%d:%d"%[x,z])
			# Dense east forest edge, isolated orchard/field-bank trees elsewhere.
			if x<45 and hash%3!=0:continue
			if x>=45 and hash%5==0:continue
			var wx:float=ox+x+float(hash%3-1)*0.5
			var wz:float=oz+z+float((hash/3)%3-1)*0.5
			wx=_tree_center(plan,wx);wz=_tree_center(plan,wz)
			if plan.height.get("grade_model","") in [Hills.MODEL,Relief.MODEL,Site.MODEL]:
				var point:Dictionary=_hills_tree_point(plan,noise,road_index,sites,wx,wz)
				if point.is_empty():continue
				wx=point.x;wz=point.z
			if not clear_of_routes(plan,wx,wz,2.2):continue
			var sample:Dictionary=Generator._sample(plan,noise,wx,wz,false,road_index)
			if sample.material!=1:continue
			var species:String=["broadleaf_tree","conifer_tree","dead_tree"][hash%3]
			var id:="rural:v3:%d:%d:%d:tree:%d:%d"%[plan.seed,plan.region_coord.x,plan.region_coord.z,x,z]
			var scale:float=0.88+float((hash/7)%4)*0.04
			sites.append({"id":id,"kind":"tree","position":{"x":wx,"y":sample.height,"z":wz},"output_id":id+":drops","drops_position":_drop(plan,noise,road_index,wx,sample.height,wz),"use":"forest-edge" if x>=45 else "field-bank","appearance":{"version":VERSION,"surface_version":1,"surface_variant":int(hash/17)%2,"model":species,"height":4.0*scale,"yaw":float((hash/13)%16)*TAU/16.0}})
	if plan.height.get("grade_model","") in ["village-contours-v4",Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]:
		var added:int=0
		for parcel:Dictionary in plan.parcels:
			if parcel.site_id not in ["home","neighbor"]:continue
			var r:Array=parcel.pad.xz
			for offset:Vector2 in [Vector2(-3.5,2),Vector2(-5.5,4.5),Vector2(-3.5,7.5),Vector2(3.5,-3.5),Vector2(6,-5.5),Vector2(8.5,-3.5)]:
				if added>=4:break
				var wx:float=float(r[0])+offset.x;var wz:float=float(r[1])+offset.y
				wx=_tree_center(plan,wx);wz=_tree_center(plan,wz)
				if plan.height.get("grade_model","") in [Hills.MODEL,Relief.MODEL,Site.MODEL]:
					var point:Dictionary=_hills_tree_point(plan,noise,road_index,sites,wx,wz)
					if point.is_empty():continue
					wx=point.x;wz=point.z
				if wx<ox+2 or wx>ox+62 or wz<oz+2 or wz>oz+62 or not clear_of_routes(plan,wx,wz,2.2):continue
				if sites.any(func(s:Dictionary)->bool:return Vector2(wx-s.position.x,wz-s.position.z).length()<2.6):continue
				var sample:Dictionary=Generator._sample(plan,noise,wx,wz,false,road_index)
				if sample.material!=1:continue
				var id:String=str(parcel.id)+":grove:"+str(added)
				var hash:int=_hash(int(plan.seed),id)
				sites.append({"id":id,"kind":"tree","position":{"x":wx,"y":sample.height,"z":wz},"output_id":id+":drops","drops_position":_drop(plan,noise,road_index,wx,sample.height,wz),"use":"courtyard-forest-edge","appearance":{"version":VERSION,"surface_version":1,"surface_variant":hash%2,"model":["broadleaf_tree","conifer_tree"][hash%2],"height":3.8+float(hash%3)*0.2,"yaw":float(hash%16)*TAU/16}})
				added+=1
	return sites

static func patches(plan:Dictionary)->Dictionary:
	var points:Array=[];var rejected:=0
	var noise:=Generator._noise(int(plan.seed));var road_index:=Generator._road_index(plan)
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	# A managed row pattern belongs only inside real soil field polygons.
	# Actual newly delivered rice images. Static abandoned rows, not simulated
	# watered/growing crops and not an inventory or free harvest source.
	for land:Dictionary in plan.landforms:
		if land.use!="field":continue
		for z in range(ceili(land.xz[1]+1),floori(land.xz[3]-1),2):
			for x in range(ceili(land.xz[0]+1),floori(land.xz[2]-1),2):
				var model:String="quality:"+(["c01_rice_vegetative","c02_rice_ripe","c03_rice_stubble"][posmod(z/2,3)] if x<int(land.xz[0])+10 else "c04_leafy_rosette")
				if not _append(points,plan,noise,road_index,x+0.25,z+0.25,model,2,"abandoned-field",0.72):rejected+=1
	# Groups follow the forest fringe and the ditch, not uniform full-scene dots.
	for site:Dictionary in plan.resource_sites:
		for offset:Vector2 in [Vector2(-1.6,-0.7),Vector2(1.4,1.3),Vector2(-0.8,1.9)]:
			var hash:=_hash(int(plan.seed),site.id+str(offset))
			var model:String="quality:"+["v01_fresh_grass","v02_dry_grass","v03_yellow_wildflowers","v05_flowering_shrub_sparse","v06_flowering_shrub_dense","v07_fern","v08_bramble"][hash%7]
			if not _append(points,plan,noise,road_index,float(site.position.x)+offset.x,float(site.position.z)+offset.y,model,1,"forest-understorey",0.65):rejected+=1
	for z in range(44,59,3):
		for x:float in [38.25,42.75]:
			if not _append(points,plan,noise,road_index,ox+x,oz+z+0.25,"quality:v04_cattails",-1,"dry-ditch-edge",0.60):rejected+=1
	return {"version":VERSION,"patches":points,"candidate_rejections":rejected,"semantics":"persisted nonblocking unmanaged vegetation; no interaction/stock/yield or crop simulation"}

static func _append(points:Array,plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,z:float,model:String,material:int,use:String,width:float)->bool:
	if plan.height.get("grade_model","") in [Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]:
		# Keep the whole existing ground-card footprint on one true tread. This
		# changes new-plan placement only, not geometry/Alpha or old vegetation.
		var margin:float=width*0.5+0.1
		x=clampf(x,floorf(x/Broad.PITCH)*Broad.PITCH+margin,floorf(x/Broad.PITCH)*Broad.PITCH+Broad.PITCH-margin)
		z=clampf(z,floorf(z/Broad.PITCH)*Broad.PITCH+margin,floorf(z/Broad.PITCH)*Broad.PITCH+Broad.PITCH-margin)
	if not clear_of_routes(plan,x,z,width*0.5):return false
	for rect:Array in plan.get("dressing_footprints",[]):
		if Generator._rect_distance(x,z,rect)<width*0.7+0.1:return false
	var sample:Dictionary=Generator._sample(plan,noise,(floori(x*2)+0.5)*0.5,(floori(z*2)+0.5)*0.5,true,roads)
	if material>=0 and sample.material!=material:return false
	if sample.material not in [1,2,3]:return false
	for site:Dictionary in plan.resource_sites:
		if Vector2(x-site.position.x,z-site.position.z).length()<0.85:return false
	var hash:=_hash(int(plan.seed),plan.region_id+":"+use+":"+str(x)+":"+str(z))
	points.append({"id":plan.region_id+":eco1:"+use+":"+str(x)+":"+str(z),"model":model,"position":{"x":x,"y":sample.height,"z":z},"yaw":0.0 if use=="abandoned-field" else float(hash%16)*TAU/16.0,"scale":0.85+float(hash%4)*0.05,"footprint":[width,width],"material":sample.material,"use":use,"phase":"unmanaged-static","blocking":false,"harvestable":false})
	return true
