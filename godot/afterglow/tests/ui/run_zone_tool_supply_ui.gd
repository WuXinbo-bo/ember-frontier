extends "res://tests/ui/run_zone_supply_consumer_ui.gd"
## Unchanged B pre-supply finite laboratory. Unique tool identity consumer;
## no copied tools, UI stock initialization or autonomous player assignment.

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("exact B before-supply finite input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var zone:=F.find(runtime.zone_records(),"B:supply:farm");var tool:="B:supply:finite-shovel";var source:="B:supply:finite-rack"
	check("unique real shovel starts in finite rack",not zone.is_empty() and runtime.tool(tool).holderId==source)
	if zone.is_empty():return finish(1)
	ui.open_panel("zone_planning");ui.zone_planning.choose_zone(ui,str(zone.id));ui.factory_view["fold:zone:assignments"]=true;ui.queue_refresh();await idle();await idle()
	check("native player checkbox creates precise draft scope",await activate("zone:worker:player") and ui.zone_planning.policy.get("worker_ids",[])==["player"],ui.zone_planning.policy)
	check("native worker policy commits original single player ID",await activate("zone:policy:apply") and runtime.zone_records()[0].policy.get("worker_ids",[])==["player"],ui.zone_planning.receipt)
	await activate("zone:work:refresh");var panel=ui.zone_planning.work_panel
	var offers:Array=panel.candidates.filter(func(row:Dictionary):return row.kind=="supply" and row.get("valid",false) and row.tool_ids.has(tool))
	check("public exact tool candidate carries A safe metadata",offers.size()==1 and offers[0].has("source_location") and offers[0].tools.size()==1 and offers[0].tools[0].id==tool)
	if offers.size()!=1:return finish(1)
	var offer:Dictionary=offers[0];var summary:Dictionary=offer.tools[0]
	check("native menu selects real tool-only supply",await choose("factory:choice:zone_work_candidate:"+str(zone.id),str(offer.id)))
	check("far-source tool identity and actual durability are readable",text_in(ui._body).contains(str(summary.name)) and text_in(ui._body).contains(P.number(summary.durability)) and text_in(ui._body).contains("已搜索容器") and not text_in(ui._body).contains(source) and keyed("zone:work:source").disabled)
	var before:=runtime.capture_checkpoint()
	check("native submit starts original route and retains real tool at source",await activate("zone:work:start") and runtime.actor("player").get("intent",{}).get("kind")=="zone_supply" and runtime.tool(tool).holderId==source and runtime.actor("player").intent.steps.size()>0)
	check("native pause preserves exact in-flight tool reference",await activate("factory:command:held:") and not runtime.actor("player").intent.held and runtime.actor("player").intent.supply.tool_ids==[tool])
	var saved:=runtime.capture_checkpoint();var encoded:=Store.encode(saved);var cold:=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	check("real paused tool route canonical save succeeds",cold.get("ok",false))
	if not cold.get("ok",false) or not await assemble_capture(cold.capture):return finish(1)
	ui.open_panel("zone_planning");ui.zone_planning.choose_zone(ui,str(zone.id));await idle();await idle()
	check("native resume uses original restored held action",await activate("factory:command:held:") and runtime.actor("player").intent.held)
	for step in 500:
		runtime.tick(.1)
		if runtime.actor("player").get("intent")==null:break
	ui.refresh();await idle()
	var entries:=P.entries(P.player_stock(ui.snapshot),ui.snapshot)
	check("real arrival transfers same unique shovel exactly once",runtime.actor("player").intent==null and runtime.tool(tool).holderId=="pack:player" and entries.filter(func(row:Dictionary):return row.reference.get("tool_id")==tool).size()==1)
	check("tool pickup never consumes seed or water stock",Data.json_equal(before.facts.stocks,runtime.capture_checkpoint().facts.stocks))
	var stable:=runtime.capture_checkpoint();var duplicate:Dictionary=ui.execute("zonework.supply",str(zone.id),{"candidate_id":str(offer.id)})
	check("completed tool candidate cannot duplicate identity",not duplicate.get("ok",false) and Data.json_equal(stable,runtime.capture_checkpoint()),duplicate)
	check("exact input file remains unmodified",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
