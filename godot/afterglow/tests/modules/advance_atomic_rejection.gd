extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var held:Array=[]
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func digest(value:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(value));return h.finish().hex_encode()
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail});if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();var loaded:=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new();var built:Dictionary=native._assemble(loaded.capture) if loaded.get("ok",false) else loaded;native.free()
	check("unchanged finite normal20 restores",built.get("ok",false))
	if not built.get("ok",false):finish();return
	var rt:RefCounted=built.runtime;var services:Dictionary=built.services;var before:Dictionary=rt.capture_checkpoint()
	var request:Dictionary={"actor_id":"player","kind":"walk","command_id":"B:advance:stale-walk","destination":G.location(rt.actor("player")),"payload":{}}
	var prepared:Dictionary=services.actions.prepare(request);var plan_sha:String=digest(prepared)
	check("real grounded walk prepares complete fact CAS",prepared.get("ok",false) and not prepared.get("fact_changes",[]).is_empty())
	check("preparation leaves complete authority untouched",digest(before)==digest(rt.capture_checkpoint()))
	var competing:Dictionary=rt.command({"actor_id":"player","kind":"rest","command_id":"B:advance:competing-rest","payload":{}})
	check("actual competing life command succeeds",competing.get("ok",false),competing.get("code"))
	var current:Dictionary=rt.capture_checkpoint();var rejected:Dictionary=rt._commit(prepared)
	check("old action CAS rejected after competing actor change",not rejected.get("ok",false),rejected.get("code"))
	check("failed CAS leaves all facts world receipts clock unchanged",digest(current)==digest(rt.capture_checkpoint()))
	check("failed commit does not mutate prepared plan",plan_sha==digest(prepared))
	var cancelled:Dictionary=rt.command({"actor_id":"player","kind":"cancel","command_id":"B:advance:cancel-rest","payload":{}})
	check("ordinary cancel still accepted",cancelled.get("ok",false))
	var resumed:Dictionary=services.actions.prepare(request)
	check("fresh same action plan still prepares and commits",resumed.get("ok",false) and rt._commit(resumed).get("ok",false))
	var canonical:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(canonical.text);var cold_host:=Native.new();var restored:Dictionary=cold_host._assemble(decoded.capture);cold_host.free()
	check("actual active walk cold restores",restored.get("ok",false))
	var output:Dictionary={"prepared":prepared,"stale_rejection":rejected,"fresh":resumed,"final":digest(rt.capture_checkpoint()),"cold":digest(restored.runtime.capture_checkpoint()) if restored.get("ok",false) else ""}
	FileAccess.open(args[0]+"/atomic-state.json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t",true,true))
	if restored.get("ok",false):restored.runtime.retire()
	rt.retire();finish()
func finish()->void:
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"scope":"Unedited normal20 real commands and deliberate stale-plan submission; CAS adversity is explicit, not natural combat"}
	FileAccess.open(OS.get_cmdline_user_args()[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));quit(0 if report.failed==0 else 1)
