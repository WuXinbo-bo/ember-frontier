extends "res://tests/world/ecology_labor.gd"
## Finite isolated labor fixture, real ZoneWork/Terrain/World CAS and pack.
## No free balanced-volume transfer, teleport or simulation shortcut.
const Batch=preload("res://scripts/terrain/terrain_batch.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var active_zone:String=""
func job(kind:String)->Dictionary:
 for c:Dictionary in services.zonework.work_candidates("player"):
  if c.zone_id==active_zone and c.operation==kind:return c
 return {}
func terrain_zone(id:String,bounds:Dictionary,mode:String,height:float,material:int=2)->bool:
 active_zone=id
 var spec:Dictionary={"kind":"terrain","region_id":"RH-HOME","bounds":bounds,"policy":{"mode":mode,"target_height":height,"fill_material":material}}
 var t:int=Time.get_ticks_usec();var preview:Dictionary=services.ecology.preview_zone(spec);preview.cpu_usec=Time.get_ticks_usec()-t
 check("actual preview "+id,preview.ok,preview)
 if not preview.ok:return false
 var result:=command("zone.create",id,{"spec":spec})
 check("actual terrain plan command "+id,result.ok,result);return result.ok
func run()->void:
 check("original rural cells load",world.load_snapshot(Rural.generate(713)).ok)
 var prod:=Production.empty_state();prod.tools=[{"id":"C:fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}},{"id":"C:fixture:pickaxe","kind":"pickaxe","holderId":"pack:player","durability":100.0,"qualities":{"pickaxe":1}}]
 check("finite tools original CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
 var actor:Dictionary={"id":"player","name":"finite earthwork fixture","x":29.25,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{},"intent":null,"relationship":{"consent":true}}
 var configured:=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
 check("actual all-owner Runtime configures",configured.ok,configured)
 if not configured.ok:return finish()
 var cell:Dictionary={"x":58,"y":-1,"z":60};var original:int=world.cell_at(58,-1,60)
 if not terrain_zone("C:cut",{"x0":58,"x1":60,"z0":60,"z1":61},"cut",-.5):return finish()
 var first:=job("terrain_dig");check("stable terrain cell target and exact half-metre plan",not first.is_empty() and first.job.target_id=="terrain:58:-1:60" and first.job.target.y==0,first)
 if first.is_empty():return finish()
 var started:=command("zonework.start",active_zone,{"candidate_id":first.id})
 check("actual earthwork command starts",started.ok,started)
 if not started.ok:return finish()
 step(1);var paused:=command("zonework.pause");var frozen:Dictionary=runtime.actor("player").pack.duplicate(true)
 step(40)
 check("pause keeps actual voxel and material unchanged",paused.ok and world.cell_at(58,-1,60)==original and runtime.actor("player").pack==frozen)
 var resumed:=command("zonework.resume");check("resume same real job",resumed.ok,resumed)
 if not resumed.ok:return finish()
 for _i:int in 160:
  step(1)
  if runtime.actor("player").get("intent")==null:break
 check("real cut changed one voxel and gained exact volume once",runtime.actor("player").get("intent")==null and world.cell_at(58,-1,60)==0 and runtime.actor("player").pack.get("soil_m3")==.125,{"actor":runtime.actor("player"),"work":services.zonework.state(),"cell":world.cell_at(58,-1,60)})
 var second:=job("terrain_dig");check("remaining selected column has separate stable target",not second.is_empty() and second.job.target_id=="terrain:59:-1:60",second)
 if not second.is_empty():
  check("second operation starts",command("zonework.start",active_zone,{"candidate_id":second.id}).ok)
  check("cancel actual in-flight second operation",command("zonework.cancel").ok)
 check("cancel preserves completed work and leaves remaining original soil",world.cell_at(58,-1,60)==0 and world.cell_at(59,-1,60)==original and runtime.actor("player").pack.get("soil_m3")==.125)
 check("cancel planning through original command",command("zone.cancel",active_zone).ok)
 if not terrain_zone("C:fill",{"x0":58,"x1":59,"z0":60,"z1":61},"fill",0):return finish()
 if not labor("terrain_fill",200):return finish()
 check("fill consumes only one carried exact 0.125 unit",world.cell_at(58,-1,60)==2 and runtime.actor("player").pack.get("soil_m3")==0,{"pack":runtime.actor("player").pack,"cell":world.cell_at(58,-1,60)})
 check("finished grade has no spurious terrain job",job("terrain_fill").is_empty())
 var spec:Dictionary={"kind":"terrain","region_id":"RH-HOME","bounds":{"x0":54,"x1":58,"z0":64,"z1":65},"policy":{"mode":"ramp_x","target_height":-.5,"fill_material":2}}
 var ramp:Dictionary=services.ecology.preview_zone(spec)
 check("bounded ramp has real quantized 1:2 or gentler endpoints",ramp.ok and ramp.estimate.voxel_operations==2 and ramp.estimate.cut_m3=={"soil_m3":.25},ramp)
 var invalid:Dictionary=spec.duplicate(true);invalid.policy.target_height=-1000000
 check("extreme height bounded before layer walk",not services.ecology.preview_zone(invalid).ok)
 invalid=spec.duplicate(true);invalid.policy.target_height=-1.0
 check("steep short ramp rejected",not services.ecology.preview_zone(invalid).ok)
 invalid=spec.duplicate(true);invalid.bounds={"x0":62,"x1":63,"z0":60,"z1":61};invalid.policy={"mode":"cut","target_height":-.5}
 check("original road excluded before any labor or material",not services.ecology.preview_zone(invalid).ok)
 var saved:Dictionary=runtime.capture_checkpoint();var encoded:=Store.encode(saved);var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 check("actual terrain/selection/receipts Native save accepted",decoded.ok,decoded.get("code"))
 if decoded.ok:
  var restored:=World.new();check("cold exact material and no original regeneration",restored.load_snapshot(decoded.capture.world).ok and restored.cell_at(58,-1,60)==2 and restored.cell_at(59,-1,60)==original and Data.json_equal(restored.extension(Ecology.KEY),decoded.capture.world.extensions[Ecology.KEY]))
 var terrain_before:Dictionary=world.snapshot();var facts_before:Dictionary=runtime.facts()
 var check_old:Dictionary=services.terrain.availability({"kind":"terrain","actor_id":"player","payload":{"edit":{"operation":"dig","cells":[{"x":59,"y":-1,"z":60}]},"tool_id":"C:fixture:shovel"}})
 check("old single-cell Terrain API remains read-only/available",check_old.ok and world.snapshot()==terrain_before and runtime.facts()==facts_before,check_old)
 finish()
