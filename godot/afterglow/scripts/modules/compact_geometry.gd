extends RefCounted
const Kit=preload("res://scripts/buildings/architecture_kit.gd")

static func parts(kind:String)->Array:
	var b:=Kit.new()
	match kind:
		"warehouse", "warehouse_upgrade":
			b.shed("warehouse-loading-roof",Vector3(0,0,.83),2.92,2.18,2.37,.43,"architecture_gray_roof")
			b.wall("warehouse-rear",Vector3(0,1.14,1.78),Vector3(2.64,2.28,.16),"b_wood_aged",Vector3.BACK,"blank")
			for side:float in [-1.0,1.0]:
				b.box("rack-upright:"+str(side),Vector3(side*1.24,1.02,1.21),Vector3(.13,2.04,.82),"painted_metal")
			for y:float in [.23,.78,1.33,1.88]:
				b.box("empty-shelf:"+str(y),Vector3(0,y,1.21),Vector3(2.38,.10,.82),"b_wood_aged")
			b.box("loading-stripe",Vector3(0,.03,-1.28),Vector3(2.80,.05,.16),"b_wood_aged",false)
			if kind=="warehouse_upgrade":
				for side:float in [-1.0,1.0]:b.box("side-dividers:"+str(side),Vector3(side*1.25,.52,.15),Vector3(.16,1.04,1.0),"painted_metal")
		"stockyard":
			for side:float in [-1.0,1.0]:b.box("yard-edge:"+str(side),Vector3(side*.92,.18,.25),Vector3(.14,.36,2.4),"b_wood_aged")
			for z:float in [-.9,.1,1.10]:b.box("yard-sleeper:"+str(z),Vector3(0,.06,z),Vector3(1.66,.12,.18),"b_wood_aged")
		"workshop":
			b.shed("tools-awning",Vector3(0,0,.82),2.90,1.28,2.30,.42,"zinc")
			b.wall("tool-board",Vector3(0,1.21,1.31),Vector3(2.64,2.22,.14),"b_wood_aged",Vector3.BACK,"blank")
			b.box("tool-rail",Vector3(0,1.30,1.18),Vector3(1.96,.13,.11),"painted_metal")
			for x:float in [-.8,-.24,.42,.82]:b.box("tool-peg:"+str(x),Vector3(x,1.22,1.07),Vector3(.06,.48,.10),"zinc",false)
			b.box("vise",Vector3(-.82,1.12,-.60),Vector3(.30,.24,.26),"painted_metal",false)
		"sawmill":
			b.shed("motor-canopy",Vector3(1.15,0,1.18),1.57,1.42,1.58,.38,"zinc")
			b.box("feed-bed",Vector3(0,.79,-.95),Vector3(3.80,.16,.85),"painted_metal")
			for x:float in [-1.55,-.76,.76,1.55]:
				b.box("roller:"+str(x),Vector3(x,.90,-.95),Vector3(.16,.11,.74),"zinc")
			for x:float in [-1.52,1.52]:b.box("trestle:"+str(x),Vector3(x,.37,-.95),Vector3(.24,.74,.64),"b_wood_aged")
			b.box("motor",Vector3(1.18,.46,.77),Vector3(1.06,.92,.75),"painted_metal")
			b.box("exhaust",Vector3(1.45,1.63,.79),Vector3(.22,2.22,.22),"painted_metal")
			var blade:=b.box("saw-disc",Vector3(0,1.10,-.95),Vector3(.08,1.08,1.08),"zinc",false)
			blade.architecture_detail={"version":Kit.DETAIL_VERSION,"kind":"details","local_size":blade.size,"discs":[{"center":{"x":.04,"y":.54,"z":.54},"radius":.54,"thickness":.08,"teeth":24,"material":"zinc"}]}
		"water", "kitchen":
			b.shed("utility-cover",Vector3(0,0,.82),2.90,1.25,2.22,.38,"zinc")
			if kind=="water":
				b.box("filter-plinth",Vector3(0,.28,.38),Vector3(2.24,.56,1.20),"old_brick")
				b.box("raw-barrel",Vector3(-.64,.91,.38),Vector3(.76,.72,.72),"b_wood_aged")
				b.box("treated-tank",Vector3(.59,1.03,.38),Vector3(.82,.94,.76),"painted_metal")
				b.box("tap",Vector3(.59,1.05,-.10),Vector3(.09,.09,.25),"zinc",false)
			else:
				b.box("brick-stove",Vector3(.70,.43,.41),Vector3(1.1,.86,1.44),"old_brick")
				b.box("hotplate",Vector3(.70,.91,.32),Vector3(1.12,.10,.90),"painted_metal")
				b.box("stove-stack",Vector3(.93,1.74,.84),Vector3(.28,2.08,.28),"old_brick")
				b.box("prep-top",Vector3(-.74,.88,.41),Vector3(1.22,.13,.78),"b_wood_aged")
				b.box("prep-frame",Vector3(-.74,.40,.41),Vector3(1.12,.80,.66),"b_wood_aged")
		"cottage":
			b.roof("home-roof-small",Vector3(0,0,.22),3.85,3.42,2.52,.86,"architecture_gray_roof","cream_plaster")
			for side:float in [-1.0,1.0]:
				b.wall("home-side:"+str(side),Vector3(side*1.79,1.25,.27),Vector3(.18,2.50,3.10),"cream_plaster",Vector3(side,0,0))
				b.wall("home-door-jamb:"+str(side),Vector3(side*1.28,1.25,-1.25),Vector3(1.08,2.50,.17),"cream_plaster",Vector3.FORWARD)
			b.box("home-door-lintel",Vector3(0,2.37,-1.25),Vector3(1.50,.26,.18),"b_wood_aged")
			b.wall("home-rear",Vector3(0,1.25,1.79),Vector3(3.43,2.50,.18),"old_brick",Vector3.BACK)
	return b.rows
