extends RefCounted
## Presentation-only connected ceiling regions from the existing wall/leaf
## sight geometry. No room authority, actor permissions or inventory is stored.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var query:RefCounted
var roofs:Array=[]
var components:Dictionary={}
var floor_y:Dictionary={}

func configure(space:RefCounted)->void:
	query=space;roofs.clear();components.clear();floor_y.clear()
	for storey:Dictionary in query.state.get("storeys",[]):floor_y[storey.id]=float(storey.elevation)
	var index:Dictionary={}
	for v:Dictionary in query.pieces:
		if float(v.hp)<=0 or query.geometry.definition(v).kind!="roof" or v.get("buildingId")==null or not floor_y.has(v.get("storeyId")):continue
		roofs.append(v)
		index[[v.regionId,v.buildingId,v.storeyId,Geometry.point(v.position)]]=v
	var number:=0
	for v:Dictionary in roofs:
		if components.has(v.id):continue
		number+=1;components[v.id]=number
		var pending:Array=[v];var cursor:=0
		while cursor<pending.size():
			var current:Dictionary=pending[cursor];cursor+=1
			for delta:Vector3 in [Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2)]:
				var key:Array=[current.regionId,current.buildingId,current.storeyId,Geometry.point(current.position)+delta]
				if not index.has(key):continue
				var other:Dictionary=index[key]
				if components.has(other.id) or not connected(room_point(current),room_point(other)):continue
				components[other.id]=number;pending.append(other)

func room_point(roof:Dictionary)->Dictionary:
	var p:=Geometry.location(roof);p.y=floor_y[roof.storeyId]
	return p

func connected(a:Dictionary,b:Dictionary)->bool:
	var av:=Geometry.point(a)+Vector3(0,1.2,0);var bv:=Geometry.point(b)+Vector3(0,1.2,0)
	for piece:Dictionary in query.nearby_pieces(str(a.regionId),AABB(av.min(bv),av.max(bv)-av.min(bv))):
		if query.geometry.definition(piece).kind not in ["wall","corner","door","window"]:continue
		for volume:AABB in query.sight_boxes.get(piece.id,[]):
			if volume.intersects_segment(av,bv)!=null:return false
	var count:=maxi(1,ceili(av.distance_to(bv)/0.15))
	for i in range(count+1):
		if not query.terrain_clear(str(a.regionId),AABB(av.lerp(bv,float(i)/count)-Vector3.ONE*0.005,Vector3.ONE*0.01)):return false
	return true

func component_at(p:Dictionary)->int:
	var candidates:Array=[]
	for roof:Dictionary in roofs:
		if roof.regionId!=p.regionId or roof.buildingId!=p.get("buildingId") or roof.storeyId!=p.get("storeyId"):continue
		candidates.append(roof)
		var b:AABB=query.bounds(roof)
		if float(p.x)>=b.position.x and float(p.x)<=b.end.x and float(p.z)>=b.position.z and float(p.z)<=b.end.z:return int(components[roof.id])
	# A real removed roof tile must not make its remaining room covers reappear.
	# Find a visible structural connection from the hole, without exposing props.
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(room_point(a)).distance_squared_to(Geometry.point(p))<Geometry.point(room_point(b)).distance_squared_to(Geometry.point(p)))
	for roof:Dictionary in candidates:
		if connected(p,room_point(roof)):return int(components[roof.id])
	return -1
