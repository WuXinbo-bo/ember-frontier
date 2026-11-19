extends Node3D
## Public A/B hint DTO only: depth-tested bounds, feet pads and direction marks.
## No pick, physics, authorization, second building mesh or reason-based guesses.
const Builder=preload("res://scripts/buildings/building_mesh.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const SCHEMA="afterglow-world-view-hints-v1"
const COLORS={"selected":Color(.82,.66,.35),"valid":Color(.48,.69,.54),"invalid":Color(.87,.36,.27),"input":Color(.52,.73,.76),"output":Color(.86,.67,.36),"service":Color(.73,.73,.63),"conflict":Color(.91,.31,.23)}
var _materials:Dictionary={}
var _selected:MeshInstance3D
var _placement:MeshInstance3D
var _signature:=""
var _stats:Dictionary={"available":false,"selected":false,"placement":false,"ports":0,"conflicts":0,"updates":0,"issues":[]}

static func _number(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))
static func _integer(v:Variant)->bool:return _number(v) and float(v)==floorf(float(v))
static func _point(v:Variant)->Variant:
	if not v is Dictionary:return null
	for key:String in ["x","y","z"]:
		if not _number(v.get(key)):return null
	return Vector3(v.x,v.y,v.z)
static func _box(v:Variant)->Variant:
	if not v is Dictionary:return null
	var low:Variant=_point(v.get("min"));var high:Variant=_point(v.get("max"))
	if low==null or high==null:return null
	var size:Vector3=high-low
	if size.x<=0 or size.y<=0 or size.z<=0:return null
	return AABB(low,size)

func _ensure()->void:
	if _selected!=null:return
	for key:String in COLORS:
		var material:=StandardMaterial3D.new();material.albedo_color=COLORS[key]
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		# Default depth test is intentional: hidden walls/objects stay hidden.
		_materials[key]=material
	_selected=MeshInstance3D.new();_selected.name="SelectedBounds";add_child(_selected)
	_placement=MeshInstance3D.new();_placement.name="PlacementHints";add_child(_placement)
	_selected.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_placement.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level=true;global_transform=Transform3D.IDENTITY
	_selected.visible=false;_placement.visible=false

func clear()->void:
	_signature=""
	if _selected!=null:_selected.mesh=null;_selected.visible=false
	if _placement!=null:_placement.mesh=null;_placement.visible=false
	_stats.available=false;_stats.selected=false;_stats.placement=false;_stats.ports=0;_stats.conflicts=0

func _reject(code:String)->bool:
	clear();_stats.issues=[code];return false

func update(dto:Dictionary,world_id:String,revision:int)->bool:
	if not is_inside_tree():return _reject("HINT_TREE_REQUIRED")
	_ensure();_stats.issues=[]
	if dto.get("schema")!=SCHEMA or world_id.is_empty() or dto.get("world_id")!=world_id or not _integer(dto.get("world_revision")) or dto.world_revision!=revision:return _reject("HINT_WORLD_OR_REVISION_INVALID")
	var selected:Variant=dto.get("selected");var placement:Variant=dto.get("placement")
	if not selected is Dictionary or not placement is Dictionary:return _reject("HINT_ARRAY_SHAPE_INVALID")
	# Revision validates authority freshness, not a reason to rebuild identical rods.
	var key:String=var_to_str([selected,placement])
	if key==_signature:return true
	var selected_builder:=Builder.new();var placement_builder:=Builder.new()
	var selected_live:=false;var placement_live:=false;var port_count:int=0;var conflict_count:int=0
	if not selected.is_empty():
		if selected.get("kind") not in ["module","water","npc","container"] or not selected.get("id") is String or selected.id.is_empty() or not selected.get("visible") is bool:return _reject("SELECTED_IDENTITY_INVALID")
		if selected.visible:
			var bounds:Variant=_box(selected.get("bounds"))
			if bounds==null:return _reject("SELECTED_BOUNDS_INVALID")
			_corners(selected_builder,bounds,"selected");selected_live=true
	if not placement.is_empty():
		var request:Variant=placement.get("request");var preview:Variant=placement.get("preview");var turn:Variant=placement.get("quarter_turn")
		if placement.get("active")!=true or placement.get("world_revision")!=revision or not request is Dictionary or not preview is Dictionary or not _integer(turn) or turn<0 or turn>3:return _reject("PLACEMENT_IDENTITY_INVALID")
		if request.get("kind")!="module.plan" or request.get("target_id")!=placement.get("module_id") or str(placement.get("module_id","")).is_empty() or not request.get("payload") is Dictionary or request.payload.get("quarter_turn")!=turn or request.payload.get("definition_id")!=preview.get("definition_id"):return _reject("PLACEMENT_REQUEST_MISMATCH")
		var bounds:Variant=_box(preview.get("footprint"));var ports:Variant=preview.get("ports");var conflicts:Variant=preview.get("conflicts",[])
		if bounds==null or not preview.get("ok") is bool or not ports is Array or ports.size()>64 or not conflicts is Array or conflicts.size()>128:return _reject("PLACEMENT_GEOMETRY_INVALID")
		var style:String="valid" if preview.ok else "invalid"
		_ring(placement_builder,bounds,style)
		var center:Vector3=bounds.get_center();center.y=bounds.position.y+.045
		_arrow(placement_builder,center,Geometry.rotate(Vector3.FORWARD,int(turn)),minf(.9,minf(bounds.size.x,bounds.size.z)*.35),style)
		var seen:Dictionary={}
		for port:Variant in ports:
			if not port is Dictionary or not port.get("id") is String or port.id.is_empty() or seen.has(port.id):return _reject("PORT_ID_INVALID")
			seen[port.id]=true
			var point:Variant=_point(port.get("location"));var normal:Variant=_point(port.get("normal"));var uses:Variant=port.get("use_points")
			if point==null or normal==null or not uses is Array or uses.size()>32:return _reject("PORT_GEOMETRY_INVALID")
			var purpose:String=str(port.get("purpose","service"));var color:String=purpose if purpose in ["input","output"] else "service"
			var clearance:Variant=port.get("clearance",{})
			var radius:Variant=clearance.get("radius") if clearance is Dictionary else null
			if _number(radius) and float(radius)>0:
				_ring(placement_builder,AABB(point-Vector3(float(radius),-.035,float(radius)),Vector3(float(radius)*2,.05,float(radius)*2)),color)
			else:_mark(placement_builder,point+Vector3.UP*.06,.14,color)
			var direction:Vector3=normal;direction.y=0
			if direction.length_squared()>.00001:_arrow(placement_builder,point+Vector3.UP*.065,(-direction if purpose=="input" else direction).normalized(),.42,color)
			for use:Variant in uses:
				var at:Variant=_point(use)
				if at==null:return _reject("PORT_USE_POINT_INVALID")
				_mark(placement_builder,at+Vector3.UP*.045,.10,color)
			port_count+=1
		for conflict:Variant in conflicts:
			if not conflict is Dictionary:return _reject("CONFLICT_DTO_INVALID")
			var at:Variant=_point(conflict.get("point"));var box:Variant=_box(conflict.get("bounds"))
			# An ID/reason alone does not authorize guessed coordinates.
			if at==null and box==null:continue
			if box!=null:_corners(placement_builder,box,"conflict")
			if at!=null:_mark(placement_builder,at+Vector3.UP*.07,.22,"conflict")
			conflict_count+=1
		placement_live=true
	_selected.mesh=selected_builder.mesh(_materials) if selected_live else null;_selected.visible=selected_live
	_placement.mesh=placement_builder.mesh(_materials) if placement_live else null;_placement.visible=placement_live
	_stats.available=true;_stats.selected=selected_live;_stats.placement=placement_live;_stats.ports=port_count;_stats.conflicts=conflict_count;_stats.updates+=1
	_signature=key
	return true

static func _bar(builder:RefCounted,a:Vector3,b:Vector3,width:float,key:String)->void:
	var length:float=a.distance_to(b)
	if length<.00001:return
	var direction:Vector3=(b-a)/length
	var helper:Vector3=Vector3.UP if absf(direction.y)<.95 else Vector3.RIGHT
	var side:Vector3=helper.cross(direction).normalized();var up:Vector3=direction.cross(side).normalized()
	var basis:=Basis(side,up,direction)
	builder.box(AABB(Vector3(-width/2,-width/2,0),Vector3(width,width,length)),Transform3D(basis,a),key,1.0)

static func _ring(builder:RefCounted,bounds:AABB,key:String)->void:
	var y:float=bounds.position.y+.025;var low:Vector3=bounds.position;var high:Vector3=bounds.end
	var points:Array=[Vector3(low.x,y,low.z),Vector3(high.x,y,low.z),Vector3(high.x,y,high.z),Vector3(low.x,y,high.z)]
	for i:int in 4:_bar(builder,points[i],points[(i+1)%4],.045,key)

static func _corners(builder:RefCounted,bounds:AABB,key:String)->void:
	for x:float in [bounds.position.x,bounds.end.x]:
		for y:float in [bounds.position.y,bounds.end.y]:
			for z:float in [bounds.position.z,bounds.end.z]:
				var at:=Vector3(x,y,z)
				var direction:=Vector3(1 if x==bounds.position.x else -1,1 if y==bounds.position.y else -1,1 if z==bounds.position.z else -1)
				_bar(builder,at,at+Vector3(direction.x*minf(.45,bounds.size.x*.25),0,0),.035,key)
				_bar(builder,at,at+Vector3(0,direction.y*minf(.4,bounds.size.y*.25),0),.035,key)
				_bar(builder,at,at+Vector3(0,0,direction.z*minf(.45,bounds.size.z*.25)),.035,key)

static func _arrow(builder:RefCounted,at:Vector3,direction:Vector3,length:float,key:String)->void:
	var end:Vector3=at+direction*length;var side:Vector3=Vector3.UP.cross(direction).normalized()
	_bar(builder,at,end,.05,key)
	for sign_value:float in [-1,1]:_bar(builder,end,end-direction*length*.28+side*length*.24*sign_value,.05,key)

static func _mark(builder:RefCounted,point:Vector3,size:float,key:String)->void:
	_bar(builder,point-Vector3(size,0,size),point+Vector3(size,0,size),.045,key)
	_bar(builder,point-Vector3(size,0,-size),point+Vector3(size,0,-size),.045,key)

func statistics()->Dictionary:return _stats.duplicate(true)
