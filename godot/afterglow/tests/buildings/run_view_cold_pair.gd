extends "res://tests/buildings/run_view_mount.gd"
## Both modes parse the SAME frozen/current sources and Native dependencies.
## Each invocation is a new headless process; no other view/resource warmup.
const Reference=preload("res://tests/buildings/view_mount_reference/building_view.gd")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 or args[2] not in ["preimage","current"]:quit(2);return
	var output:String=args[0];var input:String=args[1];var mode:String=args[2]
	DirAccess.make_dir_recursive_absolute(output)
	var input_sha:=FileAccess.get_sha256(input)
	var decoded:=Store.decode(FileAccess.get_file_as_string(input))
	check("exact actual24 original input",input_sha=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48" and decoded.get("ok",false))
	if not decoded.get("ok",false):quit(1);return
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("real Native assembly succeeds",built.get("ok",false))
	if not built.get("ok",false):quit(1);return
	var runtime:RefCounted=built.runtime;var service:RefCounted=built.services.buildings
	var before:Dictionary=runtime.capture_checkpoint();var view:Node3D
	var started:=Time.get_ticks_usec()
	if mode=="preimage":
		# Exact old BuildingService.create_view body, selecting frozen preimage
		# script only. Production service / world / facts are the same inputs.
		var View=load("res://tests/buildings/view_mount_reference/building_view.gd")
		view=View.new();var options:Dictionary={"runtime":runtime}.duplicate();options.service=service;view.configure(options)
	else:view=service.create_view({"runtime":runtime})
	var first_usec:=Time.get_ticks_usec()-started
	var state:=view_state(view);var sha:=JSON.stringify(state,"",true,true).sha256_text()
	check("same full geometry material pixel state and object counts",sha=="ed7f6c347c1ab487f092e7d7d1dc33debb7d115754e441dfb38fb5879c5a8aa7")
	check("real returned view remains synchronous and nonmutating",Data.json_equal(before,runtime.capture_checkpoint()))
	check("original source protected",FileAccess.get_sha256(input)==input_sha)
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"mode":mode,"first_create_view_usec":first_usec,"view_state_sha256":sha,"statistics":state.statistics,"texture_cache_count":view.texture_cache.size(),"input_sha256":input_sha,"scope":"New headless process first real view, same parsed preimage/current and Native dependencies. Frozen mode mirrors original service factory body. No renderer/FPS/quiet window or overall mount budget claim."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	view.free();runtime.retire();print(JSON.stringify(report,"",false,true));quit(1 if report.failed else 0)
