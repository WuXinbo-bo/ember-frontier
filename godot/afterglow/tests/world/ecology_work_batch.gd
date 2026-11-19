extends SceneTree
## Real unchanged farm02 input; read-only zone probes are explicit fixtures.
## Only cold/warm uses original World CAS. No actor/inventory injection.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Ecology=preload("res://scripts/ecology/ecology_service.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
var runtime:RefCounted
class ModuleReads extends RefCounted:
 var target:RefCounted
 var reads:int=0
 func state()->Dictionary:
  reads+=1
  return target.state()
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
 checks.append({"label":label,"ok":ok,"detail":detail})
 if not ok:print("FAIL ",label," ",detail)
func warm(id:String,resident:bool)->bool:
 for _i:int in 12:
  var p:Dictionary=runtime.world.prepare_region_residency(id,resident,runtime.world.get_revision(),32)
  if not p.get("ok",false):return false
  if not p.world_changes.is_empty():
   var tx:Dictionary=runtime.world.prepare_changes(p.world_changes,runtime.world.get_revision())
   if not tx.get("ok",false) or not runtime.world.commit_prepared(tx.capability).get("ok",false):return false
  if p.complete:return runtime.world.region_is_resident(id)==resident
 return false
func run()->void:
 var args:=OS.get_cmdline_user_args();var text:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(text)
 check("original actual E failed farm input decodes",decoded.get("ok",false))
 if not checks[-1].ok:return finish()
 var node:=Native.new();var built:Dictionary=node._assemble(decoded.capture);node.free()
 check("full original Native legally assembles and warms",built.get("ok",false))
 if not checks[-1].ok:return finish()
 runtime=built.runtime
 var script:=GDScript.new();script.source_code=FileAccess.get_file_as_string(args[2])
 check("exact7be preimage compiles as independent old API oracle",script.reload()==OK and script.can_instantiate())
 if not checks[-1].ok:return finish()
 var before:RefCounted=script.new();var after:=Ecology.new();var old_reads:=ModuleReads.new();var new_reads:=ModuleReads.new()
 old_reads.target=built.services.modules;new_reads.target=built.services.modules
 var common:Dictionary=built.services.ecology.context.duplicate();common.runtime=runtime;common.services=built.services.duplicate();common.services.modules=old_reads;before.configure(common)
 common.services=built.services.duplicate();common.services.modules=new_reads;after.configure(common)
 var calls:Dictionary={"before":0,"after":0}
 before.context.region_is_detailed=func(id:String)->bool:calls.before+=1;return runtime.region_is_detailed(id)
 after.context.region_is_detailed=func(id:String)->bool:calls.after+=1;return runtime.region_is_detailed(id)
 var authority:Dictionary=runtime.capture_checkpoint();var actor:Dictionary=runtime.actor("village-resident")
 var original_job:Dictionary=built.services.zonework.state().jobs[str(actor.intent.work_id)].job
 var jobs:Array=[original_job.duplicate(true)]
 # This temporary query descriptor is not a persisted farm or free resource.
 var zone:Dictionary={"id":"C:readonly:workbatch","kind":"farm","region_id":"RH-HOME","enabled":true,"bounds":{"x0":64,"x1":80,"z0":80,"z1":96},"policy":{"crop_id":"potato"}}
 var preview:Dictionary=after.preview_zone(zone)
 check("real current ground provides a bounded nonempty query fixture",preview.get("ok",false) and preview.cells.size()>8,{"cells":preview.get("cells",[]).size()})
 if not checks[-1].ok:return finish()
 zone.cells=preview.cells
 for job:Dictionary in after.work_candidates(zone,str(actor.id)):
  if jobs.size()>=32:break
  job.work_id="C:readonly:batch:"+str(jobs.size());job.source_id="pack:"+str(actor.id);job.output_id=job.source_id;job.tool_ids=[];jobs.append(job)
 check("32 real candidate checks retain original canonical work identity",jobs.size()==32 and jobs[0].target_id==original_job.target_id)
 var old_tx:=Draft.new(before.context);var new_tx:=Draft.new(after.context);var expected:Array=[]
 calls.before=0;calls.after=0;old_reads.reads=0;new_reads.reads=0
 for job:Dictionary in jobs:expected.append(before.check_work(old_tx,job,str(actor.id)))
 var actual:Array=after.check_work_batch(new_tx,jobs,str(actor.id))
 check("batch exactly preserves all ordered old per-job result fields",Data.json_equal(expected,actual),{"jobs":jobs.size(),"codes":actual.map(func(r:Dictionary)->String:return str(r.code))})
 check("batch reuses one complete region and module read instead of64/32",calls.before==64 and calls.after==1 and old_reads.reads==32 and new_reads.reads==1,{"detail":calls.duplicate(),"old_module_reads":old_reads.reads,"new_module_reads":new_reads.reads})
 check("same Draft observational effects are exactly preserved",Data.json_equal(old_tx.result(),new_tx.result()))
 check("original .5 feet and ground0 remain separate in batch",actual[0].location.y==.5 and actual[0].target.y==0)
 var old_info:Dictionary=before.check_work(Draft.new(before.context),jobs[0],str(actor.id));var single:Dictionary=after.check_work(Draft.new(after.context),jobs[0],str(actor.id))
 check("old public single-job signature and exact values remain compatible",Data.json_equal(old_info,single))
 actual[0].location.y=99
 check("mutating returned info cannot poison later batch or authority",after.check_work_batch(Draft.new(after.context),[jobs[0]],str(actor.id))[0].location.y==.5 and Data.json_equal(authority,runtime.capture_checkpoint()))
 var variants:Array=[]
 var changed:Dictionary=jobs[0].duplicate(true);changed.target.y=.5;variants.append(changed)
 changed=jobs[0].duplicate(true);changed.cell.y=.25;variants.append(changed)
 changed=jobs[0].duplicate(true);changed.revision=999;variants.append(changed)
 var refused:Array=after.check_work_batch(Draft.new(after.context),variants,str(actor.id));var old_refused:Array=[]
 for job:Dictionary in variants:old_refused.append(before.check_work(Draft.new(before.context),job,str(actor.id)))
 check("changed ground/fractional cell/stale revision stay ordered exact refusals",Data.json_equal(old_refused,refused) and refused.all(func(r:Dictionary)->bool:return not r.ok),refused)
 var nursery:Dictionary=jobs[1].duplicate(true);nursery.kind="nursery";nursery.tree_id="broadleaf"
 var old_missing:Dictionary=before.check_work(Draft.new(before.context),nursery,str(actor.id));var missing:Dictionary=after.check_work_batch(Draft.new(after.context),[nursery],str(actor.id))[0]
 check("same live tx missing real nursery cost preserves requirements",Data.json_equal(old_missing,missing) and not missing.ok and missing.has("requirements"),missing.get("code"))
 var removed:Dictionary=jobs[0].duplicate(true);removed.kind="till"
 check("empty batch is empty and cannot write a Draft",after.check_work_batch(Draft.new(after.context),[],str(actor.id)).is_empty())
 check("all no-commit queries preserve exact complete authority",Data.json_equal(authority,runtime.capture_checkpoint()))
 check("original cold32 CAS completes without page loss",warm("RH-HOME",false))
 var cold_before:Dictionary=before.check_work(Draft.new(before.context),jobs[0],str(actor.id));var cold_after:Dictionary=after.check_work_batch(Draft.new(after.context),[jobs[0]],str(actor.id))[0]
 check("next batch and old single cannot reuse warm proof after real cold commit",Data.json_equal(cold_before,cold_after) and cold_after.code=="REGION_NOT_DETAILED")
 check("original warm32 CAS completes without regeneration",warm("RH-HOME",true))
 check("next batch and old single recover exact canonical result after warm",Data.json_equal(before.check_work(Draft.new(before.context),jobs[0],str(actor.id)),after.check_work_batch(Draft.new(after.context),[jobs[0]],str(actor.id))[0]))
 check("malformed batch row rejects explicitly without collapsing order",after.check_work_batch(Draft.new(after.context),[null],str(actor.id))[0].code=="INVALID_ECOLOGY_JOB")
 check("actual original input bytes stay unchanged",FileAccess.get_file_as_string(args[1])==text)
 finish()
func finish()->void:
 var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"C batch versus exact7be old API. Original real E farm02 source, actual Space/ground/modules; temporary read-only32-job zone descriptor, not32 paid farms. Cold/warm original32-chunk CAS, no actor/stock injections. No FFF performance/OS/FPS or candidate26 qualification."},"\t",true,true))
 if runtime!=null:runtime.retire()
 print("ECOLOGY_WORK_BATCH ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
