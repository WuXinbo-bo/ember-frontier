extends RefCounted
## Deterministic, plan-consuming recipes. No terrain generation, actor mutation,
## random layout, clock, inventory authority or direct world commit lives here.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const MARKER="r3:building-generation"
var service:RefCounted
var world:RefCounted
var instances:Array=[]
var storeys:Array=[]
var stocks:Array=[]
var records:Array=[]
var tools:Array=[]
var extra:Array=[]
var entrances:Dictionary={}
var anchors:Dictionary={}
var parcel:Dictionary
var profile:Dictionary
var region_id:String
var building_id:String
var floor_id:String

func local_at(p:Array,inside:bool=true)->Dictionary:
	var origin:=Geometry.point(parcel.origin)
	var position:=origin+Geometry.rotate(Vector3(float(p[0]),float(p[1]),float(p[2])),int(parcel.quarter_turn))
	return {"x":position.x,"y":position.y,"z":position.z,"regionId":region_id,"buildingId":building_id if inside else null,"storeyId":floor_id if inside else null}

func piece(id:String,definition:String,p:Array,turn:int=0)->Dictionary:
	var value:Dictionary=service.make_instance(definition,building_id+":"+id,local_at(p),posmod(turn+int(parcel.quarter_turn),4),profile.recipe.owner)
	value.presentation={"profile_id":profile.id,"family_id":profile.family_id,"wall":profile.recipe.style.wall,"floor":profile.recipe.style.floor,"roof":profile.recipe.roof.material}
	instances.append(value)
	return value

func prop(id:String,asset:String,p:Array,turn:int,sleeping:bool=false)->void:
	var at:=local_at(p)
	var size:=Vector3(1.35,1.01,2.1) if sleeping else Vector3(0.4,0.6,0.4)
	var half:=Geometry.rotate(Vector3(size.x,0,size.z),posmod(turn+int(parcel.quarter_turn),4)).abs()/2
	var position:=Geometry.point(at)
	var value:Dictionary={"id":building_id+":"+id,"kind":"prop","regionId":region_id,"buildingId":building_id,"storeyId":floor_id,"position":Geometry.json_point(position),"bounds":Geometry.json_box(AABB(position-Vector3(half.x,0,half.z),Vector3(2*half.x,size.y,2*half.z))),"revision":0,"blocksTerrain":true,"supportBounds":[],"data":{"assetId":asset,"solid":true,"opaque":true,"sleeping":sleeping,"prepared":false,"owner":profile.recipe.owner,"quarterTurn":posmod(turn+int(parcel.quarter_turn),4)}}
	extra.append({"op":"entity.put","id":value.id,"before_exists":false,"before":null,"after":value})

func roof(id:String,x:float,z:float,rect:Array,porch:bool=false)->void:
	if porch:piece(id,"roof",[x,3.4,z]);return
	var spec:Dictionary=profile.recipe.roof
	var axis_x:bool=spec.axis=="x"
	var coordinate:float=x if axis_x else z
	var low:float=float(rect[0] if axis_x else rect[1])
	var high:float=float(rect[2] if axis_x else rect[3])
	var reverse:bool=spec.shape=="gable" and coordinate>(low+high)/2
	var distance:float=(high-coordinate-1) if reverse else (coordinate-low-1)
	var tier:=clampi(roundi(distance/2),0,7)
	var prefix:="half" if float(spec.rise_per_meter)==0.25 else "quarter"
	var turn:=(0 if axis_x else 1)+(2 if reverse else 0)
	piece(id,"roof_pitch_"+prefix+"_"+str(tier),[x,3.4,z],turn)

func wall(id:String,x:float,z:float,turn:int,interior:bool=false)->void:
	var selected:Dictionary={}
	for door:Dictionary in profile.recipe.doors:
		if Vector2(float(door.position[0])-x,float(door.position[2])-z).length()<0.01:selected=door;break
	var definition:="door" if not selected.is_empty() else "wall"
	# Window locations are stable structural sockets, away from internal doors.
	if selected.is_empty() and not interior and (int(x+z)%6==1):definition="window"
	var value:=piece(str(selected.id) if not selected.is_empty() else id,definition,[x,0,z],turn)
	if not selected.is_empty() and selected.exterior:
		for port:Dictionary in profile.entrance_ports:
			if port.id!=selected.id:continue
			var at:=local_at(port.position,false)
			if not entrances.has(region_id):entrances[region_id]=[]
			entrances[region_id].append({"id":building_id+":entrance:"+str(selected.id),"kind":"entrance","buildingId":building_id,"position":Geometry.json_point(Geometry.point(at)),"regionId":region_id,"x":at.x,"y":at.y,"z":at.z})
		value.protected=false

func shell()->void:
	storeys.append({"id":floor_id,"buildingId":building_id,"regionId":region_id,"index":0,"elevation":float(parcel.origin.y)})
	var cells:Dictionary={}
	var porch_cells:Dictionary={}
	var porch:Variant=profile.recipe.get("porch")
	if porch is Array:
		for x in range(int(porch[0])+1,int(porch[2]),2):
			for z in range(int(porch[1])+1,int(porch[3]),2):porch_cells[Vector2i(x,z)]=true
	for rect:Array in profile.recipe.rectangles:
		for x in range(int(rect[0])+1,int(rect[2]),2):
			for z in range(int(rect[1])+1,int(rect[3]),2):cells[Vector2i(x,z)]=rect
	for cell:Vector2i in cells:
		var x:=float(cell.x);var z:=float(cell.y)
		piece("base:%d:%d"%[cell.x,cell.y],"foundation",[x,0,z])
		roof("roof:%d:%d"%[cell.x,cell.y],x,z,cells[cell])
		for delta:Vector2i in [Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2)]:
			if cells.has(cell+delta):continue
			var center:=Vector2(x,z)+Vector2(delta)/2
			var turn:=1 if delta.x else 0
			wall("wall:%s:%s"%[center.x,center.y],center.x,center.y,turn)
			# Real 20cm strip supports full wall thickness and visible plinth.
			if porch_cells.has(cell+delta):continue
			var rim:=center+Vector2(delta).normalized()*0.1
			var definition:="foundation_rim"
			if delta.x:
				# Concave L corners have two perpendicular strips. Trim only
				# the vertical strip so their union supports the wall without
				# overlapping physical foundation volumes or leaving a hole.
				var trim_start:bool=cells.has(cell+delta+Vector2i(0,-2))
				var trim_end:bool=cells.has(cell+delta+Vector2i(0,2))
				if trim_start or trim_end:definition+="_both" if trim_start and trim_end else "_start" if trim_start else "_end"
			piece("rim:%s:%s"%[center.x,center.y],definition,[rim.x,0,rim.y],1-turn)
	for line:Array in profile.recipe.partitions:
		if line[0]==line[2]:
			for z in range(int(line[1])+1,int(line[3]),2):wall("partition:%d:%d"%[line[0],z],line[0],z,1,true)
		else:
			for x in range(int(line[0])+1,int(line[2]),2):wall("partition:%d:%d"%[x,line[1]],x,line[1],0,true)
	if porch is Array:
		for x in range(int(porch[0])+1,int(porch[2]),2):
			for z in range(int(porch[1])+1,int(porch[3]),2):
				piece("porch:base:%d:%d"%[x,z],"foundation",[x,0,z])
				roof("porch:roof:%d:%d"%[x,z],x,z,porch,true)
		for x:float in [float(porch[0])+0.15,float(porch[2])-0.15]:
			piece("porch:post:"+str(x),"porch_post",[x,0,float(porch[3])-0.15])

func contents()->void:
	var known:Dictionary={}
	for spec:Dictionary in profile.recipe.objects:
		var id:=building_id+":"+str(spec.id)
		if str(spec.definition_id).is_empty():prop(spec.id,spec.asset_id,spec.position,int(spec.quarter_turn),spec.asset_id=="city_bed")
		else:piece(spec.id,spec.definition_id,spec.position,int(spec.quarter_turn))
		if spec.has("items"):
			stocks.append({"id":id,"location":local_at(spec.position),"items":spec.items.duplicate(true),"owner":profile.recipe.owner,"searched":spec.get("searched",false),"structureId":id})
		for kind:String in spec.get("tool_kinds",[]):tools.append({"id":building_id+":"+kind,"kind":kind,"holderId":id,"durability":85.0 if kind=="salvaged_axe" else 100.0})
		if spec.get("records",false):
			records.append({"id":building_id+":record:woodwork","holderId":id,"itemId":"book_woodwork","grants":["basic_woodwork"],"seconds":12.0})
			records.append({"id":building_id+":record:repair","holderId":id,"itemId":"book_tool_repair","grants":["basic_tool_repair"],"seconds":12.0})
		if spec.has("purpose"):known[spec.purpose]={"target_id":id,"position":local_at(spec.position)}
	anchors[building_id]=known

func courtyard()->void:
	var yard:Dictionary=profile.recipe.get("yard",{})
	if yard.is_empty():return
	for x in range(int(yard.min_x)+1,int(yard.max_x),2):
		var gate:bool=x==int(yard.gate_x)
		var value:=piece("yard-gate" if gate else "yard-wall:"+str(x),"door" if gate else "yard_wall",[x,0,yard.front_z])
		value.buildingId=null;value.storeyId=null
		if gate:value.hp=60;anchors[building_id]["yard-entrance"]={"target_id":value.id,"position":local_at([float(x)+1.15,0,float(yard.front_z)-0.5],false)}
	for x:float in [float(yard.min_x),float(yard.max_x)]:
		for z in range(int(yard.side_start_z)+1,int(yard.front_z),2):
			var value:=piece("yard-return:%s:%s"%[x,z],"yard_wall",[x,0,z],1);value.buildingId=null;value.storeyId=null
	for port:Dictionary in profile.entrance_ports:
		if port.id!="yard-gate":continue
		var at:=local_at(port.position,false)
		if not entrances.has(region_id):entrances[region_id]=[]
		entrances[region_id].append({"id":building_id+":entrance:yard-gate","kind":"entrance","buildingId":building_id,"position":Geometry.json_point(Geometry.point(at)),"regionId":region_id,"x":at.x,"y":at.y,"z":at.z})

func valid_parcel(p:Dictionary,profiles:Dictionary)->bool:
	if not p.get("id") is String or str(p.id).is_empty() or not profiles.has(p.get("profile_id")) or not p.get("origin") is Dictionary:return false
	if not [p.origin.get("x"),p.origin.get("y"),p.origin.get("z"),p.get("quarter_turn")].all(func(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))):return false
	if float(p.quarter_turn)!=floor(float(p.quarter_turn)) or int(p.quarter_turn) not in [0,1,2,3]:return false
	return p.get("recipe_id",p.profile_id)==p.profile_id

func prepare(building:RefCounted,view:RefCounted,regions:Array=[])->Dictionary:
	service=building;world=view
	var profiles:Dictionary={}
	for p:Dictionary in service.generation_profiles():profiles[p.id]=p
	var previous:Dictionary=service.structures(view)
	var built:Variant=view.extension(MARKER)
	var marker:Dictionary=built.duplicate(true) if built is Dictionary else {"version":1,"parcels":{}}
	var assembled:Array=[];var seen:Dictionary={};var plans:Dictionary={}
	for region:Dictionary in view.regions():
		region_id=region.id
		if not regions.is_empty() and not regions.has(region_id):continue
		var plan:Variant=view.extension("generation:"+region_id)
		if not plan is Dictionary or plan.get("schema")!="afterglow-settlement-plan-v1":continue
		plans[region_id]=plan
		for p:Dictionary in plan.get("parcels",[]):
			if not valid_parcel(p,profiles) or seen.has(p.get("id")):return service.failure("INVALID_GENERATION_PLAN","地块身份、配方、朝向或原点无效")
			seen[p.id]=true
			# Normalize JSON integer/float representation before hashing. Reload
			# may decode 0 as 0.0; no actual plan value is changed or discarded.
			var stamp:=JSON.stringify(JSON.parse_string(JSON.stringify(p)),"",true,true).sha256_text()
			if marker.parcels.has(p.id):
				if marker.parcels[p.id].plan_sha256!=stamp:return service.failure("GENERATION_PLAN_CHANGED","已装配地块不能重新抽取或静默搬迁")
				continue
			if previous.storeys.any(func(s:Dictionary)->bool:return s.buildingId==p.id):return service.failure("GENERATION_ID_OCCUPIED","地块已有建筑事实")
			parcel=p;profile=profiles[p.profile_id].duplicate(true);building_id=p.id;floor_id=building_id+":ground"
			# A shared architectural family does not make a neighbor's home or
			# their stock player-owned. Preserve the existing household roles.
			if p.get("site_id")=="neighbor":profile.recipe.owner="village-resident"
			shell();contents();courtyard();assembled.append(p.id)
			var sites:Array=[]
			for spec:Dictionary in profile.recipe.get("construction_sites",[]):
				sites.append({"id":building_id+":"+str(spec.id),"definition_id":spec.definition_id,"name":spec.name,"position":local_at(spec.position),"quarter_turn":posmod(int(spec.quarter_turn)+int(parcel.quarter_turn),4),"owner":profile.recipe.owner})
			marker.parcels[p.id]={"profile_id":p.profile_id,"plan_sha256":stamp,"region_id":region_id,"life_anchors":anchors[building_id].duplicate(true),"construction_sites":sites}
	if assembled.is_empty():return service.failure("ALREADY_SEEDED","持久计划没有未装配地块")
	var data:=previous.duplicate(true);data.instances.append_array(instances);data.storeys.append_array(storeys)
	var changes:Array=extra.duplicate(true)
	changes.append(service.extension_change(service.EXTENSION,data,view));changes.append(service.extension_change(MARKER,marker,view))
	for v:Dictionary in instances:changes.append({"op":"entity.put","id":v.id,"before_exists":false,"before":null,"after":service.geometry.entity(v)})
	for region:String in entrances:
		var plan:Dictionary=plans[region].duplicate(true);plan.slots=plan.get("slots",[])+entrances[region]
		changes.append(service.extension_change("generation:"+region,plan,view))
	var spawns:Dictionary={}
	var query:RefCounted=service.space(view,data)
	for region:String in plans:
		var plan:Dictionary=plans[region]
		if region=="RH-HOME" and plan.get("anchors",{}).has("arrival"):
			var arrival:Variant=plan.anchors.arrival
			var at:Dictionary=Geometry.location(arrival.position if arrival.has("position") else arrival);at.regionId=region
			spawns.player=at
		for p:Dictionary in plan.parcels:
			var role:String=p.get("site_id","")
			if role not in ["repair","neighbor"]:continue
			for v:Dictionary in instances:
				if v.buildingId!=p.id or not v.has("door"):continue
				for point:Dictionary in query.use_points(v):
					var feet:Dictionary=query.standing_point(point)
					if feet.get("buildingId")==p.id:
						spawns["repair-resident" if role=="repair" else "village-resident"]=feet;break
				if spawns.has("repair-resident" if role=="repair" else "village-resident"):break
	return {"ok":true,"code":"OK","reason":null,"world_changes":changes,"fact_changes":[],"initial_stocks":stocks,"initial_tools":tools,"initial_records":records,"life_anchors":anchors,"assembled_parcels":assembled,"entrances":entrances,"spawn_points":spawns,"scope":"preparation DTO only; A merges finite facts and validates/commits same C transaction"}
