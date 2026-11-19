extends RefCounted
## Authoritative 3-D DDA, not a height-map pick. Unknown is a blocked result.
const Data = preload("res://scripts/world/world_data.gd")

static func segment_contract() -> Dictionary:
	return {"version":1,"cell_ownership":"floor/half-open [min,max)","endpoints":"included by default; include_start/include_end configurable","start_inside":"hit at distance zero","coplanar":"half-open owner only; zero-volume side grazes do not block","corner_tie":"advance all tied axes; choose largest-direction face, XYZ on equal magnitude","unknown":"nearest unknown/cold is a blocked result, never transparent","purposes":["body","sight","contact","support","selection"]}
static func pick(world: RefCounted, a: Vector3, b: Vector3) -> Dictionary:
	# Presentation cameras start above/outside the finite world. Clip only that
	# exterior part; raycast itself still treats every unknown interior cell as
	# blocked for both picking and actor/tool visibility.
	if not a.is_finite() or not b.is_finite() or a.is_equal_approx(b): return {}
	var cfg: Dictionary = world.config()
	var s := float(cfg.cellSize)
	var delta := b-a
	var intervals: Array = []
	for r in world.regions():
		if not r.get("generated",false): continue
		var lo := Vector3(r.bounds.min.x,maxf(r.bounds.min.y,cfg.minCellY*s),r.bounds.min.z)
		var hi := Vector3(r.bounds.max.x,minf(r.bounds.max.y,cfg.maxCellY*s),r.bounds.max.z)
		var enter := 0.0
		var leave := 1.0
		for axis in 3:
			if absf(delta[axis])<0.000000001:
				if a[axis]<lo[axis] or a[axis]>=hi[axis]: leave=-1.0;break
			else:
				var t0 := (lo[axis]-a[axis])/delta[axis]
				var t1 := (hi[axis]-a[axis])/delta[axis]
				enter=maxf(enter,minf(t0,t1));leave=minf(leave,maxf(t0,t1))
		if leave>enter: intervals.append(Vector2(enter,leave))
	intervals.sort_custom(func(x: Vector2,y: Vector2)->bool:return x.x<y.x)
	var epsilon := minf(0.000001,s*0.00001/delta.length())
	for interval: Vector2 in intervals:
		var start := minf(interval.y,interval.x+epsilon)
		var end := maxf(start,interval.y-epsilon)
		var hit := raycast(world,a+delta*start,a+delta*end)
		if hit.is_empty(): continue
		hit.distance=float(hit.get("distance",0.0))+start*delta.length()
		return hit
	return {}

static func raycast(world: RefCounted, a: Vector3, b: Vector3, max_cells: int = 4096, require_resident:bool=false) -> Dictionary:
	# Compatibility entry: existing tool callers retain closed endpoints and
	# generated-only default. Runtime callers explicitly request residency.
	return segment(world,a,b,{"max_cells":max_cells,"require_resident":require_resident,"purpose":"contact"})

static func coverage(world: RefCounted, a: Vector3, b: Vector3, require_resident: bool = true) -> Dictionary:
	# This proves ONLY actual traversed-cell availability. Solid terrain does
	# not make data unknown. Call segment(purpose=sight/contact) for occlusion.
	return segment(world,a,b,{"purpose":"coverage","require_resident":require_resident})

static func segment(world: RefCounted, a: Vector3, b: Vector3, options: Dictionary = {}) -> Dictionary:
	var purpose := str(options.get("purpose","contact"))
	var max_cells := int(options.get("max_cells",4096))
	var require_resident := bool(options.get("require_resident",false))
	var include_start := bool(options.get("include_start",true))
	var include_end := bool(options.get("include_end",true))
	if not a.is_finite() or not b.is_finite() or max_cells < 1 or purpose not in ["body","sight","contact","support","selection","coverage"]: return {"unknown":true,"code":"INVALID_SEGMENT"}
	var config: Dictionary = world.config()
	var s := float(config.cellSize)
	var d := b-a
	var zero_length := d.length_squared() == 0
	if zero_length and not (include_start and include_end):return {}
	var has_segment_cell := world.has_method("segment_cell")
	var has_packed_chunk := world.has_method("segment_packed_chunk")
	var chunk_size: int = int(config.get("chunkCells", 0)) if has_packed_chunk else 0
	var min_y: int = int(config.get("minCellY", 0))
	var max_y: int = int(config.get("maxCellY", 0))
	var packed_cells := PackedInt32Array()
	var chunk_low := Vector3i.ZERO
	var chunk_high := Vector3i.ZERO
	# An open start on a grid face belongs to the immediately entered cell.
	# Do not skip a whole voxel or hide a start actually inside solid terrain.
	var p := Vector3i(floori(a.x/s),floori(a.y/s),floori(a.z/s))
	if not include_start:
		# Native Vector3 can be float32: an epsilon addition can round straight
		# back onto the face. Resolve exact ownership analytically instead.
		for axis in 3:
			if d[axis]<0 and a[axis]==p[axis]*s:p[axis]-=1
	var step := Vector3i(signi(int(signf(d.x))),signi(int(signf(d.y))),signi(int(signf(d.z))))
	var delta := Vector3(INF,INF,INF)
	var next := Vector3(INF,INF,INF)
	for axis in 3:
		if d[axis] != 0:
			delta[axis] = absf(s/d[axis])
			next[axis] = ((p[axis]+(1 if step[axis]>0 else 0))*s-a[axis])/d[axis]
	var t := 0.0
	var normal := Vector3.ZERO
	for count in max_cells:
		if t > 1.0 or (not include_end and t >= 1.0): return {}
		var known: bool
		var material: int
		var unloaded: bool
		if has_segment_cell:
			var sample: int
			# The ray walks through one chunk at a time. Resolve its key once,
			# then read cells by offset without rehashing the same chunk per step.
			if chunk_size > 0 and p.y >= min_y and p.y < max_y:
				if p.x < chunk_low.x or p.x >= chunk_high.x or p.y < chunk_low.y or p.y >= chunk_high.y or p.z < chunk_low.z or p.z >= chunk_high.z:
					var chunk := Data.cell_chunk(p, chunk_size)
					chunk_low = chunk * chunk_size
					chunk_high = chunk_low + Vector3i.ONE * chunk_size
					packed_cells = world.segment_packed_chunk(chunk, require_resident)
				if not packed_cells.is_empty():
					var local := p - chunk_low
					sample = packed_cells[local.x + chunk_size * (local.z + chunk_size * local.y)]
				else:
					sample = world.segment_cell(p, require_resident)
			else:
				sample = world.segment_cell(p, require_resident)
			known = sample != -1
			unloaded = sample == -2
			material = maxi(sample, 0)
		else:
			known = world.is_cell_known(p.x,p.y,p.z)
			unloaded = require_resident and known and not world.is_cell_resident(p.x,p.y,p.z)
			if not unloaded: material = world.cell_at(p.x,p.y,p.z)
		if unloaded:return {"unknown":true,"code":"UNLOADED_CELL","cell":{"x":p.x,"y":p.y,"z":p.z},"world_revision":world.get_revision()}
		if not known or (purpose!="coverage" and Data.material_blocks(material,purpose)):
			return {"cell":{"x":p.x,"y":p.y,"z":p.z},"material":material,"distance":maxf(0,t)*d.length(),"normal":normal,"unknown":not known or not Data.MATERIALS.has(material),"world_revision":world.get_revision(),"target_id":"terrain:%d:%d:%d" % [p.x,p.y,p.z],"purpose":purpose}
		if zero_length: return {}
		var earliest := minf(next.x,minf(next.y,next.z))
		if earliest > 1: return {}
		normal = Vector3.ZERO
		var face_axis := -1
		for axis in 3:
			if absf(next[axis]-earliest) < 0.0000000001:
				p[axis] += step[axis]
				next[axis] += delta[axis]
				# Edge/corner ties still advance every tied axis, but expose one
				# deterministic face. A diagonal normal makes fill skip a face
				# neighbour and write the diagonal cell instead.
				if face_axis < 0 or absf(d[axis]) > absf(d[face_axis]): face_axis = axis
		if face_axis >= 0: normal[face_axis] = -step[face_axis]
		t = earliest
	return {"unknown":true,"code":"RAY_BUDGET"}

static func exposed_face_points(world:RefCounted,cell:Vector3i,origin:Vector3)->Array:
	# Exact face geometry, with a nearest projected point plus stable fallback
	# samples for a partly occluded face. Never grant a face next to unknown or
	# cold air. EditSight may hide only other removals in this same atomic batch.
	var s:float=float(world.config().cellSize);var inset:float=minf(0.001,s*0.001)
	var lo:=Vector3(cell)*s;var hi:=lo+Vector3.ONE*s
	var points:Array=[]
	for normal:Vector3 in [Vector3.UP,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,Vector3.DOWN]:
		var neighbor:=cell+Vector3i(normal)
		if not world.is_cell_known(neighbor.x,neighbor.y,neighbor.z) or not world.is_cell_resident(neighbor.x,neighbor.y,neighbor.z) or world.cell_at(neighbor.x,neighbor.y,neighbor.z)!=0:continue
		var axis:int=normal.abs().max_axis_index();var u:int=(axis+1)%3;var v:int=(axis+2)%3
		var center:Vector3=(lo+hi)*0.5;center[axis]=hi[axis] if normal[axis]>0 else lo[axis]
		var closest:Vector3=origin.clamp(lo+Vector3.ONE*inset,hi-Vector3.ONE*inset);closest[axis]=center[axis]
		points.append({"point":closest,"normal":normal});points.append({"point":center,"normal":normal})
		for du:float in [-1.0,1.0]:
			for dv:float in [-1.0,1.0]:
				var corner:=center;corner[u]+=du*(s*0.5-inset);corner[v]+=dv*(s*0.5-inset)
				points.append({"point":corner,"normal":normal})
	for i in points.size():points[i].order=i
	points.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		var da:float=origin.distance_squared_to(a.point);var db:float=origin.distance_squared_to(b.point)
		return da<db if da!=db else a.order<b.order)
	return points

static func target_at(world: RefCounted, point: Vector3, normal: Vector3) -> Dictionary:
	if not point.is_finite() or not normal.is_finite() or normal.length() < 0.000001: return {}
	var n := normal.normalized()
	if maxf(absf(n.x),maxf(absf(n.y),absf(n.z))) < 0.99999: return {}
	var s := float(world.config().cellSize)
	var p := point-n*s*0.00001
	var c := Vector3i(floori(p.x/s),floori(p.y/s),floori(p.z/s))
	if not world.is_cell_known(c.x,c.y,c.z): return {}
	var material: int = world.cell_at(c.x,c.y,c.z)
	if material == 0: return {}
	return {"cell":{"x":c.x,"y":c.y,"z":c.z},"material":material,"target_id":"terrain:%d:%d:%d" % [c.x,c.y,c.z],"world_revision":world.get_revision()}
