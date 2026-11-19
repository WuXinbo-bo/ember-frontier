extends RefCounted
## Known content IDs -> disposable aggregate item meshes. Never stock facts.
const Metric=preload("res://scripts/presentation/held_tool_view.gd")
const Quality=preload("res://scripts/environment/environment_quality.gd")
const MAP={
	"r34:raw_water":"water_can","r34:filtered_water":"water_can",
	"r34:potato_seed":"seed_sack","r34:bean_seed":"seed_sack","r34:rice_seed":"seed_sack",
	"r34:broadleaf_seed":"seed_sack","r34:conifer_seed":"seed_sack",
	"r34:potato":"produce","r34:beans":"produce","r34:paddy":"grain_sack","r34:rice":"grain_sack",
	"r34:broadleaf_seedling":"seedling","r34:conifer_seedling":"seedling",
	"r34:compost":"compost_sack","r34:crop_residue":"compost_sack",
	"r34:meal_simple":"meal","r34:meal_hearty":"meal","r34:dry_ration":"ration",
	"r34:structural_timber":"joinery_beam","r34:metal_fitting":"metal_bracket","r34:water_bucket":"empty_bucket"}
const KINDS=["water_can","seed_sack","produce","grain_sack","seedling","compost_sack","meal","ration","joinery_beam","metal_bracket","empty_bucket"]
static var _quality:RefCounted
static var _meshes:Dictionary={}
static var _materials:Dictionary={}

static func representation(item:String)->String:return MAP.get(item,"")

static func _surface(id:String)->Material:
	if _materials.has(id):return _materials[id]
	if _quality==null:_quality=Quality.new()
	if id in ["leaf","earth","grain"]:
		var key:String={"leaf":"v13_broadleaf_canopy_a","earth":"c05_dry_tilled_soil","grain":"c08_straw_fibres"}[id]
		_materials[id]=_quality.material(key);return _materials[id]
	if id in ["wood","metal"]:return Metric.material(id)
	var mat:=StandardMaterial3D.new();mat.roughness=.92
	mat.albedo_color={"cloth":Color("a9946c"),"potato":Color("a38351"),"bean":Color("637c46"),"raw":Color("9a7047"),"filtered":Color("b3aa72"),"meal":Color("bb8b4e"),"rice":Color("d8cba5"),"seed":Color("c2ac66")}.get(id,Color("a9946c"))
	_materials[id]=mat;return mat

static func _part(parts:Array,shape:String,at:Vector3,size:Vector3,surface:String)->void:
	var mesh:Mesh;var transform:=Transform3D(Basis.IDENTITY,at)
	if shape=="sphere":
		var primitive:=SphereMesh.new();primitive.radius=.5;primitive.height=1;primitive.radial_segments=8;primitive.rings=4;mesh=primitive
		transform.basis=Basis.IDENTITY.scaled(size)
	elif shape in ["cylinder","cone"]:
		var primitive:=CylinderMesh.new();primitive.height=1;primitive.top_radius=0 if shape=="cone" else .5;primitive.bottom_radius=.5;primitive.radial_segments=8;mesh=primitive
		transform.basis=Basis.IDENTITY.scaled(size)
	else:mesh=Metric.metric_box(size,1.0)
	parts.append({"mesh":mesh,"transform":transform,"surface":surface})

static func mesh(item:String)->ArrayMesh:
	if _meshes.has(item):return _meshes[item]
	var kind:String=representation(item)
	if kind.is_empty():return null
	var parts:Array=[]
	match kind:
		"water_can":
			_part(parts,"cylinder",Vector3(0,.16,0),Vector3(.23,.32,.23),"metal")
			_part(parts,"cylinder",Vector3(0,.33,0),Vector3(.08,.035,.08),"metal")
			_part(parts,"box",Vector3(0,.21,0),Vector3(.236,.055,.236),"raw" if item=="r34:raw_water" else "filtered")
			for x:float in [-.07,.07]:_part(parts,"box",Vector3(x,.365,0),Vector3(.024,.065,.025),"metal")
			_part(parts,"box",Vector3(0,.4,0),Vector3(.165,.025,.025),"metal")
		"seed_sack","grain_sack","compost_sack":
			_part(parts,"sphere",Vector3(0,.14,0),Vector3(.28,.28,.23),"cloth")
			_part(parts,"cylinder",Vector3(0,.265,0),Vector3(.115,.035,.1),"earth" if kind=="compost_sack" else "seed" if kind=="seed_sack" else "rice" if item=="r34:rice" else "grain")
			if kind=="seed_sack":_part(parts,"box",Vector3(0,.145,-.116),Vector3(.075,.09,.008),"seed")
		"produce":
			_part(parts,"box",Vector3(0,.018,0),Vector3(.32,.035,.26),"wood")
			for x:float in [-.15,.15]:_part(parts,"box",Vector3(x,.065,0),Vector3(.02,.09,.26),"wood")
			for z:float in [-.12,.12]:_part(parts,"box",Vector3(0,.065,z),Vector3(.3,.09,.02),"wood")
			for i:int in 4:
				var p:=Vector3((i%2-.5)*.13,.09,(i/2-.5)*.1)
				_part(parts,"sphere",p,Vector3(.11,.075,.09) if item=="r34:potato" else Vector3(.045,.04,.18),"potato" if item=="r34:potato" else "bean")
		"seedling":
			_part(parts,"cylinder",Vector3(0,.045,0),Vector3(.15,.09,.15),"earth")
			_part(parts,"cylinder",Vector3(0,.16,0),Vector3(.014,.24,.014),"wood")
			for i:int in 3:
				var y:float=.14+i*.055;var w:float=.2-i*.04
				_part(parts,"cone" if item=="r34:conifer_seedling" else "sphere",Vector3(0,y,0),Vector3(w,.1 if item=="r34:conifer_seedling" else .07,w*.8),"leaf")
		"meal":
			_part(parts,"cylinder",Vector3(0,.045,0),Vector3(.23,.09,.23),"metal")
			_part(parts,"cylinder",Vector3(0,.09,0),Vector3(.205,.012,.205),"meal")
			if item=="r34:meal_hearty":
				for x:float in [-.045,.045]:_part(parts,"sphere",Vector3(x,.11,0),Vector3(.055,.035,.065),"potato")
		"ration":
			_part(parts,"box",Vector3(0,.045,0),Vector3(.25,.09,.18),"cloth")
			_part(parts,"box",Vector3(0,.0475,0),Vector3(.045,.095,.185),"seed")
		"joinery_beam":
			# Thick structural member with a real through mortise and end tenon.
			# This is an aggregate stock proxy, not a placeable building member.
			_part(parts,"box",Vector3(-.11,.07,0),Vector3(.38,.14,.16),"wood")
			for z:float in [-.06,.06]:_part(parts,"box",Vector3(.15,.07,z),Vector3(.14,.14,.04),"wood")
			_part(parts,"box",Vector3(.26,.07,0),Vector3(.08,.14,.16),"wood")
			_part(parts,"box",Vector3(-.34,.07,0),Vector3(.08,.07,.08),"wood")
		"metal_bracket":
			# Standard L bracket: holes are absent triangles, not painted dots.
			var xs:Array[float]=[-.09,-.06,-.03,.03,.06,.09]
			var zs:Array[float]=[-.09,-.055,-.025,.025,.055,.09]
			var ys:Array[float]=[.012,.055,.085,.12,.15,.2]
			for x:int in 5:
				for j:int in 5:
					if x in [1,3] and j in [1,3]:continue
					_part(parts,"box",Vector3((xs[x]+xs[x+1])*.5,.012,(zs[j]+zs[j+1])*.5),Vector3(xs[x+1]-xs[x],.018,zs[j+1]-zs[j]),"metal")
					_part(parts,"box",Vector3((xs[x]+xs[x+1])*.5,(ys[j]+ys[j+1])*.5,-.082),Vector3(xs[x+1]-xs[x],ys[j+1]-ys[j],.018),"metal")
		"empty_bucket":
			# Reusable count tool: visible floor and inner wall, no water surface.
			_part(parts,"cylinder",Vector3(0,.006,0),Vector3(.224,.012,.224),"metal")
			for i:int in 12:
				var angle:float=TAU*float(i)/12.0
				_part(parts,"box",Vector3(sin(angle)*.115,.13,cos(angle)*.115),Vector3(.062,.25,.012),"metal")
				parts[-1].transform.basis=Basis(Vector3.UP,angle)
			for x:float in [-.115,.115]:_part(parts,"box",Vector3(x,.335,0),Vector3(.014,.18,.014),"metal")
			_part(parts,"box",Vector3(0,.425,0),Vector3(.244,.014,.014),"wood")
	# Stock slots are centred on XZ and grounded on Y. Preserve the owner's
	# exact bay, rather than enlarging it for asymmetric tenons/flange ends.
	var recenter:Vector3=Vector3(.04,0,0) if kind=="joinery_beam" else Vector3(0,-.003,.0005) if kind=="metal_bracket" else Vector3.ZERO
	var groups:Dictionary={}
	for part:Dictionary in parts:
		part.transform.origin+=recenter
		var source:Array=part.mesh.get_mesh_arrays() if part.mesh is PrimitiveMesh else part.mesh.surface_get_arrays(0)
		if not groups.has(part.surface):groups[part.surface]={"v":PackedVector3Array(),"n":PackedVector3Array(),"uv":PackedVector2Array(),"i":PackedInt32Array()}
		var group:Dictionary=groups[part.surface];var offset:int=group.v.size()
		for v:Vector3 in source[Mesh.ARRAY_VERTEX]:group.v.append(part.transform*v)
		var normal_basis:Basis=part.transform.basis.inverse().transposed()
		for n:Vector3 in source[Mesh.ARRAY_NORMAL]:group.n.append((normal_basis*n).normalized())
		group.uv.append_array(source[Mesh.ARRAY_TEX_UV])
		for i:int in source[Mesh.ARRAY_INDEX]:group.i.append(i+offset)
	var result:=ArrayMesh.new()
	for surface:String in groups:
		var group:Dictionary=groups[surface];var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=group.v;arrays[Mesh.ARRAY_NORMAL]=group.n;arrays[Mesh.ARRAY_TEX_UV]=group.uv;arrays[Mesh.ARRAY_INDEX]=group.i
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(result.get_surface_count()-1,_surface(surface))
	_meshes[item]=result;return result

static func create(item:String,extent:Vector3)->MeshInstance3D:
	var source:ArrayMesh=mesh(item)
	if source==null:return null
	var size:Vector3=source.get_aabb().size
	var fit:float=minf(extent.x/maxf(size.x,.001),minf(extent.y/maxf(size.y,.001),extent.z/maxf(size.z,.001)))
	var node:=MeshInstance3D.new();node.mesh=source;node.scale=Vector3.ONE*fit
	node.set_meta("item_id",item);node.set_meta("representation",representation(item));node.set_meta("quantity_mode","aggregate proxy, not item count or water volume")
	return node
