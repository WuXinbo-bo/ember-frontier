extends RefCounted
## Bounded, native stepped sedan. One derived mesh, no vehicle simulation,
## inventory, damage or collision authority is created by this presentation.

static func box(builder:RefCounted,view:Node3D,at:Vector3,size:Vector3,material:String)->void:
	builder.box(AABB(at-size/2,size),Transform3D.IDENTITY,material,float(view.manifest.textures[material].tile_meters))

static func panel(builder:RefCounted,vertices:Array,normal:Vector3,material:String,meters:float)->void:
	# Project planar panels in metres. A trapezoid must not squash the whole
	# image to its unequal edge lengths; degenerate quad triangles share UVs.
	var tangent:Vector3=(vertices[1]-vertices[0]).normalized()
	if tangent.is_zero_approx():tangent=(vertices[3]-vertices[0]).normalized()
	var bitangent:=normal.normalized().cross(tangent).normalized()
	builder.quad(vertices,normal.normalized(),Transform3D.IDENTITY,material)
	var uv:PackedVector2Array=builder.groups[material].uv
	for i:int in 4:
		var delta:Vector3=vertices[i]-vertices[0]
		uv[uv.size()-4+i]=Vector2(delta.dot(tangent),delta.dot(bitangent))/meters
	builder.groups[material].uv=uv

static func hull(builder:RefCounted,low:Array,high:Array,material:String,meters:float)->void:
	# Equal four-corner sections, including the sloping hood/cabin side planes.
	panel(builder,[high[0],high[3],high[2],high[1]],Vector3.UP,material,meters)
	panel(builder,[low[0],low[1],low[2],low[3]],Vector3.DOWN,material,meters)
	for i:int in 4:
		var j:int=(i+1)%4
		var normal:Vector3=(high[i]-low[i]).cross(low[j]-low[i]).normalized()
		panel(builder,[low[i],low[j],high[j],high[i]],normal,material,meters)

static func wheel(builder:RefCounted,center:Vector3,side:float,tyre:String,hub:String,tyre_meters:float,hub_meters:float)->void:
	# Twelve-sided tyre around X. The mesh, not a scaled sphere or painted
	# rectangle, provides the wheel silhouette and its original tread metric.
	for i:int in 12:
		var a:=TAU*float(i)/12;var b:=TAU*float(i+1)/12
		var p:=Vector3(0,cos(a)*0.30,sin(a)*0.30)
		var q:=Vector3(0,cos(b)*0.30,sin(b)*0.30)
		var normal:=Vector3(0,cos((a+b)/2),sin((a+b)/2))
		builder.quad([center+p+Vector3(-0.095,0,0),center+p+Vector3(0.095,0,0),center+q+Vector3(0.095,0,0),center+q+Vector3(-0.095,0,0)],normal,Transform3D.IDENTITY,tyre,-1,Rect2(0,float(i)*TAU*0.30/12/tyre_meters,0.19/tyre_meters,TAU*0.30/12/tyre_meters))
		for end:float in [-1.0,1.0]:
			var origin:=center+Vector3(end*0.095,0,0)
			var u:=p/0.30;var v:=q/0.30
			panel(builder,[origin,origin,origin+q,origin+p],Vector3(end,0,0),tyre,tyre_meters)
			# Hub faces are actual small polygonal surfaces, not another wheel.
			if end==side:
				origin.x+=side*0.002
				panel(builder,[origin,origin,origin+v*0.13,origin+u*0.13],Vector3(side,0,0),hub,hub_meters)

static func assemble(builder:RefCounted,view:Node3D)->void:
	# Old authored paint/metal remain explicit reuse until the new four car
	# surfaces pass their image QA; no pending candidate is silently accepted.
	var paint:="car_paint" if view.materials.has("car_paint") else "mint_paint"
	var rust:="car_rust" if view.materials.has("car_rust") else "painted_metal"
	var tyre:="car_tyre" if view.materials.has("car_tyre") else "painted_metal"
	var window:="car_glass" if view.materials.has("car_glass") else "painted_metal"
	var meters:float=view.manifest.textures[paint].tile_meters
	box(builder,view,Vector3(0,0.34,0),Vector3(1.48,0.18,3.66),rust)
	hull(builder,[Vector3(-0.73,0.40,-1.93),Vector3(0.73,0.40,-1.93),Vector3(0.73,0.40,1.93),Vector3(-0.73,0.40,1.93)],
		[Vector3(-0.84,0.76,-1.95),Vector3(0.84,0.76,-1.95),Vector3(0.84,0.76,1.95),Vector3(-0.84,0.76,1.95)],paint,meters)
	# Hood, boot and cabin have distinct volumes and a visibly sloping profile.
	hull(builder,[Vector3(-0.83,0.76,-1.95),Vector3(0.83,0.76,-1.95),Vector3(0.78,0.76,-0.82),Vector3(-0.78,0.76,-0.82)],
		[Vector3(-0.79,0.80,-1.94),Vector3(0.79,0.80,-1.94),Vector3(0.77,0.87,-0.82),Vector3(-0.77,0.87,-0.82)],paint,meters)
	box(builder,view,Vector3(0,0.79,1.57),Vector3(1.59,0.06,0.72),paint)
	hull(builder,[Vector3(-0.77,0.77,-0.82),Vector3(0.77,0.77,-0.82),Vector3(0.77,0.77,1.23),Vector3(-0.77,0.77,1.23)],
		[Vector3(-0.64,1.47,-0.34),Vector3(0.64,1.47,-0.34),Vector3(0.64,1.47,0.69),Vector3(-0.64,1.47,0.69)],paint,meters)
	var glass_meters:float=view.manifest.textures[window].tile_meters
	panel(builder,[Vector3(-0.70,0.86,-0.765),Vector3(0.70,0.86,-0.765),Vector3(0.59,1.405,-0.39),Vector3(-0.59,1.405,-0.39)],Vector3(0,0.56,-0.83),window,glass_meters)
	panel(builder,[Vector3(0.70,0.86,1.167),Vector3(-0.70,0.86,1.167),Vector3(-0.59,1.405,0.748),Vector3(0.59,1.405,0.748)],Vector3(0,0.59,0.81),window,glass_meters)
	for side:float in [-1.0,1.0]:
		# Insets lie on the real sloping side plane. The central pillar and
		# surrounding painted frame remain geometry, rather than glass paint.
		for zs:Array in [[-0.70,0.12,-0.29,0.12],[0.22,1.10,0.22,0.64]]:
			panel(builder,[Vector3(side*0.757,0.86,zs[0]),Vector3(side*0.757,0.86,zs[1]),Vector3(side*0.653,1.405,zs[3]),Vector3(side*0.653,1.405,zs[2])],Vector3(side,0.19,0),window,glass_meters)
		box(builder,view,Vector3(side*0.854,0.66,0.12),Vector3(0.018,0.21,0.018),rust)
		for z:float in [-0.22,0.75]:box(builder,view,Vector3(side*0.854,0.72,z),Vector3(0.025,0.035,0.15),"painted_metal")
		box(builder,view,Vector3(side*0.895,0.90,-0.63),Vector3(0.09,0.09,0.16),paint)
		for z:float in [-1.29,1.29]:wheel(builder,Vector3(side*0.817,0.30,z),side,tyre,"painted_metal",float(view.manifest.textures[tyre].tile_meters),1)
		# Lower sill weathering is static aged bodywork, never a fake HP hole.
		box(builder,view,Vector3(side*0.79,0.43,0),Vector3(0.065,0.065,1.8),rust)
	for z:float in [-2.025,2.025]:
		box(builder,view,Vector3(0,0.43,z),Vector3(1.67,0.12,0.15),rust)
		for x:float in [-0.59,0.59]:box(builder,view,Vector3(x,0.65,z-0.012*signf(z)),Vector3(0.29,0.13,0.055),"ceramic" if z<0 else "old_brick")
	for x:float in [-0.30,0,0.30]:box(builder,view,Vector3(x,0.60,-2.04),Vector3(0.24,0.07,0.025),rust)
	box(builder,view,Vector3(0,0.47,-2.108),Vector3(0.36,0.095,0.012),"painted_metal")
