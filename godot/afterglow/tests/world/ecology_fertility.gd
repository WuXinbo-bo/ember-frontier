extends "res://tests/world/ecology_lifecycle.gd"
## Four actual cycles in unchanged rural terrain, finite declared initial
## construction/tools/food/water/one seed; no initial compost or residue.
## Uses real paid module construction and B's original sole craft ledger.
const Modules=preload("res://scripts/modules/module_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
var station:String="C:fertility:actual-water-station"
var field:String="C:fertility:one-field"
func idle(label:String,limit:int)->bool:
 for _n:int in limit:
  step(1)
  if runtime.actor("player").get("intent")==null:break
 var ok:bool=runtime.actor("player").get("intent")==null
 check(label+" actual arrival/labor ends",ok,runtime.actor("player") if not ok else null)
 return ok
func cold()->bool:
 var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 check("four-cycle actual labor Native encodes/decodes",decoded.ok,decoded.get("code"))
 if not decoded.ok:return false
 FileAccess.open(OS.get_cmdline_user_args()[0]+".at"+str(int(runtime.clock()))+".native.json",FileAccess.WRITE).store_string(encoded.text)
 runtime.retire();runtime=Runtime.new();world=World.new()
 check("four-cycle new World loads exact persisted facts",world.load_snapshot(decoded.capture.world).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new(),"modules":Modules.new()}
 var context:Dictionary=decoded.capture.duplicate(true);context.world=world;context.services=services
 var result:Dictionary=runtime.configure(context);check("four-cycle full new Runtime validates exact JSON",result.ok,result)
 if not result.ok:return false
 for _n:int in 64:
  var p:Dictionary=world.prepare_region_residency("RH-HOME",true,world.get_revision(),32)
  if not p.ok:return false
  if not p.world_changes.is_empty() and not commit(p.world_changes).ok:return false
  if p.complete:break
 check("original bounded warm only, same extensions/items/modules",world.region_is_resident("RH-HOME") and Data.json_equal(world.snapshot().extensions,decoded.capture.world.extensions) and Data.json_equal(runtime.facts().actors,decoded.capture.facts.actors))
 return checks[-1].ok
func run()->void:
 check("unchanged rural terrain loads",world.load_snapshot(Rural.generate(713)).ok)
 var prod:=Production.empty_state();prod.tools=[{"id":"C:fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}},{"id":"C:fixture:hammer","kind":"hammer","holderId":"pack:player","durability":100.0,"qualities":{"hammering":1}}]
 check("finite declared tools original World CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new(),"modules":Modules.new()}
 var actor:Dictionary={"id":"player","name":"finite four-cycle fixture","x":40.0,"y":0.0,"z":27.1,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"timber":8,"stone_m3":1,"scrap":2,"food":100,"water":100,"r34:potato_seed":1,"r34:raw_water":12},"intent":null,"relationship":{"consent":true}}
 var configured:=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
 check("full finite fixture Runtime configures",configured.ok,configured)
 if not configured.ok:return finish()
 var plan:=command("module.plan",station,{"definition_id":"r34.module.water_low_v1.mechanism-v2","position":{"x":40,"y":0,"z":30,"regionId":"RH-HOME"},"quarter_turn":0,"source_id":"pack:player","tool_id":"C:fixture:hammer"})
 check("actual finite paid water building starts",plan.ok,plan)
 if not plan.ok or not idle("paid building",300):return finish()
 var module:Dictionary=services.modules.instance(station)
 check("real completed geometry/cost, no water/residue/compost grant",module.status=="operational" and not module.members.is_empty() and runtime.actor("player").pack.timber==0 and runtime.actor("player").pack.stone_m3==0 and runtime.actor("player").pack.scrap==0 and runtime.actor("player").pack["r34:raw_water"]==12 and runtime.actor("player").pack.get("r34:compost",0)==0 and runtime.actor("player").pack.get("r34:crop_residue",0)==0,module)
 # Even if a zone predates this building, completion rechecks the real port.
 var port:Dictionary=Shape.ports(module,Catalog.definition(module.definition_id))[0].location
 var cell:Dictionary={"x":floori(port.x*2),"y":-1,"z":floori(port.z*2)}
 var target:Dictionary={"x":(cell.x+.5)*.5,"y":0.0,"z":(cell.z+.5)*.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
 var job:Dictionary={"id":"C:probe:port","kind":"terrain_dig","target_id":"terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],"cell":cell,"region_id":"RH-HOME","location":port,"target":target,"revision":0,"before":world.cell_at(cell.x,-1,cell.z),"material":2}
 var before_port:Dictionary=runtime.capture_checkpoint();var tx:=Draft.new(services.zonework.context)
 var protected:Dictionary=services.ecology.check_work(tx,job,"player")
 check("new real module service exit protected at completion, read-only",not protected.ok and protected.code=="PROTECTED_SERVICE_EXIT" and Data.json_equal(before_port,runtime.capture_checkpoint()),protected)
 if not zone(field,"farm",58,60,{"crop_id":"potato"}) or not labor("till",400):return finish()
 var id:String=Rules.plant_id("RH-HOME",{"x":58,"y":0,"z":60})
 for cycle:int in range(1,5):
  active_zone=field
  if not labor("sow",300):return finish()
  if cycle==3:
   check("two harvests really exhaust fertility and create only two residues",world.extension(Ecology.KEY).plants[id].fertility==0 and runtime.actor("player").pack["r34:crop_residue"]==2 and runtime.actor("player").pack.get("r34:compost",0)==0)
   var missing:Dictionary=services.ecology.check_work(Draft.new(services.zonework.context),job("compost").job,"player")
   check("unavailable real compost returns exact supply need, no gift",not missing.ok and missing.code=="MISSING_ECOLOGY_INPUT" and missing.requirements.cost=={"r34:compost":1} and missing.requirements.reusable.is_empty(),missing)
   var before_water:float=runtime.actor("player").pack["r34:raw_water"]
   var crafted:=command("craft",station,{"direct":false,"recipe_id":"r34:compost_v2","source_id":"pack:player","output_id":"pack:player","tool_ids":["C:fixture:shovel"]})
   check("B original craft admits real harvested residues",crafted.ok,crafted)
   if not crafted.ok or not idle("original compost craft",600):return finish()
   check("single original craft transfers exact two residues and one raw water",runtime.actor("player").pack["r34:crop_residue"]==0 and runtime.actor("player").pack["r34:raw_water"]==before_water-1 and runtime.actor("player").pack["r34:compost"]==1)
   if not labor("compost",400):return finish()
   check("one real compost restores exactly two fertility",world.extension(Ecology.KEY).plants[id].fertility==2 and runtime.actor("player").pack["r34:compost"]==0)
   if not cold():return finish()
  var p:Dictionary=world.extension(Ecology.KEY).plants[id]
  if p.moisture<1 and not labor("water",300):return finish()
  step(3010)
  check("cycle "+str(cycle)+" actual first due grows",world.extension(Ecology.KEY).plants[id].stage=="growing",world.extension(Ecology.KEY).plants[id])
  if not labor("water",180):return finish()
  step(3010)
  check("cycle "+str(cycle)+" actual second due matures",world.extension(Ecology.KEY).plants[id].stage=="mature")
  if not labor("harvest_crop",200):return finish()
  check("cycle "+str(cycle)+" one yield and same protected seed",runtime.actor("player").pack.get("r34:potato")==cycle*3 and runtime.actor("player").pack["r34:potato_seed"]==0 and world.extension(Ecology.KEY).plants[id].seed_reserved==1 and world.extension(Ecology.KEY).plants[id].fertility==(1 if cycle in [1,3] else 0))
  if cycle==2 and not cold():return finish()
 check("four cycles exact final seed/residue/water/fertility accounting",runtime.actor("player").pack["r34:potato"]==12 and runtime.actor("player").pack["r34:raw_water"]==4 and runtime.actor("player").pack["r34:crop_residue"]==2 and runtime.actor("player").pack["r34:compost"]==0 and world.extension(Ecology.KEY).plants[id].fertility==0 and world.extension(Ecology.KEY).plants[id].seed_reserved==1,runtime.actor("player").pack)
 cold();finish()
