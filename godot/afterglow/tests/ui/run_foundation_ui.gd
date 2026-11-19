extends SceneTree
## UI contracts and real native Controls with an explicit controlled authority.
## Does not launch the formal scene, use user saves, or validate OS input.
const P = preload("res://scripts/ui/ui_projection.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")

class Authority extends RefCounted:
	signal changed(changes: Dictionary)
	var data := {"revision":1,"command_revision":1,"player":{"id":"player","hp":100},"actors":[{"id":"player","hp":100}],"stocks":[],"tools":[],"orders":[],"quests":[],"catalog":{},"target":{},"hand":{"slots":[],"selected":0,"mode":"tool"},"save":{"ready":true,"busy":false,"status":"idle","reason":""}}
	var refusal := {"ok":false,"code":"OCCLUDED","reason":""}
	var previews := 0
	var commands := 0
	func snapshot() -> Dictionary: return data.duplicate(true)
	func availability(_request: Dictionary) -> Dictionary:
		previews += 1
		return refusal.duplicate(true)
	func command(_request: Dictionary) -> Dictionary:
		commands += 1
		return {"ok":true,"code":"OK"}
	func start_new_world(_seed: int = -1, _id: String = "") -> Dictionary: return {"ok":false,"code":"NOT_READY"}
	func restore_saved_world(_id: String = "") -> Dictionary: return {"ok":false,"code":"NOT_READY"}
	func save_async(_id: String = "") -> Dictionary: return {"ok":false,"code":"NOT_READY"}

class Router extends Node:
	signal changed
	var modal := false
	var modal_calls := 0
	var selections := 0
	var bindings: Dictionary = {}
	func state() -> Dictionary: return {"slots":[],"selected":0,"mode":"tool","pause_reasons":{"modal":modal}}
	func set_modal(value: bool) -> void:
		modal = value
		modal_calls += 1
		changed.emit()
	func set_file_dialog(_value: bool) -> void: pass
	func set_text_focus(_value: bool) -> void: pass
	func select_slot(_index: int) -> Dictionary:
		selections += 1
		return {"ok":true,"code":"OK"}
	func bind_key(action: String, code: int) -> Dictionary:
		bindings[action] = code
		return {"ok":true,"code":"OK"}

var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(15).timeout.connect(func(): finish(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	print(("PASS " if ok else "FAIL ") + name)

func flush() -> void:
	await process_frame
	await process_frame

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): quit(2); return
	output = args[0]
	var examples := {"OUT_OF_REACH":"距离","OCCLUDED":"遮挡","BODY_BLOCKED":"通路","STEP_TOO_HIGH":"台阶","NO_SUPPORT":"支撑","NO_VALID_USE_POINT":"使用位置","NOT_READY":"就绪","FORBIDDEN":"权限","RESERVED":"占用","WRONG_TOOL":"工具","INSUFFICIENT_ITEM":"材料","STALE_INPUT":"重新","TARGET_MISSING":"目标"}
	for code: String in examples:
		var receipt := {"ok":false,"code":code,"reason":""}
		var original := receipt.duplicate(true)
		var text := P.feedback_text(receipt)
		check("stable failure code explained " + code, text.contains(examples[code]) and not text.contains(code), text)
		check("failure adaptation is read-only " + code, receipt == original)
	var movement := P.feedback_text({"code":"UNREACHABLE","reason":"UNREACHABLE"},{"purpose":"body_move"})
	check("movement unreachable never claims a distant mouse target",movement.contains("通路") and not movement.contains("目标") and not movement.contains("移近"),movement)
	check("specific authority reason and unknown code remain intact",P.feedback_text({"code":"OCCLUDED","reason":"目标背后的关门阻挡"})=="目标背后的关门阻挡" and P.feedback_text({"code":"NEW_DOMAIN_CODE"})=="NEW_DOMAIN_CODE")
	var host := Node.new(); root.add_child(host)
	var authority := Authority.new()
	var router := Router.new(); host.add_child(router)
	var ui: Control = Mount.mount(host,authority,router)
	await flush()
	for code: String in ["OUT_OF_REACH","OCCLUDED","NO_VALID_USE_POINT","NOT_READY","FORBIDDEN","RESERVED","WRONG_TOOL"]:
		authority.data.target = {"id":"controlled-target","kind":"structure","name":"既有构件","enabled":false,"code":code,"reason":""}
		ui.refresh()
		var preview: String = ui._target_text.text
		ui.report_action({"ok":false,"code":code,"reason":""})
		check("preview and submit use the same explanation " + code,preview.contains(P.feedback_text({"code":code})) and ui._notice.text.contains(P.feedback_text({"code":code})) and ui._target_text.tooltip_text.contains(code),{"target":preview,"submit":ui._notice.text})
	check("mouse-target feedback does not become movement failure",ui._movement_feedback.is_empty() and not ui._movement_hint.text.contains("移动受阻"))
	ui.report_movement({"ok":false,"code":"UNREACHABLE","reason":"UNREACHABLE"}); ui.refresh()
	check("native movement HUD has movement-specific wording",ui._movement_hint.text.contains("通路") and not ui._movement_hint.text.contains("够不到目标"),ui._movement_hint.text)
	ui.report_movement({"ok":true}); ui.refresh()
	check("successful actual movement clears prior movement refusal",ui._movement_feedback.is_empty())
	var result: Dictionary = ui.execute("controlled-action","controlled-target")
	check("actual UI preflight returns original refusal without commit",result==authority.refusal and authority.commands==0 and authority.previews==1 and ui._notice.text.contains("遮挡"),result)
	ui.world_restoring = true; ui._sync_modal()
	var previous_previews: int = authority.previews
	result = ui.execute("controlled-action","controlled-target")
	var selection: Dictionary = ui.router_call("select_slot",[2])
	check("in-flight world replacement blocks stale UI actions",result.get("code")=="BUSY" and authority.previews==previous_previews and authority.commands==0,result)
	check("in-flight world replacement blocks stale hand mutations",selection.get("code")=="BUSY" and router.selections==0,selection)
	var slot := {"kind":"inventory","stock_id":"pack:player","index":0,"reference":{"kind":"item","item_id":"food"},"quantity":2,"entry":{"name":"食物","step":1}}
	var held: Dictionary = ui._create_drag(slot)
	ui._split_slot(slot)
	check("in-flight replacement cannot start drag or split",held.is_empty() and ui.drag.is_empty() and ui.carry.is_empty() and not is_instance_valid(ui._split_layer))
	ui.open_panel("inventory"); ui.cancel_ui()
	check("in-flight replacement cannot open or resume a second panel",ui.pages.is_empty() and router.modal)
	ui.world_restoring = false
	authority.data.save={"ready":true,"busy":true,"status":"saving","reason":"真实保存进行中"}; ui.refresh()
	check("authority busy disables file re-entry even without local flag",ui.file_request_busy())
	check("ordinary saving is not mistaken for world replacement",not ui.world_change_busy())
	authority.data.save={"ready":true,"busy":false,"status":"failed","reason":"恢复校验失败"}; ui.refresh()
	check("failed restore is not mislabeled as a save failure",ui._storage_status.text.contains("恢复校验失败") and not ui._storage_status.text.begins_with("保存失败"),ui._storage_status.text)
	check("failure allows current-world controls again",not ui.file_request_busy() and not ui.world_change_busy())
	# Published global preparation can start outside this UI's local waiter.
	# A keeps save.busy true until activation or rollback; no local ready clock.
	ui.close_panels()
	for phase: String in ["loading", "generating"]:
		authority.data.save={"ready":true,"busy":true,"status":phase,"reason":"权威准备阶段 · "+phase}
		ui.refresh(); await flush()
		check("external preparation locks the router without a local request "+phase,ui.world_change_busy() and ui.file_request_busy() and not ui.world_starting and not ui.world_restoring and router.modal)
		check("external preparation displays actual phase reason "+phase,ui._storage_status.text==authority.data.save.reason,ui._storage_status.text)
		var calls: int=router.modal_calls
		ui.refresh(); await flush()
		check("preparation refresh does not loop modal change signals "+phase,router.modal_calls==calls,{"before":calls,"after":router.modal_calls})
		previous_previews=authority.previews
		result=ui.execute("controlled-action","controlled-target")
		selection=ui.router_call("select_slot",[2])
		ui.open_panel("inventory");ui.cancel_ui();ui.close_panels()
		check("external preparation blocks actions hand and panel routes "+phase,result.get("code")=="BUSY" and selection.get("code")=="BUSY" and authority.previews==previous_previews and router.selections==0 and ui.pages.is_empty() and router.modal)
		held=ui._create_drag(slot);ui._split_slot(slot)
		check("external preparation blocks inventory drag and split "+phase,held.is_empty() and ui.drag.is_empty() and ui.carry.is_empty() and not is_instance_valid(ui._split_layer))
		authority.data.save={"ready":true,"busy":false,"status":"failed","reason":"准备失败，原现场保留"}
		ui.refresh();await flush()
		check("rollback releases scene modal and retains authority reason "+phase,not ui.world_change_busy() and not router.modal and ui._storage_status.text.contains("原现场保留"))
	# An external preparation also consumes old modal-key capture and carry.
	ui.open_panel("settings");ui.capture_action="build";ui.carry={"ui_drag":"old-world-carry"}
	authority.data.save={"ready":true,"busy":true,"status":"loading","reason":"加载中"};ui.refresh();await flush()
	check("external loading cancels transient UI before a stale drop or remap",ui.carry.is_empty() and ui.drag.is_empty() and ui.capture_action.is_empty() and ui.pages.back().page=="settings")
	var during_loading := InputEventKey.new();during_loading.keycode=KEY_X;during_loading.physical_keycode=KEY_X;during_loading.pressed=true
	root.push_input(during_loading,true);await flush()
	ui.cancel_ui();ui.close_panels()
	check("loading key events cannot bind or close the old panel",router.bindings.is_empty() and ui.pages.back().page=="settings" and router.modal)
	authority.data.save={"ready":true,"busy":false,"status":"failed","reason":"原现场保留"};ui.refresh();await flush()
	ui.close_panels()
	authority.data.save={"ready":true,"busy":true,"status":"saving","reason":"普通保存"};ui.refresh();await flush()
	check("ordinary saving neither remounts nor forces scene input pause",not ui.world_change_busy() and ui.file_request_busy() and not router.modal)
	authority.data.save={"ready":true,"busy":false,"status":"loading","reason":"已回滚的旧阶段标签"};ui.refresh();await flush()
	check("completed preparation does not latch solely on an old status label",not ui.world_change_busy() and not ui.file_request_busy() and not router.modal)
	authority.data.save={"ready":true,"busy":false,"status":"failed","reason":"恢复校验失败"};ui.refresh()
	# Dynamic ordinary identities use the same existing actor projection.
	authority.data.actors=[{"id":"ordinary:visitor-07","name":"远行的修理工","hp":81,"stamina":56,"activity":"整理工具","relationship":{"met":true}},authority.data.player]
	ui.open_panel("npc","ordinary:visitor-07"); await flush()
	check("ordinary actor displays without opening-NPC ID branch",text_in(ui._body).contains("远行的修理工") and text_in(ui._body).contains("整理工具"),text_in(ui._body))
	authority.data.actors.reverse(); ui.refresh()
	check("actor reordering preserves selected identity",text_in(ui._body).contains("远行的修理工"))
	authority.data.actors[1].relationship.met=false; ui.refresh()
	check("unmet actor projection does not leak its name",not text_in(ui._body).contains("远行的修理工") and text_in(ui._body).contains("附近的幸存者"))
	authority.data.actors=[authority.data.player]; ui.refresh()
	check("removed ordinary actor leaves no stale panel identity",not text_in(ui._body).contains("远行的修理工") and text_in(ui._body).contains("当前没有可见的人物"))
	authority.data.player.intent={"owner":"actions","kind":"existing-action-variant","elapsed":1.25,"seconds":5.0}
	ui.refresh()
	check("ordinary action variant projects authority progress",ui._work_progress.visible and is_equal_approx(ui._work_progress.value,1.25) and is_equal_approx(ui._work_progress.max_value,5.0))
	await flush()
	check("native UI frames do not advance authority action time",ui._work_progress.value==1.25 and authority.data.player.intent.elapsed==1.25)
	authority.data.player.intent=null; ui.refresh()
	check("cancelled authority action removes progress",not ui._work_progress.visible)
	# Native Viewport key delivery checks physical-key/remapping boundaries only.
	ui.open_panel("settings"); await flush(); ui.capture_action="inventory"
	var key := InputEventKey.new(); key.keycode=KEY_Q; key.unicode=113; key.pressed=true
	root.push_input(key,true); await flush()
	check("unicode-only key does not invent a physical binding",router.bindings.is_empty() and ui.capture_action=="inventory")
	key=InputEventKey.new(); key.physical_keycode=KEY_Q; key.keycode=KEY_Q; key.meta_pressed=true; key.pressed=true
	root.push_input(key,true); await flush()
	check("native remap retains macOS physical key and modifier",router.bindings.get("inventory")==int(KEY_Q | KEY_MASK_META) and ui.capture_action.is_empty(),router.bindings)
	ui.capture_action="build"
	key=InputEventKey.new(); key.keycode=KEY_ESCAPE; key.physical_keycode=KEY_ESCAPE; key.pressed=true
	root.push_input(key,true); await flush()
	check("first Escape cancels remap before closing settings",ui.capture_action.is_empty() and ui.pages.back().page=="settings" and router.modal)
	root.push_input(key,true); await flush()
	check("next Escape returns one panel level",ui.pages.size()==1 and ui.pages.back().page=="npc")
	ui.carry={"ui_drag":"controlled-carry"};ui.drag={"ui_drag":"controlled-drag"};ui.capture_action="build"
	ui._on_focus_exited(); await flush()
	check("focus-loss cleanup preserves panel pause and clears transient UI",ui.carry.is_empty() and ui.drag.is_empty() and ui.capture_action.is_empty() and router.modal)
	host.queue_free(); await process_frame
	finish(0 if checks.all(func(row: Dictionary) -> bool: return row.ok) else 1)

func text_in(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): text += text_in(child)
	return text

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"fixture":"Controlled authority DTO and actual production native Control scene; no spatial truth or real storage claimed","formal_application_launched":false,"physical_OS_input":false,"whole_route_acceptance":false,"visual_acceptance":false},"  "))
	quit(code)
