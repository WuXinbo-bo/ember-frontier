extends Node3D
## Disposable quantity proxy. No collision, stock ownership, pickup or settlement.
## Each row describes ONE item and ONE unit; reservations remain visible stock.
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const Materials=preload("res://scripts/presentation/factory_materials.gd")
const Regional=preload("res://scripts/presentation/regional_item_visual.gd")
const BAND_COUNTS=[0,1,3,6,9]
const KINDS=["log","plank","scrap","wood_fuel","crate","liquid"]
static var _textures:Dictionary={}
static var _meshes:Dictionary={}
var _shape_key:=""
var _parts:Array[Node3D]=[]
var _amount:=0.0
var _capacity:=0.0
var _band:=-1
var _issue:=""
var _visual_available:=true
var _visual_reason:=""

static func band(amount:float,capacity:float)->int:
	if not is_finite(amount) or not is_finite(capacity) or amount<0 or capacity<=0:return -1
	if amount==0:return 0
	var ratio:float=amount/capacity
	return 1 if ratio<=0.25 else 2 if ratio<=0.65 else 3 if ratio<1.0 else 4

func update(row:Dictionary)->bool:
	var actual:Variant=row.get("actual");var capacity:Variant=row.get("capacity")
	var kind:String=str(row.get("representation",""));var extent:Variant=row.get("extent")
	if not _number(actual) or not _number(capacity) or band(float(actual),float(capacity))<0:
		return _reject("INVALID_QUANTITY")
	if str(row.get("item_id","")).is_empty() or str(row.get("unit","")).is_empty():return _reject("MISSING_ITEM_OR_UNIT")
	var regional:String=Regional.representation(str(row.item_id))
	if kind not in KINDS and kind not in Regional.KINDS:return _reject("UNSUPPORTED_REPRESENTATION")
	if kind in Regional.KINDS and kind!=regional:return _reject("ITEM_REPRESENTATION_MISMATCH")
	if kind=="crate" and not regional.is_empty():kind=regional
	if not extent is Vector3 or not extent.is_finite() or extent.x<=0 or extent.y<=0 or extent.z<=0:return _reject("INVALID_EXTENT")
	if kind=="liquid" and str(row.unit) not in ["l","m3"]:return _reject("LIQUID_UNIT_REQUIRED")
	var key:String=JSON.stringify([row.item_id,row.unit,kind,extent.x,extent.y,extent.z])
	if key!=_shape_key:
		_clear();_shape_key=key
		_make(kind,extent,str(row.item_id))
	_amount=float(actual);_capacity=float(capacity);_band=band(_amount,_capacity)
	for i:int in _parts.size():
		_parts[i].visible=i<BAND_COUNTS[_band]
		if kind=="liquid":
			var fill:float=minf(_amount/_capacity,1.0)
			_parts[i].scale.y=fill
			_parts[i].position.y=extent.y*fill*0.5
	# An unavailable placement hides only the disposable mesh. Quantities,
	# bands and geometry identity still follow the same valid owner row.
	_visual_available=row.get("visual_available",true)
	_visual_reason=str(row.get("visual_reason",""))
	visible=_visual_available;_issue="CAPACITY_EXCEEDED" if _amount>_capacity else ""
	set_meta("stock_ref",row.get("stock_ref",""));set_meta("item_id",row.item_id);set_meta("unit",row.unit)
	set_meta("actual",_amount);set_meta("capacity",_capacity);set_meta("band",_band);set_meta("representation",kind)
	set_meta("reserved",row.get("reserved",0));set_meta("visual_available",_visual_available);set_meta("visual_reason",_visual_reason)
	return true

static func _number(value:Variant)->bool:
	return (value is float or value is int) and is_finite(float(value))

func _reject(code:String)->bool:
	_issue=code;visible=false
	return false

func _clear()->void:
	for part:Node3D in _parts:
		remove_child(part);part.queue_free()
	_parts.clear()

static func _surface(key:String)->Material:
	if key=="end":return Materials.material("end")
	if key in ["wood","metal"]:return Surfaces.material(key)
	if _textures.has(key):return _textures[key]
	var material:=StandardMaterial3D.new();material.roughness=0.92
	if key=="water":
		material.albedo_color=Color("617f80");material.roughness=0.28
	else:
		var path:String="res://data/world/ecology/quality-v1/"+("v12_cut_endgrain.png" if key=="end" else "v09_broadleaf_bark.png")
		var source:Texture2D=load(path)
		if source!=null:
			var image:Image=source.get_image()
			if image!=null:
				if image.is_compressed():image.decompress()
				if not image.has_mipmaps():image.generate_mipmaps()
				material.albedo_texture=ImageTexture.create_from_image(image)
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.texture_repeat=key!="end"
		material.set_meta("source_resource",path)
	_textures[key]=material
	return material

static func _log_mesh(length:float,radius:float)->ArrayMesh:
	var key:String=str([length,radius])
	if _meshes.has(key):return _meshes[key]
	var primitive:=CylinderMesh.new();primitive.height=length;primitive.top_radius=radius;primitive.bottom_radius=radius;primitive.radial_segments=8
	var source:Array=primitive.get_mesh_arrays();var vertices:PackedVector3Array=source[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=source[Mesh.ARRAY_NORMAL];var indices:PackedInt32Array=source[Mesh.ARRAY_INDEX]
	var primitive_uv:PackedVector2Array=source[Mesh.ARRAY_TEX_UV]
	var mesh:=ArrayMesh.new()
	for cap:bool in [false,true]:
		var selected:=PackedInt32Array();var uv:=PackedVector2Array();uv.resize(vertices.size())
		for i:int in vertices.size():
			var p:Vector3=vertices[i]
			# AS02 bark stays 1x1m; selected production endgrain stays 0.4m.
			# Preserve the primitive's duplicated seam vertices; atan2 would fold
			# the last face across the texture instead of crossing the repeat seam.
			uv[i]=Vector2(p.x,p.z)/0.4+Vector2.ONE*0.5 if cap else Vector2(primitive_uv[i].x*TAU*radius,p.y)
		for i:int in range(0,indices.size(),3):
			if (absf(normals[indices[i]].y)>0.5)==cap:selected.append_array(indices.slice(i,i+3))
		var arrays:Array=source.duplicate();arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=selected
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,_surface("end" if cap else "bark"))
	_meshes[key]=mesh
	return mesh

func _make(kind:String,extent:Vector3,item:String="")->void:
	if kind in Regional.KINDS:
		var slot_size:=Vector3(extent.x/3,extent.y/3,extent.z*.94)
		for i:int in 9:
			var part:MeshInstance3D=Regional.create(item,slot_size)
			if part==null:continue
			part.position=Vector3((i%3-1)*extent.x/3.0,float(i/3)*slot_size.y,0)
			add_child(part);_parts.append(part)
		return
	if kind=="liquid":
		var part:MeshInstance3D=Surfaces.box(self,Vector3.ZERO,extent,"metal")
		part.material_override=_surface("water");_parts.append(part);return
	for i:int in 9:
		var column:int=i%3;var layer:int=i/3
		var slot:=Vector3((column-1)*extent.x/3.0,0,0)
		var part:Node3D
		if kind in ["log","wood_fuel"]:
			var log_mesh:=MeshInstance3D.new()
			var radius:float=minf(extent.y/6.4,extent.x/6.4)
			# The owner anchor is the actual supporting floor/rack top. Stack
			# real diameters, rather than spacing layers across empty bay height.
			slot.y=(2*layer+1)*radius
			log_mesh.mesh=_log_mesh(extent.z*0.92,radius);log_mesh.rotation.x=PI/2
			log_mesh.position=slot;add_child(log_mesh);part=log_mesh
		else:
			var size:=Vector3(extent.x*0.28,extent.y*0.28,extent.z*0.9)
			if kind=="plank":size=Vector3(extent.x*0.29,extent.y*0.10,extent.z*0.96)
			elif kind=="scrap":size=Vector3(extent.x*0.27,extent.y*0.12,extent.z*0.65)
			slot.y=(layer+0.5)*size.y
			var yaw:float=(0.12 if i%2==0 else -0.12) if kind=="scrap" else 0.0
			if kind=="scrap":
				# Alternating irregular pieces retain their real size and yaw.
				# Fit outer column centres to the rotated mesh, not its unturned
				# width; the owner's exact service clearance is not spare space.
				var half_x:float=(absf(cos(yaw))*size.x+absf(sin(yaw))*size.z)*0.5
				var outer_center:float=maxf(0.0,extent.x*0.5-half_x)
				slot.x=clampf(slot.x,-outer_center,outer_center)
			part=Materials.timber(self,slot,size,2) if kind=="plank" else Surfaces.box(self,slot,size,"metal" if kind=="scrap" else "wood")
			if kind=="scrap":part.rotation.y=yaw
		_parts.append(part)

func statistics()->Dictionary:
	return {"actual":_amount,"capacity":_capacity,"reserved":get_meta("reserved",0),"band":_band,"representation":get_meta("representation",""),"visual_available":_visual_available,"visual_reason":_visual_reason,"issue":_issue,"proxy_parts":_parts.size(),"visible_parts":_parts.filter(func(p:Node3D)->bool:return p.visible and visible).size(),"collision":false}
