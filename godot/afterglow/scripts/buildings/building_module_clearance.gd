extends RefCounted
## Reuse the same complete module footprint and service geometry consumed by
## construction, stock access and NPC work. No second occupancy/permission map.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")

static func validate(view:RefCounted,added:Array,geometry:RefCounted)->Dictionary:
	if added.is_empty():return {"ok":true}
	var state:Variant
	if view.has_method("extension_fields"):
		var fields:Array[String]=["instances"]
		state=view.extension_fields("r34:modules",fields)
	else:state=view.extension("r34:modules")
	if not state is Dictionary:return {"ok":true}
	for module:Dictionary in state.get("instances",[]):
		if module.get("status")=="dismantled":continue
		var definition:Dictionary=Catalog.definition_view(str(module.get("definition_id","")))
		if definition.is_empty():return {"ok":false,"code":"INVALID_MODULE_DEFINITION","reason":"模块空间定义不可用"}
		var footprint:AABB=Shape.transform_box(module,G.aabb(definition.footprint))
		var ports:Array=Shape.ports(module,definition)
		for piece:Dictionary in added:
			if piece.regionId!=module.region:continue
			# Only exact authoritative membership exempts a module's own authored
			# parts. A caller-supplied module_id or matching ID prefix is no proof.
			if module.get("members",[]).any(func(m:Dictionary)->bool:return m.get("id")==piece.id and m.get("kind")=="structure"):continue
			for box:AABB in geometry.boxes(piece):
				if G.overlap(box,footprint):return {"ok":false,"code":"MODULE_OCCUPIED","reason":"构件占用了完整设施占地："+str(module.id)}
				for port:Dictionary in ports:
					var radius:float=port.clearance.radius;var height:float=port.clearance.height
					for at:Dictionary in port.use_points:
						var body:=AABB(G.point(at)-Vector3(radius,0,radius),Vector3(radius*2,height,radius*2))
						if G.overlap(box,body):return {"ok":false,"code":"MODULE_PORT_OCCUPIED","reason":"构件会堵住设施真实服务面："+str(module.id)+" / "+str(port.id)}
	return {"ok":true}
