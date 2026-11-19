extends "res://scripts/buildings/building_roof_cutaway.gd"
## Reuse B's ceiling graph and missing-tile lookup. Structural rooms use the
## existing CLOSED doorway geometry, not the current animated/open door leaf.
## This is a disposable render projection, never a second room/LOS authority.
var _room_boxes:Dictionary={}

func configure(space:RefCounted)->void:
	_room_boxes.clear()
	super.configure(space)

func connected(a:Dictionary,b:Dictionary)->bool:
	var av:=Geometry.point(a)+Vector3(0,1.2,0)
	var bv:=Geometry.point(b)+Vector3(0,1.2,0)
	for piece:Dictionary in query.nearby_pieces(str(a.regionId),AABB(av.min(bv),av.max(bv)-av.min(bv))):
		if query.geometry.definition(piece).kind not in ["wall","corner","door","window"]:continue
		if not _room_boxes.has(piece.id):_room_boxes[piece.id]=query.geometry.boxes(piece,"room")
		for volume:AABB in _room_boxes[piece.id]:
			if volume.intersects_segment(av,bv)!=null:return false
	var count:=maxi(1,ceili(av.distance_to(bv)/0.15))
	for i in range(count+1):
		if not query.terrain_clear(str(a.regionId),AABB(av.lerp(bv,float(i)/count)-Vector3.ONE*0.005,Vector3.ONE*0.01)):return false
	return true
