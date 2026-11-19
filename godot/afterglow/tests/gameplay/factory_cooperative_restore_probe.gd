extends SceneTree
const Store=preload("res://scripts/storage/native_store.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Data=preload("res://scripts/world/world_data.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[0]))
	if not decoded.ok:print(decoded);quit(1);return
	var native:=Native.new();var result:Dictionary=native._assemble(decoded.capture);native.free()
	if not result.ok:print(result);quit(1);return
	var before:Dictionary=decoded.capture.facts
	var after:Dictionary=result.runtime.facts()
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"before":before,"after":after,"same":Data.json_equal(before,after)},"\t",true,true))
	print("RESTORE_PROBE same="+str(Data.json_equal(before,after)));quit()
