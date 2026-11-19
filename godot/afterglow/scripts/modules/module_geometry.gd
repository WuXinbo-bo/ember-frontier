extends RefCounted
## Derived geometry only. Physical parts live in the existing World entity set.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Families=preload("res://scripts/modules/module_family_geometry.gd")
const Quality=preload("res://scripts/modules/module_quality_geometry.gd")
const Residential=preload("res://scripts/modules/module_residential_geometry.gd")
const Civic=preload("res://scripts/modules/module_civic_geometry.gd")
const Industrial=preload("res://scripts/modules/module_industrial_geometry.gd")
const VillageStyle=preload("res://scripts/modules/village_style.gd")
const Village=preload("res://scripts/modules/village_geometry.gd")
const Housing=preload("res://scripts/modules/module_housing.gd")
const RegionalArt=preload("res://scripts/modules/village_regional_art.gd")

static func at(instance:Dictionary,local:Vector3)->Dictionary:
	var p:Vector3=G.point(instance.position)+G.rotate(local,int(instance.quarter_turn))
	return {"x":p.x,"y":p.y,"z":p.z,"regionId":instance.region,"buildingId":null,"storeyId":null}

static func transform_box(instance:Dictionary,b:AABB)->AABB:
	var a:=G.point(at(instance,b.position));var c:=G.point(at(instance,b.end))
	return AABB(a.min(c),a.max(c)-a.min(c))

static func ports(instance:Dictionary,definition:Dictionary)->Array:
	var result:Array=[]
	for source:Dictionary in definition.ports:
		var p:Array=source.position;var n:Array=source.normal
		var normal:=G.rotate(Vector3(n[0],n[1],n[2]),int(instance.quarter_turn))
		var row:Dictionary=source.duplicate(true)
		row.location=at(instance,Vector3(p[0],p[1],p[2]));row.normal=G.json_point(normal)
		row.use_points=[]
		for use:Array in source.use_points:row.use_points.append(at(instance,Vector3(use[0],use[1],use[2])))
		result.append(row)
	return result

static func parts(definition:Dictionary)->Array:
	if definition.get("regional_art",false):return RegionalArt.parts(definition.id)
	if Village.supports(definition):return Village.parts(definition)
	if definition.has("geometry_source_id"):
		var source:Dictionary=preload("res://scripts/modules/module_catalog.gd").definition_view(str(definition.geometry_source_id))
		if source.is_empty() or source.has("geometry_source_id"):return []
		if Housing.applies(definition):return Housing.parts(parts(source))
		if definition.get("geometry_version")!=source.get("geometry_version"):return []
		return parts(source)
	if Residential.supports(definition):return Residential.parts(definition)
	if Civic.supports(definition):return Civic.parts(definition)
	if Industrial.supports(definition):return Industrial.parts(definition)
	if Quality.supports(definition):return Quality.parts(definition)
	if definition.has("design_id"):return Families.parts(definition)
	var b:=G.aabb(definition.footprint);var w:float=b.size.x;var d:float=b.size.z;var h:float=b.size.y
	var result:Array=[]
	var add:=func(id:String,center:Vector3,size:Vector3,material:String,solid:bool=true)->void:
		result.append({"id":id,"center":G.json_point(center),"size":G.json_point(size),"material":material,"solid":solid})
	if definition.shape=="manual":
		add.call("bench-top",Vector3(0,0.9,0),Vector3(w,0.16,d),"wood_floor")
		for x:float in [-w/2+0.12,w/2-0.12]:
			for z:float in [-d/2+0.12,d/2-0.12]:add.call("leg:%s:%s"%[x,z],Vector3(x,0.42,z),Vector3(0.18,0.84,0.18),"wood_floor")
	else:
		# Thick enclosing surfaces, distinct from the apron where people work.
		# No doorway is advertised as an enterable interior.
		add.call("rear",Vector3(0,1.35,d/2-0.1),Vector3(w,2.7,0.2),"cream_plaster")
		add.call("front",Vector3(0,1.35,-d/2+0.1),Vector3(w,2.7,0.2),"wood_floor")
		for side:float in [-1.0,1.0]:
			add.call("side:"+str(side),Vector3(side*(w/2-0.1),1.35,0),Vector3(0.2,2.7,d),"old_brick")
			add.call("beam:"+str(side),Vector3(side*(w/2-0.13),2.8,0),Vector3(0.26,0.26,d+0.5),"wood_floor")
		# Stepped overlapping roof bands form a shallow pitched silhouette.
		for i:int in 6:
			var z:float=-d/2-0.3+(float(i)+0.5)*(d+0.6)/6.0
			var y:float=h-0.15-absf(z)/(d/2+0.3)*0.55
			add.call("roof:"+str(i),Vector3(0,y,z),Vector3(w+0.6,0.18,(d+0.6)/6.0+0.06),"roof_tile")
		# Raised trim and inset shutters produce depth at the normal camera.
		for x:float in [-w*0.28,w*0.28]:
			add.call("shutter:"+str(x),Vector3(x,1.65,-d/2-0.035),Vector3(0.85,0.8,0.12),"zinc")
			add.call("sill:"+str(x),Vector3(x,1.2,-d/2-0.1),Vector3(1.0,0.12,0.3),"wood_floor")
	if definition.shape=="woodshop":
		# The public saw anchor is the tooth line, fixed to a real bed/guard.
		# Service feet at z=-3.1 retain >body-radius clearance from the bed.
		add.call("saw-bed",Vector3(0,0.77,-2.32),Vector3(1.44,0.16,0.68),"wood_floor")
		for x:float in [-0.57,0.57]:
			add.call("saw-leg:"+str(x),Vector3(x,0.36,-2.32),Vector3(0.16,0.72,0.5),"painted_metal")
			add.call("saw-guide:"+str(x),Vector3(x,1.12,-2.21),Vector3(0.07,0.45,0.15),"painted_metal")
		add.call("fixed-power-housing",Vector3(1.4,0.5,-2.2),Vector3(0.75,0.8,0.55),"zinc")
		add.call("power-base",Vector3(1.4,0.08,-2.2),Vector3(1.0,0.16,0.75),"concrete")

	return result

static func entities(instance:Dictionary,definition:Dictionary)->Array:
	var result:Array=[]
	var original:Array=parts(preload("res://scripts/modules/module_catalog.gd").definition_view(str(definition.geometry_source_id))) if Housing.applies(definition) else []
	var rooms:Array=Housing.rooms(original)
	for part:Dictionary in VillageStyle.parts(instance,definition,Village.current_parts(instance,definition,Housing.opening_parts(instance,definition,parts(definition)))):
		if instance.get("restoration") is Dictionary and not instance.restoration.get("completed",false) and part.id in ["fixed-power","fixed-power-housing"]:continue
		var local:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size));var bounds:=transform_box(instance,local)
		result.append({"id":str(instance.id)+":part:"+str(part.id),"kind":"prop","regionId":instance.region,"position":G.json_point(bounds.position),"bounds":G.json_box(bounds),"revision":0,"blocksTerrain":true,"supportBounds":[],"data":{"module_id":instance.id,"module_geometry_version":instance.geometry_version,"module_part":{"size":G.json_point(bounds.size),"material":part.material,"atlas_cell":part.get("atlas_cell",-1)},"solid":part.solid,"opaque":part.solid,"no_interaction":true,"owner":instance.owner}})
		var room:Dictionary=Housing.metadata(instance,part,rooms)
		if room.is_empty():room=Village.room_metadata(instance,definition,part)
		if not room.is_empty():result[-1].data.module_room=room
		# Only explicit v2 parts carry the compact render recipe. The member's
		# World bounds remain authoritative; no decoration creates more entities.
		for key:String in ["roof_mesh","quality_facade","architecture_detail"]:
			if part.has(key):
				var recipe:Dictionary=part[key].duplicate(true)
				recipe.quarter_turn=int(instance.quarter_turn)
				result[-1].data.module_part[key]=recipe
	result.append_array(Housing.entities(instance,definition,original))
	result.append_array(Housing.opening_entities(instance,definition))
	result.append_array(Village.beds(instance,definition))
	# World removal retires member IDs. Keep the building and room identities
	# while giving replacement walls, furniture and beds their own IDs.
	var rebuild_count:int=int(instance.get("rebuild_count",0))
	if rebuild_count>0:
		for entity:Dictionary in result:
			entity.id += ":rebuild:"+str(rebuild_count)
	return result
