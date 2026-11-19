extends RefCounted
## Shared read-only building reach. Ports are route hints, never required feet.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const DISTANCE:float=2.5

static func near_entity(query:RefCounted,from:Dictionary,target:Dictionary,max_distance:float=DISTANCE)->bool:
	if target.is_empty() or from.get("regionId")!=target.get("regionId"):return false
	var standing:Dictionary=query.standing_point(from)
	return not standing.is_empty() and G.point(standing).distance_to(G.point(from))<=0.05 and Interaction.entity(query,from,target,max_distance)

static func entity_points(query:RefCounted,from:Dictionary,target:Dictionary,max_distance:float=DISTANCE)->Array:
	var result:Array=[]
	if near_entity(query,from,target,max_distance):return [from.duplicate(true)]
	if not target.get("bounds") is Dictionary:return result
	var box:=G.aabb(target.bounds);var center:=box.get_center()
	for offset:Vector3 in [Vector3(box.size.x*.5+.7,0,0),Vector3(-box.size.x*.5-.7,0,0),Vector3(0,0,box.size.z*.5+.7),Vector3(0,0,-box.size.z*.5-.7)]:
		var hint:=G.location(target);hint.merge(G.json_point(Vector3(center.x,box.position.y,center.z)+offset),true)
		var feet:Dictionary=query.standing_point(hint)
		if not feet.is_empty() and near_entity(query,feet,target,max_distance):result.append(feet)
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(from).distance_squared_to(G.point(a))<G.point(from).distance_squared_to(G.point(b)))
	return result

static func near(query:RefCounted,from:Dictionary,module:Dictionary,max_distance:float=DISTANCE)->bool:
	if module.is_empty() or from.get("regionId")!=module.get("region"):return false
	var at:=G.location(module.position.merged({"regionId":module.region}))
	if not Interaction.same_level(from,at):return false
	var standing:Dictionary=query.standing_point(from)
	if standing.is_empty() or G.point(standing).distance_to(G.point(from))>0.05:return false
	return _surface_near(query,from,module,max_distance)

static func _surface_near(query:RefCounted,from:Dictionary,module:Dictionary,max_distance:float)->bool:
	if from.get("regionId")!=module.get("region") or not Interaction.same_level(from,G.location(module.position.merged({"regionId":module.region}))):return false
	var definition:Dictionary=Catalog.definition_view(str(module.get("definition_id","")))
	if definition.is_empty():return false
	var box:=Shape.transform_box(module,G.aabb(definition.footprint))
	var chest:=G.point(from)+Vector3(0,1.2,0)
	var contact:=chest.max(box.position).min(box.end)
	if chest.distance_to(contact)>max_distance:return false
	# Stop just outside the actual footprint: its own wall is the touched
	# surface, while other props, terrain and intervening walls still block.
	var outward:=chest-contact
	if outward.length_squared()>0.000001:contact+=outward.normalized()*0.025
	var to:Dictionary=from.merged(G.json_point(contact-Vector3(0,1.2,0)),true)
	return query.contact_clear(from,to,str(module.id))

static func outside(module:Dictionary,from:Dictionary)->bool:
	var definition:Dictionary=Catalog.definition_view(str(module.get("definition_id","")))
	if definition.is_empty():return false
	var body:=AABB(G.point(from)-Vector3(.26,0,.26),Vector3(.52,1.8,.52))
	return not body.intersects(Shape.transform_box(module,G.aabb(definition.footprint)))

static func work_near(query:RefCounted,from:Dictionary,module:Dictionary,max_distance:float=DISTANCE)->bool:
	return outside(module,from) and near(query,from,module,max_distance)

static func points(query:RefCounted,from:Dictionary,module:Dictionary,max_distance:float=DISTANCE,exterior_only:bool=false)->Array:
	var result:Array=[]
	if (not exterior_only or outside(module,from)) and near(query,from,module,max_distance):return [from.duplicate(true)]
	var definition:Dictionary=Catalog.definition_view(str(module.get("definition_id","")))
	if definition.is_empty():return result
	var box:=Shape.transform_box(module,G.aabb(definition.footprint));var origin:=G.point(from)
	var hints:Array=[]
	for offset:float in [0.7]:
		for fraction:float in [0.0,0.5,1.0]:
			var x:float=lerpf(box.position.x,box.end.x,fraction)
			var z:float=lerpf(box.position.z,box.end.z,fraction)
			hints.append_array([Vector3(x,box.position.y,box.position.z-offset),Vector3(x,box.position.y,box.end.z+offset),Vector3(box.position.x-offset,box.position.y,z),Vector3(box.end.x+offset,box.position.y,z)])
		var x:float=clampf(origin.x,box.position.x,box.end.x);var z:float=clampf(origin.z,box.position.z,box.end.z)
		hints.append_array([Vector3(x,box.position.y,box.position.z-offset),Vector3(x,box.position.y,box.end.z+offset),Vector3(box.position.x-offset,box.position.y,z),Vector3(box.end.x+offset,box.position.y,z)])
	hints.sort_custom(func(a:Vector3,b:Vector3)->bool:return origin.distance_squared_to(a)<origin.distance_squared_to(b))
	for hint:Vector3 in hints:
		var location:=G.location(module.position.merged({"regionId":module.region}));location.merge(G.json_point(hint),true)
		var feet:Dictionary=query.standing_point(location)
		if feet.is_empty() or (exterior_only and not outside(module,feet)) or not _surface_near(query,feet,module,max_distance):continue
		if not result.any(func(row:Dictionary)->bool:return G.point(row).distance_squared_to(G.point(feet))<0.0001):result.append(feet)
		if result.size()>=8:break
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return origin.distance_squared_to(G.point(a))<origin.distance_squared_to(G.point(b)))
	return result
