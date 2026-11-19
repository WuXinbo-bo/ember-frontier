extends RefCounted
## Explicit additive v2 geometry. Existing v1 definitions never dispatch here.
const G=preload("res://scripts/buildings/building_geometry.gd")
const IDS={
	"r34.module.repair_shed_v3":"r34.module.repair_shed_v2",
	"r34.module.woodshop_long_v3":"r34.module.woodshop_long_v2",
	"r34.module.woodshop_yard_v3":"r34.module.woodshop_long_v2",
	"r34.module.home_court_v3":"r34.module.home_court_v2",
	"r34.module.home_roadside_v3":"r34.module.home_roadside_v2",
	"r34.module.warehouse_long_v3":"r34.module.warehouse_long_v2",
	"r34.module.warehouse_court_v3":"r34.module.warehouse_court_v2"}
var rows:Array=[]
static func supports(d:Dictionary)->bool:
	return IDS.has(d.get("id")) and d.get("geometry_version")==str(d.id)+".geometry-v2"
static func parts(d:Dictionary)->Array:
	if not supports(d):return []
	var b:=new();b.design(str(d.id));return b.rows
func box(id:String,p:Vector3,s:Vector3,m:String)->Dictionary:
	var row:Dictionary={"id":id,"center":G.json_point(p),"size":G.json_point(s),"material":m,"solid":true,"atlas_cell":-1}
	rows.append(row);return row
func wall(id:String,p:Vector3,s:Vector3,m:String,normal:Vector3,style:String)->void:
	var row:=box(id,p,s,m)
	row.quality_facade={"version":"r34-module-facade-v2","normal":G.json_point(normal),"style":style,"local_size":G.json_point(s)}
func roof(id:String,p:Vector3,width:float,depth:float,eave:float,rise:float,material:String="roof_tile",gable:String="")->void:
	var thickness:=0.11
	var s:=Vector3(width,rise+thickness+0.07,depth)
	var row:=box(id,p+Vector3(0,eave+s.y/2,0),s,material)
	row.roof_mesh={"version":"r34-gable-roof-mesh-v1","local_size":G.json_point(s),"rise":rise,"thickness":thickness,"gable":not gable.is_empty(),"gable_material":gable,"gable_inset":0.28,"trim_material":"b_wood_aged"}
func room(id:String,p:Vector3,width:float,depth:float,eave:float,rise:float,material:String,style:String)->void:
	# The roof edge stays in the original footprint; walls retreat 28cm.
	# The four solid walls remain sealed service rooms, never fake interiors.
	var w:float=width-0.56;var d:float=depth-0.56;var t:=0.20
	box(id+":plinth",p+Vector3(0,0.09,0),Vector3(w,0.18,d),"old_brick")
	for side:float in [-1.0,1.0]:
		wall(id+":end:"+str(side),p+Vector3(side*(w/2-t/2),eave/2,0),Vector3(t,eave,d),material,Vector3(side,0,0),style)
		if side>0 and style=="machine":
			# A real low machinery recess, not a box intersecting a full wall.
			# The 1.24m header plus the drive block prohibit a body-sized doorway.
			var left:float=1.04-p.x;var right:float=2.26-p.x;var z:float=d/2-t/2
			wall(id+":rear-left",p+Vector3((-w/2+left)/2,eave/2,z),Vector3(left+w/2,eave,t),material,Vector3.BACK,style)
			box(id+":rear-right",p+Vector3((right+w/2)/2,eave/2,z),Vector3(w/2-right,eave,t),material)
			box(id+":drive-header",p+Vector3((left+right)/2,(1.24+eave)/2,z),Vector3(right-left,eave-1.24,t),material)
		else:wall(id+(":front" if side<0 else ":rear"),p+Vector3(0,eave/2,side*(d/2-t/2)),Vector3(w,eave,t),material,Vector3(0,0,side),style)
	roof(id+":roof",p,width,depth,eave,rise,"roof_tile",material)
func shed(id:String,p:Vector3,width:float,depth:float,eave:float,rise:float,surface:String="zinc")->void:
	# Four posts/headers are real, the diagonal braces and roof trims are mesh.
	for side:float in [-1.0,1.0]:
		for end:float in [-1.0,1.0]:
			var pos:=p+Vector3(side*(width/2-0.30),0,end*(depth/2-0.30))
			box(id+":foot:%s:%s"%[side,end],pos+Vector3(0,0.14,0),Vector3(0.28,0.28,0.28),"old_brick")
			box(id+":post:%s:%s"%[side,end],pos+Vector3(0,eave/2,0),Vector3(0.16,eave,0.16),"b_wood_aged")
		box(id+":header:"+str(side),p+Vector3(0,eave-0.08,side*(depth/2-0.30)),Vector3(width-0.44,0.16,0.18),"b_wood_aged")
	roof(id+":roof",p,width,depth,eave,rise,surface)
	rows[-1].roof_mesh.open_frame=true
func machine()->void:
	# Same tooth/bed/drive anchor as the parent, not a second work station.
	box("saw-bed",Vector3(0,0.77,-1.97),Vector3(1.44,0.16,0.50),"wood_floor")
	for x:float in [-0.57,0.57]:
		box("saw-leg:"+str(x),Vector3(x,0.36,-1.97),Vector3(0.16,0.72,0.45),"painted_metal")
		box("saw-guide:"+str(x),Vector3(x,1.12,-2.03),Vector3(0.07,0.45,0.15),"painted_metal")
	box("fixed-power",Vector3(1.65,0.56,1.85),Vector3(0.85,0.95,0.55),"zinc")
	box("power-base",Vector3(1.65,0.10,1.85),Vector3(1.05,0.20,0.70),"concrete")
func design(id:String)->void:
	match id:
		"r34.module.repair_shed_v3":
			# BC04 retains its one original bench and all three service points.
			shed("repair-open-frame",Vector3.ZERO,4.0,3.0,2.46,0.72,"roof_tile")
			box("repair-rear",Vector3(0,1.23,1.26),Vector3(3.44,2.46,0.20),"b_wood_aged")
			for side:float in [-1.0,1.0]:
				wall("repair-side:"+str(side),Vector3(side*1.66,1.23,0),Vector3(0.20,2.46,2.24),"b_wood_aged",Vector3(side,0,0),"store")
			box("repair-rear-plinth",Vector3(0,0.09,1.07),Vector3(3.7,0.18,0.55),"old_brick")
			var family:=preload("res://scripts/modules/module_family_geometry.gd").new()
			family.rack("rear-empty-rack",Vector3(0,0,1.01),2.4)
			rows.append_array(family.rows)
			var backboard:=box("metal-backboard",Vector3(0,1.73,1.12),Vector3(1.55,0.64,0.08),"zinc")
			backboard.solid=false
		"r34.module.woodshop_long_v3":
			# Wide enclosed rear workshop + lower open working shed at the saw.
			room("main-workroom",Vector3(0,0,1.06),6.0,2.38,2.78,0.98,"b_wood_aged","machine")
			shed("working-shed",Vector3(0,0,-1.08),5.9,2.34,2.22,0.58)
			machine()
		"r34.module.woodshop_yard_v3":
			# Same services and body reserve, L massing leaves the actual front yard.
			room("rear-workroom",Vector3(0.7,0,1.17),4.6,2.16,2.72,0.98,"cream_plaster","machine")
			shed("left-working-wing",Vector3(-1.1,0,-1.08),3.8,2.34,2.24,0.64)
			machine()
		"r34.module.home_court_v3":
			room("main-home",Vector3(0,0,1.5),6.0,3.0,2.94,1.00,"cream_plaster","home")
			room("low-home-wing",Vector3(-1.96,0,-1.40),2.08,3.2,2.23,0.70,"old_brick","home")
			shed("veranda",Vector3(0.98,0,-0.84),3.25,1.60,2.18,0.43)
		"r34.module.home_roadside_v3":
			room("road-main-home",Vector3(0,0,0.44),5.0,3.12,2.93,1.02,"cream_plaster","home")
			shed("road-entry-porch",Vector3(-0.66,0,-1.54),2.18,0.92,2.20,0.39)
		"r34.module.warehouse_long_v3":
			# Low broad roof and truly open front loading bays, no fake goods.
			shed("long-loading-bay",Vector3(-0.64,0,0),4.72,4.0,2.43,0.84,"roof_tile")
			room("store-end-room",Vector3(2.18,0,0),1.64,4.0,2.40,0.74,"b_wood_aged","store")
		"r34.module.warehouse_court_v3":
			room("rear-store",Vector3(0,0,1.68),6.0,2.64,2.76,0.94,"b_wood_aged","store")
			shed("side-loading-wing",Vector3(-1.84,0,-1.32),2.32,3.36,2.21,0.65,"roof_tile")
