extends RefCounted
## Native geometry + original local model library. No generated bitmap assets.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const MeshBuilder=preload("res://scripts/buildings/building_mesh.gd")

static func box(builder:RefCounted,view:Node3D,at:Vector3,size:Vector3,material:String,turn:float=0)->void:
	var transform:=Transform3D(Basis(Vector3.UP,turn),at)
	var entry:Dictionary=view.manifest.textures[material]
	var meters:float=entry.tile_meters;var axes:Array=entry.uv.get("meters_xy",[meters,meters])
	builder.box(AABB(-size/2,size),transform,material,meters,-1,"",2,Vector2(axes[0],axes[1]))

static func cylinder(builder:RefCounted,radius:float,low:float,high:float,material:String,meters:float,cap:bool=true)->void:
	for i:int in 12:
		var a:=TAU*float(i)/12;var b:=TAU*float(i+1)/12
		var p:=Vector3(cos(a)*radius,low,sin(a)*radius);var q:=Vector3(cos(b)*radius,low,sin(b)*radius)
		var normal:=Vector3(cos((a+b)/2),0,sin((a+b)/2))
		builder.quad([p,q,q+Vector3(0,high-low,0),p+Vector3(0,high-low,0)],normal,Transform3D.IDENTITY,material,-1,Rect2(float(i)*TAU*radius/12/meters,0,TAU*radius/12/meters,(high-low)/meters))
		if cap:
			var t:=Vector3(p.x,high,p.z);var u:=Vector3(q.x,high,q.z)
			builder.quad([Vector3(0,high,0),Vector3(0,high,0),u,t],Vector3.UP,Transform3D.IDENTITY,material)

static func straw_bale(builder:RefCounted,view:Node3D,center:Vector3,size:Vector3)->void:
	# Consume C's already packaged, approved 0.6m straw surface directly.
	# Keep the original nine bale boxes/ropes; only their material and metric UV
	# change. This is not a crop-yield/stock/harvest or placement authority.
	var entry:Dictionary=view.manifest.textures.straw_fibres
	var axes:Array=entry.uv.meters_xy
	builder.box(AABB(center-size/2,size),Transform3D.IDENTITY,"straw_fibres",float(entry.tile_meters),-1,"",2,Vector2(axes[0],axes[1]))
	for x:float in [-size.x*0.27,size.x*0.27]:
		box(builder,view,center+Vector3(x,0.003,0),Vector3(0.018,size.y+0.006,size.z+0.006),"hemp_rope")

static func create(entity:Dictionary,view:Node3D)->Node3D:
	var profile:Dictionary=entity.data.dressing_profile
	var required:Dictionary={"well":["well_stone","sign_wood"],"sign":["sign_wood"],"haystack":["straw_fibres","hemp_rope"],"car":["car_paint","car_rust","car_tyre","car_glass"]}
	for id:String in required.get(str(profile.geometry),[]):view.material(id)
	var root:=Node3D.new();root.name="Dressing";root.position=Geometry.point(entity.position);root.rotation.y=-int(entity.data.quarterTurn)*PI/2
	var source:String=profile.source_model
	if not source.is_empty():
		var original:Node3D=view.model(source)
		if original!=null:
			if source=="city_roof_tank":
				view.material("tank_paint")
				preload("res://scripts/buildings/dressing_tank_surface.gd").apply(original,view.materials.tank_paint)
			original.position=Geometry.point(profile.model_offset);root.add_child(original)
	var builder:=MeshBuilder.new()
	match str(profile.geometry):
		"sign":
			# New authored 1x0.5m wood on the back board, leaving the original
			# front/sign UV intact and all geometry within the same footprint.
			box(builder,view,Vector3(0,1.55,-0.085),Vector3(2.98,1.02,0.025),"sign_wood")
			for x:float in [-1.05,1.05]:
				box(builder,view,Vector3(x,0.8,0),Vector3(0.11,1.6,0.13),"weathered_timber")
				box(builder,view,Vector3(x,0.08,0),Vector3(0.18,0.16,0.18),"stone_masonry")
		"barrel":
			cylinder(builder,0.43,0,0.97,"weathered_timber",float(view.manifest.textures.weathered_timber.tile_meters))
			for y:float in [0.12,0.79,0.94]:cylinder(builder,0.441,y,y+0.035,"painted_metal",1,false)
		"well":
			for tier:int in 3:
				for i:int in 8:
					var angle:float=TAU*(float(i)+(0.5 if tier%2 else 0))/8
					box(builder,view,Vector3(cos(angle)*0.72,0.14+tier*0.27,sin(angle)*0.72),Vector3(0.50,0.27,0.34),"well_stone",-angle)
			box(builder,view,Vector3(0,0.845,0),Vector3(1.34,0.07,1.34),"weathered_timber")
			for x:float in [-0.86,0.86]:box(builder,view,Vector3(x,1.24,0),Vector3(0.13,2.48,0.13),"weathered_timber")
			for side:int in [-1,1]:
				for step:int in 4:
					box(builder,view,Vector3(0,2.45-step*0.115,side*(0.125+step*0.25)),Vector3(2.1,0.1,0.25),"sign_wood")
		"haystack":
			for x:float in [-0.76,0.0,0.76]:
				for z:float in [-0.4,0.4]:straw_bale(builder,view,Vector3(x,0.30,z),Vector3(0.70,0.6,0.70))
			for x:float in [-0.38,0.38]:straw_bale(builder,view,Vector3(x,0.91,0),Vector3(0.70,0.60,0.70))
			straw_bale(builder,view,Vector3(0,1.328,0),Vector3(0.65,0.23,0.65))
		"car":preload("res://scripts/buildings/dressing_car.gd").assemble(builder,view)
	if not builder.groups.is_empty():
		for id:String in builder.groups:view.material(id)
		var mesh:=MeshInstance3D.new();mesh.name="NativeAssembly";mesh.mesh=builder.mesh(view.materials);root.add_child(mesh)
	root.set_meta("piece",entity)
	return root
