extends RefCounted
## Additive, pinned designs. Never modifies legacy geometry-v1 silhouettes.
## Ordinary modules expose exterior service faces, not enterable fake rooms.
const G=preload("res://scripts/buildings/building_geometry.gd")
var rows:Array=[]

static func parts(d:Dictionary)->Array:
	var builder:=new();builder.design(d);return builder.rows
static func bench_offset(d:Dictionary)->Vector3:
	if (d.get("architecture",{}).get("set")=="r34-architecture-30-v1" or d.has("village_geometry")) and d.get("bench_offset") is Array:
		var p:Array=d.bench_offset
		if p.size()==3:return Vector3(p[0],p[1],p[2])
	return Vector3(0,0,-0.6) if d.get("design_id")=="BC04-repair-shed" else Vector3.ZERO
func box(id:String,p:Vector3,s:Vector3,m:String,solid:bool=true,cell:int=-1)->void:
	rows.append({"id":id,"center":G.json_point(p),"size":G.json_point(s),"material":m,"solid":solid,"atlas_cell":cell})
func volume(id:String,p:Vector3,size:Vector3,wall:String="cream_plaster",open_front:bool=false)->void:
	var w:float=size.x;var d:float=size.z;var h:float=size.y;var eaves:float=h-0.76
	# Footings remain inside the reserved footprint. A 12cm plinth has real
	# thickness; columns carry each roof independently at split-volume joins.
	if open_front:box(id+":rear-plinth",p+Vector3(0,0.09,d/2-0.43),Vector3(w-0.3,0.18,0.55),"old_brick")
	else:box(id+":plinth",p+Vector3(0,0.09,0),Vector3(w-0.3,0.18,d-0.3),"old_brick")
	box(id+":rear",p+Vector3(0,eaves/2,d/2-0.24),Vector3(w-0.4,eaves,0.2),wall)
	for side:float in [-1.0,1.0]:
		box(id+":side:"+str(side),p+Vector3(side*(w/2-0.24),eaves/2,0),Vector3(0.2,eaves,d-0.4),wall)
		for z:float in [-d/2+0.24,d/2-0.24]:
			box(id+":post:%s:%s"%[side,z],p+Vector3(side*(w/2-0.24),eaves/2,z),Vector3(0.2,eaves,0.2),"b_wood_aged")
	if not open_front:box(id+":front",p+Vector3(0,eaves/2,-d/2+0.24),Vector3(w-0.4,eaves,0.2),wall)
	box(id+":lintel",p+Vector3(0,eaves-0.04,-d/2+0.2),Vector3(w-0.25,0.22,0.25),"b_wood_aged")
	# Stepped tile courses form two real slopes with an opaque gable backing.
	# Roof stays wholly within its own footprint including the ridge/caps.
	for i:int in 8:
		var z:float=-d/2+(float(i)+0.5)*d/8.0
		var y:float=h-0.17-absf(z)/(d/2)*0.58
		box(id+":roof:"+str(i),p+Vector3(0,y,z),Vector3(w,0.22,d/8.0),"roof_tile")
	box(id+":ridge",p+Vector3(0,h-0.10,0),Vector3(w,0.20,0.20),"roof_tile")
	for side:float in [-1.0,1.0]:
		box(id+":fascia:"+str(side),p+Vector3(0,h-0.69,side*(d/2-0.06)),Vector3(w,0.18,0.12),"b_wood_aged")
		for tier:int in 3:
			box(id+":gable:%s:%s"%[side,tier],p+Vector3(side*(w/2-0.24),eaves+0.1+float(tier)*0.17,0),Vector3(0.20,0.18,d*(0.78-float(tier)*0.22)),wall)
func window(id:String,x:float,z:float,width:float=0.85)->void:
	box(id+":recess",Vector3(x,1.65,z),Vector3(width,0.85,0.08),"painted_metal",false)
	for side:float in [-1.0,1.0]:box(id+":jamb:"+str(side),Vector3(x+side*width/2,1.65,z-0.06),Vector3(0.10,0.98,0.12),"b_wood_aged",false)
	box(id+":sill",Vector3(x,1.18,z-0.10),Vector3(width+0.22,0.13,0.28),"old_brick",false)
	box(id+":head",Vector3(x,2.11,z-0.06),Vector3(width+0.18,0.12,0.14),"b_wood_aged",false)
	box(id+":mullion",Vector3(x,1.65,z-0.07),Vector3(0.07,0.82,0.12),"b_wood_aged",false)
func closed_door(id:String,x:float,z:float)->void:
	# No door consumer/portal: this is the sealed exterior of a service module.
	box(id+":leaf",Vector3(x,1.04,z),Vector3(0.95,2.08,0.12),"b_wood_aged",false)
	for side:float in [-1.0,1.0]:box(id+":frame:"+str(side),Vector3(x+side*0.51,1.1,z-0.04),Vector3(0.14,2.2,0.18),"old_brick",false)
	box(id+":lintel",Vector3(x,2.18,z-0.04),Vector3(1.16,0.17,0.2),"b_wood_aged",false)
	box(id+":handle",Vector3(x+0.30,1.0,z-0.1),Vector3(0.07,0.20,0.08),"painted_metal",false)
func porch(id:String,x:float,z:float,width:float,height:float=2.65)->void:
	for side:float in [-1.0,1.0]:box(id+":post:"+str(side),Vector3(x+side*(width/2-0.12),height/2,z),Vector3(0.18,height,0.18),"b_wood_aged")
	box(id+":beam",Vector3(x,height,z),Vector3(width,0.22,0.22),"b_wood_aged")
	box(id+":canopy",Vector3(x,height+0.13,z+0.25),Vector3(width+0.08,0.20,0.80),"roof_tile")
func rack(id:String,p:Vector3,width:float)->void:
	# Empty structure only. No fixed logs, sacks, books or displayed rewards.
	for side:float in [-1.0,1.0]:box(id+":upright:"+str(side),p+Vector3(side*(width/2-0.06),0.62,0),Vector3(0.12,1.24,0.40),"b_wood_aged")
	for y:float in [0.12,0.65,1.17]:box(id+":shelf:"+str(y),p+Vector3(0,y,0),Vector3(width,0.10,0.46),"b_wood_aged")
func design(d:Dictionary)->void:
	match str(d.design_id):
		"BC02-long-bay":
			volume("long-bay",Vector3.ZERO,Vector3(6,3.9,4),"b_wood_aged")
			closed_door("loading",0,-1.81);window("left",-1.9,-1.72);window("right",1.9,-1.72)
			rack("service-rack",Vector3(-1.4,0,-1.70),2.05)
		"BC02-courtyard":
			volume("rear-store",Vector3(0,0,1.65),Vector3(6,4.3,2.7),"b_wood_aged")
			volume("side-store",Vector3(-1.9,0,-1.35),Vector3(2.2,3.65,3.3),"old_brick")
			closed_door("yard-store",0.7,0.20);window("store-window",2.1,0.20)
			rack("courtyard-rack",Vector3(-1.5,0,-2.70),2.05)
		"BC05-courtyard":
			volume("main-home",Vector3(0,0,1.5),Vector3(6,4.3,3))
			volume("home-wing",Vector3(-2.0,0,-1.5),Vector3(2,3.65,3),"old_brick")
			closed_door("home-door",0.8,-0.10);window("home-window",2.05,-0.1)
			porch("veranda",1.0,-1.48,3.2)
			box("curtain",Vector3(2.05,1.65,-0.17),Vector3(0.50,0.69,0.03),"textile_atlas",false,2)
		"BC05-roadside":
			volume("road-home",Vector3(0,0,0.4),Vector3(5,4.2,3.2))
			closed_door("entry",-0.75,-1.10);window("shutter",1.05,-1.10,1.0)
			porch("entry-porch",-0.7,-1.65,2.0)
			box("home-curtain",Vector3(1.05,1.65,-1.16),Vector3(0.60,0.70,0.03),"textile_atlas",false,3)
		"BC04-repair-shed":
			# Front is open over the real legacy workbench, no duplicated bench.
			volume("repair-shed",Vector3.ZERO,Vector3(4,3.4,3),"b_wood_aged",true)
			rack("rear-empty-rack",Vector3(0,0,1.01),2.4)
			box("metal-backboard",Vector3(0,1.73,1.12),Vector3(1.55,0.64,0.08),"zinc",false)
		"BC06-supply-roadside","BC06-supply-rear-v3":
			volume("supply",Vector3(0,0,0.4),Vector3(4.5,3.8,3.2),"cream_plaster")
			window("serving-hatch",-0.7,-1.10,1.35);closed_door("store-door",1.25,-1.10)
			porch("supply-canopy",-0.7,-1.65,2.7)
			rack("supply-empty-shelf",Vector3(-0.7,0,-1.60),1.45)
			box("shade-fabric",Vector3(-0.7,2.69,-1.40),Vector3(2.3,0.035,0.60),"textile_atlas",false,1)
			if d.design_id=="BC06-supply-rear-v3":
				# The front shelf stays visibly empty. Only the rear receives the
				# original single supplies buffer; no second inventory exists.
				box("rear-receiving-hatch",Vector3(-0.7,1.5,1.98),Vector3(1.35,0.85,0.04),"painted_metal",false)
				for x:float in [-1.42,0.02]:box("rear-hatch-jamb:"+str(x),Vector3(x,1.5,1.98),Vector3(0.1,1.0,0.04),"b_wood_aged",false)
				box("rear-receiving-sill",Vector3(-0.7,1.03,1.87),Vector3(1.65,0.13,0.24),"old_brick",false)
				rack("rear-receiving-rack",Vector3(-0.7,0,1.55),1.45)
		"BC01-long-shed":
			volume("woodshop",Vector3(0,0,0.2),Vector3(6,4.1,4.1),"b_wood_aged")
			window("shed-window",-1.8,-1.75);closed_door("shed-door",1.6,-1.75)
			box("saw-bed",Vector3(0,0.77,-1.97),Vector3(1.44,0.16,0.50),"wood_floor")
			for x:float in [-0.57,0.57]:
				box("saw-leg:"+str(x),Vector3(x,0.36,-1.97),Vector3(0.16,0.72,0.45),"painted_metal")
				box("saw-guide:"+str(x),Vector3(x,1.12,-2.03),Vector3(0.07,0.45,0.15),"painted_metal")
			box("fixed-power",Vector3(1.65,0.56,1.85),Vector3(0.85,0.95,0.55),"zinc")
			box("power-base",Vector3(1.65,0.10,1.85),Vector3(1.05,0.20,0.70),"concrete")
