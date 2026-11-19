extends SceneTree
## Controlled async callbacks + actual native recovery and in-game Controls.
## No storage scanning, actual world readiness, OS or PCK acceptance here.
const Mount = preload("res://scripts/ui/ui_mount.gd")
const ThemeFactory = preload("res://scripts/ui/ui_theme.gd")
class Calls extends RefCounted:
	signal resolved(receipt: Dictionary)
	var requests: Array = []
	var fresh_calls := 0
	func choose(id: String, sha: String) -> Dictionary:
		requests.append([id, sha])
		var receipt: Dictionary = await resolved
		return receipt
	func fresh() -> Dictionary:
		fresh_calls += 1
		var receipt: Dictionary = await resolved
		return receipt
class Authority extends RefCounted:
	signal changed(value: Dictionary)
	signal resolved(receipt: Dictionary)
	var rows: Array = []
	var save := {"ready":true,"busy":false,"status":"saved"}
	var lists := 0
	var requests: Array = []
	var commands := 0
	var saves := 0
	var wrong_id := true
	func snapshot() -> Dictionary: return {"revision":1,"command_revision":1,"player":{"id":"player","hp":100},"save":save.duplicate(true)}
	func list_recovery_candidates(_world_id: String = "") -> Dictionary:
		lists += 1
		return {"ok":true,"code":"OK","candidates":rows.duplicate(true)}
	func restore_recovery_candidate(id: String, sha: String, request_id: String = "") -> Dictionary:
		requests.append([id, sha, request_id])
		save.merge({"busy":true,"status":"loading"}, true); changed.emit({"save":true})
		var receipt: Dictionary = await resolved
		save.merge({"busy":false,"status":"failed"}, true); changed.emit({"save":true})
		return receipt.merged({"request_id":"old-request" if wrong_id else request_id}, true)
	func availability(_request: Dictionary) -> Dictionary: return {"ok":true,"code":"OK"}
	func command(_request: Dictionary) -> Dictionary: commands += 1; return {"ok":true,"code":"OK"}
	func save_async(_request_id: String = "") -> Dictionary: saves += 1; return {"ok":true,"code":"OK"}
class Router extends RefCounted:
	signal changed
	var modal := false
	func state() -> Dictionary: return {"mode":"tool","bindings":{},"slots":[]}
	func set_modal(value: bool) -> void: modal = value
	func set_file_dialog(_value: bool) -> void: pass

var checks: Array = []
var output := ""
func _initialize() -> void:
	create_timer(15).timeout.connect(func(): finish(2))
	call_deferred("run")
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail}); print(("PASS " if ok else "FAIL ") + name)
func flush() -> void:
	await process_frame; await process_frame
func key(node: Node, value: String) -> Control:
	if node is Control and node.get_meta("ui_focus_key", "") == value: return node
	for child in node.get_children():
		var result := key(child, value)
		if result != null: return result
	return null
func rows() -> Array:
	return [{"candidate_id":"b/a","namespace":"b","slot":"a","sha256":"a".repeat(64),"world_id":"world:second","seed":2026,"checkpoint_id":"cp:5","command_revision":5,"time":12.25,"requires_assembly_validation":true},{"candidate_id":"a/b","namespace":"a","slot":"b","sha256":"b".repeat(64),"world_id":"world:first","seed":713,"checkpoint_id":"cp:9","command_revision":9,"time":200.0,"requires_assembly_validation":true}]
func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	var source := rows(); var original := source.duplicate(true)
	var calls := Calls.new()
	var host := Node.new(); root.add_child(host)
	var menu: Control = Mount.mount_recovery(host, source, calls.choose, calls.fresh)
	await flush()
	check("startup recovery mounts real Control without auto selection or submission", menu.is_visible_in_tree() and menu._selected.is_empty() and menu._restore.disabled and calls.requests.is_empty() and calls.fresh_calls == 0)
	check("UI preserves supplied candidate order and source data", menu.candidates == original and source == original and key(menu,"recovery:candidate:0").text.contains("2026"))
	check("initial focus cannot restore or start a new world", root.gui_get_focus_owner() == menu._dialog)
	menu.select_candidate(source[0])
	check("selection preserves exact ID SHA and shows real metadata", menu._selected == source[0] and menu._details.text.contains("world:second") and menu._details.text.contains("cp:5") and menu._details.tooltip_text.contains(source[0].sha256) and calls.requests.is_empty())
	menu._restore_pressed()
	check("restore requires separate confirmation with safe cancel focus", menu._confirming == "restore" and not menu.busy and calls.requests.is_empty() and root.gui_get_focus_owner() == menu._back)
	menu.cancel()
	check("cancel confirmation retains only view selection without invoking a callback", menu._confirming.is_empty() and not menu._selected.is_empty() and calls.requests.is_empty())
	menu._restore_pressed(); menu._restore_pressed()
	check("confirmed restore submits exact selected identity once", menu.busy and calls.requests == [[source[0].candidate_id,source[0].sha256]], calls.requests)
	menu._restore_pressed(); menu._fresh_pressed(); menu.cancel()
	check("inflight restore blocks repeats fresh and cancel", menu.busy and calls.requests.size() == 1 and calls.fresh_calls == 0 and menu._restore.disabled and menu._back.disabled)
	calls.resolved.emit({"ok":false,"code":"STALE_CANDIDATE","reason":"候选已变化；原活动索引保留"}); await flush()
	check("failure retains selection and concrete code reason without automatic retry", not menu.busy and menu._confirming.is_empty() and menu._status.text.contains("候选已变化") and menu._status.tooltip_text.contains("STALE_CANDIDATE") and calls.requests.size() == 1)
	menu._fresh_pressed()
	check("fresh option also requires confirmation", menu._confirming == "fresh" and calls.fresh_calls == 0 and root.gui_get_focus_owner() == menu._back)
	menu.cancel(); check("fresh cancellation never invokes fresh callback", menu._confirming.is_empty() and calls.fresh_calls == 0)
	menu.configure(source, calls.choose, calls.fresh)
	menu.select_candidate(source[1]); menu._restore_pressed(); menu._restore_pressed()
	menu.configure(source, calls.choose, calls.fresh)
	calls.resolved.emit({"ok":false,"code":"IO_ERROR","reason":"旧代迟到错误"}); await flush()
	check("reconfigure discards late callback from old selection generation", not menu.busy and menu._selected.is_empty() and not menu._status.text.contains("旧代"))
	var duplicate := [source[0],source[0]]
	menu.configure(duplicate,calls.choose,calls.fresh)
	check("duplicate stable identities are not selectable", key(menu,"recovery:candidate:0").disabled and key(menu,"recovery:candidate:1").disabled)
	menu.select_candidate(source[0]); check("programmatic duplicate selection also fails closed", menu._selected.is_empty())
	for missing: String in ["candidate_id","sha256","world_id"]:
		var malformed: Dictionary = source[0].duplicate(true); malformed.erase(missing)
		menu.configure([malformed],calls.choose,calls.fresh)
		check("missing candidate field cannot submit " + missing,key(menu,"recovery:candidate:0").disabled and menu._restore.disabled)
	menu.configure([],calls.choose,calls.fresh)
	check("empty candidates remain explicit with fresh option available", menu._restore.disabled and menu._fresh.visible and menu._selected.is_empty())
	for dimensions: Vector2i in [Vector2i(1000,700),Vector2i(1280,800)]:
		root.content_scale_size = dimensions; root.size = dimensions
		for scale_factor: float in [1.0,1.5]:
			menu.text_scale = scale_factor
			menu.theme = ThemeFactory.create(load("res://themes/fonts/NotoSansCJKsc-Regular.otf"),scale_factor)
			menu.configure(source,calls.choose,calls.fresh); menu.select_candidate(source[0]); menu._restore_pressed(); await flush()
			var bounds: Rect2 = menu._dialog.get_global_rect()
			check("recovery controls fit native logical viewport " + str(dimensions) + " " + str(scale_factor),bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= dimensions.x and bounds.end.y <= dimensions.y and menu._back.get_global_rect().end.y <= bounds.end.y and menu._details.get_combined_minimum_size().x <= bounds.size.x, str(bounds))
	menu.configure(source,calls.choose,calls.fresh)
	menu.select_candidate(source[0]); menu._restore_pressed(); menu._restore_pressed()
	calls.resolved.emit({"ok":true,"code":"OK"}); await flush()
	check("callback success waits for A takeover instead of re-enabling the old world", menu.busy and menu._status.text.contains("等待") == false and menu._status.text.contains("接管"))
	menu.configure(source,calls.choose,calls.fresh)
	menu.select_candidate(source[0]); menu._restore_pressed(); menu._restore_pressed()
	host.queue_free(); await flush(); calls.resolved.emit({"ok":false,"code":"IO_ERROR","reason":"销毁后迟到"}); await flush()
	check("destroyed startup Control safely ignores late callback", not is_instance_valid(menu))
	await ingame_cases(source)
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)
func ingame_cases(source: Array) -> void:
	var authority := Authority.new(); authority.rows = source.duplicate(true)
	var router := Router.new()
	var host := Node.new(); root.add_child(host)
	var ui: Control = Mount.mount(host,authority,router)
	ui.open_panel("pause"); await flush()
	var launch: Button = key(ui,"pause:recovery-candidates")
	check("pause menu exposes actual recovery service entry", launch != null and not launch.disabled)
	ui.carry = {"temporary":"old selection"}; ui.capture_action = "interact"
	launch.pressed.emit(); await flush()
	var menu: Control = ui._recovery_menu
	check("pause entry consumes real list callback without selecting a world", authority.lists == 1 and is_instance_valid(menu) and menu.candidates == source and menu._selected.is_empty() and authority.requests.is_empty())
	check("open recovery clears old carry and key capture while preserving pause", ui.carry.is_empty() and ui.capture_action.is_empty() and router.modal and ui.pages.back().page == "pause")
	var before: Array = ui.pages.duplicate(true)
	ui.open_panel("inventory"); ui.close_panels(); ui.save_world()
	var blocked: Dictionary = ui.execute("eat", "")
	check("covered UI cannot switch panels save issue commands or change hand", ui.pages == before and authority.saves == 0 and authority.commands == 0 and blocked.get("code") == "BUSY" and ui.router_call("select_slot",[1]).get("code") == "BUSY")
	menu.select_candidate(source[1]); menu._restore_pressed(); menu._restore_pressed(); ui.refresh(); await flush()
	check("submitted choice uses real request ID and existing busy gate", authority.requests.size() == 1 and authority.requests[0][0] == source[1].candidate_id and authority.requests[0][1] == source[1].sha256 and str(authority.requests[0][2]).begins_with("ui-file:") and ui.world_restoring and ui._recovery_menu == menu and router.modal)
	authority.resolved.emit({"ok":true,"code":"OK"}); await flush()
	check("wrong request receipt cannot confirm in-game recovery", not menu.busy and not ui.world_restoring and menu._status.tooltip_text.contains("UNCONFIRMED") and menu._status.text.contains("匹配"))
	ui.cancel_ui(); await flush()
	check("returning from recovery preserves pause then returns control normally", not is_instance_valid(ui._recovery_menu) and ui.pages.back().page == "pause" and router.modal)
	ui.close_panels(); check("closing pause releases only original modal reason", not router.modal)
	ui.open_panel("pause"); ui.open_recovery_candidates()
	menu = ui._recovery_menu; menu.select_candidate(source[0]); menu._restore_pressed(); menu._restore_pressed()
	var replacement := Authority.new(); replacement.rows = source.duplicate(true)
	ui.configure(replacement,router); await flush()
	authority.resolved.emit({"ok":false,"code":"IO_ERROR","reason":"旧authority迟到"}); await flush()
	check("in-game reconfigure ignores old restore completion and disposes old overlay", not is_instance_valid(menu) and not ui.world_restoring and ui._notice.text.is_empty() and replacement.requests.is_empty())
	host.queue_free(); await flush()
func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"fixture":"controlled asynchronous candidate callbacks + actual startup and pause-menu Controls, persistent modal/request/lifecycle guards; no actual store or scene readiness","formal_application_launched":false,"physical_os_input":false,"route_acceptance":false},"  ")); file.close()
	quit(code)
