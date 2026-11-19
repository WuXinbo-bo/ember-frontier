extends Node3D
## Public DTO consumer only. B owns shells, modules, batches and stock facts.
## Unmounted/unauthorised projections never become decorative fake production.
const StockView=preload("res://scripts/presentation/factory_stock_view.gd")
const MachineView=preload("res://scripts/presentation/factory_machine_view.gd")
const ConditionView=preload("res://scripts/presentation/factory_condition_view.gd")
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
const WaterView=preload("res://scripts/presentation/factory_water_view.gd")
const WorldHints=preload("res://scripts/presentation/factory_world_view_hints.gd")
var runtime:RefCounted
var _bound_world:int=0
var _world_id:=""
var _roots:Dictionary={}
var _buffers:Dictionary={}
var _keys:Dictionary={}
var _machines:Dictionary={}
var _conditions:Dictionary={}
var _issues:Array=[]
var _available:=false
var _delay:=0.0
var _updates:=0
var _hint_provider:WeakRef
var _hints:Node3D
var _hint_renderer:=false
var _staged_generation := false
var _generation_refresh_frame := -1
var _scene_basis: Array = []
var _refresh_deferred := false

func configure_view_hints(provider:Node)->void:
	_release_hint_renderer()
	_hint_provider=weakref(provider) if is_instance_valid(provider) else null
	_sync_view_hints()

func _release_hint_renderer()->void:
	var provider:Variant=_hint_provider.get_ref() if _hint_provider!=null else null
	if is_instance_valid(provider) and provider.has_method("set_view_hint_renderer"):
		provider.call("set_view_hint_renderer",false)
	_hint_renderer=false
	if is_instance_valid(_hints):_hints.clear()

func _sync_view_hints()->void:
	var provider:Variant=_hint_provider.get_ref() if _hint_provider!=null else null
	if not is_inside_tree() or not is_instance_valid(provider) or not provider.is_inside_tree() or not provider.has_method("view_hints") or not provider.has_method("set_view_hint_renderer") or _bound_world==0:
		_release_hint_renderer();return
	var world:Variant=instance_from_id(_bound_world)
	if not is_instance_valid(world) or not world.has_method("identity") or not world.has_method("get_revision"):
		_release_hint_renderer();return
	if not is_instance_valid(_hints):
		_hints=WorldHints.new();_hints.name="WorldViewHints";add_child(_hints)
	var dto:Variant=provider.call("view_hints")
	var ready:bool=dto is Dictionary and _hints.update(dto,str(world.identity().get("worldId","")),world.get_revision())
	if not ready:_release_hint_renderer();return
	if not _hint_renderer:
		provider.call("set_view_hint_renderer",true);_hint_renderer=true

func configure(authority:RefCounted)->void:
	if authority!=runtime or _bound_world!=_world_instance(authority):_clear()
	if runtime != authority and runtime != null and runtime.has_signal("changed") and runtime.changed.is_connected(_on_runtime_change):
		runtime.changed.disconnect(_on_runtime_change)
	if runtime != authority:
		_generation_refresh_frame = -1
	runtime=authority;_delay=0
	if runtime != null and runtime.has_signal("changed") and not runtime.changed.is_connected(_on_runtime_change):
		runtime.changed.connect(_on_runtime_change)
	_bound_world=_world_instance(authority)
	sync()

static func _world_instance(authority:RefCounted)->int:
	if authority==null:return 0
	for property:Dictionary in authority.get_property_list():
		if property.name=="world":
			var world:Variant=authority.get("world")
			return world.get_instance_id() if world is Object and is_instance_valid(world) else 0
	return 0

func _process(delta:float)->void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(delta)
	preload("res://scripts/runtime/frame_costs.gd").end("presentation/factory_view.gd",measured)

func set_staged_generation(enabled: bool) -> void:
	_staged_generation = enabled

func _on_runtime_change(changes: Dictionary) -> void:
	if not _staged_generation or not changes.has("world") or changes.world.is_empty():
		return
	var events: Array = changes.get("events", [])
	if events.size() == 1 and events[0].get("kind") == "region_generated":
		# Keep module visual uploads clear of the authoritative commit, next
		# frame's ground decor and the following frame's building shell work.
		_generation_refresh_frame = Engine.get_process_frames() + 3
	elif _generation_refresh_frame >= 0 and changes.world.any(func(change: Dictionary) -> bool:
		return change.get("op") != "extension.set" or change.get("id") in ["r34:modules", "r34:production", "r3:structures"]):
		_generation_refresh_frame = -1

func _profiled_process(delta:float)->void:
	if _generation_refresh_frame >= 0:
		if Engine.get_process_frames() < _generation_refresh_frame:
			return
		_generation_refresh_frame = -1
		_delay = 0
	_delay-=delta
	if _delay > 0:
		return
	if runtime != null and runtime.has_method("reserve_periodic_display_frame"):
		if not runtime.reserve_periodic_display_frame() and not _refresh_deferred:
			_refresh_deferred = true
			return
	_refresh_deferred = false
	_delay = 0.1
	var basis: Array = runtime.factory_visual_basis() if runtime != null and runtime.has_method("factory_visual_basis") else []
	if not basis.is_empty() and _scene_basis == basis:
		# Target and placement hints also follow the player/camera. Their exact
		# read keeps running even when the building and machine facts are stable.
		_sync_view_hints()
		return
	sync()
	if _available and _issues.is_empty():
		_scene_basis = basis

func _clear()->void:
	_scene_basis.clear()
	_release_hint_renderer()
	WaterView.sync_tree(get_tree() if is_inside_tree() else null,_bound_world,{"available":false})
	for id:String in _roots.keys():_retire(id)
	_keys.clear();_world_id="";_available=false

func _exit_tree()->void:
	_release_hint_renderer();_hint_provider=null
	WaterView.sync_tree(get_tree(),_bound_world,{"available":false})

func _retire(id:String)->void:
	var node:Node3D=_roots.get(id)
	if is_instance_valid(node):remove_child(node);node.queue_free()
	_roots.erase(id);_buffers.erase(id);_machines.erase(id);_conditions.erase(id);_keys.erase(id)

func sync()->void:
	_scene_basis = []
	var world_instance:int=_world_instance(runtime)
	if _bound_world!=world_instance:
		_clear();_bound_world=world_instance
	var method:String="factory_visual_snapshot" if runtime!=null and runtime.has_method("factory_visual_snapshot") else "factory_snapshot"
	if runtime==null or not runtime.has_method(method):
		apply_snapshot({"available":false});return
	var snapshot:Variant=runtime.call(method)
	if not snapshot is Dictionary:
		apply_snapshot({"available":false});_issues.append({"code":"FACTORY_DTO_REQUIRED"});return
	apply_snapshot(snapshot)
	_sync_view_hints()

func apply_snapshot(snapshot:Dictionary)->void:
	_scene_basis = []
	_issues=[]
	if not snapshot.get("available",false):_clear();return
	if snapshot.get("schema")!=Contracts.SCHEMA or snapshot.get("version")!=Contracts.VERSION:
		_clear();_issues.append({"code":"FACTORY_SCHEMA_UNSUPPORTED"});return
	var world:String=str(snapshot.get("world_id",""))
	var modules:Variant=snapshot.get("modules")
	if world.is_empty() or not modules is Dictionary:
		_clear();_issues.append({"code":"FACTORY_IDENTITY_OR_MODULES_REQUIRED"});return
	if world!=_world_id:_clear();_world_id=world
	_available=true
	var water:Variant=snapshot.get("water",{})
	WaterView.sync_tree(get_tree() if is_inside_tree() else null,_bound_world,water if water is Dictionary else {},runtime!=null and runtime.has_method("is_paused") and bool(runtime.call("is_paused")))
	if not modules.get("available",false):
		for id:String in _roots.keys():_retire(id)
		return
	var instances:Variant=modules.get("instances")
	if not instances is Array:
		_clear();_issues.append({"code":"MODULE_INSTANCES_REQUIRED"});return
	var live:Dictionary={}
	var definitions:Dictionary={}
	var source_definitions:Variant=modules.get("definitions",[])
	if not source_definitions is Array:
		_issues.append({"code":"MODULE_DEFINITIONS_REQUIRED"});source_definitions=[]
	for value:Variant in source_definitions:
		if value is Dictionary and not str(value.get("id","")).is_empty():definitions[str(value.id)]=value
	var paused:bool=runtime!=null and runtime.has_method("is_paused") and bool(runtime.call("is_paused"))
	var counts:Dictionary={}
	for value:Variant in instances:
		if value is Dictionary:
			var id:String=str(value.get("id",""))
			counts[id]=int(counts.get(id,0))+1
	for value:Variant in instances:
		if not value is Dictionary or str(value.get("id","")).is_empty():
			_issues.append({"code":"MODULE_ID_REQUIRED"});continue
		var id:String=str(value.id)
		if int(counts[id])>1:
			if not live.has(id):_issues.append({"module_id":id,"code":"DUPLICATE_MODULE_ID"})
			live[id]=true;_retire(id);continue
		live[id]=true
		if value.has("detailed"):
			if not value.detailed is bool:
				_issues.append({"module_id":id,"code":"MODULE_DETAIL_STATE_REQUIRED"});_retire(id);continue
			if not value.detailed:
				_retire(id);continue
		if not _valid_location(value.get("location")) or not _quarter_turn(value.get("quarter_turn")):
			_issues.append({"module_id":id,"code":"MODULE_LOCATION_REQUIRED"});_retire(id);continue
		var definition:Dictionary=definitions.get(str(value.get("definition_id","")),{})
		var key: Array = [value.location, value.get("quarter_turn", 0), value.get("state_code"), value.get("visuals", {}), definition.get("state_assets", {}), paused]
		if _keys.get(id)==key:continue
		var node:Node3D=_roots.get(id)
		if node==null:
			node=Node3D.new();node.name=id.validate_node_name();node.set_meta("module_id",id);add_child(node);_roots[id]=node;_buffers[id]={}
			# Public anchors remain WORLD metres even under a transformed host.
			node.top_level=true
		node.global_transform=Transform3D(Basis(Vector3.UP,-int(value.get("quarter_turn",0))*PI/2),Vector3(value.location.x,value.location.y,value.location.z))
		node.set_meta("state_code",value.get("state_code",""))
		var issue_count:int=_issues.size()
		_apply_visuals(id,value.get("visuals",{}),str(value.get("state_code","")),definition)
		# Retry invalid projections so diagnostics remain present on stable DTOs.
		if _issues.size()==issue_count:_keys[id]=key.duplicate(true)
		else:_keys.erase(id)
		_updates+=1
	for id:String in _roots.keys():
		if not live.has(id):_retire(id)

static func _valid_location(value:Variant)->bool:
	return value is Dictionary and ["x","y","z"].all(func(k:String)->bool:return StockView._number(value.get(k)))

static func _vector(value:Variant)->Variant:
	if value is Vector3:return value if value.is_finite() else null
	if value is Array and value.size()==3 and value.all(func(n:Variant)->bool:return StockView._number(n)):return Vector3(value[0],value[1],value[2])
	return null

static func _quarter_turn(value:Variant)->bool:
	return StockView._number(value) and float(value)==float(int(value)) and int(value)>=0 and int(value)<=3

static func _anchor(value:Variant)->Variant:
	if not value is Dictionary or not _quarter_turn(value.get("quarter_turn")):return null
	return _vector(value.get("position"))

func _apply_visuals(id:String,visuals:Variant,state:String,definition:Dictionary)->void:
	var live:Dictionary={};var stocks:Dictionary=_buffers[id]
	if not visuals is Dictionary:
		_issues.append({"module_id":id,"code":"VISUALS_DTO_REQUIRED"});visuals={}
	var anchors:Variant=visuals.get("anchors",{})
	var buffers:Variant=visuals.get("buffers",[])
	if not anchors is Dictionary or not buffers is Array:
		_issues.append({"module_id":id,"code":"VISUAL_ANCHORS_OR_BUFFERS_REQUIRED"});buffers=[];anchors={}
	var counts:Dictionary={}
	for row:Variant in buffers:
		if row is Dictionary:
			var buffer_id:String=str(row.get("id",""))
			counts[buffer_id]=int(counts.get(buffer_id,0))+1
	for row:Variant in buffers:
		if not row is Dictionary:
			_issues.append({"module_id":id,"code":"BUFFER_DTO_REQUIRED"});continue
		var buffer_id:String=str(row.get("id",""));var anchor:Variant=anchors.get(str(row.get("anchor_id","")))
		var position:Variant=_anchor(anchor)
		if buffer_id.is_empty() or position==null or int(counts.get(buffer_id,0))>1:
			_issues.append({"module_id":id,"buffer_id":buffer_id,"code":"BUFFER_ID_OR_ANCHOR_REQUIRED"});continue
		live[buffer_id]=true
		var stock:Node3D=stocks.get(buffer_id)
		if stock==null:stock=StockView.new();stock.name=buffer_id.validate_node_name();_roots[id].add_child(stock);stocks[buffer_id]=stock
		var data:Dictionary=row.duplicate(true);data.extent=_vector(row.get("extent"))
		# Owner already transforms local definition anchors to WORLD metres.
		stock.global_transform=Transform3D(Basis(Vector3.UP,-int(anchor.get("quarter_turn",0))*PI/2),position)
		stock.update(data)
		if not str(stock.statistics().issue).is_empty():_issues.append({"module_id":id,"buffer_id":buffer_id,"code":stock.statistics().issue})
	for buffer_id:String in stocks.keys():
		if not live.has(buffer_id):
			var stock:Node3D=stocks[buffer_id];stock.get_parent().remove_child(stock);stock.queue_free();stocks.erase(buffer_id)
	var mechanism:Variant=visuals.get("mechanism",{})
	var machine:Node3D=_machines.get(id)
	if mechanism is Dictionary and not mechanism.is_empty():
		var anchor:Variant=anchors.get(str(mechanism.get("anchor_id","")))
		var at:Variant=_anchor(anchor)
		if at!=null:
			if machine==null:machine=MachineView.new();_roots[id].add_child(machine);_machines[id]=machine
			machine.global_transform=Transform3D(Basis(Vector3.UP,-int(anchor.get("quarter_turn",0))*PI/2),at)
			var row:Dictionary=mechanism.duplicate(true)
			if state!="running":row.active=false
			if not machine.update(row):_issues.append({"module_id":id,"code":machine.statistics().issue})
		else:
			if machine!=null:machine.hide_projection()
			_issues.append({"module_id":id,"code":"MECHANISM_ANCHOR_REQUIRED"})
	elif machine!=null:machine.hide_projection()
	_apply_conditions(id,visuals,anchors,definition)

static func _anchor_transform(anchor:Dictionary)->Transform3D:
	return Transform3D(Basis(Vector3.UP,-int(anchor.quarter_turn)*PI/2),_anchor(anchor))

func _apply_conditions(id:String,visuals:Dictionary,anchors:Dictionary,definition:Dictionary)->void:
	var construction:Variant=visuals.get("construction",{})
	var damage:Variant=visuals.get("damage",{})
	var condition:Node3D=_conditions.get(id)
	if construction is Dictionary and construction.is_empty() and damage is Dictionary and damage.is_empty():
		if condition!=null:condition.hide_projection()
		return
	if condition==null:condition=ConditionView.new();_roots[id].add_child(condition);_conditions[id]=condition
	if not construction is Dictionary or not damage is Dictionary:
		condition.hide_projection();_issues.append({"module_id":id,"code":"CONDITION_DTO_REQUIRED"});return
	var work_anchor:Variant=anchors.get(str(construction.get("anchor_id","")))
	if construction.is_empty():condition.update_construction({},Transform3D.IDENTITY)
	elif _anchor(work_anchor)!=null:
		var work_transform:Transform3D=_anchor_transform(work_anchor)
		var ground_transform:Transform3D=work_transform
		ground_transform.origin.y=_roots[id].global_position.y
		ground_transform.origin+=work_transform.basis.x*1.25-work_transform.basis.z*0.6
		var row:Dictionary=construction.duplicate()
		if runtime!=null and runtime.has_method("is_paused") and bool(runtime.call("is_paused")):row.active=false
		condition.update_construction(row,work_transform,ground_transform)
	else:
		condition.update_construction({},Transform3D.IDENTITY)
		_issues.append({"module_id":id,"code":"CONSTRUCTION_ANCHOR_REQUIRED"})
	var damage_anchor:Variant=anchors.get(str(damage.get("anchor_id","")))
	if damage.is_empty():condition.update_damage({},Transform3D.IDENTITY,"")
	elif _anchor(damage_anchor)!=null:
		var forward:Variant=damage_anchor.get("forward")
		if forward is Array and forward.size()==2 and StockView._number(forward[0]) and StockView._number(forward[1]) and Vector2(forward[0],forward[1]).length_squared()>0.0001:
			var normal:=Vector3(forward[0],0,forward[1]).normalized()
			var transform:=Transform3D(Basis(Vector3.UP.cross(normal),Vector3.UP,normal),_anchor(damage_anchor))
			var assets:Variant=definition.get("state_assets",{})
			if not assets is Dictionary:assets={}
			var surface:String=str(assets.get("damaged","")).replace("_damaged","_damage_detail")
			condition.update_damage(damage,transform,surface)
		else:
			condition.update_damage({},Transform3D.IDENTITY,"")
			_issues.append({"module_id":id,"code":"DAMAGE_SURFACE_NORMAL_REQUIRED"})
	else:
		condition.update_damage({},Transform3D.IDENTITY,"")
		_issues.append({"module_id":id,"code":"DAMAGE_SURFACE_ANCHOR_REQUIRED"})
	for code:String in condition.statistics().issues.values():_issues.append({"module_id":id,"code":code})

func statistics()->Dictionary:
	var rows:Array=[]
	for id:String in _buffers:
		for buffer_id:String in _buffers[id]:rows.append({"module_id":id,"buffer_id":buffer_id,"stock":_buffers[id][buffer_id].statistics()})
	var machines:Array=[]
	for id:String in _machines:machines.append({"module_id":id,"mechanism":_machines[id].statistics()})
	var conditions:Array=[]
	for id:String in _conditions:conditions.append({"module_id":id,"condition":_conditions[id].statistics()})
	return {"available":_available,"world_id":_world_id,"modules":_roots.size(),"updates":_updates,"buffers":rows,"mechanisms":machines,"conditions":conditions,"required_errors":_issues.duplicate(true),"scope":"read-only public factory DTO; no authority changes"}
