extends RefCounted
## Explicit new-world landscape revision. rural-1/2 are never upgraded on load.
const Legacy=preload("res://scripts/world/settlement_generator.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Ecology=preload("res://scripts/world/ecology_layout.gd")
const Dressing=preload("res://scripts/world/dressing_layout.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Broad=preload("res://scripts/world/broad_terraces.gd")
const Hills=preload("res://scripts/world/local_hills.gd")
const Relief=preload("res://scripts/world/local_relief.gd")
const Site=preload("res://scripts/world/site_relief.gd")
const VERSION="rural-3"

static func _lower_parcels(parcels:Array)->void:
	for parcel:Dictionary in parcels:
		# A low rural homestead, not a five-metre artificial rectangular mound.
		var delta:float=-1.5 if parcel.site_id=="home" else -1.0 if parcel.site_id=="shed" else 0.0
		parcel.origin.y+=delta;parcel.pad.height+=delta
		for port:Dictionary in parcel.entrance_ports:port.position.y+=delta
		for reserve:Dictionary in parcel.use_reservations:reserve.bounds.min.y+=delta;reserve.bounds.max.y+=delta
		for anchor:Dictionary in parcel.npc_anchors:anchor.position.y+=delta

static func _fit_road_pads(parcels:Array)->void:
	# New saved model only. Project the five chosen elevations onto compatible
	# half-metre pad-to-pad slopes BEFORE roads, resources or buildings exist.
	# B's bodies remain 0.52m wide: inverse-distance blending between incompatible
	# pads used to squeeze a metre of rise into one voxel at some random seeds.
	# Finite shortest-path relaxation has one deterministic result; it does not
	# retry a seed, change a profile, write old facts or flatten the whole terrain.
	var heights:Array=[]
	for parcel:Dictionary in parcels:heights.append(float(parcel.pad.height))
	for iteration in parcels.size():
		var next:Array=heights.duplicate()
		for i in parcels.size():
			var a:Array=parcels[i].pad.xz
			for j in parcels.size():
				var b:Array=parcels[j].pad.xz
				var distance:float=Vector2(maxf(maxf(a[0]-b[2],b[0]-a[2]),0.0),maxf(maxf(a[1]-b[3],b[1]-a[3]),0.0)).length()
				var rise:float=floorf(distance*0.25*2.0)*0.5
				next[i]=minf(float(next[i]),float(heights[j])+rise)
		if next==heights:break
		heights=next
	for i in parcels.size():
		var parcel:Dictionary=parcels[i];var delta:float=float(heights[i])-float(parcel.pad.height)
		parcel.origin.y+=delta;parcel.pad.height=heights[i]
		for port:Dictionary in parcel.entrance_ports:port.position.y+=delta
		for reserve:Dictionary in parcel.use_reservations:reserve.bounds.min.y+=delta;reserve.bounds.max.y+=delta
		for anchor:Dictionary in parcel.npc_anchors:anchor.position.y+=delta

static func _garden_plots(plan:Dictionary,noise:FastNoiseLite)->void:
	# S01/S06 spatial relationship, using actual pads and routes rather than
	# guessed image metres. A small kitchen plot and a larger field retain their
	# own persisted rectangles. Reject a candidate instead of blocking an access.
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	for parcel:Dictionary in plan.parcels:
		if parcel.site_id not in ["home","neighbor"]:continue
		var r:Array=parcel.pad.xz
		var width:float=5.0 if parcel.site_id=="home" else 8.0
		var depth:float=4.0 if parcel.site_id=="home" else 5.0
		var candidates:Array=[[r[0]-width-2,r[1]+1,r[0]-2,r[1]+1+depth],[r[2]+2,r[1]+1,r[2]+2+width,r[1]+1+depth],[r[0]+1,r[1]-depth-2,r[0]+1+width,r[1]-2],[r[0]+1,r[3]+2,r[0]+1+width,r[3]+2+depth]]
		if plan.height.get("grade_model","") in [Hills.MODEL,Relief.MODEL,Site.MODEL]:
			# Same one household plot, bounded alternatives along its real edge.
			# Do not silently lose a kitchen plot because the first four slots hit
			# the new road. Actual pad/route/field clearance still decides placement.
			for shift:float in [-4.0,4.0,-8.0,8.0]:
				candidates.append_array([[r[0]-width-2,r[1]+1+shift,r[0]-2,r[1]+1+depth+shift],[r[2]+2,r[1]+1+shift,r[2]+2+width,r[1]+1+depth+shift],[r[0]+1+shift,r[1]-depth-2,r[0]+1+width+shift,r[1]-2],[r[0]+1+shift,r[3]+2,r[0]+1+width+shift,r[3]+2+depth]])
		for rect:Array in candidates:
			if rect[0]<ox+1 or rect[1]<oz+1 or rect[2]>ox+63 or rect[3]>oz+63:continue
			var clear:bool=true
			for other:Dictionary in plan.parcels:
				if Dressing._overlap(rect,other.pad.xz,1.0):clear=false
			for land:Dictionary in plan.landforms:
				if Dressing._overlap(rect,land.xz,0.5):clear=false
			if not clear:continue
			for z in range(floori(rect[1]),ceili(rect[3])+1):
				for x in range(floori(rect[0]),ceili(rect[2])+1):
					for path:Dictionary in plan.paths:
						for i in path.points.size()-1:
							if Legacy._distance(x,z,path.points[i],path.points[i+1]).x<float(path.width)*0.5+1.25:clear=false
			if not clear:continue
			var x:float=(float(rect[0])+float(rect[2]))*0.5;var z:float=(float(rect[1])+float(rect[3]))*0.5
			plan.landforms.append({"id":str(parcel.id)+":kitchen-plot","use":"field","purpose":"small-kitchen-plot" if parcel.site_id=="home" else "household-field","xz":rect,"height":Legacy._snap(Legacy._terrain_height(plan,noise,x,z)),"blend":1.0,"material":2})
			break

static func plan_region(seed:int,coord:Vector2i,profiles:Array=[],generation_contract:Dictionary={})->Dictionary:
	# Capture on the owner thread; draft workers receive only detached values.
	var dressing_input:Variant=generation_contract.get("dressing_profile_input")
	var dressing_hash:String=generation_contract.get("dressing_contract_sha256","")
	if not dressing_hash.is_empty():
		var resolved:Dictionary=Dressing.resolve(dressing_hash,dressing_input)
		if not resolved.ok:return resolved
		dressing_input=resolved.profiles
	var input:Dictionary
	if generation_contract.is_empty():input=Contract.fresh(profiles)
	elif generation_contract.get("legacy",false):
		if Contract.stamp(profiles)!=generation_contract.get("profile_contract_sha256"):return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
		input={"ok":true,"profiles":profiles,"contract":generation_contract}
	else:input=Contract.resolve(generation_contract,profiles)
	if not input.ok:return input
	profiles=input.profiles
	var selection:Dictionary=input.contract.get("residential_selection",{"version":1})
	selection=selection.duplicate(true)
	if input.contract.has("layout_policy"):selection.layout_policy=input.contract.layout_policy.duplicate(true)
	var prepared:Dictionary=Legacy.plan_region(seed,coord,profiles,selection)
	if not prepared.ok:return prepared
	var plan:Dictionary=prepared.plan;var noise:=Legacy._noise(seed)
	plan.generator_version=VERSION
	plan.height.grade_model=input.contract.get("landscape_model","organic-local-v1")
	plan.height.terrain_revision=8 if plan.height.grade_model==Site.MODEL else 7 if plan.height.grade_model==Relief.MODEL else 6 if plan.height.grade_model==Hills.MODEL else 5 if plan.height.grade_model==Broad.MODEL else 4 if plan.height.grade_model=="village-contours-v4" else 3 if plan.height.grade_model=="local-apron-v3" else 2 if plan.height.grade_model=="local-apron-v2" else 1
	plan.surface_style="rural-quality-v1"
	for key:String in Contract.PIN_FIELDS:
		if input.contract.has(key):plan[key]=input.contract[key].duplicate(true) if input.contract[key] is Array or input.contract[key] is Dictionary else input.contract[key]
	var all_parcels:Array=[]
	for neighbor:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
		var parcels:Array=Legacy._parcels(seed,neighbor,noise,profiles,selection)
		_lower_parcels(parcels)
		all_parcels.append_array(parcels)
	if plan.height.grade_model in ["local-apron-v3","village-contours-v4"]:_fit_road_pads(all_parcels)
	if plan.height.grade_model==Broad.MODEL:Broad.fit_pads(all_parcels)
	if plan.height.grade_model==Hills.MODEL:Hills.fit_pads(all_parcels,noise)
	if plan.height.grade_model==Relief.MODEL:Relief.fit_pads(all_parcels,noise)
	if plan.height.grade_model==Site.MODEL:Site.fit_pads(all_parcels,noise)
	plan.parcels=all_parcels.filter(func(parcel:Dictionary)->bool:return parcel.id.begins_with(plan.region_id+":"))
	plan.grade_controls=[]
	for parcel:Dictionary in all_parcels:plan.grade_controls.append(parcel.pad.duplicate(true))
	if plan.height.grade_model==Broad.MODEL:
		# Absolute ordering and a finite common feature collar. An edge owner
		# samples exactly the same relevant landforms as its neighbour; cells
		# already committed to the world are never sampled from this grid again.
		var lands:Array=[]
		for z in range(coord.y-1,coord.y+2):
			for x in range(coord.x-1,coord.x+2):lands.append_array(Legacy._landforms(Vector2i(x,z),noise))
		Broad.prepare(plan,noise,lands)
	if plan.height.grade_model==Hills.MODEL:
		var lands:Array=[]
		for z in range(coord.y-1,coord.y+2):
			for x in range(coord.x-1,coord.x+2):lands.append_array(Hills.landforms(Legacy._landforms(Vector2i(x,z),noise),noise))
		plan.landforms=Hills.landforms(plan.landforms,noise)
		Hills.prepare(plan,noise,lands)
	if plan.height.grade_model==Relief.MODEL:
		var lands:Array=[]
		for z in range(coord.y-1,coord.y+2):
			for x in range(coord.x-1,coord.x+2):lands.append_array(Relief.landforms(Legacy._landforms(Vector2i(x,z),noise),noise))
		plan.landforms=Relief.landforms(plan.landforms,noise)
		Relief.prepare(plan,noise,lands)
	if plan.height.grade_model==Site.MODEL:
		var lands:Array=[]
		for z in range(coord.y-1,coord.y+2):
			for x in range(coord.x-1,coord.x+2):lands.append_array(Site.landforms(Legacy._landforms(Vector2i(x,z),noise),noise))
		plan.landforms=Site.landforms(plan.landforms,noise)
		Site.prepare(plan,noise,lands)
	for port:Dictionary in plan.road_ports:
		port.position.y=Legacy._snap(Legacy._road_grade(plan,noise,port.position.x,port.position.z))
		if plan.height.grade_model in ["village-contours-v4",Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]:port.width=2.5 if port.direction in ["north","south"] else 1.5
	plan.paths=Legacy._roads(plan,noise)
	if plan.paths.is_empty():return Data.reject("NO_SETTLEMENT_ROAD",JSON.stringify(plan.get("road_error",{})))
	if plan.height.grade_model in ["village-contours-v4",Broad.MODEL,Hills.MODEL,Relief.MODEL,Site.MODEL]:_garden_plots(plan,noise)
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
	var dressing:=Dressing.plan_slots(plan,dressing_input)
	plan.dressing=dressing.slots;plan.dressing_version=1
	plan.dressing_contract_sha256=dressing.contract_sha256
	plan.dressing_candidate_rejections=dressing.skipped
	plan.dressing_footprints=dressing.footprints
	plan.ecology=Ecology.patches(plan)
	return {"ok":true,"plan":plan}

static func draft_region(seed:int,coord:Vector2i,profiles:Array=[],generation_contract:Dictionary={})->Dictionary:
	var started:=Time.get_ticks_usec();var prepared:=plan_region(seed,coord,profiles,generation_contract)
	if not prepared.ok:return prepared
	return Legacy.draft_plan(prepared.plan,started)

static func generate(seed:int=713,profiles:Array=[],generation_contract:Dictionary={})->Dictionary:
	var input:=Contract.fresh(profiles) if generation_contract.is_empty() else Contract.resolve(generation_contract,profiles)
	if not input.ok:return input
	profiles=input.profiles
	var world:Dictionary={"schemaVersion":1,"worldId":"rural:v3:"+str(seed),"seed":seed,"generatorVersion":VERSION,"revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{},"receipts":{}}
	for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
		var draft:=draft_region(seed,coord,profiles,input.contract)
		if not draft.ok:return draft
		world.regions[draft.region.id]=draft.region
		world.chunks.merge(draft.chunks);world.entities.merge(draft.entities)
		world.extensions["generation:"+draft.region.id]=draft.plan
	# Retain the existing extension key/API for A, not a second configuration.
	world.extensions["generation:rural2"]={"schema":"afterglow-rural2-configuration-v1","generator_version":VERSION,"profile_contract_sha256":Legacy._profile_stamp(profiles),"max_regions":Legacy.MAX_REGIONS,"coord_limit":Legacy.COORD_LIMIT,"ecology_version":1,"dressing_contract_sha256":Dressing.contract_sha256()}
	for key:String in Contract.PIN_FIELDS:
		if input.contract.has(key):world.extensions["generation:rural2"][key]=input.contract[key].duplicate(true) if input.contract[key] is Array or input.contract[key] is Dictionary else input.contract[key]
	return world

static func prepare_region(world:RefCounted,coord:Vector2i,profiles:Array=[],expected_revision:int=-1,dressing_catalog:Variant=null)->Dictionary:
	if world.identity().generatorVersion!=VERSION:return Data.reject("GENERATOR_MISMATCH")
	if expected_revision>=0 and expected_revision!=world.get_revision():return Data.reject("STALE_REVISION")
	var id:=Legacy.region_id(coord)
	if not world.region(id).is_empty():return {"ok":true,"already_generated":true,"plan":world.extension("generation:"+id),"world_changes":[],"initial_stocks":[]}
	var config:Variant=world.extension("generation:rural2")
	if not config is Dictionary or config.get("generator_version")!=VERSION:return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
	var input:=Contract.resolve(config,profiles)
	if not input.ok:return input
	profiles=input.profiles
	var error:=Legacy._profiles_error(profiles)
	if error:return Data.reject(error)
	var dressing:Dictionary=Dressing.resolve(str(config.get("dressing_contract_sha256","")),dressing_catalog)
	if not dressing.ok:return dressing
	input.contract.dressing_contract_sha256=dressing.contract_sha256
	input.contract.dressing_profile_input=dressing.profiles
	var draft:=draft_region(int(world.identity().seed),coord,profiles,input.contract)
	if not draft.ok:return draft
	return Legacy.prepare_draft(world,draft,world.get_revision(),VERSION)
