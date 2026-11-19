extends RefCounted
## Batched architectural joinery. Coordinates are local to the member's minimum.
## Wall openings are real mesh recesses with closed panels, not walkable portals.
const G=preload("res://scripts/buildings/building_geometry.gd")
const VERSION:="r34-architecture-detail-v1"
const Roof=preload("res://scripts/buildings/module_roof_mesh.gd")

static func add(builder:RefCounted,part:Dictionary,surfaces:Dictionary)->bool:
	var recipe:Variant=part.get("architecture_detail")
	if not recipe is Dictionary or recipe.get("version")!=VERSION:return false
	var size:Vector3=G.point(recipe.local_size)
	var q:int=posmod(int(recipe.get("quarter_turn",0)),4)
	var basis:=Basis(G.rotate(Vector3.RIGHT,q),Vector3.UP,G.rotate(Vector3.BACK,q))
	var transform:=Transform3D(basis,-Vector3.ZERO.min(G.rotate(size,q)))
	if recipe.get("kind")=="wall":_wall(builder,recipe,transform,surfaces,str(part.material))
	elif recipe.get("kind")=="gable_roof":
		var starts:Dictionary={}
		for key:String in builder.groups:starts[key]=builder.groups[key].i.size()
		if not Roof.add(builder,part,surfaces):return false
		_roof_trim(builder,recipe,transform,surfaces,str(part.material))
		_clockwise(builder,starts)
	elif recipe.get("kind")=="lean_roof":_lean_roof(builder,recipe,transform,surfaces,str(part.material))
	for item:Dictionary in recipe.get("discs",[]):_disc(builder,item,transform)
	for item:Dictionary in recipe.get("boxes",[]):
		_box(builder,G.point(item.center),G.point(item.size),str(item.material),transform,surfaces)
	for item:Dictionary in recipe.get("beams",[]):
		var a:=G.point(item.a);var b:=G.point(item.b);var direction:Vector3=b-a
		if direction.length()<0.001:continue
		var y:=direction.normalized();var x:=Vector3.UP.cross(y).normalized()
		if x.length()<0.5:x=Vector3.RIGHT
		var beam_basis:=Basis(x,y,x.cross(y).normalized())
		var thick:float=item.get("thickness",0.12)
		_box(builder,Vector3.ZERO,Vector3(thick,direction.length(),thick),str(item.material),transform*Transform3D(beam_basis,(a+b)/2),surfaces)
	return true

static func _clockwise(builder:RefCounted,starts:Dictionary)->void:
	# Godot's front faces are clockwise. Double-sided materials still use the
	# facing direction to orient lighting normals. Only fix triangles emitted
	# by this new recipe; preserve old consumers and all positions/UVs/bounds.
	for key:String in builder.groups:
		var group:Dictionary=builder.groups[key]
		for i:int in range(int(starts.get(key,0)),group.i.size(),3):
			var a:Vector3=group.v[group.i[i]];var b:Vector3=group.v[group.i[i+1]];var c:Vector3=group.v[group.i[i+2]]
			if (b-a).cross(c-a).dot(group.n[group.i[i]])>0.000001:
				var index:int=group.i[i];group.i[i]=group.i[i+1];group.i[i+1]=index

static func _lean_roof(builder:RefCounted,r:Dictionary,tr:Transform3D,surfaces:Dictionary,material:String)->void:
	var s:=G.point(r.local_size);var rise:float=r.rise;var t:float=0.13
	var a:=Vector3(0,t,0);var b:=Vector3(s.x,t,0)
	var c:=Vector3(s.x,rise+t,s.z);var d:=Vector3(0,rise+t,s.z)
	var normal:=Vector3(0,s.z,-rise).normalized()
	var meters:float=float(surfaces.get(material,{}).get("tile_meters",2.0))
	builder.quad([a,b,c,d],normal,tr,material,-1,Rect2(0,0,s.x/meters,Vector2(s.z,rise).length()/meters))
	builder.quad([d-Vector3.UP*t,c-Vector3.UP*t,b-Vector3.UP*t,a-Vector3.UP*t],-normal,tr,"b_wood_aged")
	for edge:Array in [[a,b],[b,c],[c,d],[d,a]]:
		builder.quad([edge[0]-Vector3.UP*t,edge[1]-Vector3.UP*t,edge[1],edge[0]],Vector3(edge[1]-edge[0]).cross(Vector3.UP).normalized(),tr,"b_wood_aged")
	# Two overlapping front courses provide a physical lip with a shadow gap.
	for index:int in 2:
		var z:float=0.06+index*0.19;var y:float=rise*z/s.z+t
		_box(builder,Vector3(s.x/2,y,z),Vector3(s.x,0.045,0.14),material,tr,surfaces)

static func _roof_trim(builder:RefCounted,r:Dictionary,tr:Transform3D,surfaces:Dictionary,material:String)->void:
	var s:=G.point(r.local_size);var rise:float=r.rise
	# Segment caps and exposed eave ends belong to this single mesh recipe.
	# Only the two visible edge courses are articulated; the broad field is UV.
	var count:int=maxi(1,ceili(s.x/0.40))
	for i:int in count:
		var left:float=float(i)*s.x/count+0.014;var right:float=float(i+1)*s.x/count-0.014
		# Faceted half-round ridge cap: five strips, no per-cap World or Node.
		for segment:int in 5:
			var aa:float=PI*float(segment)/5;var ab:float=PI*float(segment+1)/5
			var za:float=s.z/2+cos(aa)*0.15;var zb:float=s.z/2+cos(ab)*0.15
			var ya:float=rise+0.08+sin(aa)*0.095;var yb:float=rise+0.08+sin(ab)*0.095
			builder.quad([Vector3(left,ya,za),Vector3(right,ya,za),Vector3(right,yb,zb),Vector3(left,yb,zb)],Vector3(0,sin((aa+ab)/2),cos((aa+ab)/2)),tr,material,-1,Rect2(0,0,(right-left)/2,0.10))
	for side:float in [-1,1]:
		var count_x:int=maxi(1,ceili(s.x/0.22))
		for i:int in count_x:
			var x:float=(float(i)+0.5)*s.x/count_x
			var z:float=0.055 if side<0 else s.z-0.055
			_box(builder,Vector3(x,0.105,z),Vector3(s.x/count_x-0.018,0.07,0.11),material,tr,surfaces)
		# A second course lip is stepped along the true slope, not a huge band.
		var z:float=0.22 if side<0 else s.z-0.22
		_box(builder,Vector3(s.x/2,0.11+rise*0.44/s.z,z),Vector3(s.x,0.04,0.13),material,tr,surfaces)

static func _box(builder:RefCounted,center:Vector3,size:Vector3,material:String,transform:Transform3D,surfaces:Dictionary)->void:
	if size.x<=0 or size.y<=0 or size.z<=0:return
	var meters:float=float(surfaces.get(material,{}).get("tile_meters",2.0))
	builder.box(AABB(center-size/2,size),transform,material,meters)

static func _wall(builder:RefCounted,r:Dictionary,tr:Transform3D,surfaces:Dictionary,material:String)->void:
	# Work in tangent X, height Y and inward Z, then orient to the actual wall.
	var s:=G.point(r.local_size);var normal:=G.point(r.normal)
	var side:bool=absf(normal.x)>0.5
	var w:float=s.z if side else s.x;var h:float=s.y;var t:float=s.x if side else s.z
	var tangent:=Vector3(-normal.z,0,normal.x)
	var orientation:=Basis(tangent,Vector3.UP,-normal)
	var wall_tr:Transform3D=tr*Transform3D(orientation,s/2-Vector3.UP*h/2)
	var openings:Array=r.get("openings",[])
	# Split both axes so upper-storey openings never restore a full wall
	# across a lower window. Openings can share X at different heights.
	var xs:Array=[-w/2,w/2];var ys:Array=[0.0,h]
	for o:Dictionary in openings:
		xs.append(float(o.x)-float(o.width)/2);xs.append(float(o.x)+float(o.width)/2)
		ys.append(float(o.bottom));ys.append(float(o.bottom)+float(o.height))
	xs.sort();ys.sort()
	for ix:int in xs.size()-1:
		for iy:int in ys.size()-1:
			var mid:=Vector2((xs[ix]+xs[ix+1])/2,(ys[iy]+ys[iy+1])/2)
			var cut:bool=false
			for o:Dictionary in openings:
				if absf(mid.x-o.x)<o.width/2 and mid.y>o.bottom and mid.y<o.bottom+o.height:cut=true;break
			if not cut:_box(builder,Vector3(mid.x,mid.y,0),Vector3(xs[ix+1]-xs[ix],ys[iy+1]-ys[iy],t),material,wall_tr,surfaces)
	for o:Dictionary in openings:
		var left:float=o.x-o.width/2;var right:float=o.x+o.width/2
		var top:float=o.bottom+o.height
		# Deep panel, exposed jambs, proud outer casing and sill. The panel closes
		# the service building; authority intentionally keeps a sealed wall proxy.
		_box(builder,Vector3(o.x,o.bottom+o.height/2,t/2-0.025),Vector3(o.width,o.height,0.05),str(o.get("panel","painted_metal")),wall_tr,surfaces)
		for x:float in [left,right]:
			var bottom:float=maxf(0.0,o.bottom-0.06)
			_box(builder,Vector3(x,(bottom+top+0.06)/2,-0.025),Vector3(0.075,top+0.06-bottom,t+0.05),"b_wood_aged",wall_tr,surfaces)
		for y:float in [o.bottom,top]:
			_box(builder,Vector3(o.x,maxf(0.045,y),-0.045),Vector3(o.width+0.16,0.09,t+0.09),"b_wood_aged",wall_tr,surfaces)
		if o.get("type")=="window":
			_box(builder,Vector3(o.x,o.bottom-0.035,-0.10),Vector3(o.width+0.26,0.10,t+0.22),"concrete",wall_tr,surfaces)
			_box(builder,Vector3(o.x,o.bottom+o.height/2,-0.015),Vector3(0.045,o.height,0.055),"b_wood_aged",wall_tr,surfaces)
			_box(builder,Vector3(o.x,o.bottom+o.height*0.53,-0.015),Vector3(o.width,0.045,0.055),"b_wood_aged",wall_tr,surfaces)
			# Narrow folded shutters and metal hinge straps, leaving the recess seen.
			for sign_x:float in [-1,1]:
				_box(builder,Vector3(o.x+sign_x*(o.width/2+0.13),o.bottom+o.height/2,-t/2-0.055),Vector3(0.17,o.height-0.10,0.085),"b_wood_aged",wall_tr,surfaces)
				for y:float in [o.bottom+0.16,top-0.16]:_box(builder,Vector3(o.x+sign_x*(o.width/2+0.13),y,-t/2-0.10),Vector3(0.19,0.045,0.025),"painted_metal",wall_tr,surfaces)
		else:
			_box(builder,Vector3(o.x,0.055,-t/2-0.06),Vector3(o.width+0.24,0.11,0.30),"stone_masonry",wall_tr,surfaces)
			_box(builder,Vector3(o.x+o.width*0.32,0.97,t/2-0.065),Vector3(0.055,0.18,0.055),"painted_metal",wall_tr,surfaces)
			for y:float in [0.36,1.7]:_box(builder,Vector3(left+0.12,y,t/2-0.06),Vector3(0.22,0.045,0.045),"painted_metal",wall_tr,surfaces)

static func _disc(builder:RefCounted,item:Dictionary,tr:Transform3D)->void:
	var center:=G.point(item.center);var radius:float=float(item.radius);var half:float=float(item.thickness)/2
	var steps:int=int(item.get("teeth",24))*2;var material:String=str(item.material);var starts:Dictionary={}
	for key:String in builder.groups:starts[key]=builder.groups[key].i.size()
	for i:int in steps:
		var a:float=float(i)*TAU/steps;var z:float=float(i+1)*TAU/steps
		var r0:float=radius*(1.0 if i%2==0 else .86);var r1:float=radius*(.86 if i%2==0 else 1.0)
		var p:=center+Vector3(0,cos(a)*r0,sin(a)*r0);var q:=center+Vector3(0,cos(z)*r1,sin(z)*r1)
		for side:float in [-1.0,1.0]:
			var offset:=Vector3(side*half,0,0);var normal:=Vector3(side,0,0)
			builder.quad([center+offset,p+offset,q+offset,center+offset],normal,tr,material)
		var n:Vector3=Vector3(0,(p.y+q.y)/2-center.y,(p.z+q.z)/2-center.z).normalized()
		builder.quad([p+Vector3(half,0,0),p-Vector3(half,0,0),q-Vector3(half,0,0),q+Vector3(half,0,0)],n,tr,material)
	_clockwise(builder,starts)
