extends "res://tests/ui/run_movable_container_ui.gd"
## Narrow real-hand consistency check after the paid normal UI route.
func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; input_path = args[1]
	DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	input_sha = FileAccess.get_sha256(input_path)
	var decoded: Dictionary = Store.decode(FileAccess.get_file_as_string(input_path))
	check("actual paid UI cabinet archive decodes", decoded.get("ok", false))
	if not decoded.get("ok", false): finish(); return
	host = TestClient.new(); root.add_child(host)
	if not await mount_capture(decoded.capture): finish(); return
	attach_pointer()
	for stock: Dictionary in runtime.snapshot().stocks:
		var facility: Dictionary = runtime.movable_facility(str(stock.id))
		if facility.get("available", false): cabinet_id = str(facility.structure_id); break
	check("real public stock resolves original cabinet", not cabinet_id.is_empty())
	if cabinet_id.is_empty(): finish(); return
	var axe := "r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
	var hammer := "r34:generated:RH-HOME:woodwork:tool:hammer"
	router.assign_slot(7, {"kind":"tool", "tool_id":axe}); router.select_slot(7)
	ui.open_panel("container", cabinet_id); await flush()
	var before: Dictionary = runtime.capture_checkpoint()
	var button: Button = keyed("factory:movable:move:" + cabinet_id)
	check("public readiness permits original cabinet with carried real hammer", button != null and not button.disabled and runtime.movable_facility(cabinet_id).get("can_move", false))
	if button == null or button.disabled: finish(); return
	button.pressed.emit(); await flush(); aim(Vector3(12, 0.5, 4))
	var payload: Dictionary = direct._preview.duplicate(true)
	var ready: Dictionary = runtime.availability({"actor_id":"player", "kind":"structure", "target_id":cabinet_id, "payload":payload})
	var corrected: Dictionary = payload.duplicate(true); corrected.tool_id = hammer
	var hammer_ready: Dictionary = runtime.availability({"actor_id":"player", "kind":"structure", "target_id":cabinet_id, "payload":corrected})
	check("same real destination is valid with original carried hammer", hammer_ready.get("ok", false), hammer_ready.get("reason"))
	check("context move preview uses capable carried tool while preserving axe hotbar", ready.get("ok", false) and payload.get("tool_id") == hammer and router.held_reference().get("id") == axe, {"actual_tool":payload.get("tool_id"), "ready":ready.get("reason"), "hammer_ready":hammer_ready.get("ok")})
	router.cancel(); await flush()
	check("hand probe and cancellation preserve every authority fact and original archive", Data.json_equal(before, runtime.capture_checkpoint()) and FileAccess.get_sha256(input_path) == input_sha)
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row: Dictionary): return not row.ok).size()
	FileAccess.open(output + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"input_sha256":input_sha,"scope":"post-paid normal cabinet, real axe selected and real carried hammer, original input/availability; queries only, no move submitted or grants; not OS/renderer/PCK"}, "\t", true, true))
	detach_pointer()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
