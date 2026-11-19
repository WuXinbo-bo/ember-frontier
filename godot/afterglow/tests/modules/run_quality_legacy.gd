extends "res://tests/buildings/run_view_mount.gd"
## Only the affected legacy consumer boundary. No actor/clock/perf rerun.
func run()->void:
	var args:=OS.get_cmdline_user_args();var out:String=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[2]))
	var h:=Native.new();var mounted:Dictionary=h._assemble(decoded.capture) if decoded.ok else decoded;h.free()
	check("original protected city input Native mount",mounted.ok,mounted.get("reason"))
	if mounted.ok:
		var rt:RefCounted=mounted.runtime;var authority:Dictionary=rt.capture_checkpoint()
		var old:Node3D=load(args[1]+"/scripts/buildings/building_view.gd").new()
		var current:Node3D=mounted.services.buildings.create_view({"runtime":rt})
		old.configure({"service":mounted.services.buildings,"runtime":rt})
		var original_state:=view_state(old);var new_state:=view_state(current)
		check("old city exact nodes geometry UV materials metadata visibility",Data.json_equal(original_state,new_state))
		check("old city retains real multi-floor batches and twenty doors",current.static_nodes.size()>0 and current.doors.size()==20,current.residency_statistics())
		check("legacy and current views never alter authority",Data.json_equal(authority,rt.capture_checkpoint()))
		var encoded:=Store.encode(authority);var cold:=Store.decode(encoded.text) if encoded.ok else encoded
		var host:=Native.new();var restored:Dictionary=host._assemble(cold.capture) if cold.ok else cold;host.free()
		check("legacy geometry and saves still cold-mount",restored.ok,restored.get("reason"))
		if restored.ok:
			var cv:Node3D=restored.services.buildings.create_view({"runtime":restored.runtime})
			check("legacy actual cold view matches warm state",Data.json_equal(new_state,view_state(cv)))
			cv.free();restored.runtime.retire()
		old.free();current.free();rt.retire()
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	var f:=FileAccess.open(out+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify({"ok":ok,"checks":checks,"scope":"Original legacy city actual Native/view/cold boundary under new B mesh consumers. No changes to input; no renderer, gameplay route or OS/VA/FPS."},"\t"));f.close()
	print("QUALITY LEGACY "+str(checks.size())+" "+str(ok));quit(0 if ok else 1)
