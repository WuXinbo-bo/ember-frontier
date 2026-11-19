extends RefCounted
## Native AABB nearest-surface reach. Candidate geometry never grants authority:
## callers still enforce HP/ownership/floor, and every ray uses the real world.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")

static func clear_surface(query:RefCounted,from:Dictionary,id:String,volumes:Array,distance:float)->bool:
	var chest:=Geometry.point(from)+Vector3(0,1.2,0)
	for volume:AABB in volumes:
		var contact:Vector3=chest.max(volume.position).min(volume.end)
		if chest.distance_to(contact)>distance:continue
		# Space.line_clear accepts FOOT coordinates and adds its own eye height.
		var to:=from.duplicate(true)
		to.merge(Geometry.json_point(contact-Vector3(0,1.2,0)),true)
		var actual_region:Dictionary=query.world.region_at(Geometry.json_point(contact))
		if actual_region.is_empty():continue
		to.regionId=actual_region.id
		if query.line_clear(from,to,id):return true
	return false

static func same_level(from:Dictionary,to:Dictionary)->bool:
	if absf(float(from.y)-float(to.y))>0.55:return false
	# The physical floor and ray decide reach across a doorway. Two labels for
	# adjacent houses/outside are not themselves a wall. Distinct levels inside
	# one building still retain their explicit floor boundary.
	return from.get("buildingId")==null or from.get("buildingId")!=to.get("buildingId") or from.get("storeyId")==null or to.get("storeyId")==null or from.storeyId==to.storeyId

static func structure(query:RefCounted,from:Dictionary,target:Dictionary,distance:float=1.6)->bool:
	var at:=Geometry.location(target)
	if not same_level(from,at):return false
	var kind:String=query.geometry.definition(target).get("kind","")
	if kind=="door":
		# The whole same-side doorway is an interaction area; the old 1.15m
		# jamb socket remains an NPC approach hint, not a pixel-perfect handle.
		var aperture:=Geometry.transformed_box(AABB(Vector3(-0.8,0,-0.10),Vector3(1.6,2.2,0.20)),target)
		return clear_surface(query,from,str(target.id),[aperture],distance)
	if kind in ["stairs","roof"]:return false # Existing platform/underside rules.
	return clear_surface(query,from,str(target.id),query.geometry.boxes(target),distance)

static func entity(query:RefCounted,from:Dictionary,target:Dictionary,distance:float=2.25)->bool:
	var at:=Geometry.location(target)
	if not same_level(from,at):return false
	if not target.get("bounds") is Dictionary:return false
	# Tree bounds are the authoritative trunk, never the visual canopy.
	return clear_surface(query,from,str(target.id),[Geometry.aabb(target.bounds)],distance)
