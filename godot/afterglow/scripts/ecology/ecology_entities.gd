extends RefCounted
## Real World tree/body/drop facts. Rendering and original harvest consume these
## same entities; this helper never awards a log or runs a private simulation.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Rules=preload("res://scripts/ecology/ecology_rules.gd")

static func tree(plant:Dictionary,content_version:int=0)->Dictionary:
 var p:Dictionary=G.json_point(G.point(plant.location));var stage:String=plant.stage
 var height:float=0.8 if stage=="seedling" else 2.0 if stage=="growing" else 4.0
 var radius:float=0.08 if stage=="seedling" else 0.18 if stage=="growing" else 0.35
 return {"id":plant.get("entity_id",plant.id),"kind":"tree","regionId":plant.region_id,"position":p,"bounds":G.json_box(AABB(G.point(p)-Vector3(radius,0,radius),Vector3(radius*2,height,radius*2))),"revision":0,"blocksTerrain":true,"supportBounds":[G.json_box(AABB(G.point(p)-Vector3(.35,.5,.35),Vector3(.7,.5,.7)))],"data":{"solid":true,"opaque":true,"ecology_id":plant.id,"ecology_stage":stage,"outputId":plant.output_id,"harvest":{"phase":"standing" if stage=="mature" else "growing","work":0,"seconds":12 if content_version in [16,17,18,19,20,21] else 24,"toolWear":6,"yield":{"log":3}},"appearance":{"version":1,"surface_version":1,"surface_variant":0,"model":Rules.TREES[plant.tree_id].model,"height":height,"yaw":0.0}}}

static func bed(plant:Dictionary)->Dictionary:
 var p:Dictionary=G.json_point(G.point(plant.location))
 return {"id":plant.id,"kind":"ecology_bed","regionId":plant.region_id,"position":p,"bounds":G.json_box(AABB(G.point(p)-Vector3(.245,0,.245),Vector3(.49,.03,.49))),"revision":0,"blocksTerrain":true,"supportBounds":[G.json_box(AABB(G.point(p)-Vector3(.245,.5,.245),Vector3(.49,.5,.49)))],"data":{"solid":false,"opaque":false,"ecology_id":plant.id,"visual_owner":"ecology"}}

static func drop(plant:Dictionary)->Dictionary:
 var p:Dictionary=G.json_point(G.point(plant.drop_location))
 return {"id":plant.output_id,"kind":"container","regionId":plant.region_id,"position":p,"bounds":G.json_box(AABB(G.point(p)-Vector3(.15,0,.15),Vector3(.3,.2,.3))),"revision":0,"blocksTerrain":false,"data":{"dropped":true,"inventoryOwner":"runtime","owner":null,"searched":true,"sourceId":plant.id}}

static func put(tx:RefCounted,world:RefCounted,entity:Dictionary)->void:
 var old:Dictionary=world.entity(entity.id)
 tx.extra.append({"op":"entity.put","id":entity.id,"before_exists":not old.is_empty(),"before":null if old.is_empty() else old,"after":entity})
