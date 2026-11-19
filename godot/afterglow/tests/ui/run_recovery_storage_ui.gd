extends SceneTree
## Real A coordinator/store/codec/runtime and UI, isolated slots only. The
## candidate stage/ready/activation scene is an explicit UI-only adapter.
const Client = preload("res://scripts/runtime/native_client.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
class Router extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
class Host extends Client:
	signal release_candidate
	var gate := false
	var waiting := false
	var gate_failure: Dictionary = {}
	var mounts := 0
	var discards := 0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _prepare_mount_ready(capture: Dictionary, assembly: Dictionary = {}) -> Dictionary:
		var built: Dictionary = _assemble(capture) if assembly.is_empty() else assembly
		if not built.get("ok", false): return built
		_world_epoch += 1
		if gate:
			waiting = true
			await release_candidate
			waiting = false; gate = false
		if not gate_failure.is_empty():
			var failure := gate_failure.duplicate(true); gate_failure.clear()
			built.runtime.retire()
			return failure
		await get_tree().process_frame
		return built.merged({"world_epoch":_world_epoch,"readiness":{"ready":true,"fixture":"explicit UI-only candidate gate, no 3D/physics"}}, true)
	func _activate_scene(candidate: Dictionary, fresh_profile: bool = false) -> Dictionary:
		return _mount(candidate.runtime.capture_checkpoint(), candidate, fresh_profile)
	func _discard_candidate(candidate: Dictionary) -> void:
		discards += 1
		if candidate.get("runtime") != null: candidate.runtime.retire()
	func _mount(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		var built: Dictionary = _assemble(capture) if assembly.is_empty() else assembly
		if not built.get("ok", false): return built
		if router != null: router.queue_free()
		if ui != null: ui.get_parent().queue_free()
		if runtime != null: runtime.retire()
		world = built.world; runtime = built.runtime
		router = Router.new(); router.controls_path = controls_path; add_child(router); router.configure(runtime, fresh_profile)
		ui = Mount.mount(self, runtime, router)
		mounts += 1
		return {"ok":true,"code":"OK"}
var checks: Array = []
var output := ""
func _initialize() -> void:
	create_timer(25).timeout.connect(func(): finish(2))
	call_deferred("run")
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail}); print(("PASS " if ok else "FAIL ") + name)
func flush() -> void:
	await process_frame; await process_frame
func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(value); file.close()
func save_new(store: RefCounted, capture: Dictionary) -> Dictionary:
	var result: Dictionary = store.begin_save(capture, true)
	if not result.get("ok", false): return result
	result = {}
	while result.is_empty(): await process_frame; result = store.poll()
	return result
func press(keycode: int) -> void:
	var event := InputEventKey.new(); event.physical_keycode = keycode; event.keycode = keycode; event.pressed = true
	root.push_input(event, true)
func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	var host := Host.new(); root.add_child(host)
	host.controls_path = output.path_join("isolated-no-controls.json")
	host.store = Store.new(output.path_join("isolated-saves"))
	var built: Dictionary = host._new_rural(713)
	check("real A B C old rural authority assembles through UI-only mount", built.get("ok", false), built)
	if not built.get("ok", false): host.queue_free(); finish(1); return
	var first: Dictionary = await save_new(host.store, host.runtime.capture_checkpoint())
	check("first complete real namespace saves", first.get("ok", false), first.get("reason"))
	if not first.get("ok", false): host.queue_free(); finish(1); return
	var first_text := FileAccess.get_file_as_string(str(first.path))
	var first_capture: Dictionary = Store.decode(first_text).capture
	built = host._new_rural(2026)
	check("second real world assembles without a preview", built.get("ok", false))
	var second: Dictionary = await save_new(host.store, host.runtime.capture_checkpoint())
	check("second world saves to a distinct real namespace", second.get("ok", false) and second.get("namespace") != first.get("namespace"))
	var second_text := FileAccess.get_file_as_string(str(second.path))
	var active_path: String = host.store.root + "/active.json"
	var second_pointer := FileAccess.get_file_as_string(active_path)
	var second_capture: Dictionary = Store.decode(second_text).capture
	var second_meta: Dictionary = JSON.parse_string(second_pointer)
	check("real saved active DTO contains checkpoint world and slot digest", second_meta.get("namespace") == second.get("namespace") and second_meta.get("slot") == second.get("slot") and second_meta.get("checkpoint_id") == second.get("checkpoint_id") and second_meta.get("world_id") == second_capture.world.worldId and second_meta.get("sha256") == second_text.sha256_text(), second_meta)
	# A's old-pointer adapter still requires the real checkpoint identity. Only
	# world/SHA are optional; never omit checkpoint_id to make a fixture work.
	var legacy_meta := second_meta.duplicate(true)
	legacy_meta.erase("world_id"); legacy_meta.erase("sha256")
	var legacy_pointer := JSON.stringify(legacy_meta)
	write(active_path, legacy_pointer)
	var legacy_loaded: Dictionary = host.store.load_current()
	check("legal historical pointer omits only optional world and SHA", legacy_loaded.get("ok", false) and legacy_loaded.get("checkpoint_id") == second_meta.checkpoint_id and legacy_loaded.capture.world.worldId == second_capture.world.worldId and FileAccess.get_file_as_string(active_path) == legacy_pointer)
	var before_legacy_ui: Control = host.ui
	before_legacy_ui.open_panel("pause"); before_legacy_ui.restore_saved_world(); await flush(); await flush()
	check("actual UI restores legal historical index through real coordinator", not is_instance_valid(before_legacy_ui) and host.runtime.facts() == second_capture.facts and host.world.identity().worldId == second_capture.world.worldId and not is_instance_valid(host.ui._recovery_menu) and FileAccess.get_file_as_string(active_path) == legacy_pointer)
	# Deliberately corrupt one field at a time in an otherwise real DTO. These
	# are rejection cases, not successful fixture metadata.
	for defect: String in ["missing checkpoint", "wrong checkpoint", "wrong world", "wrong SHA"]:
		var invalid_meta := second_meta.duplicate(true)
		match defect:
			"missing checkpoint": invalid_meta.erase("checkpoint_id")
			"wrong checkpoint": invalid_meta.checkpoint_id = "native:wrong:1"
			"wrong world": invalid_meta.world_id = first_capture.world.worldId
			"wrong SHA": invalid_meta.sha256 = "0".repeat(64)
		var invalid_pointer := JSON.stringify(invalid_meta)
		write(active_path, invalid_pointer)
		var original_runtime: RefCounted = host.runtime
		var original_facts: Dictionary = original_runtime.facts()
		var live_ui: Control = host.ui
		live_ui.open_panel("pause"); live_ui.restore_saved_world(); await flush()
		var invalid_menu: Control = live_ui._recovery_menu
		check("actual UI requires explicit candidates for " + defect, is_instance_valid(invalid_menu) and invalid_menu.candidates.size() == 2 and invalid_menu._selected.is_empty() and host.runtime == original_runtime and host.runtime.facts() == original_facts and FileAccess.get_file_as_string(active_path) == invalid_pointer and FileAccess.get_file_as_string(str(first.path)) == first_text and FileAccess.get_file_as_string(str(second.path)) == second_text)
		live_ui.cancel_ui(); await flush()
		check("candidate cancellation preserves rejected active bytes for " + defect, not is_instance_valid(live_ui._recovery_menu) and live_ui.pages.back().page == "pause" and host.runtime == original_runtime and FileAccess.get_file_as_string(active_path) == invalid_pointer)
	write(active_path, second_pointer)
	write(active_path, "{broken-active-ui-fixture")
	var scan: Dictionary = host.store.load_current()
	check("bad active yields candidates without choosing another world", scan.get("code") == "RECOVERY_CHOICE_REQUIRED" and scan.get("candidates", []).size() == 2 and FileAccess.get_file_as_string(active_path) == "{broken-active-ui-fixture")
	var old_runtime: RefCounted = host.runtime
	var old_facts: Dictionary = old_runtime.facts()
	var old_world: Dictionary = host.world.snapshot()
	var old_ui: Control = host.ui
	old_ui.open_panel("pause"); old_ui.restore_saved_world(); await flush()
	var menu: Control = old_ui._recovery_menu
	check("real failed restore routes candidates into same recovery Control", is_instance_valid(menu) and menu.candidates.size() == 2 and menu._selected.is_empty() and host.runtime == old_runtime and old_runtime.facts() == old_facts)
	if not is_instance_valid(menu): host.queue_free(); finish(1); return
	var chosen: Dictionary = {}
	for row: Dictionary in menu.candidates:
		if int(row.seed) == 713: chosen = row
	check("explicit source world is identified by candidate ID and SHA", not chosen.is_empty() and chosen.sha256 == first_text.sha256_text() and chosen.world_id == first_capture.world.worldId, chosen)
	menu.select_candidate(chosen)
	menu._restore_pressed(); press(KEY_ESCAPE); await flush()
	check("native viewport Escape cancels confirmation without changing active", menu._confirming.is_empty() and FileAccess.get_file_as_string(active_path) == "{broken-active-ui-fixture")
	# A digest change is a real disk fault in the isolated fixture, not a mock
	# failure code. UI must display it and preserve the current live authority.
	write(str(first.path), first_text + "\n")
	menu._restore_pressed(); menu._restore_pressed(); await flush()
	check("real stale candidate refuses with visible stable diagnostic", not menu.busy and menu._status.tooltip_text.contains("STALE_CANDIDATE") and host.runtime == old_runtime and old_runtime.facts() == old_facts and host.world.snapshot() == old_world)
	check("stale choice preserves active and all other slot bytes", FileAccess.get_file_as_string(active_path) == "{broken-active-ui-fixture" and FileAccess.get_file_as_string(str(second.path)) == second_text)
	write(str(first.path), first_text)
	host.gate = true; host.gate_failure = {"ok":false,"code":"NOT_READY","reason":"受控UI-only候选尚未就绪"}
	menu._restore_pressed(); menu._restore_pressed(); await flush()
	check("real coordinator holds old authority while candidate gate waits", host.waiting and menu.busy and old_ui.world_restoring and host.runtime == old_runtime and host._save_state.get("status") == "loading")
	var revision: int = old_runtime.get_revision()
	press(KEY_W); press(KEY_E); press(KEY_1); press(KEY_ESCAPE); await flush()
	check("viewport gameplay keys are consumed during recovery without cancelling submitted work", host.waiting and menu.busy and old_runtime.get_revision() == revision and host.router._pressed.is_empty())
	host.release_candidate.emit(); await flush()
	check("candidate ready refusal returns to same recoverable scene and reason", not menu.busy and not old_ui.world_restoring and menu._status.tooltip_text.contains("NOT_READY") and host.runtime == old_runtime and old_runtime.facts() == old_facts and FileAccess.get_file_as_string(active_path) == "{broken-active-ui-fixture")
	host.gate = true
	menu._restore_pressed(); menu._restore_pressed(); await flush()
	write(active_path, second_pointer)
	host.release_candidate.emit(); await flush()
	check("actual active CAS conflict is visible without mounting candidate", not menu.busy and menu._status.tooltip_text.contains("STALE_ACTIVE") and host.discards == 1 and host.runtime == old_runtime and old_runtime.facts() == old_facts)
	check("CAS refusal preserves the competing pointer and both complete slots", FileAccess.get_file_as_string(active_path) == second_pointer and FileAccess.get_file_as_string(str(first.path)) == first_text and FileAccess.get_file_as_string(str(second.path)) == second_text)
	menu._restore_pressed(); menu._restore_pressed(); await flush(); await flush()
	var recovered: Dictionary = host.store.load_current()
	check("explicit retry activates chosen world through real coordinator and store", recovered.get("ok", false) and recovered.capture.world.worldId == chosen.world_id and host.world.identity().worldId == chosen.world_id and host.runtime != old_runtime, recovered.get("code"))
	var activated_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(active_path))
	check("explicit recovery activation writes true checkpoint world and slot digest", activated_meta.get("namespace") == chosen.get("namespace") and activated_meta.get("slot") == chosen.get("slot") and activated_meta.get("checkpoint_id") == chosen.get("checkpoint_id") and activated_meta.get("world_id") == chosen.get("world_id") and activated_meta.get("sha256") == first_text.sha256_text(), activated_meta)
	check("restored facts and clock are saved values without new inventory", host.runtime.facts() == first_capture.facts and host.runtime.clock() == first_capture.facts.time)
	check("old UI and selected overlay are disposed after takeover", not is_instance_valid(old_ui) and not is_instance_valid(menu) and host.ui != null)
	check("retired authority rejects stale commands after successful recovery", old_runtime.availability({"kind":"drink","actor_id":"player"}).get("code") == "WORLD_RETIRED")
	check("recovery never rewrites source slot contents", FileAccess.get_file_as_string(str(first.path)) == first_text and FileAccess.get_file_as_string(str(second.path)) == second_text)
	# Exercise the exact startup callback pair without invoking Client._ready,
	# opening an app or using the real user's --continue/active files.
	var startup := Host.new(); root.add_child(startup)
	startup.controls_path = output.path_join("startup-no-controls.json"); startup.store = host.store
	var startup_menu: Control = Mount.mount_recovery(startup, [chosen], startup._startup_choose_recovery, startup._startup_fresh)
	startup._startup_recovery = startup_menu
	await flush()
	check("startup callback wiring still requires explicit selection with no runtime", startup.runtime == null and startup_menu._selected.is_empty())
	startup_menu.select_candidate(chosen); startup_menu._restore_pressed(); startup_menu._restore_pressed(); await flush(); await flush()
	check("actual A startup choose callback mounts and closes recovery Control", startup.runtime != null and startup.world.identity().worldId == chosen.world_id and not is_instance_valid(startup_menu) and startup.ui != null)
	host.queue_free(); startup.queue_free(); await flush()
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)
func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"fixture":"actual A coordinator/native_store/codec/runtime + B/C old finite worlds + production UI + isolated disk faults and Viewport keys; explicit UI-only candidate/readiness/scene adapter; startup callback pair mounted manually, not Client._ready or OS --continue","formal_application_launched":false,"physical_os_input":false,"production_readiness_validated":false,"route_acceptance":false}, "  ")); file.close()
	quit(code)
