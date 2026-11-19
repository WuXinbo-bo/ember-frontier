extends SceneTree
## UI-only headless checks, explicitly not exported-app/player-route acceptance.
const P = preload("res://scripts/ui/ui_projection.gd")
const Layout = preload("res://scripts/ui/inventory_layout.gd")
const UiScene = preload("res://scenes/ui/game_ui.tscn")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Data = preload("res://scripts/world/world_data.gd")
const RealRouter = preload("res://scripts/input/input_router.gd")
var checks: Array = []
var failed := false

class RouterDouble extends Node:
	signal changed
	signal open_requested(page: String)
	var authority: RefCounted
	var modal := false
	var file_dialog := false
	var assigned: Dictionary = {}
	var bound: Dictionary = {}
	var selected := 0
	func set_modal(value: bool) -> void:
		modal = value
		if authority != null: authority.set_paused(value or file_dialog)
	func set_file_dialog(value: bool) -> void:
		file_dialog = value
		if authority != null: authority.set_paused(value or modal)
	func state() -> Dictionary:
		return {"slots":[{},{},{},{},{},{},{},{},{}], "selected":selected, "mode":"tool", "bindings":{"interact":{"keycode":KEY_E,"physical":true,"label":"E"},"inventory":{"keycode":KEY_TAB,"label":"Tab"},"cancel":{"keycode":KEY_ESCAPE,"label":"Esc"}}}
	func assign_slot(index: int, reference: Dictionary) -> Dictionary:
		assigned = {"index":index,"reference":reference.duplicate(true)}
		return {"ok":true}
	func select_slot(index: int) -> Dictionary:
		selected = index
		return {"ok":true}
	func bind_key(action: String, code: int) -> Dictionary:
		bound = {"action":action, "code":code}
		return {"ok":false,"code":"KEY_CONFLICT","reason":"按键冲突"} if code == KEY_W else {"ok":true}
	func reset_bindings() -> Dictionary:
		return {"ok":true}
	func set_mode(_value: String) -> Dictionary:
		return {"ok":true}

class TransferDouble extends RefCounted:
	signal changed(changes: Dictionary)
	var data: Dictionary
	var calls: Array = []
	var reject := false
	func snapshot() -> Dictionary: return data.duplicate(true)
	func availability(_request: Dictionary) -> Dictionary:
		return {"ok":not reject,"reason":"容器已不可达" if reject else ""}
	func command(request: Dictionary) -> Dictionary:
		calls.append(request.duplicate(true))
		if reject: return {"ok":false,"reason":"拒绝"}
		var pack: Dictionary = data.stocks[0]
		var other: Dictionary = data.stocks[1]
		var source: Dictionary = other if request.kind == "take" else pack
		var destination: Dictionary = pack if request.kind == "take" else other
		for key in request.payload.items:
			var count := float(request.payload.items[key])
			source.items[key] = float(source.items.get(key, 0)) - count
			destination.items[key] = float(destination.items.get(key, 0)) + count
		data.revision += 1
		changed.emit({"revision":data.revision})
		return {"ok":true}

class AsyncDouble extends TransferDouble:
	signal completed(receipt: Dictionary)
	var save_count := 0
	var pending_id := ""
	func save_async(request_id: String = "") -> Dictionary:
		save_count += 1
		pending_id = request_id
		return await completed
	func snapshot() -> Dictionary:
		var result:=data.duplicate(true)
		result["save"]={"ready":true}
		return result

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	call_deferred("run")

func check(name: String, condition: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":condition,"detail":detail})
	if not condition:
		failed = true
		push_error("UI_FAIL " + name + " " + str(detail))

func total(cells: Array, key: String) -> float:
	var value := 0.0
	for cell: Dictionary in cells:
		if cell.entry.get("key") == key: value += float(cell.quantity)
	return value

func fixture() -> Dictionary:
	return {"revision":7,"player":{"id":"player","hp":88,"hunger":75,"thirst":60,"stamina":90,"fatigue":10},"actors":[{"id":"player","hp":88}],"stocks":[{"id":"pack:player","owner":"player","searched":true,"items":{"food":8,"water":3},"reserved":{"items":{"food":2}}},{"id":"chest:1","searched":true,"items":{"food":4,"scrap":2}}],"tools":[{"id":"axe:1","name":"斧头","holderId":"pack:player","durability":94},{"id":"axe:1","holderId":"pack:player"},{"id":"other:1","holderId":"hidden"}],"hand":{},"target":{},"catalog":{},"quests":[],"orders":[]}

func run() -> void:
	var data := fixture()
	var pack := P.player_stock(data)
	check("actual runtime player/owner projection",pack.get("id") == "pack:player")
	check("hidden container not enumerated",P.entries({"id":"secret","searched":false,"items":{"food":99}},data).is_empty())
	var ambiguous := data.duplicate(true)
	ambiguous.stocks.append({"id":"another","owner":"player","searched":true,"items":{}})
	check("ambiguous ownership never picks first",P.player_stock(ambiguous).is_empty())
	check("tool holder projection deduplicates unique reference",P.entries(pack,data).filter(func(e): return e.reference.kind == "tool").size()==1)
	check("reservation free amount",P.entry(pack,data,{"kind":"item","item_id":"food"}).available==6)
	check("router id reference normalizes to typed ID",P.reference_key({"kind":"tool","id":"axe:1"})=="tool:axe:1")
	var model := Layout.new()
	var cells := model.cells(pack,data)
	var food := -1
	for cell in cells:
		if cell.entry.get("key") == "item:food": food=cell.index
	check("split into specified empty cell",model.move(pack,data,food,18,3).is_empty())
	cells=model.cells(pack,data)
	check("split total and selected destination",total(cells,"item:food")==8 and cells[18].quantity==3 and cells[18].entry.key=="item:food")
	check("partial move into unlike stack rejected",not model.move(pack,data,18,1,1).is_empty())
	var smaller:=pack.duplicate(true)
	smaller.items.food=2
	check("reconcile cannot duplicate after stock shrinks",total(model.cells(smaller,data),"item:food")==2)
	var rng:=RandomNumberGenerator.new()
	rng.seed=713
	var conserved:=true
	for iteration in range(160):
		cells=model.cells(pack,data)
		var a:=rng.randi_range(0,23)
		var b:=rng.randi_range(0,23)
		if not cells[a].entry.is_empty(): model.move(pack,data,a,b,float(cells[a].quantity))
		cells=model.cells(pack,data)
		conserved=conserved and total(cells,"item:food")==8 and total(cells,"item:water")==3 and total(cells,"tool:axe:1")==1
	check("160 layout operations conserve physical totals",conserved)
	var ui=UiScene.instantiate()
	var router:=RouterDouble.new()
	root.add_child(router)
	root.add_child(ui)
	var transfer:=TransferDouble.new()
	transfer.data=fixture()
	ui.configure(transfer,router)
	await process_frame
	await process_frame
	check("native font and nine hotbar Control slots",ui._font != null and ui._hotbar.get_child_count()==9)
	var first_slot: int=ui._hotbar.get_child(0).get_instance_id()
	transfer.data.time=1000
	ui.refresh()
	check("clock-only refresh preserves hotbar focus objects",first_slot==ui._hotbar.get_child(0).get_instance_id())
	router.open_requested.emit("inventory")
	check("real router open signal and modal",ui.pages.back().page=="inventory" and router.modal)
	check("modal has reachable hotbar above its blocker",ui._modal_hotbar.visible and ui._modal_hotbar.get_parent().is_ancestor_of(ui._body) and ui._modal_hotbar.get_child_count()==9)
	ui.open_panel("container","chest:1")
	var source: Dictionary=ui.layout.cells(transfer.data.stocks[1],transfer.data)[0]
	source.merge({"kind":"inventory","stock_id":"chest:1","reference":{"kind":"item","item_id":"food"}})
	var drag: Dictionary=ui._create_drag(source)
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":18},drag)
	await process_frame
	check("controlled transfer receives one command with current revision",transfer.calls.size()==1 and transfer.calls[0].expected_revision==7 and transfer.calls[0].target_id=="chest:1")
	var after: Array=ui.layout.cells(transfer.data.stocks[0],transfer.data)
	check("actual transfer receipt places added amount in requested cell",after[18].entry.get("key")=="item:food" and after[18].quantity==4 and total(after,"item:food")==12)
	var count:=transfer.calls.size()
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":19},drag)
	check("duplicate drop token rejected",transfer.calls.size()==count)
	ui.drag={}
	ui.carry={}
	var hotbar: Dictionary={"kind":"hotbar","stock_id":"pack:player","index":0,"reference":{"kind":"item","item_id":"food"},"quantity":12}
	drag=ui._create_drag(hotbar)
	check("hotbar cannot masquerade as physical source cell",not ui._can_drop({"kind":"inventory","stock_id":"pack:player","index":3},drag))
	ui.cancel_transient()
	ui.open_panel("settings")
	ui.capture_action="interact"
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_W
	key.keycode=KEY_W
	key.pressed=true
	ui._input(key)
	check("physical int conflict retained in capture",router.bound.get("code")==KEY_W and ui.capture_action=="interact")
	key.physical_keycode=KEY_F
	key.keycode=KEY_F
	key.meta_pressed=true
	ui._input(key)
	check("mac modifier preserved in binding candidate",router.bound.get("code")==int(KEY_F | KEY_MASK_META) and ui.capture_action.is_empty())
	ui.cancel_ui()
	check("Esc closes one page",ui.pages.back().page=="container")
	ui.close_panels()
	check("last panel releases only modal",not router.modal)
	for page in ["pause","inventory","container","build","workbench","npc","neighbors","quests","settings"]:
		ui.open_panel(page,"chest:1" if page in ["container","workbench"] else "")
		await process_frame
		check("native panel renders: "+page,ui._body.get_child_count()>0)
		ui.close_panels()
	# Actual A runtime and C world, no parallel simulation in UI. Only life command tested here.
	var world:=World.new()
	var generated:Dictionary=Generator.generate(713)
	var result: Dictionary=world.load_snapshot(generated)
	check("C real world loaded for runtime connection",result.get("ok",false))
	var runtime:=Runtime.new()
	var actor_region:=""
	for region:Dictionary in generated.get("regions",{}).values():
		if Data.contains(region.bounds,{"x":16,"y":0,"z":32}): actor_region=str(region.id);break
	check("life fixture derives its actual region from generated bounds",not actor_region.is_empty())
	var actor: Dictionary={"id":"player","name":"测试角色","pack":{"water":2,"food":2},"x":16,"y":0,"z":32,"regionId":actor_region,"hp":88,"hunger":75,"thirst":50,"stamina":90,"fatigue":10,"activity":"自由行动","intent":null}
	result=runtime.configure({"world":world,"facts":{"time":0.0,"status":"playing","actors":[actor],"stocks":[],"actions":[],"quests":[]},"services":{}})
	check("A actual runtime configure",result.get("ok",false))
	router.authority=runtime
	ui.configure(runtime,router)
	ui.open_panel("inventory")
	var before_time:=runtime.clock()
	runtime.tick(1.0)
	check("modal pauses actual runtime time",runtime.clock()==before_time)
	result=ui.execute("drink","",{},true)
	check("UI submits actual runtime intent and resumes",result.get("ok",false) and runtime.actor("player").intent!=null and not router.modal)
	# One tick is frame-bounded and preserves excess debt; feed actual steps.
	for _frame in range(14): runtime.tick(0.1)
	check("real labor consumes one item without UI tick",runtime.actor("player").pack.water==1 and runtime.actor("player").thirst>50)
	check("file receipt requires matching request ID",not ui._file_receipt_ok({"ok":true,"code":"OK","request_id":"old"},"new"))
	check("file receipt accepts actual matching commit",ui._file_receipt_ok({"ok":true,"code":"OK","request_id":"new"},"new"))
	var async_service:=AsyncDouble.new()
	async_service.data=fixture()
	ui.configure(async_service,router)
	ui.save_world()
	ui.save_world()
	check("save waits and suppresses repeated submit",ui.saving and async_service.save_count==1 and ui._notice.text.contains("正在保存"))
	async_service.completed.emit({"ok":false,"code":"IO_ERROR","reason":"测试写入拒绝","request_id":async_service.pending_id})
	check("failed save keeps visible reason and enables retry",not ui.saving and ui._notice.text=="测试写入拒绝")
	ui.save_world()
	ui.configure(transfer,router)
	async_service.completed.emit({"ok":true,"code":"OK","request_id":async_service.pending_id})
	check("late prior-world save cannot report success in new world",not ui.saving and ui._notice.text.is_empty())
	var real_router:=RealRouter.new()
	root.add_child(real_router)
	real_router.configure(runtime)
	ui.configure(runtime,real_router)
	result=ui.router_call("assign_slot",[2,{"kind":"item","item_id":"water"}])
	check("real A router accepts typed UI reference through boundary",result.get("ok",false) and real_router.state().slots[2].id=="water")
	ui.open_panel("inventory")
	real_router.set_window_focus(false)
	ui.close_panels()
	check("closing UI does not clear independent window pause",real_router.state().pause_reasons.window_focus and not real_router.state().pause_reasons.modal and real_router.is_paused())
	real_router.set_window_focus(true)
	check("focus recovery has no held scene inputs",real_router.state().held.primary==false and not real_router.is_paused())
	transfer.data.catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	transfer.data.actors.append({"id":"visible-npc","name":"可见人物的中文姓名","hp":90,"stamina":80,"activity":"等待真实行动","relationship":{"met":true,"member":true,"consent":true}})
	transfer.data.quests=[{"id":"ui-layout-only","title":"用于排版检查的长中文任务名称","description":"内容仅在测试夹具中存在，不进入正式剧情或任务事实。", "status":"active"}]
	ui.configure(transfer,router)
	for resolution in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=resolution
		root.content_scale_size=resolution
		await process_frame
		await process_frame
		for scale in [1.0,1.5]:
			ui.set_text_scale(scale)
			for page in ["inventory","container","workbench","npc","quests","settings","pause"]:
				ui.open_panel(page,"chest:1" if page in ["container","workbench"] else "")
				await process_frame
				await process_frame
				var rect: Rect2=ui._dialog.get_global_rect()
				var logical: Vector2=ui.get_viewport_rect().size
				check("layout %sx%s %s%% %s"%[resolution.x,resolution.y,int(scale*100),page],logical==Vector2(resolution) and rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=logical.x+1 and rect.end.y<=logical.y+1 and ui._scroll.get_global_rect().end.y<=rect.end.y,{"rect":str(rect),"logical":str(logical)})
				check("no horizontal body overflow %sx%s %s%% %s"%[resolution.x,resolution.y,int(scale*100),page],ui._body.size.x<=ui._scroll.size.x+1,{"body":ui._body.size.x,"scroll":ui._scroll.size.x})
				ui.close_panels()
	ui.queue_free()
	router.queue_free()
	real_router.queue_free()
	await process_frame
	print(JSON.stringify({"scope":"UI headless plus actual A runtime life/C world connection; no app export or full IO acceptance","ok":not failed,"checks":checks}))
	quit(1 if failed else 0)
