extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Actual B finite paid-home lab, public module.stock_policy via native UI.
## No material/bed/stock initialization or rule changes by this consumer.

func enter_number(key_:String,value:String)->bool:
	var input:=keyed(key_) as LineEdit
	if input==null:return false
	ui._scroll.ensure_control_visible(input);await idle();await click(input.get_global_rect().get_center())
	input.select_all() # Native selection setup only; the following edit is input.
	for character:String in value:
		var event:=InputEventKey.new();event.unicode=character.unicode_at(0);event.pressed=true
		root.push_input(event,true)
		event=InputEventKey.new();event.unicode=character.unicode_at(0);event.pressed=false
		root.push_input(event,true)
	await key(KEY_ENTER);await idle();return true

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("unchanged paid-home lab decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var modules:=F.rows(ui.factory,"modules","instances").filter(func(module:Dictionary):return not module.get("stock_policies",[]).is_empty())
	check("actual paid home supplies public editable policy",not modules.is_empty())
	if modules.is_empty():return finish(1)
	var module:Dictionary=modules[0];var buffer:Dictionary=module.stock_policies[0];var bid:=str(buffer.buffer_id)
	var items:Array=buffer.items;var first:=str(items[0].item_id);var second:=str(items[1].item_id)
	var prefix:="stock-draft:"+str(module.id)+":"+bid;var button_key:="mechanism:policy:"+str(module.id)+":"+bid
	ui.factory_view["fold:stock-policy:"+str(module.id)]=true
	ui.open_panel("factory_module",str(module.id));await idle();await idle()
	var before:=runtime.capture_checkpoint()
	check("native policy chooses exact first material",await choose("factory:choice:"+prefix+":item",first))
	check("native reserve edit enters draft",await enter_number(prefix+":reserve:"+first+":value","1") and ui.factory_view[prefix].reserve.get(first)==1)
	check("native target edit enters same draft",await enter_number(prefix+":target:"+first+":value","2") and ui.factory_view[prefix].target.get(first)==2)
	check("switching material preserves unpublished draft",await choose("factory:choice:"+prefix+":item",second) and ui.factory_view[prefix].reserve.get(first)==1 and Data.json_equal(before,runtime.capture_checkpoint()))
	check("second material edits same full-buffer draft",await enter_number(prefix+":reserve:"+second+":value","1") and ui.factory_view[prefix].reserve.get(first)==1 and ui.factory_view[prefix].reserve.get(second)==1)
	check("native apply submits exact draft",await activate(button_key))
	var actual:=F.instance(runtime.factory_snapshot("player"),str(module.id));var applied:Dictionary=F.find(F.dictionaries(actual.stock_policies),bid,"buffer_id").policy
	var after:=runtime.capture_checkpoint()
	check("authority holds both reserves and target without synthesizing goods",applied.reserve.get(first)==1 and applied.reserve.get(second)==1 and applied.target.get(first)==2 and Data.json_equal(before.facts.actors,after.facts.actors) and Data.json_equal(before.facts.stocks,after.facts.stocks) and before.facts.time==after.facts.time,{"policy":applied,"changed_fact_fields":before.facts.keys().filter(func(field):return not Data.json_equal(before.facts[field],after.facts.get(field)))})
	check("policy draft resets to actual authority after receipt",ui.factory_view[prefix]==applied)
	var saved:=runtime.capture_checkpoint();var encoded:=Store.encode(saved);var cold:=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	check("policy canonical save encodes through original codec",cold.get("ok",false))
	if cold.get("ok",false) and await assemble_capture(cold.capture):
		actual=F.instance(runtime.factory_snapshot("player"),str(module.id));check("cold authority preserves full applied policy",F.find(F.dictionaries(actual.stock_policies),bid,"buffer_id").policy==applied)
		ui.factory_view["fold:stock-policy:"+str(module.id)]=true;ui.open_panel("factory_module",str(module.id));await idle();await idle()
		await choose("factory:choice:"+prefix+":item",first);await enter_number(prefix+":reserve:"+first+":value","2")
		check("discard returns local editing to authoritative values",await activate("mechanism:policy:discard:"+str(module.id)+":"+bid) and ui.factory_view[prefix].reserve.get(first)==1 and Data.json_equal(saved.facts,runtime.capture_checkpoint().facts))
		for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
			root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
			check("native policy sidebar fits "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"dialog":str(ui._dialog.get_global_rect()),"min":ui._body.get_combined_minimum_size(),"scroll":ui._scroll.size.x})
	var before_bad:=runtime.capture_checkpoint();var invalid:Dictionary=ui.execute("module.stock_policy",str(module.id),{"buffer_id":bid,"policy":{"filter":["missing:material"],"reserve":{},"target":{}}})
	check("invalid policy is rejected with no stock loss or partial change",not invalid.get("ok",false) and Data.json_equal(before_bad,runtime.capture_checkpoint()) and not ui._notice.text.is_empty(),invalid)
	check("original owner laboratory stays byte exact",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
