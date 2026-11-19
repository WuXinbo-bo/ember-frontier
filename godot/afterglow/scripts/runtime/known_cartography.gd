extends RefCounted
## Detached survey of already explored ground. Never reveals a future region,
## resource, actor or watercourse; fluid terrain does not exist in this world.
const Data=preload("res://scripts/world/world_data.gd")
var _basis:Array=[]
var _value:Dictionary={}

func build(world:RefCounted,map:Dictionary,modules:Dictionary,water:Dictionary={})->Dictionary:
	var metre:float=float(map.get("tile_metres",4.0))
	var tiles:Array=map.get("explored_tiles",[])
	var regions:Dictionary={};var chunks:Dictionary={}
	var cfg:Dictionary=world.config()
	var cell:float=float(cfg.cellSize);var n:int=int(cfg.chunkCells)
	for tile:Dictionary in tiles:
		var region_id:String=str(tile.region_id)
		if not regions.has(region_id):regions[region_id]=[]
		regions[region_id].append(Rect2(float(tile.x)*metre,float(tile.z)*metre,metre,metre))
		var cx:int=floori((float(tile.x)+0.5)*metre/cell/n)
		var cz:int=floori((float(tile.z)+0.5)*metre/cell/n)
		for cy:int in range(floori(float(cfg.minCellY)/n),ceili(float(cfg.maxCellY)/n)):
			var key:String=Data.key(Vector3i(cx,cy,cz))
			chunks[key]=world.chunk_metadata(key)
	var plans:Dictionary={};var plan_tokens:Array=[]
	for id:String in regions:
		var extension_id:String="generation:"+id
		plan_tokens.append(world.extension_token(extension_id) if world.has_method("extension_token") else world.get_revision())
	var module_shapes:Array=[];var definition_shapes:Array=[];var water_points:Array=[]
	for row:Dictionary in modules.get("instances",[]):module_shapes.append([row.id,row.definition_id,row.get("quarter_turn",0),row.get("location",{})])
	for row:Dictionary in modules.get("definitions",[]):definition_shapes.append([row.id,row.get("footprint",{})])
	for row:Dictionary in water.get("sources",[]):water_points.append([row.id,row.get("location",{})])
	var basis:Array=[world.get_instance_id(),world.identity(),cfg,tiles,chunks,plan_tokens,module_shapes,definition_shapes,water_points]
	if basis==_basis:return _value.duplicate(true)
	var result:Dictionary={"schema":"afterglow-known-cartography-v1","revision":world.get_revision(),"cell_size":metre,"cells":[],"roads":[],"water":[],"buildings":[],"regions":[]}
	for id:String in regions:
		var bounds:Rect2=regions[id][0]
		for rect:Rect2 in regions[id]:bounds=bounds.merge(rect)
		result.regions.append({"region_id":id,"bounds":{"min":{"x":bounds.position.x,"z":bounds.position.y},"max":{"x":bounds.end.x,"z":bounds.end.y}}})
		var fields:Array[String]=["paths"]
		plans[id]=world.extension_fields("generation:"+id,fields)
	for tile:Dictionary in tiles:
		var x:float=(float(tile.x)+0.5)*metre;var z:float=(float(tile.z)+0.5)*metre
		var elevation:Variant=world.surface_height(x,z)
		var terrain:String="unknown"
		if elevation!=null:
			var material:int=world.cell_at(floori(x/cell),roundi(float(elevation)/cell)-1,floori(z/cell))
			terrain=str(Data.MATERIALS.get(material,{}).get("key","unknown"))
		result.cells.append({"region_id":tile.region_id,"x":float(tile.x)*metre,"z":float(tile.z)*metre,"terrain":terrain,"elevation":elevation,"known":elevation!=null})
	for id:String in regions:
		for path:Dictionary in plans[id].get("paths",[]):
			var points:Array=path.get("points",[])
			for i:int in range(1,points.size()):
				var a:=Vector2(float(points[i-1].x),float(points[i-1].z))
				var b:=Vector2(float(points[i].x),float(points[i].z))
				for rect:Rect2 in regions[id]:
					var clipped:Array=_clip_segment(a,b,rect)
					if clipped.size()==2:result.roads.append({"region_id":id,"width":path.get("width",1.0),"points":[_point(clipped[0]),_point(clipped[1])]})
		# Water sources must already be disclosed by B, in addition to explored
		# ground. Reading a generated plan alone is never discovery authority.
		for source:Dictionary in water.get("sources",[]):
			var at:Dictionary=source.get("location",{})
			if str(at.get("regionId",""))!=id:continue
			if not at.has("x") or not _known(regions[id],Vector2(float(at.x),float(at.z))):continue
			result.water.append({"id":source.id,"region_id":id,"kind":"water_source","position":_point(Vector2(float(at.x),float(at.z)))})
	var definitions:Dictionary={}
	for definition:Dictionary in modules.get("definitions",[]):definitions[str(definition.id)]=definition
	for module:Dictionary in modules.get("instances",[]):
		var location:Dictionary=module.get("location",{})
		var id:String=str(location.get("regionId",""))
		var footprint:Dictionary=definitions.get(str(module.definition_id),{}).get("footprint",{})
		if not regions.has(id) or not footprint.has("min") or not footprint.has("max"):continue
		var corners:=PackedVector2Array()
		for local:Vector2 in [Vector2(footprint.min.x,footprint.min.z),Vector2(footprint.max.x,footprint.min.z),Vector2(footprint.max.x,footprint.max.z),Vector2(footprint.min.x,footprint.max.z)]:
			var rotated:Vector2=local.rotated(int(module.get("quarter_turn",0))*PI/2.0)
			corners.append(rotated+Vector2(float(location.x),float(location.z)))
		for rect:Rect2 in regions[id]:
			var mask:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
			for polygon:PackedVector2Array in Geometry2D.intersect_polygons(corners,mask):
				var points:Array=[]
				for point:Vector2 in polygon:points.append(_point(point))
				result.buildings.append({"id":module.id,"region_id":id,"known":true,"polygon":points})
	_basis=basis.duplicate(true);_value=result.duplicate(true)
	return result

static func _point(point:Vector2)->Dictionary:return {"x":point.x,"z":point.y}

static func _known(rects:Array,point:Vector2)->bool:
	for rect:Rect2 in rects:
		if rect.has_point(point):return true
	return false

static func _clip_segment(a:Vector2,b:Vector2,rect:Rect2)->Array:
	var delta:Vector2=b-a;var enter:float=0.0;var leave:float=1.0
	for axis:int in 2:
		if absf(delta[axis])<0.000001:
			if a[axis]<rect.position[axis] or a[axis]>rect.end[axis]:return []
		else:
			var t0:float=(rect.position[axis]-a[axis])/delta[axis]
			var t1:float=(rect.end[axis]-a[axis])/delta[axis]
			enter=maxf(enter,minf(t0,t1));leave=minf(leave,maxf(t0,t1))
	if leave<=enter:return []
	return [a+delta*enter,a+delta*leave]
