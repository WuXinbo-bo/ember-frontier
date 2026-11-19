extends SceneTree
## Current Native UI with explicit screen-target DTOs. No app/renderer,
## selection/reach claims, user storage or formal screenshot qualification.
const Client = preload("res://scripts/runtime/native_client.gd")
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Layout = preload("res://scripts/ui/target_prompt_layout.gd")
const Data = preload("res://scripts/world/world_data.gd")
const CompanionCard = preload("res://scripts/ui/companion_action_card.gd")
class TestClient extends Client:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var output := ""
var checks: Array = []
var observed: Array = []
var host: Node3D
var ui: Control
var runtime: RefCounted
var router: Node
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): check("suite completes before watchdog",false); finish())
	call_deferred("run")
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: print("FAIL "+label+" "+str(detail))
func flush() -> void:
	await process_frame; await process_frame; await process_frame
func dto(anchor: Variant = {"x":682,"y":344}) -> Dictionary:
	return {"id":"explicit-screen-fixture","kind":"module","primary":"module","name":"临路手工修理棚","action":"查看与管理","enabled":true,"projected_position":anchor}
func rectangle(value: Rect2) -> Dictionary:
	return {"x":value.position.x,"y":value.position.y,"width":value.size.x,"height":value.size.y}
func companion_order_checks() -> void:
	var actor := {"id":"companion", "hp":80, "activity":"前往取货", "relationship":{"member":true, "consent":true}}
	var workforce := {"available":true, "members":[{"actor_id":"companion", "assignment_id":"order-1"}], "assignments":[{
		"actor_id":"companion", "id":"order-1", "work_kind":"transport_order", "work_phase":"blocked", "work_reason":"接收库存已满"}]}
	var factory := {"available":true, "modules":{"available":true}, "workforce":workforce}
	var card := CompanionCard.present(actor, factory)
	check("action card shows owner's real work phase and reason", card.current == "前往取货" and card.assignment.contains("运输工单") and card.assignment.contains("受阻") and card.reason == "接收库存已满" and card.next.contains("补足条件"), card)
	actor.pending_delivery = {"phase":"deliver"}
	card = CompanionCard.present(actor, factory)
	check("actual carried stock takes priority over the queued order's next step", card.carrying and card.next.contains("仍由本人保管"), card)
	actor.relationship.consent = false
	card = CompanionCard.present(actor, factory)
	check("action card explains missing work consent before advertising dispatch", card.consent.contains("尚未同意工作"), card)

func hud_geometry_checks() -> void:
	root.content_scale_size = Vector2i(1000, 700)
	root.size = Vector2i(1000, 700)
	ui.set_text_scale(1.5)
	runtime.set_target(dto({"x":500, "y":350}))
	ui.notify("请选择一栋已查看、可管理的建筑", true)
	ui.refresh()
	await flush()
	var toast: Rect2 = ui._world_notice.get_global_rect()
	var prompt: Rect2 = ui._target.get_global_rect()
	check("world notice avoids both HUD rails, target prompt, and shortcuts at 1000×700 / 150%", ui._world_notice.is_visible_in_tree() and not toast.intersects(ui._hud_backdrop.get_global_rect()) and not toast.intersects(ui._factory_navigation.get_global_rect()) and not toast.intersects(prompt) and toast.end.y <= ui._hotbar.get_global_rect().position.y - 11, {"toast":rectangle(toast),"left":rectangle(ui._hud_backdrop.get_global_rect()),"right":rectangle(ui._factory_navigation.get_global_rect()),"prompt":rectangle(prompt),"hotbar":rectangle(ui._hotbar.get_global_rect())})
	var portrait: Button
	for entry: Node in ui.find_children("*", "Button", true, false):
		if str(entry.get_meta("ui_focus_key", "")).begins_with("hud:portrait:"):
			portrait = entry as Button
			break
	check("normal opening publishes a companion portrait", is_instance_valid(portrait))
	if not is_instance_valid(portrait): return
	var actor_id := str(portrait.get_meta("ui_focus_key")).trim_prefix("hud:portrait:")
	portrait.grab_focus()
	portrait.pressed.emit()
	await flush()
	var route: Dictionary = ui.pages.back() if not ui.pages.is_empty() else {}
	check("portrait opens the world-selection action card for the same actor", route.get("page") == "npc_quick" and route.get("subject") == actor_id and ui.world_view_selection() == {"kind":"npc", "id":actor_id}, route)
	var actions: Rect2 = ui._planning_footer.get_global_rect()
	check("primary companion actions stay below the scrolling document and above the lower viewport edge", ui._planning_footer.visible and actions.position.y >= ui._scroll.get_global_rect().end.y and actions.end.y <= 700, rectangle(actions))
	check("open action card presents normal notice locally and hides the world notice", ui._panel_notice.is_visible_in_tree() and not ui._world_notice.is_visible_in_tree())
	check("companion action card suppresses an unrelated world prompt", not ui._target.is_visible_in_tree())
	check("companion card has no world shortcuts behind it at 150 percent", not ui._hotbar.is_visible_in_tree())
	ui.begin_companion_building_pick(actor_id)
	await flush()
	check("building selection restores world prompts for companions", ui.is_companion_building_pick() and ui._target.is_visible_in_tree())
	ui.cancel_ui()
	await flush()
	check("cancel building selection leaves the action card and suppresses world prompts", not ui.is_companion_building_pick() and ui.world_view_selection().get("id") == actor_id and not ui._target.is_visible_in_tree())
	ui.cancel_ui()
	await flush()
	check("closing the companion card restores portrait keyboard focus", root.gui_get_focus_owner() == portrait)
	check("world shortcuts return with exploration", ui._hotbar.is_visible_in_tree())
	check("world point action opens through the same companion route", ui.point_companion(actor_id) and ui.world_view_selection() == {"kind":"npc", "id":actor_id})
	ui.close_panels()
	ui.notify("")

func build_placement_mount_checks() -> void:
	root.content_scale_size = Vector2i(1000, 700)
	root.size = Vector2i(1000, 700)
	ui.set_text_scale(1.5)
	var target := {"kind":"placement", "name":"储物柜", "enabled":true, "placement_locked":false}
	var counts := [0, 0]
	router.confirm_requested.connect(func(): counts[0] += 1)
	router.retract_placement_requested.connect(func(): counts[1] += 1)
	var receipt: Dictionary = router.begin_facility_placement("cabinet")
	check("normal authority can enter facility placement", receipt.get("ok", false), receipt)
	if not receipt.get("ok", false): return
	runtime.set_target(target)
	ui.refresh()
	await flush()
	var card: PanelContainer = ui.get_node("BuildPlacementCard")
	var rect := card.get_global_rect()
	check("placement mounts one action surface inside the small viewport", card.is_visible_in_tree() and not ui._target.visible and not ui._factory_navigation.visible and rect.end.x <= 1000 and rect.end.y <= 700 and not rect.intersects(ui._hud_backdrop.get_global_rect()), rectangle(rect))
	check("confirm waits for a fixed position", card._confirm.disabled and card._retract.disabled)
	target.placement_locked = true
	runtime.set_target(target)
	ui.refresh()
	await flush()
	check("fixed valid placement exposes both actions", not card._confirm.disabled and not card._retract.disabled)
	card._confirm.pressed.emit()
	card._retract.grab_focus()
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	card._retract.pressed.emit()
	check("confirm button and Enter share one router intent even when retract has focus", counts == [2, 1], counts)
	router.set_mode("tool")
	ui.refresh()
	await flush()
	check("leaving placement hides card immediately even with a stale placement target", not card.visible and not ui._target.visible and ui._factory_navigation.visible)
	runtime.set_target({})

func run() -> void:
	output=OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800)
	var profiles: Dictionary=Assembly.generation_profiles()
	var made: Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.get("ok",false) else profiles
	host=TestClient.new(); root.add_child(host)
	var built: Dictionary=host._assemble(made.capture) if made.get("ok",false) else made
	check("current actual normal Native authority assembles",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false): return finish()
	runtime=built.runtime; router=TestRouter.new(); host.add_child(router); router.configure(runtime)
	ui=Mount.mount(host,runtime,router); await flush()
	router._set_combat_ready(true)
	check("combat posture paints hand hint synchronously without a full refresh", ui._mode_hint.text.contains("战备") and not ui._refresh_queued)
	router._set_combat_ready(false)
	check("combat release immediately restores normal hand hint", not ui._mode_hint.text.contains("战备"))
	var needs := {"collection":"actors", "id":"player", "before":{"id":"player", "thirst":58, "hp":100}, "after":{"id":"player", "thirst":57, "hp":100}}
	var notice := {"world":[], "facts":[needs], "events":[]}
	check("isolated needs changes use the paced HUD read", ui._temporal_change_only(notice))
	needs.after.hp = 96
	check("a wound accompanying a needs change repaints without pacing", not ui._temporal_change_only(notice))
	var before: Dictionary=runtime.capture_checkpoint()
	companion_order_checks()
	runtime.set_target(dto()); ui.refresh(); await flush()
	var rect: Rect2=ui._target.get_global_rect()
	observed.append({"case":"build16-workshop-anchor-approximation","viewport":[1280,800],"scale":1.0,"prompt":rectangle(rect),"text":ui._target_text.text,"source_screenshot":"work/r3-4/build16-os-first/workshop-service-approach.png","scope":"actual native Control metrics with explicit approximate screenshot anchor, not a newly rendered game frame"})
	check("workshop prompt is intrinsic compact text instead of a fixed 480px panel",rect.size.x<300 and rect.size.y<=52 and not ui._target_text.text.contains("\n"),rectangle(rect))
	check("workshop name and exact E action remain visible",ui._target_text.text.contains("临路手工修理棚") and ui._target_text.text.contains("E 查看与管理"))
	check("prompt leaves workshop target and central player clear",not rect.intersects(Rect2(594,264,176,144)) and not rect.intersects(Rect2(592,320,96,120)),rectangle(rect))
	check("target label does not capture mouse keyboard or focus",ui._target.mouse_filter==Control.MOUSE_FILTER_IGNORE and ui._target_text.mouse_filter==Control.MOUSE_FILTER_IGNORE and ui._target.focus_mode==Control.FOCUS_NONE and ui._target.get_child(0).mouse_filter==Control.MOUSE_FILTER_IGNORE)
	var request: Dictionary=dto(); request.progress=0.375
	runtime.set_target(request); ui.refresh(); await flush()
	check("existing authoritative target progress is preserved",ui._progress.visible and is_equal_approx(ui._progress.value,0.375) and is_equal_approx(ui._progress.max_value,1.0))
	request=dto(); request.enabled=false; request.code="MISSING_TOOL"; request.reason="缺少可用手锤"
	runtime.set_target(request); ui.refresh(); await flush()
	check("blocked prompt retains actual reason and does not imply successful interaction",ui._target_text.text.contains("目标暂不可操作") and not ui._target_text.tooltip_text.is_empty())
	request=dto(); request.kind="structure"; request.primary="door"; request.proof_state="pending"; request.action="开门"
	runtime.set_target(request); ui.refresh(); await flush()
	check("pending door proof still explains real submit-time safety validation",ui._target_text.text.contains("尝试开门") and ui._target_text.text.contains("提交时验证通路与安全"))
	var long_request: Dictionary=dto(); long_request.enabled=false; long_request.reason="通路受到阻挡，请检查出口并移开障碍。".repeat(12)
	runtime.set_target(long_request); ui.refresh(); await flush()
	check("long passive failure is bounded to three readable native lines",ui._target_text.max_lines_visible==3 and ui._target.size.y<=100)
	runtime.set_target(dto()); ui.refresh(); await flush()
	check("long failure shrinks back to compact successful action",ui._target.size.x<300 and ui._target.size.y<=52,rectangle(ui._target.get_global_rect()))
	for view: Vector2i in [Vector2i(1000,700),Vector2i(1280,800),Vector2i(1600,1000)]:
		root.content_scale_size=view; root.size=view
		for factor: float in [1.0,1.5]:
			ui.set_text_scale(factor); await flush()
			for anchor: Vector2 in [Vector2(view)*0.5,Vector2(24,24),Vector2(view)-Vector2(24,160)]:
				runtime.set_target(dto({"x":anchor.x,"y":anchor.y})); ui.refresh(); await flush()
				rect=ui._target.get_global_rect()
				var label := "%s scale%.1f anchor%s" % [str(view),factor,str(anchor)]
				check("window scale edges remain above shortcuts and inside viewport "+label,rect.position.x>=12 and rect.position.y>=12 and rect.end.x<=view.x-11 and rect.end.y<=ui._hotbar.get_global_rect().position.y-11,rectangle(rect))
				check("window scale preserves target and central player clearance "+label,not rect.intersects(Layout.target_clearance(anchor,factor)) and not rect.intersects(Rect2(Vector2(view)*0.5-Vector2(48,80)*factor,Vector2(96,120)*factor)),rectangle(rect))
				observed.append({"case":label,"prompt":rectangle(rect)})
	await hud_geometry_checks()
	root.content_scale_size=Vector2i(1280,800); root.size=Vector2i(1280,800); ui.set_text_scale(1.0); await flush()
	for malformed: Variant in [null,{"x":NAN,"y":20},{"x":50},{"x":INF,"y":0},{"x":20,"y":30,"visible":false}]:
		runtime.set_target(dto(malformed)); ui.refresh(); await flush()
		rect=ui._target.get_global_rect()
		check("invalid or unpublished screen anchor falls back inside safe HUD area "+str(malformed),Layout.point(malformed)==null and rect.position.is_finite() and rect.end.x<=1280 and rect.end.y<=ui._hotbar.get_global_rect().position.y-11)
	ui.open_panel("inventory"); await flush()
	check("inventory hides target without passing input to scene",not ui._target.visible and router.is_paused())
	ui.close_panels(); runtime.set_target({}); ui.refresh(); await flush()
	check("cleared target removes the hint",not ui._target.visible)
	check("all presentation cases preserve authoritative world inventory knowledge and clock",Data.json_equal(before,runtime.capture_checkpoint()))
	await build_placement_mount_checks()
	finish()
func finish() -> void:
	var failed: int=checks.filter(func(row: Dictionary): return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"native Control geometry and exact display behavior over actual authority with explicit target DTOs; no actual selection/reach/OS/VA/renderer/package acceptance"},"\t",true,true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
