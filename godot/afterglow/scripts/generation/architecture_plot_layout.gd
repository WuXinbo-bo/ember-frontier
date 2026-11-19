extends RefCounted
## Read-only metre layout derived from the caller's authoritative definitions.
## No catalog, world, terrain edit, permit, resident, stock or generation version.
## The caller must still prove terrain support, current occupancy and access in
## the original module planner. A suggested pad never flattens/reserves a cell.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const VERSION:="r34-architecture-plots-v1"
const PATH_WIDTH:=1.6
const MAX_PLOTS:=64

static func plot(definition:Dictionary,position:Vector3,quarter_turn:int,court_points:Array=[])->Dictionary:
	if not position.is_finite() or quarter_turn not in [0,1,2,3] or not _definition_ok(definition):return _reject("INVALID_ARCHITECTURE_PLOT")
	if not definition.allowed_quarter_turns.any(func(q:Variant)->bool:return _integer(q) and float(q)==float(quarter_turn)):return _reject("INVALID_ARCHITECTURE_ROTATION")
	var local:=G.aabb(definition.footprint)
	var lo:=Vector2(local.position.x-1.0,local.position.z-1.0)
	var hi:=Vector2(local.end.x+1.0,local.end.z+1.0)
	var uses:Array=[]
	for port:Dictionary in definition.ports:
		for use:Array in port.use_points:
			var p:=Vector3(float(use[0]),float(use[1]),float(use[2]))
			var n:=Vector3(float(port.normal[0]),float(port.normal[1]),float(port.normal[2]))
			# Width is transverse to the approach, not a 1.6m square centred
			# on the operator. At the tool end preserve the owner's full body
			# radius; an open eave is not a solid wall or a second footprint.
			var radius:float=port.clearance.radius
			var gap:float=(p.x-local.end.x if n.x>0 else local.position.x-p.x) if absf(n.x)>0.5 else (p.z-local.end.z if n.z>0 else local.position.z-p.z)
			if gap<radius:return _reject("SERVICE_APRON_INTRUDES_FOOTPRINT")
			uses.append({"id":str(port.id),"point":p,"normal":n,"clearance":port.clearance.duplicate(true)})
			lo=lo.min(Vector2(p.x-1.0,p.z-1.0));hi=hi.max(Vector2(p.x+1.0,p.z+1.0))
	var paths:Array=[]
	var structural_parts:=Shape.parts(definition)
	var ring:Array=[Vector3(lo.x,0,lo.y),Vector3(hi.x,0,lo.y),Vector3(hi.x,0,hi.y),Vector3(lo.x,0,hi.y),Vector3(lo.x,0,lo.y)]
	paths.append(_path("outer-ring",ring,position,quarter_turn))
	var approaches:Array=[]
	for use:Dictionary in uses:
		var p:Vector3=use.point;var n:Vector3=use.normal;var join:=p
		if absf(n.x)>0.5:join.x=hi.x if n.x>0 else lo.x
		else:join.z=hi.y if n.z>0 else lo.y
		var half_width:float=maxf(PATH_WIDTH/2,float(use.clearance.radius))
		var half_size:=Vector3(float(use.clearance.radius),0,half_width) if absf(n.x)>0.5 else Vector3(half_width,0,float(use.clearance.radius))
		var low:Vector3=join.min(p)-half_size
		var high:Vector3=join.max(p)+half_size+Vector3(0,float(use.clearance.height),0)
		var throat:=AABB(low,high-low)
		for part:Dictionary in structural_parts:
			if part.solid and G.overlap(throat,AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))):return _reject("SERVICE_APPROACH_INTRUDES_STRUCTURE")
		var path:=_path("service:"+str(use.id)+":"+str(approaches.size()),[join,p],position,quarter_turn)
		path.clearance_bounds=_box(throat,position,quarter_turn)
		path.end_radius=use.clearance.radius;path.headroom=use.clearance.height
		paths.append(path)
		approaches.append({"port_id":use.id,"use_point":_point(p,position,quarter_turn),"ring_join":_point(join,position,quarter_turn),"normal":G.json_point(G.rotate(n,quarter_turn)),"clearance":use.clearance.duplicate(true),"width":PATH_WIDTH,"clearance_bounds":path.clearance_bounds.duplicate(true)})
	var pads:Array=[]
	for rect:Array in definition.foundation.pad_rectangles:
		pads.append(_rect(rect,position,quarter_turn))
		lo=lo.min(Vector2(float(rect[0]),float(rect[1])));hi=hi.max(Vector2(float(rect[2]),float(rect[3])))
	var courts:Array=[]
	for point:Variant in court_points:
		if not _array_point(point):return _reject("INVALID_COURT_PROBE")
		var p:=Vector3(float(point[0]),float(point[1]),float(point[2]))
		if p.x<local.position.x or p.x>local.end.x or p.z<local.position.z or p.z>local.end.z or not is_zero_approx(p.y):return _reject("INVALID_COURT_PROBE")
		courts.append({"position":_point(p,position,quarter_turn),"radius":0.4,"height":1.8,"status":"owner_probe_requires_current_space_validation"})
	var a:Vector3=position+G.rotate(local.position,quarter_turn)
	var b:Vector3=position+G.rotate(local.end,quarter_turn)
	return {"ok":true,"code":"OK","version":VERSION,"definition_id":definition.id,"geometry_version":definition.geometry_version,
		"architecture":definition.architecture.duplicate(true),"position":G.json_point(position),"quarter_turn":quarter_turn,
		"footprint":G.json_box(AABB(a.min(b),a.max(b)-a.min(b))),"pad_suggestions":pads,"paths":paths,"approaches":approaches,"court_probes":courts,
		"reservation_suggestion":_rect([lo.x-PATH_WIDTH/2,lo.y-PATH_WIDTH/2,hi.x+PATH_WIDTH/2,hi.y+PATH_WIDTH/2],position,quarter_turn),
		"permission":"none; original planner must validate current terrain/occupancy/cost","terrain_edits":[]}

static func layout(definitions:Array,placements:Array)->Dictionary:
	if placements.is_empty() or placements.size()>MAX_PLOTS:return _reject("INVALID_PLOT_COUNT")
	var by_id:Dictionary={}
	for definition:Variant in definitions:
		if not definition is Dictionary or not _definition_ok(definition) or by_id.has(definition.id):return _reject("INVALID_ARCHITECTURE_DEFINITIONS")
		by_id[definition.id]=definition
	var rows:Array=[];var ids:Dictionary={}
	for placement:Variant in placements:
		if not placement is Dictionary or not placement.get("id") is String or placement.id.is_empty() or ids.has(placement.id) or not by_id.has(placement.get("definition_id")):return _reject("INVALID_ARCHITECTURE_PLACEMENT")
		if not _dict_point(placement.get("position")) or not _integer(placement.get("quarter_turn")) or not placement.get("court_points",[]) is Array:return _reject("INVALID_ARCHITECTURE_PLACEMENT")
		var row:=plot(by_id[placement.definition_id],G.point(placement.position),int(placement.quarter_turn),placement.get("court_points",[]))
		if not row.ok:return row
		row.id=placement.id;row.region_id=str(placement.get("region_id",""));ids[placement.id]=true
		for other:Dictionary in rows:
			if row.region_id==other.region_id and _rect_overlap(row.reservation_suggestion,other.reservation_suggestion):return _reject("PLOT_APPROACH_OVERLAP")
		rows.append(row)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return str(a.id)<str(b.id))
	return {"ok":true,"code":"OK","version":VERSION,"plots":rows,"world_changes":[],"scope":"read-only layout; not generation or construction approval"}

static func _definition_ok(d:Dictionary)->bool:
	if not d.get("id") is String or not d.get("geometry_version") is String or d.geometry_version!=str(d.id)+".geometry-v1" or not d.get("architecture") is Dictionary or d.architecture.get("set")!="r34-architecture-30-v1":return false
	if not d.get("footprint") is Dictionary or not _dict_point(d.footprint.get("min")) or not _dict_point(d.footprint.get("max")):return false
	var bounds:=G.aabb(d.footprint)
	if bounds.size.x<=0 or bounds.size.y<=0 or bounds.size.z<=0 or not is_zero_approx(bounds.position.y):return false
	if not d.get("foundation") is Dictionary or not d.foundation.get("pad_rectangles") is Array or d.foundation.pad_rectangles.is_empty():return false
	for rect:Variant in d.foundation.pad_rectangles:
		if not rect is Array or rect.size()!=4:return false
		for number:Variant in rect:
			if not _number(number):return false
		if rect[2]<=rect[0] or rect[3]<=rect[1]:return false
	if not d.get("allowed_quarter_turns") is Array or d.allowed_quarter_turns.is_empty() or not d.get("ports") is Array or d.ports.is_empty():return false
	var ids:Dictionary={}
	for port:Variant in d.ports:
		if not port is Dictionary or not port.get("id") is String or ids.has(port.id) or not _array_point(port.get("position")) or not _array_point(port.get("normal")) or not port.get("use_points") is Array or port.use_points.is_empty():return false
		ids[port.id]=true
		var n:Array=port.normal
		if not is_zero_approx(float(n[1])) or not ((absf(float(n[0]))==1 and is_zero_approx(float(n[2]))) or (absf(float(n[2]))==1 and is_zero_approx(float(n[0])))):return false
		if not port.get("clearance") is Dictionary or not _number(port.clearance.get("radius")) or not _number(port.clearance.get("height")) or float(port.clearance.radius)<0.4 or float(port.clearance.height)<1.8 or not _number(port.get("width")) or float(port.width)<PATH_WIDTH:return false
		for use:Variant in port.use_points:
			if not _array_point(use) or not is_zero_approx(float(use[1])):return false
	return true

static func _path(id:String,points:Array,origin:Vector3,turn:int)->Dictionary:
	var result:Array=[]
	for p:Vector3 in points:result.append(_point(p,origin,turn))
	return {"id":id,"points":result,"width":PATH_WIDTH,"headroom":1.8,"status":"requires_current_support_and_space_validation"}
static func _point(p:Vector3,origin:Vector3,turn:int)->Dictionary:return G.json_point(origin+G.rotate(p,turn))
static func _box(b:AABB,origin:Vector3,turn:int)->Dictionary:
	var a:=origin+G.rotate(b.position,turn);var c:=origin+G.rotate(b.end,turn)
	return G.json_box(AABB(a.min(c),a.max(c)-a.min(c)))
static func _rect(r:Array,origin:Vector3,turn:int)->Array:
	var a:Vector3=origin+G.rotate(Vector3(float(r[0]),0,float(r[1])),turn)
	var b:Vector3=origin+G.rotate(Vector3(float(r[2]),0,float(r[3])),turn)
	return [minf(a.x,b.x),minf(a.z,b.z),maxf(a.x,b.x),maxf(a.z,b.z)]
static func _rect_overlap(a:Array,b:Array)->bool:return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
static func _number(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))
static func _integer(v:Variant)->bool:return _number(v) and float(v)==floorf(float(v))
static func _array_point(v:Variant)->bool:return v is Array and v.size()==3 and _number(v[0]) and _number(v[1]) and _number(v[2])
static func _dict_point(v:Variant)->bool:return v is Dictionary and _number(v.get("x")) and _number(v.get("y")) and _number(v.get("z"))
static func _reject(code:String)->Dictionary:return {"ok":false,"code":code}
