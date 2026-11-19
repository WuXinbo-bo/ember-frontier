extends RefCounted
## Explicit new-world landscape revision. rural-1/2 are never upgraded on load.
const Legacy=preload("res://scripts/world/settlement_generator.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Ecology=preload("res://scripts/world/ecology_layout.gd")
const Dressing=preload("res://scripts/world/dressing_layout.gd")
const VERSION="rural-3"

static func _lower_parcels(parcels:Array)->void:
	for parcel:Dictionary in parcels:
		# A low rural homestead, not a five-metre artificial rectangular mound.
		var delta:float=-1.5 if parcel.site_id=="home" else -1.0 if parcel.site_id=="shed" else 0.0
		parcel.origin.y+=delta;parcel.pad.height+=delta
		for port:Dictionary in parcel.entrance_ports:port.position.y+=delta
		for reserve:Dictionary in parcel.use_reservations:reserve.bounds.min.y+=delta;reserve.bounds.max.y+=delta
		for anchor:Dictionary in parcel.npc_anchors:anchor.position.y+=delta

static func plan_region(seed:int,coord:Vector2i,profiles:Array=[])->Dictionary:
	var prepared:Dictionary=Legacy.plan_region(seed,coord,profiles)
	if not prepared.ok:return prepared
	var plan:Dictionary=prepared.plan;var noise:=Legacy._noise(seed)
	plan.generator_version=VERSION
	plan.height.grade_model="organic-local-v1"
	plan.height.terrain_revision=1
	plan.surface_style="rural-quality-v1"
	_lower_parcels(plan.parcels)
	plan.grade_controls=[]
	for neighbor:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
		var parcels:Array=Legacy._parcels(seed,neighbor,noise,profiles)
		_lower_parcels(parcels)
		for parcel:Dictionary in parcels:plan.grade_controls.append(parcel.pad.duplicate(true))
	for port:Dictionary in plan.road_ports:port.position.y=Legacy._snap(Legacy._road_grade(plan,noise,port.position.x,port.position.z))
	plan.paths=Legacy._roads(plan,noise)
	if plan.paths.is_empty():return Data.reject("NO_SETTLEMENT_ROAD",JSON.stringify(plan.get("road_error",{})))
	plan.anchors={};plan.npc_anchors=[]
	for parcel:Dictionary in plan.parcels:
		plan.anchors[parcel.site_id]=parcel.entrance_ports[0].position.duplicate()
		plan.npc_anchors.append({"id":plan.region_id+":"+parcel.site_id+":activity","purpose":parcel.site_id,"position":parcel.entrance_ports[0].position.duplicate(),"parcel_id":parcel.id})
		for anchor:Dictionary in parcel.npc_anchors:
			var a:Dictionary=anchor.duplicate(true);a.id=parcel.id+":"+a.id;a.parcel_id=parcel.id
			plan.npc_anchors.append(a)
	var arrival:Dictionary=plan.paths[1].points[-4].duplicate()
	arrival.y=Legacy._sample(plan,noise,arrival.x,arrival.z,false).height
	plan.anchors.arrival=arrival
	plan.resource_sites=Ecology.tree_sites(plan)
	# B owns geometry/collision and its final safety/skip marker. C owns these
	# immutable purpose/coordinate slots in the same generation plan.
	var dressing:=Dressing.plan_slots(plan)
	plan.dressing=dressing.slots;plan.dressing_version=1
	plan.dressing_contract_sha256=dressing.contract_sha256
	plan.dressing_candidate_rejections=dressing.skipped
	plan.dressing_footprints=dressing.footprints
	plan.ecology=Ecology.patches(plan)
	return {"ok":true,"plan":plan}

static func draft_region(seed:int,coord:Vector2i,profiles:Array=[])->Dictionary:
	var started:=Time.get_ticks_usec();var prepared:=plan_region(seed,coord,profiles)
	if not prepared.ok:return prepared
	return Legacy.draft_plan(prepared.plan,started)

static func generate(seed:int=713,profiles:Array=[])->Dictionary:
	var world:Dictionary={"schemaVersion":1,"worldId":"rural:v3:"+str(seed),"seed":seed,"generatorVersion":VERSION,"revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{},"receipts":{}}
	for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
		var draft:=draft_region(seed,coord,profiles)
		if not draft.ok:return draft
		world.regions[draft.region.id]=draft.region
		world.chunks.merge(draft.chunks);world.entities.merge(draft.entities)
		world.extensions["generation:"+draft.region.id]=draft.plan
	# Retain the existing extension key/API for A, not a second configuration.
	world.extensions["generation:rural2"]={"schema":"afterglow-rural2-configuration-v1","generator_version":VERSION,"profile_contract_sha256":Legacy._profile_stamp(profiles),"max_regions":Legacy.MAX_REGIONS,"coord_limit":Legacy.COORD_LIMIT,"ecology_version":1,"dressing_contract_sha256":Dressing.contract_sha256()}
	return world

static func prepare_region(world:RefCounted,coord:Vector2i,profiles:Array=[],expected_revision:int=-1)->Dictionary:
	if world.identity().generatorVersion!=VERSION:return Data.reject("GENERATOR_MISMATCH")
	if expected_revision>=0 and expected_revision!=world.get_revision():return Data.reject("STALE_REVISION")
	var id:=Legacy.region_id(coord)
	if not world.region(id).is_empty():return {"ok":true,"already_generated":true,"plan":world.extension("generation:"+id),"world_changes":[],"initial_stocks":[]}
	var error:=Legacy._profiles_error(profiles)
	if error:return Data.reject(error)
	var config:Variant=world.extension("generation:rural2")
	if not config is Dictionary or config.get("generator_version")!=VERSION or config.get("profile_contract_sha256")!=Legacy._profile_stamp(profiles):return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
	if config.get("dressing_contract_sha256")!=Dressing.contract_sha256():return Data.reject("DRESSING_PROFILE_VERSION_MISMATCH")
	var draft:=draft_region(int(world.identity().seed),coord,profiles)
	if not draft.ok:return draft
	return Legacy.prepare_draft(world,draft,world.get_revision(),VERSION)
