extends RefCounted
## Explicit content8 spatial facts only. This finite stone is original voxel
## material, not an EV site, permission gate, stock, grant or new work rule.
const Data=preload("res://scripts/world/world_data.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")

static func _feet(plan:Dictionary,noise:FastNoiseLite,roads:Dictionary,x:float,z:float)->Dictionary:
	var low:float=INF;var high:float=-INF
	for dx:float in [-0.26,0.0,0.26]:
		for dz:float in [-0.26,0.0,0.26]:
			var h:float=Raster._sample(plan,noise,(floorf((x+dx)*2)+0.5)*0.5,(floorf((z+dz)*2)+0.5)*0.5,false,roads).height
			low=minf(low,h);high=maxf(high,h)
	return {} if low!=high else {"x":x,"y":high,"z":z,"regionId":plan.region_id,"buildingId":null,"storeyId":null}

static func _overlaps(a:Array,b:Array,margin:float=0.0)->bool:
	return a[0]<b[2]+margin and a[2]>b[0]-margin and a[1]<b[3]+margin and a[3]>b[1]-margin

static func prepare(plan:Dictionary)->Dictionary:
	if int(plan.get("generation_content_version",1)) in [13,14,15,16,17,18,19,20,21]:return {"ok":true,"entrances":[]}
	if plan.region_id!="RH-HOME":return {"ok":true,"entrances":[]}
	var manuals:Array=plan.parcels.filter(func(p:Dictionary)->bool:return p.site_id=="woodwork")
	if manuals.size()!=1 or plan.get("story_sites",[]).size()!=1:return Data.reject("S01_ENTRANCE_MISSING_ORIGINAL_SITES")
	var manual:Dictionary=manuals[0];var frame:Dictionary=plan.story_sites[0]
	var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	# Fixed finite half-metre candidates beside the original work throat. No
	# pad, road, building or resource is moved to manufacture a successful fit.
	for dx:float in [3.5,4.0,4.5]:
		for dz:float in [0.0,-0.5,0.5]:
			var left:float=floorf((manual.origin.x+dx)*2)*0.5
			var center_z:float=floorf((manual.origin.z+dz)*2)*0.5
			var rect:Array=[left,center_z-1.5,left+1.0,center_z+1.5]
			var valid:bool=not _overlaps(rect,frame.foundation_xz,0.5)
			for parcel:Dictionary in plan.parcels:
				if _overlaps(rect,parcel.pad.xz,0.5):valid=false
			for tree:Dictionary in plan.resource_sites:
				if _overlaps(rect,[tree.position.x-1,tree.position.z-1,tree.position.x+1,tree.position.z+1]):valid=false
			if not valid:continue
			var before:Dictionary=_feet(plan,noise,roads,left-1.0,center_z)
			var after:Dictionary=_feet(plan,noise,roads,left+2.0,center_z)
			var bypass:Array=[_feet(plan,noise,roads,left-1.0,center_z-2.5),_feet(plan,noise,roads,left+2.0,center_z-2.5)]
			if ([before,after]+bypass).any(func(p:Dictionary)->bool:return p.is_empty()):continue
			var cells:Array=[];var bases:Array=[]
			for z:int in range(roundi(rect[1]*2),roundi(rect[3]*2)):
				for x:int in range(roundi(rect[0]*2),roundi(rect[2]*2)):
					var sample:Dictionary=Raster._sample(plan,noise,(x+0.5)*0.5,(z+0.5)*0.5,false,roads)
					if sample.height!=before.y or after.y!=before.y:valid=false;break
					var base:int=roundi(sample.height*2)
					bases.append({"x":x,"y":base-1,"z":z,"material":sample.material})
					for y:int in range(base,base+2):cells.append({"x":x,"y":y,"z":z,"material":3,"clear_material":0})
				if not valid:break
			if not valid:continue
			return {"ok":true,"entrances":[{"version":1,"id":"RH-HOME:woodwork-yard-stone","kind":"yard-stone-v1","region_id":plan.region_id,"manual_id":manual.id,"frame_id":frame.id,"obstacle_cells":cells,"base_cells":bases,"approach_before":before,"approach_after":after,"bypass_points":bypass,"semantics":"finite actual stone volume; original tool, body, support and pack rules; no EV or bonus"}]}
	return Data.reject("S01_ENTRANCE_NO_SAFE_FINITE_CORRIDOR")

static func apply(draft:Dictionary)->Dictionary:
	if not draft.get("ok",false):return draft
	# Verify the entire detached batch before changing even its first cell.
	for site:Dictionary in draft.plan.get("story_entrances",[]):
		for p:Dictionary in site.base_cells+site.obstacle_cells:
			var cell:=Vector3i(p.x,p.y,p.z);var key:String=Data.key(Data.cell_chunk(cell,16))
			var expected:int=int(p.material) if p in site.base_cells else 0
			if not draft.chunks.has(key) or draft.chunks[key].cells[Data.local_index(cell,16)]!=expected:return Data.reject("S01_ENTRANCE_OCCUPIED_OR_UNSUPPORTED_CELL")
	for site:Dictionary in draft.plan.get("story_entrances",[]):
		for p:Dictionary in site.obstacle_cells:
			var cell:=Vector3i(p.x,p.y,p.z);var key:String=Data.key(Data.cell_chunk(cell,16))
			draft.chunks[key].cells[Data.local_index(cell,16)]=3
	return draft
