extends RefCounted
## Additive twelve-building set. No inventory, economy or work clock lives here.
## Fixed benches for manual shapes come from B's one building adapter.
const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const IDS=["sawmill_low_v1","sawmill_mid_v1","sawmill_high_v1","warehouse_low_v1","warehouse_mid_v1","warehouse_high_v1","canteen_low_v1","canteen_mid_v1","canteen_high_v1","artisan_low_v1","artisan_mid_v1","artisan_high_v1"]

static func supports(d:Dictionary)->bool:
	return d.get("architecture",{}).get("set")=="r34-architecture-30-v1" and str(d.get("id","")).trim_prefix("r34.module.") in IDS and d.get("geometry_version")==str(d.id)+".geometry-v1"

static func parts(d:Dictionary)->Array:
	if not supports(d):return []
	var b:=Kit.new()
	match str(d.id).trim_prefix("r34.module."):
		"sawmill_low_v1":
			b.shed("hand-saw-frame",Vector3(0,0,0.10),5.6,4.6,2.55,0.77,"zinc")
			b.wall("hand-saw-rear",Vector3(0,1.20,2.02),Vector3(4.9,2.4,0.20),"b_wood_aged",Vector3.BACK,"blank")
			_rack(b,"empty-long-stock-rack",Vector3(-2.05,0,0.65),1.35,0.48)
			_paving(b,"working-apron",Vector3(0,0,-1.55),Vector3(4.0,0.025,1.45))
			_low_saw_fixtures(b)
		"sawmill_mid_v1":
			b.room("brick-machine-room",Vector3(0.9,0,1.8),6.6,3.8,3.45,1.15,"cream_plaster","store")
			b.lean_to("saw-working-canopy",Vector3(-0.7,0,-2.05),7.2,3.7,2.45,3.35,"zinc")
			_rack(b,"empty-timber-rack",Vector3(-3.4,0,0.6),1.6,0.48)
			_saw(b,d,Vector3(3.55,0,0.2))
			_chimney(b,"power-exhaust",Vector3(3.55,0,2.25),4.65)
		"sawmill_high_v1":
			b.room("high-saw-hall",Vector3(-1.5,0,2.30),8.9,5.4,4.10,1.55,"b_wood_aged","store")
			b.lean_to("low-loading-canopy",Vector3(-1.5,0,-2.75),8.4,5.2,2.65,3.70,"zinc")
			b.shed("independent-power-bay",Vector3(5.15,0,1.15),3.0,5.4,2.85,0.90,"architecture_gray_roof")
			b.wall("power-masonry-screen",Vector3(6.34,1.15,1.15),Vector3(0.20,2.30,4.7),"old_brick",Vector3.RIGHT,"blank")
			_saw(b,d,Vector3(5.15,0,1.15))
			_chimney(b,"power-stack",Vector3(5.15,0,3.05),5.65)
			_rack(b,"empty-main-stock-frame",Vector3(-4.3,0,0.1),2.0,0.55)
			_paving(b,"loading-court",Vector3(1.7,0,-3.1),Vector3(2.6,0.025,4.0))
		"warehouse_low_v1":
			b.shed("open-store-shed",Vector3.ZERO,6.6,4.6,2.65,0.88,"architecture_gray_roof")
			b.wall("sheltered-store-back",Vector3(0,1.20,1.94),Vector3(5.9,2.4,0.20),"b_wood_aged",Vector3.BACK,"blank")
			_rack(b,"empty-storage-a",Vector3(-1.5,0,1.30),2.0,0.56)
			_rack(b,"empty-storage-b",Vector3(1.5,0,1.30),2.0,0.56)
		"warehouse_mid_v1":
			b.shed("three-loading-bays",Vector3(-1.4,0,0.4),7.5,5.8,3.05,1.10,"architecture_gray_roof")
			b.room("sealed-stock-end",Vector3(3.8,0,0.4),2.8,5.8,2.85,0.95,"old_brick","store")
			b.wall("long-store-rear",Vector3(-1.4,1.35,2.90),Vector3(6.7,2.70,0.24),"b_wood_aged",Vector3.BACK,"blank")
			for x:float in [-2.6,-0.2]:
				b.box("bay-pier:"+str(x),Vector3(x,1.5,-2.18),Vector3(0.22,3.0,0.22),"b_wood_aged")
			_rack(b,"long-empty-rack",Vector3(-1.4,0,2.10),5.8,0.60)
			b.box("side-loading-platform",Vector3(-1.4,0.09,-2.65),Vector3(6.8,0.18,0.60),"concrete")
		"warehouse_high_v1":
			b.room("rear-bulk-store",Vector3(0,0,4.00),15.2,4.0,3.72,1.34,"b_wood_aged","store")
			b.shed("west-receiving-bays",Vector3(-5.6,0,-1.35),4.0,6.2,3.10,0.95,"architecture_gray_roof")
			b.lean_to("east-dispatch-bays",Vector3(5.3,0,-1.45),4.6,6.1,2.65,3.38,"zinc")
			_rack(b,"empty-receiving-frame",Vector3(-5.5,0,0.55),2.5,0.60)
			_rack(b,"empty-dispatch-frame",Vector3(5.2,0,0.55),2.5,0.60)
			_paving(b,"open-logistics-court",Vector3(0,0,-1.0),Vector3(5.8,0.025,7.0))
		"canteen_low_v1":
			b.room("small-stove-room",Vector3(1.75,0,0.8),2.6,3.8,2.42,0.82,"old_brick","store")
			b.lean_to("open-dining-veranda",Vector3(-1.35,0,-0.25),3.5,4.9,2.20,2.90,"zinc")
			_chimney(b,"stove-flue",Vector3(2.15,0,1.15),3.35)
			_table(b,"fixed-empty-dining-table",Vector3(-1.25,0,0.40),1.6)
		"canteen_mid_v1":
			b.room("dining-hall",Vector3(-1.35,0,2.1),7.6,4.0,3.22,1.12,"cream_plaster","home")
			b.room("low-kitchen-wing",Vector3(3.65,0,0.45),3.0,6.0,2.6,0.82,"old_brick","store")
			b.lean_to("meal-service-gallery",Vector3(-1.35,0,-0.85),7.3,2.2,2.35,2.95,"architecture_gray_roof")
			_chimney(b,"kitchen-stack",Vector3(3.8,0,2.35),4.38)
			_table(b,"empty-court-table",Vector3(-3.2,0,-2.75),1.7)
			_paving(b,"canteen-court",Vector3(-0.35,0,-2.8),Vector3(3.2,0.025,2.2))
		"canteen_high_v1":
			b.room("main-dining-hall",Vector3(-1.25,0,3.5),11.0,5.0,3.92,1.35,"cream_plaster","home")
			b.room("low-service-kitchen",Vector3(5.25,0,0.65),4.0,7.2,2.82,0.96,"old_brick","store")
			b.lean_to("main-serving-gallery",Vector3(-1.25,0,-0.05),10.8,2.4,2.55,3.35,"architecture_gray_roof")
			b.shed("side-dining-shelter",Vector3(-5.1,0,-3.3),3.5,4.6,2.55,0.68,"zinc")
			_chimney(b,"large-kitchen-stack",Vector3(5.4,0,2.8),5.18)
			_table(b,"empty-sheltered-table",Vector3(-5.0,0,-3.2),1.8)
			_paving(b,"food-service-court",Vector3(0.3,0,-3.3),Vector3(5.4,0.025,4.3))
		"artisan_low_v1":
			b.shed("single-work-shed",Vector3(0,0,0.10),5.5,4.6,2.5,0.83,"architecture_gray_roof")
			b.wall("work-backboard",Vector3(0,1.08,1.96),Vector3(4.9,2.16,0.20),"b_wood_aged",Vector3.BACK,"blank")
			_rack(b,"empty-tool-frame",Vector3(-1.9,0,0.8),1.35,0.40)
			b.box("iron-tool-back",Vector3(1.45,1.50,1.80),Vector3(1.35,0.75,0.06),"zinc",false)
			_low_artisan_fixtures(b)
		"artisan_mid_v1":
			b.room("closed-rear-workshop",Vector3(0.55,0,2.0),7.8,4.0,3.25,1.08,"cream_plaster","store")
			b.room("low-material-room",Vector3(-3.6,0,-0.35),2.3,4.6,2.50,0.78,"b_wood_aged","blank")
			b.lean_to("open-work-court-canopy",Vector3(1.0,0,-1.8),6.5,3.5,2.35,3.05,"zinc")
			_rack(b,"empty-work-rack",Vector3(3.6,0,0.35),1.4,0.48)
			_paving(b,"artisan-open-apron",Vector3(0,0,-3.35),Vector3(2.6,0.025,1.5))
		"artisan_high_v1":
			b.room("multi-span-artisan-hall",Vector3(-1.4,0,2.75),10.7,5.5,4.12,1.50,"cream_plaster","store")
			b.room("separate-material-house",Vector3(5.4,0,0.45),3.1,7.0,2.7,0.92,"old_brick","blank")
			b.lean_to("low-repair-veranda",Vector3(-1.4,0,-2.55),10.5,4.7,2.55,3.55,"zinc")
			for x:float in [-4.0,1.2]:b.box("hall-bay-pier:"+str(x),Vector3(x,1.8,0.55),Vector3(0.25,3.6,0.25),"b_wood_aged")
			_rack(b,"empty-repair-rack",Vector3(-4.4,0,-0.8),2.0,0.50)
			_paving(b,"wide-work-court",Vector3(0,0,-3.8),Vector3(3.0,0.025,3.5))
	return b.rows

static func _low_saw_fixtures(b:RefCounted)->void:
	# Empty V-cradles and long timber guides identify a hand-saw yard. They
	# remain beside the one real workbench, with no logs, saw or tool grants.
	var boxes:Array=[];var beams:Array=[]
	for z:float in [0.35,1.40]:
		var p:=Vector3(1.95,0,z)
		for sx:float in [-1,1]:
			beams.append(b._beam_item(p+Vector3(sx*0.40,0.08,0),p+Vector3(-sx*0.34,1.10,0),0.11))
		boxes.append(b._box_item(p+Vector3(0,0.48,0),Vector3(0.75,0.10,0.15),"b_wood_aged"))
		boxes.append(b._box_item(p+Vector3(0,0.63,0),Vector3(0.26,0.14,0.20),"painted_metal"))
	for x:float in [1.73,2.17]:boxes.append(b._box_item(Vector3(x,0.73,0.88),Vector3(0.10,0.12,1.65),"b_wood_aged"))
	# Iron straps at the rear beam/post joints, all batched with the fixtures.
	for x:float in [-2.35,2.35]:
		boxes.append(b._box_item(Vector3(x,2.26,1.96),Vector3(0.32,0.09,0.035),"painted_metal"))
		boxes.append(b._box_item(Vector3(x,2.17,1.96),Vector3(0.07,0.28,0.035),"painted_metal"))
	b.detail("hand-saw-fixed-guides",boxes,beams)

static func _low_artisan_fixtures(b:RefCounted)->void:
	# A screened, iron-faced assembly bay contrasts with the open saw cradles.
	# Empty hooks are fixed hardware; the actual tool inventory stays empty.
	var boxes:Array=[];var beams:Array=[]
	for i:int in 6:
		var z:float=0.30+float(i)*0.26
		boxes.append(b._box_item(Vector3(-2.42,1.56,z),Vector3(0.065,1.20,0.16),"b_wood_aged"))
	for y:float in [1.03,2.10]:boxes.append(b._box_item(Vector3(-2.39,y,0.95),Vector3(0.11,0.12,1.76),"b_wood_aged"))
	for x:float in [0.79,2.11]:boxes.append(b._box_item(Vector3(x,1.50,1.73),Vector3(0.09,0.85,0.10),"b_wood_aged"))
	boxes.append(b._box_item(Vector3(1.45,1.95,1.73),Vector3(1.42,0.09,0.10),"b_wood_aged"))
	boxes.append(b._box_item(Vector3(1.45,1.04,1.60),Vector3(1.42,0.10,0.38),"b_wood_aged"))
	for i:int in 5:
		var x:float=0.95+i*0.25
		boxes.append(b._box_item(Vector3(x,1.65,1.69),Vector3(0.035,0.04,0.16),"painted_metal"))
		boxes.append(b._box_item(Vector3(x,1.69,1.61),Vector3(0.035,0.10,0.035),"painted_metal"))
	# Small permanent guide jaws on the side shelf; no second crafting station.
	for x:float in [1.30,1.60]:boxes.append(b._box_item(Vector3(x,1.16,1.57),Vector3(0.09,0.16,0.21),"painted_metal"))
	boxes.append(b._box_item(Vector3(1.45,1.13,1.57),Vector3(0.45,0.055,0.055),"painted_metal"))
	beams.append(b._beam_item(Vector3(-2.35,1.05,0.18),Vector3(-2.35,2.15,1.75),0.08))
	b.detail("artisan-screen-and-fixed-hardware",boxes,beams)

static func _saw(b:RefCounted,d:Dictionary,power:Vector3)->void:
	var a:Array=d.get("machine_work_point",[0,1.1,-2.25])
	var tooth:=Vector3(a[0],a[1],a[2]);var bed:Vector3=tooth+Vector3(0,-0.33,-0.07)
	b.box("saw-bed",bed,Vector3(1.44,0.16,0.50),"wood_floor")
	for x:float in [-0.57,0.57]:
		b.box("saw-leg:"+str(x),Vector3(x,0.36,bed.z),Vector3(0.16,0.72,0.45),"painted_metal")
		b.box("saw-guide:"+str(x),Vector3(x,1.12,tooth.z+0.04),Vector3(0.07,0.45,0.15),"painted_metal")
	b.box("fixed-power",power+Vector3(0,0.56,0),Vector3(0.85,0.95,0.55),"zinc")
	b.box("power-base",power+Vector3(0,0.10,0),Vector3(1.05,0.20,0.70),"concrete")

static func _rack(b:RefCounted,id:String,p:Vector3,width:float,depth:float)->void:
	for x:float in [-width/2+0.06,width/2-0.06]:b.box(id+":upright:"+str(x),p+Vector3(x,0.72,0),Vector3(0.12,1.44,depth),"b_wood_aged")
	# Fixed empty furniture, not stock. The shelf mesh is merged by material.
	var boxes:Array=[]
	for y:float in [0.18,0.76,1.34]:boxes.append(b._box_item(p+Vector3(0,y,0),Vector3(width,0.10,depth+0.06),"b_wood_aged"))
	b.detail(id+":empty-shelves",boxes)

static func _table(b:RefCounted,id:String,p:Vector3,width:float)->void:
	b.box(id+":top",p+Vector3(0,0.76,0),Vector3(width,0.12,0.70),"b_wood_aged")
	for x:float in [-width/2+0.18,width/2-0.18]:b.box(id+":trestle:"+str(x),p+Vector3(x,0.36,0),Vector3(0.16,0.72,0.56),"b_wood_aged")
	for z:float in [-0.72,0.72]:
		b.box(id+":bench:"+str(z),p+Vector3(0,0.42,z),Vector3(width,0.10,0.30),"b_wood_aged")
		for x:float in [-width/2+0.18,width/2-0.18]:b.box(id+":bench-leg:%s:%s"%[z,x],p+Vector3(x,0.20,z),Vector3(0.14,0.40,0.22),"b_wood_aged")

static func _chimney(b:RefCounted,id:String,p:Vector3,height:float)->void:
	b.box(id+":stack",p+Vector3(0,height/2,0),Vector3(0.44,height,0.48),"old_brick")
	b.box(id+":cap",p+Vector3(0,height-0.06,0),Vector3(0.64,0.12,0.66),"stone_masonry")
	var bars:Array=[]
	for x:float in [-0.22,0.22]:bars.append(b._box_item(p+Vector3(x,height+0.08,0),Vector3(0.08,0.20,0.46),"old_brick"))
	bars.append(b._box_item(p+Vector3(0,height+0.20,0),Vector3(0.64,0.10,0.66),"stone_masonry"))
	b.detail(id+":cowl",bars)

static func _paving(b:RefCounted,id:String,p:Vector3,size:Vector3)->void:
	b.box(id,p+Vector3(0,size.y/2,0),size,"concrete",false)
