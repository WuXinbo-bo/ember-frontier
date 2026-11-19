extends SceneTree
## Narrow UI/router/preview connection. No formal app, OS input or visual acceptance.
const World = preload("res://scripts/world/world_state.gd")
const Rural = preload("res://scripts/world/rural_generator.gd")
const Initial = preload("res://scripts/runtime/initial_state.gd")
const Gameplay = preload("res://scripts/runtime/rural_gameplay.gd")
const Buildings = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
const Interaction = preload("res://scripts/input/direct_interaction.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Modes = preload("res://scripts/ui/ui_work_modes.gd")
const P = preload("res://scripts/ui/ui_projection.gd")

class RouterProbe extends "res://scripts/input/input_router.gd":
	# Only suppress user://controls.json writes; keep real mode/input behavior.
	func _persist_bindings() -> bool: return true

class RuntimeProbe extends "res://scripts/runtime/game_runtime.gd":
	# Trace the submitted boundary; execution remains the actual runtime transaction.
	var submitted: Dictionary = {}
	func command(request: Dictionary) -> Dictionary:
		submitted = request.duplicate(true)
		return super.command(request)

class InteractionProbe extends "res://scripts/input/direct_interaction.gd":
	# Pointer rays are supplied explicitly; inherited preview/actions/cancel stay real.
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass

var checks: Array = []
var shared_defects: Array = []
var completed_sections: Dictionary = {}
var failed := false
var output := ""
var world := World.new()
var runtime := RuntimeProbe.new()
var buildings := Buildings.new()
var production := Production.new()
var actions := Actions.new()
var terrain := Terrain.new()
var router: RouterProbe
var interaction: InteractionProbe
var ui: Control
var host: Node3D
var cabinet_id := "ui-mode:actual-cabinet"

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("UI work-mode timeout"); quit(2))
	call_deferred("run")

func check(name: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":condition,"detail":detail.duplicate(true) if detail is Dictionary or detail is Array else detail})
	if not condition: failed = true; push_error(name + " " + str(detail))

func by_key(node: Node, key: String) -> Control:
	if node is Control and str(node.get_meta("ui_focus_key", "")) == key: return node
	for child in node.get_children():
		var found := by_key(child, key)
		if found != null: return found
	return null

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): push_error("explicit isolated evidence path required"); quit(2); return
	output = OS.get_cmdline_user_args()[0]
	check("actual C world generated", world.load_snapshot(Rural.generate(713)).get("ok", false))
	var actor := {"id":"player","name":"UI模式隔离检查","x":23.0,"y":0.0,"z":44.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":40.0,"fatigue":0.0,"stamina":100.0,"skills":{"crafting":2},"pack":{"water":1,"timber":4,"scrap":2},"relationship":{"member":true,"consent":true},"intent":null}
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("actual A B C services configure", runtime.configure({"world":world,"services":{"buildings":buildings,"actions":actions,"production":production,"terrain":terrain},"definitions":definitions,"facts":{"time":0.0,"status":"playing","actors":[actor],"stocks":[],"actions":[],"quests":[]}}).get("ok", false))
	var piece: Dictionary = buildings.make_instance("cabinet", cabinet_id, {"x":21.0,"y":0.0,"z":44.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var prepared: Dictionary = buildings.prepare_edit([], [piece])
	check("B validates actual movable cabinet fixture", prepared.get("ok", false), prepared.get("reason"))
	if not prepared.get("ok", false): finish(); return
	var draft: Dictionary = world.prepare_changes(prepared.world_changes, world.get_revision())
	check("C commits actual cabinet", draft.get("ok", false) and world.commit_prepared(draft.capability).get("ok", false))
	var state: Dictionary = Production.empty_state()
	state.tools = [{"id":"ui-mode:hammer","kind":"hammer","holderId":"pack:player","durability":90.0},{"id":"ui-mode:shovel","kind":"shovel","holderId":"pack:player","durability":90.0}]
	draft = world.prepare_changes([buildings.extension_change(Production.KEY, state)], world.get_revision())
	check("C commits unique tool fixture", draft.get("ok", false) and world.commit_prepared(draft.capability).get("ok", false))
	var use_points: Array = buildings.use_points(cabinet_id)
	check("B publishes a real source use point for preview fixture", not use_points.is_empty())
	if use_points.is_empty(): finish(); return
	actor.merge(use_points[0], true)
	check("fixture uses actual B reach point without widening interaction range", runtime.configure({"world":world,"services":{"buildings":buildings,"actions":actions,"production":production,"terrain":terrain},"definitions":definitions,"facts":{"time":0.0,"status":"playing","actors":[actor],"stocks":[],"actions":[],"quests":[]}}).get("ok", false))
	host = Node3D.new(); root.add_child(host)
	router = RouterProbe.new(); host.add_child(router); router.configure(runtime)
	ui = Mount.mount(host, runtime, router)
	check("same runtime router mounts an actual UI control", ui != null and ui.has_method("open_panel"))
	if ui == null or not ui.has_method("open_panel"): host.queue_free(); await process_frame; finish(); return
	var camera := Camera3D.new(); host.add_child(camera)
	var surface := Node3D.new(); host.add_child(surface)
	interaction = InteractionProbe.new(); host.add_child(interaction)
	interaction.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":buildings,"terrain":surface,"ui":ui})
	await process_frame
	await mode_cases()
	await brush_cases()
	await preview_cases()
	await hint_cases()
	await task_cases()
	check("all targeted sections reached their final assertion", ["modes","brush","preview","hints","tasks"].all(func(id: String): return completed_sections.get(id, false)), completed_sections)
	host.queue_free(); await process_frame
	finish()

func mode_cases() -> void:
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_panel("build")
	var ids: Array = router.state().modes
	check("UI exposes all actual router work modes", ids.all(func(id: String): return by_key(ui, "mode:" + id) != null), ids)
	for id in ["repair", "move", "demolish", "destroy", "terrain_dig", "terrain_fill", "terrain_level", "tool"]:
		ui.open_panel("build")
		var button: Button = by_key(ui, "mode:" + str(id))
		if button != null: button.pressed.emit()
		check("mode button reaches actual router: " + str(id), router.state().mode == id and ui.pages.is_empty())
	check("mode selection never modifies world materials clock or work orders", before == runtime.capture_checkpoint())
	ui.open_panel("inventory")
	var receipt: Dictionary = ui.select_work_mode("repair", "missing:actual-structure")
	check("missing structure receipt preserves panel and facts", not receipt.get("ok", false) and receipt.get("code") == "MISSING_TARGET" and not ui.pages.is_empty() and before == runtime.capture_checkpoint(), ui._notice.text)
	check("router failure reason is visible", ui._notice.text == receipt.get("reason"))
	ui.select_work_mode("repair", cabinet_id)
	check("explicit existing structure keeps its real stable id", router.state().structure_target_id == cabinet_id)
	await process_frame
	completed_sections.modes = true

func brush_cases() -> void:
	var before: Dictionary = runtime.capture_checkpoint()
	ui.open_panel("terrain")
	var operation: OptionButton = by_key(ui, "terrain:operation")
	var material: OptionButton = by_key(ui, "terrain:material")
	var cells: OptionButton = by_key(ui, "terrain:cells")
	var height: SpinBox = by_key(ui, "terrain:height")
	check("native brush controls reflect real brush", operation != null and material != null and cells != null and height != null and material.get_selected_id() == router.state().terrain.material and height.value == router.state().terrain.height)
	material.select(material.get_item_index(3)); cells.select(cells.get_item_index(2)); height.value = 1.5
	for index in operation.item_count:
		if operation.get_item_metadata(index) == "level": operation.select(index)
	var brush_before: Dictionary = router.state().terrain
	ui.cancel_ui()
	check("cancelled control draft never changes real brush or facts", brush_before == router.state().terrain and before == runtime.capture_checkpoint())
	ui.open_panel("terrain")
	var receipt: Dictionary = ui.apply_terrain_brush("level", 3, 0.25, 2)
	check("unaligned brush rejected by actual A router and stays editable", not receipt.get("ok", false) and receipt.get("code") == "INVALID_HEIGHT" and not ui.pages.is_empty() and brush_before == router.state().terrain, ui._notice.text)
	receipt = ui.apply_terrain_brush("fill", 999, 0, 1)
	check("unknown material rejected without replacing current brush", not receipt.get("ok", false) and brush_before == router.state().terrain, ui._notice.text)
	ui.open_panel("terrain")
	operation = by_key(ui, "terrain:operation"); material = by_key(ui, "terrain:material"); cells = by_key(ui, "terrain:cells"); height = by_key(ui, "terrain:height")
	material.select(material.get_item_index(3)); cells.select(cells.get_item_index(2)); height.value = 1.5
	for index in operation.item_count:
		if operation.get_item_metadata(index) == "level": operation.select(index)
	var apply_button: Button = by_key(ui, "terrain:apply")
	apply_button.pressed.emit()
	check("apply passes native control values to actual brush contract", ui.pages.is_empty() and router.state().mode == "terrain_level" and router.state().terrain == {"operation":"level","material":3,"height":1.5,"brush_cells":2}, router.state().terrain)
	check("brush apply does not excavate place consume or advance time", before == runtime.capture_checkpoint())
	ui.refresh()
	check("HUD reads actual brush settings", ui._mode_hint.text.contains("石") and ui._mode_hint.text.contains("2×2") and ui._mode_hint.text.contains("1.5"), ui._mode_hint.text)
	for scale_factor in [1.0, 1.5]:
		ui.set_text_scale(scale_factor)
		ui.open_panel("terrain")
		await process_frame
		check("terrain controls fit native dialog at text scale " + str(scale_factor), by_key(ui,"terrain:height").get_global_rect().end.x <= ui._dialog.get_global_rect().end.x and ui._body.get_combined_minimum_size().x <= ui._scroll.size.x + 1)
		ui.close_panels()
	ui.set_text_scale(1.0)
	await process_frame
	completed_sections.brush = true

func preview_cases() -> void:
	# Keep real hotbar references; suppress only preference-file writes in RouterProbe.
	router.assign_slot(2, {"kind":"tool","tool_id":"ui-mode:hammer"}); router.select_slot(2)
	ui.select_work_mode("repair")
	var repair_before: Dictionary = runtime.capture_checkpoint()
	interaction._target = interaction._describe(world.entity(cabinet_id))
	runtime.set_target(interaction._target); ui.refresh()
	var repair_reason: Variant = interaction._target.get("reason")
	interaction._primary(true)
	check("actual building repair refusal reaches HUD without E label or mutation", not interaction._target.get("enabled", true) and repair_reason is String and ui._notice.text == "操作未完成 · " + P.feedback_text(interaction._target) and ui._notice.tooltip_text.contains(repair_reason) and ui._target_text.text.contains("按住左键维修") and repair_before == runtime.capture_checkpoint(), ui._notice.text)
	ui.select_work_mode("move")
	var before: Dictionary = runtime.capture_checkpoint()
	interaction._target = interaction._describe(world.entity(cabinet_id))
	interaction._primary(true)
	check("left target selection reaches same A move route", router.state().structure_target_id == cabinet_id and interaction._moving_target == cabinet_id)
	interaction._update_preview({}, Vector3(21, 10, 46), Vector3.DOWN)
	ui.refresh()
	var target: Dictionary = runtime.snapshot().target
	check("UI consumes actual A preview using original structure id", target.get("kind") == "placement" and target.get("id") == cabinet_id and ui._target_text.text.contains("右键确定"), target)
	check("valid nearby preview reads actual green preflight", target.get("enabled", false) and target.get("reason") == null, target)
	check("preview never commits a move or consumes materials", before == runtime.capture_checkpoint())
	router.rotate_requested.emit()
	interaction._update_preview({}, Vector3(21, 10, 46), Vector3.DOWN)
	check("rotation uses existing A preview without UI geometry", interaction._preview.get("destination", {}).get("quarterTurn") == 1)
	# Explicitly beyond B's 2.25m nearby-move limit; do not assume grid snapping
	# a cabinet onto the actor necessarily overlaps the actual cabinet bounds.
	interaction._update_preview({}, Vector3(25, 10, 46), Vector3.DOWN)
	ui.refresh(); target = runtime.snapshot().target
	check("invalid destination displays actual preflight refusal", target.get("enabled") == false and target.get("reason") is String and ui._target_text.text.contains(target.reason), target)
	interaction._secondary()
	check("failed actual placement receipt keeps original facts", before == runtime.capture_checkpoint() and not ui._notice.text.is_empty(), ui._notice.text)
	router.cancel(); ui.refresh()
	check("cancel clears actual preview and restores tool mode", router.state().mode == "tool" and interaction._moving_target.is_empty() and interaction._preview.is_empty() and before == runtime.capture_checkpoint())
	# UI must display the precise C hit identity; it does not construct a cell target.
	var hit: Dictionary = Queries.pick(world, Vector3(24, 8, 45), Vector3(24, -3, 45))
	check("C supplies actual stable cell identity", str(hit.get("target_id", "")).begins_with("terrain:") and hit.has("world_revision"), hit)
	ui.apply_terrain_brush("fill", 2, 0, 1)
	router.assign_slot(3, {"kind":"tool","tool_id":"ui-mode:shovel"}); router.select_slot(3)
	var payload: Dictionary = Interaction.terrain_payload(hit, router.state().terrain, "fill", float(world.config().cellSize))
	payload.merge({"tool_id":"ui-mode:shovel","held":true,"requires_hold":false})
	var ready: Dictionary = runtime.availability({"kind":"terrain","actor_id":"player","target_id":hit.get("target_id", ""),"payload":payload})
	runtime.set_target({"id":hit.get("target_id", ""),"kind":"terrain","primary":"terrain","name":"填土","enabled":ready.get("ok", false),"code":ready.get("code"),"reason":ready.get("reason"),"edit":payload.edit,"cell":hit.get("cell"),"world_revision":hit.get("world_revision")})
	ui.refresh()
	check("terrain identity revision edit and exact refusal survive UI refresh", ui.snapshot.target.id == hit.target_id and ui.snapshot.target.world_revision == hit.world_revision and ui.snapshot.target.edit.operation=="fill" and not ui.snapshot.target.enabled and ui._target_text.text.contains(P.feedback_text(ready)) and not ui._target_text.text.contains("按住左键"), ui._target_text.text)
	interaction._target = runtime.snapshot().target
	interaction._terrain_payload = payload
	interaction._secondary()
	check("terrain refusal comes from actual C service without mutation", not ready.get("ok", false) and before == runtime.capture_checkpoint() and ui._notice.text == "操作未完成 · " + P.feedback_text(ready) and ui._notice.tooltip_text.contains(str(ready.get("code"))), {"availability":ready,"notice":ui._notice.text})
	await process_frame
	completed_sections.preview = true

func hint_cases() -> void:
	var hand: Dictionary = router.state()
	hand.mode = "repair"
	var text := Modes.target_hint({"kind":"structure","action":"按住左键维修"}, hand)
	check("repair is not mislabeled as E action", text.begins_with("按住左键维修") and not text.begins_with("E"), text)
	hand.mode = "terrain_level"
	hand.bindings.interact = {"keycode":KEY_F,"label":"F"}
	hand.bindings.rotate = {"keycode":KEY_G,"label":"G"}
	hand.bindings.cancel = {"keycode":KEY_Q,"label":"Q"}
	text = Modes.target_hint({"kind":"terrain"}, hand)
	check("level sample key follows actual binding label", text.contains("F取样基准") and not text.contains("E取样"), text)
	text = Modes.target_hint({"kind":"placement","hint":"右键确定 · R旋转 · Esc取消"}, hand)
	check("preview hints follow rebound rotate and cancel", text.contains("G旋转") and text.contains("Q取消") and not text.contains("R旋转"), text)
	check("HUD contrast fix uses text shadows", ui._mode_hint.get_theme_color("font_shadow_color").a > 0.9)
	# Known shared boundary, measured without modifying A: consumable right-click priority.
	ui.select_work_mode("terrain_fill"); router.assign_slot(0, {"kind":"item","item_id":"water"}); router.select_slot(0)
	var before: Dictionary = runtime.capture_checkpoint()
	interaction._secondary()
	var intent: Variant = runtime.actor("player").get("intent")
	if intent is Dictionary and intent.get("kind") == "drink":
		shared_defects.append({"id":"UI-A-MODE-01","owner":"A scripts/input/direct_interaction.gd::_secondary","observed":"terrain_fill with water hotbar starts drink before terrain/placement mode dispatch","expected":"active scene-work mode must dispatch or refuse without consuming a different held item","ui_scope":"UI correctly selected actual terrain_fill; do not clear user's hotbar or rewrite shared runtime as workaround"})
		ui.execute("cancel", "")
	else: check("active work mode does not route to a different consumable", before == runtime.capture_checkpoint())
	await process_frame
	completed_sections.hints = true

func action_button(kind: String, target: String = "", payload: Dictionary = {}) -> Button:
	return by_key(ui, kind + ":" + target + ":" + str(payload.hash()))

func texts(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += texts(child)
	return result

func gameplay_fixture(value: Dictionary) -> bool:
	var draft: Dictionary = world.prepare_changes([buildings.extension_change(Gameplay.KEY, value)], world.get_revision())
	return draft.get("ok", false) and world.commit_prepared(draft.capability).get("ok", false)

func task_cases() -> void:
	var gameplay := Gameplay.new()
	var facts: Dictionary = runtime.facts()
	var location := {"x":24.0,"y":0.0,"z":46.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var worker: Dictionary = Initial.actor("ui-worker", "隔离工作居民", location, location, {})
	worker.relationship = {"member":true,"met":true,"consent":true,"home_arrived":true}
	facts.actors.append(worker)
	facts.scenario = "rural-home-r33"
	facts.quests = Initial.facts({"spawn_points":{"player":location,"village-resident":location,"repair-resident":location},"initial_stocks":[]}).quests
	facts.quests[0].status = "进行中"
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("A actual work and gameplay projections configure", runtime.configure({"world":world,"services":{"buildings":buildings,"actions":actions,"production":production,"terrain":terrain,"gameplay":gameplay},"definitions":definitions,"facts":facts}).get("ok", false))
	ui.refresh()
	check("HUD recognizes actual Chinese active quest status", ui._scene_hint.text.contains("回到旧宅"), ui._scene_hint.text)
	ui.open_panel("npc", "ui-worker")
	var targets: Array = runtime.snapshot().work_targets
	var gather: Dictionary = {}
	for candidate: Dictionary in targets:
		if candidate.job == "gather": gather = candidate; break
	check("A projects real stable work candidate with payload", not gather.is_empty() and gather.get("work_payload", {}).get("action_kind") == "harvest", gather)
	if not gather.is_empty():
		var payload := {"job":str(gather.job),"work_target_id":str(gather.id),"work_payload":gather.work_payload.duplicate(true)}
		var job_button: Button = action_button("job", "ui-worker", payload)
		check("native work button uses projected payload", job_button != null and not job_button.disabled)
		if job_button != null: job_button.pressed.emit()
		check("UI submits actual work target and payload unchanged", runtime.submitted.get("payload") == payload, runtime.submitted)
		check("A keeps actual target and complete worker payload", runtime.actor("ui-worker").work_target_id == gather.actual_target_id and runtime.actor("ui-worker").work_payload == gather.work_payload and ui.pages.is_empty())
	ui.open_panel("quests")
	var start: Button = action_button("explore_start")
	check("actual gameplay start choice is rendered and preflighted", start != null and not start.disabled)
	var pack: Dictionary = runtime.actor("player").pack
	var time := runtime.clock()
	if start != null: start.pressed.emit()
	check("start choice reaches actual gameplay without invented loot or time", world.extension(Gameplay.KEY).exploration.status == "running" and runtime.actor("player").pack == pack and runtime.clock() == time and ui.pages.is_empty())
	var state: Dictionary = world.extension(Gameplay.KEY)
	state.exploration.candidates = ["shove", "guard"]
	state.exploration.stages = 1
	check("isolated candidate fixture commits via actual C capability", gameplay_fixture(state))
	ui.open_panel("quests")
	check("actual candidates and stage facts reach native page", action_button("explore_choose", "", {"choice_id":"shove"}) != null and action_button("explore_choose", "", {"choice_id":"guard"}) != null and texts(ui._body).contains("本次已完成阶段 1"))
	var before: Dictionary = runtime.capture_checkpoint()
	var rejected: Dictionary = ui.execute("explore_choose", "", {"choice_id":"missing:choice"})
	check("invalid candidate uses A refusal without changing facts", not rejected.get("ok", false) and rejected.get("code") == "INVALID_CHOICE" and before == runtime.capture_checkpoint() and ui._notice.text == rejected.get("reason"))
	var choose: Button = action_button("explore_choose", "", {"choice_id":"guard"})
	if choose != null: choose.pressed.emit()
	check("real choice consumes only its projected candidate set", world.extension(Gameplay.KEY).exploration.upgrades == ["guard"] and world.extension(Gameplay.KEY).exploration.candidates.is_empty() and runtime.actor("player").pack == pack)
	ui.open_panel("quests")
	check("selected technique displays real count without inventing labels", texts(ui._body).contains("本次临时技巧：已选择 1 项") and action_button("explore_choose", "", {"choice_id":"guard"}) == null)
	before = runtime.capture_checkpoint()
	rejected = ui.execute("explore_choose", "", {"choice_id":"guard"})
	check("stale repeated choice is rejected without a second effect", not rejected.get("ok", false) and before == runtime.capture_checkpoint())
	state = world.extension(Gameplay.KEY)
	state.defense.status = "warning"; state.defense.arrival_at = runtime.clock() + 60
	check("isolated warning fixture commits via C", gameplay_fixture(state))
	ui.open_panel("quests")
	var defense_button: Button = action_button("defend")
	check("warning uses actual remaining time and defense choice", ui.snapshot.defense.remaining == 60.0 and texts(ui._body).contains("来袭前剩余 60.0 秒") and defense_button != null and not defense_button.disabled, {"remaining":ui.snapshot.defense.remaining,"button_exists":defense_button != null,"disabled":defense_button.disabled if defense_button != null else null})
	ui.close_panels()
	await process_frame
	completed_sections.tasks = true

func finish() -> void:
	var result := {"scope":"targeted actual A/B/C/UI mode, preview, work payload and gameplay choice connection; explicit pointer rays and declared isolated candidate fixtures, no physical mouse or formal application acceptance", "ok":not failed, "checks":checks, "shared_defects":shared_defects, "route_acceptance":false}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t", true, true)); file.close()
	print(JSON.stringify(result)); quit(1 if failed else 0)
