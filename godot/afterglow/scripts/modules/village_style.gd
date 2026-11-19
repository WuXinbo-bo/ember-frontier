extends RefCounted
## Explicit instance-pinned additions for NEW scenario-three construction only.
## No historical definition/instance is reinterpreted; fixtures contain no cargo.
const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
static func eligible(d:Dictionary)->bool:return not d.has("village_geometry") and d.get("mechanism",{}).get("family") in ["sawmill","warehouse"]
static func parts(v:Dictionary,d:Dictionary,source:Array)->Array:
	if v.get("config",{}).get("village_style_v1")!=1 or not eligible(d):return source
	var b:=Kit.new();var bounds:=G.aabb(d.footprint);var w:float=bounds.size.x;var depth:float=bounds.size.z
	var family:String=str(d.mechanism.family);var tier:int=int(d.mechanism.tier)
	if family=="sawmill":
		# Long EMPTY infeed cradle is fixed hardware, not free harvested logs.
		var x:float=bounds.position.x+.42;var rear:float=bounds.end.z-.85
		for z:float in [rear-.7,rear+.3]:
			for side:float in [-1.0,1.0]:b.box("village-style:infeed-post:%s:%s"%[z,side],Vector3(x+side*.26,.5,z),Vector3(.11,1.0,.15),"b_wood_aged")
		b.box("village-style:long-feed-rail",Vector3(x,.38,rear-.2),Vector3(.72,.13,1.6),"b_wood_aged")
		if tier>=2:
			var a:Array=d.get("machine_work_point",[0,1.1,-depth/2+.25]);var tooth:=Vector3(a[0],a[1],a[2])
			# The original machine stays fixed. A .76m blade fits its paid apron;
			# the previous .84m blade crossed the front footprint by .03m.
			var blade:=b.box("village-style:toothed-blade",tooth+Vector3(0,.12,.04),Vector3(.065,.76,.76),"zinc")
			blade.architecture_detail={"version":Kit.DETAIL_VERSION,"kind":"details","local_size":blade.size,"discs":[{"center":{"x":.0325,"y":.38,"z":.38},"radius":.38,"thickness":.065,"teeth":24,"material":"zinc"}]}
			# Original power housing and full-height flue remain the only motor
			# hardware. A detached marker above the roof corner would float.
		else:
			# Low tier remains MANUAL: a visible suspended bow-saw, no free motor.
			for side:float in [-1.0,1.0]:b.box("village-style:bow-saw:"+str(side),Vector3(side*.7,2.1,bounds.position.z+.30),Vector3(.09,.54,.09),"b_wood_aged",false)
			b.box("village-style:bow-saw-back",Vector3(0,2.35,bounds.position.z+.30),Vector3(1.48,.09,.09),"b_wood_aged",false)
			b.box("village-style:bow-saw-teeth",Vector3(0,1.86,bounds.position.z+.30),Vector3(1.48,.035,.045),"zinc",false)
	else:
		# An open loading header and crate-outline mark distinguish stores from homes.
		var front:float=bounds.position.z+.24;var sign_y:float=minf(2.32,bounds.size.y-.7)
		b.box("village-style:warehouse-loading-sign",Vector3(0,sign_y,front),Vector3(minf(w-1.0,2.6),.48,.12),"old_brick",false)
		for x:float in [-.50,0,.50]:b.box("village-style:crate-stave:"+str(x),Vector3(x,sign_y,front-.075),Vector3(.07,.35,.045),"b_wood_aged",false)
		for y:float in [sign_y-.17,sign_y+.17]:b.box("village-style:crate-rim:"+str(y),Vector3(0,y,front-.075),Vector3(1.07,.06,.045),"b_wood_aged",false)
		# Three clearly legible shelf levels; exact body volumes are authoritative.
		var shelf_x:float=bounds.end.x-.5;var shelf_z:float=bounds.end.z-.75
		for z:float in [shelf_z-.6,shelf_z+.6]:b.box("village-style:store-rack-upright:"+str(z),Vector3(shelf_x,.95,z),Vector3(.14,1.9,.14),"b_wood_aged")
		for y:float in [.18,.92,1.66]:b.box("village-style:empty-store-shelf:"+str(y),Vector3(shelf_x,y,shelf_z),Vector3(.65,.10,1.35),"b_wood_aged")
	var result:Array=source.duplicate(true)
	for part:Dictionary in b.rows:
		# Every solid stays within the existing paid footprint. Exterior service
		# feet remain outside it, so their reserved body collar cannot be blocked.
		var volume:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))
		if part.solid and (volume.position.x<bounds.position.x or volume.end.x>bounds.end.x or volume.position.z<bounds.position.z or volume.end.z>bounds.end.z):continue
		result.append(part)
	return result
