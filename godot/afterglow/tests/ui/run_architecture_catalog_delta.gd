extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Only the post-325 owner description/capacity delta. No repeat of GUI routes.
func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size() < 3: check("sealed save and exact owner delta expectation supplied", false); return finish(1)
	var original := FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary = Store.decode(original)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	check("original sealed capture decodes", decoded.get("ok", false))
	if not decoded.get("ok", false): return finish(1)
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	host = TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var before: Dictionary = runtime.capture_checkpoint()
	var definitions := F.build_definitions(runtime.factory_snapshot("player"))
	check("new public owner retains 40 choices with 30 architecture definitions", definitions.size() == 40 and definitions.filter(func(row: Dictionary): return not Catalog.architecture(row).is_empty()).size() == 30)
	ui.open_panel("factory_catalog"); await idle(); await idle()
	for row: Dictionary in definitions:
		var architecture_ := Catalog.architecture(row)
		if architecture_.is_empty(): continue
		var node := card(str(row.id))
		var shown := text_in(node) if node != null else ""
		if architecture_.family == "home":
			check("unchanged housing capacity remains descriptive " + str(row.id), shown.contains(Catalog.capacity_text(row)) and shown.contains("不代表实际入住或床位") and not shown.contains("已住"))
		else:
			check("new non-home DTO omits capacity and no housing is displayed " + str(row.id), not architecture_.has("design_capacity") and Catalog.capacity_text(row).is_empty() and not shown.contains("设计容量") and not shown.contains("0 人"))
		if expected.get("descriptions", {}).has(str(row.id)):
			check("corrected owner prose reaches actual native card " + str(row.id), architecture_.description == expected.descriptions[str(row.id)] and shown.contains(str(architecture_.description)) and not shown.contains("tooth anchor") and not shown.contains("bench_offset") and not shown.contains("增加攻击"), shown)
	check("description rendering preserves world and original input bytes", Data.json_equal(before, runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1]) == original)
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func finish(code: int) -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"method":"Post-325 owner delta only: unchanged A save through original Native/Runtime/UI, corrected Chinese descriptions and absence of non-home capacity, no repeated GUI route checks","scope":"Current-source native Control description support; original 325 retains its original source identity; no geometry/paid-build/PCK/OS/VA/FPS qualification"}, "\t", true, true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(code)
