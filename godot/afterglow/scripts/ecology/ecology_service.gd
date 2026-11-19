extends RefCounted
## One World extension and A clock. B lends the SAME DomainDraft; only this
## owner settles ecology materials. No commit, private process or hidden stock.
const KEY:="r34:ecology"
const Rules=preload("res://scripts/ecology/ecology_rules.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Earthwork=preload("res://scripts/terrain/terrain_batch.gd")
const Sources=preload("res://scripts/ecology/ecology_sources.gd")
const Entities=preload("res://scripts/ecology/ecology_entities.gd")
const Contact=preload("res://scripts/buildings/interaction_contact.gd")
const ZoneDef=preload("res://scripts/planning/zone_definitions.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Context=preload("res://scripts/actions/domain_context.gd")
var context:Dictionary={}
var _services:Dictionary={}
var _host:WeakRef
var _validation_token:Dictionary={}
var _validation_result:Dictionary={}

func configure(value:Dictionary)->void:
 _services.clear();context={};_validation_token.clear();_validation_result.clear()
 if not value.get("world") is RefCounted:return
 context=Context.isolate(value)
 _host=weakref(value.runtime) if value.get("runtime") is RefCounted else null
 for name:String in value.get("services",{}):
  if value.services[name] is RefCounted and value.services[name]!=self:_services[name]=weakref(value.services[name])
func service(name:String)->Variant:return _services[name].get_ref() if _services.has(name) else null
func state(overrides:Dictionary={})->Dictionary:
 var value:Variant=overrides[KEY] if overrides.has(KEY) else context.world.extension(KEY) if not context.is_empty() else null
 return value if value is Dictionary else Rules.initial()
func now()->float:return float(context.clock.call())
func _detailed(region:String,ground_batch:Dictionary={})->bool:
 # Only a stack-local synchronous batch may reuse this full predicate. Calls
 # without an explicit batch remain fresh, including cold/warm and reload.
 if not ground_batch.has("detailed_regions"):ground_batch.detailed_regions={}
 if ground_batch.detailed_regions.has(region):return ground_batch.detailed_regions[region]
 var detailed:bool=context.get("region_is_detailed") is Callable and context.region_is_detailed.call(region)
 if detailed:detailed=not context.world.has_method("region_is_resident") or context.world.region_is_resident(region)
 ground_batch.detailed_regions[region]=detailed
 return detailed
func _loc(region:String,cell:Dictionary)->Dictionary:
 var s:float=context.world.config().cellSize
 return {"x":(float(cell.x)+.5)*s,"y":float(cell.y)*s,"z":(float(cell.z)+.5)*s,"regionId":region,"buildingId":null,"storeyId":null}
func _empty()->Dictionary:return {"ok":true,"code":"OK","world_changes":[],"fact_changes":[],"events":[],"duration":0.0}

func preview_zone(spec:Dictionary)->Dictionary:
 if context.is_empty():return Data.reject("MISSING_WORLD")
 var b:Variant=spec.get("bounds");var kind:String=str(spec.get("kind",""));var region:String=str(spec.get("region_id",""))
 if kind not in ["forestry","farm","forage","clear","terrain","stockpile","patrol"] or not b is Dictionary or not b.has_all(["x0","z0","x1","z1"]) or not [b.x0,b.z0,b.x1,b.z1].all(Data.integer) or b.x1<=b.x0 or b.z1<=b.z0 or (b.x1-b.x0)*(b.z1-b.z0)>Rules.MAX_ZONE_CELLS:return Data.reject("INVALID_ECOLOGY_ZONE")
 var cells:Array=[];var excluded:Array=[];var reasons:Dictionary={};var water:int=0;var policy:Dictionary=spec.get("policy",{});var ground_batch:Dictionary={}
 for z:int in range(int(b.z0),int(b.z1)):
  for x:int in range(int(b.x0),int(b.x1)):
   var found:=_ground(region,x,z,kind,policy,"",ground_batch)
   if found.ok:cells.append(found.cell);water+=int(found.get("water",0))
   else:
    excluded.append({"x":x,"z":z,"code":found.code});reasons[found.code]=int(reasons.get(found.code,0))+1
 if kind=="terrain" and not cells.is_empty():
  var zone:Dictionary=spec.duplicate(true);zone.cells=cells
  var graded:Dictionary=Earthwork.preview(context.world,zone)
  if graded.get("ok",false):graded.excluded.append_array(excluded)
  return graded
 return {"ok":not cells.is_empty(),"code":"OK" if not cells.is_empty() else "NO_VALID_CELLS","cells":cells,"excluded":excluded,"reasons":reasons,"estimate":{"cells":cells.size(),"soil_m3":float(cells.size())*.125 if kind=="farm" else 0.0,"water_units":water},"world_revision":context.world.get_revision()}

func _ground(region:String,x:int,z:int,kind:String,policy:Dictionary={},ignore_id:String="",ground_batch:Dictionary={})->Dictionary:
 var world:RefCounted=context.world;var s:float=world.config().cellSize
 if not _detailed(region,ground_batch):return Data.reject("REGION_NOT_DETAILED")
 var height:Variant=world.surface_height((x+.5)*s,(z+.5)*s)
 if height==null:return Data.reject("UNKNOWN_CELL")
 var y:int=roundi(float(height)/s);var cell:Dictionary={"x":x,"y":y,"z":z};var p:=_loc(region,cell)
 if world.region_at(p).get("id")!=region or not world.is_cell_resident(x,y-1,z) or not world.is_cell_resident(x,y,z):return Data.reject("UNLOADED_CELL")
 if kind=="stockpile" and policy.get("mode")=="collect_ground":return {"ok":true,"cell":cell}
 var m:int=world.cell_at(x,y-1,z)
 if m==4:return Data.reject("PROTECTED_ROAD")
 if kind=="farm" and m not in [1,2]:return Data.reject("UNSUITABLE_SOIL")
 if kind=="forestry" and m not in [1,2]:return Data.reject("UNSUITABLE_SOIL")
 if kind in ["stockpile","patrol"]:
  var query:RefCounted=context.spatial.current_space();var foot:Dictionary=query.standing_point(p)
  if foot.is_empty() or absf(float(foot.y)-float(p.y))>.025:return Data.reject("NO_CONTINUOUS_BODY_SUPPORT")
 var radius:float=.25 if kind in ["farm","stockpile","patrol"] else .5
 var bound:Dictionary=G.json_box(AABB(G.point(p)-Vector3(radius,.01,radius),Vector3(radius*2,1.81,radius*2)))
 var objects: Array = world.entities_in_any_bounds([bound]) if kind == "clear" else world.entities_in_bounds(bound)
 for e:Dictionary in objects:
  if kind in ["forestry","forage","clear"] and e.kind=="tree":continue
  if e.id==ignore_id or (kind=="farm" and e.get("kind")=="ecology_bed"):continue
  if e.get("blocksTerrain",true) or e.get("data",{}).has("water_source_id"):return Data.reject("OCCUPIED_OR_PROTECTED")
 if _service_exit_protected(region,p,ground_batch):return Data.reject("PROTECTED_SERVICE_EXIT")
 if kind=="farm" and str(policy.get("crop_id",""))=="rice":
  for dz:int in [-1,0,1]:
   for dx:int in [-1,0,1]:
    if not world.is_cell_known(x+dx,y-1,z+dz) or not world.is_cell_resident(x+dx,y-1,z+dz) or not world.is_cell_resident(x+dx,y,z+dz) or world.region_at(_loc(region,{"x":x+dx,"y":y,"z":z+dz})).get("id")!=region:return Data.reject("RICE_REQUIRES_RESIDENT_BED")
    var neighbour:Variant=world.surface_height((x+dx+.5)*s,(z+dz+.5)*s)
    if neighbour==null or float(neighbour)!=float(height):return Data.reject("RICE_REQUIRES_LEVEL_BED")
 return {"ok":true,"cell":cell,"location":p,"water":2 if policy.get("crop_id")=="rice" else 1}

func _service_exit_protected(region:String,at:Dictionary,ground_batch:Dictionary={})->bool:
 var modules:Variant=service("modules")
 if modules==null:return false
 # A batch belongs to exactly one synchronous preview/advance invocation. No
 # await or authoritative commit occurs inside it; never retain it on self.
 # Keep the original per-point region/32m/1.3m tests, but detach module state
 # once and derive each relevant instance's unchanged ports at most once.
 if not ground_batch.has("module_instances"):
  ground_batch.module_instances=modules.state().get("instances",[])
  ground_batch.module_ports={}
 var Shape=load("res://scripts/modules/module_geometry.gd");var Catalog=load("res://scripts/modules/module_catalog.gd")
 for i:int in ground_batch.module_instances.size():
  var instance:Dictionary=ground_batch.module_instances[i]
  if instance.region!=region or G.point(instance.position).distance_to(G.point(at))>32:continue
  if not ground_batch.module_ports.has(i):ground_batch.module_ports[i]=Shape.ports(instance,Catalog.definition(instance.definition_id))
  for port:Dictionary in ground_batch.module_ports[i]:
   if G.point(port.location).distance_to(G.point(at))<1.3:return true
 return false

func harvest_target(entity:Dictionary,policy:Dictionary)->bool:
 return entity.get("kind")=="tree" and not policy.get("conserve",false) and entity.get("data",{}).get("appearance",{}).get("model")!="dead_tree" and entity.get("data",{}).get("harvest",{}).get("phase")=="standing" and (not policy.get("mature_only",true) or entity.get("data",{}).get("ecology_stage","mature")=="mature")

func standing_harvest_targets(zone:Dictionary)->Array:
 var regions:Dictionary={}
 var min_y:float=INF;var max_y:float=-INF
 for id:String in zone.region_ids:
  if not _detailed(id):continue
  var region:Dictionary=context.world.region(id)
  if region.is_empty():continue
  regions[id]=true
  min_y=minf(min_y,float(region.bounds.min.y));max_y=maxf(max_y,float(region.bounds.max.y))
 if regions.is_empty():return []
 var b:Dictionary=zone.bounds;var size:float=context.world.config().cellSize
 var bounds:Dictionary=G.json_box(AABB(Vector3(float(b.x0)*size,min_y,float(b.z0)*size),Vector3(float(b.x1-b.x0)*size,max_y-min_y,float(b.z1-b.z0)*size)))
 var entities:Array=context.world.entities_in_any_bounds([bounds])
 return entities.filter(func(e:Dictionary)->bool:return regions.has(e.regionId) and harvest_target(e,zone.policy) and ZoneDef.contains_xz(b,G.location(e),size))

func _ordered_tree_jobs(zone:Dictionary,actor_id:String)->Array:
 var rows:Array=[];var actor:Dictionary=context.actor.call(actor_id);var ready:Dictionary={}
 if actor.is_empty() or not zone.get("enabled",false):return rows
 for region:String in zone.region_ids:ready[region]=_detailed(region)
 var targets:Array=standing_harvest_targets(zone) if zone.policy.get("standing_order",false) else zone.target_ids.map(func(id:String)->Dictionary:return context.world.entity(id))
 if targets.is_empty():return rows
 var space:RefCounted=context.spatial.current_space()
 for e:Dictionary in targets:
  if not harvest_target(e,zone.policy) or not ready.get(e.regionId,false):continue
  if not ZoneDef.contains_xz(zone.bounds,G.location(e),context.world.config().cellSize):continue
  var points:Array=Contact.tree_points(space,e)
  if points.is_empty():continue
  points.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(a).distance_squared_to(G.point(actor))<G.point(b).distance_squared_to(G.point(actor)))
  var scope:Dictionary=zone.duplicate(false);scope.region_id=e.regionId
  rows.append(_job(scope,"harvest_tree",e.id,{},points[0],int(e.revision),G.location(e)))
  if rows.size()>=ZoneDef.MAX_ORDER_TARGETS:break
 return rows

func work_candidates(zone:Dictionary,actor_id:String,observation:Dictionary={})->Array:
 if zone.has("region_ids") and ZoneDef.target_mode(zone)=="harvest_only":return _ordered_tree_jobs(zone,actor_id)
 if context.is_empty() or not zone.get("enabled",true) or not _detailed(str(zone.get("region_id",""))):return []
 var actor:Dictionary=context.actor.call(actor_id)
 if actor.is_empty() or float(actor.get("hp",0))<=0:return []
 if zone.get("kind")=="terrain":return _terrain_candidates(zone,actor_id)
 if zone.get("kind")=="clear" and zone.get("policy",{}).get("mode")=="player_clear":
  return _player_clear_jobs(zone,actor,observation) if actor_id=="player" else []
 var rows:Array=[];var ids:Array=[];var chapter:bool=_content_version()>=20
 for cell:Dictionary in zone.get("cells",[]):ids.append(Rules.plant_id(str(zone.region_id),cell))
 var observed:Dictionary={"plants":context.world.extension_entries(KEY,"plants",ids),"seed_receipts":{}};var policy:Dictionary=zone.get("policy",{});var region:String=zone.region_id
 if zone.get("kind") in ["farm","forage"]:
  var b:Dictionary=zone.bounds;var size:float=context.world.config().cellSize
  var source_bounds:=G.json_box(AABB(Vector3(b.x0*size,-4,b.z0*size),Vector3((b.x1-b.x0)*size,28,(b.z1-b.z0)*size)))
  for e:Dictionary in context.world.entities_in_bounds(source_bounds):
   if e.regionId!=region or (chapter and (zone.kind=="farm" or (policy.get("mode")=="water_only" and not policy.get("item_ids",[]).is_empty() and not policy.item_ids.has(e.id)))):continue
   var j:=_water_job(zone,e)
   if not j.is_empty():rows.append(j)
 if chapter and policy.get("mode")=="water_only":return rows
 if zone.get("kind") in ["forestry","forage","clear"]:
  var b:Dictionary=zone.bounds;var size:float=context.world.config().cellSize
  var bound:=G.json_box(AABB(Vector3(b.x0*size,-4,b.z0*size),Vector3((b.x1-b.x0)*size,28,(b.z1-b.z0)*size)))
  for e:Dictionary in context.world.entities_in_bounds(bound):
   if rows.size()>=256:break
   if e.kind!="tree" or e.regionId!=region:continue
   var model:String=e.get("data",{}).get("appearance",{}).get("model","broadleaf_tree")
   if model=="dead_tree" or e.get("data",{}).get("harvest",{}).get("phase")!="standing":continue
   var candidates:Array=Contact.tree_points(context.spatial.current_space(),e)
   if candidates.is_empty():continue
   candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(a).distance_squared_to(G.point(actor))<G.point(b).distance_squared_to(G.point(actor)))
   var work_at:Dictionary=candidates[0]
   var species:String="conifer" if model=="conifer_tree" else "broadleaf"
   if policy.get("mature_only",true) and e.get("data",{}).get("ecology_stage","mature")!="mature":continue
   if zone.kind=="forestry" and not policy.get("conserve",false):rows.append(_job(zone,"harvest_tree",e.id,{},work_at,int(e.revision),G.location(e)))
   if zone.kind=="forestry" and policy.get("mode")=="harvest_only":continue
   var receipt:Dictionary=context.world.extension_entries(KEY,"seed_receipts",[e.id]).get(e.id,{})
   if float(receipt.get("next_at",0))<=now():
    var j:=_job(zone,"collect_seed",e.id,{},work_at,int(e.revision),G.location(e));j.tree_id=species;rows.append(j)
 if zone.kind=="forestry" and policy.get("mode")=="harvest_only":return rows
 for cell:Dictionary in zone.get("cells",[]):
  if rows.size()>=256:break
  var target:String=Rules.plant_id(region,cell);var plant:Dictionary=observed.plants.get(target,{})
  if zone.kind=="farm":
   var crop:String=str(policy.get("crop_id","potato"))
   if not Rules.CROPS.has(crop):continue
   if not plant.is_empty() and int(plant.get("seed_reserved",0))>0 and policy.get("mode")=="recover_seed":
    var j:=_ground_job(zone,"recover_seed",target,cell,int(plant.revision),observation)
    if not j.is_empty():rows.append(j)
    continue
   if not plant.is_empty() and plant.get("kind")=="crop" and plant.get("stage") in ["seedling","growing","mature"] and policy.get("mode")=="clear":
    var j:=_ground_job(zone,"remove_crop",target,cell,int(plant.revision),observation)
    if not j.is_empty():rows.append(j)
    continue
   var planted:String=str(plant.get("crop_id",""))
   var active_crop:String=planted if chapter and plant.get("stage") in ["seedling","growing","mature"] and Rules.CROPS.has(planted) else crop
   var needs_potato_care:bool=chapter and active_crop=="potato"
   var need:int=0 if needs_potato_care and plant.get("stage")=="growing" else int(Rules.CROPS[active_crop].water)
   var kind:String="till" if plant.is_empty() else "sow" if plant.stage in ["tilled","harvested"] else "harvest_crop" if plant.stage=="mature" else "compost" if int(plant.fertility)==0 and not needs_potato_care else "water" if int(plant.moisture)<need else ""
   if not kind.is_empty():
    var j:=_ground_job(zone,kind,target,cell,int(plant.get("revision",-1)),observation)
    if not j.is_empty():j.crop_id=active_crop;rows.append(j)
  elif zone.kind=="forestry" and policy.get("mode")=="nursery" and plant.is_empty():
   var j:=_ground_job(zone,"nursery",target,cell,-1,observation)
   if not j.is_empty():j.tree_id=str(policy.get("tree_id","broadleaf"));rows.append(j)
  elif zone.kind=="forestry" and not plant.is_empty() and plant.kind=="tree" and _is_stump(plant):
   var at:=_work_point(_loc(region,cell),str(plant.get("entity_id",plant.id)),true,observation)
   if not at.is_empty():rows.append(_job(zone,"clear_stump",target,cell,at,int(plant.revision),_loc(region,cell)))
  elif zone.kind=="forestry" and policy.get("replant",false) and (plant.is_empty() or plant.get("stage")=="cleared"):
   var at:=_work_point(_loc(region,cell),target,true,observation)
   if at.is_empty():continue
   var j:=_job(zone,"plant_tree",target,cell,at,int(plant.get("revision",-1)),_loc(region,cell));j.tree_id=str(policy.get("tree_id","broadleaf"));rows.append(j)
 return rows

func player_clear_targets(zone: Dictionary) -> Dictionary:
 var cells: Array = zone.get("cells", [])
 var result: Dictionary = {"trees": [], "stumps": []}
 if cells.is_empty(): return result
 var region_id: String = str(zone.region_id)
 var region: Dictionary = context.world.region(region_id)
 if region.is_empty(): return result
 var cells_xz: Dictionary = {}
 var plant_ids: Array = []
 for cell: Dictionary in cells:
  cells_xz[Vector2i(int(cell.x), int(cell.z))] = cell
  plant_ids.append(Rules.plant_id(region_id, cell))
 var size: float = context.world.config().cellSize
 var b: Dictionary = zone.bounds
 var minimum_y: float = float(region.bounds.min.y)
 var bounds: Dictionary = G.json_box(AABB(Vector3(float(b.x0) * size, minimum_y, float(b.z0) * size), Vector3(float(b.x1 - b.x0) * size, float(region.bounds.max.y) - minimum_y, float(b.z1 - b.z0) * size)))
 for entity: Dictionary in context.world.entities_in_any_bounds([bounds]):
  if entity.regionId != region_id or not harvest_target(entity, zone.policy): continue
  var at: Dictionary = G.location(entity)
  if cells_xz.has(Vector2i(floori(float(at.x) / size), floori(float(at.z) / size))):
   result.trees.append(entity)
 var plants: Dictionary = context.world.extension_entries(KEY, "plants", plant_ids)
 for cell: Dictionary in cells:
  var plant: Dictionary = plants.get(Rules.plant_id(region_id, cell), {})
  if plant.get("kind") == "tree" and _is_stump(plant):
   result.stumps.append({"plant": plant, "cell": cell})
 return result

func _player_clear_jobs(zone: Dictionary, actor: Dictionary, observation: Dictionary) -> Array:
 var targets := player_clear_targets(zone)
 var jobs: Array = []
 var space: RefCounted = context.spatial.current_space()
 for tree: Dictionary in targets.trees:
  var points: Array = Contact.tree_points(space, tree)
  if points.is_empty(): continue
  points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
   return G.point(a).distance_squared_to(G.point(actor)) < G.point(b).distance_squared_to(G.point(actor)))
  jobs.append(_job(zone, "harvest_tree", str(tree.id), {}, points[0], int(tree.revision), G.location(tree)))
 for entry: Dictionary in targets.stumps:
  var ground := _loc(str(zone.region_id), entry.cell)
  var at := _work_point(ground, str(entry.plant.get("entity_id", entry.plant.id)), true, observation)
  if not at.is_empty():
   jobs.append(_job(zone, "clear_stump", str(entry.plant.id), entry.cell, at, int(entry.plant.revision), ground))
 return jobs

func _ground_job(zone:Dictionary,kind:String,target:String,cell:Dictionary,revision:int,observation:Dictionary={})->Dictionary:
 var contact:=_loc(str(zone.region_id),cell);var feet:=_work_point(contact,target,false,observation)
 if feet.is_empty():return {}
 return _job(zone,kind,target,cell,feet,revision,contact)
func _job(zone:Dictionary,kind:String,target:String,cell:Dictionary,location:Dictionary,revision:int,contact:Dictionary={})->Dictionary:
 return {"id":Rules.job_id(str(zone.id),kind,target,revision),"zone_id":zone.id,"kind":kind,"target_id":target,"cell":cell.duplicate(true),"location":location.duplicate(true),"revision":revision,"region_id":zone.region_id,"target":location.duplicate(true) if contact.is_empty() else contact.duplicate(true)}

func check_work(tx:RefCounted,job:Dictionary,actor_id:String)->Dictionary:
 return _check_work(tx,job,actor_id,{})

func check_work_batch(tx:RefCounted,jobs:Array,actor_id:String,ground_batch:Dictionary={})->Array:
 # B lends one observation Draft for this synchronous query. No await,
 # commit or caller-retained scratch: reuse only the complete live region
 # and module-port predicates. Resource/reservation/body checks stay per job.
 var results:Array=[]
 for job:Variant in jobs:
  results.append(_check_work(tx,job,actor_id,ground_batch) if job is Dictionary else Data.reject("INVALID_ECOLOGY_JOB"))
 return results

func _check_work(tx:RefCounted,job:Dictionary,actor_id:String,ground_batch:Dictionary)->Dictionary:
 if context.is_empty() or not job.has_all(["id","kind","target_id","location","revision"]) or not Data.vec(job.location):return Data.reject("INVALID_ECOLOGY_JOB")
 var actor:Dictionary=tx.actor(actor_id);var prod:Variant=ground_batch.get("production",service("production"))
 if prod==null:return Data.reject("MISSING_PRODUCTION")
 if actor.is_empty() or float(actor.get("hp",0))<=0 or (actor_id!="player" and not actor.get("relationship",{}).get("consent",false)):return Data.reject("ACTOR_UNAVAILABLE")
 var region:String=str(job.location.get("regionId",""))
 if not _detailed(region,ground_batch):return Data.reject("REGION_NOT_DETAILED")
 var kind:String=str(job.kind)
 if kind in ["terrain_dig","terrain_fill"]:return _check_terrain(tx,job,actor_id)
 var observed:Dictionary
 if tx.extensions.has(KEY):observed=tx.extensions[KEY]
 else:observed={"plants":context.world.extension_entries(KEY,"plants",[str(job.target_id)]),"seed_receipts":context.world.extension_entries(KEY,"seed_receipts",[str(job.target_id)]),"sources":context.world.extension_entries(KEY,"sources",[str(job.target_id)])}
 var plant:Dictionary=observed.plants.get(job.target_id,{});var work_location:Dictionary=job.location.duplicate(true)
 if not Data.vec(job.location) or not Data.vec(job.get("target",job.location)):return Data.reject("INVALID_ECOLOGY_LOCATION")
 if kind in ["till","sow","plant_tree","nursery","water","compost","harvest_crop","clear_stump","remove_crop","recover_seed"]:
  if not job.get("cell") is Dictionary or not job.cell.has_all(["x","y","z"]) or not job.cell.values().all(Data.integer) or Rules.plant_id(region,job.cell)!=job.target_id:return Data.reject("INVALID_ECOLOGY_CELL")
  var ground:=_ground(region,int(job.cell.x),int(job.cell.z),"forestry" if kind in ["plant_tree","nursery","clear_stump"] else "farm",{"crop_id":job.get("crop_id",plant.get("crop_id",""))},str(plant.get("entity_id",job.target_id)),ground_batch)
  if not ground.ok:return ground
  if not Data.json_equal(ground.cell,job.cell) or G.point(ground.location).distance_to(G.point(job.get("target",job.location)))>.001:return Data.reject("ECOLOGY_GROUND_CHANGED")
  if int(plant.get("revision",-1))!=int(job.revision):return Data.reject("STALE_ECOLOGY_JOB")
  # A terrain contact is not a whole-body standing point on half-metre steps.
  # Reprove both independently, including old persisted jobs whose location
  # was the contact. B plans to this returned feet point; never lift target.
  work_location=_work_point(ground.location,str(job.target_id),kind in ["plant_tree","clear_stump"],ground_batch)
  if work_location.is_empty():return Data.reject("NO_SAFE_ECOLOGY_WORK_SITE")
 var cost:Dictionary={};var outputs:Dictionary={};var qualities:Dictionary={};var reusable:Dictionary={};var duration:float=8.0
 match kind:
  "harvest_tree":return Data.reject("USE_ORIGINAL_HARVEST","原木仅由原actions.harvest结算")
  "collect_seed":
   var tree:Dictionary=context.world.entity(str(job.target_id));var species:String=str(job.get("tree_id",""))
   if not Rules.TREES.has(species) or tree.get("kind")!="tree" or tree.get("revision")!=job.revision or tree.get("data",{}).get("harvest",{}).get("phase")!="standing" or tree.get("data",{}).get("appearance",{}).get("model","broadleaf_tree")!=Rules.TREES[species].model:return Data.reject("NO_MATURE_MOTHER_TREE")
   if not tree.get("data",{}).get("ecology_stage","mature")=="mature":return Data.reject("NO_MATURE_MOTHER_TREE")
   if G.point(G.location(tree)).distance_to(G.point(job.get("target",job.location)))>.001 or G.point(G.location(tree)).distance_to(G.point(job.location))>1.6:return Data.reject("INVALID_TREE_CONTACT")
   if float(observed.seed_receipts.get(tree.id,{}).get("next_at",0))>now():return Data.reject("SEED_COOLDOWN")
   outputs[Rules.TREES[species].seed]=2;duration=12.0
  "nursery":
   var species:String=str(job.get("tree_id",""))
   if not Rules.TREES.has(species):return Data.reject("UNKNOWN_TREE_SPECIES")
   cost={Rules.TREES[species].seed:1,"r34:raw_water":1};outputs[Rules.TREES[species].seedling]=1;duration=24.0
  "plant_tree":
   var species:String=str(job.get("tree_id",""))
   if not Rules.TREES.has(species) or (not plant.is_empty() and plant.get("stage")!="cleared") or (plant.is_empty() and _plant_count()>=Rules.MAX_PLANTS):return Data.reject("INVALID_TREE_PLANTING")
   if _drop_point(job.get("target",job.location)).is_empty():return Data.reject("NO_SAFE_TREE_OUTPUT")
   var at:Vector3=G.point(job.get("target",job.location))
   for e:Dictionary in context.world.entities_in_bounds(G.json_box(AABB(at-Vector3(3,0,3),Vector3(6,8,6)))):
    if e.kind=="tree" and e.get("data",{}).get("phase")!="stump" and e.get("data",{}).get("harvest",{}).get("phase")!="stump":return Data.reject("TREE_SPACING")
   cost={Rules.TREES[species].seedling:1};qualities={"shovel":1};duration=16.0
  "clear_stump":
   if plant.get("kind")!="tree" or not _is_stump(plant):return Data.reject("NO_HARVESTED_STUMP")
   qualities={"shovel":1};duration=16.0
  "recover_seed":
   var crop:String=str(plant.get("crop_id",""))
   if int(plant.get("seed_reserved",0))!=1 or not Rules.CROPS.has(crop):return Data.reject("NO_RETAINED_SEED")
   outputs[Rules.CROPS[crop].seed]=1;duration=6.0
  "remove_crop":
   if plant.get("kind")!="crop" or plant.get("stage") not in ["seedling","growing","mature"]:return Data.reject("NO_LIVING_CROP")
   qualities={"shovel":1};duration=8.0 # explicit clearance; no immature yield or planted-seed refund
  "till":
   if not plant.is_empty() or _plant_count()>=Rules.MAX_PLANTS:return Data.reject("BED_ALREADY_EXISTS_OR_LIMIT")
   qualities={"shovel":1};duration=8.0
  "sow":
   var crop:String=str(job.get("crop_id",""))
   if plant.get("stage") not in ["tilled","harvested"] or not Rules.CROPS.has(crop):return Data.reject("BED_NOT_READY")
   if int(plant.get("seed_reserved",0))>0 and plant.get("crop_id")!=crop:return Data.reject("RETAINED_SEED_CROP_CHANGE","先取回田内留种再改作物")
   if int(plant.get("seed_reserved",0))==0:cost[Rules.CROPS[crop].seed]=1
   duration=6.0
  "water":
   if plant.is_empty() or plant.stage not in ["seedling","growing"] or plant.moisture>=3:return Data.reject("NO_WATERING_NEEDED")
   cost={"r34:raw_water":1};duration=6.0
  "compost":
   if plant.is_empty() or plant.fertility>=3:return Data.reject("NO_COMPOST_NEEDED")
   cost={"r34:compost":1};duration=6.0
  "harvest_crop":
   var crop:String=str(plant.get("crop_id",""))
   if plant.get("stage")!="mature" or not Rules.CROPS.has(crop):return Data.reject("CROP_NOT_MATURE")
   if _chapter_crop(crop):outputs[Rules.CROPS[crop].item]=4;duration=5.0
   else:outputs[Rules.CROPS[crop].item]=int(Rules.CROPS[crop].yield);outputs["r34:crop_residue"]=1;duration=12.0
  "draw_raw_water":
   if job.get("direct_well",false) and _content_version()<20:return Data.reject("WATER_SOURCE_UNAVAILABLE")
   var entity:Dictionary=context.world.entity(str(job.target_id));var descriptor:Dictionary=entity.get("data",{}).get("raw_water_source",{})
   if not Sources.valid(descriptor) or descriptor.region_id!=region:return Data.reject("NO_ACTUAL_RAW_SOURCE")
   var stored:Dictionary=observed.sources.get(job.target_id,{})
   var source:Dictionary=_water_observation(descriptor,stored)
   if source.is_empty() or source.remaining<1 or int(stored.get("revision",0))!=job.revision:return Data.reject("RAW_SOURCE_EMPTY_OR_CHANGED")
   if not Data.json_equal(descriptor.use_point,job.location) or G.point(G.location(entity)).distance_to(G.point(job.get("target",{})))>.001:return Data.reject("SOURCE_LOCATION_CHANGED")
   reusable={"r34:water_bucket":1}
   outputs={"r34:raw_water":int(mini(2,int(source.remaining))) if _content_version()>=20 else 1};duration=5.0 if _content_version()>=20 else 12.0
  _:return Data.reject("UNKNOWN_ECOLOGY_WORK")
 var work_id:String=str(job.get("work_id",job.id));var source_id:String=str(job.get("source_id","pack:"+actor_id));var output_id:String=str(job.get("output_id","pack:"+actor_id))
 var requirements:Dictionary={"cost":cost.duplicate(true),"tool_quality":qualities.duplicate(true),"reusable":reusable.duplicate(true),"location":work_location.duplicate(true),"target":job.get("target",job.location).duplicate(true)}
 for item:String in reusable:
  if float(tx.stock("pack:"+actor_id).get("items",{}).get(item,0))-prod.work_reserved("pack:"+actor_id,item,work_id,tx)<float(reusable[item]):return _needs("REUSABLE_BUCKET_REQUIRED",item,requirements)
 if prod.use_reserved(str(job.target_id),work_id,tx):return Data.reject("ECOLOGY_TARGET_RESERVED")
 for item:String in cost:
  var stock:Dictionary=tx.stock(source_id)
  if prod.reach(actor_id,source_id,stock,"stock",tx)!=null:return _needs("INPUT_NOT_WITH_WORKER",item,requirements)
  if float(stock.items.get(item,0))-prod.work_reserved(source_id,item,work_id,tx)<cost[item]:return _needs("MISSING_ECOLOGY_INPUT",item,requirements)
 if not outputs.is_empty():
  if prod.reach(actor_id,output_id,tx.stock(output_id),"stock",tx)!=null:return Data.reject("OUTPUT_NOT_WITH_WORKER")
  var capacity:Dictionary=prod.capacity_check(output_id,outputs,work_id,tx)
  if not capacity.ok:return capacity
 return {"ok":true,"code":"OK","duration":duration,"cost":cost,"outputs":outputs,"tool_quality":qualities,"target":job.get("target",job.location).duplicate(true),"location":work_location.duplicate(true),"stamina":duration*.5,"wear":.5,"source_id":source_id,"output_id":output_id,"settlement_owner":"ecology","requirements":requirements}

func _needs(code:String,reason:String,requirements:Dictionary)->Dictionary:
 var result:=Data.reject(code,reason);result.requirements=requirements.duplicate(true);return result

func complete_work(tx:RefCounted,job:Dictionary,actor_id:String)->Dictionary:
 var checked:=check_work(tx,job,actor_id)
 if not checked.ok:return checked
 var a:Dictionary=tx.actor(actor_id);var q:RefCounted=context.spatial.current_space();var feet:Dictionary=q.standing_point(G.location(a))
 var work_location:Dictionary=checked.location
 if feet.is_empty() or a.regionId!=work_location.regionId or absf(float(a.y)-float(work_location.y))>.025 or G.point(G.location(a)).distance_to(G.point(work_location))>.26:return Data.reject("ECOLOGY_OPERATOR_NOT_AT_SITE")
 var terrain_work:bool=job.kind in ["terrain_dig","terrain_fill"]
 if not terrain_work and not q.contact_clear(G.location(a),job.get("target",job.location),str(job.target_id)):return Data.reject("ECOLOGY_OPERATOR_NOT_AT_SITE")
 var tools:Dictionary=tx.extension("r3:production",service("production").empty_state())
 if not service("production").qualities(tools,job.get("tool_ids",[]),checked.tool_quality):return Data.reject("MISSING_ECOLOGY_TOOL")
 for tool_id:Variant in job.get("tool_ids",[]):
  var tool:Dictionary=Draft.find(tools.tools,str(tool_id))
  if tool.is_empty() or tool.get("holderId")!="pack:"+actor_id or float(tool.get("durability",0))<=0 or service("production").tool_unavailable(str(tool_id),str(job.get("work_id",job.id)),tx):return Data.reject("ECOLOGY_TOOL_CHANGED")
 var s:Dictionary=tx.extension(KEY,Rules.initial());var work_id:String=str(job.get("work_id",job.id))
 if s.completed.has(work_id):return Data.reject("ECOLOGY_ALREADY_SETTLED")
 if s.completed.size()>=16384:return Data.reject("ECOLOGY_RECEIPT_LIMIT")
 var terrain_plan:Dictionary={}
 if terrain_work:
  # Recheck against the pre-settlement pack; otherwise fill would require a
  # second unit after the one real cost has already been removed below.
  terrain_plan=service("terrain").prepare_zone_work_in(tx,job,actor_id)
  if not terrain_plan.ok:return terrain_plan
  var net:Dictionary=checked.outputs.duplicate(true)
  for item:String in checked.cost:net[item]=float(net.get(item,0))-float(checked.cost[item])
  if net!=terrain_plan.material_delta:return Data.reject("EARTHWORK_MATERIAL_CHANGED")
 # All checks precede the first mutation; caller discards the Draft if rejected.
 if not checked.cost.is_empty() and not tx.stock_delta(checked.source_id,checked.cost,-1):return Data.reject("ECOLOGY_INPUT_CHANGED")
 if not checked.outputs.is_empty() and not tx.stock_delta(checked.output_id,checked.outputs):return Data.reject("ECOLOGY_OUTPUT_CHANGED")
 var p:Dictionary=s.plants.get(job.target_id,{})
 if terrain_work:tx.extra.append_array(terrain_plan.world_changes)
 match str(job.kind):
  "collect_seed":s.seed_receipts[job.target_id]={"next_at":now()+1200.0,"count":int(s.seed_receipts.get(job.target_id,{}).get("count",0))+2}
  "till","plant_tree":
   var cycle:int=int(p.get("cycle",-1))+1;var plant_revision:int=int(p.get("revision",-1))+1
   p={"id":job.target_id,"cycle":cycle,"region_id":job.location.regionId,"cell":job.cell.duplicate(true),"location":job.get("target",job.location).duplicate(true),"kind":"tree" if job.kind=="plant_tree" else "bed","tree_id":job.get("tree_id",""),"crop_id":"","stage":"seedling" if job.kind=="plant_tree" else "tilled","moisture":1,"fertility":2,"seed_reserved":0,"revision":plant_revision,"owner":actor_id,"next_at":-1.0}
   s.plants[p.id]=p;s.plant_count=s.plants.size()
   if not s.has("buckets"):s.buckets=_all_buckets(s.plants)
   else:
    var bucket:=_bucket(p.region_id,p.cell)
    if not s.buckets.has(bucket):s.buckets[bucket]=[]
    if not s.buckets[bucket].has(p.id):s.buckets[bucket].append(p.id);s.buckets[bucket].sort()
   if p.kind=="tree":
    var drop_at:=_drop_point(p.location)
    if drop_at.is_empty():return Data.reject("NO_SAFE_TREE_OUTPUT")
    p.entity_id=p.id+":tree:"+str(cycle);p.output_id=p.entity_id+":drops";p.drop_location=drop_at
    Entities.put(tx,context.world,Entities.tree(p,_content_version()));Entities.put(tx,context.world,Entities.drop(p))
    tx.staged.stocks.append({"id":p.output_id,"items":{},"owner":null,"searched":true,"location":drop_at.duplicate(true)})
    _schedule(s,p,now()+Rules.TREES[p.tree_id].young_seconds)
   else:Entities.put(tx,context.world,Entities.bed(p))
  "clear_stump":
   var old:Dictionary=context.world.entity(str(p.get("entity_id",p.id)))
   tx.extra.append({"op":"entity.remove","id":old.id,"before":old})
   p.stage="cleared";p.next_at=-1.0;p.revision+=1
  "recover_seed":p.seed_reserved=0;p.revision+=1
  "remove_crop":p.kind="bed";p.stage="tilled";p.next_at=-1.0;p.revision+=1
  "sow":
   p.crop_id=job.crop_id;p.kind="crop";p.stage="seedling";p.seed_reserved=0;p.revision+=1
   if _chapter_crop(str(p.crop_id)):p.moisture=0
   _schedule(s,p,now()+_crop_stage_seconds(str(p.crop_id)))
  "water":p.moisture=mini(3,int(p.moisture)+1);p.revision+=1
  "compost":p.fertility=mini(3,int(p.fertility)+2);p.revision+=1
  "harvest_crop":
   p.stage="harvested";p.seed_reserved=1;p.revision+=1;p.next_at=-1.0
   if not _chapter_crop(str(p.crop_id)):p.fertility=maxi(0,int(p.fertility)-1)
  "draw_raw_water":
   var descriptor:Dictionary=context.world.entity(job.target_id).data.raw_water_source
   var source:Dictionary=_water_observation(descriptor,s.sources.get(job.target_id,{}))
   source.remaining-=int(checked.outputs["r34:raw_water"]);source.revision+=1;s.sources[job.target_id]=source
 s.revision+=1;s.completed[work_id]={"target_id":job.target_id,"kind":job.kind,"time":now()}
 tx.events.append({"kind":"ecology-work-completed","actor_id":actor_id,"target_id":job.target_id,"operation":job.kind,"work_id":work_id,"cost":checked.cost.duplicate(true),"outputs":checked.outputs.duplicate(true)})
 return {"ok":true,"code":"OK","settlement_owner":"ecology"}

func _schedule(s:Dictionary,p:Dictionary,at:float)->void:
 p.next_at=at;Rules.push(s.due,{"at":at,"id":p.id,"revision":p.revision});s.next_due=s.due[0].at
func advance(dt:float)->Dictionary:
 if not (is_finite(dt) and dt>0 and dt<=1):return Data.reject("INVALID_STEP")
 if context.is_empty():return Data.reject("MISSING_WORLD")
 var meta:Dictionary=_fields(["next_due"])
 if meta.has("next_due"):
  if float(meta.next_due)<0 or float(meta.next_due)>now():return _empty()
 else:
  var observed:=state()
  if observed.due.is_empty() or float(observed.due[0].at)>now():return _empty()
 var tx:=Draft.new(context);var s:Dictionary=tx.extension(KEY,Rules.initial());var count:int=0;var ground_batch:Dictionary={}
 while not s.due.is_empty() and float(s.due[0].at)<=now() and count<Rules.MAX_DUE_PER_STEP:
  var event:=Rules.pop(s.due);s.next_due=-1.0 if s.due.is_empty() else s.due[0].at;count+=1;var p:Dictionary=s.plants.get(event.id,{})
  if p.is_empty() or p.next_at!=event.at:continue
  # Cold regions preserve their pending stage, not invisible simulation gains.
  if not _detailed(p.region_id,ground_batch):_schedule(s,p,now()+1.0);continue
  if p.kind=="tree":
   var current:Dictionary=context.world.entity(str(p.get("entity_id",p.id)))
   if current.get("data",{}).get("harvest",{}).get("phase")=="stump" or current.get("data",{}).get("phase")=="stump":p.stage="harvested";p.next_at=-1.0;p.revision+=1;s.revision+=1;continue
   if current.is_empty():return Data.reject("ECOLOGY_TREE_ENTITY_MISSING")
   var ground:=_ground(p.region_id,int(p.cell.x),int(p.cell.z),"forestry",{},str(p.get("entity_id",p.id)),ground_batch)
   if not ground.ok or not Data.json_equal(ground.cell,p.cell):_schedule(s,p,now()+30.0);continue
   var grown:Dictionary=p.duplicate(true);grown.stage="growing" if p.stage=="seedling" else "mature"
   var entity:Dictionary=Entities.tree(grown,_content_version())
   if not _growth_clear(entity):_schedule(s,p,now()+30.0);continue
   p.stage=grown.stage;p.revision+=1
   if p.stage=="growing":_schedule(s,p,now()+Rules.TREES[p.tree_id].mature_seconds)
   else:p.next_at=-1.0
   Entities.put(tx,context.world,Entities.tree(p,_content_version()))
  elif p.stage in ["seedling","growing"]:
   # Recheck real support and the nine-cell paddy grade at the due boundary.
   # A previously valid plan cannot mature across a later dug/cold edge.
   var ground:=_ground(p.region_id,int(p.cell.x),int(p.cell.z),"farm",{"crop_id":p.crop_id},"",ground_batch)
   if not ground.ok or not Data.json_equal(ground.cell,p.cell):_schedule(s,p,now()+30.0);continue
   var chapter_crop:bool=_chapter_crop(str(p.crop_id))
   var need:int=0 if chapter_crop and p.stage=="growing" else int(Rules.CROPS[p.crop_id].water)
   if int(p.moisture)<need or (int(p.fertility)<=0 and not chapter_crop):_schedule(s,p,now()+(5.0 if chapter_crop else 30.0));continue
   p.moisture-=need;p.stage="growing" if p.stage=="seedling" else "mature";p.revision+=1
   if p.stage=="growing":_schedule(s,p,now()+_crop_stage_seconds(str(p.crop_id)))
   else:p.next_at=-1.0
  s.revision+=1
 tx.events.append({"kind":"ecology-due-advanced","processed":count})
 return tx.result()

func validate_extensions(_facts:Dictionary,overrides:Dictionary={})->Dictionary:
 if not overrides.has(KEY) and not context.world.has_extension(KEY):return {"ok":true,"code":"OK"}
 var token:Dictionary=context.world.extension_token(KEY) if context.world.has_method("extension_token") else {}
 if not overrides.has(KEY) and not token.is_empty() and token==_validation_token and not _validation_result.is_empty():return _validation_result.duplicate(true)
 var result:=_validate_state(overrides)
 if not overrides.has(KEY) and not token.is_empty() and result.ok:_validation_token=token;_validation_result=result.duplicate(true)
 return result

func _validate_state(overrides:Dictionary={})->Dictionary:
 if not overrides.has(KEY) and not context.world.has_extension(KEY):return {"ok":true}
 var s:Variant=overrides[KEY] if overrides.has(KEY) else context.world.extension(KEY)
 if not s is Dictionary or s.get("version")!=Rules.VERSION or not Data.integer(s.get("revision")) or s.revision<0 or not s.get("plants") is Dictionary or not s.get("due") is Array or not s.get("sources") is Dictionary or not s.get("seed_receipts") is Dictionary or not s.get("completed") is Dictionary or s.plants.size()>Rules.MAX_PLANTS or s.due.size()>Rules.MAX_PLANTS*4 or s.completed.size()>16384:return Data.reject("INVALID_ECOLOGY_STATE")
 for id:Variant in s.plants:
  var p:Variant=s.plants[id]
  if not p is Dictionary or p.get("id")!=id or not Data.valid_id(id) or not Data.valid_id(p.get("region_id")) or not Data.vec(p.get("location")) or not p.get("cell") is Dictionary or not p.cell.has_all(["x","y","z"]) or not p.cell.values().all(Data.integer) or Rules.plant_id(p.region_id,p.cell)!=id or not Data.integer(p.get("revision")) or p.revision<0 or p.get("stage") not in ["tilled","seedling","growing","mature","harvested","cleared"] or p.get("kind") not in ["tree","crop","bed"] or not _bounded_integer(p.get("seed_reserved"),0,1) or not _bounded_integer(p.get("moisture"),0,3) or not _bounded_integer(p.get("fertility"),0,3) or not Data.valid_id(p.get("owner")):return Data.reject("INVALID_ECOLOGY_PLANT")
  if not _number(p.get("next_at")) or (p.kind=="tree" and not Rules.TREES.has(p.get("tree_id"))) or (p.kind=="crop" and not Rules.CROPS.has(p.get("crop_id"))):return Data.reject("INVALID_ECOLOGY_SPECIES")
  if G.point(p.location)!=G.point(_loc(p.region_id,p.cell)) or p.location.get("regionId")!=p.region_id or p.next_at < -1:return Data.reject("INVALID_ECOLOGY_LOCATION")
  if p.kind=="tree" and p.stage not in ["seedling","growing","mature","harvested","cleared"]:return Data.reject("INVALID_TREE_STAGE")
  if p.kind=="bed" and p.stage!="tilled":return Data.reject("INVALID_BED_STAGE")
  if p.kind=="crop" and p.stage not in ["seedling","growing","mature","harvested"]:return Data.reject("INVALID_CROP_STAGE")
  if (p.stage in ["seedling","growing"])!=(float(p.next_at)>=0):return Data.reject("INVALID_GROWTH_SCHEDULE")
  if int(p.seed_reserved)>0 and (p.stage!="harvested" or not Rules.CROPS.has(p.crop_id)):return Data.reject("INVALID_RETAINED_SEED")
  if p.has("cycle") and (not Data.integer(p.cycle) or p.cycle<0):return Data.reject("INVALID_PLANT_CYCLE")
  if p.kind=="tree" and p.has("entity_id") and (not p.has("cycle") or not Data.valid_id(p.entity_id) or p.entity_id!=str(p.id)+":tree:"+str(int(p.cycle)) or p.get("output_id")!=p.entity_id+":drops" or not Data.vec(p.get("drop_location"))):return Data.reject("INVALID_PLANTED_TREE_IDENTITY")
 var pending:Dictionary={}
 for e:Variant in s.due:
  if e is Dictionary and s.plants.has(e.get("id")) and e.get("at")==s.plants[e.id].get("next_at"):pending[e.id]=int(pending.get(e.id,0))+1
 for p:Dictionary in s.plants.values():
  if float(p.next_at)>=0 and int(pending.get(p.id,0))!=1:return Data.reject("INVALID_LIVE_DUE_IDENTITY")
 for id:Variant in s.seed_receipts:
  var receipt:Variant=s.seed_receipts[id]
  if not Data.valid_id(id) or not receipt is Dictionary or not _number(receipt.get("next_at")) or receipt.next_at<0 or not Data.integer(receipt.get("count")) or receipt.count<0 or int(receipt.count)%2!=0:return Data.reject("INVALID_SEED_RECEIPT")
 if s.seed_receipts.size()>16384 or s.sources.size()>64:return Data.reject("ECOLOGY_SOURCE_LIMIT")
 for id:Variant in s.sources:
  var source:Variant=s.sources[id]
  if not Data.valid_id(id) or not source is Dictionary or source.get("id")!=id or not Data.valid_id(source.get("source_key")) or not Data.integer(source.get("remaining")) or source.remaining<0 or source.remaining>64 or not Data.integer(source.get("revision")) or source.revision<0 or not _number(source.get("updated_at")) or source.updated_at<0 or not _number(source.get("fraction")) or source.fraction<0 or source.fraction>=1:return Data.reject("INVALID_RAW_SOURCE_STATE")
 for id:Variant in s.completed:
  var receipt:Variant=s.completed[id]
  if not Data.valid_id(id) or not receipt is Dictionary or not Data.valid_id(receipt.get("target_id")) or receipt.get("kind") not in ["collect_seed","nursery","plant_tree","clear_stump","till","sow","water","compost","harvest_crop","recover_seed","remove_crop","draw_raw_water","terrain_dig","terrain_fill"] or not _number(receipt.get("time")) or receipt.time<0:return Data.reject("INVALID_ECOLOGY_SETTLEMENT")
 if s.has("buckets") and (not s.buckets is Dictionary or s.buckets!=_all_buckets(s.plants)):return Data.reject("INVALID_ECOLOGY_BUCKETS")
 if s.has("plant_count") and (not Data.integer(s.plant_count) or s.plant_count!=s.plants.size()):return Data.reject("INVALID_ECOLOGY_PLANT_COUNT")
 for i:int in s.due.size():
  var e:Variant=s.due[i]
  if not e is Dictionary or not _number(e.get("at")) or e.at<0 or not s.plants.has(e.get("id")) or not Data.integer(e.get("revision")) or (i>0 and Rules.before(e,s.due[(i-1)/2])):return Data.reject("INVALID_ECOLOGY_DUE_HEAP")
 if s.has("next_due") and (not _number(s.next_due) or float(s.next_due)!=(-1.0 if s.due.is_empty() else float(s.due[0].at))):return Data.reject("INVALID_ECOLOGY_NEXT_DUE")
 return {"ok":true,"code":"OK"}
func presentation_projection(actor_id:String="player")->Dictionary:
 if context.is_empty():return {"available":false,"revision":0,"visuals":[]}
 var actor:Dictionary=context.actor.call(actor_id);var meta:Dictionary=_fields(["revision","plant_count"])
 var revision:int=int(meta.get("revision",0));var visuals:Array=[]
 if actor.is_empty():return {"available":false,"revision":revision,"visuals":[]}
 var ids:Array=[];var seen:Dictionary={};var buckets:Array=[];var region:String=actor.regionId
 # Eight metre buckets, derived and validated in the same persistent state.
 for z:int in range(floori((float(actor.z)-28.0)/8),floori((float(actor.z)+28.0)/8)+1):
  for x:int in range(floori((float(actor.x)-28.0)/8),floori((float(actor.x)+28.0)/8)+1):buckets.append(region+":"+str(x)+":"+str(z))
 var local:Dictionary=context.world.extension_entries(KEY,"buckets",buckets)
 for rows:Array in local.values():
  for id:String in rows:
   if not seen.has(id):seen[id]=true;ids.append(id)
 var plants:Dictionary=context.world.extension_entries(KEY,"plants",ids)
 if local.is_empty() and not meta.has("plant_count"):plants=state().plants # pre-index WIP compatibility only
 var query:RefCounted=context.spatial.current_space();var batch:Dictionary={}
 for p:Dictionary in plants.values():
  if not _detailed(p.region_id,batch) or p.region_id!=region or G.point(p.location).distance_to(G.point(actor))>28:continue
  if p.owner!=actor_id and p.owner!="player":continue
  if not query.line_clear(G.location(actor),p.location,p.id):continue
  var row:Dictionary=p.duplicate(true);row.known=true;row.resident=true;row.visible=true
  row.visual_owner="environment" if p.kind=="tree" else "ecology";row.world_entity_id=p.get("entity_id",p.id)
  if p.kind=="tree" and _is_stump(p):row.stage="harvested"
  # Moisture is an agronomic state, not a claim of simulated flood volume.
  row.rice_level_bed=p.crop_id=="rice";row.water_surface=false
  visuals.append(row)
 var box:=G.json_box(AABB(G.point(G.location(actor))-Vector3(28,4,28),Vector3(56,32,56)))
 var sources:Array=context.world.entities_with_data_in_bounds(box,"raw_water_source") if context.world.has_method("entities_with_data_in_bounds") else context.world.entities_in_bounds(box)
 for entity:Dictionary in sources:
  var descriptor:Dictionary=entity.get("data",{}).get("raw_water_source",{})
  if entity.regionId!=region or not _detailed(region,batch) or not Sources.valid(descriptor) or not query.line_clear(G.location(actor),G.location(entity),entity.id):continue
  var stored:Dictionary=context.world.extension_entries(KEY,"sources",[entity.id]).get(entity.id,{})
  var source:Dictionary=_water_observation(descriptor,stored)
  visuals.append({"id":entity.id,"kind":"water_source","location":G.location(entity),"region_id":region,"stage":"available" if source.remaining>0 else "recharging","revision":int(stored.get("revision",0)),"known":true,"resident":true,"visible":true,"visual_owner":"ecology","capacity":descriptor.capacity,"remaining":source.remaining,"recharge_seconds":descriptor.recharge_seconds,"world_entity_id":entity.id})
 return {"available":true,"revision":revision,"visuals":visuals}

static func _bucket(region:String,cell:Dictionary)->String:return region+":"+str(floori(float(cell.x)/16))+":"+str(floori(float(cell.z)/16))
static func _all_buckets(plants:Dictionary)->Dictionary:
 var buckets:Dictionary={}
 for p:Dictionary in plants.values():
  var key:=_bucket(p.region_id,p.cell)
  if not buckets.has(key):buckets[key]=[]
  buckets[key].append(p.id)
 for values:Array in buckets.values():values.sort()
 return buckets
static func _number(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))
static func _bounded_integer(v:Variant,lo:int,hi:int)->bool:
 # JSON decodes numbers as float. Accept exact finite integer values only;
 # bool, fractions and out-of-range values must never acquire a schema proof.
 return Data.integer(v) and v>=lo and v<=hi

func _drop_point(at:Dictionary)->Dictionary:
 var q:RefCounted=context.spatial.current_space()
 for offset:Vector3 in [Vector3(.9,0,0),Vector3(-.9,0,0),Vector3(0,0,.9),Vector3(0,0,-.9)]:
  var probe:Dictionary=at.merged(G.json_point(G.point(at)+offset),true)
  var feet:Dictionary=q.standing_point(probe)
  if not feet.is_empty() and absf(float(feet.y)-float(at.y))<=.5 and feet.regionId==at.regionId and q.contact_clear(at,feet):return feet
 return {}

func _plant_count()->int:
 var meta:Dictionary=_fields(["plant_count"])
 return int(meta.plant_count) if meta.has("plant_count") else state().plants.size()

func _fields(fields:Array)->Dictionary:
 var typed:Array[String]=[];typed.assign(fields)
 return context.world.extension_fields(KEY,typed)

func _work_point(target:Dictionary,id:String,side:bool=false,observation:Dictionary={})->Dictionary:
 # Scratch belongs to one synchronous candidate/check batch, never admission
 # across frames. Cache exact target/ignored collider/side, including failure.
 var key:String=JSON.stringify([target,id,side],"",true)
 if not observation.has("work_points"):observation.work_points={}
 if not observation.work_points.has(key):observation.work_points[key]=_find_work_point(target,id,side)
 return observation.work_points[key].duplicate(true)

func _find_work_point(target:Dictionary,id:String,side:bool)->Dictionary:
 var q:RefCounted=context.spatial.current_space();var choices:Array=[]
 if not side:choices.append(target)
 for offset:Vector3 in [Vector3(1.2,0,0),Vector3(-1.2,0,0),Vector3(0,0,1.2),Vector3(0,0,-1.2)]:choices.append(target.merged(G.json_point(G.point(target)+offset),true))
 for probe:Dictionary in choices:
  var feet:Dictionary=q.standing_point(probe)
  if feet.is_empty() or feet.regionId!=target.regionId or absf(float(feet.y)-float(target.y))>.5:continue
  if q.contact_clear(feet,target,id):return feet
 return {}

func _growth_clear(entity:Dictionary)->bool:
 for other:Dictionary in context.world.entities_in_bounds(entity.bounds):
  if other.id==entity.id:continue
  if other.get("data",{}).get("solid",false):return false
 for actor:Dictionary in context.facts.call().get("actors",[]):
  if float(actor.get("hp",0))<=0 or actor.regionId!=entity.regionId:continue
  var body:=G.json_box(AABB(G.point(G.location(actor))-Vector3(.4,0,.4),Vector3(.8,1.8,.8)))
  if Data.intersects(body,entity.bounds):return false
 return true

func presentation_basis(actor_id:String="player")->Dictionary:
 if context.is_empty():return {"available":false}
 var actor:Dictionary=context.actor.call(actor_id)
 if actor.is_empty():return {"available":false}
 var host:Variant=_host.get_ref() if _host!=null else null
 var fields:Dictionary=_fields(["revision"])
 return {"available":true,"world_revision":context.world.get_revision(),"runtime_revision":host.get_revision() if host!=null else now(),"ecology_revision":int(fields.get("revision",0)),"ecology_generation":context.world.extension_token(KEY) if context.world.has_method("extension_token") else {"conservative_clock":now()},"actor_id":actor_id,"location":G.location(actor),"alive":float(actor.get("hp",0))>0,"consent":actor.get("relationship",{}).get("consent",false),"detailed":_detailed(str(actor.regionId))}

func _is_stump(plant:Dictionary)->bool:
 var entity:Dictionary=context.world.entity(str(plant.get("entity_id",plant.id)))
 return not entity.is_empty() and (entity.get("data",{}).get("phase")=="stump" or entity.get("data",{}).get("harvest",{}).get("phase")=="stump")

func _terrain_candidates(zone:Dictionary,_actor_id:String)->Array:
 var rows:Array=[]
 for cell:Dictionary in zone.get("cells",[]):
  if rows.size()>=128:break
  var row:Dictionary=Earthwork.next_cell(context.world,zone,cell)
  if not row.ok:continue
  var at:=_work_point(row.target,"",true)
  if at.is_empty():continue
  var chunk:String=Data.key(Data.cell_chunk(Vector3i(row.cell.x,row.cell.y,row.cell.z),int(context.world.config().chunkCells)))
  var revision:int=int(context.world.chunk_metadata(chunk).get("revision",-1))
  var target:String="terrain:%d:%d:%d"%[int(row.cell.x),int(row.cell.y),int(row.cell.z)]
  var job:=_job(zone,"terrain_"+row.operation,target,row.cell,at,revision,row.target)
  job.before=row.before;job.material=row.after if row.after!=0 else 2
  rows.append(job)
 return rows

func _check_terrain(tx:RefCounted,job:Dictionary,actor_id:String)->Dictionary:
 var world:RefCounted=context.world
 if service("terrain")==null or not job.get("cell") is Dictionary or not job.cell.has_all(["x","y","z"]) or not job.cell.values().all(Data.integer):return Data.reject("INVALID_EARTHWORK_JOB")
 if not Data.integer(job.get("before")) or not Data.integer(job.get("material",2)) or not Data.vec(job.get("target")):return Data.reject("INVALID_EARTHWORK_JOB")
 var region:String=str(job.location.regionId);var cfg:Dictionary=world.config()
 if not world.is_cell_known(job.cell.x,job.cell.y,job.cell.z) or not world.is_cell_resident(job.cell.x,job.cell.y,job.cell.z):return Data.reject("UNLOADED_CELL")
 var at:Dictionary={"x":(float(job.cell.x)+.5)*cfg.cellSize,"y":float(job.cell.y)*cfg.cellSize,"z":(float(job.cell.z)+.5)*cfg.cellSize}
 if world.region_at(at).get("id")!=region or job.get("region_id")!=region or job.target.get("regionId")!=region:return Data.reject("WRONG_REGION")
 if _service_exit_protected(region,job.target):return Data.reject("PROTECTED_SERVICE_EXIT")
 var target:String="terrain:%d:%d:%d"%[int(job.cell.x),int(job.cell.y),int(job.cell.z)]
 if job.target_id!=target or world.cell_at(job.cell.x,job.cell.y,job.cell.z)!=job.get("before"):return Data.reject("EARTHWORK_CELL_CHANGED")
 var reason:String=Earthwork.protected(world,job.cell,str(job.location.regionId))
 if not reason.is_empty():return Data.reject(reason)
 var pack:String="pack:"+actor_id
 if job.get("source_id",pack)!=pack or job.get("output_id",pack)!=pack:return Data.reject("EARTHWORK_REQUIRES_REAL_CARRY")
 var material:int=int(job.before) if job.kind=="terrain_dig" else int(job.get("material",2))
 if not Data.MATERIALS.has(material) or (job.kind=="terrain_fill" and material not in [2,3,6]) or not Data.MATERIALS[material].get("diggable",false):return Data.reject("PROTECTED_TERRAIN")
 var item:String=str(Data.MATERIALS[material].get("item",""));var required:String=str(Data.MATERIALS[material].get("tool",""))
 if required.is_empty():required="shovel" # batch labor always uses an actual tool
 var cost:Dictionary={};var outputs:Dictionary={};var qualities:Dictionary={}
 if not required.is_empty():qualities[required]=1
 if job.kind=="terrain_dig":outputs[item]=.125
 else:cost[item]=.125
 var production:Variant=service("production");var work_id:String=str(job.get("work_id",job.id))
 if production.use_reserved(job.target_id,work_id,tx):return Data.reject("EARTHWORK_RESERVED")
 var requirements:Dictionary={"cost":cost.duplicate(true),"tool_quality":qualities.duplicate(true),"reusable":{},"location":job.location.duplicate(true),"target":job.target.duplicate(true)}
 if job.kind=="terrain_fill" and production.available_for(pack,item,"work",work_id,tx)<.125:return _needs("NO_MATERIAL",item,requirements)
 if job.kind=="terrain_dig":
  var capacity:Dictionary=production.capacity_check(pack,outputs,work_id,tx)
  if not capacity.ok:return capacity
 return {"ok":true,"code":"OK","duration":1.5,"cost":cost,"outputs":outputs,"tool_quality":qualities,"target":job.target.duplicate(true),"location":job.location.duplicate(true),"stamina":1.0,"wear":.1,"source_id":pack,"output_id":pack,"settlement_owner":"ecology","requirements":requirements}

func _content_version()->int:
 var fields:Array[String]=["content_version"]
 var generation:Variant=context.world.extension_fields("generation:factory-r34",fields) if context.world.has_method("extension_fields") else context.world.extension("generation:factory-r34")
 return int(generation.get("content_version",0)) if generation is Dictionary else 0

func _chapter_crop(crop:String)->bool:return crop=="potato" and _content_version()>=20
func _crop_stage_seconds(crop:String)->float:return 45.0 if _chapter_crop(crop) else float(Rules.CROPS[crop].seconds)/2
func _water_observation(descriptor:Dictionary,stored:Dictionary)->Dictionary:
 return Sources.observe(descriptor,stored,now(),3.0 if _content_version()>=20 else 1.0)

func _water_job(zone:Dictionary,entity:Dictionary)->Dictionary:
 var descriptor:Dictionary=entity.get("data",{}).get("raw_water_source",{})
 if not Sources.valid(descriptor):return {}
 var stored:Dictionary=context.world.extension_entries(KEY,"sources",[entity.id]).get(entity.id,{})
 var water:Dictionary=_water_observation(descriptor,stored)
 if water.is_empty() or int(water.remaining)<1:return {}
 return _job(zone,"draw_raw_water",entity.id,{},descriptor.use_point,int(stored.get("revision",0)),G.location(entity))

func chapter_water_job(target_id:String)->Dictionary:
 if _content_version()<20:return {}
 var entity:Dictionary=context.world.entity(target_id)
 if entity.is_empty() or not _detailed(str(entity.get("regionId",""))):return {}
 return _water_job({"id":"well:"+target_id,"revision":0,"region_id":entity.regionId},entity)
