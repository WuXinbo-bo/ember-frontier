extends SceneTree
## Real A generation/store/runtime/router and native UI; only the 3D mount is omitted.
## Isolated files and preference writes, never a formal app or OS-input acceptance.
const Client = preload("res://scripts/runtime/native_client.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Playtest = preload("res://scripts/runtime/playtest_profile.gd")
const Modes = preload("res://scripts/ui/ui_work_modes.gd")

class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass

class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true

class UiClient extends Client:
	var mounts := 0
	var requested_seeds: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func start_new_world(seed: int = -1, request_id: String = "") -> Dictionary:
		requested_seeds.append(seed)
		return await super.start_new_world(seed, request_id)
	func _mount_ready(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		# Test UI/control lifecycle only; production terrain readiness belongs to A.
		return _mount(capture, assembly, fresh_profile)
	func _prepare_mount_ready(capture: Dictionary, assembly: Dictionary = {}) -> Dictionary:
		# Import now stages then activates. Keep its real coordinator/store, but
		# replace the scene/readiness boundary explicitly with a UI-only adapter.
		var built: Dictionary = _assemble(capture) if assembly.is_empty() else assembly
		if not built.get("ok", false): return built
		_world_epoch += 1
		await get_tree().process_frame
		return built.merged({"world_epoch":_world_epoch,"readiness":{"ready":true,"fixture":"UI-only controlled readiness"}},true)
	func _candidate_readiness(_candidate: Dictionary) -> Dictionary:
		return {"ready":true,"fixture":"UI-only controlled readiness"}
	func _activate_scene(candidate: Dictionary, fresh_profile: bool = false) -> Dictionary:
		return _mount(candidate.runtime.capture_checkpoint(),candidate,fresh_profile)
	func _discard_candidate(candidate: Dictionary) -> void:
		if candidate.get("runtime") != null: candidate.runtime.retire()
	func _mount(capture: Dictionary, assembly: Dictionary = {}, fresh_profile: bool = false) -> Dictionary:
		var built: Dictionary = _assemble(capture) if assembly.is_empty() else assembly
		if not built.get("ok", false): return built
		if router != null: router.queue_free()
		if ui != null: ui.get_parent().queue_free()
		world = built.world; runtime = built.runtime
		router = TestRouter.new(); add_child(router); router.configure(runtime, fresh_profile)
		ui = Mount.mount(self, runtime, router)
		mounts += 1
		return {"ok":true,"code":"OK"}

class DeferredAuthority extends RefCounted:
	signal changed(changes: Dictionary)
	signal resolve
	var state := {"ready":true,"busy":false,"status":"unsaved","reason":"尚未手动保存"}
	var seeds: Array = []
	func snapshot() -> Dictionary: return {"save":state.duplicate(true)}
	func save_async(id: String = "") -> Dictionary:
		return {"ok":true,"code":"OK","reason":"controlled preserve fixture","request_id":id}
	func start_new_world(seed: int = -1, id: String = "") -> Dictionary:
		seeds.append(seed)
		state.merge({"busy":true,"status":"generating","reason":"受控等待生成回执"}, true)
		changed.emit({"save":true})
		await resolve
		state.merge({"busy":false,"status":"failed","reason":"受控生成失败"}, true)
		changed.emit({"save":true})
		return {"ok":false,"code":"GENERATION_TEST","reason":"受控生成失败","request_id":id}

var checks: Array = []
var output := ""
var host: UiClient

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("basic actions UI timeout"); finish(2))
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
		var found := by_key(child, key)
		if found != null: return found
	return null

func text_in(node: Node) -> String:
	var value: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): value += text_in(child)
	return value

func activate(ui: Control, key: String) -> void:
	var target := by_key(ui, key) as Button
	check("enabled control " + key, target != null and not target.disabled)
	if target != null and not target.disabled: target.pressed.emit()

func key(code: Key, pressed: bool, shift: bool = false, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code
	event.pressed = pressed; event.shift_pressed = shift; event.ctrl_pressed = ctrl
	root.push_input(event, true)
	await flush()

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	await seed_validation()
	host = UiClient.new(); root.add_child(host)
	host.store = Store.new(output + "/isolated-saves")
	var legacy: Dictionary = host._new_rural(713)
	check("actual legacy world assembles without 3D preview", legacy.get("ok", false), legacy)
	if not legacy.get("ok", false): finish(1); return
	await flush()
	var old: Dictionary = await host.save_async("ui-basic:old-explicit-save")
	check("legacy fixture explicitly saves through real coordinator", old.get("ok", false), old)
	var pointer := output + "/isolated-saves/active.json"
	var old_pointer := FileAccess.get_file_as_bytes(pointer)
	var old_slot: Dictionary = JSON.parse_string(old_pointer.get_string_from_utf8())
	var old_path := output + "/isolated-saves/" + str(old_slot["namespace"]) + "/" + str(old_slot.slot) + ".json"
	var old_bytes := FileAccess.get_file_as_bytes(old_path)
	var ui: Control = host.ui
	ui.open_panel("pause"); activate(ui, "pause:new-world"); await flush()
	check("legacy current world also gets preserve-first warning", text_in(ui._body).contains("先保存当前世界") and text_in(ui._body).contains("旧世界存档独立保留"))
	check("default seed is 713 and cancellation owns safe focus", (by_key(ui,"new-world:seed") as LineEdit).text == "713" and root.gui_get_focus_owner() == by_key(ui,"new-world:cancel"))
	var serial: int = ui._serial
	activate(ui,"new-world:cancel")
	check("cancel sends no request and leaves real saves unchanged", ui._serial == serial and host.requested_seeds.is_empty() and FileAccess.get_file_as_bytes(pointer) == old_pointer)
	activate(ui,"pause:new-world"); activate(ui,"new-world:confirm")
	while host.requested_seeds.is_empty() and ui.world_starting: await process_frame
	check("default UI forwards 713 after preserve save", host.requested_seeds == [713] and ui.world_starting, host.requested_seeds.duplicate())
	old_pointer = FileAccess.get_file_as_bytes(pointer)
	ui.refresh()
	check("generating state is authoritative and actions are disabled", host._save_state.status == "generating" and host._save_state.busy and by_key(ui,"new-world:confirm").disabled and by_key(ui,"new-world:cancel").disabled and not (by_key(ui,"new-world:seed") as LineEdit).editable)
	ui.confirm_new_world(); ui.save_world(); ui.cancel_ui()
	check("busy generation cannot repeat save or resume", host.requested_seeds.size() == 1 and host.router.is_paused() and ui.pages.back().page == "new_world")
	while host._world_loading: await process_frame
	await flush()
	ui = host.ui
	check("actual generation remounts once and retains preserved world active", host.mounts == 2 and host._save_state.status == "unsaved" and FileAccess.get_file_as_bytes(pointer) == old_pointer and FileAccess.get_file_as_bytes(old_path) == old_bytes)
	check("fresh status describes unsaved world without claiming saved", ui._storage_status.visible and ui._storage_status.text.contains("尚未保存") and ui._storage_status.tooltip_text == host._save_state.reason and not ui._storage_status.text.contains("已保存"), ui._storage_status.text)
	var snapshot: Dictionary = host.runtime.snapshot()
	check("actual profile is recognized by published id without enabled flag", P.playtest_profile(snapshot).get("id") == "ready-to-test-v1" and not snapshot.playtest.has("enabled") and snapshot.playtest.automatic_save == false)
	var entries := P.entries(P.player_stock(snapshot), snapshot)
	var tools := entries.filter(func(row: Dictionary): return row.reference.kind == "tool")
	check("five actual uniquely held tools exist in player's native grid", tools.size() == Playtest.TOOL_KINDS.size() and tools.all(func(row: Dictionary): return row.available == 1 and row.durability == 100), tools)
	for kind: String in Playtest.TOOL_KINDS:
		check("actual tool identity and owner " + kind, host.runtime.tool("playtest:player:" + kind).get("holderId") == "pack:player")
	check("actual fresh hotbar selects shovel and finite consumables", host.router.state().selected == 1 and host.router.held_reference().id == "playtest:player:shovel" and host.router.state().slots == Playtest.slots())
	for id: String in Playtest.ITEMS:
		check("actual finite starter item " + id, host.runtime.actor("player").pack.get(id) == Playtest.ITEMS[id])
	check("profile HUD has one identity label and no invented seed", ui._profile_hint.text == snapshot.playtest.label and not ui._profile_hint.text.contains("种子"), ui._profile_hint.text)
	ui.open_panel("pause"); await flush()
	var content := text_in(ui._body)
	check("pause discloses exact initial supplies and explicit recovery", content.contains("并非当前余量") and content.contains("木料 × 12") and content.contains("土方 × 2.0 m³") and content.contains("--continue") and (by_key(ui,"pause:import") as Button).text.contains("恢复存档文件"), content)
	var before: Dictionary = host.runtime.capture_checkpoint()
	ui.refresh(); ui.configure(host.runtime, host.router); ui.refresh()
	check("reconfiguration does not grant tools or alter authoritative world", Data.json_equal(before, host.runtime.capture_checkpoint()))
	await input_and_feedback()
	await movement_route_case()
	await geometry_cases()
	ui = host.ui
	ui.open_panel("pause")
	var good_store: RefCounted = host.store
	var blocker := FileAccess.open(output + "/blocked-parent", FileAccess.WRITE)
	blocker.store_string("Explicit isolated manual-save failure fixture"); blocker.close()
	host.store = Store.new(output + "/blocked-parent/saves")
	var unsaved: Dictionary = host.runtime.capture_checkpoint()
	await ui.save_world(); ui.refresh()
	check("real manual save failure leaves new world unsaved and retryable", host._save_state.status == "failed" and not ui.saving and not by_key(ui,"pause:save").disabled and ui._notice.text.contains("目录"), ui._notice.text)
	check("failed manual save preserves real live world old pointer and old bytes", Data.json_equal(unsaved,host.runtime.capture_checkpoint()) and old_pointer == FileAccess.get_file_as_bytes(pointer) and old_bytes == FileAccess.get_file_as_bytes(old_path))
	host.store = good_store
	await ui.save_world()
	var saved_pointer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pointer))
	check("only explicit manual save creates fresh namespace", host._save_state.status == "saved" and saved_pointer["namespace"] != old_slot["namespace"] and old_bytes == FileAccess.get_file_as_bytes(old_path), saved_pointer)
	var saved_path := output + "/isolated-saves/" + str(saved_pointer["namespace"]) + "/" + str(saved_pointer.slot) + ".json"
	var captured: Dictionary = host.store.load_current()
	check("real manual slot has one profile and exactly five player tools", captured.get("ok",false) and captured.capture.source.playtest.id == "ready-to-test-v1" and captured.capture.world.extensions["r3:production"].tools.filter(func(row: Dictionary): return row.holderId == "pack:player").size() == 5)
	ui._file_operation = "import"
	ui._file_selected(saved_path)
	check("actual staged import publishes loading before any UI remount",host._saving and host._world_loading and host._save_state.status=="loading" and host._save_state.busy and ui.importing and host.mounts==2)
	while host._saving: await process_frame
	await flush()
	check("explicit UI file recovery mounts validated real saved authority", host.mounts == 3 and host.runtime.snapshot().playtest.id == "ready-to-test-v1" and P.entries(P.player_stock(host.runtime.snapshot()),host.runtime.snapshot()).filter(func(row: Dictionary): return row.reference.kind == "tool").size() == 5,{"mounts":host.mounts,"save":host._save_state.duplicate(true)})
	check("recovery retains old slot and does not issue another fresh world", old_bytes == FileAccess.get_file_as_bytes(old_path) and host.requested_seeds == [713])
	host.queue_free(); await flush()
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func seed_validation() -> void:
	var authority := DeferredAuthority.new()
	var ui: Control = Mount.mount(root,authority,null)
	ui.open_panel("pause"); ui.choose_new_world(); await flush()
	var field := by_key(ui,"new-world:seed") as LineEdit
	for invalid: String in ["abc","-1","2147483648","1.2"]:
		field.text = invalid; field.text_changed.emit(invalid)
		ui.confirm_new_world()
		check("invalid native seed cannot submit " + invalid, not ui.new_world_seed_reason().is_empty() and by_key(ui,"new-world:confirm").disabled and authority.seeds.is_empty())
	field.text = "2026"; field.text_changed.emit("2026")
	check("valid fixed seed re-enables without destroying text focus", not by_key(ui,"new-world:confirm").disabled and ui._new_world_seed_text == "2026")
	ui.confirm_new_world(); await flush()
	check("fixed input forwards exact requested integer", authority.seeds == [2026] and ui.world_starting)
	authority.resolve.emit(); await flush()
	check("actual failed receipt leaves retry and editable retained seed", not ui.world_starting and ui.pages.back().page == "new_world" and text_in(ui._body).contains("受控生成失败") and (by_key(ui,"new-world:seed") as LineEdit).text == "2026" and not by_key(ui,"new-world:confirm").disabled)
	ui.get_parent().queue_free(); await flush()

func input_and_feedback() -> void:
	var ui: Control = host.ui
	var router: TestRouter = host.router
	router.reset_bindings(); ui.close_panels(); await flush()
	await key(KEY_SHIFT,true,true); await key(KEY_W,true,true)
	check("real router accepts Shift then W independently", router.state().held.run and router._pressed.has("up"))
	await key(KEY_SHIFT,false)
	check("Shift release clears run without cancelling held W", not router.state().held.run and router._pressed.has("up"))
	ui.open_panel("inventory")
	check("modal releases movement and pauses single runtime", router.is_paused() and router._pressed.is_empty() and host.runtime.is_paused())
	ui.close_panels(); await key(KEY_W,false); await key(KEY_SHIFT,true,true)
	router.set_window_focus(false); ui._on_focus_exited()
	check("real focus boundary releases held run and no automatic resume", not router.state().held.run and router._pressed.is_empty() and router.is_paused())
	router.set_window_focus(true)
	check("focus return requires a fresh run press", not router.state().held.run and not router.is_paused())
	ui.open_panel("settings"); ui.capture_action = "run"
	await key(KEY_F,true); await key(KEY_F,false)
	check("native UI run capture remaps actual physical router binding", ui.capture_action.is_empty() and int(router.state().bindings.run.keycode) == KEY_F and not router.state().held.run)
	ui.close_panels(); await key(KEY_F,true)
	check("remapped run action is held through real viewport input", router.state().held.run)
	await key(KEY_F,false); ui.open_panel("settings"); ui.capture_action = "run"
	await key(KEY_SHIFT,true,true); await key(KEY_SHIFT,false)
	check("bare Shift restores without Shift plus Shift packing", ui.capture_action.is_empty() and int(router.state().bindings.run.keycode) == KEY_SHIFT)
	ui.capture_action = "run"; await key(KEY_SHIFT,true,true,true); await key(KEY_SHIFT,false)
	check("modified Shift is not silently reduced to bare Shift", ui.capture_action == "run" and ui._notice.text.contains("保留") and int(router.state().bindings.run.keycode) == KEY_SHIFT)
	ui.capture_action = ""; activate(ui,"bind:reset"); ui.close_panels(); await flush()
	var data: Dictionary = host.runtime.snapshot()
	data.hand = router.state()
	check("runtime stamina maximum is shown from actual projection", ui._need_labels.stamina.label.text.ends_with(" / " + ui._hud_number(P.player_movement(data).stamina_max)), ui._need_labels.stamina.label.text)
	var cap_fixture := data.duplicate(true)
	cap_fixture.movement = {"npc-only":{"moving":true,"mode":"run","speed":99}}
	check("other actor motion is never substituted as player movement", P.player_movement(cap_fixture).is_empty())
	cap_fixture.movement = {"player":{"moving":true,"mode":"run","speed":3.25,"stamina_max":61,"can_run":true,"reason":null}}
	check("explicit display contract uses supplied speed with real binding", P.movement_text(cap_fixture).contains("跑步中") and P.movement_text(cap_fixture).contains("3.25 m/s") and P.movement_text(cap_fixture).contains(P.binding_label(router.state().bindings.run)))
	cap_fixture.movement.player.merge({"moving":false,"can_run":false,"reason":"体力不足，改为步行"},true)
	check("run exhaustion is walk fallback rather than collision", P.movement_text(cap_fixture).contains("改为步行") and not P.movement_text(cap_fixture).contains("受阻"))
	ui.notify("")
	var baseline: Dictionary = host.runtime.capture_checkpoint()
	host.runtime.set_target({"id":"terrain:far-test","kind":"terrain","primary":"terrain","name":"挖掘","enabled":false,"reason":"UNREACHABLE"})
	ui.refresh()
	check("distant mouse target remains a neutral local precheck", ui._target_text.text.contains("目标暂不可操作") and ui._notice.text.is_empty() and not ui._movement_hint.text.contains("受阻") and ui._movement_feedback.is_empty(), ui._target_text.text)
	ui.report_action({"ok":false,"code":"MISSING_TOOL","reason":"MISSING_TOOL"})
	check("attempted tool rejection is action feedback and no movement failure", ui._notice.text.begins_with("操作未完成") and ui._notice.text.contains("铲／镐") and not ui._movement_hint.text.contains("受阻"))
	ui.report_movement({"ok":false,"code":"BLOCKED","reason":"测试身体通路被墙体挡住"}); ui.refresh()
	check("explicit movement callback is independently scoped with reason", ui._movement_hint.text.contains("移动受阻 · 测试身体通路被墙体挡住") and ui._movement_hint.tooltip_text.contains("BLOCKED"))
	var failure_serial: int = ui._movement_feedback_serial
	for index in 100: ui.report_movement({"ok":false,"code":"BLOCKED","reason":"测试身体通路被墙体挡住"})
	check("repeated per-frame identical failures reuse one feedback lifetime",ui._movement_feedback_serial == failure_serial)
	ui.report_movement({"ok":true,"code":"OK"}); ui.refresh()
	check("successful movement receipt clears scoped failure", ui._movement_feedback.is_empty() and not ui._movement_hint.text.contains("受阻"))
	var cleared_serial: int = ui._movement_feedback_serial
	for index in 100: ui.report_movement({"ok":true,"code":"OK"})
	check("successful movement frames do not refresh unchanged UI",ui._movement_feedback_serial == cleared_serial)
	ui.notify("old transient failure",true); ui.notify("新的真实受理回执")
	ui.report_movement({"ok":false,"code":"UNSUPPORTED","reason":"测试落脚点缺少支撑"})
	await create_timer(4.1,true).timeout; await flush()
	check("expired movement feedback clears and stale notice timer preserves new receipt", ui._movement_feedback.is_empty() and ui._notice.text == "新的真实受理回执")
	check("all view feedback leaves actual inventory time and intents unchanged", Data.json_equal(baseline,host.runtime.capture_checkpoint()))
	check("direct terrain use still needs no new object menu", Modes.mode_hint(router.state()).contains("按住左键挖掘") and ui.pages.is_empty())
	host.runtime.set_target({})

func movement_route_case() -> void:
	# A separate explicit actor-position fixture in the old saved world. Actual
	# A/B/C movement validation and direct adapter remain unmodified.
	var saved: Dictionary = host.store.load_current()
	var capture: Dictionary = saved.capture.duplicate(true)
	for actor: Dictionary in capture.facts.actors:
		if actor.id == "player":
			actor.merge({"x":27.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"intent":null,"fatigue":40.0,"stamina":60.0},true)
	var assembly: Dictionary = host._assemble(capture)
	check("explicit old-world movement fixture validates through actual assembler",assembly.get("ok",false),assembly.get("reason"))
	if not assembly.get("ok",false): return
	var parent := Node3D.new(); root.add_child(parent)
	var router := TestRouter.new(); parent.add_child(router); router.configure(assembly.runtime); router.reset_bindings()
	var ui: Control = Mount.mount(parent,assembly.runtime,router)
	var camera := Camera3D.new(); parent.add_child(camera)
	var pointer := Pointer.new(); parent.add_child(pointer)
	pointer.runtime=assembly.runtime; pointer.world=assembly.world; pointer.router=router; pointer.ui=ui; pointer.camera=camera; pointer.buildings=assembly.services.buildings
	await flush()
	var invalid: Dictionary = assembly.runtime.facts()
	for actor: Dictionary in invalid.actors:
		if actor.id=="player":actor.x=9999.0;actor.z=9999.0
	var configured: Dictionary=assembly.runtime.configure(host._context(assembly.world,assembly.services,invalid,capture.source))
	check("explicit outside-generated-world rejection fixture configures",configured.get("ok",false))
	ui.notify(""); var before: Dictionary=assembly.runtime.capture_checkpoint()
	pointer._move(Vector2.RIGHT,0.1); ui.refresh()
	check("actual failed direct move reaches scoped UI callback without generic notice",not ui._movement_feedback.is_empty() and ui._movement_hint.text.contains("移动受阻") and ui._movement_hint.text.contains("已生成世界之外") and ui._notice.text.is_empty(),{"feedback":ui._movement_feedback,"movement":ui._movement_hint.text})
	check("actual rejected movement leaves world inventory time and actor unchanged",Data.json_equal(before,assembly.runtime.capture_checkpoint()))
	# Restore the explicit valid fixture, keeping the adapter's real last
	# failure state. A only forwards failure/success transitions.
	assembly.runtime.configure(host._context(assembly.world,assembly.services,capture.facts,capture.source))
	var actor_before: Dictionary = assembly.runtime.actor("player")
	pointer._move(Vector2.RIGHT,0.1); ui.refresh()
	var actor_after: Dictionary = assembly.runtime.actor("player")
	var movement: Dictionary = P.player_movement(assembly.runtime.snapshot())
	check("actual direct move clears failure only after real successful displacement", float(actor_after.x)>float(actor_before.x) and ui._movement_feedback.is_empty() and movement.moving and movement.mode=="walk", {"from":actor_before.x,"to":actor_after.x,"movement":movement,"feedback":ui._movement_feedback})
	check("HUD reads real movement speed and fatigue-derived stamina cap", ui._movement_hint.text.contains("步行中") and ui._movement_hint.text.contains(P.number(movement.speed)+" m/s") and ui._need_labels.stamina.label.text.ends_with(" / "+ui._hud_number(movement.stamina_max)), {"movement":ui._movement_hint.text,"stamina":ui._need_labels.stamina.label.text})
	parent.queue_free(); await flush()

func geometry_cases() -> void:
	var ui: Control = host.ui
	for size: Vector2i in [Vector2i(1000,700),Vector2i(1280,800)]:
		for scale_factor: float in [1.0,1.5]:
			root.content_scale_size = size; root.size = size
			ui.set_text_scale(scale_factor); ui.close_panels(); await flush()
			check("HUD fits above hotbar " + str(size) + " " + str(scale_factor), ui._hud_backdrop.get_global_rect().end.y < ui._hotbar.get_global_rect().position.y and ui._hud_backdrop.get_global_rect().end.x <= size.x, {"hud":str(ui._hud_backdrop.get_global_rect()),"hotbar":str(ui._hotbar.get_global_rect())})
			ui.report_movement({"ok":false,"code":"UNSUPPORTED","reason":"脚下支撑或台阶高度不合法，请绕到有支撑的同侧地面"}); ui.refresh(); await flush()
			check("actual failure HUD preserves hotbar space " + str(size) + " " + str(scale_factor), ui._movement_hint.visible and not ui._mode_hint.visible and ui._hud_backdrop.get_global_rect().end.y < ui._hotbar.get_global_rect().position.y,{"hud":str(ui._hud_backdrop.get_global_rect()),"hotbar":str(ui._hotbar.get_global_rect())})
			ui.report_movement({"ok":true}); ui.refresh(); await flush()
			ui.open_panel("pause"); ui.choose_new_world(); await flush()
			check("new-world native input and actions fit dialog " + str(size) + " " + str(scale_factor), ui._body.get_combined_minimum_size().x <= ui._scroll.size.x + 1 and ui._scroll.get_global_rect().encloses(by_key(ui,"new-world:confirm").get_global_rect()) and ui._scroll.get_global_rect().encloses(by_key(ui,"new-world:seed").get_global_rect()), {"body":str(ui._body.get_combined_minimum_size()),"scroll":str(ui._scroll.get_global_rect()),"confirm":str(by_key(ui,"new-world:confirm").get_global_rect())})
			ui.close_panels()
	root.content_scale_size = Vector2i(1280,800); root.size = Vector2i(1280,800)
	ui.set_text_scale(1.0); await flush()

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"formal_application_launched":false,"physical_os_pointer":false,"route_acceptance":false,"visual_acceptance":false,"fixture":"Actual A native coordinator/store/generation/runtime/router and UI, 3D mount omitted; isolated storage and no preference writes; controlled seed-failure and movement-feedback contract cases explicitly labelled"},"\t",true,true))
		file.close()
	print("Basic actions UI checks " + str(checks.size()) + " exit " + str(code))
	quit(code)
