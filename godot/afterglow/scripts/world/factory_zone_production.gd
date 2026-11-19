extends RefCounted
## Explicit content12 only, based on stable10 terrain. No paused11 adoption,
## old-stock refill, safe water or extra starting food. The one separate seed
## bag is a real container; B alone registers its finite first-receipt stock.
const Data=preload("res://scripts/world/world_data.gd")
const Sources=preload("res://scripts/ecology/ecology_sources.gd")
const Water=preload("res://scripts/world/factory_water_sources.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const RegionalArt=preload("res://scripts/modules/village_regional_catalog.gd")
const Village=preload("res://scripts/world/village_opening_layout.gd")
const POLICY="regional-production-v1"
const START_ITEMS={"r34:potato_seed":4,"r34:bean_seed":4,"r34:rice_seed":4,"r34:water_bucket":1}

static func prepare_plan(plan:Dictionary,profiles:Array=[])->Dictionary:
 if int(plan.get("generation_content_version",1)) not in [12,13,14,15,16,17,18,19,20,21]:return {"ok":true}
 plan.zone_production_policy=POLICY
 if plan.region_id=="RH-VILLAGE":
  var stores:Array=plan.module_seeds.filter(func(s:Dictionary)->bool:return s.get("purpose")=="store" and s.get("id")=="r34:generated:RH-VILLAGE:store" and s.get("definition_id")==RegionalArt.id_for("r34.module.supply_rear_v3",int(plan.generation_content_version)))
  if stores.size()!=1:return Data.reject("MISSING_S03_SEED_BAG_SOURCE")
  var seed:Dictionary=stores[0];var found:Array=profiles.filter(func(p:Dictionary)->bool:return p.id==seed.definition_id)
  if found.size()!=1:return Data.reject("MISSING_S03_SEED_BAG_PROFILE")
  var site:Dictionary=_bag_site(plan,seed,found[0])
  if site.is_empty():return Data.reject("NO_SAFE_S03_SEED_BAG_SITE")
  var id:String=str(seed.id)+":regional-seed-bag:v1"
  seed.zone_production_additions={"policy":POLICY,"version":1,"source_key":seed.source_key,"module_id":seed.id,"source_id":id,"entity_id":id,"region_id":plan.region_id,"position":site.position,"use_point":site.use_point,"receipt_id":str(seed.source_key)+":regional-production-v1","items":START_ITEMS.duplicate(true),"semantics":"one finite independently searchable S03 bag; no peripheral loot or historical backfill"}
 plan.ecology_sources=[]
 if plan.region_id!="RH-HOME":return {"ok":true}
 var field:Array=plan.landforms.filter(func(row:Dictionary)->bool:return row.use=="field")
 if field.size()!=1:return Data.reject("ECOLOGY_FIELD_MISSING")
 var rect:Array=field[0].xz;var noise:=Raster._noise(int(plan.seed));var roads:=Raster._road_index(plan)
 var chapter:bool=int(plan.get("generation_content_version",1))>=20
 var water_sides:Array=[float(rect[0])+2.0,float(rect[2])-2.0]
 if int(plan.get("generation_content_version",1)) in [13,14,15,16,17,18,19,20,21]:
  # The old two-edge probe can fail on otherwise usable seeded fields.
  # Search a bounded interior lattice; never grant a source off its real floor.
  for x:float in range(ceili(rect[0]+3),floori(rect[2]-3),2):
   if not water_sides.has(x):water_sides.append(x)
  if int(plan.seed)%2==1:water_sides.reverse()
 var water_rows:Array=range(ceili(rect[1]+2),floori(rect[3]-2),2)
 if chapter:water_rows=[42.0,44.0,46.0]+water_rows
 for z:float in water_rows:
  for x:float in water_sides:
   var h:Variant=Water._surface(plan,noise,roads,x,z,1.0)
   var ux:float=x+1.3;var uh:Variant=Water._surface(plan,noise,roads,ux,z,.8)
   if h==null or uh==null or absf(float(h)-float(uh))>.5:continue
   var b:Dictionary={"min":{"x":x-.7,"y":float(h),"z":z-.7},"max":{"x":ux+.6,"y":float(h)+1.8,"z":z+.7}}
   if not Water._clear(plan,b):continue
   if chapter and (not Village.clear_expansion(plan,x,z,1.4) or not Village.clear_expansion(plan,ux,z,.8)):continue
   var occupied:bool=false
   for source:Dictionary in plan.get("water_sources",[]):
    if Vector2(x,z).distance_to(Vector2(source.position.x,source.position.z))<3.5:occupied=true
   for segment:Dictionary in roads.get(Vector2i(floori(x/8),floori(z/8)),[]):
    if Raster._distance(x,z,segment.a,segment.b).x<float(segment.half)+1.0:occupied=true
   if occupied:continue
   var id:String="r34:ecology:raw-source:"+str(plan.region_id)
   var descriptor:Dictionary={"id":id,"source_key":"r34:%d:%s:groundwater-v1"%[int(plan.seed),str(plan.region_id)],"region_id":plan.region_id,"location":{"x":x,"y":float(h),"z":z},"use_point":{"x":ux,"y":float(uh),"z":z,"regionId":plan.region_id,"buildingId":null,"storeyId":null},"kind":"groundwater-raw-v1","capacity":20 if chapter else 12,"initial_units":8 if chapter else 4,"recharge_seconds":90.0 if chapter else 120.0,"policy":POLICY,"water_quality":"raw-not-drinkable"}
   if not Sources.valid(descriptor):return Data.reject("INVALID_ECOLOGY_SOURCE")
   plan.ecology_sources.append(descriptor);return {"ok":true}
 return Data.reject("NO_SAFE_RAW_SOURCE_SITE")

static func apply(draft:Dictionary)->Dictionary:
 if not draft.get("ok",false):return draft
 for seed:Dictionary in draft.plan.get("module_seeds",[]):
  var bag:Variant=seed.get("zone_production_additions")
  if bag==null:continue
  if not _valid_bag(draft.plan,seed,bag) or draft.entities.has(bag.entity_id):return Data.reject("INVALID_INITIAL_SEED_BAG")
  var p:Vector3=G.point(bag.position);var box:=G.json_box(AABB(p-Vector3(.25,0,.25),Vector3(.5,.55,.5)))
  for old:Dictionary in draft.entities.values():
   if old.get("data",{}).get("solid",false) and Data.intersects(box,old.bounds):return Data.reject("SEED_BAG_SITE_OCCUPIED")
  draft.entities[bag.entity_id]={"id":bag.entity_id,"kind":"container","regionId":bag.region_id,"position":bag.position.duplicate(true),"bounds":box,"revision":0,"blocksTerrain":true,"supportBounds":[G.json_box(AABB(p-Vector3(.25,.5,.25),Vector3(.5,.5,.5)))],"data":{"assetId":"r1_storage_container","solid":true,"opaque":false,"dropped":false,"owner":null,"regional_seed_bag":true,"use_point":bag.use_point.duplicate(true)}}
 for descriptor:Dictionary in draft.plan.get("ecology_sources",[]):
  if not Sources.valid(descriptor) or draft.entities.has(descriptor.id):return Data.reject("INVALID_ECOLOGY_SOURCE")
  draft.entities[descriptor.id]=Sources.entity(descriptor)
 return draft

static func opening_additions(world:RefCounted)->Dictionary:
 var config:Variant=world.extension("generation:factory-r34")
 if not config is Dictionary or config.get("content_version") not in [12,13,14,15,16,17,18,19,20,21] or config.get("zone_production_policy")!=POLICY:return {"ok":true,"additions":[]}
 var plan:Variant=world.extension("generation:RH-VILLAGE")
 if not plan is Dictionary or plan.get("zone_production_policy")!=POLICY:return Data.reject("MISSING_ZONE_PRODUCTION_PLAN")
 var rows:Array=[]
 for seed:Dictionary in plan.get("module_seeds",[]):
  var addition:Variant=seed.get("zone_production_additions")
  if addition==null:continue
  if not _valid_bag(plan,seed,addition):return Data.reject("INVALID_INITIAL_SEED_ADDITION")
  rows.append(addition.duplicate(true))
 if rows.size()!=1:return Data.reject("MISSING_S03_INITIAL_SEED_ADDITION")
 return {"ok":true,"additions":rows,"semantics":"DTO only; B original source_receipts/stock_rows authorize first registration, never runtime top-up"}

static func _valid_bag(plan:Dictionary,seed:Dictionary,bag:Variant)->bool:
 var id:String=str(seed.get("id",""))+":regional-seed-bag:v1"
 return plan.get("region_id")=="RH-VILLAGE" and int(plan.get("generation_content_version",0)) in [12,13,14,15,16,17,18,19,20,21] and seed.get("id")=="r34:generated:RH-VILLAGE:store" and seed.get("purpose")=="store" and seed.get("definition_id")==RegionalArt.id_for("r34.module.supply_rear_v3",int(plan.generation_content_version)) and bag is Dictionary and bag.get("policy")==POLICY and bag.get("version")==1 and bag.get("items")==START_ITEMS and bag.get("source_key")==seed.source_key and bag.get("module_id")==seed.id and bag.get("source_id")==id and bag.get("entity_id")==id and bag.get("region_id")==plan.region_id and bag.get("receipt_id")==str(seed.source_key)+":regional-production-v1" and Data.vec(bag.get("position")) and Data.vec(bag.get("use_point")) and bag.use_point.get("regionId")==plan.region_id

static func _bag_site(plan:Dictionary,seed:Dictionary,profile:Dictionary)->Dictionary:
 var service:Array=profile.get("ports",[]).filter(func(p:Dictionary)->bool:return p.get("purpose")=="service")
 if service.size()!=1 or service[0].get("use_points",[]).is_empty():return {}
 var point:Array=service[0].use_points[0];var root:=Vector3(point[0],point[1],point[2]);var turn:int=seed.quarter_turn
 var noise:=Raster._noise(int(plan.seed));var roads:=Raster._road_index(plan)
 for side:float in [1.0,-1.0]:
  for offset:Vector2 in [Vector2(1.4,.4),Vector2(1.8,.4),Vector2(1.4,.9),Vector2(2.2,.4),Vector2(1.4,1.4),Vector2(1.8,1.4),Vector2(2.2,1.4),Vector2(1.8,2.0)]:
   var p:Vector3=G.point(seed.position)+G.rotate(root+Vector3(side*offset.x,0,offset.y),turn)
   var u:Vector3=p+G.rotate(Vector3(side*.9,0,0),turn)
   var h:Variant=Water._surface(plan,noise,roads,p.x,p.z,.5);var uh:Variant=Water._surface(plan,noise,roads,u.x,u.z,.8)
   if h==null or uh==null or absf(float(h)-float(uh))>.5:continue
   p.y=float(h);u.y=float(uh)
   var clear:bool=true
   var local:Vector3=G.rotate(p-G.point(seed.position),(4-turn)%4);var f:Dictionary=profile.footprint
   if local.x>f.min.x-.3 and local.x<f.max.x+.3 and local.z>f.min.z-.3 and local.z<f.max.z+.3:continue
   for parcel:Dictionary in plan.parcels:
    if "r34:generated:"+str(parcel.id)==seed.id:continue
    var r:Array=parcel.pad.xz
    if p.x>r[0]-.3 and p.x<r[2]+.3 and p.z>r[1]-.3 and p.z<r[3]+.3:clear=false
   for tree:Dictionary in plan.resource_sites:
    if Vector2(p.x,p.z).distance_to(Vector2(tree.position.x,tree.position.z))<1.4:clear=false
   for segment:Dictionary in roads.get(Vector2i(floori(p.x/8),floori(p.z/8)),[]):
    if Raster._distance(p.x,p.z,segment.a,segment.b).x<float(segment.half)+.26:clear=false
   for port:Dictionary in profile.ports:
    for use:Array in port.use_points:
     var at:Vector3=G.point(seed.position)+G.rotate(Vector3(use[0],use[1],use[2]),turn)
     if Vector2(p.x-at.x,p.z-at.z).length()<float(port.clearance.radius)+.3:clear=false
   if clear:return {"position":G.json_point(p),"use_point":G.json_point(u).merged({"regionId":plan.region_id,"buildingId":null,"storeyId":null},true)}
 return {}
