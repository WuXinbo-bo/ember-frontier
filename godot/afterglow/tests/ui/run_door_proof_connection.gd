extends SceneTree
## Real A/B/C authority and target transport into the production UI. The legal
## stance and stale pointer are arranged fixtures, not OS/ray/route acceptance.
const Client = preload("res://scripts/runtime/native_client.gd")
const Assembly = preload("res://scripts/runtime/settlement_assembly.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Direct = preload("res://scripts/input/direct_interaction.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")

class RouterProbe extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true

class SelectedPointer extends Direct:
	# No ray or scene is mounted. Keep the selected DTO deliberately stale for
	# the command test; inherited _describe and _interact remain production.
	func _refresh() -> void: pass

var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): finish(2))
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	print(("PASS " if ok else "FAIL ") + label)

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713, Building.generation_profiles()))
	check("actual finite rural capture prepares", prepared.get("ok", false), prepared.get("reason"))
	if not prepared.get("ok", false): finish(1); return
	var client := Client.new()
	var built: Dictionary = client._assemble(prepared.capture)
	check("real A assembler configures the B C authority", built.get("ok", false), built.get("reason"))
	if not built.get("ok", false): client.free(); finish(1); return
	var runtime: RefCounted = built.runtime
	var buildings: RefCounted = built.services.buildings
	var door: Dictionary = {}
	var preview: Dictionary = {}
	for piece: Dictionary in buildings.structures().instances:
		if not piece.has("door") or piece.door.get("locked", false): continue
		for at: Dictionary in buildings.current_space().use_points(piece):
			var actor: Dictionary = runtime.actor("player")
			var stance := actor.duplicate(true)
			stance.merge(at, true); stance.stamina = 100.0; stance.intent = null
			var moved: Dictionary = runtime._commit({"fact_changes":[{"collection":"actors","id":"player","before":actor,"after":stance}]})
			if not moved.get("ok", false): continue
			preview = buildings.door_preview({"kind":"door","actor_id":"player","target_id":piece.id,"payload":{"direct":true}})
			if preview.get("ok", false): door = piece; break
		if not door.is_empty(): break
	check("real door preview accepts an arranged legal use point", not door.is_empty(), preview)
	if door.is_empty(): client.free(); finish(1); return
	var host := Node.new(); root.add_child(host)
	var router := RouterProbe.new(); host.add_child(router)
	router.controls_path = "res://tests/ui/no-door-proof-preferences.json"
	router.configure(runtime)
	var ui: Control = Mount.mount(host, runtime, router)
	var pointer := SelectedPointer.new()
	pointer.runtime = runtime; pointer.world = built.world
	pointer.buildings = buildings; pointer.router = router; pointer.ui = ui
	router.interact_requested.connect(pointer._interact)
	await process_frame
	var before: Dictionary = runtime.capture_checkpoint()
	var target: Dictionary = pointer._describe(built.world.entity(str(door.id)))
	check("A transports actual structure-door pending proof", target.get("kind") == "structure" and target.get("primary") == "door" and target.get("proof_state") == "pending" and target.get("enabled", false), target)
	check("A transports exact B versions and operation", target.get("target_version") == preview.get("target_version") and target.get("world_revision") == preview.get("world_revision") and target.get("operation") == preview.get("operation"), target)
	runtime.set_target(target); ui.refresh(); await process_frame
	check("same-runtime UI displays exactly one attempt prefix", ui._target.visible and ui._target_text.text.count("尝试") == 1 and ui._target_text.text.contains("E尝试") and ui._target_text.text.contains("提交时验证通路与安全"), ui._target_text.text)
	check("pending actual target uses neutral presentation without a refusal", ui._target_text.get_theme_color("font_color").is_equal_approx(Color("b8b7ad")) and ui._target_text.tooltip_text.is_empty() and not ui._target_text.text.contains("目标暂不可操作"))
	check("hover and UI do not change world facts or proof", runtime.capture_checkpoint() == before and runtime.snapshot().target == target)
	var actor: Dictionary = runtime.actor("player")
	var exhausted := actor.duplicate(true); exhausted.stamina = 0.0
	var changed: Dictionary = runtime._commit({"fact_changes":[{"collection":"actors","id":"player","before":actor,"after":exhausted}]})
	check("real authority changes the current continuous condition", changed.get("ok", false))
	var facts_before: Dictionary = runtime.facts()
	var world_before: Dictionary = built.world.snapshot()
	pointer._target = target.duplicate(true)
	var sequence_before: int = router._sequence
	router.interact_requested.emit()
	check("attempt routes through one original E command", router._sequence == sequence_before + 1)
	check("actual command refusal reaches production UI with exact diagnostic", ui._notice.text.contains("体力不足") and ui._notice.tooltip_text.contains("EXHAUSTED"), {"notice":ui._notice.text,"diagnostic":ui._notice.tooltip_text})
	check("stale pending cannot mutate facts geometry resources or clock", runtime.facts() == facts_before and built.world.snapshot() == world_before)
	var rejected: Dictionary = pointer._describe(built.world.entity(str(door.id)))
	runtime.set_target(rejected); ui.refresh()
	check("updated actual rejected target retains exact code and reason", rejected.get("proof_state") == "rejected" and rejected.get("code") == "EXHAUSTED" and ui._target_text.text.contains(str(rejected.get("reason"))) and ui._target_text.tooltip_text.contains("code: EXHAUSTED") and not ui._target_text.has_theme_color_override("font_color"), ui._target_text.text)
	pointer.free(); host.queue_free(); client.free(); await process_frame
	finish(0 if checks.all(func(row: Dictionary): return row.ok) else 1)

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"fixture":"real A assembler/runtime/router/direct target + B door_preview + C generated world + production UI; explicitly arranged legal stance and frozen pointer; no 3D stage, ray picking or native application","production_door_preview_integrated":true,"formal_application_launched":false,"physical_os_input":false,"route_acceptance":false,"visual_acceptance":false}, "  ")); file.close()
	quit(code)
