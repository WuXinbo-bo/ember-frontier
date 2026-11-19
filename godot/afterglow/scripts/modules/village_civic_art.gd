extends RefCounted
const Kit=preload("res://scripts/buildings/architecture_kit.gd")

## Major assemblies stay within their pad; the front service approach is open.
static func parts(kind:String,level:int,base:Array)->Array:
	var k:=Kit.new()
	match kind:
		"water":_water(k,level)
		"kitchen":_kitchen(k,level)
		"repair":_repair(k,level)
		"guard":_guard(k,level)
		"supply":_supply(k,level)
		"radio":_radio(k,level)
		_:return base
	return k.rows

static func _water(k:RefCounted,level:int)->void:
	k.box("filter-plinth",Vector3(0,.15,.62),Vector3(2.76,.30,1.62),"old_brick")
	_tank(k,"raw-cask",Vector3(-.88,.30,.65),.83,1.0,"b_wood_aged")
	_tank(k,"clean-vessel",Vector3(.84,.30,.68),.96,1.45 if level>=2 else 1.05,"painted_metal")
	_tank(k,"filter-core",Vector3(0,.30,.81),.50,1.45,"zinc")
	var fixtures:Array=[
		k._box_item(Vector3(-.40,1.15,.65),Vector3(.30,.11,.11),"zinc"),
		k._box_item(Vector3(.38,1.16,.65),Vector3(.34,.11,.11),"zinc"),
		k._box_item(Vector3(.84,.94,.13),Vector3(.14,.14,.38),"zinc"),
		k._box_item(Vector3(.84,.85,-.03),Vector3(.13,.20,.12),"painted_metal"),
		k._box_item(Vector3(.84,.49,-.04),Vector3(.62,.08,.52),"zinc")]
	var pipes:Array=[]
	if level>=2:
		_tank(k,"second-filter",Vector3(-.35,.30,.02),.46,1.18,"zinc")
		pipes.append(k._beam_item(Vector3(-.35,1.36,.03),Vector3(0,1.43,.66),.10,"painted_metal"))
	if level>=3:
		_tank(k,"upper-header",Vector3(.81,1.81,.68),.68,.73,"painted_metal")
		fixtures.append(k._box_item(Vector3(.84,1.80,.68),Vector3(1.06,.13,1.06),"b_wood_aged"))
		pipes.append(k._beam_item(Vector3(.80,2.28,.30),Vector3(.80,1.04,.30),.13,"zinc"))
		fixtures.append(k._box_item(Vector3(.79,2.56,.68),Vector3(.32,.10,.32),"zinc"))
	k.detail("manifold-tap-and-drip-tray",fixtures,pipes)
	_apron(k,"drained-fill-pad",[Vector3(-.82,0,-.55),Vector3(.82,0,-.55)],"concrete")

static func _tank(k:RefCounted,id:String,p:Vector3,width:float,height:float,material:String)->void:
	# Stepped shoulders keep the vessel readable at normal voxel scale.
	var body:Vector3=p+Vector3(0,height*.5,0)
	k.box(id+":core",body,Vector3(width*.72,height,width),material)
	for side:float in [-1,1]:
		k.box(id+":shoulder:"+str(side),body+Vector3(side*width*.43,0,0),Vector3(width*.14,height,width*.72),material)
	var trim:Array=[k._box_item(p+Vector3(0,height+.035,0),Vector3(width*.62,.07,width*.64),"zinc")]
	for y:float in [height*.18,height*.78]:
		for side:float in [-1,1]:
			trim.append(k._box_item(p+Vector3(0,y,side*(width/2+.008)),Vector3(width*.73,.08,.037),"painted_metal"))
			trim.append(k._box_item(p+Vector3(side*(width/2+.008),y,0),Vector3(.037,.08,width*.73),"painted_metal"))
	k.detail(id+":bands-and-lid",trim)

static func _kitchen(k:RefCounted,level:int)->void:
	k.box("brick-range",Vector3(.58,.47,.68),Vector3(1.52,.94,1.38),"old_brick")
	k.box("range-cooktop",Vector3(.58,1.01,.64),Vector3(1.60,.14,1.45),"painted_metal")
	k.box("exhaust-stack",Vector3(.94,1.79,1.03),Vector3(.34,1.70,.36),"old_brick")
	k.box("range-screen",Vector3(.53,1.35,1.30),Vector3(1.56,.62,.12),"cream_plaster")
	var details:Array=[
		k._box_item(Vector3(.57,.64,-.027),Vector3(1.15,.44,.08),"painted_metal"),
		k._box_item(Vector3(.56,.76,-.081),Vector3(.30,.055,.07),"zinc"),
		k._box_item(Vector3(.65,1.70,.71),Vector3(1.39,.24,.94),"zinc"),
		k._box_item(Vector3(.74,1.88,.87),Vector3(1.01,.14,.59),"painted_metal"),
		k._box_item(Vector3(.94,2.68,1.03),Vector3(.49,.11,.51),"zinc")]
	for x:float in [.23,.89]:
		details.append(k._box_item(Vector3(x,1.11,.46),Vector3(.42,.08,.37),"zinc"))
		details.append(k._box_item(Vector3(x,1.13,.46),Vector3(.30,.06,.27),"painted_metal"))
	var counter_depth:float=1.38 if level>=2 else .87
	var counter_z:float=.57 if level==1 else .27
	k.box("prep-and-service-counter",Vector3(-.84,.48,counter_z),Vector3(.95,.96,counter_depth),"b_wood_aged")
	details.append(k._box_item(Vector3(-.84,1.01,counter_z),Vector3(1.04,.11,counter_depth+.09),"wood_floor"))
	if level>=2:
		details.append(k._box_item(Vector3(-.84,1.12,-.53),Vector3(1.04,.12,.31),"concrete"))
		for x:float in [-1.27,-.44]:details.append(k._box_item(Vector3(x,1.59,.18),Vector3(.11,1.13,.11),"b_wood_aged"))
		details.append(k._box_item(Vector3(-.84,2.16,.07),Vector3(1.13,.13,1.14),"zinc"))
	if level>=3:
		k.box("holding-oven",Vector3(-.87,1.38,.83),Vector3(.86,.63,.66),"painted_metal")
		details.append(k._box_item(Vector3(-.87,1.42,.478),Vector3(.63,.43,.042),"zinc"))
		details.append(k._box_item(Vector3(-.87,1.55,.44),Vector3(.34,.065,.065),"b_wood_aged"))
	k.detail("hood-hotplates-and-counter-joinery",details)
	_apron(k,"kitchen-work-apron",[Vector3(-.84,0,-.80),Vector3(.52,0,-.80)],"old_brick")

static func _repair(k:RefCounted,level:int)->void:
	k.lean_to("repair-bay",Vector3(0,0,.86),2.86,1.08,2.18,2.64,"zinc")
	k.wall("parts-board",Vector3(0,1.21,1.33),Vector3(2.56,2.42,.15),"old_brick",Vector3.BACK,"blank")
	var details:Array=[k._box_item(Vector3(0,1.66,1.22),Vector3(2.22,.92,.10),"b_wood_aged")]
	for x:float in [-.89,-.56,-.24,.27,.64,.95]:
		details.append(k._box_item(Vector3(x,1.82,1.14),Vector3(.08,.33,.09),"zinc"))
	for y:float in [.50,.84,1.15]:
		details.append(k._box_item(Vector3(-.77,y,1.06),Vector3(.92,.11,.39),"wood_floor"))
	if level>=2:
		k.box("spares-cabinet",Vector3(.76,.68,1.00),Vector3(.89,1.36,.77),"painted_metal")
		for y:float in [.37,.69,1.01]:details.append(k._box_item(Vector3(.76,y,.59),Vector3(.65,.09,.07),"zinc"))
	if level>=3:
		for x:float in [-1.25,1.25]:k.box("service-frame-post:"+str(x),Vector3(x,1.25,.52),Vector3(.16,2.50,.16),"painted_metal")
		details.append(k._box_item(Vector3(0,2.51,.19),Vector3(2.69,.17,.26),"painted_metal"))
		details.append(k._box_item(Vector3(.34,2.36,.19),Vector3(.29,.23,.22),"zinc"))
		details.append(k._box_item(Vector3(.34,2.12,.19),Vector3(.08,.31,.08),"painted_metal"))
	k.detail("parts-board-and-bench-hardware",details)
	_apron(k,"repair-apron",[Vector3(-.78,0,-.94),Vector3(.78,0,-.94)],"concrete")

static func _guard(k:RefCounted,level:int)->void:
	# A raised lookout silhouette does not add a traversable floor.
	var height:float=1.06 if level==1 else 1.65
	var braces:Array=[]
	for x:float in [-.87,.87]:
		for z:float in [.07,1.16]:
			k.box("lookout-foot:%s:%s"%[x,z],Vector3(x,.13,z),Vector3(.32,.26,.32),"stone_masonry")
			k.box("lookout-post:%s:%s"%[x,z],Vector3(x,height/2+.13,z),Vector3(.19,height+.12,.19),"b_wood_aged")
		braces.append(k._beam_item(Vector3(x,.34,1.14),Vector3(x,height+.05,.11),.14))
	k.box("lookout-deck",Vector3(0,height+.09,.61),Vector3(2.13,.18,1.64),"b_wood_aged")
	var fittings:Array=[]
	for x:float in [-.96,.96]:
		fittings.append(k._box_item(Vector3(x,height+.49,.59),Vector3(.13,.15,1.48),"b_wood_aged"))
		for z:float in [.01,1.22]:fittings.append(k._box_item(Vector3(x,height+.39,z),Vector3(.13,.54,.13),"b_wood_aged"))
	fittings.append(k._box_item(Vector3(0,height+.49,1.28),Vector3(1.94,.15,.13),"b_wood_aged"))
	if level>=2:
		for x:float in [-.90,.90]:
			k.box("lookout-roof-post:"+str(x),Vector3(x,2.24,1.16),Vector3(.13,1.10,.13),"b_wood_aged")
		k.roof("lookout-roof",Vector3(0,0,.65),2.43,1.62,2.70,.32,"architecture_gray_roof")
	if level>=3:
		k.box("rear-windbreak",Vector3(0,2.08,1.32),Vector3(1.54,.66,.12),"painted_metal")
		fittings.append(k._box_item(Vector3(1.30,2.48,.41),Vector3(.11,1.46,.11),"b_wood_aged"))
		fittings.append(k._box_item(Vector3(1.30,2.93,.36),Vector3(.34,.37,.26),"zinc"))
	k.detail("lookout-rails-and-cross-bracing",fittings,braces)
	_apron(k,"lookout-front",[Vector3(0,0,-.84)],"stone_masonry")

static func _supply(k:RefCounted,level:int)->void:
	k.shed("dispatch-shelter",Vector3(0,0,.65),2.80,1.64,2.38,.46,"architecture_gray_roof")
	k.wall("sorting-back",Vector3(0,1.09,1.34),Vector3(2.48,2.18,.16),"b_wood_aged",Vector3.BACK,"blank")
	var details:Array=[]
	for x:float in [-.75,.75]:
		k.box("dispatch-bench:"+str(x),Vector3(x,.49,.78),Vector3(1.02,.98,.55),"b_wood_aged")
		details.append(k._box_item(Vector3(x,1.02,.76),Vector3(1.14,.12,.68),"zinc"))
		if level>=2:details.append(k._box_item(Vector3(x,1.43,1.14),Vector3(1.13,.10,.34),"wood_floor"))
	if level>=3:k.box("route-board",Vector3(0,2.04,-.01),Vector3(1.34,.38,.11),"painted_metal")
	k.detail("dispatch-benches-and-empty-shelves",details)
	_apron(k,"dispatch-loading-bays",[Vector3(-.74,0,-.68),Vector3(.74,0,-.68)],"concrete")

static func _radio(k:RefCounted,level:int)->void:
	# Radio operation stays with the existing interaction owner.
	k.lean_to("radio-hood",Vector3(-.30,0,.76),2.17,1.36,2.04,2.38,"zinc")
	k.box("radio-console",Vector3(-.37,.49,.74),Vector3(1.54,.98,.71),"b_wood_aged")
	k.box("radio-cabinet",Vector3(-.43,1.22,.79),Vector3(1.16,.48,.48),"painted_metal")
	var details:Array=[k._box_item(Vector3(-.57,1.31,.535),Vector3(.59,.11,.045),"zinc")]
	var mast:float=2.50 if level==1 else 3.05
	var beams:Array=[
		k._beam_item(Vector3(.92,.10,.59),Vector3(.92,mast,.59),.11,"zinc"),
		k._beam_item(Vector3(.50,mast-.23,.59),Vector3(1.34,mast-.23,.59),.065,"painted_metal")]
	if level>=2:beams.append(k._beam_item(Vector3(.33,mast-.05,.59),Vector3(1.45,mast-.05,.59),.065,"zinc"))
	if level>=3:
		beams.append(k._beam_item(Vector3(.92,mast-.29,.05),Vector3(.92,mast-.29,1.32),.065,"zinc"))
		details.append(k._box_item(Vector3(.94,.35,.69),Vector3(.56,.66,.56),"old_brick"))
	k.detail("radio-controls-and-mast",details,beams)

static func _apron(k:RefCounted,id:String,centers:Array,material:String)->void:
	var pieces:Array=[]
	for p:Vector3 in centers:
		pieces.append(k._box_item(p+Vector3(0,.022,0),Vector3(1.16,.035,.75),material))
		pieces.append(k._box_item(p+Vector3(0,.042,-.34),Vector3(1.10,.028,.07),"painted_metal"))
	k.detail(id,pieces)
