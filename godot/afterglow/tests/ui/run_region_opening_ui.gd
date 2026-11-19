extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Consume A's actual new12 searched seed-bag capture. No initial supplies,
## source bags, persons, beds or world facts are created by this test.
const Icons=preload("res://scripts/ui/ui_icons.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("actual new12 finite seed-bag save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var before:=runtime.capture_checkpoint();var pack:Dictionary=runtime.actor("player").pack
	var ids:Array=["r34:potato_seed","r34:bean_seed","r34:rice_seed","r34:water_bucket"]
	ui.open_panel("factory_inventory");await idle();await idle()
	for id:String in ids:
		var slot:=cell("inventory","pack:player",-1,"item:"+id)
		check("actual finite bag item bound to real inventory "+id,slot!=null and slot.slot.quantity==pack[id] and slot.slot.quantity==(1 if id=="r34:water_bucket" else 4))
		if slot!=null:check("actual owned slot uses adopted exact icon "+id,slot.get_meta("ui_icon",{}).get("id")==id and slot.get_meta("ui_icon",{}).get("path")==Icons.descriptor({"reference":{"kind":"item","item_id":id}}).path and slot.tooltip_text.contains(P.item_name(id)))
	var bucket:=cell("inventory","pack:player",-1,"item:r34:water_bucket")
	check("actual owned bucket explains reusable count and never promises liquid",bucket!=null and bucket.tooltip_text.contains("可重复") and bucket.tooltip_text.contains("不代表液体"))
	var source:=cell("inventory","pack:player",-1,"item:r34:potato_seed")
	check("native drag begins from actual four seeds",await start(source))
	var destination:=cell("hotbar","pack:player",8)
	check("ninth shortcut target is visible",destination!=null and root.get_visible_rect().encloses(destination.get_global_rect()),view_layout(destination))
	await motion(destination.get_global_rect().get_center() if destination!=null else Vector2(8,8));await button(false)
	check("native drop binds same seed reference without duplicating stock",P.reference_key(router.state().slots[8])=="item:r34:potato_seed" and Data.json_equal(before,runtime.capture_checkpoint()) and ui.carry.is_empty() and ui.drag.is_empty())
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		check("real new12 inventory fits with readable text "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,view_layout())
		check("new item shortcut remains inside actual viewport "+str(viewport),cell("hotbar","pack:player",8)!=null and root.get_visible_rect().encloses(cell("hotbar","pack:player",8).get_global_rect()),view_layout(cell("hotbar","pack:player",8)))
	ui.close_panels();ui.open_panel("factory_people");await idle();await idle()
	check("housing projection is not polled for a collapsed section",ui.housing_view.projection_reads==0)
	check("actual care excludes seeds and bucket",runtime.life_consumables("player","eat").all(func(row:Dictionary):return not ids.has(row.item_id)) and runtime.life_consumables("player","drink").all(func(row:Dictionary):return not ids.has(row.item_id)))
	check("native opening reaches on-demand actual housing",await activate("fold:housing:") and ui.housing_view.projection_reads==1)
	var actual:Dictionary=runtime.housing_projection("player")
	check("housing UI consumes exact public homes without inventing beds",Data.json_equal(ui.housing_view.projection,actual))
	if actual.get("homes",[]).is_empty():check("absent housing is an explicit truthful empty state",text_in(ui._body).contains("尚无已知且获准查看的住宅寝位") and not ui._body.find_children("*","Button",true,false).any(func(node):return str(node.get_meta("ui_focus_key","")).begins_with("housing:rest:")))
	for index in 5:ui.refresh()
	await idle();check("repeated Controls refresh never repeats housing routes",ui.housing_view.projection_reads==1)
	check("explicit native refresh re-reads actual authority",await activate("housing:refresh:") and ui.housing_view.projection_reads==2)
	await key(KEY_ESCAPE)
	check("Esc leaves management without changing bag or clock",ui.pages.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	check("original finite seed-bag save stays byte exact",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func view_layout(control:Control=null)->Dictionary:
	return {"dialog":str(ui._dialog.get_global_rect()),"scroll":str(ui._scroll.get_global_rect()),"body_min":str(ui._body.get_combined_minimum_size()),"modal_hotbar":str(ui._modal_hotbar.get_global_rect()),"hotbar_visible":ui._modal_hotbar.is_visible_in_tree(),"child":str(control.get_global_rect()) if control!=null else "missing","pages":ui.pages.duplicate(true),"scale":ui.text_scale}
