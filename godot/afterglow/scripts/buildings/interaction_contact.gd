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
		if query.contact_clear(from,to,id):return true
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

static func station_points(query:RefCounted,target:Dictionary)->Array:
	# Derived approach hints, not a change to pinned station geometry/reach.
	# A real body may stand closer than the old 0.6m use socket; every returned
	# foot still passes full support/body and tool-contact occlusion queries.
	var legacy:Array=query.use_points(target);var points:Array=[]
	if query.geometry.definition(target).get("kind")!="workbench":return legacy
	for hint:Dictionary in legacy:
		for volume:AABB in query.geometry.boxes(target):
			var foot:=Geometry.point(hint);var surface:=foot.max(volume.position).min(volume.end)
			var normal:=foot-surface;normal.y=0
			if normal.length_squared()<0.000001:continue
			var at:Dictionary=hint.duplicate(true);at.merge(Geometry.json_point(surface+normal.normalized()*(float(query.agent.radius)+0.04)),true);at.y=hint.y
			var resolved:Dictionary=query.standing_point(at)
			if not resolved.is_empty() and structure(query,resolved,target):points.append(resolved)
	points.append_array(legacy);return points

static func player_tree_near(from:Dictionary,target:Dictionary)->bool:
	if not target.get("bounds") is Dictionary:return false
	var foot:=Geometry.point(from)
	var trunk:=Geometry.aabb(target.bounds)
	return absf(foot.y-trunk.position.y)<=1.25 and foot.distance_to(foot.max(trunk.position).min(trunk.end))<=2.25

static func tree_points(query:RefCounted,target:Dictionary,player_contact:bool=false)->Array:
	if target.get("kind")!="tree" or not target.get("bounds") is Dictionary or target.get("data",{}).get("harvest",{}).get("phase")!="standing":return []
	# Harvest authority requires BOTH the trunk and the real ground output.
	# A close trunk foot on a slope can see the trunk while the same trunk
	# blocks the ray to its side drop. Never plan labor at that impossible foot
	# or bypass the output check at submission/advance.
	var drop:Dictionary=query.world.entity(str(target.get("data",{}).get("outputId","")))
	if drop.get("kind")!="container" or not drop.get("data",{}).get("dropped",false):return []
	var volume:=Geometry.aabb(target.bounds);var close:Array=[];var legacy:Array=[]
	for direction:Vector3 in [Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT]:
		var hint:Dictionary=Geometry.location(target)
		hint.merge(Geometry.json_point(Geometry.point(target.position)+direction*1.2),true)
		var foot:=Geometry.point(hint);var surface:=foot.max(volume.position).min(volume.end)
		var normal:=foot-surface;normal.y=0
		if normal.length_squared()>0.000001:
			var at:Dictionary=hint.duplicate(true)
			at.merge(Geometry.json_point(surface+normal.normalized()*(float(query.agent.radius)+0.04)),true);at.y=hint.y
			var resolved:Dictionary=query.standing_point(at)
			if not resolved.is_empty() and (player_tree_near(resolved,target) if player_contact else entity(query,resolved,target) and entity(query,resolved,drop)):close.append(resolved)
		var old:Dictionary=query.standing_point(hint)
		if not old.is_empty() and (player_tree_near(old,target) if player_contact else entity(query,old,target) and entity(query,old,drop)):legacy.append(old)
	close.append_array(legacy);return close
