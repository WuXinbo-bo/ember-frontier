extends SceneTree
## Explicit finite agronomy fixture through the real Runtime/Zone/ZoneWork.
## Not a new-world economy, natural source, PCK, renderer or visual acceptance.
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Ecology=preload("res://scripts/ecology/ecology_service.gd")
const Zones=preload("res://scripts/planning/zone_service.gd")
const Work=preload("res://scripts/planning/zone_work_service.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Rules=preload("res://scripts/ecology/ecology_rules.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var checks:Array=[];var commands:Array=[];var sequence:int=0
var world:=World.new();var runtime:=Runtime.new();var services:Dictionary
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
 checks.append({"label":label,"ok":ok,"detail":detail})
 if not ok:print("FAIL ",label," ",detail)
func commit(changes:Array)->Dictionary:
 var d:=world.prepare_changes(changes,world.get_revision())
 return world.commit_prepared(d.capability) if d.ok else d
func command(kind:String,target:String="",payload:Dictionary={})->Dictionary:
 sequence+=1
 var request:Dictionary={"command_id":"C:ecology:"+str(sequence),"actor_id":"player","kind":kind,"target_id":target,"payload":payload}
 var result:Dictionary=runtime.command(request);commands.append({"request":request,"result":result});return result
func step(count:int)->void:
 for _i:int in count:runtime.tick(.1)
func job(kind:String)->Dictionary:
 for c:Dictionary in services.zonework.work_candidates("player"):
  if c.operation==kind:return c
 return {}
func labor(kind:String,limit:int)->bool:
 var c:=job(kind)
 check("actual candidate "+kind,not c.is_empty(),c)
 if c.is_empty():return false
 var started:=command("zonework.start",str(c.zone_id),{"candidate_id":c.id})
 check("actual command starts "+kind,started.ok,started)
 if not started.ok:return false
 for _i:int in limit:
  step(1)
  if runtime.actor("player").get("intent")==null:break
 var done:bool=runtime.actor("player").get("intent")==null
 check("effective labor completes "+kind,done,{"actor":runtime.actor("player"),"work":services.zonework.state()})
 return done
func run()->void:
 check("unmodified finite old terrain loads",world.load_snapshot(Rural.generate(713)).ok)
 var prod:=Production.empty_state();prod.tools=[{"id":"C:fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}]
 check("explicit finite fixture tools inserted by original CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
 var actor:Dictionary={"id":"player","name":"finite fixture","x":29.25,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"r34:potato_seed":2,"r34:raw_water":8,"r34:compost":2},"intent":null,"relationship":{"consent":true}}
 var configured:=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
 check("real Runtime all ecology/zonework owners configured",configured.ok,configured)
 if not configured.ok:return finish()
 var spec:Dictionary={"kind":"farm","region_id":"RH-HOME","bounds":{"x0":58,"x1":59,"z0":60,"z1":61},"policy":{"crop_id":"potato"}}
 var preview:Dictionary=services.ecology.preview_zone(spec)
 check("true half-metre ground boundary and volume preview",preview.ok and preview.cells==[{"x":58,"y":0,"z":60}],preview)
 var created:=command("zone.create","C:field",{"spec":spec})
 check("zone real command changes no crop inventory",created.ok and runtime.actor("player").pack["r34:potato_seed"]==2,created)
 if not created.ok:return finish()
 if not labor("till",140):return finish()
 var id:String=Rules.plant_id("RH-HOME",{"x":58,"y":0,"z":60})
 check("true protective bed in sole World",world.entity(id).get("kind")=="ecology_bed")
 if not labor("sow",120):return finish()
 check("seed consumed once and seedling persisted",runtime.actor("player").pack["r34:potato_seed"]==1 and world.extension(Ecology.KEY).plants[id].stage=="seedling")
 var before:Dictionary=runtime.capture_checkpoint();var ec:Dictionary=world.extension(Ecology.KEY);var detached:=world.extension_entries(Ecology.KEY,"plants",[id]);detached[id].stage="mature"
 check("nested selected projection owns its mutable data",world.extension(Ecology.KEY)==ec and runtime.capture_checkpoint()==before)
 var view:Dictionary=services.ecology.presentation_projection()
 check("real DTO bed uses boundary y and ecological visual owner",view.visuals.size()==1 and view.visuals[0].location.y==0 and view.visuals[0].visual_owner=="ecology",view)
 # Actual clock progression, no injected maturity/revision/capture edit.
 step(3010)
 check("A clock advances seedling into growing",world.extension(Ecology.KEY).plants[id].stage=="growing",world.extension(Ecology.KEY).plants[id])
 if not labor("water",120):return finish()
 step(3010)
 check("real watered plant reaches mature",world.extension(Ecology.KEY).plants[id].stage=="mature",world.extension(Ecology.KEY).plants[id])
 if not labor("harvest_crop",180):return finish()
 check("same Draft yield and protected retained seed",runtime.actor("player").pack.get("r34:potato",0)==3 and world.extension(Ecology.KEY).plants[id].seed_reserved==1)
 var seed_before:float=runtime.actor("player").pack["r34:potato_seed"]
 if labor("sow",120):check("retained seed resows without a second external seed",runtime.actor("player").pack["r34:potato_seed"]==seed_before and world.extension(Ecology.KEY).plants[id].seed_reserved==0)
 var bad:Dictionary=world.extension(Ecology.KEY);bad.next_due=-1
 check("faked idle due metadata rejected by full owner validator",not services.ecology.validate_extensions(runtime.facts(),{Ecology.KEY:bad}).ok)
 var save:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(save.text) if save.ok else save
 check("real full Native codec accepts ecology and current intents",decoded.ok,decoded.get("code"))
 if decoded.ok:
  var outer:Dictionary=JSON.parse_string(JSON.parse_string(save.text).payload)
  var canonical:Dictionary=JSON.parse_string(outer.world.payload).world.extensions[Ecology.KEY]
  check("canonical crop/seed/due/receipts strict restored",Data.json_equal(decoded.capture.world.extensions[Ecology.KEY],canonical),{"raw_live_equal":Data.json_equal(decoded.capture.world.extensions[Ecology.KEY],world.extension(Ecology.KEY)),"comparison":"exact encoded payload, not epsilon or float truncation"})
  FileAccess.open(OS.get_cmdline_user_args()[0]+".native.json",FileAccess.WRITE).store_string(save.text)
 finish()
func finish()->void:
 var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"scope":"Explicit finite fixture; original Runtime commands and A clock. No natural economy, PCK/VA/FPS."},"\t",true,true))
 print("ECOLOGY_LABOR ",checks.size()," failed=",failed);runtime.retire();quit(0 if failed==0 else 1)
