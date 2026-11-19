extends SceneTree
## UI-only mount adapter, real A async coordinator/store and C/B generation.
## No main scene, renderer, user saves or formal application/OS-input acceptance.
const Client = preload("res://scripts/runtime/native_client.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const Data = preload("res://scripts/world/world_data.gd")

class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true

class UiClient extends Client:
	signal release_ui_mount
	var mounts := 0
	var requested_seeds: Array = []
	var gate_ui_mount := false
	var ui_mount_waiting := false
	var ui_mount_failure: Dictionary = {}
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func start_new_world(seed: int = -1, id: String = "") -> Dictionary:
		requested_seeds.append(seed)
		return await super.start_new_world(seed,id)
	func _mount_ready(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		# Test-only async readiness gate; no production 3D readiness claim.
		if gate_ui_mount:
			ui_mount_waiting=true
			await release_ui_mount
			ui_mount_waiting=false;gate_ui_mount=false
		if not ui_mount_failure.is_empty():
			var failure := ui_mount_failure.duplicate(true)
			ui_mount_failure.clear()
			return failure
		return _mount(capture, assembly, fresh_profile)
	func _mount(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		# Keep A's validation/authorities/lifecycle, omit production 3D views.
		var built: Dictionary = _assemble(capture) if assembly.is_empty() else assembly
		if not built.get("ok", false): return built
		if router != null: router.queue_free()
		if ui != null: ui.get_parent().queue_free()
		world = built.world
		runtime = built.runtime
		router = TestRouter.new(); add_child(router); router.configure(runtime, fresh_profile)
		ui = Mount.mount(self, runtime, router)
		mounts += 1
		return {"ok":true,"code":"OK"}

class DeferredAuthority extends RefCounted:
	signal changed(changes: Dictionary)
	signal resolve
	signal resolve_save
	var wait_for_save := false
	var save_calls := 0
	var bad_save_id := false
	var save_receipt := {"ok":true,"code":"OK","reason":"受控保存成功"}
	var save := {"ready":true,"busy":false,"status":"idle","reason":"尚未保存"}
	var receipt := {"ok":false,"code":"GENERATION_TEST","reason":"受控生成失败，旧档保留"}
	var calls := 0
	var request_id := ""
	var bad_id := false
	func snapshot() -> Dictionary: return {"save":save.duplicate(true)}
	func save_async(id: String = "") -> Dictionary:
		save_calls += 1
		save.merge({"busy":true,"status":"saving","reason":"受控保存等待"}, true)
		changed.emit({"save":true})
		if wait_for_save: await resolve_save
		save.merge({"busy":false,"status":"saved" if save_receipt.ok else "failed","reason":save_receipt.reason}, true)
		changed.emit({"save":true})
		return save_receipt.merged({"request_id":"wrong-save-id" if bad_save_id else id}, true)
	func start_new_world(seed: int = -1, id: String = "") -> Dictionary:
		calls += 1; request_id = id
		assert(seed == 713)
		save.merge({"busy":true,"status":"generating","reason":"受控生成等待"}, true)
		changed.emit({"save":true})
		await resolve
		save.merge({"busy":false,"status":"saved" if receipt.ok else "failed","reason":receipt.reason}, true)
		changed.emit({"save":true})
		var result := receipt.duplicate(true)
		result.request_id = "different-request" if bad_id else id
		return result

class ProfileAuthority extends DeferredAuthority:
	var opening_profile := "normal"
	var requested_profiles:Array=[]
	func snapshot()->Dictionary:return super.snapshot().merged({"opening_profile":opening_profile})
	func start_profiled_world(profile:String,seed:int=-1,id:String="")->Dictionary:
		requested_profiles.append(profile)
		return await super.start_new_world(seed,id)

var checks: Array = []
var output := ""
var host: UiClient
var states: Array = []

func _initialize() -> void:
	create_timer(75).timeout.connect(func(): push_error("UI new-world check timeout"); finish(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok: push_error(name + " " + str(detail))

func button_key(node: Node, key: String) -> Button:
	if node is Button and node.get_meta("ui_focus_key", "") == key: return node
	for child in node.get_children():
		var found := button_key(child, key)
		if found != null: return found
	return null

func text_in(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += text_in(child)
	return result

func activate(ui: Control, key: String) -> void:
	var control := button_key(ui, key)
	check("enabled UI button " + key, control != null and not control.disabled)
	if control != null and not control.disabled: control.pressed.emit()

func flush() -> void:
	await process_frame
	await process_frame

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	host = UiClient.new(); root.add_child(host)
	host.store = Store.new(output + "/isolated-saves")
	var setup: Dictionary = host._new_rural(713)
	check("actual old-world assembly with UI-only test mount", setup.get("ok", false), setup)
	if not setup.get("ok", false): finish(1); return
	await flush()
	var ui: Control = host.ui
	ui.open_panel("pause")
	var saved: Dictionary = await host.save_async("ui-fixture-old-slot")
	check("actual isolated old save exists", saved.get("ok", false), saved)
	ui.refresh()
	var pointer_path := output + "/isolated-saves/active.json"
	var pointer_bytes := FileAccess.get_file_as_bytes(pointer_path)
	var old_capture: Dictionary = host.runtime.capture_checkpoint()
	var old_runtime: RefCounted = host.runtime
	var saved_form: Dictionary = Store.decode(Store.encode(old_capture).text).capture
	var initial_serial: int = ui._serial
	activate(ui, "pause:new-world")
	await flush()
	check("first click only opens secondary confirmation", ui.pages.back().page == "new_world" and ui._serial == initial_serial and not host._world_loading)
	var content := text_in(ui._body)
	check("confirmation explains preserve-first and fixed default", content.contains("先保存当前世界") and content.contains("旧世界存档独立保留") and content.contains("默认种子713") and ui._new_world_seed_text == "713", content)
	var focus := root.gui_get_focus_owner()
	check("safe initial focus is cancellation", is_instance_valid(focus) and focus.get_meta("ui_focus_key", "") == "new-world:cancel")
	activate(ui, "new-world:cancel")
	check("cancel returns to pause without request or save mutation", ui.pages.back().page == "pause" and ui._serial == initial_serial and pointer_bytes == FileAccess.get_file_as_bytes(pointer_path) and Data.json_equal(old_capture, host.runtime.capture_checkpoint()))
	host._save_state.ready = false; ui.refresh()
	check("not-ready storage disables new-world entry", button_key(ui, "pause:new-world").disabled)
	host._save_state.merge({"ready":true,"busy":true,"status":"saving","reason":"external save fixture"}, true); ui.refresh()
	check("external save disables new-world and existing file actions", button_key(ui, "pause:new-world").disabled and button_key(ui, "pause:save").disabled and button_key(ui, "pause:export").disabled and button_key(ui, "pause:import").disabled)
	ui.choose_new_world()
	check("live busy recheck rejects a stale menu event", ui.pages.back().page == "pause" and ui._serial == initial_serial)
	host._save_state.merge({"busy":false,"status":"saved","reason":"fixture released"}, true); ui.refresh()
	activate(ui, "pause:new-world")
	var good_store: RefCounted = host.store
	var blocked := FileAccess.open(output + "/blocked-parent", FileAccess.WRITE)
	blocked.store_string("isolated preserve failure fixture"); blocked.close()
	host.store = Store.new(output + "/blocked-parent/saves")
	activate(ui, "new-world:confirm")
	while ui.world_starting: await process_frame
	ui.refresh()
	check("actual old save failure prevents generation and mount", host.requested_seeds.is_empty() and host.mounts == 1 and host.runtime == old_runtime and ui._new_world_receipt.code == "IO_ERROR", ui._new_world_receipt)
	check("failed save preserves live capture and prior active bytes", Data.json_equal(old_capture, host.runtime.capture_checkpoint()) and pointer_bytes == FileAccess.get_file_as_bytes(pointer_path))
	check("save failure retains seed and usable retry/cancel", ui._new_world_seed_text == "713" and not button_key(ui,"new-world:confirm").disabled and not button_key(ui,"new-world:cancel").disabled and text_in(ui._body).contains("当前世界保存未完成"), text_in(ui._body))
	host.store = good_store
	old_runtime.changed.connect(func(_change: Dictionary):
		var state: Dictionary = old_runtime.snapshot().save
		if states.is_empty() or states[-1] != state: states.append(state))
	host.gate_ui_mount = true
	host.ui_mount_failure = {"ok":false,"code":"WORLD_READY_TIMEOUT","reason":"受控UI装配门拒绝，旧现场保留"}
	activate(ui, "new-world:confirm")
	ui.refresh()
	check("preserve-first wait blocks return and shows real saving", ui.world_starting and host._save_state.status == "saving" and text_in(ui._body).contains("正在保存当前世界") and button_key(ui,"new-world:confirm").disabled and button_key(ui,"new-world:cancel").disabled and ui._back_button.disabled, text_in(ui._body))
	while not host.ui_mount_waiting and ui.world_starting: await process_frame
	ui.refresh()
	check("default 713 reaches real coordinator only after actual save", host.ui_mount_waiting and host._world_loading and host._save_state.busy and host._save_state.status == "generating" and ui.world_starting and host.requested_seeds == [713])
	var preserved_pointer := FileAccess.get_file_as_bytes(pointer_path)
	var actual_saved: Dictionary = host.store.load_current()
	check("preserve receipt corresponds to full canonical saved world", actual_saved.get("ok",false) and Data.json_equal(saved_form,actual_saved.get("capture",{})), actual_saved.get("code"))
	host.release_ui_mount.emit()
	while ui.world_starting: await process_frame
	ui.refresh()
	check("controlled readiness refusal returns without replacing authority", ui._new_world_receipt.get("code") == "WORLD_READY_TIMEOUT" and not host._world_loading and not host._save_state.busy and host.mounts == 1 and host.runtime == old_runtime, ui._new_world_receipt)
	check("failed generation retains live world and newly preserved pointer", Data.json_equal(old_capture,host.runtime.capture_checkpoint()) and preserved_pointer == FileAccess.get_file_as_bytes(pointer_path))
	check("failure reason remains with usable retry and return", text_in(ui._body).contains("WORLD_READY_TIMEOUT") and not button_key(ui,"new-world:confirm").disabled and not button_key(ui,"new-world:cancel").disabled and not ui._back_button.disabled, text_in(ui._body))
	var old_view: WeakRef = weakref(ui)
	host.gate_ui_mount = true
	activate(ui, "new-world:confirm")
	ui.refresh()
	check("retry locks before either async phase can yield", ui.world_starting and button_key(ui,"new-world:confirm").disabled and button_key(ui,"new-world:cancel").disabled and ui._back_button.disabled)
	var serial: int = ui._serial
	ui.confirm_new_world(); ui.save_world(); ui.choose_import(); ui.export_world(); ui.choose_new_world()
	ui.close_panels(); ui.cancel_ui(); ui.open_panel("inventory")
	check("repeat/file/navigation cannot duplicate or resume during preserve", ui._serial == serial and ui.pages.back().page == "new_world" and host.mounts == 1 and host.router.is_paused() and old_runtime.is_paused() and not ui._file_dialog.visible)
	var key := InputEventKey.new(); key.keycode = KEY_ESCAPE; key.physical_keycode = KEY_ESCAPE; key.pressed = true
	root.push_input(key, true)
	key = InputEventKey.new(); key.keycode = KEY_ESCAPE; key.physical_keycode = KEY_ESCAPE
	root.push_input(key, true)
	check("native GUI Esc keeps submitted operation modal", ui.pages.back().page == "new_world" and host.router.is_paused())
	while not host.ui_mount_waiting and ui.world_starting: await process_frame
	ui.refresh()
	check("real generating reason is visible without invented percentage", host._save_state.status == "generating" and text_in(ui._body).contains("正在生成村落") and ui._storage_status.text == host._save_state.reason and host.requested_seeds == [713,713], {"save":host._save_state.duplicate(true),"body":text_in(ui._body)})
	var prior_pointer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pointer_path))
	var archived_path := output + "/isolated-saves/" + str(prior_pointer["namespace"]) + "/" + str(prior_pointer.slot) + ".json"
	var archived_bytes := FileAccess.get_file_as_bytes(archived_path)
	preserved_pointer = FileAccess.get_file_as_bytes(pointer_path)
	host.release_ui_mount.emit()
	while host._world_loading: await process_frame
	await flush()
	check("actual coordinator remounts once and disposes awaited UI safely", host.mounts == 2 and old_view.get_ref() == null and host.runtime != old_runtime)
	check("fresh world remains unsaved and old preserved world stays active", host._save_state.status == "unsaved" and preserved_pointer == FileAccess.get_file_as_bytes(pointer_path))
	check("old namespace remains byte-identical and decodable", not archived_bytes.is_empty() and archived_bytes == FileAccess.get_file_as_bytes(archived_path) and Store.decode(archived_bytes.get_string_from_utf8()).get("ok",false))
	var restored: Dictionary = host.store.load_current()
	check("preserved old world equals full canonical checkpoint including original facts", restored.get("ok",false) and Data.json_equal(saved_form,restored.get("capture",{})))
	host.ui.refresh()
	check("fresh UI has no stale modal and does not claim new world saved", host.ui.pages.is_empty() and not host.ui.world_starting and not host.router.is_paused() and host.ui.storage_state().status == "unsaved" and host.ui._storage_status.text.contains("尚未保存"),host.ui._storage_status.text)
	check("real states show saving before generating", states.size() >= 2 and states[0].status == "saving" and states.any(func(row:Dictionary):return row.status == "generating"),states)
	await host.ui.save_world()
	var new_pointer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pointer_path))
	check("saving generated progress uses separate native namespace", new_pointer["namespace"] != prior_pointer["namespace"] and archived_bytes == FileAccess.get_file_as_bytes(archived_path) and host.store.load_current().get("ok",false), {"old":prior_pointer,"new":new_pointer})
	var icon: Dictionary = Icons.descriptor({"reference":{"kind":"item","item_id":"gravel_m3"}})
	check("delivered gravel loads actual texture through exact ID", icon.available and Icons.texture({"reference":{"kind":"item","item_id":"gravel_m3"}}) is Texture2D,icon)

	host.queue_free(); await flush()
	await controlled_profile_cases()
	await controlled_preserve_cases()
	await controlled_lifecycle_cases()
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func controlled_profile_cases()->void:
	var authority:=ProfileAuthority.new()
	var ui:Control=Mount.mount(root,authority,null)
	ui.open_panel("pause");ui.choose_new_world();await flush()
	check("normal opening_profile selects true normal configuration",ui._new_world_profile=="normal")
	activate(ui,"new-world:profile:playtest");await flush()
	check("test opening is explicit native choice",ui._new_world_profile=="playtest" and text_in(ui._body).contains("正常经济"))
	ui.confirm_new_world();await flush()
	check("profiled entry still waits for actual old save first",authority.save_calls==1 and authority.calls==1 and authority.requested_profiles==["playtest"] and ui.world_starting)
	check("profile choice cannot change while submitted",button_key(ui,"new-world:profile:normal").disabled and button_key(ui,"new-world:profile:playtest").disabled)
	authority.resolve.emit();await flush()
	ui.cancel_ui();authority.opening_profile="playtest";ui.refresh();ui.choose_new_world();await flush()
	check("reopened choice uses public opening_profile",ui._new_world_profile=="playtest")
	activate(ui,"new-world:profile:normal");await flush();ui.confirm_new_world();await flush()
	check("normal choice calls same profiled authority without duplicated save",authority.save_calls==2 and authority.calls==2 and authority.requested_profiles==["playtest","normal"])
	authority.resolve.emit();await flush()
	check("profiled generation failure keeps matching reason and retry",ui._new_world_receipt.code=="GENERATION_TEST" and not ui.world_starting and not button_key(ui,"new-world:confirm").disabled)
	ui.get_parent().queue_free();await flush()

func controlled_preserve_cases() -> void:
	var authority := DeferredAuthority.new()
	authority.wait_for_save = true
	var ui: Control = Mount.mount(root,authority,null)
	ui.open_panel("pause"); ui.choose_new_world(); ui._new_world_seed_text = ""
	ui.confirm_new_world(); await flush()
	check("blank seed uses default and cannot start before matching save", authority.save_calls == 1 and authority.calls == 0 and ui.world_starting)
	authority.save_receipt = {"ok":false,"code":"IO_ERROR","reason":"受控保存失败"}
	authority.resolve_save.emit(); await flush()
	check("refused save aborts generation with original error", authority.calls == 0 and not ui.world_starting and ui._new_world_receipt.code == "IO_ERROR" and ui._notice.text.contains("受控保存失败"))
	authority.save_receipt = {"ok":true,"code":"OK","reason":"wrong matching fixture"}; authority.bad_save_id = true
	ui.confirm_new_world(); authority.resolve_save.emit(); await flush()
	check("wrong save ID cannot authorize world generation", authority.calls == 0 and not ui.world_starting and ui._new_world_receipt.code == "UNCONFIRMED")
	authority.bad_save_id = false
	ui.confirm_new_world()
	var fresh := DeferredAuthority.new()
	ui.configure(fresh,null); ui.open_panel("pause")
	authority.resolve_save.emit(); await flush()
	check("late preserve receipt cannot start generation after reconfigure", authority.calls == 0 and ui.runtime == fresh and ui.pages.back().page == "pause")
	fresh.wait_for_save = true
	ui.choose_new_world(); ui.confirm_new_world()
	var view_ref: WeakRef = weakref(ui)
	ui.get_parent().queue_free(); await flush()
	fresh.resolve_save.emit(); await flush()
	check("freed view cannot proceed from save to generation", view_ref.get_ref() == null and fresh.calls == 0)

func controlled_lifecycle_cases() -> void:
	var authority := DeferredAuthority.new()
	var ui: Control = Mount.mount(root, authority, null)
	await flush()
	ui.open_panel("pause"); activate(ui,"pause:new-world"); activate(ui,"new-world:confirm")
	await flush()
	check("controlled generation never reports success before receipt", ui.world_starting and not ui._notice.text.contains("已进入"))
	authority.resolve.emit(); await flush()
	check("generation failure preserves confirmation and actual reason", not ui.world_starting and ui.pages.back().page == "new_world" and text_in(ui._body).contains("GENERATION_TEST") and not button_key(ui,"new-world:cancel").disabled, text_in(ui._body))
	authority.bad_id = true; authority.receipt = {"ok":true,"code":"OK","reason":"untrusted stale success"}
	activate(ui,"new-world:confirm"); authority.resolve.emit(); await flush()
	check("mismatched success receipt is never accepted", ui._new_world_receipt.code == "UNCONFIRMED" and not ui._new_world_receipt.ok and not ui.pages.is_empty() and not ui._notice.text.contains("untrusted stale success"), ui._notice.text)
	activate(ui,"new-world:confirm")
	var fresh := DeferredAuthority.new()
	ui.configure(fresh, null); ui.open_panel("pause")
	authority.resolve.emit(); await flush()
	check("reconfigured UI ignores old generation receipt", ui.runtime == fresh and not ui.world_starting and ui.pages.back().page == "pause" and ui._new_world_receipt.is_empty() and ui._notice.text.is_empty())
	activate(ui,"pause:new-world"); activate(ui,"new-world:confirm")
	var view_ref: WeakRef = weakref(ui)
	ui.get_parent().queue_free(); await flush()
	fresh.resolve.emit(); await flush()
	check("freed UI awaits through weak static continuation without error", view_ref.get_ref() == null and fresh.calls == 1)

func finish(code: int) -> void:
	if not output.is_empty():
		var report := {"ok":code == 0,"checks":checks,"observed_real_save_states":states,"fixture":"actual A save_async then start_new_world with default713 and C/B/codec/store; controlled save and UI-only readiness gates; no production 3D or OS acceptance","formal_application_launched":false,"physical_os_pointer":false,"route_acceptance":false,"visual_acceptance":false}
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	print("UI new-world checks " + str(checks.size()) + " exit " + str(code))
	quit(code)
