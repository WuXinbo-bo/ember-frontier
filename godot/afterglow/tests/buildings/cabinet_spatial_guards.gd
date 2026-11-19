extends "res://tests/integration/run_factory_economy.gd"
## Read-only counterexamples from the immutable C4 normal-economy save.
## No actor, terrain, inventory or module fixture is manufactured here.
var input_sha:String=""
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];DirAccess.make_dir_recursive_absolute(outdir)
	input_sha=FileAccess.get_sha256(args[1])
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("actual candidate17 normal save decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("actual C4 normal authority restores",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var building:RefCounted=built.services.buildings
	var before:Dictionary=runtime.capture_checkpoint()
	var module:Dictionary=built.services.modules.instance("r34:generated:RH-HOME:woodwork")
	var definition:Dictionary=Modules.definition(str(module.definition_id))
	var at:Dictionary=Geometry.location(module.position);at.regionId=module.region
	var shell:Dictionary=building.make_instance("cabinet","B:MV01:shell-counterexample",at)
	var occupied:Dictionary=building.prepare_edit([],[shell])
	check("ordinary cabinet cannot occupy the complete real module footprint",not occupied.ok and occupied.get("code")=="MODULE_OCCUPIED",occupied)
	for port:Dictionary in ModuleShape.ports(module,definition):
		var cabinet:Dictionary=building.make_instance("cabinet","B:MV01:port-counterexample",port.use_points[0])
		var rejected:Dictionary=building.prepare_edit([],[cabinet])
		check("ordinary cabinet cannot block real module service feet "+str(port.id),not rejected.ok and rejected.get("code") in ["MODULE_OCCUPIED","MODULE_PORT_OCCUPIED"],rejected)
		# Top and horizontal grazing remain legal geometry, not an expanded pad.
		var raised:Dictionary=cabinet.duplicate(true);raised.position.y+=3.0
		var support:Dictionary=building.prepare_edit([],[raised])
		check("unsupported furniture above a port still fails actual support "+str(port.id),not support.ok and support.get("code")=="DEPENDENT",support)
		if port.id=="load-in" or port.id=="load-out":
			var forged:Dictionary=cabinet.duplicate(true);forged.id=module.id+":caller-supplied-cabinet";forged.module_id=module.id
			var forged_edit:Dictionary=building.prepare_edit([],[forged])
			check("ID prefix and caller module_id cannot forge authoritative membership "+str(port.id),not forged_edit.ok and forged_edit.get("code")=="MODULE_PORT_OCCUPIED",forged_edit)
			var beside:Dictionary=cabinet.duplicate(true);beside.position.x+=0.9001
			var edge:Dictionary=building.prepare_edit([],[beside])
			check("supported legal cabinet beside exact service clearance is not over-expanded "+str(port.id),edge.ok,edge.get("reason"))
	var member:Dictionary=building.instance(module.id+":workbench")
	var retained:Dictionary=building.prepare_edit([member.id],[member])
	check("original authoritative module workbench remains compatible at its real location",retained.ok,retained.get("reason"))
	check("all spatial queries preserve the full authoritative checkpoint",Data.json_equal(before,runtime.capture_checkpoint()))
	check("original source save remains byte-identical",FileAccess.get_sha256(args[1])==input_sha)
	finish()

func finish()->void:
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"input_sha256":input_sha,"scope":"actual C4 normal-save pure spatial guards; no GUI/package/OS/VA qualification"}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if report.failed else 0)
