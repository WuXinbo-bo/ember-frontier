extends "res://tests/gameplay/factory_n3_carrying.gd"
## Isolated failure probe from the preserved real pre-fix cargo checkpoint.
## Only the test adapter corrupts the guard request AFTER real B cargo pause.
## This is not a normal gameplay journey or a modification of B production.
class GuardFailureProbe extends RefCounted:
	var actual:RefCounted
	var calls:Array=[]
	var saw_paused_draft:bool=false
	var rejected:Dictionary={}
	func workforce_candidates(actor_id:String,facts:Dictionary={},overrides:Dictionary={})->Array:
		return actual.workforce_candidates(actor_id,facts,overrides)
	func safe_handoff(actor_id:String,candidate_id:String="",facts:Dictionary={},overrides:Dictionary={})->Dictionary:
		var result:Dictionary=actual.safe_handoff(actor_id,candidate_id,facts,overrides)
		calls.append({"actor_id":actor_id,"candidate_id":candidate_id,"ok":result.get("ok"),"code":result.get("code")})
		return result
	func prepare_workforce(request:Dictionary,facts:Dictionary={},overrides:Dictionary={})->Dictionary:
		return actual.prepare_workforce(request,facts,overrides)
	func prepare_guard(request:Dictionary,facts:Dictionary={},overrides:Dictionary={})->Dictionary:
		var a:Dictionary=preload("res://scripts/actions/domain_draft.gd").find(facts.actors,str(request.actor_id))
		for task:Dictionary in overrides.get("r34:logistics",{}).get("tasks",[]):
			if task.actor_id==request.actor_id and task.phase=="deliver":
				saw_paused_draft=task.status=="cargo_held" and task.reason=="safe_handoff" and a.pack.get("timber")==1 and a.get("intent")==null and a.pending_delivery.task_id==task.id
		var invalid:Dictionary=request.duplicate(true)
		invalid.site_id="fixture:missing-guard-site"
		rejected=actual.prepare_guard(invalid,facts,overrides)
		return rejected

func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"prerequisite":{"path":source_path,"sha256":source_sha},"scope":"Isolated guard-failure fixture using preserved real cargo checkpoint. Detached next-due scheduling input only; actual B handoff, test-injected missing guard site request, actual B rejection, E discard and A feedback-only commit. Not a normal gameplay journey or PCK/OS/VA/performance qualification."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("preserved real pre-fix cargo interruption decodes",decoded.ok)
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("actual native restores complete cargo checkpoint canonically",built.get("ok",false) and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var service:RefCounted=built.services.workforce
	var before:Dictionary=runtime.capture_checkpoint();var actor_before:Dictionary=runtime.actor("repair-resident")
	tracked_task=str(actor_before.get("pending_delivery",{}).get("task_id",""));tracked_actor="repair-resident"
	var task_before:Dictionary=find_task(runtime,tracked_task)
	check("real checkpoint has original delivering task and physical board during warning",task_before.get("phase")=="deliver" and task_before.get("status")=="delivering" and task_before.get("actor_id")==tracked_actor and actor_before.pack.get("timber")==1 and built.world.extension(Gameplay.KEY).defense.status=="warning",task_before)
	var adapter:=GuardFailureProbe.new();adapter.actual=built.services.actions
	var original:WeakRef=service._actions;service._actions=weakref(adapter)
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(service.context)
	# Exercise the next due decision in a detached draft. Runtime clock and all
	# original bodies, cargo, task, reservations and world remain untouched.
	service._advance_survival(tx,built.services.residents,0.1,runtime.clock()+2.0)
	service._actions=original
	check("real B first refuses guard switch then prepares empty safe pause",adapter.calls.size()==2 and adapter.calls[0].code=="CARGO_HANDOFF_REQUIRED" and adapter.calls[1].candidate_id=="" and adapter.calls[1].ok,adapter.calls)
	check("B guard receives the same paused original cargo draft",adapter.saw_paused_draft)
	check("actual B refuses injected nonexistent guard site",not adapter.rejected.get("ok",true) and adapter.rejected.get("code")=="INVALID_GUARD_DESTINATION",adapter.rejected)
	var plan:Dictionary=tx.result();var after_actor:Dictionary=tx.actor(tracked_actor)
	check("E discards successful pause when guard prepare fails",tx.extensions.get("r34:logistics",runtime.world.extension("r34:logistics"))==runtime.world.extension("r34:logistics") and after_actor.intent==actor_before.intent and after_actor.pending_delivery==actor_before.pending_delivery and after_actor.pack==actor_before.pack and tx.staged.stocks==runtime.facts().stocks and tx.events.is_empty(),plan)
	check("failure preparation never changes authority or clock",Data.json_equal(before,runtime.capture_checkpoint()))
	var committed:Dictionary=runtime._commit(plan)
	check("A commits only failed-decision feedback without partial handoff",committed.get("ok",false) and find_task(runtime,tracked_task)==task_before and runtime.actor(tracked_actor).intent==actor_before.intent and runtime.actor(tracked_actor).pending_delivery==actor_before.pending_delivery and runtime.actor(tracked_actor).pack==actor_before.pack and runtime.facts().stocks==before.facts.stocks and runtime.clock()==before.facts.time and runtime.actor(tracked_actor).self_routine.last_failure.code=="INVALID_GUARD_DESTINATION",committed)
	var restored:Dictionary=cold_restore(runtime,"failed-guard-no-partial-handoff")
	check("cold restore retains original still-delivering cargo after guard failure",restored.get("ok",false) and find_task(restored.runtime,tracked_task)==task_before and restored.runtime.actor(tracked_actor).intent==actor_before.intent)
	finish()
