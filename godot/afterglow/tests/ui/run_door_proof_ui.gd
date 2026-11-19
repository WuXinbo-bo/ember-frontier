extends SceneTree
## Published target DTO + production UI projection/Controls only. No door
## preview implementation, authority safety, OS input or formal visibility claim.
const Modes = preload("res://scripts/ui/ui_work_modes.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const P = preload("res://scripts/ui/ui_projection.gd")

class Authority extends RefCounted:
	signal changed(changes: Dictionary)
	var target: Dictionary = {}
	var previews := 0
	var commands := 0
	func snapshot() -> Dictionary: return {"revision":1,"command_revision":1,"player":{"id":"player","hp":100},"target":target.duplicate(true)}
	func availability(_request: Dictionary) -> Dictionary:
		previews += 1
		return {"ok":false,"code":"FORBIDDEN","reason":"受控当前权限拒绝"}
	func command(_request: Dictionary) -> Dictionary:
		commands += 1
		return {"ok":false,"code":"FORBIDDEN","reason":"受控当前权限拒绝"}

var checks: Array = []
var output := ""

func _initialize() -> void:
	create_timer(10).timeout.connect(func(): finish(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	print(("PASS " if ok else "FAIL ")+name)

func flush() -> void:
	await process_frame
	await process_frame

func run() -> void:
	if OS.get_cmdline_user_args().is_empty():quit(2);return
	output=OS.get_cmdline_user_args()[0]
	var hand := {"mode":"tool","bindings":{}}
	for action: String in ["开门","关门"]:
		var target := {"id":"door:controlled","kind":"door","name":"旧宅门","action":action,"enabled":true,"proof_state":"pending"}
		var original := target.duplicate(true)
		var text := Modes.target_hint(target,hand)
		check("pending door announces an attempt "+action,text.begins_with("E尝试"+action) and text.contains("提交时验证通路与安全"),text)
		check("pure proof projection preserves authority DTO "+action,target==original)
		var prefixed := target.duplicate(true)
		prefixed.action = "尝试" + action
		check("published A attempt action is displayed exactly once "+action,Modes.target_hint(prefixed,hand)==text,Modes.target_hint(prefixed,hand))
	var remapped := {"bindings":{"interact":{"keycode":KEY_F,"label":"F","physical":true}},"mode":"tool"}
	var target := {"id":"door:controlled","kind":"door","name":"旧宅门","action":"开门","enabled":true,"proof_state":"pending","hint":"E 已确认可操作"}
	var text := Modes.target_hint(target,remapped)
	check("pending proof overrides optimistic hint and uses real remapped key",text.begins_with("F尝试开门") and not text.contains("已确认") and not text.begins_with("E"),text)
	var structure_target := {"id":"door:structure","kind":"structure","primary":"door","name":"结构门","action":"关门","enabled":true,"proof_state":"pending"}
	check("actual structure entity with door primary also uses pending wording",Modes.target_hint(structure_target,hand).begins_with("E尝试关门"),Modes.target_hint(structure_target,hand))
	check("existing left-button structure work is not relabelled as E door use",Modes.target_hint(structure_target,{"mode":"repair"}).begins_with("按住左键维修"))
	for proof: String in ["confirmed",""]:
		var original := target.duplicate(true)
		if proof.is_empty():original.erase("proof_state")
		else:original.proof_state=proof
		check("confirmed and field-absent hints keep old behavior "+proof,Modes.target_hint(original,hand)=="E 已确认可操作")
	var authority:=Authority.new()
	var host:=Node.new();root.add_child(host)
	var ui:Control=Mount.mount(host,authority,null)
	await flush()
	authority.target=structure_target.duplicate(true);ui.refresh()
	check("structure door Control consumes the same proof field",ui._target_text.text.contains("E尝试关门") and ui._target_text.has_theme_color_override("font_color"),ui._target_text.text)
	# Real scene text/color paths. Changing projections never submits a door.
	for action: String in ["开门","关门"]:
		authority.target={"id":"door:controlled","kind":"door","name":"旧宅门","action":action,"enabled":true,"proof_state":"pending","code":"OK","reason":null}
		ui.refresh();await flush()
		check("pending Control is neutral without confirmation colors "+action,ui._target.visible and ui._target_text.text.contains("E尝试"+action) and ui._target_text.has_theme_color_override("font_color") and ui._target_text.get_theme_color("font_color").is_equal_approx(Color("b8b7ad")),ui._target_text.text)
		check("pending preview does not present a refusal or confirm completion "+action,not ui._target_text.text.contains("目标暂不可操作") and not ui._target_text.text.contains("已确认") and ui._target_text.tooltip_text.is_empty())
		var original := authority.target.duplicate(true)
		await flush();ui.refresh()
		check("waiting never promotes proof or submits authority work "+action,authority.target==original and authority.previews==0 and authority.commands==0)
	for proof: String in ["confirmed",""]:
		if proof.is_empty():authority.target.erase("proof_state")
		else:authority.target.proof_state=proof
		ui.refresh()
		check("Control transition restores existing label styling "+proof,not ui._target_text.has_theme_color_override("font_color") and ui._target_text.text=="旧宅门\nE 关门" and ui._target_text.tooltip_text.is_empty(),ui._target_text.text)
	for enabled: bool in [false,true]:
		authority.target={"id":"door:controlled","kind":"door","name":"旧宅门","action":"关门","enabled":enabled,"proof_state":"rejected","code":"BODY_BLOCKED","reason":"门扇将挡住同伴的通路"}
		ui.refresh()
		check("rejected proof preserves exact refusal even with stale enabled "+str(enabled),ui._target_text.text.contains("门扇将挡住同伴的通路") and ui._target_text.text.contains("目标暂不可操作") and ui._target_text.tooltip_text.contains("code: BODY_BLOCKED") and ui._target_text.tooltip_text.contains("reason: 门扇将挡住同伴的通路") and not ui._target_text.has_theme_color_override("font_color"),ui._target_text.text)
	authority.target={"id":"door:controlled","kind":"door","name":"旧宅门","action":"开门","enabled":false,"proof_state":"rejected","code":"FORBIDDEN","reason":""}
	ui.refresh()
	check("bare rejected code retains localized explanation and raw diagnostic",ui._target_text.text.contains(P.feedback_text(authority.target)) and ui._target_text.tooltip_text.contains("FORBIDDEN"),ui._target_text.text)
	authority.target={"id":"door:controlled","kind":"door","name":"旧宅门","action":"开门","enabled":true,"proof_state":"pending"}
	ui.refresh()
	check("rejected-to-pending transition clears stale refusal diagnostics",ui._target_text.tooltip_text.is_empty() and not ui._target_text.text.contains("目标暂不可操作"))
	for dimensions: Vector2i in [Vector2i(1000,700),Vector2i(1280,800)]:
		root.content_scale_size=dimensions;root.size=dimensions
		for scale_factor: float in [1.0,1.5]:
			ui.set_text_scale(scale_factor);ui.refresh();await flush()
			var bounds:Rect2=ui._target.get_global_rect()
			check("pending hint keeps playfield and hotbar space "+str(dimensions)+" "+str(scale_factor),ui.size==Vector2(dimensions) and bounds.position.x>=0 and bounds.end.x<=dimensions.x and bounds.end.y<=ui._hotbar.get_global_rect().position.y and bounds.size.y<=(120.0*scale_factor),{"ui":str(ui.size),"target":str(bounds),"hotbar":str(ui._hotbar.get_global_rect())})
	var before:=authority.target.duplicate(true)
	var receipt:Dictionary=ui.execute("door","door:controlled",{"direct":true})
	check("attemptable preview does not bypass current command preflight",receipt.get("code")=="FORBIDDEN" and authority.previews==1 and authority.commands==0 and authority.target==before and ui._notice.text.contains("受控当前权限拒绝"),receipt)
	for kind: String in ["npc","terrain","placement"]:
		authority.target={"id":"other","kind":kind,"name":"原对象","action":"交谈","enabled":true,"proof_state":"pending","hint":"原有非门提示"}
		ui.refresh()
		check("door proof rule leaves other target kinds intact "+kind,not ui._target_text.text.contains("尝试") and not ui._target_text.has_theme_color_override("font_color"),ui._target_text.text)
	authority.target={};ui.refresh()
	check("empty target still hides original scene hint",not ui._target.visible)
	host.queue_free();await flush()
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int) -> void:
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok":code==0,"checks":checks,"fixture":"Published door proof DTO and production pure projection/Control with controlled authority; no B door_preview, A direct target transport, real door safety, formal native app or OS visibility evidence","formal_application_launched":false,"production_door_preview_integrated":false,"physical_os_input":false,"route_acceptance":false,"visual_acceptance":false},"  "));file.close()
	quit(code)
