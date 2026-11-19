extends SceneTree
## External script, with production preloads resolved from the fixed PCK only.
const Store=preload("res://scripts/storage/native_store.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	for path:String in Array(args).slice(1):
		var before:PackedByteArray=FileAccess.get_file_as_bytes(path)
		var decoded:Dictionary=Store.decode(before.get_string_from_utf8())
		var native:=Native.new()
		var result:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded
		var model:String=decoded.capture.world.extensions["generation:rural2"].landscape_model if decoded.ok else ""
		var row:Dictionary={"label":"fixed PCK decodes and offscreen-safely assembles "+path.get_file(),"ok":result.ok,"detail":{"code":result.get("code"),"reason":result.get("reason"),"model":model,"source_revision":decoded.capture.world.revision if decoded.ok else null,"assembled_revision":result.world.get_revision() if result.ok else null}}
		checks.append(row)
		checks.append({"label":"original capture bytes unchanged "+path.get_file(),"ok":before==FileAccess.get_file_as_bytes(path)})
		native.free()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Actual fixed candidate11 PCK decode/Native offscreen safety only; no new v5 generator in this PCK, no scene/frames/OS or default adoption."},"\t",true,true)+"\n")
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
