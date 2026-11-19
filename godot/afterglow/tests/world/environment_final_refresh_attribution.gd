extends "res://tests/world/environment_mount.gd"
const Profile=preload("res://tests/world/fixtures/environment_final_refresh_profile.gd")
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var output:String=args[0];var input:String=args[1]
	check("same real24 input",FileAccess.get_sha256(input)=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48")
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input));var host:=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("actual Native24 assembles",built.get("ok",false))
	if not built.get("ok",false):return finish(output)
	world=built.world;var before:Dictionary=built.runtime.capture_checkpoint()
	var view:=Profile.new();root.add_child(view);var start:int=Time.get_ticks_usec();view.configure({"world":world});var configure_usec:int=Time.get_ticks_usec()-start
	var samples:Array=[]
	for i:int in 4:
		view.reset_profile();start=Time.get_ticks_usec();view.on_world_changed({"entities":[]})
		samples.append({"total_usec":Time.get_ticks_usec()-start,"inclusive_attribution":view.phase.duplicate(true),"ecology_candidates":view._last_ecology_candidates,"trees":view._roots.size(),"patch_chunks":view._ecology.size()})
	check("attribution keeps complete authority",Data.json_equal(before,built.runtime.capture_checkpoint()))
	costs={"configure_usec":configure_usec,"samples":samples,"scope":"same real24 current scoped-sampler preimage attribution; instrumented nested inclusive clocks not before/after or OS/FPS"}
	view.free();built.runtime.retire();host.free();finish(output)
