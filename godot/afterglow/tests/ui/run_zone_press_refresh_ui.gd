extends "res://tests/ui/run_zone_planning_ui.gd"
## A26 OS regression: native press -> true .1s authority STEP -> release.
## Actual unchanged QA save and observed loaded terrain; no emit pressed.

func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	var original := FileAccess.get_file_as_string(args[1]); var decoded := Store.decode(original)
	check("unchanged owner QA capture decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	region=str(runtime.actor("player").regionId)
	ui.open_panel("zone_planning");await idle();await idle()
	var buttons:Array=[]
	for id:String in ["create","append","erase"]:buttons.append(keyed("zone:tool:"+id))
	check("mode controls are three equal short buttons without interleaved reason",buttons.all(func(node:Button):return node!=null and node.size.y<60 and absf(node.size.x-buttons[0].size.x)<2) and buttons[0].get_parent().get_child_count()==3,buttons.map(func(node:Button):return str(node.get_global_rect())))
	start_cell=find_patch();check("observed loaded real land permits preview",not start_cell.is_empty())
	if start_cell.is_empty():return finish(1)
	await draft(start_cell,offset(start_cell,2,2))
	check("real authority preview is ready before confirmation",ui.zone_planning.preview.get("ok",false) and not ui.zone_planning.preview.cells.is_empty())
	var action:=keyed("zone:submit") as Button
	check("confirmation is pinned outside scrolling content",action!=null and not ui._scroll.is_ancestor_of(action) and root.get_visible_rect().encloses(action.get_global_rect()),str(action.get_global_rect()) if action!=null else "missing")
	if action==null:return finish(1)
	if ui._scroll.is_ancestor_of(action):ui._scroll.ensure_control_visible(action)
	await idle()
	var action_id:=action.get_instance_id();var before_count:=runtime.zone_records().size()
	await motion(action.get_global_rect().get_center());await button(true)
	check("native button has actual pending mouse press",is_instance_valid(action) and action.is_pressed())
	var before_step:Dictionary=runtime.capture_checkpoint();runtime.tick(.1);ui.refresh();await idle()
	var after_step:Dictionary=runtime.capture_checkpoint()
	check("original true STEP advances authority while pointer is held",not Data.json_equal(before_step,after_step))
	check("same pressed native control survives STEP and page refresh",is_instance_valid(action) and keyed("zone:submit")!=null and keyed("zone:submit").get_instance_id()==action_id)
	await button(false);await idle()
	check("native release commits exactly one original zone",runtime.zone_records().size()==before_count+1,ui.zone_planning.receipt)
	check("successful release selects exact new zone and clears draft",not ui.zone_planning.selected_id.is_empty() and ui.zone_planning.selected().get("id")==ui.zone_planning.selected_id and ui.zone_planning.bounds.is_empty() and ui.zone_planning.preview.is_empty(),{"selected":ui.zone_planning.selected_id,"bounds":ui.zone_planning.bounds,"receipt":ui.zone_planning.receipt})
	var serial: int=ui._panel_render_serial;var clock: float=runtime.clock();var times:Array=[]
	var companion_ids: Array=ui._companions.find_children("*","Button",true,false).map(func(node:Button):return node.get_instance_id())
	for step in 10:
		runtime.tick(.1)
		var start:=Time.get_ticks_usec();ui.refresh();times.append(Time.get_ticks_usec()-start)
		await idle()
	check("ten real authority STEPs do not rebuild idle zone contents",ui._panel_render_serial==serial,{"before":serial,"after":ui._panel_render_serial,"refresh_usec":times})
	check("world clock remains live during incremental planning",runtime.clock()>=clock+.99)
	check("existing HUD companion controls survive live actor changes",companion_ids==ui._companions.find_children("*","Button",true,false).map(func(node:Button):return node.get_instance_id()),{"initial_controls":companion_ids.size()})
	for viewport: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		await draft(start_cell,start_cell)
		var pinned:=keyed("zone:submit") as Button;var rect:=pinned.get_global_rect()
		ui._scroll.scroll_vertical=100000;await idle()
		check("native footer counts and confirmation stay pinned "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and root.get_visible_rect().encloses(rect) and rect==pinned.get_global_rect() and not ui._scroll.is_ancestor_of(pinned) and keyed("zone:preview:counts")!=null,{"dialog":str(ui._dialog.get_global_rect()),"confirm":str(rect)})
		await key(KEY_ESCAPE)
		check("first Esc retracts pinned draft and retains original live editor "+str(viewport),ui.is_zone_planning() and ui.zone_planning.bounds.is_empty())
	check("original QA input bytes remain unchanged",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
