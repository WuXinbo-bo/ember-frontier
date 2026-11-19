extends SceneTree
## Actual A/C rejections through UI labels; controlled pointer and reason edge cases.
## No formal 3D scene, user saves, preferences, or physical OS input.
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")
class Router extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass
var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): finish(2))
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: push_error(label + " " + str(detail))

func run() -> void:
	if OS.get_cmdline_user_args().is_empty(): quit(2); return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var world := World.new()
	check("actual rural world loads", world.load_snapshot(Generator.generate(713)).get("ok", false))
	var runtime := Runtime.new()
	var actor := {"id":"player","name":"UI isolated rejection fixture","x":27.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"stamina":100.0,"pack":{},"skills":{},"relationship":{"consent":true},"intent":null}
	var facts := {"time":0.0,"status":"playing","actors":[actor],"stocks":[],"actions":[],"quests":[]}
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	var configured := runtime.configure({"world":world,"services":{"buildings":Building.new(),"production":Production.new(),"terrain":Terrain.new()},"definitions":definitions,"facts":facts})
	check("actual runtime and B C services configure", configured.get("ok", false), configured)
	if not configured.get("ok", false): finish(1); return
	var host := Node.new(); root.add_child(host)
	var router := Router.new(); host.add_child(router); router.configure(runtime)
	var ui := Mount.mount(host, runtime, router)
	await process_frame; await process_frame
	var pointer := Pointer.new(); host.add_child(pointer)
	pointer.ui = ui; pointer.router = router
	var before := runtime.capture_checkpoint()
	var near_payload := {"edit":{"operation":"dig","material":2,"cells":[{"x":55,"y":-1,"z":86}]},"tool_id":"","held":true,"requires_hold":true}
	var far_payload := near_payload.duplicate(true)
	far_payload.edit.cells = [{"x":20,"y":-1,"z":86}]
	var missing: Dictionary = runtime.availability({"kind":"terrain","actor_id":"player","target_id":"terrain:55:-1:86","payload":near_payload})
	var unreachable: Dictionary = runtime.availability({"kind":"terrain","actor_id":"player","target_id":"terrain:20:-1:86","payload":far_payload})
	check("actual near gravel rejects missing shovel without changing rules", not missing.get("ok", false) and missing.get("code") == "MISSING_TOOL" and missing.get("reason") == "MISSING_TOOL", missing)
	check("actual far terrain rejects distance without changing rules", not unreachable.get("ok", false) and unreachable.get("code") == "UNREACHABLE" and not str(unreachable.get("reason", "")).is_empty(), unreachable)
	for receipt: Dictionary in [missing, unreachable]:
		var original := receipt.duplicate(true)
		var target := {"id":"terrain:ui-feedback","kind":"terrain","primary":"terrain","name":"挖掘","enabled":false,"reason":receipt.reason,"edit":{"operation":"dig"}}
		runtime.set_target(target); ui.refresh()
		var code: String = receipt.code
		var raw_reason := str(receipt.reason)
		var expected := "铲／镐" if code == "MISSING_TOOL" else ("同侧可达处" if raw_reason == code else raw_reason)
		check("target shows actionable Chinese: " + code, ui._target_text.text.contains(expected) and not ui._target_text.text.contains(code), ui._target_text.text)
		check("target tooltip retains raw reason: " + code, ui._target_text.tooltip_text.contains(raw_reason) and runtime.snapshot().target.reason == receipt.reason)
		if code == "UNREACHABLE": check("passive distance precheck stays hidden", not ui._target.visible)
		pointer._feedback(receipt)
		check("actual adapter receipt displays Chinese and code diagnostic: " + code, ui._notice.text.contains(expected) and ui._notice.tooltip_text.contains("code: " + code) and ui._notice.tooltip_text.contains("reason: " + raw_reason), {"text":ui._notice.text,"diagnostic":ui._notice.tooltip_text})
		pointer._target = target
		pointer._interact() # Controlled pointer; real disabled E path calls notify directly.
		check("disabled E direct notify also explains rejection: " + code, ui._notice.text.contains(expected) and ui._notice.tooltip_text == raw_reason and ui.pages.is_empty())
		check("display never mutates authority receipt: " + code, Data.json_equal(original, receipt))
	var rejected: Dictionary = ui.execute("terrain", "terrain:55:-1:86", near_payload)
	check("UI execute returns actual rejection unchanged with retained diagnostic", rejected == missing and ui._notice.text.contains("工具") and ui._notice.tooltip_text.contains("code: MISSING_TOOL"), rejected)
	var specific := {"ok":false,"code":"UNREACHABLE","reason":"门关闭或通路被阻挡"}
	ui.report_action(specific)
	check("specific authority reason wins over generic advice", ui._notice.text == "操作未完成 · " + specific.reason and ui._notice.tooltip_text.contains("code: UNREACHABLE") and ui._notice.tooltip_text.contains(specific.reason))
	ui.report_action({"ok":false,"code":"UNREACHABLE","reason":null})
	check("null reason uses confirmed code without displaying null", ui._notice.text.contains("移近") and ui._notice.tooltip_text.contains("code: UNREACHABLE"))
	check("leveling advice uses explicit target operation", P.feedback_text(missing,{"kind":"terrain","edit":{"operation":"level"}}) == "请在快捷栏选中可用的铲，再整平地面")
	check("unknown context does not invent terrain tool requirement", P.feedback_text(missing).contains("适用工具") and not P.feedback_text(missing).contains("铲"))
	check("known suffix translates and unknown bare code gets safe player copy", P.reason_text("材料不足或已预留：timber") == "材料不足或已预留：木料" and P.reason_text("SOME_FUTURE_CODE").contains("条件尚未满足") and P.feedback_diagnostic({"code":"SOME_FUTURE_CODE"}).contains("SOME_FUTURE_CODE"))
	check("empty reason uses exact confirmed code and no receipt falls back safely", P.feedback_text({"reason":"","code":"MISSING_TOOL"}).contains("适用工具") and P.feedback_text({}, {}, "当前不可用") == "当前不可用")
	ui.notify("已受理")
	ui.report_action({"ok":true,"code":"OK","reason":null})
	check("success clears old diagnostics and is not declared complete", ui._notice.text == "已受理" and ui._notice.tooltip_text.is_empty())
	runtime.set_target({"id":"now-available","kind":"terrain","name":"挖掘","enabled":true})
	ui.refresh()
	check("enabled target clears obsolete failure diagnostic", ui._target_text.tooltip_text.is_empty())
	check("all feedback keeps actual inventory clock world and intents unchanged", Data.json_equal(before, runtime.capture_checkpoint()))
	host.queue_free(); await process_frame
	finish(0 if checks.all(func(row: Dictionary) -> bool: return row.ok) else 1)

func finish(code: int) -> void:
	if not output.is_empty():
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code == 0,"checks":checks,"failed":checks.filter(func(row: Dictionary) -> bool: return not row.ok).size(),"formal_application_launched":false,"physical_os_pointer":false,"route_acceptance":false,"visual_acceptance":false,"fixture":"Actual A runtime and B/C services, rural-1 world, explicit isolated actor; controlled adapter calls; no formal 3D or OS inputs"},"\t",true,true))
		file.close()
	print("UI readable failure checks " + str(checks.size()) + " exit " + str(code))
	quit(code)
