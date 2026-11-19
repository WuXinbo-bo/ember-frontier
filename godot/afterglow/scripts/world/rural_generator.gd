extends RefCounted
## Finite RH-HOME/RH-VILLAGE, new worlds only. Never regenerate an imported town.
const Data = preload("res://scripts/world/world_data.gd")
const SITE = "res://data/world/rural-site-v1.json"
const BUILDINGS = "res://data/world/rural-buildings-v2.json"
const Settlement = preload("res://scripts/world/settlement_generator.gd")
const Landscape = preload("res://scripts/world/landscape_generator.gd")
const Contract = preload("res://scripts/world/generation_contract.gd")
const Dressing = preload("res://scripts/world/dressing_layout.gd")

static func generate_settlement(seed: int=713,profiles: Array=[],version:String=Landscape.VERSION) -> Dictionary:
	# Explicit opt-in only. generate()/all rural-1 saves retain their old facts.
	if version==Landscape.VERSION:return Landscape.generate(seed,profiles)
	if version==Settlement.VERSION:return Settlement.generate(seed,profiles)
	return Data.reject("UNSUPPORTED_GENERATOR")

static func draft_settlement_region(seed:int,coord:Vector2i,profiles:Array=[],version:String=Landscape.VERSION,generation_contract:Dictionary={})->Dictionary:
	# Capture with region_generation_input on the main thread. A worker receives
	# only detached values, including the saved layout policy, never WorldState.
	if version==Landscape.VERSION:return Landscape.draft_region(seed,coord,profiles,generation_contract)
	if version==Settlement.VERSION:
		if not generation_contract.is_empty():
			if generation_contract.get("legacy")!=true or Contract.stamp(profiles)!=generation_contract.get("profile_contract_sha256"):return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
			return Settlement.draft_region(seed,coord,profiles,{"version":1})
		return Settlement.draft_region(seed,coord,profiles)
	return Data.reject("UNSUPPORTED_GENERATOR")

static func region_generation_input(world:RefCounted,profiles:Array,dressing_catalog:Variant=null)->Dictionary:
	var identity:Dictionary=world.identity()
	if identity.generatorVersion not in [Landscape.VERSION,Settlement.VERSION]:return Data.reject("GENERATOR_MISMATCH")
	if not Data.json_equal(world.config(),Data.DEFAULT_CONFIG):return Data.reject("GENERATION_CONFIG_MISMATCH")
	var input:=Contract.resolve(world.extension("generation:rural2"),profiles)
	if not input.ok:return input
	var error:=Settlement._profiles_error(input.profiles)
	if error:return Data.reject(error)
	if identity.generatorVersion==Landscape.VERSION:
		var dressing:Dictionary=Dressing.resolve(str(world.extension("generation:rural2").get("dressing_contract_sha256","")),dressing_catalog)
		if not dressing.ok:return dressing
		input.contract.dressing_contract_sha256=dressing.contract_sha256
		input.contract.dressing_profile_input=dressing.profiles
	return {"ok":true,"seed":int(identity.seed),"version":str(identity.generatorVersion),"profiles":input.profiles,"generation_contract":input.contract,"expected_world_revision":world.get_revision(),"dependency":{"world_id":identity.worldId,"seed":identity.seed,"version":identity.generatorVersion,"configuration":world.extension("generation:rural2")}}

static func draft_region_request(input:Dictionary,coord:Vector2i)->Dictionary:
	# Optional owner-facing wrapper, retaining the existing lower-level draft
	# API. Pure captured values only. A owns its runtime epoch/cancellation.
	if absi(coord.x)>Settlement.COORD_LIMIT or absi(coord.y)>Settlement.COORD_LIMIT:return Data.reject("GENERATION_COORD_LIMIT")
	if not input.get("ok",false) or not Data.json_value(input) or not input.get("dependency") is Dictionary or not Data.integer(input.get("seed")) or not input.get("profiles") is Array or not input.get("generation_contract") is Dictionary:return Data.reject("INVALID_GENERATION_REQUEST")
	var dependency:Dictionary=input.dependency
	if not Data.valid_id(dependency.get("world_id")) or dependency.get("seed")!=input.seed or dependency.get("version")!=input.get("version") or not dependency.get("configuration") is Dictionary:return Data.reject("INVALID_GENERATION_REQUEST")
	var draft:Dictionary=draft_settlement_region(int(input.seed),coord,input.profiles,str(input.version),input.generation_contract)
	if draft.ok:draft.input_dependency=dependency.duplicate(true)
	return draft

static func prepare_region(world: RefCounted,coord: Vector2i,profiles: Array=[],expected_revision: int=-1) -> Dictionary:
	if world.identity().generatorVersion==Landscape.VERSION:return Landscape.prepare_region(world,coord,profiles,expected_revision)
	return Settlement.prepare_region(world,coord,profiles,expected_revision)

static func prepare_region_draft(world: RefCounted,draft: Dictionary,expected_revision: int) -> Dictionary:
	if draft.has("input_dependency"):
		var dependency:Variant=draft.input_dependency;var identity:Dictionary=world.identity()
		if not dependency is Dictionary or dependency.get("world_id")!=identity.worldId or dependency.get("seed")!=identity.seed or dependency.get("version")!=identity.generatorVersion:return Data.reject("FOREIGN_GENERATION_REQUEST")
		if not Data.json_equal(dependency.get("configuration"),world.extension("generation:rural2")):return Data.reject("STALE_GENERATION_CONFIGURATION")
	# expected_revision is the caller's CURRENT commit CAS. Unrelated world
	# metadata changes need not throw away a geometry-correct worker result.
	return Settlement.prepare_draft(world,draft,expected_revision,str(world.identity().generatorVersion))

static func _inside(x: float, z: float, r: Array, pad: float = 0.0) -> bool:
	return x >= r[0]-pad and x <= r[2]+pad and z >= r[1]-pad and z <= r[3]+pad

static func _segment_distance(x: float, z: float, a: Array, b: Array) -> float:
	var p := Vector2(x,z)
	var from := Vector2(a[0],a[2])
	var delta := Vector2(b[0]-a[0],b[2]-a[2])
	var t := clampf((p-from).dot(delta)/maxf(delta.length_squared(),0.000001),0.0,1.0)
	return p.distance_to(from+t*delta)

static func layout() -> Dictionary:
	var site: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SITE))
	var building: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BUILDINGS))
	var paths: Array = building.home.paths.duplicate(true)
	for p in paths: p.region_id = "RH-HOME"
	for c in building.site_alignment.requested_connectors:
		paths.append({"id":c.id+":connector","points":c.points.duplicate(true),"clear_width":2.0,"region_id":c.region_id})
	# Rear house-to-shed approach extends to the real shed pad.
	paths.append({"id":"rear-shed-complete","region_id":"RH-HOME","clear_width":2.0,"points":[[12.15,0,25.5],[12.15,0,21.5]]})
	return {"site":site,"buildings":building,"paths":paths,"reservations":building.site_alignment.requested_connectors.duplicate(true)}

static func _surface_material(x: float, z: float, region: Dictionary, plan: Dictionary) -> int:
	if x >= 30 and x < 34 and z >= region.road.z_min and z < region.road.z_max: return 4
	if region.id == "RH-HOME" and _inside(x,z,[8,40,28,48]): return 6
	for p in plan.paths:
		if p.region_id != region.id: continue
		for i in p.points.size()-1:
			if _segment_distance(x,z,p.points[i],p.points[i+1]) <= p.clear_width/2.0: return 4
	return 1

static func generate(seed: int = 713) -> Dictionary:
	var plan := layout()
	var world := {"schemaVersion":1,"worldId":"rural:v1:"+str(seed),"seed":seed,"generatorVersion":"rural-1","revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{},"receipts":{}}
	for proposal in plan.site.regions:
		var r: Dictionary = proposal.duplicate(true)
		var region := {"id":r.id,"kind":"rural","bounds":r.bounds.duplicate(true),"generated":true,"exits":[{"id":r.id+":road","toRegionId":r.connection.to_region,"position":r.connection.inside_point.duplicate(true),"width":4,"direction":"north" if r.id == "RH-HOME" else "south"}],"editAreas":[{"id":r.id+":land","bounds":r.bounds.duplicate(true),"minY":-4,"maxY":20,"operations":["dig","fill","level"]}],"data":{"generationVersion":"rural-1","groundElevation":0}}
		world.regions[r.id] = region
		world.extensions["generation:"+r.id] = {"version":"rural-1","paths":plan.paths.filter(func(p: Dictionary) -> bool: return p.region_id == r.id),"reservations":plan.reservations.filter(func(p: Dictionary) -> bool: return p.region_id == r.id),"groundElevation":0,"resourceIds":[]}
		var n := int(world.config.chunkCells)
		for cz in range(floori(r.bounds.min.z/8.0),ceili(r.bounds.max.z/8.0)):
			for cx in range(8):
				for cy in range(-1,3):
					var cells := PackedInt32Array()
					cells.resize(n**3)
					for ly in n:
						var y := cy*n+ly
						if y < -8 or y >= 0: continue
						for lz in n:
							for lx in n:
								var m := 5 if y == -8 else (3 if y < -3 else 2)
								if y == -1: m = _surface_material((cx*n+lx+0.5)*0.5,(cz*n+lz+0.5)*0.5,r,plan)
								cells[lx+n*(lz+n*ly)] = m
					var key := Data.key(Vector3i(cx,cy,cz))
					world.chunks[key] = {"key":key,"coord":{"x":cx,"y":cy,"z":cz},"cells":cells,"revision":0,"resident":true,"generated":true,"generatorVersion":"rural-1"}
		for candidate in r.resource_site_candidates:
			var pos := {"x":candidate.x,"y":0,"z":candidate.z}
			var entity := {"id":candidate.id,"kind":"tree","regionId":r.id,"position":pos,"bounds":{"min":{"x":pos.x-0.35,"y":0,"z":pos.z-0.35},"max":{"x":pos.x+0.35,"y":4,"z":pos.z+0.35}},"revision":0,"blocksTerrain":true,"supportBounds":[{"min":{"x":pos.x-0.35,"y":-0.5,"z":pos.z-0.35},"max":{"x":pos.x+0.35,"y":0,"z":pos.z+0.35}}],"data":{"solid":true,"opaque":true,"outputId":candidate.id+":drops","harvest":{"phase":"standing","work":0,"seconds":24,"toolWear":6,"yield":{"log":3}}}}
			world.entities[candidate.id] = entity
			var drop_pos := {"x":pos.x+1.0,"y":0,"z":pos.z}
			var drop_id: String = entity.data.outputId
			world.entities[drop_id] = {"id":drop_id,"kind":"container","regionId":r.id,"position":drop_pos,"bounds":{"min":{"x":drop_pos.x-0.15,"y":0,"z":drop_pos.z-0.15},"max":{"x":drop_pos.x+0.15,"y":0.2,"z":drop_pos.z+0.15}},"revision":0,"blocksTerrain":false,"data":{"dropped":true,"inventoryOwner":"runtime","owner":null,"searched":true,"sourceId":candidate.id}}
			world.extensions["generation:"+r.id].resourceIds.append(candidate.id)
	return world

static func empty_resource_stocks(world: RefCounted) -> Array:
	# Initial facts DTO only. A owns the returned stocks, never stored in world.
	var stocks: Array = []
	for e in world.entities():
		if e.kind == "container" and e.data.get("dropped",false):
			stocks.append({"id":e.id,"items":{},"owner":null,"searched":true,"location":{"x":e.position.x,"y":e.position.y,"z":e.position.z,"regionId":e.regionId,"buildingId":null,"storeyId":null}})
	return stocks
