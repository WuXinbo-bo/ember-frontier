extends "res://tests/ui/run_zone_planning_ui.gd"
## Exact E actual12 joined-home continuation. Public summary and full member
## queries, native Controls, real revisions. No fake candidate provider.

func run() -> void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("unchanged real new12 joined capture decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var before:Dictionary=runtime.capture_checkpoint()
	var summary:Dictionary=runtime.factory_ui_snapshot("player")
	var full:Dictionary=runtime.factory_snapshot("player")
	check("HUD consumes explicit real summary without invented empty work",ui.factory.get("workforce",{}).get("candidates_included")==false and summary.workforce.get("candidates_state")=="not_requested" and summary.workforce.people.all(func(person:Dictionary):return not person.has("candidates") and not person.has("decision")))
	for field:String in ["modules","production","logistics","water","definitions","alerts","alert_history","alert_summary","map","scope"]:
		check("light UI query retains complete original public field "+field,Data.json_equal(summary.get(field),full.get(field)))
	var members:Array=F.rows(summary,"workforce","members").filter(func(member:Dictionary):return member.actor_id!="player")
	check("actual input has two joined original companions",members.size()==2)
	ui.open_panel("factory_people");await idle();await idle()
	for member:Dictionary in members:
		var id:=str(member.actor_id);var person:Dictionary=ui.workforce_person(id)
		var expected:Dictionary=F.find(runtime.workforce_snapshot(id).get("people",[]),id,"actor_id")
		check("visible member gets complete current candidates and decision "+id,person.has("candidates") and person.has("decision") and Data.json_equal(person,expected))
		if person.get("candidates",[]).any(func(row:Dictionary):return row.get("valid",false)):
			check("real eligible member work stays operable "+id,keyed("factory:choice:workforce_candidate:"+id)!=null)
	var reads: int=ui.workforce_detail_reads
	for pass_ in 3:
		ui.refresh();await idle()
		for member:Dictionary in members:ui.workforce_person(str(member.actor_id))
	check("same exact authority key reuses full member display queries",ui.workforce_detail_reads==reads and reads==members.size(),{"reads":reads,"after":ui.workforce_detail_reads})
	if not members.is_empty():
		await activate("factory:workforce:refresh:"+str(members[0].actor_id))
		check("native explicit refresh invalidates only requested member",ui.workforce_detail_reads==reads+1,{"before":reads,"after":ui.workforce_detail_reads})
	check("summary and member display queries never mutate authority",Data.json_equal(before,runtime.capture_checkpoint()))
	ui.close_panels();runtime.tick(.1);ui.refresh();await idle()
	ui.open_panel("factory_people");await idle();await idle()
	check("real revision refreshes every currently displayed member",ui.workforce_detail_reads>=reads+1+members.size(),ui.workforce_detail_reads)
	ui.close_panels();ui.open_panel("zone_planning");await idle();await idle()
	region=str(runtime.actor("player").regionId);start_cell=find_patch()
	check("new12 actual loaded land can be selected",not start_cell.is_empty())
	if not start_cell.is_empty():
		await draft(start_cell,offset(start_cell,2,2));await activate("zone:submit")
		var serial: int=ui._panel_render_serial;var costs:Array=[]
		for step in 3:
			runtime.tick(.1);var start:=Time.get_ticks_usec();ui.refresh();costs.append(Time.get_ticks_usec()-start);await idle()
		check("selected-zone idle STEPs keep summary and native content stable",ui.factory.workforce.get("candidates_included")==false and ui._panel_render_serial==serial,{"render_before":serial,"render_after":ui._panel_render_serial,"refresh_usec":costs})
	ui.close_panels()
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5)
		ui.open_panel("factory");await idle();await idle()
		var actions: Array=ui._body.find_children("*","Button",true,false).filter(func(node:Button):return str(node.get_meta("ui_focus_key","")).begins_with("factory:module:"))
		check("facility actions retain native text width "+str(viewport),not actions.is_empty() and actions.all(func(node:Button):return node.size.x>=node.get_theme_font("font").get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x and root.get_visible_rect().encloses(node.get_global_rect())),actions.map(func(node:Button):return {"text":node.text,"rect":str(node.get_global_rect())}))
		check("facility window fits current logical viewport "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()))
	check("actual new12 input bytes remain unchanged",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
