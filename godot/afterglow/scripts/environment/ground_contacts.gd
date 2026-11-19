extends RefCounted
## Disposable visual boundary of live foundation facts. Not navigation/support,
## not new terrain/material facts, and never saved. Buckets only bound derivation.
const WIDTH := 0.3
var pitch := 8.0
var _signature := ""
var _footprints: Array = []
var _bins: Dictionary = {}
var _candidates: Dictionary = {}
var _segments: Dictionary = {}

func _bucket(x: float,z: float) -> String: return str(floori(x/pitch))+","+str(floori(z/pitch))

func update(entities: Array) -> Array:
	var footprints: Array = []
	for e in entities:
		if e.get("kind")!="structure" or not e.get("tags",[]).has("foundation"): continue
		if float(e.get("data",{}).get("structure",{}).get("hp",0))<=0: continue
		var b: Dictionary = e.bounds
		var y := float(e.position.y)
		if absf(float(b.max.y)-y)>0.05: continue
		footprints.append({"id":e.id,"lo":Vector2(b.min.x,b.min.z),"hi":Vector2(b.max.x,b.max.z),"y":y})
	footprints.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return str(a.id)<str(b.id))
	var signature := str(footprints)
	if signature==_signature: return []
	var dirty: Dictionary = {}
	for key in _candidates: dirty[key]=true
	_signature=signature;_footprints=footprints;_bins.clear();_candidates.clear();_segments.clear()
	for i in _footprints.size():
		var f: Dictionary = _footprints[i]
		for z in range(floori((f.lo.y-WIDTH)/pitch),floori((f.hi.y+WIDTH)/pitch)+1):
			for x in range(floori((f.lo.x-WIDTH)/pitch),floori((f.hi.x+WIDTH)/pitch)+1):
				var bucket := str(x)+","+str(z)
				if not _bins.has(bucket): _bins[bucket]=[]
				_bins[bucket].append(i)
	# Resolve static internal/shared foundation edges once per layout change,
	# not again for every chunk and every voxel edit. Ground support/residency
	# remains queried on each build, so this cache cannot resurrect old terrain.
	for index in _footprints.size():
		var f: Dictionary = _footprints[index]
		var corners := [Vector2(f.lo.x,f.lo.y),Vector2(f.hi.x,f.lo.y),Vector2(f.hi.x,f.hi.y),Vector2(f.lo.x,f.hi.y)]
		for side in 4:
			var a: Vector2=corners[side];var b: Vector2=corners[(side+1)%4]
			var length := a.distance_to(b)
			if length<0.00001: continue
			var along := (b-a)/length;var out := Vector2(along.y,-along.x)
			for part in ceili(length/0.5):
				var from := a+along*minf(part*0.5,length)
				var to := a+along*minf((part+1)*0.5,length)
				var middle := (from+to)/2.0
				if _covered(middle+out*0.001,f.y,index): continue
				var center := middle+out*WIDTH/2.0
				var key := str(floori(center.x/pitch))+","+str(floori((f.y-0.001)/pitch))+","+str(floori(center.y/pitch))
				var size := Vector2(absf(to.x-from.x)+absf(out.x)*WIDTH,absf(to.y-from.y)+absf(out.y)*WIDTH)
				if not _segments.has(key): _segments[key]=[]
				_segments[key].append({"id":f.id,"center":Vector3(center.x,f.y,center.y),"size":size,"points":[from,to,to+out*WIDTH,from+out*WIDTH]})
				_candidates[key]=true;dirty[key]=true
	return dirty.keys()

func _covered(p: Vector2,y: float,excluding: int) -> bool:
	for i in _bins.get(_bucket(p.x,p.y),[]):
		if i==excluding: continue
		var f: Dictionary = _footprints[i]
		if absf(float(f.y)-y)<0.01 and p.x>=f.lo.x-0.00001 and p.x<=f.hi.x+0.00001 and p.y>=f.lo.y-0.00001 and p.y<=f.hi.y+0.00001: return true
	return false

func build(key: String,grounded: Callable) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var ids: Dictionary = {}
	for segment in _segments.get(key,[]):
		# Full footprint, resident exposed grass only: no grass on roads,
		# floating dirt over holes, or decorations in unknown/cold chunks.
		if not grounded.call(segment.center,segment.size,1): continue
		var first := vertices.size()
		for k in 4:
			var p: Vector2=segment.points[k]
			vertices.append(Vector3(p.x,segment.center.y+0.009,p.y))
			normals.append(Vector3.UP);uvs.append(p)
			colours.append(Color(1,1,1,1 if k<2 else 0))
		for k in [0,1,2,0,2,3]: indices.append(first+k)
		ids[segment.id]=true
	var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_INDEX]=indices
	return {"arrays":arrays,"quads":vertices.size()/4,"source_ids":ids.keys()}
