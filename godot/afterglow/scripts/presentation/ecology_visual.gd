extends Node3D
## Read-only ecology DTO -> real near-field plants/soil. No growth clock/yield.
const Batch=preload("res://scripts/presentation/regional_visual_batch.gd")
const Planning=preload("res://scripts/presentation/planning_visual.gd")
const Quality=preload("res://scripts/environment/environment_quality.gd")
const Models=preload("res://scripts/environment/ecology_models.gd")
const Metric=preload("res://scripts/presentation/held_tool_view.gd")
const Water=preload("res://scripts/presentation/factory_water_view.gd")
const REGIONAL_ASSETS="res://data/presentation/regional-ecology-v1/manifest.json"
const STAGES=["tilled","seedling","growing","mature","harvested"]
const CROPS=["potato","bean","rice"]
const MAX_VISUALS=8192
var runtime:RefCounted
var _world:int=0
var _delay:float=0
var _batch:Node3D
var _quality:RefCounted
var _models:RefCounted
var _meshes:Dictionary={}
var _issues:Array=[]
var _displayed:Array=[]
var _available:bool=false
var _signature:String=""
var _query_basis:String=""

func configure(authority:RefCounted)->void:
	if runtime!=authority or _world!=Planning.world_instance(authority):clear()
	runtime=authority;_world=Planning.world_instance(authority);_delay=0;sync()

func clear()->void:
	if is_instance_valid(_batch):_batch.clear()
	_displayed.clear();_issues.clear();_available=false
	_signature="";_query_basis=""

func _process(delta:float)->void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("presentation/ecology_visual.gd",measured)

func _profiled_process(delta:float)->void:
	_delay-=delta
	if _delay>0:return
	_delay=0.1;sync()

func sync(snapshot:Dictionary={})->void:
	var current:int=Planning.world_instance(runtime)
	if current!=_world:clear();_world=current
	var dto:Variant=snapshot
	if snapshot.is_empty() and runtime!=null and runtime.has_method("domain_service"):
		var service:Variant=runtime.call("domain_service","ecology")
		if service!=null and service.has_method("presentation_projection"):
			if service.has_method("presentation_basis"):
				var basis:Variant=service.call("presentation_basis","player")
				if not basis is Dictionary or basis.get("available")!=true:clear();return
				var key:String=var_to_str([service.get_instance_id(),_world,basis])
				if key==_query_basis:return
				_query_basis=key
			dto=service.call("presentation_projection","player")
	else:_query_basis=""
	apply_snapshot(dto if dto is Dictionary else {})

func _prepare()->void:
	if not is_instance_valid(_batch):_batch=Batch.new();_batch.name="EcologyBatches";add_child(_batch)
	if _quality==null:_quality=Quality.new()
	if not _quality.get_meta("regional_assets_loaded",false):
		_quality.set_meta("regional_assets_loaded",true)
		if FileAccess.file_exists(REGIONAL_ASSETS):
			var doc:Variant=JSON.parse_string(FileAccess.get_file_as_string(REGIONAL_ASSETS))
			if doc is Dictionary and doc.get("assets") is Array:
				for row:Dictionary in doc.assets:_quality.rows[row.id]=row.duplicate(true)
	if _models==null:_models=Models.new()

func _valid(row:Dictionary)->bool:
	if not row.get("id") is String or str(row.id).is_empty() or not row.get("region_id") is String:return false
	if not Batch.point(row.get("location")):return false
	if row.get("location",{}).get("regionId")!=row.region_id:return false
	if not Batch.number(row.get("revision")) or float(row.revision)!=floor(float(row.revision)) or int(row.revision)<0:return false
	if row.get("kind")=="water_source":
		for key:String in ["capacity","remaining","recharge_seconds"]:
			if not Batch.number(row.get(key)):return false
		return row.get("stage") in ["available","recharging"] and float(row.capacity)>0 and float(row.remaining)>=0 and float(row.remaining)<=float(row.capacity) and float(row.recharge_seconds)>0 and row.get("visual_owner")=="ecology" and ((row.stage=="available")==bool(float(row.remaining)>0))
	if not Batch.cell(row.get("cell")):return false
	if row.get("stage") not in STAGES or row.get("kind") not in ["tree","crop","bed"]:return false
	for key:String in ["moisture","fertility"]:
		if not Batch.number(row.get(key)) or float(row[key])!=floor(float(row[key])) or int(row[key])<0 or int(row[key])>3:return false
	if row.kind=="crop" and row.get("crop_id") not in CROPS:return false
	if row.kind=="tree" and row.get("tree_id") not in ["broadleaf","conifer"]:return false
	return true

func apply_snapshot(snapshot:Dictionary)->void:
	_prepare()
	if snapshot.get("available")!=true or not snapshot.get("visuals") is Array:
		clear();return
	if snapshot.visuals.size()>MAX_VISUALS:
		clear()
		_issues.append({"code":"ECOLOGY_VISUAL_CAPACITY"});_batch.clear();return
	var rows:Array=[];var seen:Dictionary={}
	for value:Variant in snapshot.visuals:
		if not value is Dictionary or not _valid(value):
			clear()
			_issues.append({"code":"INVALID_ECOLOGY_VISUAL"});_batch.clear();return
		if seen.has(value.id):clear();_issues.append({"code":"DUPLICATE_ECOLOGY_VISUAL","id":value.id});return
		seen[value.id]=true
		# Explicit disclosure gates, not proximity guesses or a second World read.
		if value.get("known")!=true or value.get("resident")!=true or value.get("visible")!=true:continue
		rows.append(value)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return str(a.id)<str(b.id))
	var signature:String=var_to_str(rows)
	if _available and signature==_signature:return
	_issues.clear();_displayed.clear();_available=false
	_signature=signature
	var groups:Dictionary={};var beds:Dictionary={}
	for row:Dictionary in rows:
		var p:=Vector3(float(row.location.x),float(row.location.y),float(row.location.z))
		if row.kind in ["bed","crop"]:
			var bed_key:String=str([row.region_id,row.cell.x,row.cell.y,row.cell.z])
			if not beds.has(bed_key) or row.kind=="bed":beds[bed_key]=row
		if row.kind=="crop":_crop(groups,row,p)
		elif row.kind=="tree":_tree(groups,row,p)
		elif row.kind=="water_source":_water_source(groups,row,p)
		_displayed.append({"id":row.id,"kind":row.kind,"stage":row.stage,"revision":row.revision,"moisture":row.get("moisture"),"remaining":row.get("remaining"),"capacity":row.get("capacity")})
	for row:Dictionary in beds.values():_bed(groups,row)
	_batch.apply(groups);_available=true

func _append(groups:Dictionary,row:Dictionary,key:String,mesh:Mesh,at:Vector3,scale_value:Vector3=Vector3.ONE,yaw:float=0)->void:
	var origin:=Vector3(floor(at.x/8)*8,0,floor(at.z/8)*8)
	Batch.append(groups,Batch.chunk_key(row.region_id,at),origin,key,mesh,Transform3D(Basis(Vector3.UP,yaw).scaled(scale_value),at),[row.id,row.stage,row.get("moisture"),row.get("fertility"),key,at,scale_value,yaw])

func _primitive(key:String,shape:String,material_id:String)->Mesh:
	if _meshes.has(key):return _meshes[key]
	var mesh:PrimitiveMesh
	if shape=="sphere":
		var sphere:=SphereMesh.new();sphere.radius=.5;sphere.height=1;sphere.radial_segments=8;sphere.rings=4;mesh=sphere
	elif shape=="stem":
		var cylinder:=CylinderMesh.new();cylinder.height=1;cylinder.top_radius=.4;cylinder.bottom_radius=.5;cylinder.radial_segments=6;mesh=cylinder
	else:
		var box:=BoxMesh.new();box.size=Vector3.ONE;mesh=box
	mesh.material=_quality.material(material_id);_meshes[key]=mesh;return mesh

func _box(size:Vector3,surface:String)->Mesh:
	var key:String=surface+str(size)
	if _meshes.has(key):return _meshes[key]
	var mesh:ArrayMesh=Metric.metric_box(size,1.0)
	mesh.surface_set_material(0,_quality.material(surface));_meshes[key]=mesh;return mesh

func _bed(groups:Dictionary,row:Dictionary)->void:
	var p:=Vector3((float(row.cell.x)+.5)*.5,float(row.cell.y)*.5,float(row.cell.z)*.5+.25)
	var surface:String="c05_dry_tilled_soil" if int(row.moisture)==0 else "c06_damp_tilled_soil"
	# A shallow top covers exactly the authoritative half-metre soil cell.
	_append(groups,row,surface,_box(Vector3(.5,.018,.5),surface),p+Vector3(0,.009,0))
	for offset:float in [-.16,0,.16]:
		_append(groups,row,surface+":ridge",_box(Vector3(.085,.032,.46),surface),p+Vector3(offset,.025,0))
	# Moisture is dampness only; no imaginary water volume, irrigation or yield.

func _crop(groups:Dictionary,row:Dictionary,p:Vector3)->void:
	if row.stage=="tilled":return
	var crop:String=row.crop_id;var stage:String=row.stage
	var exact_id:String=crop+"_"+stage
	if _quality.rows.has(exact_id):
		# Use the source's full fixed canvas. Visible pixels alone get larger
		# across stages; never normalize a small seedling to the mature crown.
		var width:float=_quality.rows[exact_id].visible_size_m[0]
		for part:Dictionary in _quality.cutout_parts(exact_id,width):
			var origin:=Vector3(floor(p.x/8)*8,0,floor(p.z/8)*8)
			var t:Transform3D=part.transform;t.origin+=p
			Batch.append(groups,Batch.chunk_key(row.region_id,p),origin,exact_id,part.mesh,t,[row.id,crop,stage,p,exact_id])
		return
	if crop=="rice":
		var material_id:String={"seedling":"c01_rice_vegetative","growing":"c01_rice_vegetative","mature":"c02_rice_ripe","harvested":"c03_rice_stubble"}[stage]
		var width:float={"seedling":.18,"growing":.32,"mature":.38,"harvested":.28}[stage]
		for part:Dictionary in _quality.cutout_parts(material_id,width):
			var origin:=Vector3(floor(p.x/8)*8,0,floor(p.z/8)*8)
			var t:Transform3D=part.transform;t.origin+=p
			Batch.append(groups,Batch.chunk_key(row.region_id,p),origin,material_id+":"+str(width),part.mesh,t,[row.id,crop,stage,p,width])
		if stage=="seedling":_issues.append({"code":"RICE_SEEDLING_IMAGE_PENDING","id":row.id,"fallback":"existing rice vegetative reduced; not image/VA accepted"})
		return
	# Named native foliage geometry until ART's exact potato/bean cutouts arrive.
	# Potato stays low/bushy, bean has a taller stem and trifoliate leaf nodes.
	if stage=="harvested":
		_append(groups,row,"residue",_primitive("residue","stem","c08_straw_fibres"),p+Vector3(0,.035,0),Vector3(.018,.07,.018));return
	var level:int=["seedling","growing","mature"].find(stage)
	var height:float=([.16,.3,.45] if crop=="potato" else [.2,.52,.8])[level]
	var width:float=([.2,.4,.5] if crop=="potato" else [.18,.38,.5])[level]
	var leaf_mesh:Mesh=_primitive("crop-leaf","sphere","v13_broadleaf_canopy_a")
	var stem_mesh:Mesh=_primitive("crop-stem","stem","v13_broadleaf_canopy_a")
	_append(groups,row,"crop-stem",stem_mesh,p+Vector3(0,height*.45,0),Vector3(.018,height*.9,.018))
	for tier:int in level+2:
		var y:float=height*(.32+.24*float(tier))
		for leaf:int in (3 if crop=="bean" else 4):
			var angle:float=TAU*float(leaf)/(3.0 if crop=="bean" else 4.0)+tier*.65
			var radius:float=width*.26
			var at:Vector3=p+Vector3(cos(angle)*radius,y,sin(angle)*radius)
			_append(groups,row,"crop-leaf",leaf_mesh,at,Vector3(width*.44,.025,width*.24),angle)
	_issues.append({"code":"CROP_NATIVE_GEOMETRY","id":row.id,"species":crop,"stage":stage,"scope":"real owner stage; exact species image pending; normal-camera VA pending"})

func _water_mesh(key:String)->Mesh:
	if _meshes.has(key):return _meshes[key]
	var mesh:Mesh
	if key=="well_water":
		var disk:=CylinderMesh.new();disk.height=.012;disk.top_radius=.29;disk.bottom_radius=.29;disk.radial_segments=12
		disk.material=Water.materials().get("water");mesh=disk
	else:
		var size:Vector3={"well_stone":Vector3(.23,.16,.13),"well_post":Vector3(.055,.96,.055),"well_beam":Vector3(.76,.065,.07),"well_axle":Vector3(.5,.045,.045)}[key]
		var box:ArrayMesh=Metric.metric_box(size,1.0)
		box.surface_set_material(0,Water._surface("res://data/buildings/textures/p01_well_stone.png",.94,0) if key=="well_stone" else Metric.material("wood"))
		mesh=box
	_meshes[key]=mesh;return mesh

func _water_source(groups:Dictionary,row:Dictionary,p:Vector3)->void:
	# Fits C's actual 0.9 x 1.05 x 0.9m source body. A public count is NOT m3.
	for tier:int in 4:
		for stone:int in 10:
			var angle:float=(float(stone)+(.5 if tier%2 else 0))*TAU/10.0
			_append(groups,row,"well_stone",_water_mesh("well_stone"),p+Vector3(sin(angle)*.345,.08+tier*.16,cos(angle)*.345),Vector3.ONE,angle)
	for x:float in [-.34,.34]:_append(groups,row,"well_post",_water_mesh("well_post"),p+Vector3(x,.48,0))
	_append(groups,row,"well_beam",_water_mesh("well_beam"),p+Vector3(0,1.005,0))
	_append(groups,row,"well_axle",_water_mesh("well_axle"),p+Vector3(0,.78,0))
	# The visible source surface says only 'water available'. Its fixed level
	# never claims a litre conversion or fractional volume from count units.
	if float(row.remaining)>0:_append(groups,row,"well_water",_water_mesh("well_water"),p+Vector3(0,.12,0))

func _tree(groups:Dictionary,row:Dictionary,p:Vector3)->void:
	var model:String="conifer_tree" if row.tree_id=="conifer" else "broadleaf_tree"
	if row.stage=="tilled":return
	if row.stage=="harvested":
		model="tree_stump"
	# Explicit environment ownership prevents drawing the mature resource twice.
	if row.get("visual_owner")=="environment":return
	if row.get("visual_owner")!="ecology":
		_issues.append({"code":"TREE_VISUAL_OWNER_REQUIRED","id":row.id});return
	var height:float={"seedling":.45,"growing":1.6,"mature":3.6,"harvested":.25}[row.stage]
	var parts:Array=_models.quality_parts(model,height,0)
	var bounds:AABB=_models.bounds(model)
	var scale_value:float=height/maxf(bounds.size.y,.001)
	var placement:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_value),p)*Transform3D(Basis.IDENTITY,Vector3(0,-bounds.position.y,0))
	for i:int in parts.size():
		var part:Dictionary=parts[i];var t:Transform3D=placement*part.transform
		var origin:=Vector3(floor(p.x/8)*8,0,floor(p.z/8)*8)
		Batch.append(groups,Batch.chunk_key(row.region_id,p),origin,model+":"+str(height)+":"+str(i),part.mesh,t,[row.id,row.stage,model,height,p])

func statistics()->Dictionary:
	var result:Dictionary=_batch.statistics() if is_instance_valid(_batch) else {}
	result.merge({"available":_available,"visuals":_displayed.duplicate(true),"issues":_issues.duplicate(true),"authority_write":false,"growth_clock":false})
	return result
