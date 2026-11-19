extends "res://tests/world/ground_budget_split.gd"
func run()->void:
	var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("fixed actual native capture assembles in fresh process",built.ok,built.get("reason"))
	if not built.ok:return finish_split(args)
	var world:RefCounted=built.world;var snapshot:Dictionary=world.snapshot();var facts:Dictionary=built.runtime.facts()
	var after:bool=args[2]=="after"
	var sample:Dictionary=await one(world,AfterTerrain if after else BeforeTerrain,"13,0,0",after)
	check("native physics ready after full staged geometry",sample.geometry_ready and sample.physics_was_closed and sample.ready and sample.pending==0)
	if after:
		check("fresh-process pure array phases load no textures",sample.no_layer_loads)
		check("fresh-process upload loads no textures",sample.no_upload_loads)
		check("fresh-process ground request loads no more than one image",sample.single)
	check("full facts world and residency exact after native derivation",Data.json_equal(snapshot,world.snapshot()) and Data.json_equal(facts,built.runtime.facts()))
	sample.erase("signature");samples.append(sample);finish_split(args)
