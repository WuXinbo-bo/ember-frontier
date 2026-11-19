extends "res://tests/ui/run_service_access_ui.gd"
## Actual E teacher activity checkpoint and B finite restoration adversarial
## checkpoint. No new economy/source/teacher fixture, no OS/visual acceptance.
const P = preload("res://scripts/ui/ui_projection.gd")

func press(key:String)->bool:
	var button:=keyed(key) as Button
	check("real workflow action available "+key,button!=null and not button.disabled,button.tooltip_text if button!=null else "missing")
	if button==null or button.disabled:return false
	button.pressed.emit();await flush();return true

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestClient.new();root.add_child(host)
	if args.size()<3:check("two exact owner checkpoints provided",false);return finish()
	await teaching(args[1])
	await restoration(args[2])
	finish()

func teaching(path:String)->void:
	var original:=FileAccess.get_file_as_string(path);var decoded:=Store.decode(original)
	check("E normal five-second teacher checkpoint decodes",decoded.get("ok",false))
	if not decoded.get("ok",false) or not await mount_capture(decoded.capture):return
	var id:="repair-resident"
	var original_intent:Dictionary=runtime.actor("player").get("intent",{})
	check("original normal player has actual teaching intent",original_intent.get("owner")=="actions")
	ui.open_panel("npc",id);await flush()
	var before:Dictionary=runtime.capture_checkpoint()
	for i in 20:runtime.tick(0.1)
	check("NPC page pauses real teacher labor without granting knowledge",Data.json_equal(before,runtime.capture_checkpoint()))
	ui.close_panels();ui.open_panel("factory_people");await flush()
	var cancel:=button_with("取消当前行动")
	check("real people page cancels original learning",cancel!=null and not cancel.disabled)
	if cancel==null or cancel.disabled:return
	cancel.pressed.emit();await flush()
	check("cancelled partial lesson awards no knowledge",runtime.actor("player").get("intent")==null and not runtime.snapshot().get("knowledge",{}).get("player",[]).has("basic_tool_repair"))
	ui.open_panel("npc",id);await flush()
	var offers:Dictionary=runtime.teaching_snapshot("player",id)
	var available:Array=offers.get("offers",[]).filter(func(row:Dictionary):return not row.get("known",false) and row.get("can_start",false))
	check("public actual teacher supplies retry offer",not available.is_empty(),offers)
	if available.is_empty():return
	var offer:Dictionary=available[0];var knowledge:=str(offer.knowledge_id)
	var possessions:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not await press("teaching:"+id+":"+knowledge):return
	check("lesson receipt closes modal and resumes only world clock",ui.pages.is_empty() and not router.is_paused() and not runtime.is_paused() and runtime.actor("player").get("intent") is Dictionary)
	for i in 60:runtime.tick(0.1)
	check("six effective seconds do not grant a twelve-second lesson",not runtime.snapshot().get("knowledge",{}).get("player",[]).has(knowledge))
	var partial:Dictionary=runtime.capture_checkpoint();var encoded:=Store.encode(partial)
	var cold:Dictionary=host._assemble(Store.decode(encoded.text).capture) if encoded.get("ok",false) else encoded
	check("actual partial lesson cold restores same unpaid knowledge",cold.get("ok",false) and not cold.runtime.snapshot().get("knowledge",{}).get("player",[]).has(knowledge) and Data.json_equal(cold.runtime.actor("player").intent,runtime.actor("player").intent))
	for i in 65:runtime.tick(0.1)
	check("real twelve-second owner completion grants once",runtime.snapshot().get("knowledge",{}).get("player",[]).count(knowledge)==1 and runtime.actor("player").get("intent")==null)
	ui.open_panel("npc",id);await flush()
	check("learned UI has no duplicate lesson action",keyed("teaching:"+id+":"+knowledge)==null and text_in(ui._body).contains("已经掌握"))
	check("lesson does not mint items or auto-recruit teacher",Data.json_equal(possessions,runtime.actor("player").pack) and not F.rows(runtime.factory_snapshot(),"workforce","members").any(func(row:Dictionary):return row.actor_id==id))
	check("E sealed teaching input remains byte-identical",FileAccess.get_file_as_string(path)==original)

func restoration(path:String)->void:
	var original:=FileAccess.get_file_as_string(path);var decoded:=Store.decode(original)
	check("B actual interrupted restoration adversarial checkpoint decodes",decoded.get("ok",false))
	if not decoded.get("ok",false) or not await mount_capture(decoded.capture):return
	# B's safety archive deliberately starts a valid project on an undiscovered
	# frame. Execute the normal discovery command at its existing physical work
	# point before expecting the public UI to show it; never flip visibility.
	var discovered:Dictionary=runtime.command({"command_id":"ui:restore:normal-discovery","actor_id":"player","kind":"module.discover","target_id":"RH-HOME:woodshop-old-frame","payload":{}})
	check("normal owner discovery exposes safety fixture without forged visibility",discovered.get("ok",false),discovered)
	ui.refresh();await flush()
	var rows:=F.rows(ui.factory,"modules","instances").filter(func(row:Dictionary):return row.get("state_code")=="needs_restoration" or not str(row.get("project_id","")).is_empty())
	check("actual original project instance published",rows.size()==1,rows)
	if rows.size()!=1:return
	var id:=str(rows[0].id);var old_project:=str(rows[0].project_id)
	var pack:Dictionary=runtime.actor("player").pack.duplicate(true)
	ui.open_panel("module",id);await flush()
	check("original restore labor shown without configuration or generic repair",not text_in(ui._body).contains("生产目标") and keyed("factory:command:module.repair:"+id)==null and text_in(ui._body).contains("现场作业"))
	var before:Dictionary=runtime.capture_checkpoint()
	for i in 10:runtime.tick(0.1)
	check("restore modal preserves unique project and actual progress",Data.json_equal(before,runtime.capture_checkpoint()))
	if not await press("factory:command:module.held:"+id):return
	check("held pause preserves project and material ownership",runtime.actor("player").intent.held==false and F.instance(runtime.factory_snapshot(),id).project_id==old_project and Data.json_equal(pack,runtime.actor("player").pack))
	if not await press("factory:command:module.cancel:"+id):return
	check("cancel confirmation explains releasing unused reservation",ui.pages.back().page=="factory_confirm" and text_in(ui._body).contains("释放尚未消费"))
	if not await press("factory:confirm:submit"):return
	check("cancel releases actual hold without duplicate refunds",runtime.actor("player").get("intent")==null and Data.json_equal(pack,runtime.actor("player").pack) and F.instance(runtime.factory_snapshot(),id).get("state_code")=="needs_restoration")
	ui.close_panels();ui.open_panel("module",id);await flush()
	var row:=F.instance(runtime.factory_snapshot(),id)
	var cost:Dictionary=row.get("restoration_requirements",{}).get("cost",{})
	check("retry shows actual owner restoration costs",not cost.is_empty() and text_in(ui._body).contains("需要补齐"))
	if not await press("factory:command:module.restore:"+id):return
	check("retry uses original module owner, not generic repair",ui.pages.is_empty() and runtime.actor("player").intent.owner=="modules" and not runtime.is_paused())
	for i in 410:runtime.tick(0.1)
	ui.open_panel("module",id);await flush()
	row=F.instance(runtime.factory_snapshot(),id)
	check("forty effective seconds restores same existing module",row.get("status")=="operational" and row.get("state_code")!="needs_restoration" and keyed("factory:command:module.restore:"+id)==null,row.get("status"))
	var actual:Dictionary=runtime.actor("player").pack
	check("real restoration debits each original cost once",cost.keys().all(func(key):return is_equal_approx(float(pack.get(key,0))-float(cost[key]),float(actual.get(key,0)))))
	var final_capture:Dictionary=runtime.capture_checkpoint();var encoded:=Store.encode(final_capture)
	if encoded.get("ok",false):
		var file:=FileAccess.open(output+"/actual-ui-restored.native.json",FileAccess.WRITE);file.store_string(encoded.text);file.close()
	var decoded_final:Dictionary=Store.decode(FileAccess.get_file_as_string(output+"/actual-ui-restored.native.json")) if encoded.get("ok",false) else encoded
	var restored:Dictionary=host._assemble(decoded_final.capture) if decoded_final.get("ok",false) else decoded_final
	# Compare the exact persisted JSON payload, including all facts. Native JSON
	# canonicalizes floating point values; the in-memory pre-encode payload is
	# not the persisted oracle. Do not remove bodies, ledgers or inventory keys.
	check("actual UI-restored file keeps one module and same paid facts",restored.get("ok",false) and Data.json_equal(restored.runtime.capture_checkpoint().facts,decoded_final.capture.facts) and F.instance(restored.runtime.factory_snapshot(),id).get("status")=="operational",restored.get("reason"))
	check("cold restore preserves every module production logistics reservation and simulation value",restored.get("ok",false) and Data.json_equal(restored.world.snapshot().extensions,decoded_final.capture.world.extensions) and Data.json_equal(restored.runtime.capture_checkpoint().simulation,decoded_final.capture.simulation))
	check("B original finite adversarial input remains byte-identical",FileAccess.get_file_as_string(path)==original)

func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Actual E normal lesson checkpoint and B explicitly finite interrupted restoration adversity input, native Controls/public commands, one Runtime/clock; no normal restoration acquisition, PCK/OS/VA/performance qualification"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
