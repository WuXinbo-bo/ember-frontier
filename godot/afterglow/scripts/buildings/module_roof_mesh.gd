extends RefCounted
## Whole roofs reuse BuildingMesh. Slopes/eaves/ridge are render-derived,
## never separate authoritative tiles. UVs use true slant metres.
const G=preload("res://scripts/buildings/building_geometry.gd")
const VERSION:="r34-gable-roof-mesh-v1"

static func add(builder:RefCounted,part:Dictionary,surfaces:Dictionary)->bool:
	var p:Variant=part.get("roof_mesh")
	if not p is Dictionary or p.get("version")!=VERSION:return false
	var s:Variant=p.get("local_size");var rise:Variant=p.get("rise");var thickness:Variant=p.get("thickness")
	if not s is Dictionary or not G.point(s).is_finite() or not (rise is int or rise is float) or not (thickness is int or thickness is float):return false
	var size:Vector3=G.point(s)
	var meters:float=float(surfaces.get(str(part.material),{}).get("tile_meters",2.0))
	if size.x<=0 or size.z<=0 or not is_finite(float(rise)) or not is_finite(float(thickness)) or float(rise)<=0 or float(thickness)<=0 or size.y<float(rise)+float(thickness) or meters<=0:return false
	var q:int=posmod(int(p.get("quarter_turn",0)),4)
	var rot:=Basis(G.rotate(Vector3.RIGHT,q),Vector3.UP,G.rotate(Vector3.BACK,q))
	var lo:Vector3=Vector3.ZERO.min(G.rotate(size,q))
	var transform:=Transform3D(rot,-lo)
	var w:float=size.x;var d:float=size.z;var t:float=thickness;var h:float=rise
	var surface:String=str(part.material);var trim:String=str(p.get("trim_material","b_wood_aged"))
	var trim_meters:float=float(surfaces.get(trim,{}).get("tile_meters",2.0))
	# local min includes underside. Ridge caps stay inside the member envelope.
	for side:float in [-1.0,1.0]:
		var eave_z:float=0.0 if side<0 else d
		var a:=Vector3(0,t,eave_z);var b:=Vector3(w,t,eave_z)
		var c:=Vector3(w,h+t,d/2);var e:=Vector3(0,h+t,d/2)
		var slope_length:float=Vector2(d/2,h).length()
		var normal:=Vector3(0,d/2,side*h).normalized()
		builder.quad([a,b,c,e],normal,transform,surface,-1,Rect2(0,0,w/meters,slope_length/meters))
		builder.quad([e-Vector3.UP*t,c-Vector3.UP*t,b-Vector3.UP*t,a-Vector3.UP*t],-normal,transform,trim,-1,Rect2(0,0,w/trim_meters,slope_length/trim_meters))
		builder.quad([a-Vector3.UP*t,b-Vector3.UP*t,b,a],Vector3(0,0,side),transform,trim,-1,Rect2(0,0,w/trim_meters,t/trim_meters))
		for end:int in 2:
			var x:float=0.0 if end==0 else w
			var aa:=Vector3(x,t,eave_z);var bb:=Vector3(x,h+t,d/2)
			builder.quad([aa-Vector3.UP*t,bb-Vector3.UP*t,bb,aa],Vector3.LEFT if end==0 else Vector3.RIGHT,transform,trim,-1,Rect2(0,0,slope_length/trim_meters,t/trim_meters))
	# Thin capped ridge: one shared-material box, no per-tile nodes/entities.
	builder.box(AABB(Vector3(0,h+t-0.025,d/2-0.075),Vector3(w,0.09,0.15)),transform,surface,meters)
	if p.get("open_frame",false):
		# Exposed ties and king posts belong to the same mesh/material groups.
		# They fit wholly in the roof proxy, without adding World entities.
		for end:float in [0.28,w-0.28]:
			builder.box(AABB(Vector3(end-0.055,0,d*0.10),Vector3(0.11,0.10,d*0.80)),transform,trim,trim_meters)
			builder.box(AABB(Vector3(end-0.055,0,d/2-0.055),Vector3(0.11,h,0.11)),transform,trim,trim_meters)
	if p.get("gable",false):
		var wall:String=str(p.get("gable_material","cream_plaster"))
		var wall_inset:float=float(p.get("gable_inset",0.28))
		for end:int in 2:
			var x:float=wall_inset if end==0 else w-wall_inset
			_triangle(builder,[Vector3(x,0,wall_inset),Vector3(x,0,d-wall_inset),Vector3(x,h,d/2)],Vector3.LEFT if end==0 else Vector3.RIGHT,transform,wall,float(surfaces.get(wall,{}).get("tile_meters",2.0)))
	return true

static func _triangle(builder:RefCounted,points:Array,normal:Vector3,transform:Transform3D,material:String,meters:float)->void:
	if not builder.groups.has(material):builder.groups[material]={"v":PackedVector3Array(),"n":PackedVector3Array(),"uv":PackedVector2Array(),"i":PackedInt32Array()}
	var g:Dictionary=builder.groups[material];var offset:int=g.v.size()
	for p:Vector3 in points:
		g.v.append(transform*p);g.n.append(transform.basis*normal);g.uv.append(Vector2(p.z,p.y)/meters)
	for i:int in 3:g.i.append(offset+i)
