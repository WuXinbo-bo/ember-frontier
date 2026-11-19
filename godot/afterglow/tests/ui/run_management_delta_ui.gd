extends "res://tests/ui/run_service_access_ui.gd"
## Post23 real public capability consumption; one explicitly reduced public
## logistics projection checks the empty-receiver view, never world facts.
const P = preload("res://scripts/ui/ui_projection.gd")
const Ops = preload("res://scripts/ui/factory_operations.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const Identity = preload("res://scripts/ui/ui_identity.gd")

func press(key: String) -> bool:
	var button := keyed(key) as Button
	check("native action available " + key, button != null and not button.disabled)
	if button == null or button.disabled: return false
	button.pressed.emit(); await flush(); return true

func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800); root.content_scale_size = root.size
	host = TestClient.new(); root.add_child(host)
	var profiles: Dictionary = Assembly.generation_profiles()
	var normal: Dictionary = Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("current formal content prepares", normal.get("ok",false))
	if not normal.get("ok",false) or not await mount_capture(normal.capture): return finish()
	var before:Dictionary = runtime.capture_checkpoint()
	var home := F.find(F.rows(ui.factory,"modules","instances"),"r34:generated:RH-HOME:home")
	check("real home is publicly disclosed", not home.is_empty())
	if not home.is_empty():
		ui.open_panel("module",str(home.id)); await flush()
		check("home shows care and own object title without machine schema", text_in(ui._body).contains("自身照料与同伴") and not text_in(ui._body).contains("原料 → 加工 → 成品") and not text_in(ui._body).contains("尚无在制批次") and ui._title.text == home.name)
		if await press("factory:handbook:link:module:"+str(home.id)):
			check("home stable definition link does not masquerade as machine",ui.handbook.selection.id == "module:"+str(home.definition_id))
			ui.cancel_ui(); await flush()
			check("home definition Esc restores exact object",ui.world_view_selection()=={"kind":"module","id":home.id})
	ui.close_panels();ui.open_panel("factory_catalog");await flush()
	var definitions := F.rows(ui.factory,"modules","definitions")
	check("all twelve published module geometry thumbnails map accurately", definitions.size()==12 and definitions.all(func(d:Dictionary): return Images.module_texture(d) != null), definitions.map(func(d:Dictionary):return d.id))
	for id: String in ["r34.module.warehouse","r34.module.hand_workshop","r34.module.home_service","r34.module.supply_rear_v3"]:
		check("catalog real shape and handbooks retained "+id,Images.module_texture(F.definition(ui.factory,id)) != null and keyed("factory:handbook:link:catalog:"+id)!=null)
	ui.close_panels();ui.open_panel("factory_inventory");await flush()
	var grid: GridContainer
	for node: Node in ui._body.find_children("*","GridContainer",true,false):
		if not node.get_children().is_empty() and node.get_child(0).get("slot") is Dictionary: grid=node;break
	check("single pack centers actual grid and binds original pack",grid != null and grid.size_flags_horizontal == Control.SIZE_SHRINK_CENTER and grid.get_child(0).slot.stock_id == P.player_stock(ui.snapshot).id)
	ui.close_panels();ui.open_panel("factory_people");await flush()
	check("player appears once in people page",text_in(ui._body).count(str(P.player(ui.snapshot).name)+"\n")==1)
	check("known places shown without internal region codes",not text_in(ui._body).contains("RH-HOME") and not text_in(ui._body).contains("RH-VILLAGE"))
	check("arbitration codes translated without adding assignments",not text_in(ui._body).contains("no_eligible_work") and Identity.decision_text({"reason":"no_eligible_work"})=="当前没有可执行岗位")
	check("needs precision separate from material units",P.stat_number(89.631)=="90" and P.number(0.125)=="0.125")
	check("missing medicine does not claim all supplies exhausted",P.action_feedback({"ok":false,"code":"NO_ITEM","reason":"随身物品已经耗尽"},"medicine").contains("药品") and not P.action_feedback({"ok":false,"code":"NO_ITEM"},"medicine").contains("全部"))
	for actor:Dictionary in P.records(ui.snapshot.get("actors",[])):
		if actor.id in ["player","village-resident","repair-resident"]:check("permanent appearance portrait "+str(actor.id),Identity.portrait(actor)!=null)
	ui.close_panels();ui.open_panel("factory_alerts");await flush()
	var chooser := keyed("factory:map:region") as OptionButton
	check("map translates visible labels preserving exact region metadata",chooser!=null and chooser.item_count>0 and not chooser.get_item_text(0).begins_with("RH-") and not str(chooser.get_item_metadata(0)).is_empty())
	check("management reads do not alter one authority",Data.json_equal(before,runtime.capture_checkpoint()))
	if args.size()>1:await actual_inventory_and_receiver(args[1])
	for viewport in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await flush()
		for page:String in ["factory_inventory","factory_people","factory_logistics","factory_alerts","factory_handbook"]:
			ui.close_panels();ui.open_panel(page);await flush()
			var rect:Rect2=ui._dialog.get_rect()
			check("management window fits "+page+" "+str(viewport),rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=viewport.x and rect.end.y<=viewport.y,rect)
	finish()

func actual_inventory_and_receiver(path:String)->void:
	var original:=FileAccess.get_file_as_string(path);var decoded:=Store.decode(original)
	check("sealed real normal economy input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false) or not await mount_capture(decoded.capture):return
	var before:Dictionary=runtime.capture_checkpoint()
	var targets:Array=[]
	for module:Dictionary in F.rows(ui.factory,"modules","instances"):
		for ref:Dictionary in F.known_stocks(ui.factory,ui.snapshot,module):
			if not ref.stock.is_empty() and ref.stock.get("searched",false) and not ref.stock.get("display_only",false):targets.append({"module":module,"ref":ref})
	check("actual searched source available for paired native inventory",not targets.is_empty())
	if targets.is_empty():return
	var target:Dictionary=targets[0];var id:=str(target.ref.stock_id)
	ui.open_panel("factory_inventory",id);await flush()
	var refs:Array=[]
	for node:Node in ui._body.find_children("*","Button",true,false):
		var slot:Variant=node.get("slot")
		if slot is Dictionary and slot.get("kind")=="inventory" and not refs.has(slot.stock_id):refs.append(slot.stock_id)
	check("paired inventory preserves two actual unique stock identities",refs.size()==2 and refs.has(id) and refs.has(P.player_stock(ui.snapshot).id),refs)
	# Reduced display-only DTO keeps one actual disclosed source. No fabricated
	# destination, quantities or command authority; original Runtime unchanged.
	var display:Dictionary=ui.factory.duplicate(true)
	var selected:Dictionary=target.module.duplicate(true);selected.stock_refs={target.ref.buffer_id:id}
	display.modules.instances=[selected]
	ui.factory=display
	for child:Node in ui._body.get_children():ui._body.remove_child(child);child.free()
	Ops.logistics_form(ui,ui._body);await flush()
	check("single known source gives specific receiver empty state",text_in(ui._body).contains("尚无接收库存") and keyed("factory:logistics:find-receiver")!=null and keyed("factory:logistics:build-receiver")!=null)
	check("no empty destination amount or create task controls",keyed("factory:choice:logistics_destination")==null and keyed("factory:command:logistics.create:")==null)
	check("empty state neither grants destination nor mutates original facts",Data.json_equal(before,runtime.capture_checkpoint()))
	ui.refresh();await flush()
	check("original input byte-identical",FileAccess.get_file_as_string(path)==original)
