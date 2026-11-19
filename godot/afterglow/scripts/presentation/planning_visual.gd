extends Node3D
## A's exact selection/preview cells only. A/UI owns hits, plans and permission.
const Batch=preload("res://scripts/presentation/regional_visual_batch.gd")
const SCHEMA="afterglow-work-zones-v1"
const LIMIT=4096
var runtime:RefCounted
var _world:int=0
var _provider:WeakRef
var _selected:String=""
var _preview:Dictionary={}
var _draft:Dictionary={}
var _snapshot:Dictionary={}
var _batch:Node3D
var _meshes:Dictionary={}
var _delay:float=0.0
var _issues:Array=[]
var _counts:Dictionary={}
var _signature:String=""
var _query_basis:String=""

static func world_instance(authority:RefCounted)->int:
	if authority==null:return 0
	for property:Dictionary in authority.get_property_list():
		if property.name=="world":
			var value:Variant=authority.get("world")
			return value.get_instance_id() if value is Object and is_instance_valid(value) else 0
	return 0

func configure(authority:RefCounted)->void:
	if runtime!=authority or _world!=world_instance(authority):clear()
	runtime=authority;_world=world_instance(authority);_delay=0.0
	sync()

func configure_planning(provider:Node)->void:
	_provider=weakref(provider) if is_instance_valid(provider) else null
	_sync_provider()

func _process(delta:float)->void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("presentation/planning_visual.gd",measured)

func _profiled_process(delta:float)->void:
	_delay-=delta
	if _delay>0:return
	_delay=0.1;sync()

func _sync_provider()->void:
	var provider:Variant=_provider.get_ref() if _provider!=null else null
	if not is_instance_valid(provider) or not provider.has_method("planning_view"):
		if _provider!=null:clear_preview()
		return
	var dto:Variant=provider.call("planning_view")
	if not dto is Dictionary or dto.get("active")!=true:clear_preview();return
	if dto.get("zone_id") is String:_selected=dto.zone_id
	_draft={"bounds":dto.get("bounds",{}),"y":dto.get("draft_y",0.0)} if dto.get("bounds") is Dictionary and not dto.bounds.is_empty() else {}
	var preview:Variant=dto.get("preview")
	set_preview(preview if preview is Dictionary else {})

func sync(snapshot:Dictionary={})->void:
	var current:int=world_instance(runtime)
	if current!=_world:clear();_world=current
	_sync_provider()
	var dto:Variant=snapshot
	if snapshot.is_empty() and runtime!=null and runtime.has_method("zone_projection"):
		if runtime.has_method("zone_view_basis"):
			var basis:Variant=runtime.call("zone_view_basis","player")
			if not basis is Dictionary or not basis.get("available") is bool:
				_snapshot={};_query_basis="";_redraw();return
			var key:String=var_to_str([basis.get("zones_revision"),basis.get("zones_generation"),_selected,basis.available,basis.get("world_generation"),basis.get("runtime_generation")])
			if key==_query_basis:_redraw();return
			_query_basis=key
		dto=runtime.call("zone_projection","player",_selected)
	else:_query_basis=""
	if not dto is Dictionary:dto={}
	_snapshot=dto.duplicate(true)
	_redraw()

func set_preview(preview:Dictionary)->void:
	_preview=preview.duplicate(true);_redraw()

func clear_preview()->void:
	if _preview.is_empty() and _draft.is_empty():return
	_preview.clear();_draft.clear();_redraw()

func set_selected(zone_id:String)->void:
	if _selected==zone_id:return
	_selected=zone_id;sync()

func clear()->void:
	_preview.clear();_draft.clear();_snapshot.clear();_counts.clear();_issues.clear();_selected=""
	_signature="";_query_basis=""
	if is_instance_valid(_batch):_batch.clear()

func _mesh(kind:String)->Mesh:
	if _meshes.has(kind):return _meshes[kind]
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color={"selected":Color("e5c988"),"valid":Color("83bca4"),"excluded":Color("d48478")}[kind]
	# Keep depth testing: a plan never shines through a building or hill.
	var box:=BoxMesh.new();box.size=Vector3.ONE;box.material=material
	_meshes[kind]=box;return box

func _segment(groups:Dictionary,region:String,a:Vector3,b:Vector3,kind:String)->void:
	var delta:Vector3=b-a;var length:float=delta.length()
	if length<=0:return
	var middle:Vector3=(a+b)*0.5
	var basis:Basis=Basis(Vector3.UP,-atan2(delta.z,delta.x)).scaled(Vector3(length,0.016,0.018))
	var origin:=Vector3(floor(middle.x/8)*8,0,floor(middle.z/8)*8)
	Batch.append(groups,Batch.chunk_key(region,middle),origin,kind,_mesh(kind),Transform3D(basis,middle),[a,b,kind],GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

func _cells(groups:Dictionary,cells:Array,region:String,kind:String)->void:
	if cells.size()>LIMIT:_issues.append("ZONE_VISUAL_CAPACITY");return
	var occupied:Dictionary={}
	for value:Variant in cells:
		if not Batch.cell(value):_issues.append("INVALID_CELL");return
		var key:=Vector3i(int(value.x),int(value.y),int(value.z))
		occupied[key]=true
	_counts[kind]=occupied.size()
	var ordered:Array=occupied.keys();ordered.sort()
	for key:Vector3i in ordered:
		# C _ground returns the standing cell above support (not y-1 solid).
		var p:=Vector3(key.x*0.5,key.y*0.5+0.025,key.z*0.5)
		if kind=="excluded":
			_segment(groups,region,p+Vector3(.08,0,.08),p+Vector3(.42,0,.42),kind)
			_segment(groups,region,p+Vector3(.42,0,.08),p+Vector3(.08,0,.42),kind);continue
		var directions:Array=[Vector3i(0,0,-1),Vector3i(1,0,0),Vector3i(0,0,1),Vector3i(-1,0,0)]
		var corners:Array=[Vector3.ZERO,Vector3(.5,0,0),Vector3(.5,0,.5),Vector3(0,0,.5)]
		for i:int in 4:
			if not occupied.has(key+directions[i]):_segment(groups,region,p+corners[i],p+corners[(i+1)%4],kind)

func _redraw()->void:
	if not is_instance_valid(_batch):_batch=Batch.new();_batch.name="PlanningBatches";add_child(_batch)
	var signature:String=var_to_str([_selected,_snapshot.get("available"),_snapshot.get("schema"),_snapshot.get("selection"),_preview,_draft])
	if signature==_signature:return
	_signature=signature
	_issues.clear();_counts.clear()
	var groups:Dictionary={}
	if not _draft.is_empty():
		var b:Dictionary=_draft.bounds;var y:float=float(_draft.y)+.06
		var points:Array=[Vector3(b.x0*.5,y,b.z0*.5),Vector3(b.x1*.5,y,b.z0*.5),Vector3(b.x1*.5,y,b.z1*.5),Vector3(b.x0*.5,y,b.z1*.5)]
		for i:int in 4:_segment(groups,"draft",points[i],points[(i+1)%4],"selected")
	if _snapshot.get("available")==true and _snapshot.get("schema")==SCHEMA:
		var selection:Variant=_snapshot.get("selection")
		if selection is Dictionary and selection.get("id")==_selected and selection.get("enabled")==true and selection.get("cells") is Array and selection.get("region_id") is String:
			_cells(groups,selection.cells,selection.region_id,"selected")
	# Error responses and UI bounds never imply legal ground.
	if _preview.get("ok")==true and _preview.get("schema")==SCHEMA and _preview.get("cells") is Array:
		var region:String=str(_preview.get("region_id","preview"))
		_cells(groups,_preview.cells,region,"valid")
		var excluded:Array=[]
		for row:Variant in _preview.get("excluded",[]):
			if row is Dictionary and Batch.cell(row.get("cell")):excluded.append(row.cell)
		_cells(groups,excluded,region,"excluded")
	_batch.apply(groups)

func statistics()->Dictionary:
	var result:Dictionary=_batch.statistics() if is_instance_valid(_batch) else {}
	result.merge({"selected":_selected,"counts":_counts.duplicate(true),"issues":_issues.duplicate(true),"preview_ok":_preview.get("ok")==true,"authority_write":false})
	return result
