extends RefCounted
## Stable dollhouse rendering. World geometry, actor visibility, permissions,
## discovery and saved facts remain exclusively in their existing services.
const Rooms=preload("res://scripts/presentation/interior_room_projection.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const ModuleData=preload("res://scripts/world/world_data.gd")
const SETTLE_MS:=140
const COVERAGE_LIMIT:=256.0
const COVERAGE_CACHE_LIMIT:=4096
var _query:RefCounted
var _rooms:=Rooms.new()
var _groups:Dictionary={}
var _storeys:Dictionary={}
var _floor_bounds:Dictionary={}
var _active:Dictionary={}
var _pending:Dictionary={}
var _pending_since:int=0
var _observed:Dictionary={}
var _side:=Vector2(1,1)
var _initialized:=false
var _version:=0
var _transitions:=0
var _last_sample_ms:=0
var _topology_key:String=""
# Disposable exact-segment proofs. C remains the sole generated/resident
# authority; never quantize the observer across a chunk/region boundary.
var _coverage_world:RefCounted
var _coverage_revision:int=-1
var _coverage_origin:Array=[]
var _coverage:Dictionary={}
var _shell_coverage:Dictionary={}
var _coverage_checks:int=0
var _coverage_hits:int=0
var _adjacency_world:RefCounted
var _adjacency_revision:int=-1
var _adjacency_region:String=""
var _adjacent:Dictionary={}
var _module_rooms:Dictionary={}
var _module_world_stamp:String=""
var _module_epoch:int=0
var _module_piece_keys:Dictionary={}

func _structure_key(space:RefCounted)->String:
	var records:Array=[]
	for piece:Dictionary in space.pieces:
		records.append(JSON.stringify([piece.id,piece.get("definitionId"),piece.get("geometryVersion",1),float(piece.get("hp",0))>0,piece.get("position"),piece.get("quarterTurn",0),piece.get("regionId"),piece.get("buildingId"),piece.get("storeyId")]))
	records.sort()
	var chunks:Array=[]
	for id:String in space.world.chunk_keys():
		# Room topology needs only revision/generated. Copying the full voxel
		# arrays here repeats megabytes of work on every paging publication.
		var chunk:Dictionary=space.world.chunk_metadata(id)
		chunks.append([id,chunk.get("revision",0),chunk.get("generated",false)])
	chunks.sort_custom(func(a:Array,b:Array)->bool:return a[0]<b[0])
	# B resolves these fields from geometry_history_v1. Pure material/catalog
	# changes cannot reset a doorway transition or redefine a saved room.
	var geometry_records:Array=[]
	var ids:Array=space.geometry.definitions.keys();ids.sort()
	for id:String in ids:
		var definition:Dictionary=space.geometry.definitions[id];var fields:Array=[id]
		for key:String in Geometry.GEOMETRY_KEYS:fields.append([key,definition.get(key)])
		geometry_records.append(fields)
	return str([space.world.get_instance_id(),space.world.identity(),space.world.config(),space.state.get("storeys",[]),records,chunks,Geometry.GEOMETRY_VERSION,geometry_records.hash()])

func configure(space:RefCounted,camera_offset:Vector3=Vector3(24,29,31))->void:
	var token:Dictionary=space.world.extension_token("r34:modules") if space!=null and space.world.has_method("extension_token") else {}
	var stamp:String=var_to_str([space.world.get_instance_id(),token.get("authority"),token.get("generation")]) if space!=null else ""
	if stamp!=_module_world_stamp:_module_rooms.clear();_module_piece_keys.clear();_module_world_stamp=stamp;_module_epoch+=1
	var next_side:=Vector2(signf(camera_offset.x),signf(camera_offset.z))
	if space==_query and next_side==_side:return
	_side=next_side
	if space==_query:
		_version+=1
		return
	_module_piece_keys.clear()
	var topology:String=_structure_key(space)
	# A new query may bind a restored snapshot with equal revision numbers.
	# Do not let the independently stable room topology retain coverage proofs.
	_coverage.clear();_coverage_origin.clear();_coverage_world=null;_coverage_revision=-1
	_adjacency_world=null
	if topology==_topology_key:
		# Rebind actual sight without resetting the structural room/transition.
		_query=space;_rooms.query=space
		return
	_topology_key=topology
	_query=space;_groups.clear();_storeys.clear();_floor_bounds.clear()
	_rooms.configure(space)
	for floor_record:Dictionary in space.state.get("storeys",[]):_storeys[floor_record.id]=floor_record.duplicate(true)
	for roof:Dictionary in _rooms.roofs:
		var component:int=_rooms.components[roof.id]
		var box:AABB=space.bounds(roof)
		if not _groups.has(component):_groups[component]={"id":str(roof.id),"bounds":box}
		else:
			if str(roof.id)<str(_groups[component].id):_groups[component].id=str(roof.id)
			_groups[component].bounds=_groups[component].bounds.merge(box)
	# A removed ceiling or a legitimate uncovered floor still has a stable
	# floor anchor; no invented y=0 plane or regeneration of an old building.
	for piece:Dictionary in space.pieces:
		if float(piece.get("hp",0))<=0 or piece.get("buildingId")==null or piece.get("storeyId")==null:continue
		var key:=_floor_key(piece)
		var box:AABB=space.bounds(piece)
		_floor_bounds[key]=_floor_bounds[key].merge(box) if _floor_bounds.has(key) else box
	_version+=1;_initialized=false;_pending.clear()

static func _floor_key(value:Dictionary)->String:
	return JSON.stringify([value.get("regionId"),value.get("buildingId"),value.get("storeyId")])

func _scope(location:Dictionary)->Dictionary:
	var result:Dictionary={"key":JSON.stringify([location.get("regionId"),null]),"regionId":location.get("regionId"),"buildingId":null,"storeyId":null}
	if location.get("buildingId")==null or location.get("storeyId")==null:return result
	var floor_record:Dictionary=_storeys.get(location.storeyId,{})
	if floor_record.is_empty() or floor_record.get("buildingId")!=location.buildingId or floor_record.get("regionId")!=location.regionId:return result
	var floor_key:=_floor_key(location)
	if not _floor_bounds.has(floor_key):return result
	var component:int=_rooms.component_at(location)
	var group:Dictionary=_groups.get(component,{})
	var bounds:AABB=group.get("bounds",_floor_bounds[floor_key])
	var room_key:String=str(group.get("id",floor_key))
	return {"key":JSON.stringify([location.regionId,location.buildingId,location.storeyId,room_key]),"regionId":location.regionId,"buildingId":location.buildingId,"storeyId":location.storeyId,"elevation":float(floor_record.elevation),"index":int(floor_record.get("index",0)),"anchor":bounds.get_center(),"room_id":room_key,"bounds":bounds}

func sample(location:Dictionary,now_ms:int=-1)->bool:
	if _query==null or location.is_empty():return false
	var now:int=Time.get_ticks_msec() if now_ms<0 else now_ms
	_sample_module_rooms(location,now)
	var next:=_scope(location)
	var discontinuity:bool=not _observed.is_empty() and (location.get("regionId")!=_observed.get("regionId") or Geometry.point(location).distance_to(Geometry.point(_observed))>3.0)
	_observed=location.duplicate(true)
	_last_sample_ms=now
	if not _initialized or discontinuity:
		_initialized=true;_pending.clear()
		return _activate(next)
	if next.key==_active.get("key"):
		_pending.clear()
		return false
	if next.key!=_pending.get("key"):
		_pending=next;_pending_since=now
		return false
	if now-_pending_since<SETTLE_MS:return false
	_pending.clear()
	return _activate(next)

func _activate(scope:Dictionary)->bool:
	var changed:bool=_active.get("key")!=scope.key
	_active=scope
	if changed:_transitions+=1
	return changed

func signature()->String:
	return str(_version)+"|"+str(_active.get("key","unbound"))+"|"+str(_side)+"|module:"+str(_module_epoch)

func base_visible(piece:Dictionary,role:String)->bool:
	if role=="cap":return false
	# The actual region is never delayed by doorway hysteresis.
	# Exterior structure keeps its real building/storey metadata; projecting
	# endpoints outdoors proves finite data coverage, never room/content sight.
	if piece.get("regionId")!=_observed.get("regionId") and not _outdoor_coverage(_observed,Geometry.location(piece)):return false
	return _floor_visible(piece,role)

func _floor_visible(piece:Dictionary,role:String)->bool:
	if _active.get("buildingId")==null or piece.get("buildingId")!=_active.get("buildingId"):return true
	var floor_record:Dictionary=_storeys.get(piece.get("storeyId"),{})
	if not floor_record.is_empty() and float(floor_record.elevation)>float(_active.elevation)+0.05:return false
	if floor_record.is_empty() and float(piece.get("position",piece).get("y",0))>float(_active.elevation)+1.0:return false
	if role=="roof" and (piece.get("storeyId")==_active.storeyId or float(piece.get("position",piece).get("y",0))>float(_active.elevation)+0.2):return false
	return true

func module_shell_visible(piece:Dictionary,player:Dictionary,observer:Dictionary,resident:bool)->bool:
	if not module_part_visible(piece,player):return false
	if not resident or _query==null:return false
	var target:=Geometry.location(piece)
	# A successful 96m shell query already proves the same endpoints for the
	# wider exterior query. Resolve the actual target location before checking
	# the top-level region label, which may differ on legacy display records.
	if observer.get("regionId")!=target.get("regionId"):
		if not shell_coverage(_query.world,observer,target):return false
	elif piece.get("regionId")!=_observed.get("regionId") and not _outdoor_coverage(_observed,target):return false
	return _floor_visible(piece,"object")

func can_observe_geometry(piece:Dictionary,player:Dictionary)->bool:
	# Fixed shells only, never NPCs, content discovery or action authority.
	if _query==null or not base_visible(piece,"object"):return false
	var p:=Geometry.location(player);var at:=Geometry.location(piece)
	if at.buildingId==null:
		if at.storeyId!=null:return false
		if at.regionId!=p.regionId or _query.world.identity().generatorVersion in ["rural-2","rural-3"]:
			if not _outdoor_coverage(p,at):return false
		return _query.line_clear(p,at,str(piece.get("id","")))
	if at.regionId!=p.regionId:return false
	if at.buildingId!=p.buildingId or at.storeyId!=p.storeyId:return false
	var component:int=_rooms.component_at(at)
	var group:Dictionary=_groups.get(component,{})
	if not group.is_empty() and _active.get("buildingId")==at.buildingId and _active.get("storeyId")==at.storeyId and _active.get("room_id")==str(group.id):return true
	return _query.line_clear(p,at,str(piece.get("id","")))

func _bind_coverage(world:RefCounted,observer:Dictionary)->void:
	var revision:int=world.get_revision()
	var origin:Array=[observer.get("regionId"),Geometry.point(observer)]
	if world!=_coverage_world or revision!=_coverage_revision or origin!=_coverage_origin:
		_coverage.clear();_shell_coverage.clear();_coverage_world=world;_coverage_revision=revision;_coverage_origin=origin

func _can_cross_region(world:RefCounted,observer:Dictionary,target:Dictionary)->bool:
	return _can_cross_region_ids(world,str(observer.get("regionId","")),str(target.get("regionId","")))

func shell_region_candidate(region:String)->bool:
	# A different, nonadjacent region is already vetoed by base_visible.
	# Out-of-region parts cannot update the local module room transition.
	return _query==null or _can_cross_region_ids(_query.world,str(_observed.get("regionId","")),region)

func _can_cross_region_ids(world:RefCounted,region:String,destination:String)->bool:
	if region==destination or not world.has_method("continuous_outdoor_neighbors"):return true
	var revision:int=world.get_revision()
	if world!=_adjacency_world or revision!=_adjacency_revision or region!=_adjacency_region:
		_adjacent.clear()
		for neighbor:Dictionary in world.continuous_outdoor_neighbors(region):_adjacent[neighbor.to_region_id]=true
		_adjacency_world=world;_adjacency_revision=revision;_adjacency_region=region
	# Only reject. Candidates still run C's exact endpoint, face and coverage proof.
	return _adjacent.has(destination)

func shell_coverage(world:RefCounted,observer:Dictionary,target:Dictionary)->bool:
	# Keep B's original 96m shell query, including indoor partition rejection.
	# A successful exact segment is also a proof for this policy's 256m bound.
	# Reuse ONLY success, for these same endpoints/world/current revision;
	# a shorter-range failure must never veto a valid longer policy segment.
	if observer.get("buildingId")!=null or observer.get("storeyId")!=null or target.get("buildingId")!=null or target.get("storeyId")!=null:return false
	if not _can_cross_region(world,observer,target):return false
	_bind_coverage(world,observer)
	# The 96m call also checks endpoint partitions, unlike the projected
	# exterior query. Keep its own exact proof (including negative results).
	var key:Array=[observer.get("buildingId"),observer.get("storeyId"),target.get("regionId"),target.get("buildingId"),target.get("storeyId"),Geometry.point(target)]
	if _shell_coverage.has(key):return _shell_coverage[key]
	var accepted:bool=world.continuous_outdoor_segment(observer,target,96.0,true).ok
	if _shell_coverage.size()>=COVERAGE_CACHE_LIMIT:_shell_coverage.clear()
	_shell_coverage[key]=accepted
	if accepted and _query!=null and _query.world==world:
		if _coverage.size()>=COVERAGE_CACHE_LIMIT:_coverage.clear()
		_coverage[[target.get("regionId"),Geometry.point(target)]]=true
	return accepted

func _outdoor_coverage(observer:Dictionary,target:Dictionary)->bool:
	if _query==null or observer.is_empty():return false
	var world:RefCounted=_query.world
	if not world.has_method("continuous_outdoor_segment"):return false
	if not _can_cross_region(world,observer,target):return false
	_bind_coverage(world,observer)
	var key:Array=[target.get("regionId"),Geometry.point(target)]
	if _coverage.has(key):
		_coverage_hits+=1
		return _coverage[key]
	var from:Dictionary=Geometry.location(observer);var to:Dictionary=Geometry.location(target)
	from.buildingId=null;from.storeyId=null;to.buildingId=null;to.storeyId=null
	# A cold endpoint is already a conclusive rejection from C's public cell
	# query. Avoid asking for a detailed long rejection DTO for every hidden
	# distant shell. A positive still requires the complete actual C segment.
	var accepted:=true
	for point:Vector3 in [Geometry.point(from),Geometry.point(to)]:
		if not world.is_cell_resident(floori(point.x/_query.cell_size),floori(point.y/_query.cell_size),floori(point.z/_query.cell_size)):
			accepted=false;break
	if accepted:
		accepted=world.continuous_outdoor_segment(from,to,COVERAGE_LIMIT,true).ok
		_coverage_checks+=1
	# Multiple faces, details and picking share the same actual piece anchor.
	# B sight still handles exact opaque geometry; no permission is cached.
	if _coverage.size()>=COVERAGE_CACHE_LIMIT:_coverage.clear()
	_coverage[key]=accepted
	return accepted

func entry_boxes(piece:Dictionary)->Array:
	# Exact B doorway trim, not replacement collision or closed-door sight.
	if _query==null:return []
	var d:Dictionary=_query.geometry.definition(piece)
	if not d.has("door") or float(piece.get("hp",0))<=0:return []
	var width:float=d.door.width;var height:float=d.door.height
	var boxes:Array=[]
	for x:float in [-width/2.0-0.035,width/2.0+0.035]:
		boxes.append(Geometry.transformed_box(AABB(Vector3(x-0.035,0,-0.135),Vector3(0.07,height,0.27)),piece))
	boxes.append(Geometry.transformed_box(AABB(Vector3(-width/2.0-0.07,height,-0.135),Vector3(width+0.14,0.07,0.27)),piece))
	return boxes

func pick_boxes(piece:Dictionary)->Array:
	if _query==null:return []
	var kind:String=_query.geometry.definition(piece).get("kind","")
	if not base_visible(piece,kind):return []
	if cut_wall(piece):return entry_boxes(piece) if kind=="door" else []
	if kind in ["cabinet","workbench"] and not can_observe_geometry(piece,_observed):return []
	return _query.geometry.boxes(piece)

func cut_wall(piece:Dictionary)->bool:
	if _query==null or _active.get("buildingId")==null or piece.get("regionId")!=_observed.get("regionId") or piece.get("buildingId")!=_active.get("buildingId") or piece.get("storeyId")!=_active.get("storeyId"):return false
	if not _query.by_id.has(piece.get("id")):return false
	var kind:String=_query.geometry.definition(piece).kind
	if kind not in ["wall","corner","door","window"]:return false
	var box:AABB=_query.bounds(piece)
	var center:=box.get_center()
	var anchor:Vector3=_active.anchor
	# Compare with the fixed structural ROOM, never the moving player. Long
	# wall axes identify their facing direction, including rotated buildings.
	var normal_x:bool=box.size.z>=box.size.x*0.75
	var normal_z:bool=box.size.x>=box.size.z*0.75
	return (normal_x and _side.x!=0 and (center.x-anchor.x)*_side.x>0.05) or (normal_z and _side.y!=0 and (center.z-anchor.z)*_side.y>0.05)

func module_part_visible(piece:Dictionary,player:Dictionary,now_ms:int=-1)->bool:
	# An additional render veto only. B must still apply its original resident,
	# coverage and object disclosure checks; true never grants visibility/LOS.
	var data:Dictionary=piece.get("data",{})
	var version:String=str(data.get("module_geometry_version",""))
	if not version.begins_with("r34.module.home_") or not version.ends_with(".geometry-v2"):return true
	if piece.get("regionId")!=player.get("regionId") or not ModuleData.vec(player):return true
	var room:Variant=data.get("module_room")
	# Hundreds of fixed parts share a handful of room records. Formatting the
	# complete room/bounds to text on every movement used to dominate this
	# pass. Cache only this derived key and recheck ALL inputs before reuse;
	# arbitrary callers changing a piece dictionary cannot retain an old key.
	var id:String=str(piece.get("id",""));var compiled:Dictionary=_module_piece_keys.get(id,{})
	var key:String
	if not id.is_empty() and compiled.get("version")==version and compiled.get("module_id")==data.get("module_id") and compiled.get("region")==piece.get("regionId") and compiled.get("room")==room:
		key=compiled.key
	else:
		if not room is Dictionary or room.get("version")!=2 or not room.get("room_id") is String or str(room.room_id).is_empty() or not ModuleData.bounds(room.get("bounds")):return true
		if room.get("role") not in ["roof","wall","trim"] or not ModuleData.vec(room.get("normal")):return true
		key=var_to_str([data.get("module_id"),version,room.room_id,room.bounds,piece.get("regionId")])
		if not id.is_empty():
			if _module_piece_keys.size()>=4096:_module_piece_keys.clear()
			_module_piece_keys[id]={"version":version,"module_id":data.get("module_id"),"region":piece.get("regionId"),"room":room.duplicate(true),"key":key}
	var now:int=Time.get_ticks_msec() if now_ms<0 else now_ms
	var inside:bool=ModuleData.contains(room.bounds,player)
	if not _module_rooms.has(key):
		if _module_rooms.size()>=256:_module_rooms.erase(_module_rooms.keys()[0])
		_module_rooms[key]={"inside":inside,"pending":inside,"since":now,"bounds":room.bounds.duplicate(true),"region":piece.get("regionId")}
		_module_epoch+=1
	var state:Dictionary=_module_rooms[key]
	_set_module_inside(state,inside,now)
	if not state.inside:return true
	if room.role=="roof":return false
	var normal:=Vector2(float(room.normal.x),float(room.normal.z))
	# Fixed owner wall normal and fixed camera side, never player-side peeling.
	return normal.length_squared()<.000001 or normal.normalized().dot(_side.normalized())<=.05

func _set_module_inside(state:Dictionary,inside:bool,now:int)->void:
	if inside==bool(state.inside):state.pending=inside;state.since=now
	elif inside!=bool(state.pending):state.pending=inside;state.since=now
	elif now-int(state.since)>=SETTLE_MS:state.inside=inside;_module_epoch+=1

func _sample_module_rooms(location:Dictionary,now:int)->void:
	if not ModuleData.vec(location):return
	for state:Dictionary in _module_rooms.values():
		_set_module_inside(state,location.get("regionId")==state.region and ModuleData.contains(state.bounds,location),now)

func statistics()->Dictionary:
	var anchor:Vector3=_active.get("anchor",Vector3.ZERO)
	return {"policy":"stable-floor-room-v1","outdoor_scope":"finite-resident-v1","region_id":_observed.get("regionId"),"building_id":_active.get("buildingId"),"storey_id":_active.get("storeyId"),"room_id":_active.get("room_id"),"anchor":[anchor.x,anchor.y,anchor.z],"pending":not _pending.is_empty(),"settle_ms":SETTLE_MS,"transitions":_transitions,"topology_rebuilds":_version,"structural_rooms":_groups.size(),"coverage_entries":_coverage.size(),"coverage_queries":_coverage_checks,"coverage_hits":_coverage_hits,"sample_ms":_last_sample_ms,"authority_changes":false}
