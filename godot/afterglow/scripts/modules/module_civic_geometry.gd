extends RefCounted
## Additive civic structures only. No water, stock, work or combat settlement.
## All dimensions include eaves and the yard boundary. Upper guard rooms are
## sealed service volumes; this module advertises no invented stairs/portals.
const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const IDS={
	"r34.module.water_low_v1":"water:low", "r34.module.water_mid_v1":"water:mid", "r34.module.water_high_v1":"water:high",
	"r34.module.repair_low_v1":"repair:low", "r34.module.repair_mid_v1":"repair:mid", "r34.module.repair_high_v1":"repair:high",
	"r34.module.guard_low_v1":"guard:low", "r34.module.guard_mid_v1":"guard:mid", "r34.module.guard_high_v1":"guard:high"}

static func supports(definition:Dictionary)->bool:
	return IDS.has(definition.get("id")) and definition.get("geometry_version")==str(definition.id)+".geometry-v1" and definition.get("architecture",{}).get("set")=="r34-architecture-30-v1"

static func parts(definition:Dictionary)->Array:
	if not supports(definition):return []
	var k:=Kit.new()
	match str(IDS[definition.id]):
		"water:low":
			k.shed("well-pavilion",Vector3(-0.55,0,0.1),3.5,3.3,2.55,0.72,"architecture_gray_roof")
			_well(k,Vector3(-0.55,0,0.2),1.65)
			_rack(k,"bucket-rack",Vector3(1.73,0,0.9),0.82)
		"water:mid":
			# Separate draw pavilion, covered vessel and empty return shelf.
			k.shed("draw-pavilion",Vector3(-2.0,0,-0.65),3.4,3.8,2.65,0.85,"architecture_gray_roof")
			_well(k,Vector3(-2.0,0,-0.25),1.75)
			k.shed("barrel-shed",Vector3(1.75,0,1.15),3.5,3.4,2.85,0.85,"architecture_gray_roof")
			_vessel(k,"covered-cistern",Vector3(1.7,0,1.35),Vector3(1.85,1.9,1.65))
			_rack(k,"empty-return-shelf",Vector3(1.7,0,-1.8),2.0)
			_boundary(k,8,6,false)
		"water:high":
			# L service yard: masonry pump house, independent covered storage
			# and a lower front draw canopy. The vessel is closed and unfilled.
			k.room("pump-house",Vector3(-3.25,0,1.9),4.1,4.7,3.15,1.10,"old_brick","store")
			k.shed("storage-canopy",Vector3(2.6,0,2.0),4.1,4.5,3.35,0.95,"architecture_gray_roof")
			_vessel(k,"service-tank",Vector3(2.6,0,2.0),Vector3(2.6,2.3,2.4))
			k.lean_to("draw-counter-canopy",Vector3(0.4,0,-2.9),6.1,2.8,2.60,3.20,"zinc")
			k.box("draw-counter",Vector3(-0.8,0.46,-2.55),Vector3(1.8,0.92,0.5),"old_brick")
			_rack(k,"returns-empty",Vector3(2.0,0,-2.5),1.5)
			_boundary(k,11,9,true)
		"repair:low":
			k.shed("single-repair-frame",Vector3.ZERO,4.85,3.65,2.55,0.72,"architecture_gray_roof")
			k.wall("rear-tool-wall",Vector3(0,1.27,1.65),Vector3(4.05,2.54,0.22),"b_wood_aged",Vector3.BACK,"blank")
			_rack(k,"rear-empty-parts",Vector3(0,0,1.12),2.7)
			_backboard(k,Vector3(0,1.75,1.48),2.7)
		"repair:mid":
			# A sealed parts room behind an open repair bay, with a lower side
			# sorting canopy. The sole workbench is made by the original owner.
			k.room("parts-room",Vector3(1.7,0,1.35),4.1,3.1,3.25,1.05,"cream_plaster","store")
			k.shed("repair-bay",Vector3(0,0,-1.10),5.2,3.5,2.85,0.85,"architecture_gray_roof")
			k.lean_to("sorting-lean-to",Vector3(2.55,0,-1.7),2.4,2.0,2.30,2.90,"zinc")
			_rack(k,"empty-spares",Vector3(-2.1,0,1.6),2.5)
			_boundary(k,8,6,false)
		"repair:high":
			# High transverse work shed + low masonry stores form a real repair
			# court, keeping the north throat and both loading faces independent.
			k.shed("high-clearance-repair",Vector3(-1.6,0,1.55),8.2,6.4,4.30,1.35,"architecture_gray_roof")
			k.room("low-parts-annex",Vector3(4.3,0,1.7),3.0,6.1,2.95,0.95,"cream_plaster","store")
			k.lean_to("front-bench-porch",Vector3(-0.25,0,-3.45),6.2,2.6,2.85,3.60,"zinc")
			_rack(k,"empty-long-parts",Vector3(-3.0,0,3.85),3.6)
			_backboard(k,Vector3(-1.1,2.1,4.32),4.6)
			_boundary(k,12,10,true)
		"guard:low":
			k.shed("observation-shelter",Vector3.ZERO,3.85,3.65,2.50,0.75,"architecture_gray_roof")
			k.wall("rear-watch-screen",Vector3(0,0.98,1.55),Vector3(2.95,1.96,0.22),"b_wood_aged",Vector3.BACK,"blank")
			k.box("map-counter",Vector3(0,0.47,1.15),Vector3(1.8,0.94,0.52),"b_wood_aged")
			_rail(k,"west-low-rail",Vector3(-1.55,0,-0.1),2.2,0)
		"guard:mid":
			k.box("masonry-support",Vector3(0,1.15,0.75),Vector3(2.7,2.3,2.7),"old_brick")
			k.room("raised-watch-room",Vector3(0,2.30,0.45),4.3,3.65,2.12,0.90,"b_wood_aged","home")
			k.box("balcony-slab",Vector3(0,2.30,-1.22),Vector3(4.1,0.2,1.1),"concrete")
			_rail(k,"balcony-front",Vector3(0,2.40,-1.68),3.9,1)
			k.box("ground-service-counter",Vector3(0,0.45,-1.1),Vector3(1.6,0.9,0.46),"b_wood_aged")
		"guard:high":
			k.box("tower-masonry-base",Vector3(-1.85,1.62,1.1),Vector3(3.1,3.24,3.5),"old_brick")
			k.room("tower-watch-room",Vector3(-1.85,3.15,1.1),4.05,4.3,3.10,1.25,"cream_plaster","home")
			k.room("low-gate-lodge",Vector3(2.05,0,1.25),3.55,4.1,2.75,0.88,"b_wood_aged","home")
			k.shed("gate-service-canopy",Vector3(0,0,-1.85),5.9,2.9,2.55,0.78,"architecture_gray_roof")
			k.box("gate-desk",Vector3(1.3,0.47,-1.7),Vector3(1.7,0.94,0.5),"b_wood_aged")
			_boundary(k,8,7,true)
	_ground_finish(k,definition)
	return k.rows

static func _well(k:RefCounted,p:Vector3,width:float)->void:
	# Four thick masonry sides leave a genuine open well mouth. It has no
	# water material, inventory or resource descriptor. Existing ground is intact.
	var t:=0.25
	for side:float in [-1.0,1.0]:
		k.box("well-side-x:"+str(side),p+Vector3(side*(width-t)/2,0.48,0),Vector3(t,0.96,width),"old_brick")
		k.box("well-side-z:"+str(side),p+Vector3(0,0.48,side*(width-t)/2),Vector3(width-2*t,0.96,t),"old_brick")
	var boxes:Array=[]
	for side:float in [-1.0,1.0]:
		boxes.append(k._box_item(p+Vector3(side*(width-t)/2,1.0,0),Vector3(t+0.08,0.12,width+0.08),"concrete"))
		boxes.append(k._box_item(p+Vector3(0,1.0,side*(width-t)/2),Vector3(width-2*t,0.12,t+0.08),"concrete"))
	boxes.append(k._box_item(p+Vector3(0,1.88,0),Vector3(width+0.2,0.16,0.16),"b_wood_aged"))
	boxes.append(k._box_item(p+Vector3(0,1.3,0),Vector3(0.04,1.0,0.04),"b_wood_aged"))
	k.detail("well-coping-winch-rope",boxes)

static func _vessel(k:RefCounted,id:String,p:Vector3,size:Vector3)->void:
	k.box(id+":base",p+Vector3(0,0.12,0),Vector3(size.x+0.22,0.24,size.z+0.22),"concrete")
	k.box(id+":closed-vessel",p+Vector3(0,size.y/2+0.24,0),size,"b_wood_aged")
	var items:Array=[]
	for y:float in [0.35,size.y*0.5+0.24,size.y+0.13]:
		for side:float in [-1.0,1.0]:
			items.append(k._box_item(p+Vector3(side*(size.x/2+0.015),y,0),Vector3(0.055,0.10,size.z+0.07),"painted_metal"))
			items.append(k._box_item(p+Vector3(0,y,side*(size.z/2+0.015)),Vector3(size.x+0.07,0.10,0.055),"painted_metal"))
	items.append(k._box_item(p+Vector3(0,size.y+0.30,0),Vector3(size.x+0.06,0.12,size.z+0.06),"zinc"))
	k.detail(id+":bands-lid",items)

static func _rack(k:RefCounted,id:String,p:Vector3,width:float)->void:
	# Empty furniture only. Real stock is rendered by the original stock owner.
	for x:float in [-width/2+0.07,width/2-0.07]:
		k.box(id+":upright:"+str(x),p+Vector3(x,0.66,0),Vector3(0.14,1.32,0.42),"b_wood_aged")
	for y:float in [0.14,0.72,1.28]:k.box(id+":shelf:"+str(y),p+Vector3(0,y,0),Vector3(width,0.10,0.46),"b_wood_aged")

static func _backboard(k:RefCounted,p:Vector3,width:float)->void:
	k.detail("empty-tool-backboard",[k._box_item(p,Vector3(width,0.66,0.08),"zinc")])

static func _boundary(k:RefCounted,width:float,depth:float,masonry:bool)->void:
	# Rear boundary only: the two side loading/repair faces stay open. No
	# crossing gate bar is placed across the ground approach.
	k.box("rear-yard-boundary",Vector3(0,0.46,depth/2-0.19),Vector3(width-0.4,0.92,0.22),"old_brick" if masonry else "b_wood_aged")
	for side:float in [-1.0,1.0]:
		k.box("rear-boundary-pier:"+str(side),Vector3(side*(width/2-0.27),0.66,depth/2-0.24),Vector3(0.32,1.32,0.32),"old_brick")
	var caps:Array=[k._box_item(Vector3(0,0.97,depth/2-0.19),Vector3(width-0.35,0.12,0.30),"concrete")]
	for side:float in [-1.0,1.0]:caps.append(k._box_item(Vector3(side*(width/2-0.27),1.35,depth/2-0.24),Vector3(0.40,0.12,0.40),"concrete"))
	k.detail("yard-wall-coping",caps)

static func _ground_finish(k:RefCounted,definition:Dictionary)->void:
	# Shallow in-footprint hardstanding is derived mesh, not a second terrain
	# pad or support surface. Ground/step/navigation remain the actual voxels.
	var fp:Dictionary=definition.footprint
	var x0:float=fp.min.x;var x1:float=fp.max.x;var z0:float=fp.min.z
	var paving:Array=[]
	var columns:int=maxi(3,floori((x1-x0-0.7)/0.62))
	var width:float=(x1-x0-0.7)/float(columns)
	for row:int in 2:
		for column:int in columns:
			var x:float=x0+0.35+(float(column)+0.5)*width
			paving.append(k._box_item(Vector3(x,0.018,z0+0.25+float(row)*0.47),Vector3(width-0.025,0.028,0.435),"concrete"))
	# A narrow gravel/stone edge and a covered drain give a purpose to the
	# service frontage. Neither water flow nor a free resource is simulated.
	paving.append(k._box_item(Vector3(0,0.025,z0+0.06),Vector3(x1-x0-0.45,0.04,0.10),"old_brick"))
	var drain_x:float=x1-0.24
	paving.append(k._box_item(Vector3(drain_x,0.021,z0+0.7),Vector3(0.18,0.025,1.2),"painted_metal"))
	for i:int in 9:paving.append(k._box_item(Vector3(drain_x,0.04,z0+0.2+float(i)*0.12),Vector3(0.20,0.035,0.035),"zinc"))
	k.detail("service-paving-drain",paving)

static func _rail(k:RefCounted,id:String,p:Vector3,length:float,axis:int)->void:
	for side:float in [-1.0,1.0]:
		var offset:=Vector3(side*(length/2-0.10),0,0) if axis==1 else Vector3(0,0,side*(length/2-0.10))
		k.box(id+":post:"+str(side),p+offset+Vector3(0,0.5,0),Vector3(0.14,1.0,0.14),"b_wood_aged")
	for y:float in [0.4,0.9]:
		k.box(id+":bar:"+str(y),p+Vector3(0,y,0),Vector3(length,0.10,0.10) if axis==1 else Vector3(0.10,0.10,length),"b_wood_aged")
