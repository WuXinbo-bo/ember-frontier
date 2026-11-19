extends RefCounted
## New-world successor: retain v7 natural features, correct measured site controls.
## Saved cells and historical model implementations remain unchanged.
const Relief=preload("res://scripts/world/local_relief.gd")
const Broad=preload("res://scripts/world/broad_terraces.gd")
const MODEL="site-relief-v8"
const PITCH=Relief.PITCH
const SIDE=Relief.SIDE
const RELAX=Relief.RELAX
const PAD_LIMIT=Relief.PAD_LIMIT

static func _edge_low(noise:FastNoiseLite,r:Array)->float:
	var low:=INF
	var nx:int=ceili((r[2]-r[0])/PITCH);var nz:int=ceili((r[3]-r[1])/PITCH)
	for i in nx+1:
		var x:float=lerpf(r[0],r[2],float(i)/nx)
		low=minf(low,minf(Relief._base(noise,x,r[1]),Relief._base(noise,x,r[3])))
	for i in nz+1:
		var z:float=lerpf(r[1],r[3],float(i)/nz)
		low=minf(low,minf(Relief._base(noise,r[0],z),Relief._base(noise,r[2],z)))
	return low

static func fit_pads(parcels:Array,noise:FastNoiseLite)->void:
	Relief.fit_pads(parcels,noise)
	for p:Dictionary in parcels:
		# A centre on a hill cannot raise the whole full B footprint several
		# steps above its lowest edge. Bound fill there to one half-metre.
		var target:float=minf(float(p.pad.height),Relief._half(_edge_low(noise,p.pad.xz)+0.5))
		var delta:float=target-float(p.pad.height)
		p.origin.y+=delta;p.pad.height=target
		for port:Dictionary in p.entrance_ports:port.position.y+=delta
		for reserve:Dictionary in p.use_reservations:reserve.bounds.min.y+=delta;reserve.bounds.max.y+=delta
		for anchor:Dictionary in p.npc_anchors:anchor.position.y+=delta
	Broad.fit_pads(parcels)

static func landforms(original:Array,noise:FastNoiseLite)->Array:
	var result:Array=Relief.landforms(original,noise)
	for land:Dictionary in result:
		if land.use=="dry-ditch":land.surface_shape={"kind":"closed-local-channel-v1","depth_m":0.5,"half_width_m":3.0,"end_taper_m":4.0,"meander_m":1.25}
	return result

static func channel_weight(_noise:FastNoiseLite,land:Dictionary,x:float,z:float)->float:
	var r:Array=land.xz;var shape:Dictionary=land.surface_shape
	if z<=r[1] or z>=r[3]:return 0.0
	var t:float=(z-float(r[1]))/(float(r[3])-float(r[1]))
	var center:float=(float(r[0])+float(r[2]))*0.5+sin(TAU*t)*float(shape.meander_m)
	var ends:float=smoothstep(0.0,float(shape.end_taper_m),z-float(r[1]))*smoothstep(0.0,float(shape.end_taper_m),float(r[3])-z)
	return (1.0-smoothstep(0.0,float(shape.half_width_m),absf(x-center)))*ends

static func material_contains(noise:FastNoiseLite,land:Dictionary,x:float,z:float)->bool:
	return channel_weight(noise,land,x,z)>=0.5 if land.has("surface_shape") else Relief._rect_distance(x,z,land.xz)==0.0

static func _desired(noise:FastNoiseLite,x:float,z:float,lands:Array,features:Array)->float:
	var height:float=Relief._base_from(noise,x,z,features)
	for land:Dictionary in lands:
		if land.has("surface_shape"):
			# Relative shallow cut, not a fixed absolute trench through a hill.
			height-=float(land.surface_shape.depth_m)*channel_weight(noise,land,x,z)
		else:
			var distance:float=Relief._rect_distance(x,z,land.xz)
			if distance<4.0:height=lerpf(height,float(land.height),1.0-smoothstep(0.0,4.0,distance))
	return clampf(height,-0.5,3.0)

static func prepare(plan:Dictionary,noise:FastNoiseLite,lands:Array)->void:
	var origin:=Vector2i(int(plan.region_coord.x)*32-1,int(plan.region_coord.z)*32-1)
	var features:Array=Relief._features(noise.seed,Vector2i(int(plan.region_coord.x),int(plan.region_coord.z)))
	var side:int=SIDE+RELAX*2
	var values:=PackedInt32Array();values.resize(side*side)
	for z in side:
		for x in side:
			values[x+side*z]=floori(_desired(noise,(origin.x+x-RELAX+0.5)*PITCH,(origin.y+z-RELAX+0.5)*PITCH,lands,features)*2.0+0.5)
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
	plan.height.natural_surface={"version":1,"relief_features":features,"pitch":PITCH,"side":SIDE,"origin_cell":[origin.x,origin.y],"height_half_metres":cells,"pad_influence_limit_m":PAD_LIMIT,"pad_altered_samples":altered,"pad_altered_beyond_limit":far_altered,"semantics":"immutable local natural grade input only; saved authoritative cells are never regenerated"}

static func height(plan:Dictionary,x:float,z:float)->float:
	return Relief.height(plan,x,z)
