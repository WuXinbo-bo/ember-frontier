extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Actual B paid-v1 home continuation. Proposals/disabled state and atomic
## refusals only; no injected cost, money, v2 building, floor or inventory.

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("owner sealed paid-home input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var homes:Array=F.rows(ui.factory,"modules","instances").filter(func(row:Dictionary):return row.get("player_built",false) and F.definition(ui.factory,str(row.definition_id)).get("shape")=="home")
	check("input contains actually player-paid building",not homes.is_empty())
	if homes.is_empty():return finish(1)
	var home:Dictionary=homes[0];var before:=runtime.capture_checkpoint()
	ui.factory_view["fold:upgrade:"+str(home.id)]=true
	ui.open_panel("factory_module",str(home.id));await idle();await idle()
	var proposals:Array=home.get("upgrade_proposals",[])
	check("actual old paid identity remains and publishes proposal",not home.definition_id.ends_with(".mechanism-v2") and not proposals.is_empty(),home.get("upgrade_proposals"))
	check("actual upgrade explanation separates paid delta and labor",text_in(ui._body).contains("实际需补材料") and text_in(ui._body).contains("有效劳动"),text_in(ui._body))
	for proposal:Dictionary in proposals:
		var keys:Array=[]
		for node:Node in ui._body.find_children("*","Button",true,false):
			if str(node.get_meta("ui_focus_key","")).begins_with("factory:command:module.upgrade:"+str(home.id)):
				keys.append(node.get_meta("ui_focus_key"))
		check("proposal controls have exact target-specific focus key",keys.size()<=proposals.size())
		var payload:Dictionary={"definition_id":str(proposal.definition_id),"source_id":"pack:player","tool_id":"missing:ui-test"}
		var rejection:Dictionary=ui.execute("module.upgrade",str(home.id),payload)
		check("invalid real tool fails without payment or shape mutation",not rejection.get("ok",false) and Data.json_equal(before,runtime.capture_checkpoint()),rejection)
		if rejection.get("ok",false):return finish(1) # Keep one real red; no cascading stale-baseline claims.
	var old_policy:Dictionary=ui.execute("module.stock_policy",str(home.id),{"buffer_id":"supplies","policy":{"filter":[],"reserve":{},"target":{}}})
	check("legacy definition cannot gain v2 policy by UI command",not old_policy.get("ok",false) and Data.json_equal(before,runtime.capture_checkpoint()),old_policy)
	var old_order:Dictionary=ui.execute("module.recipe.configure",str(home.id),{"recipe_id":"r34:saw_timber_v2","mode":"quantity","quantity":1,"source_id":"pack:player","output_id":"pack:player"})
	check("legacy definition cannot gain v2 recipe by UI command",not old_order.get("ok",false) and Data.json_equal(before,runtime.capture_checkpoint()),old_order)
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		if ui.pages.is_empty():ui.open_panel("factory_module",str(home.id))
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		check("real upgrade sidebar keeps scene and fits "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._dialog.size.x<=viewport.x*.52+1 and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"dialog":str(ui._dialog.get_global_rect()),"body":ui._body.get_combined_minimum_size().x,"scroll":ui._scroll.size.x})
		var actor:=runtime.actor("player");await key(KEY_W)
		check("upgrade modal consumes world movement "+str(viewport),not ui.pages.is_empty() and Data.json_equal(actor,runtime.actor("player")) and Data.json_equal(before,runtime.capture_checkpoint()))
		await key(KEY_E)
		check("E closes object sidebar without starting world interaction "+str(viewport),ui.pages.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	ui.open_panel("factory_module",str(home.id));await idle()
	await key(KEY_ESCAPE)
	check("Esc returns to original scene without starting upgrade",ui.pages.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	check("owner input remains byte exact",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
