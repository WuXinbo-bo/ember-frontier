extends RefCounted
## Consume C's persistent placement facts. No RNG, direct commit, stock, clock,
## alternate navigation or legacy-world auto-population belongs in this adapter.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const KEY="r3:dressing"

static func profiles()->Array:
	var doc:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/dressing_profiles.json"))
	return doc.get("profiles",[]).duplicate(true) if doc is Dictionary else []

static func entity_for(profile:Dictionary,slot:Dictionary,region:String)->Dictionary:
	var lo:Dictionary=profile.footprint.min;var hi:Dictionary=profile.footprint.max
	var instance:Dictionary={"position":slot.position,"quarterTurn":int(slot.quarter_turn)}
	var bounds:=Geometry.transformed_box(AABB(Vector3(lo.x,0,lo.z),Vector3(hi.x-lo.x,profile.height,hi.z-lo.z)),instance)
	# The original terrain edit validator already protects solid object feet.
	# Explicit bounds additionally retain this support fact in the same world DTO.
	var support:=AABB(bounds.position-Vector3(0,0.5,0),Vector3(bounds.size.x,0.5,bounds.size.z))
	return {"id":slot.id,"kind":"prop","regionId":region,"position":slot.position.duplicate(true),"bounds":Geometry.json_box(bounds),"revision":0,"blocksTerrain":true,"supportBounds":[Geometry.json_box(support)],"tags":["rural-dressing",profile.id],"data":{"solid":true,"opaque":profile.opaque,"quarterTurn":int(slot.quarter_turn),"dressing_profile_id":profile.id,"dressing_profile":profile.duplicate(true),"aging":"aged","no_stock":true,"no_interaction":true}}

static func plan_conflict(plan:Dictionary,bounds:AABB,profile:Dictionary)->String:
	var center:=Vector2(bounds.get_center().x,bounds.get_center().z)
	var radius:=Vector2(bounds.size.x,bounds.size.z).length()/2.0
	for path:Dictionary in plan.get("paths",[]):
		for i:int in range(path.get("points",[]).size()-1):
			var a:=Vector2(path.points[i].x,path.points[i].z);var b:=Vector2(path.points[i+1].x,path.points[i+1].z)
			if center.distance_to(Geometry2D.get_closest_point_to_segment(center,a,b))<radius+float(path.width)/2+float(profile.clearance.road):return "road-clearance"
	for parcel:Dictionary in plan.get("parcels",[]):
		# C owns the complete parcel and all reserved future work sites. Do not
		# fill an empty-looking room/porch or block a door's future swept volume.
		var rect:Array=parcel.get("pad",{}).get("xz",[])
		if rect.size()==4 and bounds.position.x<float(rect[2]) and bounds.end.x>float(rect[0]) and bounds.position.z<float(rect[3]) and bounds.end.z>float(rect[1]):return "parcel-pad"
		for reservation:Dictionary in parcel.get("use_reservations",[]):
			if reservation.get("bounds") is Dictionary and Geometry.overlap(bounds,Geometry.aabb(reservation.bounds)):return "reserved-use-volume"
		for port:Dictionary in parcel.get("entrance_ports",[]):
			var at:=Vector2(port.position.x,port.position.z)
			if center.distance_to(at)<radius+float(profile.clearance.entrance):return "entrance-clearance"
	return ""

static func safe_placement(service:RefCounted,view:RefCounted,query:RefCounted,plan:Dictionary,entity:Dictionary,profile:Dictionary,pending:Array,actors:Array)->String:
	var bounds:=Geometry.aabb(entity.bounds);var region:Dictionary=view.region(entity.regionId)
	if region.is_empty():return "missing-region"
	var limits:=Geometry.aabb(region.bounds)
	if bounds.position.x<limits.position.x or bounds.end.x>limits.end.x or bounds.position.z<limits.position.z or bounds.end.z>limits.end.z:return "region-boundary"
	var reason:=plan_conflict(plan,bounds,profile)
	if not reason.is_empty():return reason
	var cs:float=view.config().cellSize
	var xs:Array=[bounds.position.x+0.001,bounds.end.x-0.001];var zs:Array=[bounds.position.z+0.001,bounds.end.z-0.001]
	for x:int in range(floori(bounds.position.x/cs),ceili(bounds.end.x/cs)):xs.append((x+0.5)*cs)
	for z:int in range(floori(bounds.position.z/cs),ceili(bounds.end.z/cs)):zs.append((z+0.5)*cs)
	for x:float in xs:
		for z:float in zs:
			if x<bounds.position.x or x>=bounds.end.x or z<bounds.position.z or z>=bounds.end.z:continue
			var y:Variant=view.surface_height(x,z)
			if y==null or absf(float(y)-float(entity.position.y))>float(profile.terrain_tolerance):return "unsupported-or-stepped-footprint"
	if not query.terrain_clear(entity.regionId,AABB(bounds.position+Vector3(0,0.01,0),bounds.size-Vector3(0,0.01,0))):return "terrain-or-existing-solid"
	for piece:Dictionary in query.nearby_pieces(entity.regionId,bounds):
		for solid:AABB in service.geometry.boxes(piece):
			if Geometry.overlap(bounds,solid):return "existing-building"
	for other:Dictionary in pending:
		if other.get("regionId")==entity.regionId and other.get("bounds") is Dictionary and Geometry.overlap(bounds,Geometry.aabb(other.bounds)):return "pending-entity"
	for actor:Dictionary in actors:
		var at:=Geometry.location(actor)
		if at.regionId!=entity.regionId or float(actor.get("hp",100))<=0:continue
		var body:=AABB(Geometry.point(at)+Vector3(-0.26,0.015,-0.26),Vector3(0.52,1.785,0.52)).grow(float(profile.clearance.actor))
		if Geometry.overlap(bounds,body):return "resident-clearance"
	return ""

func prepare(service:RefCounted,view:RefCounted,region_ids:Array=[],pending_changes:Array=[],extra_actors:Array=[])->Dictionary:
	var indexed:Dictionary={}
	for profile:Dictionary in profiles():indexed[profile.id]=profile
	var prior:Variant=view.extension(KEY)
	if prior!=null and (not prior is Dictionary or prior.get("version")!=1 or not prior.get("entries") is Dictionary):return service.failure("INVALID_DRESSING_MARKER","invalid persistent dressing marker")
	var marker:Dictionary=prior.duplicate(true) if prior is Dictionary else {"version":1,"entries":{}}
	var seen:Dictionary={};var pending:Array=[];var operations:Array=[];var rows:Array=[]
	for op:Dictionary in pending_changes:
		if op.get("op")=="entity.put":pending.append(op.after)
	var actors:Array=service.facts().get("actors",[]).duplicate(true);actors.append_array(extra_actors)
	var query:RefCounted
	for region:Dictionary in view.regions():
		if not region_ids.is_empty() and not region_ids.has(region.id):continue
		var plan:Variant=view.extension("generation:"+str(region.id))
		if not plan is Dictionary or not plan.has("dressing"):continue
		if not plan.dressing is Array or plan.dressing.size()>48:return service.failure("INVALID_DRESSING_PLAN","invalid or oversized dressing list")
		for slot:Variant in plan.dressing:
			if not slot is Dictionary or not Data.valid_id(slot.get("id")) or not str(slot.id).begins_with(str(region.id)+":") or seen.has(slot.id) or not indexed.has(slot.get("profile_id")) or not Data.vec(slot.get("position")) or not Data.integer(slot.get("quarter_turn")) or int(slot.quarter_turn) not in [0,1,2,3] or slot.get("state")!="aged":return service.failure("INVALID_DRESSING_PLAN","invalid dressing identity, profile, position, rotation or state")
			seen[slot.id]=true
			var stamp:=JSON.stringify(JSON.parse_string(JSON.stringify(slot)),"",true,true).sha256_text()
			if marker.entries.has(slot.id):
				var processed:Variant=marker.entries[slot.id]
				if not processed is Dictionary or processed.get("id")!=slot.id or processed.get("status") not in ["placed","skipped"] or not processed.get("plan_sha256") is String:return service.failure("INVALID_DRESSING_MARKER","invalid processed dressing entry")
				if processed.plan_sha256!=stamp:return service.failure("DRESSING_PLAN_CHANGED","processed dressing cannot move or reroll")
				continue
			var profile:Dictionary=indexed[slot.profile_id];var entity:=entity_for(profile,slot,region.id)
			if query==null:query=service.space(view)
			var reason:="identity-occupied" if not view.entity(slot.id).is_empty() else safe_placement(service,view,query,plan,entity,profile,pending,actors)
			var row:Dictionary={"id":slot.id,"profile_id":profile.id,"plan_sha256":stamp,"status":"placed" if reason.is_empty() else "skipped","reason":reason,"source_world_revision":view.get_revision()}
			marker.entries[slot.id]=row.duplicate(true);rows.append(row)
			if reason.is_empty():operations.append({"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity});pending.append(entity)
	if rows.is_empty():return service.failure("ALREADY_SEEDED","no unprocessed persistent dressing slots")
	operations.append(service.extension_change(KEY,marker,view))
	return {"ok":true,"code":"OK","world_changes":operations,"fact_changes":[],"dressing_results":rows,"scope":"sole transaction DTO; rejected placement remains durably skipped; no stocks or implicit old-plan fill"}
