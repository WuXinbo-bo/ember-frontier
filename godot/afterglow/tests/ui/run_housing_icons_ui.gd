extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Delta9 only. A's unchanged new12 seed-bag world, ART's exact new GPU PNGs.

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("original actual new12 input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	check("exact9 image manifest supplied with no pending images",manifest.entries.size()==9 and manifest.pending.is_empty())
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var before:=runtime.capture_checkpoint();var ids:Array=[]
	for entry:Dictionary in manifest.entries:
		var id:=str(entry.definition_id);ids.append(id)
		var definition:=F.definition(ui.factory,id);var mapping:Dictionary=Pictures.HOUSING_MECHANISM_V2.get(id,{})
		var texture:=Pictures.module_texture(definition)
		var source:=Image.load_from_file(args[2].get_base_dir().path_join(str(entry.image_path).get_file()))
		check("actual definition source and geometry match exact manifest "+id,not definition.is_empty() and definition.geometry_source_id==entry.geometry_source_id and definition.geometry_version==entry.geometry_version and mapping.get("geometry_source_id")==entry.geometry_source_id)
		check("runtime image equals exact new256 pixels "+id,texture!=null and source!=null and texture.get_size()==Vector2(256,256) and texture.get_image().get_data()==source.get_data())
		var old:=F.definition(ui.factory,str(entry.geometry_source_id))
		check("old geometry1 picture remains independently readable "+id,Pictures.module_texture(old)!=null and Pictures.module_texture(old)!=texture and old.geometry_version==entry.old_v1_comparison.geometry_version)
		var wrong:=definition.duplicate(true);wrong.geometry_version+=".future"
		var guessed:=definition.duplicate(true);guessed.geometry_version=str(definition.id)+".geometry-v2"
		var missing:=definition.duplicate(true);missing.erase("geometry_source_id")
		check("wrong future doubled suffix and missing source are all refused "+id,Pictures.module_texture(wrong)==null and Pictures.module_texture(guessed)==null and Pictures.module_texture(missing)==null)
	ui.open_panel("factory_catalog");await idle();await idle()
	check("native housing filter isolates all actual9 current designs",await choose("factory:catalog:family","home") and preview_ids().size()==9 and preview_ids().all(func(id):return ids.has(id)))
	for id:String in ids:
		var current:=card(id);var texture:=Pictures.module_texture(F.definition(ui.factory,id))
		check("actual scene catalog card displays exact geometry2 image "+id,current!=null and not text_in(current).contains("缩图待交付") and current.find_children("*","TextureRect",true,false).any(func(node):return node.texture==texture))
	var first:=str(ids[0])
	check("native catalog opens exact new-home handbook",await activate("factory:handbook:link:catalog:"+first) and ui.handbook.get("selection",{}).get("id")=="module:"+first)
	check("actual handbook displays same new-home PNG",ui._body.find_children("*","TextureRect",true,false).any(func(node):return node.texture==Pictures.module_texture(F.definition(ui.factory,first))))
	await key(KEY_ESCAPE)
	check("Esc returns to same9 filtered catalog",not ui.pages.is_empty() and ui.pages.back().page=="factory_catalog" and preview_ids().size()==9)
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		check("new9 cards fit scene-side catalog "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1)
	check("image and handbook use never mutate real world or owner file",Data.json_equal(before,runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
