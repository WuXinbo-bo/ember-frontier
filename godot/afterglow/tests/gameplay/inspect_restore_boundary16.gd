extends SceneTree
const Store=preload("res://scripts/storage/native_store.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	if not built.get("ok",false):print(JSON.stringify(built));return quit(1)
	var runtime:RefCounted=built.runtime
	var home:Dictionary=runtime._services.modules.instance("r34:generated:RH-HOME:home")
	print(JSON.stringify({"safe":Projects.footprint_check(runtime._services.modules,home,runtime.facts(),home.id),"actors":runtime.facts().actors,"hammer":runtime.tool("r34:generated:RH-HOME:woodwork:tool:hammer")}))
	runtime.retire();quit()
