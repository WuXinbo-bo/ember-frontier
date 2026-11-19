extends "res://tests/world/ecology_cold_work.gd"
## Targeted persistence regression: exact original single-cell and batch
## material/face semantics, without repeating the already accepted29 suite.
func roundtrip_active(label:String)->bool:
 var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 check(label+" actual held intent encodes/decodes",decoded.ok,decoded.get("code"))
 if not decoded.ok:return false
 FileAccess.open(OS.get_cmdline_user_args()[0]+"."+label+".native.json",FileAccess.WRITE).store_string(encoded.text)
 runtime.retire();runtime=Runtime.new();world=World.new()
 check(label+" full Runtime accepts original JSON intent",mount(decoded.capture))
 if checks[-1].ok!=true:return false
 check(label+" original bounded warm",warm_region("RH-HOME"))
 return checks[-1].ok
func run()->void:
 check("unchanged old terrain loaded",world.load_snapshot(Rural.generate(713)).ok)
 var prod:=Production.empty_state();prod.tools=[{"id":"C:fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}]
 check("declared finite tool original CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
 var actor:Dictionary={"id":"player","name":"finite terrain cold fixture","x":29.25,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{},"intent":null,"relationship":{"consent":true}}
 check("original full Runtime configures",runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services}).ok)
 for operation:String in ["dig","fill"]:
  var started:=command("terrain","",{"edit":{"operation":operation,"cells":[{"x":59,"y":-1,"z":60}],"material":2},"tool_id":"C:fixture:shovel"})
  check("original "+operation+" actual command starts",started.ok,started)
  if not started.ok:return finish()
  step(1)
  if not roundtrip_active(operation):return finish()
  var intent:Dictionary=runtime.actor("player").intent
  check(operation+" exact JSON float coordinates retained",intent.request.payload.edit.cells[0].x is float and intent.request.payload.edit.material is float)
  var invalid:Dictionary=intent.duplicate(true);invalid.request.payload.edit.material=2.5
  check(operation+" fractional material remains rejected",not services.terrain.validate_intent(invalid,runtime.actor("player")).ok)
  invalid=intent.duplicate(true);invalid.request.payload.edit.cells[0].x=true
  check(operation+" bool coordinate remains rejected",not services.terrain.validate_intent(invalid,runtime.actor("player")).ok)
  for _n:int in 30:
   step(1)
   if runtime.actor("player").get("intent")==null:break
  check(operation+" completes real original face after cold",runtime.actor("player").get("intent")==null and world.cell_at(59,-1,60)==(0 if operation=="dig" else 2) and runtime.actor("player").pack.get("soil_m3")==(.125 if operation=="dig" else 0),runtime.actor("player"))
 var region_spec:Dictionary={"kind":"terrain","region_id":"RH-HOME","bounds":{"x0":59,"x1":60,"z0":60,"z1":61},"policy":{"mode":"cut","target_height":-.5,"fill_material":2}}
 check("batch zone actual command",command("zone.create","C:terrain:cold",{"spec":region_spec}).ok)
 var c:=job("terrain_dig");check("batch actual candidate exists",not c.is_empty(),c)
 if c.is_empty():return finish()
 check("batch actual labor starts",command("zonework.start",str(c.zone_id),{"candidate_id":c.id}).ok)
 step(1)
 if not roundtrip_active("batch"):return finish()
 for _n:int in 180:
  step(1)
  if runtime.actor("player").get("intent")==null:break
 check("batch JSON job actual face settles once after cold",runtime.actor("player").get("intent")==null and world.cell_at(59,-1,60)==0 and runtime.actor("player").pack.get("soil_m3")==.125,runtime.actor("player"))
 finish()
