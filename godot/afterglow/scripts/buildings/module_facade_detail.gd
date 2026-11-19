extends RefCounted
## Versioned presentation skin on EXISTING closed module walls. No opening,
## collider, inventory or saved geometry is added or reinterpreted.
const G=preload("res://scripts/buildings/building_geometry.gd")
const VERSION:="r34-closed-facade-skin-v1"

static func add(view:Node3D,builder:RefCounted,entity:Dictionary)->bool:
	var data:Dictionary=entity.get("data",{})
	if not data.get("module_part") is Dictionary:return false
	var id:String=str(entity.id);var rear:bool=id.ends_with(":rear")
	var side:int=1 if id.ends_with(":side:1.0") else -1 if id.ends_with(":side:-1.0") else 0
	if not rear and side==0:return false
	# Existing pinned entity is authoritative even when its design changes in
	# a future catalog. This derived skin only follows its actual wall bounds.
	var owner:Dictionary={}
	var source:Variant=view.service.context.world.extension("r34:modules")
	for module:Dictionary in source.get("instances",[]) if source is Dictionary else []:
		if module.id==data.get("module_id"):owner=module;break
	if owner.is_empty() or (not str(owner.definition_id).ends_with("_v2") and owner.definition_id!="r34.module.supply_rear_v3") or owner.status not in ["operational","damaged"]:return false
	var bounds:=G.aabb(entity.bounds);var size:=bounds.size
	var q:int=int(owner.quarter_turn)
	var normal:=G.rotate(Vector3(0,0,1) if rear else Vector3(side,0,0),q)
	var tangent:=Vector3(normal.z,0,-normal.x)
	var width:float=size.x if absf(normal.z)>0.5 else size.z
	var height:float=size.y
	if width<1.2 or height<1.8:return false
	var face:Vector3=bounds.get_center()-G.point(entity.position)
	face.y=0
	face+=normal*((size.z if absf(normal.z)>0.5 else size.x)/2)
	var transform:=Transform3D(Basis(tangent,Vector3.UP,normal),face)
	var wood:String="b_wood_aged"
	var plaster:bool=str(data.module_part.material)=="cream_plaster"
	var base:String="old_brick" if plaster else "painted_metal"
	view.material(wood);view.material(base)
	# Real raised base, upper tie and corner boards break the two blank planes
	# visible to the normal camera. All sit on the closed external wall face.
	_box(view,builder,transform,Vector3(0,0.18,0.018),Vector3(width,0.30,0.036),base)
	_box(view,builder,transform,Vector3(0,height-0.12,0.028),Vector3(width,0.15,0.056),wood)
	for end:float in [-1.0,1.0]:
		_box(view,builder,transform,Vector3(end*(width/2-0.09),height/2,0.025),Vector3(0.13,height,0.05),wood)
	# Closed wooden shutters, visibly framed and opaque rather than a false
	# glass hole in an unchanged solid collision/LOS wall. Two on long walls.
	var count:int=2 if width>3.7 else 1
	for index:int in count:
		var x:float=0.0 if count==1 else (-0.23 if index==0 else 0.23)*width
		var y:float=minf(1.64,height-0.65);var w:float=minf(0.9,width*0.34);var h:float=0.84
		_box(view,builder,transform,Vector3(x,y,0.024),Vector3(w,h,0.048),base)
		for panel:int in 5:
			_box(view,builder,transform,Vector3(x+(float(panel)-2.0)*w/5.0,y,0.056),Vector3(w/5.0-0.018,h-0.08,0.05),wood)
		for edge:float in [-1.0,1.0]:
			_box(view,builder,transform,Vector3(x+edge*(w/2+0.045),y,0.054),Vector3(0.09,h+0.19,0.108),wood)
		_box(view,builder,transform,Vector3(x,y-h/2-0.055,0.085),Vector3(w+0.26,0.12,0.17),"old_brick")
		_box(view,builder,transform,Vector3(x,y+h/2+0.055,0.054),Vector3(w+0.22,0.12,0.108),wood)
		for band:float in [-0.24,0.24]:
			_box(view,builder,transform,Vector3(x,y+band,0.088),Vector3(w-0.08,0.065,0.025),"painted_metal")
	view.material("old_brick");view.material("painted_metal")
	return true

static func _box(view:Node3D,builder:RefCounted,transform:Transform3D,p:Vector3,size:Vector3,material:String)->void:
	builder.box(AABB(p-size/2,size),transform,material,float(view.manifest.textures.get(material,{}).get("tile_meters",2.0)))
