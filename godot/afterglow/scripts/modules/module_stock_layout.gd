extends RefCounted
## Disposable, metre-sized stock bays. No inventory, colliders or persisted
## geometry are created here. Only immutable catalog geometry is cached.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const DEPTH:=0.40
const HEIGHT:=0.38
const GAP:=0.025
const MARGIN:=0.10
static var _mutex:Mutex=Mutex.new()
static var _plans:Dictionary={}

static func local_plan(d:Dictionary,ruined:bool=false)->Dictionary:
	var key:String=str(d.id)+":"+str(d.geometry_version)+":"+str(ruined)
	_mutex.lock()
	if not _plans.has(key):_plans[key]=_build(d,ruined)
	var result:Dictionary=_plans[key].duplicate(true)
	_mutex.unlock()
	return result

static func bay(v:Dictionary,d:Dictionary,buffer_id:String,item_id:String)->Dictionary:
	var plan:=local_plan(d,v.status=="ruined")
	var local:Dictionary=plan.get(buffer_id+":"+item_id,{})
	if local.is_empty():return {}
	return _world_bay(v,local)

static func projection(v:Dictionary,d:Dictionary)->Dictionary:
	var plan:=local_plan(d,v.status=="ruined");var result:Dictionary={}
	for key:String in plan:result[key]=_world_bay(v,plan[key])
	return result

static func _world_bay(v:Dictionary,local:Dictionary)->Dictionary:
	var q:int=posmod(int(v.quarter_turn)+int(local.quarter_turn),4)
	var position:Vector3=G.point(Shape.at(v,G.point(local.position)))
	var forward:=G.rotate(Vector3(0,0,-1),q)
	return {"anchor":{"position":[position.x,position.y,position.z],"forward":[forward.x,forward.z],"quarter_turn":q},"extent":local.extent.duplicate(),"support":local.support,"layout_version":1}

static func visibility(query:RefCounted,v:Dictionary,bay:Dictionary)->Dictionary:
	var a:Array=bay.anchor.position;var e:Array=bay.extent
	var box:=_bounds(Vector3(a[0],a[1],a[2]),int(bay.anchor.quarter_turn),Vector3(e[0],e[1],e[2]))
	# Same immutable BuildingSpace as movement/edits. A transparent solid is
	# still physical; opacity is deliberately irrelevant to cargo placement.
	if not query.terrain_clear(str(v.region),box.grow(-0.001)):
		return {"visual_available":false,"visual_reason":"occupied"}
	for entry:Dictionary in query.candidates(str(v.region),box.position,box.end,0.0):
		if G.overlap(entry.bounds,box):return {"visual_available":false,"visual_reason":"occupied"}
	var supported:bool=query.terrain_supports(str(v.region),box) if bay.support=="ground" else false
	if bay.support!="ground":
		for member:Dictionary in v.members:
			var entity:Dictionary=query.world.entity(str(member.id))
			if entity.is_empty() or not entity.get("data",{}).get("solid",false):continue
			var fixed:=G.aabb(entity.bounds)
			if absf(fixed.end.y-box.position.y)<0.001 and fixed.position.x<=box.position.x+0.001 and fixed.end.x>=box.end.x-0.001 and fixed.position.z<=box.position.z+0.001 and fixed.end.z>=box.end.z-0.001:
				supported=true;break
	return {"visual_available":supported,"visual_reason":"" if supported else "unsupported"}

static func _build(d:Dictionary,ruined:bool)->Dictionary:
	var result:Dictionary={}
	for b:Dictionary in d.buffer_specs:
		# This surface is physically behind the real legacy workbench. Its new
		# close workport has no room for a pile between the worker and the bench.
		if not ruined and d.get("compact_kind") in ["warehouse","warehouse_upgrade"] and b.id=="storage":
			var shelves:Array=[["log","timber"],["scrap","food","water"],["cloth","tool_handle","axe_head"],["r34:salvaged_drive_unit"]]
			if d.get("village_family_art")=="warehouse" and b.limits.has("timber"):
				shelves[0]=["log"]
				_put(result,b.id,"timber",Vector3(.83,0,-1.18),1,1.12,"ground",.50)
			for tier:int in shelves.size():
				var items:Dictionary={}
				for item:String in shelves[tier]:
					if b.limits.has(item):items[item]=b.limits[item]
				if not items.is_empty():_shelf(result,{"id":b.id,"limits":items},Vector3(0,[.28,.83,1.38,1.93][tier],1.21),2.32,.60)
		elif not ruined and d.get("design_id")=="BC04-repair-shed" and b.id=="tools":
			# The rear plinth is 1cm above the lowest shelf. Use that actual
			# surface, forward of the thick rear wall and between the uprights.
			_shelf(result,b,Vector3(0,0.18,0.965),2.16,0.34)
		elif not ruined and d.get("design_id")=="BC06-supply-roadside" and b.id=="supplies":
			# One long bottom bay and two pairs above, all on actual empty shelves.
			var keys:Array=b.limits.keys()
			for item:String in keys:
				var tier:int=0 if item=="timber" else 1+int(keys.filter(func(k:String)->bool:return k!="timber").find(item))/2
				var index:int=keys.filter(func(k:String)->bool:return k!="timber").find(item)
				var p:=Vector3(-0.7,[0.17,0.70,1.22][tier],-1.60)
				if item!="timber":p.x+=-0.29 if index%2==0 else 0.29
				_put(result,b.id,item,p,1,1.20 if item=="timber" else 0.55,"fixed_surface")
		else:_ground(result,d,b,ruined)
	return result

static func _length(item:String)->float:
	if item in ["log","timber"]:return 1.20
	if item.begins_with("book_"):return 0.36
	return 0.48

static func _minimum(item:String)->float:
	return 0.92 if item=="log" else 0.96 if item=="timber" else 0.24

static func _shelf(result:Dictionary,b:Dictionary,center:Vector3,width:float,depth:float=DEPTH)->void:
	var keys:Array=b.limits.keys();var lengths:Dictionary=_lengths(keys,width)
	var total:float=GAP*float(maxi(0,keys.size()-1))
	for item:String in keys:total+=float(lengths[item])
	var cursor:float=center.x-total/2
	for item:String in keys:
		var length:float=lengths[item]
		_put(result,b.id,item,Vector3(cursor+length/2,center.y,center.z),1,length,"fixed_surface",depth)
		cursor+=length+GAP

static func _lengths(keys:Array,width:float)->Dictionary:
	var preferred:=0.0;var minimum:=0.0
	for item:String in keys:preferred+=_length(item);minimum+=_minimum(item)
	var available:float=width-GAP*float(maxi(0,keys.size()-1))
	var ratio:float=clampf((available-minimum)/maxf(0.000001,preferred-minimum),0.0,1.0)
	var values:Dictionary={}
	for item:String in keys:values[item]=lerpf(_minimum(item),_length(item),ratio)
	return values

static func _ground(result:Dictionary,d:Dictionary,b:Dictionary,ruined:bool)->void:
	var port:Dictionary={}
	for p:Dictionary in d.ports:
		if p.id==b.port_id:port=p;break
	if port.is_empty():return
	var normal:=Vector3(port.normal[0],0,port.normal[2])
	for item:String in b.limits:
		var placed:=false
		# The service point is an access point, not the storage volume. Wrap
		# around the SAME module's graded apron where an old short side cannot
		# contain a metre-long log and boards. Never stack unsupported tiers.
		for turn:int in 4:
			var n:=G.rotate(normal,turn);var t:=Vector3(-n.z,0,n.x)
			var footprint:=G.aabb(d.footprint);var face:float=maxf(n.dot(footprint.position),n.dot(footprint.end))
			var center:Vector3=n*(face+0.015+DEPTH/2);var q:int=1 if absf(n.z)>0.5 else 0
			for span:Vector2 in _free_segments(d,n,ruined,result):
				if span.y-span.x<_minimum(item)-0.000001:continue
				var length:float=minf(_length(item),span.y-span.x)
				_put(result,b.id,item,center+t*(span.x+length/2),q,length,"ground")
				placed=true;break
			if placed:break
		if not placed:return

static func _free_segments(d:Dictionary,n:Vector3,ruined:bool,occupied:Dictionary)->Array:
	var t:=Vector3(-n.z,0,n.x)
	var footprint:=G.aabb(d.footprint)
	var minimum:float=minf(t.dot(footprint.position),t.dot(footprint.end))+MARGIN
	var maximum:float=maxf(t.dot(footprint.position),t.dot(footprint.end))-MARGIN
	var face:float=maxf(n.dot(footprint.position),n.dot(footprint.end))
	var center:Vector3=n*(face+0.015+DEPTH/2)
	var q:int=1 if absf(n.z)>0.5 else 0
	var strip:=_bounds(center+t*((minimum+maximum)/2),q,Vector3(DEPTH,HEIGHT,maximum-minimum))
	var segments:Array=[Vector2(minimum,maximum)]
	if not ruined:
		# Fixed saw legs/power bases can extend beyond old footprint records.
		# Remove their real occupied intervals instead of drawing cargo through
		# them or expanding body openings. Closed walls stay inside the strip.
		for part:Dictionary in Shape.parts(d):
			if not part.solid:continue
			var box:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))
			if not strip.intersects(box):continue
			var lo:float=minf(t.dot(box.position),t.dot(box.end))-GAP
			var hi:float=maxf(t.dot(box.position),t.dot(box.end))+GAP
			segments=_subtract(segments,lo,hi)
		# New manual architecture has the original separately-owned workbench,
		# which is not in Shape.parts. Reuse its pinned physical definition so
		# cargo cannot be drawn through that real bench or its legs. Legacy bay
		# layout is unchanged, including the original repair shelf special case.
		if d.get("architecture",{}).get("set")=="r34-architecture-30-v1" and d.shape=="manual":
			var geometry:=G.new();geometry.configure({})
			var bench:Dictionary={"definitionId":"workbench","geometryVersion":1,"quarterTurn":0,"hp":1.0,"position":G.json_point(Shape.Families.bench_offset(d))}
			for box:AABB in geometry.boxes(bench):
				if strip.intersects(box):segments=_subtract(segments,minf(t.dot(box.position),t.dot(box.end))-GAP,maxf(t.dot(box.position),t.dot(box.end))+GAP)
	for key:String in occupied:
		var prior:Dictionary=occupied[key];var e:Array=prior.extent
		var box:=_bounds(G.point(prior.position),int(prior.quarter_turn),Vector3(e[0],e[1],e[2])).grow(GAP)
		if strip.intersects(box):segments=_subtract(segments,minf(t.dot(box.position),t.dot(box.end)),maxf(t.dot(box.position),t.dot(box.end)))
	for port:Dictionary in d.ports:
		for use:Array in port.use_points:
			var p:=Vector3(use[0],use[1],use[2]);var radius:float=port.clearance.radius
			var normal_distance:float=absf(n.dot(p)-n.dot(center))-DEPTH/2
			if normal_distance<radius:segments=_subtract(segments,t.dot(p)-radius,t.dot(p)+radius)
	return segments

static func _subtract(spans:Array,lo:float,hi:float)->Array:
	var result:Array=[]
	for span:Vector2 in spans:
		if hi<=span.x or lo>=span.y:result.append(span);continue
		if lo>span.x:result.append(Vector2(span.x,lo))
		if hi<span.y:result.append(Vector2(hi,span.y))
	return result

static func _put(result:Dictionary,buffer_id:String,item:String,p:Vector3,q:int,length:float,support:String,depth:float=DEPTH)->void:
	result[buffer_id+":"+item]={"position":G.json_point(p),"quarter_turn":q,"extent":[depth,HEIGHT,length],"support":support}

static func _bounds(p:Vector3,q:int,extent:Vector3)->AABB:
	var lo:=G.rotate(Vector3(-extent.x/2,0,-extent.z/2),q)+p
	var hi:=G.rotate(Vector3(extent.x/2,extent.y,extent.z/2),q)+p
	return AABB(lo.min(hi),lo.max(hi)-lo.min(hi))
