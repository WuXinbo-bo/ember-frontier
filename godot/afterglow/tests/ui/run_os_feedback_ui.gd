extends "res://tests/ui/run_factory_native_drag.gd"
## A's candidate24 OS findings: native layout and rejection consumer only.
## Fresh normal generation + unchanged E normal save, never injected inventory.
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const F = preload("res://scripts/ui/factory_projection.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("current normal content prepares",prepared.get("ok",false))
	if not prepared.get("ok",false) or not await assemble_capture(prepared.capture):return finish(1)
	var initial:Dictionary=runtime.capture_checkpoint()
	check("normal initial public view is the sparse OS case",F.rows(ui.factory,"modules","instances").size()==2 and F.rows(ui.factory,"workforce","members").size()==1,{"modules":F.rows(ui.factory,"modules","instances").size(),"people":F.rows(ui.factory,"workforce","members").size()})
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle()
		for page:String in ["factory","factory_people"]:
			ui.close_panels();ui.open_panel(page);await idle();await idle()
			var rect:Rect2=ui._dialog.get_global_rect()
			check("sparse native window stays within logical viewport "+page+str(viewport),root.get_visible_rect().encloses(rect),str(rect))
			check("sparse management width responds to content "+page+str(viewport),rect.size.x<1000 and rect.get_center().distance_to(root.get_visible_rect().get_center())<1.0,str(rect))
			if viewport.x==1280:check("normal sparse window does not reserve full-height blank space "+page,rect.size.y<640,str(rect))
			for destination:String in ["factory","factory_catalog","factory_production","factory_logistics","factory_people","factory_alerts","factory_handbook"]:
				var nav:=keyed("factory:nav:"+destination) as Button
				check("navigation is retained and fits "+page+" "+destination+str(viewport),nav!=null and nav.is_visible_in_tree() and root.get_visible_rect().encloses(nav.get_global_rect()))
			check("back action stays short and reachable "+page+str(viewport),ui._back_button.size.x<160*ui.text_scale and root.get_visible_rect().encloses(ui._back_button.get_global_rect()))
			if page=="factory":
				var cards:Array=[]
				for node:Node in ui._body.find_children("*","VBoxContainer",true,false):
					if node.has_meta("ui_module_id"):cards.append(node)
				check("both actual facilities retain unique cards "+str(viewport),cards.size()==2 and cards[0].get_meta("ui_module_id")!=cards[1].get_meta("ui_module_id"))
				if viewport.x==1280 and cards.size()==2:check("normal facility cards share a two-column row",absf(cards[0].get_global_rect().position.y-cards[1].get_global_rect().position.y)<1.0)
				for module:Dictionary in F.rows(ui.factory,"modules","instances"):
					var action:=keyed("factory:module:"+str(module.id)) as Button
					check("facility action has content width "+str(module.id)+str(viewport),action!=null and action.size.x<240*ui.text_scale)
			else:
				check("single real person preserves care and truthful companion empty state "+str(viewport),text_in(ui._body).contains("目前没有可分工的同行者") and text_in(ui._body).contains("进食") and text_in(ui._body).contains("处理伤势"))
			# Repeated native sizing must not grow from a stale scroll allocation.
			ui._size_dialog();await idle();await idle()
			check("adaptive sizing settles without allocation drift "+page+str(viewport),ui._dialog.get_global_rect()==rect,{"before":str(rect),"after":str(ui._dialog.get_global_rect())})
	check("management layout does not alter authority or discovery",Data.json_equal(initial,runtime.capture_checkpoint()))
	check("count values are integers and cubic quantities retain precision",F.quantity(2.0)=="2 件" and F.quantity(0.125,"m3")=="0.125 m³" and P.number(2.0)=="2")
	var buffer:Dictionary={"item_id":"timber","unit":"count","actual":2.0,"capacity":10.0,"reserved":0.0}
	check("zero output reservations do not compete with actual stock",not F.buffer_text(buffer).contains("输出预占") and F.buffer_text(buffer).contains("2 件 / 10 件"))
	buffer.reserved=4.0
	check("real positive output reservations remain separate from actual",F.buffer_text(buffer).contains("2 件 / 10 件") and F.buffer_text(buffer).contains("输出预占 4 件"))
	ui.close_panels();root.size=Vector2i(1280,800);root.content_scale_size=root.size;ui.set_text_scale(1.0);ui.refresh();await idle()
	check("normal HUD suppresses duplicate profile and routine storage",not ui._profile_hint.visible and not ui._storage_status.visible)
	var profile:String=P.playtest_text(ui.snapshot)
	var save_reason:String=str(ui.storage_state().get("reason",""))
	ui.open_panel("pause");await idle()
	check("Pause retains real profile and storage detail",(profile.is_empty() or text_in(ui._body).contains(profile)) and (save_reason.is_empty() or text_in(ui._body).contains(save_reason)),{"profile":profile,"storage":save_reason,"page":text_in(ui._body)})
	var before_format:Dictionary=runtime.capture_checkpoint()
	var live_save:Dictionary=ui.snapshot.get("save",{}).duplicate(true)
	# Explicit render-only save DTOs. No claim of a real disk failure or write.
	for state:Dictionary in [{"status":"generating","busy":true,"reason":"正在生成村落"},{"status":"failed","busy":false,"reason":"目标目录不可写"}]:
		ui.snapshot.save=state;ui._render_storage_state();ui._refresh_factory_hud(P.player(ui.snapshot));await idle()
		check("busy or failed public save projection remains visible "+str(state.status),ui._storage_status.visible and ui._storage_status.text.contains(state.reason))
	ui.snapshot.save=live_save;ui.refresh();await idle()
	check("save feedback formatting never writes or changes world",Data.json_equal(before_format,runtime.capture_checkpoint()))
	var soil:String=P.action_feedback({"ok":false,"code":"BUFFER_FILTER","reason":"soil_m3"},"deposit")
	check("older frozen soil receipt explains rejection without inventing a destination",soil.contains("土方") and soil.contains("原库存") and not soil.contains("soil_m3") and not soil.contains("仓储") and not soil.contains("仓棚"))
	check("non-transfer rejection does not invent cargo holder",not P.action_feedback({"code":"BUFFER_FILTER","reason":"soil_m3"},"logistics.retarget").contains("原库存"))
	if args.size()<2:check("actual unchanged normal save supplied",false);return finish(1)
	var original:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(original)
	check("sealed normal economy input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false) or not await assemble_capture(decoded.capture):return finish(1)
	var subject:="r34:generated:RH-HOME:home:stock:supplies"
	ui.open_panel("container",subject);await idle()
	var book:=cell("inventory","pack:player",-1,"item:book_woodwork")
	check("real pack book is visible for native rejected transfer",book!=null and root.get_visible_rect().encloses(book.get_global_rect()))
	if book!=null:
		var before:Dictionary=runtime.capture_checkpoint()
		await click(book.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
		check("native Shift transfer explains real owner filter and accepted goods",ui._panel_notice.is_visible_in_tree() and ui._panel_notice.text.contains("木工手册") and ui._panel_notice.text.contains("仅接收") and ui._panel_notice.text.contains("原库存") and not ui._panel_notice.text.contains("book_woodwork"),ui._panel_notice.text)
		check("visible rejection stays in window and keeps exact owner diagnostic",root.get_visible_rect().encloses(ui._panel_notice.get_global_rect()) and ui._panel_notice.tooltip_text.contains("BUFFER_FILTER"),{"rect":str(ui._panel_notice.get_global_rect()),"diagnostic":ui._panel_notice.tooltip_text})
		check("rejected native transfer is atomic and clears transient selection",Data.json_equal(before,runtime.capture_checkpoint()) and ui.carry.is_empty() and ui.drag.is_empty() and runtime.actor("player").pack.book_woodwork==1)
	check("normal economy source bytes remain unchanged",FileAccess.get_file_as_string(args[1])==original)
	if args.size()>2: await actual_soil_rejection(args[2])
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func actual_soil_rejection(path:String)->void:
	# B's sealed arrival is a lawful continuation of A24 ready-to-test QA.
	# Do not call this normal natural acquisition or repeat B's domain suite.
	var original:String=FileAccess.get_file_as_string(path);var decoded:Dictionary=Store.decode(original)
	check("B actual24 QA lawful arrival snapshot decodes",decoded.get("ok",false))
	if not decoded.get("ok",false) or not await assemble_capture(decoded.capture):return
	var subject:="r34:generated:RH-HOME:home:stock:supplies"
	ui.open_panel("container",subject);await idle()
	var soil:=cell("inventory","pack:player",-1,"item:soil_m3")
	check("real QA soil2 is bound to native source cell",soil!=null and soil.slot.quantity==2 and root.get_visible_rect().encloses(soil.get_global_rect()))
	if soil==null:return
	var before:Dictionary=runtime.capture_checkpoint()
	await click(soil.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
	check("actual native soil rejection explains owner list without imaginary warehouse",ui._panel_notice.is_visible_in_tree() and ui._panel_notice.text.contains("土方") and ui._panel_notice.text.contains("仅接收") and ui._panel_notice.text.contains("原库存") and not ui._panel_notice.text.contains("soil_m3") and not ui._panel_notice.text.contains("仓储") and not ui._panel_notice.text.contains("仓棚"),ui._panel_notice.text)
	check("actual soil remains with original holder on rejection",Data.json_equal(before,runtime.capture_checkpoint()) and runtime.actor("player").pack.soil_m3==2 and ui.carry.is_empty() and ui.drag.is_empty())
	root.size=Vector2i(1000,700);root.content_scale_size=root.size;ui.set_text_scale(1.5);await idle();await idle()
	check("real rejection remains fully readable at small 150-percent viewport",ui._panel_notice.is_visible_in_tree() and root.get_visible_rect().encloses(ui._panel_notice.get_global_rect()) and ui._panel_notice.get_line_count()<=ui._panel_notice.max_lines_visible,{"rect":str(ui._panel_notice.get_global_rect()),"lines":ui._panel_notice.get_line_count()})
	check("B QA arrival source bytes stay unchanged",FileAccess.get_file_as_string(path)==original)

func text_in(node:Node)->String:
	var text:String=node.text+"\n" if node is Label or node is Button else ""
	for child:Node in node.get_children():text+=text_in(child)
	return text

func assemble_capture(capture:Dictionary)->bool:
	if is_instance_valid(ui):ui.get_parent().free()
	if is_instance_valid(router):router.free()
	var made:Dictionary=host._assemble(capture)
	check("same Native configures real owners",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return false
	runtime=made.runtime;world=made.world;router=Router.new();host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router);await idle();await idle();return true

func finish(code:int)->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"method":"Actual Native fresh normal world + unchanged E normal-economy save; Viewport Shift input; explicit render-only save/older soil receipt DTOs","scope":"Current source headless native Control support only, not candidate24 package/physical OS/Retina/VA/WF/FPS/G5"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
