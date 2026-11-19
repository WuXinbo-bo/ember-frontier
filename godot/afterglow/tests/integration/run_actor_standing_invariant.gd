extends SceneTree
## Final authority and offscreen recovery counterexamples from the actual
## seed12 save, plus explicit provider-draft fixtures. Never reads live saves.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
class Fixture extends Client:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func edit(runtime:RefCounted,id:String,after:Dictionary)->Dictionary:
	var before:Dictionary=runtime.actor(id)
	return runtime._commit({"fact_changes":[{"collection":"actors","id":id,"before":null if before.is_empty() else before,"after":after}]})
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var host:=Fixture.new();host.controls_path=output+"/controls.json";host.store=Store.new(output+"/saves");root.add_child(host)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Buildings.generation_profiles()))
	check("ordinary generated seed713 capture is valid",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(host);return
	var start:int=Time.get_ticks_usec()
	var built:Dictionary=host._assemble(prepared.capture)
	check("full offscreen safety accepts ordinary seed713 without moving actors",built.ok,built.get("reason"))
	checks[-1].assembly_usec=Time.get_ticks_usec()-start
	if not built.ok:finish(host);return
	var r:RefCounted=built.runtime
	var before:Dictionary=r.capture_checkpoint();var p:Dictionary=r.actor("player")
	var invalid:Dictionary=p.duplicate(true);invalid.y+=2.0
	var result:Dictionary=edit(r,"player",invalid)
	check("fact-only provider cannot publish unsupported player pose",not result.ok and result.get("code")=="SPATIAL_REJECTED",result.get("code"))
	check("rejected pose preserves world facts time receipts and movement budget",r.capture_checkpoint()==before)
	var ordinary:Dictionary=p.duplicate(true);ordinary.id="fixture:standing";ordinary.pack={};ordinary.intent=null
	invalid=ordinary.duplicate(true);invalid.y+=2.0
	result=edit(r,str(invalid.id),invalid)
	check("new living ordinary actor needs real full-body support",not result.ok and result.get("code")=="SPATIAL_REJECTED" and r.actor(str(invalid.id)).is_empty(),result.get("code"))
	result=edit(r,str(ordinary.id),ordinary)
	check("new supported actor uses same non-special-ID entry",result.ok,result.get("reason"))
	var dead:Dictionary=r.actor(str(ordinary.id));dead.hp=0;dead.y+=2.0
	result=edit(r,str(dead.id),dead)
	check("nonliving diagnostic actor is not silently relocated",result.ok and r.actor(str(dead.id)).y==dead.y,result.get("reason"))
	before=r.capture_checkpoint()
	var revived:Dictionary=dead.duplicate(true);revived.hp=50.0
	result=edit(r,str(revived.id),revived)
	check("revival cannot make unsupported body live",not result.ok and result.get("code")=="SPATIAL_REJECTED" and r.capture_checkpoint()==before,result.get("code"))
	var metadata:Dictionary=r.actor("player");metadata.activity="unchanged standing metadata"
	check("unchanged supported actor metadata remains legal",edit(r,"player",metadata).ok)
	var valid:Dictionary=r.capture_checkpoint()
	var encoded:Dictionary=Store.encode(valid)
	check("ordinary world with explicitly nonliving actor remains saveable",encoded.ok,encoded.get("reason"))
	if args.size()>1:
		var input:String=args[1];var raw:String=FileAccess.get_file_as_string(input)
		var decoded:Dictionary=Store.decode(raw)
		check("preserved actual invalid-pose save still decodes without rewriting it",decoded.ok,decoded.get("reason"))
		if decoded.ok:
			start=Time.get_ticks_usec();var rejected:Dictionary=host._assemble(decoded.capture)
			check("actual seed12 invalid-pose candidate cannot assemble",not rejected.ok and rejected.get("code")=="SPATIAL_REJECTED",rejected.get("code"))
			checks[-1].assembly_usec=Time.get_ticks_usec()-start
			check("actual saved bytes stay exact after rejected assembly",FileAccess.get_file_as_string(input)==raw)
			# A retained, isolated live world must survive the same rejection.
			check("isolated valid world mounts before failed restore",host._mount(prepared.capture).ok)
			var saved:Dictionary=await host.save_async("standing:valid")
			check("isolated valid namespace saved",saved.ok,saved.get("reason"))
			var pointer_path:String=output+"/saves/active.json"
			var pointer:PackedByteArray=FileAccess.get_file_as_bytes(pointer_path)
			var old:RefCounted=host.runtime;var scene:Node3D=host.scene_root
			var failed:Dictionary=await host.import_checkpoint(raw,"standing:invalid-import")
			check("bad standing import retains visible authority and active bytes",not failed.ok and failed.get("code")=="SPATIAL_REJECTED" and host.runtime==old and host.scene_root==scene and FileAccess.get_file_as_bytes(pointer_path)==pointer,failed.get("code"))
			check("bad import releases locks and never mutates original file",not host._saving and not host._world_loading and FileAccess.get_file_as_string(input)==raw)
			# Real stored bytes are valid to the codec but invalid to current
			# standing rules. Exercise the exact startup restore helper in an
			# isolated store, not the user's active namespace or a fake receipt.
			var startup:=Fixture.new();startup.controls_path=output+"/startup-controls.json";startup.store=Store.new(output+"/startup-saves");root.add_child(startup)
			var staged:Dictionary=startup.store.begin_save(decoded.capture,true,raw)
			check("isolated original bad-pose bytes can be retained as a legacy slot",staged.ok,staged.get("reason"))
			if staged.ok:
				var written:Dictionary={}
				while written.is_empty():await process_frame;written=startup.store.poll()
				var active_path:String=output+"/startup-saves/active.json"
				var active:PackedByteArray=FileAccess.get_file_as_bytes(active_path)
				var alternative:Dictionary=startup.store.begin_save(prepared.capture,true,"",false)
				var other:Dictionary={}
				if alternative.ok:
					while other.is_empty():await process_frame;other=startup.store.poll()
				check("valid other-world candidate exists without changing bad active pointer",alternative.ok and other.get("ok",false) and not other.get("activated",true) and FileAccess.get_file_as_bytes(active_path)==active)
				var loaded:Dictionary=startup.store.load_current()
				check("startup reads actual byte-valid saved candidate before domain checks",written.ok and loaded.ok,written.get("code"))
				if loaded.ok:
					var denied:Dictionary=await startup._startup_restore(loaded)
					check("invalid standing startup returns true domain failure with explicit recovery choices",not denied.ok and denied.get("code")=="SPATIAL_REJECTED" and not denied.get("candidates",[]).is_empty(),denied.get("code"))
					check("failed startup leaves no playable authority and mounts recovery UI",startup.runtime==null and startup.world==null and startup.scene_root==null and not startup._ready_game and is_instance_valid(startup._startup_recovery))
					check("startup failure releases busy locks and preserves active and original bytes",not startup._saving and not startup._world_loading and not startup._save_state.busy and FileAccess.get_file_as_bytes(active_path)==active and FileAccess.get_file_as_string(input)==raw)
					var candidate:Dictionary={};var valid_candidate:Dictionary={}
					for row:Dictionary in denied.candidates:
						if row.world_id=="rural:v3:12":candidate=row
						elif row.world_id=="rural:v3:713":valid_candidate=row
					check("startup scan lists both worlds but selects neither automatically",not candidate.is_empty() and not valid_candidate.is_empty() and startup.runtime==null and FileAccess.get_file_as_bytes(active_path)==active)
					var selected:Dictionary=await startup._startup_choose_recovery(candidate.candidate_id,candidate.sha256)
					check("explicit reselect cannot bypass standing safety or remove the recovery exit",not selected.ok and selected.code=="SPATIAL_REJECTED" and is_instance_valid(startup._startup_recovery) and FileAccess.get_file_as_bytes(active_path)==active,selected.get("code"))
					var layer:Node=startup._startup_recovery.get_parent()
					selected=await startup._startup_choose_recovery(valid_candidate.candidate_id,valid_candidate.sha256)
					check("explicit valid alternative becomes active only after actual readiness",selected.ok and selected.get("activated",false) and startup._ready_game and startup.world.identity().worldId=="rural:v3:713" and FileAccess.get_file_as_bytes(active_path)!=active,selected.get("code"))
					await process_frame
					check("successful explicit recovery removes entire startup overlay and preserves input bytes",startup._startup_recovery==null and not is_instance_valid(layer) and FileAccess.get_file_as_string(input)==raw)
			startup.free()
	finish(host)
func finish(host:Node)->void:
	var report:Dictionary={"scope":"source/headless final fact-only body guard, actual read-only invalid seed12 save and isolated failed import; provider-draft insertion fixtures explicit; not OS or performance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close();host.free();print(JSON.stringify(report));quit(1 if report.failed else 0)
