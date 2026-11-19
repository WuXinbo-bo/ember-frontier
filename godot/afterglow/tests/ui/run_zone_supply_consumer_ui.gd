extends "res://tests/ui/run_architecture_catalog_ui.gd"
## B's unchanged declared finite rack/flat-land capture after its original
## worker-denial check. Restore policy through real Controls, never edit facts.

func activate(key_:String)->bool:
	var node:=keyed(key_) as Button
	if node==null or node.disabled:
		trace.append({"key":key_,"found":node!=null,"disabled":node.disabled if node!=null else null,"tooltip":node.tooltip_text if node!=null else ""});return false
	ui._scroll.ensure_control_visible(node);await idle()
	trace.append({"key":key_,"rect":str(node.get_global_rect()),"dialog":str(ui._dialog.get_global_rect()),"scroll":ui._scroll.scroll_vertical})
	if not root.get_visible_rect().encloses(node.get_global_rect()):return false
	await click(node.get_global_rect().get_center());await idle();return true

func choose_source(source:String)->bool:
	return await choose("zone:stock:source_stock_id",source) and ui.zone_planning.policy.get("source_stock_id")==source

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("B finite supply laboratory decodes unchanged",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var zones:Array=runtime.zone_records();var zone:=F.find(zones,"B:supply:farm")
	check("owner laboratory has real restricted farm and finite source",not zone.is_empty() and zone.policy.worker_ids==["village-resident"] and runtime.stock("B:supply:finite-rack").items.get("r34:raw_water")==2)
	if zone.is_empty():return finish(1)
	var id:=str(zone.id);var source:="B:supply:finite-rack";var panel=ui.zone_planning.work_panel
	ui.open_panel("zone_planning");ui.zone_planning.choose_zone(ui,id);ui.factory_view["fold:zone:assignments"]=true;ui.queue_refresh();await idle();await idle()
	var before:=runtime.capture_checkpoint()
	check("unknown original worker restriction is preserved and honestly labelled",ui.zone_planning.policy.worker_ids==["village-resident"] and text_in(ui._body).contains("保留原有未在当前同行名单") and keyed("zone:worker:player") is CheckBox)
	check("native unlimited-workers action edits only draft",await activate("zone:workers:all") and ui.zone_planning.policy.get("worker_ids",[]).is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	check("far ordinary stock is not invented as a visible source option",keyed("zone:stock:source_stock_id") is OptionButton and keyed("zone:stock:source_stock_id").item_count==1 and Data.json_equal(before,runtime.capture_checkpoint()))
	check("native policy apply restores actual eligibility without adding inventory",await activate("zone:policy:apply") and runtime.zone_records()[0].policy.get("worker_ids",[]).is_empty() and Data.json_equal(before.facts.stocks,runtime.capture_checkpoint().facts.stocks),{"policy":runtime.zone_records()[0].policy,"draft":ui.zone_planning.policy,"receipt":ui.zone_planning.receipt})
	panel=ui.zone_planning.work_panel
	check("native refresh finds real raw-water supply offer",await activate("zone:work:refresh"))
	var offers:Array=panel.candidates.filter(func(row:Dictionary):return row.kind=="supply" and row.get("valid",false) and row.source_id==source and row.items.get("r34:raw_water")==1)
	check("candidate comes from public original provider and exact command",offers.size()==1 and offers[0].command.kind=="zonework.supply" and offers[0].command.target_id==id)
	if offers.size()!=1:return finish(1)
	var offer:Dictionary=offers[0]
	check("native candidate menu selects precise supply identity",await choose("factory:choice:zone_work_candidate:"+id,str(offer.id)))
	check("source quantities and truthful before-arrival feedback render",text_in(ui._body).contains("前置取料") and text_in(ui._body).contains("原水") and text_in(ui._body).contains("随身背包") and keyed("zone:work:start").text=="前往来源取料" and not keyed("zone:work:start").disabled)
	var stable:=runtime.capture_checkpoint()
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		check("real supply controls fit native viewport "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"dialog":str(ui._dialog.get_global_rect()),"body":ui._body.get_combined_minimum_size(),"scroll":ui._scroll.size.x})
	check("view-source honestly disables while ordinary source is outside public near view",keyed("zone:work:source").disabled and ui.is_zone_planning() and Data.json_equal(stable,runtime.capture_checkpoint()))
	# Explicit malformed public DTO rendering probe only; no authority mutation.
	panel.candidates=[offer.duplicate(true)];panel.candidates[0].command.payload={"candidate_id":"wrong"};panel.chosen=str(offer.id);panel._serial+=1;ui.queue_refresh();await idle()
	check("mismatched candidate payload disables submission atomically",keyed("zone:work:start").disabled and Data.json_equal(stable,runtime.capture_checkpoint()))
	panel.load_candidates(ui);await idle();await choose("factory:choice:zone_work_candidate:"+id,str(offer.id))
	check("native supply starts original actions route with no instant grant",await activate("zone:work:start") and runtime.actor("player").get("intent",{}).get("kind")=="zone_supply" and runtime.actor("player").pack.get("r34:raw_water",0)==0 and runtime.stock(source).items.get("r34:raw_water")==2)
	check("in-flight UI distinguishes real source stock from received cargo",text_in(ui._body).contains("物资仍在实际来源") and keyed("factory:command:held:")!=null)
	check("native pause applies original held control",await activate("factory:command:held:") and runtime.actor("player").intent.held==false)
	var paused:=runtime.capture_checkpoint();var at:=runtime.actor("player").duplicate(true)
	for step in 4:runtime.tick(.1)
	check("paused supply does not move or transfer",runtime.actor("player").x==at.x and runtime.actor("player").z==at.z and runtime.stock(source).items.get("r34:raw_water")==2)
	var encoded:=Store.encode(runtime.capture_checkpoint());var cold:=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	check("paused supply encodes through actual original codec",cold.get("ok",false))
	if not cold.get("ok",false) or not await assemble_capture(cold.capture):return finish(1)
	ui.open_panel("zone_planning");ui.zone_planning.choose_zone(ui,id);await idle();await idle()
	check("cold real route remains paused and UI offers correct continuation",runtime.actor("player").intent.kind=="zone_supply" and not runtime.actor("player").intent.held and keyed("factory:command:held:").text=="接续取料")
	check("native cancel asks consequence before touching route",await activate("factory:command:cancel:") and ui.pages.back().page=="factory_confirm" and runtime.actor("player").intent!=null)
	check("native cancel releases only pending pickup and keeps finite water",await activate("factory:confirm:submit") and runtime.actor("player").intent==null and runtime.stock(source).items.get("r34:raw_water")==2 and runtime.actor("player").pack.get("r34:raw_water",0)==0)
	check("cancel returns to live original planning",ui.is_zone_planning() and not router.state().pause_reasons.modal)
	await activate("zone:work:refresh");await choose("factory:choice:zone_work_candidate:"+id,str(offer.id))
	check("original public candidate can be retried after safe cancellation",await activate("zone:work:start") and runtime.actor("player").intent!=null)
	for step in 500:
		runtime.tick(.1)
		if runtime.actor("player").get("intent")==null:break
	ui.refresh();await idle()
	check("actual walking and arrival transfer exactly one finite raw water",runtime.actor("player").intent==null and runtime.actor("player").pack.get("r34:raw_water",0)==1 and runtime.stock(source).items.get("r34:raw_water")==1,{"actor":runtime.actor("player"),"stock":runtime.stock(source)})
	ui.factory_view["fold:zone:assignments"]=true;ui.queue_refresh();await idle()
	check("native source selection exposes exact searched stock only at real arrival",await choose_source(source))
	ui.open_panel("factory_inventory",source);await idle();await idle();var after_pickup:=runtime.capture_checkpoint()
	check("real near-source inventory uses original stock identity",ui.pages.back().subject==source and text_in(ui._body).contains("当前容器") and not text_in(ui._body).contains("尚未搜索"))
	await key(KEY_W);await key(KEY_E)
	check("real source inventory consumes movement and E without transfer",Data.json_equal(after_pickup,runtime.capture_checkpoint()))
	await key(KEY_ESCAPE);await idle()
	check("Esc returns to original live planning",ui.is_zone_planning() and not router.state().pause_reasons.modal)
	var ready:=runtime.capture_checkpoint();var rejected:Dictionary=ui.execute("zonework.supply",id,{"candidate_id":str(offer.id)})
	check("already-supplied candidate cannot duplicate or lose water",not rejected.get("ok",false) and Data.json_equal(ready,runtime.capture_checkpoint()),rejected)
	check("original owner input remains byte exact",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
