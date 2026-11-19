extends "res://tests/ui/run_os_feedback_ui.gd"
## Actual delivered PNGs through the existing resource loader, native themes
## and Viewport input. No synthetic texture, importer, renderer or OS window.
const WorkshopTheme = preload("res://scripts/ui/ui_theme.gd")
const Pictures = preload("res://scripts/ui/ui_images.gd")
var texture_paths: Array = []

func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]
	DirAccess.make_dir_recursive_absolute(output)
	if args.size()<2: check("original normal-economy input supplied",false); return finish(1)
	for kind: String in ["panel","title","slot"]:
		var spec: Dictionary=WorkshopTheme.CHROME[kind]
		WorkshopTheme._chrome_textures.erase(kind); Pictures._cache.erase(spec.path)
		var actual: Texture2D=WorkshopTheme._chrome_texture(kind)
		check("actual delivered PNG loads without cache injection "+kind,actual!=null and actual.get_size()==Vector2(spec.size))
		if actual==null: return finish(1)
		var pixels: Image=actual.get_image(); pixels.convert(Image.FORMAT_RGBA8)
		var original_pixels: Image=Image.load_from_file(spec.path); original_pixels.convert(Image.FORMAT_RGBA8)
		check("actual loaded pixels match delivered PNG "+kind,pixels.get_data()==original_pixels.get_data())
		var style: StyleBox=WorkshopTheme.chrome(kind,WorkshopTheme.BASE if kind=="panel" else WorkshopTheme.SURFACE)
		var cuts: Array=[]
		for side: int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: cuts.append(style.get_texture_margin(side) if style is StyleBoxTexture else -1)
		check("actual native style keeps all source cuts "+kind,style is StyleBoxTexture and style.texture==actual and cuts==[spec.slices.x,spec.slices.y,spec.slices.z,spec.slices.w] and style.draw_center and style.axis_stretch_horizontal==StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH and style.axis_stretch_vertical==StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH,cuts)
		check("normal skin retains delivered base colour "+kind,style is StyleBoxTexture and style.modulate_color.is_equal_approx(Color.WHITE))
		texture_paths.append({"kind":kind,"path":spec.path,"texture_class":actual.get_class(),"import_sidecar_present":FileAccess.file_exists(spec.path+".import"),"source_pixels_match":true})
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	var original: String=FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary=Store.decode(original)
	check("original normal-economy save decodes unchanged",decoded.get("ok",false))
	if not decoded.get("ok",false): return finish(1)
	host=TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var before: Dictionary=runtime.capture_checkpoint()
	for viewport: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport; root.content_scale_size=viewport; ui.set_text_scale(1.0 if viewport.x==1280 else 1.5)
		for page: String in ["factory","factory_catalog","factory_inventory","factory_production","factory_logistics","factory_people","factory_alerts","factory_handbook","pause"]:
			ui.close_panels(); ui.open_panel(page); await idle(); await idle()
			var title_plate: Control=ui._title.get_parent().get_parent()
			var panel_skin: StyleBox=ui._dialog.get_theme_stylebox("panel")
			var title_skin: StyleBox=title_plate.get_theme_stylebox("panel")
			check("real panel and title consume delivered skins "+page+str(viewport),panel_skin is StyleBoxTexture and title_skin is StyleBoxTexture and panel_skin.texture==WorkshopTheme._chrome_texture("panel") and title_skin.texture==WorkshopTheme._chrome_texture("title"))
			check("real skin preserves reachable native bounds "+page+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and root.get_visible_rect().encloses(ui._back_button.get_global_rect()) and root.get_visible_rect().encloses(ui._title.get_global_rect()),str(ui._dialog.get_global_rect()))
	ui.close_panels(); ui.open_panel("inventory"); await idle()
	var source: Button=cell("inventory","pack:player",-1,"item:book_woodwork")
	if source!=null: ui._scroll.ensure_control_visible(source); await idle()
	check("real handbook source is inside scroll viewport before native input",source!=null and ui._scroll.get_global_rect().encloses(source.get_global_rect()),str(source.get_global_rect()) if source!=null else "missing")
	check("native drag starts from original real handbook item",source!=null and await start(source))
	var destination: Button=cell("hotbar","pack:player",6)
	check("actual skinned hotbar destination is reachable",destination!=null and root.get_visible_rect().encloses(destination.get_global_rect()))
	if destination==null: return finish(1)
	await motion(destination.get_global_rect().get_center()); await button(false)
	check("native skinned binding retains the one original item reference",P.reference_key(router.state().slots[6])=="item:book_woodwork" and ui.drag.is_empty() and ui.carry.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	router.select_slot(6); ui.refresh(); await idle()
	destination=cell("hotbar","pack:player",6)
	var normal: StyleBox=destination.get_theme_stylebox("normal")
	var focus: StyleBox=destination.get_theme_stylebox("focus")
	check("actual selected skin keeps native label and independent keyboard focus",destination.visual_state.selected and text_in(destination).contains("[7]") and normal is StyleBoxTexture and normal.texture==WorkshopTheme._chrome_texture("slot") and focus!=normal and destination.focus_mode==Control.FOCUS_ALL)
	await key(KEY_W); await key(KEY_E)
	check("skinned inventory still consumes scene movement and interaction",not ui.pages.is_empty() and Data.json_equal(before,runtime.capture_checkpoint()))
	source=cell("inventory","pack:player",-1,"item:book_woodwork")
	if source!=null: ui._scroll.ensure_control_visible(source); await idle()
	check("skinned cancellation starts through native callbacks",await start(source))
	await motion(Vector2(5,5)); await button(false); await key(KEY_ESCAPE)
	check("skinned cancellation and close return goods and release modal only",ui.drag.is_empty() and ui.carry.is_empty() and ui.pages.is_empty() and not router.state().pause_reasons.modal and Data.json_equal(before,runtime.capture_checkpoint()))
	check("original input file remains byte-identical",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row: Dictionary):return row.ok) else 1)

func finish(code: int) -> void:
	var failed: int=checks.filter(func(row: Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"actual_textures":texture_paths,"trace":trace,"method":"Actual three delivered PNGs through existing native loader; untouched normal-economy save and Native; nine pages at 100/150 percent; actual Viewport drag/binding/cancel and scene input consumption","scope":"Source headless Control and actual PNG pixel/StyleBox consumption only; source ImageTexture fallback is not an imported/PCK/renderer/OS/Retina/VA/WF/FPS/G5 qualification"},"\t",true,true)); file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(code)
