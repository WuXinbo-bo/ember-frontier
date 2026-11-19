extends SceneTree
## Real B local door preview through A's input consumer; arranged actor/use-point
## fixtures only. No formal app, live saves, OS input or performance acceptance.
const Client=preload("res://scripts/runtime/native_client.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Direct=preload("res://scripts/input/direct_interaction.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
class ReadProbe extends RefCounted:
	var authority:RefCounted
	var calls:int=0
	func stock(id:String)->Dictionary:return authority.stock(id)
	func availability(request:Dictionary)->Dictionary:
		calls+=1
		return authority.availability(request)
class CommandRouter extends Node:
	var authority:RefCounted
	var calls:int=0
	var mode:String="tool"
	func state()->Dictionary:return {"mode":mode}
	func request(kind:String,id:String="",payload:Dictionary={})->Dictionary:
		calls+=1
		return authority.command({"command_id":"input-door:"+str(calls),"actor_id":"player","kind":kind,"target_id":id,"payload":payload})
class FrozenPointer extends Direct:
	func _refresh()->void:pass
class Feedback extends Control:
	var receipts:Array=[]
	func report_action(value:Dictionary)->void:receipts.append(value.duplicate(true))
	func notify(_message:String,_bad:bool=false)->void:pass
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("actual finite rural authority prepares",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish();return
	var client:=Client.new()
	var built:Dictionary=client._assemble(prepared.capture)
	check("formal offscreen assembler validates domains",built.ok,built.get("reason"))
	if not built.ok:client.free();finish();return
	var r:RefCounted=built.runtime;var b:RefCounted=built.services.buildings
	var before:Dictionary=r.actor("player")
	var door:Dictionary={};var local:Dictionary={}
	# These are explicitly arranged legal use-point fixtures, not a claim that
	# an OS player walked the route or that an invalid position was repaired.
	for piece:Dictionary in b.structures().instances:
		if not piece.has("door") or piece.door.get("locked",false):continue
		for at:Dictionary in b.current_space().use_points(piece):
			var next:Dictionary=before.duplicate(true);next.merge(at,true);next.stamina=100.0;next.intent=null
			var placed:Dictionary=r._commit({"fact_changes":[{"collection":"actors","id":"player","before":r.actor("player"),"after":next}]})
			if not placed.ok:continue
			local=b.door_preview({"kind":"door","actor_id":"player","target_id":piece.id,"payload":{"direct":true}})
			if local.ok:door=piece;break
		if not door.is_empty():break
	check("arranged legal real door handle has local proof",not door.is_empty(),local)
	if door.is_empty():client.free();finish();return
	var reader:=ReadProbe.new();reader.authority=r
	var router:=CommandRouter.new();router.authority=r
	var ui:=Feedback.new();var input:=FrozenPointer.new()
	input.runtime=reader;input.world=built.world;input.buildings=b;input.router=router;input.ui=ui
	var capture:Dictionary=r.capture_checkpoint()
	var target:Dictionary={}
	for i:int in 4:target=input._describe(built.world.entity(str(door.id)))
	check("hover avoids authoritative availability and complete door prepare",reader.calls==0,reader.calls)
	check("local success is only an attempt, never confirmed",target.get("enabled",false) and target.get("proof_state")=="pending" and str(target.get("action","")).begins_with("尝试"),target)
	check("hover carries target version and world dependency",target.get("target_version")==door.version and target.get("world_revision")==built.world.get_revision(),target)
	check("hover does not change facts world receipts clock or resources",capture==r.capture_checkpoint())
	# Leave the previously eligible pointer deliberately stale. E must still
	# reach the real runtime, whose CURRENT stamina invalidates the request.
	var actor:Dictionary=r.actor("player");var exhausted:Dictionary=actor.duplicate(true);exhausted.stamina=0.0
	var changed:Dictionary=r._commit({"fact_changes":[{"collection":"actors","id":"player","before":actor,"after":exhausted}]})
	check("real transaction changes a current continuous condition",changed.ok,changed)
	var facts_before:Dictionary=r.facts();var world_before:Dictionary=built.world.snapshot()
	input.runtime=r;input._target=target.duplicate(true);input._interact()
	check("E still submits one current authoritative command",router.calls==1 and ui.receipts.size()==1,ui.receipts)
	check("stale eligible preview cannot authorize exhausted actor",ui.receipts.size()==1 and not ui.receipts[0].get("ok",true) and ui.receipts[0].get("code")=="EXHAUSTED",ui.receipts)
	check("rejected stale preview has no cost geometry or facts change",r.facts()==facts_before and built.world.snapshot()==world_before)
	var rejected:Dictionary=input._describe(built.world.entity(str(door.id)))
	check("new hover exposes concrete rejection and no pending success",not rejected.get("enabled",true) and rejected.get("proof_state")=="rejected" and rejected.get("code")=="EXHAUSTED",rejected)
	input.free();router.free();ui.free();client.free();finish()
func finish()->void:
	var report:Dictionary={"scope":"real A input/B door preview/runtime with explicitly arranged legal use-point and exhausted-state fixtures; not OS/PCK/performance acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var path:String=OS.get_cmdline_user_args()[0].path_join("results.json")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));quit(1 if report.failed else 0)
