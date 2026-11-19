extends RefCounted
## Persistent work plans, not resource creation, labor or an independent clock.
const Def=preload("res://scripts/planning/zone_definitions.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Context=preload("res://scripts/actions/domain_context.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Regional=preload("res://scripts/actions/regional_workforce.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const KEY="r34:zones"
const SCHEMA="afterglow-work-zones-v1"
var context:Dictionary={}
var _host:WeakRef
var _projection_revision:int=-1
var _projection_token:Dictionary={}
var _validated_token:Dictionary={}
var _projection_rows:Array=[]
var _projection_zones:Dictionary={}
var _completion_at:float=0.0

func configure(value:Dictionary)->void:
	context=Context.isolate(value)
	_projection_revision=-1;_projection_token.clear();_validated_token.clear();_projection_rows.clear();_projection_zones.clear()
	_completion_at=0.0
	if value.get("runtime") is RefCounted:_host=weakref(value.runtime)

static func initial()->Dictionary:
	return {"version":1,"revision":0,"zones":[]}

func _domain(name:String)->Variant:
	var host:Variant=_host.get_ref() if _host!=null else null
	return host.domain_service(name) if host!=null and host.has_method("domain_service") else null

func state(overrides:Dictionary={})->Dictionary:
	var value:Variant=overrides[KEY] if overrides.has(KEY) else context.world.extension(KEY)
	return value if value is Dictionary else initial()

func zone_records()->Array:
	return state().get("zones",[]).duplicate(true)

static func validate_state(value:Variant)->Dictionary:
	if not value is Dictionary or value.get("version")!=1 or not Def.integer(value.get("revision")) or int(value.revision)<0 or not value.get("zones") is Array or value.zones.size()>Def.MAX_ZONES:return Def.bad("INVALID_ZONE_STATE","区域规划存档格式无效，原存档保留")
	var seen:Dictionary={};var total:int=0
	for zone:Variant in value.zones:
		if not zone is Dictionary or not Data.valid_id(zone.get("id")) or seen.has(zone.id) or not Def.KINDS.has(zone.get("kind")) or not Data.valid_id(zone.get("region_id")) or not zone.get("cells") is Array or not zone.get("enabled") is bool or not Def.integer(zone.get("revision")) or int(zone.revision)<1:return Def.bad("INVALID_ZONE_STATE","区域身份、类型或状态无效")
		seen[zone.id]=true
		if not zone.get("name","") is String or str(zone.get("name","")).length()>64 or not zone.get("station_id","") is String:return Def.bad("INVALID_ZONE_STATE","区域名称或工作站无效")
		var object_order:bool=zone.has("region_ids")
		if not Def.bounds_check(zone.get("bounds"),Def.MAX_ORDER_CELLS if object_order else Def.MAX_ZONE_CELLS).ok or not Def.policy_check(zone.get("policy")).ok:return Def.bad("INVALID_ZONE_STATE","区域边界或策略无效")
		if object_order:
			var ids:Variant=zone.region_ids
			var targets:Variant=zone.get("target_ids",[])
			if Def.target_mode(zone).is_empty() or not ids is Array or ids.is_empty() or ids.size()>Def.MAX_ORDER_REGIONS or ids[0]!=zone.region_id or not ids.all(Data.valid_id) or ids.size()!=_unique(ids) or not targets is Array or targets.size()>Def.MAX_ORDER_TARGETS or not targets.all(Data.valid_id) or targets.size()!=_unique(targets):return Def.bad("INVALID_ZONE_STATE","派工范围或目标身份无效")
			if zone.has("completed") and not zone.completed is bool:return Def.bad("INVALID_ZONE_STATE","派工完成状态无效")
		if zone.cells.size()>Def.MAX_ZONE_CELLS or (zone.cells.is_empty() and zone.enabled and not object_order):return Def.bad("INVALID_ZONE_STATE","区域有效格数无效")
		var cells:Dictionary={}
		for cell:Variant in zone.cells:
			if not Def.valid_cell(cell) or int(cell.x)<int(zone.bounds.x0) or int(cell.x)>=int(zone.bounds.x1) or int(cell.z)<int(zone.bounds.z0) or int(cell.z)>=int(zone.bounds.z1):return Def.bad("INVALID_ZONE_STATE","规划格超出区域边界")
			# Coordinates were fully range/integer checked above. A local native
			# integer vector avoids allocating formatted strings for schema-only
			# duplicate detection; persisted cell keys and zone IDs stay unchanged.
			var key:Vector3i=Vector3i(int(cell.x),int(cell.y),int(cell.z))
			if cells.has(key):return Def.bad("INVALID_ZONE_STATE","区域包含重复地形格")
			cells[key]=true
		total+=zone.cells.size()
	if total>Def.MAX_TOTAL_CELLS:return Def.bad("ZONE_CAPACITY","区域总格数超过当前规划容量")
	return {"ok":true,"code":"OK"}

static func _unique(values:Array)->int:
	var seen:Dictionary={}
	for value:Variant in values:seen[value]=true
	return seen.size()

func authority_token()->Dictionary:
	# The token is assigned by successful authority commits/load, never by
	# persisted zone metadata. Draft WorldView has no token and gets no cache.
	return context.world.extension_token(KEY) if context.world.has_method("extension_token") else {}

func validate_extensions(_facts:Dictionary,overrides:Dictionary={})->Dictionary:
	if overrides.has(KEY):return validate_state(overrides[KEY])
	if not context.world.has_extension(KEY):return {"ok":true,"code":"OK"}
	var token:Dictionary=authority_token()
	if not token.is_empty() and token==_validated_token:return {"ok":true,"code":"OK"}
	var checked:Dictionary=validate_state(context.world.extension(KEY))
	if checked.ok:_validated_token=token.duplicate()
	return checked

func _gate(actor_id:String)->Dictionary:
	var actor:Dictionary=context.actor.call(actor_id)
	if actor_id!="player" or actor.is_empty() or float(actor.get("hp",0))<=0:return Def.bad("ZONE_NOT_AUTHORIZED","当前角色不能管理区域")
	return {"ok":true,"code":"OK"}

func preview(spec:Dictionary)->Dictionary:
	return _preview(spec,false)

func _preview(spec:Dictionary,committing:bool)->Dictionary:
	var gate:Dictionary=_gate("player")
	if not gate.ok:return gate
	if not Def.KINDS.has(spec.get("kind")) or not Data.valid_id(spec.get("region_id")):return Def.bad("INVALID_ZONE_SPEC","请选择区域用途和地区")
	var mode:String=Def.target_mode(spec) if spec.get("operation","create")=="create" else ""
	var checked:Dictionary=Def.bounds_check(spec.get("bounds"),Def.MAX_ORDER_CELLS if not mode.is_empty() else Def.MAX_ZONE_CELLS)
	if not checked.ok:return checked
	var policy:Dictionary=Def.policy_check(spec.get("policy",{}))
	if not policy.ok:return policy
	if spec.get("operation")=="erase":
		var original:Dictionary=Draft.find(state().zones,str(spec.get("id","")))
		if original.is_empty() or original.region_id!=spec.region_id:return Def.bad("UNKNOWN_ZONE","请选择同一地区的原工作区")
		var erased:Array=[]
		for cell:Dictionary in original.cells:
			if int(cell.x)>=int(spec.bounds.x0) and int(cell.x)<int(spec.bounds.x1) and int(cell.z)>=int(spec.bounds.z0) and int(cell.z)<int(spec.bounds.z1):erased.append(cell.duplicate(true))
		return {"ok":not erased.is_empty(),"code":"OK" if not erased.is_empty() else "NO_ZONE_CELLS","reason":"" if not erased.is_empty() else "选区内没有原规划格","cells":erased,"excluded":[],"valid_count":erased.size(),"excluded_count":0,"estimate":{},"reasons":[],"world_revision":context.world.get_revision()}
	if context.world.region(str(spec.region_id)).is_empty():return Def.bad("UNKNOWN_ZONE_REGION","请先探索目标地区")
	if not mode.is_empty():return _preview_order(spec,mode,committing)
	var ecology:Variant=_domain("ecology")
	if ecology==null or not ecology.has_method("preview_zone"):return Def.bad("ZONE_TERRAIN_UNAVAILABLE","区域土地检查尚未接通")
	var result:Variant=ecology.preview_zone(spec.duplicate(true))
	if not result is Dictionary or not result.get("ok") is bool:return Def.bad("INVALID_ZONE_PREVIEW","土地检查未返回有效结果")
	if not result.ok:return result
	if not result.get("cells") is Array:return Def.bad("INVALID_ZONE_PREVIEW","土地检查缺少真实有效格")
	var valid:Array=[];var excluded:Array=result.get("excluded",[]).duplicate(true);var occupied:Dictionary={}
	for other:Dictionary in state().zones:
		if not other.get("enabled",false) or other.get("id")==spec.get("id") or other.region_id!=spec.region_id or other.kind=="patrol" or spec.kind=="patrol":continue
		if _ground_collection(other) or _ground_collection(spec):continue
		for cell:Dictionary in other.cells:occupied[Def.cell_key(cell)]=other.id
	var seen:Dictionary={}
	for cell:Variant in result.cells:
		if not Def.valid_cell(cell) or int(cell.x)<int(spec.bounds.x0) or int(cell.x)>=int(spec.bounds.x1) or int(cell.z)<int(spec.bounds.z0) or int(cell.z)>=int(spec.bounds.z1):return Def.bad("INVALID_ZONE_PREVIEW","土地检查返回范围外地形格")
		var key:String=Def.cell_key(cell)
		if seen.has(key):return Def.bad("INVALID_ZONE_PREVIEW","土地检查返回重复地形格")
		seen[key]=true
		if occupied.has(key):excluded.append({"cell":cell.duplicate(true),"code":"ZONE_OVERLAP","reason":"与已有工作区重叠","zone_id":occupied[key]})
		else:valid.append(cell.duplicate(true))
	if valid.is_empty():return Def.bad("NO_VALID_ZONE_CELLS","选区内没有可安排工作的土地，请查看冲突或缩小范围")
	if valid.size()>Def.MAX_ZONE_CELLS:return Def.bad("ZONE_TOO_LARGE","单区规划格数过多，请分区")
	var estimate: Dictionary = result.get("estimate", {}).duplicate(true)
	if spec.kind == "clear" and spec.get("policy", {}).get("mode") == "player_clear":
		var targets: Dictionary = ecology.player_clear_targets(spec.merged({"cells": valid}, true))
		estimate.trees = targets.trees.size()
		estimate.stumps = targets.stumps.size()
	return {"ok":true,"code":"OK","schema":SCHEMA,"cells":valid,"excluded":excluded,"valid_count":valid.size(),"excluded_count":excluded.size(),"estimate":estimate,"reasons":result.get("reasons",[]).duplicate(true),"world_revision":context.world.get_revision()}

func _preview_order(spec:Dictionary,mode:String,committing:bool)->Dictionary:
	var b:Dictionary=spec.bounds;var size:float=context.world.config().cellSize
	var regions:Array=[str(spec.region_id)];var waiting:Array=[];var ready:Dictionary={}
	var min_y:float=INF;var max_y:float=-INF
	for region:Dictionary in context.world.regions():
		var box:Dictionary=region.bounds
		if float(b.x0)*size>=float(box.max.x) or float(b.x1)*size<=float(box.min.x) or float(b.z0)*size>=float(box.max.z) or float(b.z1)*size<=float(box.min.z):continue
		if not regions.has(region.id):regions.append(region.id)
		min_y=minf(min_y,float(box.min.y));max_y=maxf(max_y,float(box.max.y))
		if not context.get("region_is_detailed") is Callable or context.region_is_detailed.call(region.id):ready[region.id]=true
		else:waiting.append(region.id)
	if not ready.has(spec.region_id) and not waiting.has(spec.region_id):return Def.bad("ZONE_ANCHOR_OUTSIDE","工作范围需要覆盖起始地区")
	if regions.size()>Def.MAX_ORDER_REGIONS:return Def.bad("ZONE_TOO_MANY_REGIONS","一次最多跨 %d 个地区，请缩小范围" % Def.MAX_ORDER_REGIONS)
	var cells:Array=[];var visible_count:int=0;var targets:Array=[];var seen:Dictionary={}
	var bounds:Dictionary=G.json_box(AABB(Vector3(float(b.x0)*size,min_y,float(b.z0)*size),Vector3(float(b.x1-b.x0)*size,max_y-min_y,float(b.z1-b.z0)*size)))
	var ecology:Variant=_domain("ecology")
	if mode=="harvest_only" and ecology==null:return Def.bad("ZONE_TERRAIN_UNAVAILABLE","采伐服务尚未就绪")
	for entity:Dictionary in context.world.entities_in_any_bounds([bounds]):
		if not regions.has(entity.regionId) or (not ready.has(entity.regionId) and not committing) or not Def.contains_xz(b,G.location(entity),size):continue
		if mode=="harvest_only" and not ecology.harvest_target(entity,spec.policy):continue
		if mode=="collect_ground" and (entity.kind!="container" or not entity.get("data",{}).get("dropped",false)):continue
		if mode=="collect_ground":
			var stock:Dictionary=context.stock.call(entity.id)
			var workers:Array=spec.policy.get("worker_ids",[])
			var worker:Dictionary=context.actor.call(str(workers[0])) if workers.size()==1 else {}
			if stock.get("items",{}).is_empty() or not stock.get("searched",false) or worker.is_empty() or not Regional.Factory.permitted(worker,stock.get("owner")):continue
		if mode=="harvest_only":targets.append(entity.id)
		if max(targets.size(),visible_count)>Def.MAX_ORDER_TARGETS:return Def.bad("ZONE_TOO_MANY_TARGETS","目标太多，请缩小框选范围")
		if not ready.has(entity.regionId):continue
		visible_count+=1
		if visible_count>Def.MAX_ORDER_TARGETS:return Def.bad("ZONE_TOO_MANY_TARGETS","目标太多，请缩小框选范围")
		var p:Dictionary=G.location(entity)
		var cell:Dictionary={"x":floori(float(p.x)/size),"y":roundi(float(p.y)/size),"z":floori(float(p.z)/size)}
		var key:String=Def.cell_key(cell)
		if not seen.has(key):cells.append(cell);seen[key]=true
	var standing:bool=spec.get("policy",{}).get("standing_order",false)
	var result:Dictionary={"ok":standing or visible_count>0 or not waiting.is_empty(),"code":"OK","schema":SCHEMA,"cells":cells,"excluded":[],"valid_count":visible_count,"excluded_count":0,"target_count":visible_count,"target_mode":mode,"standing_order":standing,"waiting_count":waiting.size(),"region_count":regions.size(),"region_ids":regions,"world_revision":context.world.get_revision()}
	if committing and mode=="harvest_only" and not standing:result.target_ids=targets
	if not result.ok:
		result.code="NO_ZONE_TARGETS";result.reason="范围内没有可砍的树" if mode=="harvest_only" else "范围内没有可捡的地面物资"
	return result

static func _ground_collection(spec:Dictionary)->bool:
	return spec.get("kind")=="stockpile" and spec.get("policy",{}).get("mode")=="collect_ground"

func availability(request:Dictionary)->Dictionary:
	var result:Dictionary=prepare(request)
	if result.get("ok",false):result.world_changes=[];result.fact_changes=[];result.events=[]
	return result

func prepare(request:Dictionary)->Dictionary:
	var gate:Dictionary=_gate(str(request.get("actor_id","player")))
	if not gate.ok:return gate
	var kind:String=str(request.get("kind",""));var payload:Variant=request.get("payload",{})
	if not payload is Dictionary:return Def.bad("INVALID_ZONE_COMMAND","区域操作参数无效")
	var tx:=Draft.new(context)
	var after:Dictionary=tx.extension(KEY,initial())
	var zone:Dictionary=Draft.find(after.zones,str(request.get("target_id","")))
	if kind=="zone.create":
		if after.zones.size()>=Def.MAX_ZONES:return Def.bad("ZONE_CAPACITY","工作区数量已达当前上限")
		var raw:Variant=payload.get("spec",{})
		if not raw is Dictionary:return Def.bad("INVALID_ZONE_SPEC","区域规划参数无效")
		var spec:Dictionary=raw.duplicate(true)
		var id:String=str(request.get("target_id",""))
		if id.is_empty():id="zone:"+str(request.get("command_id",""))
		if not Data.valid_id(id) or not Draft.find(after.zones,id).is_empty():return Def.bad("ZONE_ID_OCCUPIED","区域标识无效或已经存在")
		spec.id=id
		var collection:bool=_ground_collection(spec)
		if collection or (spec.get("kind")=="forestry" and spec.get("policy",{}).get("mode")=="harvest_only"):
			var workers:Variant=spec.policy.get("worker_ids",[])
			if not workers is Array or workers.size()!=1 or not Data.valid_id(workers[0]) or workers[0]=="player":return Def.bad("WORKER_REQUIRED","请选择一名同伴")
			var worker:Dictionary=tx.actor(str(workers[0]));var relationship:Dictionary=worker.get("relationship",{})
			if float(worker.get("hp",0))<=0:return Def.bad("WORKER_UNAVAILABLE","同伴目前无法行动")
			if not relationship.get("member",false) or not relationship.get("consent",false):return Def.bad("WORKER_UNAVAILABLE","同伴尚未同意工作")
			if collection:
				var receiver:Dictionary=tx.stock(str(spec.policy.get("target_stock_id","")))
				if not Regional.ground_receiver(context.world,worker,receiver):return Def.bad("RECEIVER_UNAVAILABLE","请选择已知且有权使用的接收仓库")
		var selected:Dictionary=_preview(spec,true)
		if not selected.ok:return selected
		var name:Variant=spec.get("name",Def.KINDS[spec.kind].name)
		var station:Variant=spec.get("station_id","")
		if not name is String or name.length()>64 or not station is String or (not station.is_empty() and not Data.valid_id(station)):return Def.bad("INVALID_ZONE_SPEC","工作区名称或工作站标识无效")
		var policy:Dictionary=Def.defaults(spec.kind);policy.merge(spec.get("policy",{}),true)
		zone={"id":id,"name":name,"kind":spec.kind,"region_id":spec.region_id,"bounds":spec.bounds.duplicate(true),"cells":selected.cells,"policy":policy,"station_id":station,"enabled":true,"revision":1}
		if selected.has("region_ids"):
			zone.region_ids=selected.region_ids
			zone.target_ids=selected.get("target_ids",[])
		after.zones.append(zone)
	elif kind in ["zone.update","zone.policy"]:
		if zone.is_empty():return Def.bad("UNKNOWN_ZONE","这个工作区已经不存在")
		var patch:Variant=payload.get("patch",{})
		if not patch is Dictionary:return Def.bad("INVALID_ZONE_COMMAND","区域调整参数无效")
		if zone.has("region_ids") and (patch.has("bounds") or patch.has("append_bounds") or patch.has("policy")):return Def.bad("ZONE_ORDER_FIXED","请停止原任务，再框选新的范围")
		if zone.get("completed",false) and patch.get("enabled",false):return Def.bad("ZONE_ORDER_FIXED","这次工作已经完成，请重新安排")
		for key:Variant in patch:
			if key not in ["name","bounds","append_bounds","policy","station_id","enabled"]:return Def.bad("INVALID_ZONE_COMMAND","不能修改区域身份或直接写入地形格")
		if patch.has("bounds") and patch.has("append_bounds"):return Def.bad("INVALID_ZONE_COMMAND","一次操作不能同时替换和追加范围")
		if patch.has("name"):
			if not patch.name is String or patch.name.length()>64:return Def.bad("INVALID_ZONE_COMMAND","区域名称无效")
			zone.name=patch.name
		if patch.has("station_id"):
			if not patch.station_id is String or (not patch.station_id.is_empty() and not Data.valid_id(patch.station_id)):return Def.bad("INVALID_ZONE_COMMAND","工作站标识无效")
			zone.station_id=patch.station_id
		if patch.has("policy"):
			var pc:Dictionary=Def.policy_check(patch.policy)
			if not pc.ok:return pc
			zone.policy.merge(patch.policy,true)
		if patch.has("bounds"):
			var spec:Dictionary=zone.duplicate(true);spec.bounds=patch.bounds
			var selected:Dictionary=preview(spec)
			if not selected.ok:return selected
			zone.bounds=patch.bounds.duplicate(true);zone.cells=selected.cells
		if patch.has("append_bounds"):
			var spec:Dictionary=zone.duplicate(true);spec.bounds=patch.append_bounds
			var selected:Dictionary=preview(spec)
			if not selected.ok:return selected
			var union:Dictionary={"x0":mini(int(zone.bounds.x0),int(spec.bounds.x0)),"z0":mini(int(zone.bounds.z0),int(spec.bounds.z0)),"x1":maxi(int(zone.bounds.x1),int(spec.bounds.x1)),"z1":maxi(int(zone.bounds.z1),int(spec.bounds.z1))}
			var limit:Dictionary=Def.bounds_check(union)
			if not limit.ok:return limit
			var present:Dictionary={}
			for cell:Dictionary in zone.cells:present[Def.cell_key(cell)]=true
			for cell:Dictionary in selected.cells:
				if not present.has(Def.cell_key(cell)):zone.cells.append(cell);present[Def.cell_key(cell)]=true
			zone.bounds=union
		if patch.has("enabled"):
			if not patch.enabled is bool or (patch.enabled and zone.cells.is_empty() and not zone.has("region_ids")):return Def.bad("INVALID_ZONE_COMMAND","空工作区不能启用")
			zone.enabled=patch.enabled
		zone.revision+=1
	elif kind=="zone.erase":
		if zone.is_empty():return Def.bad("UNKNOWN_ZONE","这个工作区已经不存在")
		if zone.has("region_ids"):return Def.bad("ZONE_ORDER_FIXED","请停止原任务，再框选新的范围")
		var removed:Variant=payload.get("cells")
		if not removed is Array or removed.size()>Def.MAX_ZONE_CELLS:return Def.bad("INVALID_ZONE_COMMAND","请选择需要擦除的规划格")
		var keys:Dictionary={}
		for cell:Variant in removed:
			if not Def.valid_cell(cell):return Def.bad("INVALID_ZONE_COMMAND","擦除格无效")
			keys[Def.cell_key(cell)]=true
		var kept:Array=[]
		for cell:Dictionary in zone.cells:
			if not keys.has(Def.cell_key(cell)):kept.append(cell)
		zone.cells=kept;zone.enabled=zone.enabled and not kept.is_empty();zone.revision+=1
	elif kind=="zone.cancel":
		if zone.is_empty():return Def.bad("UNKNOWN_ZONE","这个工作区已经不存在")
		zone.enabled=false;zone.revision+=1
	else:return Def.bad("UNKNOWN_ZONE_COMMAND","未识别的区域操作")
	after.revision+=1
	var checked:Dictionary=validate_state(after)
	if not checked.ok:return checked
	tx.events.append({"kind":"zone-changed","zone_id":zone.id,"operation":kind,"at":float(context.clock.call())})
	var result:Dictionary=tx.result();result.zone_id=zone.id
	return result

func advance(_dt:float)->Dictionary:
	var now:float=float(context.clock.call())
	if now<_completion_at:return _idle()
	_completion_at=now+1.0
	var ecology:Variant=_domain("ecology")
	if ecology==null:return _idle()
	var done:Dictionary={}
	for zone:Dictionary in state().zones:
		if not zone.enabled or not zone.has("region_ids") or Def.target_mode(zone)!="harvest_only":continue
		if zone.policy.get("standing_order",false):continue
		var remains:bool=false
		for id:String in zone.target_ids:
			if ecology.harvest_target(context.world.entity(id),zone.policy):remains=true;break
		if not remains and context.get("region_is_detailed") is Callable:
			for region:String in zone.region_ids:
				if not context.region_is_detailed.call(region):remains=true;break
		if not remains:done[zone.id]=true
	if done.is_empty():return _idle()
	var tx:=Draft.new(context);var after:Dictionary=tx.extension(KEY,initial())
	for zone:Dictionary in after.zones:
		if not done.has(zone.id):continue
		zone.completed=true;zone.enabled=false;zone.revision+=1
		tx.events.append({"kind":"zone-changed","zone_id":zone.id,"operation":"complete","at":now})
	after.revision+=1
	return tx.result()

func _idle()->Dictionary:
	return {"ok":true,"code":"OK","world_changes":[],"fact_changes":[],"events":[]}

func hold_descriptors(_facts:Dictionary,_overrides:Dictionary={})->Array:
	return []

func view_basis(actor_id:String="player")->Dictionary:
	var fields:Array[String]=["revision"]
	var meta:Dictionary=context.world.extension_fields(KEY,fields)
	return {"available":_gate(actor_id).ok,"zones_revision":int(meta.get("revision",0)),"world_revision":context.world.get_revision(),"zones_generation":authority_token()}

func projection(actor_id:String="player",zone_id:String="")->Dictionary:
	var result:Dictionary={"schema":SCHEMA,"version":1,"available":false,"revision":0,"zones":[],"definitions":Def.KINDS.duplicate(true),"selection":{},"defaults":{},"limits":{"max_zones":Def.MAX_ZONES,"max_zone_cells":Def.MAX_ZONE_CELLS,"max_total_cells":Def.MAX_TOTAL_CELLS}}
	if not _gate(actor_id).ok:return result
	var basis:Dictionary=view_basis(actor_id)
	var revision:int=int(basis.zones_revision)
	var token:Dictionary=basis.zones_generation
	# A tokenless draft remains safe by falling back to its complete world revision.
	if token.is_empty():token={"world":context.world.get_instance_id(),"revision":context.world.get_revision()}
	if token!=_projection_token:
		_projection_rows.clear();_projection_zones.clear()
		# One detached authoritative read per actual plan revision. List rows
		# never clone all designated cells merely to discard them afterwards.
		for zone:Dictionary in state().zones:
			_projection_zones[zone.id]=zone
			var row:Dictionary={}
			for key:String in zone:
				if key not in ["cells","target_ids"]:row[key]=zone[key].duplicate(true) if zone[key] is Dictionary or zone[key] is Array else zone[key]
			row.cell_count=zone.cells.size();_projection_rows.append(row)
		_projection_revision=revision;_projection_token=token.duplicate()
	result.available=true;result.revision=revision
	result.zones=_projection_rows.duplicate(true)
	result.selection=_projection_zones.get(zone_id,{}).duplicate(true)
	if result.selection.has("target_ids") and Def.target_mode(result.selection)=="harvest_only":
		var ecology:Variant=_domain("ecology")
		if result.selection.policy.get("standing_order",false):
			result.selection.remaining_targets=ecology.standing_harvest_targets(result.selection).size() if ecology!=null else 0
		else:
			var all:Array=result.selection.target_ids;var left:int=0
			if ecology!=null:
				for id:String in all:
					if ecology.harvest_target(context.world.entity(id),result.selection.policy):left+=1
			result.selection.total_targets=all.size();result.selection.remaining_targets=left
	result.selection.erase("target_ids")
	for kind:String in Def.KINDS:result.defaults[kind]=Def.defaults(kind)
	return result
