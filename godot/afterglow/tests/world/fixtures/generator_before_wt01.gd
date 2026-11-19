extends RefCounted
## R34 new-world entry. Produces detached values; A owns scheduling/commit and
## B owns module/content registration. Never regenerate an explored region.
const Data=preload("res://scripts/world/world_data.gd")
const Terrain=preload("res://scripts/world/factory_landscape.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const Site=preload("res://scripts/world/site_relief.gd")
const Ecology=preload("res://scripts/world/ecology_layout.gd")
const RegionalSites=preload("res://scripts/world/factory_regional_sites.gd")
const FactoryEcology=preload("res://scripts/world/factory_ecology.gd")
const Orientation=preload("res://scripts/world/factory_parcel_orientation.gd")
const VERSION=Terrain.VERSION
const SCENARIO=Terrain.SCENARIO
const SCHEMA="afterglow-factory-settlement-plan-v1"
const CONFIG_KEY=Contract.EXTENSION

static func region_id(coord:Vector2i)->String:
	return Terrain.region_id(coord)

static func _coord_valid(coord:Vector2i)->bool:
	return absi(coord.x)<=Terrain.COORD_LIMIT and absi(coord.y)<=Terrain.COORD_LIMIT

static func _missing_roles(profiles:Array)->Array:
	var missing:Array=[]
	for role:String in ["home","workshop","storage"]:
		if not profiles.any(func(p:Dictionary)->bool:return p.get("generation_role",p.get("category",""))==role):missing.append(role)
	return missing

static func _resource_stocks(entities:Array)->Array:
	var stocks:Array=[]
	for entity:Dictionary in entities:
		if entity.get("kind")!="container" or not entity.get("data",{}).get("dropped",false) or not entity.data.has("sourceId"):continue
		var p:Dictionary=entity.position
		stocks.append({"id":entity.id,"items":{},"owner":null,"searched":true,"location":{"x":p.x,"y":p.y,"z":p.z,"regionId":entity.regionId,"buildingId":null,"storeyId":null}})
	stocks.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.id<b.id)
	return stocks

static func initial_resource_stocks(world_or_snapshot:Variant)->Array:
	# First registration only. A's assembler decides whether a stock already
	# exists; this helper never fills or replaces an existing harvested stock.
	if world_or_snapshot is Dictionary:return _resource_stocks(world_or_snapshot.get("entities",{}).values())
	return _resource_stocks(world_or_snapshot.entities())

static func _lots(seed:int,coord:Vector2i,profiles:Array,content_version:int=1)->Array:
	var result:Array=[]
	# Purpose slots are finite and do not add population or items. Definitions
	# determine the complete footprint and service collar, never a guessed box.
	var specs:Array=[]
	if coord==Vector2i.ZERO:specs=[["home","home",6,24],["woodwork","workshop",6,6]]
	elif coord==Vector2i(0,-1):
		var store_role:String="supply" if content_version>=3 and profiles.any(func(p:Dictionary)->bool:return p.get("generation_role")=="supply") else "storage"
		specs=[["store",store_role,6,24],["neighbor","home",6,6]]
	elif Terrain.hash_key(seed,"layout","site:%d:%d"%[coord.x,coord.y])%3==0:specs=[["field-stockyard","storage",6,22]]
	for spec:Array in specs:
		var candidates:Array=profiles.filter(func(p:Dictionary)->bool:return p.get("generation_role",p.get("category",""))==spec[1])
		if content_version>=3:
			var designs:Array=candidates.filter(func(p:Dictionary)->bool:return p.has("visual_family") and p.has("design_id"))
			if not designs.is_empty():candidates=designs
		else:candidates=candidates.filter(func(p:Dictionary)->bool:return not p.has("visual_family") and not p.has("design_id"))
		if candidates.is_empty():continue
		var choice:int=Terrain.hash_key(seed,"layout","family:"+region_id(coord)+":"+spec[0])%candidates.size()
		if content_version>=3 and spec[0]=="neighbor" and candidates.size()>1:choice=(Terrain.hash_key(seed,"layout","family:RH-HOME:home")+1)%candidates.size()
		var selected:Dictionary=candidates[choice]
		if content_version>=4:
			var id:String=region_id(coord)+":"+str(spec[0])
			var oriented:Dictionary=Orientation.parcel(selected,Vector2(coord.x*64+float(spec[2]),coord.y*64+float(spec[3])),Vector2(coord.x*64+34,coord.y*64+30),id)
			oriented.merge({"id":id,"site_id":spec[0],"profile_id":selected.id,"definition_id":selected.id,"definition_version":selected.version,"geometry_version":selected.geometry_version},true)
			result.append(oriented)
			continue
		var f:Dictionary=selected.footprint
		var x:float=coord.x*64+float(spec[2])-float(f.min.x)
		var z:float=coord.y*64+float(spec[3])-float(f.min.z)
		var pad:Array=[x+f.min.x-1.0,z+f.min.z-1.0,x+f.max.x+1.0,z+f.max.z+1.0]
		for r:Array in selected.foundation.get("pad_rectangles",[]):pad=[minf(pad[0],x+r[0]),minf(pad[1],z+r[1]),maxf(pad[2],x+r[2]),maxf(pad[3],z+r[3])]
		var ports:Array=[]
		for p:Dictionary in selected.ports:
			var pos:Array=p.position
			var world:Dictionary=Terrain.vec(x+pos[0],0,z+pos[2])
			var use_points:Array=[]
			for use:Array in p.use_points:
				var at:Dictionary=Terrain.vec(x+use[0],0,z+use[2]);use_points.append(at)
				var radius:float=float(p.clearance.radius)+0.5
				pad=[minf(pad[0],at.x-radius),minf(pad[1],at.z-radius),maxf(pad[2],at.x+radius),maxf(pad[3],at.z+radius)]
			ports.append({"id":p.id,"position":world,"direction":p.direction,"width":p.get("width",1.6),"purpose":p.purpose,"use_points":use_points,"clearance":p.clearance.duplicate(true)})
			pad=[minf(pad[0],world.x-1),minf(pad[1],world.z-1),maxf(pad[2],world.x+1),maxf(pad[3],world.z+1)]
		result.append({"id":region_id(coord)+":"+spec[0],"site_id":spec[0],"profile_id":selected.id,"definition_id":selected.id,"definition_version":selected.version,"geometry_version":selected.geometry_version,"origin":Terrain.vec(x,0,z),"quarter_turn":0,"footprint":f.duplicate(true),"pad":{"xz":pad,"height":0.0,"blend":4.0},"entrance_ports":ports,"use_reservations":[],"npc_anchors":[]})
	return result

static func _parcels(seed:int,coord:Vector2i,profiles:Array,content_version:int=1)->Dictionary:
	# All active finite sites participate in the SAME deterministic pad fit.
	# A wider halo is unnecessary: pads are >4m from edges and influence <14m.
	var all:Array=[]
	for z in range(coord.y-1,coord.y+2):
		for x in range(coord.x-1,coord.x+2):all.append_array(_lots(seed,Vector2i(x,z),profiles,content_version))
	Site.fit_pads(all,Terrain.noise(seed))
	# The reused fit moves original port/reservation positions. New explicit
	# working points share that same final pad plane; do not leave them at y0.
	for p:Dictionary in all:
		for port:Dictionary in p.entrance_ports:
			for use:Dictionary in port.use_points:use.y=p.pad.height
	var own:Array=all.filter(func(p:Dictionary)->bool:return str(p.id).begins_with(region_id(coord)+":"))
	var ox:float=coord.x*64;var oz:float=coord.y*64
	for p:Dictionary in own:
		var r:Array=p.pad.xz
		if r[0]<ox+2 or r[1]<oz+2 or r[2]>ox+30 or r[3]>oz+44:return Data.reject("MODULE_PROFILE_EXCEEDS_PURPOSE_SLOT",p.id)
		for other:Dictionary in own:
			if p.id!=other.id and r[0]<other.pad.xz[2]+1 and r[2]>other.pad.xz[0]-1 and r[1]<other.pad.xz[3]+1 and r[3]>other.pad.xz[1]-1:return Data.reject("MODULE_PURPOSE_SLOTS_OVERLAP",p.id)
	return {"ok":true,"parcels":own,"controls":all}

static func _clear(plan:Dictionary,x:float,z:float,radius:float)->bool:
	return Ecology.clear_of_routes(plan,x,z,radius)

static func _resources(plan:Dictionary)->void:
	var noise:=Raster._noise(int(plan.seed));var index:Dictionary=Raster._road_index(plan)
	var coord:=Vector2i(plan.region_coord.x,plan.region_coord.z);var ox:float=coord.x*64;var oz:float=coord.y*64
	var sites:Array=[]
	for z in range(23,62,4):
		for x in range(45,62,4):
			var key:String="tree:%d:%d:%d:%d"%[coord.x,coord.y,x,z]
			var h:int=Terrain.hash_key(int(plan.seed),"resources",key)
			if h%5==0:continue
			# A true 2m tread centre supports the trunk and its normal use side.
			var wx:float=ox+x;var wz:float=oz+z
			if not _clear(plan,wx,wz,2.2):continue
			var surface:Dictionary=Raster._sample(plan,noise,wx,wz,false,index)
			if surface.material!=1:continue
			var id:String="r34:%d:%d:%d:tree:%d:%d"%[plan.seed,coord.x,coord.y,x,z]
			var species:String=["broadleaf_tree","conifer_tree","dead_tree"][h%3]
			sites.append({"id":id,"kind":"tree","position":Terrain.vec(wx,surface.height,wz),"output_id":id+":drops","drops_position":Terrain.vec(wx+0.7,surface.height,wz),"use":"forest-edge","source_stream":"resources","appearance":{"version":1,"surface_version":1,"surface_variant":int(h/17)%2,"model":species,"height":4.0*(0.88+float((h/7)%4)*0.04),"yaw":float((h/13)%16)*TAU/16.0}})
	plan.resource_sites=sites
	# Stone is actual exposed editable material3. Never a prop with free yield.
	# Content sources are stable spatial DTOs; A/B/E lock their actual finite
	# stock/knowledge/permission once and record that registration separately.
	plan.source_nodes=[{"id":region_id(coord)+":stone","kind":"voxel","item_id":"stone_m3","material_id":3,"tool_quality":"pickaxe","xz":[ox+46,oz+6,ox+58,oz+18],"owner_region":region_id(coord),"semantics":"amount comes only from actual successful cell edits"}]
	plan.content_anchors=[]
	for local:Vector2 in [Vector2(55,13),Vector2(55,9),Vector2(47,9),Vector2(57,17),Vector2(47,17),Vector2(57,7)]:
		var x:float=ox+local.x;var z:float=oz+local.y
		if not _clear(plan,x,z,0.8):continue
		var p:Dictionary=Terrain.vec(x,Site.height(plan,x,z),z)
		p.regionId=plan.region_id;p.buildingId=null;p.storeyId=null
		plan.content_anchors.append({"id":region_id(coord)+":stockyard-content","purpose":"stockyard-and-recovery","position":p,"source_key":"r34:%d:%d:%d:stockyard"%[plan.seed,coord.x,coord.y],"content_seed":Terrain.hash_key(plan.seed,"content",region_id(coord)+":stockyard"),"registration_owner":"A/B","initialization":"generated-place-once"})
		break

static func _ecology(plan:Dictionary)->void:
	if int(plan.get("generation_content_version",1))>=3:
		plan.ecology=FactoryEcology.patches(plan);return
	var patches:Array=[];var noise:=Raster._noise(int(plan.seed));var roads:Dictionary=Raster._road_index(plan)
	var ox:float=plan.region_coord.x*64;var oz:float=plan.region_coord.z*64
	var rejected:int=0
	for z in range(3,62,3):
		for x in range(3,62,3):
			var h:int=Terrain.hash_key(int(plan.seed),"decor",plan.region_id+":%d:%d"%[x,z])
			if h%4!=0:continue
			var model:String=["quality:v01_fresh_grass","quality:v05_flowering_shrub_sparse","quality:v07_fern"][h%3]
			# Existing image atlas/geometry. No new fake collectible vegetation.
			if not Ecology._append(patches,plan,noise,roads,ox+x+0.25,oz+z+0.25,model,-1,"r34-groundcover",0.65):rejected+=1
	for land:Dictionary in plan.landforms:
		if land.use!="field":continue
		for z in range(ceili(land.xz[1]+1),floori(land.xz[3]-1),2):
			for x in range(ceili(land.xz[0]+1),floori(land.xz[2]-1),2):
				var h:int=Terrain.hash_key(int(plan.seed),"decor",plan.region_id+":field:%d:%d"%[x,z])
				var model:String="quality:"+["c01_rice_vegetative","c02_rice_ripe","c03_rice_stubble"][h%3]
				if not Ecology._append(patches,plan,noise,roads,x+0.25,z+0.25,model,2,"abandoned-field",0.72):rejected+=1
	plan.ecology={"version":1,"patches":patches,"candidate_rejections":rejected,"semantics":"nonblocking unmanaged decoration, never stock or crop yield"}

static func plan_region(seed:int,coord:Vector2i,module_profiles:Array=[],generation_contract:Dictionary={})->Dictionary:
	if not Data.integer(seed) or not _coord_valid(coord):return Data.reject("GENERATION_COORD_LIMIT")
	var input:Dictionary=Contract.fresh(module_profiles) if generation_contract.is_empty() else Contract.resolve(generation_contract,module_profiles)
	if not input.ok:return input
	var parcels:Dictionary=_parcels(seed,coord,input.profiles,int(input.contract.get("content_version",1)))
	if not parcels.ok:return parcels
	var plan:Dictionary={"schema":SCHEMA,"generator_version":VERSION,"scenario":SCENARIO,"seed":seed,"region_id":region_id(coord),"region_coord":{"x":coord.x,"z":coord.y},"configuration_sha256":Contract.digest(input.contract),"spaces":Terrain.spaces(coord),"road_ports":[],"paths":[],"parcels":parcels.parcels,"resource_sites":[],"landforms":[],"grade_controls":[],"height":{},"npc_anchors":[],"anchors":{},"surface_style":"rural-quality-v1","module_seeds":[],"dressing":[],"dressing_footprints":[],"module_profiles_complete":not input.profiles.is_empty()}
	if int(input.contract.get("content_version",1))>=2:plan.generation_content_version=int(input.contract.content_version)
	plan.missing_profile_roles=_missing_roles(input.profiles);plan.module_profiles_complete=plan.missing_profile_roles.is_empty()
	for direction:String in ["north","south","west","east"]:plan.road_ports.append(Terrain.port(seed,coord,direction))
	Terrain.prepare_height(plan,parcels.controls)
	if int(input.contract.get("content_version",1))>=4:
		for p:Dictionary in plan.parcels:p.orientation.target.y=Site.height(plan,p.orientation.target.x,p.orientation.target.z)
	var road:Dictionary=Terrain.roads(plan)
	if not road.ok:return road
	plan.paths=road.paths
	plan.anchors.arrival=Terrain.vec(coord.x*64+34,Site.height(plan,coord.x*64+34,coord.y*64+30),coord.y*64+30)
	plan.anchors.defence_north=Terrain.vec(coord.x*64+34,Site.height(plan,coord.x*64+34,coord.y*64+12),coord.y*64+12)
	plan.anchors.forest=Terrain.vec(coord.x*64+50,Site.height(plan,coord.x*64+50,coord.y*64+30),coord.y*64+30)
	for p:Dictionary in plan.parcels:
		plan.anchors[p.site_id]=p.entrance_ports[0].position.duplicate(true)
		if int(input.contract.get("content_version",1))>=4:
			for anchor:Dictionary in p.npc_anchors:
				var at:Dictionary=anchor.duplicate(true);at.parcel_id=p.id
				plan.npc_anchors.append(at)
		plan.module_seeds.append({"id":"r34:generated:"+p.id,"definition_id":p.definition_id,"definition_version":p.definition_version,"geometry_version":p.geometry_version,"region":plan.region_id,"position":p.origin.duplicate(true),"quarter_turn":p.quarter_turn,"source_key":"r34:%d:%s"%[seed,p.id],"content_seed":Terrain.hash_key(seed,"content",p.id),"purpose":p.site_id,"initialization":"generated-place-once","player_built":false})
	_resources(plan)
	if int(plan.get("generation_content_version",1))>=3:FactoryEcology.add_groves(plan)
	if plan.content_anchors.is_empty():return Data.reject("NO_SAFE_STOCKYARD_CONTENT_ANCHOR")
	_ecology(plan)
	# Keep the established plain location shape used by A. Additional story
	# aliases never create people, rewards, events or a second content registry.
	var north:Dictionary=plan.road_ports[0].position.duplicate(true);north.z+=1.0
	plan.anchors.townward_road=north
	if plan.anchors.has("neighbor"):plan.anchors.neighbor_contact=plan.anchors.neighbor.duplicate(true)
	if plan.anchors.has("woodwork"):plan.anchors.repair_contact=plan.anchors.woodwork.duplicate(true)
	var road_index:Dictionary=Raster._road_index(plan);var noise:=Raster._noise(seed)
	for key:String in plan.anchors:
		var anchor:Dictionary=plan.anchors[key];var low:float=INF;var high:float=-INF
		for dx:float in [-0.26,0.0,0.26]:
			for dz:float in [-0.26,0.0,0.26]:
				var wx:float=(floorf((float(anchor.x)+dx)*2.0)+0.5)*0.5
				var wz:float=(floorf((float(anchor.z)+dz)*2.0)+0.5)*0.5
				var h:float=Raster._sample(plan,noise,wx,wz,false,road_index).height
				low=minf(low,h);high=maxf(high,h)
		if high-low>0.5:return Data.reject("INVALID_STORY_ANCHOR_SUPPORT",key)
		anchor.y=high;anchor.regionId=plan.region_id;anchor.buildingId=null;anchor.storeyId=null
	if plan.has("generation_content_version"):
		var sites:Dictionary=RegionalSites.plan_site(plan)
		if not sites.ok:return sites
		plan.regional_sites=sites.sites
	if int(input.contract.get("story_clue_version",0))==1:_story_clues(plan)
	return {"ok":true,"plan":plan,"generation_contract":input.contract}

static func _story_clues(plan:Dictionary)->void:
	# A persistent environmental description of an actual generated site,
	# attached to its real store source. Not an item, reward, map reveal,
	# permission or substitute for E's onsite reading/survey transaction.
	for seed:Dictionary in plan.module_seeds:
		if seed.purpose!="store":continue
		var clues:Array=[]
		for site:Dictionary in plan.get("regional_sites",[]):
			if site.get("kind")!="stone-roadfall-v1" or site.get("region_id")!=seed.region:continue
			clues.append({"id":str(seed.source_key)+":route-record:"+str(site.id),"version":1,"story_id":"ST03","kind":"route-record","source_key":seed.source_key,"module_id":seed.id,"site_id":site.id,"text":"北向村路曾有塌石挡路，侧肩可绕行；当前通行状况以现场为准。清理前先确认风险和返程补给。"})
		if not clues.is_empty():seed.story_clues=clues

static func draft_region(seed:int,coord:Vector2i,module_profiles:Array=[],generation_contract:Dictionary={})->Dictionary:
	var start:int=Time.get_ticks_usec();var planned:Dictionary=plan_region(seed,coord,module_profiles,generation_contract)
	if not planned.ok:return planned
	return RegionalSites.apply(Raster.draft_plan(planned.plan,start))

static func generate(seed:int=713,module_profiles:Array=[],generation_contract:Dictionary={})->Dictionary:
	var input:Dictionary=Contract.fresh(module_profiles) if generation_contract.is_empty() else Contract.resolve(generation_contract,module_profiles)
	if not input.ok:return input
	if not _missing_roles(input.profiles).is_empty():return Data.reject("MISSING_MODULE_GENERATION_PROFILES","Missing generation roles: "+str(_missing_roles(input.profiles)))
	var world:Dictionary={"schemaVersion":1,"worldId":"r34:factory:"+str(seed),"seed":seed,"generatorVersion":VERSION,"revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{},"receipts":{}}
	world.extensions[CONFIG_KEY]=input.contract
	for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
		var draft:Dictionary=draft_region(seed,coord,input.profiles,input.contract)
		if not draft.ok:return draft
		world.regions[draft.region.id]=draft.region;world.chunks.merge(draft.chunks);world.entities.merge(draft.entities)
		world.extensions["generation:"+draft.region.id]=draft.plan
	return world

static func region_generation_input(world:RefCounted,module_profiles:Array)->Dictionary:
	var identity:Dictionary=world.identity()
	if identity.generatorVersion!=VERSION:return Data.reject("GENERATOR_MISMATCH")
	if not Data.json_equal(world.config(),Data.DEFAULT_CONFIG):return Data.reject("GENERATION_CONFIG_MISMATCH")
	var configuration:Variant=world.extension(CONFIG_KEY);var input:Dictionary=Contract.resolve(configuration,module_profiles)
	if not input.ok:return input
	return {"ok":true,"seed":int(identity.seed),"version":VERSION,"profiles":input.profiles,"generation_contract":input.contract,"expected_world_revision":world.get_revision(),"dependency":{"world_id":identity.worldId,"seed":identity.seed,"version":VERSION,"configuration":configuration}}

static func draft_region_request(input:Dictionary,coord:Vector2i)->Dictionary:
	if not _coord_valid(coord):return Data.reject("GENERATION_COORD_LIMIT")
	if not input.get("ok",false) or not Data.json_value(input) or not Data.integer(input.get("seed")) or input.get("version")!=VERSION or not input.get("profiles") is Array or not input.get("generation_contract") is Dictionary or not input.get("dependency") is Dictionary:return Data.reject("INVALID_GENERATION_REQUEST")
	var dep:Dictionary=input.dependency
	if not Data.valid_id(dep.get("world_id")) or dep.get("seed")!=input.seed or dep.get("version")!=VERSION or not Data.json_equal(dep.get("configuration"),input.generation_contract):return Data.reject("INVALID_GENERATION_REQUEST")
	var draft:Dictionary=draft_region(input.seed,coord,input.profiles,input.generation_contract)
	if draft.ok:draft.input_dependency=dep.duplicate(true)
	return draft

static func prepare_region_draft(world:RefCounted,draft:Dictionary,expected_revision:int)->Dictionary:
	if expected_revision!=world.get_revision():return Data.reject("STALE_REVISION")
	var identity:Dictionary=world.identity()
	if identity.generatorVersion!=VERSION:return Data.reject("GENERATOR_MISMATCH")
	if not draft.get("ok",false) or not draft.get("plan") is Dictionary or not draft.get("region") is Dictionary or not draft.get("chunks") is Dictionary or not draft.get("entities") is Dictionary or not draft.get("input_dependency") is Dictionary:return Data.reject("INVALID_REGION_DRAFT")
	var dep:Dictionary=draft.input_dependency;var config:Variant=world.extension(CONFIG_KEY)
	if dep.get("world_id")!=identity.worldId or dep.get("seed")!=identity.seed or dep.get("version")!=VERSION:return Data.reject("FOREIGN_GENERATION_REQUEST")
	if not Data.json_equal(dep.get("configuration"),config):return Data.reject("STALE_GENERATION_CONFIGURATION")
	var plan:Dictionary=draft.plan;var point:Variant=plan.get("region_coord")
	if not point is Dictionary or not Data.integer(point.get("x")) or not Data.integer(point.get("z")):return Data.reject("INVALID_REGION_DRAFT")
	var coord:=Vector2i(point.x,point.z);var id:String=region_id(coord)
	if not _coord_valid(coord) or plan.get("schema")!=SCHEMA or plan.get("generator_version")!=VERSION or plan.get("scenario")!=SCENARIO or plan.get("seed")!=identity.seed or plan.get("region_id")!=id or plan.get("configuration_sha256")!=Contract.digest(config) or draft.region.get("id")!=id:return Data.reject("INVALID_REGION_DRAFT")
	# Even a valid late worker cannot replay modules, trees, drops or old cells.
	if not world.region(id).is_empty():return {"ok":true,"already_generated":true,"plan":world.extension("generation:"+id),"world_changes":[],"initial_stocks":[],"module_seeds":[],"content_anchors":[]}
	if not Data.json_equal(world.config(),Data.DEFAULT_CONFIG):return Data.reject("GENERATION_CONFIG_MISMATCH")
	if world.regions().size()>=Terrain.MAX_REGIONS or world.chunk_keys().size()+256>8192:return Data.reject("GENERATION_CAPACITY")
	var bounds:Dictionary={"min":Terrain.vec(coord.x*64,-4,coord.y*64),"max":Terrain.vec((coord.x+1)*64,20,(coord.y+1)*64)}
	if draft.chunks.size()!=256 or not Data.json_equal(draft.region.get("bounds"),bounds):return Data.reject("INVALID_REGION_DRAFT","bounds/lattice")
	for z in 8:
		for x in 8:
			for y in range(-1,3):
				var key:String=Data.key(Vector3i(coord.x*8+x,y,coord.y*8+z))
				if not draft.chunks.has(key):return Data.reject("INVALID_REGION_DRAFT","lattice")
				if not world.chunk(key).is_empty():return Data.reject("GENERATION_CHUNK_OCCUPIED",key)
	var changes:Array=[{"op":"region.put","id":id,"before_exists":false,"before":null,"after":draft.region}]
	for key:String in draft.chunks:changes.append({"op":"chunk.put","id":key,"before_exists":false,"before":null,"after":draft.chunks[key]})
	for key:String in draft.entities:
		if not world.entity(key).is_empty() or key in world.retired_entity_ids():return Data.reject("GENERATION_ENTITY_OCCUPIED",key)
		changes.append({"op":"entity.put","id":key,"before_exists":false,"before":null,"after":draft.entities[key]})
	changes.append({"op":"extension.set","id":"generation:"+id,"before_exists":false,"before":null,"after":plan})
	var stocks:Array=_resource_stocks(draft.entities.values())
	return {"ok":true,"already_generated":false,"expected_world_revision":expected_revision,"plan":plan,"world_changes":changes,"initial_stocks":stocks,"module_seeds":plan.module_seeds.duplicate(true),"content_anchors":plan.content_anchors.duplicate(true),"cost":draft.cost}
