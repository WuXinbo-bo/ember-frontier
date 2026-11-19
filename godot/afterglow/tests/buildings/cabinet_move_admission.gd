extends "res://tests/buildings/cabinet_spatial_guards.gd"
## This entry deliberately uses no post17 InputRouter/Runtime API. A can run
## the identical real MV01 save and these assertions against immutable17 and
## the next package to distinguish the admission fix from normal UI changes.
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];DirAccess.make_dir_recursive_absolute(outdir)
	input_sha=FileAccess.get_sha256(args[1])
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("actual completed normal MV01 save decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("real normal moved cabinet restores into the shipping authority",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var building:RefCounted=built.services.buildings
	var piece:Dictionary=building.instance("B:MV01:normal-cabinet")
	check("test reads the actual paid moved 60HP object and original stock",not piece.is_empty() and piece.hp==60 and runtime.stock(piece.id).structureId==piece.id)
	if piece.is_empty():return finish()
	var before:Dictionary=runtime.capture_checkpoint()
	var unsupported:Dictionary=piece.duplicate(true);unsupported.position.y+=0.5
	var occupied:Dictionary=piece.duplicate(true);occupied.position=Geometry.json_point(Geometry.point(runtime.actor("player")))
	for case:Dictionary in [{"piece":unsupported,"code":"DEPENDENT","label":"missing real support"},{"piece":occupied,"code":"OCCUPIED","label":"actual live player body"}]:
		var request:Dictionary={"command_id":"B:MV01:admission:"+str(case.code),"actor_id":"player","kind":"structure","target_id":piece.id,"payload":{"kind":"move","destination":case.piece,"source_id":"pack:player","output_id":"pack:player","tool_id":"r34:generated:RH-HOME:woodwork:tool:hammer","direct":true}}
		var preview:Dictionary=runtime.availability(request)
		check("move preview rejects before labor: "+str(case.label),not preview.ok and preview.get("code")==case.code,{"ok":preview.ok,"code":preview.get("code"),"reason":preview.get("reason")})
		check("move preview is a pure query: "+str(case.label),Data.json_equal(before,runtime.capture_checkpoint()))
		var submitted:Dictionary=runtime.command(request)
		check("move authoritative admission rejects before labor: "+str(case.label),not submitted.ok and submitted.get("code")==case.code,{"ok":submitted.ok,"code":submitted.get("code"),"reason":submitted.get("reason")})
		check("move rejection preserves exact checkpoint: "+str(case.label),Data.json_equal(before,runtime.capture_checkpoint()))
		# Immutable17 is expected to fail the rejection assertions; stop before
		# its admitted order contaminates the second independent counterexample.
		if submitted.ok:break
	check("actual normal MV01 source save remains byte-identical",FileAccess.get_sha256(args[1])==input_sha)
	finish()
