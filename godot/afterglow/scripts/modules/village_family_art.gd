extends RefCounted
## Versioned village fixtures. Actual goods are supplied by the stock view.
const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const TIMBER="b_wood_aged"
const STEEL="painted_metal"
const IRON="zinc"
const BRICK="old_brick"
const STONE="stone_masonry"
const WOOD="wood_floor"
const PLASTER="cream_plaster"
const TILE="architecture_gray_roof"

static func parts(kind:String,level:int,base:Array)->Array:
	var b:=Kit.new()
	match kind:
		"home", "heritage_home", "cottage":
			_home(b,kind!="cottage",level)
			return base+b.rows
		"warehouse", "warehouse_upgrade":
			_warehouse(b,maxi(level,2) if kind=="warehouse_upgrade" else level)
		"workshop", "artisan":
			_workshop(b,kind=="artisan",level)
		"sawmill", "village_sawmill":
			_sawmill(b,level)
		"stockyard":
			_stockyard(b,level)
		_:
			return base
	return b.rows

static func _home(b:Kit,heritage:bool,level:int)->void:
	# Preserve the original room, roof gap, collision and bed routing.
	var z:float=-0.70 if heritage else -1.36
	var x:float=2.48 if heritage else 1.70
	var chimney_x:float=2.32 if heritage else 1.28
	var chimney_z:float=-1.54 if heritage else 0.80
	var cap_y:float=3.58 if heritage else 3.28
	var boxes:Array=[]
	for side:float in [-1.0,1.0]:
		boxes.append(b._box_item(Vector3(side*x,0.20,z),Vector3(0.31,0.40,0.18),STONE))
		boxes.append(b._box_item(Vector3(side*x,1.27,z),Vector3(0.14,2.12,0.10),TIMBER))
	boxes.append(b._box_item(Vector3(chimney_x,cap_y-0.27,chimney_z),Vector3(0.34,0.52,0.37),BRICK))
	boxes.append(b._box_item(Vector3(chimney_x,cap_y,chimney_z),Vector3(0.44,0.10,0.49),STONE))
	if not heritage:
		boxes.append(b._box_item(Vector3(0,2.48,-1.58),Vector3(1.71,0.09,0.68),TILE))
		boxes.append(b._box_item(Vector3(0,2.42,-1.90),Vector3(1.74,0.14,0.10),TIMBER))
	if level>=2:
		var rail_z:float=-2.59 if heritage else -1.82
		for side:float in [-1.0,1.0]:
			boxes.append(b._box_item(Vector3(side*(1.88 if heritage else 1.26),0.69,rail_z),Vector3(1.49 if heritage else 0.91,0.12,0.12),TIMBER))
			boxes.append(b._box_item(Vector3(side*(2.43 if heritage else 1.65),0.47,rail_z),Vector3(0.14,0.94,0.14),TIMBER))
	if level>=3:
		# The dormer sits on the intact half of the old home's roof.
		var dormer:=Vector3(-1.44,3.43,-0.05) if heritage else Vector3(0,3.00,-0.80)
		boxes.append(b._box_item(dormer,Vector3(0.92,0.48,0.40),PLASTER))
		boxes.append(b._box_item(dormer+Vector3(0,0,-0.22),Vector3(0.61,0.32,0.05),"architecture_window"))
		boxes.append(b._box_item(dormer+Vector3(0,0.28,0),Vector3(1.16,0.12,0.64),TILE))
	b.detail("home-family-trim",boxes)

static func _warehouse(b:Kit,level:int)->void:
	# Keep the restoration roof ID and the exact stock shelf top elevations.
	var depth:float=2.80 if level>=3 else 2.18
	b.shed("warehouse-loading-roof",Vector3(0,0,1.96-depth/2),2.92,depth,2.37,0.43,TILE)
	b.wall("warehouse-rear",Vector3(0,1.14,1.78),Vector3(2.64,2.28,0.16),TIMBER,Vector3.BACK,"blank")
	for side:float in [-1.0,1.0]:
		b.box("rack-upright:"+str(side),Vector3(side*1.24,1.02,1.21),Vector3(0.13,2.04,0.82),STEEL)
	for y:float in [0.23,0.78,1.33,1.88]:
		b.box("empty-shelf:"+str(y),Vector3(0,y,1.21),Vector3(2.38,0.10,0.82),TIMBER)
	var boxes:Array=[]
	_surface(b,boxes,Vector3(-0.82,0.014,-1.18),0.92,1.36,4)
	_surface(b,boxes,Vector3(0.83,0.014,-1.18),1.16,0.56,2)
	_surface(b,boxes,Vector3(1.02,0.014,0.48),0.83,0.70,3)
	_chevron(b,boxes,Vector3(-0.82,0.031,-1.26),Vector3.BACK)
	_chevron(b,boxes,Vector3(1.10,0.031,0.48),Vector3.RIGHT)
	if level>=2:
		boxes.append(b._box_item(Vector3(0,1.37,0.12),Vector3(0.16,1.90,0.18),TIMBER))
		for side:float in [-1.0,1.0]:
			boxes.append(b._box_item(Vector3(side*0.65,2.11,0.10),Vector3(0.87,0.23,0.13),STEEL if side>0 else TIMBER))
			boxes.append(b._box_item(Vector3(side*0.65,2.11,0.02),Vector3(0.30,0.09,0.04),IRON))
	if level>=3:
		boxes.append(b._box_item(Vector3(1.24,0.49,0.47),Vector3(0.41,0.12,0.61),STEEL))
		for z:float in [0.23,0.47,0.71]:
			boxes.append(b._box_item(Vector3(1.24,0.57,z),Vector3(0.42,0.04,0.08),IRON))
	b.detail("warehouse-freight-markings",boxes)

static func _workshop(b:Kit,artisan:bool,level:int)->void:
	if artisan:
		b.shed("artisan-canopy",Vector3(0,0,0.99),2.88,0.98,2.25,0.44,TILE)
		b.wall("artisan-tool-wall",Vector3(0,1.05,1.36),Vector3(2.65,2.10,0.16),BRICK,Vector3.FORWARD,"blank")
		b.box("artisan-drawers",Vector3(0.89,0.45,0.91),Vector3(0.76,0.90,0.58),STEEL)
	else:
		b.lean_to("workbench-awning",Vector3(0,0,0.91),2.88,1.03,2.12,2.68,IRON)
		b.wall("handtool-backboard",Vector3(0,1.15,1.35),Vector3(2.66,2.30,0.16),TIMBER,Vector3.FORWARD,"blank")
	var boxes:Array=[]
	var beams:Array=[]
	_surface(b,boxes,Vector3(0,0.013,-0.76),2.74,1.10,7)
	if artisan:
		boxes.append(b._box_item(Vector3(-1.02,1.56,1.00),Vector3(0.37,2.48,0.40),BRICK))
		boxes.append(b._box_item(Vector3(-1.02,2.85,1.00),Vector3(0.49,0.10,0.53),STONE))
		for y:float in [0.23,0.42,0.61,0.80]:
			boxes.append(b._box_item(Vector3(0.89,y,0.60),Vector3(0.30,0.05,0.08),IRON))
		for x:float in [-0.45,0.06,0.56]:
			beams.append(b._beam_item(Vector3(x-0.12,1.29,1.24),Vector3(x+0.10,1.87,1.24),0.12,IRON))
			boxes.append(b._box_item(Vector3(x+0.10,1.87,1.24),Vector3(0.27,0.11,0.12),STEEL))
		if level>=2:
			boxes.append(b._box_item(Vector3(-0.88,0.61,0.46),Vector3(0.72,0.16,0.52),STEEL))
			boxes.append(b._box_item(Vector3(-0.94,0.86,0.46),Vector3(0.43,0.14,0.30),IRON))
			beams.append(b._beam_item(Vector3(-1.13,0.87,0.46),Vector3(-1.37,0.99,0.46),0.11,IRON))
		if level>=3:
			boxes.append(b._box_item(Vector3(0.43,2.52,1.08),Vector3(1.24,0.19,0.42),STEEL))
			for x:float in [0.06,0.42,0.78]:
				boxes.append(b._box_item(Vector3(x,2.64,1.08),Vector3(0.19,0.09,0.34),IRON))
	else:
		# A fixed bow saw differentiates the village's hand tool station.
		for x:float in [-0.91,0.18]:
			boxes.append(b._box_item(Vector3(x,1.64,1.19),Vector3(0.10,0.77,0.12),TIMBER))
		boxes.append(b._box_item(Vector3(-0.36,1.89,1.19),Vector3(1.18,0.09,0.13),WOOD))
		boxes.append(b._box_item(Vector3(-0.36,1.36,1.17),Vector3(1.15,0.07,0.06),IRON))
		if level>=2:
			boxes.append(b._box_item(Vector3(1.11,1.31,0.88),Vector3(0.61,0.10,0.57),STEEL))
			for y:float in [1.55,1.81]:
				boxes.append(b._box_item(Vector3(1.11,y,1.12),Vector3(0.59,0.11,0.16),WOOD))
		if level>=3:
			for x:float in [-1.08,-0.62,-0.16,0.30,0.76]:
				boxes.append(b._box_item(Vector3(x,2.33,0.12),Vector3(0.17,0.22,0.08),TIMBER))
			boxes.append(b._box_item(Vector3(-0.17,2.43,0.10),Vector3(2.12,0.17,0.09),IRON))
	b.detail("workshop-family-tools",boxes,beams)

static func _sawmill(b:Kit,level:int)->void:
	# West takes raw logs, east discharges timber. Keep both landings open.
	var guard_y:float=1.67 if level<3 else 1.83
	var z:float=-0.95
	b.box("mill-stone-base",Vector3(0,0.12,z),Vector3(2.32,0.24,0.80),STONE)
	b.box("mill-cast-base",Vector3(0,0.53,z),Vector3(1.12,0.66,0.92),STEEL)
	b.box("mill-feed-bed",Vector3(0,0.85,z),Vector3(3.72,0.15,0.74),STEEL)
	for x:float in [-1.58,1.56]:
		b.box("mill-trestle:"+str(x),Vector3(x,0.40,z),Vector3(0.19,0.80,0.60),TIMBER)
	var blade:Dictionary=b.box("saw-disc",Vector3(0,1.10,z),Vector3(0.08,1.02,1.02),IRON,false)
	blade.architecture_detail={"version":Kit.DETAIL_VERSION,"kind":"details","local_size":blade.size,"discs":[{"center":{"x":0.04,"y":0.51,"z":0.51},"radius":0.51,"thickness":0.08,"teeth":24,"material":IRON}]}
	var power_width:float=1.64 if level>=3 else 1.31
	b.shed("power-hood",Vector3(1.14,0,1.19),power_width,1.46,1.98 if level>=2 else 1.60,0.34,IRON)
	b.box("motor",Vector3(1.10,0.43,1.14),Vector3(1.00,0.86,0.87),STEEL)
	b.box("exhaust",Vector3(1.48,1.69,1.21),Vector3(0.23,2.45,0.23),BRICK)
	var boxes:Array=[]
	var beams:Array=[]
	for x:float in [-1.59,-1.24,-0.86,0.82,1.20,1.59]:
		boxes.append(b._box_item(Vector3(x,0.956,z),Vector3(0.18,0.06,0.68),IRON))
	for x:float in [-1.51,-0.87]:
		for side:float in [-1.0,1.0]:
			beams.append(b._beam_item(Vector3(x,0.91,z+side*0.12),Vector3(x,1.28,z+side*0.39),0.12,TIMBER))
	boxes.append(b._box_item(Vector3(0,guard_y,z-0.07),Vector3(0.38,0.20,0.91),STEEL))
	boxes.append(b._box_item(Vector3(0,guard_y-0.15,z+0.32),Vector3(0.38,0.31,0.13),STEEL))
	boxes.append(b._box_item(Vector3(1.48,2.97,1.21),Vector3(0.38,0.12,0.38),IRON))
	_surface(b,boxes,Vector3(-1.58,0.014,z),0.76,0.98,4)
	_surface(b,boxes,Vector3(1.58,0.014,z),0.76,0.98,4)
	_chevron(b,boxes,Vector3(-1.79,0.031,z+0.31),Vector3.RIGHT)
	_chevron(b,boxes,Vector3(1.87,0.031,z+0.31),Vector3.RIGHT)
	if level>=2:
		for rail_z:float in [z-0.21,z+0.21]:
			boxes.append(b._box_item(Vector3(0.91,1.07,rail_z),Vector3(1.50,0.12,0.14),STEEL))
		for x:float in [0.35,1.59]:
			boxes.append(b._box_item(Vector3(x,0.55,z),Vector3(0.18,0.58,0.74),STEEL))
	if level>=3:
		boxes.append(b._box_item(Vector3(0.64,1.12,0.40),Vector3(0.44,0.26,1.18),STEEL))
		boxes.append(b._box_item(Vector3(-0.83,1.35,-0.46),Vector3(1.56,0.16,0.17),IRON))
		for x:float in [-1.56,-0.10]:
			boxes.append(b._box_item(Vector3(x,1.15,-0.46),Vector3(0.17,0.43,0.17),STEEL))
	b.detail("mill-family-guards-and-rollers",boxes,beams)

static func _stockyard(b:Kit,level:int)->void:
	var boxes:Array=[]
	_surface(b,boxes,Vector3(0,0.014,0),1.70,2.80,5)
	for side:float in [-1.0,1.0]:
		b.box("yard-edge:"+str(side),Vector3(side*0.92,0.16,0.17),Vector3(0.14,0.32,2.49),TIMBER)
		for z:float in [-1.18,1.24]:
			boxes.append(b._box_item(Vector3(side*0.89,0.31,z),Vector3(0.18,0.62,0.20),TIMBER))
			if level>=2:
				boxes.append(b._box_item(Vector3(side*0.89,0.61,z),Vector3(0.21,0.09,0.23),IRON))
	if level>=2:
		for z:float in [-0.93,0.82]:
			boxes.append(b._box_item(Vector3(0,0.068,z),Vector3(1.60,0.10,0.15),TIMBER))
	if level>=3:
		boxes.append(b._box_item(Vector3(0,0.66,1.28),Vector3(1.90,0.18,0.18),STEEL))
		boxes.append(b._box_item(Vector3(0,0.90,1.27),Vector3(0.57,0.30,0.10),TIMBER))
		boxes.append(b._box_item(Vector3(0,0.92,1.20),Vector3(0.38,0.09,0.05),IRON))
	b.detail("yard-family-markings",boxes)

static func _surface(b:Kit,boxes:Array,at:Vector3,width:float,depth:float,count:int)->void:
	var pitch:float=width/float(count)
	for i:int in count:
		boxes.append(b._box_item(at+Vector3(-width/2+(i+0.5)*pitch,0,0),Vector3(pitch-0.028,0.027,depth),WOOD if i%3!=0 else TIMBER))

static func _chevron(b:Kit,boxes:Array,p:Vector3,direction:Vector3)->void:
	var across:=Vector3(-direction.z,0,direction.x)
	boxes.append(b._box_item(p,Vector3(0.065,0.012,0.065),IRON))
	for side:float in [-1.0,1.0]:
		for step:int in range(1,4):
			var f:float=float(step)/4.0
			boxes.append(b._box_item(p+across*side*f*0.19-direction*f*0.21,Vector3(0.065,0.012,0.065),IRON))
