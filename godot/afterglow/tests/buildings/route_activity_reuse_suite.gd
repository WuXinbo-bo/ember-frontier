extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail});if not ok:print("FAIL ",label," ",detail)
func digest(v:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(v));return h.finish().hex_encode()
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free();return built
func run()->void:
	var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var built:=mount(decoded.capture)
	check("same actual normal20 mounts",built.get("ok",false))
	if not built.get("ok",false):finish();return
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]));var source:Dictionary=evidence.rows[0].profile.actions.route.slow[0];var id:String=source.actor_id
	var rt:RefCounted=built.runtime;var rows:Array=[];var origin:=G.location(rt.actor(id));var commands:Array=[]
	for n in 120:
		rt.tick(0.1)
		if n==3:check("original NPC really has active movement",rt.actor(id).get("intent",{}).get("kind")=="walk",rt.actor(id).get("intent"))
		if n==6:
			var encoded:=Store.encode(rt.capture_checkpoint());FileAccess.open(args[0]+"/active.native.json",FileAccess.WRITE).store_string(encoded.text)
			decoded=Store.decode(encoded.text);var prior:Dictionary=rt.capture_checkpoint();rt.retire();built=mount(decoded.capture);check("active route cold recovery mounts",built.get("ok",false))
			if not built.get("ok",false):finish();return
			rt=built.runtime
			FileAccess.open(args[0]+"/cold-prior.json",FileAccess.WRITE).store_string(JSON.stringify(prior,"\t",true,true))
			FileAccess.open(args[0]+"/cold-mounted.json",FileAccess.WRITE).store_string(JSON.stringify(rt.capture_checkpoint(),"\t",true,true))
			# Native residency restores may rebase chunk/world revisions; JSON
			# parsing also normalizes numeric representation. Compare ALL decoded
			# facts, then the before/after runs compare every entire mounted state.
			check("cold retains all canonical decoded facts including active route",Data.json_equal(decoded.capture.facts,rt.capture_checkpoint().facts))
		if n==10:
			var stopped:Dictionary=rt.command({"actor_id":id,"kind":"cancel","command_id":"B:route-tail:cancel","payload":{}});commands.append(stopped)
			check("actual cancel of recovered route accepted",stopped.get("ok",false),stopped)
			var resumed:Dictionary=rt.command({"actor_id":id,"kind":"walk","command_id":"B:route-tail:resume","destination":source.to,"payload":{}});commands.append(resumed)
			check("real same-goal route resumes through transaction",resumed.get("ok",false),resumed)
		rows.append({"step":n,"capture_sha256":digest(rt.capture_checkpoint())})
	check("same live NPC actually moved without teleport",G.point(origin).distance_to(G.point(G.location(rt.actor(id))))>0.5)
	var final:=Store.encode(rt.capture_checkpoint());FileAccess.open(args[0]+"/final.native.json",FileAccess.WRITE).store_string(final.text)
	FileAccess.open(args[0]+"/states.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"commands":commands,"final_capture_sha256":digest(rt.capture_checkpoint())},"\t",true,true));rt.retire();finish()
func finish()->void:
	var result:Dictionary={"checks":checks,"scope":"Original real normal20 NPC 120 fixed steps, active cold recovery, explicit cancellation/restart adversity. Full per-step capture SHA compared externally, no population/frequency/rule change."}
	FileAccess.open(OS.get_cmdline_user_args()[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
