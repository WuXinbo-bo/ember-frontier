extends RefCounted
## Immutable-by-contract projection: no setter; every public aggregate is isolated.
const Data = preload("res://scripts/world/world_data.gd")
const TerrainQueries = preload("res://scripts/terrain/terrain_queries.gd")
var _state: Dictionary

func _init(state: Dictionary = {}) -> void:
	_state = state

func snapshot() -> Dictionary: return _state.duplicate(true)
func get_revision() -> int: return int(_state.get("revision",0))
func config() -> Dictionary: return _state.get("config",Data.DEFAULT_CONFIG).duplicate(true)
func identity() -> Dictionary: return {"worldId":_state.get("worldId",""),"seed":_state.get("seed",0),"generatorVersion":_state.get("generatorVersion","")}
func entity(id: String) -> Dictionary: return _state.get("entities",{}).get(id,{}).duplicate(true)
func region(id: String) -> Dictionary: return _state.get("regions",{}).get(id,{}).duplicate(true)
func regions() -> Array: return _state.get("regions",{}).values().duplicate(true)
func region_ids()->Array:return _state.get("regions",{}).keys()
func chunk(id: String) -> Dictionary: return _state.get("chunks",{}).get(id,{}).duplicate(true)
func chunk_metadata(key:String)->Dictionary:
	# Detached scalar projection only; never copy cells or unpack a cold page.
	# Re-read each call: this is not a cached permission to use derived geometry.
	var c:Dictionary=_state.get("chunks",{}).get(key,{})
	if c.is_empty():return {}
	return {"revision":c.get("revision",-1),"generated":c.get("generated",false),"resident":c.get("resident",false)}

func chunk_boundary(key:String,axis:int,sign:int)->PackedInt32Array:
	# Exact incoming neighbour plane used by TerrainView. Its result owns only
	# n*n material values, with no mutable reference to the authoritative graph.
	var values:=PackedInt32Array()
	if axis<0 or axis>2 or sign not in [-1,1]:return values
	var c:Dictionary=_state.get("chunks",{}).get(key,{})
	if not c.get("generated",false) or not c.get("resident",false):return values
	var n:int=int(_state.get("config",Data.DEFAULT_CONFIG).chunkCells)
	var strides:Array=[1,n*n,n];var layer:int=0 if sign>0 else n-1
	var cells:PackedInt32Array=c.cells
	values.resize(n*n)
	for v in n:
		for u in n:values[u+n*v]=cells[layer*strides[axis]+u*strides[(axis+1)%3]+v*strides[(axis+2)%3]]
	return values

func chunk_is_generated(key:String)->bool:
	# Readiness only: do not copy cells, unpack cold pages or cache metadata.
	var metadata:Dictionary=_state.get("chunks",{}).get(key,{})
	return metadata.get("generated",false)
func chunk_keys() -> Array: return _state.get("chunks",{}).keys()
func cell_storage_statistics()->Dictionary:
	var full:int=0;var pages:int=0;var characters:int=0
	for c:Dictionary in _state.get("chunks",{}).values():
		full+=c.get("cells",[]).size()
		if c.has("cell_page"):pages+=1;characters+=str(c.cell_page.data).length()
	return {"full_cell_count":full,"full_cell_bytes":full*4,"cold_page_count":pages,"cold_base64_bytes":characters,"semantic_cell_count":_state.get("chunks",{}).size()*int(config().chunkCells)**3}
func retired_entity_ids() -> Array: return _state.get("retiredEntityIds",[]).duplicate()
func has_extension(id: String) -> bool: return _state.get("extensions",{}).has(id)
func extension(id: String) -> Variant:
	var v: Variant = _state.get("extensions",{}).get(id)
	return v.duplicate(true) if v is Array or v is Dictionary else v

func extension_fields(id:String,fields:Array[String])->Dictionary:
	# A detached projection of requested top-level fields, never the full plan.
	# Unknown/non-dictionary extensions project to {}; absent fields stay absent.
	var source:Variant=_state.get("extensions",{}).get(id)
	var result:Dictionary={}
	if not source is Dictionary:return result
	for field:String in fields:
		if not source.has(field):continue
		var value:Variant=source[field]
		result[field]=value.duplicate(true) if value is Array or value is Dictionary else value
	return result

func extension_entries(id:String,field:String,ids:Array)->Dictionary:
	# A bounded, detached nested projection. No authority reference crosses the
	# API; a local query does not deep-copy unrelated plants/receipts/regions.
	var result:Dictionary={}
	if ids.size()>4096:return result
	var extension_value:Variant=_state.get("extensions",{}).get(id)
	if not extension_value is Dictionary:return result
	var source:Variant=extension_value.get(field)
	if not source is Dictionary:return result
	for key:Variant in ids:
		if not key is String or not source.has(key):continue
		var value:Variant=source[key]
		result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func entities(region_id: String = "") -> Array:
	var out: Array = []
	for e in _state.get("entities",{}).values():
		if region_id.is_empty() or e.regionId == region_id: out.append(e.duplicate(true))
	return out

func entities_in_bounds(bounds: Dictionary) -> Array:
	var out: Array = []
	for e in _state.get("entities",{}).values():
		if Data.intersects(e.bounds,bounds): out.append(e.duplicate(true))
	return out

func entities_with_data_in_bounds(bounds:Dictionary,field:String)->Array:
	# Exact ordered subset, detached at the read boundary. Ecology's water
	# pass needs one source, not copies of every nearby wall, tree and prop.
	var out:Array=[]
	for e:Dictionary in _state.get("entities",{}).values():
		if e.get("data",{}).has(field) and Data.intersects(e.bounds,bounds):out.append(e.duplicate(true))
	return out

func entities_in_any_bounds(volumes:Array)->Array:
	# One ordered broad-phase read; detach only potentially relevant entities.
	# Keep original entity order for exact equal-distance selection tie behavior.
	var out:Array=[]
	for e:Dictionary in _state.get("entities",{}).values():
		for bounds:Dictionary in volumes:
			if Data.intersects(e.bounds,bounds):out.append(e.duplicate(true));break
	return out

func region_at(position: Dictionary) -> Dictionary:
	for r in _state.get("regions",{}).values():
		if Data.contains(r.bounds,position): return r.duplicate(true)
	return {}

func region_is_resident(region_id:String)->bool:
	# Detailed simulation's current data-readiness predicate, not a distance
	# policy or proof that facts have been released. Read metadata in-place;
	# never duplicate cells, infer readiness from a renderer, or memo residency.
	var r:Dictionary=_state.get("regions",{}).get(region_id,{})
	if not r.get("generated",false):return false
	var cfg:Dictionary=_state.config
	var width:float=float(cfg.cellSize)*int(cfg.chunkCells)
	var bounds:Dictionary=r.bounds
	var low:=Vector3i(floori(bounds.min.x/width),floori(maxf(bounds.min.y,int(cfg.minCellY)*float(cfg.cellSize))/width),floori(bounds.min.z/width))
	# Half-open region/config bounds include a partially covered last chunk.
	var high:=Vector3i(ceili(bounds.max.x/width)-1,ceili(minf(bounds.max.y,int(cfg.maxCellY)*float(cfg.cellSize))/width)-1,ceili(bounds.max.z/width)-1)
	if low.x>high.x or low.y>high.y or low.z>high.z:return false
	for z in range(low.z,high.z+1):
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var metadata:Dictionary=_state.get("chunks",{}).get(Data.key(Vector3i(x,y,z)),{})
				if not metadata.get("generated",false) or not metadata.get("resident",false):return false
	return true

func region_chunk_keys(region_id:String)->Array:
	var r:Dictionary=_state.get("regions",{}).get(region_id,{})
	if r.is_empty():return []
	var cfg:Dictionary=_state.config;var b:Dictionary=r.bounds
	var width:float=float(cfg.cellSize)*int(cfg.chunkCells);var keys:Array=[]
	for z in range(floori(b.min.z/width),ceili(b.max.z/width)):
		for y in range(floori(maxf(b.min.y,int(cfg.minCellY)*float(cfg.cellSize))/width),ceili(minf(b.max.y,int(cfg.maxCellY)*float(cfg.cellSize))/width)):
			for x in range(floori(b.min.x/width),ceili(b.max.x/width)):keys.append(Data.key(Vector3i(x,y,z)))
	return keys

func region_residency_state(region_id:String)->Dictionary:
	# Scheduler metrics only; no public chunk copy or decompression to inspect
	# this state. page_bytes counts the actual ASCII base64 payload in memory.
	var r:Dictionary=_state.get("regions",{}).get(region_id,{})
	var result:Dictionary={"region_id":region_id,"world_revision":get_revision(),"generated":r.get("generated",false),"resident":false,"mixed":false,"paged":false,"required_chunks":0,"resident_chunks":0,"page_chunks":0,"missing_chunks":0,"unpacked_bytes":0,"page_bytes":0,"compressed_bytes":0}
	var keys:Array=region_chunk_keys(region_id);result.required_chunks=keys.size()
	for key:String in keys:
		var c:Dictionary=_state.get("chunks",{}).get(key,{})
		if not c.get("generated",false):result.missing_chunks+=1;continue
		if c.get("resident",false):result.resident_chunks+=1
		result.unpacked_bytes+=c.get("cells",[]).size()*4
		if c.has("cell_page"):
			result.page_chunks+=1
			var payload:String=c.cell_page.data
			result.page_bytes+=payload.length()
			result.compressed_bytes+=payload.length()/4*3-(2 if payload.ends_with("==") else 1 if payload.ends_with("=") else 0)
	result.resident=result.generated and not keys.is_empty() and result.resident_chunks==keys.size() and result.missing_chunks==0
	result.paged=not keys.is_empty() and result.page_chunks==keys.size()
	result.mixed=(result.page_chunks>0 and result.page_chunks<keys.size()) or (result.resident_chunks>0 and result.resident_chunks<keys.size())
	return result

func continuous_outdoor_step(from_location:Dictionary,to_location:Dictionary)->Dictionary:
	# Partition/residency proof ONLY. B still checks the exact swept body,
	# terrain support/steps, buildings, doors, entities and permissions.
	return _continuous_outdoor_space(from_location,to_location,1.00001,0.26,1.8,float(config().cellSize))

func continuous_outdoor_contact(from_location:Dictionary,to_location:Dictionary)->Dictionary:
	# The SAME partition proof for a hand-to-surface segment; not visibility,
	# tool permission or a replacement for the caller's actual reach check.
	# The caller measures the actual face distance; 1mm here accommodates its
	# strictly-inside endpoint at a half-open ownership boundary, not extra reach.
	return _continuous_outdoor_space(from_location,to_location,float(config().maxReach)+0.001,0.0,0.0,0.0)

func continuous_outdoor_segment(from_location:Dictionary,to_location:Dictionary,max_distance:float,require_resident:bool=true)->Dictionary:
	# Management adjacency/data coverage ONLY, independent of hand reach and
	# actual occlusion. B/E must still apply their own range, sight/contact,
	# entity/door/permission rules. No old-city portal bypass, no body proof.
	if not is_finite(max_distance) or max_distance<=0.0 or max_distance>256.0:return Data.reject("INVALID_SEGMENT_LIMIT")
	return _continuous_outdoor_space(from_location,to_location,max_distance,0.0,0.0,0.0,require_resident)

func continuous_outdoor_neighbors(region_id:String)->Array:
	# Topology only. The face is half-open on its two varying axes and has
	# zero thickness on axis; B supplies real inset feet/body/door candidates.
	var result:Array=[]
	if not Data.is_continuous_outdoor_generator(str(identity().generatorVersion)):return result
	var first:Dictionary=region(region_id)
	if first.get("kind")!="rural" or not first.get("generated",false):return result
	for other:Dictionary in regions():
		if other.id==region_id or other.get("kind")!="rural" or not other.get("generated",false):continue
		var a:Dictionary=first.bounds;var b:Dictionary=other.bounds
		var lo:=Vector3(maxf(a.min.x,b.min.x),maxf(a.min.y,b.min.y),maxf(a.min.z,b.min.z))
		var hi:=Vector3(minf(a.max.x,b.max.x),minf(a.max.y,b.max.y),minf(a.max.z,b.max.z))
		if lo.y>=hi.y:continue
		var axis:String="";var coordinate:=0.0
		if (a.max.x==b.min.x or b.max.x==a.min.x) and lo.z<hi.z:axis="x";coordinate=lo.x
		elif (a.max.z==b.min.z or b.max.z==a.min.z) and lo.x<hi.x:axis="z";coordinate=lo.z
		if axis.is_empty():continue
		result.append({"from_region_id":region_id,"to_region_id":other.id,"face":{"axis":axis,"coordinate":coordinate,"min":{"x":lo.x,"y":lo.y,"z":lo.z},"max":{"x":hi.x,"y":hi.y,"z":hi.z}},"world_revision":get_revision()})
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.to_region_id<b.to_region_id)
	return result

func _continuous_outdoor_space(from_location:Dictionary,to_location:Dictionary,limit:float,radius:float,height:float,depth:float,require_resident:bool=true)->Dictionary:
	var result:Dictionary={"ok":false,"code":"NOT_CONTINUOUS_OUTDOOR","reason":"仅支持已生成且已驻留的连续农村室外空间","from_region_id":str(from_location.get("regionId","")),"to_region_id":str(to_location.get("regionId","")),"world_revision":get_revision()}
	if not Data.vec(from_location) or not Data.vec(to_location):result.code="INVALID_LOCATION";return result
	if from_location.get("buildingId")!=null or from_location.get("storeyId")!=null or to_location.get("buildingId")!=null or to_location.get("storeyId")!=null:return result
	if not Data.is_continuous_outdoor_generator(str(identity().generatorVersion)):return result
	var a:=Vector3(from_location.x,from_location.y,from_location.z);var b:=Vector3(to_location.x,to_location.y,to_location.z)
	if a.distance_to(b)>limit+0.000001:result.code="SEGMENT_TOO_LONG";result.reason="连续空间查询超过本次有界段长度";return result
	var first:Dictionary=region_at(from_location);var last:Dictionary=region_at(to_location)
	if first.is_empty() or last.is_empty():result.code="UNKNOWN_REGION";result.reason="目标尚未生成";return result
	if first.id!=result.from_region_id or last.id!=result.to_region_id:result.code="REGION_MISMATCH";result.reason="位置与实际地区分区不一致";return result
	for r:Dictionary in [first,last]:
		if r.get("kind")!="rural" or not r.get("generated",false):return result
	# Real bounds, not seed/region-name guesses or a preselected exit portal.
	# A straight segment can cross one shared rectangular face; corner-only
	# adjacency and gaps remain closed, even if some unrelated chunks exist.
	var lo:=a.min(b)-Vector3(radius,depth,radius)
	var hi:=a.max(b)+Vector3(radius,height,radius)
	var outer_min:=Vector3(first.bounds.min.x,first.bounds.min.y,first.bounds.min.z)
	var outer_max:=Vector3(first.bounds.max.x,first.bounds.max.y,first.bounds.max.z)
	if first.id!=last.id:
		var f:Dictionary=first.bounds;var t:Dictionary=last.bounds
		var along_x:bool=(float(f.max.x)==float(t.min.x) or float(t.max.x)==float(f.min.x)) and maxf(f.min.z,t.min.z)<minf(f.max.z,t.max.z)
		var along_z:bool=(float(f.max.z)==float(t.min.z) or float(t.max.z)==float(f.min.z)) and maxf(f.min.x,t.min.x)<minf(f.max.x,t.max.x)
		if not along_x and not along_z:result.code="NOT_ADJACENT";result.reason="农村地区没有公共连续边界";return result
		outer_min=Vector3(minf(f.min.x,t.min.x) if along_x else maxf(f.min.x,t.min.x),maxf(f.min.y,t.min.y),maxf(f.min.z,t.min.z) if along_x else minf(f.min.z,t.min.z))
		outer_max=Vector3(maxf(f.max.x,t.max.x) if along_x else minf(f.max.x,t.max.x),minf(f.max.y,t.max.y),minf(f.max.z,t.max.z) if along_x else maxf(f.max.z,t.max.z))
	if lo.x<outer_min.x or lo.y<outer_min.y or lo.z<outer_min.z or hi.x>=outer_max.x or hi.y>=outer_max.y or hi.z>=outer_max.z:
		result.code="UNKNOWN_SPACE";result.reason="本段接触或身体包络越出已证明的连续区域";return result
	if radius==0.0 and height==0.0 and depth==0.0:
		var missing:Dictionary=_outdoor_coverage(a,b,require_resident)
		if not missing.is_empty():result.code=missing.get("code","UNKNOWN_CELL");result.reason="本段实际经过的体素尚未就绪";result.cell=missing.get("cell",{});return result
		result.ok=true;result.code="OK";result.reason=null
		return result
	var cfg:Dictionary=config();var width:float=float(cfg.cellSize)*int(cfg.chunkCells)
	var lower:=Vector3i(floori(lo.x/width),floori(lo.y/width),floori(lo.z/width))
	var upper:=Vector3i(floori(hi.x/width),floori(hi.y/width),floori(hi.z/width))
	for z in range(lower.z,upper.z+1):
		for y in range(lower.y,upper.y+1):
			for x in range(lower.x,upper.x+1):
				var chunk_data:Dictionary=_state.get("chunks",{}).get(Data.key(Vector3i(x,y,z)),{})
				if not chunk_data.get("generated",false):result.code="UNKNOWN_CELL";result.reason="本段体素尚未生成";return result
				if not chunk_data.get("resident",false):result.code="UNLOADED_CELL";result.reason="本段体素尚未加载";return result
	result.ok=true;result.code="OK";result.reason=null
	return result

func _outdoor_coverage(a:Vector3,b:Vector3,require_resident:bool)->Dictionary:
	# Coverage is uniform within each generated/resident chunk. Do not copy its
	# cells or read materials for a partition proof; actual occlusion stays in
	# TerrainQueries/B. No memo or secondary residency authority is introduced.
	var cfg:Dictionary=_state.config
	var cell_size:float=float(cfg.cellSize)
	# The finite vertical cell interval may cut through a chunk. Retain the
	# exact cell traversal at its boundary, including closed negative endpoints.
	if minf(a.y,b.y)<=int(cfg.minCellY)*cell_size or maxf(a.y,b.y)>=int(cfg.maxCellY)*cell_size:
		return TerrainQueries.coverage(self,a,b,require_resident)
	var width:float=cell_size*int(cfg.chunkCells)
	var p:=Vector3i(floori(a.x/width),floori(a.y/width),floori(a.z/width))
	var d:=b-a
	var step:=Vector3i(signi(int(signf(d.x))),signi(int(signf(d.y))),signi(int(signf(d.z))))
	# Scalar doubles avoid repeatedly accumulating Vector3's float32 t values
	# on long lines; exact tied axes advance together, never a side-grazed cell.
	var delta:=PackedFloat64Array([INF,INF,INF])
	var next:=PackedFloat64Array([INF,INF,INF])
	for axis in 3:
		if d[axis]!=0.0:
			delta[axis]=absf(width/d[axis])
			next[axis]=((p[axis]+(1 if step[axis]>0 else 0))*width-a[axis])/d[axis]
	for count in 4096:
		var chunk_data:Dictionary=_state.chunks.get(Data.key(p),{})
		if not chunk_data.get("generated",false) or (require_resident and not chunk_data.get("resident",false)):
			# Rare rejected paths preserve the previous exact nearest-cell DTO and
			# code. Positive visible paths never do a long per-cell traversal.
			return TerrainQueries.coverage(self,a,b,require_resident)
		var earliest:float=minf(next[0],minf(next[1],next[2]))
		if earliest>1.0:return {}
		for axis in 3:
			if absf(next[axis]-earliest)<0.0000000001:
				p[axis]+=step[axis]
				next[axis]+=delta[axis]
	return {"unknown":true,"code":"RAY_BUDGET"}

func is_cell_known(x: int, y: int, z: int) -> bool:
	if _state.is_empty(): return false
	var c: Dictionary = _state.config
	if y < c.minCellY or y >= c.maxCellY: return false
	var metadata:Dictionary=_state.chunks.get(Data.key(Data.cell_chunk(Vector3i(x,y,z),int(c.chunkCells))),{})
	return metadata.get("generated",false) and not metadata.has("cell_page")

func cell_at(x: int, y: int, z: int) -> int:
	if _state.is_empty(): return 0
	if y < _state.config.minCellY or y >= _state.config.maxCellY: return 0
	var c := Vector3i(x,y,z)
	var n := int(_state.config.chunkCells)
	var chunk_data: Dictionary = _state.chunks.get(Data.key(Data.cell_chunk(c,n)),{})
	return int(chunk_data.cells[Data.local_index(c,n)]) if chunk_data.get("generated",false) and not chunk_data.has("cell_page") else 0

func is_cell_resident(x: int,y: int,z: int) -> bool:
	if _state.is_empty() or y < _state.config.minCellY or y >= _state.config.maxCellY: return false
	var c: Dictionary = _state.chunks.get(Data.key(Data.cell_chunk(Vector3i(x,y,z),int(_state.config.chunkCells))),{})
	return c.get("generated",false) and c.get("resident",false)

func surface_height(x: float, z: float) -> Variant:
	if _state.is_empty() or not is_finite(x) or not is_finite(z): return null
	var c: Dictionary = _state.config
	var i := floori(x/c.cellSize)
	var k := floori(z/c.cellSize)
	var n := int(c.chunkCells)
	var cx := floori(float(i)/n)
	var cz := floori(float(k)/n)
	var column := posmod(i,n)+n*posmod(k,n)
	var j := int(c.maxCellY)-1
	while j >= int(c.minCellY):
		var cy := floori(float(j)/n)
		var chunk_data: Dictionary = _state.chunks.get(Data.key(Vector3i(cx,cy,cz)),{})
		if not chunk_data.get("generated",false) or chunk_data.has("cell_page"): return null
		var bottom := maxi(int(c.minCellY),cy*n)
		var cells: PackedInt32Array = PackedInt32Array(chunk_data.cells)
		while j >= bottom:
			if cells[column+n*n*posmod(j,n)] != 0: return (j+1)*float(c.cellSize)
			j -= 1
	return null
