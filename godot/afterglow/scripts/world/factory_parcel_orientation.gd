extends RefCounted
## Complete, detached v4 parcel transforms. B remains the geometry authority.
## The target is the real shared road/courtyard junction, never the camera.
const G=preload("res://scripts/buildings/building_geometry.gd")
const POLICY="road-court-v1"
const DIRECTIONS={"north":Vector3(0,0,-1),"east":Vector3(1,0,0),"south":Vector3(0,0,1),"west":Vector3(-1,0,0)}

static func _vector(a:Array)->Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

static func box(value:Dictionary,turn:int)->Dictionary:
	var a:Vector3=G.rotate(G.point(value.min),turn)
	var b:Vector3=G.rotate(G.point(value.max),turn)
	return {"min":G.json_point(a.min(b)),"max":G.json_point(a.max(b))}

static func rectangle(value:Array,turn:int)->Array:
	var a:Vector3=G.rotate(Vector3(value[0],0,value[1]),turn)
	var b:Vector3=G.rotate(Vector3(value[2],0,value[3]),turn)
	return [minf(a.x,b.x),minf(a.z,b.z),maxf(a.x,b.x),maxf(a.z,b.z)]

static func primary_port(profile:Dictionary)->Dictionary:
	for purpose:String in ["service","work","input"]:
		for port:Dictionary in profile.ports:
			if port.purpose==purpose:return port
	return profile.ports[0]

static func select(profile:Dictionary,slot_min:Vector2,road_junction:Vector2,quality:bool=false)->int:
	var primary:Dictionary=primary_port(profile)
	var best:int=0;var alignment:float=-INF;var distance:float=INF
	# Canonical tie order makes equivalent allowed-q array orders irrelevant.
	for turn:int in 4:
		if not profile.get("allowed_quarter_turns",[0]).any(func(q:Variant)->bool:return q==turn):continue
		var f:Dictionary=box(profile.footprint,turn)
		var origin:=Vector2(slot_min.x-f.min.x,slot_min.y-f.min.z)
		var normal:Vector3=G.rotate(DIRECTIONS[primary.direction],turn)
		var toward:Vector2=(road_junction-origin).normalized()
		var facing:float=Vector2(normal.x,normal.z).dot(toward)
		# Only the explicit9 branch considers the established camera. Roadward
		# service remains primary; never rotate every building for a false facade.
		if quality:
			var visible:float=Vector2(normal.x,normal.z).dot(Vector2(24,31).normalized())
			facing+=visible*0.2
		var mouth:Vector3=G.rotate(_vector(primary.position),turn)
		var travel:float=(road_junction-origin-Vector2(mouth.x,mouth.z)).length_squared()
		if facing>alignment+0.000001 or (absf(facing-alignment)<=0.000001 and travel<distance):
			best=turn;alignment=facing;distance=travel
	return best

static func parcel(profile:Dictionary,slot_min:Vector2,road_junction:Vector2,id:String,quality:bool=false)->Dictionary:
	var turn:int=select(profile,slot_min,road_junction,quality)
	var f:Dictionary=box(profile.footprint,turn)
	var x:float=slot_min.x-f.min.x;var z:float=slot_min.y-f.min.z
	var origin:Dictionary={"x":x,"y":0.0,"z":z}
	var foundation:Dictionary=profile.foundation.duplicate(true)
	foundation.pad_rectangles=[]
	var pad:Array=[x+f.min.x-1.0,z+f.min.z-1.0,x+f.max.x+1.0,z+f.max.z+1.0]
	for source:Array in profile.foundation.get("pad_rectangles",[]):
		var r:Array=rectangle(source,turn);foundation.pad_rectangles.append(r)
		pad=[minf(pad[0],x+r[0]),minf(pad[1],z+r[1]),maxf(pad[2],x+r[2]),maxf(pad[3],z+r[3])]
	var ports:Array=[];var reserves:Array=[];var anchors:Array=[]
	var primary:Dictionary=primary_port(profile)
	for source:Dictionary in profile.ports:
		var local:Vector3=G.rotate(_vector(source.position),turn)
		var normal:Vector3=G.rotate(DIRECTIONS[source.direction],turn)
		var direction:String=""
		for name:String in DIRECTIONS:
			if DIRECTIONS[name]==normal:direction=name;break
		var row:Dictionary={"id":source.id,"position":{"x":x+local.x,"y":local.y,"z":z+local.z},"direction":direction,"normal":G.json_point(normal),"width":source.get("width",1.6),"purpose":source.purpose,"use_points":[],"clearance":source.clearance.duplicate(true)}
		for i:int in source.use_points.size():
			var use:Vector3=G.rotate(_vector(source.use_points[i]),turn)
			var at:Dictionary={"x":x+use.x,"y":use.y,"z":z+use.z};row.use_points.append(at)
			var radius:float=float(source.clearance.radius)+0.5
			pad=[minf(pad[0],at.x-radius),minf(pad[1],at.z-radius),maxf(pad[2],at.x+radius),maxf(pad[3],at.z+radius)]
			var r:float=source.clearance.radius
			reserves.append({"id":id+":port:"+str(source.id)+":use:"+str(i),"port_id":source.id,"purpose":source.purpose,"bounds":{"min":{"x":at.x-r,"y":at.y,"z":at.z-r},"max":{"x":at.x+r,"y":at.y+float(source.clearance.height),"z":at.z+r}}})
			if source.id==primary.id:anchors.append({"id":id+":service:"+str(source.id)+":"+str(i),"purpose":source.purpose,"port_id":source.id,"position":at.duplicate(true)})
		ports.append(row)
		pad=[minf(pad[0],row.position.x-1.0),minf(pad[1],row.position.z-1.0),maxf(pad[2],row.position.x+1.0),maxf(pad[3],row.position.z+1.0)]
	var orientation:Dictionary={"policy":POLICY,"primary_port_id":primary.id,"target":{"x":road_junction.x,"y":0.0,"z":road_junction.y},"reason":"shared-road-and-courtyard-junction"}
	if quality:
		orientation.policy="road-court-camera-v2";orientation.reason="real-road-court-with-normal-camera-service-readability";orientation.camera_reference={"x":24,"y":29,"z":31}
	return {"origin":origin,"quarter_turn":turn,"footprint":f,"foundation":foundation,"pad":{"xz":pad,"height":0.0,"blend":4.0},"entrance_ports":ports,"use_reservations":reserves,"npc_anchors":anchors,"orientation":orientation}
