extends "res://tests/ui/run_service_access_ui.gd"
## Content14 native Control and real runtime inspection. No renderer/package claim.
const P = preload("res://scripts/ui/ui_projection.gd")
const Identity = preload("res://scripts/ui/ui_identity.gd")
const Palette = preload("res://scripts/ui/ui_theme.gd")
const Delta = preload("res://scripts/ui/ui_delta.gd")
const Modes = preload("res://scripts/ui/ui_work_modes.gd")
const Composition = preload("res://scripts/ui/ui_composition.gd")
const Care = preload("res://scripts/ui/life_care.gd")
class TransferSpy extends RefCounted:
	signal changed(changes:Dictionary)
	var calls:Array=[]
	var reject:=false
	var data:Dictionary={"revision":1,"command_revision":1,"player":{"id":"player","stock_id":"pack:player","hp":100,"stamina":100},"stocks":[{"id":"pack:player","owner":"player","searched":true,"items":{}},{"id":"crate","searched":true,"items":{"timber":8,"scrap":2},"reserved":{"items":{"timber":3}}}],"tools":[{"id":"hammer:free","holderId":"crate","durability":70}],"catalog":{},"target":{}}
	func snapshot()->Dictionary:return data.duplicate(true)
	func availability(_command:Dictionary)->Dictionary:return {"ok":not reject,"reason":"容量不足，按件取走" if reject else ""}
	func command(command:Dictionary)->Dictionary:
		calls.append(command.duplicate(true))
		for item:String in command.payload.items:
			data.stocks[1].items[item]-=float(command.payload.items[item])
			data.stocks[0].items[item]=float(data.stocks[0].items.get(item,0))+float(command.payload.items[item])
		for tool:Dictionary in data.tools:
			if command.payload.tool_ids.has(tool.id):tool.holderId="pack:player"
		data.revision+=1;data.command_revision+=1
		changed.emit({"revision":data.revision})
		return {"ok":true}

func run() -> void:
	output=OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestClient.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("current content14 normal world prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false) or not await mount_capture(prepared.capture):return finish()
	var before:Dictionary=runtime.capture_checkpoint()
	var contrast:float=(Palette.BASE.srgb_to_linear().get_luminance()+.05)/(Palette.INK.srgb_to_linear().get_luminance()+.05)
	check("warm paper and ink maintain contrast above 7 to 1",contrast>=7,contrast)
	check("retained vector HUD reflects actual actor",ui._vitals.values.get("hp")==P.player(ui.snapshot).get("hp") and ui._vitals.values.get("stamina")==P.player(ui.snapshot).get("stamina"))
	for actor:Dictionary in P.records(ui.snapshot.get("actors",[])):
		if actor.get("appearance_id") in ["village_linxia_v14","village_chentuo_v14"]:
			check("content14 real appearance has independent young portrait "+str(actor.id),Identity.portrait(actor)!=null and Identity.profile(actor).contains("岁"),Identity.profile(actor))
	var left:=Identity.portrait({"appearance_id":"village_linxia_v14"})
	var right:=Identity.portrait({"appearance_id":"village_chentuo_v14"})
	check("new portraits exist and retain distinct images",left!=null and right!=null and left!=right)
	check("old appearance mapping remains available",Identity.portrait({"appearance_id":"r1_resident_neighbor"})!=null)
	var ids:Array=ui._hotbar.get_children().map(func(n:Node):return n.get_instance_id())
	ui.snapshot.hand.selected=1;ui._render_hotbar()
	check("hotbar selection preserves all native slot identities",ids==ui._hotbar.get_children().map(func(n:Node):return n.get_instance_id()))
	ui.refresh()
	var payload_state:Dictionary={"tools":[{"id":"hammer:free","holderId":"crate"},{"id":"hammer:held","holderId":"crate","reserved":true}]}
	var fixture:Dictionary={"id":"crate","searched":true,"items":{"timber":8,"scrap":2},"reserved":{"items":{"timber":3},"tool_ids":["hammer:held"]}}
	var payload:Dictionary=ui.take_all_payload(fixture,payload_state)
	check("take-all display payload contains only real free quantity and tools",payload=={"items":{"timber":5.0,"scrap":2.0},"tool_ids":["hammer:free"]},payload)
	check("unknown container grants no take-all payload",ui.take_all_payload({"id":"hidden","searched":false,"items":{"timber":99}},payload_state).items.is_empty())
	check("revision-only changes preserve content signature",Delta.display_hash({"world_revision":1,"modules":{"revision":2,"hp":60}})==Delta.display_hash({"world_revision":99,"modules":{"revision":7,"hp":60}}))
	check("real content change still invalidates content signature",Delta.display_hash({"modules":{"hp":60}})!=Delta.display_hash({"modules":{"hp":59}}))
	check("pickup primary displays actual E action",Modes.target_hint({"primary":"pickup"},ui.snapshot.hand).contains("拾取入包"))
	ui.show_pickup({"timber":2,"scrap":0})
	check("pickup toast displays only actual positive material amounts",ui._pickup_toast.visible and ui._pickup_toast.text.contains("+2") and not ui._pickup_toast.text.contains("废料"),ui._pickup_toast.text)
	ui.open_panel("settings");await flush()
	var toggle:=keyed("settings:auto-pickup") as CheckBox
	check("settings uses native focusable auto-pickup control",toggle!=null and toggle.focus_mode==Control.FOCUS_ALL)
	if toggle!=null:
		toggle.toggled.emit(true);await flush()
		check("auto-pickup uses actual router setting",router.state().get("auto_pickup",false))
		toggle=keyed("settings:auto-pickup") as CheckBox
		if toggle!=null:toggle.toggled.emit(false);await flush()
	var modules:Array=F.rows(ui.factory,"modules","instances")
	var restored:int=0
	for module:Dictionary in modules:
		if module.get("state_code")!="needs_restoration":continue
		ui.close_panels();ui.open_panel("module",str(module.id));await flush()
		var copy:=text_in(ui._body)
		check("restoration names actual building "+str(module.id),copy.contains("修复"+str(module.name)) and not copy.contains("旧机架"),copy)
		check("restoration shows real material preparation "+str(module.id),copy.contains("修复准备") and copy.contains("可用量已扣预留"))
		restored+=1
	check("fresh opening exposes repairable heritage buildings",restored>=2,restored)
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5)
		for page:String in ["factory_inventory","factory_catalog","factory_people","factory_production","factory_logistics","factory_alerts","factory_handbook","water","settings","pause"]:
			ui.close_panels();ui.open_panel(page);await flush()
			check("native custom page fits "+page+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()),str(ui._dialog.get_global_rect()))
	ui.close_panels();ui.refresh();await flush()
	check("all UI inspection keeps world authority unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
	# Explicit command spy isolates request correctness and refusal handling;
	# it does not count as a real owner capacity/permission integration test.
	var spy:=TransferSpy.new();ui.configure(spy,router);await flush()
	var care:=VBoxContainer.new();ui.add_child(care);Care.render(ui,care,false)
	for spec:Array in [["eat","食物"],["drink","安全饮水"],["medicine","医疗物品"]]:
		var reason:String="随身没有可用的"+str(spec[1])
		var action:Button=keyed("care:use:"+str(spec[0]),care) as Button
		check("missing care supply has one complete visible reason "+str(spec[0]),text_in(care).count(reason)==1 and action!=null and action.disabled and action.tooltip_text==reason)
	care.free()
	ui.open_panel("container","crate");await flush()
	var accepted:Dictionary=ui.take_all_current();await flush()
	check("take-all submits exactly one current command with tools and free items",accepted.get("ok",false) and spy.calls.size()==1 and spy.calls[0].kind=="take" and spy.calls[0].target_id=="crate" and spy.calls[0].payload=={"items":{"timber":5.0,"scrap":2.0},"tool_ids":["hammer:free"]},spy.calls)
	check("take-all receipt reports actual observed pack delta",spy.data.stocks[0].items=={"timber":5.0,"scrap":2.0} and ui._notice.text.contains("3项入包"),ui._notice.text)
	spy.data.stocks[1].items.scrap=1;spy.reject=true
	var frozen:Dictionary=spy.snapshot();var refused:Dictionary=ui.take_all_current();await flush()
	check("owner refusal keeps original stock and sends no mutating command",not refused.get("ok",true) and spy.calls.size()==1 and Data.json_equal(frozen,spy.snapshot()) and ui._notice.text.contains("容量不足"))
	finish()

func finish() -> void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"scope":"experience14 current-source headless native Control; real fresh Native runtime for read-only pages, actual router settings, exact authority comparison; explicit display DTO payload probe and TransferSpy for request/refusal verification; no OS pointer, renderer, PCK, full route, visual acceptance or performance qualification"}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
