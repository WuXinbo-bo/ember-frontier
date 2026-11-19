extends RefCounted
## Finite, persisted EV01 terrain source. No story tick, permission gate,
## bonus rewards, fake bridge or regeneration of an explored plan.
const Data=preload("res://scripts/world/world_data.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")

static func location(x:float,y:float,z:float,region:String)->Dictionary:
	return {"x":x,"y":y,"z":z,"regionId":region,"buildingId":null,"storeyId":null}

static func height(plan:Dictionary,noise:FastNoiseLite,index:Dictionary,x:float,z:float)->float:
	return float(Raster._sample(plan,noise,x,z,false,index).height)

static func feet(plan:Dictionary,noise:FastNoiseLite,index:Dictionary,x:float,z:float)->Dictionary:
	var high:float=-INF;var low:float=INF
	for dx:float in [-0.26,0.0,0.26]:
		for dz:float in [-0.26,0.0,0.26]:
			var h:float=height(plan,noise,index,(floorf((x+dx)*2)+0.5)*0.5,(floorf((z+dz)*2)+0.5)*0.5)
			high=maxf(high,h);low=minf(low,h)
	return {} if high-low>0.5 else location(x,high,z,str(plan.region_id))

static func plan_site(plan:Dictionary)->Dictionary:
	if plan.region_id!="RH-VILLAGE" or int(plan.get("generation_content_version",1))<2:return {"ok":true,"sites":[]}
	var noise:=Raster._noise(int(plan.seed));var index:Dictionary=Raster._road_index(plan)
	var north:Array=plan.paths.filter(func(p:Dictionary)->bool:return str(p.id).ends_with(":north"))
	if north.is_empty():return Data.reject("REGIONAL_SITE_NO_NORTH_ROAD")
	var path:Dictionary=north[0]
	for n in range(path.points.size()-1,0,-1):
		var a:Dictionary=path.points[n-1];var b:Dictionary=path.points[n]
		var start:=Vector2(a.x,a.z);var end:=Vector2(b.x,b.z)
		if start.distance_to(end)<7.0:continue
		var along:Vector2=(end-start).normalized();var across:=Vector2(-along.y,along.x)
		if absf(along.x)>0.001 and absf(along.y)>0.001:continue
		for fraction:float in [0.5,0.35,0.65]:
			var center:Vector2=start.lerp(end,fraction)
			center=(center*2).floor()*0.5
			if center.x<6 or center.x>58 or center.y<-58 or center.y>-38:continue
			var stones:Array=[];var bases:Array=[];var clear:Array=[];var valid:bool=true
			for u in range(-3,3):
				for v in range(-1,1):
					var at:Vector2=center+across*(u*0.5+0.25)+along*(v*0.5+0.25)
					var sample:Dictionary=Raster._sample(plan,noise,at.x,at.y,false,index)
					if sample.material!=4:valid=false;break
					var x:int=floori(at.x*2);var z:int=floori(at.y*2);var floor_y:int=roundi(sample.height*2)
					bases.append({"x":x,"y":floor_y-1,"z":z,"material":4})
					for y in range(floor_y,floor_y+2):
						stones.append({"x":x,"y":y,"z":z,"material":3,"clear_material":0})
						clear.append({"x":x,"y":y,"z":z})
				if not valid:break
			if not valid:continue
			var before:Dictionary=feet(plan,noise,index,center.x-along.x*2.5,center.y-along.y*2.5)
			var after:Dictionary=feet(plan,noise,index,center.x+along.x*2.5,center.y+along.y*2.5)
			var encounter:Dictionary=feet(plan,noise,index,center.x+along.x*6,center.y+along.y*6)
			var encounters:Array=[]
			for offset:float in [0.0,-0.7,0.7]:encounters.append(feet(plan,noise,index,center.x+along.x*6+across.x*offset,center.y+along.y*6+across.y*offset))
			var left_before:Dictionary=feet(plan,noise,index,center.x-along.x*2.5+across.x*2.5,center.y-along.y*2.5+across.y*2.5)
			var left_after:Dictionary=feet(plan,noise,index,center.x+along.x*2.5+across.x*2.5,center.y+along.y*2.5+across.y*2.5)
			if ([before,after,encounter,left_before,left_after]+encounters).any(func(p:Dictionary)->bool:return p.is_empty() or p.x<0.6 or p.x>63.4 or p.z<-63.4 or p.z>-0.6):continue
			var id:String="r34:regional:townward-roadfall:RH-VILLAGE"
			return {"ok":true,"sites":[{"id":id,"kind":"stone-roadfall-v1","generation_content_version":2,"region_id":plan.region_id,"survey_point":before.duplicate(true),"obstacle_cells":stones,"goal_corridor":{"base_cells":bases,"clear_cells":clear,"approach_before":before,"approach_after":after,"width_m":2.5,"bypass_points":[left_before,left_after]},"encounter_position":encounter,"encounter_positions":encounters,"warning_points":{"survey":before.duplicate(true),"approach_before":before.duplicate(true),"approach_after":after.duplicate(true)},"semantics":"actual stone cell volume only; survey/risk/events owned by E/A; no extra reward"}]}
	return Data.reject("REGIONAL_SITE_NO_SAFE_STONE_CORRIDOR")

static func apply(draft:Dictionary)->Dictionary:
	if not draft.get("ok",false):return draft
	for site:Dictionary in draft.plan.get("regional_sites",[]):
		for p:Dictionary in site.obstacle_cells:
			var cell:=Vector3i(p.x,p.y,p.z);var key:String=Data.key(Data.cell_chunk(cell,16))
			if not draft.chunks.has(key) or draft.chunks[key].cells[Data.local_index(cell,16)]!=0:return Data.reject("REGIONAL_SITE_OCCUPIED_CELL")
			draft.chunks[key].cells[Data.local_index(cell,16)]=3
	return draft
