extends "res://tests/ui/run_os_feedback_ui.gd"
## Regression for A's exact25 home-sidebar screenshot. Native container
## measurement and actual actions; normal-camera rendering remains A's scope.
var metrics: Array = []

func text_fits(button: Button) -> bool:
	if button == null: return false
	var natural:Vector2=button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size"))
	return button.size.x>=natural.x and button.size.y<=44*ui.text_scale

func run() -> void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("actual formal new9 prepares",prepared.get("ok",false))
	if not prepared.get("ok",false) or not await assemble_capture(prepared.capture):return finish(1)
	var before:Dictionary=runtime.capture_checkpoint()
	var homes:Array=F.rows(ui.factory,"modules","instances").filter(func(row:Dictionary):return F.definition(ui.factory,str(row.definition_id)).get("generation_role")=="home")
	check("real generated home available",not homes.is_empty())
	if homes.is_empty():return finish(1)
	var id:=str(homes[0].id)
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5)
		ui.close_panels();ui.open_panel("module",id);await idle();await idle()
		var plate:Control=ui._title.get_parent().get_parent()
		var link:=keyed("factory:handbook:link:module:"+id) as Button
		var inventory_buttons:Array=ui._body.find_children("*","Button",true,false).filter(func(node:Button):return node.text.contains("取放生活物资"))
		var sample:Dictionary={"viewport":str(viewport),"scale":ui.text_scale,"dialog":str(ui._dialog.get_global_rect()),"plate":str(plate.get_global_rect()),"plate_min":str(plate.get_combined_minimum_size()),"title":str(ui._title.get_global_rect()),"back":str(ui._back_button.get_global_rect()),"back_min":str(ui._back_button.get_combined_minimum_size()),"back_text":ui._back_button.text,"link":str(link.get_global_rect()) if link!=null else "missing","link_min":str(link.get_combined_minimum_size()) if link!=null else "missing","link_text":link.text if link!=null else "missing","scroll":str(ui._scroll.get_global_rect())}
		metrics.append(sample)
		check("object title is one compact readable line "+str(viewport),plate.size.y<=64*ui.text_scale and text_fits(ui._back_button),sample)
		check("handbook shortcut is a readable action rather than empty vertical strip "+str(viewport),text_fits(link),sample)
		check("identity status leads directly to actual living supplies "+str(viewport),inventory_buttons.size()==1 and inventory_buttons[0].get_global_rect().end.y<=ui._scroll.get_global_rect().end.y and text_in(ui._body).contains("生活物资"),sample)
		check("all body action labels fit within sidebar width "+str(viewport),ui._body.find_children("*","Button",true,false).all(func(node:Button):return node.size.x<=ui._scroll.size.x),sample)
		if link!=null:
			ui._scroll.ensure_control_visible(link);await idle();await click(link.get_global_rect().get_center())
			check("native readable shortcut opens home's real definition "+str(viewport),ui.pages.back().page=="factory_handbook" and ui.handbook.get("selection",{}).get("id")=="module:"+str(homes[0].definition_id))
			await key(KEY_ESCAPE)
			check("native Escape returns same real sidebar "+str(viewport),ui.world_view_selection()=={"kind":"module","id":id})
	check("object density and navigation never alter true stock or owners",Data.json_equal(before,runtime.capture_checkpoint()))
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int) -> void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"metrics":metrics,"scope":"Actual new9 home Native Control measured density/action/navigation at100/150%; no normal-camera/OS/Retina/VA acceptance"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
