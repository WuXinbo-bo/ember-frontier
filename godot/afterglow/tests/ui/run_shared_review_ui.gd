extends "res://tests/ui/run_service_access_ui.gd"
## Continue E's sealed actual two-delivery save. UI never writes people,
## bodies, memories, goods, positions, event IDs or rewards into the world.
const Stories = preload("res://scripts/ui/factory_stories.gd")
var sequence := 0

func send(kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"ui:actual-review:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})

func story()->Dictionary:
	return F.find(F.rows(runtime.factory_snapshot(),"workforce","stories"),"ST02")

func action(kind:String,id:String)->Button:
	for node in ui._body.find_children("*","Button",true,false):
		if str(node.get_meta("ui_focus_key","")).begins_with(kind+":"+id+":"):return node
	return null

func open_person(id:String)->void:
	ui.close_panels();Stories.open_person(ui,id);await flush()

func contact(id:String)->bool:
	ui.close_panels()
	for attempt in 18:
		if runtime.availability({"kind":"talk","actor_id":"player","target_id":id}).get("ok",false):return true
		var at:Dictionary=G.location(runtime.actor(id))
		var offset:=Vector2.RIGHT.rotated(float(attempt%8)*PI/4)*0.9
		at.x+=offset.x;at.z+=offset.y
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if not feet.is_empty():
			var receipt:=send("walk","",{},feet)
			if receipt.get("ok",false):progress()
	return runtime.availability({"kind":"talk","actor_id":"player","target_id":id}).get("ok",false)

func economic()->Dictionary:
	var result:Dictionary=runtime.capture_checkpoint()
	result.erase("command_revision");result.erase("receipts")
	result.facts.erase("ledger");result.facts.erase("log")
	result.world.extensions.erase("r34:gameplay");result.world.erase("revision")
	return result

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestClient.new();root.add_child(host)
	if args.size()<3:check("actual E delivery and no-history sources provided",false);return finish()
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("sealed actual two-delivery checkpoint decodes",decoded.get("ok",false))
	if not decoded.get("ok",false) or not await mount_capture(decoded.capture):return finish()
	var id:="repair-resident";var other:="village-resident"
	var published:=story()
	check("public projection has two distinct actual event references",published.get("experiences",{}).size()==2 and published.experiences[id].event_id!=published.experiences[other].event_id and published.commands.size()==2)
	var memory:Dictionary=published.experiences.get(id,{}).duplicate(true)
	var before:Dictionary=runtime.capture_checkpoint()
	await open_person(id)
	var button:=action("settlement.read_story",id)
	check("own person page shows original real experience and review",button!=null and text_in(ui._body).contains("真实交付") and text_in(ui._body).contains("旧宅周边"))
	check("per-person history never offers another resident's command",action("settlement.read_story",other)==null and not text_in(ui._body).contains("周婶"))
	check("remote review is disabled by real owner contact policy",button!=null and button.disabled and not button.tooltip_text.is_empty())
	for i in 10:runtime.tick(0.1)
	check("viewing original history pauses sole clock and grants nothing",Data.json_equal(before,runtime.capture_checkpoint()))
	var arrived:=await contact(id)
	check("player follows actual legal walk to original carrier",arrived)
	if not arrived:return finish()
	await open_person(id);button=action("settlement.read_story",id)
	check("same review becomes available at real physical contact",button!=null and not button.disabled)
	if button==null or button.disabled:return finish()
	var economy:=economic();var count:int=runtime.capture_checkpoint().facts.ledger.size()
	button.pressed.emit();await flush()
	published=story()
	check("actual Control submits original person and exact event once",published.people[id].get("reviewed",false) and not published.people[other].get("reviewed",false) and published.experiences[id].event_id==memory.event_id)
	var ledger:Array=runtime.capture_checkpoint().facts.ledger
	check("owner receipt references original delivery rather than invented history",ledger.size()==mini(count+1,256) and ledger.back().get("kind")=="settlement-story-reviewed" and ledger.back().get("event_id")==memory.event_id and ledger.back().get("person_id")==id)
	check("review changes no item body knowledge geometry or nonstory system",Data.json_equal(economy,economic()))
	check("completed review replaces action with permitted followups",action("settlement.read_story",id)==null and text_in(ui._body).contains("已在现场回顾") and keyed("factory:story:workforce:"+id)!=null and action("job",id)!=null)
	var duplicate_before:Dictionary=runtime.capture_checkpoint()
	var duplicate:Dictionary=ui.execute("settlement.read_story",id,{"story_id":"ST02","person_id":id,"event_id":memory.event_id})
	await flush()
	check("duplicate fails visibly and atomically with no second event",not duplicate.get("ok",false) and duplicate.get("code")=="ALREADY_REVIEWED" and not ui._panel_notice.text.is_empty() and Data.json_equal(duplicate_before,runtime.capture_checkpoint()))
	var jobs:=keyed("factory:story:workforce:"+id) as Button
	if jobs!=null:
		jobs.pressed.emit();await flush()
		check("job shortcut keeps original person's identity in real page history",ui.pages.back().page=="factory_people" and ui.pages.back().subject==id)
		var cards:Array=ui._body.find_children("*","VBoxContainer",true,false).filter(func(node):return node.has_meta("ui_person_id"))
		check("job page actually focuses original resident's real assignments",cards.size()==1 and cards[0].get_meta("ui_person_id")==id and keyed("factory:person:"+other)==null)
		ui.cancel_ui();await flush()
		check("back returns to same resident's history",ui.factory_view.story_person==id and ui.pages.back().page=="factory_handbook")
	var rest:=action("job",id)
	check("rest uses original permitted job action",rest!=null and not rest.disabled)
	if rest!=null and not rest.disabled:
		rest.pressed.emit();await flush()
		check("real rest followup assigns only original resident",runtime.actor(id).job=="rest" and runtime.actor(other).job!="rest")
	ui.close_panels()
	var withdrawn:=send("consent",id,{"enabled":false})
	check("original resident can revoke current work consent",withdrawn.get("ok",false))
	await open_person(id)
	check("withdrawn consent hides rest while preserving actual reviewed history",action("job",id)==null and keyed("factory:story:workforce:"+id)!=null and text_in(ui._body).contains("已在现场回顾") and story().experiences[id].event_id==memory.event_id)
	var encoded:=Store.encode(runtime.capture_checkpoint())
	if encoded.get("ok",false):
		var file:=FileAccess.open(output+"/actual-ui-reviewed.native.json",FileAccess.WRITE);file.store_string(encoded.text);file.close()
	var cold:=Store.decode(FileAccess.get_file_as_string(output+"/actual-ui-reviewed.native.json")) if encoded.get("ok",false) else encoded
	check("real review and consent save decodes",cold.get("ok",false))
	if cold.get("ok",false) and await mount_capture(cold.capture):
		check("cold runtime preserves all canonical facts and every owner extension",Data.json_equal(cold.capture.facts,runtime.capture_checkpoint().facts) and Data.json_equal(cold.capture.world.extensions,runtime.world.snapshot().extensions))
		await open_person(id)
		check("fresh UI consumes persisted reviewed history without a local completion flag",action("settlement.read_story",id)==null and action("job",id)==null and text_in(ui._body).contains("已在现场回顾"))
	check("original delivery input stays byte-identical",FileAccess.get_file_as_string(args[1])==original)
	var negative_original:=FileAccess.get_file_as_string(args[2]);var negative:=Store.decode(negative_original)
	if negative.get("ok",false) and await mount_capture(negative.capture):
		await open_person(id)
		check("no-experience real source exposes no review or followup",story().get("experiences",{}).is_empty() and action("settlement.read_story",id)==null and action("job",id)==null and keyed("factory:story:workforce:"+id)==null)
	check("normal no-history input stays byte-identical",FileAccess.get_file_as_string(args[2])==negative_original)
	finish()

func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Actual E original normal deliveries and normal no-history checkpoints, native Controls, physical walk, real owner event/consent/job and canonical cold; current source only, no PCK/OS/VA/FPS/G5"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
