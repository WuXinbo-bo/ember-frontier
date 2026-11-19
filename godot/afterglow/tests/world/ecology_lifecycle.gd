extends "res://tests/world/ecology_labor.gd"
## Explicit finite inputs, original labor/clock/tree harvesting, no maturity
## injection. This does not claim the normal opening economy or VA.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var active_zone:String=""
var care_ticks:int=0
func labor(kind:String,limit:int)->bool:
 if float(runtime.actor("player").stamina)<25:
  for _r:int in 8:
   var rested:=command("rest")
   if not rested.ok:break
   for _t:int in 140:
    runtime.tick(.1)
    if runtime.actor("player").get("intent")==null:break
   if float(runtime.actor("player").stamina)>=60:break
 return super.labor(kind,limit)
func step(count:int)->void:
 for _n:int in count:
  runtime.tick(.1);care_ticks+=1
  if care_ticks%100!=0 or runtime.actor("player").get("intent")!=null:continue
  for need:Array in [["hunger","food","eat"],["thirst","water","drink"]]:
   if float(runtime.actor("player")[need[0]])<50 and runtime.actor("player").pack.get(need[1],0)>0:
    var result:=command(need[2])
    if result.ok:
     for _c:int in 60:
      runtime.tick(.1)
      if runtime.actor("player").get("intent")==null:break
func job(kind:String)->Dictionary:
 for c:Dictionary in services.zonework.work_candidates("player"):
  if c.zone_id==active_zone and c.operation==kind:return c
 return {}
func zone(id:String,kind:String,x:int,z:int,policy:Dictionary)->bool:
 active_zone=id
 var result:=command("zone.create",id,{"spec":{"kind":kind,"region_id":"RH-HOME","bounds":{"x0":x,"x1":x+1,"z0":z,"z1":z+1},"policy":policy}})
 check("actual zone "+id,result.ok,result)
 return result.ok
func policy(values:Dictionary)->bool:
 var result:=command("zone.policy",active_zone,{"patch":{"policy":values}})
 check("policy command "+active_zone,result.ok,result);return result.ok
func capture_roundtrip(label:String)->bool:
 var before:Dictionary=runtime.capture_checkpoint();var save:Dictionary=Store.encode(before);var decoded:Dictionary=Store.decode(save.text) if save.ok else save
 check(label+" canonical codec accepts",decoded.ok,decoded.get("code"))
 if not decoded.ok:return false
 var outer:Dictionary=JSON.parse_string(JSON.parse_string(save.text).payload);var canonical:Dictionary=JSON.parse_string(outer.world.payload).world.extensions[Ecology.KEY]
 check(label+" exact canonical ecology",Data.json_equal(decoded.capture.world.extensions[Ecology.KEY],canonical))
 var restored:=World.new();check(label+" new authority loads all cells/entities",restored.load_snapshot(decoded.capture.world).ok)
 check(label+" exact world identity/tree/drop preserved",Data.json_equal(restored.identity(),world.identity()) and decoded.capture.world.entities.keys().all(func(id:String)->bool:return Data.json_equal(restored.entity(id),decoded.capture.world.entities[id])),{"identity":restored.identity(),"source_identity":world.identity(),"mismatch_ids":decoded.capture.world.entities.keys().filter(func(id:String)->bool:return not Data.json_equal(restored.entity(id),decoded.capture.world.entities[id]))})
 return true
func run()->void:
 check("old finite terrain loaded",world.load_snapshot(Rural.generate(713)).ok)
 var prod:=Production.empty_state();prod.tools=[{"id":"C:fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}},{"id":"C:fixture:axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0,"qualities":{"chopping":1}}]
 check("explicit finite tools original CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
 var actor:Dictionary={"id":"player","name":"finite lifecycle fixture","x":29.25,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"food":100,"water":100,"r34:potato_seed":2,"r34:bean_seed":2,"r34:rice_seed":2,"r34:raw_water":24,"r34:compost":4,"r34:broadleaf_seed":2},"intent":null,"relationship":{"consent":true}}
 var configured:=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
 check("real lifecycle Runtime configures",configured.ok,configured)
 if not configured.ok:return finish()
 var i:int=0
 for species:String in ["potato","bean","rice"]:
  var x:int=58;var z:int=60+i*4;i+=1
  if not zone("C:crop:"+species,"farm",x,z,{"crop_id":species}):return finish()
  if not labor("till",200) or not labor("sow",200):return finish()
  var id:String=Rules.plant_id("RH-HOME",{"x":x,"y":0,"z":z});var before_seed:float=runtime.actor("player").pack[Rules.CROPS[species].seed]
  if species=="rice" and not labor("water",160):return finish()
  step(int(Rules.CROPS[species].seconds*5)+2)
  check(species+" unique clock actual growing",world.extension(Ecology.KEY).plants[id].stage=="growing")
  for _n:int in int(Rules.CROPS[species].water):
   if not labor("water",160):return finish()
  step(int(Rules.CROPS[species].seconds*5)+2)
  check(species+" actual mature",world.extension(Ecology.KEY).plants[id].stage=="mature")
  if not labor("harvest_crop",180):return finish()
  check(species+" sole yield and retained seed/fertility",runtime.actor("player").pack.get(Rules.CROPS[species].item)==Rules.CROPS[species].yield and world.extension(Ecology.KEY).plants[id].seed_reserved==1 and world.extension(Ecology.KEY).plants[id].fertility==1)
  if species=="potato":
   if not policy({"crop_id":"bean"}):return finish()
   var c:=job("sow");check("crop change preserves old retained seed",not c.is_empty() and not c.valid and world.extension(Ecology.KEY).plants[id].seed_reserved==1,c.get("reason"))
   if not policy({"crop_id":"bean","mode":"recover_seed"}) or not labor("recover_seed",100):return finish()
   check("recover real retained seed once",runtime.actor("player").pack["r34:potato_seed"]==before_seed+1 and world.extension(Ecology.KEY).plants[id].seed_reserved==0)
   if not policy({"crop_id":"bean","mode":"normal"}) or not labor("sow",160):return finish()
   var bean_seed:float=runtime.actor("player").pack["r34:bean_seed"];var beans:float=runtime.actor("player").pack.get("r34:beans",0)
   if not policy({"crop_id":"bean","mode":"clear"}) or not labor("remove_crop",180):return finish()
   check("explicit immature clearance gives no seed or crop refund",world.extension(Ecology.KEY).plants[id].kind=="bed" and world.extension(Ecology.KEY).plants[id].stage=="tilled" and runtime.actor("player").pack["r34:bean_seed"]==bean_seed and runtime.actor("player").pack.get("r34:beans",0)==beans)
  else:
   if not labor("sow",140):return finish()
   check(species+" retained seed resumes real next cycle",world.extension(Ecology.KEY).plants[id].seed_reserved==0 and runtime.actor("player").pack[Rules.CROPS[species].seed]==before_seed)
  check("disable completed test field",command("zone.update",active_zone,{"patch":{"enabled":false}}).ok)
 if not capture_roundtrip("crop stages and seed identities"):return finish()
 if not zone("C:nursery","forestry",70,60,{"tree_id":"broadleaf","mode":"nursery","replant":false,"conserve":true}):return finish()
 if not labor("nursery",400):return finish()
 check("real nursery only transfers one seed and one raw unit",runtime.actor("player").pack["r34:broadleaf_seed"]==1 and runtime.actor("player").pack.get("r34:broadleaf_seedling")==1)
 if not policy({"tree_id":"broadleaf","mode":"sustainable","replant":true,"conserve":true}) or not labor("plant_tree",400):return finish()
 var tree_id:String=Rules.plant_id("RH-HOME",{"x":70,"y":0,"z":60});var p:Dictionary=world.extension(Ecology.KEY).plants[tree_id]
 var entity_id:String=p.entity_id;var drop_id:String=p.output_id
 check("seedling has one real protected World entity/drop stock",world.entity(entity_id).data.harvest.phase=="growing" and world.entity(entity_id).data.solid and runtime.stock(drop_id).items.is_empty() and runtime.actor("player").pack["r34:broadleaf_seedling"]==0)
 # No growth write may conceal an actor in the trunk. Actor remains at actual
 # side work feet; the normal growth path checks all actors/physical bodies.
 step(12002)
 check("A clock grows actual trunk and harvest remains protected",world.extension(Ecology.KEY).plants[tree_id].stage=="growing" and world.entity(entity_id).data.harvest.phase=="growing" and world.entity(entity_id).bounds.max.y==2.0,{"plant":world.extension(Ecology.KEY).plants[tree_id],"time":runtime.clock(),"entity":world.entity(entity_id)})
 var cell_key:String=Data.key(Data.cell_chunk(Vector3i(70,0,60),16));var cold:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":cell_key,"before":true,"after":false}],world.get_revision())
 check("explicit cold one chunk through original World CAS",cold.ok and world.commit_prepared(cold.capability).ok)
 var cold_ec:Dictionary=world.extension(Ecology.KEY)
 check("cold region exposes no ecological work or visuals",services.ecology.work_candidates(services.zones.zone_records()[0],"player").is_empty() and not services.ecology.presentation_basis().detailed)
 step(36002)
 check("cold growth cannot grant maturity",world.extension(Ecology.KEY).plants[tree_id].stage=="growing")
 var warm:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":cell_key,"before":false,"after":true}],world.get_revision())
 check("original warm CAS",warm.ok and world.commit_prepared(warm.capability).ok)
 step(20)
 check("warm actual mature tree preserves entity/drop identity",world.extension(Ecology.KEY).plants[tree_id].stage=="mature" and world.extension(Ecology.KEY).plants[tree_id].entity_id==entity_id and world.entity(entity_id).bounds.max.y==4.0)
 if not labor("collect_seed",240):return finish()
 check("mature original tree source provides exactly two seed",runtime.actor("player").pack["r34:broadleaf_seed"]==3)
 check("seed cooldown rejects replay",job("collect_seed").is_empty())
 var nursery_disabled := command("zone.update", active_zone, {"patch": {"enabled": false}})
 check("forest policy yields the selected cell to player clearing", nursery_disabled.ok, nursery_disabled)
 if not nursery_disabled.ok: return finish()
 var clear_policy: Dictionary = {"worker_ids":["player"], "mode":"player_clear"}
 var clear_spec: Dictionary = {"kind":"clear", "region_id":"RH-HOME", "bounds":{"x0":70,"x1":71,"z0":60,"z1":61}, "policy":clear_policy}
 var clear_preview: Dictionary = runtime.zone_preview(clear_spec)
 var preview_matches: bool = clear_preview.ok and clear_preview.estimate.trees == 1 and clear_preview.estimate.stumps == 0 and world.entity(entity_id).data.harvest.phase == "standing"
 check("player clearing counts the live tree without changing it", preview_matches, clear_preview)
 if not preview_matches: return finish()
 if not zone("C:player-clearing", "clear", 70, 60, clear_policy) or not labor("harvest_tree",800):return finish()
 check("only original production awards actual three logs",runtime.stock(drop_id).items.get("log")==3 and world.entity(entity_id).data.harvest.phase=="stump")
 var scoped_clear_work: Array = services.zonework.work_candidates("player", {}, {}, active_zone)
 var stump_offered: bool = scoped_clear_work.any(func(candidate: Dictionary) -> bool:
  return candidate.get("operation") == "clear_stump")
 var only_clear_work: bool = scoped_clear_work.all(func(candidate: Dictionary) -> bool:
  return candidate.get("zone_id") == active_zone and (candidate.get("kind") == "supply" or candidate.get("operation") == "clear_stump"))
 check("scoped clearing only offers the stump after harvesting", stump_offered and only_clear_work, scoped_clear_work)
 if not labor("clear_stump",400):return finish()
 check("cleared stump retires old identity, no duplicate log",world.entity(entity_id).is_empty() and world.retired_entity_ids().has(entity_id) and runtime.stock(drop_id).items.get("log")==3 and world.extension(Ecology.KEY).plants[tree_id].stage=="cleared")
 var clearing_closed := command("zone.cancel", active_zone)
 var nursery_restored := command("zone.update", "C:nursery", {"patch": {"enabled": true}}) if clearing_closed.ok else {}
 var reopened: bool = clearing_closed.ok and nursery_restored.get("ok", false)
 check("finishing clearing releases the cell", reopened, [clearing_closed, nursery_restored])
 if not reopened: return finish()
 active_zone="C:nursery"
 if not policy({"tree_id":"broadleaf","mode":"nursery","replant":false,"conserve":true}):return finish()
 # Nursery may use another free cell; a cleared slot is reserved for replant.
 if not zone("C:nursery:two","forestry",74,60,{"tree_id":"broadleaf","mode":"nursery","replant":false,"conserve":true}) or not labor("nursery",400):return finish()
 active_zone="C:nursery"
 if not policy({"tree_id":"broadleaf","mode":"sustainable","replant":true,"conserve":true}) or not labor("plant_tree",400):return finish()
 p=world.extension(Ecology.KEY).plants[tree_id]
 check("new cycle never resurrects retired tree or refills old drop",p.cycle==1 and p.entity_id!=entity_id and p.output_id!=drop_id and runtime.stock(drop_id).items.get("log")==3 and runtime.stock(p.output_id).items.is_empty() and world.retired_entity_ids().has(entity_id))
 capture_roundtrip("actual forestry seed/stump/new-cycle")
 finish()
