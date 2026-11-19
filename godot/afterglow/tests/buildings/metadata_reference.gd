extends RefCounted
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Space = preload("res://scripts/buildings/building_space.gd")
const DoorProjection=preload("res://scripts/buildings/building_door_projection.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const EXTENSION := "r3:structures"
var context: Dictionary = {}
var source_catalog: Dictionary = {}
var geometry := Geometry.new()
var _space: RefCounted
var _space_world: RefCounted
var _space_revision := -1
var _validation_key := ""
var _validation_space: RefCounted
var _exit_hints: Dictionary = {}

func configure(value: Dictionary) -> void:
	context = preload("res://scripts/actions/domain_context.gd").isolate(value, false)
	source_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	geometry.configure(source_catalog)
	_space = null
	_validation_key=""; _validation_space=null; _exit_hints.clear()
	var runtime: Variant = value.get("runtime")
	if runtime != null and not runtime.changed.is_connected(_world_changed): runtime.changed.connect(_world_changed)

func _world_changed(changes: Dictionary) -> void:
	var spatial := false
	for c in changes.get("world", []):
		if c.get("op") != "extension.set" or c.get("id") not in ["r3:production", "r3:structure-orders"]: spatial = true; break
	if spatial: _space = null; _validation_key=""; _validation_space=null
	elif _space != null and _space_world == context.world: _space_revision = context.world.get_revision()

static func failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason, "world_changes": [], "fact_changes": [], "duration": 0.0, "destination": {}, "events": []}

static func success(world_changes: Array = [], fact_changes: Array = [], duration: float = 0.0, destination: Dictionary = {}, events: Array = []) -> Dictionary:
	return {"ok": true, "code": "OK", "reason": null, "world_changes": world_changes, "fact_changes": fact_changes, "duration": duration, "destination": destination, "events": events}

func structures(view: RefCounted = null) -> Dictionary:
	var w: RefCounted = context.world if view == null else view
	var value: Variant = w.extension(EXTENSION)
	return value if value is Dictionary else {"schemaVersion": 1, "catalogVersion": 1, "instances": [], "storeys": []}

func actor(id: String) -> Dictionary:
	var value: Variant = context.actor.call(id)
	return value if value is Dictionary else {}

func facts() -> Dictionary:
	return context.facts.call()

static func list(values: Variant) -> Array:
	return values.values() if values is Dictionary else values if values is Array else []

func permission(actor_id: String, target_id: String, action: String, piece: Dictionary = {}, staged: Dictionary = {}) -> Variant:
	var resident := actor(actor_id)
	if not staged.is_empty():
		for a in list(staged.get("actors", [])):
			if a.id == actor_id: resident = a
	if resident.is_empty() or float(resident.get("hp", 0)) <= 0: return "角色已失能"
	var target := piece
	if target.is_empty():
		var entity: Dictionary = context.world.entity(target_id)
		target = entity.get("data", {}).get("structure", entity.get("data", {}))
	var owner: Variant = target.get("owner")
	var visiting: bool = target.has("door") and not target.door.get("locked", false) and action in ["open", "close", "use"]
	if owner != null and owner not in ["home-residents", actor_id, resident.get("householdId", resident.get("household_id"))] and not visiting: return "尚未获得物主许可"
	var relationship: Dictionary = resident.get("relationship", {})
	if actor_id != "player" and action in ["place", "remove", "damage", "move"] and not relationship.get("consent", false) and relationship.get("promise") != target_id: return "住户没有同意这项工作"
	return null

func space(view: RefCounted = null, proposed: Dictionary = {}, staged: Dictionary = {}) -> RefCounted:
	var w: RefCounted = context.world if view == null else view
	var data := structures(w) if proposed.is_empty() else proposed
	var query := Space.new()
	var owner_ref: WeakRef = weakref(self)
	query.configure(w, data, geometry, func(a: String, t: String, k: String, p: Dictionary) -> Variant: return owner_ref.get_ref().permission(a, t, k, p, staged) if owner_ref.get_ref() != null else "运行时已关闭")
	return query

func current_space() -> RefCounted:
	var revision: int = context.world.get_revision()
	if _space == null or _space_world != context.world or revision != _space_revision:
		_space = space()
		_space_world = context.world
		_space_revision = revision
	return _space

func validation_space(view: RefCounted,data: Dictionary,staged: Dictionary) -> RefCounted:
	if view != context.world:return space(view,data,staged)
	# Native value equality compares the complete immutable projection without
	# serializing every structure for every moving actor's preview. Actor facts
	# are still rebound below; world identity/revision remains a separate guard.
	var key:=str(view.get_instance_id())+":"+str(view.get_revision())
	if _validation_space==null or key!=_validation_key or _validation_space.state!=data:
		var base:RefCounted=_space if _space!=null and _space_world==view and _space_revision==view.get_revision() else null
		var door:Dictionary=DoorProjection.changed_door(base.state,data) if base!=null else {}
		if not door.is_empty():
			var owner_ref:WeakRef=weakref(self)
			var can_open:Callable=func(a:String,t:String,k:String,p:Dictionary)->Variant:return owner_ref.get_ref().permission(a,t,k,p,staged) if owner_ref.get_ref()!=null else "运行时已关闭"
			_validation_space=DoorProjection.project(base,data,door,can_open)
		else:_validation_space=space(view,data,staged)
		_validation_key=key
	else:
		# Geometry cache never stores actor authorization: replace the full staged binding.
		var owner_ref:WeakRef=weakref(self)
		_validation_space.permission=func(a:String,t:String,k:String,p:Dictionary)->Variant:return owner_ref.get_ref().permission(a,t,k,p,staged) if owner_ref.get_ref()!=null else "运行时已关闭"
	return _validation_space

func exit_reachable(query:RefCounted,actor_id:String,from:Dictionary,to:Dictionary) -> bool:
	var key:=actor_id+"|"+str([to.regionId,to.x,to.y,to.z])
	var hint:Array=_exit_hints.get(key,[])
	var current:=from
	var valid:=not hint.is_empty()
	for step in hint:
		if step.kind=="move":
			var r:Dictionary=query.walk(actor_id,current,step.to,true)
			if not r.ok or Geometry.point(r.location).distance_to(Geometry.point(step.to))>0.025:valid=false;break
			current=r.location
		elif step.kind=="open-door":
			var door:Dictionary=query.by_id.get(step.targetId,{})
			if door.is_empty() or float(door.hp)<=0:valid=false;break
			if not door.door.open and (door.door.locked or door.door.blocked or query.permission.call(actor_id,door.id,"open",door)!=null):valid=false;break
		elif step.kind=="stairs":
			var stair:Dictionary=query.by_id.get(step.targetId,{})
			if stair.is_empty() or not query.stair_clear(stair) or Geometry.point(current).distance_to(Geometry.point(step.from))>0.025:valid=false;break
			current=step.to
		else:valid=false;break
	if valid and Geometry.point(current).distance_to(Geometry.point(to))<=0.025:return true
	var path:Dictionary=query.route(actor_id,from,to)
	if not path.ok:return false
	if _exit_hints.size()>=64:_exit_hints.erase(_exit_hints.keys()[0])
	_exit_hints[key]=path.steps.duplicate(true)
	return true

func instance(id: String) -> Dictionary:
	return current_space().by_id.get(id, {}).duplicate(true)

func use_points(id: String) -> Array:
	var v := instance(id)
	return current_space().use_points(v) if not v.is_empty() else []

func can_use(actor_id: String, target: Dictionary, at: Dictionary = {}, staged: Dictionary = {}) -> Variant:
	var a := actor(actor_id)
	if not staged.is_empty():
		for resident in list(staged.get("actors",[])):
			if resident.id==actor_id:a=resident;break
	if a.is_empty() or float(a.get("hp", 0)) <= 0: return "角色已失能"
	var from := Geometry.location(a)
	var query := current_space()
	if at.is_empty() and Interaction.structure(query,from,target):return null
	var uses: Array = query.use_points(target) if at.is_empty() else [at]
	for p in uses:
		var feet: Dictionary = query.standing_point(p)
		if not feet.is_empty() and Interaction.same_level(from,feet) and Geometry.point(from).distance_to(Geometry.point(feet)) <= 1.3 and query.line_clear(from, feet, str(target.get("id", ""))):
			if geometry.definition(target).get("kind") == "roof":
				if absf(float(target.position.y) - float(feet.y) - 3.4) > Geometry.EPS: continue
				var hand := Geometry.point(from) + Vector3(0,1.3,0)
				var underside := Vector3(feet.x,float(target.position.y)-0.215,feet.z)
				var clear := true
				if not query.terrain_clear(str(from.regionId),AABB(hand.min(underside)-Vector3(0.025,0,0.025),(hand.max(underside)-hand.min(underside))+Vector3(0.05,0,0.05))): clear=false
				for entry in query.candidates(str(from.regionId),hand,underside,0.025):
					if entry.instance.id != target.id and entry.bounds.intersects_segment(hand,underside) != null: clear=false;break
				if not clear: continue
			return null
	return "需要靠近同层物件或门洞，且使用线不能被遮挡"

func availability(request: Dictionary) -> Dictionary:
	var result := prepare(request)
	if result.ok:
		result.world_changes = []
		result.fact_changes = []
	return result

func prepare(request: Dictionary) -> Dictionary:
	if request.get("kind") == "door": return prepare_door(request)
	return failure("UNKNOWN_COMMAND", "建筑服务不处理此动作")

func hostile_contact(query:RefCounted,a:Dictionary,v:Dictionary)->Dictionary:
	if float(v.get("hp",0))<=0 or v.get("protected",false) or geometry.definition(v).get("kind") not in ["door","wall","corner","window"] or v.regionId!=a.get("regionId"):return {}
	var chest:=Geometry.point(Geometry.location(a))+Vector3(0,1.2,0)
	var nearest:=INF;var contact:=Vector3.ZERO
	for bounds in geometry.boxes(v):
		var at:Vector3=chest.max(bounds.position).min(bounds.end)
		var distance:=chest.distance_to(at)
		if distance<nearest:nearest=distance;contact=at
	if nearest>0.9:return {}
	var to:=Geometry.location(a);to.x=contact.x;to.y=contact.y-1.2;to.z=contact.z
	if not query.line_clear(Geometry.location(a),to,str(v.id)):return {}
	return {"distance":nearest,"point":Geometry.json_point(contact)}

func strike_structure(tx:RefCounted,actor_id:String,target_id:String="")->Dictionary:
	# Called by A's hostile AI inside its existing Draft, never a player/hammer
	# command or another clock/commit. Every accepted hit uses normal edit safety.
	var a:Dictionary=tx.actor(actor_id)
	if a.is_empty() or a.get("faction")!="infected" or float(a.get("hp",0))<=0:return failure("FORBIDDEN","只有存活感染者可执行敌方近战")
	if float(a.get("cooldown",0))>0 or float(a.get("stunned_until",0))>float(context.clock.call()):return failure("COOLDOWN","敌方近战冷却或受控中")
	var data:Dictionary=tx.extensions.get(EXTENSION,structures())
	var query:RefCounted=current_space() if not tx.extensions.has(EXTENSION) else space(context.world,data,tx.staged)
	var target:Dictionary={};var contact:Dictionary={}
	var candidates:Array=data.instances if not target_id.is_empty() else query.nearby_pieces(str(a.regionId),AABB(Geometry.point(a)-Vector3(1.2,0,1.2),Vector3(2.4,1.8,2.4)))
	for v in candidates:
		if not target_id.is_empty() and v.id!=target_id:continue
		var hit:=hostile_contact(query,a,v)
		if hit.is_empty():continue
		if contact.is_empty() or hit.distance<contact.distance:target=v;contact=hit
	if target.is_empty():return failure("OUT_OF_REACH","没有接触距离内且无遮挡的可破坏门墙")
	var next:=target.duplicate(true)
	var damage:=minf(12.0,float(next.hp))
	next.hp=maxf(0,float(next.hp)-damage);next.version=int(next.version)+1
	if next.hp<=0 and next.has("door"):next.door.open=true;next.door.locked=false;next.door.blocked=false
	var edit:=prepare_edit([target.id],[next],tx.staged,data)
	if not edit.ok:return edit
	for op in edit.world_changes:
		if op.op=="extension.set":tx.extensions[op.id]=op.after
		else:
			# Several enemies may hit the same door in one A fixed step. Keep
			# its original CAS before-image and the final staged after-image.
			var merged:=false
			for prior in tx.extra:
				if prior.get("op")=="entity.put" and op.op=="entity.put" and prior.id==op.id:prior.after=op.after;merged=true;break
			if not merged:tx.extra.append(op)
	a.cooldown=1.3;a.attack_until=float(context.clock.call())+0.28;a.activity="撞击真实门墙"
	tx.events.append({"kind":"structure-damaged","actor_id":actor_id,"target_id":target.id,"damage":damage,"hp":next.hp,"position":contact.point,"hostile":true})
	return success([],[],0,{},[{"kind":"structure-damaged","target_id":target.id,"damage":damage}])

func prepare_door(request: Dictionary, proposed: Dictionary = {}, staged: Dictionary = {}) -> Dictionary:
	var id := str(request.get("target_id", ""))
	var resident_id := str(request.get("actor_id", ""))
	var query := current_space() if proposed.is_empty() else space(context.world, proposed, staged)
	var v: Dictionary = query.by_id.get(id, {}).duplicate(true)
	var current_facts := facts() if staged.is_empty() else staged
	var operation := str(request.get("payload", {}).get("operation", "close" if v.get("door",{}).get("open",false) else "open"))
	if operation not in ["open", "close", "lock", "unlock"]: return failure("INVALID", "门操作无效")
	if not v.has("door") or float(v.get("hp", 0)) <= 0: return failure("DESTROYED", "门已毁坏或不存在")
	var access: Variant = can_use(resident_id, v, {}, current_facts)
	if access != null: return failure("UNREACHABLE", access)
	access = permission(resident_id, id, operation, v, current_facts)
	if access != null: return failure("FORBIDDEN", access)
	if v.door.get("blocked", false): return failure("BLOCKED", "门被堵塞")
	if operation == "open" and v.door.get("locked", false): return failure("LOCKED", "门已上锁")
	if operation == "lock" and v.door.get("open", false): return failure("BLOCKED", "请先关门再上锁")
	var next := v.duplicate(true)
	if operation in ["open", "close"]: next.door.open = operation == "open"
	else: next.door.locked = operation == "lock"
	if next.door.open != v.door.open:
		var signs: Array = [int(v.door.swing), -int(v.door.swing)] if operation == "open" else [int(v.door.swing)]
		var clear := false
		for sign in signs:
			var safe := true
			for n in range(25):
				var leaf: AABB = geometry.leaf(v, sign * PI / 2.0 * n / 24.0)
				if not query.terrain_clear(str(v.regionId), leaf): safe = false; break
				for a in list(current_facts.get("actors", [])):
					if float(a.get("hp", 0)) <= 0: continue
					var p := Geometry.location(a)
					if p.regionId == v.regionId and Geometry.overlap(leaf, AABB(Geometry.point(p) + Vector3(-0.26, 0.02, -0.26), Vector3(0.52, 1.78, 0.52))): safe = false; break
				if not safe: break
				for entry in query.candidates(str(v.regionId), leaf.position, leaf.end, 0.0):
					if entry.instance.id != id and Geometry.overlap(leaf, entry.bounds): safe = false; break
				if not safe: break
			if safe:
				next.door.swing = sign
				clear = true
				break
		if not clear: return failure("OCCUPIED", "门扇完整扫掠被人物、构件或地形占用")
	next.version = int(v.version) + 1
	var data := structures() if proposed.is_empty() else proposed.duplicate(true)
	for i in data.instances.size():
		if data.instances[i].id == id: data.instances[i] = next
	var valid := validate_structures(context.world, data, current_facts, [], [])
	if not valid.ok: return valid
	var a := actor(resident_id)
	for resident in list(current_facts.get("actors",[])):
		if resident.id==resident_id:a=resident;break
	if float(a.get("stamina", 0)) < 0.25: return failure("EXHAUSTED", "体力不足")
	var after := a.duplicate(true)
	after.stamina = maxf(0, float(a.stamina) - 0.25)
	return success(changes_for(data, [next], []), [{"collection": "actors", "id": resident_id, "before": a, "after": after}], 0.4, Geometry.display_location(Geometry.location(a)), [{"kind": "door", "target_id": id, "operation": operation, "noise_radius": 4}])

func extension_change(key: String, after: Variant, view: RefCounted = null) -> Dictionary:
	var w: RefCounted = context.world if view == null else view
	return {"op": "extension.set", "id": key, "before_exists": w.has_extension(key), "before": w.extension(key), "after": after.duplicate(true) if after is Dictionary or after is Array else after}

func changes_for(data: Dictionary, added: Array, removed: Array) -> Array:
	var changes: Array = [extension_change(EXTENSION, data)]
	for v in added:
		var prior: Dictionary = context.world.entity(str(v.id))
		changes.append({"op": "entity.put", "id": v.id, "before_exists": not prior.is_empty(), "before": prior if not prior.is_empty() else null, "after": geometry.entity(v)})
	for id in removed:
		changes.append({"op": "entity.remove", "id": id, "before": context.world.entity(id)})
	return changes

func supported(query: RefCounted, v: Dictionary, visited: Dictionary = {}, terrain_proofs: Dictionary = {}) -> bool:
	if visited.is_empty():
		if query.support_roots.has(v.id):return query.support_roots[v.id]
		var result:=supported_uncached(query,v,visited,terrain_proofs)
		query.support_roots[v.id]=result
		return result
	return supported_uncached(query,v,visited,terrain_proofs)

func supported_uncached(query: RefCounted, v: Dictionary, visited: Dictionary, terrain_proofs: Dictionary) -> bool:
	var slabs:=0
	for id in visited:
		if query.by_id.has(id) and geometry.definition(query.by_id[id]).kind in ["floor","roof"]:slabs+=1
	return not support_witness(query,v,visited,terrain_proofs,slabs).is_empty()

func support_witness(query:RefCounted,v:Dictionary,visited:Dictionary,terrain_proofs:Dictionary,slabs:int)->Dictionary:
	# Positive certificates contain every chosen dependency and the greatest
	# incoming slab count accepted by that proof. Reuse requires disjoint actual
	# ancestors AND sufficient slab budget. An ancestry-dependent false is never
	# memoized, and any conflict falls back to the original ordered predicate.
	if float(v.get("hp",0))<=0:return {"ids":{},"slab_limit":2147483647}
	if visited.has(v.id):return {}
	var saved:Dictionary=query.support_witnesses.get(v.id,{})
	if not saved.is_empty() and slabs<=int(saved.slab_limit):
		var compatible:=true
		for id in visited:
			if saved.ids.has(id):compatible=false;break
		if compatible:return saved
	var ancestry := visited.duplicate()
	ancestry[v.id] = true
	var d: Dictionary = geometry.definition(v)
	var b: AABB = query.bounds(v)
	var own_slab:=1 if d.kind in ["floor","roof"] else 0
	var witness:Dictionary={"ids":{v.id:true},"slab_limit":2147483647}
	if d.support == "terrain":
		if not terrain_proofs.has(v.id): terrain_proofs[v.id] = query.terrain_supports(str(v.regionId), AABB(b.position, Vector3(b.size.x, 0, b.size.z)))
		if not terrain_proofs[v.id]:return {}
	elif d.support == "wall-top":
		var child:Dictionary={}
		for other in query.support_walls(v):
			child=support_witness(query,other,ancestry,terrain_proofs,slabs+own_slab)
			if not child.is_empty():break
		if child.is_empty():
			if slabs+own_slab>=3:return {}
			witness.slab_limit=2-own_slab
			for other in query.support_slabs(v):
				child=support_witness(query,other,ancestry,terrain_proofs,slabs+own_slab)
				if not child.is_empty():break
		if child.is_empty():return {}
		witness.ids.merge(child.ids)
		witness.slab_limit=mini(int(witness.slab_limit),int(child.slab_limit)-own_slab)
	else:
		for sample:Dictionary in surface_support_samples(query,v,b):
			if sample.ground:continue
			var child:Dictionary={}
			for floor_piece:Dictionary in sample.pieces:
				child=support_witness(query,floor_piece,ancestry,terrain_proofs,slabs+own_slab)
				if not child.is_empty():break
			if child.is_empty():return {}
			witness.ids.merge(child.ids)
			witness.slab_limit=mini(int(witness.slab_limit),int(child.slab_limit)-own_slab)
	query.support_witnesses[v.id]=witness
	return witness

func surface_support_samples(query:RefCounted,v:Dictionary,b:AABB)->Array:
	# Cache only immutable geometric candidates and exact terrain samples for
	# this complete query. Recursive truth still uses the caller's ancestry and
	# three-slab limit; no success/failure is shared across recursion contexts.
	if query.surface_support_neighbors.has(v.id):return query.surface_support_neighbors[v.id]
	var d:Dictionary=geometry.definition(v)
	var footprint:=b
	if d.has("stairs"):footprint=Geometry.transformed_box(AABB(Vector3(-float(d.size.x)/2,0,0),Vector3(float(d.size.x),0,0.4)),v)
	var result:Array=[]
	for x in samples(footprint.position.x,footprint.end.x):
		for z in samples(footprint.position.z,footprint.end.z):
			var pieces:Array=[]
			for floor_piece:Dictionary in query.support_at(str(v.regionId),Vector3(x,v.position.y,z)):
				if floor_piece.id!=v.id:pieces.append(floor_piece)
			result.append({"pieces":pieces,"ground":v.get("storeyId")==null and query.terrain_supports(str(v.regionId),AABB(Vector3(x,v.position.y,z),Vector3.ZERO))})
	query.surface_support_neighbors[v.id]=result
	return result

static func samples(lo: float, hi: float) -> Array:
	if hi - lo < 0.35: return [(lo + hi) / 2.0]
	var values: Array = [lo + 0.01, hi - 0.01]
	var n := lo + 0.5
	while n < hi:
		values.append(n)
		n += 0.5
	return values

func validate_structures(view: RefCounted, data: Dictionary, staged: Dictionary, removed: Array = [], added: Array = []) -> Dictionary:
	var query := validation_space(view, data, staged)
	var terrain_proofs: Dictionary = {}
	for v in data.get("instances", []):
		if not geometry.definitions.has(v.get("definitionId", "")): return failure("INVALID", "未知建筑目录")
		if not supported(query, v, {}, terrain_proofs): return failure("DEPENDENT", "修改会使构件失去基础或承重支撑：" + str(v.id))
		if v.has("stairs") and float(v.hp) > 0 and not query.stair_clear(v): return failure("BLOCKED", "楼梯净空、真实连接或平台不足")
	for v in added:
		for part in geometry.boxes(v):
			if geometry.definition(v).kind != "foundation" and not query.terrain_clear(str(v.regionId), part): return failure("OCCUPIED", "构件与实体地形冲突")
			for entry in query.candidates(str(v.regionId), part.position, part.end, 0.0):
				if entry.instance.id == v.id or not Geometry.overlap(part, entry.bounds): continue
				var walls: Array = ["wall", "corner", "door", "window"]
				var intersection: AABB = part.intersection(entry.bounds)
				if geometry.definition(v).kind in walls and geometry.definition(entry.instance).kind in walls and intersection.size.x <= 0.201 and intersection.size.z <= 0.201: continue
				return failure("OCCUPIED", "建筑占地冲突：" + str(entry.instance.id))
			for a in list(staged.get("actors", [])):
				if float(a.get("hp", 0)) <= 0: continue
				var p := Geometry.location(a)
				if p.regionId == v.regionId and Geometry.overlap(part, AABB(Geometry.point(p) + Vector3(-0.26, 0.015, -0.26), Vector3(0.52, 1.785, 0.52))): return failure("OCCUPIED", "有人占用施工体积")
	var previous := structures()
	for v in previous.instances:
		if not v.get("protected", false) and not v.has("stairs"): continue
		if removed.has(v.id) and not query.by_id.has(v.id): return failure("BLOCKED", "唯一楼梯或关键出口不能移除")
		for p in current_space().use_points(v):
			var volume := AABB(Geometry.point(p) + Vector3(-0.3, 0.05, -0.3), Vector3(0.6, 1.8, 0.6))
			for n in added:
				if n.id == v.id: continue
				for part in geometry.boxes(n):
					if Geometry.overlap(volume, part): return failure("BLOCKED", "修改会堵住楼梯或关键出口")
	for a in list(staged.get("actors", [])):
		if float(a.get("hp", 0)) <= 0: continue
		var p := Geometry.location(a)
		var feet: Dictionary = query.standing_point(p)
		if feet.is_empty() or Geometry.point(feet).distance_to(Geometry.point(p)) > 0.025: return failure("SPATIAL_REJECTED", "人物脚下支撑或身体净空失效：" + str(a.id))
		if p.get("buildingId") == null: continue
		var generation: Variant = view.extension("generation:" + str(p.regionId))
		if not generation is Dictionary: continue
		for slot in generation.get("slots", []):
			if slot.get("kind") != "entrance" or slot.get("buildingId") != p.buildingId: continue
			var exit := Geometry.location(slot)
			exit.buildingId = null
			exit.storeyId = null
			var ground: Variant = view.surface_height(exit.x, exit.z)
			if ground != null: exit.y = float(ground)
			if not exit_reachable(query,str(a.id),p,exit): return failure("SPATIAL_REJECTED", "修改会困住住户，必须保留可达出口：" + str(a.id))
	return success()

func validate_world_draft(world_draft: RefCounted, fact_snapshot: Dictionary, changes: Array) -> Dictionary:
	var structure_facts := false
	var production_facts := false
	for c in changes:
		if c.get("id") == EXTENSION or c.get("op") in ["entity.put","entity.remove"]: structure_facts = true
		if c.get("id") in ["r3:production","r3:structure-orders"]: production_facts = true
	var integrity: Dictionary = preload("res://scripts/buildings/building_snapshot.gd").validate(world_draft, fact_snapshot, source_catalog, structure_facts, production_facts)
	if not integrity.ok: return integrity
	# Production/order facts do not alter terrain, geometry or actor permissions.
	# Never reuse this shortcut for unknown extensions, entities, doors or voxel edits.
	var spatial := false
	for c in changes:
		if c.get("op") != "extension.set" or c.get("id") not in ["r3:production", "r3:structure-orders"]: spatial = true; break
	if not spatial:
		var old: Dictionary = facts()
		for a in list(fact_snapshot.get("actors", [])):
			var before: Dictionary = {}
			for other in list(old.get("actors", [])):
				if other.id == a.id: before = other; break
			if before.is_empty() or Geometry.location(before) != Geometry.location(a) or before.get("relationship") != a.get("relationship") or float(before.get("hp", 0)) != float(a.get("hp", 0)): spatial = true; break
		if not spatial: return success()
	var data := structures(world_draft)
	var removed: Array = []
	var added: Array = []
	for change in changes:
		if change.get("op") == "entity.remove": removed.append(change.id)
		if change.get("op") == "entity.put" and change.get("after", {}).get("kind") == "structure": added.append(change.after.data.structure)
	var terrain_equivalent:=true
	for c in changes:
		if c.get("op")=="extension.set" and c.get("id") in [EXTENSION,"r3:production","r3:structure-orders"]:continue
		if c.get("op") in ["entity.put","entity.remove"]:
			var before:Variant=c.get("before")
			var after:Variant=c.get("after")
			if (before==null or (before is Dictionary and before.get("kind")=="structure")) and (after==null or (after is Dictionary and after.get("kind")=="structure")):continue
		terrain_equivalent=false;break
	return validate_structures(context.world if terrain_equivalent else world_draft, data, fact_snapshot, removed, added)

func validate_snapshot(view: RefCounted, fact_snapshot: Dictionary) -> Dictionary:
	return preload("res://scripts/buildings/building_snapshot.gd").validate(view, fact_snapshot, source_catalog)

func create_view(value: Dictionary) -> Node3D:
	var View = load("res://scripts/buildings/building_view.gd")
	var node: Node3D = View.new()
	var options := value.duplicate()
	options.service = self
	node.configure(options)
	return node

func catalog() -> Array:
	return source_catalog.get("structure_definitions", {}).values().duplicate(true)

static func generation_profiles()->Array:
	# Pure DTO: no world read, randomness, actor, time or persistent mutation.
	var document:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json"))
	return document.get("profiles",[]).duplicate(true) if document is Dictionary else []

static func dressing_profiles()->Array:
	return preload("res://scripts/buildings/building_dressing.gd").profiles()

func seed_rural(world: RefCounted) -> Dictionary:
	if world.identity().generatorVersion!="rural-1":return prepare_generation(world)
	var Seeder = load("res://scripts/buildings/rural_buildings.gd")
	return Seeder.new().generate(self, world)

func prepare_generation(view:RefCounted,region_ids:Array=[])->Dictionary:
	# A owns the final world/facts transaction, including initial finite stock.
	var family:Dictionary=preload("res://scripts/buildings/building_families.gd").new().prepare(self,view,region_ids)
	if not family.ok and family.code!="ALREADY_SEEDED":return family
	var spawns:Array=[]
	for p:Dictionary in family.get("spawn_points",{}).values():spawns.append(p)
	var dressing:Dictionary=preload("res://scripts/buildings/building_dressing.gd").new().prepare(self,view,region_ids,family.get("world_changes",[]),spawns)
	if not dressing.ok and dressing.code!="ALREADY_SEEDED":return dressing
	if not dressing.ok:return family
	if not family.ok:family={"ok":true,"code":"OK","reason":null,"world_changes":[],"fact_changes":[],"initial_stocks":[],"initial_tools":[],"initial_records":[],"life_anchors":{},"assembled_parcels":[],"entrances":{},"spawn_points":{}}
	family.world_changes.append_array(dressing.world_changes)
	family.dressing_results=dressing.dressing_results
	return family

func life_anchors(view:RefCounted=null)->Dictionary:
	var w:RefCounted=context.world if view==null else view
	var marker:Variant=w.extension("r3:building-generation")
	var result:Dictionary={}
	if not marker is Dictionary:return result
	for id:String in marker.get("parcels",{}):
		var anchors:Dictionary=marker.parcels[id].get("life_anchors",{}).duplicate(true)
		# Stored sockets identify initial purposes; live object positions remain
		# authoritative after actual relocation/demolition and native restore.
		for purpose:String in anchors.keys():
			var entity:Dictionary=w.entity(str(anchors[purpose].get("target_id","")))
			if entity.is_empty() or float(entity.get("data",{}).get("structure",{}).get("hp",1))<=0:anchors.erase(purpose)
			else:anchors[purpose].position=Geometry.location(entity)
		result[id]=anchors
	return result

func generation_work_sites()->Array:
	var marker:Variant=context.world.extension("r3:building-generation")
	var result:Array=[]
	if marker is Dictionary:
		for parcel:Dictionary in marker.get("parcels",{}).values():result.append_array(parcel.get("construction_sites",[]))
	return result

func make_instance(definition_id: String, id: String, location: Dictionary, quarter_turn: int = 0, owner: Variant = "home-residents") -> Dictionary:
	var d: Dictionary = geometry.definitions.get(definition_id, {})
	if d.is_empty(): return {}
	var p := Geometry.location(location)
	var result := {"id": id, "definitionId": definition_id, "regionId": p.regionId, "buildingId": p.buildingId, "storeyId": p.storeyId,
		"position": Geometry.json_point(Geometry.point(p)), "quarterTurn": posmod(quarter_turn, 4), "hp": d.maxHp, "version": 0, "protected": false, "owner": owner}
	if d.has("door"): result.door = {"open": false, "locked": false, "blocked": false, "swing": 1}
	return result

func prepare_edit(removed: Array, added: Array, staged: Dictionary = {}, proposed: Dictionary = {}) -> Dictionary:
	var data := structures() if proposed.is_empty() else proposed.duplicate(true)
	var ids: Dictionary = {}
	for v in data.instances:
		if not removed.has(v.id): ids[v.id] = true
	var next: Array = data.instances.filter(func(v: Dictionary) -> bool: return not removed.has(v.id))
	for v in added:
		if ids.has(v.get("id")) or not geometry.definitions.has(v.get("definitionId")): return failure("INVALID", "构件身份重复或目录未知")
		if not v.get("position") is Dictionary or not [v.position.get("x"), v.position.get("y"), v.position.get("z"), v.get("hp")].all(func(n: Variant) -> bool: return (n is float or n is int) and is_finite(float(n))): return failure("INVALID", "构件坐标或生命值无效")
		if not context.world.entity(v.id).is_empty() and not removed.has(v.id): return failure("OCCUPIED", "世界身份已被占用")
		ids[v.id] = true; next.append(v.duplicate(true))
	data.instances = next
	var valid := validate_structures(context.world, data, facts() if staged.is_empty() else staged, removed, added)
	return valid if not valid.ok else success(changes_for(data, added, removed.filter(func(id: String) -> bool: return not ids.has(id))))
