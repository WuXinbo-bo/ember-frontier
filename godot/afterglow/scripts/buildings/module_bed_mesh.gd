extends RefCounted
## Real 0.98 x 2.02m beds. Local +Z is the pillow/head end.
## The upper berth has its own mattress, rails and visible access ladder.
const MeshBuilder=preload("res://scripts/buildings/building_mesh.gd")
static func create(e:Dictionary,materials:Dictionary)->MeshInstance3D:
	var meta:Dictionary=e.data.module_bed;var y:float=float(meta.level)*1.02;var b:=MeshBuilder.new()
	b.box(AABB(Vector3(-.49,y+.32,-1.01),Vector3(.98,.12,2.02)),Transform3D.IDENTITY,"b_wood_aged",2)
	for x:float in [-.44,.37]:
		for z:float in [-.96,.89]:b.box(AABB(Vector3(x,y+.10,z),Vector3(.07,.22,.07)),Transform3D.IDENTITY,"b_wood_aged",2)
	b.box(AABB(Vector3(-.49,y+.44,.94),Vector3(.98,.30,.07)),Transform3D.IDENTITY,"b_wood_aged",2)
	if e.data.get("prepared",false):
		b.box(AABB(Vector3(-.47,y+.44,-.99),Vector3(.94,.12,1.98)),Transform3D.IDENTITY,"textile_atlas",1,0)
		b.box(AABB(Vector3(-.36,y+.56,.64),Vector3(.72,.08,.28)),Transform3D.IDENTITY,"textile_atlas",1,1)
	else:b.box(AABB(Vector3(-.46,y+.44,-.98),Vector3(.92,.04,1.96)),Transform3D.IDENTITY,"wood_floor",2)
	if int(meta.level)>0:
		for x:float in [-.49,.42]:b.box(AABB(Vector3(x,y+.59,-.96),Vector3(.07,.08,1.35)),Transform3D.IDENTITY,"b_wood_aged",2)
		for z:float in [-.91,.78]:b.box(AABB(Vector3(-.49,.10,z),Vector3(.07,y+.50,.07)),Transform3D.IDENTITY,"b_wood_aged",2)
		for x:float in [-.46,-.14]:b.box(AABB(Vector3(x,.10,-1.01),Vector3(.05,y+.40,.05)),Transform3D.IDENTITY,"b_wood_aged",2)
		for i:int in 4:b.box(AABB(Vector3(-.46,.30+i*.27,-1.01),Vector3(.37,.045,.05)),Transform3D.IDENTITY,"b_wood_aged",2)
	var n:=MeshInstance3D.new();n.name="ActualModuleBed";n.mesh=b.mesh(materials);return n
