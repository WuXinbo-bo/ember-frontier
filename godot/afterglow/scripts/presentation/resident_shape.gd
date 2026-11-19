extends RefCounted
## Finite derived meshes for the three delivered rigid-part rigs. Original
## GLBs, part transforms, animation tracks, hands and sockets remain untouched.
const POLICY="ar18-faceted-silhouette-v1"
static var _derived:Dictionary={}
static var _lens:StandardMaterial3D

static func apply(model:Node3D,profile:String)->Dictionary:
	if profile not in ["r1_resident_commuter","r1_resident_neighbor","r1_resident_shopkeeper"]:return {"ok":true,"policy":"original","parts":[]}
	if model.has_meta("resident_shape_report"):return model.get_meta("resident_shape_report").duplicate(true)
	var meshes:Array=model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:meshes.push_front(model)
	var changes:Array=[];var errors:Array=[];var found:Array=[]
	for node:MeshInstance3D in meshes:
		var role:String=str(node.name)
		if role not in ["root","head","arm_l","arm_r","leg_l","leg_r"]:continue
		found.append(role)
		var expected:int=16 if profile=="r1_resident_neighbor" else 12 if profile=="r1_resident_shopkeeper" else 10
		if role!="head":expected=4 if role=="root" and profile!="r1_resident_shopkeeper" else 3 if role=="root" else 2
		var source:Mesh=node.mesh
		if source==null or source.get_surface_count()!=1:
			errors.append({"part":role,"reason":"original single surface missing"});continue
		var arrays:Array=source.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_VERTEX].size()!=expected*24:
			errors.append({"part":role,"reason":"original rigid cuboid topology changed","vertices":arrays[Mesh.ARRAY_VERTEX].size()});continue
		var targets:Dictionary=_targets(arrays,role,profile)
		if not targets.ok:
			errors.append({"part":role,"reason":"original cuboid dimensions changed","detail":targets});continue
		# A freed/reloaded GLB has new instance IDs. Keep one finite slot per
		# profile/part; replace its revision instead of accumulating stale keys.
		var key:String=profile+":"+role
		var signature:String=var_to_bytes(arrays).hex_encode().sha256_text()+":"+str(source.surface_get_material(0).get_instance_id())
		changes.append({"node":node,"source":source,"targets":targets.parts,"signature":signature,"key":key,"part":role})
	for role:String in ["root","head","arm_l","arm_r","leg_l","leg_r"]:
		if found.count(role)!=1:errors.append({"reason":"one of each original rigid part required","part":role,"found":found})
	if not errors.is_empty():return {"ok":false,"policy":POLICY,"errors":errors}
	var report:Array=[]
	for change:Dictionary in changes:
		if not _derived.has(change.key) or _derived[change.key].signature!=change.signature:
			_derived[change.key]={"signature":change.signature,"mesh":_build(change.source,change.part,profile,change.targets)}
		var mesh:ArrayMesh=_derived[change.key].mesh
		change.node.mesh=mesh
		change.node.set_meta("resident_shape",POLICY)
		report.append({"part":change.part,"surfaces":mesh.get_surface_count(),"triangles":mesh.get_faces().size()/3})
	model.set_meta("resident_shape",POLICY)
	var result:Dictionary={"ok":true,"policy":POLICY,"parts":report,"new_uv":false,"rig_changed":false}
	model.set_meta("resident_shape_report",result)
	return result.duplicate(true)

static func _targets(a:Array,role:String,profile:String)->Dictionary:
	# Godot's importer reorders cuboids; original GLB ordinal is NOT a stable ID.
	# Match finite original local bounds, including normal import quantization.
	var boxes:Dictionary={}
	if role=="head":
		boxes={1:[Vector3(-.205,.03,-.18),Vector3(.205,.39,.18)],2:[Vector3(-.22,.355,-.21),Vector3(.22,.465,.18)],3:[Vector3(-.21,.11,-.195),Vector3(.21,.39,-.125)]}
		if profile=="r1_resident_neighbor":
			boxes.merge({10:[Vector3(-.18,.1775,.1985),Vector3(-.03,.2825,.2135)],11:[Vector3(-.16,.195,.2135),Vector3(-.05,.265,.2205)],12:[Vector3(.03,.1775,.1985),Vector3(.18,.2825,.2135)],13:[Vector3(.05,.195,.2135),Vector3(.16,.265,.2205)],15:[Vector3(-.105,.24,-.37),Vector3(.105,.44,-.17)]})
		elif profile=="r1_resident_shopkeeper":boxes.merge({10:[Vector3(-.23,.44,-.2),Vector3(.23,.52,.2)],11:[Vector3(-.22,.4225,.17),Vector3(.22,.4575,.33)]})
	elif role=="root":boxes={0:[Vector3(-.24,.83,-.145),Vector3(.24,1.43,.145)]}
	elif role in ["arm_l","arm_r"]:boxes={0:[Vector3(-.095,-.46,-.125),Vector3(.095,0,.125)]}
	elif role in ["leg_l","leg_r"]:boxes={1:[Vector3(-.115,-.78,-.135),Vector3(.115,-.63,.205)]}
	var parts:Dictionary={}
	for semantic:int in boxes:
		var matches:Array=[]
		for actual:int in int(a[Mesh.ARRAY_VERTEX].size()/24):
			var b:AABB=_bounds(a,actual)
			if b.position.distance_to(boxes[semantic][0])<.00005 and b.end.distance_to(boxes[semantic][1])<.00005:matches.append(actual)
		if matches.size()!=1 or parts.has(matches[0]):return {"ok":false,"semantic":semantic,"matches":matches}
		parts[matches[0]]=semantic
	return {"ok":true,"parts":parts}

static func _build(source:Mesh,role:String,profile:String,targets:Dictionary)->ArrayMesh:
	var a:Array=source.surface_get_arrays(0)
	var solid:Dictionary=_bucket();var glass:Dictionary=_bucket()
	var spans:Array=[]
	var count:int=a[Mesh.ARRAY_VERTEX].size()/24
	for actual:int in count:
		var part:int=targets.get(actual,-1)
		var box:AABB=_bounds(a,actual)
		if role=="head" and profile=="r1_resident_neighbor" and part in [11,13]:
			var first_glass:int=glass.vertices.size();_copy(a,actual,glass)
			spans.append({"part":actual,"semantic":part,"surface":1,"first":first_glass,"count":glass.vertices.size()-first_glass});continue
		var first_solid:int=solid.vertices.size()
		if role=="head" and profile=="r1_resident_neighbor" and part in [10,12]:
			_frame(a,actual,box,solid)
			spans.append({"part":actual,"semantic":part,"surface":0,"first":first_solid,"count":solid.vertices.size()-first_solid});continue
		if role=="head" and part==2:
			_hair(a,actual,box,profile,solid)
			spans.append({"part":actual,"semantic":part,"surface":0,"first":first_solid,"count":solid.vertices.size()-first_solid});continue
		var rings:Array=[]
		if role=="head" and part==1:
			# Faceted jaw/temple inside the original head; eye/front plane retained.
			rings=[_ring(box,0,0.78,0.82,0.028),_ring(box,0.18,1,1,0.034),_ring(box,0.80,1,1,0.034),_ring(box,1,0.88,0.94,0.032)]
		elif role=="head" and part==3:
			rings=[_ring(box,0,0.90,0.86,0.014),_ring(box,0.84,1,1,0.018),_ring(box,1,0.92,0.92,0.018)]
		elif role=="head" and profile=="r1_resident_neighbor" and part==15:
			rings=[_ring(box,0,0.70,0.72,0.025),_ring(box,0.45,1,1,0.035),_ring(box,1,0.68,0.70,0.025)]
		elif role=="head" and profile=="r1_resident_shopkeeper" and part==10:
			rings=[_ring(box,0,1,1,0.050),_ring(box,0.50,0.96,0.95,0.052),_ring(box,1,0.72,0.70,0.040)]
		elif role=="head" and profile=="r1_resident_shopkeeper" and part==11:
			rings=[_ring(box,0,0.95,0.90,0.025),_ring(box,1,1,1,0.032)]
		elif role=="root" and part==0:
			# Keep the chest/hem envelope, slope only the top shoulder corners.
			rings=[_ring(box,0,0.98,0.98,0.024),_ring(box,0.90,1,1,0.030),_ring(box,1,0.64,0.78,0.025)]
		elif role in ["arm_l","arm_r"] and part==0:
			# Keep the inner shoulder seam; bevel the outer cap, not the joint.
			# Original hand positions/UV are exact; normals use native packing.
			var inward:float=0.0095 if role=="arm_l" else -0.0095
			rings=[_ring(box,0,1,1,0.018),_ring(box,0.84,1,1,0.022),_ring(box,1,0.90,0.90,0.020,Vector2(inward,0))]
		elif role in ["leg_l","leg_r"] and part==1:
			# Full sole contact bounds remain; the toe/upper tapers to the ankle.
			rings=[_ring(box,0,1,1,0.024),_ring(box,0.20,1,1,0.024),_ring(box,0.66,0.96,0.94,0.028),_ring(box,1,0.86,0.68,0.025,Vector2(0,-0.038))]
		if rings.is_empty():_copy(a,actual,solid)
		else:_loft(a,actual,rings,solid)
		spans.append({"part":actual,"semantic":part,"surface":0,"first":first_solid,"count":solid.vertices.size()-first_solid})
	var mesh:=ArrayMesh.new()
	_surface(mesh,solid,source.surface_get_material(0))
	if not glass.vertices.is_empty():_surface(mesh,glass,_lens_material())
	mesh.set_meta("resident_shape",POLICY)
	mesh.set_meta("source_spans",spans)
	return mesh

static func _bucket()->Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"indices":PackedInt32Array()}

static func _hair(a:Array,part:int,box:AABB,profile:String,out:Dictionary)->void:
	# One connected fitted base with broad swept facets, no flat cap plateau.
	# The two ridge vertices stay within the original height and UV footprint.
	var base:Array=_ring(box,0,1,1,.032)
	var rim:Array=_ring(box,0,1,1,.032)
	var heights:Array=[.40,.45,.40,.60,.55,.50,.65,.60]
	for i:int in 8:rim[i].y=box.position.y+box.size.y*float(heights[i])
	_polygon(a,part,base,Vector3.DOWN,out)
	for i:int in 8:
		var next:int=(i+1)%8;var middle:Vector3=(base[i]+base[next])*.5-box.get_center()
		_polygon(a,part,[base[i],base[next],rim[next],rim[i]],Vector3(middle.x,0,middle.z),out)
	var side:float=-1 if profile=="r1_resident_neighbor" else 1
	var c:Vector3=box.get_center()
	var ridge_a:=Vector3(c.x+side*.028,box.end.y,c.z-.070)
	var ridge_b:=Vector3(c.x-side*.060,box.end.y-.018,c.z+.055)
	for points:Array in [[ridge_a,rim[0],rim[1]],[ridge_a,rim[1],rim[2]],[ridge_a,rim[2],rim[3]],[ridge_a,rim[3],ridge_b],[ridge_b,rim[3],rim[4]],[ridge_b,rim[4],rim[5]],[ridge_b,rim[5],rim[6]],[ridge_b,rim[6],rim[7]],[ridge_b,rim[7],ridge_a],[ridge_a,rim[7],rim[0]]]:
		_polygon(a,part,points,Vector3.UP,out)

static func _bounds(a:Array,part:int)->AABB:
	var vs:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
	var result:=AABB(vs[part*24],Vector3.ZERO)
	for i:int in range(part*24+1,(part+1)*24):result=result.expand(vs[i])
	return result

static func _ring(box:AABB,height:float,width:float,depth:float,bevel:float,offset:Vector2=Vector2.ZERO)->Array:
	var c:Vector3=box.get_center();var x:float=box.size.x*width*0.5;var z:float=box.size.z*depth*0.5
	var b:float=minf(bevel,minf(x,z)*0.75);var y:float=box.position.y+box.size.y*height
	var result:Array=[]
	for p:Vector2 in [Vector2(-x+b,-z),Vector2(x-b,-z),Vector2(x,-z+b),Vector2(x,z-b),Vector2(x-b,z),Vector2(-x+b,z),Vector2(-x,z-b),Vector2(-x,-z+b)]:
		result.append(Vector3(c.x+p.x+offset.x,y,c.z+p.y+offset.y))
	return result

static func _loft(a:Array,part:int,rings:Array,out:Dictionary)->void:
	_polygon(a,part,rings[0],Vector3.DOWN,out)
	_polygon(a,part,rings[-1],Vector3.UP,out)
	for level:int in rings.size()-1:
		for edge:int in 8:
			var next:int=(edge+1)%8
			var points:Array=[rings[level][edge],rings[level][next],rings[level+1][next],rings[level+1][edge]]
			var center:Vector3=_bounds(a,part).get_center();var middle:Vector3=(points[0]+points[1])*0.5
			_polygon(a,part,points,Vector3(middle.x-center.x,0,middle.z-center.z),out)

static func _copy(a:Array,part:int,out:Dictionary)->void:
	var base:int=out.vertices.size();var start:int=part*24
	for i:int in range(start,start+24):
		out.vertices.append(a[Mesh.ARRAY_VERTEX][i]);out.normals.append(a[Mesh.ARRAY_NORMAL][i]);out.uv.append(a[Mesh.ARRAY_TEX_UV][i])
	for i:int in a[Mesh.ARRAY_INDEX]:
		if i>=start and i<start+24:out.indices.append(base+i-start)

static func _frame(a:Array,part:int,box:AABB,out:Dictionary)->void:
	var p:Vector3=box.position;var s:Vector3=box.size
	var rail_x:float=0.020;var rail_y:float=0.0175
	_cuboid(a,part,AABB(p,Vector3(s.x,rail_y,s.z)),out)
	_cuboid(a,part,AABB(p+Vector3(0,s.y-rail_y,0),Vector3(s.x,rail_y,s.z)),out)
	_cuboid(a,part,AABB(p+Vector3(0,rail_y,0),Vector3(rail_x,s.y-2*rail_y,s.z)),out)
	_cuboid(a,part,AABB(p+Vector3(s.x-rail_x,rail_y,0),Vector3(rail_x,s.y-2*rail_y,s.z)),out)

static func _cuboid(a:Array,part:int,b:AABB,out:Dictionary)->void:
	var p:Vector3=b.position;var q:Vector3=b.end
	for axis:int in 3:
		var u:int=(axis+1)%3;var v:int=(axis+2)%3
		for sign:int in [-1,1]:
			var points:Array=[]
			for step:Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var point:Vector3=p;point[axis]=q[axis] if sign>0 else p[axis];point[u]=lerpf(p[u],q[u],step.x);point[v]=lerpf(p[v],q[v],step.y);points.append(point)
			var normal:=Vector3.ZERO;normal[axis]=sign;_polygon(a,part,points,normal,out)

static func _polygon(a:Array,part:int,input:Array,outward:Vector3,out:Dictionary)->void:
	var points:Array=input.duplicate()
	var normal:Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if normal.dot(outward)<0:points.reverse();normal=-normal
	var base:int=out.vertices.size()
	for p:Vector3 in points:
		out.vertices.append(p);out.normals.append(normal);out.uv.append(_face_uv(a,part,p,normal))
	var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX];var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=a[Mesh.ARRAY_NORMAL]
	var winding:float=(vertices[indices[1]]-vertices[indices[0]]).cross(vertices[indices[2]]-vertices[indices[0]]).dot(normals[indices[0]])
	for i:int in range(1,points.size()-1):
		out.indices.append(base);out.indices.append(base+i if winding>0 else base+i+1);out.indices.append(base+i+1 if winding>0 else base+i)

static func _face_uv(a:Array,part:int,p:Vector3,n:Vector3)->Vector2:
	# Project to the best ORIGINAL cuboid face and interpolate its UV plane.
	# All new facets remain inside that part's existing atlas island.
	var best:int=part*24;var score:float=-2
	for face:int in 6:
		var first:int=part*24+face*4;var dot:float=a[Mesh.ARRAY_NORMAL][first].dot(n)
		if dot>score:score=dot;best=first
	var origin:Vector3=a[Mesh.ARRAY_VERTEX][best];var e:Vector3=a[Mesh.ARRAY_VERTEX][best+1]-origin
	var other:int=best+2
	if e.cross(a[Mesh.ARRAY_VERTEX][other]-origin).length_squared()<0.0000000001:other=best+3
	var f:Vector3=a[Mesh.ARRAY_VERTEX][other]-origin;var d:Vector3=p-origin
	var aa:float=e.dot(e);var ab:float=e.dot(f);var bb:float=f.dot(f);var det:float=aa*bb-ab*ab
	var u:float=(d.dot(e)*bb-d.dot(f)*ab)/det;var v:float=(d.dot(f)*aa-d.dot(e)*ab)/det
	return a[Mesh.ARRAY_TEX_UV][best]+u*(a[Mesh.ARRAY_TEX_UV][best+1]-a[Mesh.ARRAY_TEX_UV][best])+v*(a[Mesh.ARRAY_TEX_UV][other]-a[Mesh.ARRAY_TEX_UV][best])

static func _surface(mesh:ArrayMesh,b:Dictionary,material:Material)->void:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=b.vertices;arrays[Mesh.ARRAY_NORMAL]=b.normals;arrays[Mesh.ARRAY_TEX_UV]=b.uv;arrays[Mesh.ARRAY_INDEX]=b.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(mesh.get_surface_count()-1,material)

static func _lens_material()->StandardMaterial3D:
	if _lens==null:
		_lens=StandardMaterial3D.new();_lens.resource_name="AR18 clear lens, never body atlas"
		_lens.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		_lens.albedo_color=Color(0.78,0.88,0.93,0.14)
		_lens.roughness=0.18;_lens.metallic=0;_lens.cull_mode=BaseMaterial3D.CULL_DISABLED
		_lens.set_meta("resident_clear_lens",true)
	return _lens
