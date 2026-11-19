extends Control
## Draw only A's detached known-map DTO. No world scans, movement or camera calls.
signal marker_selected(marker: Dictionary)
const SCHEMA := "afterglow-known-map-v1"
const COLORS := {"player":Color("a8c0ba"), "member":Color("b8c4ae"), "module":Color("d1bb83"), "regional_site":Color("c8bda7"), "hostile":Color("e8ae99")}
const LAND := {"grass":Color("485b3d"),"soil":Color("766148"),"stone":Color("79796e"),"road":Color("a48b62"),"gravel":Color("8d8974")}
static var _terrain_cache:Dictionary={}
var cartography:Dictionary={}
var terrain_cache_hit:=false
var _terrain_texture:Texture2D
var _terrain_bounds:=Rect2()
var region_id := ""
var tiles: Array = []
var markers: Array = []
var focus: Dictionary = {}
var tile_metres := 4.0
var text_scale := 1.0
var _bounds := Rect2(-12, -12, 24, 24)
var _bounds_ready := false

static func valid_location(value: Variant) -> bool:
	if not value is Dictionary or str(value.get("regionId", "")).is_empty(): return false
	for key: String in ["x", "z"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])): return false
	return true

static func regions(data: Dictionary) -> Array:
	var known: Dictionary = {}
	if data.get("schema") != SCHEMA: return []
	for tile: Dictionary in data.get("explored_tiles", []):
		if not str(tile.get("region_id", "")).is_empty(): known[str(tile.region_id)] = true
	for marker: Dictionary in data.get("markers", []):
		if valid_location(marker.get("location")): known[str(marker.location.regionId)] = true
	var result: Array = known.keys(); result.sort()
	return result

func configure(data: Dictionary, selected: Dictionary = {}, requested_region: String = "", scale_text: float = 1.0) -> void:
	tiles.clear(); markers.clear(); focus.clear(); region_id = ""; _bounds_ready = false
	text_scale = scale_text
	custom_minimum_size = Vector2(280, 300 * text_scale)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if data.get("schema") != SCHEMA: return
	var known := regions(data)
	region_id = requested_region if known.has(requested_region) else str(known[0]) if not known.is_empty() else ""
	if valid_location(selected.get("location")):
		focus = selected.duplicate(true)
		region_id = str(focus.location.regionId)
	tile_metres = float(data.get("tile_metres", 4.0))
	if not is_finite(tile_metres) or tile_metres <= 0: tile_metres = 4.0
	tiles = data.get("explored_tiles", []).filter(func(row: Dictionary): return row.get("region_id") == region_id).duplicate(true)
	markers = data.get("markers", []).filter(func(row: Dictionary): return valid_location(row.get("location")) and row.location.regionId == region_id).duplicate(true)
	cartography=data.get("cartography",{}) if data.get("cartography") is Dictionary else {}
	_prepare_terrain()
	queue_redraw()

func _prepare_terrain()->void:
	_terrain_texture=null;terrain_cache_hit=false
	if cartography.get("schema")!="afterglow-known-cartography-v1":return
	_terrain_bounds=view_bounds()
	var cells:Array=cartography.get("cells",[]).filter(func(row:Dictionary):return row.get("region_id")==region_id and row.get("known",false))
	var cell_size:float=float(cartography.get("cell_size",tile_metres))
	if cells.is_empty() or not is_finite(cell_size) or cell_size<=0:return
	var key:int=[region_id,_terrain_bounds,cell_size,cells].hash()
	if _terrain_cache.has(key):_terrain_texture=_terrain_cache[key];terrain_cache_hit=true;return
	# One cached, small raster for surveyed terrain. Actors/alerts remain live
	# CanvasItem symbols; no extra 3D scene, camera, lighting or world queries.
	var image:=Image.create(512,512,false,Image.FORMAT_RGBA8)
	image.fill(Color("222c25"))
	var pixels:Vector2=Vector2(512,512)/_terrain_bounds.size
	for row:Dictionary in cells:
		var top_left:Vector2=(Vector2(float(row.x),float(row.z))-_terrain_bounds.position)*pixels
		var span:Vector2=Vector2.ONE*cell_size*pixels
		var rect:=Rect2i(Vector2i(floori(top_left.x),floori(top_left.y)),Vector2i(ceili(span.x)+1,ceili(span.y)+1)).intersection(Rect2i(0,0,512,512))
		var color:Color=LAND.get(str(row.get("terrain","")),Color("4b5141"))
		var elevation:float=float(row.elevation) if row.get("elevation") is float or row.get("elevation") is int else 0.0
		color=color.lightened(clampf(elevation*0.008,-0.08,0.12)) if elevation>=0 else color.darkened(minf(0.12,-elevation*0.008))
		image.fill_rect(rect,color)
		if rect.size.x>5 and rect.size.y>5:
			var speck:=Rect2i(rect.position+Vector2i(2,2),Vector2i(2,1))
			image.fill_rect(speck,color.lightened(0.07))
	_terrain_texture=ImageTexture.create_from_image(image)
	if _terrain_cache.size()>=8:_terrain_cache.erase(_terrain_cache.keys()[0])
	_terrain_cache[key]=_terrain_texture

func update_markers(data:Dictionary,selected:Dictionary={})->void:
	var next:Array=data.get("markers",[]).filter(func(row:Dictionary):return valid_location(row.get("location")) and row.location.regionId==region_id)
	var next_focus:Dictionary=selected if valid_location(selected.get("location")) else {}
	if next==markers and next_focus==focus:return
	markers=next.duplicate(true);focus=next_focus.duplicate(true);queue_redraw()

func view_bounds() -> Rect2:
	if _bounds_ready: return _bounds
	_bounds = _calculate_bounds(); _bounds_ready = true
	return _bounds

func _calculate_bounds() -> Rect2:
	var points: Array = []
	for tile: Dictionary in tiles:
		var corner := Vector2(float(tile.x), float(tile.z)) * tile_metres
		points.append(corner); points.append(corner + Vector2.ONE * tile_metres)
	for row: Dictionary in markers: points.append(Vector2(float(row.location.x), float(row.location.z)))
	if not focus.is_empty(): points.append(Vector2(float(focus.location.x), float(focus.location.z)))
	if points.is_empty(): return Rect2(-12, -12, 24, 24)
	var low: Vector2 = points[0]; var high := low
	for point: Vector2 in points: low = low.min(point); high = high.max(point)
	var center := (low + high) * 0.5
	if not focus.is_empty(): center = Vector2(float(focus.location.x), float(focus.location.z))
	var extent := Vector2(maxf(24, high.x - low.x + 8), maxf(24, high.y - low.y + 8))
	return Rect2(center - extent * 0.5, extent)

func map_point(location: Dictionary) -> Vector2:
	var bounds := view_bounds()
	var factor := minf(maxf(1, size.x - 48) / bounds.size.x, maxf(1, size.y - 48) / bounds.size.y)
	return size * 0.5 + (Vector2(float(location.x), float(location.z)) - bounds.get_center()) * factor

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	var closest: Dictionary = {}; var distance := 14.0 * text_scale
	for marker: Dictionary in markers:
		var candidate: float = event.position.distance_to(map_point(marker.location))
		if candidate <= distance: closest = marker; distance = candidate
	if not closest.is_empty(): marker_selected.emit(closest.duplicate(true))
	accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("1b241f"))
	var bounds := view_bounds()
	var factor := minf(maxf(1, size.x - 48) / bounds.size.x, maxf(1, size.y - 48) / bounds.size.y)
	if _terrain_texture!=null:
		var corner:=map_point({"x":_terrain_bounds.position.x,"z":_terrain_bounds.position.y})
		draw_texture_rect(_terrain_texture,Rect2(corner,_terrain_bounds.size*factor),false)
	else:
		for tile: Dictionary in tiles:
			var at := map_point({"x":float(tile.x) * tile_metres, "z":float(tile.z) * tile_metres})
			var rect := Rect2(at, Vector2.ONE * tile_metres * factor)
			draw_rect(rect, Color("344036")); draw_rect(rect, Color("445044"), false, 1)
	for road:Dictionary in cartography.get("roads",[]):
		if road.get("region_id")!=region_id:continue
		var points:=PackedVector2Array()
		for point:Dictionary in road.get("points",[]):points.append(map_point(point))
		if points.size()>1:draw_polyline(points,Color("b39a70"),maxf(1.5,float(road.get("width",1))*factor),true)
	for building:Dictionary in cartography.get("buildings",[]):
		if building.get("region_id")!=region_id or not building.get("known",false):continue
		var polygon:=PackedVector2Array()
		for point:Dictionary in building.get("polygon",[]):polygon.append(map_point(point))
		if polygon.size()<3:continue
		draw_colored_polygon(polygon,Color("706044"))
		polygon.append(polygon[0]);draw_polyline(polygon,Color("c2aa76"),1.2,true)
	for source:Dictionary in cartography.get("water",[]):
		if source.get("region_id")!=region_id or source.get("kind")!="water_source":continue
		var at:=map_point(source.position)
		draw_circle(at,5,Color("4a7780"));draw_arc(at,6.5,0,TAU,16,Color("a7ced0"),1.2,true)
	for marker: Dictionary in markers:
		var at := map_point(marker.location)
		var color: Color = COLORS.get(str(marker.get("kind", "")), Color("cec6b3"))
		if marker.get("kind") == "module": draw_rect(Rect2(at - Vector2(4,4), Vector2(8,8)), color)
		else: draw_circle(at, 5 if marker.get("kind") == "player" else 4, color)
	if not focus.is_empty():
		var at := map_point(focus.location)
		draw_arc(at, 11, 0, TAU, 32, Color("f0dfad"), 2)
		var text := str(focus.get("title", focus.get("id", "定位")))
		draw_string(get_theme_default_font(), Vector2(clampf(at.x+15, 8, maxf(8,size.x-190)), clampf(at.y-12, 22, size.y-8)), text, HORIZONTAL_ALIGNMENT_LEFT, 180, int(14*text_scale), Color("f0dfad"))
	draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),Color("6f7154"),false,1)
	draw_line(Vector2(size.x-23,38),Vector2(size.x-23,18),Color("d8d0ad"),1.5,true)
	draw_line(Vector2(size.x-23,18),Vector2(size.x-28,25),Color("d8d0ad"),1.5,true)
	draw_string(get_theme_default_font(),Vector2(size.x-40,54),"北",HORIZONTAL_ALIGNMENT_CENTER,34,13,Color("d8d0ad"))
	var metres:float=5 if bounds.size.x<70 else 10 if bounds.size.x<180 else 25
	var length:float=metres*factor
	draw_line(Vector2(18,size.y-20),Vector2(18+length,size.y-20),Color("d8d0ad"),2,true)
	draw_string(get_theme_default_font(),Vector2(18,size.y-27),"%s 米" % str(int(metres)),HORIZONTAL_ALIGNMENT_LEFT,100,12,Color("d8d0ad"))
