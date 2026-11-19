extends SceneTree
## Real Native world equivalence plus explicitly isolated module-read observer.
## The observer's changed snapshots are not world edits or paid construction.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Ecology=preload("res://scripts/ecology/ecology_service.gd")
var checks:Array=[]
var runtime:RefCounted
class ModuleReads extends RefCounted:
 var target:RefCounted
 var reads:int=0
 var fixture:Variant=null
 func state()->Dictionary:
  reads+=1
  return target.state() if fixture==null else fixture.duplicate(true)
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
 checks.append({"label":label,"ok":ok,"detail":detail})
 if not ok:print("FAIL ",label," ",detail)
func warm(world:RefCounted,id:String,resident:bool)->bool:
 for _i:int in 64:
  var prepared:Dictionary=world.prepare_region_residency(id,resident,world.get_revision(),32)
  if not prepared.ok:return false
  if not prepared.world_changes.is_empty():
   var plan:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision())
   if not plan.ok or not world.commit_prepared(plan.capability).ok:return false
  if prepared.complete:return world.region_is_resident(id)==resident
 return false
func run()->void:
 var args:=OS.get_cmdline_user_args();var input:String=FileAccess.get_file_as_string(args[1])
 var decoded:Dictionary=Store.decode(input)
 check("untouched original new12 Native input decodes",decoded.get("ok",false))
 if not decoded.get("ok",false):return finish()
 var node:=Native.new();var built:Dictionary=node._assemble(decoded.capture);node.free()
 check("original Native assembly has real modules and ecology",built.get("ok",false) and built.get("services",{}).has_all(["ecology","modules"]))
 if not checks[-1].ok:return finish()
 runtime=built.runtime
 var original:=GDScript.new();original.source_code=FileAccess.get_file_as_string(args[2])
 check("exact old source compiles as equivalence oracle",original.reload()==OK and original.can_instantiate())
 if not checks[-1].ok:return finish()
 var before:RefCounted=original.new();var after:=Ecology.new()
 var old_reads:=ModuleReads.new();old_reads.target=built.services.modules
 var new_reads:=ModuleReads.new();new_reads.target=built.services.modules
 var common:Dictionary=built.services.ecology.context.duplicate();common.runtime=runtime
 common.services=built.services.duplicate();common.services.modules=old_reads;before.configure(common)
 common.services=built.services.duplicate();common.services.modules=new_reads;after.configure(common)
 var detail_counts:Dictionary={"before":0,"after":0}
 before.context.region_is_detailed=func(id:String)->bool:detail_counts.before+=1;return runtime.region_is_detailed(id)
 after.context.region_is_detailed=func(id:String)->bool:detail_counts.after+=1;return runtime.region_is_detailed(id)
 var authority:Dictionary=runtime.capture_checkpoint();var player:Dictionary=runtime.actor("player");var region:String=player.regionId
 var x0:int=floori(float(player.x)*2)-12;var z0:int=floori(float(player.z)*2)-12
 var batch:Dictionary={};var same:bool=true;var reasons:Dictionary={};var compared:int=0
 for kind:String in ["farm","rice","forestry","stockpile","patrol","terrain"]:
  for dz:int in range(0,25,3):
   for dx:int in range(0,25,3):
    var policy:Dictionary={"crop_id":"rice" if kind=="rice" else "potato"}
    var actual_kind:String="farm" if kind=="rice" else kind
    var a:Dictionary=before._ground(region,x0+dx,z0+dz,actual_kind,policy)
    var b:Dictionary=after._ground(region,x0+dx,z0+dz,actual_kind,policy,"",batch)
    same=same and Data.json_equal(a,b);compared+=1
    var reason:String=str(a.get("code","OK"));reasons[reason]=int(reasons.get(reason,0))+1
 check("486 real ground queries exactly match all old decisions and DTOs",same and compared==486,{"compared":compared,"reasons":reasons})
 check("real module state detached once per synchronous ground batch",new_reads.reads==1 and old_reads.reads>1,{"before_reads":old_reads.reads,"after_reads":new_reads.reads})
 check("full real readiness predicate reused only inside this batch",detail_counts.before==486 and detail_counts.after==1,detail_counts.duplicate())
 var instances:Array=built.services.modules.state().instances;var ports:Array=[]
 for instance:Dictionary in instances:
  if instance.region!=region:continue
  for port:Dictionary in Shape.ports(instance,Catalog.definition(instance.definition_id)):ports.append(port.location)
 check("real five-module source supplies actual same-region service ports",instances.size()==5 and not ports.is_empty(),{"instances":instances.size(),"ports":ports.size()})
 var port_batch:Dictionary={};var ports_same:bool=true;var port_checks:int=0
 for at:Dictionary in ports:
  for offset:Vector3 in [Vector3.ZERO,Vector3(1.299999,0,0),Vector3(1.3,0,0),Vector3(1.300001,0,0),Vector3(0,1.3,0),Vector3(0,0,-1.3),Vector3(32,0,0),Vector3(32.000001,0,0)]:
   var point:Dictionary=at.merged(G.json_point(G.point(at)+offset),true)
   ports_same=ports_same and before._service_exit_protected(region,point)==after._service_exit_protected(region,point,port_batch);port_checks+=1
   ports_same=ports_same and before._service_exit_protected("not-this-region",point)==after._service_exit_protected("not-this-region",point,port_batch);port_checks+=1
 check("actual rotated ports retain strict1.3m,32m and region boundaries",ports_same,{"comparisons":port_checks})
 var anchor:Dictionary=ports[0]
 check("original private API still checks real service port",after._service_exit_protected(region,anchor))
 # Deliberately isolated module-state changes only: move/remove/add/redefine,
 # while original world/facts remain byte-value identical. Fresh calls MUST
 # read again; there is no persistent token/cache to stale across a commit.
 for mode:String in ["moved","removed","restored","rotated"]:
  var changed:Dictionary=built.services.modules.state()
  if mode=="moved":
   for instance:Dictionary in changed.instances:instance.position.x+=1000.0
  elif mode=="removed":changed.instances=[]
  elif mode=="rotated":
   for instance:Dictionary in changed.instances:instance.quarter_turn=(int(instance.quarter_turn)+1)%4
  old_reads.fixture=changed;new_reads.fixture=changed
  var fresh_same:bool=true
  for at:Dictionary in ports:fresh_same=fresh_same and before._service_exit_protected(region,at)==after._service_exit_protected(region,at)
  check("fresh old-signature calls observe isolated "+mode+" module snapshot",fresh_same)
 old_reads.fixture=null;new_reads.fixture=null
 check("all probes and isolated observer changes left authority unchanged",Data.json_equal(runtime.capture_checkpoint(),authority))
 var first:Dictionary=after._ground(region,x0+12,z0+12,"farm",{"crop_id":"rice"})
 check("original legal32 cold commits complete",warm(runtime.world,region,false))
 var cold_old:Dictionary=before._ground(region,x0+12,z0+12,"farm",{"crop_id":"rice"})
 var cold_new:Dictionary=after._ground(region,x0+12,z0+12,"farm",{"crop_id":"rice"})
 check("cold original private API rejects identically without stale batch",Data.json_equal(cold_old,cold_new) and cold_new.get("code")=="REGION_NOT_DETAILED",cold_new)
 check("original legal32 warm commits complete",warm(runtime.world,region,true))
 check("warm fresh query equals original and pre-cold result",Data.json_equal(after._ground(region,x0+12,z0+12,"farm",{"crop_id":"rice"}),first) and Data.json_equal(before._ground(region,x0+12,z0+12,"farm",{"crop_id":"rice"}),first))
 check("cold warm preserves original module state and all actor/stock facts",Data.json_equal(runtime.facts(),authority.facts) and Data.json_equal(built.services.modules.state(),authority.world.extensions[preload("res://scripts/modules/module_service.gd").KEY]))
 check("original immutable input bytes unchanged",FileAccess.get_file_as_string(args[1])==input)
 finish()
func finish()->void:
 var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Real original Native new12 read-only ground equivalence and legal cold/warm; isolated module-state observer changes explicitly not paid game construction. No renderer/PCK/OS/FPS."},"\t",true,true))
 if runtime!=null:runtime.retire()
 print("ECOLOGY_GROUND_BATCH ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
