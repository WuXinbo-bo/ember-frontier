extends "res://tests/ui/run_controls15.gd"
## Native retained trees, relevant DTO fences and queued refresh semantics.
## Mutation probes touch detached display dictionaries, never world authority.
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("current actual village prepares",prepared.get("ok",false))
	if not prepared.get("ok",false):return finish()
	var made:Dictionary=host._assemble(Opening.prepare_opening(prepared.capture,"normal"))
	check("same Native authority assembles",made.get("ok",false))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json"
	host.add_child(router);router.configure(runtime,false,true)
	ui=Mount.mount(host,runtime,router);await flush()
	var original:Dictionary=runtime.capture_checkpoint()
	var bodies:Dictionary={}
	for page:String in ["pause","inventory","factory_catalog"]:
		ui.close_panels();ui.open_panel(page);await flush()
		bodies[page]=ui._body.get_instance_id()
		ui.close_panels();ui.open_panel(page);await flush()
		check("unchanged reopen retains native tree "+page,ui._body.get_instance_id()==bodies[page] and ui._panel_view_hits>0)
		var serial:int=ui._panel_render_serial
		ui.queue_refresh();ui.refresh();await flush()
		check("direct refresh consumes older notification without tree rebuild "+page,ui._panel_render_serial==serial and not ui._refresh_queued)
	ui.close_panels();ui.open_panel("pause");await flush()
	check("cross-route cache restores original native pause tree",ui._body.get_instance_id()==bodies.pause)
	ui.close_panels();ui.open_panel("inventory");await flush()
	var stock_snapshot:Dictionary=ui.snapshot.duplicate(true)
	var baseline:int=ui._visible_panel_signature()
	var player:Dictionary=ui.snapshot.player
	player.stamina=float(player.get("stamina",100))-0.1
	check("factory inventory ignores undisplayed stamina",ui._visible_panel_signature()==baseline)
	player.x=float(player.get("x",0))+1
	check("player contact movement invalidates inventory",ui._visible_panel_signature()!=baseline)
	ui.snapshot=stock_snapshot.duplicate(true);player=ui.snapshot.player;player.hp=0
	check("player death invalidates inventory",ui._visible_panel_signature()!=baseline)
	ui.snapshot=stock_snapshot.duplicate(true);ui.snapshot.stocks.append({"id":"detached-probe","items":{"wood":2},"reserved":{"wood":1}})
	check("stock quantity and reservation DTO invalidates inventory",ui._visible_panel_signature()!=baseline)
	ui.snapshot=stock_snapshot.duplicate(true);ui.snapshot.tools.append({"id":"detached-probe","durability":1})
	check("tool durability DTO invalidates inventory",ui._visible_panel_signature()!=baseline)
	ui.snapshot=stock_snapshot.duplicate(true);ui.snapshot.catalog["detached-probe"]=true
	check("inventory catalogue DTO invalidates inventory",ui._visible_panel_signature()!=baseline)
	ui.snapshot=stock_snapshot;ui.close_panels();ui.open_panel("factory_catalog");await flush()
	var search:LineEdit=keyed("factory:search:catalog_search")
	check("retained catalogue has native search",search!=null)
	if search!=null:
		search.text="unmatched-retained-view-probe";search.text_changed.emit(search.text);await flush()
		check("search invalidates native catalogue contents",not text_in(ui._body).contains("下一页") and ui.factory_view.catalog_search=="unmatched-retained-view-probe")
		var again:LineEdit=keyed("factory:search:catalog_search")
		again.text="";again.text_changed.emit("");await flush()
		check("clear search restores full catalogue pagination",keyed("factory:catalog:next")!=null)
	ui.close_panels();ui.open_panel("inventory");await flush()
	var nav:Button=keyed("factory:nav:factory_inventory",ui)
	var navigation:Container=ui._planning_navigation if ui._planning_navigation.visible else ui._panel_navigation
	var first_id:int=navigation.get_child(0).get_instance_id()
	ui.open_panel("factory_people");await flush()
	check("ordinary management pages reuse native navigation",navigation.get_child(0).get_instance_id()==first_id)
	var people:Button=keyed("factory:nav:factory_people",ui)
	check("retained navigation updates selected page",people!=null and people.button_pressed and people.tooltip_text=="当前页面")
	ui.close_panels();ui.open_panel("inventory");await flush()
	var original_body:int=ui._body.get_instance_id();var original_children:int=ui._body.get_child(0).get_instance_id()
	ui.set_text_scale(1.5);await flush()
	check("text scale rebuilds native content",ui._body.get_instance_id()==original_body and ui._body.get_child(0).get_instance_id()!=original_children)
	var resized_child:int=ui._body.get_child(0).get_instance_id()
	root.size=Vector2i(1000,700);root.content_scale_size=root.size;await flush();ui.refresh();await flush()
	check("viewport resize rebuilds native content",ui._body.get_child(0).get_instance_id()!=resized_child)
	check("retained trees and DTO probes preserve exact authority",Data.json_equal(original,runtime.capture_checkpoint()))
	ui.configure(runtime,router);await flush()
	check("reconfigure clears detached tree ownership",ui._panel_views.is_empty())
	finish()
