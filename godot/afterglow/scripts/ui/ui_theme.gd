extends RefCounted
## Native controls over reusable illustrated paper, wood and stitched skins.
## Craft method adapted from unslop by Damir Sokolovsky, CC-BY-4.0.
const Images = preload("res://scripts/ui/ui_images.gd")
const BASE := Color("f2ead7")
const SURFACE := Color("fbf6e9")
const RAISED := Color("e6dcc4")
const INK := Color("302f27")
const SECONDARY := Color("666650")
const MUTED := Color("8a856e")
const EDGE := Color("b9ad8c")
const MOSS := Color("536b47")
const RUST := Color("a34f32")
const ACCENT := MOSS
const ERROR := RUST
const CHROME := {
	"panel":{"path":"res://themes/illustrated19/panel.png", "size":Vector2i(256,256), "slices":Vector4(12,12,12,12)},
	"title":{"path":"res://themes/illustrated19/title.png", "size":Vector2i(256,256), "slices":Vector4(12,12,12,12)},
	"slot":{"path":"res://themes/illustrated19/slot.png", "size":Vector2i(256,256), "slices":Vector4(12,12,12,12)},
	"card":{"path":"res://themes/illustrated19/card.png", "size":Vector2i(256,256), "slices":Vector4(12,12,12,12)},
	"button":{"path":"res://themes/illustrated19/button.png", "size":Vector2i(256,256), "slices":Vector4(12,12,12,12)},
	"button_primary":{"path":"res://themes/illustrated19/button_primary.png", "size":Vector2i(256,256), "slices":Vector4(12,12,12,12)}
}
static var _chrome_textures: Dictionary = {}
static var _control_glyphs: Dictionary = {}

static func _chrome_texture(kind: String) -> Texture2D:
	if _chrome_textures.has(kind): return _chrome_textures[kind]
	var spec: Dictionary = CHROME.get(kind, {})
	var texture: Texture2D
	if not spec.is_empty(): texture = Images.texture(str(spec.path))
	# Both positive and absent results are cached. Missing optional artwork is
	# handled once at startup, never repeatedly loaded during a world STEP.
	_chrome_textures[kind] = texture
	return texture

static func chrome(kind: String, fill: Color = BASE, border: Color = EDGE, width: int = 1) -> StyleBox:
	# One native skin, with exactly the same content metrics before/after art.
	# Slice pixels equal logical border pixels; the center stretches separately.
	var texture := _chrome_texture(kind)
	var style: StyleBox
	if texture != null:
		var image := StyleBoxTexture.new(); image.texture = texture
		var slices: Vector4 = CHROME[kind].slices
		for side: int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			image.set_texture_margin(side, slices[side])
		image.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		image.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		image.draw_center = true
		var base: Color = SURFACE if kind in ["slot", "title", "card", "button"] else ACCENT if kind == "button_primary" else BASE
		image.modulate_color = Color(minf(1.25,fill.r/base.r),minf(1.25,fill.g/base.g),minf(1.25,fill.b/base.b),fill.a)
		style = image
	else:
		var native := box(fill,border,width)
		native.set_corner_radius_all(2)
		if kind == "title":
			native.set_border_width_all(0); native.border_width_bottom = 2
		elif kind == "panel": native.border_width_top = 2
		style = native
	style.content_margin_left = 4 if kind == "slot" else 12
	style.content_margin_right = 4 if kind == "slot" else 12
	style.content_margin_top = 4 if kind == "slot" else 8
	style.content_margin_bottom = 4 if kind == "slot" else 8
	return style

static func box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill; style.border_color = border; style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 8; style.content_margin_bottom = 8
	return style

static func control_glyph(kind: String, scale_factor: float, color: Color = INK) -> Texture2D:
	# Native SVG rasterizer supplies only interface marks, never item artwork.
	# Cache per text scale/color rather than producing textures on each STEP.
	var pixels := roundi(16 * scale_factor)
	var key := "%s:%s:%s" % [kind, pixels, color.to_html()]
	if _control_glyphs.has(key): return _control_glyphs[key]
	var marks := {
		"house":"<path d='M1 7 8 1l7 6M3 6v9h10V6M6 15V9h4v6'/>",
		"crate":"<rect x='2' y='3' width='12' height='11' rx='1'/><path d='M2 6h12M5 6v8M11 6v8M6 3V1h4v2'/>",
		"map":"<path d='m1 3 4-2 6 2 4-2v12l-4 2-6-2-4 2ZM5 1v12M11 3v12'/>",
		"book":"<path d='M8 3C5 1 3 1 1 2v12c2-1 4-1 7 1 3-2 5-2 7-1V2c-2-1-4-1-7 1v12'/>",
		"down":"<path d='m4 6 4 4 4-4'/>",
		"right":"<path d='m6 4 4 4-4 4'/>",
		"close":"<path d='m4 4 8 8M12 4l-8 8'/>",
		"check":"<rect x='2' y='2' width='12' height='12' rx='1'/><path d='m4.5 8 2.5 2.5 4.5-5'/>",
		"empty":"<rect x='2' y='2' width='12' height='12' rx='1'/>",
		"radio":"<circle cx='8' cy='8' r='6'/><circle cx='8' cy='8' r='2' fill='currentColor'/>",
		"radio_empty":"<circle cx='8' cy='8' r='6'/>",
		"updown":"<path d='m5 5 3-3 3 3M5 11l3 3 3-3'/>",
		"blank":""
	}
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%s' height='%s' viewBox='0 0 16 16' color='#%s'><g fill='none' stroke='currentColor' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % [pixels, pixels, color.to_html(false), marks.get(kind, "")]
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK: return null
	var texture := ImageTexture.create_from_image(image)
	_control_glyphs[key] = texture
	return texture

static func _control_box(fill: Color, edge: Color, scale_factor: float, width: int = 1) -> StyleBoxFlat:
	var style := box(fill, edge, width)
	style.set_corner_radius_all(roundi(2 * scale_factor))
	style.content_margin_left = roundi(12 * scale_factor)
	style.content_margin_right = roundi(12 * scale_factor)
	style.content_margin_top = roundi(7 * scale_factor)
	style.content_margin_bottom = roundi(7 * scale_factor)
	return style

static func _control_skin(kind: String, fill: Color, edge: Color, scale_factor: float, width: int = 1) -> StyleBox:
	var style := chrome(kind,fill,edge,width)
	style.content_margin_left = roundi(12 * scale_factor)
	style.content_margin_right = roundi(12 * scale_factor)
	style.content_margin_top = roundi(7 * scale_factor)
	style.content_margin_bottom = roundi(7 * scale_factor)
	return style

static func _focus(scale_factor: float) -> StyleBoxFlat:
	# An independent copper outline preserves the selected texture and remains
	# visible on both the pale ordinary and dark primary button backgrounds.
	var focus := _control_box(Color.TRANSPARENT,Color("ad762f"),scale_factor,2)
	focus.expand_margin_left=1;focus.expand_margin_right=1
	focus.expand_margin_top=1;focus.expand_margin_bottom=1
	return focus

static func _button_style(type: String, state: String, scale_factor: float) -> StyleBox:
	var selected: bool = state in ["pressed", "hover_pressed"]
	var disabled: bool = state == "disabled"
	var primary: bool = not disabled and (type == "PrimaryButton" or (type == "NavigationButton" and selected))
	# Repeated secondary actions should read as paper labels, rather than a
	# wall of riveted frames. Reserve the dark framed skin for real emphasis.
	var quiet: bool = type in ["QuietButton", "NavigationButton"] and not primary
	var kind := "button_primary" if primary else "card" if quiet else "button"
	var fill: Color = ACCENT if primary else SURFACE
	if disabled: fill=Color("ded8ca")
	elif type == "DangerButton": fill=Color("f0d9c6") if state=="normal" else Color("ead0b8") if state=="hover" else Color("dfbea2") if state=="hover_pressed" else Color("d8b69b")
	elif selected: fill=fill.darkened(.10 if state=="hover_pressed" else .15)
	elif state=="hover": fill=fill.lightened(.10) if primary else RAISED
	elif type=="QuietButton": fill=Color("eee5d0")
	var style := _control_skin(kind,fill,ERROR if type=="DangerButton" else ACCENT if selected else EDGE,scale_factor)
	return style

static func _button_ink(type: String, state: String) -> Color:
	if state == "disabled": return SECONDARY
	if type == "PrimaryButton" or (type=="NavigationButton" and state in ["pressed","hover_pressed"]): return SURFACE
	if type == "DangerButton": return Color("813b27")
	return INK

static func create(font: Font, scale_factor: float = 1.0) -> Theme:
	var theme := Theme.new(); theme.default_font = font; theme.default_font_size = roundi(15 * scale_factor)
	for type in ["Label", "Button", "LineEdit", "OptionButton", "CheckBox", "PopupMenu", "SpinBox", "TabBar"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_disabled_color", type, MUTED)
		theme.set_color("font_hover_color", type, INK)
		theme.set_color("font_focus_color", type, INK)
	for spec in [["PageTitle",22,INK],["SectionTitle",18,INK],["Caption",13,SECONDARY]]:
		theme.set_type_variation(spec[0], "Label")
		theme.set_font_size("font_size",spec[0],roundi(spec[1]*scale_factor))
		theme.set_color("font_color",spec[0],spec[2])
	for type: String in ["Button", "OptionButton", "PrimaryButton", "QuietButton", "DangerButton", "NavigationButton"]:
		if type not in ["Button","OptionButton"]: theme.set_type_variation(type,"Button")
		for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			theme.set_stylebox(state,type,_button_style(type,state,scale_factor))
			theme.set_color("font_color" if state=="normal" else "font_"+state+"_color",type,_button_ink(type,state))
			theme.set_color("icon_normal_color" if state=="normal" else "icon_"+state+"_color",type,Color.WHITE if state!="disabled" else Color("a6a18f"))
		# Keyboard focus may appear over a selected toggle. The focus font
		# follows each type's ordinary foreground; selected colors stay explicit.
		if type!="NavigationButton":theme.set_color("font_focus_color",type,_button_ink(type,"normal"))
	var focus := _focus(scale_factor)
	for type in ["Button", "OptionButton", "LineEdit", "TextEdit", "CheckBox", "TabBar"]: theme.set_stylebox("focus", type, focus)
	for type: String in ["PrimaryButton","QuietButton","DangerButton","NavigationButton"]:theme.set_stylebox("focus",type,focus)
	# Panel and popup surfaces consume the delivered artwork as well. Child
	# controls continue drawing real text, item amounts and current commands.
	for type: String in ["Panel","PanelContainer","PopupMenu","PopupPanel"]:theme.set_stylebox("panel",type,chrome("panel",BASE,EDGE))
	for spec in [["WorkshopPanel","panel",BASE,EDGE],["WorkshopTitle","title",SURFACE,ACCENT]]:
		theme.set_type_variation(spec[0],"PanelContainer")
		theme.set_stylebox("panel",spec[0],chrome(spec[1],spec[2],spec[3]))
	for spec in [["WorkshopCard",EDGE],["WorkshopEmphasis",ACCENT]]:
		theme.set_type_variation(spec[0],"PanelContainer")
		var card := _control_skin("card",SURFACE if spec[0]=="WorkshopCard" else Color("e6ebd7"),spec[1],scale_factor)
		theme.set_stylebox("panel",spec[0],card)
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, _control_skin("card",SURFACE,EDGE,scale_factor))
		theme.set_stylebox("read_only", type, _control_skin("card",BASE,EDGE,scale_factor))
		theme.set_color("caret_color", type, INK)
		theme.set_color("selection_color", type, Color("b5c1a2"))
		theme.set_color("font_placeholder_color", type, MUTED)
	theme.set_type_variation("SearchField","LineEdit")
	theme.set_icon("clear","LineEdit",control_glyph("close",scale_factor,SECONDARY))
	theme.set_icon("arrow","OptionButton",control_glyph("down",scale_factor,SECONDARY))
	theme.set_constant("arrow_margin","OptionButton",roundi(8*scale_factor))
	theme.set_icon("updown","SpinBox",control_glyph("updown",scale_factor,SECONDARY))
	for spec in [["checked","check"],["unchecked","empty"],["radio_checked","radio"],["radio_unchecked","radio_empty"]]:
		theme.set_icon(spec[0],"CheckBox",control_glyph(spec[1],scale_factor,ACCENT if spec[0] in ["checked","radio_checked"] else SECONDARY))
		theme.set_icon(spec[0]+"_disabled","CheckBox",control_glyph(spec[1],scale_factor,MUTED))
	theme.set_stylebox("hover","CheckBox",_control_skin("button",RAISED,EDGE,scale_factor,0))
	theme.set_constant("h_separation","CheckBox",roundi(8*scale_factor))
	var popup_hover := _control_skin("button",RAISED,EDGE,scale_factor,0)
	theme.set_stylebox("hover","PopupMenu",popup_hover)
	theme.set_constant("v_separation","PopupMenu",roundi(10*scale_factor))
	theme.set_icon("submenu","PopupMenu",control_glyph("right",scale_factor))
	for spec in [["checked","check"],["unchecked","empty"],["radio_checked","radio"],["radio_unchecked","radio_empty"]]:
		theme.set_icon(spec[0],"PopupMenu",control_glyph(spec[1],scale_factor,ACCENT))
	theme.set_stylebox("panel","TooltipPanel",_control_skin("card",SURFACE,EDGE,scale_factor))
	theme.set_color("font_color","TooltipLabel",INK)
	theme.set_font_size("font_size","TooltipLabel",roundi(13*scale_factor))
	for type in ["VScrollBar","HScrollBar"]:
		var scroll_track := box(BASE,Color.TRANSPARENT,0)
		scroll_track.set_content_margin_all(0)
		theme.set_stylebox("scroll",type,scroll_track)
		for state in ["grabber","grabber_highlight","grabber_pressed"]:
			var grab := box(ACCENT if state=="grabber_pressed" else SECONDARY if state=="grabber_highlight" else EDGE,Color.TRANSPARENT,0)
			grab.set_content_margin_all(roundi(5*scale_factor))
			theme.set_stylebox(state,type,grab)
		for icon in ["increment","decrement","increment_highlight","decrement_highlight","increment_pressed","decrement_pressed"]:
			theme.set_icon(icon,type,control_glyph("blank",0.0625))
	var track := box(RAISED, Color.TRANSPARENT, 0)
	var fill := box(ACCENT, Color.TRANSPARENT, 0)
	for style in [track, fill]:
		style.content_margin_top=0;style.content_margin_bottom=0;style.content_margin_left=0;style.content_margin_right=0
	theme.set_stylebox("background","ProgressBar",track);theme.set_stylebox("fill","ProgressBar",fill)
	for type in ["VBoxContainer","HBoxContainer"]: theme.set_constant("separation",type,roundi(8*scale_factor))
	for type in ["HFlowContainer","VFlowContainer","GridContainer"]:
		theme.set_constant("h_separation",type,roundi(8*scale_factor));theme.set_constant("v_separation",type,roundi(8*scale_factor))
	theme.set_constant("line_spacing","Label",4)
	return theme
