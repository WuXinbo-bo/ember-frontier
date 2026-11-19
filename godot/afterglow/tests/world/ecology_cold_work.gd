extends "res://tests/world/ecology_labor.gd"
## Original actual labor save, original bounded residency API, actual water
## command and native consumer. No capture/plant/item/readiness alteration.
const FactoryServices=preload("res://scripts/runtime/factory_services.gd")
const EcologyView=preload("res://scripts/presentation/ecology_visual.gd")
func command(kind:String,target:String="",payload:Dictionary={})->Dictionary:
 sequence+=1
 var request:Dictionary={"command_id":"C:cold-work:"+str(sequence),"actor_id":"player","kind":kind,"target_id":target,"payload":payload}
 var result:Dictionary=runtime.command(request);commands.append({"request":request,"result":result});return result
func warm_region(id:String)->bool:
 for _n:int in 64:
  var prepared:Dictionary=world.prepare_region_residency(id,true,world.get_revision(),32)
  if not prepared.ok:return false
  if not prepared.world_changes.is_empty():
   var result:=commit(prepared.world_changes)
   if not result.ok:return false
  if prepared.complete:return world.region_is_resident(id)
 return false
func mount(capture:Dictionary)->bool:
 if not world.load_snapshot(capture.world).ok:return false
 var attached:=FactoryServices.attach({"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()},capture)
 if not attached.ok:return false
 services=attached.services
 var context:Dictionary=capture.duplicate(true);context.world=world;context.services=services
 return runtime.configure(context).ok
func run()->void:
 var args:=OS.get_cmdline_user_args();var raw:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(raw)
 check("original actual Native save decodes untouched",decoded.ok,decoded.get("code"))
 if not decoded.ok:return finish()
 check("full Runtime mounts unconverted actual JSON",mount(decoded.capture))
 if checks[-1].ok!=true:return finish()
 var id:String=world.extension(Ecology.KEY).plants.keys()[0];var plant:Dictionary=world.extension(Ecology.KEY).plants[id]
 check("codec cold state is not permission to simulate or render",not world.region_is_resident("RH-HOME") and not services.ecology.presentation_basis().detailed and services.ecology.presentation_projection().visuals.is_empty() and services.zonework.work_candidates("player").is_empty())
 check("bounded original 32-chunk warm completes, preserves original crop",warm_region("RH-HOME") and Data.json_equal(world.extension(Ecology.KEY).plants[id],plant))
 var visual:=EcologyView.new();root.add_child(visual);visual.set_process(false);visual.configure(runtime);visual.sync()
 check("warm native view shows actual same seedling DTO",services.ecology.presentation_basis().detailed and visual.statistics().visuals.size()==1 and visual.statistics().visuals[0].id==id and visual.statistics().instances>0,visual.statistics())
 var before_raw:float=runtime.actor("player").pack["r34:raw_water"]
 if not labor("water",160):visual.free();return finish()
 visual.sync()
 check("legitimately warm actual water transfers once and view follows",runtime.actor("player").pack["r34:raw_water"]==before_raw-1 and world.extension(Ecology.KEY).plants[id].moisture==1 and visual.statistics().visuals.size()==1 and visual.statistics().visuals[0].revision>plant.revision,visual.statistics())
 var encoded:=Store.encode(runtime.capture_checkpoint());var again:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 check("actual continued labor stores/decodes",again.ok,again.get("code"))
 if not again.ok:visual.free();return finish()
 FileAccess.open(args[0]+".native.json",FileAccess.WRITE).store_string(encoded.text)
 var current:Dictionary=world.extension(Ecology.KEY).plants[id];runtime.retire();runtime=Runtime.new();world=World.new()
 check("second full cold mounts unchanged saved labor",mount(again.capture))
 visual.configure(runtime);visual.sync()
 check("second cold view/work stays gated until real readiness",visual.statistics().visuals.is_empty() and services.zonework.work_candidates("player").is_empty())
 check("second bounded warm preserves actual material and plant",warm_region("RH-HOME") and runtime.actor("player").pack["r34:raw_water"]==before_raw-1 and Data.json_equal(world.extension(Ecology.KEY).plants[id],current))
 visual.sync()
 check("second warm native geometry is nonempty and exact persisted plant",visual.statistics().instances>0 and visual.statistics().visuals.size()==1 and visual.statistics().visuals[0].revision==current.revision,visual.statistics())
 check("original immutable input bytes remain exact",FileAccess.get_file_as_string(args[1])==raw)
 visual.free();finish()
