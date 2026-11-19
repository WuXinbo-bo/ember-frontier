extends RefCounted
## A real source descriptor authorizes raw water, never a building radius.
## No weather, safe-water conversion, private inventory or wall-clock refill.
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
static func valid(d:Variant)->bool:
 if not d is Dictionary or not d.has_all(["id","source_key","region_id","location","use_point","capacity","initial_units","recharge_seconds","kind"]):return false
 if not Data.valid_id(d.id) or not Data.valid_id(d.source_key) or not Data.valid_id(d.region_id) or not Data.vec(d.location) or not Data.vec(d.use_point) or d.use_point.get("regionId")!=d.region_id:return false
 if d.kind!="groundwater-raw-v1" or not Data.integer(d.capacity) or not Data.integer(d.initial_units) or d.capacity<1 or d.capacity>64 or d.initial_units<0 or d.initial_units>d.capacity:return false
 return (d.recharge_seconds is int or d.recharge_seconds is float) and is_finite(float(d.recharge_seconds)) and d.recharge_seconds>=60 and d.recharge_seconds<=86400
static func first(d:Dictionary,time:float)->Dictionary:
 return {"id":d.id,"source_key":d.source_key,"remaining":int(d.initial_units),"revision":0,"updated_at":time,"fraction":0.0}
static func observe(d:Dictionary,stored:Dictionary,time:float,recharge_units:float=1.0)->Dictionary:
 var row:Dictionary=first(d,time) if stored.is_empty() else stored.duplicate(true)
 # A source begins refilling only after its first real draw/registration. No
 # retroactive grant to a historical save or fake elapsed wall-clock catch-up.
 if time<row.updated_at:return {}
 var total:float=float(row.fraction)+(time-float(row.updated_at))*recharge_units/float(d.recharge_seconds)
 var units:int=floori(total);row.updated_at=time
 row.remaining=mini(int(d.capacity),int(row.remaining)+units)
 row.fraction=0.0 if row.remaining==d.capacity else total-units
 return row
static func entity(d:Dictionary)->Dictionary:
 var p:=G.point(d.location)
 return {"id":d.id,"kind":"raw_water_source","regionId":d.region_id,"position":G.json_point(p),"bounds":G.json_box(AABB(p-Vector3(.45,0,.45),Vector3(.9,1.05,.9))),"revision":0,"blocksTerrain":true,"supportBounds":[G.json_box(AABB(p-Vector3(.45,.5,.45),Vector3(.9,.5,.9)))],"data":{"solid":true,"opaque":true,"raw_water_source":d.duplicate(true),"visual_owner":"ecology","appearance":{"model":"existing-well","height":1.05}}}
