extends RefCounted
## Pure-value greedy meshing jobs. Native ArrayMesh creation stays on main thread.
const Data = preload("res://scripts/world/world_data.gd")

static func begin(world: RefCounted, key: String, greedy: bool = true) -> Dictionary:
	var chunk: Dictionary = world.chunk(key)
	var output := {"ok":true,"groups":{},"quads":0,"solid_cells":0,"revision":world.get_revision()}
	if chunk.is_empty() or not chunk.resident:return {"done":true,"output":output}
	var n := int(world.config().chunkCells)
	var s := float(world.config().cellSize)
	var origin := Vector3(int(chunk.coord.x)*n,int(chunk.coord.y)*n,int(chunk.coord.z)*n)*s
	var cells: PackedInt32Array = PackedInt32Array(chunk.cells)
	var solid := cells.size()-cells.count(0)
	output.solid_cells=solid
	if solid==0:return {"done":true,"output":output}
	var first_solid := 0
	while cells[first_solid]==0:first_solid+=1
	var last_solid := cells.size()-1
	while cells[last_solid]==0:last_solid-=1
	var plane := n*n
	var slab := solid == last_solid-first_solid+1 and first_solid%plane==0 and (last_solid+1)%plane==0
	var tasks:Array=[]
	for d in 3:
		for sign in [-1,1]:
			var q:Vector3i=Data.coord(key);q[d]+=sign
			var neighbor:Dictionary=world.chunk(Data.key(q))
			var other_cells:Variant=neighbor.get("cells") if neighbor.get("resident",false) else null
			var layers:Array=range(first_solid/plane,last_solid/plane+1) if d==1 else range(n)
			if slab:layers=[last_solid/plane if sign>0 else first_solid/plane] if d==1 else [n-1 if sign>0 else 0]
			for layer:int in layers:tasks.append({"d":d,"sign":sign,"layer":layer,"other_cells":other_cells})
	# Packed arrays are detached COW snapshots. No later step reads a mutable
	# world or accesses Nodes/Resources; callers validate dependencies to publish.
	return {"done":false,"output":output,"n":n,"s":s,"origin":origin,"cells":cells,"tasks":tasks,"cursor":0,"greedy":greedy}

static func advance(job:Dictionary,max_layers:int=1)->bool:
	if job.done:return true
	var n:int=job.n;var s:float=job.s;var origin:Vector3=job.origin
	var cells:PackedInt32Array=job.cells;var greedy:bool=job.greedy
	var groups:Dictionary=job.output.groups;var quads:int=job.output.quads
	var strides := [1,n*n,n]
	for iteration in maxi(1,max_layers):
		if int(job.cursor)>=job.tasks.size():break
		var task:Dictionary=job.tasks[job.cursor];job.cursor+=1
		var d:int=task.d;var sign:int=task.sign;var layer:int=task.layer
		var other_cells:Variant=task.other_cells
		var u:int=(d+1)%3;var v:int=(d+2)%3
		var layer_stride:int=strides[d];var u_stride:int=strides[u];var v_stride:int=strides[v]
		var mask := PackedInt32Array()
		mask.resize(n*n)
		var adjacent: int = layer+sign
		var inside: bool = adjacent>=0 and adjacent<n
		var neighbor_offset: int = ((0 if sign>0 else n-1)-layer)*layer_stride
		for y in n:
			var row: int = layer*layer_stride+y*v_stride
			for x in n:
				var index: int = row+x*u_stride
				var m := cells[index]
				if m == 0: continue
				var other := 0
				if inside: other = cells[index+sign*layer_stride]
				elif other_cells != null: other = int(other_cells[index+neighbor_offset])
				if other == 0: mask[x+n*y] = m
		for y in n:
			var x := 0
			while x < n:
				var m := mask[x+n*y]
				if m == 0:
					x += 1
					continue
				var w := 1
				var h := 1
				if greedy:
					while x+w < n and mask[x+w+n*y] == m: w += 1
					var extend := true
					while y+h < n and extend:
						for dx in w:
							if mask[x+dx+n*(y+h)] != m:
								extend = false
								break
						if extend: h += 1
				var face := "top" if d == 1 and sign > 0 else "side"
				var texture: String = Data.MATERIALS[m][face]
				var group_id := str(m)+":"+face
				if not groups.has(group_id): groups[group_id] = {"texture":texture,"material":m,"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uvs":PackedVector2Array(),"indices":PackedInt32Array()}
				var g: Dictionary = groups[group_id]
				var first: int = g.vertices.size()
				var normal := Vector3.ZERO
				normal[d] = sign
				var corners := [[0,0],[w,0],[w,h],[0,h]] if sign > 0 else [[0,0],[0,h],[w,h],[w,0]]
				for corner in corners:
					var p := origin
					p[d] += (layer+(1 if sign > 0 else 0))*s
					p[u] += (x+corner[0])*s
					p[v] += (y+corner[1])*s
					g.vertices.append(p)
					g.normals.append(normal)
					# Continuous world metres, never chunk-local texture origins.
					# The bound material applies its manifest's own metre scale.
					g.uvs.append(Vector2(p.x,p.z) if d == 1 else Vector2(p.z if d == 0 else p.x,p.y))
				# Existing TS order has cross=outward; Godot expects clockwise.
				for i in [0,2,1,0,3,2]: g.indices.append(first+i)
				quads += 1
				for dy in h:
					for dx in w: mask[x+dx+n*(y+dy)] = 0
				x += w
	job.output.quads=quads
	job.done=int(job.cursor)>=job.tasks.size()
	return job.done

static func build(world:RefCounted,key:String,greedy:bool=true)->Dictionary:
	var job:=begin(world,key,greedy)
	while not advance(job,96):pass
	return job.output

static func mesh(data: Dictionary, materials: RefCounted = null) -> ArrayMesh:
	var out := ArrayMesh.new()
	for g in data.groups.values():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.vertices
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		arrays[Mesh.ARRAY_INDEX] = g.indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if materials != null:
			var top: bool = g.normals[0].y>0.5
			# Exposed soil tops and vertical excavated sections are separate render
			# treatments. The authoritative material number and mesh stay intact.
			var id: String = "soil_top" if top and g.material==2 else g.texture
			out.surface_set_material(out.get_surface_count()-1,materials.terrain_material(id,"top" if top else "side"))
	return out
