extends "res://tests/ui/run_factory_native_drag.gd"
## Actual A25 manually saved paused harvest. No invented order, tools or stock.
const Direct = preload("res://scripts/input/direct_interaction.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
class Pointer extends Direct:
	var cursor := Vector2.ZERO
	func _refresh() -> void: _refresh_at(cursor)
	func _process(_delta: float) -> void: pass
class Ground extends Node3D:
	var world: RefCounted
	func pick(origin: Vector3, direction: Vector3) -> Dictionary:
		return Queries.raycast(world, origin, direction)

func order_elapsed(id: String) -> float:
	for row: Dictionary in runtime.snapshot().get("orders", []):
		if row.id == id: return float(row.elapsed)
	return -1.0

func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size()!=2: check("A actual25 paused manual save supplied",false);return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("untouched A actual25 paused manual save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	host=TestNative.new();root.add_child(host)
	var made:Dictionary=host._assemble(decoded.capture)
	check("original Native cold assembler accepts all real owners",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish(1)
	runtime=made.runtime;world=made.world
	router=Router.new();host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router);await idle()
	var intent:Dictionary=runtime.actor("player").get("intent",{})
	var tool_id:=str(intent.get("request",{}).get("payload",{}).get("tool_id",""))
	var target_id:=str(intent.get("request",{}).get("target_id",""))
	check("input is one real held-false harvest with retained order",intent.get("kind")=="harvest" and intent.get("held")==false and not tool_id.is_empty() and not str(intent.get("order_id","")).is_empty())
	router.assign_slot(0,{"kind":"tool","id":tool_id});router.select_slot(0)
	var camera:=Camera3D.new();host.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
	var feet:=Geometry.point(runtime.actor("player"));camera.position=feet+Vector3(24,29,31);camera.look_at(feet+Vector3(0,0.7,0))
	var ground:=Ground.new();host.add_child(ground);ground.world=world
	var pointer:=Pointer.new();host.add_child(pointer)
	pointer.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":made.services.buildings,"modules":made.services.modules,"terrain":ground,"ui":ui});pointer.set_process(false)
	await idle();pointer.cursor=camera.unproject_position(feet+Vector3(6,0,-6));pointer._refresh();ui.refresh();await idle()
	var before:=runtime.capture_checkpoint()
	check("actual pointer exposes A same paused tree contract",pointer._target.get("id")==target_id and pointer._target.get("active_work",false) and pointer._target.get("work_paused",false))
	check("paused HUD names work and continuation rather than unrelated digging",ui._scene_hint.text.contains("已暂停") and ui._scene_hint.text.contains("采伐") and ui._scene_hint.text.contains("按住左键继续") and ui._scene_hint.text.contains("Esc") and (not ui._mode_hint.visible or not ui._mode_hint.text.contains("挖掘")),ui._scene_hint.text+" / "+ui._mode_hint.text)
	check("actual target prompt consumes paused-work state",ui._target_text.text.contains("继续采伐") and ui._target_text.text.contains("Esc") and not ui._target_text.text.contains("暂不可操作"),ui._target_text.text)
	var busy:Dictionary=ui.execute("eat", "");await idle()
	check("real life BUSY keeps authority's exact reason",busy.get("code")=="BUSY" and ui._notice.text.contains(str(busy.reason)) and not ui._notice.text.contains("处理中") and ui._notice.tooltip_text.contains("BUSY"),ui._notice.text)
	check("bare BUSY never claims asynchronous processing",P.reason_text("BUSY").contains("行动") and not P.reason_text("BUSY").contains("处理中"),P.reason_text("BUSY"))
	check("specific save and assembly BUSY reasons remain untouched",P.feedback_text({"code":"BUSY","reason":"保存正在写入独立文件"})=="保存正在写入独立文件" and P.feedback_text({"code":"BUSY","reason":"世界正在组装，请等待就绪"})=="世界正在组装，请等待就绪")
	check("display and rejected alternative never alter paused authority",Data.json_equal(before,runtime.capture_checkpoint()))
	await motion(pointer.cursor);await button(true);pointer._refresh();ui.refresh();await idle()
	check("native mouse hold resumes original order and truthful active HUD",runtime.actor("player").intent.id==intent.id and runtime.actor("player").intent.order_id==intent.order_id and runtime.actor("player").intent.held and ui._scene_hint.text.contains("采伐中") and not ui._scene_hint.text.contains("已暂停"),ui._scene_hint.text)
	var elapsed:=order_elapsed(str(intent.order_id));runtime.tick(0.1);ui.refresh();await idle()
	check("HUD progress is real original order progress",order_elapsed(str(intent.order_id))>elapsed and ui._work_progress.visible and is_equal_approx(ui._work_progress.value,order_elapsed(str(intent.order_id))))
	await button(false);pointer._refresh();ui.refresh();await idle()
	elapsed=order_elapsed(str(intent.order_id))
	check("native release restores paused prompt without completing order",runtime.actor("player").intent.id==intent.id and not runtime.actor("player").intent.held and ui._scene_hint.text.contains("已暂停") and ui._target_text.text.contains("继续采伐"))
	for step in 3:runtime.tick(0.1)
	ui.refresh();await idle()
	check("paused progress never runs a UI work clock",is_equal_approx(elapsed,order_elapsed(str(intent.order_id))) and is_equal_approx(ui._work_progress.value,elapsed))
	var other_id:=""
	for tool:Dictionary in runtime.snapshot().tools:
		if tool.id!=tool_id and tool.holderId=="pack:player":other_id=str(tool.id);break
	check("negative tool case uses an existing real tool",not other_id.is_empty())
	if not other_id.is_empty():
		router.assign_slot(1,{"kind":"tool","id":other_id});router.select_slot(1);pointer._refresh();ui.refresh();await idle()
		check("different hand tells player to reselect original work tool",ui._scene_hint.text.contains("选回原作业工具") and not pointer._target.get("active_work",false),ui._scene_hint.text)
		router.select_slot(0);pointer._refresh();ui.refresh();await idle()
	root.size=Vector2i(1000,700);root.content_scale_size=root.size;ui.set_text_scale(1.5);await idle()
	check("large text paused HUD and target remain in viewport",root.get_visible_rect().encloses(ui._hud_backdrop.get_global_rect()) and root.get_visible_rect().encloses(ui._target.get_global_rect()))
	await key(KEY_ESCAPE);ui.refresh();await idle()
	check("real Escape cancels sole order and removes obsolete paused HUD",runtime.actor("player").get("intent")==null and not ui._scene_hint.text.contains("已暂停") and not ui._work_progress.visible)
	check("actual original paused QA file stays byte-identical",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int) -> void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"scope":"A actual25 manually saved QA harvest input; original Native owners/Direct/InputRouter, real Viewport hold/release/Escape and UI progress. Current source only, no OS/PCK/normal-economy/VA/FPS/G5 acceptance"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
