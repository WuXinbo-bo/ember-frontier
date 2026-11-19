extends SceneTree
## Controlled file callback lifecycle with the real native UI. No filesystem,
## candidate validation, formal app or OS dialog behavior is claimed here.
const Mount = preload("res://scripts/ui/ui_mount.gd")

class Authority extends RefCounted:
	signal changed(changes: Dictionary)
	signal resolve
	var save := {"ready":true,"busy":false,"status":"idle","reason":""}
	var calls := 0
	var bad_id := false
	var refusal := true
	func snapshot() -> Dictionary: return {"save":save.duplicate(true)}
	func import_checkpoint_file(_path: String, id: String) -> Dictionary:
		calls += 1
		save.merge({"busy":true,"status":"loading","reason":"受控文件候选等待"},true)
		changed.emit({"save":true})
		await resolve
		save.merge({"busy":false,"status":"failed" if refusal else "imported","reason":"受控候选失败" if refusal else "受控文件完成"},true)
		changed.emit({"save":true})
		return {"ok":not refusal,"code":"WORLD_READY_TIMEOUT" if refusal else "OK","reason":save.reason,"request_id":"wrong-id" if bad_id else id}

var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(8).timeout.connect(func(): finish(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	print(("PASS " if ok else "FAIL ")+name)

func flush() -> void:
	await process_frame
	await process_frame

func submit(ui: Control) -> void:
	ui._file_operation="import"
	ui._file_selected("controlled://ui-only-no-file")

func run() -> void:
	if OS.get_cmdline_user_args().is_empty():quit(2);return
	output=OS.get_cmdline_user_args()[0]
	var authority:=Authority.new()
	var ui:Control=Mount.mount(root,authority,null)
	ui.open_panel("pause");submit(ui);await flush()
	check("yielded file candidate consumes actual published loading projection",authority.calls==1 and ui.importing and ui.world_change_busy() and ui._storage_status.text==authority.save.reason)
	var serial:int=ui._serial
	submit(ui);ui.close_panels();ui.cancel_ui();ui.open_panel("inventory")
	check("file wait blocks duplicate stale callback and scene resume",authority.calls==1 and ui._serial==serial and ui.pages.back().page=="pause")
	authority.resolve.emit();await flush()
	check("file refusal releases wait and presents exact reason without success",not ui.importing and not ui.world_change_busy() and ui._notice.text==authority.save.reason and not ui._notice.text.contains("已验证并导入"),ui._notice.text)
	authority.refusal=false;authority.bad_id=true
	submit(ui);authority.resolve.emit();await flush()
	check("file success with wrong request ID is never accepted",not ui.importing and ui._notice.text.contains("未收到匹配本次请求") and not ui._notice.text.contains("检查点已验证"),ui._notice.text)
	authority.refusal=true;authority.bad_id=false
	submit(ui);await flush()
	var fresh:=Authority.new()
	ui.configure(fresh,null);ui.notify("新一代UI保留回执")
	authority.resolve.emit();await flush()
	check("late file receipt cannot overwrite a reconfigured UI",ui.runtime==fresh and not ui.importing and ui._notice.text=="新一代UI保留回执")
	ui.open_panel("pause");submit(ui);await flush()
	var gone:WeakRef=weakref(ui)
	ui.get_parent().queue_free();await flush()
	fresh.resolve.emit();await flush()
	check("late file receipt safely ignores UI freed during activation",gone.get_ref()==null)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int) -> void:
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"fixture":"Controlled asynchronous file authority + actual UI Control; no file IO, production readiness or OS dialog acceptance","formal_application_launched":false,"route_acceptance":false,"visual_acceptance":false},"  "));file.close()
	quit(code)
