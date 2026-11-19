extends RefCounted
## Derived streaming interest, never exploration, gameplay reach or collision.
## Reuse the actual Camera3D projection instead of size * an assumed radius.
const Data=preload("res://scripts/world/world_data.gd")

static func footprint(camera:Camera3D,world:RefCounted,margin:float=0.0)->Dictionary:
	if not is_instance_valid(camera) or not camera.is_inside_tree():return {"ok":false,"code":"CAMERA_NOT_READY"}
	if camera.projection!=Camera3D.PROJECTION_ORTHOGONAL:return {"ok":false,"code":"CAMERA_PROJECTION_UNSUPPORTED"}
	var size:Vector2=camera.get_viewport().get_visible_rect().size
	if size.x<=0 or size.y<=0:return {"ok":false,"code":"CAMERA_VIEWPORT_EMPTY"}
	var config:Dictionary=world.config()
	var lo:float=float(config.minCellY)*float(config.cellSize)
	var hi:float=float(config.maxCellY)*float(config.cellSize)
	var points:PackedVector2Array=[]
	for screen:Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
		var origin:Vector3=camera.project_ray_origin(screen)
		var direction:Vector3=camera.project_ray_normal(screen)
		if absf(direction.y)<0.05:return {"ok":false,"code":"CAMERA_TERRAIN_ANGLE"}
		var at_low:float=(lo-origin.y)/direction.y
		var at_high:float=(hi-origin.y)/direction.y
		var first:float=maxf(0.0,minf(at_low,at_high))
		var last:float=minf(camera.far-camera.near,maxf(at_low,at_high))
		if first>last:continue
		# At wide zoom a corner may start INSIDE the vertical terrain slab.
		# Clip at the near/far planes, rather than rejecting its negative hit.
		for distance:float in [first,last]:
			var at:Vector3=origin+direction*distance
			points.append(Vector2(at.x,at.z))
	if points.is_empty():return {"ok":false,"code":"CAMERA_TERRAIN_DEPTH"}
	var rect:=Rect2(points[0],Vector2.ZERO)
	for at:Vector2 in points:rect=rect.expand(at)
	return {"ok":true,"rect":rect.grow(maxf(0,margin)),"viewport":size,"height_min":lo,"height_max":hi,"samples":points}

static func intersects_region(rect:Rect2,region:Dictionary)->bool:
	var bounds:Dictionary=region.bounds
	return rect.intersects(Rect2(Vector2(bounds.min.x,bounds.min.z),Vector2(bounds.max.x-bounds.min.x,bounds.max.z-bounds.min.z)),true)

static func known_chunk_keys(world:RefCounted,rect:Rect2)->Array:
	# Keys are metadata. Avoid world.chunk() and its detached cell-array copy.
	var config:Dictionary=world.config()
	var width:float=float(config.cellSize)*int(config.chunkCells)
	var keys:Array=[]
	for key:String in world.chunk_keys():
		var coord:Variant=Data.coord(key)
		if coord==null:continue
		if rect.intersects(Rect2(Vector2(coord.x*width,coord.z*width),Vector2(width,width)),true):keys.append(key)
	return keys
