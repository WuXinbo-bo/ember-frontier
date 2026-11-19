extends SceneTree
## Real native Controls with controlled failure/callback DTOs. A separately
## owns the bad-standing capture, startup scan, assembly and active bytes.
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Recovery = preload("res://scripts/ui/recovery_menu.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const ThemeFactory = preload("res://scripts/ui/ui_theme.gd")

class Calls extends RefCounted:
	signal resolved(receipt: Dictionary)
	var choices: Array = []
	var fresh_count := 0
	func choose(id: String, sha: String) -> Dictionary:
		choices.append([id, sha])
		var receipt: Dictionary = await resolved
		return receipt
	func fresh() -> Dictionary:
		fresh_count += 1
		var receipt: Dictionary = await resolved
		return receipt

var output := ""
var checks: Array = []
func _initialize() -> void:
	create_timer(12).timeout.connect(func(): finish(2))
	call_deferred("run")
func flush() -> void:
	await process_frame; await process_frame
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	print(("PASS " if ok else "FAIL ") + name)
func candidate() -> Dictionary:
	return {"candidate_id":"saved/a","namespace":"saved","slot":"a","sha256":"a".repeat(64),"checkpoint_id":"cp:12","world_id":"world:12","seed":12,"command_revision":5,"time":53.7,"requires_assembly_validation":true}
func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	var calls := Calls.new()
	var source: Array = [candidate()]
	var failure := {"ok":false,"code":"SPATIAL_REJECTED","reason":"存档中的玩家站位无有效支撑；原存档保留","diagnostic":{"actor":"player"}}
	var original := failure.duplicate(true)
	var old_host := Node.new(); root.add_child(old_host)
	var old_menu: Control = Mount.mount_recovery(old_host, source, calls.choose, calls.fresh)
	await flush()
	check("four-argument API keeps empty initial feedback and no automatic choice", old_menu._status.text.is_empty() and old_menu._selected.is_empty() and calls.choices.is_empty() and calls.fresh_count == 0)
	old_host.queue_free(); await flush()
	# Mount before the parent enters the scene tree: rendering must wait, but
	# the failure identity and display state must survive the ready callback.
	var host := Node.new()
	var menu: Control = Mount.mount_recovery(host, source, calls.choose, calls.fresh, failure)
	check("fifth-argument failure is accepted before tree readiness", not menu.is_node_ready() and menu._feedback.contains(original.reason) and menu._diagnostic == P.feedback_diagnostic(original))
	failure.reason = "caller changed its own receipt"
	root.add_child(host); await flush()
	check("first native frame displays copied authoritative failure", menu._status.text.contains(original.reason) and not menu._status.text.contains(failure.reason) and menu._status.tooltip_text == P.feedback_diagnostic(original))
	check("initial failure does not select submit or hide the fresh exit", menu._selected.is_empty() and menu._restore.disabled and menu._fresh.visible and not menu._fresh.disabled and calls.choices.is_empty() and calls.fresh_count == 0)
	check("initial failure gives neutral focus instead of a destructive action", root.gui_get_focus_owner() == menu._dialog)
	check("initial display preserves input candidate and original receipt", menu.candidates == source and original.get("diagnostic") == {"actor":"player"})
	menu.show_failure({"ok":false,"code":"UNKNOWN_OFFLINE_REJECTION"})
	check("public failure API preserves an unknown code without inventing a reason", menu._status.text.contains("UNKNOWN_OFFLINE_REJECTION") and menu._status.tooltip_text == "code: UNKNOWN_OFFLINE_REJECTION\n")
	var status: String = menu._status.text
	menu.show_failure({}); menu.show_failure({"ok":true,"code":"OK"})
	check("empty or successful receipts cannot fabricate a recovery success", menu._status.text == status and not menu.busy and menu._selected.is_empty() and calls.choices.is_empty())
	var replacement := candidate(); replacement.sha256 = "b".repeat(64)
	var refresh := {"ok":false,"code":"STALE_CANDIDATE","reason":"候选已变化，请重新明确选择","candidates":[replacement]}
	menu.select_candidate(source[0]); menu._restore_pressed()
	menu.show_failure(refresh)
	check("public failure cancels an unsubmitted confirmation and refreshes explicit choices", menu._confirming.is_empty() and menu._selected.is_empty() and menu.candidates == refresh.candidates and menu._restore.disabled and root.gui_get_focus_owner() == menu._dialog and calls.choices.is_empty())
	refresh.candidates[0].sha256 = "c".repeat(64)
	check("refreshed candidate rows are detached from the caller", menu.candidates[0].sha256 == "b".repeat(64))
	menu.select_candidate(menu.candidates[0]); menu._restore_pressed(); menu._restore_pressed()
	check("explicit retry submits only the selected current ID and SHA", menu.busy and calls.choices == [["saved/a","b".repeat(64)]])
	menu.show_failure(original)
	check("external display cannot unlock an already submitted recovery", menu.busy and menu._restore.disabled and menu._back.disabled and menu._status.text.contains("等待真实回执") and calls.choices.size() == 1)
	calls.resolved.emit({"ok":false,"code":"NOT_READY","reason":"真实回调拒绝候选就绪"}); await flush()
	check("submitted failure still follows the original finished diagnostic path", not menu.busy and menu._status.text.contains("真实回调拒绝候选就绪") and menu._status.tooltip_text.contains("code: NOT_READY") and calls.choices.size() == 1)
	menu.show_failure({"ok":false,"code":"SPATIAL_REJECTED","reason":original.reason,"candidates":[]})
	check("empty recovery list still exposes a separately confirmed fresh exit", menu.candidates.is_empty() and menu._selected.is_empty() and menu._restore.disabled and menu._fresh.visible and not menu._fresh.disabled and calls.fresh_count == 0)
	menu._fresh_pressed()
	check("initial assembly failure never bypasses fresh confirmation", menu._confirming == "fresh" and root.gui_get_focus_owner() == menu._back and calls.fresh_count == 0)
	menu.cancel()
	check("fresh cancellation keeps the failure and old storage untouched by callbacks", menu._confirming.is_empty() and menu._status.text.contains(original.reason) and calls.fresh_count == 0)
	menu._fresh_pressed(); menu._fresh_pressed()
	check("explicit fresh confirmation reaches exactly one existing callback", menu.busy and calls.fresh_count == 1)
	calls.resolved.emit({"ok":false,"code":"IO_ERROR","reason":"新图准备失败，旧档保持"}); await flush()
	check("failed fresh callback returns to the same usable failure screen", not menu.busy and menu._status.text.contains("新图准备失败，旧档保持") and menu._fresh.visible and not menu._fresh.disabled)
	for dimensions: Vector2i in [Vector2i(1000,700),Vector2i(1280,800)]:
		root.content_scale_size = dimensions; root.size = dimensions
		for scale_factor: float in [1.0,1.5]:
			menu.theme = ThemeFactory.create(load("res://themes/fonts/NotoSansCJKsc-Regular.otf"),scale_factor)
			menu.configure(source,calls.choose,calls.fresh); menu.show_failure(original); await flush()
			var bounds: Rect2 = menu._dialog.get_global_rect()
			check("initial failure and fresh exit fit logical viewport " + str(dimensions) + " " + str(scale_factor), bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= dimensions.x and bounds.end.y <= dimensions.y and menu._fresh.get_global_rect().end.y <= bounds.end.y and menu._status.get_global_rect().end.y <= bounds.end.y, str(bounds))
	menu.configure(source,calls.choose,calls.fresh)
	check("new configuration clears the previous initial failure", menu._status.text.is_empty() and menu._status.tooltip_text.is_empty())
	# Directly constructed Control has the same public pre-ready contract.
	var detached := Recovery.new(); detached.configure([],calls.choose,calls.fresh); detached.show_failure(original)
	host.add_child(detached); await flush()
	check("direct public show_failure works before ready without mount helper", detached._status.text.contains(original.reason) and detached._status.tooltip_text == P.feedback_diagnostic(original) and detached._selected.is_empty())
	host.queue_free(); await flush()
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)
func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"fixture":"production recovery Control/mount and native focus/layout; controlled failure and async callbacks; no actual bad standing capture/startup scan/store/OS/PCK","formal_application_launched":false,"route_acceptance":false},"  ")); file.close()
	quit(code)
