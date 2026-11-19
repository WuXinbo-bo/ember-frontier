extends RefCounted
## Finite placement combinations inside existing two-region content. Operates
## on B's resolved pad/port/use bounds; never invents a footprint or rotates a
## family beyond its published orientation. Missing policy keeps old layouts.
const POLICY={"id":"rural-bounded-layout","version":1}
const POSITIONS={
	# Preserve the existing readable home/field/rear-lane composition: moving
	# it increased long risers in the actual713/973/275 paired raster probes.
	# Finite variation comes from the three real Village parcels below and
	# existing B family selection, rather than degrading the opening yard.
	"home":[[[8,26],[4,8]]],
	"village":[[[8,38],[44,20],[8,8]],[[12,39],[44,19],[9,7]],[[10,40],[45,18],[12,8]],[[14,38],[44,21],[7,7]]]
}

static func valid_policy(value:Variant)->bool:
	return value is Dictionary and value.size()==2 and value.get("id")==POLICY.id and (value.get("version") is int or value.get("version") is float) and value.get("version")==1

static func _translate(parcel:Dictionary,dx:float,dz:float)->void:
	parcel.origin.x+=dx;parcel.origin.z+=dz
	for i in 4:parcel.pad.xz[i]+=dx if i%2==0 else dz
	for port:Dictionary in parcel.entrance_ports:port.position.x+=dx;port.position.z+=dz
	for reserve:Dictionary in parcel.use_reservations:
		reserve.bounds.min.x+=dx;reserve.bounds.max.x+=dx;reserve.bounds.min.z+=dz;reserve.bounds.max.z+=dz
	for anchor:Dictionary in parcel.npc_anchors:anchor.position.x+=dx;anchor.position.z+=dz

static func constraint_error(parcels:Array,coord:Vector2i)->String:
	var ox:float=coord.x*64;var oz:float=coord.y*64
	for i in parcels.size():
		var a:Array=parcels[i].pad.xz
		if a[0]<ox+1 or a[1]<oz+1 or a[2]>ox+63 or a[3]>oz+63:return "region-margin"
		# Preserve a 3m corridor around the existing road hub. Road A* and B's
		# final complete body/door/use-point proofs still run after this filter.
		if ox+34>=a[0]-3 and ox+34<=a[2]+3 and oz+30>=a[1]-3 and oz+30<=a[3]+3:return "road-hub"
		# The higher workshop apron must leave the established central road's
		# full grading collar. A 6m gap passed footprint-only checks yet formed
		# a narrow double riser at seed275196493; retain that negative fixture.
		if parcels[i].site_id=="repair" and a[0]<ox+41.5:return "workshop-grade-collar"
		for j in range(i+1,parcels.size()):
			var b:Array=parcels[j].pad.xz
			var gap:=Vector2(maxf(maxf(a[0]-b[2],b[0]-a[2]),0),maxf(maxf(a[1]-b[3],b[1]-a[3]),0)).length()
			if gap<2.5:return "pad-corridor"
	return ""

static func apply(seed:int,coord:Vector2i,parcels:Array)->Array:
	var kind:String="home" if coord==Vector2i.ZERO else "village" if coord==Vector2i(0,-1) else ""
	if kind.is_empty() or parcels.is_empty():return parcels
	var candidates:Array=POSITIONS[kind]
	var start:int=(str(seed)+":bounded-layout-v1:"+kind).sha256_text().substr(0,8).hex_to_int()%candidates.size()
	var rejected:Array=[]
	for attempt in candidates.size():
		var id:int=(start+attempt)%candidates.size();var positions:Array=candidates[id]
		var result:Array=parcels.duplicate(true)
		for i in result.size():
			_translate(result[i],coord.x*64+positions[i][0]-float(result[i].origin.x),coord.y*64+positions[i][1]-float(result[i].origin.z))
		var error:String=constraint_error(result,coord)
		if not error.is_empty():rejected.append({"candidate":id,"reason":error});continue
		for parcel:Dictionary in result:parcel.layout_choice={"policy":POLICY.duplicate(),"candidate":id,"attempts":attempt+1,"rejected":rejected.duplicate(true),"fallback":false}
		return result
	# A finite explicit original-layout fallback, still subject to the same
	# downstream profile/overlap/road/body proofs. Never silently change seed.
	var fallback:Array=parcels.duplicate(true)
	for parcel:Dictionary in fallback:parcel.layout_choice={"policy":POLICY.duplicate(),"candidate":0,"attempts":candidates.size(),"rejected":rejected.duplicate(true),"fallback":true}
	return fallback
