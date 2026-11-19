extends RefCounted
## Scenario three: explicit usable rooms, empty working fixtures and repairable shells.
## Fixed fixtures never stand in for stocks. Three sleeping positions are real entities.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const Housing=preload("res://scripts/modules/module_housing.gd")
const Compact=preload("res://scripts/modules/compact_geometry.gd")
const FamilyArt=preload("res://scripts/modules/village_family_art.gd")
const CivicArt=preload("res://scripts/modules/village_civic_art.gd")
static func supports(d:Dictionary)->bool:return d.get("village_geometry",{}).get("version")==1
static func parts(d:Dictionary)->Array:
	var family:String=str(d.get("village_family_art",""))
	if not family.is_empty():
		var level:int=int(d.village_tier)
		if family in ["water","kitchen","repair","guard","supply"]:return CivicArt.parts(family,level,[])
		var rows:=FamilyArt.parts(family,level,_baseline(d))
		return rows+_chapter_parts(d,false) if d.get("chapter_geometry",false) else rows
	return _baseline(d)

static func _chapter_parts(d:Dictionary,damaged:bool)->Array:
	var b:=Kit.new();var boxes:Array=[];var braces:Array=[]
	var family:String=d.get("village_family_art","")
	if family=="warehouse":
		# Continuous loading lintel and separated bays identify the depot even empty.
		boxes.append(b._box_item(Vector3(0,2.19,-.12),Vector3(2.66,.24,.17),"b_wood_aged" if damaged else "painted_metal"))
		for side:float in [-1.0,1.0]:
			boxes.append(b._box_item(Vector3(side*1.23,.91,-.12),Vector3(.13,1.82,.15),"b_wood_aged"))
			boxes.append(b._box_item(Vector3(side*.74,2.19,-.221),Vector3(.56,.15,.045),"old_brick" if damaged else "zinc"))
			if damaged:braces.append(b._beam_item(Vector3(side*1.23,.19,-.245),Vector3(side*.58,1.84,-.245),.09,"b_wood_aged"))
			else:boxes.append(b._box_item(Vector3(side*.73,.035,-1.62),Vector3(.75,.06,.12),"painted_metal"))
	elif family in ["sawmill","workshop"]:
		if family=="sawmill":
			# Feed cradle on the log side, four rollers on the board side.
			for z:float in [-1.23,-.67]:boxes.append(b._box_item(Vector3(-1.57,1.22,z),Vector3(.69,.10,.10),"b_wood_aged"))
			for x:float in [.60,.94,1.28,1.65]:boxes.append(b._box_item(Vector3(x,1.042,-.95),Vector3(.09,.055,.65),"zinc"))
		else:
			boxes.append(b._box_item(Vector3(.91,1.28,1.18),Vector3(.70,.18,.19),"painted_metal"))
			for x:float in [.70,.91,1.12]:boxes.append(b._box_item(Vector3(x,1.51,1.16),Vector3(.09,.29,.075),"zinc"))
	elif family=="home":
		for side:float in [-1.0,1.0]:
			boxes.append(b._box_item(Vector3(side*1.93,.25,-2.91),Vector3(1.18,.17,.12),"old_brick" if damaged else "stone_masonry"))
			if damaged:braces.append(b._beam_item(Vector3(side*2.38,.43,-2.87),Vector3(side*1.68,.73,-2.87),.08,"b_wood_aged"))
			else:boxes.append(b._box_item(Vector3(side*1.93,.56,-2.88),Vector3(1.16,.12,.15),"b_wood_aged"))
	b.detail("chapter-service-character",boxes,braces)
	return b.rows

static func _baseline(d:Dictionary)->Array:
	if d.has("compact_kind"):return Compact.parts(d.compact_kind)
	var b:=Kit.new();var kind:String=str(d.village_geometry.kind)
	if d.shape=="home":
		# A real 1.5m doorway and a clear transverse aisle in front of the beds.
		for side:float in [-1.0,1.0]:
			b.wall("home-side:"+str(side),Vector3(side*2.60,1.38,1.0),Vector3(.20,2.76,3.36),"cream_plaster",Vector3(side,0,0))
			b.wall("home-door-jamb:"+str(side),Vector3(side*1.69,1.38,-.58),Vector3(1.88,2.76,.20),"cream_plaster",Vector3.FORWARD)
		b.box("home-door-lintel",Vector3(0,2.48,-.58),Vector3(1.5,.56,.20),"b_wood_aged")
		b.wall("home-rear",Vector3(0,1.38,2.58),Vector3(5.2,2.76,.20),"old_brick",Vector3.BACK)
		# Two independently restorable roof spans make the missing section physical.
		b.roof("home-roof-west",Vector3(-1.4,0,1),2.8,3.8,2.80,1.0,"architecture_gray_roof","cream_plaster")
		b.roof("home-roof-east",Vector3(1.4,0,1),2.8,3.8,2.80,1.0,"architecture_gray_roof","cream_plaster")
		b.lean_to("home-porch",Vector3(0,0,-1.45),3.4,1.55,2.22,2.74,"zinc")
		for side:float in [-1.0,1.0]:b.box("court-front:"+str(side),Vector3(side*1.92,.35,-2.75),Vector3(1.76,.7,.22),"old_brick")
		b.box("stove-hearth",Vector3(2.20,.42,-1.54),Vector3(.65,.84,.70),"old_brick")
		b.box("stove-chimney",Vector3(2.32,1.9,-1.54),Vector3(.30,2.1,.34),"old_brick")
		if kind.ends_with("expanded"):b.lean_to("repaired-entry-gallery",Vector3(-1.95,0,-1.45),1.55,1.55,2.24,2.74)
	elif d.shape=="warehouse":
		b.shed("warehouse-loading-roof",Vector3.ZERO,5.8,5.8,2.65,.95,"architecture_gray_roof")
		b.wall("warehouse-rear",Vector3(0,1.18,2.63),Vector3(5.1,2.36,.18),"b_wood_aged",Vector3.BACK,"blank")
		# Tall empty shelving and two open loading bays identify actual storage.
		for x:float in [-1.65,1.65]:
			for side:float in [-1.0,1.0]:b.box("rack-upright:%s:%s"%[x,side],Vector3(x+side*.65,1.05,1.90),Vector3(.12,2.1,.66),"b_wood_aged")
			for y:float in [.20,1.0,1.82]:b.box("empty-shelf:%s:%s"%[x,y],Vector3(x,y,1.90),Vector3(1.42,.10,.72),"b_wood_aged")
		b.box("loading-header",Vector3(0,2.42,-2.44),Vector3(4.8,.24,.22),"b_wood_aged")
		# Fixed crate-outline signage contains no goods and creates no stock.
		b.box("warehouse-sign",Vector3(.8,2.12,-2.56),Vector3(1.35,.48,.10),"old_brick",false)
		for x:float in [.26,.8,1.34]:b.box("crate-icon:"+str(x),Vector3(x,2.12,-2.63),Vector3(.06,.36,.05),"b_wood_aged",false)
		if kind.ends_with("expanded"):
			for x:float in [-2.20,2.20]:
				for y:float in [.4,1.4,2.3]:b.box("expanded-side-rack:%s:%s"%[x,y],Vector3(x,y,.15),Vector3(.68,.12,1.72),"painted_metal")
	elif d.shape=="manual":
		b.shed("hand-saw-shelter",Vector3.ZERO,3.9,2.9,2.45,.72,"zinc")
		b.wall("workshop-backboard",Vector3(0,1.20,1.30),Vector3(3.30,2.40,.16),"b_wood_aged",Vector3.BACK,"blank")
		# Empty long-stock cradles and a fixed bow-saw frame, away from the bench.
		for z:float in [.72,1.1]:
			for side:float in [-1.0,1.0]:b.box("stock-cradle:%s:%s"%[z,side],Vector3(-1.5+side*.24,.48,z),Vector3(.12,.96,.15),"b_wood_aged")
		for x:float in [.7,1.3]:b.box("bow-saw-post:"+str(x),Vector3(x,1.48,1.12),Vector3(.07,.66,.07),"b_wood_aged")
		b.box("bow-saw-blade",Vector3(1.0,1.20,1.12),Vector3(.67,.025,.025),"painted_metal",false)
		b.box("bow-saw-top",Vector3(1.0,1.79,1.12),Vector3(.67,.07,.07),"b_wood_aged",false)
	else:
		# Dedicated mill: a long feed bed, large toothed blade, motor bay and flue.
		b.shed("sawmill-canopy",Vector3.ZERO,4.8,3.8,2.65,.85,"zinc")
		# Keep the actual cutting group near the open work face, inside z=-2.
		# The work-port body collar begins at z=-2.7 and remains clear.
		b.box("sawmill-feed-bed",Vector3(0,.80,-1.28),Vector3(3.90,.16,.82),"painted_metal")
		for x:float in [-1.65,1.65]:b.box("sawmill-trestle:"+str(x),Vector3(x,.4,-1.28),Vector3(.20,.80,.70),"b_wood_aged")
		b.box("fixed-power",Vector3(.95,.45,1.35),Vector3(1.0,.9,.68),"painted_metal")
		b.box("mill-exhaust",Vector3(1.08,2.10,1.35),Vector3(.22,2.50,.22),"painted_metal")
		var blade:=b.box("mill-toothed-blade",Vector3(0,1.05,-1.28),Vector3(.06,1.20,1.20),"zinc",false)
		blade.architecture_detail={"version":Kit.DETAIL_VERSION,"kind":"details","local_size":blade.size,"discs":[{"center":{"x":.03,"y":.60,"z":.60},"radius":.60,"thickness":.06,"teeth":24,"material":"zinc"}]}
	return b.rows

static func current_parts(v:Dictionary,d:Dictionary,source:Array)->Array:
	if not supports(d) or not v.get("restoration") is Dictionary or v.restoration.get("completed",false):return source
	var result:Array=[]
	for original:Dictionary in source:
		var id:String=str(original.id)
		# Open roof gaps have neither an invisible collider nor a complete render.
		if id.begins_with("home-roof-east") or id.begins_with("warehouse-loading-roof:roof") or id.begins_with("empty-shelf:"):continue
		if d.get("chapter_geometry",false) and id=="chapter-service-character":
			result.append_array(_chapter_parts(d,true));continue
		var p:Dictionary=original.duplicate(true)
		if id.begins_with("court-front:"):p.size.y=.32;p.center.y=.16
		result.append(p)
	return result

static func beds(v:Dictionary,d:Dictionary)->Array:
	if not supports(d) or d.shape!="home":return []
	var result:Array=[];var count:int=int(d.mechanism.beds)
	for i:int in count:
		var compact:bool=d.get("compact_kind")=="cottage"
		var x:float=(-.86 if i%2==0 else .86) if compact else (float(i%3)-1.0)*1.70;var level:int=int(i/(2 if compact else 3))
		var z:float=.65 if compact else 1.45
		var slot:Dictionary={"position":[x,0,z],"quarter_turn":0,"level":level,"approach":[x,0,-.75 if compact else .05],"room_id":"village-home-room"}
		var at:Dictionary=G.json_point(G.point(v.position)).merged({"regionId":v.region,"buildingId":null,"storeyId":null})
		var a:Vector3=G.point(v.position)+G.rotate(Vector3(x-.49,.10+level*1.02,-.36 if compact else .44),int(v.quarter_turn));var b:Vector3=G.point(v.position)+G.rotate(Vector3(x+.49,.74+level*1.02,1.66 if compact else 2.46),int(v.quarter_turn))
		var room:AABB=_room(v,d)
		var bed:=Housing.bed_entity(v,i,slot,at,AABB(a.min(b),a.max(b)-a.min(b)),room,true)
		bed.data.village_shelter=true;result.append(bed)
	return result

static func _room(v:Dictionary,d:Dictionary)->AABB:
	if d.get("compact_kind")=="cottage":return Housing.room_box(v,{"center":{"x":0,"y":0,"z":.24},"width":3.4,"depth":3.0})
	return Housing.room_box(v,{"center":{"x":0,"y":0,"z":1.0},"width":5.0,"depth":3.2})

static func room_metadata(v:Dictionary,d:Dictionary,part:Dictionary)->Dictionary:
	if not supports(d) or d.shape!="home" or not str(part.id).begins_with("home-"):return {}
	var role:String="trim";var normal:=Vector3.ZERO;var id:String=str(part.id)
	if part.has("roof_mesh") or id.contains(":roof") or id.begins_with("home-roof-"):role="roof"
	elif id.begins_with("home-side:"):
		role="wall";normal=Vector3(signf(float(part.center.x)),0,0)
	elif id.begins_with("home-door-"):role="wall";normal=Vector3.FORWARD
	elif id=="home-rear":role="wall";normal=Vector3.BACK
	return {"version":2,"room_id":str(v.id)+":village-home-room","bounds":G.json_box(_room(v,d)),"role":role,"normal":G.json_point(G.rotate(normal,int(v.quarter_turn)))}
