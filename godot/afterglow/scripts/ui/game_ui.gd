extends Control
## Native UI: read one display snapshot and send intentions to A's runtime/router.
const UiProjection = preload("res://scripts/ui/ui_projection.gd")
const Layout = preload("res://scripts/ui/inventory_layout.gd")
const Slot = preload("res://scripts/ui/inventory_slot.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const WorkshopVitals = preload("res://scripts/ui/workshop_vitals.gd")
const UiDelta = preload("res://scripts/ui/ui_delta.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const WorkModes = preload("res://scripts/ui/ui_work_modes.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const Recovery = preload("res://scripts/ui/recovery_menu.gd")
const Factory = preload("res://scripts/ui/factory_projection.gd")
const FactoryOps = preload("res://scripts/ui/factory_operations.gd")
const FactoryPanels = preload("res://scripts/ui/factory_panels.gd")
const Handbook = preload("res://scripts/ui/factory_handbook.gd")
const Water = preload("res://scripts/ui/factory_water.gd")
const Identity = preload("res://scripts/ui/ui_identity.gd")
const CompanionCard = preload("res://scripts/ui/companion_action_card.gd")
const BuildPlacementCard = preload("res://scripts/ui/build_placement_card.gd")
const Composition = preload("res://scripts/ui/ui_composition.gd")
const TargetPrompt = preload("res://scripts/ui/target_prompt_layout.gd")
const ZonePlanning = preload("res://scripts/ui/zone_planning.gd")
const Housing = preload("res://scripts/ui/housing_panel.gd")
const Feedback19 = preload("res://scripts/ui/ui_feedback19.gd")
const ExpeditionHud = preload("res://scripts/ui/expedition_hud.gd")
const ChapterPanel = preload("res://scripts/ui/chapter_panel.gd")
const LIVE_REFRESH_USEC := 100000
const DEFAULT_NEW_WORLD_SEED := 713

var runtime: Object
var input_router: Object
var snapshot: Dictionary = {}
var factory: Dictionary = {}
var chapter_stock:Dictionary={}
var _seen_chapter_status:Dictionary={}
var _scene_selection:Dictionary={}
var factory_view: Dictionary = {}
var factory_favorites: Dictionary = {}
var handbook: Dictionary = {}
var handbook_serial := 0
var _service_access_key: Array = []
var _service_access_value: Dictionary = {}
var _workforce_details: Dictionary = {}
var workforce_detail_reads := 0
var _route_scrolls: Dictionary = {}
var layout := Layout.new()
var pages: Array = []
var carry: Dictionary = {}
var drag: Dictionary = {}
var capture_action := ""
var saving := false
var exporting := false
var importing := false
var world_starting := false
var world_restoring := false
var text_scale := 1.0
var _generation := 0
var _serial := 0
var _refresh_queued := false
var _last_refresh_us := 0
var _live_refresh_pending := false
var _live_timer_pending := false
var _panel_dirty := false
var _choice_popup: WeakRef
var _pressed_control: WeakRef
var _panel_views:Dictionary={}
var _body_route:=""
var _body_signature:=0
var _body_cacheable:=false
var _panel_view_hits:=0
var _navigation_basis:Array=[]
var _known_map_canvas:Control
var _known_map_focus_label:Label
var _page_read_basis:Dictionary={}
var _page_reads:Dictionary={}
var _page_read_serial:int=0
var _workforce_refresh_serial:int=0
var _font: Font
var _hud_backdrop: PanelContainer
var _expedition_hud: VBoxContainer
var _expedition_hud_phase := ""
var _hud: VBoxContainer
var _navigation: HBoxContainer
var _personal_navigation: HFlowContainer
var _inventory_button:Button
var _pause_button:Button
var _factory_navigation: PanelContainer
var _factory_alert: Button
var _companions: VBoxContainer
var _companion_signature := 0
var _companion_buttons: Dictionary = {}
var _vitals: Control
var _pickup_hint: Label
var _pickup_toast: Label
var _pickup_tween: Tween
var _hotbar_nodes: Dictionary = {}
var _hotbar_input_signature := 0
var _hud_pack_basis: Array = []
var _hud_pack_entries: Dictionary = {}
var _hud_pack_rebuilds := 0
var _shell_layout_basis: Array = []
var _status: Label
var _need_labels: Dictionary = {}
var _scene_hint: Label
var _mode_hint: Label
var _movement_hint: Label
var _profile_hint: Label
var _work_progress: ProgressBar
var _repair_details:Button
var _notice: Label
var _world_notice: PanelContainer
var _build_placement_card: BuildPlacementCard
var _hud_entry_focus: WeakRef
var _panel_notice: Label
var _modal_policy_hint: Label
var _storage_status: Label
var _target: PanelContainer
var _target_text: Label
var _progress: ProgressBar
var _hotbar: HBoxContainer
var _modal_hotbar: HBoxContainer
var _modal: ColorRect
var _dialog: PanelContainer
var _workspace: HBoxContainer
var _panel_navigation: VBoxContainer
var _planning_navigation: HFlowContainer
var _body: VBoxContainer
var _planning_footer: VBoxContainer
var _title: Label
var _scroll: ScrollContainer
var _split_layer: PanelContainer
var _file_dialog: FileDialog
var _file_operation := ""
var _hotbar_signature: int = 0
var _panel_signature: int = 0
var _panel_render_serial := 0
var _recent_crafts: Dictionary = {}
var _close_receipt: Dictionary = {}
var _new_world_receipt: Dictionary = {}
var _new_world_seed_text := ""
var _new_world_profile := "normal"
var _back_button: Button
var _seen_feedback: Dictionary = {}
var _notice_serial := 0
var _movement_feedback: Dictionary = {}
var _movement_feedback_serial := 0
var _closing_wait := false
var _modal_router_active: Variant = null
var _modal_router_pause_world: Variant = null
var _recovery_menu: Control
var _drag_trace_enabled := false
var _drag_trace_count := 0
var zone_planning := ZonePlanning.new()
var housing_view := Housing.new()

func configure(authority: Object, router: Object) -> void:
	_disconnect_authority()
	_clear_panel_views()
	_invalidate_page_reads()
	if is_instance_valid(_recovery_menu): _recovery_menu.queue_free()
	_recovery_menu = null
	if is_instance_valid(input_router) and input_router.has_method("set_modal"): input_router.call("set_modal", false)
	if is_instance_valid(input_router) and input_router.has_method("set_file_dialog"): input_router.call("set_file_dialog", false)
	_generation += 1
	_last_refresh_us = 0
	_live_refresh_pending = false
	_live_timer_pending = false
	runtime = authority
	input_router = router
	layout.clear()
	factory.clear()
	handbook.clear()
	handbook_serial += 1
	factory_view.clear()
	zone_planning.reset()
	housing_view.reset()
	factory_favorites.clear()
	_service_access_key.clear()
	_service_access_value.clear()
	_workforce_details.clear()
	workforce_detail_reads = 0
	_route_scrolls.clear()
	pages.clear()
	carry.clear()
	drag.clear()
	capture_action = ""
	saving = false
	exporting = false
	importing = false
	world_starting = false
	world_restoring = false
	_modal_router_active = null
	_modal_router_pause_world = null
	_new_world_receipt.clear()
	_new_world_seed_text = ""
	_hotbar_signature = 0
	_hotbar_input_signature = 0
	_hud_pack_basis.clear()
	_hud_pack_entries.clear()
	_hud_pack_rebuilds = 0
	_companion_signature = 0
	_companion_buttons.clear()
	_panel_signature = 0
	_panel_render_serial += 1
	_pressed_control = null
	_recent_crafts.clear()
	_movement_feedback.clear()
	_movement_feedback_serial += 1
	_seen_feedback.clear()
	_hud_entry_focus = null
	_closing_wait = false
	_close_receipt.clear()
	if is_instance_valid(runtime) and runtime.has_signal("changed"):
		runtime.connect("changed", _on_changed)
	if is_instance_valid(input_router) and input_router.has_signal("panel_requested"):
		input_router.connect("panel_requested", open_panel)
	if is_instance_valid(input_router) and input_router.has_signal("open_requested"):
		input_router.connect("open_requested", open_panel)
	if is_instance_valid(input_router) and input_router.has_signal("save_requested"):
		input_router.connect("save_requested", save_world)
	if is_instance_valid(input_router) and input_router.has_signal("changed"):
		input_router.connect("changed", _on_router_changed)
	if is_instance_valid(input_router) and input_router.has_signal("combat_ready_changed"):
		input_router.connect("combat_ready_changed", _on_combat_ready_changed)
	if is_instance_valid(runtime) and runtime.has_signal("close_failed"):
		runtime.connect("close_failed", _on_close_failed)
	if is_node_ready():
		_mount_build_placement_card()
		notify("")
		_sync_modal()
		refresh()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_trace_enabled = "--ui-drag-trace" in OS.get_cmdline_user_args()
	_font = load("res://themes/fonts/NotoSansCJKsc-Regular.otf")
	theme = UiTheme.create(_font)
	_build_shell()
	get_window().focus_exited.connect(_on_focus_exited)
	resized.connect(_size_dialog)
	get_viewport().gui_focus_changed.connect(_gui_focus_changed)
	refresh()
	# A finalizes the mount receipt after adding this new view.
	queue_refresh()

func _temporal_change_only(changes: Dictionary) -> bool:
	# Only display pacing: actions and unknown notifications retain immediate reads.
	if changes.is_empty(): return false # Router changed has no payload.
	if changes.has("clock"):
		for key in changes:
			if key not in ["clock", "revision", "simulation"]: return false
		if changes.has("simulation") and not _simulation_diagnostics_only(changes.simulation): return false
		return true
	for key in changes:
		if key not in ["world", "facts", "events", "revision", "actor_transitions"]: return false
	if changes.has("actor_transitions") and (not changes.actor_transitions is Array or not changes.actor_transitions.is_empty()): return false
	if not changes.get("world") is Array or not changes.world.is_empty(): return false
	if not changes.get("events") is Array or not changes.get("facts") is Array: return false
	if changes.events.is_empty():
		# Needs publication can share the existing clock-paced HUD read. Work,
		# permissions, health, equipment and action events still repaint now.
		return not changes.facts.is_empty() and changes.facts.all(_actor_needs_only)
	for event in changes.events:
		if not event is Dictionary or event.get("kind") != "actor-moved": return false
	for fact in changes.facts:
		if not fact is Dictionary or fact.get("collection") != "actors": return false
	return true

static func _actor_needs_only(fact: Variant) -> bool:
	if not fact is Dictionary or fact.get("collection") != "actors": return false
	var before: Variant = fact.get("before")
	var after: Variant = fact.get("after")
	if not before is Dictionary or not after is Dictionary: return false
	if before.get("id") != fact.get("id") or after.get("id") != fact.get("id"): return false
	if before.size() != after.size(): return false
	for key: Variant in before:
		if not after.has(key): return false
		if before[key] == after[key]: continue
		if key not in ["hunger", "thirst", "fatigue", "stamina", "cooldown", "nextDecision"]: return false
		if not (before[key] is float or before[key] is int) or not (after[key] is float or after[key] is int): return false
	return true

func _simulation_diagnostics_only(value: Variant) -> bool:
	# Runtime.simulation_budget's current read-only counters only. A new field,
	# malformed value or lifecycle payload must bypass display pacing.
	if not value is Dictionary: return false
	for key in value:
		if key == "policy":
			if value[key] != "bounded-catch-up-preserve-debt": return false
		elif key == "waiting_for_geometry":
			if not value[key] is bool: return false
		elif key in ["frames", "steps", "last_steps", "last_usec", "max_step_usec", "max_backlog", "over_budget", "step_seconds", "max_steps_per_frame", "budget_usec", "backlog_seconds", "pending_steps"]:
			if not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key]) < 0: return false
		else: return false
	return true

func _queue_live_refresh() -> void:
	_live_refresh_pending = true
	if _refresh_queued: return
	var remaining := LIVE_REFRESH_USEC - (Time.get_ticks_usec() - _last_refresh_us)
	if _live_timer_pending: return
	_live_timer_pending = true
	if remaining <= 0:
		# Clock and motion updates are already paced. Place their HUD read on
		# the following frame instead of adding it to the same simulation step.
		get_tree().process_frame.connect(_flush_live_refresh.bind(_generation), CONNECT_ONE_SHOT)
	else:
		get_tree().create_timer(float(remaining) / 1000000.0, true).timeout.connect(_flush_live_refresh.bind(_generation))

func _flush_live_refresh(generation: int, deferred_once: bool = false) -> void:
	# The frame signal runs before the simulation. Check the display budget
	# after the nodes have processed, just before this low-priority HUD read.
	call_deferred("_finish_live_refresh", generation, deferred_once)

func _finish_live_refresh(generation: int, deferred_once: bool) -> void:
	if generation != _generation:
		return
	if _live_refresh_pending and not _refresh_queued and not deferred_once and runtime.has_method("reserve_periodic_display_frame"):
		if not runtime.reserve_periodic_display_frame():
			get_tree().process_frame.connect(_flush_live_refresh.bind(generation, true), CONNECT_ONE_SHOT)
			return
	_live_timer_pending = false
	if _live_refresh_pending:
		queue_refresh()

func _exit_tree() -> void:
	_generation += 1
	_clear_panel_views()
	_disconnect_authority()
	if is_instance_valid(input_router) and input_router.has_method("set_modal"):
		input_router.call("set_modal", false)
	if is_instance_valid(input_router) and input_router.has_method("set_file_dialog"):
		input_router.call("set_file_dialog", false)

func _disconnect_authority() -> void:
	if is_instance_valid(runtime) and runtime.has_signal("changed") and runtime.is_connected("changed", _on_changed):
		runtime.disconnect("changed", _on_changed)
	if is_instance_valid(input_router) and input_router.has_signal("panel_requested") and input_router.is_connected("panel_requested", open_panel):
		input_router.disconnect("panel_requested", open_panel)
	if is_instance_valid(input_router) and input_router.has_signal("open_requested") and input_router.is_connected("open_requested", open_panel):
		input_router.disconnect("open_requested", open_panel)
	if is_instance_valid(input_router) and input_router.has_signal("save_requested") and input_router.is_connected("save_requested",save_world):
		input_router.disconnect("save_requested",save_world)
	if is_instance_valid(input_router) and input_router.has_signal("changed") and input_router.is_connected("changed", _on_router_changed):
		input_router.disconnect("changed", _on_router_changed)
	if is_instance_valid(input_router) and input_router.has_signal("combat_ready_changed") and input_router.is_connected("combat_ready_changed", _on_combat_ready_changed):
		input_router.disconnect("combat_ready_changed", _on_combat_ready_changed)
	if is_instance_valid(runtime) and runtime.has_signal("close_failed") and runtime.is_connected("close_failed", _on_close_failed):
		runtime.disconnect("close_failed", _on_close_failed)

func _build_shell() -> void:
	_hud_backdrop = PanelContainer.new()
	_hud_backdrop.position = Vector2(20, 18)
	_hud_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_backdrop.add_theme_stylebox_override("panel", UiTheme.chrome("panel"))
	add_child(_hud_backdrop)
	_hud = VBoxContainer.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_constant_override("separation", 3)
	_hud_backdrop.add_child(_hud)
	_status = label("正在连接世界…")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 380
	_hud.add_child(_status)
	_vitals = WorkshopVitals.new()
	_hud.add_child(_vitals)
	_expedition_hud = ExpeditionHud.new()
	_hud.add_child(_expedition_hud)
	_pickup_hint = label("")
	_pickup_hint.theme_type_variation = "Caption"
	_pickup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pickup_hint.max_lines_visible = 1
	_pickup_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud.add_child(_pickup_hint)
	var needs := HFlowContainer.new()
	needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(needs)
	needs.hide()
	for spec in [["hunger", "饥饿"], ["thirst", "饮水"], ["stamina", "体力"], ["fatigue", "疲劳"], ["wounds", "伤势"]]:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		needs.add_child(row)
		var texture := Icons.status_texture(str(spec[0]))
		if texture != null: row.add_child(Icons.image(texture, 18))
		var value := label("")
		value.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		value.add_theme_constant_override("shadow_offset_y", 2)
		row.add_child(value)
		_need_labels[str(spec[0])] = {"row":row, "label":value, "name":spec[1]}
	_scene_hint = label("")
	_scene_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scene_hint.custom_minimum_size.x = 380
	_scene_hint.add_theme_color_override("font_color", UiTheme.MOSS)
	_hud.add_child(_scene_hint)
	_mode_hint = label("")
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.custom_minimum_size.x = 380
	_hud.add_child(_mode_hint)
	_movement_hint = label("")
	_movement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_movement_hint.custom_minimum_size.x = 380
	_hud.add_child(_movement_hint)
	_profile_hint = label("")
	_profile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_hint.max_lines_visible = 1
	_profile_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_profile_hint.custom_minimum_size.x = 380
	_profile_hint.add_theme_color_override("font_color", UiTheme.SECONDARY)
	_hud.add_child(_profile_hint)
	_work_progress = ProgressBar.new()
	_work_progress.step = 0.0
	_work_progress.custom_minimum_size = Vector2(280, 5)
	_work_progress.show_percentage = false
	_work_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_work_progress)
	_repair_details=button("施工详情",func():
		var current:Dictionary=snapshot.get("player_work",{})
		if not str(current.get("module_id","")).is_empty():open_panel("factory_module",str(current.module_id)),"hud:repair:details")
	_repair_details.theme_type_variation="QuietButton";_repair_details.hide();_hud.add_child(_repair_details)
	var navigation := HBoxContainer.new()
	_navigation = navigation
	navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(navigation)
	for entry in [["背包", "inventory"], ["任务", "quests"], ["暂停", "pause"]]:
		var action := button(entry[0], func(): open_panel(entry[1]), "hud:" + entry[1])
		if entry[1] == "inventory":
			action.icon = Icons.status_texture("inventory")
			action.expand_icon = true
			action.add_theme_constant_override("icon_max_width", 18)
		navigation.add_child(action)
	_personal_navigation=HFlowContainer.new()
	_personal_navigation.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_personal_navigation)
	_inventory_button=button("背包",func():open_panel("inventory"),"hud:personal:inventory")
	_inventory_button.icon=Icons.status_texture("inventory")
	_inventory_button.expand_icon=true
	_inventory_button.add_theme_constant_override("icon_max_width",18)
	_personal_navigation.add_child(_inventory_button)
	_pause_button=button("暂停",func():open_panel("pause"),"hud:personal:pause")
	_personal_navigation.add_child(_pause_button)
	_world_notice = PanelContainer.new()
	_world_notice.name = "WorldNotice"
	_world_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_notice.add_theme_stylebox_override("panel", UiTheme.chrome("panel"))
	_world_notice.hide()
	add_child(_world_notice)
	_notice = label("")
	_notice.hide()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.max_lines_visible = 3
	_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_world_notice.add_child(_notice)
	_world_notice.minimum_size_changed.connect(_position_feedback)
	_world_notice.resized.connect(_position_feedback)
	_storage_status = label("")
	_storage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_storage_status.custom_minimum_size.x = 380
	_hud.add_child(_storage_status)
	_factory_navigation = PanelContainer.new()
	_factory_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_factory_navigation)
	var factory_nav := VBoxContainer.new()
	_factory_navigation.add_child(factory_nav)
	var companion_title := label("同伴与村务")
	companion_title.theme_type_variation="SectionTitle"
	factory_nav.add_child(companion_title)
	_companions = VBoxContainer.new()
	factory_nav.add_child(_companions)
	var factory_links := HFlowContainer.new()
	factory_nav.add_child(factory_links)
	for spec in [["设施", "factory"], ["建造", "factory_catalog"], ["库存", "factory_stock"], ["区域", "zone_planning"], ["任务", "quests"], ["手册", "factory_handbook"]]:
		var link := button(spec[0], func(): open_panel(spec[1]), "hud:" + spec[1])
		link.icon = UiTheme.control_glyph(str({"factory":"crate","factory_catalog":"house","factory_stock":"crate","zone_planning":"map","quests":"book","factory_handbook":"book"}[spec[1]]),1.0)
		factory_links.add_child(link)
	_factory_alert = button("", func(): open_panel("factory_alerts"), "hud:factory_alerts")
	_factory_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	factory_nav.add_child(_factory_alert)
	_factory_navigation.hide()
	for text: Label in [_status, _scene_hint, _mode_hint, _movement_hint, _profile_hint, _notice, _storage_status]:
		text.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		text.add_theme_constant_override("shadow_offset_x", 1)
		text.add_theme_constant_override("shadow_offset_y", 2)
	_target = PanelContainer.new()
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prompt_style := UiTheme.box(UiTheme.BASE, UiTheme.EDGE)
	prompt_style.content_margin_left = 8; prompt_style.content_margin_right = 8
	prompt_style.content_margin_top = 8; prompt_style.content_margin_bottom = 8
	_target.add_theme_stylebox_override("panel", prompt_style)
	add_child(_target)
	_target.resized.connect(_position_target)
	_target.minimum_size_changed.connect(func():
		# Wrapped text resolves its native minimum after the container's first
		# sort, including the first appearance of a formerly hidden prompt.
		_target.size.y = _target.get_combined_minimum_size().y
		_position_target())
	var target_body := VBoxContainer.new()
	target_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_body.add_theme_constant_override("separation", 4)
	_target.add_child(target_body)
	_target_text = label("")
	_target_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_target_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_text.max_lines_visible = 3
	_target_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_target_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_body.add_child(_target_text)
	_progress = ProgressBar.new()
	_progress.step = 0.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 5
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_body.add_child(_progress)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 8)
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.offset_left = -315
	_hotbar.offset_right = 315
	_hotbar.offset_top = -124
	_hotbar.offset_bottom = -24
	add_child(_hotbar)
	_pickup_toast = label("")
	_pickup_toast.theme_type_variation = "SectionTitle"
	_pickup_toast.add_theme_color_override("font_color", UiTheme.SURFACE)
	_pickup_toast.add_theme_color_override("font_shadow_color", UiTheme.INK)
	_pickup_toast.add_theme_constant_override("shadow_outline_size", 4)
	_pickup_toast.add_theme_constant_override("shadow_offset_y", 2)
	_pickup_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_toast.offset_left = -250; _pickup_toast.offset_right = 250
	_pickup_toast.offset_top = -170; _pickup_toast.offset_bottom = -126
	_pickup_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_toast.hide()
	add_child(_pickup_toast)
	_modal = ColorRect.new()
	_modal.color = Color(0.025, 0.035, 0.03, 0.55)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.mouse_force_pass_scroll_events = false
	_modal.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _dialog.grab_focus())
	_modal.hide()
	add_child(_modal)
	_dialog = PanelContainer.new()
	_dialog.theme_type_variation = "WorkshopPanel"
	_dialog.focus_mode = Control.FOCUS_ALL
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog.mouse_force_pass_scroll_events = false
	_modal.add_child(_dialog)
	var column := VBoxContainer.new()
	_dialog.add_child(column)
	var title_plate := PanelContainer.new()
	title_plate.theme_type_variation = "WorkshopTitle"
	title_plate.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(title_plate)
	var header := HBoxContainer.new()
	title_plate.add_child(header)
	_title = label("")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.theme_type_variation = "PageTitle"
	header.add_child(_title)
	_back_button = button("Esc 返回", cancel_ui, "dialog:back")
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(_back_button)
	_planning_navigation = HFlowContainer.new()
	_planning_navigation.hide()
	column.add_child(_planning_navigation)
	_panel_notice = label("")
	_panel_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_notice.max_lines_visible = 3
	_panel_notice.hide()
	column.add_child(_panel_notice)
	# Navigation belongs to the window, not to the document being scrolled.
	# Management uses a compact rail; planning keeps a narrow return strip so
	# the world remains the placement canvas. Objects retain their direct view.
	_workspace = HBoxContainer.new()
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_workspace)
	_panel_navigation = VBoxContainer.new()
	_panel_navigation.hide()
	_workspace.add_child(_panel_navigation)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_workspace.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_body.minimum_size_changed.connect(func(): _fit_sparse_panel.call_deferred(_panel_render_serial))
	_planning_footer = VBoxContainer.new()
	_planning_footer.hide()
	column.add_child(_planning_footer)
	_modal_hotbar = HBoxContainer.new()
	_modal_hotbar.add_theme_constant_override("separation", 8)
	_modal_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_modal_hotbar)
	_modal_hotbar.minimum_size_changed.connect(func(): _fit_sparse_panel.call_deferred(_panel_render_serial))
	_modal_policy_hint = label("界面内暂停 · 关闭后行动继续")
	_modal_policy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_modal_policy_hint)
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.json ; 世界检查点"])
	_file_dialog.file_selected.connect(_file_selected)
	_file_dialog.canceled.connect(_file_cancelled)
	add_child(_file_dialog)
	_mount_build_placement_card()
	_size_dialog()

func _mount_build_placement_card() -> void:
	if is_instance_valid(_build_placement_card):
		remove_child(_build_placement_card)
		_build_placement_card.queue_free()
	var card := BuildPlacementCard.new()
	card.name = "BuildPlacementCard"
	card.configure(self)
	card.resized.connect(_position_feedback, CONNECT_DEFERRED)
	add_child(card)
	_build_placement_card = card

func _size_dialog() -> void:
	if not is_instance_valid(_dialog): return
	var viewport_size := get_viewport_rect().size
	var compact := Factory.enabled(factory)
	var page := str(pages.back().page) if not pages.is_empty() else "pause"
	var count := Factory.rows(factory,"modules","instances").size() if page=="factory" else Factory.rows(factory,"workforce","members").size() if page=="factory_people" else 0
	var layout_basis:Array=[viewport_size,text_scale,compact,page,count,_expedition_hud_phase]
	if layout_basis == _shell_layout_basis: return
	_shell_layout_basis=layout_basis
	var hud_width := _hud_width(viewport_size.x, compact)
	_hud_backdrop.size = Vector2(hud_width, 0)
	var bounds := Composition.bounds(viewport_size, page, text_scale)
	if page in ["factory", "factory_people"]:
		var rows := Factory.rows(factory, "modules", "instances") if page == "factory" else Factory.rows(factory, "workforce", "members")
		var width := (780.0 if rows.size() > 1 else 560.0) if page == "factory" else (860.0 if rows.size() > 2 else 640.0)
		bounds.size.x = minf(width * minf(text_scale, 1.2), viewport_size.x - 32)
		bounds.position.x = (viewport_size.x - bounds.size.x) * 0.5
	_dialog.position = bounds.position
	_dialog.size = bounds.size
	var form := Composition.form(page)
	_modal.color = Color(0.025, 0.025, 0.025, 0.14 if form in ["object", "planning"] else 0.52)
	if is_instance_valid(_factory_navigation):
		var rail_width := minf(280 * text_scale, viewport_size.x * 0.32)
		_factory_navigation.position = Vector2(viewport_size.x - rail_width - 16, 16)
		_factory_navigation.size = Vector2(rail_width, 0)
	_position_feedback.call_deferred()
	_size_split_layer()
	if page in ["factory", "factory_people"]: _fit_sparse_panel.call_deferred(_panel_render_serial)

func _hud_width(view_width: float, compact: bool) -> float:
	return minf(314 * text_scale, view_width * 0.34) if compact else minf(420, view_width - 40)

func _fit_sparse_panel(render_serial: int) -> void:
	if render_serial != _panel_render_serial or pages.is_empty() or str(pages.back().page) not in ["factory", "factory_people"]: return
	# The native containers measure wrapped text/cards at the actual width.
	# Scroll only when content exceeds the available height; sparse pages do
	# not reserve the entire screen for nonexistent people or facilities.
	# Use native minimum sizes, not the scroll area's last allocated height:
	# a resize/render may have reset the dialog before containers are sorted.
	var chrome := maxf(0, _dialog.get_combined_minimum_size().y - _workspace.get_combined_minimum_size().y)
	var content_height := maxf(_body.get_combined_minimum_size().y, _panel_navigation.get_combined_minimum_size().y if _panel_navigation.visible else 0)
	var height := clampf(content_height + chrome + 8, 240, get_viewport_rect().size.y - 32)
	_dialog.size.y = height
	_dialog.position.y = (get_viewport_rect().size.y - height) * 0.5

func _size_split_layer() -> void:
	if not is_instance_valid(_split_layer): return
	var span := _split_layer.get_combined_minimum_size().max(Vector2(380, 180))
	_split_layer.size = span
	_split_layer.position = (get_viewport_rect().size - span) * 0.5

# A revalidates authority, current region and real entity geometry. This is
# only the fixed context being viewed, never the pointer hover or permission.
func world_view_selection() -> Dictionary:
	if pages.is_empty(): return _scene_selection.duplicate()
	var route: Dictionary = pages.back()
	var id := str(route.get("subject", ""))
	if id.is_empty(): return {}
	match str(route.page):
		"factory_module": return {"kind":"module", "id":id}
		"water": return {"kind":"water", "id":id}
		"npc", "npc_quick": return {"kind":"npc", "id":id}
		"container", "factory_inventory": return {"kind":"container", "id":id}
	return {}

func select_scene_target(target:Dictionary)->void:
	_scene_selection={"id":str(target.id),"kind":str(target.get("kind","")),"entity_id":str(target.get("entity_id",target.id)),"name":str(target.get("name",""))} if not target.is_empty() else {}
	queue_refresh()

func open_scene_work(target: Dictionary, person: String = "") -> bool:
	if world_change_busy() or not carry.is_empty() or not drag.is_empty() or is_zone_planning():
		return false
	if not person.is_empty():
		return point_companion(person)
	var primary: String = target.get("primary", "")
	if primary == "module":
		var module_id: String = target.id
		factory_view["building_tab:" + module_id] = "use"
		var preferred: String = str(pages.back().subject) if not pages.is_empty() and pages.back().page == "npc_quick" else ""
		open_panel("factory_module", module_id, preferred)
		return true
	if primary not in ["harvest", "pickup"] or runtime.expedition_snapshot().is_empty():
		return false
	var location: Dictionary = target.get("location", {})
	if location.is_empty():
		return false
	var preferred: String = str(pages.back().subject) if not pages.is_empty() and pages.back().page == "npc_quick" else ""
	var worker: String = preferred if not preferred.is_empty() else village_worker("scout_hauler")
	if worker.is_empty():
		notify("没有能接这项工作的同伴", true)
		return true
	var cell_size: float = runtime.world.config().cellSize
	var x := floori(float(location.x) / cell_size)
	var z := floori(float(location.z) / cell_size)
	if primary == "pickup":
		start_companion_area(worker, "haul")
		zone_planning.set_scoped_target(self, location.regionId, x, z)
		return true
	var spec := {"kind":"forestry", "region_id":location.regionId, "bounds":{"x0":x,"z0":z,"x1":x+1,"z1":z+1},
		"policy":{"mode":"harvest_only","worker_ids":[worker],"priority":4,"replant":false,"mature_only":true}}
	var result := execute("zone.create", "", {"spec":spec})
	if result.get("ok", false):
		var actor: Dictionary = runtime.actor(worker)
		notify("%s将采伐这棵树并运回木料" % actor.get("name", "同伴"))
	return true

func village_worker(role: String, candidate_id: String = "") -> String:
	var choices: Array[Dictionary] = []
	for actor: Dictionary in UiProjection.records(snapshot.get("actors", [])):
		var relation: Dictionary = actor.get("relationship", {})
		if actor.id == "player" or float(actor.hp) <= 0 or not relation.get("member", false) or not relation.get("consent", false) or actor.get("expedition_follow", false):
			continue
		var assignment := Factory.find(Factory.rows(factory, "workforce", "assignments"), str(actor.id), "actor_id")
		var phase: String = assignment.get("building_phase", assignment.get("work_phase", ""))
		if not candidate_id.is_empty() and not assignment.is_empty() and phase not in ["completed", "ended"]:
			continue
		var command := request("workforce.assign", "", {"candidate_id":candidate_id}) if not candidate_id.is_empty() else {}
		if not command.is_empty():
			command.actor_id = actor.id
			if not availability(command).get("ok", false):
				continue
		var score: int = 2 if actor.get("role_id") == role else 0
		if actor.get("pending_delivery", {}).get("phase") == "deliver":
			score -= 3
		choices.append({"id":actor.id,"score":score})
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score if a.score != b.score else a.id < b.id)
	return str(choices[0].id) if not choices.is_empty() else ""

func planning_active() -> bool:
	if is_zone_planning(): return true
	if not pages.is_empty() and pages.back().page == "npc_quick": return true
	if pages.is_empty() or str(pages.back().page) not in ["factory_catalog", "build", "terrain"]: return false
	var hand: Dictionary = input_router.call("state") if is_instance_valid(input_router) and input_router.has_method("state") else snapshot.get("hand", {})
	return str(hand.get("mode", "")) in ["module_place", "facility_place"] or str(hand.get("mode", "")).begins_with("terrain_")

func is_zone_planning() -> bool:
	return not pages.is_empty() and str(pages.back().page) == "zone_planning"

func is_companion_building_pick() -> bool:
	return not pages.is_empty() and pages.back().page == "npc_quick" and pages.back().get("building_pick",false)

func handle_world_click(hit: Dictionary, event: InputEvent) -> bool:
	if not is_zone_planning(): return false
	if world_change_busy() or not carry.is_empty() or not drag.is_empty() or not capture_action.is_empty():
		zone_planning.finish_pointer(self); return true
	var hovered := get_viewport().gui_get_hovered_control()
	if is_instance_valid(hovered) and (_dialog == hovered or _dialog.is_ancestor_of(hovered)):
		if zone_planning.drawing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			zone_planning.handle_world_click(self, {}, event)
		return true
	var focus := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and (focus is LineEdit or focus is TextEdit) and _dialog.is_ancestor_of(focus): return true
	return zone_planning.handle_world_click(self, hit, event)

func planning_view() -> Dictionary:
	return zone_planning.view(is_zone_planning())

func _flush_zone_preview(generation: int) -> void:
	zone_planning.flush_preview(self, generation)

func label(text: String) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func paragraph(text: String, parent: Node = null) -> Label:
	var node := label(text)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent != null else _body).add_child(node)
	return node

func button(text: String, action: Callable, focus_key: String = "", reason: String = "") -> Button:
	var node := Button.new()
	node.text = text
	# Native short actions need their text width in HBox/HFlow minimum sizes.
	# Wrapping here reduces them to the style's 24px minimum and turns the
	# back/handbook actions into tall clipped strips that inflate whole rows.
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.tooltip_text = UiProjection.reason_text(reason) if not reason.is_empty() else ""
	node.disabled = not reason.is_empty()
	node.set_meta("ui_focus_key", focus_key)
	node.pressed.connect(action)
	Feedback19.bind(node)
	return node

func add_button(text: String, action: Callable, key: String, reason: String = "", parent: Node = null) -> Button:
	var node := button(text, action, key, reason)
	var container: Node = parent if parent != null else _body
	# Full-width vertical actions can wrap long names at the allocated width.
	# Native horizontal/flow rows wrap the action controls themselves instead.
	if not container is HBoxContainer and not container is HFlowContainer:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(node)
	if reason in ["已选择", "当前页面"]: node.theme_type_variation = "PrimaryButton"
	elif not reason.is_empty() and reason not in ["已是第一页", "已是最后一页"]:
		var target: Node = parent if parent != null else _body
		# Dictionary keys may contain full Chinese reasons; metadata identifiers may not.
		var reasons: Dictionary = target.get_meta("ui_reason_cache", {})
		if not reasons.has(reason):
			reasons[reason] = true
			target.set_meta("ui_reason_cache", reasons)
			var note: Label = Composition.caption(self, UiProjection.reason_text(reason), target)
			note.tooltip_text = reason
	return node

func _on_changed(changes: Dictionary = {}) -> void:
	if _temporal_change_only(changes):
		if changes.has("facts"): housing_view.invalidate()
		_queue_live_refresh()
		return
	# A's inexpensive basis fences zone/world generations and permission. Known
	# actor/clock/stock commits need not re-copy the unchanged list/selection.
	var unknown := changes.is_empty()
	for key in changes:
		if key not in ["world","facts","events","revision","actor_transitions","clock","simulation"]: unknown=true
	if unknown:
		_invalidate_page_reads()
		_workforce_details.clear();_workforce_refresh_serial+=1
	if unknown or not is_instance_valid(runtime) or not runtime.has_method("zone_view_basis"): zone_planning.invalidate()
	if unknown or changes.has("facts") or changes.has("world") or changes.has("actor_transitions"):housing_view.invalidate()
	for event: Dictionary in UiProjection.records(changes.get("events", [])):
		if str(event.get("actor_id", event.get("actorId", ""))) != str(UiProjection.player(snapshot).get("id", "")): continue
		var kind := str(event.get("kind", ""))
		var text: String = {"crafted":"制作已完成", "learned":"知识已掌握", "tool-repaired":"工具已维修", "tree-felled":"采伐完成，物资在树旁", "structure-completed":"构件作业已完成"}.get(kind, "")
		var id := str(event.get("id", event.get("order_id", "")))
		if text.is_empty() or id.is_empty() or _seen_feedback.has(id): continue
		_seen_feedback[id] = true
		if _seen_feedback.size() > 64: _seen_feedback.erase(_seen_feedback.keys()[0])
		notify(text + " · " + str(event.get("target_id", event.get("targetId", ""))))
	queue_refresh()

func _on_router_changed() -> void:
	# Hover/hand/focus changes do not mutate zone records. The actual runtime
	# callback above retains immediate invalidation for unknown/permission edits.
	queue_refresh()

func report_action(receipt: Dictionary) -> void:
	# A can forward scene-input rejections here. Accepted work is not declared complete.
	if not receipt.get("ok", false):
		notify("操作未完成 · " + UiProjection.feedback_text(receipt, _feedback_target(), "当前操作被拒绝"), true, UiProjection.feedback_diagnostic(receipt))

func report_movement(receipt: Dictionary) -> void:
	# Only A's attempted-movement route may supply this view receipt.
	# A far mouse target is never interpreted as a failed WASD attempt.
	if receipt.get("ok", false) and _movement_feedback.is_empty(): return
	# The direct route runs every movement frame. One unchanged refusal needs
	# one display timer, not a new timer and snapshot refresh on every frame.
	if not receipt.get("ok", false) and not _movement_feedback.is_empty() and receipt.get("code") == _movement_feedback.get("code") and receipt.get("reason") == _movement_feedback.get("reason"): return
	_movement_feedback_serial += 1
	_movement_feedback = {} if receipt.get("ok", false) else receipt.duplicate(true)
	if not _movement_feedback.is_empty():
		get_tree().create_timer(4.0, true).timeout.connect(_expire_movement_feedback.bind(_movement_feedback_serial))
	queue_refresh()

func _expire_movement_feedback(serial: int) -> void:
	if serial != _movement_feedback_serial or not is_node_ready(): return
	_movement_feedback.clear()
	queue_refresh()

func _feedback_target() -> Dictionary:
	# The direct-input adapter may notify before the next UI refresh.
	var current: Dictionary = snapshot
	if is_instance_valid(runtime):
		if runtime.has_method("ui_read_basis"):
			var basis:Variant=runtime.call("ui_read_basis")
			if basis is Dictionary and basis.get("target") is Dictionary:return basis.target
		if runtime.has_method("snapshot"):
			var value: Variant = runtime.call("snapshot")
			if value is Dictionary: current = value
	return current.get("target", {}) if current.get("target") is Dictionary else {}

func queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	call_deferred("_flush_refresh")

func _flush_refresh() -> void:
	if not _refresh_queued:return
	_refresh_queued = false
	if is_inside_tree(): refresh()

func refresh() -> void:
	# A synchronous route refresh consumes notifications queued before it.
	# A genuinely new notification raised during the read queues a new pass.
	_refresh_queued=false
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiledrefresh()
	preload("res://scripts/runtime/frame_costs.gd").end("ui/game_ui.gd",measured)

func _invalidate_page_reads()->void:
	_page_read_serial+=1
	_page_read_basis.clear()
	_page_reads.clear()

func _read_page(page:String,subject:String)->Dictionary:
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var measured:int=Costs.begin()
	var basis:Dictionary={}
	if is_instance_valid(runtime) and runtime.has_method("ui_read_basis"):
		var current:Variant=runtime.call("ui_read_basis")
		if current is Dictionary:basis=current
	# This public fence contains process frame as well as all authority state.
	# Missing fences disable reuse, and unknown notifications invalidate it.
	if basis.is_empty() or basis!=_page_read_basis:
		_page_reads.clear();_page_read_basis=basis.duplicate(true)
	var key:String=str([page,subject])
	Costs.end("ui/read_fence",measured)
	if not basis.is_empty() and _page_reads.has(key):return _page_reads[key]
	var serial:int=_page_read_serial
	var value:Variant={}
	measured=Costs.begin()
	if is_instance_valid(runtime) and runtime.has_method("snapshot"):
		var state_page:String={"npc_quick":"npc","factory_stock":"quests","chapter_complete":"quests"}.get(page,page)
		value=runtime.call("ui_page_snapshot",state_page,subject) if runtime.has_method("ui_page_snapshot") else runtime.call("hud_snapshot" if page.is_empty() and runtime.has_method("hud_snapshot") else "snapshot")
	var state:Dictionary=value if value is Dictionary else {}
	Costs.end("ui/hud_snapshot",measured)
	measured=Costs.begin()
	var read_page:String="factory_inventory" if page=="zone_planning" and zone_planning.companion_purpose=="haul" else page
	# A personal pack does not need nearby module buffers. Haul planning does.
	var read_subject := "pack:player" if page == "factory_inventory" and subject.is_empty() else subject
	var projection:Dictionary=Factory.read_page(runtime,str(UiProjection.player(state).get("id","player")),read_page,read_subject)
	Costs.end("ui/factory_snapshot",measured)
	var result:Dictionary={"snapshot":state,"factory":projection}
	if page=="factory_stock" and is_instance_valid(runtime) and runtime.has_method("chapter_stock_snapshot"):
		result.chapter_stock=runtime.call("chapter_stock_snapshot")
	if not basis.is_empty() and serial==_page_read_serial and runtime.call("ui_read_basis")==basis:_page_reads[key]=result
	return result

func _profiledrefresh() -> void:
	if not is_node_ready(): return
	const Costs = preload("res://scripts/runtime/frame_costs.gd")
	var phase:int=Costs.begin()
	_last_refresh_us = Time.get_ticks_usec()
	_live_refresh_pending = false
	var route:Dictionary=pages.back() if not pages.is_empty() else {}
	var page:String=str(route.get("page",""))
	var subject:String=str(route.get("subject",""))
	var read:Dictionary=_read_page(page,subject)
	Costs.end("ui/read_page",phase)
	phase=Costs.begin()
	# Root-only writes (hand/save) must not mutate the cached detached DTO.
	snapshot=read.snapshot.duplicate()
	factory=read.factory
	chapter_stock=read.get("chapter_stock",{})
	if is_zone_planning(): zone_planning.sync(self)
	# Read A's router state, including its sole key map and nine real references.
	if is_instance_valid(input_router) and input_router.has_method("state"):
		var state: Variant = input_router.call("state")
		if state is Dictionary: snapshot["hand"] = state.duplicate(true)
	if world_change_busy() and (not carry.is_empty() or not drag.is_empty() or not capture_action.is_empty() or is_instance_valid(_split_layer)):
		cancel_transient()
	_sync_modal()
	_note_chapter_completion()
	var actor := UiProjection.player(snapshot)
	var movement := UiProjection.player_movement(snapshot)
	_status.text = "余晖 · " + UiProjection.activity_text(actor)
	if actor.get("wounds") is Array and not actor.wounds.is_empty(): _status.text += " · 伤势 " + str(actor.wounds.size())
	_vitals.present(actor, movement)
	_vitals.set_display_scale(text_scale)
	_pickup_hint.text = WorkModes.key(snapshot.get("hand",{}),"auto_pickup",KEY_G) + " 自动拾取 · " + ("开" if snapshot.get("hand", {}).get("auto_pickup",false) else "关")
	for id in _need_labels:
		var field: Dictionary = _need_labels[id]
		var value: Variant = actor.get(id)
		if id == "wounds":
			field.row.visible = value is Array and not value.is_empty()
			field.label.text = "伤势 " + str(value.size()) if value is Array else ""
		else:
			field.row.visible = value is int or value is float
			field.label.text = str(field.name) + " " + _hud_number(value)
			if id == "stamina" and (movement.get("stamina_max") is int or movement.get("stamina_max") is float):
				field.label.text += " / " + _hud_number(movement.stamina_max)
	_movement_hint.text = UiProjection.movement_text(snapshot)
	if not _movement_feedback.is_empty():
		_movement_hint.text += ("\n" if not _movement_hint.text.is_empty() else "") + "移动受阻 · " + UiProjection.feedback_text(_movement_feedback, {"purpose":"body_move"})
	_movement_hint.tooltip_text = UiProjection.feedback_diagnostic(_movement_feedback)
	_movement_hint.add_theme_color_override("font_color", UiTheme.RUST if not _movement_feedback.is_empty() else UiTheme.SECONDARY)
	_movement_hint.visible = not _movement_hint.text.is_empty()
	_profile_hint.text = UiProjection.playtest_text(snapshot)
	_profile_hint.visible = not _profile_hint.text.is_empty()
	_render_scene_feedback(actor)
	_render_build_placement_card()
	_render_target()
	_render_storage_state()
	var hand: Dictionary = snapshot.get("hand", {})
	_render_hand_hint(hand)
	var showing_failure := not _movement_feedback.is_empty() or (_notice.visible and not _notice.tooltip_text.is_empty())
	# Retained held work has its own truthful continuation hint, including
	# the original-tool requirement; don't pair it with generic digging copy.
	var intent: Dictionary = actor.get("intent", {}) if actor.get("intent") is Dictionary else {}
	_mode_hint.visible = not showing_failure and WorkModes.held_work_hint(intent, hand).is_empty() and WorkModes.repair_work_hint(snapshot.get("player_work",{})).is_empty()
	_profile_hint.visible = not _profile_hint.text.is_empty() and not showing_failure
	_refresh_factory_hud(actor)
	Costs.end("ui/hud_controls",phase)
	if drag.is_empty():
		_render_hotbar()
		_position_feedback()
		if not pages.is_empty():
			var signature: int
			if is_zone_planning(): signature = zone_planning.panel_signature(self)
			elif pages.back().page == "factory_handbook" and not Handbook.is_stories(self): signature = Handbook.view_signature(self)
			else:signature=_visible_panel_signature()
			if signature != _panel_signature and not _choice_popup_visible() and not _panel_press_active():
				_panel_signature = signature
				_render_panel()
				# Pagination/selection-scroll flags settle during handbook render.
				# Store that small final view state, avoiding one redundant rebuild.
				if pages.back().page == "factory_handbook" and not Handbook.is_stories(self): _panel_signature = Handbook.view_signature(self)
				elif not is_zone_planning():_panel_signature=_visible_panel_signature()
	else: _panel_dirty = true
	# A restored retained map must receive this read's live markers immediately.
	if page=="factory_alerts" and is_instance_valid(_known_map_canvas) and _known_map_canvas.is_inside_tree():
		var data:Dictionary=factory.get("map",{})
		var selected:Dictionary=FactoryPanels.Alerts.focused(self,data)
		_known_map_canvas.update_markers(data,selected)
		if is_instance_valid(_known_map_focus_label) and not selected.is_empty():_known_map_focus_label.text="地图焦点 · "+str(selected.get("title",selected.get("id","")))+" · "+Factory.location(selected.get("location",{}))
	if is_zone_planning(): zone_planning.work_panel.update_live()

func _visible_panel_signature()->int:
	var page:String=str(pages.back().page)
	var common:Array=[pages,factory_view,factory_favorites,carry,capture_action,text_scale,get_viewport_rect().size,_notice.text]
	if page=="factory_stock":return [common,chapter_stock].hash()
	if page in ["quests","chapter_complete"]:common.append(snapshot.get("village",{}))
	if page=="npc_quick":
		var selected := UiProjection.find(snapshot.get("actors", []), str(pages.back().subject))
		var player := UiProjection.player(snapshot)
		var context := [selected.get("id"), selected.get("appearance_id"), Identity.needs(selected)]
		# Refresh contact affordances at a useful distance granularity, while
		# avoiding a new subtree for every interpolated movement sample.
		for person: Dictionary in [selected, player]:
			context.append([person.get("regionId"), person.get("storeyId"), roundi(float(person.get("x", 0)) * 2), roundi(float(person.get("z", 0)) * 2)])
		return [common, context, CompanionCard.present(selected, factory)].hash()
	if page=="factory_people":common.append([factory.get("world_revision"),factory.get("runtime_revision"),_workforce_refresh_serial,_generation,_page_read_basis.get("epoch"),_page_read_basis.get("world_token"),_page_read_basis.get("scopes")])
	if page=="factory_inventory":
		var player:Dictionary=UiProjection.player(snapshot)
		var context:Array=[]
		for key:String in ["id","x","y","z","position","regionId","buildingId","storeyId","intent","relationship"]:context.append(player.get(key))
		# A container's current service/geometry fence can change its contact
		# and movable-facility availability without changing its item counts.
		var contact_revision:Variant=factory.get("world_revision") if not str(pages.back().get("subject","")).is_empty() else null
		return [common,context,float(player.get("hp",0))>0,snapshot.get("stocks"),snapshot.get("tools"),snapshot.get("records"),snapshot.get("catalog"),UiDelta.display_hash(factory),contact_revision,file_request_busy()].hash()
	if page=="factory_catalog":
		var hand:Dictionary=snapshot.get("hand",{})
		return [common,factory.get("modules",{}).get("definitions",[]),factory.get("modules",{}).get("build_definition_ids",[]),snapshot.get("catalog"),hand.get("mode"),hand.get("module_definition_id"),hand.get("facility_definition_id"),hand.get("bindings"),file_request_busy()].hash()
	if page in ["pause","settings","new_world","close_failed"]:
		return [common,snapshot.get("save"),snapshot.get("hand"),snapshot.get("playtest"),saving,exporting,importing,world_starting,world_restoring,_new_world_receipt,_new_world_profile,_close_receipt,_closing_wait].hash()
	if page=="factory_alerts":
		var data:Dictionary=factory.get("map",{})
		var geography:Dictionary=data.get("cartography",{}).duplicate()
		geography.erase("revision")
		var markers:Array=[]
		for marker:Dictionary in data.get("markers",[]):markers.append([marker.get("id"),marker.get("kind"),marker.get("title"),marker.get("location",{}).get("regionId")])
		var timed:bool=Factory.alerts(factory).any(func(row:Dictionary):return row.get("status")=="ignored")
		return [common,data.get("explored_tiles"),geography,markers,factory.get("alerts"),factory.get("alert_summary"),factory.get("alert_history") if factory_view.get("alert_history_open",false) else [],factory.get("scope"),factory.get("workforce",{}).get("regional_event",{}),floorf(float(snapshot.get("time",0))*10) if timed else 0].hash()
	return [common,snapshot.get("stocks"),snapshot.get("tools"),snapshot.get("actors"),snapshot.get("catalog"),snapshot.get("quests"),snapshot.get("orders"),snapshot.get("knowledge"),snapshot.get("records"),snapshot.get("work_targets"),snapshot.get("exploration"),snapshot.get("defense"),snapshot.get("radio"),snapshot.get("save"),snapshot.get("hand"),snapshot.get("playtest"),UiDelta.display_hash(factory),housing_view.serial,saving,exporting,importing,world_starting,world_restoring,_new_world_receipt,_new_world_profile,_close_receipt,_closing_wait].hash()

func _panel_press_active() -> bool:
	var control: Variant = _pressed_control.get_ref() if _pressed_control != null else null
	return is_instance_valid(control) and control.is_visible_in_tree()

func _choice_popup_visible() -> bool:
	var popup: Variant=_choice_popup.get_ref() if _choice_popup!=null else null
	return is_instance_valid(popup) and popup.visible

func _wire_choice_popups() -> void:
	# A live planning page may receive authority/focus updates while the native
	# menu is open. Replacing its OptionButton would destroy the user's popup.
	for control: Node in _dialog.find_children("*","BaseButton",true,false):
		Feedback19.bind(control)
		if control.has_meta("ui_press_wired"): continue
		control.set_meta("ui_press_wired", true)
		control.button_down.connect(func(): _pressed_control = weakref(control))
		control.button_up.connect(func():
			if _pressed_control != null and _pressed_control.get_ref() == control:
				_pressed_control = null; queue_refresh())
		if not control is OptionButton: continue
		var popup: PopupMenu=control.get_popup()
		popup.about_to_popup.connect(func():_choice_popup=weakref(popup))
		popup.popup_hide.connect(func():
			if _choice_popup!=null and _choice_popup.get_ref()==popup:
				_choice_popup=null;queue_refresh())

func _refresh_factory_hud(actor: Dictionary) -> void:
	var active := Factory.enabled(factory)
	var phase: String = snapshot.get("expedition",{}).get("phase","")
	var night_phase: String = snapshot.get("night",{}).get("phase","")
	_expedition_hud_phase = phase + ":" + night_phase
	var expedition_action: bool = phase in ["warning","fighting","between","complete","retreat"] or night_phase in ["warning","fighting","between"]
	_factory_navigation.visible = active and pages.is_empty() and not expedition_action and not _build_placement_card.visible
	_pickup_hint.visible = not expedition_action
	_navigation.visible = not active
	if not _scene_selection.is_empty() and str(snapshot.get("hand",{}).get("mode","tool"))!="tool":_scene_selection.clear()
	_personal_navigation.visible=active and pages.is_empty()
	_inventory_button.text="背包 · "+WorkModes.keys(snapshot.get("hand",{}),"inventory",KEY_TAB)
	_pause_button.text="暂停 · "+WorkModes.key(snapshot.get("hand",{}),"cancel",KEY_ESCAPE)
	_hud_backdrop.visible=not active or pages.is_empty() or planning_active()
	_panel_notice.visible = not pages.is_empty() and _notice.visible
	_world_notice.visible = pages.is_empty() and _notice.visible
	_panel_notice.text=_notice.text
	_panel_notice.tooltip_text=_notice.tooltip_text
	_panel_notice.add_theme_color_override("font_color",_notice.get_theme_color("font_color"))
	var width := maxf(96, _hud_width(get_viewport_rect().size.x, active) - 28)
	for text: Label in [_status, _scene_hint, _mode_hint, _movement_hint, _profile_hint, _pickup_hint, _storage_status]:
		text.custom_minimum_size.x = width
	_expedition_hud.refresh(self, snapshot.get("expedition",{}), snapshot.get("actors", []), snapshot.get("night",{}))
	if not active: return
	_profile_hint.visible=false # Full profile and save details remain in Pause.
	_movement_hint.visible=not _movement_feedback.is_empty()
	_mode_hint.max_lines_visible=2
	_mode_hint.visible = not _mode_hint.text.is_empty() and not expedition_action and not _build_placement_card.visible
	_storage_status.visible = saving or importing or exporting or world_change_busy() or snapshot.get("save", {}).get("busy", false) or snapshot.get("save", {}).get("status") == "failed" or not str(snapshot.get("save", {}).get("error", "")).is_empty()
	_scene_hint.max_lines_visible=2
	_status.tooltip_text = "生命 %s · 饥饿 %s · 饮水 %s · 疲劳 %s · 体力 %s" % [UiProjection.number(actor.get("hp")),UiProjection.number(actor.get("hunger")),UiProjection.number(actor.get("thirst")),UiProjection.number(actor.get("fatigue")),UiProjection.number(actor.get("stamina"))]
	for id in _need_labels:
		var field: Dictionary = _need_labels[id]
		if id == "wounds": continue
		var value: Variant = actor.get(id)
		field.row.visible = (value is int or value is float) and (id == "stamina" or (float(value) >= 70 if id == "fatigue" else float(value) <= 30))
	if expedition_action:
		_scene_hint.hide()
		_target.hide()
		_work_progress.hide()
		_repair_details.hide()
		_size_dialog()
		return
	_render_companions()
	var alerts := Factory.attention_alerts(factory)
	var summary: Dictionary = factory.get("alert_summary", {})
	_factory_alert.text = "地图与告警 · 未解决 " + str(summary.get("total", Factory.alerts(factory).size()))
	if int(summary.get("ignored", 0)) > 0: _factory_alert.text += " · 暂忽略 " + str(summary.ignored)
	if not alerts.is_empty(): _factory_alert.text += "\n" + str(alerts[0].get("title", alerts[0].get("reason", "现场问题")))
	_size_dialog()

func _render_companions() -> void:
	var player_id: String = UiProjection.player(snapshot).get("id", "player")
	var members := Factory.rows(factory, "workforce", "members").filter(func(member: Dictionary) -> bool:
		return member.get("actor_id") != player_id).slice(0, 2)
	var actors := members.map(func(member: Dictionary) -> Dictionary:
		return UiProjection.find(snapshot.get("actors", []), str(member.get("actor_id", "")))).filter(func(actor: Dictionary) -> bool:
		return not actor.is_empty())
	var signature := [actors.map(func(actor: Dictionary) -> Array:
		return [actor.get("id"), actor.get("appearance_id")]), text_scale].hash()
	if signature != _companion_signature:
		_companion_signature = signature
		_companion_buttons.clear()
		_clear(_companions)
		for actor: Dictionary in actors:
			var id := str(actor.id)
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_companions.add_child(row)
			var portrait := Identity.portrait(actor)
			if portrait != null:
				var avatar := button("", _point_hud_companion.bind(id), "hud:portrait:" + id)
				avatar.icon = portrait
				avatar.expand_icon = true
				avatar.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				avatar.custom_minimum_size = Vector2.ONE * roundi(42 * minf(text_scale, 1.2))
				avatar.tooltip_text = "查看%s的行动和工作" % str(actor.get("name", "同伴"))
				row.add_child(avatar)
			var action := button("", _point_hud_companion.bind(id), "hud:person:" + id)
			action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action.alignment = HORIZONTAL_ALIGNMENT_LEFT
			action.theme_type_variation = "QuietButton"
			row.add_child(action)
			_companion_buttons[id] = weakref(action)
	for actor: Dictionary in actors:
		var ref: WeakRef = _companion_buttons[str(actor.id)]
		var action: Button = ref.get_ref()
		var state := CompanionCard.present(actor, factory)
		var title := "%s\n%s" % [str(actor.get("name", "同伴")), str(state.current)]
		if action.text != title: action.text = title
		action.tooltip_text = "\n".join(PackedStringArray([Identity.needs(actor), state.assignment, state.reason, state.next].filter(func(line: String) -> bool: return not line.is_empty())))

func _point_hud_companion(id: String) -> void:
	var trigger := get_viewport().gui_get_focus_owner()
	if point_companion(id) and is_instance_valid(trigger) and _companions.is_ancestor_of(trigger):
		_hud_entry_focus = weakref(trigger)

func workforce_person(actor_id: String, refresh_now: bool = false) -> Dictionary:
	# A display cache of one original person query, fenced by the real
	# runtime/world/load generation and revision. Never an accepted command.
	if refresh_now: _workforce_details.erase(actor_id)
	var generation: Dictionary={}
	if is_instance_valid(runtime) and runtime.has_method("zone_view_basis"):
		var value: Variant=runtime.call("zone_view_basis","player")
		if value is Dictionary: generation=value
	var basis: Array=[runtime.get_instance_id() if is_instance_valid(runtime) else 0,generation.get("runtime_generation"),generation.get("world_generation"),generation.get("zones_generation",{}),factory.get("world_id"),factory.get("world_revision"),factory.get("runtime_revision"),actor_id,_page_read_basis.get("epoch"),_page_read_basis.get("world_token"),_page_read_basis.get("scopes")]
	var entry: Dictionary=_workforce_details.get(actor_id,{})
	if entry.get("basis")!=basis:
		workforce_detail_reads += 1
		entry={"basis":basis.duplicate(true),"person":Factory.read_person(runtime,actor_id)}
		_workforce_details[actor_id]=entry
	return entry.get("person",{})

func refresh_workforce_person(actor_id: String) -> void:
	_workforce_details.erase(actor_id)
	_workforce_refresh_serial+=1
	queue_refresh()

func _note_chapter_completion()->void:
	var chapter:Dictionary=snapshot.get("village",{}).get("chapter_one",{})
	if not chapter.get("active",false) and not chapter.get("completed",false):return
	var world_id:String=str(factory.get("world_id",""))
	if world_id.is_empty():return
	var completed:bool=chapter.get("completed",false)
	if not _seen_chapter_status.has(world_id) or not completed:
		_seen_chapter_status[world_id]=completed
		return
	if _seen_chapter_status[world_id] or not pages.is_empty():return
	_seen_chapter_status[world_id]=true
	notify("第一章完成 · 成果已记录在任务页")

func _render_scene_feedback(actor: Dictionary) -> void:
	_scene_hint.text = ""
	for quest: Dictionary in UiProjection.records(snapshot.get("quests", [])):
		if str(quest.get("status", "")) in ["active", "available", "in_progress", "进行中"]:
			_scene_hint.text = str(quest.get("name", quest.get("title", quest.get("id", "")))) + "\n" + str(quest.get("hint", ""))
			break
	var village:Dictionary=snapshot.get("village",{})
	if village.get("available",false):
		var objective_text:String="继续建设与探索"
		for objective:Dictionary in UiProjection.records(village.get("objectives",[])):
			if objective.get("status")!="已完成":objective_text=str(objective.get("text",""));break
		_scene_hint.text="旧村复兴 · "+str(village.get("title",""))+"\n当前目标："+objective_text
	var intent: Dictionary = actor.get("intent", {}) if actor.get("intent") is Dictionary else {}
	var work := intent
	if intent.has("order_id"):
		work = UiProjection.find(snapshot.get("orders", []), str(intent.order_id))
	if intent.get("owner") == "modules" and intent.get("kind") == "water":
		work = Water.work(self)
		if not work.is_empty(): _scene_hint.text += "\n" + ("修复储水装置" if work.get("operation") == "repair" else "手动取水") + " · " + WorkModes.key(snapshot.get("hand", {}), "cancel", KEY_ESCAPE) + "取消"
	var held_hint := WorkModes.held_work_hint(intent, snapshot.get("hand", {}))
	if not held_hint.is_empty(): _scene_hint.text += ("\n" if not _scene_hint.text.is_empty() else "") + held_hint
	var current_work:Dictionary=snapshot.get("player_work",{})
	var repair_hint:String=WorkModes.repair_work_hint(current_work)
	_repair_details.visible=not repair_hint.is_empty() and pages.is_empty() and not str(current_work.get("module_id","")).is_empty()
	if not repair_hint.is_empty():
		_scene_hint.text+=("\n" if not _scene_hint.text.is_empty() else "")+repair_hint
		work={"duration":current_work.get("duration_seconds",0),"elapsed":current_work.get("progress_seconds",0)}
		var ratio:Dictionary=Factory.progress(current_work)
		if not ratio.is_empty():_scene_hint.text+=" · "+str(roundi(float(ratio.value)*100))+"%"
	var progress := UiProjection.progress(work)
	_work_progress.visible = not progress.is_empty()
	if _work_progress.visible:
		_work_progress.max_value = progress.maximum
		_work_progress.value = progress.value
	if work.get("status") == "blocked" and work.get("reason") != null:
		_scene_hint.text += "\n作业受阻 · " + UiProjection.feedback_text(work)
	_scene_hint.visible = not _scene_hint.text.strip_edges().is_empty()

func _hud_number(value: Variant) -> String:
	return str(roundi(float(value))) if (value is int or value is float) and is_finite(float(value)) else "—"

func _selected_reference(hand: Dictionary) -> Dictionary:
	var slots: Array = hand.get("slots", [])
	var selected := int(hand.get("selected", 0))
	return UiProjection.normalize_reference(slots[selected]) if selected >= 0 and selected < slots.size() and slots[selected] is Dictionary else {}

func _hud_pack_index(stock: Dictionary) -> Dictionary:
	# All inputs read by entries(), without location/revision-only changes.
	# The hand hint, passive target and hotbar share this display-only index.
	var catalog: Dictionary = snapshot.get("catalog", {}) if snapshot.get("catalog") is Dictionary else {}
	var basis: Array = [stock.get("id"),stock.get("searched"),stock.get("items"),stock.get("reserved"),stock.get("tool_ids"),snapshot.get("tools"),catalog.get("tool_definitions")]
	if basis != _hud_pack_basis:
		_hud_pack_basis = basis.duplicate(true)
		_hud_pack_entries.clear()
		for entry: Dictionary in UiProjection.entries(stock,snapshot): _hud_pack_entries[str(entry.key)] = entry
		_hud_pack_rebuilds += 1
	return _hud_pack_entries

func _hud_hand_entry(reference: Dictionary) -> Dictionary:
	var key := UiProjection.reference_key(reference)
	if key.is_empty(): return {}
	var stock := UiProjection.player_stock(snapshot)
	if reference.get("kind") == "recipe": return UiProjection.hand_entry(stock,snapshot,reference)
	return _hud_pack_index(stock).get(key,{})

func _on_combat_ready_changed() -> void:
	# DirectInteraction publishes the scene target independently. Only the
	# retained hand hint needs repainting for this posture change.
	if is_node_ready():
		_render_hand_hint(snapshot.get("hand", {}))

func _render_hand_hint(hand: Dictionary) -> void:
	_mode_hint.text = _hand_hint(hand)
	if str(hand.get("mode", "")).begins_with("terrain_"):
		_mode_hint.text += "\n" + WorkModes.brush_text(hand)

func _hand_hint(hand: Dictionary) -> String:
	if str(hand.get("mode", "")) == "module_place":
		var definition := Factory.definition(factory, str(hand.get("module_definition_id", "")))
		return "建造 · " + str(definition.get("name", "完整模块")) + " · " + _build_keys(hand)
	if str(hand.get("mode", "tool")) != "tool":
		return WorkModes.title(str(hand.mode)) + " · " + WorkModes.mode_hint(hand)
	if _combat_ready(): return "战备 · 左键攻击 · " + ("再点右键解除" if hand.get("combat_toggle", false) else "松开右键解除")
	if is_companion_building_pick(): return "为同伴选建筑 · 左键指定 · " + WorkModes.key(hand, "cancel", KEY_ESCAPE) + "返回"
	var reference := _selected_reference(hand)
	var entry := _hud_hand_entry(reference)
	var build := WorkModes.key(hand, "build", KEY_B) + ("建造模块" if Factory.enabled(factory) else "构件与作业")
	if reference.is_empty(): return "空手 · " + WorkModes.key(hand, "interact", KEY_E) + "交互 · " + build
	if reference.get("kind") == "recipe":
		return "手持构件 · " + str(entry.get("name", reference.get("definition_id", ""))) + " · 右键放置 · " + WorkModes.key(hand, "rotate", KEY_R) + "旋转"
	var name := str(entry.get("name", UiProjection.item_name(str(reference.get("item_id", ""))) if reference.get("kind") == "item" else "工具"))
	if entry.is_empty() or float(entry.get("quantity", 0)) <= 0: return "手持 " + name + " · 已耗尽或不可用 · " + build
	if float(entry.get("available", 0)) <= 0: return "手持 " + name + " · 已预留，当前不可用 · " + build
	var use_hint := " · 左键工具作业 · "
	if reference.get("kind") == "item":
		use_hint = (" · " + WorkModes.key(hand, "consume", KEY_F) + "使用消耗品 · ") if hand.get("bindings", {}).has("consume") else " · 使用键待绑定 · "
	return "手持 " + name + use_hint + build

func _combat_ready() -> bool:
	return is_instance_valid(input_router) and input_router.has_method("combat_ready") and bool(input_router.call("combat_ready"))

func _build_keys(hand: Dictionary) -> String:
	return "左键锁定 · %s旋转 · Enter确认 · 右键解锁 · %s逐层返回" % [WorkModes.key(hand, "rotate", KEY_R), WorkModes.key(hand, "cancel", KEY_ESCAPE)]

func _hide_passive_terrain(target: Dictionary, hand: Dictionary) -> bool:
	if target.get("kind") != "terrain": return false
	if not target.get("enabled", false) and target.get("code") == "OUT_OF_REACH": return true
	# Retain the prior contract fallback until A publishes typed distance codes.
	if not target.get("enabled", false) and str(target.get("reason", "")) in ["UNREACHABLE", "实际格面超出手部触及距离"]: return true
	if str(hand.get("mode", "tool")) != "tool": return false
	var reference := _selected_reference(hand)
	if reference.get("kind") != "item": return false
	var entry := _hud_hand_entry(reference)
	# A real consumable in hand should not advertise an unrelated digging action.
	return not entry.is_empty() and float(entry.get("quantity", 0)) > 0

func show_world_target(target: Dictionary) -> void:
	if not is_node_ready(): return
	# Pointer feedback has its own retained controls. It need not wait for
	# the next HUD read of stock, jobs or world time.
	snapshot["target"] = target.duplicate(true)
	_render_build_placement_card()
	_render_target()

func _render_build_placement_card() -> void:
	var can_place: bool = is_instance_valid(input_router) and input_router.has_method("is_placement") and input_router.call("is_placement")
	var scene_visible: bool = pages.is_empty() or (planning_active() and pages.back().page in ["factory_catalog", "build", "terrain"])
	var expedition: Dictionary = snapshot.get("expedition", {})
	var expedition_active: bool = expedition.get("phase") in ["warning", "fighting", "between", "complete", "retreat"] or snapshot.get("night",{}).get("phase") in ["warning", "fighting", "between"]
	var target: Variant = snapshot.get("target", {})
	_build_placement_card.update_target(target if can_place and scene_visible and not expedition_active and target is Dictionary else {})

func _render_target() -> void:
	var companion_card_open: bool = not pages.is_empty() and pages.back().page == "npc_quick"
	if is_zone_planning() or _build_placement_card.visible or (companion_card_open and not is_companion_building_pick()):
		_target.hide()
		return
	var target: Dictionary = snapshot.get("target", {}) if snapshot.get("target") is Dictionary else {}
	if target.get("kind") == "placement": _target.hide(); return
	var hand: Dictionary = snapshot.get("hand", {})
	_target.visible = not target.is_empty() and (pages.is_empty() or planning_active()) and not _hide_passive_terrain(target, hand)
	if target.is_empty(): return
	var door_proof := WorkModes.door_proof_state(target, hand)
	if door_proof == "pending": _target_text.add_theme_color_override("font_color", Color("b8b7ad"))
	else: _target_text.remove_theme_color_override("font_color")
	var instruction := WorkModes.target_hint(target, hand)
	var name := str(target.get("name", ""))
	var text := instruction if name.is_empty() else name + " · " + instruction
	if pages.is_empty() and target.get("id")==_scene_selection.get("id") and not _scene_selection.is_empty():text="已选中 · "+text
	if target.get("kind") == "terrain":
		text = str(target.get("name", "")) + " · " + ("右键填土" if str(target.get("edit", {}).get("operation", "dig")) == "fill" else "按住左键作业")
	if not target.get("enabled", false) or door_proof == "rejected":
		text = str(target.get("name", "")) + " · 目标暂不可操作 · " + UiProjection.feedback_text(target, target, "当前不可用") if target.get("kind") == "terrain" else text + "\n目标暂不可操作 · " + UiProjection.feedback_text(target, target, "当前不可用")
		_target_text.tooltip_text = UiProjection.feedback_diagnostic(target)
	else: _target_text.tooltip_text = ""
	if _target_text.text != text:
		_target_text.text = text
	var font: Font = _target_text.get_theme_font("font")
	var font_size: int = _target_text.get_theme_font_size("font_size")
	var width := 0.0
	for line: String in text.split("\n"): width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	width = ceilf(minf(width, minf(320 * text_scale, maxf(120, size.x - 40))))
	if not is_equal_approx(_target_text.custom_minimum_size.x, width):
		_target_text.custom_minimum_size.x = width
	# Native Label wrapping computes the height; allow a former long failure to
	# shrink back to the compact action rather than retaining its previous box.
	_target.size = Vector2(width + 16, 0)
	var progress := UiProjection.progress(target.get("progress"))
	_progress.visible = not progress.is_empty()
	if _progress.visible:
		_progress.max_value = progress.maximum
		_progress.value = progress.value
	_position_target()

func _position_feedback() -> void:
	if not is_instance_valid(_world_notice) or not is_instance_valid(_hotbar): return
	if is_instance_valid(_build_placement_card) and _build_placement_card.visible:
		var width := minf(300 * text_scale, size.x * 0.36)
		var card_size := Vector2(width, _build_placement_card.get_combined_minimum_size().y)
		if _build_placement_card.size != card_size: _build_placement_card.size = card_size
		_build_placement_card.position = Vector2(size.x - _build_placement_card.size.x - 16, 16)
	if _world_notice.visible:
		var font := _notice.get_theme_font("font")
		var font_size := _notice.get_theme_font_size("font_size")
		var text_width := 0.0
		for line: String in _notice.text.split("\n"):
			text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var width := ceilf(minf(text_width, minf(360 * text_scale, get_viewport_rect().size.x * 0.42)))
		if _hud_backdrop.is_visible_in_tree() and _factory_navigation.is_visible_in_tree() and size.x <= 1100:
			var gutter := _factory_navigation.get_global_rect().position.x - _hud_backdrop.get_global_rect().end.x
			width = minf(width, maxf(108, floorf(gutter - 50)))
		if not is_equal_approx(_notice.custom_minimum_size.x, width): _notice.custom_minimum_size.x = width
		var measured := _world_notice.get_combined_minimum_size()
		if _world_notice.size != measured: _world_notice.size = measured
		var obstacles := _hud_obstacles()
		_world_notice.position = TargetPrompt.place(size, _world_notice.size, null, size * 0.5, obstacles, text_scale, _feedback_bottom())
	_position_target()

func _hud_obstacles() -> Array:
	var obstacles: Array = []
	for control: Control in [_hud_backdrop, _factory_navigation, _pickup_toast, _dialog, _build_placement_card]:
		if is_instance_valid(control) and control.is_visible_in_tree(): obstacles.append(control.get_global_rect())
	return obstacles

func _feedback_bottom() -> float:
	return _hotbar.get_global_rect().position.y if is_instance_valid(_hotbar) and _hotbar.is_visible_in_tree() else size.y

func _position_target() -> void:
	if not is_instance_valid(_target_text) or not _target.visible: return
	var target: Dictionary = snapshot.get("target", {})
	var anchor: Variant = TargetPrompt.point(target.get("projected_position"))
	var player_anchor := size * 0.5
	var camera: Camera3D = get_viewport().get_camera_3d()
	var player := UiProjection.player(snapshot)
	if camera != null and player.has("x") and player.has("y") and player.has("z"):
		var at := Vector3(float(player.x), float(player.y) + 0.9, float(player.z))
		if not camera.is_position_behind(at): player_anchor = camera.unproject_position(at)
	var obstacles := _hud_obstacles()
	if is_instance_valid(_world_notice) and _world_notice.is_visible_in_tree(): obstacles.append(_world_notice.get_global_rect())
	_target.position = TargetPrompt.place(size, _target.size, anchor, player_anchor, obstacles, text_scale, _feedback_bottom())

func _render_hotbar() -> void:
	var hand: Dictionary = snapshot.get("hand", {})
	var references: Array = hand.get("slots", [])
	var stock := UiProjection.player_stock(snapshot)
	var input_signature:int=[references,hand.get("selected",0),stock.get("id"),stock.get("searched"),stock.get("items"),stock.get("reserved"),stock.get("tool_ids"),snapshot.get("tools"),snapshot.get("catalog"),text_scale].hash()
	if input_signature==_hotbar_input_signature:return
	_hotbar_input_signature=input_signature
	var displayed: Array = []
	var entries:Dictionary=_hud_pack_index(stock)
	for index in range(9):
		var reference: Dictionary = UiProjection.normalize_reference(references[index]) if index < references.size() and references[index] is Dictionary else {}
		var item:Dictionary = UiProjection.hand_entry(stock,snapshot,reference) if reference.get("kind")=="recipe" else entries.get(UiProjection.reference_key(reference),{})
		var title := "空格" if reference.is_empty() else str(item.get("name", UiProjection.item_name(str(reference.get("item_id", ""))) if reference.get("kind") == "item" else "工具"))
		displayed.append({"kind":"hotbar", "index":index, "reference":reference, "entry":item, "stock_id":stock.get("id", ""), "quantity":item.get("quantity", 0), "available":item.get("available", 0), "title":title})
	# Locations, other containers and held keys are not slot visual state.
	var signature := [displayed, hand.get("selected", 0), text_scale].hash()
	if signature == _hotbar_signature: return
	_hotbar_signature = signature
	for index in range(9):
		for host in [_hotbar, _modal_hotbar]:
			var key := str(host.get_instance_id()) + ":" + str(index)
			var node: Slot = _hotbar_nodes.get(key)
			if not is_instance_valid(node):
				node = _slot(displayed[index]); host.add_child(node); _hotbar_nodes[key] = node
			var slot_signature := [displayed[index], index == int(hand.get("selected",0)), text_scale].hash()
			if node.get_meta("ui_slot_signature",0) == slot_signature: continue
			node.set_meta("ui_slot_signature",slot_signature)
			node.slot = displayed[index].duplicate(true)
			node.present(str(displayed[index].title), index == int(hand.get("selected", 0)), text_scale)
	_hotbar.offset_top = -16 - 90 * text_scale
	var width := 9 * 64 * text_scale + 8 * 8
	_hotbar.offset_left = -width * 0.5
	_hotbar.offset_right = width * 0.5

func apply_icon(node: Button, item: Dictionary) -> void:
	Icons.apply_button(node, item)

func _slot(data: Dictionary) -> Slot:
	var node := Slot.new()
	node.slot = data.duplicate(true)
	node.create_drag = _create_drag
	node.can_receive = _can_drop
	node.receive = _drop
	node.activate = _activate_slot
	node.split = _split_slot
	node.set_meta("ui_focus_key", str(data.get("stock_id", "hotbar")) + ":" + str(data.get("index", -1)) + ":" + str(data.get("kind", "")))
	if _drag_trace_enabled:
		node.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				_trace_drag("pointer_down" if event.pressed else "pointer_up", {"slot":_trace_slot(data), "local_position":str(event.position)}))
	Feedback19.bind(node)
	return node

func _trace_slot(value: Dictionary) -> Dictionary:
	return {"kind":value.get("kind"), "stock_id":value.get("stock_id"), "index":value.get("index"), "reference":value.get("reference", {})}

func _trace_drag(stage: String, detail: Dictionary = {}) -> void:
	# Explicit diagnostic flag only; bounded and never enabled for timing windows.
	if not _drag_trace_enabled or _drag_trace_count >= 120: return
	_drag_trace_count += 1
	print("R3.3 UI drag " + JSON.stringify({"stage":stage, "ticks_us":Time.get_ticks_usec(), "native_drag":get_viewport().gui_is_dragging(), "token":drag.get("ui_drag", carry.get("ui_drag", "")), "mouse_logical":str(get_global_mouse_position()), "viewport_logical":str(get_viewport_rect().size), "text_scale":text_scale, "pages":pages, "detail":detail}))

func inventory_grid(stock: Dictionary, parent: Node, limit: int = 0, handbook: bool = true) -> void:
	if stock.is_empty():
		paragraph("真实背包／容器绑定尚未提供", parent)
		return
	if not stock.get("searched", false):
		paragraph("尚未观察此容器，内容不可见", parent)
		return
	var grid := GridContainer.new()
	grid.columns = 5 if text_scale > 1.25 and not pages.is_empty() and str(pages.back().get("page", "")) == "container" else 6
	if Factory.enabled(factory):
		var width := _dialog.size.x - 100
		if parent.has_meta("ui_inventory_width"): width = float(parent.get_meta("ui_inventory_width"))
		elif parent.get_parent() is HBoxContainer: width = (width - 24) * 0.5
		if parent.has_meta("ui_inventory_single"): grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.columns = clampi(floori(width / (64 * text_scale + 8)), 1, 6)
	parent.add_child(grid)
	var cells: Array = layout.cells(stock, snapshot)
	if limit > 0: cells = cells.slice(0, limit)
	for cell in cells:
		var data: Dictionary = cell.duplicate(true)
		data.merge({"kind":"inventory", "stock_id":str(stock.id), "reference":cell.entry.get("reference", {})}, true)
		var node := _slot(data)
		node.present(str(cell.entry.get("name", "空格")), false, text_scale)
		grid.add_child(node)
	if handbook and Factory.enabled(factory): Handbook.inventory_shortcut(self, stock, parent)

func open_handbook(entry_id: String = "") -> void:
	if not carry.is_empty() or not drag.is_empty():
		notify("请先将拿起的物品归位，再查阅定义", true)
		return
	open_panel("factory_handbook", entry_id)

func refresh_handbook() -> void:
	Handbook.load_snapshot(self, str(factory_view.get("handbook_entry", "")))
	queue_refresh()

func item_row(items: Dictionary, title: String, parent: Node) -> void:
	if items.is_empty(): return
	if not title.is_empty(): paragraph(title, parent)
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	for id in items:
		var chip := HBoxContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		var entry := {"reference":{"kind":"item", "item_id":str(id)}}
		var texture := Icons.texture(entry)
		if texture != null: chip.add_child(Icons.image(texture))
		chip.add_child(label(UiProjection.item_text(str(id), items[id])))
		chip.set_meta("ui_icon", Icons.descriptor(entry))

func open_panel(page: String, subject: String = "", dispatch_actor: String = "") -> void:
	if page.is_empty() or world_change_busy() or is_instance_valid(_recovery_menu): return
	if is_zone_planning() and page != "zone_planning":
		zone_planning.clear_preview(); zone_planning.end_companion()
	if Factory.enabled(factory):
		page = {"build":"factory_catalog", "module":"factory_module", "inventory":"factory_inventory", "container":"factory_inventory", "neighbors":"factory_people", "map":"factory_alerts"}.get(page, page)
	elif page == "map": page = "quests"
	if page == "factory_handbook":
		Handbook.normalize_alias(self)
		Handbook.load_snapshot(self, subject)
	var route := {"page":page, "subject":subject}
	if not dispatch_actor.is_empty():route.dispatch_actor=dispatch_actor
	if pages.is_empty() or pages.back() != route:
		_scene_selection.clear()
		_cancel_companion_placement()
		if is_companion_building_pick():pages.back().erase("building_pick")
		_remember_scroll()
		pages.append(route)
		_scroll.scroll_vertical = 0
	_size_dialog()
	cancel_transient()
	_sync_modal()
	refresh()
	_dialog.grab_focus()
	if page == "npc_quick":
		_restore_focus.call_deferred("npc:work" if str(CompanionCard.present(UiProjection.find(snapshot.get("actors", []), subject), factory).consent).is_empty() else "npc:details", _panel_render_serial)

func point_companion(id: String) -> bool:
	if id.is_empty() or is_instance_valid(_recovery_menu): return false
	if world_change_busy() or not carry.is_empty() or not drag.is_empty(): return false
	if not pages.is_empty():
		if pages.back().page != "npc_quick": return false
		if pages.back().subject == id: return true
		pages.pop_back()
	open_panel("npc_quick", id)
	return true

func close_companion_card_for_world_input() -> bool:
	if pages.is_empty() or pages.back().page != "npc_quick" or is_companion_building_pick(): return false
	close_panels()
	return true

func observe_companion_selection(_visible: Array) -> void:
	# Dispatch refers to a persistent member, independently of the camera.
	pass

func start_companion_area(id: String, purpose: String) -> void:
	zone_planning.begin_companion(id, purpose)
	open_panel("zone_planning")

func begin_companion_building_pick(id:String) -> void:
	if pages.is_empty() or pages.back().page!="npc_quick" or pages.back().subject!=id:return
	router_call("set_mode",["tool"])
	pages.back().building_pick=true
	refresh()

func point_companion_building(hit:Dictionary) -> bool:
	if not is_companion_building_pick():return false
	if hit.get("primary")=="module":
		var actor_id:String=pages.back().subject
		pages.back().erase("building_pick")
		factory_view["building_tab:"+str(hit.id)]="use"
		open_panel("factory_module",str(hit.id),actor_id)
	else:notify("请选择一栋已查看、可管理的建筑",true)
	return true

func building_dispatch_actor() -> String:
	return str(pages.back().get("dispatch_actor","")) if not pages.is_empty() else ""

func open_companion_home_catalog(id:String) -> void:
	open_panel("factory_catalog","",id)

func _cancel_companion_placement() -> void:
	if not is_instance_valid(input_router):return
	var hand:Dictionary=input_router.call("state")
	if hand.get("mode")=="module_place" and not str(hand.get("module_worker_id","")).is_empty():
		router_call("set_mode",["tool"])

func finish_companion_blueprint(module_id:String, worker_id:String) -> void:
	var result:Dictionary=execute("workforce.assign","",{"candidate_id":"building-order:"+module_id},false,worker_id)
	if result.get("ok",false):
		close_panels()
		notify("住宅蓝图已放置 · 已交给同伴")
	else:
		open_panel("factory_module",module_id,worker_id)
		notify("蓝图已放置 · 未能指派："+UiProjection.action_feedback(result,"workforce.assign"),true)

func close_panels() -> void:
	if world_change_busy() or is_instance_valid(_recovery_menu): return
	_cancel_companion_placement()
	zone_planning.clear_preview()
	zone_planning.end_companion()
	cancel_transient()
	_remember_scroll()
	pages.clear()
	_panel_signature = 0
	_sync_modal()
	refresh()
	_restore_hud_companion_focus()

func cancel_ui() -> void:
	# The submitted operation belongs to A and cannot be cancelled by hiding UI.
	if world_change_busy(): return
	if is_instance_valid(_recovery_menu): _recovery_menu.cancel(); return
	if not capture_action.is_empty() or not carry.is_empty() or not drag.is_empty() or is_instance_valid(_split_layer):
		cancel_transient()
		queue_refresh()
		return
	if _file_dialog.visible:
		_file_dialog.hide()
		_file_cancelled()
		return
	if not pages.is_empty() and pages.back().page == "close_failed":
		cancel_close()
		return
	if is_zone_planning():
		if not zone_planning.cancel_draft():
			zone_planning.end_companion()
			_remember_scroll()
			pages.pop_back()
		_sync_modal(); refresh()
		return
	if is_companion_building_pick():
		pages.back().erase("building_pick")
		refresh()
		return
	if planning_active() and pages.back().page != "npc_quick":
		router_call("cancel")
		_sync_modal()
		refresh()
		return
	if not pages.is_empty():
		_remember_scroll()
		pages.pop_back()
		if not pages.is_empty() and pages.back().page == "factory_handbook": Handbook.load_snapshot(self, str(pages.back().get("subject", "")))
	_sync_modal()
	refresh()
	if not pages.is_empty():_scroll.set_deferred("scroll_vertical",int(_route_scrolls.get(str(pages.back()),0)))
	else: _restore_hud_companion_focus()

func _restore_hud_companion_focus() -> void:
	if _hud_entry_focus == null: return
	var trigger: Control = _hud_entry_focus.get_ref()
	_hud_entry_focus = null
	if is_instance_valid(trigger) and trigger.is_visible_in_tree(): trigger.grab_focus()

func _remember_scroll() -> void:
	if not pages.is_empty():_route_scrolls[str(pages.back())]=_scroll.scroll_vertical

func cancel_transient() -> void:
	if not drag.is_empty() or not carry.is_empty(): _trace_drag("cancel_transient")
	capture_action = ""
	carry.clear()
	drag.clear()
	if is_inside_tree() and get_viewport().gui_is_dragging(): get_viewport().gui_cancel_drag()
	if is_instance_valid(_split_layer):
		_split_layer.queue_free()
		_split_layer = null
	_sync_modal()

func _sync_modal() -> void:
	if not is_node_ready(): return
	var was_visible:bool=_modal.visible
	if pages.is_empty():
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus) and _modal.is_ancestor_of(focus): focus.release_focus()
	_modal.visible = not pages.is_empty()
	if _modal.visible and not was_visible:Feedback19.reveal(_dialog)
	elif not _modal.visible and was_visible:Feedback19.finish_reveal(_dialog)
	# Planning and companion actions own their own shortcuts. Keep the fixed
	# world hotbar out of the side panels, especially at large text scales.
	var side_panel_owns_shortcuts: bool = not pages.is_empty() and pages.back().page in ["npc_quick", "zone_planning"]
	_hotbar.visible = pages.is_empty() or (planning_active() and not side_panel_owns_shortcuts)
	_modal_hotbar.visible = not pages.is_empty() and pages.back().page in ["inventory", "container", "build", "factory_inventory"] and (not Factory.enabled(factory) or get_viewport_rect().size.x >= 9 * 64 * text_scale + 110)
	if is_instance_valid(input_router) and input_router.has_method("set_modal"):
		var busy := file_request_busy()
		var planning := planning_active() and carry.is_empty() and drag.is_empty() and capture_action.is_empty() and not busy
		var focus := get_viewport().gui_get_focus_owner()
		var text_entry := is_instance_valid(focus) and (focus is LineEdit or focus is TextEdit) and _dialog.is_ancestor_of(focus)
		var active := is_instance_valid(_recovery_menu) or (not pages.is_empty() and not planning) or text_entry or not carry.is_empty() or not drag.is_empty() or busy
		_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE if planning else Control.MOUSE_FILTER_STOP
		var live_view := input_router.has_method("set_modal_policy") and not pages.is_empty() and str(pages.back().page) == "factory_alerts" and carry.is_empty() and drag.is_empty() and capture_action.is_empty() and not is_instance_valid(_split_layer) and not busy
		var pause_world := not live_view and not planning
		_modal_policy_hint.text = "" if planning and side_panel_owns_shortcuts else _build_keys(snapshot.get("hand", {})) if planning else "查看不暂停结算 · Esc返回" if live_view else "世界暂停 · 配置可提交，劳动与生产待关页继续"
		# Keep world input consumed even for a live map. Only A's router changes
		# the one simulation pause policy; confirmations and held items still pause.
		if _modal_router_active != active or _modal_router_pause_world != pause_world:
			_modal_router_active = active
			_modal_router_pause_world = pause_world
			if input_router.has_method("set_modal_policy"): input_router.call("set_modal_policy", active, pause_world)
			else: input_router.call("set_modal", active)

func _on_focus_exited() -> void:
	_trace_drag("focus_exit")
	_pressed_control = null
	zone_planning.finish_pointer(self)
	cancel_transient()
	# A owns held keys, pointer state, focus pause and resume-with-fresh-input.
	if not pages.is_empty(): queue_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_trace_drag("native_drag_end", {"engine_accepted_drop":get_viewport().gui_is_drag_successful()})
		# Native drag consumes the source button's release. Retained hotbar
		# slots now survive, so that press lock must end with the drag itself.
		_pressed_control = null
		drag.clear()
		_sync_modal()
		_panel_dirty = false
		queue_refresh()

func _bindings() -> Dictionary:
	var hand: Dictionary = snapshot.get("hand", {})
	return hand.get("bindings", {}) if hand.get("bindings") is Dictionary else {}

func _input(event: InputEvent) -> void:
	# The persistent recovery overlay owns its own native focus/confirmation.
	# Let it consume events instead of toggling the covered pause/backpack UI.
	if is_instance_valid(_recovery_menu): return
	if world_change_busy():
		accept_event()
		return
	if is_zone_planning() and zone_planning.drawing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		if is_instance_valid(hovered) and (_dialog == hovered or _dialog.is_ancestor_of(hovered)):
			zone_planning.handle_world_click(self, {}, event)
			accept_event(); return
	if not event is InputEventKey or not event.pressed: return
	var focus := get_viewport().gui_get_focus_owner()
	# The native focus may sit on “换个位置”. Keep Enter bound to the same
	# confirmation intent as the card's primary button in the placement view.
	if is_instance_valid(_build_placement_card) and _build_placement_card.is_visible_in_tree() and not (focus is LineEdit or focus is TextEdit):
		var placement_key: int = event.get_physical_keycode_with_modifiers() if event.physical_keycode != KEY_NONE else event.get_keycode_with_modifiers()
		if placement_key in [KEY_ENTER, KEY_KP_ENTER]:
			accept_event()
			if not event.echo: input_router.call("confirm_placement")
			return
	if pages.is_empty() and drag.is_empty() and carry.is_empty(): return
	if event.keycode == KEY_ESCAPE and focus is LineEdit and focus.has_ime_text():
		focus.cancel_ime()
		accept_event()
		return
	if not capture_action.is_empty():
		if focus is LineEdit and focus.has_ime_text(): return
		accept_event()
		if event.echo: return
		if event.keycode == KEY_ESCAPE:
			capture_action = ""
			queue_refresh()
			return
		var code := UiProjection.physical_key(event)
		# A's run action accepts bare Shift; do not bind it as Shift+Shift.
		if capture_action == "run" and event.physical_keycode == KEY_SHIFT and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed: code = KEY_SHIFT
		if code == 0: return
		var result := router_call("bind_key", [capture_action, code])
		if result.get("ok", false): capture_action = ""
		else: notify(str(result.get("reason", "键位未被接受")), true)
		queue_refresh()
		return
	var code := UiProjection.physical_key(event)
	if event.keycode == KEY_ESCAPE or code == UiProjection.binding_code(_bindings().get("cancel"), KEY_ESCAPE):
		accept_event()
		if not event.echo: cancel_ui()
	elif not pages.is_empty() and not (focus is LineEdit or focus is TextEdit) and WorkModes.matches(event,snapshot.get("hand",{}),"inventory",KEY_TAB):
		accept_event()
		if not event.echo:
			if str(pages.back().page) in ["inventory", "container", "factory_inventory"]:close_panels()
			else:open_panel("inventory")
	elif not pages.is_empty() and not (focus is LineEdit or focus is TextEdit) and ((code == UiProjection.binding_code(_bindings().get("build"), KEY_B) and str(pages.back().page) in ["build", "terrain", "factory_catalog"]) or (code == UiProjection.binding_code(_bindings().get("interact"), KEY_E) and _interaction_page_open())):
		# Explicit menu keys toggle back to the scene; E never auto-crafts.
		accept_event()
		if not event.echo: close_panels()
	elif (event.meta_pressed or event.ctrl_pressed) and not event.alt_pressed and (event.keycode == KEY_S or event.physical_keycode == KEY_S):
		accept_event()
		if not event.echo: save_world()

func _unhandled_key_input(_event: InputEvent) -> void:
	if not pages.is_empty() and not planning_active(): get_viewport().set_input_as_handled()

func _interaction_page_open()->bool:
	if pages.is_empty() or is_companion_building_pick():return false
	var route:Dictionary=pages.back()
	return route.page in ["workbench","factory_module","npc_quick","water"] or (route.page in ["container","factory_inventory"] and not str(route.get("subject","")).is_empty())

func _gui_focus_changed(_control: Control) -> void:
	# Search owns keyboard input while planning. Leaving it restores the one
	# router's world context with fresh input; UI never unpauses Runtime itself.
	_sync_modal()

func _render_panel() -> void:
	if not drag.is_empty():
		_panel_dirty = true
		return
	var focus := get_viewport().gui_get_focus_owner()
	var key := str(focus.get_meta("ui_focus_key", "")) if is_instance_valid(focus) and _dialog.is_ancestor_of(focus) else ""
	var caret: int = focus.caret_column if focus is LineEdit else -1
	var scroll := _scroll.scroll_vertical
	_panel_render_serial += 1
	if pages.is_empty():return
	var route: Dictionary = pages.back()
	var navigation_rebuilt:=false
	var reused:bool=_select_panel_body(route,_panel_signature)
	if not reused:
		# Construct the complete unchanged native subtree off-tree. One attach
		# avoids propagating inherited theme/layout work for every new child.
		if _body.get_parent()==_scroll:_scroll.remove_child(_body)
		_clear(_body)
	_clear(_planning_footer)
	_planning_footer.hide()
	_panel_navigation.hide()
	_planning_navigation.hide()
	_title.text = {"inventory":"随身背包", "container":"取放物品", "build":"构件与场景作业", "terrain":"地形笔刷", "npc":"邻里与合作", "neighbors":"邻里与合作", "workbench":"工位 · 制作1批", "water":"封闭应急储水装置", "quests":"当前任务", "settings":"键位与界面", "pause":"歇一会儿", "new_world":"新建生成村落"}.get(route.page, "现场详情")
	if Factory.TITLES.has(str(route.page)): _title.text = Factory.TITLES[str(route.page)]
	if route.page=="factory_inventory" and str(route.get("subject","")).is_empty():_title.text="随身背包"
	if route.page=="chapter_complete":_title.text="第一章 · 旧村复兴"
	if route.page == "zone_planning": _title.text = "区域规划"
	if Factory.enabled(factory) and str(route.page).begins_with("factory") and str(route.page) not in ["factory_module", "factory_confirm"]:
		var horizontal := Composition.form(str(route.page)) == "planning" or get_viewport_rect().size.x < 1100 * minf(text_scale, 1.25)
		var navigation: Container = _planning_navigation if horizontal else _panel_navigation
		var basis:Array=[str(route.page)=="factory_catalog",horizontal,text_scale]
		for section_name:String in ["modules","production","logistics","workforce"]:
			basis.append(Factory.section(factory,section_name).get("available",false))
		if basis!=_navigation_basis:
			_clear(_panel_navigation);_clear(_planning_navigation)
			FactoryPanels.navigation(self,navigation,str(route.page))
			_navigation_basis=basis
			navigation_rebuilt=true
		else:
			for item:Node in navigation.get_children():
				if item is Button and item.toggle_mode:
					var selected:bool=str(item.get_meta("ui_focus_key",""))=="factory:nav:"+str(route.page)
					item.set_pressed_no_signal(selected)
					item.tooltip_text="当前页面" if selected else ""
		navigation.show()
	if route.page == "factory_module":
		var object := Factory.instance(factory, str(route.get("subject", "")))
		_title.text = str(object.get("name", "设施详情"))
	elif route.page in ["npc", "npc_quick"]:
		_title.text = str(UiProjection.find(snapshot.get("actors", []), str(route.get("subject", ""))).get("name", "邻里与合作"))
	_back_button.disabled = world_change_busy()
	_back_button.tooltip_text = "世界切换尚在进行，请等待实际回执" if _back_button.disabled else ""
	if reused:
		_panel_view_hits+=1
		if navigation_rebuilt:_wire_choice_popups()
		_scroll.set_deferred("scroll_vertical",scroll)
		_settle_panel_size.call_deferred(_panel_render_serial)
		return
	if not capture_action.is_empty(): paragraph("正在改键：%s · 按新键，Esc取消" % capture_action)
	if not carry.is_empty(): paragraph("拿起 %s × %s · 选择目的格，Esc归位" % [carry.get("name", "物品"), UiProjection.number(carry.get("amount"))])
	if not _notice.text.is_empty() and not _panel_notice.visible: paragraph(_notice.text)
	if route.page == "zone_planning":
		zone_planning.render(self, _body)
		_planning_footer.show()
		zone_planning.render_footer(self, _planning_footer)
	elif route.page == "npc_quick":
		var id := str(route.get("subject", ""))
		var state := CompanionCard.present(UiProjection.find(snapshot.get("actors", []), id), factory)
		CompanionCard.render(self, _body, id, state)
		_planning_footer.show()
		CompanionCard.footer(self, _planning_footer, id, state)
	elif route.page == "water": Water.render(self, _body, str(route.get("subject", "")))
	elif route.page == "factory_stock": ChapterPanel.stock(self,_body,chapter_stock)
	elif route.page == "chapter_complete": ChapterPanel.ending(self,_body,snapshot.get("village",{}).get("chapter_one",{}))
	elif str(route.page).begins_with("factory"): FactoryPanels.render(self, _body, route)
	else: Panels.render(self, _body, route)
	if _body.get_parent()!=_scroll:_scroll.add_child(_body)
	_body_signature=_visible_panel_signature() if _body_cacheable else 0
	_wire_choice_popups()
	if route.page == "factory_alerts" and factory_view.get("map_locating", false):
		factory_view.erase("map_locating")
		scroll = 0; key = ""; _dialog.grab_focus()
	if route.page == "factory_handbook" and factory_view.get("handbook_selection_changed", false):
		factory_view.erase("handbook_selection_changed")
		scroll = 0
	_scroll.set_deferred("scroll_vertical", scroll)
	_settle_panel_size.call_deferred(_panel_render_serial)
	if str(route.page) in ["factory", "factory_people"]: _fit_sparse_panel.call_deferred(_panel_render_serial)
	if not key.is_empty(): _restore_focus.call_deferred(key, _panel_render_serial, caret, scroll if route.page in ["inventory", "container", "factory_inventory"] else -1)

func _clear_panel_views()->void:
	for cached:Dictionary in _panel_views.values():
		var body:Variant=cached.get("body")
		if is_instance_valid(body) and body!=_body:body.free()
	_panel_views.clear();_body_route="";_body_signature=0;_body_cacheable=false;_panel_view_hits=0
	_navigation_basis.clear()

func _select_panel_body(route:Dictionary,signature:int)->bool:
	var key:String=str([route.get("page"),route.get("subject","")])
	var cacheable:bool=str(route.page) in ["pause","settings","factory_catalog","factory_inventory","inventory","container","factory_people","factory_alerts"] and carry.is_empty() and drag.is_empty() and capture_action.is_empty()
	if _body_route!=key:
		if is_instance_valid(_body):
			if _body.get_parent()==_scroll:_scroll.remove_child(_body)
			if _body_cacheable:_panel_views[_body_route]={"body":_body,"signature":_body_signature,"map":_known_map_canvas if is_instance_valid(_known_map_canvas) and _body.is_ancestor_of(_known_map_canvas) else null,"map_label":_known_map_focus_label if is_instance_valid(_known_map_focus_label) and _body.is_ancestor_of(_known_map_focus_label) else null}
			else:_body.queue_free()
		var cached:Dictionary=_panel_views.get(key,{}) if cacheable else {}
		_panel_views.erase(key)
		if not cached.is_empty() and is_instance_valid(cached.get("body")):
			_body=cached.body;_body_signature=int(cached.signature)
			_known_map_canvas=cached.get("map");_known_map_focus_label=cached.get("map_label")
		else:
			_known_map_canvas=null;_known_map_focus_label=null
			_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_body.minimum_size_changed.connect(func():_fit_sparse_panel.call_deferred(_panel_render_serial))
			_body_signature=0
		_scroll.add_child(_body)
		_body_route=key
	_body_cacheable=cacheable
	while _panel_views.size()>8:
		var oldest:String=str(_panel_views.keys()[0])
		var obsolete:Variant=_panel_views[oldest].get("body")
		if is_instance_valid(obsolete):obsolete.queue_free()
		_panel_views.erase(oldest)
	return cacheable and _body_signature!=0 and _body_signature==signature

func _settle_panel_size(render_serial: int) -> void:
	# On the first open, wrapped chrome is initially measured at its old width.
	# Fit again after native layout so stale wrapped minima cannot push the
	# pinned inventory hotbar beyond the window. Long content stays scrollable.
	await get_tree().process_frame
	if render_serial == _panel_render_serial and not pages.is_empty():
		# A new page first inherits the previous body's native minimum size.
		# Force one settled layout after that body has actually been replaced.
		_shell_layout_basis.clear()
		_size_dialog()

func _restore_focus(key: String, render_serial: int = -1, caret: int = -1, restore_scroll: int = -1) -> void:
	if pages.is_empty() or not _modal.visible or (render_serial >= 0 and render_serial != _panel_render_serial): return
	for node in _dialog.find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and node.get_meta("ui_focus_key", "") == key and not (node is BaseButton and node.disabled):
			# Rebuilding a grid can give a retained focus key a transient size.
			# Keep the visible inventory rows fixed while returning keyboard focus.
			var follow_focus := _scroll.follow_focus
			if restore_scroll >= 0: _scroll.follow_focus = false
			node.grab_focus()
			_scroll.follow_focus = follow_focus
			if restore_scroll >= 0: _scroll.scroll_vertical = restore_scroll
			if node is LineEdit and caret >= 0: node.caret_column = caret
			return
	_dialog.grab_focus()

func _clear(parent: Node) -> void:
	parent.remove_meta("ui_reason_cache")
	for node in parent.get_children():
		parent.remove_child(node)
		node.queue_free()

func notify(text: String, failed: bool = false, diagnostic: String = "") -> void:
	if not is_node_ready(): return
	_notice_serial += 1
	var target := _feedback_target() if failed and text.strip_edges() == "MISSING_TOOL" else {}
	_notice.text = UiProjection.reason_text(text, target) if failed else text
	_notice.tooltip_text = (diagnostic if not diagnostic.is_empty() else text) if failed else ""
	_notice.visible = not text.is_empty()
	_notice.add_theme_color_override("font_color", UiTheme.RUST if failed else UiTheme.MOSS)
	if not text.is_empty():
		# A local display lifetime only; no simulation clock, action retry or cost.
		get_tree().create_timer(4.0, true).timeout.connect(_expire_notice.bind(_notice_serial))
	queue_refresh()

func show_pickup(items: Dictionary) -> void:
	# Caller supplies only the accepted inventory-transfer event's actual delta.
	# This draws a receipt and never changes stock, capacity or simulation time.
	if not is_node_ready(): return
	var parts: PackedStringArray = []
	for item: String in items:
		var quantity: Variant = items[item]
		if (quantity is int or quantity is float) and float(quantity) > 0:
			parts.append("+" + UiProjection.number(quantity) + " " + UiProjection.item_name(item))
	if parts.is_empty(): return
	if is_instance_valid(_pickup_tween): _pickup_tween.kill()
	_pickup_toast.text = "   ".join(parts)
	_pickup_toast.modulate = Color.WHITE; _pickup_toast.show()
	_position_feedback.call_deferred()
	_pickup_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pickup_tween.tween_interval(1.4)
	_pickup_tween.tween_property(_pickup_toast,"modulate:a",0.0,0.5)
	_pickup_tween.tween_callback(func():
		_pickup_toast.hide()
		_position_feedback())

func set_auto_pickup(enabled: bool) -> void:
	var receipt := router_call("set_auto_pickup", [enabled])
	notify("自动拾取已" + ("开启" if enabled else "关闭") if receipt.get("ok",false) else str(receipt.get("reason","设置失败")), not receipt.get("ok",false))
	queue_refresh()

func _expire_notice(serial: int) -> void:
	if serial != _notice_serial or not is_node_ready(): return
	_notice.text = ""
	_notice.tooltip_text = ""
	_notice.hide()
	queue_refresh()

func router_call(method: String, arguments: Array = []) -> Dictionary:
	if is_instance_valid(_recovery_menu): return {"ok":false, "code":"BUSY", "reason":"请先完成或退出恢复选择"}
	if world_change_busy(): return {"ok":false, "code":"BUSY", "reason":"世界切换进行中，请等待实际回执"}
	if not is_instance_valid(input_router) or not input_router.has_method(method):
		return {"ok":false, "reason":"输入路由尚未提供 " + method}
	if method == "assign_slot" and arguments.size() == 2:
		var reference := UiProjection.normalize_reference(arguments[1])
		var key := UiProjection.reference_key(reference)
		# Current A router stores {kind,id}; retain the contract's typed ID at the boundary.
		if not key.is_empty(): reference["id"] = key.substr(key.find(":") + 1)
		arguments = [arguments[0], reference]
	var value: Variant = input_router.callv(method, arguments)
	# Void reset/cancel setters may be accepted; action receipts must remain explicit.
	if value == null and method in ["reset_bindings", "cancel", "set_mode"]: return {"ok":true}
	return value if value is Dictionary else {"ok":false, "reason":"未收到输入路由回执"}

func module_preview_reason() -> String:
	if not Factory.enabled(factory): return "完整模块目录尚不可用"
	if not is_instance_valid(input_router) or not input_router.has_method("begin_module_placement"): return "场景选址尚未就绪；当前可查看足迹、成本与作业面"
	return ""

func begin_module_preview(definition_id: String) -> Dictionary:
	var reason := module_preview_reason()
	if reason.is_empty() and Factory.definition(factory, definition_id).is_empty(): reason = "模块定义已改变，请重新选择"
	if not reason.is_empty():
		notify(reason, true)
		return {"ok":false,"reason":reason}
	var worker:String=building_dispatch_actor() if not pages.is_empty() and pages.back().page=="factory_catalog" else ""
	var receipt := router_call("begin_module_placement", [definition_id] if worker.is_empty() else [definition_id,worker])
	if receipt.get("ok", false):
		_sync_modal()
		refresh()
		_dialog.grab_focus()
	else: notify(str(receipt.get("reason", "未能开始选址")), true)
	return receipt

func factory_transfer_reason(stock: Dictionary) -> String:
	if stock.is_empty() or not stock.get("searched", false): return "尚未搜索，无法取放"
	if stock.get("display_only",false):return "当前为公开缓存汇总，靠近建筑即可取放"
	# Empty preview checks contact and ownership without choosing or moving goods.
	var check := availability(request("deposit", str(stock.id), {"items":{}, "tool_ids":[]}))
	return "" if check.get("ok", false) else UiProjection.feedback_text(check, {}, "距离不足，请走近建筑或容器后取放")

func select_work_mode(mode: String, target_id: String = "") -> Dictionary:
	var result: Dictionary
	if mode in ["repair", "move", "demolish", "destroy"] and is_instance_valid(input_router) and input_router.has_method("begin_structure_action"):
		result = router_call("begin_structure_action", [mode, target_id])
	elif mode.begins_with("terrain_"):
		var hand: Dictionary = input_router.call("state") if is_instance_valid(input_router) and input_router.has_method("state") else {}
		var brush: Dictionary = hand.get("terrain", {})
		return apply_terrain_brush(mode.trim_prefix("terrain_"), int(brush.get("material", 2)), float(brush.get("height", 0)), int(brush.get("brush_cells", 1)))
	else: result = router_call("set_mode", [mode])
	if result.get("ok", false):
		close_panels()
		notify("已选择" + WorkModes.title(mode) + " · 请在场景中操作")
	else:
		notify(str(result.get("reason", "模式未能切换")), true)
		queue_refresh()
	return result

func apply_terrain_brush(operation: String, material: int, height: float, brush_cells: int) -> Dictionary:
	var result := router_call("set_terrain_brush", [operation, material, height, brush_cells])
	if result.get("ok", false):
		close_panels()
		notify("已选择" + WorkModes.title("terrain_" + operation) + " · 请在场景中操作")
	else:
		notify(str(result.get("reason", "笔刷设置未被接受")), true)
		queue_refresh()
	return result

func read_service_approaches(module_id: String, force: bool = false) -> Dictionary:
	var unavailable := {"available":false, "module_id":module_id, "approaches":[], "reason":"建筑附近通路信息暂不可用"}
	if Factory.instance(factory, module_id).is_empty(): return unavailable
	var player := UiProjection.player(snapshot)
	var intent: Variant = player.get("intent")
	var cache_key: Array = [_generation, module_id, factory.get("world_id"), factory.get("world_revision", factory.get("revision")), snapshot.get("revision"), snapshot.get("command_revision"), player.get("id"), player.get("regionId"), player.get("x"), player.get("y"), player.get("z"), player.get("position"), intent.get("id") if intent is Dictionary else null]
	if not force and cache_key == _service_access_key: return _service_access_value.duplicate(true)
	var result: Dictionary = unavailable
	if is_instance_valid(runtime) and runtime.has_method("module_service_approaches"):
		var value: Variant = runtime.call("module_service_approaches", module_id, str(player.get("id", "player")))
		if value is Dictionary and value.get("available") is bool and value.get("module_id") == module_id and value.get("approaches") is Array: result = value.duplicate(true)
	_service_access_key = cache_key.duplicate(true)
	_service_access_value = result.duplicate(true)
	return result.duplicate(true)

func request(kind: String, target_id: String, payload: Dictionary = {}, destination: Dictionary = {}) -> Dictionary:
	_serial += 1
	return {"command_id":"ui:%s:%s" % [get_instance_id(), _serial], "actor_id":str(UiProjection.player(snapshot).get("id", "")), "kind":kind, "target_id":target_id, "destination":destination.duplicate(true), "payload":payload.duplicate(true), "expected_revision":snapshot.get("command_revision", snapshot.get("revision", -1))}

func availability(command: Dictionary) -> Dictionary:
	if is_instance_valid(_recovery_menu): return {"ok":false, "code":"BUSY", "reason":"请先完成或退出恢复选择"}
	if world_change_busy(): return {"ok":false, "code":"BUSY", "reason":"世界切换进行中，请等待实际回执"}
	if not is_instance_valid(runtime) or not runtime.has_method("availability"): return {"ok":false, "reason":"真实行动服务尚未接入"}
	if int(command.expected_revision) < 0 or str(command.actor_id).is_empty(): return {"ok":false, "reason":"世界版本／角色尚未提供"}
	var value: Variant = runtime.call("availability", command)
	return value if value is Dictionary else {"ok":false, "reason":"未收到行动预检"}

func execute(kind: String, target_id: String, payload: Dictionary = {}, leave_scene: bool = false, worker_id: String = "", destination: Dictionary = {}) -> Dictionary:
	if world_change_busy(): return {"ok":false, "code":"BUSY", "reason":"世界切换进行中，请等待实际回执"}
	if not is_instance_valid(runtime) or not runtime.has_method("command"): return {"ok":false, "reason":"真实行动服务尚未接入"}
	if is_instance_valid(_recovery_menu): return {"ok":false, "code":"BUSY", "reason":"请先完成或退出恢复选择"}
	var command := request(kind, target_id, payload, destination)
	if runtime.has_method("get_revision") and runtime.has_method("actor"):
		# A click needs the current revision and player ID. The command owner
		# validates the full operation, so skip a world read and duplicate preflight.
		command.expected_revision = runtime.get_revision()
		command.actor_id = str(runtime.actor("player").get("id", ""))
	if not worker_id.is_empty() and kind in ["workforce.assign", "workforce.clear", "workforce.priority"]: command.actor_id = worker_id
	var receipt: Variant = runtime.call("command", command)
	var result: Dictionary = receipt if receipt is Dictionary else {"ok":false, "reason":"未收到行动回执，请核对现场"}
	if result.get("ok", false):
		if kind == "craft" and not target_id.is_empty() and not str(payload.get("recipe_id", "")).is_empty():
			# View preference only: rebuild all quantities/tools and preflight next time.
			_recent_crafts.erase(target_id)
			_recent_crafts[target_id] = {"recipe_id":str(payload.recipe_id), "repair_tool_id":str(payload.get("repair_tool_id", ""))}
			if _recent_crafts.size() > 16: _recent_crafts.erase(_recent_crafts.keys()[0])
		if kind in ["alerts.acknowledge", "alerts.ignore"]:
			notify("已记录已阅读；问题尚未解决" if kind == "alerts.acknowledge" else "已暂忽略本次提醒；问题尚未解决，紧急升级会再次显示")
		elif kind == "handbook.favorite": notify("已收藏条目" if payload.get("enabled", false) else "已取消收藏")
		elif kind == "handbook.track": notify("已固定目标 · 可查看所需材料与来源" if payload.get("enabled", false) else "已取消固定目标")
		elif kind == "factory.configure": notify("目标已配置 · 世界暂停时加工尚未推进，关页后按实际条件继续" if snapshot.get("hand", {}).get("world_paused", false) or not pages.is_empty() else "目标已配置 · 生产仍需现场材料、能量与输出空间")
		elif kind == "night.start": notify("开始守夜 · 留意来袭方向")
		elif kind == "night.next": notify("强化已生效 · 下一波即将到来")
		elif kind == "night.reward": notify("补给已放入背包")
		else: notify("已受理 · 结果与工时以实际行动为准")
		if leave_scene: close_panels()
	else: notify(UiProjection.action_feedback(result, kind), true, UiProjection.feedback_diagnostic(result))
	queue_refresh()
	return result

func _create_drag(slot: Dictionary) -> Dictionary:
	if world_change_busy(): return {}
	if Factory.enabled(factory) and not Factory.stock_visible(factory, snapshot, str(slot.get("stock_id", ""))): return {}
	var reference: Dictionary = UiProjection.normalize_reference(slot.get("reference", {}))
	if UiProjection.reference_key(reference).is_empty(): return {}
	_serial += 1
	carry.clear()
	drag = {"ui_drag":str(get_instance_id()) + ":" + str(_serial), "generation":_generation, "source":slot.duplicate(true), "reference":reference.duplicate(true), "amount":float(slot.get("quantity", 0)), "name":str(slot.get("entry", {}).get("name", reference.get("definition_id", "物品")))}
	_trace_drag("create_reference", {"source":_trace_slot(slot), "amount":drag.amount})
	_sync_modal()
	return drag.duplicate(true)

func _valid_carry(data: Dictionary) -> bool:
	return data.get("generation") == _generation and not str(data.get("ui_drag", "")).is_empty() and (data.get("ui_drag") == drag.get("ui_drag") or data.get("ui_drag") == carry.get("ui_drag"))

func _can_drop(destination: Dictionary, data: Dictionary) -> bool:
	if world_change_busy(): return false
	if not _valid_carry(data): return false
	if destination.get("kind") == "hotbar":
		var reference: Dictionary = data.get("reference", {})
		var pack := UiProjection.player_stock(snapshot)
		return not UiProjection.reference_key(reference).is_empty() and str(data.get("source", {}).get("stock_id", "")) == str(pack.get("id", "")) and (reference.get("kind") == "recipe" or not UiProjection.entry(pack, snapshot, reference).is_empty())
	if data.get("source", {}).get("kind") == "hotbar": return false
	if data.get("reference", {}).get("kind") == "recipe": return false
	var stock := UiProjection.find(snapshot.get("stocks", []), str(destination.get("stock_id", "")))
	if stock.is_empty() or not stock.get("searched", false): return false
	if str(destination.stock_id) == str(data.source.get("stock_id", "")): return true
	if not layout.destination_reason(stock, snapshot, int(destination.index), data.reference).is_empty(): return false
	if Factory.enabled(factory):
		if not Factory.stock_visible(factory,snapshot,str(data.source.get("stock_id",""))) or not Factory.stock_visible(factory,snapshot,str(destination.stock_id)):return false
		var pack := UiProjection.player_stock(snapshot)
		var subject := _inventory_subject()
		var kind := "deposit" if str(data.source.get("stock_id", "")) == str(pack.get("id", "")) and str(destination.stock_id) == subject else "take" if str(data.source.get("stock_id", "")) == subject and str(destination.stock_id) == str(pack.get("id", "")) else ""
		if kind.is_empty(): return false
		var payload := {"items":{}, "tool_ids":[]}
		if data.reference.kind == "tool": payload.tool_ids.append(str(data.reference.tool_id))
		else: payload.items[str(data.reference.item_id)] = float(data.amount)
		return availability(request(kind, subject, payload)).get("ok", false)
	return true

func _drop(destination: Dictionary, data: Dictionary) -> void:
	_trace_drag("drop_received", {"destination":_trace_slot(destination)})
	if is_instance_valid(runtime) and runtime.has_method("snapshot"):
		var current: Variant = runtime.call("snapshot")
		if current is Dictionary: snapshot = current
	if not _can_drop(destination, data):
		_trace_drag("drop_rejected", {"reason":"destination_or_reference_changed"})
		notify("目的格或物品已改变，物品仍由原库存持有", true)
		return
	if data.source.get("kind") == "inventory":
		var source_stock := UiProjection.stock(snapshot, str(data.source.get("stock_id", "")))
		var cells := layout.cells(source_stock, snapshot)
		var source_index := int(data.source.get("index", -1))
		if source_index < 0 or source_index >= cells.size() or cells[source_index].entry.get("key", "") != UiProjection.reference_key(data.reference) or float(data.amount) > float(cells[source_index].quantity):
			_trace_drag("drop_rejected", {"reason":"source_or_amount_changed"})
			notify("源格或数量已变化，请重新拿起", true)
			return
	if destination.kind == "hotbar":
		var result := router_call("assign_slot", [int(destination.index), data.reference])
		notify("已绑定真实物品引用" if result.get("ok", false) else str(result.get("reason", "绑定失败")), not result.get("ok", false))
	elif str(destination.stock_id) == str(data.source.stock_id):
		var stock := UiProjection.find(snapshot.get("stocks", []), str(destination.stock_id))
		var reason := layout.move(stock, snapshot, int(data.source.index), int(destination.index), float(data.amount))
		if not reason.is_empty(): notify(reason, true)
		# Sorting is UI allocation only; no world revision changes to invalidate it.
		else: _panel_signature = 0;_body_signature=0
	else: _transfer(data, str(destination.stock_id), int(destination.index))
	_trace_drag("drop_finished", {"destination":_trace_slot(destination), "notice":_notice.text})
	carry.clear()
	drag.clear()
	_sync_modal()
	queue_refresh()

func _activate_slot(slot: Dictionary) -> void:
	if world_change_busy(): return
	if not carry.is_empty():
		_drop(slot, carry.duplicate(true))
		return
	if slot.kind == "hotbar":
		var result := router_call("select_slot", [int(slot.index)])
		if not result.get("ok", false): notify(str(result.get("reason", "选栏失败")), true)
		queue_refresh()
		return
	if slot.get("entry", {}).is_empty(): return
	var data := _create_drag(slot)
	if data.is_empty(): return
	carry = data.duplicate(true)
	drag.clear()
	if slot.get("quick_transfer",false):
		carry.amount = float(slot.get("available", 0))
		transfer_carried()
	_sync_modal()
	queue_refresh()

func transfer_carried() -> void:
	if carry.is_empty() or pages.is_empty():return
	var pack:=UiProjection.player_stock(snapshot)
	var destination:=_inventory_subject() if str(carry.source.get("stock_id",""))==str(pack.get("id","")) else str(pack.get("id",""))
	_transfer(carry.duplicate(true),destination)
	cancel_transient()
	queue_refresh()

func take_all_payload(stock: Dictionary, state: Dictionary) -> Dictionary:
	var payload := {"items":{}, "tool_ids":[]}
	if stock.get("display_only", false): return payload
	for entry: Dictionary in UiProjection.entries(stock, state):
		if float(entry.get("available", 0)) <= 0: continue
		var reference: Dictionary = entry.get("reference", {})
		if reference.get("kind") == "item": payload.items[str(reference.item_id)] = float(entry.available)
		elif reference.get("kind") == "tool": payload.tool_ids.append(str(reference.tool_id))
	return payload

func _inventory_subject() -> String:
	if pages.is_empty(): return ""
	var subject := str(pages.back().get("subject", ""))
	if pages.back().get("page") != "factory_module": return subject
	var module := Factory.instance(factory, subject)
	var selected := str(factory_view.get("building-stock:" + subject, ""))
	return selected if module.get("stock_refs", {}).values().has(selected) else ""

func take_all_current() -> Dictionary:
	if world_change_busy() or pages.is_empty() or not carry.is_empty() or not drag.is_empty(): return {"ok":false,"reason":"先放回手中物品"}
	var subject := _inventory_subject()
	if subject.is_empty(): return {"ok":false,"reason":"请先打开现场容器"}
	var state: Dictionary = runtime.call("snapshot") if is_instance_valid(runtime) else {}
	var visible: Dictionary = Factory.read(runtime) if Factory.enabled(factory) else {}
	if Factory.enabled(factory) and not Factory.stock_visible(visible,state,subject):
		notify("容器可见性已改变，请先到现场搜索", true)
		return {"ok":false,"reason":"容器不再可见"}
	var source := UiProjection.stock(state, subject)
	var payload := take_all_payload(source, state)
	if payload.items.is_empty() and payload.tool_ids.is_empty():
		notify("这里没有未预留的可取物品")
		return {"ok":false,"reason":"没有可取物品"}
	var before_pack := UiProjection.player_stock(state)
	var receipt := execute("take", subject, payload)
	if not receipt.get("ok", false): return receipt
	var after: Dictionary = runtime.call("snapshot")
	var pack := UiProjection.player_stock(after)
	var changed := 0
	for item: String in payload.items:
		var delta := float(pack.get("items", {}).get(item, 0)) - float(before_pack.get("items", {}).get(item, 0))
		if delta > 0: changed += 1
	for tool: String in payload.tool_ids:
		if not UiProjection.entry(pack,after,{"kind":"tool","tool_id":tool}).is_empty(): changed += 1
	if changed > 0: notify("已拿取全部可用物品 · " + str(changed) + "项入包")
	else: notify("取物已受理，尚未观察到库存变化，请核对", true)
	queue_refresh()
	return receipt

func _transfer(data: Dictionary, to_id: String, to_index: int = -1) -> void:
	if world_change_busy(): return
	var before: Dictionary = runtime.call("snapshot") if is_instance_valid(runtime) else {}
	var source := UiProjection.find(before.get("stocks", []), str(data.source.get("stock_id", "")))
	var destination := UiProjection.find(before.get("stocks", []), to_id)
	var pack := UiProjection.player_stock(before)
	var visible: Dictionary=Factory.read(runtime) if Factory.enabled(factory) else {}
	if Factory.enabled(factory) and (not Factory.stock_visible(visible,before,str(source.get("id",""))) or not Factory.stock_visible(visible,before,to_id)):
		notify("容器可见性已改变，请先到现场搜索",true)
		return
	var item := UiProjection.entry(source, before, data.reference)
	var amount := float(data.get("amount", 0))
	if source.is_empty() or destination.is_empty() or item.is_empty() or amount <= 0 or amount > float(item.get("available", 0)):
		notify("物品、预留或容器已改变，请重新选择", true)
		return
	if to_index >= 0 and not layout.destination_reason(destination, before, to_index, data.reference).is_empty():
		notify("跨容器请放入空格或同类物品格", true)
		return
	var kind := ""
	var subject := _inventory_subject()
	if source.id == pack.get("id") and to_id == subject: kind = "deposit"
	elif source.id == subject and to_id == pack.get("id"): kind = "take"
	if kind.is_empty():
		notify("当前容器已改变，请重新打开", true)
		return
	var payload := {"items":{}, "tool_ids":[]}
	if data.reference.kind == "tool": payload.tool_ids.append(str(data.reference.tool_id))
	else: payload.items[str(data.reference.item_id)] = amount
	var receipt := execute(kind, subject, payload)
	if not receipt.get("ok", false): return
	var after: Dictionary = runtime.call("snapshot")
	var after_destination := UiProjection.find(after.get("stocks", []), to_id)
	var old := UiProjection.entry(destination, before, data.reference)
	var current := UiProjection.entry(after_destination, after, data.reference)
	if float(current.get("quantity", 0)) - float(old.get("quantity", 0)) <= 0:
		notify("取放已受理，尚未观察到真实库存变化，请核对", true)
		return
	layout.transferred(source, before, int(data.source.index), amount)
	if to_index >= 0: layout.received(destination, before, after_destination, after, to_index, data.reference)
	notify("物品已实际转移")

func _split_slot(slot: Dictionary) -> void:
	if world_change_busy(): return
	if slot.get("kind") != "inventory" or slot.get("entry", {}).is_empty(): return
	cancel_transient()
	var item: Dictionary = slot.entry
	var step := float(item.get("step", 1))
	if float(slot.get("quantity", 0)) <= step:
		notify("此格没有可拆分份额")
		return
	_split_layer = PanelContainer.new()
	# This overlay uses explicit viewport coordinates. Center anchors would add
	# another half viewport on parenting and put the confirm button off screen.
	_split_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_split_layer.custom_minimum_size = Vector2(380, 180)
	_modal.add_child(_split_layer)
	_split_layer.minimum_size_changed.connect(_size_split_layer)
	var body := VBoxContainer.new()
	_split_layer.add_child(body)
	body.add_child(label("拆分 · " + str(item.name)))
	var amount := SpinBox.new()
	amount.min_value = step
	amount.max_value = float(slot.quantity) - step
	amount.step = step
	amount.value = maxf(step, floorf(float(slot.quantity) / (2.0 * step)) * step)
	body.add_child(amount)
	body.add_child(button("拿起这份", func():
		var data := _create_drag(slot)
		if data.is_empty(): return
		data.amount = amount.value
		carry = data.duplicate(true)
		drag.clear()
		_split_layer.queue_free()
		_split_layer = null
		queue_refresh(), "split:confirm"))
	body.add_child(button("取消 · 原物归位", cancel_ui, "split:cancel"))
	_size_split_layer()
	amount.get_line_edit().grab_focus()

func file_request_busy() -> bool:
	return is_instance_valid(_recovery_menu) or saving or importing or exporting or world_change_busy() or not _file_operation.is_empty() or storage_state().get("busy", false)

func world_change_busy() -> bool:
	var state := storage_state()
	return world_starting or world_restoring or (state.get("busy", false) and state.get("status") in ["loading", "generating"])

func restore_saved_world() -> void:
	if file_request_busy(): return
	var reason := storage_reason("restore_saved_world", true)
	if not reason.is_empty():
		notify(reason, true)
		return
	cancel_transient()
	world_restoring = true
	_sync_modal()
	var id := _next_file_request("restore-saved")
	notify("正在恢复上次手动保存…")
	_await_saved_world(weakref(self), runtime, _generation, id)

static func _await_saved_world(view_ref: WeakRef, authority: Object, generation: int, id: String) -> void:
	# A awaits readiness before activation and disposes this UI on success.
	# Failed preparation returns to the existing view; late receipts stay weak.
	var receipt: Variant = await authority.call("restore_saved_world", id)
	var view: Variant = view_ref.get_ref()
	if not is_instance_valid(view) or not view.is_inside_tree() or view._generation != generation: return
	if view.is_queued_for_deletion() or view.get_parent().is_queued_for_deletion(): return
	view._saved_world_finished(receipt, id)

func _saved_world_finished(receipt: Variant, id: String) -> void:
	world_restoring = false
	storage_state(true)
	var ok := _file_receipt_ok(receipt, id)
	if ok:
		layout.clear()
		cancel_transient()
		pages.clear()
	notify(str(receipt.get("reason", "已恢复上次手动保存")) if ok else "恢复未完成 · " + _file_reason(receipt, id), not ok)
	_sync_modal()
	queue_refresh()
	if not ok and receipt is Dictionary and receipt.get("request_id") == id and receipt.get("candidates") is Array:
		open_recovery_candidates(receipt.candidates)

func open_recovery_candidates(provided: Variant = null) -> void:
	if file_request_busy(): return
	var reason := storage_reason("restore_recovery_candidate", true)
	if not reason.is_empty(): notify(reason, true); return
	var rows: Array = []
	if provided is Array:
		rows = provided.duplicate(true)
	else:
		reason = storage_reason("list_recovery_candidates", true)
		if not reason.is_empty(): notify(reason, true); return
		var result: Variant = runtime.call("list_recovery_candidates", "")
		if not result is Dictionary or not result.get("ok", false) or not result.get("candidates") is Array:
			notify(UiProjection.feedback_text(result, {}, "未收到恢复候选") if result is Dictionary else "未收到恢复候选", true)
			return
		rows = result.candidates.duplicate(true)
	cancel_transient()
	var menu := Recovery.new()
	menu.allow_cancel = true; menu.text_scale = text_scale
	menu.configure(rows, _restore_recovery_selection.bind(weakref(self), runtime, _generation), Callable())
	menu.closed.connect(_recovery_closed)
	_recovery_menu = menu
	add_child(menu)
	_sync_modal()

func _recovery_closed() -> void:
	_recovery_menu = null
	_sync_modal(); queue_refresh()
	if not pages.is_empty(): _dialog.grab_focus()

static func _restore_recovery_selection(candidate_id: String, sha256: String, view_ref: WeakRef, authority: Object, generation: int) -> Dictionary:
	var view: Variant = view_ref.get_ref()
	if not is_instance_valid(view) or not view.is_inside_tree() or view._generation != generation:
		return {"ok":false, "code":"STALE_INPUT", "reason":"恢复界面已换代，请重新打开"}
	# The menu itself is modal, not a file request. Only the submitted choice
	# enters A's existing world-restoring gate and receives a real request ID.
	if view.saving or view.exporting or view.importing or view.world_change_busy():
		return {"ok":false, "code":"BUSY", "reason":"文件或世界请求正在进行"}
	var reason: String = view.storage_reason("restore_recovery_candidate", true)
	if not reason.is_empty(): return {"ok":false, "code":"NOT_READY", "reason":reason}
	view.cancel_transient(); view.world_restoring = true; view._sync_modal()
	var id: String = view._next_file_request("recovery-choice")
	var receipt: Variant = await authority.call("restore_recovery_candidate", candidate_id, sha256, id)
	view = view_ref.get_ref()
	if is_instance_valid(view) and view.is_inside_tree() and not view.is_queued_for_deletion() and view._generation == generation:
		view.world_restoring = false; view.storage_state(true); view._sync_modal(); view.queue_refresh()
	if not receipt is Dictionary or receipt.get("request_id") != id:
		return {"ok":false, "code":"UNCONFIRMED", "reason":"未收到匹配本次选择的回执，原档保持"}
	return receipt

func choose_new_world() -> void:
	if file_request_busy(): return
	var reason := new_world_storage_reason(true)
	if not reason.is_empty():
		notify(reason, true)
		return
	_new_world_receipt.clear()
	_new_world_seed_text = str(DEFAULT_NEW_WORLD_SEED)
	_new_world_profile = str(snapshot.get("opening_profile", "playtest" if not UiProjection.playtest_profile(snapshot).is_empty() else "normal"))
	open_panel("new_world")
	_restore_focus.call_deferred("new-world:cancel")

func new_world_seed_reason() -> String:
	var value := _new_world_seed_text.strip_edges()
	if value.is_empty(): return ""
	return "种子须为0至2147483647的整数；留空使用713" if not value.is_valid_int() or int(value) < 0 or int(value) > 2147483647 else ""

func new_world_storage_reason(live: bool = false) -> String:
	var reason := storage_reason("start_profiled_world" if is_instance_valid(runtime) and runtime.has_method("start_profiled_world") else "start_new_world", live)
	return storage_reason("save_async", live) if reason.is_empty() else reason

func confirm_new_world() -> void:
	# A second click/shortcut cannot submit again, even before deferred rendering.
	if file_request_busy() or pages.is_empty() or pages.back().page != "new_world": return
	var reason := new_world_storage_reason(true)
	if reason.is_empty(): reason = new_world_seed_reason()
	if not reason.is_empty():
		notify(reason, true)
		queue_refresh()
		return
	cancel_transient()
	world_starting = true
	_new_world_receipt.clear()
	_sync_modal()
	var id := _next_file_request("new-world")
	notify("正在保存当前世界，保存成功后生成新村落…")
	queue_refresh()
	# A replaces/frees this UI on successful mount. A static waiter only retains
	# a weak UI reference; it never resumes an instance method on a freed view.
	var seed_text := _new_world_seed_text.strip_edges()
	_await_new_world(weakref(self), runtime, _generation, id, DEFAULT_NEW_WORLD_SEED if seed_text.is_empty() else int(seed_text), _new_world_profile)

static func _await_new_world(view_ref: WeakRef, authority: Object, generation: int, id: String, seed: int, profile: String = "normal") -> void:
	# The live native coordinator currently generates without saving the old world.
	# Preserve it through the sole storage authority before requesting replacement.
	var save_id := id + ":preserve"
	var saved: Variant = await authority.call("save_async", save_id)
	var saving_view: Variant = view_ref.get_ref()
	if not is_instance_valid(saving_view) or not saving_view.is_inside_tree() or saving_view._generation != generation or saving_view.runtime != authority: return
	if saving_view.is_queued_for_deletion() or saving_view.get_parent().is_queued_for_deletion(): return
	if not saving_view._file_receipt_ok(saved, save_id):
		var code := str(saved.get("code", "SAVE_FAILED")) if saved is Dictionary and saved.get("request_id") == save_id else "UNCONFIRMED"
		saving_view._new_world_finished({"ok":false, "code":code, "reason":"当前世界保存未完成，未生成新村落 · " + saving_view._file_reason(saved, save_id), "request_id":id}, id)
		return
	# Do not retain the Control across A's awaited mount, which frees the old UI.
	saving_view = null
	var receipt: Variant
	if authority.has_method("start_profiled_world"): receipt = await authority.call("start_profiled_world", profile, seed, id)
	else: receipt = await authority.call("start_new_world", seed, id)
	var view: Variant = view_ref.get_ref()
	if not is_instance_valid(view) or not view.is_inside_tree() or view._generation != generation: return
	if view.is_queued_for_deletion() or view.get_parent().is_queued_for_deletion(): return
	view._new_world_finished(receipt, id)

func _new_world_finished(receipt: Variant, id: String) -> void:
	world_starting = false
	storage_state(true)
	var ok := _file_receipt_ok(receipt, id)
	_new_world_receipt = {"ok":ok, "reason":str(receipt.get("reason", "")) if ok else _file_reason(receipt, id), "code":str(receipt.get("code", "")) if receipt is Dictionary and receipt.get("request_id") == id else "UNCONFIRMED"}
	if ok:
		layout.clear()
		cancel_transient()
		pages.clear()
		notify(str(_new_world_receipt.reason))
	else:
		notify("新建村落未完成 · " + str(_new_world_receipt.reason), true)
	_sync_modal()
	queue_refresh()

func save_world() -> void:
	if file_request_busy(): return
	var reason := storage_reason("save_async", true)
	if not reason.is_empty():
		notify(reason, true)
		return
	saving = true
	var generation := _generation
	var id := _next_file_request("save")
	notify("正在保存完整世界…")
	queue_refresh()
	var receipt: Variant = await runtime.call("save_async", id)
	if generation != _generation or not is_inside_tree(): return
	saving = false
	var ok := _file_receipt_ok(receipt, id)
	notify("完整世界已保存" if ok else _file_reason(receipt, id), not ok)
	queue_refresh()

func choose_import() -> void:
	if file_request_busy(): return
	var reason := storage_reason("import_checkpoint_file", true)
	if not reason.is_empty():
		notify(reason, true)
		return
	_file_operation = "import"
	if is_instance_valid(input_router) and input_router.has_method("set_file_dialog"): input_router.call("set_file_dialog", true)
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "选择要恢复的世界存档／检查点"
	_file_dialog.popup_centered_ratio(0.7)

func _file_cancelled() -> void:
	_file_operation = ""
	if is_instance_valid(input_router) and input_router.has_method("set_file_dialog"): input_router.call("set_file_dialog", false)
	if not pages.is_empty(): _dialog.grab_focus()

func _file_selected(path: String) -> void:
	# File reading and validation belong to A; no UI-side FileAccess or decoder.
	var operation := _file_operation
	_file_cancelled()
	if operation not in ["import", "export"]: return
	var method := "import_checkpoint_file" if operation == "import" else "export_checkpoint_file"
	var reason := storage_reason(method, true)
	if not reason.is_empty():
		notify(reason, true)
		return
	if file_request_busy(): return
	importing = operation == "import"
	exporting = operation == "export"
	_sync_modal()
	var generation := _generation
	var id := _next_file_request(operation)
	notify("正在验证并导入新槽…" if importing else "正在写出已验证检查点…")
	queue_refresh()
	var receipt: Variant = await runtime.call(method, path, id)
	if generation != _generation or not is_inside_tree(): return
	importing = false
	exporting = false
	_sync_modal()
	var ok := _file_receipt_ok(receipt, id)
	if ok and operation == "import":
		_generation += 1
		layout.clear()
		cancel_transient()
	if receipt is Dictionary and receipt.get("code") == "CANCELLED":
		queue_refresh()
		return
	notify(("检查点已验证并导入新槽" if operation == "import" else "检查点已实际写出 · " + str(receipt.get("path", path))) if ok else _file_reason(receipt, id), not ok)
	queue_refresh()

func export_world() -> void:
	if file_request_busy(): return
	var reason := storage_reason("export_checkpoint_file", true)
	if not reason.is_empty():
		notify(reason, true)
		return
	_file_operation = "export"
	if is_instance_valid(input_router) and input_router.has_method("set_file_dialog"): input_router.call("set_file_dialog", true)
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = "导出世界检查点"
	_file_dialog.current_file = "末日余晖-检查点.json"
	_file_dialog.popup_centered_ratio(0.7)

func storage_state(live: bool = false) -> Dictionary:
	if live and is_instance_valid(runtime) and runtime.has_method("snapshot"):
		var current: Variant = runtime.call("snapshot")
		if current is Dictionary: snapshot["save"] = current.get("save", {})
	return snapshot.save.duplicate(true) if snapshot.get("save") is Dictionary else {}

func _render_storage_state() -> void:
	var state := storage_state()
	var status := str(state.get("status", ""))
	var text := str(state.get("reason", ""))
	_storage_status.text = ""
	if status == "generating": _storage_status.text = text if not text.is_empty() else "正在生成村落，旧档保留…"
	elif state.get("busy", false): _storage_status.text = text if not text.is_empty() else "正在处理文件请求…"
	elif status == "failed": _storage_status.text = ("新建村落未完成 · " if not _new_world_receipt.is_empty() else "文件操作未完成 · ") + text
	elif status == "unsaved": _storage_status.text = "尚未保存 · ⌘S 手动保存当前世界"
	elif status in ["saved", "restored"]: _storage_status.text = text
	_storage_status.tooltip_text = text
	_storage_status.modulate = Color("e1a088") if status == "failed" else UiTheme.SECONDARY
	_storage_status.visible = not _storage_status.text.is_empty()

func storage_reason(method: String, live: bool = false) -> String:
	if not is_instance_valid(runtime) or not runtime.has_method(method): return "真实文件服务尚未装配"
	var state := storage_state(live)
	if state.get("busy", false):
		var reason := str(state.get("reason", ""))
		return reason if not reason.is_empty() else "正在处理当前保存请求"
	if not state.get("ready", false):
		var reason := str(state.get("reason", ""))
		return reason if not reason.is_empty() else "文件服务尚未就绪，原档保持"
	return ""

func _next_file_request(operation: String) -> String:
	_serial += 1
	return "ui-file:%s:%s:%s:%s" % [get_instance_id(), _generation, operation, _serial]

func _file_receipt_ok(receipt: Variant, id: String) -> bool:
	return receipt is Dictionary and receipt.get("request_id") == id and receipt.get("ok", false) and receipt.get("code") == "OK"

func _file_reason(receipt: Variant, id: String) -> String:
	if not receipt is Dictionary or receipt.get("request_id") != id: return "未收到匹配本次请求的提交回执，原档保留"
	return str(receipt.reason) if receipt.get("reason") != null and not str(receipt.reason).is_empty() else "文件提交未确认，原档保留"

func _on_close_failed(receipt: Dictionary) -> void:
	_closing_wait = false
	_close_receipt = receipt.duplicate(true)
	if receipt.get("lifecycle_shell",false):return
	open_panel("close_failed")

func retry_close() -> void:
	if _closing_wait: return
	if is_instance_valid(runtime) and runtime.has_method("retry_close"):
		_closing_wait = true
		_close_receipt.clear()
		notify("正在重试保存并退出…")
		queue_refresh()
		runtime.call("retry_close")

func cancel_close() -> void:
	if is_instance_valid(runtime) and runtime.has_method("cancel_close"):
		runtime.call("cancel_close")
		_closing_wait = false
		_close_receipt.clear()
		close_panels()

func set_text_scale(value: float) -> void:
	text_scale = value
	theme = UiTheme.create(_font, text_scale)
	queue_refresh()
