extends SceneTree
## Actual delivered textures in native Theme resources, including state and
## missing-art fallback checks. Root alone runs this bounded engine test.
const UiSkin19 = preload("res://scripts/ui/ui_theme.gd")
const Pictures = preload("res://scripts/ui/ui_images.gd")
const Slot = preload("res://scripts/ui/inventory_slot.gd")
var checks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: print("FAIL "+label+" "+str(detail))

func _textured(style: StyleBox, kind: String) -> bool:
	return style is StyleBoxTexture and style.texture == UiSkin19._chrome_texture(kind) and style.texture != null and style.draw_center and style.get_texture_margin(SIDE_LEFT)==12 and style.get_texture_margin(SIDE_TOP)==12 and style.get_texture_margin(SIDE_RIGHT)==12 and style.get_texture_margin(SIDE_BOTTOM)==12

func _luminance(color: Color) -> float:
	var linear: Array = []
	for channel: float in [color.r,color.g,color.b]: linear.append(channel/12.92 if channel<=.04045 else pow((channel+.055)/1.055,2.4))
	return linear[0]*.2126+linear[1]*.7152+linear[2]*.0722

func _contrast(a: Color, b: Color) -> float:
	var light: float = maxf(_luminance(a),_luminance(b))
	var dark: float = minf(_luminance(a),_luminance(b))
	return (light+.05)/(dark+.05)

func _center(style: StyleBoxTexture) -> Color:
	var pixels := style.texture.get_image()
	if pixels == null or pixels.is_empty(): return Color.TRANSPARENT
	if pixels.is_compressed(): pixels.decompress()
	var total := Color(0,0,0,0)
	var samples := 0
	for x: int in range(96,160,8):
		for y: int in range(96,160,8):
			total += pixels.get_pixel(x,y)
			samples += 1
	return total/float(samples)*style.modulate_color

func run() -> void:
	var output := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	var available := true
	for kind: String in UiSkin19.CHROME:
		var spec: Dictionary = UiSkin19.CHROME[kind]
		UiSkin19._chrome_textures.erase(kind)
		Pictures._cache.erase(spec.path)
		var texture: Texture2D = UiSkin19._chrome_texture(kind)
		var loaded: bool = texture != null and texture.get_size()==Vector2(256,256)
		available = available and loaded
		check("delivered material loads as real 256 pixel texture "+kind,loaded,str(spec.path))
		if loaded:
			check("repeated loads reuse the same texture resource "+kind,UiSkin19._chrome_texture(kind)==texture)
	var font: Font = load("res://themes/fonts/NotoSansCJKsc-Regular.otf")
	var theme := UiSkin19.create(font)
	for type: String in ["Button","OptionButton","PrimaryButton","QuietButton","DangerButton","NavigationButton"]:
		var states: Dictionary = {}
		for state: String in ["normal","hover","pressed","disabled","hover_pressed"]:
			var style := theme.get_stylebox(state,type)
			var expected := "button"
			if state!="disabled" and (type=="PrimaryButton" or (type=="NavigationButton" and state in ["pressed","hover_pressed"])):expected="button_primary"
			elif type in ["QuietButton","NavigationButton"]:expected="card"
			check("native control uses delivered nine slice "+type+":"+state,_textured(style,expected))
			if style is StyleBoxTexture:
				states[state]=style.modulate_color
				check("control content metrics preserve the existing layout "+type+":"+state,style.get_content_margin(SIDE_LEFT)==12 and style.get_content_margin(SIDE_TOP)==7)
				if available:
					var ink := theme.get_color("font_color" if state=="normal" else "font_"+state+"_color",type)
					var ratio := _contrast(ink,_center(style))
					check("actual center and current label retain readable contrast "+type+":"+state,ratio>=3.0,{"ratio":ratio,"disabled":state=="disabled"})
		if states.size()==5:
			check("hover pressed and disabled are visually distinct "+type,states.normal!=states.hover and states.normal!=states.pressed and states.normal!=states.disabled and states.pressed!=states.hover_pressed)
		var focus := theme.get_stylebox("focus",type)
		check("keyboard focus has its own visible outline "+type,focus is StyleBoxFlat and focus.bg_color.a==0 and focus.border_color.a>0 and focus.border_width_left>=2 and focus!=theme.get_stylebox("normal",type))
		var button := OptionButton.new() if type=="OptionButton" else Button.new()
		button.theme=theme
		if type not in ["Button","OptionButton"]:button.theme_type_variation=type
		# Control caches native defaults during construction. Entering the tree
		# emits THEME_CHANGED and refreshes those caches for the assigned theme.
		# Test the live control lifecycle, rather than a detached new() fixture.
		root.add_child(button)
		await process_frame
		var resolved: Dictionary = {}
		for state: String in ["normal","hover","pressed","disabled","hover_pressed","focus"]:
			resolved[state]=button.get_theme_stylebox(state)==theme.get_stylebox(state,type)
		check("real control resolves exact selected theme resources "+type,button.is_inside_tree() and resolved.values().all(func(matches:bool)->bool:return matches),{"inside_tree":button.is_inside_tree(),"variation":str(button.theme_type_variation),"states":resolved})
		button.free()
	for spec: Array in [["Panel","panel"],["PanelContainer","panel"],["PopupMenu","panel"],["PopupPanel","panel"],["WorkshopPanel","panel"],["WorkshopTitle","title"],["WorkshopCard","card"],["WorkshopEmphasis","card"],["TooltipPanel","card"]]:
		check("window card popup and tooltip consume delivered artwork "+str(spec[0]),_textured(theme.get_stylebox("panel",str(spec[0])),str(spec[1])))
	check("primary foreground is ivory and ordinary foreground stays dark",theme.get_color("font_color","PrimaryButton")==UiSkin19.SURFACE and theme.get_color("font_color","Button")==UiSkin19.INK)
	check("disabled navigation never reuses selected ivory foreground",theme.get_color("font_disabled_color","NavigationButton")==UiSkin19.SECONDARY and theme.get_color("font_pressed_color","NavigationButton")==UiSkin19.SURFACE)
	var slot := Slot.new()
	slot.theme=theme
	slot.slot={"index":0,"kind":"inventory","reference":{},"entry":{},"quantity":0,"available":0}
	root.add_child(slot)
	slot.present("空格")
	check("real inventory slot consumes delivered slot nine slice",_textured(slot.get_theme_stylebox("normal"),"slot") and slot.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)==4)
	check("slot input and native focus remain enabled",slot.focus_mode==Control.FOCUS_ALL and slot.mouse_filter==Control.MOUSE_FILTER_STOP)
	slot.queue_free()
	var larger := UiSkin19.create(font,1.5)
	check("text scaling preserves established padding",larger.get_stylebox("normal","Button").get_content_margin(SIDE_LEFT)==18 and larger.get_stylebox("normal","Button").get_content_margin(SIDE_TOP)==11)
	var saved: Dictionary = UiSkin19._chrome_textures.duplicate()
	for kind: String in UiSkin19.CHROME:UiSkin19._chrome_textures[kind]=null
	var fallback := UiSkin19.create(font)
	check("missing button artwork safely uses readable native fallback",fallback.get_stylebox("normal","Button") is StyleBoxFlat and fallback.get_stylebox("normal","PrimaryButton") is StyleBoxFlat and fallback.get_color("font_color","PrimaryButton")==UiSkin19.SURFACE)
	check("missing panel artwork preserves content and focus affordances",fallback.get_stylebox("panel","WorkshopPanel") is StyleBoxFlat and fallback.get_stylebox("panel","WorkshopPanel").get_content_margin(SIDE_LEFT)==12 and fallback.get_stylebox("focus","Button") is StyleBoxFlat)
	for kind: String in UiSkin19.CHROME:UiSkin19._chrome_textures[kind]=saved.get(kind)
	var failed: int = checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Actual PNG-backed Theme/control resource, label contrast, state and safe missing-art checks; no renderer screenshot or gameplay/FPS claim."},"\t"));file.close()
	print("illustrated theme19 "+str(checks.size()-failed)+"/"+str(checks.size()))
	quit(0 if failed==0 else 1)
