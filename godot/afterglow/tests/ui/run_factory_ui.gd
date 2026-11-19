extends SceneTree
## Actual factory authority + native UI, without formal scene/renderer/user saves.
const Client = preload("res://scripts/runtime/native_client.gd")
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Modules = preload("res://scripts/modules/module_service.gd")
const Shape = preload("res://scripts/modules/module_geometry.gd")
const Draft = preload("res://scripts/actions/domain_draft.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Gameplay = preload("res://scripts/runtime/factory_gameplay.gd")
const Store = preload("res://scripts/storage/native_store.gd")
class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
class TestClient extends Client:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
var checks: Array = []
var output := ""
var host: Node3D
var ui: Control
var runtime: RefCounted
var router: Node
var services:Dictionary={}
var mouse:=Vector2.ZERO
var mouse_held:=false
var machine_id:="ui:test-built-woodshop"
func _initialize() -> void:
	create_timer(60).timeout.connect(func():check("timeout",false);finish())
	call_deferred("run")
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok: print("FAIL " + name + " " + str(detail))
func flush() -> void:
	await process_frame
	await process_frame
func text_in(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): result += text_in(child)
	return result
func keyed(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("ui_focus_key", "") == key: return node
	for child in node.get_children():
		var found := keyed(child, key)
		if found != null: return found
	return null
func run() -> void:
	root.size=Vector2i(1280,800)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var profiles := Assembly.generation_profiles()
	var prepared := Assembly.prepare(Assembly.generate(713, profiles.profiles)) if profiles.ok else profiles
	check("actual normal factory capture", prepared.get("ok",false), prepared.get("reason"))
	if not prepared.ok: return finish()
	host = TestClient.new(); root.add_child(host)
	var built: Dictionary = host._assemble(prepared.capture)
	check("actual formal service assembly",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime = built.runtime; services=built.services
	router = TestRouter.new(); host.add_child(router); router.configure(runtime)
	ui = Mount.mount(host,runtime,router)
	await flush()
	check("native UI mounts public factory projection",F.enabled(ui.factory) and ui.factory.schema==F.SCHEMA)
	for page in ["factory","build","module","container","factory_production","factory_logistics","factory_people","factory_alerts","factory_handbook","pause","new_world"]:
		ui.close_panels()
		var subject := str(ui.factory.modules.instances[0].id) if page=="module" else ""
		ui.open_panel(page,subject); await flush()
		check("renders " + page,not ui.pages.is_empty() and not text_in(ui._body).is_empty())
	ui.close_panels(); await flush()
	check("factory HUD replaces legacy navigation",ui._factory_navigation.visible and not ui._navigation.visible)
	check("normal factory HUD protects playfield",ui._hud_backdrop.size.x<=340 and ui._hud_backdrop.size.y<200 and not ui._profile_hint.visible and not ui._movement_hint.visible,{"hud":ui._hud_backdrop.size})
	check("normal opening identity is real",runtime.snapshot().get("opening_profile")=="normal" and runtime.snapshot().get("playtest",{}).is_empty())
	var before:Dictionary=runtime.capture_checkpoint()
	ui.open_panel("build");await flush()
	check("B enters full-module catalog",ui.pages.back().page=="factory_catalog" and keyed(ui,"factory:preview:r34.module.warehouse")!=null and not text_in(ui._body).contains("地形笔刷"))
	var selected:Dictionary=ui.begin_module_preview("r34.module.warehouse")
	check("catalog uses true module input mode without paying",selected.get("ok",false) and router.state().mode=="module_place" and router.state().module_definition_id=="r34.module.warehouse" and ui.pages.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	router.cancel()
	ui.open_panel("inventory");await flush()
	check("Tab inventory stays in factory workflow",ui.pages.back().page=="factory_inventory" and not text_in(ui._body).contains("高级笔刷"))
	ui.close_panels()
	var module:Dictionary=ui.factory.modules.instances[0]
	var known_id:String=module.stock_refs.values()[0]
	var hidden:Dictionary=ui.factory.duplicate(true)
	for row:Dictionary in hidden.modules.instances:
		if row.id==module.id:row.stock_visibility=false
	check("explicit hidden buffer overrides raw stocks",not F.stock_visible(hidden,ui.snapshot,known_id))
	hidden=ui.factory.duplicate(true)
	for row:Dictionary in hidden.modules.instances:
		if row.id==module.id:row.visuals.buffers=[]
	check("missing buffer rows never prove empty known stock",not F.stock_visible(hidden,ui.snapshot,known_id))
	check("capacity reservation not subtracted twice",F.buffer_text({"item_id":"timber","actual":8,"capacity":24,"reserved":4,"unit":"count"}).contains("8") and F.buffer_text({"item_id":"timber","actual":8,"capacity":24,"reserved":4,"unit":"count"}).contains("预占 4"))
	if not await build_fixture(prepared.capture):return finish()
	await production_and_inventory()
	finish()

func remount(capture:Dictionary)->bool:
	if is_instance_valid(ui):ui.get_parent().free()
	if is_instance_valid(router):router.free()
	var built:Dictionary=host._assemble(capture)
	check("fixture restores through actual Native validators",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return false
	runtime=built.runtime;services=built.services
	router=TestRouter.new();host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router)
	await flush();return true

func build_fixture(original:Dictionary)->bool:
	# Explicit fixture supplies only. Vacate one actual graded pad; subsequent
	# module and machine behavior goes through real authority, not projected fakes.
	var capture:=original.duplicate(true)
	var state:Dictionary=capture.world.extensions[Modules.KEY]
	var homes: Array = state.instances.filter(func(v: Dictionary) -> bool: return Modules.definition(v.definition_id).get("generation_role") == "home" and v.region == "RH-HOME")
	check("fixture resolves current generated home variant", not homes.is_empty())
	if homes.is_empty(): return false
	var home: Dictionary = homes[0]
	var position:Dictionary=home.position.duplicate(true);position.regionId=home.region
	for member:Dictionary in home.members:capture.world.entities.erase(member.id)
	state.instances.erase(home)
	for key in state.source_receipts.keys():
		if state.source_receipts[key].module_id==home.id:state.source_receipts.erase(key)
	capture.facts.stocks=capture.facts.stocks.filter(func(stock:Dictionary):return stock.get("module_id")!=home.id)
	var actor:=Draft.find(capture.facts.actors,"player")
	actor.pack={"timber":64,"scrap":32,"r34:salvaged_drive_unit":1,"log":20,"food":1,"water":1}
	actor.x=position.x;actor.y=position.y;actor.z=position.z-3.1;actor.regionId=home.region
	var hammer:Dictionary=capture.world.extensions["r3:production"].tools.filter(func(tool:Dictionary):return tool.kind=="hammer")[0]
	hammer.holderId="pack:player"
	if not await remount(capture):return false
	var planned:Dictionary=ui.execute("module.plan",machine_id,{"definition_id":"r34.module.fuel_woodshop","position":position,"quarter_turn":0,"source_id":"pack:player","tool_id":hammer.id})
	check("UI command submits actual module project",planned.get("ok",false),planned)
	if not planned.get("ok",false):return false
	ui.open_panel("module",machine_id);await flush()
	check("construction projects expose actual controls",keyed(ui,"factory:command:module.cancel:"+machine_id)!=null and text_in(ui._body).contains("施工进度"))
	for i in 410:
		var step:Dictionary=services.modules.advance(0.1)
		if not step.get("ok",false) or not runtime._commit(step).get("ok",false):check("fixture on-site labor",false,step);return false
	check("actual construction completes, empty buffers",services.modules.instance(machine_id).status=="operational" and runtime.stock(services.modules.instance(machine_id).stock_refs.input).items.is_empty())
	return true

func motion(position:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=position;event.global_position=position;event.relative=position-mouse;event.button_mask=MOUSE_BUTTON_MASK_LEFT if mouse_held else 0
	mouse=position;root.push_input(event,true);await flush()
func mouse_button(down:bool,shift:bool=false)->void:
	mouse_held=down
	var event:=InputEventMouseButton.new();event.position=mouse;event.global_position=mouse;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	event.shift_pressed=shift
	root.push_input(event,true);await flush()
func slot_node(stock_id:String,reference:String="",index:int=-1)->Button:
	for node in ui.find_children("*","Button",true,false):
		if not node.is_visible_in_tree() or not node.get("slot") is Dictionary or node.slot.get("kind")!="inventory" or node.slot.get("stock_id")!=stock_id:continue
		if index>=0 and node.slot.get("index")!=index:continue
		if not reference.is_empty() and P.reference_key(node.slot.get("reference",{}))!=reference:continue
		return node
	return null
func data_slot(stock_id:String,item_id:String)->Dictionary:
	for node in ui.find_children("*","Button",true,false):
		if node.get("slot") is Dictionary and node.slot.get("kind")=="inventory" and node.slot.get("stock_id")==stock_id and node.slot.get("reference",{}).get("item_id")==item_id:return node.slot.duplicate(true)
	return {}
func production_step()->void:
	var step:Dictionary=services.production.advance(0.1)
	check("actual production authority advances once",step.get("ok",false) and runtime._commit(step).get("ok",false),step.get("reason"))
	ui.refresh();await flush()
func activate(key:String)->bool:
	var node:=keyed(ui,key)
	check("available actual UI action "+key,node is Button and not node.disabled)
	if node is Button and not node.disabled:node.pressed.emit();return true
	return false
func production_and_inventory()->void:
	var module:Dictionary=services.modules.instance(machine_id)
	var capture:Dictionary=runtime.capture_checkpoint();var actor:=Draft.find(capture.facts.actors,"player")
	var port:=Draft.find(Shape.ports(module,Modules.definition(module.definition_id)),"log-input")
	actor.x=port.location.x;actor.y=port.location.y;actor.z=port.location.z
	if not await remount(capture):return
	ui.open_panel("container",str(module.stock_refs.input));await flush()
	var stock_id:=str(module.stock_refs.input)
	var slot:=data_slot("pack:player","log")
	check("native dual inventory binds one real item reference",not slot.is_empty() and slot.reference=={"kind":"item","item_id":"log"})
	var before:Dictionary=runtime.capture_checkpoint()
	var drag_data:Dictionary=ui._create_drag(slot);drag_data.amount=2
	ui._transfer(drag_data,stock_id);ui.cancel_transient();ui.refresh();await flush()
	check("near drop transfers actual goods exactly once",runtime.actor("player").pack.log==18 and runtime.stock(stock_id).items.log==2)
	var source_node:=slot_node(stock_id,"item:log")
	var destination_node:=slot_node("pack:player","",10)
	check("native paired-grid pointer source and destination visible",source_node!=null and destination_node!=null and root.get_visible_rect().encloses(source_node.get_global_rect()) and root.get_visible_rect().encloses(destination_node.get_global_rect()))
	if source_node!=null and destination_node!=null:
		await motion(source_node.get_global_rect().get_center());await mouse_button(true)
		await motion(source_node.get_global_rect().get_center()+Vector2(20,0))
		check("Godot begins real factory drag",root.gui_is_dragging() and not ui.drag.is_empty())
		await motion(destination_node.get_global_rect().get_center());await mouse_button(false)
		check("native drop performs sole actual take",runtime.actor("player").pack.log==20 and runtime.stock(stock_id).items.log==0 and ui.drag.is_empty() and ui.carry.is_empty())
		var returned:Dictionary=ui._create_drag(data_slot("pack:player","log"));returned.amount=2
		ui._transfer(returned,stock_id);ui.cancel_transient();ui.refresh();await flush()
	# Synthetic pointer modifier deliberately differs from global Input state,
	# including Shift released before click completes, like the OS symptom.
	source_node=slot_node(stock_id,"item:log")
	await motion(source_node.get_global_rect().get_center());await mouse_button(true,true);await mouse_button(false)
	check("Shift pointer event commits actual take without global key polling",runtime.actor("player").pack.log==20 and runtime.stock(stock_id).items.log==0 and ui.carry.is_empty())
	var returned:Dictionary=ui._create_drag(data_slot("pack:player","log"));returned.amount=2;ui._transfer(returned,stock_id);ui.cancel_transient();ui.refresh();await flush()
	source_node=slot_node(stock_id,"item:log")
	await motion(source_node.get_global_rect().get_center());await mouse_button(true);await mouse_button(false)
	check("plain click is visibly uncommitted with explicit take action",not ui.carry.is_empty() and runtime.actor("player").pack.log==18 and runtime.stock(stock_id).items.log==2 and keyed(ui,"factory:inventory:transfer") is Button)
	activate("factory:inventory:transfer");await flush()
	check("explicit take button commits only observed real stock delta",runtime.actor("player").pack.log==20 and runtime.stock(stock_id).items.log==0 and ui.carry.is_empty())
	source_node=slot_node("pack:player","item:log")
	await motion(source_node.get_global_rect().get_center());await mouse_button(true);await mouse_button(false)
	ui.carry.amount=2;ui.queue_refresh();await flush()
	check("selected portion offers explicit real deposit",keyed(ui,"factory:inventory:transfer") is Button and keyed(ui,"factory:inventory:transfer").text.begins_with("存入当前容器"))
	activate("factory:inventory:transfer");await flush()
	check("explicit deposit conserves the selected quantity",runtime.actor("player").pack.log==18 and runtime.stock(stock_id).items.log==2 and ui.carry.is_empty())
	before=runtime.capture_checkpoint()
	source_node=slot_node("pack:player","item:log")
	await motion(source_node.get_global_rect().get_center());await mouse_button(true,true);await mouse_button(false)
	check("Shift capacity rejection retains exact goods without success or stale carry",Data.json_equal(before,runtime.capture_checkpoint()) and ui.carry.is_empty() and ui.drag.is_empty() and not ui._notice.text.contains("物品已实际转移"))
	check("capacity rejection remains readable inside inventory",ui._panel_notice.is_visible_in_tree() and ui._panel_notice.text==ui._notice.text and not ui._panel_notice.text.is_empty())
	check("inventory modal hides duplicate scene HUD",not ui._hud_backdrop.visible)
	var split:=data_slot("pack:player","log")
	ui._split_slot(split);await flush()
	check("native split opens without touching real inventory",is_instance_valid(ui._split_layer) and runtime.actor("player").pack.log==18)
	ui.cancel_ui();await flush()
	check("Esc split returns transient without duplication",not is_instance_valid(ui._split_layer) and ui.carry.is_empty() and ui.drag.is_empty() and runtime.actor("player").pack.log==18)
	ui._create_drag(data_slot("pack:player","log"));ui._on_focus_exited();await flush()
	check("focus exit clears all uncommitted drag references",ui.drag.is_empty() and ui.carry.is_empty() and runtime.actor("player").pack.log==18)
	ui.close_panels();ui.open_panel("factory_production");await flush()
	var configure_key:="factory:command:factory.configure:"+machine_id
	check("machine configuration is a true actionable surface",keyed(ui,configure_key)!=null)
	activate(configure_key);await flush()
	check("configure creates real single order with no free output",runtime.factory_snapshot().production.orders.size()==1 and runtime.stock(module.stock_refs.output).items.is_empty())
	check("missing fuel is diagnosed from owner",text_in(ui._body).contains("缺少能源") or text_in(ui._body).contains("缺能"),text_in(ui._body))
	# Remote inventory query cannot transfer, even if known public metadata exists.
	ui.close_panels();ui.open_panel("container",str(module.stock_refs.fuel));await flush()
	before=runtime.capture_checkpoint();var payload:Dictionary=ui._create_drag(data_slot("pack:player","log"));payload.amount=1
	ui._transfer(payload,str(module.stock_refs.fuel));ui.cancel_transient();ui.refresh();await flush()
	check("remote container cannot teleport a log",Data.json_equal(before,runtime.capture_checkpoint()))
	capture=runtime.capture_checkpoint();actor=Draft.find(capture.facts.actors,"player");port=Draft.find(Shape.ports(module,Modules.definition(module.definition_id)),"fuel-input")
	actor.x=port.location.x;actor.y=port.location.y;actor.z=port.location.z
	if not await remount(capture):return
	ui.open_panel("container",str(module.stock_refs.fuel));await flush()
	payload=ui._create_drag(data_slot("pack:player","log"));payload.amount=1;ui._transfer(payload,str(module.stock_refs.fuel));ui.cancel_transient();ui.close_panels()
	await production_step()
	ui.open_panel("factory_production");await flush()
	var live:Dictionary=runtime.factory_snapshot().production.batches[-1]
	check("actual WIP and output promise remain distinct",live.wip=={"log":1.0} and live.elapsed>0 and runtime.stock(module.stock_refs.output).items.is_empty())
	activate("factory:command:factory.cancel:"+machine_id);await flush()
	check("stop requires consequence confirmation",ui.pages.back().page=="factory_confirm" and text_in(ui._body).contains("保留在制"))
	var before_cancel:Dictionary=runtime.capture_checkpoint();activate("factory:confirm:cancel");await flush()
	check("cancel confirmation sends no command",Data.json_equal(before_cancel,runtime.capture_checkpoint()))
	activate("factory:command:factory.cancel:"+machine_id);await flush();activate("factory:confirm:submit");await flush()
	check("stop preserves progressed log and does not refund energy",runtime.factory_snapshot().production.batches[-1].wip=={"log":1.0} and runtime.factory_snapshot().production.orders[0].remaining==0)
	activate("factory:command:factory.discard:"+machine_id);await flush()
	check("discard states zero recovery and safe cancel focus",text_in(ui._body).contains("回收为0") and root.gui_get_focus_owner().get_meta("ui_focus_key","")=="factory:confirm:cancel")
	activate("factory:confirm:submit");await flush()
	check("explicit discard settles once without product or log refund",runtime.factory_snapshot().production.batches[-1].status=="discarded" and runtime.stock(module.stock_refs.output).items.is_empty() and runtime.stock(module.stock_refs.input).items.log==1)
	ui.close_panels();ui.open_panel("factory_logistics");await flush()
	check("real logistics form uses known eligible stocks",text_in(ui._body).contains("安排真实取送") or text_in(ui._body).contains("尚无已搜索"))
	ui.factory_view.merge({"logistics_source":str(module.stock_refs.input),"logistics_destination":str(module.stock_refs.fuel),"logistics_item":"log","logistics_amount:log":1,"logistics_repeat":true},true)
	ui.queue_refresh();await flush()
	var goods_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	activate("factory:command:logistics.create:");await flush()
	var tasks:Array=runtime.factory_snapshot().logistics.tasks
	check("logistics UI creates real repeating task without moving goods",tasks.size()==1 and tasks[0].source_id==module.stock_refs.input and tasks[0].destination_id==module.stock_refs.fuel and tasks[0].repeat and runtime.actor("player").pack==goods_before and runtime.stock(module.stock_refs.input).items.log==1)
	ui.close_panels();ui.open_panel("factory_people");await flush()
	check("published actual N6 candidate can be selected",keyed(ui,"factory:command:workforce.assign::player")!=null)
	activate("factory:command:workforce.assign::player");await flush()
	check("workforce selection targets actual actor and unique B candidate",runtime.factory_snapshot().workforce.assignments.size()==1 and runtime.factory_snapshot().workforce.assignments[0].actor_id=="player" and runtime.factory_snapshot().workforce.assignments[0].candidate_id==tasks[0].id)
	ui.factory_view["workforce_priority:player"]=7;ui.queue_refresh();await flush()
	activate("factory:command:workforce.priority::player");await flush()
	check("real workforce priority updates exact assignment",runtime.factory_snapshot().workforce.assignments[0].priority==7)
	activate("factory:command:workforce.clear::player");await flush();activate("factory:confirm:submit");await flush()
	check("clear unstarted assignment preserves physical goods",runtime.factory_snapshot().workforce.assignments.is_empty() and runtime.actor("player").pack==goods_before and runtime.stock(module.stock_refs.input).items.log==1)
	ui.close_panels();ui.open_panel("factory_logistics");await flush()
	activate("factory:command:logistics.cancel:"+str(tasks[0].id));await flush();activate("factory:confirm:submit");await flush()
	check("logistics cancellation has actual receipt without refunds or copies",runtime.factory_snapshot().logistics.tasks[0].status=="cancelled" and runtime.actor("player").pack==goods_before and runtime.stock(module.stock_refs.input).items.log==1)
	ui.close_panels();ui.open_panel("factory_handbook");ui.factory_view.handbook_section="stories";ui.queue_refresh();await flush()
	check("handbook excludes unknown neighbours despite raw story source registration",not text_in(ui._body).contains("邻里小院") and text_in(ui._body).contains("已发现的地点与同行经历"))
	ui.close_panels();ui.open_panel("factory_alerts");await flush()
	var event:Dictionary=runtime.factory_snapshot().workforce.get("regional_event",{})
	check("undiscovered remote regional site is not exposed by UI",not event.get("available",false) and event.get("sites",[]).is_empty() and keyed(ui,"factory:command:settlement.survey:")==null)
	for dimensions in [Vector2i(1000,700),Vector2i(800,600)]:
		ui.close_panels();root.size=dimensions;ui.set_text_scale(1.5);await flush()
		ui.open_panel("container",str(module.stock_refs.fuel));await flush()
		var grids:Array=ui._body.find_children("*","GridContainer",true,false)
		var overflow:=false
		for grid in grids:
			if grid.size.x>ui._scroll.size.x+1:overflow=true
		check("large-text inventory grid fits logical canvas for window "+str(dimensions),not overflow,{"requested_window":dimensions,"logical_viewport":root.get_visible_rect().size,"scroll_width":ui._scroll.size.x,"grids":grids.map(func(grid):return grid.size.x)})
		ui.close_panels();ui.open_panel("build");await flush()
		check("catalog remains inside viewport "+str(dimensions),root.get_visible_rect().encloses(ui._dialog.get_global_rect()))
		var search:=keyed(ui,"factory:search:catalog_search") as LineEdit
		search.grab_focus();search.text="仓储";search.caret_column=1;search.text_changed.emit(search.text);await flush()
		var restored:=keyed(ui,"factory:search:catalog_search") as LineEdit
		check("native search preserves text caret and focus "+str(dimensions),restored.text=="仓储" and restored.caret_column==1 and restored.has_focus())
		ui.factory_view.erase("catalog_search")
	ui.close_panels()
	var snapshot_file:=FileAccess.open(output+"/factory-snapshot.json",FileAccess.WRITE);snapshot_file.store_string(JSON.stringify(runtime.factory_snapshot(),"\t",true,true));snapshot_file.close()
	var base:Dictionary=runtime.capture_checkpoint()
	await player_care_controls(base)
	await regional_controls(base)
	await recovery_controls(base)
	await logistics_recovery_controls(base)

func player_care_controls(base:Dictionary)->void:
	if not await remount(base):return
	ui.open_panel("factory_people");await flush()
	var key:="drink::"+str({}.hash())
	check("factory people retains real player needs and care",text_in(ui._body).contains("你 · 身体与行动") and text_in(ui._body).contains("饮水 · "+P.number(runtime.actor("player").thirst)) and keyed(ui,key)!=null)
	activate(key);await flush()
	check("care starts actual runtime action and closes modal",ui.pages.is_empty() and runtime.actor("player").get("intent") is Dictionary and runtime.actor("player").intent.kind=="drink" and not runtime.is_paused())

func regional_controls(base:Dictionary)->void:
	# Move only an isolated checkpoint to the real survey point. This verifies
	# GUI consent/authority, not the normal walking/supply budget or OS journey.
	# Private plan access exists only in this fixture, never production UI.
	var planned_sites: Array = base.world.extensions.get("generation:RH-VILLAGE", {}).get("regional_sites", [])
	check("regional fixture has an actual persisted C survey point", not planned_sites.is_empty())
	if planned_sites.is_empty(): return
	var planned_site: Dictionary = planned_sites[0]
	var near:Dictionary=base.duplicate(true)
	var actor:=Draft.find(near.facts.actors,"player")
	actor.merge(planned_site.survey_point,true);actor.intent=null
	if not await remount(near):return
	var event: Dictionary = runtime.factory_snapshot().workforce.regional_event
	var site: Dictionary = F.find(event.get("sites", []), str(planned_site.id))
	check("real near survey point is published through owner facade", event.get("available", false) and not site.is_empty())
	if site.is_empty(): return
	ui.set_text_scale(1);root.size=Vector2i(1280,800)
	ui.open_panel("factory_alerts",str(site.id));await flush()
	activate("factory:command:settlement.survey:");await flush()
	var state:Dictionary=runtime.world.extension(Gameplay.KEY)
	check("survey UI commits exploration without risk consent or threat",state.regional_objectives[site.id].surveyed and not state.regional_objectives[site.id].risk_accepted and state.defense.status=="dormant")
	activate("factory:command:settlement.begin_route_work:");await flush()
	check("route work requires explicit risk consequence and safe cancel focus",ui.pages.back().page=="factory_confirm" and text_in(ui._body).contains("当地威胁") and root.gui_get_focus_owner().get_meta("ui_focus_key","")=="factory:confirm:cancel")
	var before:Dictionary=runtime.capture_checkpoint()
	activate("factory:confirm:cancel");await flush()
	check("risk confirmation cancel preserves exact world and goods",Data.json_equal(before,runtime.capture_checkpoint()))
	activate("factory:command:settlement.begin_route_work:");await flush();activate("factory:confirm:submit");await flush()
	check("confirmed UI submits true site risk without clearing obstruction",runtime.world.extension(Gameplay.KEY).regional_objectives[site.id].risk_accepted and not runtime.world.extension(Gameplay.KEY).regional_objectives[site.id].corridor_clear)
	ui.close_panels();runtime.tick(0.1);ui.open_panel("factory_alerts");await flush()
	state=runtime.world.extension(Gameplay.KEY)
	check("actual warning and remaining time are displayed from sole clock",state.defense.status=="warning" and text_in(ui._body).contains("有效预告余时") and float(state.defense.warning_remaining)>=60)
	var warnings: Array = F.alerts(ui.factory).filter(func(row: Dictionary) -> bool: return row.get("object_id") == site.id)
	# Contract6.4: ordinary warning/info needs one simulation second of stable
	# cause. The regional risk/banner is immediate; the alert list is not.
	# Poll only the same public DTO while real clock advances, bounded at2s.
	for index in 20:
		if not warnings.is_empty():break
		runtime.tick(0.1);ui.refresh();await flush()
		warnings=F.alerts(ui.factory).filter(func(row:Dictionary)->bool:return row.get("object_id")==site.id)
	check("published alarm detail is visible without private state lookup",not warnings.is_empty() and not str(warnings[0].get("detail", "")).is_empty() and text_in(ui._body).contains(str(warnings[0].detail)),{"clock":runtime.clock(),"public_alerts":warnings})
	check("accepted site cannot be restarted through UI",keyed(ui,"factory:command:settlement.begin_route_work:") is Button and keyed(ui,"factory:command:settlement.begin_route_work:").disabled)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	check("UI consent and warning encode in actual native store",encoded.get("ok",false))
	if encoded.get("ok",false):
		var decoded:Dictionary=Store.decode(encoded.text)
		if decoded.get("ok",false) and await remount(decoded.capture):
			ui.open_panel("factory_alerts");await flush()
			check("cold restored UI retains one risk and real warning",runtime.world.extension(Gameplay.KEY).defense.warning_id==state.defense.warning_id and text_in(ui._body).contains("风险承诺 · 已确认"))

func recovery_controls(base:Dictionary)->void:
	if not await remount(base):return
	var damage:Dictionary=services.modules.prepare_damage(machine_id,1000,"ui:actual-domain-damage")
	check("actual damage authority creates a ruin",damage.get("ok",false) and runtime._commit(damage).get("ok",false))
	var ruin:Dictionary=services.modules.instance(machine_id)
	ui.open_panel("module",machine_id);await flush()
	var button:=keyed(ui,"factory:command:module.clear_ruin:"+machine_id)
	check("ruin UI shows frozen ledger and blocks uncleared cache",button is Button and button.disabled and text_in(ui._body).contains("冻结回收账本") and text_in(ui._body).contains("尚未清空") and keyed(ui,"factory:command:factory.configure:"+machine_id)==null)
	var capture:Dictionary=runtime.capture_checkpoint()
	var actor:=Draft.find(capture.facts.actors,"player")
	var port:=Draft.find(Shape.ports(ruin,Modules.definition(ruin.definition_id)),"log-input")
	actor.merge(port.location,true);actor.intent=null
	if not await remount(capture):return
	ui.open_panel("container",str(ruin.stock_refs.input));await flush()
	var take:Dictionary=ui.execute("take",str(ruin.stock_refs.input),{"items":{"log":1},"tool_ids":[]})
	check("ruin cached input remains real takeable goods",take.get("ok",false) and float(runtime.stock(ruin.stock_refs.input).items.get("log",0))==0,take)
	capture=runtime.capture_checkpoint();actor=Draft.find(capture.facts.actors,"player")
	port=Draft.find(Shape.ports(ruin,Modules.definition(ruin.definition_id)),"repair")
	actor.merge(port.location,true);actor.intent=null
	if not await remount(capture):return
	ui.open_panel("module",machine_id);await flush()
	var before:Dictionary=runtime.capture_checkpoint()
	activate("factory:command:module.clear_ruin:"+machine_id);await flush()
	check("clear ruin confirms once and does not grant salvage on opening",ui.pages.back().page=="factory_confirm" and Data.json_equal(before,runtime.capture_checkpoint()) and text_in(ui._body).contains("冻结账本"))
	activate("factory:confirm:cancel");await flush()
	check("clear ruin cancellation preserves frozen ledger",Data.json_equal(before,runtime.capture_checkpoint()))
	activate("factory:command:module.clear_ruin:"+machine_id);await flush();activate("factory:confirm:submit");await flush()
	check("confirmed ruin clear starts real labor and resumes sole world",services.modules.state().projects[-1].operation=="clear_ruin" and services.modules.state().projects[-1].status=="active" and ui.pages.is_empty() and not runtime.is_paused())
	ui.close_panels()
	var failed_step:Dictionary={}
	for index in 125:
		var step:Dictionary=services.modules.advance(0.1)
		if not step.get("ok",false) or not runtime._commit(step).get("ok",false):failed_step=step;break
	var cleared:Dictionary=services.modules.instance(machine_id)
	check("UI clear settles exact frozen recovery once after labor",failed_step.is_empty() and cleared.status=="dismantled" and cleared.recovery.claimed and cleared.recovery_settlement.items==ruin.recovery.items,failed_step)
	for item:String in ruin.recovery.items:
		check("exact recovered quantity "+item,is_equal_approx(float(runtime.actor("player").pack.get(item,0))-float(Draft.find(before.facts.actors,"player").pack.get(item,0)),float(ruin.recovery.items[item])))

func logistics_recovery_controls(base:Dictionary)->void:
	# Explicit consent/nearby receiving crate fixture. Pickup, held cargo,
	# retarget and delivery still run through the actual E/B/A services.
	var capture:Dictionary=base.duplicate(true)
	var workshops: Array = capture.world.extensions[Modules.KEY].instances.filter(func(row: Dictionary) -> bool: return Modules.definition(row.definition_id).get("generation_role") == "workshop")
	check("logistics fixture resolves current generated workshop variant", not workshops.is_empty())
	if workshops.is_empty(): return
	var workshop: Dictionary = workshops[0]
	var point:Dictionary=Draft.find(Shape.ports(workshop,Modules.definition(workshop.definition_id)),"work").location
	var worker:=Draft.find(capture.facts.actors,"repair-resident")
	worker.merge(point,true);worker.buildingId=null;worker.storeyId=null;worker.intent=null;worker.pack={};worker.householdId="home-residents";worker.relationship.member=true;worker.relationship.consent=true;worker.relationship.home_arrived=true;worker.job="rest";worker.thirst=90;worker.hunger=90;worker.fatigue=0
	var player:=Draft.find(capture.facts.actors,"player");player.merge(point,true);player.z-=1.5;player.intent=null
	var source:=Draft.find(capture.facts.stocks,str(workshop.stock_refs.tools));source.searched=true
	Draft.find(capture.facts.stocks,str(workshop.stock_refs.input)).searched=true
	var receiving:Dictionary=point.duplicate(true);receiving.z-=1
	var receiver:="ui:recovery:receiver"
	capture.facts.stocks.append({"id":receiver,"location":receiving,"items":{},"owner":"home-residents","searched":true})
	if not await remount(capture):return
	var created:Dictionary=ui.execute("logistics.create","",{"source_id":source.id,"destination_id":workshop.stock_refs.input,"items":{"timber":1}})
	check("recovery UI queues one physical transport",created.get("ok",false),created)
	var task_id:=str(runtime.factory_snapshot().logistics.tasks[-1].id)
	ui.open_panel("factory_people");await flush()
	check("known consenting NPC gets its real public N6 suggestion",keyed(ui,"factory:command:workforce.assign::"+str(worker.id))!=null)
	activate("factory:command:workforce.assign::"+str(worker.id));await flush()
	check("NPC UI assignment preserves exact actor and original task",F.find(runtime.factory_snapshot().workforce.assignments,str(worker.id),"actor_id").get("candidate_id")==task_id)
	ui.close_panels()
	for index in 100:
		runtime.tick(0.1)
		if F.find(runtime.factory_snapshot().logistics.tasks,task_id).get("phase")=="deliver":break
	var task:=F.find(runtime.factory_snapshot().logistics.tasks,task_id)
	check("real worker picked up one exact timber before UI cancellation",task.get("phase")=="deliver" and runtime.actor(worker.id).pack.get("timber")==1,task)
	ui.open_panel("factory_logistics");await flush()
	activate("factory:command:logistics.cancel:"+task_id);await flush();activate("factory:confirm:submit");await flush()
	task=F.find(runtime.factory_snapshot().logistics.tasks,task_id)
	check("cancelled cargo stays with same actor and has no residual haul intent",task.status=="cargo_held" and task.actor_id==worker.id and runtime.actor(worker.id).pack.get("timber")==1 and runtime.actor(worker.id).intent==null)
	ui.factory_view["retarget:"+task_id]=receiver;ui.queue_refresh();await flush()
	var before:Dictionary=runtime.capture_checkpoint()
	activate("factory:command:logistics.retarget:"+task_id);await flush()
	check("retarget confirmation does not move or duplicate cargo",ui.pages.back().page=="factory_confirm" and Data.json_equal(before,runtime.capture_checkpoint()))
	activate("factory:confirm:cancel");await flush()
	check("retarget cancel retains old destination and cargo",Data.json_equal(before,runtime.capture_checkpoint()))
	activate("factory:command:logistics.retarget:"+task_id);await flush();activate("factory:confirm:submit");await flush()
	task=F.find(runtime.factory_snapshot().logistics.tasks,task_id)
	check("retarget changes only same task destination before real delivery",task.destination_id==receiver and task.source_id==source.id and task.actor_id==worker.id and runtime.actor(worker.id).pack.get("timber")==1 and runtime.stock(receiver).items.is_empty() and runtime.factory_snapshot().logistics.tasks.size()==before.world.extensions["r34:logistics"].tasks.size())
	ui.close_panels()
	for index in 200:
		runtime.tick(0.1)
		if F.find(runtime.factory_snapshot().logistics.tasks,task_id).status=="completed":break
	task=F.find(runtime.factory_snapshot().logistics.tasks,task_id)
	check("same worker actually delivers retargeted cargo once",task.status=="completed" and task.trips==1 and runtime.stock(receiver).items.get("timber")==1 and runtime.actor(worker.id).pack.get("timber",0)==0,task)

func finish() -> void:
	var report := {"scope":"native controls with actual factory service assembly; no formal application/renderer/OS/VA/performance acceptance", "checks":checks,"failed":checks.filter(func(c:Dictionary):return not c.ok).size()}
	var file := FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	if is_instance_valid(host):host.free()
	quit(1 if report.failed else 0)
