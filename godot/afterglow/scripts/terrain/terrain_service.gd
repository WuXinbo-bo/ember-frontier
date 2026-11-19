extends RefCounted
## Actual runtime domain: one A-clock labor intent, real pack/tool CAS, no private
## simulation. advance(dt) is called by A's fixed step, never a scene process.
const Data = preload("res://scripts/world/world_data.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
const Draft = preload("res://scripts/actions/domain_draft.gd")
const Definitions = preload("res://scripts/runtime/content_definitions.gd")
var context: Dictionary
var _tool_definitions: Dictionary = {}
var _production: WeakRef
var _runtime_host: WeakRef
var _work_projection_cache: Dictionary = {}
var _work_projection_revisions: Array = []
var _material_contract: Dictionary = {"ok":true}

static func validate_material_definitions(materials:Dictionary=Data.MATERIALS)->Dictionary:
	# Terrain yields cubic metres, never item counts. Consume A's immutable
	# item descriptions without registering another inventory/catalogue.
	for material:Variant in materials:
		var record:Variant=materials[material]
		if not record is Dictionary:return Data.reject("INVALID_MATERIAL_ITEM",str(material))
		var item:Variant=record.get("item","")
		if not item is String:return Data.reject("INVALID_MATERIAL_ITEM",str(material))
		if item.is_empty():
			if record.get("diggable",false):return Data.reject("INVALID_MATERIAL_ITEM",str(material))
			continue
		var definition:Dictionary=Definitions.item_definition(item)
		if definition.is_empty() or definition.get("unit")!="m3" or not Definitions.quantity_valid(item,0.125):return Data.reject("INVALID_MATERIAL_ITEM",item)
	return {"ok":true,"code":"OK"}

class EditSight extends RefCounted:
	# Disposable query projection of removals in this same atomic level edit.
	# It never owns or mutates cells, and never hides an unknown cell or a
	# non-selected obstruction. The target itself must remain a real hit.
	var world: RefCounted
	var removed: Dictionary = {}
	var target := ""
	func config() -> Dictionary: return world.config()
	func get_revision() -> int: return world.get_revision()
	func is_cell_known(x: int,y: int,z: int) -> bool: return world.is_cell_known(x,y,z)
	func is_cell_resident(x:int,y:int,z:int)->bool:return world.is_cell_resident(x,y,z)
	func cell_at(x: int,y: int,z: int) -> int:
		var id := "%d,%d,%d" % [x,y,z]
		return 0 if id != target and removed.has(id) else world.cell_at(x,y,z)

func configure(value: Dictionary) -> void:
	_work_projection_cache.clear();_work_projection_revisions.clear()
	if not value.has("world"):
		context = {}
		_production = null
		_runtime_host = null
		return
	context = preload("res://scripts/actions/domain_context.gd").isolate(value)
	_runtime_host = weakref(value.runtime) if value.get("runtime") is RefCounted else null
	_material_contract = validate_material_definitions()
	var production: Variant = value.get("services",{}).get("production")
	_production = weakref(production) if production is RefCounted else null
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	if catalog is Dictionary: _tool_definitions = catalog.get("tool_definitions",{})

func availability(request: Dictionary) -> Dictionary:
	var result := prepare(request) if request.get("kind") == "held" else _plan(request)
	if result.ok:
		result.erase("world_changes")
		result.erase("material_delta")
		result.erase("fact_changes")
	return result

func validate_intent(intent:Dictionary,actor_state:Dictionary={},_facts_state:Dictionary={})->Dictionary:
	# Pure schema check. v0 is the existing explicitly known terrain action;
	# compatibility never manufactures an ID, reserves stock, or reads a scene.
	var version:Variant=intent.get("schema_version",0)
	if not Data.integer(version) or int(version) not in [0,1] or intent.get("owner")!="terrain" or intent.get("kind")!="terrain":return Data.reject("INVALID_TERRAIN_INTENT","owner/kind/schema_version")
	if not Data.valid_id(intent.get("id")):return Data.reject("INVALID_TERRAIN_INTENT","id")
	for key:String in ["elapsed","duration"]:
		var value:Variant=intent.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value<0:return Data.reject("INVALID_TERRAIN_INTENT",key)
	if intent.elapsed>intent.duration or intent.duration<=0:return Data.reject("INVALID_TERRAIN_INTENT","progress")
	if not intent.get("held",true) is bool or not intent.get("tool_id","") is String:return Data.reject("INVALID_TERRAIN_INTENT","held/tool_id")
	var request:Variant=intent.get("request")
	if not request is Dictionary or request.get("kind")!="terrain" or not Data.valid_id(request.get("actor_id")) or not request.get("payload") is Dictionary:return Data.reject("INVALID_TERRAIN_INTENT","request")
	if not actor_state.is_empty() and request.actor_id!=actor_state.get("id"):return Data.reject("INVALID_TERRAIN_INTENT","actor reference")
	var edit:Variant=request.payload.get("edit",request.payload)
	if not edit is Dictionary or edit.get("operation","dig") not in ["dig","fill","level"] or not edit.get("cells",[]) is Array:return Data.reject("INVALID_TERRAIN_INTENT","edit")
	var request_tool:Variant=request.payload.get("tool_id",request.payload.get("toolId",edit.get("tool_id",edit.get("toolId",""))))
	if not request_tool is String or request_tool!=intent.get("tool_id","") or (request.has("command_id") and request.command_id!=intent.id):return Data.reject("INVALID_TERRAIN_INTENT","request identity/tool")
	if not Data.integer(edit.get("material",2)) or (edit.get("operation","dig")!="dig" and int(edit.get("material",2)) not in [2,3,6]):return Data.reject("INVALID_TERRAIN_INTENT","material")
	if edit.get("operation","dig")=="level":
		var area:Variant=edit.get("area");var height:Variant=edit.get("height")
		if not area is Dictionary or not area.has_all(["minI","maxI","minK","maxK"]) or not area.values().all(Data.integer) or area.maxI<=area.minI or area.maxK<=area.minK or not (height is int or height is float) or not is_finite(float(height)):return Data.reject("INVALID_TERRAIN_INTENT","level area/height")
	else:
		if edit.get("cells",[]).is_empty() or edit.cells.size()>4096:return Data.reject("INVALID_TERRAIN_INTENT","cells")
	for cell:Variant in edit.get("cells",[]):
		if not cell is Dictionary or not cell.has_all(["x","y","z"]) or not [cell.x,cell.y,cell.z].all(Data.integer):return Data.reject("INVALID_TERRAIN_INTENT","cell coordinate")
	var cost:Variant=intent.get("cost",{})
	if not cost is Dictionary or not intent.get("source_id","") is String:return Data.reject("INVALID_TERRAIN_INTENT","hold")
	if intent.has("source_id") and intent.source_id!="pack:"+str(request.actor_id):return Data.reject("INVALID_TERRAIN_INTENT","source identity")
	for item:Variant in cost:
		if not Data.valid_id(item) or not (cost[item] is float or cost[item] is int) or not is_finite(float(cost[item])) or cost[item]<=0:return Data.reject("INVALID_TERRAIN_INTENT","cost")
		# Only explicit v0 compatibility may retain an unknown historical item.
		# New formal costs must resolve; no suffix heuristic or rounding of m3.
		if not Definitions.quantity_valid(item,cost[item],int(version)==0):return Data.reject("INVALID_TERRAIN_INTENT","cost definition")
	if int(version)==1 and not intent.has_all(["held","tool_id","source_id","cost"]):return Data.reject("INVALID_TERRAIN_INTENT","v1 fields")
	return {"ok":true,"code":"OK"}

func hold_descriptors(facts:Dictionary,_extension_overrides:Dictionary={})->Array:
	var holds:Array=[]
	for actor:Variant in facts.get("actors",[]):
		if not actor is Dictionary or not actor.get("intent") is Dictionary:continue
		var intent:Dictionary=actor.intent
		if not validate_intent(intent,actor,facts).ok or float(actor.get("hp",0))<=0:continue
		if actor.id!="player" and not actor.get("relationship",{}).get("consent",false):continue
		var tool:String=intent.get("tool_id","")
		holds.append({"schema_version":1,"owner":"terrain","intent_id":intent.id,"actor_id":actor.id,"phase":"active" if intent.get("held",true) else "paused","source_id":intent.get("source_id","pack:"+str(actor.id)),"cost":intent.get("cost",{}).duplicate(true),"tool_ids":[] if tool.is_empty() else [tool],"use_target_id":""})
	return holds

func _plan(request: Dictionary, completing: bool = false, observed:RefCounted=null) -> Dictionary:
	if context.is_empty(): return Data.reject("MISSING_WORLD")
	if not _material_contract.ok:return _material_contract.duplicate(true)
	var world: RefCounted = context.world
	var a: Dictionary = context.actor.call(str(request.get("actor_id",""))) if observed==null else observed.actor(str(request.get("actor_id","")))
	if a.is_empty() or float(a.get("hp",0)) <= 0: return Data.reject("ACTOR_UNAVAILABLE")
	if a.id != "player" and not a.get("relationship",{}).get("consent",false): return Data.reject("NO_CONSENT")
	if not completing and a.get("intent") != null: return Data.reject("BUSY")
	if not request.get("payload",{}) is Dictionary: return Data.reject("INVALID_TERRAIN_EDIT")
	var payload: Dictionary = request.get("payload",{})
	if not payload.get("edit",payload) is Dictionary: return Data.reject("INVALID_TERRAIN_EDIT")
	var edit: Dictionary = payload.get("edit",payload)
	var operation := str(edit.get("operation","dig"))
	if operation not in ["dig","fill","level"]: return Data.reject("INVALID_TERRAIN_EDIT")
	var cfg: Dictionary = world.config()
	var s := float(cfg.cellSize)
	if not edit.get("cells",[]) is Array: return Data.reject("INVALID_TERRAIN_EDIT")
	var cells: Array = edit.get("cells",[]).duplicate(true)
	var tool_id := str(payload.get("tool_id",payload.get("toolId",edit.get("tool_id",edit.get("toolId","")))))
	var selected: Dictionary = (context.tool.call(tool_id) if observed==null else Draft.find(observed.extension("r3:production",{}).get("tools",[]),tool_id)) if not tool_id.is_empty() else {}
	var qualities: Dictionary = selected.get("qualities",_tool_definitions.get(selected.get("kind"),{}).get("qualities",{}))
	if not tool_id.is_empty() and (selected.is_empty() or selected.get("holderId") != "pack:"+str(a.id) or float(selected.get("durability",0)) <= 0 or (float(qualities.get("shovel",0)) <= 0 and float(qualities.get("pickaxe",0)) <= 0)): return Data.reject("MISSING_TOOL")
	var production: Variant = _production.get_ref() if _production != null else null
	var excluding := str(a.intent.get("id","")) if completing and a.get("intent") is Dictionary else ""
	if production != null and not tool_id.is_empty() and production.tool_reserved(tool_id,excluding,observed): return Data.reject("TOOL_RESERVED")
	for other in (context.facts.call() if observed==null else observed.staged).get("actors",[]):
		if other.id != a.id and other.get("intent") is Dictionary and other.intent.get("owner") == "terrain" and other.intent.get("tool_id") == tool_id and not tool_id.is_empty(): return Data.reject("TOOL_RESERVED")
	if not Data.integer(edit.get("material",2)): return Data.reject("UNKNOWN_MATERIAL")
	var material := int(edit.get("material",2))
	if operation != "dig" and material not in [2,3,6]: return Data.reject("UNKNOWN_MATERIAL")
	if operation == "level":
		if not edit.get("area",{}) is Dictionary: return Data.reject("INVALID_TERRAIN_EDIT")
		var area: Dictionary = edit.get("area",{})
		var height: Variant = edit.get("height")
		if not area.has_all(["minI","maxI","minK","maxK"]) or not area.values().all(Data.integer) or not (height is int or height is float) or not is_finite(float(height)) or absf(float(height)/s-roundf(float(height)/s))>0.0000001: return Data.reject("INVALID_TERRAIN_EDIT")
		var target := roundi(float(height)/s)
		if target <= cfg.minCellY or target >= cfg.maxCellY or area.maxI <= area.minI or area.maxK <= area.minK or (area.maxI-area.minI)*(area.maxK-area.minK)>cfg.maxEditCells: return Data.reject("INVALID_TERRAIN_EDIT")
		if float(qualities.get("shovel",0)) <= 0: return Data.reject("MISSING_TOOL")
		cells.clear()
		for z in range(int(area.minK),int(area.maxK)):
			for x in range(int(area.minI),int(area.maxI)):
				var top: Variant = world.surface_height((x+0.5)*s,(z+0.5)*s)
				if top == null: return Data.reject("UNKNOWN_CELL")
				var current := roundi(float(top)/s)
				for y in range(mini(current,target),maxi(current,target)):
					cells.append({"x":x,"y":y,"z":z,"_after":material if y<target else 0})
					if cells.size()>cfg.maxEditCells: return Data.reject("EDIT_TOO_LARGE")
	if cells.is_empty() or cells.size()>cfg.maxEditCells: return Data.reject("INVALID_TERRAIN_EDIT")
	var seen := {}
	var changes: Array = []
	var delta := {}
	var position := Vector3(float(a.x),float(a.y),float(a.z))
	var hand:Vector3=position+Vector3(0,1.2,0)
	var contacts:Array=[]
	var sight := EditSight.new()
	sight.world = world
	if operation in ["level","dig"]:
		for c in cells:
			if not c is Dictionary: return Data.reject("INVALID_TERRAIN_EDIT")
			var point := {"x":c.get("x",c.get("i")),"y":c.get("y",c.get("j")),"z":c.get("z",c.get("k"))}
			if not Data.vec(point) or not point.values().all(Data.integer): return Data.reject("INVALID_TERRAIN_EDIT")
			if operation=="dig" or c._after==0: sight.removed[Data.key(Vector3i(point.x,point.y,point.z))] = true
	for c in cells:
		if not c is Dictionary: return Data.reject("INVALID_TERRAIN_EDIT")
		var p := {"x":c.get("x",c.get("i")),"y":c.get("y",c.get("j")),"z":c.get("z",c.get("k"))}
		if not Data.vec(p) or not p.values().all(Data.integer): return Data.reject("INVALID_TERRAIN_EDIT")
		var cell := Vector3i(p.x,p.y,p.z)
		var id := Data.key(cell)
		if seen.has(id): return Data.reject("DUPLICATE_CELL")
		seen[id] = true
		if cell.y <= cfg.minCellY or cell.y >= cfg.maxCellY: return Data.reject("HEIGHT_LIMIT")
		if not world.is_cell_known(cell.x,cell.y,cell.z): return Data.reject("UNKNOWN_CELL")
		if not world.is_cell_resident(cell.x,cell.y,cell.z): return Data.reject("UNLOADED_CELL","目标地形尚未加载")
		var minp := {"x":cell.x*s,"y":cell.y*s,"z":cell.z*s}
		var maxp := {"x":minp.x+s,"y":minp.y+s,"z":minp.z+s}
		var volume := {"min":minp,"max":maxp}
		var center := Vector3((cell.x+0.5)*s,(cell.y+0.5)*s,(cell.z+0.5)*s)
		var region: Dictionary = world.region_at({"x":center.x,"y":center.y,"z":center.z})
		if region.is_empty(): return Data.reject("WRONG_REGION")
		if region.id!=a.regionId and not Data.is_continuous_outdoor_generator(str(world.identity().generatorVersion)):return Data.reject("WRONG_REGION")
		var permitted := false
		for area in region.editAreas:
			if operation in area.operations and minp.x >= area.bounds.min.x and maxp.x <= area.bounds.max.x and minp.z >= area.bounds.min.z and maxp.z <= area.bounds.max.z and minp.y >= maxf(area.bounds.min.y,area.minY) and maxp.y <= minf(area.bounds.max.y,area.maxY): permitted = true
		if not permitted: return Data.reject("PROTECTED_TERRAIN")
		# Broad rejection only. Exact reach below is to a real visible face from
		# the same 1.2m operational hand/chest origin used by B, never foot→centre.
		var closest:Vector3=hand.clamp(center-Vector3.ONE*s*0.5,center+Vector3.ONE*s*0.5)
		if hand.distance_to(closest)>float(cfg.maxReach)+0.000001:return Data.reject("UNREACHABLE","实际格面超出手部触及距离")
		var before: int = world.cell_at(cell.x,cell.y,cell.z)
		var after := int(c._after) if operation == "level" else (0 if operation == "dig" else material)
		if before == after: continue
		if after == 0 and not Data.MATERIALS[before].diggable: return Data.reject("PROTECTED_TERRAIN")
		if operation == "fill" and before != 0: return Data.reject("CELL_OCCUPIED")
		var required := str(Data.MATERIALS[before if after == 0 else after].get("tool",""))
		if not required.is_empty() and float(qualities.get(required,0))<=0: return Data.reject("MISSING_TOOL")
		for e in world.entities_in_bounds({"min":{"x":minp.x,"y":minp.y-s,"z":minp.z},"max":{"x":maxp.x,"y":maxp.y+s,"z":maxp.z}}):
			if after != 0 and e.get("blocksTerrain",true) and Data.intersects(e.bounds,volume): return Data.reject("ENTITY_OCCUPIED")
			for support in e.get("supportBounds",[]):
				var support_volume: Dictionary = support.duplicate(true)
				support_volume.min.y -= s
				if after == 0 and Data.intersects(support_volume,volume): return Data.reject("FOUNDATION_SUPPORT")
			if after == 0 and e.get("blocksTerrain",true):
				# Legacy beds/objects need not carry explicit supportBounds. Match
				# the existing terrain rule instead of leaving them floating.
				var foot := {"min":{"x":e.bounds.min.x,"y":e.bounds.min.y-s,"z":e.bounds.min.z},"max":{"x":e.bounds.max.x,"y":e.bounds.min.y+0.001,"z":e.bounds.max.z}}
				if Data.intersects(foot,volume): return Data.reject("ENTITY_SUPPORT")
		sight.target = id
		var contact:Dictionary=_cell_contact(sight if operation in ["level","dig"] else world,hand,cell,after==0,a,str(region.id))
		if not contact.ok:return contact
		contacts.append(contact)
		for pair in [[before,1.0],[after,-1.0]]:
			var item := str(Data.MATERIALS[pair[0]].get("item",""))
			if not item.is_empty(): delta[item] = float(delta.get(item,0))+pair[1]*s*s*s
		changes.append({"op":"voxel.set","cell":p,"before":before,"after":after})
	if changes.is_empty(): return Data.reject("NO_CHANGE")
	var pending := {}
	for change in changes: pending[Data.key(Vector3i(change.cell.x,change.cell.y,change.cell.z))] = change.after
	for change in changes:
		if change.after == 0: continue
		var below := Vector3i(change.cell.x,change.cell.y-1,change.cell.z)
		if not Data.material_blocks(int(pending.get(Data.key(below),world.cell_at(below.x,below.y,below.z))),"support"): return Data.reject("NO_SUPPORT")
	for item in delta:
		if not Definitions.quantity_valid(item,absf(float(delta[item]))):return Data.reject("INVALID_MATERIAL_ITEM",str(item))
		if float(a.pack.get(item,0))+float(delta[item]) < -0.000001: return Data.reject("NO_MATERIAL")
		if float(delta[item]) < 0 and production != null and float(a.pack.get(item,0))+float(delta[item])+0.000001 < (production.reserved("pack:"+str(a.id),str(item),excluding) if observed==null else production.work_reserved("pack:"+str(a.id),str(item),excluding,observed)): return Data.reject("MATERIAL_RESERVED")
	var stamina := changes.size()*(1.0 if not selected.is_empty() else 2.0)
	if observed==null and float(a.get("stamina",0))<stamina: return Data.reject("EXHAUSTED")
	return {"ok":true,"code":"OK","world_changes":changes,"material_delta":delta,"stamina":stamina,"wear":changes.size()*0.1 if not selected.is_empty() else 0.0,"tool_id":tool_id,"duration":changes.size()*(1.5 if not selected.is_empty() else 4.0),"contacts":contacts}

func _cell_contact(query:RefCounted,hand:Vector3,cell:Vector3i,removing:bool,actor:Dictionary,target_region:String)->Dictionary:
	var world:RefCounted=context.world
	var max_reach:float=float(world.config().maxReach)
	var p:Dictionary={"x":cell.x,"y":cell.y,"z":cell.z}
	var within:=false;var unloaded:=false
	for face:Dictionary in Queries.exposed_face_points(query,cell,hand):
		var point:Vector3=face.point;var normal:Vector3=face.normal
		if hand.distance_to(point)>max_reach+0.000001:continue
		within=true
		var endpoint:Vector3=point-normal*0.0001
		var hit:Dictionary=Queries.segment(query,hand,endpoint,{"purpose":"contact","require_resident":true})
		if hit.get("unknown",false):unloaded=unloaded or hit.get("code")=="UNLOADED_CELL";continue
		if removing and (hit.is_empty() or not Data.json_equal(hit.get("cell"),p) or hit.get("normal",Vector3.ZERO)==Vector3.ZERO):continue
		if not removing and not hit.is_empty() and not Data.json_equal(hit.get("cell"),p):continue
		if not hit.is_empty():
			point=hand+(endpoint-hand).normalized()*float(hit.distance)
			normal=hit.normal
			endpoint=point-normal*0.0001
		if hand.distance_to(point)>max_reach+0.000001:continue
		if target_region!=actor.regionId:
			var from:Dictionary={"x":hand.x,"y":hand.y,"z":hand.z,"regionId":actor.regionId,"buildingId":actor.get("buildingId"),"storeyId":actor.get("storeyId")}
			var to:Dictionary={"x":endpoint.x,"y":endpoint.y,"z":endpoint.z,"regionId":target_region,"buildingId":null,"storeyId":null}
			var continuous:Dictionary=world.continuous_outdoor_contact(from,to)
			if not continuous.ok:return continuous
		# Use both partitions' ORIGINAL wall/entity LOS. DDA above alone uses the
		# projected removals, never hides an unselected cell, wall or unknown.
		var visible_end:Vector3=point-(point-hand).normalized()*0.001
		if not _structures_clear(hand,visible_end,[str(actor.regionId),target_region]):continue
		return {"ok":true,"code":"OK","cell":p,"target_id":"terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],"point":{"x":point.x,"y":point.y,"z":point.z},"normal":{"x":normal.x,"y":normal.y,"z":normal.z},"distance":hand.distance_to(point),"world_revision":world.get_revision(),"from_region_id":actor.regionId,"to_region_id":target_region}
	if unloaded:return Data.reject("UNLOADED_CELL","触及路径经过尚未加载体素")
	return Data.reject("OCCLUDED" if within else "UNREACHABLE","实际格面被遮挡或没有已知露出面" if within else "没有手部距离内的已知露出格面")

func _structures_clear(from:Vector3,to:Vector3,regions:Array)->bool:
	var spatial:Variant=context.get("spatial")
	if spatial==null or not spatial.has_method("current_space"):return true
	var space:RefCounted=spatial.current_space();var checked:Dictionary={}
	for region:String in regions:
		if checked.has(region):continue
		checked[region]=true
		for piece:Dictionary in space.nearby_pieces(region,AABB(from.min(to),from.max(to)-from.min(to))):
			for box:AABB in space.sight_boxes.get(piece.id,[]):
				if box.intersects_segment(from,to)!=null:return false
	for entity:Dictionary in space.solid_entities:
		if entity.regionId not in checked:continue
		var lo:=Vector3(entity.bounds.min.x,entity.bounds.min.y,entity.bounds.min.z)
		var hi:=Vector3(entity.bounds.max.x,entity.bounds.max.y,entity.bounds.max.z)
		if AABB(lo,hi-lo).intersects_segment(from,to)!=null:return false
	return true

func actor_work_projection(actor_id:String)->Dictionary:
	# Read the sole persisted intent and current legal edit. Presentation never
	# advances work, reserves anything, settles cells or trusts an old hit face.
	if context.is_empty():return {}
	var a:Dictionary=context.actor.call(actor_id);var intent:Variant=a.get("intent")
	if not intent is Dictionary or intent.get("owner")!="terrain" or not validate_intent(intent,a).ok:return {}
	var result:Dictionary={"owner":"terrain","kind":"terrain","operation":str(intent.request.payload.get("edit",intent.request.payload).get("operation","dig")),"tool_id":intent.tool_id,"progress_seconds":intent.elapsed,"duration_seconds":intent.duration,"effective_work":false,"paused_reason":""}
	var host:Variant=_runtime_host.get_ref() if _runtime_host!=null else null
	if host!=null and host.is_paused():result.paused_reason="paused";return result
	if context.get("region_is_detailed") is Callable and not context.region_is_detailed.call(str(a.regionId)):result.paused_reason="region_paused";return result
	if not intent.get("held",true):result.paused_reason="held";return result
	# Exact same committed facts/cells may be painted several frames between
	# fixed steps. Validate the edit once per Runtime+world revision, never on
	# a wall-clock TTL; pause/held/readiness gates above still run every read.
	if host!=null:
		var revisions:Array=[context.world.get_revision(),host.get_revision()]
		if revisions!=_work_projection_revisions:_work_projection_cache.clear();_work_projection_revisions=revisions
		if _work_projection_cache.has(actor_id):return _work_projection_cache[actor_id].duplicate(true)
	result=_work_contact_projection(a,intent,result)
	if host!=null:_work_projection_cache[actor_id]=result.duplicate(true)
	return result

func _work_contact_projection(a:Dictionary,intent:Dictionary,result:Dictionary)->Dictionary:
	var plan:Dictionary=_plan(intent.request,true)
	if not plan.ok:result.paused_reason=str(plan.get("code","UNAVAILABLE"));return result
	var world:RefCounted=context.world;var hand:=Vector3(a.x,a.y,a.z)+Vector3(0,1.2,0)
	for change:Dictionary in plan.world_changes:
		var c:Dictionary=change.cell;var cell:=Vector3i(c.x,c.y,c.z)
		var center:=Vector3(cell)+Vector3.ONE*0.5;center*=float(world.config().cellSize)
		var region:Dictionary=world.region_at({"x":center.x,"y":center.y,"z":center.z})
		if region.is_empty():continue
		# A level batch may validate hidden later cells with EditSight. The
		# visible tool contact must instead hit the ORIGINAL current real world.
		var hit:Dictionary=_cell_contact(world,hand,cell,change.after==0,a,str(region.id))
		if not hit.ok:continue
		result.contact={"position":[hit.point.x,hit.point.y,hit.point.z],"normal":[hit.normal.x,hit.normal.y,hit.normal.z]}
		result.target_id=hit.target_id;result.cell=hit.cell.duplicate(true);result.world_revision=hit.world_revision
		result.effective_work=float(intent.elapsed)>0.0
		if not result.effective_work:result.paused_reason="not_started"
		return result
	result.paused_reason="NO_VISIBLE_CONTACT"
	return result

func prepare(request: Dictionary) -> Dictionary:
	if request.get("kind") == "held":
		if context.is_empty(): return Data.reject("MISSING_WORLD")
		if not request.get("payload",{}) is Dictionary or not request.get("payload",{}).get("held",false) is bool: return Data.reject("INVALID_TERRAIN_EDIT")
		var actor: Dictionary = context.actor.call(str(request.get("actor_id","")))
		if not actor.get("intent") is Dictionary or actor.intent.get("owner") != "terrain": return Data.reject("NO_TERRAIN_INTENT")
		var updated := actor.duplicate(true)
		updated.intent.held = bool(request.get("payload",{}).get("held",false))
		return {"ok":true,"world_changes":[],"fact_changes":[{"collection":"actors","id":actor.id,"before":actor,"after":updated}],"duration":0.0,"events":[]}
	var plan := _plan(request)
	if not plan.ok: return plan
	var a: Dictionary = context.actor.call(str(request.actor_id))
	var next := a.duplicate(true)
	# A persists the intent in the sole actor fact. B's shared reservation query
	# can consume the same id/source_id/cost contract as care/radio holds. Store
	# only net input (never reserve an output or a gross amount already yielded
	# by this atomic batch); nothing is deducted before the final CAS commit.
	var cost := {}
	for item in plan.material_delta:
		if float(plan.material_delta[item])<0: cost[item]=-float(plan.material_delta[item])
	next.intent = {"schema_version":1,"id":str(request.get("command_id","preview")),"source_id":"pack:"+str(a.id),"cost":cost,"owner":"terrain","kind":"terrain","request":request.duplicate(true),"elapsed":0.0,"duration":plan.duration,"tool_id":plan.tool_id,"held":bool(request.get("payload",{}).get("held",true))}
	next.activity = "改造地形"
	return {"ok":true,"code":"OK","world_changes":[],"fact_changes":[{"collection":"actors","id":a.id,"before":a,"after":next}],"duration":plan.duration,"destination":{},"events":[]}

func advance(dt: float) -> Dictionary:
	if not is_finite(dt) or dt<=0 or dt>1: return Data.reject("INVALID_STEP")
	# Observe the latest isolated actors every STEP, not the stocks/quests and
	# their second staged copy. Most steps contain no terrain write at all.
	# Held intents still validate: malformed paused work must be interrupted.
	var host:Variant=_runtime_host.get_ref() if _runtime_host!=null else null
	var actors:Array=host.actor_states() if host!=null and host.has_method("actor_states") else context.facts.call().get("actors",[]) if context.get("facts") is Callable else []
	var writes:bool=false
	for actor:Dictionary in actors:
		var active:Variant=actor.get("intent")
		if not active is Dictionary or active.get("owner")!="terrain":continue
		if active.get("held",true) or not validate_intent(active,actor).ok:writes=true;break
	if not writes:
		# Exact empty Draft result, including a retired weak-host rejection.
		# Nothing is retained across steps or borrowed for mutation.
		if context.get("available") is Callable and not context.available.call():return {"ok":false,"code":"UNAVAILABLE","reason":"事务所属运行时已关闭","world_changes":[],"fact_changes":[],"events":[]}
		return {"ok":true,"code":"OK","reason":null,"world_changes":[],"fact_changes":[],"duration":0.0,"destination":{},"events":[]}
	# All writing paths keep the original full isolated Draft and final CAS.
	var tx := Draft.new(context)
	for a in tx.staged.get("actors",[]):
		if not a.get("intent") is Dictionary or a.intent.get("owner") != "terrain": continue
		var intent: Dictionary = a.intent
		if not validate_intent(intent,a,tx.staged).ok:
			a.intent=null;a.activity="改造中断：行动数据无效";continue
		if not intent.get("held",true): continue
		if float(a.get("hp",0))<=0 or (a.id != "player" and not a.get("relationship",{}).get("consent",false)):
			a.intent = null
			a.activity = "行动中断"
			continue
		intent.elapsed = minf(float(intent.duration),float(intent.elapsed)+dt)
		if float(intent.elapsed)+0.000001 < float(intent.duration): continue
		var plan := _plan(intent.request,true)
		if not plan.ok:
			a.intent = null
			a.activity = "改造中断："+str(plan.get("reason",plan.code))
			continue
		if not tx.stock_delta("pack:"+str(a.id),plan.material_delta): return Data.reject("NO_MATERIAL")
		if not plan.tool_id.is_empty():
			var production: Dictionary = tx.extension("r3:production")
			var tool: Dictionary = Draft.find(production.get("tools",[]),plan.tool_id)
			if tool.is_empty(): return Data.reject("MISSING_TOOL")
			if preload("res://scripts/runtime/tool_wear_policy.gd").enabled(context.world):tool.durability = maxf(0,float(tool.durability)-float(plan.wear))
		a.stamina = maxf(0,float(a.stamina)-float(plan.stamina))
		a.intent = null
		a.activity = "改造完成"
		tx.extra.append_array(plan.world_changes)
		tx.events.append({"kind":"terrain.completed","actor_id":a.id,"cells":plan.world_changes.size()})
		# One completion at a time; next actor revalidates against committed terrain.
		break
	return tx.result()

func prepare_zone_work_in(tx:RefCounted,job:Dictionary,actor_id:String)->Dictionary:
	# B has already paid effective labor/stamina/tool wear in this SAME Draft.
	# Reuse every original terrain face, permission, support/material and CAS
	# check against the current staged actor/tool. No second intent or commit.
	if job.get("kind") not in ["terrain_dig","terrain_fill"]:return Data.reject("INVALID_BATCH_WORK")
	if not job.get("cell") is Dictionary or not job.cell.has_all(["x","y","z"]) or not job.cell.values().all(Data.integer) or not job.get("tool_ids",[]) is Array or not Data.integer(job.get("material",2)):return Data.reject("INVALID_BATCH_WORK")
	var operation:String="dig" if job.kind=="terrain_dig" else "fill"
	var material:int=context.world.cell_at(job.cell.x,job.cell.y,job.cell.z) if operation=="dig" else int(job.get("material",2))
	if not Data.MATERIALS.has(material):return Data.reject("UNKNOWN_MATERIAL")
	var tool_id:String=""
	for id:Variant in job.get("tool_ids",[]):
		var tool:Dictionary=Draft.find(tx.extension("r3:production",{}).get("tools",[]),str(id))
		var need:String=str(Data.MATERIALS[material].get("tool",""))
		if need.is_empty():need="shovel"
		if float(tool.get("qualities",_tool_definitions.get(tool.get("kind"),{}).get("qualities",{})).get(need,0))>0:tool_id=str(id);break
	if tool_id.is_empty():return Data.reject("MISSING_TOOL")
	return _plan({"kind":"terrain","actor_id":actor_id,"payload":{"edit":{"operation":operation,"cells":[job.cell.duplicate(true)],"material":int(job.get("material",2))},"tool_id":tool_id}},true,tx)
