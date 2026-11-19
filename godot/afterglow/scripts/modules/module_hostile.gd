extends RefCounted
## R34 contact attack inside the caller's Draft. No clock, commit or AI here.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const KEY="r34:modules"

static func detailed(host:RefCounted,region:String)->bool:
	return host.context.region_is_detailed.call(region) if host.context.get("region_is_detailed") is Callable else host.context.world.region_is_resident(region)

static func strike(host:RefCounted,tx:RefCounted,actor_id:String,module_id:String)->Dictionary:
	var actor:Dictionary=tx.actor(actor_id)
	if tx.staged.get("scenario")!="factory-settlement-r34" or actor.is_empty() or actor.get("faction")!="infected" or float(actor.get("hp",0))<=0:return Data.reject("FORBIDDEN")
	var now:float=float(tx.staged.get("time",host.context.clock.call()))
	if float(actor.get("cooldown",0))>0 or float(actor.get("stunned_until",0))>now:return Data.reject("COOLDOWN")
	var region:String=str(actor.get("regionId",""))
	if not detailed(host,region):return Data.reject("REGION_PAUSED")
	if host.context.get("spatial")==null:return Data.reject("SPATIAL_UNAVAILABLE")
	var view:RefCounted=host.context.world
	# Pending doors, shells, removals and terrain must participate in this hit.
	# This is only a read projection: the caller still owns the sole commit.
	if not tx.extra.is_empty():
		var projected:Dictionary=view.prepare_changes(tx.extra,view.get_revision())
		if not projected.get("ok",false):return Data.reject("INVALID_PENDING_GEOMETRY")
		view=projected.view
	var structures:Dictionary=tx.extensions.get("r3:structures",{})
	var query:RefCounted=host.context.spatial.space(view,structures,tx.staged) if view!=host.context.world or not structures.is_empty() else host.context.spatial.current_space()
	var feet:Dictionary=G.location(actor)
	var standing:Dictionary=query.standing_point(feet)
	if standing.is_empty() or G.point(standing).distance_to(G.point(feet))>0.001:return Data.reject("INVALID_ATTACK_STANCE")
	var modules:Dictionary=host.state(tx.extensions)
	var chest:Vector3=G.point(feet)+Vector3(0,1.2,0)
	var search:=AABB(chest-Vector3.ONE*0.9,Vector3.ONE*1.8)
	var parts:Array=[];var seen:Dictionary={}
	for x:int in range(floori(search.position.x/2),floori(search.end.x/2)+1):
		for z:int in range(floori(search.position.z/2),floori(search.end.z/2)+1):
			for e:Dictionary in query.entity_buckets.get(region,{}).get(Vector2i(x,z),[]):
				if seen.has(e.id):continue
				seen[e.id]=true
				var facts:Dictionary=e.get("data",{})
				# The click target spans the footprint, including empty courtyards.
				# Only collision-bearing parts can receive a contact hit.
				if not facts.get("solid",false) or facts.get("protected",false) or not facts.has("module_id"):continue
				var v:Dictionary=Draft.find(modules.instances,str(facts.module_id))
				if valid_target(v,region,module_id) and v.members.any(func(m:Dictionary)->bool:return m.id==e.id and m.kind=="entity") and facts.get("owner")==v.owner and facts.get("module_geometry_version",v.geometry_version)==v.geometry_version:
					parts.append({"module":v,"member_id":e.id,"bounds":G.aabb(e.bounds)})
	# Manual stations can have real Building pieces. Map only nearby pieces to
	# their registered member, never infer a module from an ID prefix/centre.
	for piece:Dictionary in query.nearby_pieces(region,search):
		if float(piece.hp)<=0 or piece.get("protected",false):continue
		for v:Dictionary in modules.instances:
			if not valid_target(v,region,module_id) or piece.get("owner")!=v.owner or not v.members.any(func(m:Dictionary)->bool:return m.id==piece.id and m.kind=="structure"):continue
			for box:AABB in query.geometry.boxes(piece):parts.append({"module":v,"member_id":piece.id,"bounds":box})
	var hit:Dictionary={}
	for part:Dictionary in parts:
		var box:AABB=part.bounds;var point:Vector3=chest.max(box.position).min(box.end)
		var distance:float=chest.distance_to(point)
		if distance>0.9 or (not hit.is_empty() and distance>=float(hit.distance)):continue
		var to:Dictionary=feet.merged(G.json_point(point-Vector3(0,1.2,0)),true)
		if not query.contact_clear(feet,to,str(part.member_id)) or not query.line_clear(feet,to,str(part.member_id)):continue
		hit={"module":part.module,"member_id":part.member_id,"point":point,"distance":distance}
	if hit.is_empty():return Data.reject("OUT_OF_REACH")
	var target:Dictionary=hit.module
	if not detailed(host,str(target.region)):return Data.reject("REGION_PAUSED")
	var cause_id:String="module-hostile:"+JSON.stringify([view.identity().worldId,actor_id,target.id,now],"",false,true).sha256_text()
	if target.get("damage_receipts",{}).has(cause_id):return Data.reject("NO_CHANGE")
	# Recovery may reject late (e.g. a bad cache/ruin conflict). Work on a private
	# copy and adopt only an actual hit; every rejection leaves ALL caller data.
	var trial:=Draft.new(tx.context)
	trial.initial=tx.initial.duplicate(true);trial.staged=tx.staged.duplicate(true)
	trial.extensions=tx.extensions.duplicate(true);trial.extra=tx.extra.duplicate(true);trial.events=tx.events.duplicate(true)
	var damage:float=minf(12,float(target.hp))
	var result:Dictionary=host.damage_in(trial,str(target.id),damage,cause_id)
	if not result.get("ok",false):return result
	var after:Dictionary=host.instance(str(target.id),trial.extensions)
	if float(after.get("hp",target.hp))>=float(target.hp):return Data.reject("NO_CHANGE")
	var merged:Dictionary=merge_entities(trial.extra)
	if not merged.ok:return merged
	var enemy:Dictionary=trial.actor(actor_id)
	enemy.cooldown=1.3;enemy.attack_until=now+0.28;enemy.activity="撞击真实设施"
	trial.events.append({"kind":"module-hostile-hit","actor_id":actor_id,"module_id":target.id,"target_id":target.id,"member_id":hit.member_id,"cause_id":cause_id,"damage":damage,"hp":after.hp,"position":G.json_point(hit.point),"hostile":true})
	# E may hold actor/state dictionaries while iterating this SAME Draft.
	# Preserve their identities instead of replacing staged/extension roots.
	adopt(tx.staged,trial.staged);adopt(tx.extensions,trial.extensions)
	tx.extra.assign(merged.changes);tx.events.assign(trial.events)
	return {"ok":true,"code":"OK","module_id":target.id,"member_id":hit.member_id,"cause_id":cause_id,"damage":damage,"hp":after.hp}

static func valid_target(v:Dictionary,region:String,id:String)->bool:
	return not v.is_empty() and (id.is_empty() or v.id==id) and v.region==region and v.status in ["operational","damaged"] and float(v.hp)>0 and not v.get("protected",false)

static func merge_entities(changes:Array)->Dictionary:
	var out:Array=[];var indices:Dictionary={}
	for source:Dictionary in changes:
		var op:Dictionary=source.duplicate(true)
		if op.op not in ["entity.put","entity.remove"]:out.append(op);continue
		if not indices.has(op.id):indices[op.id]=out.size();out.append(op);continue
		var first:Dictionary=out[indices[op.id]]
		var matches_original:bool=op.before_exists==first.before_exists and Data.json_equal(op.before,first.before)
		var matches_staged:bool=op.before_exists==(first.op=="entity.put") and Data.json_equal(op.before,first.after)
		if not matches_original and not matches_staged:return Data.reject("CONFLICTING_ENTITY_GUARD")
		first.op=op.op;first.after=op.after
	return {"ok":true,"changes":out.filter(func(op:Dictionary)->bool:return op.op!="entity.remove" or op.before_exists)}

static func adopt(target:Variant,source:Variant)->void:
	if target is Dictionary:
		for key:Variant in target.keys():
			if not source.has(key):target.erase(key)
		for key:Variant in source:
			if target.has(key) and ((target[key] is Dictionary and source[key] is Dictionary) or (target[key] is Array and source[key] is Array)):adopt(target[key],source[key])
			else:target[key]=source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
	else:
		target.resize(source.size())
		for i:int in source.size():
			if (target[i] is Dictionary and source[i] is Dictionary) or (target[i] is Array and source[i] is Array):adopt(target[i],source[i])
			else:target[i]=source[i].duplicate(true) if source[i] is Dictionary or source[i] is Array else source[i]
