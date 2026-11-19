extends RefCounted

const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const Regional=preload("res://scripts/modules/village_regional_catalog.gd")
const WOOD="b_wood_aged"
const STEEL="painted_metal"
const BRICK="old_brick"

static func parts(id:String)->Array:
	var k:=Kit.new()
	match id:
		Regional.FRAME:_mill(k)
		Regional.STORE:_store(k)
		Regional.HOME:_home(k)
		Regional.SHED:_shed(k)
	return k.rows

static func _mill(k:Kit)->void:
	k.lean_to("mill-weather-canopy",Vector3(0,0,.98),3.55,1.72,2.23,2.83,"zinc")
	k.wall("mill-tool-board",Vector3(0,1.18,1.72),Vector3(3.52,2.36,.16),WOOD,Vector3.BACK,"blank")
	k.box("saw-bed",Vector3(0,.79,-.68),Vector3(3.70,.18,.70),STEEL)
	for x:float in [-1.59,-.65,.65,1.59]:
		k.box("bed-leg:"+str(x),Vector3(x,.36,-.68),Vector3(.17,.72,.56),STEEL)
	k.box("drive-plinth",Vector3(.79,.16,.15),Vector3(.94,.32,.68),"concrete")
	k.box("fixed-power-housing",Vector3(.79,.60,.15),Vector3(.70,.56,.50),STEEL)
	var details:Array=[]
	for x:float in [-1.64,-1.30,-.96,-.62,.62,.96,1.30,1.64]:
		details.append(k._box_item(Vector3(x,.92,-.68),Vector3(.12,.08,.67),"zinc"))
	for x:float in [-.23,.23]:
		details.append(k._box_item(Vector3(x,1.01,-.68),Vector3(.08,.24,.67),"zinc"))
	for x:float in [-1.22,1.22]:
		details.append(k._box_item(Vector3(x,.025,-1.55),Vector3(1.1,.04,.54),"wood_floor"))
	k.detail("rollers-guides-and-loading-boards",details)

static func _store(k:Kit)->void:
	k.roof("store-roof",Vector3(0,0,-.13),3.90,2.13,2.30,.71,"architecture_gray_roof","cream_plaster")
	k.wall("store-front",Vector3(0,1.15,-1.18),Vector3(3.52,2.30,.15),"cream_plaster",Vector3.FORWARD)
	k.wall("store-dividing-wall",Vector3(0,1.05,.56),Vector3(3.52,2.10,.15),BRICK,Vector3.BACK,"blank")
	for x:float in [-1.74,1.74]:
		k.wall("store-side:"+str(x),Vector3(x,1.10,-.32),Vector3(.14,2.20,1.67),WOOD,Vector3(signf(x),0,0),"blank")
	k.lean_to("rear-loading-awning",Vector3(0,0,1.27),3.65,1.27,2.12,2.36,"zinc")
	for x:float in [-1.53,1.53]:k.box("loading-awning-post:"+str(x),Vector3(x,1.08,1.78),Vector3(.12,2.16,.13),STEEL)
	for y:float in [.24,.79,1.34]:k.box("rear-stock-shelf:"+str(y),Vector3(-.63,y,1.11),Vector3(1.46,.10,.66),WOOD)
	k.box("front-closed-counter",Vector3(-.66,.85,-1.37),Vector3(1.61,.19,.31),WOOD)
	k.detail("postal-sign-and-loading-stripes",[k._box_item(Vector3(-.66,1.69,-1.28),Vector3(1.45,.37,.12),STEEL),k._box_item(Vector3(-.66,1.69,-1.35),Vector3(.76,.075,.028),"cream_plaster"),k._box_item(Vector3(-.65,.020,1.80),Vector3(1.64,.03,.16),"concrete")])

static func _home(k:Kit)->void:
	k.roof("house-tile-roof",Vector3(-.30,0,.27),3.52,2.71,2.49,.84,"roof_tile","cream_plaster")
	k.wall("house-front",Vector3(-.30,1.22,-.94),Vector3(3.22,2.44,.18),"cream_plaster",Vector3.FORWARD)
	k.wall("house-back",Vector3(-.30,1.22,1.48),Vector3(3.22,2.44,.18),BRICK,Vector3.BACK)
	for x:float in [-1.89,1.29]:k.wall("house-side:"+str(x),Vector3(x,1.22,.27),Vector3(.16,2.44,2.37),"cream_plaster",Vector3(signf(x),0,0),"blank")
	k.lean_to("side-porch",Vector3(1.80,0,.49),1.18,1.75,1.97,2.42,"zinc")
	k.box("stove-chimney",Vector3(.68,2.17,.95),Vector3(.38,3.68,.36),BRICK)
	k.box("front-stoop",Vector3(-.32,.10,-1.39),Vector3(1.18,.20,.58),BRICK)
	k.detail("door-shutters-and-stoop-trim",[k._box_item(Vector3(-.32,1.08,-1.06),Vector3(.82,1.80,.11),WOOD),k._box_item(Vector3(.61,1.24,-1.06),Vector3(.77,.67,.10),"architecture_window"),k._box_item(Vector3(-1.25,1.24,-1.06),Vector3(.76,.67,.10),"architecture_window"),k._box_item(Vector3(.68,3.99,.95),Vector3(.52,.13,.49),"zinc")])

static func _shed(k:Kit)->void:
	k.lean_to("field-depot-roof",Vector3(0,0,1.04),5.32,1.63,2.12,2.79,"zinc")
	k.wall("field-depot-rear",Vector3(0,1.14,1.82),Vector3(5.10,2.28,.15),WOOD,Vector3.BACK,"blank")
	for x:float in [-2.40,0,2.40]:k.box("field-depot-upright:"+str(x),Vector3(x,1.08,.45),Vector3(.14,2.16,.17),STEEL)
	for x:float in [-1.27,1.27]:
		for y:float in [.24,.82,1.40]:k.box("produce-rack:%s:%s"%[x,y],Vector3(x,y,1.17),Vector3(2.10,.10,.75),WOOD)
	var details:Array=[]
	for x:float in [-1.40,1.40]:
		details.append(k._box_item(Vector3(x,.023,-1.07),Vector3(1.56,.038,.73),"concrete"))
		for z:float in [-1.45,-.69]:details.append(k._box_item(Vector3(x,.046,z),Vector3(1.56,.014,.04),STEEL))
	k.detail("separate-load-and-unload-pads",details)
