extends SceneTree
## Actual A native restore/store/validation with a UI-only mount adapter.
## No formal app, 3D scene, user saves or physical OS-input acceptance.
const Client = preload("res://scripts/runtime/native_client.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Playtest = preload("res://scripts/runtime/playtest_profile.gd")
const Data = preload("res://scripts/world/world_data.gd")
const P = preload("res://scripts/ui/ui_projection.gd")

class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true

class RestoreHost extends Client:
	signal release_ui_mount
	var mounts := 0
	var restore_ids: Array = []
	var restore_inflight := false
	var gate_ui_mount := false
	var ui_mount_waiting := false
	var ui_mount_failure: Dictionary = {}
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func restore_saved_world(id: String = "") -> Dictionary:
		restore_ids.append(id)
		restore_inflight = true
		var receipt: Dictionary = await super.restore_saved_world(id)
		restore_inflight = false
		return receipt
	func _mount_ready(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		# Explicit UI-only adapter: do not exercise or claim production 3D readiness.
		if gate_ui_mount:
			ui_mount_waiting = true
			await release_ui_mount
			ui_mount_waiting = false
			gate_ui_mount = false
		if not ui_mount_failure.is_empty():
			var failure := ui_mount_failure.duplicate(true)
			ui_mount_failure.clear()
			return failure
		return _mount(capture, assembly, fresh_profile)
	func _mount(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		var built: Dictionary = _assemble(capture) if assembly.is_empty() else assembly
		if not built.get("ok", false): return built
		if router != null: router.queue_free()
		if ui != null: ui.get_parent().queue_free()
		world = built.world; runtime = built.runtime
		router = TestRouter.new(); add_child(router); router.configure(runtime,fresh_profile)
		ui = Mount.mount(self,runtime,router)
		mounts += 1
		return {"ok":true,"code":"OK"}

class DeferredAuthority extends RefCounted:
	signal changed(changes: Dictionary)
	signal resolve
	var save := {"ready":true,"busy":false,"status":"unsaved","reason":"受控未保存地图"}
	var calls := 0
	var bad_id := true
	func snapshot() -> Dictionary: return {"save":save.duplicate(true)}
	func restore_saved_world(id: String = "") -> Dictionary:
		calls += 1
		await resolve
		return {"ok":true,"code":"OK","reason":"controlled receipt","request_id":"stale" if bad_id else id}

var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("restore saved UI timeout"); finish(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok: push_error(name + " " + str(detail))

func flush() -> void:
	await process_frame
	await process_frame

func by_key(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("ui_focus_key", "") == key: return node
	for child in node.get_children():
		var result := by_key(child,key)
		if result != null: return result
	return null

func text_in(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += text_in(child)
	return result

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var host := RestoreHost.new(); root.add_child(host)
	host.store = Store.new(output + "/isolated-saves")
	var setup: Dictionary = host._new_rural(713)
	check("real old rural world assembles without preview",setup.get("ok",false),setup)
	if not setup.get("ok",false): finish(1); return
	# Explicit test-profile fixture, using A's actual fresh constructor once.
	var fresh: Dictionary = Playtest.apply(host.runtime.capture_checkpoint())
	check("actual A profile mounts in isolated UI fixture",host._mount(fresh,{},true).get("ok",false))
	await flush()
	var saved: Dictionary = await host.save_async("ui-restore:manual")
	check("real manual save exists before testing restoration",saved.get("ok",false),saved)
	var pointer := output + "/isolated-saves/active.json"
	var pointer_bytes := FileAccess.get_file_as_bytes(pointer)
	var loaded: Dictionary = host.store.load_current()
	var slot_bytes := FileAccess.get_file_as_bytes(loaded.path)
	var original_tools: Array = loaded.capture.world.extensions["r3:production"].tools
	var ui: Control = host.ui
	var drink: Dictionary = ui.execute("drink","",{},true)
	for index in 14:host.runtime.tick(0.1)
	check("real unsaved play changes one water without saving",drink.get("ok",false) and host.runtime.actor("player").pack.water == 3 and FileAccess.get_file_as_bytes(pointer)==pointer_bytes)
	ui.open_panel("pause"); await flush()
	var action := by_key(ui,"pause:restore-saved") as Button
	check("visible pause action and local loss warning require no extra confirmation",action != null and not action.disabled and action.text=="恢复上次手动保存" and text_in(ui._body).contains("当前未保存的测试进度不保留") and ui.pages.size()==1)
	check("continue command and external file restore remain distinct",text_in(ui._body).contains("--continue") and by_key(ui,"pause:import") != null)
	var old_view: WeakRef = weakref(ui)
	var old_runtime: RefCounted = host.runtime
	var mounts_before: int = host.mounts
	host.gate_ui_mount=true
	action.pressed.emit()
	await flush()
	check("actual restore publishes loading until the test-only mount gate releases",host.restore_inflight and host.ui_mount_waiting and host._save_state.busy and host._save_state.status=="loading" and ui.world_restoring and ui._storage_status.text==host._save_state.reason)
	var serial: int=ui._serial
	ui.restore_saved_world();ui.choose_new_world();ui.save_world();ui.open_panel("inventory");ui.cancel_ui()
	check("actual yielded restore rejects duplicates and keeps original pause route",host.restore_ids.size()==1 and ui._serial==serial and ui.pages.back().page=="pause" and host.runtime==old_runtime and host.router.is_paused() and not ui._file_dialog.visible)
	host.release_ui_mount.emit()
	while host.restore_inflight: await process_frame
	await flush()
	check("one click awaits real restore and mounts exactly once",host.restore_ids.size()==1 and host.mounts==mounts_before+1 and host.runtime!=old_runtime,host.restore_ids.duplicate())
	check("remounted view disposes old UI safely and resumes scene",old_view.get_ref()==null and host.ui.pages.is_empty() and not host.ui.world_restoring and not host.router.is_paused())
	check("new view reads final restored status after awaited UI-only mount",host.ui._storage_status.visible and host.ui._storage_status.text==host._save_state.reason and host._save_state.status=="restored",host.ui._storage_status.text)
	check("restore returns saved water and time without retaining unsaved changes",host.runtime.actor("player").pack.water==4 and host.runtime.clock()==float(loaded.capture.facts.time))
	check("restore does not grant duplicate tools or alter unique holders",Data.json_equal(original_tools,host.world.extension("r3:production").tools) and P.entries(P.player_stock(host.runtime.snapshot()),host.runtime.snapshot()).filter(func(row: Dictionary):return row.reference.kind=="tool").size()==5)
	check("restore does not write a new save or change active bytes",FileAccess.get_file_as_bytes(pointer)==pointer_bytes and FileAccess.get_file_as_bytes(loaded.path)==slot_bytes)
	ui=host.ui; ui.open_panel("pause"); await flush()
	check("pause displays actual restored reason",text_in(ui._body).contains("已明确恢复上次手动保存"))
	var good_store: RefCounted = host.store
	var baseline: Dictionary = host.runtime.capture_checkpoint()
	var authority: RefCounted = host.runtime
	var count: int = host.mounts
	host.gate_ui_mount=true
	host.ui_mount_failure={"ok":false,"code":"WORLD_READY_TIMEOUT","reason":"受控UI挂载门超时，原现场保留"}
	ui.restore_saved_world();await flush()
	check("failed-mount fixture first observes real coordinator loading",host.restore_inflight and host.ui_mount_waiting and ui.world_change_busy() and host._save_state.status=="loading")
	host.release_ui_mount.emit()
	while host.restore_inflight:await process_frame
	await flush()
	check("readiness refusal preserves old authority and releases UI busy lock",host.runtime==authority and host.mounts==count and not host._save_state.busy and host._save_state.status=="failed" and not ui.world_restoring and not ui.world_change_busy() and ui._notice.text.contains("原现场保留") and not ui._back_button.disabled,ui._notice.text)
	check("readiness refusal leaves live facts and saved bytes exactly intact",Data.json_equal(baseline,host.runtime.capture_checkpoint()) and pointer_bytes==FileAccess.get_file_as_bytes(pointer) and slot_bytes==FileAccess.get_file_as_bytes(loaded.path))
	ui.close_panels();await flush()
	check("readiness rollback can return to the old playable authority",ui.pages.is_empty() and not host.router.is_paused() and not host.runtime.is_paused())
	ui.open_panel("pause");await flush()
	host.store=Store.new(output+"/no-saves")
	ui.restore_saved_world(); await flush()
	check("actual NO_SAVE failure remains in current world and permits retry",host.runtime==authority and host.mounts==count and not ui.world_restoring and ui.pages.back().page=="pause" and ui._notice.text.contains("尚无原生存档") and not by_key(ui,"pause:restore-saved").disabled,ui._notice.text)
	check("missing save leaves exact live authority and existing saved bytes",Data.json_equal(baseline,host.runtime.capture_checkpoint()) and pointer_bytes==FileAccess.get_file_as_bytes(pointer))
	var invalid_dir := output+"/invalid-index"
	DirAccess.make_dir_recursive_absolute(invalid_dir)
	var invalid := FileAccess.open(invalid_dir+"/active.json",FileAccess.WRITE)
	invalid.store_string("explicit invalid checkpoint fixture");invalid.close()
	host.store=Store.new(invalid_dir)
	ui.restore_saved_world(); await flush()
	check("real invalid index reason is shown without replacing current world",ui._notice.text.contains("存档索引无效") and host.runtime==authority and host.mounts==count and Data.json_equal(baseline,host.runtime.capture_checkpoint()),ui._notice.text)
	check("failed restore never edits corrupt source or valid old save",FileAccess.get_file_as_string(invalid_dir+"/active.json")=="explicit invalid checkpoint fixture" and slot_bytes==FileAccess.get_file_as_bytes(loaded.path))
	host.store=good_store
	host._closing=true
	ui.restore_saved_world(); await flush()
	check("actual native BUSY rejects hidden close race and releases UI lock",ui._notice.text.contains("保存或世界装配进行中") and not ui.world_restoring and host.runtime==authority and host.mounts==count,ui._notice.text)
	host._closing=false
	var calls: int=host.restore_ids.size()
	host._save_state.merge({"busy":true,"status":"saving","reason":"external live save fixture"},true);ui.refresh()
	check("authoritative save busy disables restore button",by_key(ui,"pause:restore-saved").disabled)
	ui.restore_saved_world()
	check("live recheck prevents a stale restore event from calling runtime",host.restore_ids.size()==calls and not ui.world_restoring)
	host._save_state.merge({"busy":false,"status":"restored","reason":"fixture released"},true);ui.refresh()
	ui._file_operation="import";ui.restore_saved_world();ui._file_operation=""
	check("active file chooser prevents concurrent last-save restoration",host.restore_ids.size()==calls)
	for size: Vector2i in [Vector2i(1000,700),Vector2i(1280,800)]:
		for scale_factor: float in [1.0,1.5]:
			root.content_scale_size=size;root.size=size;ui.set_text_scale(scale_factor);await flush()
			var restore := by_key(ui,"pause:restore-saved")
			check("restore action remains on initial pause viewport "+str(size)+" "+str(scale_factor),ui._scroll.get_global_rect().encloses(restore.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"button":str(restore.get_global_rect()),"scroll":str(ui._scroll.get_global_rect())})
	check("failed and busy attempts never save current map or mutate valid slot",pointer_bytes==FileAccess.get_file_as_bytes(pointer) and slot_bytes==FileAccess.get_file_as_bytes(loaded.path) and Data.json_equal(baseline,host.runtime.capture_checkpoint()))
	host.queue_free();await flush()
	await lifecycle_cases()
	finish(0 if checks.all(func(row: Dictionary):return row.ok) else 1)

func lifecycle_cases() -> void:
	var authority := DeferredAuthority.new()
	var ui: Control = Mount.mount(root,authority,null)
	ui.open_panel("pause");ui.restore_saved_world();await flush()
	var serial: int=ui._serial
	ui.restore_saved_world();ui.save_world();ui.choose_new_world();ui.choose_import();ui.close_panels();ui.cancel_ui()
	check("controlled yielded restore locks duplicate requests and navigation",ui.world_restoring and authority.calls==1 and ui._serial==serial and ui.pages.back().page=="pause" and by_key(ui,"pause:restore-saved").disabled and ui._back_button.disabled)
	authority.resolve.emit();await flush()
	check("wrong-id OK is not accepted as restored",not ui.world_restoring and ui.pages.back().page=="pause" and ui._notice.text.contains("未收到匹配本次请求") and not ui._notice.text.contains("controlled receipt"))
	ui.restore_saved_world();await flush()
	ui.configure(authority,null);ui.notify("new generation receipt")
	authority.resolve.emit();await flush()
	check("old pending receipt cannot write after UI configure generation changes",not ui.world_restoring and ui._notice.text=="new generation receipt")
	ui.open_panel("pause");ui.restore_saved_world();await flush()
	var gone: WeakRef=weakref(ui)
	ui.get_parent().queue_free();await flush();authority.resolve.emit();await flush()
	check("late restore receipt safely ignores a freed UI",gone.get_ref()==null)

func finish(code: int) -> void:
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"formal_application_launched":false,"route_acceptance":false,"visual_acceptance":false,"fixture":"Actual A async restore/store/validation/runtime/router and native UI, explicit test profile over legacy rural fixture; UI-only mount with a controlled await/failure gate, no 3D readiness validation; isolated saved files and no preference writes; late receipt cases are controlled lifecycle fixtures"},"\t",true,true));file.close()
	print("Restore saved UI checks "+str(checks.size())+" exit "+str(code));quit(code)
