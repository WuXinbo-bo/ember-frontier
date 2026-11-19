extends "res://tests/world/ecology_lifecycle.gd"
## Bounded original-clock paddy/real adjacent earthwork safety delta only.
## Finite declared tools/seed/raw water; no natural economy or renderer claim.
func edge_edit(operation:String)->bool:
 # Batch selection intentionally protects a wider crop-contact margin. The
 # preexisting exact single-cell path may edit the diagonal without touching
 # the bed's real support. This is a real player edit, not a fixture CAS.
 var result:=command("terrain","",{"edit":{"operation":operation,"cells":[{"x":59,"y":-1,"z":64}],"material":2},"tool_id":"C:fixture:shovel"})
 check("actual original single-cell neighbor edit "+operation,result.ok,result)
 if not result.ok:return false
 for _n:int in 80:
  step(1)
  if runtime.actor("player").get("intent")==null:break
 check("actual original neighbor labor completed "+operation,runtime.actor("player").get("intent")==null)
 return runtime.actor("player").get("intent")==null
func run()->void:
 check("original bounded world unchanged",world.load_snapshot(Rural.generate(713)).ok)
 var prod:=Production.empty_state();prod.tools=[{"id":"C:fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}]
 check("finite boundary tools original CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
 var actor:Dictionary={"id":"player","name":"finite rice boundary fixture","x":29.25,"y":0.0,"z":31.75,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"food":10,"water":10,"r34:rice_seed":1,"r34:raw_water":8},"intent":null,"relationship":{"consent":true}}
 var configured:=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
 check("boundary Runtime configures",configured.ok,configured)
 if not configured.ok:return finish()
 if not zone("C:paddy","farm",58,63,{"crop_id":"rice"}) or not labor("till",180) or not labor("sow",160) or not labor("water",140):return finish()
 var id:String=Rules.plant_id("RH-HOME",{"x":58,"y":0,"z":63})
 var before:Dictionary=services.ecology.state().plants[id]
 check("paddy needs two actual raw units per stage",before.moisture==2 and runtime.actor("player").pack["r34:raw_water"]==7)
 # Neighbor lies across an actual 16-cell chunk boundary, not the crop chunk.
 var key:String=Data.key(Data.cell_chunk(Vector3i(59,0,64),16))
 var cold:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
 check("cold adjacent different chunk via original CAS",cold.ok and world.commit_prepared(cold.capability).ok and key!=Data.key(Data.cell_chunk(Vector3i(58,0,63),16)))
 check("cold paddy footprint cannot produce work",services.ecology.work_candidates(services.zones.zone_records()[0],"player").is_empty())
 var warm:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],world.get_revision())
 check("warm original neighbor retains crop",warm.ok and world.commit_prepared(warm.capability).ok and Data.json_equal(services.ecology.state().plants[id],before))
 if not edge_edit("dig"):return finish()
 check("actual neighbor cut carried one soil volume",world.cell_at(59,-1,64)==0 and runtime.actor("player").pack.get("soil_m3")==.125)
 active_zone="C:paddy"
 var preview:Dictionary=services.ecology.preview_zone({"kind":"farm","region_id":"RH-HOME","bounds":{"x0":58,"x1":59,"z0":63,"z1":64},"policy":{"crop_id":"rice"}})
 check("later nonlevel paddy selection rejected with owner reason",not preview.ok and preview.reasons.has("RICE_REQUIRES_LEVEL_BED"),preview)
 step(6010)
 var stalled:Dictionary=services.ecology.state().plants[id]
 check("actual due does not grow or spend water on later broken paddy",stalled.stage=="seedling" and stalled.moisture==2 and stalled.revision==before.revision and stalled.next_at>runtime.clock(),stalled)
 if not edge_edit("fill"):return finish()
 check("same real soil restores edge once",world.cell_at(59,-1,64)==2 and runtime.actor("player").pack.get("soil_m3")==0)
 active_zone="C:paddy";step(310)
 check("restored physical paddy resumes original stage and spends two water",services.ecology.state().plants[id].stage=="growing" and services.ecology.state().plants[id].moisture==0)
 if not labor("water",160) or not labor("water",160):return finish()
 step(6010)
 check("repaired paddy actual next stage becomes mature",services.ecology.state().plants[id].stage=="mature")
 if not labor("harvest_crop",200):return finish()
 check("one actual rice yield/residue, protected seed",runtime.actor("player").pack.get("r34:paddy")==4 and runtime.actor("player").pack.get("r34:crop_residue")==1 and services.ecology.state().plants[id].seed_reserved==1)
 capture_roundtrip("real cross-chunk rice repair")
 finish()
