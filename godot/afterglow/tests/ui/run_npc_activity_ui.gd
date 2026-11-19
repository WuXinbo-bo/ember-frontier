extends "res://tests/ui/run_os_feedback_ui.gd"
## A's unchanged real25 manual capture. Presentation only, no work re-assignment.
const Identity = preload("res://scripts/ui/ui_identity.gd")
const EXPLANATION := "原安排的岗位当前不可执行"

func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size()!=2:check("A actual25 NPC capture supplied",false);return finish(1)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("unchanged A NPC manual save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var before:Dictionary=runtime.capture_checkpoint()
	var ids:=["village-resident","repair-resident"]
	for id:String in ids:
		check("real persisted NPC has exact unavailable assignment activity "+id,runtime.actor(id).activity=="candidate_unavailable" and runtime.actor(id).get("intent")==null)
	check("confirmed lowercase reason explains assignment without inventing a cause",P.reason_text("candidate_unavailable")==EXPLANATION)
	check("decision uses same confirmed explanation",Identity.decision_text({"reason":"candidate_unavailable"})==EXPLANATION)
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=root.size;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);ui.close_panels();ui.refresh();await idle()
		for id:String in ids:
			var companion:=keyed("hud:person:"+id) as Button
			check("HUD explains real companion in Chinese "+id+str(viewport),companion!=null and companion.text.contains(EXPLANATION) and not companion.text.contains("candidate_unavailable"),companion.text if companion!=null else "missing")
			check("HUD companion stays within native bounds "+id+str(viewport),companion!=null and root.get_visible_rect().encloses(companion.get_global_rect()),str(companion.get_global_rect()) if companion!=null else "missing")
		for page:String in ["factory_people","npc"]:
			ui.open_panel(page,ids[0] if page=="npc" else "");await idle();await idle()
			var text:=text_in(ui._body)
			check("person surface translates original activity "+page+str(viewport),text.contains(EXPLANATION) and not text.contains("candidate_unavailable"),text)
			await key(KEY_ESCAPE)
		check("presentation preserves exact real authority "+str(viewport),Data.json_equal(before,runtime.capture_checkpoint()))
	# Explicit detached view probe: future code must not leak or invent work.
	var probe:=VBoxContainer.new();ui.add_child(probe)
	Identity.header(ui,probe,{"name":"显示探针","activity":"future_activity_code"})
	check("unknown activity code has neutral Chinese fallback",not text_in(probe).contains("future_activity_code") and text_in(probe).contains("当前行动条件尚未满足"),text_in(probe));probe.free()
	check("specific authority Chinese reason is retained",P.reason_text("活动受阻：门口尚无可用落脚点")=="活动受阻：门口尚无可用落脚点")
	check("original manual save remains byte-identical",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int) -> void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"A actual25 NPC capture, original Native assembly and UI at100/150%; display-only future-code probe is explicit. Current-source headless Control, not PCK/OS/NPC overlap/VA/WF/FPS/G5 acceptance"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
