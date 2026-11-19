extends RefCounted
## Immutable wall recipe -> shared-material render details only. These closed
## shutters do not promise an enterable door, inventory or a working machine.
const G=preload("res://scripts/buildings/building_geometry.gd")
static func add(builder:RefCounted,part:Dictionary,surfaces:Dictionary)->bool:
	var p:Variant=part.get("quality_facade")
	if not p is Dictionary or p.get("version")!="r34-module-facade-v2":return false
	var s:Vector3=G.point(p.local_size);var normal:Vector3=G.point(p.normal)
	if not s.is_finite() or not normal.is_finite() or normal.y!=0 or absf(normal.x)+absf(normal.z)!=1:return false
	var width:float=s.x if absf(normal.z)>0.5 else s.z;var height:float=s.y
	if width<0.5 or height<1.8:return false
	var q:int=int(p.get("quarter_turn",0));var tangent:=Vector3(normal.z,0,-normal.x)
	var basis:=Basis(G.rotate(Vector3.RIGHT,q),Vector3.UP,G.rotate(Vector3.BACK,q))
	var origin:Vector3=s/2+normal*(s.z/2 if absf(normal.z)>0.5 else s.x/2);origin.y=0
	var rotated_min:Vector3=Vector3.ZERO.min(G.rotate(s,q))
	var transform:=Transform3D(basis*Basis(tangent,Vector3.UP,normal),basis*origin-rotated_min)
	var wood:="b_wood_aged";var metal:="painted_metal"
	_box(builder,transform,Vector3(0,0.13,0.025),Vector3(width,0.26,0.05),"old_brick",surfaces)
	_box(builder,transform,Vector3(0,height-0.10,0.035),Vector3(width,0.16,0.07),wood,surfaces)
	for side:float in [-1.0,1.0]:
		_box(builder,transform,Vector3(side*(width/2-0.07),height/2,0.03),Vector3(0.14,height,0.06),wood,surfaces)
	var style:String=str(p.style)
	# Window group placement depends on actual wall width, not camera facing.
	# Opaque boards sit in front of the unchanged real wall surface.
	var count:int=2 if width>3.4 else 1
	var window_width:float=minf(0.92,width-0.36)
	for index:int in count:
		var x:float=0.0 if count==1 else (-0.24 if index==0 else 0.24)*width
		var y:float=minf(1.60,height-0.56);var h:float=0.78 if style=="home" else 0.52
		_box(builder,transform,Vector3(x,y,0.035),Vector3(window_width+0.14,h+0.14,0.07),metal,surfaces)
		for board:int in 4:
			_box(builder,transform,Vector3(x+(float(board)-1.5)*window_width/4,y,0.09),Vector3(window_width/4-0.018,h,0.07),wood,surfaces)
		for side:float in [-1.0,1.0]:
			_box(builder,transform,Vector3(x+side*(window_width/2+0.05),y,0.09),Vector3(0.10,h+0.24,0.18),wood,surfaces)
		_box(builder,transform,Vector3(x,y-h/2-0.10,0.12),Vector3(window_width+0.30,0.12,0.24),"old_brick",surfaces)
		_box(builder,transform,Vector3(x,y+h/2+0.10,0.08),Vector3(window_width+0.26,0.12,0.16),wood,surfaces)
		if style=="home":
			# A simple service latch, not an opening or a second authority.
			_box(builder,transform,Vector3(x,y,0.14),Vector3(0.07,0.20,0.04),metal,surfaces)
	return true
static func _box(builder:RefCounted,transform:Transform3D,p:Vector3,s:Vector3,m:String,surfaces:Dictionary)->void:
	builder.box(AABB(p-s/2,s),transform,m,float(surfaces.get(m,{}).get("tile_meters",2.0)))
