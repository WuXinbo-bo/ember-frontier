extends SceneTree
## Explicit public-zone fixture into a marked QA directory; never user saves.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args();var qa:String=args[1]
 if not qa.is_absolute_path() or not FileAccess.file_exists(qa.path_join("afterglow-qa-root.json")):quit(2);return
 var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[0]))
 if not decoded.get("ok",false):quit(2);return
 var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
 if not built.get("ok",false):push_error(str(built));quit(1);return
 var rt:RefCounted=built.runtime
 var spec:Dictionary={"kind":"forestry","region_id":"RH-VILLAGE","bounds":{"x0":20,"z0":-96,"x1":39,"z1":-86},"policy":{"replant":true,"mature_only":true,"tree_id":"broadleaf"}}
 var receipt:Dictionary=rt.command({"kind":"zone.create","actor_id":"player","target_id":"PERF:forestry","command_id":"PERF:create","payload":{"spec":spec}})
 if not receipt.get("ok",false):push_error(str(receipt));quit(1);return
 var saved:Dictionary=Store.new(qa.path_join("saves"))._save_job(rt.capture_checkpoint(),true,"",true)
 var metadata:Dictionary={"source_sha256":FileAccess.get_sha256(args[0]),"public_command":receipt.get("ok"),"valid_cells":rt.zone_records()[0].cells.size(),"actors":rt.facts().actors.size(),"regions":built.world.regions().size(),"clock":rt.clock(),"simulation":rt.simulation_budget(),"saved":saved}
 FileAccess.open(qa.path_join("fixture.json"),FileAccess.WRITE).store_string(JSON.stringify(metadata,"\t"));rt.retire();quit(0 if saved.get("ok",false) else 1)
