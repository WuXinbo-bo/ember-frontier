extends RefCounted
## Explicit new-world-only successor to v5, not an upgrade of saved cells.
## Native coherent noise owns the broad contour; pads are local safety edits.
const Broad=preload("res://scripts/world/broad_terraces.gd")
const MODEL="local-hills-v6"
const PITCH=2.0
const SIDE=35
const RELAX=7
const MIN_LEVEL=-1
const MAX_LEVEL=6
const PAD_LIMIT=14.0

static func _half(h:float)->float:
	return floorf(h*2.0+0.5)*0.5

static func _base(noise:FastNoiseLite,x:float,z:float)->float:
	# Reuse native OpenSimplex2S/FBM2 at a lower metre frequency. There is no
	# per-cell jitter and no inherited high-pad/low-base mismatch from v5.
	return clampf(1.25+noise.get_noise_2d(x*0.55,z*0.55)*2.4+noise.get_noise_2d(x*0.8+217.0,z*0.8-193.0)*0.25,MIN_LEVEL*0.5,MAX_LEVEL*0.5)

static func fit_pads(parcels:Array,noise:FastNoiseLite)->void:
	var home_height:=0.0
	for p:Dictionary in parcels:
		if p.site_id=="home":
			var r:Array=p.pad.xz
			home_height=maxf(0.0,_half(_base(noise,(r[0]+r[2])*0.5,(r[1]+r[3])*0.5)))
	for p:Dictionary in parcels:
		var r:Array=p.pad.xz
		var y:float=_half(_base(noise,(r[0]+r[2])*0.5,(r[1]+r[3])*0.5))
		if p.site_id=="home":y=home_height
		if p.site_id=="shed":y=home_height-0.5
		var delta:float=y-float(p.pad.height)
		p.origin.y+=delta;p.pad.height=y
		for port:Dictionary in p.entrance_ports:port.position.y+=delta
		for reserve:Dictionary in p.use_reservations:reserve.bounds.min.y+=delta;reserve.bounds.max.y+=delta
		for anchor:Dictionary in p.npc_anchors:anchor.position.y+=delta
	# Existing finite relaxation protects real full pad/port/reservation geometry.
	Broad.fit_pads(parcels)

static func landforms(original:Array,noise:FastNoiseLite)->Array:
	var result:Array=original.duplicate(true)
	var field_height:float=0.0
	for land:Dictionary in result:
		var r:Array=land.xz
		if land.use=="field":
			field_height=_half(clampf(_base(noise,(r[0]+r[2])*0.5,(r[1]+r[3])*0.5)-0.5,-0.5,3.0))
			land.height=field_height
		elif land.use=="field-bank":land.height=minf(field_height+0.5,3.0)
		elif land.use=="dry-ditch":land.height=_half(clampf(_base(noise,(r[0]+r[2])*0.5,(r[1]+r[3])*0.5)-0.5,-0.5,3.0))
	return result

static func _rect_distance(x:float,z:float,r:Array)->float:
	return Vector2(maxf(maxf(r[0]-x,x-r[2]),0.0),maxf(maxf(r[1]-z,z-r[3]),0.0)).length()

static func _desired(noise:FastNoiseLite,x:float,z:float,lands:Array)->float:
	var height:float=_base(noise,x,z)
	for land:Dictionary in lands:
		var distance:float=_rect_distance(x,z,land.xz)
		# A local field/ditch target, not an unbounded height cone or global pad.
		if distance<4.0:height=lerpf(height,float(land.height),1.0-smoothstep(0.0,4.0,distance))
	return clampf(height,-0.5,3.0)

static func prepare(plan:Dictionary,noise:FastNoiseLite,lands:Array)->void:
	var origin:=Vector2i(int(plan.region_coord.x)*32-1,int(plan.region_coord.z)*32-1)
	var side:int=SIDE+RELAX*2
	var values:=PackedInt32Array();values.resize(side*side)
	for z in side:
		for x in side:
			values[x+side*z]=floori(_desired(noise,(origin.x+x-RELAX+0.5)*PITCH,(origin.y+z-RELAX+0.5)*PITCH,lands)*2.0+0.5)
	# Finite min-plus graph relaxation of the natural surface. 7 is the entire
	# possible level range, so farther samples cannot lower any result. Exact
	# collars make either boundary owner see the same answer, independent of
	# region order. Eight-neighbour level delta<=1 covers diagonal body probes.
	for iteration in RELAX:
		var next:PackedInt32Array=values.duplicate()
		for z in range(1,side-1):
			for x in range(1,side-1):
				var h:int=values[x+side*z]
				for dz in range(-1,2):
					for dx in range(-1,2):h=mini(h,values[x+dx+side*(z+dz)]+1)
				next[x+side*z]=h
		values=next
	var cells:Array=[];var altered:=0;var far_altered:=0
	for z in SIDE:
		for x in SIDE:
			var wx:float=(origin.x+x+0.5)*PITCH;var wz:float=(origin.y+z+0.5)*PITCH
			var natural:float=values[x+RELAX+side*(z+RELAX)]*0.5
			var lower:float=-INF;var upper:float=INF;var nearest:float=INF
			for pad:Dictionary in plan.grade_controls:
				var distance:float=Broad.distance(wx,wz,Broad.rect(pad))
				nearest=minf(nearest,distance)
				if distance>=PAD_LIMIT:continue
				lower=maxf(lower,float(pad.height)-distance*0.25)
				upper=minf(upper,float(pad.height)+distance*0.25)
			var level:int=floori(clampf(natural,lower,upper)*2.0+0.5)
			if level!=roundi(natural*2.0):
				altered+=1
				if nearest>=PAD_LIMIT:far_altered+=1
			cells.append(level)
	plan.height.natural_surface={"version":1,"pitch":PITCH,"side":SIDE,"origin_cell":[origin.x,origin.y],"height_half_metres":cells,"pad_influence_limit_m":PAD_LIMIT,"pad_altered_samples":altered,"pad_altered_beyond_limit":far_altered,"semantics":"immutable local natural grade input only; saved authoritative cells are never regenerated"}

static func height(plan:Dictionary,x:float,z:float)->float:
	var grid:Dictionary=plan.height.natural_surface
	var ix:int=floori(x/PITCH)-int(grid.origin_cell[0]);var iz:int=floori(z/PITCH)-int(grid.origin_cell[1])
	assert(ix>=0 and iz>=0 and ix<SIDE and iz<SIDE,"v6 planning sample outside finite collar")
	return float(grid.height_half_metres[ix+SIDE*iz])*0.5
