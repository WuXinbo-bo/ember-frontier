extends SceneTree
## Resume the original real new12 blocked till, never a manufactured farm.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Ecology=preload("res://scripts/ecology/ecology_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var commands:Array=[]
var runtime:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
 checks.append({"label":label,"ok":ok,"detail":detail})
 if not ok:print("FAIL ",label," ",detail)
func assemble(capture:Dictionary)->Dictionary:
 var node:=Native.new();var result:Dictionary=node._assemble(capture);node.free();return result
func receipt(state:Dictionary,id:String)->Dictionary:
 for r:Dictionary in state.receipts:
  if r.id==id:return r
 return {}
func run()->void:
 var args:=OS.get_cmdline_user_args();var input:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(input)
 check("unmodified real E farm02 Native input decodes",decoded.get("ok",false))
 if not checks[-1].ok:return finish()
 var built:=assemble(decoded.capture)
 check("original Native full assembly accepts original blocked job",built.get("ok",false))
 if not checks[-1].ok:return finish()
 runtime=built.runtime
 var ecology:RefCounted=built.services.ecology;var work_service:RefCounted=built.services.zonework
 var actor:Dictionary=runtime.actor("village-resident");var work:Dictionary=work_service.state().jobs[str(actor.intent.work_id)];var job:Dictionary=work.job
 var authority:Dictionary=runtime.capture_checkpoint();var q:RefCounted=ecology.context.spatial.current_space();var target:Dictionary=job.target
 check("actual failed identity and progress preserved",work.status=="blocked" and work.elapsed==0 and actor.y==.5 and job.location.y==0 and target.y==0, {"work_id":work.id,"location":work.location,"job_location":job.location,"target":target,"elapsed":work.elapsed})
 var ground:Dictionary=ecology._ground(str(job.region_id),int(job.cell.x),int(job.cell.z),"farm",{"crop_id":job.crop_id})
 var feet:Dictionary=q.standing_point(job.location)
 check("real terrain target0 differs from supported whole-body feet.5",ground.get("ok",false) and ground.location.y==0 and feet.get("y")==.5 and Data.json_equal(feet,G.location(actor)),{"ground":ground,"feet":feet})
 check("original contact line from actual actor to ground remains clear",q.contact_clear(G.location(actor),target,str(job.target_id)))
 var info:Dictionary=ecology.check_work(Draft.new(ecology.context),job,str(actor.id))
 check("old persisted job is rechecked with canonical feet and unchanged target",info.get("ok",false) and Data.json_equal(info.location,feet) and Data.json_equal(info.target,target) and Data.json_equal(info.requirements.location,feet),info)
 var zone:Dictionary={}
 for z:Dictionary in runtime.world.extension("r34:zones").zones:
  if z.id==job.zone_id:zone=z
 var candidate:Dictionary={}
 for row:Dictionary in ecology.work_candidates(zone,str(actor.id)):
  if row.id==job.id:candidate=row
 check("fresh candidate keeps stable cell/id with distinct feet and target",not candidate.is_empty() and Data.json_equal(candidate.location,feet) and Data.json_equal(candidate.target,target) and Data.json_equal(candidate.cell,job.cell),candidate)
 var completion_tx:=Draft.new(ecology.context)
 var completion_result:Dictionary=ecology.complete_work(completion_tx,job,str(actor.id))
 check("old job can plan completion only at actual supported feet",completion_result.get("ok",false),completion_result.get("code"))
 var plan:Dictionary=completion_tx.result() if completion_result.get("ok",false) else completion_result
 var planned_bed:Dictionary={}
 for change:Dictionary in plan.get("world_changes",[]):
  if change.get("op")=="entity.put" and change.id==job.target_id:planned_bed=change.after
 check("planned bed stays on real ground0 rather than body feet.5",planned_bed.get("kind")=="ecology_bed" and planned_bed.position.y==0,planned_bed.get("position"))
 var wrong_ground:Dictionary=job.duplicate(true);wrong_ground.target.y=.5
 check("lifting original contact target to feet is still rejected",ecology.check_work(Draft.new(ecology.context),wrong_ground,str(actor.id)).get("code")=="ECOLOGY_GROUND_CHANGED")
 var fractional:Dictionary=job.duplicate(true);fractional.cell.y=.25
 check("fractional authoritative ground cell is still rejected",ecology.check_work(Draft.new(ecology.context),fractional,str(actor.id)).get("code")=="INVALID_ECOLOGY_CELL")
 for label:String in ["unsupported-ground-y","distant-feet"]:
  var tx:=Draft.new(ecology.context);var a:Dictionary=tx.actor(str(actor.id))
  if label=="unsupported-ground-y":a.y=0.0
  else:a.x+=1.0
  check("isolated Draft-only "+label+" cannot settle",ecology.complete_work(tx,job,str(actor.id)).get("code")=="ECOLOGY_OPERATOR_NOT_AT_SITE")
 check("all read-only and isolated refusal probes preserve actual authority",Data.json_equal(authority,runtime.capture_checkpoint()))
 var tool_id:String=job.tool_ids[0];var durability:float=runtime.tool(tool_id).durability
 var request:Dictionary={"command_id":"C:worksite:actual-farm02:resume:1","actor_id":actor.id,"kind":"zonework.resume","target_id":work.id,"payload":{"work_id":work.id}}
 var resumed:Dictionary=runtime.command(request);commands.append({"request":request,"result":resumed})
 check("original public resume accepts same blocked job without clearing intent",resumed.get("ok",false),resumed)
 if not checks[-1].ok:return finish()
 var active:Dictionary=work_service.state().jobs[work.id]
 check("B persists actual endpoint and keeps identity/elapsed/target",active.id==work.id and active.elapsed==work.elapsed and Data.json_equal(active.location,feet) and Data.json_equal(active.target,target) and runtime.actor(str(actor.id)).intent.work_id==work.id,active)
 var ticks:int=0
 for _i:int in 100:
  runtime.tick(.1);ticks+=1
  if not receipt(work_service.state(),str(work.id)).is_empty():break
 var done:Dictionary=receipt(work_service.state(),str(work.id));var plant:Dictionary=runtime.world.extension(Ecology.KEY).plants.get(job.target_id,{})
 check("actual original same work completes through real clock labor",done.get("status")=="completed" and float(done.get("elapsed",0))>=7.999999,{"receipt":done,"ticks":ticks})
 check("actual bed and extension agree at original ground cell0",runtime.world.entity(str(job.target_id)).get("kind")=="ecology_bed" and runtime.world.entity(str(job.target_id)).position.y==0 and Data.json_equal(plant.get("cell"),job.cell) and plant.get("stage")=="tilled",plant)
 check("original tool pays exactly once without geometry shortcut",absf(float(runtime.tool(tool_id).durability)-(durability-.5))<.000001,{"before":durability,"after":runtime.tool(tool_id).durability})
 if done.get("status")!="completed":return finish()
 var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var saved:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 check("actual continued till stores and cold-decodes with original identity",saved.get("ok",false),saved.get("code"))
 if not saved.get("ok",false):return finish()
 FileAccess.open(args[0]+".native.json",FileAccess.WRITE).store_string(encoded.text)
 var completed:Dictionary=done.duplicate(true);runtime.retire();built=assemble(saved.capture)
 check("second full Runtime legally warms saved actual completed till",built.get("ok",false))
 if not checks[-1].ok:return finish()
 runtime=built.runtime;work_service=built.services.zonework
 check("cold restore keeps original completed receipt/bed/feet and tool",Data.json_equal(receipt(work_service.state(),str(work.id)),completed) and runtime.world.entity(str(job.target_id)).position.y==0 and runtime.actor(str(actor.id)).y==.5 and absf(float(runtime.tool(tool_id).durability)-(durability-.5))<.000001)
 runtime.tick(.1)
 check("revisit cannot double-complete or re-charge same original job",work_service.state().receipts.filter(func(r:Dictionary)->bool:return r.id==work.id).size()==1 and absf(float(runtime.tool(tool_id).durability)-(durability-.5))<.000001)
 check("original natural failed save bytes remain unchanged",FileAccess.get_file_as_string(args[1])==input)
 finish()
func finish()->void:
 var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"scope":"Untouched original E natural farm02 Native input. Original public resume/clock/B labor/C same-Draft settlement and cold revisit. Malformed actor probes are isolated uncommitted Drafts, not actual teleports. No renderer/PCK/OS/FPS/full food-economy acceptance."},"\t",true,true))
 if runtime!=null:runtime.retire()
 print("ECOLOGY_WORKSITE ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
